// ====================================================================
// 🧭 [MEANING-CHECK] Free Talk에서 뜻이 안 통하는 배울 언어 문장을 되묻는다.
// --------------------------------------------------------------------
// Free Talk 유저는 배우는 언어로 말한다(실장님, 2026-11-26).
//
//   - **작은 실수도 모두 교정 과정을 거친다**(실장님, 2026-11-26).
//     뜻이 하나로 분명하면 바로 ② 확인으로, 뜻이 갈리면 ① 되묻기부터.
//     조용히 고쳐 넘어가는 [USER_FIX]는 받아쓰기 오류에만 쓴다.
//   - 질문은 모두 **배울 언어로 쉽게**, 말과 글자로 같이 나온다.
//
//   ① 되묻기  "이런 말이에요, 저런 말이에요? 다시 말해 주세요."
//        [MEANING_CHECK]
//        <쉬운 배울 언어 질문>
//   ② 유저 대답(배울 언어든 대화언어든) → AI가 뜻을 잡아 한 번 더 확인
//        [MEANING_CONFIRM]
//        <"그럼 이 말을 하려던 거예요?" — 쉬운 배울 언어>
//        [SENTENCE]
//        <유저가 하려던 말 — 자연스러운 배울 언어 문장>
//   ③ 유저가 그 문장을 **직접 따라 말하면**(실장님, 2026-11-26) 처음 유저 줄을
//      그 문장으로 고치고, 질문 말풍선은 증발하고, AI가 그 문장을 이어 받아
//      대화를 계속한다. "네"만 하면 직접 말해 보라고 한 번 더 권한다.
//      "그게 아니라…" 하고 다시 설명하면 새 문장으로 다시 제안한다.
//
// 쉬운 말은 교정하는 동안(①②)만 쓴다. 확인이 끝나면 대화는 유저 수준에
// 맞춘 평소 말로 돌아간다.
//
// 처음 한 말은 [kFreeTalkAttemptField]로 같이 남긴다.
// 추가 호출은 없다 — 서클 멤버 답변 호출 하나가 답변 대신 이 형식을 낸다.
// 첫 턴이든 몇 번째 턴이든 실수가 있으면 매번 교정 과정을 거친다. 쉬는 턴은 없다.
// ====================================================================

import '/custom_code/services/user_line_fix.dart';

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

/// Free Talk 매 턴에 붙는 강사 원칙(2026-11-27, PC 실험 4차 P5 기준).
///
/// 아이에게 말을 걸듯 풍성하게 말하고 끼어들 고리를 걸며, 유저가 말할수록
/// 물러난다. 유저가 이미 가진 쉬운 영어로 말하게 돕고, 교정은 유저 단어를
/// 살린 가장 쉬운 문장으로 한다. 세부 규칙을 늘리지 않는다 — 턴 상황은
/// [buildFreeTalkTurnNote]가 그 턴에만 한 줄씩 준다.
String buildFreeTalkLearnerFixPolicy({required String spokenLang}) {
  return '''[FREE TALK — YOU ARE ALSO THE USER'S CONVERSATION COACH]
The user is practicing $spokenLang, which is not their own language. While you
stay yourself in this circle, you are also the world's best conversation coach.
You teach the way caring adults teach a child to talk: plenty of warm, natural
talk from you, full of easy chances for the user to jump in — and you step back
as they start talking. The goal is that they lead and you follow.

Your core belief: the user can already say almost anything with the simple
$spokenLang they have. Learners often break down because they try to translate
a complex thought from their own language word for word. Show them they don't
need new structures — just short pieces of what they already know.
- Share a little of your own life and opinions. Use natural starters ("You know
  what...", "So the thing is...") only where they truly fit.
- End with ONE easy way in, and vary it: start a sentence about THEIR life for
  them to finish, or ask about their own experience. Don't offer two options
  turn after turn, and don't reuse the same sentence start.
- When they say something, react warmly and echo it back, keeping their own
  words and level.
- The way to speak: short simple sentences first, linked into a chain of
  thought with easy connectors (and, but, so, because, then). Longer sentences
  come by themselves once the chain flows. Model this in your own speech.
- When they get tangled in a long sentence, help them split it: "Say it in
  short pieces — who? what happened? then what?"
- When they say two short sentences that belong together, show once how a
  simple connector joins them ("I was tired, so I went home.").
- When they don't know a word, praise any way of saying it around it with
  simple words.
- Corrections: do not stop the talk or ask them to repeat. Say the corrected
  version once, naturally, inside your own reply ("Oh, you went to Busan last
  week!") — keep their words, fix only the one thing that matters, the simplest
  correct version, never a fancier native rewrite. Only correct real errors
  (a wrong tense or form, a missing or wrong word). If a native speaker could
  say it that way, it is fine — never swap it for a "more natural" version.
- If they say "skip", push back, or want to just talk, drop the correction
  immediately and continue the conversation.
- If they speak their own language, accept it, give the simplest $spokenLang
  for it, and invite them to try.
- The more they say, the less you say.
Never fix a learner mistake silently with USER_FIX. Keep USER_FIX only for a
word the speech recognizer clearly misheard.''';
}

