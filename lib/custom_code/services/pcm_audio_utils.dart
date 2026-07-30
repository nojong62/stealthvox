// 🎚️ [PCM-UTILS] PCM16 ↔ WAV 컨테이너 유틸.
//   TTS 어댑터(히스토리 저장용 WAV 포장)와 재전사 서비스(gpt-4o-mini-transcribe
//   업로드용 WAV 포장)가 공유한다. 순수 함수만 둔다 — 상태/플랫폼 의존 금지.

import 'dart:typed_data';

/// PCM16(LE, interleaved) 원시 바이트를 WAV 컨테이너로 감싼다.
Uint8List pcm16ToWav(
  Uint8List pcm, {
  required int sampleRate,
  int channels = 1,
}) {
  const int bitsPerSample = 16;
  final int byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
  final int blockAlign = channels * (bitsPerSample ~/ 8);
  final int dataSize = pcm.length;
  final int chunkSize = 36 + dataSize;

  final header = ByteData(44);
  // RIFF chunk
  header.setUint8(0, 0x52); // 'R'
  header.setUint8(1, 0x49); // 'I'
  header.setUint8(2, 0x46); // 'F'
  header.setUint8(3, 0x46); // 'F'
  header.setUint32(4, chunkSize, Endian.little);
  header.setUint8(8, 0x57); // 'W'
  header.setUint8(9, 0x41); // 'A'
  header.setUint8(10, 0x56); // 'V'
  header.setUint8(11, 0x45); // 'E'
  // fmt sub-chunk
  header.setUint8(12, 0x66); // 'f'
  header.setUint8(13, 0x6D); // 'm'
  header.setUint8(14, 0x74); // 't'
  header.setUint8(15, 0x20); // ' '
  header.setUint32(16, 16, Endian.little); // PCM fmt chunk size
  header.setUint16(20, 1, Endian.little); // audio format = PCM
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  // data sub-chunk
  header.setUint8(36, 0x64); // 'd'
  header.setUint8(37, 0x61); // 'a'
  header.setUint8(38, 0x74); // 't'
  header.setUint8(39, 0x61); // 'a'
  header.setUint32(40, dataSize, Endian.little);

  final out = Uint8List(44 + dataSize);
  out.setRange(0, 44, header.buffer.asUint8List());
  out.setRange(44, 44 + dataSize, pcm);
  return out;
}

/// PCM16 바이트 길이 → 재생 시간(ms).
int pcm16DurationMs(int byteLength, {required int sampleRate, int channels = 1}) {
  final int bytesPerSecond = sampleRate * channels * 2;
  if (bytesPerSecond <= 0) return 0;
  return (byteLength * 1000 / bytesPerSecond).round();
}
