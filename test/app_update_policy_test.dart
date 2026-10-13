import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/app_update_policy.dart';
import 'package:stealth_vox/custom_code/widgets/app_update_gate.dart';
import 'package:stealth_vox/custom_code/services/origin_surface_localization.dart';

/// 업데이트 안내는 폰 시스템 언어를 따른다. 테스트 환경 언어에 묶이지 않게
/// 화면이 쓰는 같은 표에서 문구를 읽는다.
String _t(String key) => OriginSurfaceCopy.forSystemLocale()[key];

void main() {
  group('evaluateAndroidAppUpdate', () {
    AppUpdateDecision evaluate({
      bool isAndroid = true,
      bool fetchSucceeded = true,
      int? current = 10,
      Object? min = 5,
      Object? latest = 10,
      Object? message = '업데이트 메시지',
      Object? storeUrl = kStealthVoxPlayStoreUrl,
    }) {
      return evaluateAndroidAppUpdate(
        isAndroid: isAndroid,
        remoteConfigFetchSucceeded: fetchSucceeded,
        currentVersionCode: current,
        minVersion: min,
        latestVersion: latest,
        updateMessage: message,
        storeUrl: storeUrl,
      );
    }

    test('current가 min보다 낮으면 강제 업데이트다', () {
      expect(
        evaluate(current: 4).requirement,
        AppUpdateRequirement.required,
      );
    });

    test('Remote Config 문자열 정수도 versionCode로 판정한다', () {
      expect(
        evaluate(current: 4, min: '5', latest: '10').requirement,
        AppUpdateRequirement.required,
      );
    });

    test('min 이상 latest 미만이면 권장 업데이트다', () {
      expect(
        evaluate(current: 7).requirement,
        AppUpdateRequirement.recommended,
      );
    });

    test('latest 이상이면 정상 진입한다', () {
      expect(evaluate().requirement, AppUpdateRequirement.none);
    });

    test('0/0 기본값은 정상 진입한다', () {
      expect(
        evaluate(current: 152, min: 0, latest: 0).requirement,
        AppUpdateRequirement.none,
      );
    });

    test('버전 값 누락은 fail-open이다', () {
      expect(
        evaluate(min: null).requirement,
        AppUpdateRequirement.none,
      );
      expect(
        evaluate(latest: null).requirement,
        AppUpdateRequirement.none,
      );
    });

    test('음수 또는 파싱 실패는 fail-open이다', () {
      expect(
        evaluate(min: -1).requirement,
        AppUpdateRequirement.none,
      );
      expect(
        evaluate(latest: 'not-a-number').requirement,
        AppUpdateRequirement.none,
      );
    });

    test('min이 latest보다 크면 fail-open이다', () {
      expect(
        evaluate(min: 11, latest: 10).requirement,
        AppUpdateRequirement.none,
      );
    });

    test('buildNumber 획득 또는 파싱 실패는 fail-open이다', () {
      expect(
        evaluate(current: null).requirement,
        AppUpdateRequirement.none,
      );
      expect(
        evaluate(current: 0).requirement,
        AppUpdateRequirement.none,
      );
    });

    test('Remote Config 실패나 시간 초과 결과는 fail-open이다', () {
      expect(
        evaluate(fetchSucceeded: false, current: 1).requirement,
        AppUpdateRequirement.none,
      );
    });

    test('Android 이외 플랫폼은 정상 진입한다', () {
      expect(
        evaluate(isAndroid: false, current: 1).requirement,
        AppUpdateRequirement.none,
      );
    });

    test('빈 업데이트 문구는 기본 문구로 대체한다', () {
      expect(
        evaluate(current: 4, message: '   ').message,
        kDefaultAndroidUpdateMessage,
      );
      expect(
        evaluate(current: 4, message: 123).message,
        kDefaultAndroidUpdateMessage,
      );
    });

    test('비정상 Play Store URL은 공식 주소로 대체한다', () {
      expect(
        evaluate(current: 4, storeUrl: 'https://example.com/app').storeUrl,
        kStealthVoxPlayStoreUrl,
      );
      expect(
        evaluate(current: 4, storeUrl: null).storeUrl,
        kStealthVoxPlayStoreUrl,
      );
    });

    test('정상 Play Store URL은 유지한다', () {
      const url =
          'https://play.google.com/store/apps/details?id=com.aienglishpractice.stealthvox&hl=ko';
      expect(evaluate(current: 4, storeUrl: url).storeUrl, url);
    });
  });

  group('AppUpdateGate', () {
    testWidgets('권장 업데이트를 나중에 선택하면 같은 세션에서 다시 표시하지 않는다', (tester) async {
      const decision = AppUpdateDecision(
        requirement: AppUpdateRequirement.recommended,
      );

      Widget app() => const MaterialApp(
            home: AppUpdateGate(
              decision: decision,
              child: Scaffold(body: Text('앱 본문')),
            ),
          );

      await tester.pumpWidget(app());
      expect(find.text(_t('updateAvailable')), findsOneWidget);
      expect(find.text(_t('later')), findsOneWidget);

      await tester.tap(find.text(_t('later')));
      await tester.pump();
      expect(find.text(_t('updateAvailable')), findsNothing);
      expect(find.text('앱 본문'), findsOneWidget);

      // 같은 위젯 위치의 State가 유지되는 앱 재빌드는 같은 실행 세션이다.
      await tester.pumpWidget(app());
      await tester.pump();
      expect(find.text(_t('updateAvailable')), findsNothing);
    });

    testWidgets('강제 업데이트는 나중에 버튼과 뒤로가기 우회가 없다', (tester) async {
      const decision = AppUpdateDecision(
        requirement: AppUpdateRequirement.required,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: AppUpdateGate(
            decision: decision,
            child: Scaffold(body: Text('앱 본문')),
          ),
        ),
      );

      expect(find.text(_t('updateAvailable')), findsOneWidget);
      expect(find.text(_t('update')), findsOneWidget);
      expect(find.text(_t('later')), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text(_t('updateAvailable')), findsOneWidget);
    });
  });
}