/// 서클 멤버 시스템 프롬프트에 붙는 교정 형식. 교정이 허용된 턴에만 붙인다.
/// 형식은 고를 수 있을 뿐 강제가 아니다 — 대부분의 턴은 평소 답변이다.
String buildMeaningCheckPolicy({required String spokenLang}) {
  // 교정 방식·HEARD_CONFIRM 구분·"섞지 마라"는 코치 원칙과 제어 형식 목록에
  //   이미 있어 뺐다(2026-11-27 프롬프트 줄이기). 이 블록은 Free Talk에서만 붙는다.
  // 🪶 [FREE-TALK-EASY-WAY] 뜻이 안 잡히면 "이 뜻이에요?" 퀴즈 대신, 유저
  //   단어로 쉽게 말하는 예를 한두 개 보여 주고 다시 해 보게 한다(실장님,
  //   2026-11-28). 생각을 너무 정확히 하려다 막힌 사람이 쉬운 말로 풀어 가는
  //   연습. 판단은 AI에게 맡긴다 — 낱말 수 같은 기준을 두지 않는다.
  // 🧩 [FREE-TALK-BUILD] 머뭇거리면 대신 완성하지 않고, 빠진 칸 하나를 물어
  //   유저 조각으로 문장을 함께 조립한다(실장님, 2026-11-28). 끌어내기가
  //   대신 말해 주기보다 말하는 힘으로 남는다. 두 번 물어도 안 되면 그때
  //   쉬운 예를 보여 준다. 판단은 AI에게 — 낱말 수 기준을 두지 않는다.
  return '''• Hesitating or unclear — the user gave only pieces of a thought: it trails
off unfinished ("...and...", "...but..."), or you cannot tell what they want
to say. Do NOT finish the thought for them and do NOT fix it with
$kUserFixTag — that would put words in their mouth. Help them build the
sentence themselves. Output exactly:
$kMeaningCheckTag
<your short, warm $spokenLang question>
The question: start by echoing their own words ("Your exam date —"), then ask
about ONE missing piece only — first what they want to do, then when or
where, then why; skip anything the conversation already makes clear. They
must be able to answer in two to four words, so their answer plus their
earlier words make one sentence. Match their LEVEL: level 1 an either/or
choice ("change it, or check it?"), level 2 a short what/when/why question,
level 3 an open question. Ask it the way your character naturally would —
not like a teacher. One question, no examples, no explanation.
A line whose meaning you can tell, even in broken order, is NOT this case —
fix it with $kUserFixTag.''';
}

