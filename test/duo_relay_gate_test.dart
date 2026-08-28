import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_relay_gate.dart';

/// 24kHz·16bit 기준 한 프레임(80ms = 3840바이트)을 만든다.
/// [amplitude]는 0.0~1.0. 0이면 완전한 무음이다.
Uint8List frame(double amplitude, {int ms = 80}) {
  const int bytesPerMs = 48; // 24000Hz * 2byte / 1000
  final int samples = ms * bytesPerMs ~/ 2;
  final bytes = Uint8List(samples * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < samples; i++) {
    // 사인파 한 줄. RMS는 진폭/√2가 된다.
    final double v = math.sin(i * 0.05) * amplitude;
    view.setInt16(i * 2, (v * 32767).round(), Endian.little);
  }
  return bytes;
}

int totalBytes(List<Uint8List> frames) =>
    frames.fold(0, (sum, f) => sum + f.lengthInBytes);

void main() {
  const int bytesPerMs = 48;

  group('duoFrameRms', () {
    test('무음은 0이다', () {
      expect(duoFrameRms(frame(0.0)), 0.0);
    });

    test('사인파의 RMS는 진폭의 약 0.707배다', () {
      expect(duoFrameRms(frame(0.5)), closeTo(0.5 / math.sqrt2, 0.02));
    });

    test('빈 프레임도 터지지 않는다', () {
      expect(duoFrameRms(Uint8List(0)), 0.0);
    });
  });

  group('DuoRelayGate', () {
    DuoRelayGate build({double threshold = 0.01}) => DuoRelayGate(
          threshold: threshold,
          bytesPerMs: bytesPerMs,
        );

    test('조용한 동안에는 한 조각도 안 나간다 — 되먹임 고리를 끊는 자리', () {
      final gate = build();
      for (var i = 0; i < 20; i++) {
        expect(gate.accept(frame(0.0)), isEmpty);
      }
      expect(gate.isOpen, isFalse);
      expect(gate.heldBytes, greaterThan(0));
    });

    test('말이 시작되면 물고 있던 앞소리가 함께 나간다 — 첫 음절을 지킨다', () {
      final gate = build();
      // 500ms 앞소리 예산이면 80ms 프레임 6개가 남는다.
      for (var i = 0; i < 10; i++) {
        gate.accept(frame(0.0));
      }
      final out = gate.accept(frame(0.4));
      expect(gate.isOpen, isTrue);
      // 방금 프레임 하나만 나가면 앞이 잘린 것이다.
      expect(out.length, greaterThan(1));
      expect(totalBytes(out),
          lessThanOrEqualTo((kDuoRelayGatePrefixMs + 80) * bytesPerMs));
    });

    test('열린 뒤에는 프레임이 그대로 흐른다', () {
      final gate = build();
      gate.accept(frame(0.4));
      for (var i = 0; i < 5; i++) {
        expect(gate.accept(frame(0.4)).length, 1);
      }
    });

    test('말을 멈춰도 여운 동안은 계속 보낸다 — 문장 사이에서 안 끊긴다', () {
      final gate = build();
      gate.accept(frame(0.4));
      // 800ms 여운 = 80ms 프레임 10개. 그 안에서는 무음도 실려 나간다.
      for (var i = 0; i < 9; i++) {
        expect(gate.accept(frame(0.0)).length, 1,
            reason: '여운 ${(i + 1) * 80}ms에서 끊겼다');
      }
      expect(gate.isOpen, isTrue);
    });

    test('여운이 지나면 닫히고 다시 조용해진다', () {
      final gate = build();
      gate.accept(frame(0.4));
      for (var i = 0; i < 10; i++) {
        gate.accept(frame(0.0));
      }
      expect(gate.isOpen, isFalse);
      expect(gate.accept(frame(0.0)), isEmpty);
    });

    test('문턱 아래 소리는 열지 못한다 — 벽 너머로 새어 든 상대 목소리', () {
      final gate = build(threshold: 0.05);
      for (var i = 0; i < 10; i++) {
        expect(gate.accept(frame(0.01)), isEmpty);
      }
      expect(gate.isOpen, isFalse);
    });

    test('열고 닫힐 때만 알린다', () {
      final events = <bool>[];
      final gate = DuoRelayGate(
        threshold: 0.01,
        bytesPerMs: bytesPerMs,
        onGateChanged: (open, _) => events.add(open),
      );
      gate.accept(frame(0.4));
      gate.accept(frame(0.4));
      for (var i = 0; i < 10; i++) {
        gate.accept(frame(0.0));
      }
      expect(events, <bool>[true, false]);
    });

    test('닫혀 있는 동안 본 가장 큰 소리를 기억한다 — 울림의 정체를 가르는 값', () {
      final gate = build(threshold: 0.05);
      gate.accept(frame(0.0));
      gate.accept(frame(0.02)); // 문턱 아래지만 무음은 아니다
      gate.accept(frame(0.01));
      expect(gate.isOpen, isFalse);
      expect(gate.peakClosedRms, closeTo(0.02 / math.sqrt2, 0.002));
    });

    test('문턱 0.004에서도 무음은 문을 못 연다 — 낮춰도 막는 힘은 그대로다', () {
      final gate = build(threshold: 0.004);
      for (var i = 0; i < 20; i++) {
        expect(gate.accept(frame(0.0)), isEmpty);
      }
      // 실기기에서 가장 작았던 발화(RMS 0.0130)는 열어야 한다.
      expect(gate.accept(frame(0.0130 * math.sqrt2)), isNotEmpty);
    });

    test('reset이 앞소리까지 버린다 — 지난 통화 소리가 새 통화로 새면 안 된다', () {
      final gate = build();
      for (var i = 0; i < 10; i++) {
        gate.accept(frame(0.0));
      }
      gate.reset();
      expect(gate.heldBytes, 0);
      expect(gate.accept(frame(0.4)).length, 1);
    });
  });
}
