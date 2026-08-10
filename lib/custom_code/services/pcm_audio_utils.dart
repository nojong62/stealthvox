// 🎚️ [PCM-UTILS] PCM16 ↔ WAV 컨테이너 유틸.
//   TTS 어댑터(히스토리 저장용 WAV 포장)와 재전사 서비스(gpt-4o-mini-transcribe
//   업로드용 WAV 포장)가 공유한다. 순수 함수만 둔다 — 상태/플랫폼 의존 금지.

import 'dart:typed_data';

/// 🎚️ 유저 음성 입력 파이프라인 전체가 쓰는 단 하나의 샘플레이트.
///
/// OpenAI Realtime transcription의 입력 PCM이 24kHz 고정이라 여기에 맞춘다.
/// 마이크 녹음(RecordConfig) · Deepgram URI의 `sample_rate` · 폴백
/// gpt-4o-transcribe의 WAV 헤더가 **반드시 같은 값**이어야 한다. 한 곳만
/// 어긋나면 소리가 빨라지거나 느려져 전사문이 통째로 망가지는데, 에러가 아니라
/// "이상한 문장"으로 나와서 원인을 찾기 어렵다.
const int kStealthVoxSttSampleRate = 24000;

/// PCM16 mono 기준 1ms당 바이트 수. 과금 로그·버퍼 상한 계산이 쓴다.
const int kStealthVoxSttBytesPerMs = kStealthVoxSttSampleRate * 2 ~/ 1000;

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
int pcm16DurationMs(int byteLength,
    {required int sampleRate, int channels = 1}) {
  final int bytesPerSecond = sampleRate * channels * 2;
  if (bytesPerSecond <= 0) return 0;
  return (byteLength * 1000 / bytesPerSecond).round();
}

/// PCM16 mono 앞부분의 대기 무음을 제거한다.
///
/// 짧은 프레임의 평균 절댓값과 피크를 함께 보므로 작은 마이크의 첫 자음은
/// 놓치지 않으면서 디지털 무음/방 대기음은 건너뛴다. 연속 프레임 조건과
/// [paddingMs]만큼의 앞 여유를 둬 발화 시작이 잘리지 않게 한다.
Uint8List trimLeadingSilencePcm16(
  Uint8List pcm, {
  required int sampleRate,
  int frameMs = 20,
  int consecutiveFrames = 2,
  int meanAbsThreshold = 180,
  int peakThreshold = 1200,
  int paddingMs = 300,
}) {
  if (pcm.length < 2 || sampleRate <= 0) return pcm;

  final int alignedLength = pcm.length - (pcm.length.isOdd ? 1 : 0);
  final int samplesPerFrame = (sampleRate * frameMs ~/ 1000).clamp(1, 1 << 20);
  final int bytesPerFrame = samplesPerFrame * 2;
  final data = ByteData.sublistView(pcm, 0, alignedLength);

  int consecutive = 0;
  int candidateStartByte = 0;
  for (int frameStart = 0;
      frameStart + bytesPerFrame <= alignedLength;
      frameStart += bytesPerFrame) {
    int absoluteSum = 0;
    int peak = 0;
    for (int offset = frameStart;
        offset < frameStart + bytesPerFrame;
        offset += 2) {
      final int sample = data.getInt16(offset, Endian.little);
      final int absolute = sample < 0 ? -sample : sample;
      absoluteSum += absolute;
      if (absolute > peak) peak = absolute;
    }
    final int meanAbsolute = absoluteSum ~/ samplesPerFrame;
    final bool hasVoice =
        meanAbsolute >= meanAbsThreshold || peak >= peakThreshold;
    if (hasVoice) {
      if (consecutive == 0) candidateStartByte = frameStart;
      consecutive++;
      if (consecutive >= consecutiveFrames) {
        final int paddingBytes = sampleRate * 2 * paddingMs ~/ 1000;
        final int trimStart =
            (candidateStartByte - paddingBytes).clamp(0, alignedLength).toInt();
        if (trimStart <= 0) return Uint8List.sublistView(pcm, 0, alignedLength);
        return Uint8List.sublistView(pcm, trimStart, alignedLength);
      }
    } else {
      consecutive = 0;
    }
  }

  // 확실한 발화를 찾지 못했다면 원본을 유지한다. 잘못된 과도 트림보다 안전하다.
  return Uint8List.sublistView(pcm, 0, alignedLength);
}
