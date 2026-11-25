/// 🗣️ 앱이 Gateway로 보내는 목소리 ID (2026-11-25).
///
/// 이름은 **성별만** 뜻한다. 실제 목소리는 Gateway가 고른다
/// (`firebase/functions/secure_ai_gateway.js`):
///   - Gemini TTS: 여 Zephyr / 남 Charon
///   - Chirp 3 HD: 여 Leda / 남 Puck, 한국어는 여 Achernar / 남 Puck
///   - WaveNet(기본 음성): 언어별 여·남 짝
///   - OpenAI 예비 경로(Google이 실패했을 때): 여 shimmer / 남 echo
///
/// 예전에는 OpenAI 목소리 이름(nova·verse·shimmer·echo·alloy)을 ID로 써서
/// 실제로 무슨 소리가 나는지 헷갈렸다. 새 코드는 이 두 값만 쓴다.
/// (공부방 Practice의 `google-female`·`google-male`은 이미 같은 뜻의 중립 ID다.)
const String kVoiceFemale = 'female';
const String kVoiceMale = 'male';

/// 💾 소리 **캐시 키 전용** 옛 이름표.
///
/// 기기에 저장된 소리의 캐시 키에 예전 목소리 ID가 들어 있다. 키를 바꾸면
/// 저장된 소리를 못 찾아 다시 만들게 되고(비용), 무료 사용자는 공부방 다시
/// 듣기가 막힌다. 그래서 캐시 키에만 옛 이름을 그대로 남긴다.
///
/// **소리와는 아무 관계가 없다.** 서버로 보내지 말 것.
class LegacyVoiceCacheKey {
  LegacyVoiceCacheKey._();

  /// 공부방 AI 줄·다시 듣기, 시나리오톡 사용자 통문장(여).
  static const String historyFemale = 'nova';

  /// 공부방 HOST 줄, 서클톡·시나리오톡 사용자 목소리(남).
  static const String historyMale = 'verse';

  /// 서클톡 AI(여).
  static const String circleFemale = 'shimmer';

  /// 시나리오톡 AI(남).
  static const String scenarioMale = 'echo';
}

/// Gateway(`MALE_VOICE_IDS`)가 남자로 읽는 옛 이름. 목록이 같아야 소리가
/// 바뀌지 않는다.
const Set<String> _legacyMaleVoices = <String>{
  'ash',
  'ballad',
  'cedar',
  'echo',
  'fable',
  'onyx',
  'verse',
};

/// Gateway가 여자로 읽는 옛 이름(남자 목록에 없으면 여자다).
const Set<String> _legacyFemaleVoices = <String>{
  'alloy',
  'coral',
  'marin',
  'nova',
  'sage',
  'shimmer',
};

/// 저장돼 있던 옛 목소리 이름을 중립 ID로 바꾼다.
/// 중립 ID(`female`·`male`·`google-*`)와 모르는 값은 그대로 돌려준다.
String wireVoiceFor(String raw) {
  final String v = raw.trim().toLowerCase();
  if (_legacyMaleVoices.contains(v)) return kVoiceMale;
  if (_legacyFemaleVoices.contains(v)) return kVoiceFemale;
  return raw.trim();
}

/// 캐시 키에 쓰는 이름. 중립 ID는 옛 키(`nova`·`verse`)로 되돌리고, 그 밖의
/// 값은 그대로 둔다. 옛 이름이 이미 저장돼 있으면 그 이름이 곧 키다.
String legacyCacheVoiceFor(String raw) {
  final String v = raw.trim();
  switch (v.toLowerCase()) {
    case kVoiceFemale:
      return LegacyVoiceCacheKey.historyFemale;
    case kVoiceMale:
      return LegacyVoiceCacheKey.historyMale;
    default:
      return v;
  }
}
