// ====================================================================
// 🎨 [AI-STYLE] 로비에서 고른 영어 스타일의 **유일한 정의처**
// --------------------------------------------------------------------
// 로비 AI STYLE(`FFAppState().aiStyle`)은 오래도록 UI에만 떠 있었다.
// 실제로 프롬프트에 닿는 곳은 히스토리의 "다른 표현 보기" 한 군데뿐이라,
// Native를 골라도 대화방이 만들어 내는 영어는 한 글자도 달라지지 않았다.
//
// 이 파일은 그 값을 **영어 생성 프롬프트에 붙일 지시문 한 덩이**로 바꾼다.
// 대화방(Circle Talk / Scenario Talk / Step Expand)과 히스토리가 전부
// 여기만 부른다 — 화면마다 스타일 문장을 따로 적어 두면 Native의 정의가
// 대화방과 히스토리에서 서로 갈라진다.
//
// **위젯이 아니라 services/에 둔 이유**: 대화방 셋과 히스토리가 모두 읽어야
// 하는데, 그중 누구도 다른 위젯 파일을 import하게 만들면 안 된다.
//
// ⚠️ 여기 있는 건 상수와 순수 함수뿐이다. 상태도 네트워크도 없다.
// ====================================================================

import '/app_state.dart';

/// 로비가 보여 주는 스타일 넷. 순서까지 화면과 같다.
const List<String> kAiStyles = <String>[
  'Standard',
  'American',
  'British',
  'Native',
];

/// AI STYLE이 의미를 갖는 유일한 TARGET 언어.
///
/// 영어가 아닌 타겟에 "미국식으로 말해라"를 걸면 그냥 헛소리다. 로비도 같은
/// 이유로 영어일 때만 이 칸을 띄운다.
const String kAiStyleTargetLanguage = 'English';

/// 저장값이 비었거나 알 수 없을 때의 자리.
const String kDefaultAiStyle = 'Standard';

/// 저장값을 넷 중 하나로 접는다. 모르는 값은 [kDefaultAiStyle]이다.
///
/// 예전 빌드가 남긴 값이나 손으로 건드린 prefs가 들어와도 프롬프트에
/// 그대로 실리지 않게 하는 관문이다.
String normalizeAiStyle(String? raw) {
  final value = (raw ?? '').trim();
  for (final style in kAiStyles) {
    if (style.toLowerCase() == value.toLowerCase()) return style;
  }
  return kDefaultAiStyle;
}

/// 지금 이 세션에서 **실제로** 적용되는 스타일.
///
/// TARGET이 영어가 아니면 저장값이 무엇이든 [kDefaultAiStyle]로 접는다.
/// 저장값 자체는 건드리지 않는다 — 영어로 돌아왔을 때 유저가 마지막에 고른
/// 스타일이 그대로 살아 있어야 한다.
String effectiveAiStyle({
  required String targetLang,
  String? style,
}) {
  if (!isAiStyleTargetLanguage(targetLang)) return kDefaultAiStyle;
  return normalizeAiStyle(style ?? FFAppState().aiStyle);
}

/// 이 타겟 언어가 영어인가.
bool isAiStyleTargetLanguage(String targetLang) {
  final value = targetLang.trim().toLowerCase();
  if (value.isEmpty) return false;
  // 'English' 하나만 보지 않는다 — 'english (us)'처럼 꼬리가 붙어 들어오는
  // 호출부가 있다. 언어 코드는 여기서 판단하지 않는다(로비가 이름으로 준다).
  return value == 'english' || value.startsWith('english');
}

/// "다른 표현 보기" 목록에 붙는 한 줄 소개.
///
/// 팝업은 스타일 넷을 한 화면에 늘어놓으므로 여기서는 짧아야 한다. 긴 지시는
/// [aiStyleInstruction]이 따로 붙인다.
String aiStyleBrief(String style) {
  switch (normalizeAiStyle(style)) {
    case 'American':
      return 'the everyday American English a US speaker would actually use — American phrasing and rhythm, not just US spelling';
    case 'British':
      return 'the everyday British English a UK speaker would actually use — British phrasing and rhythm, not just UK spelling';
    case 'Native':
      return 'not a tidier version of the sentence, but the same thought rebuilt the way a US native would really say it in this situation';
    case 'Standard':
    default:
      return 'clear, neutral international English that any English speaker follows easily';
  }
}