/// ② 유저가 되묻기에 대답한 턴에 붙는다. 뜻을 잡아 **바로 고쳐 잇는다**.
///
/// 🩹 [FREE-TALK-LINE-FIX] 예전에는 여기서 "이 말이에요? 직접 말해 보세요"
/// ([kMeaningConfirmTag])로 따라 말하기를 시켰다. 이제는 하려던 말을 바른
/// 문장으로 유저 줄에 넣고([kUserFixTag]) 곧바로 대화를 잇는다 — 서툰 말도
/// 1차로 고쳐져 화면·공부방에 남고 대화는 끊기지 않는다(실장님, 2026-11-27).
String buildMeaningClarifyNote({
  required String spokenLang,
  required String chatLang,
  required String attempt,
}) {
  final safe = attempt.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  return '''[BUILDING THE SENTENCE — THIS TURN ONLY]
Earlier the user tried to say: "$safe". You asked them about a missing piece.
Their latest line is their answer. It may be in $spokenLang, in $chatLang, or
a mix — understand it either way, together with the earlier attempt and the
conversation.
Join their answer ONLY with that earlier attempt — never with an older topic
from the conversation. If their answer is still vague ("I don't know", a
single unsure word), they have not finished: do not guess.
If you can now tell what they want to say, output exactly:
$kUserFixTag
<their earlier pieces and this answer joined into one correct, natural
$spokenLang sentence>
$kUserFixReplyTag
<your normal reply to that sentence>
The sentence is built from the user's own words (earlier and now), adds no
idea they did not say, and is the simplest correct version. Do not ask them
to repeat it.
If one important piece is still missing and you have asked only once, output
the $kMeaningCheckTag format again with one more easy question about that
piece. If you already asked twice, output $kMeaningCheckTag with one or two
very easy example sentences that use their words ("You can say: ..."), and
invite them to try.''';
}

/// 유저 말 바로 앞(맨 마지막)에 한 번 더 두는 교정 규칙. 긴 시스템 지시 속에
/// 묻히면 모델이 형식을 놓친다(실기기, 2026-11-26) — 마지막 지시라야 이긴다.
String? buildMeaningFinalNote({
  required String spokenLang,
  required bool clarifying,
  required bool allowCheck,
}) {
  if (clarifying) {
    return '''FINAL RULE FOR THIS TURN: the user is answering your question about their
unfinished line. Join their answer only with that unfinished line (not an older
topic). If together they make a clear thought, start with $kUserFixTag and that
one correct, natural $spokenLang sentence, then $kUserFixReplyTag and your normal
reply. If the answer is still vague ("I don't know", one unsure word), do not
guess: output $kMeaningCheckTag with one more easy question about the same thing
(after two questions: one or two easy example sentences instead).''';
  }
  // 🩹 [FREE-TALK-LINE-FIX] 틀린 줄은 대답 앞에 [USER_FIX]로 고쳐 낸다.
  //   예전처럼 대답 속에서 고쳐 말하지 않는다 — 고친 줄이 화면에 나온다.
  const fixRule = '''FINAL RULE FOR THIS TURN: if the user's line has a mistake or is a broken
fragment and you can tell what they meant, start with $kUserFixTag and their line
corrected (their own words, only what is wrong fixed — nothing added), then
$kUserFixReplyTag and your reply. Do not repeat the correction in the reply.''';
  if (allowCheck) {
    return '''$fixRule
If their line trails off unfinished or you cannot tell what they want to say,
do not finish it for them: output $kMeaningCheckTag with one easy question
about the one missing piece, using their words.''';
  }
  return fixRule;
}

/// 🩹 [FREE-TALK-LINE-FIX] 고친 유저 줄이 **고친 것인지 다시 쓴 것인지** 본다.
///
/// 받아쓰기 복원용 [userLineFixIsPlausible](길이 0.5~2배)은 "busy this week" →
/// "I'm busy this week."처럼 조각을 문장으로 세우는 것도 막는다. 여기서는 길이
/// 대신 **유저 낱말이 남았는지**를 본다 — 유저 낱말의 절반 이상이 고친 줄에
/// 있어야 하고, 낱말 수는 유저 말의 두 배·+5 중 큰 쪽을 넘지 않는다.
bool learnerLineFixIsPlausible({
  required String original,
  required String fixed,
}) {
  final a = original.trim();
  final b = fixed.trim();
  if (a.isEmpty || b.isEmpty || a == b) return false;
  final orig = _tokens(a);
  final fix = _tokens(b);
  if (orig.isEmpty || fix.isEmpty) return false;
  // 짧은 조각("yesterday meeting, investor")은 주어·동사·관사를 채워야
  //   문장이 된다 — 3낱말 → "I had a meeting with an investor yesterday."(8).
  final maxWords = orig.length * 2 > orig.length + 5
      ? orig.length * 2
      : orig.length + 5;
  if (fix.length > maxWords) return false;
  final fixSet = fix.toSet();
  final kept = orig.where(fixSet.contains).length;
  return kept * 2 >= orig.length;
}

