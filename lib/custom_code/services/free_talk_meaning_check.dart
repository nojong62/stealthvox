// ====================================================================
// 🧭 [MEANING-CHECK] Free Talk에서 뜻이 안 통하는 배울 언어 문장을 되묻는다.
// --------------------------------------------------------------------
// Free Talk 유저는 배우는 언어로 말한다(실장님, 2026-11-26).
//
//   - 작은 실수(뜻은 통함): 멈추지 않는다. 유저 줄을 바른 배울 언어 문장으로
//     고쳐 보여 주고([USER_FIX] 형식) 대화를 잇는다.
//   - 뜻이 안 통함: 두 단계로 확인한다. 질문은 모두 **배울 언어로 쉽게**,
//     말과 글자로 같이 나온다.
//
//   ① 되묻기  "이런 말이에요, 저런 말이에요? 다시 말해 주세요."
//        [MEANING_CHECK]
//        <쉬운 배울 언어 질문>
//   ② 유저 대답(배울 언어든 대화언어든) → AI가 뜻을 잡아 한 번 더 확인
//        [MEANING_CONFIRM]
//        <"그럼 이 말을 하려던 거예요?" — 쉬운 배울 언어>
//        [SENTENCE]
//        <유저가 하려던 말 — 자연스러운 배울 언어 문장>
//   ③ "네"면 처음 유저 줄을 그 문장으로 고치고, 질문 말풍선은 증발하고,
//      AI가 그 문장을 이어 받아 대화를 계속한다. "아니요"면 ①로 돌아간다.
//
// 쉬운 말은 교정하는 동안(①②)만 쓴다. 확인이 끝나면 대화는 유저 수준에
// 맞춘 평소 말로 돌아간다.
//
// 처음 한 말은 [kFreeTalkAttemptField]로 같이 남긴다.
// 추가 호출은 없다 — 서클 멤버 답변 호출 하나가 답변 대신 이 형식을 낸다.
// 첫 턴이든 몇 번째 턴이든 뜻이 안 통하면 매번 묻는다(실장님, 2026-11-26).
// 쉬는 턴은 없다. 작은 실수는 묻지 않고 고쳐서 잇는 것으로 흐름을 지킨다.
// ====================================================================

const String kMeaningCheckTag = '[MEANING_CHECK]';
const String kMeaningConfirmTag = '[MEANING_CONFIRM]';
const String kMeaningSentenceTag = '[SENTENCE]';

/// 고쳐진 유저 줄에 같이 남기는 처음 시도 문장.
const String kFreeTalkAttemptField = 'free_talk_attempt';

/// 한 문장을 두고 되묻기를 이만큼 했으면 더 묻지 않고 대화를 잇는다.
const int kMeaningCheckMaxRounds = 3;

/// 이 턴에 되묻기 규칙을 프롬프트에 넣어도 되는가. Free Talk이면 언제나다.
/// 단 이미 확인 중이거나 확인된 문장을 처리하는 턴은 다시 묻지 않는다.
bool meaningCheckAllowed({
  required bool freeTalk,
  bool alreadyConfirmed = false,
}) =>
    freeTalk && !alreadyConfirmed;

/// Free Talk 매 턴에 붙는 규칙. 작은 실수는 멈추지 않고 고쳐서 잇는다.
String buildFreeTalkLearnerFixPolicy({required String spokenLang}) {
  return '''[FREE TALK — THE USER IS A LEARNER OF $spokenLang]
The user is practicing $spokenLang, which is not their own language. Learner
mistakes are normal. Never stop the conversation over a small mistake.
When the meaning is clear but the line has small learner mistakes (grammar, a
wrong ending, an unnatural word), use the USER_FIX format to show the natural
$spokenLang sentence and keep talking. For this learner, USER_FIX may also fix
these learner mistakes, not only misrecognized words — but keep the user's own
words, meaning and sentence shape; change only what is wrong. If the line is
already natural, use no tags.''';
}

