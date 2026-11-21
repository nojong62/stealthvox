import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_checkpoint_chime.dart';

void main() {
  test('the chime is a short, audible two-tone sound', () {
    final pcm = buildDuoChimePcm();
    final ms = pcm.lengthInBytes ~/ 2 * 1000 ~/ 24000;
    // 0.28s + 0.04s + 0.42s
    expect(ms, inInclusiveRange(700, 760));
    final view = ByteData.sublistView(pcm);
    var peak = 0;
    for (var i = 0; i < pcm.lengthInBytes ~/ 2; i++) {
      final v = view.getInt16(i * 2, Endian.little).abs();
      if (v > peak) peak = v;
    }
    // 소리가 들릴 만큼 크고(>5000), 찌그러지지 않을 만큼 작다(<24000).
    expect(peak, inInclusiveRange(5000, 24000));
  });

  test('the chime wav has a valid header and the same sample count', () {
    final wav = buildDuoChimeWav();
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(wav.lengthInBytes, buildDuoChimePcm().lengthInBytes + 44);
  });

  test('the chime ends softly (no click at the tail)', () {
    final pcm = buildDuoChimePcm();
    final view = ByteData.sublistView(pcm);
    final last = view.getInt16(pcm.lengthInBytes - 2, Endian.little).abs();
    expect(last, lessThan(1500));
  });

  test('checkpoint cadence is ten minutes and the mute covers the sound', () {
    expect(kDuoCheckpointEvery, const Duration(minutes: 10));
    expect(kDuoChimeMuteMs, greaterThan(750)); // 소리 길이(약 0.74초)보다 길다
  });
}
