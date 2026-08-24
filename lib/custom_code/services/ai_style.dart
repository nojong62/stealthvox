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

/// 프롬프트 끝에 그대로 이어 붙일 블록. 영어 타겟이 아니면 **빈 문자열**이다.
///
/// 반환값에는 앞쪽 개행 두 개가 들어 있어, 호출부는 `'$prompt${block}'`처럼
/// 조건 없이 이어 붙이면 된다. 빈 문자열일 때는 프롬프트가 예전과 한 글자도
/// 달라지지 않는다 — 이게 비영어 타겟을 안 건드린다는 보장이다.
///
/// [scope]는 이 블록이 무엇을 지배하는지 한 줄로 못 박는다. 대화방 프롬프트는
/// 한국어 줄과 영어 줄을 함께 만드는 곳이 있어서(Step Expand의 PART 1/PART 2)
/// "어느 쪽 영어인가"를 적어 주지 않으면 스타일이 한국어 줄까지 흘러간다.
String aiStylePromptBlock({
  required String targetLang,
  String? style,
  String scope = 'the English you produce',
}) {
  if (!isAiStyleTargetLanguage(targetLang)) return '';
  final resolved = effectiveAiStyle(targetLang: targetLang, style: style);
  return '''


[ENGLISH STYLE — applies to $scope]
${aiStyleInstruction(resolved)}
These style rules decide HOW the English is worded. They never override the instructions above about length, sentence count, output format, output language, or what content is allowed. When a rule above says "exactly one sentence", stay in one sentence and restructure inside it.''';
}