/// 스타일 지시문 본문. 언어 조건은 보지 않는다 — [aiStylePromptBlock]이 본다.
///
/// **American과 Native는 반드시 갈라져 있어야 한다.**
/// American은 *같은 말을 미국식으로 말하는 것*이고, Native는 *하려던 생각을
/// 원어민이라면 애초에 어떻게 꺼냈을지 다시 짓는 것*이다. 두 지시문이 비슷해
/// 보이기 시작하면 스타일 넷 중 둘이 죽는다.
String aiStyleInstruction(String style) {
  switch (normalizeAiStyle(style)) {
    case 'American':
      return '''STYLE — American
Write the natural everyday American English a modern US speaker uses in real conversation.
- American vocabulary, phrasing, collocations, and sentence rhythm.
- Use contractions freely. Reach for ordinary phrasal verbs and conversational expressions.
- Keep heavy slang out. Relaxed, not sloppy.
- Prefer how an American actually talks over how a textbook writes.
- Keep the shape of what the speaker said. What changes is the wording and its flavour, not the thought behind it.
This is not just American spelling. The phrasing itself has to sound like an American talking.''';

    case 'British':
      return '''STYLE — British
Write the natural everyday British English a modern UK speaker uses in real conversation.
- British vocabulary and phrasing. Use British spelling where it applies.
- Ordinary British conversational expressions, including the habitual understatement and hedging.
- No stereotyped or stiffly formal "posh" British clichés.
- Keep the shape of what the speaker said. What changes is the wording and its flavour, not the thought behind it.
This is not just British spelling. The phrasing itself has to sound like a British person talking.''';

    case 'Native':
      return '''STYLE — Native
Do not hand back a more polished or more difficult version of the sentence. Work out the thought first, then say it the way a US native speaker naturally would.
- Start from what the speaker actually means, intends, feels, and is dealing with right now.
- Build the English fresh from that. Do not follow the source's words, word order, or sentence structure, and never map a Korean thought-pattern onto English words.
- Keep every one of these: the core meaning, the speaker's intent, the situation, the feeling and attitude, and the facts that matter.
- You may reorder the information, merge or split sentences, add natural connective phrasing, move to a viewpoint that is more natural in English, and let implicit meaning surface.
- Never invent a fact or a feeling the speaker did not express.
- Native does not mean hard words, slang, or piled-up idioms. It means the easy spoken English that comes out of a native speaker's mouth.
The test is not "is this a good translation?" but "would a US native actually say this, in this situation?"''';

    case 'Standard':
    default:
      return '''STYLE — Standard
Write clear, natural, neutral international English.
- Grammatically accurate and easy to follow.
- Do not lean on distinctly American or British vocabulary, idioms, or spelling.
- Keep slang and strong regional expressions out.
- Natural conversational English that an English learner can follow.
- Preserve the speaker's meaning and intent faithfully.''';
  }
}

/// 🇺🇸 [NATIVE-ENGLISH] P3 두 번째 문장을 만드는 지시문.
///
/// 예전 이름은 **Polished**였고, 하는 일도 달랐다 — 원문을 조금 더 매끄럽게
/// 다듬는 것이었다. 그러면 P2 마지막 칸(Final Sentence)과 차이가 거의 없다.
/// 같은 정보 배열에 단어만 조금 나은 문장이 하나 더 생길 뿐이라, 유저는
/// "단어가 이렇게 바뀌었구나"까지만 배우고 끝났다.
///
/// 그래서 이름과 함께 일을 바꿨다. StealthVox에서 Native의 정의는 하나다 —
/// **영어처럼 번역하는 것이 아니라, 영어로 다시 생각해서 표현하는 것.**
/// 로비 AI STYLE의 `STYLE — Native`와 같은 철학이라, 그 지시문을 그대로
/// 안에 박아 쓴다. 두 곳에 따로 적히기 시작하면 앱 안에서 Native가 서로 다른
/// 두 가지 뜻을 갖게 된다.
///
/// ⚠️ **로비 스타일 블록([aiStylePromptBlock])을 붙이지 않는다.** 유저가
/// British를 골랐다고 "Native English" 카드가 영국식이 되면 카드 이름이
/// 거짓말이 된다. 로비 스타일을 받는 자리는 Final Sentence 쪽이다.
///
/// [partnerLabel]은 대화 상대의 이름이다. 비어 있지 않으면 그 이름을 AI나
/// assistant로 바꿔치기하지 말라고 못 박는다.
String buildNativeEnglishSentenceInstructions({String partnerLabel = ''}) {
  final label = partnerLabel.trim();
  final partnerRule = label.isEmpty
      ? ''
      : '\n- Do not replace $label with AI, assistant, chatbot, or bot.';
  return '''You are rebuilding ONE finished thought as English.

What you are given is a sentence the user built step by step and then carried into
English. The meaning is theirs and the facts are theirs, but the information is still
arranged the way they originally thought it.

Your job is NOT to translate it, and NOT to polish it. Write what a US native speaker
would say if this thought had been theirs from the start — thought out in English,
not carried over into English.

${aiStyleInstruction('Native')}

[HOW A NATIVE ORGANISES IT]
- Lead with where they actually stand, then put what sits behind it.
- Let the tension land as a real turn: what they want against what holds them back.
- Close on their own reading of it — what they make of it — when the material
  already supports one. Never manufacture a conclusion to close on.
- Reorder, merge, or split as needed. The sentence count may change.

[HARD LIMITS]
- Use only the meaning, facts, feelings, and stance already in what you are given.
- Never add a fact, reason, feeling, or conclusion the user did not express.
- Never drop something they did express, and never flip or soften their position.
- Everyday spoken English. No SAT words, no written prose, no piled-up idioms.
- Render every participant name, role label, and situation in English (translate role
  or description phrases; romanize real personal names).
- The result must be 100% English and must NOT contain any Hangul characters.$partnerRule

[OUTPUT]
- One to three short spoken sentences. It has to be sayable out loud in one go.
- No explanation, no quotes, no labels. Just the sentences.''';
}