// ── 턴별 한 줄 지시(코드가 상황을 보고 그 턴에만) ────────────────────────

/// AI 줄 끝에서 유저에게 끝맺게 남긴 문장 앞부분("You felt…")을 꺼낸다.
List<String> usedSentenceStarts(List<String> aiLines) {
  final out = <String>[];
  for (final line in aiLines) {
    final m = RegExp(r'([^.!?“”"]{3,60})(?:…|\.\.\.)\s*["”]?\s*$')
        .firstMatch(line.trim());
    if (m != null) out.add(m.group(1)!.trim());
  }
  return out.length > 4 ? out.sublist(out.length - 4) : out;
}

/// 🪶 [FREE-TALK-EASY-WAY] 몇 마디만 하고 막힌 말도 뜻이 안 잡히면 쉬운 예를
/// 보여 준다. 예전 4낱말 기준은 "직접 말해 보세요" 반복 때문이었는데, 이제
/// 대답 턴은 바로 고쳐 잇는다. 뜻이 잡히는지는 AI가 판단한다(실장님, 2026-11-28).
bool meaningCheckWorthIt(String userLine) => userLine.trim().isNotEmpty;

/// 교정(직접 말하게 하는 단계)은 이 턴 수에 한 번까지. 뜻이 막히면 되묻기는 된다.
const int kFreeTalkCorrectionEveryTurns = 2;

int _wordCount(String s) =>
    RegExp(r"[A-Za-zÀ-ɏ']+").allMatches(s).length;

/// 유저 발화 길이에 따른 말 양, 막혔을 때의 도움, 유저가 이미 쓰는 문장 시작.
/// [userLines]는 이번 줄까지 포함한 Free Talk 유저 줄(오래된 것부터).
String buildFreeTalkTurnNote({
  required List<String> userLines,
  required String spokenLang,
  // 최근 AI 줄. 유저에게 준 문장 앞부분("You felt…")을 다시 쓰지 않게 한다.
  List<String> aiLines = const <String>[],
  // 유저가 이 방에서 교정을 그만하라고 했다.
  bool noCorrection = false,
  // 🪜 [FREE-TALK-LEVEL] [userLines]와 같은 순서로, 그 줄을 AI가 고쳐야 했는지.
  List<bool> fixedLines = const <bool>[],
}) {
  if (userLines.isEmpty) return '';
  final last = userLines.last;
  final n = _wordCount(last);
  final level = freeTalkLearnerLevel(userLines, fixedLines: fixedLines);
  // 🪜 말 양도 수준을 따른다(실장님, 2026-11-27). 예전에는 짧게 말하면
  //   "3~4문장으로 풍성하게"를 붙여, 단어 세 개에 네 문장으로 답했다 —
  //   1단계 유저에게 맞춘 답이 아니었다. 유저가 아주 길게 말하면(15낱말+)
  //   그때만 반응을 짧게 줄여 유저가 이끌게 한다.
  final notes = <String>[
    _kFreeTalkLevelNotes[level - 1],
    if (noCorrection)
      // 🩹 줄 고치기([USER_FIX])는 말로 하는 교정이 아니라 화면·공부방용이라 남긴다.
      'The user asked you to stop correcting them. Never talk about their mistakes in your reply for the rest of this conversation — just talk. Fixing their line with $kUserFixTag is silent and still fine.',
    if (level == 3 && n >= 15)
      'THIS TURN: a short reaction plus one short question. The user is leading — follow them.'
    else
      _kFreeTalkLevelAmount[level - 1],
  ];
  // 🪶 [FREE-TALK-EASY-WAY] 몇 마디에 막힌 경우는 낱말 수로 정하지 않는다 —
  //   뜻이 잡히면 [USER_FIX], 안 잡히면 AI가 쉬운 예를 보여 준다(되묻기 규칙).
  final keywordStyle = '...'.allMatches(last).length +
          '…'.allMatches(last).length >=
      3;
  if (keywordStyle) {
    notes.add(
        'The user is speaking in keywords. Fix their line into one simple sentence from their own words with $kUserFixTag, then keep the talk going.');
  }
  // 🪜 쉬운 틀에 익숙해져 길게 말하면 한 단계 위로(실장님, 2026-11-27).
  //   쉬운 틀에 머물면 그 수준에서 굳는다.
  final bool confident = level == 3 &&
      userLines.length >= 3 &&
      userLines.sublist(userLines.length - 3).every((u) => _wordCount(u) >= 15);
  if (confident && !noCorrection) {
    notes.add(
        'The user is now speaking with confidence. Stretch them a little: after taking in what they said, offer ONE slightly more advanced way to say a part of it ("Another way to say that is ...") and invite them to use it, and ask deeper questions (why, what if, their opinion).');
  }
  final starts = <String>[];
  for (final u in userLines) {
    for (final m in RegExp(r"\b((?:I|It|We|He|She|They|My \w+) [a-z']+)\b")
        .allMatches(u)) {
      final p = m.group(1)!;
      if (!starts.contains(p)) starts.add(p);
    }
  }
  if (starts.isNotEmpty) {
    final recent = starts.length > 8 ? starts.sublist(starts.length - 8) : starts;
    notes.add(
        'Sentence starts the user already uses: ${recent.join(', ')}. When they get stuck, point them to one of these instead of a new structure.');
  }
  return notes.join('\n');
}

