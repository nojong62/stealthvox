// ====================================================================
// 📝 [HISTORY-FINALIZE] 히스토리 첫 페이지는 **마지막 원고 검수 자리**다.
// --------------------------------------------------------------------
// 대화가 끝나면 공부방 첫 화면에서 사용자가 자기가 한 말을 한 번 훑고,
// 잘못 들린 줄을 고치고, 공부할 것이 아닌 줄을 지운다. 그렇게 **확정한
// 원문 하나만**이 그 뒤 모든 학습 자료(배울글·Practice·My English·
// Native English)의 재료가 된다.
//
// 그래서 방마다 단계가 둘이다.
//
//   DRAFT      아직 검수 중. 원문을 고치고 지울 수 있고, **AI 생성은 하나도
//              돌지 않는다.** 확정 전에 만든 번역은 어차피 버려질 글이라,
//              만들지 않는 것이 비용·정합성 양쪽에서 옳다.
//
//   FINALIZED  사용자가 `최종 수정 완료`를 눌렀다. 원문은 잠기고, 그때부터
//              생성이 열린다. **되돌리는 문은 만들지 않는다** — 마음에 안
//              들면 방을 통째로 지우고 새로 만든다.
//
// ⚠️ **방 전체의 GENERATED 상태는 만들지 않는다.** My English와 Native
//   English는 그 페이지를 열 때 만드는 lazy generation이라, 사용자가 그
//   페이지를 끝내 안 열면 방은 영영 "생성 완료"가 아니다. 무엇이 만들어졌는지는
//   이미 생성물마다 자기 마커가 쥐고 있다 — `target_generated_at`(줄 단위),
//   `speech_generated_at`·`my_speech`·`native_english`(방 단위). 그 위에 방
//   전체 상태를 하나 더 얹으면 두 진실이 어긋나는 날이 온다.
//
// 📌 **필드가 없는 방은 FINALIZED다.** 마이그레이션은 하지 않는다. 이 기능이
//   생기기 전에 쌓인 방들은 이미 학습 자료를 다 만들어 두고 쓰고 있어서,
//   DRAFT로 보면 멀쩡히 쓰던 사람에게 어느 날 "먼저 확정하세요"가 뜬다.
//   옛 방은 지금까지처럼 그대로 돌고, 편집만 없다(원래도 없었다).
// ====================================================================

import 'duo_study_state.dart';

/// 방 문서에 적는 단계. 없으면 옛 방이다([resolveHistoryPhase]).
const String kHistoryStateField = 'history_state';

/// 검수 중. **새로 만드는 방만 이 값으로 시작한다.**
const String kHistoryStateDraft = 'draft';

/// 사용자가 확정했다. 원문 잠금 + 생성 허용.
const String kHistoryStateFinalized = 'finalized';

/// 확정한 순간. 어느 원문을 기준으로 만든 학습 자료인지 되짚는 기준선이다.
const String kHistoryFinalizedAtField = 'history_finalized_at';

/// 사용자가 이 줄을 직접 손댔다는 표시(수정이든 삭제든).
///
/// **Canonical이 이 줄을 다시 덮지 못하게 하는 근거다.** 통화 정돈은 방을 열
/// 때마다 새 판이 왔는지 보고 원문을 갈아 끼우는데, 사용자가 고친 줄까지
/// 갈아 끼우면 방금 한 수정이 조용히 사라진다.
const String kMessageUserEditedAtField = 'user_edited_at';

/// 🧭 [SUBJECT-HINT] 이 줄이 **누구 얘기인가**를 적은 참고용 주어.
///
/// 한국어는 이미 통하는 주어를 생략한다. 영어는 못 한다. 그래서 배울글을
/// 만들 때 누군가는 그 자리를 채워야 하고, 지금까지는 GPT가 줄마다 따로
/// 찍었다 — 같은 사람이 줄마다 he·they로 갈린 이유가 그것이다.
///
/// **3자가 나오는 줄에만 값이 있다.** 두 사람의 통화라 거의 모든 줄은 나
/// 아니면 너이고, 그런 줄은 비어 있다.
///
/// ⚠️ **`original_text`에 넣지 않는다.** 확정된 원문 하나가 배울글·Practice·
/// My English의 재료라, 참고 표시가 거기 섞이면 학습 자료에 괄호가 따라간다.
/// 화면에서만 줄 앞에 흐리게 붙여 보여준다.
const String kMessageSubjectHintField = 'subject_hint';

/// 참고 주어를 사용자가 직접 고친 순간. 찍혀 있으면 정돈이 덮지 않는다.
/// 줄 자체를 고친 것([kMessageUserEditedAtField])과는 별개다 — 글자는 그대로
/// 두고 주어만 바로잡을 수 있다.
const String kMessageSubjectHintEditedField = 'subject_hint_edited_at';