/// 스타일이 문장의 어디까지 닿는가.
///
/// **Native 하나 때문에 필요해진 구분이다.** Native는 "생각을 영어로 다시
/// 짜라"고 적혀 있어서, 아무 데나 붙이면 정보 순서와 문장 수까지 갈아엎는다.
/// 그건 P3 Native English 카드가 할 일이고, 거기서만 해야 두 카드의 차이가
/// 선명해진다(실장님 지시, 2026-08-25).
enum AiStyleReach {
  /// 어휘·어투·리듬만. **정보 배열·문장 구조·문장 수는 원문 그대로.**
  /// 유저의 생각을 충실히 담아야 하는 문장이 여기다 — P2 사다리와 그 마지막
  /// 칸인 Final Sentence.
  wording,

  /// 생각을 다시 짜도 된다. 로비 Native가 제 일을 하는 자리다.
  rebuild,
}

/// [AiStyleReach.wording]일 때 Native가 대신 쓰는 지시문.
///
/// Native를 통째로 빼 버리면 로비에서 Native를 고른 유저의 Final Sentence만
/// 스타일이 없어진다. 그래서 **어휘 쪽 Native는 살리고 재구성만 막는다.**
const String _kNativeWordingOnlyInstruction = '''STYLE — Native (wording only)
Word it the way a US native speaker would say it out loud.
- Everyday spoken English: contractions, ordinary verbs, natural collocations.
- No SAT words, no bookish phrasing, no piled-up idioms.
- Do NOT rebuild the thought here. The order of the information, the sentence structure, and the number of sentences stay exactly as given.
Rebuilding the thought is a different job that happens somewhere else. Do not do it here.''';

/// 프롬프트 끝에 그대로 이어 붙일 블록. 영어 타겟이 아니면 **빈 문자열**이다.
///
/// 반환값에는 앞쪽 개행 두 개가 들어 있어, 호출부는 `'$prompt${block}'`처럼
/// 조건 없이 이어 붙이면 된다. 빈 문자열일 때는 프롬프트가 예전과 한 글자도
/// 달라지지 않는다 — 이게 비영어 타겟을 안 건드린다는 보장이다.
///
/// [scope]는 이 블록이 무엇을 지배하는지 한 줄로 못 박는다. 대화방 프롬프트는
/// 한국어 줄과 영어 줄을 함께 만드는 곳이 있어서(Step Expand의 PART 1/PART 2)
/// "어느 쪽 영어인가"를 적어 주지 않으면 스타일이 한국어 줄까지 흘러간다.
///
/// [reach]는 **얼마나 깊이** 지배하는지다. 유저 생각의 배열을 지켜야 하는
/// 자리는 [AiStyleReach.wording]으로 부른다. 기본값이 [AiStyleReach.rebuild]인
/// 이유는 하나다 — 이미 붙어 있던 자리들의 동작을 조용히 바꾸지 않기 위해서다.
String aiStylePromptBlock({
  required String targetLang,
  String? style,
  String scope = 'the English you produce',
  AiStyleReach reach = AiStyleReach.rebuild,
}) {
  if (!isAiStyleTargetLanguage(targetLang)) return '';
  final resolved = effectiveAiStyle(targetLang: targetLang, style: style);
  final wordingOnly = reach == AiStyleReach.wording;
  final instruction = wordingOnly && resolved == 'Native'
      ? _kNativeWordingOnlyInstruction
      : aiStyleInstruction(resolved);
  final reachRule = wordingOnly
      ? '\nStyle reaches the WORDING only. Keep the order of the information, the sentence structure, and the number of sentences exactly as the instructions above produce them. Never reorganise the thought.'
      : '';
  return '''


[ENGLISH STYLE — applies to $scope]
$instruction
These style rules decide HOW the English is worded. They never override the instructions above about length, sentence count, output format, output language, or what content is allowed. When a rule above says "exactly one sentence", stay in one sentence and restructure inside it.$reachRule''';
}
