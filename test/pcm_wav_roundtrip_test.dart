// 🎚️ [PCM-WAV] 감쌌다 벗기면 그대로인가.
//
// 샘플레이트가 한 곳만 어긋나도 소리가 빨라지거나 느려지는데, 에러가 아니라
// **"이상한 문장"**으로 나와서 원인을 찾기 어렵다. 창고가 파일에 WAV로 쓰고
// 읽을 때 벗기는 구조라, 이 왕복이 어긋나면 복원이 엉뚱한 소리를 근거로
// 원문을 고치게 된다.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/pcm_audio_utils.dart';

Uint8List ramp(int bytes) {
  final out = Uint8List(bytes);
  for (var i = 0; i < bytes; i++) {
    out[i] = (i * 13 + 7) & 0xFF;
  }
  return out;
}

void main() {
  group('왕복', () {
    test('감쌌다 벗기면 원본과 같다', () {
      final pcm = ramp(4800);
      final wav = pcm16ToWav(pcm, sampleRate: kStealthVoxSttSampleRate);
      expect(wavToPcm16(wav), orderedEquals(pcm));
    });

    test('헤더에 24kHz가 박힌다', () {
      final wav = pcm16ToWav(ramp(960), sampleRate: kStealthVoxSttSampleRate);
      final view = ByteData.sublistView(wav);
      expect(view.getUint32(24, Endian.little), 24000);
      expect(view.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(view.getUint16(34, Endian.little), 16, reason: '16bit');
    });

    test('빈 PCM은 벗길 것이 없다', () {
      final wav = pcm16ToWav(Uint8List(0), sampleRate: kStealthVoxSttSampleRate);
      expect(wavToPcm16(wav), isNull);
    });
  });

  group('망가진 입력', () {
    test('WAV가 아니면 null이다', () {
      expect(wavToPcm16(Uint8List.fromList(List<int>.filled(100, 0x41))), isNull);
    });

    test('너무 짧으면 null이다', () {
      expect(wavToPcm16(Uint8List(8)), isNull);
      expect(wavToPcm16(Uint8List(0)), isNull);
    });

    test('RIFF는 맞지만 WAVE가 아니면 null이다', () {
      final wav = pcm16ToWav(ramp(480), sampleRate: kStealthVoxSttSampleRate);
      wav[9] = 0x58; // 'A' → 'X'
      expect(wavToPcm16(wav), isNull);
    });

    test('data 청크가 없으면 null이다', () {
      final wav = pcm16ToWav(ramp(480), sampleRate: kStealthVoxSttSampleRate);
      wav[36] = 0x58; // 'd' → 'X'
      expect(wavToPcm16(wav), isNull);
    });

    test('중간에 잘린 파일은 남은 만큼 살린다', () {
      // 강제종료·디스크 가득으로 반만 쓰인 파일. 앞부분은 진짜 소리다.
      final full = pcm16ToWav(ramp(4800), sampleRate: kStealthVoxSttSampleRate);
      final cut = Uint8List.sublistView(full, 0, 44 + 2000);

      final back = wavToPcm16(cut);
      expect(back, isNotNull);
      expect(back!.lengthInBytes, 2000);
      expect(back, orderedEquals(ramp(4800).sublist(0, 2000)));
    });

    test('홀수로 잘리면 반쪽 샘플은 버린다', () {
      final full = pcm16ToWav(ramp(480), sampleRate: kStealthVoxSttSampleRate);
      final cut = Uint8List.sublistView(full, 0, 44 + 101);

      final back = wavToPcm16(cut);
      expect(back!.lengthInBytes, 100, reason: '16bit 샘플은 2바이트 단위다');
    });

    test('헤더만 있고 데이터가 없으면 null이다', () {
      final full = pcm16ToWav(ramp(480), sampleRate: kStealthVoxSttSampleRate);
      expect(wavToPcm16(Uint8List.sublistView(full, 0, 44)), isNull);
    });
  });

  test('길이 → 재생 시간', () {
    // 24kHz 16bit mono = 48 bytes/ms
    expect(pcm16DurationMs(4800, sampleRate: kStealthVoxSttSampleRate), 100);
    expect(pcm16DurationMs(48000, sampleRate: kStealthVoxSttSampleRate), 1000);
    expect(pcm16DurationMs(0, sampleRate: kStealthVoxSttSampleRate), 0);
  });
}
