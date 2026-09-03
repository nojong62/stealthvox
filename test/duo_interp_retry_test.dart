// 🔁 [INTERP-RETRY] 만능 통역이 못 붙었을 때 다시 붙는다
//
// WebRTC 통역이 기본 경로가 되면서 생긴 자리다. 그 전에는 시작이 실패해도
// record + Firestore가 돌고 있었지만, 지금은 실패하면 **통역이 통째로 시작되지
// 않는다.** 그런데 `_interpAutoStartAttempted`는 시도 전에 세워지고 실패
// 갈래에서 풀리지 않아, 한 번 못 붙으면 상대가 나갔다 들어올 때까지 아무 일도
// 일어나지 않았다.
//
// 규칙(2·5·10초, 3회)은 `duo_interp_retry.dart`에 순수 코드로 있어 시계 없이
// 그대로 시험한다. 위젯 쪽은 시계를 거는 배선이라 소스로 지킨다.
//
// 🚫 **실패해도 Firestore로 갈아타지 않는다.** 통로는 통화가 시작될 때 한 번
//   박히고 끝날 때까지 고정이다(`_interpTransport`). 되돌리는 일은 Remote
//   Config가 다음 통화부터 한다 — 이번 기능과 다른 축이다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_interp_retry.dart';

const String _duo = 'lib/custom_code/widgets/routine_mode_duo.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _region(String src, String start, String end) {
  final int a = src.indexOf(start);
  if (a < 0) throw StateError('없는 선언: $start');
  final int b = src.indexOf(end, a + 1);
  if (b < a) throw StateError('없는 선언: $end');
  return src.substring(a, b);
}

