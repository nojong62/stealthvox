import 'package:firebase_app_check/firebase_app_check.dart';

class RealtimeAppCheck {
  RealtimeAppCheck._();

  static bool _initialized = false;
  static const bool _debugProviderFromBuild = bool.fromEnvironment(
    'REALTIME_APPCHECK_DEBUG',
    defaultValue: false,
  );
  static bool _usingDebugProvider = false;

  static bool get usingDebugProvider => _usingDebugProvider;

  static Future<void> initialize({bool debugProvider = false}) async {
    if (_initialized) return;
    final useDebugProvider = debugProvider || _debugProviderFromBuild;
    await FirebaseAppCheck.instance.activate(
      androidProvider: useDebugProvider
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
      appleProvider:
          useDebugProvider ? AppleProvider.debug : AppleProvider.deviceCheck,
    );
    _usingDebugProvider = useDebugProvider;
    _initialized = true;
  }
}
