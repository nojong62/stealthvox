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

/// ✨ Snap Echoing 소리를 Gemini TTS로 만들지 여부. 기본은 꺼짐(2026-11-23).
/// 실기기에서 Gemini가 첫 문장을 되풀이해 336자가 188.7초, 544자가 251.9초로
/// 나왔다(정상 20~40초). 켜려면 빌드에 `--dart-define=SNAP_GEMINI_TTS=true`.
const bool kSnapGeminiTts =
    bool.fromEnvironment('SNAP_GEMINI_TTS', defaultValue: false);

/// Gemini로 만든 소리의 캐시 판 꼬리표. 지시문을 바꾸면 올린다.
const String kSnapGeminiCacheTag = 'gem5';

/// Gemini에게 주는 낭독 지시(소리에 실린다). Gateway는 800자까지만 받는다.
///
/// 속도는 정상 대화 속도의 95%. 영어는 강세를 박자 삼아, 퀵은 한 호흡에 강세
/// 1개, 풀은 강세 2개로 읽게 한다. 다른 언어는 강세 규칙 대신 그 언어 원어민의
/// 자연스러운 리듬으로 짧은 호흡 단위마다 쉬게 한다.
String snapGeminiStylePrompt(SnapUnitSize size, {String languageName = 'English'}) {
  if (snapIsEnglish(languageName)) {
    final beats = size == SnapUnitSize.quick ? 'exactly one' : 'exactly two';
    return 'Read this the way a native English speaker would say it naturally in '
        'conversation, for a learner who will repeat it right after you. Speak at '
        'about 95 percent of normal speed with a lively, natural rhythm. Center '
        'the rhythm on the stressed syllables: each stressed syllable is a beat, '
        'and the unstressed words around it are light and quick, leaning into the '
        'next stress. Read in short breath groups of $beats stressed beat'
        '${size == SnapUnitSize.quick ? '' : 's'}, with a brief natural pause '
        'after each group. Do not slow down, do not exaggerate, and do not add '
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
