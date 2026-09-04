// 🎛️ [GUM-CONSTRAINTS] getUserMedia 제약이 네이티브까지 실제로 간다
//
// 예전 호출부는 이랬다:
//   'audio': {'echoCancellation': true, 'noiseSuppression': true,
//             'autoGainControl': true}
//
// 읽으면 표준을 그대로 요청하는 것처럼 보이는데 **한 글자도 적용되지 않았다.**
// flutter_webrtc 1.5.2 경로가 그렇다:
//
//   GetUserMediaImpl.getUserAudio
//     · `audio`가 Boolean이면  → addDefaultAudioConstraints() 로 기본 제약을 붙임
//     · Boolean이 아니면       → parseMediaConstraints(map)
//   MediaConstraintsUtils.parseMediaConstraints
//     · `"mandatory"`(Map)와 `"optional"`(Array) **두 열쇠만** 읽는다
//     · 평평한 맵에는 둘 다 없다 → 빈 MediaConstraints
//   → createAudioSource(빈 제약)
//
// 즉 맵을 넘긴 탓에 googEchoCancellation·googNoiseSuppression·
// googEchoCancellation2·googDAEchoCancellation을 **하나도 못 받았다.**
// 적게 요청하려고 명시한 셈이었다.
//
// 🚫 이 제약은 **상대에게 가는 소리**에만 닿는다. 전사가 쓰는 PCM은 MicTap이
//   소프트웨어 APM 앞에서 갈라 가므로 무관하다 — 원거리 음성이 STT에 들어오는
//   것과 이 수정은 별개의 건이다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _call = 'lib/custom_code/services/duo_webrtc_call.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// [start]부터 [end] 직전까지의 소스 조각.
String _region(String src, String start, String end) {
  final int a = src.indexOf(start);
  if (a < 0) throw StateError('없는 자리: $start');
  final int b = src.indexOf(end, a + 1);
  if (b < a) throw StateError('없는 자리: $end');
  return src.substring(a, b);
}

void main() {
  final String call = _read(_call);

  group('제약은 플러그인이 알아듣는 모양으로 넘긴다', () {
    test("'audio': true 로 넘긴다", () {
      expect(call, contains("'audio': true,"),
          reason: 'Boolean이라야 addDefaultAudioConstraints()가 돈다');
    });

    test('평평한 맵을 다시 넘기지 않는다', () {
      final String body = _region(
          call, 'navigator.mediaDevices.getUserMedia(', 'catch (e) {');
      for (final String dropped in <String>[
        "'echoCancellation'",
        "'noiseSuppression'",
        "'autoGainControl'",
      ]) {
        expect(body, isNot(contains(dropped)),
            reason: '$dropped 는 평평한 맵에서 조용히 버려진다');
      }
    });

    test('되돌릴 때의 함정을 코드 옆에 적어 뒀다', () {
      // deviceId가 필요해지면 맵으로 돌아가야 하는데, 그때 이 함정을
      // 모르면 같은 버그를 그대로 다시 만든다.
      expect(call, contains("'mandatory'"),
          reason: '맵으로 되돌릴 때 필요한 모양이 주석에 없다');
      expect(call, contains('parseMediaConstraints'));
      expect(call, contains('addDefaultAudioConstraints'));
    });

    test('이 값이 전사 경로와 무관하다는 사실을 적어 뒀다', () {
      expect(call, contains('APM **앞에서** 갈라 가므로'),
          reason: '다음 사람이 이 값을 원거리 STT 문제의 손잡이로 오해한다');
    });
  });

  group('통화 자체는 건드리지 않았다', () {
    test('마이크는 여전히 연다', () {
      expect(call, contains('await navigator.mediaDevices.getUserMedia('));
      expect(call, contains('_localAudioTrack = tracks.first;'));
    });

    test('통역은 여전히 원음을 안 보낸다', () {
      // 트랙은 얹되(녹음을 시작시키려고) 꺼 둔다. 자세한 근거는
      // `duo_interp_webrtc_test.dart`.
      expect(call, contains('await pc.addTrack(_localAudioTrack!, stream);'));
      expect(call, contains('if (!sendAudio) {'));
      expect(call, contains('_localAudioTrack!.enabled = false;'));
    });

    test('통화 모드 설정은 마이크보다 먼저다', () {
      final int mode = call.indexOf('AndroidAudioConfiguration.communication');
      final int gum = call.indexOf('navigator.mediaDevices.getUserMedia(');
      expect(mode, greaterThan(-1));
      expect(gum, greaterThan(mode),
          reason: '마이크를 먼저 열면 AEC가 참조를 못 잡는다');
    });
  });
}