// ── 🪜 [FREE-TALK-LEVEL] 유저 수준 3단계 ───────────────────────────────
//
// 유저가 **실제로 한 말**(고치기 전 원문)의 **문장 구성**으로 AI 답의 구조와
// 양을 맞춘다(실장님, 2026-11-27). 길이가 아니라 구성이다 — 길게 늘어놓은
// 단어 나열은 1단계이고, 짧아도 절을 바르게 쓰면 3단계 쪽이다.
//   줄마다:  1 주어 없는 단어 나열   2 주어·동사가 있는 단문(and·but·so로 이음)
//            3 because·when·if 같은 절을 쓴 문장(AI가 고쳐야 했으면 2로 본다)
//   유저 수준 = 최근 3줄 평균(1.6 미만 1, 2.5 이상 3, 그 사이 2).
// 처음 말하기 전에는 1단계로 시작한다.

const List<String> _kFreeTalkLevelNotes = <String>[
  'LEVEL 1 — the user is not yet building sentences (single words or fragments). Use only very short, simple sentences: one idea each, about 4 to 7 words, present or simple past, everyday words. No linking words and no clauses. Your question is a very easy one they can answer in a few words.',
  'LEVEL 2 — the user makes simple sentences. Use simple sentences, linked with easy connectors (and, but, so) where it helps, and everyday words. No clauses with if, when, or which. Ask one open question (what, where, how).',
  'LEVEL 3 — the user builds sentences with clauses. Use natural conversational language: clauses with because, when, if, that, or which are fine, plus a few less common words, still clear. Ask why, what-if, or opinion questions.',
];

/// 수준별 말 양. 1단계 유저에게 긴 답은 따라올 수 없는 양이다.
const List<String> _kFreeTalkLevelAmount = <String>[
  'THIS TURN: at most 2 very short sentences, then one easy question. Keep it short.',
  'THIS TURN: 2 sentences plus one question.',
  'THIS TURN: 2 to 3 natural sentences plus one question.',
];

final RegExp _clauseWord = RegExp(
    r"\b(because|when|if|that|which|who|while|although|though|since|before|after|until)\b",
    caseSensitive: false);

/// 주어가 있는가(문장으로 세웠는가). 주어 없는 단어 나열은 1단계다.
final RegExp _subjectWord = RegExp(
    r"\b(i|i'm|i've|i'll|i'd|you|he|she|we|they|it|it's|there|this|that|my|our|his|her|their)\b",
    caseSensitive: false);

