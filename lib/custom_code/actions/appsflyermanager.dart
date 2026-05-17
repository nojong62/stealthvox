// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:appsflyer_sdk/appsflyer_sdk.dart';

// Placeholder so FlutterFlow recognizes this file as a custom action.
Future<void> appsflyermanager() async {}

class AppsFlyerManager {
  static AppsflyerSdk? _instance;
  static bool _isInitialized = false;
  // Callback replaced per screen without re-creating the SDK instance.
  static Function(Map<String, dynamic>)? _onDeepLink;

  static Future<void> initialize({
    required String devKey,
    required String appId,
    required Function(Map<String, dynamic>) onDeepLink,
  }) async {
    // 콜백은 항상 최신 화면 핸들러로 업데이트 (SDK 생성과 분리)
    _onDeepLink = onDeepLink;
    if (_isInitialized) return;
    try {
      final AppsFlyerOptions options = AppsFlyerOptions(
        afDevKey: devKey,
        appId: appId,
        showDebug: false,
        timeToWaitForATTUserAuthorization: 60,
      );

      _instance = AppsflyerSdk(options);

      _instance!.onInstallConversionData((res) {
        final cb = _onDeepLink;
        if (cb != null) _routeCallback(res, cb);
      });

      _instance!.onAppOpenAttribution((res) {
        final cb = _onDeepLink;
        if (cb != null) _routeCallback(res, cb);
      });

      _instance!.onDeepLinking((DeepLinkResult dp) {
        if (dp.status == Status.FOUND) {
          try {
            final clickEvent = dp.deepLink?.clickEvent;
            final params = clickEvent == null
                ? <String, dynamic>{}
                : Map<String, dynamic>.from(clickEvent);
            if (dp.deepLink?.deepLinkValue != null) {
              params['deep_link_value'] = dp.deepLink!.deepLinkValue!;
            }
            _onDeepLink?.call(params);
          } catch (e) {
            debugPrint('[AppsFlyerManager] onDeepLinking error: $e');
          }
        }
      });

      await _instance!.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );

      _isInitialized = true;
    } catch (e) {
      debugPrint('[AppsFlyerManager] init error: $e');
    }
  }

  static void _routeCallback(
    dynamic res,
    Function(Map<String, dynamic>) onDeepLink,
  ) {
    try {
      if (res == null) return;
      final Map<dynamic, dynamic> raw = res as Map<dynamic, dynamic>;
      if ((raw['status']?.toString() ?? '') != 'success') return;
      final dynamic payload = raw['data'] ?? raw;
      if (payload == null) return;
      onDeepLink(Map<String, dynamic>.from(payload as Map));
    } catch (e) {
      debugPrint('[AppsFlyerManager] callback error: $e');
    }
  }
}
