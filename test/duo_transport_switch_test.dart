// 🔀 [DUO-TRANSPORT] 통로 스위치가 언제 열리는가를 지키는 시험.
//
// 여기서 지키는 두 문장:
//   1. "'webrtc'라고 정확히 적혀 있을 때만 새 경로다." 오타·빈 값·모르는
//      값은 전부 기존 릴레이로 떨어진다 — 이 스위치가 실기기 검증 전의
//      유일한 안전장치이므로 느슨하게 읽으면 안 된다.
//   2. "통로와 모드는 다른 축이다." 만능 통역은 통로 값이 무엇이든 원음을
//      보내지 않는다.
//
// 위젯의 `_fetchKeys`가 하는 판정과 **같은 규칙**을 여기 두어, 나중에 한쪽만
// 느슨해지는 것을 막는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/widgets/routine_mode_duo.dart'
    show kDuoTransportRelay, kDuoTransportWebrtc, kDuoModeDirect;

/// 위젯이 Remote Config 값을 읽는 규칙과 같은 판정.
String resolveTransport(String raw) =>
    raw.trim().toLowerCase() == kDuoTransportWebrtc
        ? kDuoTransportWebrtc
        : kDuoTransportRelay;

void main() {
  group('통로 선택 — 기본은 릴레이다', () {
    test('값이 없으면 릴레이', () {
      expect(resolveTransport(''), kDuoTransportRelay);
      expect(resolveTransport('   '), kDuoTransportRelay);
    });

    test('모르는 값이면 릴레이', () {
      expect(resolveTransport('rtc'), kDuoTransportRelay);
      expect(resolveTransport('peer'), kDuoTransportRelay);
      expect(resolveTransport('true'), kDuoTransportRelay);
      expect(resolveTransport('1'), kDuoTransportRelay);
    });

    test('오타는 릴레이로 떨어진다 — 새 경로가 실수로 켜지지 않는다', () {
      expect(resolveTransport('webrtc '), kDuoTransportWebrtc); // trim은 한다
      expect(resolveTransport('webrct'), kDuoTransportRelay);
      expect(resolveTransport('web-rtc'), kDuoTransportRelay);
      expect(resolveTransport('webrtc2'), kDuoTransportRelay);
    });
  });

  group('통로 선택 — 켜지는 조건', () {
    test("'webrtc'라고 적혀야만 켜진다", () {
      expect(resolveTransport('webrtc'), kDuoTransportWebrtc);
    });

    test('대소문자는 봐준다 — Remote Config 콘솔에서 손으로 넣는 값이다', () {
      expect(resolveTransport('WebRTC'), kDuoTransportWebrtc);
      expect(resolveTransport('WEBRTC'), kDuoTransportWebrtc);
    });
  });

  group('통로와 모드는 다른 축이다', () {
    test('두 상수는 서로 다른 값 공간이다', () {
      // mode('direct'/'interpreter')와 transport('relay'/'webrtc')가 같은
      // 문자열을 쓰면 언젠가 한쪽을 다른 쪽에 넣는 실수가 난다.
      expect(kDuoTransportRelay, isNot(kDuoModeDirect));
      expect(kDuoTransportWebrtc, isNot(kDuoModeDirect));
    });

    test('통로 값 두 개는 서로 다르다', () {
      expect(kDuoTransportRelay, isNot(kDuoTransportWebrtc));
    });
  });

  group('WebRTC 실패 폴백', () {
    final source = File('lib/custom_code/widgets/routine_mode_duo.dart')
        .readAsStringSync();
    final callSource = File('lib/custom_code/services/duo_webrtc_call.dart')
        .readAsStringSync();

    test('초기 연결 실패는 WebRTC를 정리한 뒤 릴레이 하나만 연다', () {
      final start = source.indexOf('Future<void> _startDirectCall()');
      final end = source.indexOf('DuoMicPcmFanout _buildDirectFanout', start);
      final body = source.substring(start, end);
      expect(body, contains('!transportOk && useWebrtcNow'));
      expect(body, contains('_directRelayFallback = true'));
      expect(body, contains('await _openRelayTransport(generation, roomId)'));

      final open = source.indexOf('Future<bool> _openWebrtcTransport(');
      final fallback = source.indexOf(
        'Future<void> _fallbackActiveWebrtcToRelay(',
        open,
      );
      final openBody = source.substring(open, fallback);
      expect(openBody, contains('await call.dispose()'));
      expect(openBody,
          isNot(contains("_stopDirectCall('webrtc_connect_failed')")));
    });

    test('통화 중 ICE 실패도 종료 후 릴레이로 다시 시작한다', () {
      final start = source.indexOf(
        'Future<void> _fallbackActiveWebrtcToRelay(',
      );
      final end = source.indexOf('/// 🔬 [DUO-AB]', start);
      final body = source.substring(start, end);
      expect(
          body, contains("await _stopDirectCall('webrtc_fallback_\$reason')"));
      expect(body, contains('await _startDirectCall()'));
      expect(body, contains('_directFallbackInProgress'));
    });

    test('게스트도 호스트 재협상 창이 끝나면 폴백 신호를 받는다', () {
      final start = callSource.indexOf('void _scheduleIceRestart(');
      final end = callSource.indexOf('void _cancelIceRestart()', start);
      final body = callSource.substring(start, end);
      expect(body, contains('if (!isOfferer)'));
      expect(body, contains("onFatal?.call('answerer_recovery_timeout')"));
      expect(
        body,
        contains('kDuoWebrtcMaxIceRestarts + 1'),
      );
    });

    test('폴백은 번역 모드가 아니라 Direct transport만 바꾼다', () {
      final start = source.indexOf(
        'Future<void> _fallbackActiveWebrtcToRelay(',
      );
      final end = source.indexOf('/// 🔬 [DUO-AB]', start);
      final body = source.substring(start, end);
      expect(body, isNot(contains('_duoMode =')));
      expect(body, isNot(contains('kDuoModeInterpreter')));
      expect(body, isNot(contains('_startInterpreter')));
    });
  });
}
