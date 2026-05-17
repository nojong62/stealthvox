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

import 'appsflyermanager.dart' show AppsFlyerManager;

/// FlutterFlow에서 호출하는 단일 진입점.
/// 실제 초기화와 payload 파싱은 AppsFlyerManager로 위임한다.
Future<void> initAppsFlyer(
  String? devKey,
  String? appId,
) async {
  if (devKey == null || devKey.isEmpty || appId == null || appId.isEmpty) {
    debugPrint('[initAppsFlyer] devKey or appId is null/empty, skipping');
    return;
  }
  debugPrint('[initAppsFlyer] delegating to AppsFlyerManager.initialize()');
  await AppsFlyerManager.initialize(devKey: devKey, appId: appId);
}
