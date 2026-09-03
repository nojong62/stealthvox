// 📮 [INTERP-PENDING] DataChannel이 안 열렸을 때의 발화를 잠깐 들었다 민다
//
// WebRTC 통역에서 상대에게 가는 것은 DataChannel 한 줄뿐이다. Firestore는
// 기록으로만 남고 받는 쪽이 건너뛰므로, `sendData`가 false를 내면 그 발화는
// **어디로도 가지 않는다.** peer는 붙었는데 채널이 아직 열리기 전, 잠깐 닫혔다
// 다시 열리는 사이, 재연결 직후 — 세 창이 그렇다.
//
// 이 큐가 지키는 것 넷:
//   ① 최근 5건까지만 든다 (무한 큐 금지)
//   ② 10초를 넘긴 말은 **보내지 않고 버린다** — 뒤늦게 쏟아지면 대화 순서가
//      무너지고, 그게 한 건 잃는 것보다 나쁘다
//   ③ 같은 발화는 같은 msgId로 다시 간다 — 새로 만들면 두 번 읽힌다
//   ④ 지난 통화의 말이 다음 통화로 넘어가지 않는다
//
// 규칙은 순수 코드라 시계 없이 그대로 잰다. 위젯 쪽은 배선이라 소스로 지킨다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_interp_pending_sends.dart';

const String _duo = 'lib/custom_code/widgets/routine_mode_duo.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _region(String src, String start, String end) {
  final int a = src.indexOf(start);
  if (a < 0) throw StateError('없는 선언: $start');
  final int b = src.indexOf(end, a + 1);
  if (b < a) throw StateError('없는 선언: $end');
  return src.substring(a, b);
}

final DateTime _t0 = DateTime(2026, 9, 4, 10, 0, 0);

DuoInterpPendingSend _item(String id, {int atMs = 0, int gen = 1}) =>
    DuoInterpPendingSend(
      payload: <String, dynamic>{'msgId': id, 'text': '말 $id'},
      queuedAt: _t0.add(Duration(milliseconds: atMs)),
      generation: gen,
    );

