// ====================================================================
// 🔁 [LATE-CONTINUATION] 늦은 이어 말하기 — 모드 공용 규칙
// --------------------------------------------------------------------
// Circle Talk과 Scenario Talk이 **같은 함수를 쓴다.** 각 모드에 규칙을 따로
// 두면 한쪽만 고쳐지고 다른 쪽은 옛 규칙으로 남는다 — 이 파일이 그것을 막는다.
//
// 여기 있는 것은 순수 함수뿐이다. 타이머·마이크·세대 번호 같은 상태는 각
// 모드가 자기 파일에서 들고, 이 함수들에 값으로 넘긴다.
// ====================================================================

// ====================================================================
// 🔁 [LATE-CONTINUATION] 늦은 이어 말하기 복구 창
// --------------------------------------------------------------------
// 문장 중간에 잠깐 쉬면 Server VAD가 발화 종료로 보고 speech_stopped를 준다.
// 그때 마이크를 바로 닫아 버리면 곧이어 나온 뒷말이 통째로 사라진다.
//   "주말에는 친구하고" → (공백) → "야구장에 가려고 해요"
// 이 창이 열려 있는 동안에는 녹음과 오디오 게이트를 살려 둬서, 뒷말이 같은
// 사용자 턴으로 합쳐질 수 있게 한다.
//
// ⚠️ 기준점은 speech_stopped다. transcription.completed 기준으로 잡으면
//   실측 437~841ms가 창을 먼저 갉아먹는다. 그리고 Server VAD의
//   silence_duration_ms(600)보다 짧은 공백은 애초에 갈리지 않으므로,
//   이 창이 실제로 막아야 하는 것은 600ms 이상 쉰 경우뿐이다.
//
// ⚠️ **정상 경로에 고정 지연을 추가하지 않는다.** 첫 전사가 확정되면 GPT는
//   지금과 똑같이 즉시 출발한다. 창은 마이크를 더 열어 둘 뿐이다.
const int kFreeTalkContinuationWindowMs = 1200;

/// 이어 발화의 `speech_stopped` 뒤 전사를 기다리는 기본 상한.
/// 실측 전사 지연이 437~841ms라 2,500ms면 넉넉하다.
const int kFreeTalkContinuationTranscriptTimeoutMs = 2500;

/// 대기 총량의 하드캡. `speech_stopped` 기준으로 이 시간이 지나면 서버가 아직
/// 전사를 물고 있다고 해도 확보된 조각으로 답변을 만든다.
///
/// ⚠️ **유저가 말하는 중일 때는 이 캡을 적용하지 않는다** — 말을 자르는 것보다
/// 몇 초 늦는 편이 낫다. 캡은 "말이 끝난 뒤 서버를 기다리는 시간"에만 걸린다.
const int kFreeTalkContinuationHardCapMs = 5000;

/// 🔁 [LATE-CONTINUATION] 새 `speech_started`를 앞 발화의 연속으로 볼 것인가.
///
/// **자격은 오직 이 시각 하나로 정해진다** — 유저가 복구 창 안에서 다시 말하기
/// 시작했는가. 전사가 언제 도착했는지는 자격과 무관하다. 전사는 발화마다 따로
/// 도는 비동기 작업이라 창 뒤에 올 수 있고, 그걸 이유로 발화를 버리면 유저가
/// 분명히 한 말이 사라진다.
///
/// 화면·세션 동일성은 호출부의 `_isStreamingTurnOwner`(mounted · !disposing ·
/// conversationActive · micOwner)가 이미 확인한 뒤다.
bool shouldTreatAsLateContinuation({
  required int msSinceSpeechStopped,
  required bool candidateAlive,
  required bool aiPlaybackStarted,
}) {
  if (msSinceSpeechStopped < 0) return false; // 앞 발화가 끝난 적이 없다
  if (msSinceSpeechStopped > kFreeTalkContinuationWindowMs) return false;
  if (candidateAlive) return false; // 이미 잡아 둔 후보가 있다
  if (aiPlaybackStarted) return false; // §H AI 음성이 이미 나가고 있다
  return true;
}

/// 후보가 살아 있는 동안 조각 하나를 접수한 뒤 무엇을 할 것인가.
enum ContinuationDecision {
  /// 아직 서버가 물고 있는 발화가 있다 — 더 기다린다.
  wait,

