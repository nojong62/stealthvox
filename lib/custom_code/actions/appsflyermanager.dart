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

// FlutterFlow export 유지용 no-op (삭제 금지)
Future<void> appsflyermanager() async {
  debugPrint('[AppsFlyerManager] no-op placeholder called');
}

class AppsFlyerManager {
  static AppsflyerSdk? _instance;
  static bool _isInitialized = false;

  /// 유일한 SDK 초기화 진입점.
  /// FlutterFlow에서 initAppsFlyer(devKey, appId) → 여기 호출됨.
  static Future<void> initialize({
    required String devKey,
    required String appId,
  }) async {
    if (_isInitialized) {
      debugPrint('[AppsFlyerManager] already initialized, skipping');
      return;
    }
    try {
      final AppsFlyerOptions options = AppsFlyerOptions(
        afDevKey: devKey,
        appId: appId,
        showDebug: true, // 테스트 기간 동안 true 유지
        timeToWaitForATTUserAuthorization: 15,
      );

      _instance = AppsflyerSdk(options);

      // Unified Deep Link (앱 설치된 상태 — 권장 경로)
      _instance!.onDeepLinking((DeepLinkResult res) {
        debugPrint('[AppsFlyer] onDeepLinking status: ${res.status}');
        if (res.status == Status.FOUND) {
          try {
            final clickEvent = res.deepLink?.clickEvent ?? {};
            final params = Map<String, dynamic>.from(clickEvent);
            if (res.deepLink?.deepLinkValue != null) {
              params['deep_link_value'] = res.deepLink!.deepLinkValue!;
            }
            debugPrint('[AppsFlyer] raw payload (onDeepLinking): $params');
            _handlePayload(params);
          } catch (e) {
            debugPrint('[AppsFlyer] onDeepLinking parse error: $e');
          }
        }
      });

      // Deferred Deep Link (앱 미설치 → 설치 후 첫 실행)
      _instance!.onInstallConversionData((res) {
        debugPrint('[AppsFlyer] onInstallConversionData raw: $res');
        _routeCallback(res, _handlePayload);
      });

      // App Open Attribution (구형 폴백)
      _instance!.onAppOpenAttribution((res) {
        debugPrint('[AppsFlyer] onAppOpenAttribution raw: $res');
        _routeCallback(res, _handlePayload);
      });

      await _instance!.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );

      _isInitialized = true;
      debugPrint('[AppsFlyerManager] initialized successfully');
    } catch (e) {
      debugPrint('[AppsFlyerManager] init error: $e');
    }
  }

  /// onInstallConversionData / onAppOpenAttribution 응답을 파싱해
  /// _handlePayload 형태로 변환하는 어댑터
  static void _routeCallback(
    dynamic res,
    void Function(Map<String, dynamic>) handler,
  ) {
    try {
      if (res == null) return;
      final raw = res as Map<dynamic, dynamic>;
      if ((raw['status']?.toString() ?? '') != 'success') return;
      final payload = raw['data'] ?? raw;
      if (payload == null) return;
      final params = Map<String, dynamic>.from(payload as Map);
      debugPrint('[AppsFlyer] raw payload (routeCallback): $params');
      handler(params);
    } catch (e) {
      debugPrint('[AppsFlyerManager] _routeCallback error: $e');
    }
  }

  /// 세 콜백 경로 공통 파싱 + FFAppState 저장
  static void _handlePayload(Map<String, dynamic> params) {
    try {
      // room_id 우선, 없으면 duo_room_id → deep_link_sub2 → af_sub2 순서로 폴백
      final String roomId = (params['room_id'] ??
              params['duo_room_id'] ??
              params['deep_link_sub2'] ??
              params['af_sub2'] ??
              '')
          .toString()
          .trim();

      // inviter_id 우선, 없으면 deep_link_sub1 폴백
      final String inviterUid =
          (params['inviter_id'] ?? params['deep_link_sub1'] ?? '')
              .toString()
              .trim();

      final String deepLinkValue =
          (params['deep_link_value'] ?? '').toString().trim();
      final String inviteType =
          (params['invite_type'] ?? '').toString().trim();
      final String afDp = (params['af_dp'] ?? '').toString().trim();

      debugPrint('[AppsFlyer] parsed duo roomId: $roomId');
      debugPrint('[AppsFlyer] parsed inviterUid: $inviterUid');
      debugPrint('[AppsFlyer] parsed deepLinkValue: $deepLinkValue');
      debugPrint('[AppsFlyer] parsed inviteType: $inviteType');

      // Duo 초대 판정 (deep_link_value, invite_type, af_dp 모두 체크)
      final bool isDuoInvite =
          deepLinkValue == 'duo_chat' ||
          inviteType == 'duo' ||
          afDp.contains('duo');

      if (isDuoInvite && roomId.isNotEmpty) {
        FFAppState().isGuestSession = true;
        FFAppState().duoRoomId = roomId;
        FFAppState().inviterUid = inviterUid;
        FFAppState().pendingInviteType = 'duo';
        FFAppState().update(() {});
        debugPrint('[AppsFlyer] saved FFAppState duo invite');
      } else {
        debugPrint(
            '[AppsFlyer] not a duo invite or roomId empty, skipping state save');
      }
    } catch (e) {
      debugPrint('[AppsFlyerManager] _handlePayload error: $e');
    }
  }
}
