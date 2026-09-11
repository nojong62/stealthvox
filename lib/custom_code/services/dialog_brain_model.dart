// ====================================================================
// 🧠 [DIALOG BRAIN] 대화 상대의 말을 **만드는** 모델.
// --------------------------------------------------------------------
// 서클톡·시나리오톡에서 AI가 다음에 할 말을 생성하는 경로 전용이다.
// 번역·정돈·교정·판정은 [history_text_model.dart]의 상수들이 맡고, 여기와
// 섞지 않는다 — 두뇌를 바꿨을 때 대화가 달라진 건지 후처리가 달라진 건지
// 갈라 볼 수 있어야 한다.
//
// 2026-09-12: `gpt-4o-mini` → `gpt-5.6-luna` 시험 시작.
//   1차는 서클톡 정규 턴([UnifiedBrain.streamCircleMemberTurn]) 한 곳만
//   이 상수를 본다. 실기기에서 HTTP·스트리밍·usage·지연이 확인된 뒤에
//   오프너·시나리오톡 정규 턴으로 넓힌다. 그 전에는 다른 호출부가 이
//   상수를 보게 하지 않는다.
// ====================================================================

/// 대화 두뇌 모델.
const String kDialogBrainModel = 'gpt-5.6-luna';

/// 되돌릴 때 쓸 이전 값. 지우지 말 것 — A/B의 반대편이다.
const String kDialogBrainModelPrevious = 'gpt-4o-mini';

/// Chat Completions `reasoning_effort`. 실시간 회화는 깊은 추론보다 첫 토큰이
/// 먼저라 `none`으로 고정하고 시작한다. 부족하면 `low`부터 올린다.
///
/// Responses API의 `reasoning: {effort}`와 이름이 다르다. 우리는 전부
/// Chat Completions다.
const String kDialogBrainReasoningEffort = 'none';
