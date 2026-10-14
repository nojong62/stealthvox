// ====================================================================
// ✍️ [TEXT MODELS] 글을 손보는 모델을 **계층마다 따로** 둔다.
// --------------------------------------------------------------------
// 글자가 만들어지는 단계는 셋이고, 상수도 셋이다. 하나를 A/B 하려고 바꿨을 때
// 다른 기능의 결과까지 같이 흔들리면 무엇이 좋아졌는지 알 수 없다.
//
//   ① 소리 → 글자   `gpt-transcribe` (스트리밍 전사)
//      **오디오 모델이라 여기 상수들과 무관하다.** chat 계열로 대체할 수 없다.
//      이 층의 지렛대는 전사 세션의 `prompt`(어휘 힌트)인데 아직 안 쓴다.
//
//   ② 통화 정돈     [kDuoCanonicalModel]
//      양쪽 전사를 한 시간축으로 합쳐 조각을 잇고 되먹임·중복을 가른다.
//      **글자는 고치지 않는다.**
//
//   ②-a 원문 문맥 교정 [kDuoOriginCorrectorModel]
//      통화 전체 문맥으로 잘못 들린 낱말 하나를 되살린다. ②의 앞에 선다.
//
//   ③ 공부방 교정   [kHistoryRepairModel]
//      잘못 들은 낱말을 문맥으로 되살리고 배울글을 만든다.
//
// "글자가 이상하다"의 원인이 ①이면 ②③을 아무리 올려도 안 낫는다.
// 서클톡·시나리오톡 모델은 여기서 건드리지 않는다.
// ====================================================================

/// ② 듀오 통화 정돈(canonical reconciliation).
///
/// 2026-10-14: gpt-4.1-mini(2027-01-14 종료) → `gpt-6-luna` + [kHistoryTextReasoningEffort].
const String kDuoCanonicalModel = 'gpt-6-luna';

/// ②-a 통화 원문 문맥 교정(Duo Direct).
///
/// **①의 결과를 고치는 층이고, ②의 구조 판정과 다른 일이다.** 통화가 끝나
/// 전체 문맥이 생긴 뒤에 잘못 들린 낱말 하나를 되살린다. 대사를 만드는
/// [kDialogBrainModel]과도, 구조만 보는 [kDuoCanonicalModel]과도 합치지
/// 않는다 — 셋 중 하나를 바꿨을 때 무엇이 달라졌는지 갈라 볼 수 있어야 한다.
///
/// 2026-09-29: Circle 검증 결과를 반영해 `gpt-6-luna`로 전환했다.
const String kDuoOriginCorrectorModel = 'gpt-6-luna';

/// ③ 공부방 원문 교정 + 배울글.
///
/// ②와 **일부러 따로 둔다.** 지금은 값이 같지만, 한쪽만 되돌릴 수 있어야 한다.
/// 2026-10-14: gpt-4.1-mini(2027-01-14 종료) → `gpt-6-luna`.
const String kHistoryRepairModel = 'gpt-6-luna';

/// ⚡ Snap Echoing 의미 단위 나누기. 글자는 안 바꾸고 끊는 자리만 정한다.
/// ③과 따로 둔다 — 끊는 결과만 따로 A/B 할 수 있어야 한다.
const String kSnapChunkModel = 'gpt-6-luna';

/// ②③과 학습용 문장 생성의 `reasoning_effort`. 통화·대화가 끝난 뒤에 도는
/// 일이라 지연보다 문맥 해석이 먼저다. 대화 중에 도는 후처리는
/// [kLiveTextReasoningEffort]를 본다 — 이 값을 거기로 옮기지 말 것.
///
/// 추론 토큰도 `max_completion_tokens`에서 나간다. 각 호출부는 옛
/// `max_tokens`의 약 2.5배를 주고, 바닥나면 `[COMPLETION-BUDGET]`이 찍힌다.
const String kHistoryTextReasoningEffort = 'low';

