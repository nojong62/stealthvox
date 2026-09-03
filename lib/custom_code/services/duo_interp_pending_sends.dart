// ====================================================================
// 📮 [INTERP-PENDING] DataChannel이 아직 안 열렸을 때의 발화를 잠깐 든다
// --------------------------------------------------------------------
// WebRTC 통역에서 상대에게 가는 것은 DataChannel 한 줄뿐이다. Firestore는
// 기록으로만 남고 받는 쪽이 건너뛰므로, `sendData`가 false를 내면 그 발화는
// **어디로도 가지 않는다.**
//
// 그런 창이 셋 있다:
//   ① peer는 붙었는데 DataChannel이 아직 open 전 (SCTP 핸드셰이크)
//   ② 통화 중 채널이 잠깐 닫혔다 다시 열리는 사이
//   ③ 재연결 직후
//
// 그래서 못 보낸 payload를 **아주 짧게** 들고 있다가 채널이 열리면 다시
// 보낸다.
//
// 🚫 **이것은 파이프라인 재실행 큐가 아니다.** 다시 전사하지도, 다시 번역하지도,
//   History나 Firestore를 다시 쓰지도 않는다. 처음 만든 payload를 그대로
//   다시 밀어 넣을 뿐이고 `msgId`도 그대로다 — 받는 쪽이 그 값으로 중복을
//   가르기 때문에 새로 만들면 같은 말을 두 번 읽는다.
//
// ⏳ **오래된 말은 보내지 않고 버린다.** 통역에서 10초 전 문장이 뒤늦게
//   쏟아지는 것은 한 건을 잃는 것보다 나쁘다 — 대화의 순서가 무너진다.
//
// 📐 시계를 들고 있지 않다. 호출부가 `now`를 넘긴다 — 그래야 10초를 실제로
//   기다리지 않고 그대로 시험할 수 있다.
// ====================================================================

/// 큐에 들 수 있는 최대 건수. 넘치면 **가장 오래된 것부터** 버린다.
/// 통역에서 살릴 값이 있는 것은 최근 말이다.
const int kDuoInterpPendingMaxItems = 5;

/// 이만큼 지난 발화는 보내지 않고 버린다.
const Duration kDuoInterpPendingMaxAge = Duration(seconds: 10);

/// 왜 버렸나. 실기기 로그에서 "첫 발화가 왜 안 갔나"를 가르는 값이다.
enum DuoInterpPendingDropReason {
  /// 5건을 넘겨 가장 오래된 것을 밀어냈다.
  overflow,

  /// 10초를 넘겼다.
  expired,

  /// 그 사이 통역 세션이 바뀌었다.
  staleGeneration,
}

/// 못 보낸 발화 한 건.
class DuoInterpPendingSend {
  const DuoInterpPendingSend({
    required this.payload,
    required this.queuedAt,
    required this.generation,
  });

  /// **처음 만든 그대로다.** `msgId`가 여기 들어 있고 바꾸지 않는다.
  final Map<String, dynamic> payload;

  final DateTime queuedAt;

  /// 넣을 때의 통역 세대. 다음 통화로 넘어가지 않게 하는 빗장이다.
  final int generation;

  String get msgId => (payload['msgId'] ?? '').toString();

  int ageMs(DateTime now) => now.difference(queuedAt).inMilliseconds;

  bool isExpired(DateTime now) => now.difference(queuedAt) > kDuoInterpPendingMaxAge;
}

/// 버려진 한 건과 그 사유.
class DuoInterpPendingDropped {
  const DuoInterpPendingDropped(this.item, this.reason);
  final DuoInterpPendingSend item;
  final DuoInterpPendingDropReason reason;
}

/// [DuoInterpPendingSendQueue.flush] 한 번의 결과.
class DuoInterpPendingFlushResult {
  const DuoInterpPendingFlushResult({
    required this.sent,
    required this.dropped,
    required this.blocked,
    required this.remaining,
  });

  /// 실제로 보낸 항목의 `msgId`. 보낸 순서 그대로다.
  final List<String> sent;

  /// 보내지 않고 버린 것들.
  final List<DuoInterpPendingDropped> dropped;

  /// 전송이 다시 실패해 도중에 멈췄는가. 그때 남은 것은 큐에 그대로 있다.
  final bool blocked;

  /// 큐에 남은 건수.
  final int remaining;
}

/// 못 보낸 발화를 **오래된 순서로** 들고 있는 짧은 큐.
///
/// 통화 한 번 = 이 객체 한 개. 세션이 끝나면 [clear]한다.
class DuoInterpPendingSendQueue {
  final List<DuoInterpPendingSend> _items = <DuoInterpPendingSend>[];

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  /// 지금 든 것들. 시험과 로그용이고 밖에서 고치지 못한다.
  List<DuoInterpPendingSend> get items => List<DuoInterpPendingSend>.unmodifiable(_items);

  /// 한 건을 넣는다. 5건을 넘기면 **가장 오래된 것을 밀어내고** 그것을 돌려준다.
  ///
  /// 최신 대화를 살리는 쪽이 맞다 — 통역에서 지금 한 말이 안 가는 것이
  /// 10초 전 말이 안 가는 것보다 훨씬 크게 느껴진다.
  DuoInterpPendingSend? add(DuoInterpPendingSend item) {
    _items.add(item);
    if (_items.length <= kDuoInterpPendingMaxItems) return null;
    return _items.removeAt(0);
  }

  /// 보낼 자격을 잃은 것을 걷어낸다. 버린 것들을 돌려준다.
  ///
  /// [generation]과 다른 세대의 항목은 지난 통화의 것이므로 버린다.
  List<DuoInterpPendingDropped> prune({
    required DateTime now,
    required int generation,
  }) {
    final List<DuoInterpPendingDropped> dropped = <DuoInterpPendingDropped>[];
    _items.removeWhere((item) {
      if (item.generation != generation) {
        dropped.add(DuoInterpPendingDropped(
            item, DuoInterpPendingDropReason.staleGeneration));
        return true;
      }
      if (item.isExpired(now)) {
        dropped.add(
            DuoInterpPendingDropped(item, DuoInterpPendingDropReason.expired));
        return true;
      }
      return false;
    });
    return dropped;
  }

  /// 오래된 것부터 [send]로 다시 밀어 넣는다.
  ///
  /// [send]가 false를 내면 **그 항목부터 남기고 멈춘다.** 채널이 닫힌 상태에서
  /// 끝까지 돌면 남은 것을 전부 헛되이 실패시키고, 로그만 어지러워진다.
  ///
  /// 보내기 전에 [prune]을 먼저 돌리므로 만료·헌 세대는 전송 대상이 아니다.
  DuoInterpPendingFlushResult flush({
    required DateTime now,
    required int generation,
    required bool Function(Map<String, dynamic> payload) send,
  }) {
    final List<DuoInterpPendingDropped> dropped =
        prune(now: now, generation: generation);
    final List<String> sent = <String>[];
    bool blocked = false;
    while (_items.isNotEmpty) {
      final DuoInterpPendingSend head = _items.first;
      if (!send(head.payload)) {
        blocked = true;
        break;
      }
      _items.removeAt(0);
      sent.add(head.msgId);
    }
    return DuoInterpPendingFlushResult(
      sent: sent,
      dropped: dropped,
      blocked: blocked,
      remaining: _items.length,
    );
  }

  /// 전부 버린다. 통역이 멈추거나 방을 나갈 때 부른다.
  List<DuoInterpPendingSend> clear() {
    final List<DuoInterpPendingSend> gone =
        List<DuoInterpPendingSend>.of(_items);
    _items.clear();
    return gone;
  }
}