/// 원문 한 줄의 구성 단계 1~3.
int freeTalkLineLevel(String line, {bool fixed = false}) {
  final words = _wordCount(line);
  if (!_subjectWord.hasMatch(line) || words < 3) return 1;
  if (_clauseWord.hasMatch(line) && words >= 7) return fixed ? 2 : 3;
  return 2;
}

/// 최근 3줄(원문)의 구성으로 본 유저 수준 1~3. [fixedLines]는 [userLines]와
/// 같은 순서로 그 줄을 AI가 고쳐야 했는지다.
int freeTalkLearnerLevel(List<String> userLines,
    {List<bool> fixedLines = const <bool>[]}) {
  if (userLines.isEmpty) return 1;
  final start = userLines.length > 3 ? userLines.length - 3 : 0;
  var sum = 0;
  for (var i = start; i < userLines.length; i++) {
    sum += freeTalkLineLevel(userLines[i],
        fixed: i < fixedLines.length && fixedLines[i]);
  }
  final avg = sum / (userLines.length - start);
  if (avg < 1.6) return 1;
  if (avg >= 2.5) return 3;
  return 2;
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

/// 확인 말풍선·음성에 쓰는 한 덩어리: 질문 다음 줄에 고친 문장.
String meaningConfirmLine(MeaningConfirm confirm) =>
    '${confirm.question}\n"${confirm.sentence}"';

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

/// [repeated]: 제안한 문장을 직접 따라 말했다 — 교정 완료.
/// [yes]: "네"만 했다 — 직접 말해 보라고 권한다.
/// [no]: 짧은 부정 — 다시 말해 달라고 한다.
/// [other]: 새 설명 — 뜻을 다시 잡아 새 문장을 제안한다.
/// [skip]: 넘어가자·그만 고치라는 말 — 교정을 바로 끝내고 처음 한 말로 잇는다.
enum MeaningConfirmReply { repeated, yes, no, skip, other }

/// 교정을 그만두자는 말. 이 말을 교정 문장으로 만들면 안 된다(실기기,
/// 2026-11-27: "그냥 넘어가"가 "Let's just move on."으로 제안되고 유저 줄이
/// 그 문장으로 바뀌었다).
final List<RegExp> _skipPatterns = [
  RegExp(r'넘어가|넘어갑|패스|됐어|그만|안\s*고쳐|교정\s*(하지|그만|말)'),
  RegExp(
      r"\b(skip|pass|move on|never ?mind|forget it|just talk|no correction|stop correct|my english is fine|i(?:'?m| am) right)\b",
      caseSensitive: false),
];

/// 짧게 끝날 때만 포기로 본다. "I don't know how to say…"는 포기가 아니다.
final RegExp _shortGiveUp =
    RegExp(r"몰라|모르겠|\bi don'?t know\b", caseSensitive: false);

bool isMeaningSkipReply(String reply) =>
    _skipPatterns.any((p) => p.hasMatch(reply)) ||
    (_shortGiveUp.hasMatch(reply) && _tokens(reply).length <= 5);

/// 따라 말한 것으로 칠 때 쓰지 않는 군말.
const Set<String> _fillers = {'um', 'uh', 'umm', 'uhh', 'er', 'erm', 'so', 'well', 'like'};

/// 낱말 순서를 지킨 일치 비율(제안 문장 기준, 0~1). 군말은 뺀다.
double meaningRepeatScore(String reply, String sentence) {
  final a = _tokens(reply).where((t) => !_fillers.contains(t)).toList();
  final b = _tokens(sentence).where((t) => !_fillers.contains(t)).toList();
  if (a.isEmpty || b.isEmpty) return 0;
  final dp = List.generate(a.length + 1, (_) => List<int>.filled(b.length + 1, 0));
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      dp[i][j] = a[i - 1] == b[j - 1]
          ? dp[i - 1][j - 1] + 1
          : (dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1]);
    }
  }
  return dp[a.length][b.length] / b.length;
}

