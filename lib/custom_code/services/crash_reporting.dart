// ====================================================================
// 🧯 [CRASH] 사용자 폰에서 난 오류를 Firebase Crashlytics로 보낸다
// --------------------------------------------------------------------
// 2026-11-10 실장님 지시. 앱이 죽거나 잡히지 않은 오류가 나면 어느 줄에서
// 났는지, 어떤 폰·버전인지가 Firebase 콘솔에 쌓이고 새 오류는 메일로 온다.
//
//   · 디버그 빌드는 보내지 않는다 — 개발 중 오류로 통계를 더럽히지 않는다.
//     콘솔 출력도 예전 그대로다.
//   · 대화 내용·전사문은 보내지 않는다. 오류 종류와 스택만 간다.
//   · 사용자 id는 붙이지 않는다(붙이려면 Play 데이터 보안 항목부터 정한다).
// ====================================================================

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Firebase 초기화 **뒤에** 한 번 부른다.
Future<void> installCrashReporting() async {
  final crashlytics = FirebaseCrashlytics.instance;
  await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
  if (kDebugMode) return;

  // 화면을 그리다 난 오류(Flutter 프레임워크가 잡은 것).
  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    crashlytics.recordFlutterFatalError(details);
    previousFlutterError?.call(details);
  };

  // 그 밖의 잡히지 않은 오류(비동기 작업 등).
  final previousPlatformError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    crashlytics.recordError(error, stack, fatal: true);
    return previousPlatformError?.call(error, stack) ?? true;
  };
}