/// 히스토리 방이 지금 어느 단계인가.
enum HistoryEditPhase {
  /// 검수 중 — 편집 가능, 생성 금지.
  draft,

  /// 확정됨 — 편집 금지, 생성 허용. **옛 방도 여기다.**
  finalized,
}

String _stateOf(Map<String, dynamic>? room) =>
    (room?[kHistoryStateField] ?? '').toString().trim();

/// 이 방의 단계. **모르는 값과 없는 값은 모두 FINALIZED다** — 판단이 안 서면
/// 지금까지 돌던 대로 도는 쪽이 안전하다(편집만 안 열린다).
HistoryEditPhase resolveHistoryPhase(Map<String, dynamic>? room) =>
    _stateOf(room) == kHistoryStateDraft
        ? HistoryEditPhase.draft
        : HistoryEditPhase.finalized;

/// 이 방이 **새 흐름으로 만들어진 방인가.** 옛 방(필드 없음)과 구별한다.
///
/// 옛 방은 FINALIZED로 취급하지만 "사용자가 확정한 방"은 아니다. 둘을
/// 뭉뚱그리면 옛 Duo 방에 Canonical이 영영 못 붙는다 — 앱을 먼저 끄는 바람에
/// 아직 정돈 결과를 못 받은 방이 그대로 굳는다.
bool historyStateIsExplicit(Map<String, dynamic>? room) {
  final state = _stateOf(room);
  return state == kHistoryStateDraft || state == kHistoryStateFinalized;
}

/// 사용자가 직접 확정을 누른 방인가.
bool historyIsUserFinalized(Map<String, dynamic>? room) =>
    _stateOf(room) == kHistoryStateFinalized;

/// 원문을 고치고 지울 수 있는가.
bool historyEditAllowed(Map<String, dynamic>? room) =>
    resolveHistoryPhase(room) == HistoryEditPhase.draft;

/// AI가 무언가를 새로 만들어도 되는가(배울글·Practice·My/Native English).
///
/// **확정 전에는 무엇도 만들지 않는다.** 만들어 봐야 사용자가 다음 줄을 고치는
/// 순간 버릴 글이고, 그 사이 화면은 "곧 나올 것"처럼 보인다.
bool historyGenerationAllowed(Map<String, dynamic>? room) =>
    resolveHistoryPhase(room) == HistoryEditPhase.finalized;

/// 지금 `최종 수정 완료`를 누를 수 있는가. **1회성이다** — 확정된 방에서 다시
/// 누르는 길은 없다.
bool canFinalizeHistory(Map<String, dynamic>? room) =>
    resolveHistoryPhase(room) == HistoryEditPhase.draft;

/// 새 방을 만들 때 얹는 값. 방 생성 자리마다 이 한 줄만 넣는다.
Map<String, dynamic> historyDraftSeed() => <String, dynamic>{
      kHistoryStateField: kHistoryStateDraft,
    };

/// 확정할 때 방 문서에 쓰는 값. [finalizedAt]은 호출부가 넘긴다
/// (`FieldValue.serverTimestamp()`) — 이 파일은 Firestore를 모른다.
Map<String, dynamic> historyFinalizePatch({required Object finalizedAt}) =>
    <String, dynamic>{
      kHistoryStateField: kHistoryStateFinalized,
      kHistoryFinalizedAtField: finalizedAt,
    };

/// 편집한 원문을 저장할 때 줄 문서에 쓰는 값.
///
/// **배울글을 함께 비운다.** 그 번역은 고치기 전 문장에서 나온 것이라, 원문만
/// 바꾸면 두 줄이 서로 다른 이야기를 하게 된다. 비워 두면 확정 후 생성기가
/// 최종 원문으로 다시 만든다(`_historyTargetNeedsWork`).
Map<String, dynamic> historyMessageEditPatch({
  required String text,
  required Object editedAt,
}) =>
    <String, dynamic>{
      'original_text': text.trim(),
      'translated_text': '',
      kMessageUserEditedAtField: editedAt,
    };

/// 🧭 참고 주어만 고쳤을 때 줄 문서에 쓰는 값.
///
/// **배울글을 함께 비운다.** 참고 주어는 번역이 주어를 채우는 근거라,
/// 그것이 바뀌면 옛 번역은 다른 사람 얘기를 하고 있는 셈이 된다.
///
/// 원문([kMessageUserEditedAtField])은 건드리지 않는다 — 말은 그대로 두고
/// 누구 얘기인지만 바로잡는 자리다.
Map<String, dynamic> historySubjectHintEditPatch({
  required String subject,
  required Object editedAt,
}) =>
    <String, dynamic>{
      kMessageSubjectHintField: subject.trim(),
      'translated_text': '',
      kMessageSubjectHintEditedField: editedAt,
    };