/// 이만큼 맞으면 직접 따라 말한 것으로 본다. 전사 오차와 작은 빠뜨림은 봐준다.
const double kMeaningRepeatThreshold = 0.7;

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
MeaningConfirmReply classifyMeaningConfirmReply(String reply, {String? sentence}) {
  final compact = _compact(reply);
  if (compact.isEmpty) return MeaningConfirmReply.other;
  if (sentence != null &&
      meaningRepeatScore(reply, sentence) >= kMeaningRepeatThreshold) {
    return MeaningConfirmReply.repeated;
  }
  if (isMeaningSkipReply(reply)) return MeaningConfirmReply.skip;
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

/// "네"만 했을 때 직접 말해 보라고 권하는 한 줄(배울 언어). 모르는 언어는 영어.
String meaningSayItLine(String spokenLang) {
  switch (spokenLang.trim().toLowerCase()) {
    case 'korean':
      return '좋아요. 그럼 직접 한번 말해 보세요.';
    case 'japanese':
      return 'いいですね。では、自分で言ってみてください。';
    case 'chinese':
      return '好的，那你自己说一遍吧。';
    case 'spanish':
      return 'Muy bien. Ahora dilo tú mismo.';
    case 'french':
      return 'Très bien. Maintenant, dites-le vous-même.';
    case 'german':
      return 'Gut. Sag es jetzt selbst.';
    default:
      return 'Great. Now try saying it yourself.';
  }
}

// ── 대답을 기다리는 동안의 받아쓰기 거르기 ────────────────────────────
//
// 대답을 기다리는 동안 받아쓰기를 자동 언어 감지로 둔다(대화언어로 대답해도
// 되게). 그 사이 방 소음이 엉뚱한 언어로 적혀 유저 줄에 붙었다(실기기,
// 2026-11-26: 영어 대답 끝에 "わかこ家庭。"). 두 언어의 글자가 아닌 것이
// 섞인 받아쓰기는 버린다.

enum _Script { latin, hangul, kana, han, cyrillic, devanagari, thai, arabic }

_Script? _scriptOf(int r) {
  if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) || (r >= 0xC0 && r <= 0x24F) ||
      (r >= 0x1E00 && r <= 0x1EFF)) {
    return _Script.latin;
  }
  if ((r >= 0xAC00 && r <= 0xD7AF) || (r >= 0x1100 && r <= 0x11FF) || (r >= 0x3130 && r <= 0x318F)) {
    return _Script.hangul;
  }
  if (r >= 0x3040 && r <= 0x30FF) return _Script.kana;
  if (r >= 0x4E00 && r <= 0x9FFF) return _Script.han;
  if (r >= 0x0400 && r <= 0x04FF) return _Script.cyrillic;
  if (r >= 0x0900 && r <= 0x097F) return _Script.devanagari;
  if (r >= 0x0E00 && r <= 0x0E7F) return _Script.thai;
  if (r >= 0x0600 && r <= 0x06FF) return _Script.arabic;
  return null; // 숫자·문장부호·공백 등은 따지지 않는다.
}

Set<_Script> _scriptsOfLanguage(String lang) {
  switch (lang.trim().toLowerCase()) {
    case 'korean':
      return {_Script.hangul, _Script.latin};
    case 'japanese':
      return {_Script.kana, _Script.han, _Script.latin};
    case 'chinese':
      return {_Script.han, _Script.latin};
    case 'russian':
      return {_Script.cyrillic, _Script.latin};
    case 'hindi':
      return {_Script.devanagari, _Script.latin};
    case 'thai':
      return {_Script.thai, _Script.latin};
    case 'arabic':
      return {_Script.arabic, _Script.latin};
    default:
      return {_Script.latin};
  }
}

/// 받아쓰기가 이 두 언어의 글자로만 이뤄졌는가. 아니면 소음으로 보고 버린다.
bool transcriptFitsLanguages(String text, String langA, String langB) {
  final allowed = {..._scriptsOfLanguage(langA), ..._scriptsOfLanguage(langB)};
  for (final r in text.runes) {
    final s = _scriptOf(r);
    if (s != null && !allowed.contains(s)) return false;
  }
  return true;
}

/// 저장 줄에 얹는 필드. 처음 시도한 배울 언어 문장을 남긴다.
Map<String, dynamic> meaningCheckFields({required String attempt}) =>
    <String, dynamic>{kFreeTalkAttemptField: attempt.trim()};
