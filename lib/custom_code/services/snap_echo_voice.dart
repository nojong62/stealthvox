// ⚡ [SNAP-VOICE] Snap Echoing 소리 설정.
//
//   예전에는 글자를 먼저 LLM으로 "의미 단위"로 쪼개고, 그 단위마다 TTS를 따로
//   불러 무음을 끼워 붙였다. 효과가 없어서 **전부 걷어냈다**(2026-11-22).
//   지금은 글자를 그대로 TTS에 한 번 보낸다.
//     · 영어 — Gemini 2.5 Flash TTS. 낭독 지시(프롬프트)로 원어민처럼 자연스럽게,
//       강세를 박자 삼아 읽게 한다. 실패하면 Gateway가 Chirp 3 HD로 읽는다.
//     · 그 밖의 언어 — Chirp 3 HD. 쉼은 문장부호·줄 끝 기준([chirpPauseMarkup]).
//   속도는 95%다. Gemini는 숫자 속도 칸이 없어 프롬프트에 말로 적는다.
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

/// ✨ 영어 Snap Echoing 소리를 Gemini TTS로 만든다. Gateway가 실패하거나 꺼져
/// 있으면 Chirp 3 HD가 대신 읽는다. 끄려면 빌드에
/// `--dart-define=SNAP_GEMINI_TTS=false`.
const bool kSnapGeminiTts =
    bool.fromEnvironment('SNAP_GEMINI_TTS', defaultValue: true);

/// Gemini로 만든 소리의 캐시 판 꼬리표. 지시문을 바꾸면 올린다.
const String kSnapGeminiCacheTag = 'gem5';

/// Gemini에게 주는 낭독 지시(소리에 실린다). Gateway는 800자까지만 받는다.
///
/// 속도는 정상 대화 속도의 95%. 퀵은 한 호흡에 강세 1개, 풀은 강세 2개.
String snapGeminiStylePrompt(SnapUnitSize size) {
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
