/// 역할교환(Practice) 한 줄 읽기 판정.
///
/// 판정은 배울 언어의 글자 체계에 따라 갈린다.
/// - 라틴 글자(영어·스페인어 등): 단어 단위. 8단어 미만은 인식만 되면 통과,
///   8단어 이상은 60% 이상 맞아야 통과(기존 동작 그대로).
/// - 그 밖의 글자(한글·가나·한자·키릴·데바나가리 등): 단어 경계가 불안정하므로
///   글자 단위 2-gram 일치율로 본다. 짧은 줄(16자 미만)은 인식만 되면 통과,
///   긴 줄은 대본 2-gram의 50% 이상이 인식 결과에 있어야 통과.
library;

String normalizePracticeMatchText(String text) {
  var normalized = text
      .toLowerCase()
      .replaceAll(RegExp(r"[’`´]"), "'")
      .replaceAll(RegExp(r"\bi'm\b"), "i am")
      .replaceAll(RegExp(r"\byou're\b"), "you are")
      .replaceAll(RegExp(r"\bwe're\b"), "we are")
      .replaceAll(RegExp(r"\bthey're\b"), "they are")
      .replaceAll(RegExp(r"\bhe's\b"), "he is")
      .replaceAll(RegExp(r"\bshe's\b"), "she is")
      .replaceAll(RegExp(r"\bit's\b"), "it is")
      .replaceAll(RegExp(r"\bdon't\b"), "do not")
      .replaceAll(RegExp(r"\bdoesn't\b"), "does not")
      .replaceAll(RegExp(r"\bdidn't\b"), "did not")
      .replaceAll(RegExp(r"\bcan't\b"), "cannot")
      .replaceAll(RegExp(r"\bcannot\b"), "can not")
      .replaceAll(RegExp(r"\bwon't\b"), "will not")
      .replaceAll(RegExp(r"\bwouldn't\b"), "would not")
      .replaceAll(RegExp(r"\bcouldn't\b"), "could not")
      .replaceAll(RegExp(r"\bshouldn't\b"), "should not")
      .replaceAll(RegExp(r"\bisn't\b"), "is not")
      .replaceAll(RegExp(r"\baren't\b"), "are not")
      .replaceAll(RegExp(r"\bwasn't\b"), "was not")
      .replaceAll(RegExp(r"\bweren't\b"), "were not")
      .replaceAll(RegExp(r"\bi've\b"), "i have")
      .replaceAll(RegExp(r"\byou've\b"), "you have")
      .replaceAll(RegExp(r"\bi'll\b"), "i will")
      .replaceAll(RegExp(r"\byou'll\b"), "you will")
      .replaceAll(RegExp(r"\bi'd\b"), "i would")
      .replaceAll(RegExp(r"\byou'd\b"), "you would");
  // 글자(모든 언어)와 숫자만 남긴다. 예전에는 a-z0-9만 남겨서 한글이 전부 지워졌다.
  normalized = normalized.replaceAll(RegExp(r"[^\p{L}\p{N}\s]", unicode: true), " ");
  return normalized.replaceAll(RegExp(r"\s+"), " ").trim();
}

bool _isLatinScript(String normalized) {
  final letters = RegExp(r"\p{L}", unicode: true).allMatches(normalized).length;
  if (letters == 0) return true;
  final latin = RegExp(r"[a-zÀ-ɏ]").allMatches(normalized).length;
  return latin * 2 >= letters;
}

Set<String> practiceMatchWords(String text) {
  const weakWords = {'a', 'the', 'to', 'of', 'in', 'on'};
  return normalizePracticeMatchText(text)
      .split(' ')
      .where((word) => word.length > 1 && !weakWords.contains(word))
      .toSet();
}

String _practicePhoneticKey(String word) {
  return word
      .replaceAll('th', 't')
      .replaceAll(RegExp(r'[rl]'), 'l')
      .replaceAll(RegExp(r'[bv]'), 'b')
      .replaceAll(RegExp(r'[pf]'), 'p')
      .replaceAll(RegExp(r'[tds]'), 't')
      .replaceAll(RegExp(r'[zj]'), 'j');
}

bool practiceWordsMatch(String target, String spoken) {
  if (target == spoken) return true;
  if ((target.length - spoken.length).abs() > 2) return false;
  return _practicePhoneticKey(target) == _practicePhoneticKey(spoken);
}

double practiceSimilarity(Set<String> targetWords, Set<String> spokenWords) {
  if (targetWords.isEmpty || spokenWords.isEmpty) return 0.0;
  var matched = 0;
  for (final target in targetWords) {
    if (spokenWords.any((spoken) => practiceWordsMatch(target, spoken))) {
      matched++;
    }
  }
  return matched / targetWords.length;
}

List<String> _bigrams(String compact) {
  if (compact.length < 2) return compact.isEmpty ? const [] : [compact];
  return [for (var i = 0; i < compact.length - 1; i++) compact.substring(i, i + 2)];
}

/// 대본 2-gram 중 인식 결과에도 있는 비율(0~1).
double practiceBigramCoverage(String target, String spoken) {
  final t = _bigrams(normalizePracticeMatchText(target).replaceAll(' ', ''));
  final s = _bigrams(normalizePracticeMatchText(spoken).replaceAll(' ', '')).toSet();
  if (t.isEmpty || s.isEmpty) return 0.0;
  return t.where(s.contains).length / t.length;
}

/// 한 줄을 끝까지 읽었는지. [targetText]는 화면에 보이는 대본(배울 언어).
bool practiceReadThroughPass({
  required String targetText,
  required String transcript,
}) {
  if (transcript.trim().isEmpty) return false;
  final normTarget = normalizePracticeMatchText(targetText);
  if (_isLatinScript(normTarget)) {
    final tWords = practiceMatchWords(targetText);
    final sWords = practiceMatchWords(transcript);
    if (sWords.isEmpty) return false;
    if (tWords.length < 8) return true;
    return practiceSimilarity(tWords, sWords) >= 0.6;
  }
  final compactSpoken = normalizePracticeMatchText(transcript).replaceAll(' ', '');
  if (compactSpoken.isEmpty) return false;
  final compactTarget = normTarget.replaceAll(' ', '');
  if (compactTarget.length < 16) return true;
  return practiceBigramCoverage(targetText, transcript) >= 0.5;
}