void main() {
  final String duo = _read(_duo);

  // ==========================================================================
  // 규칙 자체는 시계가 없어 그대로 잰다.
  group('간격은 2 → 5 → 10초, 세 번이 전부다', () {
    late DuoInterpRetryPolicy policy;
    setUp(() => policy = DuoInterpRetryPolicy());

    test('첫 실패 뒤 2초', () {
      expect(policy.takeNextDelay(), const Duration(seconds: 2));
      expect(policy.attempts, 1);
    });

    test('두 번째 실패 뒤 5초', () {
      policy.takeNextDelay();
      expect(policy.takeNextDelay(), const Duration(seconds: 5));
      expect(policy.attempts, 2);
    });

    test('세 번째 실패 뒤 10초', () {
      policy.takeNextDelay();
      policy.takeNextDelay();
      expect(policy.takeNextDelay(), const Duration(seconds: 10));
      expect(policy.attempts, 3);
    });

    test('네 번째는 없다 — 무한 재시도로 흐르지 않는다', () {
      for (int i = 0; i < kDuoInterpRetryDelays.length; i++) {
        expect(policy.takeNextDelay(), isNotNull);
      }
      expect(policy.exhausted, isTrue);
      // 몇 번을 더 물어도 계속 null이다.
      for (int i = 0; i < 5; i++) {
        expect(policy.takeNextDelay(), isNull);
      }
      expect(policy.attempts, kDuoInterpRetryDelays.length,
          reason: '소진된 뒤에도 횟수가 늘면 로그가 거짓말을 한다');
    });

    test('간격이 점점 길어진다 — 붙지도 않는 망을 계속 두드리지 않는다', () {
      for (int i = 1; i < kDuoInterpRetryDelays.length; i++) {
        expect(kDuoInterpRetryDelays[i], greaterThan(kDuoInterpRetryDelays[i - 1]));
      }
    });

    test('reset이 처음으로 되돌린다', () {
      policy.takeNextDelay();
      policy.takeNextDelay();
      policy.reset();
      expect(policy.attempts, 0);
      expect(policy.exhausted, isFalse);
      expect(policy.takeNextDelay(), const Duration(seconds: 2),
          reason: '되돌린 뒤 첫 간격이 2초가 아니면 수동 재시도가 10초를 기다린다');
    });

    test('남은 횟수를 셀 수 있다', () {
      expect(policy.remaining, 3);
      policy.takeNextDelay();
      expect(policy.remaining, 2);
    });
  });

  // ==========================================================================
  group('실패하면 예약하고, 붙으면 접는다', () {
    test('WebRTC 실패 갈래가 예약을 건다', () {
      final String capture = _region(duo,
          'Future<void> _startInterpreterCapture(', 'Future<bool> _startInterpreterWebrtc(');
      expect(capture, contains('_scheduleInterpRetry(generation)'),
          reason: '실패하고 그냥 끝나면 상대가 나갔다 들어올 때까지 아무 일도 없다');
    });

    test('예약에 그때의 generation을 실어 보낸다', () {
      expect(duo, contains('void _scheduleInterpRetry(int generation)'));
    });

    test('두 시작 경로 모두 성공하면 예약을 접는다', () {
      // record 경로와 WebRTC 경로 둘 다. 한쪽만 접으면 늦게 울린 시계가
      // 이미 도는 통역 위에 두 번째 시작을 얹는다.
      expect(RegExp(r'_noteInterpStartSucceeded\(\)').allMatches(duo).length,
          greaterThanOrEqualTo(3),
          reason: '선언 1 + 호출 2 미만이면 한쪽 경로가 예약을 안 접는다');
      final String body =
          _region(duo, 'void _noteInterpStartSucceeded()', 'void _retryInterpreterNow()');
      expect(body, contains("_cancelInterpRetry('started')"));
      expect(body, contains('_interpRetry.reset()'));
    });

    test('마이크를 접을 때 예약도 접는다', () {
      final String stop = _region(duo,
          'Future<void> _stopInterpreterCapture(String reason)',
          'Future<void> _handleInterpreterPartnerLeft(');
      expect(stop, contains('_cancelInterpRetry(reason)'),
          reason: '닫은 통역을 예약이 다시 열려 든다');
    });

    test('상대가 나가면 횟수도 되돌린다', () {
      final String left = _region(duo,
          'Future<void> _handleInterpreterPartnerLeft(', '// ====');
      expect(left, contains('_interpRetry.reset()'),
          reason: '앞 상대에게 세 번 실패했다고 다음 상대에게 한 번도 안 걸면 안 된다');
    });

    test('dispose가 시계를 끈다', () {
      final int at = duo.indexOf('_interpPulse.dispose();');
      expect(at, greaterThan(-1));
      expect(duo.substring(at, at + 200), contains("_cancelInterpRetry('dispose')"));
    });
  });

  // ==========================================================================
  group('늦게 울린 시계는 아무것도 하지 않는다', () {
    late String timer;
    setUp(() {
      timer = _region(duo, '_interpRetryTimer = Timer(delay, () {',
          'void _cancelInterpRetry(String reason)');
    });

    test('방을 나갔거나 dispose됐으면 버린다', () {
      expect(timer, contains('if (!mounted || _isExiting)'));
      expect(timer, contains('disposed_or_exiting'));
    });

    test('generation이 바뀌었으면 버린다', () {
      expect(timer, contains('if (generation != _interpGeneration)'));
      expect(timer, contains('stale_generation'));
    });

    test('상대가 나갔으면 버린다', () {
      expect(timer, contains('if (!_isPartnerOnline)'));
      expect(timer, contains('partner_offline'));
    });

    test('이미 돌고 있으면 버린다 — 두 개가 겹치지 않는다', () {
      expect(timer, contains('if (_interpCaptureLive || _interpStarting)'));
      expect(timer, contains('already_live'));
    });

    test('살아 있는지 판단이 두 경로를 모두 본다', () {
      // WebRTC 경로는 `_interpCapture`를 채우지 않는다. 한쪽만 보면
      // 이미 도는 통역 위에 두 번째 시작을 얹는다.
      final String body =
          _region(duo, 'bool get _interpCaptureLive', 'bool get _interpShowManualRetry');
      expect(body, contains('_interpCapture != null'));
      expect(body, contains('_interpMicTap != null'));
    });

    test('시계가 울리면 자기 참조를 먼저 비운다', () {
      final int at = timer.indexOf('_interpRetryTimer = null;');
      final int guard = timer.indexOf('if (!mounted || _isExiting)');
      expect(at, greaterThan(-1));
      expect(at, lessThan(guard),
          reason: '버리는 갈래로 빠져도 시계 참조가 남으면 "다시 시도"가 안 뜬다');
    });
  });

  // ==========================================================================
  group('transport pinning을 깨지 않는다', () {
    test('firestore로 박힌 통화에서는 예약하지 않는다', () {
      final String body = _region(
          duo, 'void _scheduleInterpRetry(int generation)', '/// 예약을 접는다.');
      expect(body, contains('if (!_useInterpWebrtc)'));
      expect(body, contains('firestore_transport'));
      final int guard = body.indexOf('if (!_useInterpWebrtc)');
      final int take = body.indexOf('_interpRetry.takeNextDelay()');
      expect(guard, lessThan(take), reason: '횟수를 소비한 뒤 막으면 헛되이 센다');
    });

    test('재시도가 통로를 갈아 끼우지 않는다', () {
      // 실패했다고 record + Firestore로 넘어가면 pinning이 깨진다.
      final String body = _region(
          duo, 'void _scheduleInterpRetry(int generation)', 'void _cancelInterpRetry(');
      expect(body, isNot(contains('_interpTransport =')));
      expect(body, isNot(contains('PreparedAudioCapture')));
      final String manual = _region(
          duo, 'void _retryInterpreterNow()', '/// 🔵 [INTERP-LIVE] 상대가 방에 있으면');
      expect(manual, isNot(contains('_interpTransport =')));
    });

    test('재시도는 같은 진입점을 다시 부른다 — 두 번째 경로를 만들지 않았다', () {
      expect(duo, contains("unawaited(_startInterpreterCapture('retry_\$attempt'))"));
      expect(duo, contains("unawaited(_startInterpreterCapture('manual_retry'))"));
    });

    test('재시도가 ORIGIN 판정을 초기화하지 않는다', () {
      // `_maybeAutoStartInterpreter`를 다시 부르면 OriginLanguageSession이
      // 비워져 대화 중간에 언어 판정이 처음으로 돌아간다.
      final String sched = _region(
          duo, 'void _scheduleInterpRetry(int generation)', 'void _cancelInterpRetry(');
      final String manual = _region(
          duo, 'void _retryInterpreterNow()', '/// 🔵 [INTERP-LIVE] 상대가 방에 있으면');
      for (final String body in <String>[sched, manual]) {
        expect(body, isNot(contains('_maybeAutoStartInterpreter(')),
            reason: 'OriginLanguageSession.begin()이 다시 돌아 판정이 초기화된다');
        expect(body, isNot(contains('OriginLanguageSession')));
      }
    });
  });

  // ==========================================================================
  group('수동 다시 시도', () {
    test('자동이 다 끝났을 때만 보인다', () {
      final String body = _region(
          duo, 'bool get _interpShowManualRetry', 'void _pinInterpTransport(');
      expect(body, contains('_interpStartFailed'));
      expect(body, contains('_interpRetryTimer == null'),
          reason: '시계가 아직 돌고 있으면 누를 것이 없다');
      expect(body, contains('_isPartnerOnline'));
      expect(body, contains('!_isExiting'));
      expect(body, contains('_useInterpWebrtc'),
          reason: 'firestore 통화에는 이 버튼이 뜨면 안 된다');
      expect(body, contains('!_interpCaptureLive'));
      expect(body, contains('!_interpStarting'));
    });

    test('누르면 횟수와 예약과 실패 표시를 되돌린다', () {
      final String body = _region(
          duo, 'void _retryInterpreterNow()', '/// 🔵 [INTERP-LIVE] 상대가 방에 있으면');
      expect(body, contains("_cancelInterpRetry('manual')"));
      expect(body, contains('_interpRetry.reset()'));
      expect(body, contains('_interpStartFailed = false'));
    });

    test('보일 조건을 그대로 다시 확인하고 시작한다', () {
      final String body = _region(
          duo, 'void _retryInterpreterNow()', '/// 🔵 [INTERP-LIVE] 상대가 방에 있으면');
      expect(body, contains('if (!_interpShowManualRetry) return;'),
          reason: '버튼이 사라진 뒤 도착한 탭이 나간 방을 다시 열 수 있다');
    });

    test('화면에 그 조건으로만 붙는다', () {
      expect(duo, contains('if (_interpShowManualRetry) ...['));
      expect(duo, contains('onPressed: _retryInterpreterNow'));
    });

    test('예약이 도는 동안에는 문구가 "다시 연결하는 중"이다', () {
      final String label =
          _region(duo, 'String _interpStatusLabel()', 'Widget _buildInterpreterMicIndicator');
      expect(label, contains('_interpRetryTimer != null'));
      expect(label, contains('다시 연결하는 중'));
      expect(label, contains('마이크를 열지 못했습니다'));
    });
  });
}