  /// 필요한 조각이 다 왔다 — 합친 문장으로 AI 답변을 **한 번** 시작한다.
  startAssistant,

  /// 안전 타임아웃까지 쓸 문장이 하나도 안 왔다 — 턴을 놓아준다(§G).
  abandon,
}

/// 이어 말하기 후보의 다음 행동. 우선순위가 곧 안전성이다.
///
///   1. [isUserSpeaking] → **무조건 기다린다.** 지금 나오고 있는 말을 두고
///      답변을 시작하면 그 말은 통째로 버려진다.
///   2. [serverHasPendingUtterance] → 기다린다(전사가 창 뒤에 와도 접수한다).
///   3. 둘 다 거짓이고 의미 있는 조각이 있음 → 답변을 **한 번** 시작한다.
///   4. 안전 타임아웃이고 유효 조각이 없음 → 턴을 놓아준다.
///
/// ⚠️ [isUserSpeaking]을 [serverHasPendingUtterance]로 갈음하면 안 된다.
///   B가 말하는 중에는 아직 `committed`가 안 나서 pending 장부가 비어 있을 수
///   있다. 그 순간 A의 전사만 도착하면 A 하나로 답이 나가 버린다.
///   1번이 2번보다 먼저이고, **[safetyExpired]로도 뚫리지 않는다.**
ContinuationDecision decideContinuationNext({
  required bool isUserSpeaking,
  required bool serverHasPendingUtterance,
  required bool hasMeaningfulSegment,
  required bool safetyExpired,
}) {
  if (isUserSpeaking) return ContinuationDecision.wait;
  if (!safetyExpired && serverHasPendingUtterance) {
    return ContinuationDecision.wait;
  }
  // 의미 있는 조각이 확보됐으면 시작한다. 안전 타임아웃이 났더라도 확보된
  // 문장은 잃지 않는다.
  if (hasMeaningfulSegment) return ContinuationDecision.startAssistant;
  // §F 머뭇거림만 있는 상태 — 시간이 남았으면 다음 의미 발화를 더 기다린다.
  if (!safetyExpired) return ContinuationDecision.wait;
  return ContinuationDecision.abandon;
}

/// 안전 타이머가 깨어났을 때 더 기다릴지, 지금 마무리할지.
///
/// [msSinceWaitStarted]는 **마지막 `speech_stopped`부터**의 경과시간이다.
/// 말하는 중이면 캡을 재지 않는다 — 캡은 "말이 끝난 뒤 서버를 기다린 시간"에만
/// 걸린다.
enum ContinuationWaitAction { keepWaiting, resolveNow }

ContinuationWaitAction decideContinuationWait({
  required bool isUserSpeaking,
  required bool serverHasPendingUtterance,
  required int msSinceWaitStarted,
}) {
  // 말하는 중인 유저를 시간으로 자르지 않는다.
  if (isUserSpeaking) return ContinuationWaitAction.keepWaiting;
  if (serverHasPendingUtterance &&
      msSinceWaitStarted < kFreeTalkContinuationHardCapMs) {
    return ContinuationWaitAction.keepWaiting;
  }
  return ContinuationWaitAction.resolveNow;
}

/// 🔁 [LATE-CONTINUATION] 한 사용자 턴의 전사 조각 하나.
///
/// [order]는 **발화 순서**다 — 소켓의 `input_audio_buffer.committed` 순번이며,
/// 전사 완료(`transcription.completed`)의 도착 순서와 다를 수 있다.
class UserTurnSegment {
  const UserTurnSegment({
    required this.itemId,
    required this.order,
    required this.text,
  });

  final String itemId;
  final int order;
  final String text;
}

/// 조각들을 **발화 순서대로** 한 문장으로 잇는다.
///
/// **GPT로 다듬거나 의미를 추측하지 않는다.** 허용하는 것은 기계적인 정리뿐이다:
/// 앞뒤 공백 제거 · 중복 공백 제거 · 뒤에 말이 더 붙는 조각의 임시 마침표 제거.
///
/// ⚠️ **글자가 같다는 이유로 조각을 버리지 않는다.** "정말 좋아요… 정말
/// 좋아요"처럼 실제로 두 번 말할 수 있다. 중복 차단은 오직 같은 `item_id`의
/// 재수신에만 적용한다([mergeUserTurnSegments]).
String composeUserTurnText(Iterable<String> orderedPieces) {
  final parts = <String>[];
  for (final raw in orderedPieces) {
    final piece = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (piece.isEmpty) continue;
    if (parts.isNotEmpty) {
      // 물음표·느낌표는 화자의 의도라 남긴다.
      final trimmed =
          parts.last.replaceAll(RegExp(r'[.,、。]+$'), '').trimRight();
      if (trimmed.isEmpty) {
        parts.removeLast();
      } else {
        parts[parts.length - 1] = trimmed;
      }
    }
    parts.add(piece);
  }
  return parts.join(' ').trim();
}