/// 서클 멤버 시스템 프롬프트에 붙는 ① 되묻기 규칙. 허용된 턴에만 붙인다.
String buildMeaningCheckPolicy({required String spokenLang}) {
  return '''[MEANING_CHECK — WHEN THE LEARNER'S MEANING IS NOT CLEAR]
Use MEANING_CHECK only when a fellow member who speaks $spokenLang would genuinely
not know what the user means: a wrong word that changes the meaning, grammar or
word order so broken that two readings are possible, or a line that makes no
sense in this conversation. If one reading is clearly most likely, use USER_FIX
instead and keep talking. When the words are understandable but the meaning is
unclear because of learner mistakes, use MEANING_CHECK, not the ask-back
confirmation. Keep the ask-back confirmation for a garbled transcript
(non-words, a sentence cut off mid-way).

In that case do NOT reply to the content. Output exactly:
$kMeaningCheckTag
<a very short, very easy question in $spokenLang>

The question connects to what the user was saying, offers the one or two
meanings you think they might have meant ("Do you mean ...? Or ...?"), and asks
them to say it again. Use the simplest words and short sentences a beginner
understands. Never combine $kMeaningCheckTag with any other control format.''';
}

/// ② 유저가 되묻기에 대답한 턴에 붙는다. 뜻을 잡아 한 번 더 확인하게 한다.
String buildMeaningClarifyNote({
  required String spokenLang,
  required String chatLang,
  required String attempt,
}) {
  final safe = attempt.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  return '''[MEANING CLARIFICATION — THIS TURN ONLY]
Earlier the user tried to say: "$safe". You did not understand it and asked
what they meant. Their latest line is their answer. It may be in $spokenLang,
in $chatLang, or a mix — understand it either way, together with the earlier
attempt and the conversation.
Do NOT reply to the content yet. Output exactly:
$kMeaningConfirmTag
<a very short, very easy $spokenLang question: "So you want to say this?">
$kMeaningSentenceTag
<what the user wanted to say, as one natural $spokenLang sentence>
The sentence keeps the user's own words wherever possible and fits this
conversation. If you still cannot tell what they mean, output the
$kMeaningCheckTag format instead with an even simpler question.''';
}

/// ③ 확인이 끝난 직후 턴에 붙는다. 그 문장 전체를 이어 받아 대화를 잇는다.
String buildMeaningResolvedNote({
  required String spokenLang,
  required String sentence,
}) {
  final safe = sentence.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  return '''[MEANING CONFIRMED]
The user just confirmed what they meant: "$safe".
The checking is over. Go back to the conversation's normal level: speak the
$spokenLang that fits this user and this conversation, not the extra-easy words
used while checking. Take in their whole sentence naturally, the way a member
would echo it back in passing, then continue with one short line. Do not
correct or explain anything, and do not use any control format.''';
}

/// ① 되묻기. [question]은 말과 글자로 같이 나간다.
class MeaningCheck {
  const MeaningCheck({required this.question});
  final String question;
}

/// ② 확인. [sentence]가 확인되면 유저 줄이 된다.
class MeaningConfirm {
  const MeaningConfirm({required this.question, required this.sentence});
  final String question;
  final String sentence;
}

String _stripQuotes(String s) =>
    s.trim().replaceAll(RegExp(r'^["“”「」\s]+|["“”「」\s]+$'), '');

String _oneLine(String s) => s.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ').trim();

bool _startsWithTag(String output, String tag) =>
    output.trimLeft().toUpperCase().startsWith(tag);

/// 답변 전체가 `[MEANING_CHECK]` 형식이면 질문을 꺼낸다. 아니면 null.
MeaningCheck? parseMeaningCheck(String output) {
  if (!_startsWithTag(output, kMeaningCheckTag)) return null;
  final question =
      _oneLine(output.trimLeft().substring(kMeaningCheckTag.length));
  if (question.isEmpty) return null;
  return MeaningCheck(question: question);
}

