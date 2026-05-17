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

Future initAppsFlyer(
  String? devKey,
  String? appId,
) async {
  if (devKey == null || appId == null) {
    return;
  }

  final AppsFlyerOptions options = AppsFlyerOptions(
    afDevKey: devKey,
    appId: appId,
    showDebug: true,
    timeToWaitForATTUserAuthorization: 15,
  );

  AppsflyerSdk appsflyerSdk = AppsflyerSdk(options);

  // 초기화
  await appsflyerSdk.initSdk(
    registerConversionDataCallback: true,
    registerOnAppOpenAttributionCallback: true,
    registerOnDeepLinkingCallback: true,
  );

  // 딥링크 수신 시 로직
  appsflyerSdk.onDeepLinking((DeepLinkResult res) {
    if (res.status == Status.FOUND) {
      final String? inviterId = res.deepLink?.clickEvent['inviter_id'];
      if (inviterId != null) {
        // App State 업데이트
        FFAppState().isGuestSession = true;
        FFAppState().inviterUid = inviterId;
      }
    }
  });
}
