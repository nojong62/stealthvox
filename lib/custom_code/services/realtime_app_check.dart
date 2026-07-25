import 'package:firebase_app_check/firebase_app_check.dart';

class RealtimeAppCheck {
  RealtimeAppCheck._();

  static bool _initialized = false;

  static Future<void> initialize({bool debugProvider = false}) async {
    if (_initialized) return;
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          debugProvider ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider:
          debugProvider ? AppleProvider.debug : AppleProvider.deviceCheck,
    );
    _initialized = true;
  }
}