/// 사용자가 내용을 다 지웠을 때 줄 문서에 쓰는 값.
///
/// **문서를 지우지 않는다.** 원본은 남고 보이지 않을 뿐이다 — 듀오 원본과의
/// 대조, 되짚기, 권한 어느 쪽으로도 지울 이유가 없다.
Map<String, dynamic> historyMessageDeletePatch({required Object editedAt}) =>
    <String, dynamic>{
      kStudyStateField: kStudyStateDeletedByUser,
      kMessageUserEditedAtField: editedAt,
    };

/// 편집 입력이 "이 줄을 지운다"는 뜻인가.
bool editedOriginalMeansDelete(String input) => input.trim().isEmpty;

// ══════════════════════════════════════════════════
// 📋 [PREVIEW] 목록에 뜨는 한 줄(`last_message`)
//
//   미리보기는 **원본 로그의 마지막 줄이 아니라, 지금 화면에 보이는 마지막
//   줄**이어야 한다. 그러지 않으면 사용자가 분명히 지운 문장이 목록에 계속
//   남아 "삭제가 안 된 것처럼" 보인다.
//
//   보이는지 아닌지는 [isStudyVisible] 하나로 판정한다 — 화면·연습·배울글이
//   보는 그 규칙 그대로다. 여기에 두 번째 판정을 만들지 않는다.
// ══════════════════════════════════════════════════

/// 미리보기 후보가 되는 줄의 원문만 시간순으로 추린다.
/// 기술적으로 감춰진 줄(에코·중복·조각)과 사용자가 지운 줄이 함께 빠진다.
List<String> visibleOriginalsForPreview(
        Iterable<Map<String, dynamic>> messages) =>
    <String>[
      for (final m in messages)
        if (isStudyVisible(m[kStudyStateField]))
          (m['original_text'] ?? '').toString()
    ];

/// 편집·삭제 뒤 방 문서에 쓸 미리보기.
///
/// 반환값 셋을 구별한다.
///   · `null` — **쓸 필요가 없다.** 중간 줄을 고쳤거나 지운 경우다. 방 문서에
///     쓸데없이 쓰지 않는다.
///   · `''`   — 보이는 줄이 하나도 남지 않았다. **필드를 지우지 않고 빈
///     문자열을 쓴다.** 이 구별이 목록에서 두 방을 가른다.
///       · 필드가 아예 없는 방 = 대사가 한 번도 없던 방 → 목록에서 뺀다
///         (`_discardOutgoingRoomIfUnused`와 같은 정책).
///       · 필드가 빈 방   = 대화가 있었는데 사용자가 다 지운 방 → 목록에
///         남는다. 안 남기면 방에 다시 들어가 지울 수도 볼 수도 없는
///         유령 방이 된다.
///   · 그 외  — 새 미리보기.
///
/// [visibleOriginals]는 [visibleOriginalsForPreview]가 만든 목록,
/// [changedIndex]는 그 안에서 바뀐 줄의 자리다(없으면 음수).
String? recomputeLastMessage({
  required List<String> visibleOriginals,
  required int changedIndex,
  required bool deleted,
  String editedText = '',
}) {
  if (changedIndex < 0 || visibleOriginals.isEmpty) return null;
  final int lastIndex = visibleOriginals.length - 1;
  // 미리보기는 마지막 줄만 비춘다. 중간 줄은 무엇을 해도 그대로다.
  if (changedIndex != lastIndex) return null;
  if (!deleted) return editedText.trim();
  // 마지막 줄을 지웠다 → 그 앞의 **보이는** 줄로 물러난다.
  for (int i = lastIndex - 1; i >= 0; i--) {
    final String text = visibleOriginals[i].trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}

/// 🧩 [CANONICAL 가드 ①] 이 **방**에 통화 정돈 결과를 반영해도 되는가.
///
/// 확정한 방은 절대 안 된다 — 사용자가 최종본이라고 못 박은 글이다. 옛 방은
/// 지금까지처럼 반영한다(필드가 없다고 해서 정돈을 잃으면 안 된다).
bool duoCanonicalMayApplyToRoom(Map<String, dynamic>? room) =>
    !historyIsUserFinalized(room);

/// 🧩 [CANONICAL 가드 ②] 이 **줄**을 통화 정돈이 덮어써도 되는가.
///
/// 사용자가 한 번이라도 손댄 줄은 덮지 않는다. DRAFT에서 한 줄을 고친 직후
/// 새 판이 도착하는 일이 실제로 있고, 그때 방 단위 가드만으로는 그 수정이
/// 조용히 지워진다.
bool duoCanonicalMayApplyToMessage(Map<String, dynamic>? message) {
  if (message == null) return true;
  if (message[kMessageUserEditedAtField] != null) return false;
  final state = (message[kStudyStateField] ?? '').toString().trim();
  return state != kStudyStateDeletedByUser;
}
