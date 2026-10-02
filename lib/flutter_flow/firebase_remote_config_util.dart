import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '/custom_code/services/app_update_policy.dart';

const Duration _remoteConfigFetchTimeout = Duration(seconds: 5);

/// 앱 시작 시 Remote Config를 한 번 활성화한다.
///
/// 이번 실행의 fetch가 정상 완료됐는지를 반환한다. 실패나 시간 초과 시에는
/// 캐시된 강제 업데이트 값을 적용하지 않고 앱을 정상 진입시킨다.
Future<bool> initializeFirebaseRemoteConfig() async {
  try {
    final remoteConfig = FirebaseRemoteConfig.instance;
    await remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: _remoteConfigFetchTimeout,
      minimumFetchInterval: const Duration(hours: 1),
    ));
    await remoteConfig.setDefaults(const {
      'OpenAIAPIKey': '',
      // TTS 모델 교체는 앱 배포 없이 이 키들로 전환한다. 값이 비어 있으면
      // 코드의 검증된 기본 프로필(tts-1 / gpt-4o-mini-tts)을 유지한다.
      'OpenAITtsConversationModel': '',
      'OpenAITtsConversationOptionMode': '',
      'OpenAITtsExpressiveModel': '',
      'OpenAITtsExpressiveOptionMode': '',
      'OpenAITtsCacheVersion': '',
      'android_min_version': 0,
      'android_latest_version': 0,
      'android_update_message': kDefaultAndroidUpdateMessage,
      'android_store_url': kStealthVoxPlayStoreUrl,
    });
    await remoteConfig
        .fetchAndActivate()
        .timeout(_remoteConfigFetchTimeout + const Duration(seconds: 2));
    return true;
  } catch (error) {
    debugPrint('[RemoteConfig] startup fetch failed: $error');
    return false;
  }
}

/// 이번 실행의 Remote Config fetch가 성공한 Android 앱에서만 업데이트 정책을
/// 평가한다. 플랫폼/빌드 번호/Remote Config 값 오류는 모두 fail-open이다.
Future<AppUpdateDecision> resolveAndroidAppUpdateDecision({
  required bool remoteConfigFetchSucceeded,
}) async {
  final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  if (!isAndroid || !remoteConfigFetchSucceeded) {
    return const AppUpdateDecision.none();
  }

  try {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersionCode = int.tryParse(packageInfo.buildNumber.trim());
    final remoteConfig = FirebaseRemoteConfig.instance;
    return evaluateAndroidAppUpdate(
      isAndroid: true,
      remoteConfigFetchSucceeded: true,
      currentVersionCode: currentVersionCode,
      minVersion: remoteConfig.getValue('android_min_version').asString(),
      latestVersion: remoteConfig.getValue('android_latest_version').asString(),
      updateMessage: remoteConfig.getValue('android_update_message').asString(),
      storeUrl: remoteConfig.getValue('android_store_url').asString(),
    );
  } catch (error) {
    debugPrint('[AppUpdate] version check failed open: $error');
    return const AppUpdateDecision.none();
  }
}

String getRemoteConfigString(String key) =>
    FirebaseRemoteConfig.instance.getString(key);

bool getRemoteConfigBool(String key) =>
    FirebaseRemoteConfig.instance.getBool(key);

int getRemoteConfigInt(String key) => FirebaseRemoteConfig.instance.getInt(key);

double getRemoteConfigDouble(String key) =>
    FirebaseRemoteConfig.instance.getDouble(key);
