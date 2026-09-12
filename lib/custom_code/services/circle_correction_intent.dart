enum CircleCorrectionAction { none, retry, replace }

class CircleCorrectionDecision {
  const CircleCorrectionDecision(this.action, {this.replacement = ''});

  final CircleCorrectionAction action;
  final String replacement;
}

String stripCircleCorrectionFraming(String transcript) {
  var cleaned = transcript.trim();
  cleaned = cleaned.replaceFirst(
    RegExp(
      r'^(아니[요]?[,.!\s]*|아\s*)?'
      r'(그게|그\s*말(?:이|은)?|그런\s*게|그런\s*뜻이|내\s*(말|뜻)이?)\s*'
      r'아니(?:라|고|야|에요|예요|었고|었다)?[,.!\s]*',
      caseSensitive: false,
    ),
    '',
  );
  cleaned = cleaned.replaceFirst(
    RegExp(
      r'^(내\s*(말|뜻)은|내가\s*(말한\s*건|한\s*말은)|그러니까|다시\s*말하면|'
      r'I\s+mean|what\s+I\s+mean\s+is|that.?s\s+not\s+what\s+I\s+meant)[,:.\s]*',
      caseSensitive: false,
    ),
    '',
  );
  return cleaned.trim();
}

/// 방금 전 사용자+AI 교환을 부정하는 명시적인 불만만 잡는다.
/// 단순 부정 답변("아니, 안 갔어")은 정상 대화로 그대로 둔다.
CircleCorrectionDecision detectCircleCorrectionIntent(
  String transcript, {
  required bool hasPreviousExchange,
}) {
  if (!hasPreviousExchange) {
    return const CircleCorrectionDecision(CircleCorrectionAction.none);
  }
  final text = transcript.trim();
  if (text.isEmpty) {
    return const CircleCorrectionDecision(CircleCorrectionAction.none);
  }

  final strongReplacementLead = RegExp(
    r'(그게\s*아니라|그\s*말(?:이|은)?\s*아니라|그런\s*뜻이\s*아니|'
    r'내\s*(말|뜻)은|내가\s*(말한\s*건|한\s*말은)|'
    r'다시\s*말하면|그러니까|I\s+mean|'
    r'what\s+I\s+mean\s+is|that.?s\s+not\s+what\s+I\s+meant)',
    caseSensitive: false,
  ).hasMatch(text);
  final noThenQuotedRestatement = RegExp(
    r'^\s*(아니|아니야|아니요)[,.!\s]+.+(?:냐|라|다|자|말했|물었|얘기했)고(?:요)?[.!?\s]*$',
    caseSensitive: false,
  ).hasMatch(text);

  if (strongReplacementLead || noThenQuotedRestatement) {
    var replacement = stripCircleCorrectionFraming(text);
    if (noThenQuotedRestatement) {
      replacement = replacement.replaceFirst(
        RegExp(r'^\s*(아니|아니야|아니요)[,.!\s]+', caseSensitive: false),
        '',
      );
    }
    if (replacement.isNotEmpty) {
      return CircleCorrectionDecision(
        CircleCorrectionAction.replace,
        replacement: replacement,
      );
    }
  }

  final previousWordsRejected = RegExp(
    r'(그\s*말|그런\s*말|그런\s*뜻|내\s*말|내가\s*(방금\s*)?말한\s*(말|게|건|것)|'
    r'방금\s*(내가\s*)?(한|말한)\s*(말|게|건|것)).{0,12}(아니|틀렸|잘못|다르)',
    caseSensitive: false,
  ).hasMatch(text);
  final explicitMisheard = RegExp(
    r'(잘못\s*(들었|알아들었|적었|받아적었|인식했|이해했)|'
    r'(내\s*말|그\s*말|방금\s*말).{0,8}(오해|잘못\s*(들|적|인식|이해))|'
    r'내가\s*(그런|그렇게)\s*말(?:을)?\s*(?:한\s*(게|건|것이)?\s*아니|안|않)|'
    r'(그렇게|그런\s*뜻으로)\s*말한\s*(게|건|것이)?\s*아니)',
    caseSensitive: false,
  ).hasMatch(text);
  if (previousWordsRejected || explicitMisheard) {
    return const CircleCorrectionDecision(CircleCorrectionAction.retry);
  }

  return const CircleCorrectionDecision(CircleCorrectionAction.none);
}
