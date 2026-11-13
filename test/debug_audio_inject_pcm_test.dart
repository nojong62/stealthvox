import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/debug_audio_inject.dart';

Uint8List _wav16k(int samples, double hz) {
  const rate = 16000;
  final data = ByteData(44 + samples * 2);
  void ascii(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  ascii(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    final v = (math.sin(2 * math.pi * hz * i / rate) * 12000).round();
    data.setInt16(44 + i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  test('16kHz WAV becomes 24kHz mono PCM16 of the same duration', () async {
    final dir = await Directory.systemTemp.createTemp('inject_pcm');
    final f = File('${dir.path}/t.wav');
    await f.writeAsBytes(_wav16k(16000, 440)); // 1.0 s
    final pcm = await readDebugWavAsPcm24k(f.path);
    expect(pcm, isNotNull);
    expect(pcm!.length, 24000 * 2); // 1.0 s at 24kHz, 2 bytes each
    final b = ByteData.sublistView(pcm);
    var peak = 0;
    for (var i = 0; i < pcm.length ~/ 2; i++) {
      peak = math.max(peak, b.getInt16(i * 2, Endian.little).abs());
    }
    expect(peak, greaterThan(10000)); // signal survived, not silence
    await dir.delete(recursive: true);
  });
}
