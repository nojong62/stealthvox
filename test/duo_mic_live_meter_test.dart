// 🩺 [DUO-MIC-HEALTH] 마이크 경합의 지문을 읽어 내는 계측기 시험.
//
// 이 계측기가 있는 이유는 하나다. AudioRecord 두 개가 경합하면 Android는
// **오류를 내지 않고 한쪽에 무음 버퍼만 계속 준다.** 프레임 수만 세면
// "잘 돌고 있다"로 보이고 글자만 안 나온다. 그 상태를 숫자로 가른다.
//
//   frames 있음 + allZero == frames  → 마이크 경합 (조각은 오는데 전부 0)
//   frames 있음 + voiced == 0        → 소리를 못 받고 있다
//   frames 있음 + voiced > 0         → 정상
//
// ⚠️ 이 값은 **판정에 쓰지 않는다.** 전사 게이트는 DuoUtteranceRmsMeter가
//   그대로 맡는다. 여기는 관찰만 한다.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_direct_audio.dart';

/// PCM16 LE mono 한 조각. [amplitude]는 0.0~1.0.
Uint8List _tone(int samples, double amplitude) {
  final bytes = Uint8List(samples * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < samples; i++) {
    final double v = math.sin(2 * math.pi * i / 32) * amplitude;
    view.setInt16(i * 2, (v * 32767).round(), Endian.little);
  }
  return bytes;
}

Uint8List _silence(int samples) => Uint8List(samples * 2);

void main() {
  group('무음 버퍼 — 마이크 경합의 지문', () {
    test('전부 0인 조각은 allZero로 세고 voiced로 세지 않는다', () {
      final meter = DuoMicLiveMeter(speakerRole: 'HOST', logEveryFrames: 0);
      for (var i = 0; i < 10; i++) {
        meter.addPcm(_silence(480));
      }
      expect(meter.lifetimeFrames, 10);
      expect(meter.lifetimeAllZeroFrames, 10);
      expect(meter.lifetimeVoicedFrames, 0);
      // 조각은 왔는데 목소리가 한 번도 없었다 — 이게 경합의 모습이다.
      expect(meter.neverHeardVoice, isTrue);
    });

    test('요약 한 줄에 경고가 드러난다 — 실기기 로그에서 이걸 찾는다', () {
      final meter = DuoMicLiveMeter(speakerRole: 'GUEST', logEveryFrames: 0);
      for (var i = 0; i < 5; i++) {
        meter.addPcm(_silence(480));
      }
      final summary = meter.summary();
      expect(summary, contains('allZeroFrames=5'));
      expect(summary, contains('통화 내내 목소리 없음'));
    });
  });

  group('정상 마이크', () {
    test('사람 목소리 크기의 조각은 voiced로 센다', () {
      final meter = DuoMicLiveMeter(speakerRole: 'HOST', logEveryFrames: 0);
      for (var i = 0; i < 10; i++) {
        meter.addPcm(_tone(480, 0.2)); // 약 -17 dBFS
      }
      expect(meter.lifetimeFrames, 10);
      expect(meter.lifetimeVoicedFrames, 10);
      expect(meter.lifetimeAllZeroFrames, 0);
      expect(meter.neverHeardVoice, isFalse);
      expect(meter.summary(), contains('ok'));
    });

    test('아주 조용한 소리도 관찰은 한다 — 게이트 문턱보다 낮게 본다', () {
      // 게이트는 -42dBFS에서 버리지만, 관찰용 문턱은 -50이라 여기 잡힌다.
      // "조용해서 버려졌다"와 "아예 안 들어왔다"를 가르기 위한 여유다.
      final meter = DuoMicLiveMeter(speakerRole: 'HOST', logEveryFrames: 0);
      meter.addPcm(_tone(480, 0.005)); // 약 -49 dBFS
      expect(meter.lifetimeVoicedFrames, 1);
      expect(meter.neverHeardVoice, isFalse);
    });
  });

  group('셈의 규칙', () {
    test('빈 조각은 아무것도 세지 않는다', () {
      final meter = DuoMicLiveMeter(speakerRole: 'HOST', logEveryFrames: 0);
      meter.addPcm(Uint8List(0));
      expect(meter.lifetimeFrames, 0);
      // 조각이 아예 없으면 "목소리 없음"이라고 단정하지 않는다.
      expect(meter.neverHeardVoice, isFalse);
    });

    test('주기 로그가 켜져 있어도 누적값은 통화 전체를 센다', () {
      final lines = <String>[];
      final meter = DuoMicLiveMeter(
        speakerRole: 'HOST',
        logEveryFrames: 3,
        onLog: (tag, msg) => lines.add(msg),
      );
      for (var i = 0; i < 9; i++) {
        meter.addPcm(_tone(480, 0.2));
      }
      expect(lines.length, 3); // 3조각마다 한 줄
      expect(meter.lifetimeFrames, 9); // 누적은 리셋되지 않는다
      expect(meter.lifetimeVoicedFrames, 9);
    });

    test('로그에 오디오 내용은 실리지 않는다 — 세는 값과 dBFS뿐', () {
      final lines = <String>[];
      final meter = DuoMicLiveMeter(
        speakerRole: 'HOST',
        logEveryFrames: 1,
        onLog: (tag, msg) => lines.add(msg),
      );
      meter.addPcm(_tone(480, 0.2));
      final line = lines.single;
      for (final field in <String>[
        'speaker=',
        'frames=',
        'avgDbfs=',
        'voicedFrames=',
        'allZeroFrames=',
      ]) {
        expect(line, contains(field));
      }
      // 샘플 값이나 바이트 배열이 새어 나가지 않는다.
      expect(line, isNot(contains('[')));
    });
  });
}
