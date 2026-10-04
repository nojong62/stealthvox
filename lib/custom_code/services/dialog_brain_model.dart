// ====================================================================
// 🧠 [DIALOG BRAIN] 대화 상대의 말을 **만드는** 모델.
// --------------------------------------------------------------------
// 서클톡·시나리오톡에서 AI가 다음에 할 말을 생성하는 경로 전용이다.
// 번역·정돈·교정·판정은 [history_text_model.dart]의 상수들이 맡고, 여기와
// 섞지 않는다 — 두뇌를 바꿨을 때 대화가 달라진 건지 후처리가 달라진 건지
// 갈라 볼 수 있어야 한다.
//
// 2026-09-12: `gpt-4o-mini`에서 Luna 계열 시험을 시작했다.
// 2026-09-29: Circle 검증 결과를 반영해 대화 두뇌를 `gpt-6-luna`로 통일했다.
// 서클톡과 시나리오톡의 정규 턴·오프너 등 활성 대화 경로가 이 모델을 본다.
// 번역·복원·기타 후처리는 별도 상수를 유지해 독립적으로 되돌릴 수 있다.
// ====================================================================

/// 서클톡 전용 대화 두뇌 모델.
const String kCircleDialogBrainModel = 'gpt-6-luna';

/// 시나리오톡과 공용 대화 경로의 기본 두뇌 모델.
const String kDialogBrainModel = 'gpt-6-luna';

/// 되돌릴 때 쓸 이전 값. 지우지 말 것 — A/B의 반대편이다.
const String kDialogBrainModelPrevious = 'gpt-4o-mini';

/// Chat Completions `reasoning_effort`의 기본값. 대부분의 독립적인 실시간
/// 대화 턴과 오프너는 `low`를 쓴다. 앞뒤 문맥을 다시 해석해야 하는 턴만
/// [selectDialogBrainReasoning]이 그 호출 하나를 `medium`으로 올린다.
///
/// Responses API의 `reasoning: {effort}`와 이름이 다르다. 우리는 전부
/// Chat Completions다.
const String kDialogBrainReasoningEffort = 'low';

/// Circle/Scenario의 한 Dialog Brain 호출에만 적용되는 추론 선택 결과.
/// 상태를 들고 있지 않으므로 `medium`은 다음 턴으로 이어지지 않는다.
class DialogBrainReasoningDecision {
  const DialogBrainReasoningDecision(this.effort, this.reason);

  final String effort;
  final String reason;
}

/// 별도 모델 호출 없이 현재 발화와 이미 알고 있는 대화 상태만으로
/// Dialog Brain의 추론 강도를 고른다.
///
/// 문장 길이는 입력으로 받지도 않는다. 긴 독립 문장은 `low`, 짧더라도 정정,
/// 지시어, 앞선 질문과의 재연결이 필요한 문장은 `medium`이 된다.
DialogBrainReasoningDecision selectDialogBrainReasoning({
  required String userText,
  String previousAssistantText = '',
  bool hasConversationContext = false,
  bool isCorrectionRetry = false,
  bool hasSttCorrectionContext = false,
  bool previousTurnHadUserFix = false,
  bool isStep2 = false,
}) {
  final text = userText.trim().toLowerCase();
  final previous = previousAssistantText.trim().toLowerCase();

  if (isCorrectionRetry || _containsUserCorrection(text)) {
    return const DialogBrainReasoningDecision('medium', 'user_correction');
  }
  if (hasSttCorrectionContext) {
    return const DialogBrainReasoningDecision('medium', 'stt_correction');
  }
  if (previousTurnHadUserFix) {
    return const DialogBrainReasoningDecision('medium', 'user_fix_context');
  }
  if (hasConversationContext && _hasAmbiguousMeaningScope(text)) {
    return const DialogBrainReasoningDecision('medium', 'meaning_scope');
  }
  if (hasConversationContext && _containsContextReference(text)) {
    return const DialogBrainReasoningDecision('medium', 'context_reference');
  }
  if (hasConversationContext && _conflictsWithPreviousInterpretation(text)) {
    return const DialogBrainReasoningDecision(
        'medium', 'interpretation_conflict');
  }
  if (isStep2 &&
      previous.isNotEmpty &&
      _previousTurnHasMultipleParts(previous) &&
      _looksLikePartialAnswer(text)) {
    return const DialogBrainReasoningDecision('medium', 'step2_partial_answer');
  }
  return const DialogBrainReasoningDecision('low', 'normal_turn');
}

