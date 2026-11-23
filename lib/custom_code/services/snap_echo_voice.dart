// ⚡ [SNAP-VOICE] Snap Echoing 소리 설정.
//
//   예전에는 글자를 먼저 LLM으로 "의미 단위"로 쪼개고, 그 단위마다 TTS를 따로
//   불러 무음을 끼워 붙였다. 효과가 없어서 **전부 걷어냈다**(2026-11-22).
//   지금은 글자를 그대로 TTS에 한 번 보낸다.
//     · 현재(2026-11-23)는 모든 언어가 Chirp 3 HD. 쉼은 문장부호·줄 끝 기준
//       ([chirpPauseMarkup]).
//     · Gemini 2.5 Flash TTS는 빌드 옵션으로만 켠다([kSnapGeminiTts]). 낭독 지시
//       (프롬프트)로 원어민처럼 읽게 하는 방식이었으나 실기기에서 반복·지연이 났다.
//   속도는 95%다. Gemini는 숫자 속도 칸이 없어 프롬프트에 말로 적는다.
//   Chirp으로 읽을 때는 앱이 보내는 숫자 속도 0.95가 그대로 적용된다.
//
//   호흡 경계는 여전히 소리의 무음으로 찾는다(`analyzeBreaths`).

/// Snap Echoing 한 덩어리의 크기. 영어 Gemini 프롬프트에서 강세 박자 수로 쓴다.
enum SnapUnitSize { quick, full }

extension SnapUnitSizeLabel on SnapUnitSize {
  /// 화면 이름. 고유명사처럼 쓰므로 번역하지 않는다.
  String get label => this == SnapUnitSize.quick ? 'Quick Snap' : 'Full Beat';
}

/// 배울 언어가 영어인가.
bool snapIsEnglish(String languageName) {
  final name = languageName.trim().toLowerCase();
  return name == 'english' ||
      name.startsWith('english ') ||
      name.startsWith('english(') ||
      name == 'en' ||
      name.startsWith('en-');
}

/// 배울 언어에서 Snap Echoing을 쓸 수 있는가. 한 줄이 한 호흡인 짧은 문장
/// 연습이 어색한 언어는 뺀다(2026-11-23): 베트남어(음절마다 띄어 써서 한 줄이
/// 약 5음절로 너무 짧다). 인도네시아어는 시뮬레이션에서 다른 언어와 비슷해
/// 다시 넣었다. 쉐도잉은 모든 언어에서 쓴다.
/// 더 빼려면 [kSnapEchoingExcludedLanguages]에 이름이나 코드를 더한다.
const Set<String> kSnapEchoingExcludedLanguages = <String>{
  'vietnamese',
  'vi',
  'tiếng việt',
};

bool snapEchoingSupported(String languageName) {
  final name = languageName.trim().toLowerCase();
  if (name.isEmpty) return true;
  final String base = name.split(RegExp(r'[\s(_-]')).first;
  return !kSnapEchoingExcludedLanguages.contains(name) &&
      !kSnapEchoingExcludedLanguages.contains(base);
}

/// 배울 언어가 한국어인가. 한국어는 Gemini를 쓰지 않는다.
bool snapIsKorean(String languageName) {
  final name = languageName.trim().toLowerCase();
  return name == 'korean' ||
      name == 'ko' ||
      name.startsWith('ko-') ||
      name.startsWith('korean ') ||
      name.startsWith('korean(') ||
      languageName.contains('한국');
}

/// ✨ 영어 Snap Echoing 소리를 Gemini TTS로 만들지 여부. 기본은 꺼짐(2026-11-23).
/// 글 전체를 내려받는 데 오래 걸렸고(336자 21초, 544자 41초) 소리도 되풀이돼
/// Chirp 3 HD로 돌아왔다. 호흡 단위는 MY STORY 글의 줄이 정한다. 역할교환만
/// Gemini를 쓴다. 켜려면 빌드에 `--dart-define=SNAP_GEMINI_TTS=true`.
const bool kSnapGeminiTts =
    bool.fromEnvironment('SNAP_GEMINI_TTS', defaultValue: false);

/// Gemini로 만든 소리의 캐시 판 꼬리표. 지시문을 바꾸면 올린다.
const String kSnapGeminiCacheTag = 'gem6';

/// 🎭 역할교환(Practice) 대사를 Gemini 2.5 Flash TTS로 읽는다(2026-11-23).
/// 대사가 짧아 한 줄을 통째로 한 번에 보낸다. 지시문을 바꾸면 꼬리표를 올린다.
const String kRolePlayGeminiCacheTag = 'rp1';

/// 역할교환 낭독 지시. 속도는 정상(100%), 리듬은 살리고 감정은 대사에 맞게.
String rolePlayGeminiStylePrompt({String languageName = 'English'}) {
  final language = languageName.trim().isEmpty ? 'the' : languageName.trim();
  return 'Read this line the way a native $language speaker would say it in a '
      'real conversation, with natural emotion that fits what is being said. '
      'Speak at about 100 percent of normal speed with a lively, natural '
      'rhythm, clear enough for a language learner to follow. Do not add '
      'anything.';
}

/// Gemini에게 주는 낭독 지시(소리에 실린다). Gateway는 800자까지만 받는다.
///
/// 속도는 정상 대화 속도의 95%. 영어는 강세를 박자 삼아, 퀵은 한 호흡에 강세
/// 1개, 풀은 강세 2개로 읽게 한다. 다른 언어는 강세 규칙 대신 그 언어 원어민의
/// 자연스러운 리듬으로 짧은 호흡 단위마다 쉬게 한다.
String snapGeminiStylePrompt(SnapUnitSize size, {String languageName = 'English'}) {
  if (snapIsEnglish(languageName)) {
    // 2026-11-23: 문장이 길어 호흡 단위가 길었다. 길어도 한 호흡(3~6단어)으로
    // 끊어 강세 하나를 박자로 삼고, 단위 사이는 아주 짧게 이어 붙인다.
    // 끝의 "반복하지 말 것"은 첫 줄 되풀이를 막는 장치다.
    final stress = size == SnapUnitSize.quick
        ? 'exactly one important word'
        : 'exactly two important words';
    return 'Read this the way a native English speaker would say it naturally in '
        'conversation, for a learner who will echo it right after you. Speak at '
        'about 100 percent of normal speed. Split the text into short rhythmic '
        'phrases that fit in one breath, about three to six words each, even '
        'when a sentence is long. In each phrase, stress $stress clearly, and '
        'keep the other words light and quick, leaning into the next stress. '
        'Link the phrases smoothly with only a very brief natural pause between '
        'them. Do not slow down, do not exaggerate, and do not add or repeat '
        'anything.';
  }
  final language = languageName.trim().isEmpty ? 'the' : languageName.trim();
  return 'Read this the way a native $language speaker would say it naturally in '
      'conversation, for a learner who will repeat it right after you. Speak at '
      'about 95 percent of normal speed with a lively, natural rhythm and clear '
      'stress on the important words. Read in short natural breath groups, with '
      'a brief pause after each group. Do not slow down, do not exaggerate, and '
      'do not add anything.';
}