/// Circle Talk History의 원문 복원 필요 여부를 먼저 가르는 Decisions 모델.
///
/// 이 모델은 문장을 고치지 않는다. `false`면 기존 원문 복원을 생략하고,
/// `true`거나 판정 호출이 실패하면 [kHistoryRepairModel]이 하던 기존
/// 의심 span 탐지 → PCM 재청취 → 수정 흐름을 그대로 탄다.
const String kCircleHistoryDecisionModel = 'gpt-6-luna';

/// 되돌릴 때 쓸 이전 값. 지우지 말 것 — A/B의 반대편이다.
const String kTextModelPrevious = 'gpt-4o-mini';

// ====================================================================
// 🛠️ [POST-PROCESS] 위 ②③을 뺀 **나머지 후처리 전부**가 보는 모델.
// --------------------------------------------------------------------
// 번역·정돈·검증·요약·언어 판정·공부방 문장 생성 등, "이미 만들어진 말을
// 다듬는" 28곳이 여기 한 상수를 본다. 2026-09-18 전까지는 파일마다
// `'gpt-4o-mini'` 문자열이 박혀 있어 한 번에 바꿀 수도, 되돌릴 수도 없었다.
//
// 대사를 만드는 [kDialogBrainModel]과 값이 같아도 **합치지 않는다** — 두뇌를
// 되돌릴 때 후처리까지 같이 되돌아가면 무엇이 달라졌는지 갈라 볼 수 없다.
//
// ⚠️ 현재 reasoning 모델 호출은 `temperature` 없이 `max_completion_tokens`와
//   `reasoning_effort`를 사용한다. 호출부는 모두 이 형식으로 맞춰 두었으며,
//   gpt-4o-mini로 되돌려도 이 요청 형식은 그대로 사용할 수 있다.
// ====================================================================

/// 후처리 모델. 2026-09-29: `gpt-4o-mini` 계열에서 `gpt-6-luna`로 전환했다.
const String kPostProcessModel = 'gpt-6-luna';

/// 후처리 `reasoning_effort`. 판정·번역은 첫 토큰이 먼저라 `none`으로 시작한다.
const String kPostProcessReasoningEffort = 'none';

/// 대화 **도중에** 도는 후처리의 `reasoning_effort`. 유저 턴 번역, 자막용
/// 원문, 말투 교정, 세션 롤오버 요약, 원문 언어 판정이 본다.
///
/// [kPostProcessReasoningEffort]와 **일부러 따로 둔다.** History 품질을 위해
/// 후처리를 올려도 대화 반응 속도는 흔들리지 않아야 한다. 올리지 말 것.
const String kLiveTextReasoningEffort = 'none';

// ====================================================================
// 🗣️ [DUO LIVE TRANSLATION] 통화 중 현재 발화 번역 전용 모델.
// --------------------------------------------------------------------
// 공용 후처리와 분리한다. 듀오 번역만 되돌려 비교할 수 있어야 하며,
// Circle/Scenario와 히스토리 정돈·복원·요약에는 이 설정을 쓰지 않는다.
// 문맥을 덧붙이지 않고 현재 발화 하나만 보낸다.
//
// 2026-10-14: gpt-4o-mini(2027-01-14 종료) → gpt-6-luna `none`.
// 기준선(gpt-4o-mini, 독일어↔중국어 10턴): translateTotalMs 895~1604ms.
// 추론을 켜면 통화가 그만큼 굼떠진다 — `none`에서 올리지 말 것.
// ====================================================================

const String kDuoLiveTranslationModel = 'gpt-6-luna';
const String kDuoLiveTranslationReasoningEffort = 'none';

const Map<String, dynamic> kDuoLiveTranslationModelOptions = <String, dynamic>{
  'model': kDuoLiveTranslationModel,
  'reasoning_effort': kDuoLiveTranslationReasoningEffort,
};
