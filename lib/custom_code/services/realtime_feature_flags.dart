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

  static bool enabledFor(String mode) {
    final remoteConfig = FirebaseRemoteConfig.instance;
    if (remoteConfig.getBool(globalKillSwitch)) return false;
    switch (mode) {
      case 'anyone':
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