/// 답변 전체가 `[MEANING_CONFIRM] … [SENTENCE] …` 형식이면 갈라낸다.
MeaningConfirm? parseMeaningConfirm(String output) {
  final match = RegExp(
    r'^\s*\[MEANING_CONFIRM\]\s*([\s\S]*?)\s*\[SENTENCE\]\s*([\s\S]+)$',
    caseSensitive: false,
  ).firstMatch(output);
  if (match == null) return null;
  final question = _oneLine(match.group(1) ?? '');
  final sentence = _stripQuotes(_oneLine(match.group(2) ?? ''));
  if (question.isEmpty || sentence.isEmpty) return null;
  return MeaningConfirm(question: question, sentence: sentence);
}

/// 제어 형식으로 시작했는가. 형식이 깨져도 태그를 읽어 주면 안 된다.
bool looksLikeMeaningControl(String output) =>
    _startsWithTag(output, kMeaningCheckTag) ||
    _startsWithTag(output, kMeaningConfirmTag);

// ── ② 확인 질문에 대한 대답 ─────────────────────────────────────────

enum MeaningConfirmReply { yes, no, other }

String _compact(String s) =>
    s.toLowerCase().replaceAll(RegExp(r"[\s\p{P}\p{S}]", unicode: true), '');

List<String> _tokens(String s) => s
    .toLowerCase()
    .split(RegExp(r"[\s\p{P}\p{S}]+", unicode: true))
    .where((t) => t.isNotEmpty)
    .toList();

// 띄어쓰기 없는 언어용: 대답 전체가 이것이면 그 뜻이다.
const Set<String> _yesCompact = {
  '네', '예', '응', '어', '맞아', '맞아요', '맞습니다', '네맞아요', '그래', '그래요',
  '네그래요', '맞아맞아', '그거요', '그거예요', '네그거요',
  'はい', 'うん', 'そう', 'そうです', 'はいそうです',
  '是', '是的', '对', '对的', '对对', '嗯', '没错',
  'हाँ', 'हां', 'जी', 'जीहाँ',
};
const Set<String> _noCompact = {
  '아니', '아니요', '아뇨', '아닙니다', '아니에요', '틀려', '틀렸어', '틀렸어요',
  'いいえ', 'いや', '違う', '違います', 'ちがう',
  '不是', '不对', '不', '错了',
  'नहीं', 'नही',
};
// 띄어쓰기 있는 언어용: 짧은 대답 안의 낱말로 본다.
const Set<String> _yesTokens = {
  'yes', 'yeah', 'yep', 'yup', 'right', 'correct', 'exactly', 'ok', 'okay',
  'sure', 'sí', 'si', 'oui', 'ja', 'genau', 'да', 'sim', 'certo', 'esatto',
  'klopt', 'vâng', 'đúng', 'ya', 'iya', 'betul',
};
const Set<String> _noTokens = {
  'no', 'nope', 'nah', 'wrong', 'non', 'nein', 'нет', 'não', 'nao', 'nee',
  'không', 'tidak', 'bukan',
};

/// 확인 질문("이 말을 하려던 거예요?")에 대한 대답이 무엇인가.
///
/// 짧은 긍정·부정만 yes/no로 본다. 그 밖의 말은 새 설명([MeaningConfirmReply.other])
/// 이라 한 번 더 뜻을 잡는다.
MeaningConfirmReply classifyMeaningConfirmReply(String reply) {
  final compact = _compact(reply);
  if (compact.isEmpty) return MeaningConfirmReply.other;
  if (_yesCompact.contains(compact)) return MeaningConfirmReply.yes;
  if (_noCompact.contains(compact)) return MeaningConfirmReply.no;
  final tokens = _tokens(reply);
  if (tokens.length > 4) return MeaningConfirmReply.other;
  final saysYes = tokens.any(_yesTokens.contains);
  final saysNo = tokens.any(_noTokens.contains);
  if (saysYes && !saysNo) return MeaningConfirmReply.yes;
  if (saysNo && !saysYes && tokens.length <= 2) return MeaningConfirmReply.no;
  return MeaningConfirmReply.other;
}

/// 저장 줄에 얹는 필드. 처음 시도한 배울 언어 문장을 남긴다.
Map<String, dynamic> meaningCheckFields({required String attempt}) =>
    <String, dynamic>{kFreeTalkAttemptField: attempt.trim()};