bool _containsUserCorrection(String text) => RegExp(
      r'(아니\s*(그|제가|내가|그게|그건)?\s*(뜻|말|사람|거|것)?\s*(이|가)?\s*아니|'
      r'그\s*(뜻|말|사람|거|것)\s*(이|가)?\s*아니|제가\s*말한\s*(건|것은)|'
      r'내가\s*말한\s*(건|것은)|잘못\s*(이해|알아들|들었)|'
      r'no[, ]+i\s+mean|that(?:\s+is|\x27s)\s+not\s+what\s+i\s+meant|'
      r'i\s+didn(?:\x27t| not)\s+mean|you\s+misunderstood)',
      caseSensitive: false,
    ).hasMatch(text);

bool _containsContextReference(String text) => RegExp(
      r'(아까\s*(말|얘기|이야기)?|전에\s*(말|얘기|이야기)했던|앞에서\s*(말|얘기)한|'
      r'방금\s*(말|얘기)한|그\s*(사람|말|뜻|얘기|이야기|거|것|때|곳)|'
      r'그전에\s*(말|얘기)한|앞서\s*(말|언급)한|'
      r'what\s+(?:i|you)\s+(?:said|mentioned)\s+(?:earlier|before)|'
      r'(?:that|the)\s+(?:person|thing|meaning)\s+(?:from\s+)?(?:earlier|before)|'
      r'as\s+(?:i|you)\s+(?:said|mentioned)\s+(?:earlier|before))',
      caseSensitive: false,
    ).hasMatch(text);

bool _hasAmbiguousMeaningScope(String text) {
  final asksMeaning = RegExp(
    r'(무슨\s*뜻|뜻이\s*뭐|의미가\s*뭐|뭘\s*의미|what\s+does\s+(?:that|it|this)\s+mean|what\s+do\s+you\s+mean)',
    caseSensitive: false,
  ).hasMatch(text);
  final ambiguousTarget = RegExp(
    r'(이게|그게|그\s*말|그\s*뜻|이\s*말|저게|that|it|this|what\s+you\s+said)',
    caseSensitive: false,
  ).hasMatch(text);
  return asksMeaning && ambiguousTarget;
}

bool _conflictsWithPreviousInterpretation(String text) => RegExp(
      r'(그렇게\s*(말|생각)한\s*게\s*아니|그건\s*내\s*말이\s*아니|'
      r'왜\s*그렇게\s*(이해|생각)|내\s*말은\s*그게\s*아니|'
      r'that\s+isn(?:\x27t| is not)\s+what\s+i\s+said|'
      r'why\s+did\s+you\s+(?:think|take|understand)\s+it\s+that\s+way)',
      caseSensitive: false,
    ).hasMatch(text);

bool _previousTurnHasMultipleParts(String text) {
  final questionCount = '?'.allMatches(text).length;
  if (questionCount >= 2) return true;
  return RegExp(
    r'(그리고|또(?:는)?|둘\s*다|각각|왜.+어떻게|언제.+어디|'
    r'and\s+(?:why|how|when|where|what)|both|each)',
    caseSensitive: false,
  ).hasMatch(text);
}

bool _looksLikePartialAnswer(String text) {
  if (text.isEmpty) return true;
  return RegExp(
    r'^(그냥|글쎄(?:요)?|잘\s*모르|모르겠(?:어요|네요)?|한\s*가지만|그것만|일단|아마(?:요)?|'
    r'not\s+sure|i\s+don(?:\x27t| not)\s+know|maybe|just\s+that)'
    r'(?:\s|[.,!?]|$)',
    caseSensitive: false,
  ).hasMatch(text);
}