// ── 말풍선 장부 조작 ────────────────────────────────────────────────
// 인덱스는 앞쪽 말풍선이 지워지면 밀린다. 취소된 AI 말풍선을 정확히 집어
// 내려면 id가 있어야 한다. 위젯은 이 함수들을 setState로 감싸기만 한다 —
// 규칙 자체는 여기 있어야 화면 없이 검증할 수 있다.

int bubbleIndexById(List<Map<String, dynamic>> messages, String id) {
  if (id.isEmpty) return -1;
  return messages.indexWhere((m) => m['msgId'] == id);
}

/// 있으면 글자만 바꾼다. 없으면 false — 호출부가 새로 만든다.
bool updateBubbleTextById(
  List<Map<String, dynamic>> messages,
  String id,
  String text,
) {
  final index = bubbleIndexById(messages, id);
  if (index < 0) return false;
  messages[index]['target'] = text;
  return true;
}

bool removeBubbleById(List<Map<String, dynamic>> messages, String id) {
  final index = bubbleIndexById(messages, id);
  if (index < 0) return false;
  messages.removeAt(index);
  return true;
}

/// 사용자 말풍선은 한 턴에 **하나**다. 이어 말하기로 문장이 자라도 새로
/// 만들지 않고 기존 말풍선을 갱신한다.
void upsertUserBubble(
  List<Map<String, dynamic>> messages, {
  required String id,
  required String text,
}) {
  messages.removeWhere((m) => m['role'] == 'HOST_TEMP');
  if (updateBubbleTextById(messages, id, text)) return;
  messages.add(<String, dynamic>{
    'role': 'HOST',
    'target': text,
    'original': '',
    'msgId': id,
  });
}

/// 조각 하나를 턴에 넣고 **발화 순서대로** 다시 세운다.
///
/// ⚠️ `transcription.completed`의 도착 순서는 발화 순서가 아니다. 전사는
/// 발화마다 따로 도는 비동기 작업이라 짧은 뒷말이 먼저 끝나 먼저 도착할 수
/// 있다. 도착 순서로 이으면 "야구장에 가려고 해요 주말에는 친구하고"가 된다.
///
/// 같은 `item_id`가 다시 오면 넣지 않는다. 서로 다른 `item_id`는 전사 내용이
/// 똑같아도 둘 다 남긴다.
///
/// 반환값은 "새로 들어갔는가"다.
bool mergeUserTurnSegments(
  List<UserTurnSegment> segments,
  UserTurnSegment incoming,
) {
  if (incoming.itemId.isNotEmpty &&
      segments.any((s) => s.itemId == incoming.itemId)) {
    return false;
  }
  segments.add(incoming);
  // 순번이 같으면(순번을 못 받은 예외) 들어온 순서를 지켜야 한다. Dart의
  // List.sort는 불안정하므로 삽입 인덱스를 2차 키로 넣어 안정 정렬로 만든다.
  final indexed = <MapEntry<int, UserTurnSegment>>[
    for (var i = 0; i < segments.length; i++) MapEntry(i, segments[i]),
  ];
  indexed.sort((a, b) {
    final byOrder = a.value.order.compareTo(b.value.order);
    return byOrder != 0 ? byOrder : a.key.compareTo(b.key);
  });
  segments
    ..clear()
    ..addAll(indexed.map((e) => e.value));
  return true;
}

/// "어…", "음…" 같은 머뭇거림만인가. 이것만으로는 답변을 확정하지 않고
/// 다음 의미 있는 전사를 짧게 더 기다린다(§F).
bool isHesitationOnlyTranscript(String text) {
  final clean = text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s가-힣]'), '')
      .replaceAll(RegExp(r'\s+'), '')
      .trim();
  if (clean.isEmpty) return true;
  return RegExp(r'^[흠음어아으그저네넵응윽허헐하흐엄]{1,6}$').hasMatch(clean);
}