void main() {
  final String duo = _read(_duo);

  // ==========================================================================
  group('① 최대 5건 — 최신을 살린다', () {
    test('다섯 번째까지는 아무것도 안 버린다', () {
      final q = DuoInterpPendingSendQueue();
      for (int i = 0; i < kDuoInterpPendingMaxItems; i++) {
        expect(q.add(_item('m$i')), isNull);
      }
      expect(q.length, 5);
    });

    test('여섯 번째가 들어오면 가장 오래된 것이 밀려난다', () {
      final q = DuoInterpPendingSendQueue();
      for (final String id in <String>['A', 'B', 'C', 'D', 'E']) {
        q.add(_item(id));
      }
      final evicted = q.add(_item('F'));
      expect(evicted?.msgId, 'A', reason: '밀어내는 것은 가장 오래된 쪽이다');
      expect(q.items.map((e) => e.msgId).toList(), <String>['B', 'C', 'D', 'E', 'F']);
      expect(q.length, 5, reason: '무한 큐가 되면 안 된다');
    });

    test('계속 넣어도 5건을 넘지 않는다', () {
      final q = DuoInterpPendingSendQueue();
      for (int i = 0; i < 50; i++) {
        q.add(_item('m$i'));
      }
      expect(q.length, kDuoInterpPendingMaxItems);
      expect(q.items.last.msgId, 'm49', reason: '가장 최근 말이 살아 있어야 한다');
    });
  });

  // ==========================================================================
  group('② 10초를 넘기면 보내지 않고 버린다', () {
    test('9.9초는 보낸다', () {
      final q = DuoInterpPendingSendQueue()..add(_item('A'));
      final sentIds = <String>[];
      final r = q.flush(
        now: _t0.add(const Duration(milliseconds: 9900)),
        generation: 1,
        send: (p) {
          sentIds.add(p['msgId'].toString());
          return true;
        },
      );
      expect(r.sent, <String>['A']);
      expect(sentIds, <String>['A']);
      expect(r.dropped, isEmpty);
    });

    test('10.1초는 send를 아예 부르지 않는다', () {
      final q = DuoInterpPendingSendQueue()..add(_item('A'));
      var sendCalls = 0;
      final r = q.flush(
        now: _t0.add(const Duration(milliseconds: 10100)),
        generation: 1,
        send: (p) {
          sendCalls++;
          return true;
        },
      );
      expect(sendCalls, 0, reason: '만료분을 보내면 대화 순서가 무너진다');
      expect(r.sent, isEmpty);
      expect(r.dropped.single.reason, DuoInterpPendingDropReason.expired);
      expect(q.isEmpty, isTrue);
    });

    test('만료분만 골라 버리고 나머지는 보낸다', () {
      final q = DuoInterpPendingSendQueue()
        ..add(_item('old', atMs: 0))
        ..add(_item('new', atMs: 9000));
      final sent = <String>[];
      final r = q.flush(
        now: _t0.add(const Duration(milliseconds: 12000)), // old=12s, new=3s
        generation: 1,
        send: (p) {
          sent.add(p['msgId'].toString());
          return true;
        },
      );
      expect(sent, <String>['new']);
      expect(r.dropped.single.item.msgId, 'old');
    });

    test('경계값 정확히 10초는 아직 보낸다', () {
      final q = DuoInterpPendingSendQueue()..add(_item('A'));
      final r = q.flush(
          now: _t0.add(kDuoInterpPendingMaxAge),
          generation: 1,
          send: (_) => true);
      expect(r.sent, <String>['A']);
    });
  });

  // ==========================================================================
  group('③ 다시 보내는 것은 처음 그 payload다', () {
    test('msgId를 새로 만들지 않는다', () {
      final Map<String, dynamic> original = <String, dynamic>{
        'msgId': 'HOST-7-1757000000000',
        'text': '안녕하세요',
        'seq': 7,
      };
      final q = DuoInterpPendingSendQueue()
        ..add(DuoInterpPendingSend(
            payload: original, queuedAt: _t0, generation: 1));
      Map<String, dynamic>? seen;
      q.flush(
          now: _t0.add(const Duration(seconds: 1)),
          generation: 1,
          send: (p) {
            seen = p;
            return true;
          });
      expect(identical(seen, original), isTrue,
          reason: 'payload를 다시 만들면 msgId가 달라져 같은 말이 두 번 읽힌다');
    });

    test('FIFO — 말한 순서 그대로 나간다', () {
      final q = DuoInterpPendingSendQueue();
      for (final String id in <String>['A', 'B', 'C']) {
        q.add(_item(id));
      }
      final sent = <String>[];
      q.flush(
          now: _t0.add(const Duration(seconds: 1)),
          generation: 1,
          send: (p) {
            sent.add(p['msgId'].toString());
            return true;
          });
      expect(sent, <String>['A', 'B', 'C']);
    });
  });

  // ==========================================================================
  group('flush 도중 다시 실패하면 거기서 멈춘다', () {
    test('첫 건 성공 · 둘째 실패 → 둘째부터 남는다', () {
      final q = DuoInterpPendingSendQueue();
      for (final String id in <String>['A', 'B', 'C']) {
        q.add(_item(id));
      }
      var calls = 0;
      final r = q.flush(
          now: _t0.add(const Duration(seconds: 1)),
          generation: 1,
          send: (p) {
            calls++;
            return p['msgId'] == 'A';
          });
      expect(r.sent, <String>['A']);
      expect(r.blocked, isTrue);
      expect(calls, 2, reason: '실패한 뒤에도 계속 돌면 남은 것을 헛되이 다 실패시킨다');
      expect(q.items.map((e) => e.msgId).toList(), <String>['B', 'C']);
      expect(r.remaining, 2);
    });

    test('막힌 뒤 채널이 다시 열리면 남은 것을 이어서 민다', () {
      final q = DuoInterpPendingSendQueue();
      for (final String id in <String>['A', 'B']) {
        q.add(_item(id));
      }
      q.flush(
          now: _t0.add(const Duration(seconds: 1)),
          generation: 1,
          send: (p) => p['msgId'] == 'A');
      final sent = <String>[];
      final r2 = q.flush(
          now: _t0.add(const Duration(seconds: 2)),
          generation: 1,
          send: (p) {
            sent.add(p['msgId'].toString());
            return true;
          });
      expect(sent, <String>['B']);
      expect(r2.blocked, isFalse);
      expect(q.isEmpty, isTrue);
    });

    test('첫 건부터 실패하면 아무것도 안 나가고 다 남는다', () {
      final q = DuoInterpPendingSendQueue()..add(_item('A'))..add(_item('B'));
      final r = q.flush(
          now: _t0.add(const Duration(seconds: 1)),
          generation: 1,
          send: (_) => false);
      expect(r.sent, isEmpty);
      expect(r.blocked, isTrue);
      expect(q.length, 2);
    });
  });

  // ==========================================================================
  group('④ 지난 통화의 말이 넘어가지 않는다', () {
    test('세대가 다르면 보내지 않고 버린다', () {
      final q = DuoInterpPendingSendQueue()
        ..add(_item('old', gen: 1))
        ..add(_item('now', gen: 2));
      var sendCalls = 0;
      final r = q.flush(
          now: _t0.add(const Duration(seconds: 1)),
          generation: 2,
          send: (_) {
            sendCalls++;
            return true;
          });
      expect(sendCalls, 1);
      expect(r.sent, <String>['now']);
      expect(r.dropped.single.reason, DuoInterpPendingDropReason.staleGeneration);
    });

    test('clear가 전부 버리고 버린 것을 돌려준다', () {
      final q = DuoInterpPendingSendQueue()..add(_item('A'))..add(_item('B'));
      expect(q.clear().length, 2);
      expect(q.isEmpty, isTrue);
    });
  });

  // ==========================================================================
  group('배선 — 넣는 자리와 미는 자리', () {
    test('sendData 실패에서만 큐에 넣는다', () {
      expect(duo, contains('final bool sent = _interpCall?.sendData(payload) ?? false;'));
      expect(duo, contains('if (!sent) _queueInterpPendingSend(payload);'));
    });

    test('payload를 변수로 만들어 그대로 보관한다', () {
      final String pipe = _region(
          duo, 'Future<void> _processRelayPipeline(', 'Future<String?> _uploadMyMessage(');
      final int decl = pipe.indexOf('final Map<String, dynamic> payload =');
      final int send = pipe.indexOf('_interpCall?.sendData(payload)');
      expect(decl, greaterThan(-1), reason: 'payload를 인라인으로 만들면 큐에 넣을 것이 없다');
      expect(send, greaterThan(decl));
      expect(pipe, contains("'msgId': msgId,"));
    });

    test('flush 기준은 DataChannel OPEN이다 — peer connected가 아니다', () {
      final String start = _region(
          duo, 'Future<bool> _startInterpreterWebrtc(', 'void _onInterpreterData(');
      final int hook = start.indexOf('onDataChannelState: (open) {');
      expect(hook, greaterThan(-1), reason: '채널 상태 훅이 없으면 열린 순간을 못 잡는다');
      final String body = start.substring(hook, hook + 420);
      expect(body, contains("if (open) _flushInterpPendingSends('channel_open')"));
      // connect() 반환 직후에는 밀지 않는다.
      expect(start, isNot(contains("_flushInterpPendingSends('connected')")));
    });

    test('채널이 닫혀 있으면 flush가 시도조차 안 한다', () {
      final String body = _region(duo, 'void _flushInterpPendingSends(String reason)',
          'void _clearInterpPendingSends(String reason)');
      expect(body, contains('!call.isDataChannelOpen'));
      expect(body, contains('pending_flush_blocked reason=channel_closed'));
    });
  });

  // ==========================================================================
  group('중복 저장을 만들지 않는다', () {
    late String flushBody;
    setUp(() {
      flushBody = _region(duo, 'void _flushInterpPendingSends(String reason)',
          'void _clearInterpPendingSends(String reason)');
    });

    test('flush가 History를 다시 쓰지 않는다', () {
      expect(flushBody, isNot(contains('_saveHistoryMessage')));
    });

    test('flush가 Firestore messages를 다시 쓰지 않는다', () {
      expect(flushBody, isNot(contains('_uploadMyMessage')));
    });

    test('flush가 파이프라인을 다시 돌리지 않는다', () {
      for (final String forbidden in <String>[
        '_processRelayPipeline',
        'translateForSpeech',
        '_onInterpreterTranscript',
      ]) {
        expect(flushBody, isNot(contains(forbidden)),
            reason: '이 큐는 송신 재시도 큐이지 파이프라인 재실행 큐가 아니다');
      }
    });

    test('전송 실패가 기록을 취소하지 않는다', () {
      // Firestore·History는 실패와 무관하게 한 번씩 나간다.
      final String branch = _region(
          duo, 'if (!sent) _queueInterpPendingSend(payload);', '    } else {');
      expect(branch, contains('unawaited(_uploadMyMessage('));
      expect(branch, contains('unawaited(_saveHistoryMessage('));
    });
  });

  // ==========================================================================
  group('통로·세션 규칙을 깨지 않는다', () {
    test('Firestore transport에서는 큐를 쓰지 않는다', () {
      for (final String fn in <String>[
        'void _queueInterpPendingSend(Map<String, dynamic> payload)',
        'void _flushInterpPendingSends(String reason)',
      ]) {
        final String body = _region(duo, fn, '\n  /// ');
        expect(body, contains('if (!_useInterpWebrtc) return;'),
            reason: '$fn 이 firestore 통화에서도 돈다');
      }
    });

    test('큐가 통로를 갈아 끼우지 않는다', () {
      final String body = _region(duo, 'void _queueInterpPendingSend(Map<String, dynamic> payload)',
          'void _clearInterpPendingSends(String reason)');
      expect(body, isNot(contains('_interpTransport =')));
      expect(body, isNot(contains('_listenForMessages')));
      expect(body, isNot(contains('PreparedAudioCapture')));
    });

    test('마이크를 접을 때 큐도 비운다', () {
      final String stop = _region(duo, 'Future<void> _stopInterpreterCapture(String reason)',
          'Future<void> _handleInterpreterPartnerLeft(');
      expect(stop, contains('_clearInterpPendingSends(reason)'));
    });

    test('세대를 올리기 전에 비운다', () {
      final int at = duo.indexOf("_clearInterpPendingSends('generation_changed')");
      final int bump = duo.indexOf('++_interpGeneration;', at);
      expect(at, greaterThan(-1));
      expect(bump, greaterThan(at));
    });

    test('dispose가 큐를 비운다', () {
      final int at = duo.indexOf('_interpPulse.dispose();');
      expect(duo.substring(at, at + 260),
          contains("_clearInterpPendingSends('dispose')"));
    });
  });

  // ==========================================================================
  group('로그로 추적할 수 있다', () {
    test('사유를 다 가릴 수 있다', () {
      for (final String line in <String>[
        'pending_added',
        'pending_drop reason=overflow',
        'pending_flush_start',
        'pending_sent',
        'pending_flush_blocked reason=send_failed',
        'pending_cleared',
      ]) {
        expect(duo, contains(line), reason: '로그 "$line" 이 없다');
      }
      // expired / staleGeneration은 enum 이름으로 찍힌다.
      expect(duo, contains('pending_drop reason=\${d.reason.name}'));
      expect(DuoInterpPendingDropReason.expired.name, 'expired');
      expect(DuoInterpPendingDropReason.staleGeneration.name, 'staleGeneration');
    });

    test('버린 것의 나이가 로그에 남는다', () {
      expect(duo, contains('ageMs='));
    });
  });
}
