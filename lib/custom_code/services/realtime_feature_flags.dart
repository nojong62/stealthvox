import 'package:flutter/foundation.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

/// Realtime rollout gates. All modes intentionally default to the legacy path.
class RealtimeFeatureFlags {
  RealtimeFeatureFlags._();

  static const globalKillSwitch = 'realtime_global_kill_switch';
  static const anyone = 'realtime_anyone_enabled';
  static const roleplay = 'realtime_roleplay_enabled';
  static const duo = 'realtime_duo_enabled';
  static const stepFirstTurn = 'realtime_step_first_turn_enabled';
  static const minimumAppVersion = 'realtime_min_app_version';

  static const Map<String, dynamic> defaults = <String, dynamic>{
    globalKillSwitch: false,
    anyone: false,
    roleplay: false,
    duo: false,
    stepFirstTurn: false,
    minimumAppVersion: '',
  };

  static Future<void> initialize() async {
    final remoteConfig = FirebaseRemoteConfig.instance;
    await remoteConfig.setDefaults(defaults);
  }

  /// 🧪 [DEV] Remote Config의 anyone 게이트는 dev_test_device 조건(설치 ID
  /// 화이트리스트)으로만 열린다. 앱을 재설치하면 설치 ID가 바뀌어 조건에서
  /// 빠지므로, 디버그 빌드에서는 화이트리스트와 무관하게 Realtime을 탄다.
  /// 릴리스 빌드와 실사용자는 기존 Remote Config 게이트 그대로다.
  static const bool forceAnyoneRealtimeInDebug = true;

  static bool enabledFor(String mode) {
    final remoteConfig = FirebaseRemoteConfig.instance;
    if (remoteConfig.getBool(globalKillSwitch)) return false;
    switch (mode) {
      case 'anyone':
        if (kDebugMode && forceAnyoneRealtimeInDebug) return true;
        return remoteConfig.getBool(anyone);
      case 'roleplay':
        return remoteConfig.getBool(roleplay);
      case 'duo':
        return remoteConfig.getBool(duo);
      case 'step_first_turn':
        return remoteConfig.getBool(stepFirstTurn);
      default:
        return false;
    }
  }
}
