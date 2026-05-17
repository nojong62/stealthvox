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

import 'package:purchases_flutter/purchases_flutter.dart';
import 'dart:io' show Platform;

Future initRevenueCat() async {
  // 🔥 여기에 방금 복사한 goog_... 키를 따옴표 안에 붙여넣으세요! (따옴표는 지우면 안 됩니다)
  final String androidApiKey = 'goog_XfTPcusZVFeDsZEkFHYiFgUUUIK';

  if (Platform.isAndroid) {
    await Purchases.setLogLevel(LogLevel.debug);
    PurchasesConfiguration configuration =
        PurchasesConfiguration(androidApiKey);
    await Purchases.configure(configuration);
  }
}
