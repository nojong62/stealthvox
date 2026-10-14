import 'package:firebase_remote_config/firebase_remote_config.dart';

/// TTS 용도별 모델 계약.
///
/// 대화 음성은 짧은 지연과 숫자형 speed가 중요하고, 학습 음성은
/// instructions 기반 표현력이 중요하다. 후속 모델이 발표돼도 두 계약을
/// 한 모델로 성급하게 합치지 않도록 프로필을 분리한다.
enum TtsWorkload {
  conversation,
  expressiveStudy,
}

enum TtsOptionMode {
  speed,
  instructions,
  none,
}

class TtsModelProfile {
  const TtsModelProfile({
    required this.model,
    required this.optionMode,
    required this.cacheVersion,
  });

  final String model;
  final TtsOptionMode optionMode;
  final String cacheVersion;

  Map<String, dynamic> speechPayload({
    required String input,
    required String voice,
    double speed = 1.0,
    String? instructions,
    String? responseFormat,
    String? language,
  }) {
    final trimmedInstructions = instructions?.trim() ?? '';
    final trimmedLanguage = language?.trim() ?? '';
    return <String, dynamic>{
      'model': model,
      'input': input,
      'voice': voice,
      // Gateway 전용 칸. OpenAI로 넘길 때는 Gateway가 지운다.
      if (trimmedLanguage.isNotEmpty) 'language': trimmedLanguage,
      if (responseFormat != null && responseFormat.isNotEmpty)
        'response_format': responseFormat,
      if (optionMode == TtsOptionMode.speed) 'speed': speed,
      if (optionMode == TtsOptionMode.instructions &&
          trimmedInstructions.isNotEmpty)
        'instructions': trimmedInstructions,
    };
  }
}

/// 앱 전체 OpenAI TTS 모델 선택의 단일 진입점.
///
/// 우선순위:
/// 1. 빌드 강제값 — 장애 시 원격값을 무시하는 최후의 롤백 수단
/// 2. Firebase Remote Config — 앱 재배포 없이 후보 모델 전환
/// 3. 코드 기본값 — 현재 검증된 운영 동작
///
/// Remote Config 키:
/// - OpenAITtsConversationModel / OpenAITtsConversationOptionMode
/// - OpenAITtsExpressiveModel / OpenAITtsExpressiveOptionMode
/// - OpenAITtsCacheVersion
///
/// option mode 값은 speed, instructions, none 중 하나다. 새 모델 전환 때
/// 모델명만 바꾸지 말고 해당 모델이 실제 지원하는 옵션 계약도 함께 지정한다.
class TtsModelPolicy {
  TtsModelPolicy._();

  static const String conversationModelKey = 'OpenAITtsConversationModel';
  static const String conversationOptionModeKey =
      'OpenAITtsConversationOptionMode';
  static const String expressiveModelKey = 'OpenAITtsExpressiveModel';
  static const String expressiveOptionModeKey = 'OpenAITtsExpressiveOptionMode';
  static const String cacheVersionKey = 'OpenAITtsCacheVersion';

  static const String _forcedConversationModel = String.fromEnvironment(
    'OPENAI_TTS_CONVERSATION_MODEL',
    defaultValue: '',
  );
  static const String _forcedConversationOptionMode = String.fromEnvironment(
    'OPENAI_TTS_CONVERSATION_OPTION_MODE',
    defaultValue: '',
  );
  static const String _forcedExpressiveModel = String.fromEnvironment(
    'OPENAI_TTS_EXPRESSIVE_MODEL',
    defaultValue: '',
  );
  static const String _forcedExpressiveOptionMode = String.fromEnvironment(
    'OPENAI_TTS_EXPRESSIVE_OPTION_MODE',
    defaultValue: '',
  );
  static const String _forcedCacheVersion = String.fromEnvironment(
    'OPENAI_TTS_CACHE_VERSION',
    defaultValue: '',
  );

  static const TtsModelProfile _conversationDefault = TtsModelProfile(
    model: 'tts-1',
    optionMode: TtsOptionMode.speed,
    cacheVersion: 'legacy-v1',
  );
  static const TtsModelProfile _expressiveDefault = TtsModelProfile(
    model: 'gpt-4o-mini-tts',
    optionMode: TtsOptionMode.instructions,
    cacheVersion: 'legacy-v1',
  );

  static TtsModelProfile get conversation => _resolve(TtsWorkload.conversation);

  static TtsModelProfile get expressiveStudy =>
      _resolve(TtsWorkload.expressiveStudy);

  static TtsModelProfile forWorkload(TtsWorkload workload) =>
      _resolve(workload);

  static String cacheNamespace(
    TtsWorkload workload,
    String namespace,
  ) {
    final profile = forWorkload(workload);
    // The audio provider can change without the caller's cache key changing.
    // v3: every conversation language moved to Chirp 3 HD, so prior OpenAI
    // bytes must not be replayed.
    return '${profile.model}_${profile.cacheVersion}_tts-route-v3_$namespace';
  }

  static TtsModelProfile _resolve(TtsWorkload workload) {
    final defaults = workload == TtsWorkload.conversation
        ? _conversationDefault
        : _expressiveDefault;
    final forcedModel = workload == TtsWorkload.conversation
        ? _forcedConversationModel
        : _forcedExpressiveModel;
    final forcedOption = workload == TtsWorkload.conversation
        ? _forcedConversationOptionMode
        : _forcedExpressiveOptionMode;
    final remoteModelKey = workload == TtsWorkload.conversation
        ? conversationModelKey
        : expressiveModelKey;
    final remoteOptionKey = workload == TtsWorkload.conversation
        ? conversationOptionModeKey
        : expressiveOptionModeKey;

    final model = _validModelId(forcedModel) ??
        _validModelId(_remoteString(remoteModelKey)) ??
        defaults.model;
    final optionMode = _parseOptionMode(forcedOption) ??
        _parseOptionMode(_remoteString(remoteOptionKey)) ??
        defaults.optionMode;
    final cacheVersion = _validCacheToken(_forcedCacheVersion) ??
        _validCacheToken(_remoteString(cacheVersionKey)) ??
        defaults.cacheVersion;
    return TtsModelProfile(
      model: model,
      optionMode: optionMode,
      cacheVersion: cacheVersion,
    );
  }

  static String _remoteString(String key) {
    try {
      return FirebaseRemoteConfig.instance.getString(key).trim();
    } catch (_) {
      return '';
    }
  }

  static String? _validModelId(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value.length > 128) return null;
    return RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*').stringMatch(value) == value
        ? value
        : null;
  }

  static String? _validCacheToken(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value.length > 64) return null;
    return RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*').stringMatch(value) == value
        ? value
        : null;
  }

  static TtsOptionMode? _parseOptionMode(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'speed':
        return TtsOptionMode.speed;
      case 'instructions':
        return TtsOptionMode.instructions;
      case 'none':
        return TtsOptionMode.none;
      default:
        return null;
    }
  }
}
