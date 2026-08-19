// 🌬️ [BREATH-ANALYZER] PCM16에서 실제 호흡 경계를 찾는다.
//
//   **입력은 PCM 바이트뿐이다.** 텍스트를 인자로 받지 않는다 — 받을 수 있게
//   두면 언젠가 문법으로 자르는 코드가 들어온다. 단어 수·쉼표·접속사는 이
//   파일 어디에도 없다.
//
//   순수 함수만 둔다. UI·AudioPlayer·플랫폼 의존이 없어서 합성 PCM으로
//   단위 테스트가 된다(`test/breath_analyzer_test.dart`).
//
//   프레임 판정식은 `pcm_audio_utils.dart`의 [trimLeadingSilencePcm16]에서
//   가져왔다. 그 파일은 Duo·Circle Talk·Scenario Talk·Step Expand·전사가
//   함께 쓰므로 **읽기만 하고 고치지 않는다.**

import 'dart:math' as math;
import 'dart:typed_data';

import 'breath_segment.dart';
import 'pcm_audio_utils.dart';

/// 무음 한 구간. 관리자 화면이 "pause 190ms"를 표시하는 데 쓴다.
class SilenceRun {
  const SilenceRun({required this.startMs, required this.endMs});

  final int startMs;
  final int endMs;

  int get durationMs => endMs - startMs;
}

/// 분석 결과 한 벌.
class BreathAnalysis {
  const BreathAnalysis({
    required this.totalMs,
    required this.segments,
    required this.gaps,
  });

  /// 원본 PCM 전체 길이.
  final int totalMs;

  /// 호흡 구간들. 서로 겹치지 않고 [0, totalMs] 안에 있다.
  final List<BreathSegment> segments;

  /// segment 사이의 **실제 무음**(padding 적용 전 speech↔speech 간격).
  /// 길이는 항상 `segments.length - 1`이다.
  final List<SilenceRun> gaps;

  bool get isEmpty => segments.isEmpty;

  static const BreathAnalysis empty =
      BreathAnalysis(totalMs: 0, segments: <BreathSegment>[], gaps: <SilenceRun>[]);
}

/// 분석 파라미터.
///
/// 🚧 **[minSilenceMs]/[minBreathMs]/[padMs]의 기본값은 Phase 1 tuning
/// defaults다 — 최종 Breath 정책으로 확정된 값이 아니다.** 관리자가 Voice
/// Lab에서 실제 Smooth Jazz PCM을 듣고 정한다.
///
/// 진폭 임계값 둘은 노출하지 않는다. `trimLeadingSilencePcm16`이 실사용에서
/// 검증한 값을 그대로 쓴다 — 여기까지 손대기 시작하면 변수가 다섯 개가 되어
/// 무엇 때문에 좋아졌는지 알 수 없게 된다.
class BreathAnalysisConfig {
  const BreathAnalysisConfig({
    this.minSilenceMs = 180,
    this.minBreathMs = 900,
    this.padMs = 80,
    this.frameMs = 20,
    this.meanAbsThreshold = 180,
    this.peakThreshold = 1200,
    this.sampleRate = kStealthVoxSttSampleRate,
  });

  /// 이보다 짧은 무음은 호흡 경계로 보지 않고 발성의 일부로 흡수한다.
  final int minSilenceMs;

  /// 이보다 짧은 호흡은 이웃과 합친다.
  final int minBreathMs;

  /// 경계 앞뒤로 남길 여유. 음절이 잘리는 것을 막는다.
  final int padMs;

  final int frameMs;
  final int meanAbsThreshold;
  final int peakThreshold;
  final int sampleRate;

  BreathAnalysisConfig copyWith({
    int? minSilenceMs,
    int? minBreathMs,
    int? padMs,
  }) =>
      BreathAnalysisConfig(
        minSilenceMs: minSilenceMs ?? this.minSilenceMs,
        minBreathMs: minBreathMs ?? this.minBreathMs,
        padMs: padMs ?? this.padMs,
        frameMs: frameMs,
        meanAbsThreshold: meanAbsThreshold,
        peakThreshold: peakThreshold,
        sampleRate: sampleRate,
      );
}

/// PCM16 mono 전체를 프레임 단위로 훑어 **발성 프레임 여부**를 낸다.
///
/// 판정식은 [trimLeadingSilencePcm16]과 같다: 프레임 평균 절댓값과 피크를
/// 함께 봐서, 작은 소리의 첫 자음은 놓치지 않으면서 디지털 무음은 거른다.
List<bool> voicedFrames(Uint8List pcm, BreathAnalysisConfig cfg) {
  final int alignedLength = pcm.length - (pcm.length.isOdd ? 1 : 0);
  if (alignedLength < 2 || cfg.sampleRate <= 0) return const <bool>[];

  final int samplesPerFrame =
      (cfg.sampleRate * cfg.frameMs ~/ 1000).clamp(1, 1 << 20);
  final int bytesPerFrame = samplesPerFrame * 2;
  final data = ByteData.sublistView(pcm, 0, alignedLength);

  final frames = <bool>[];
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
    frames.add(
        meanAbsolute >= cfg.meanAbsThreshold || peak >= cfg.peakThreshold);
  }
  return frames;
}

/// PCM16 mono → 호흡 구간.
///
/// 흐름:
///   ① 프레임 스캔 → 발성/무음
///   ② 발성 run 추출
///   ③ [BreathAnalysisConfig.minSilenceMs]보다 짧은 무음은 흡수
///   ④ [BreathAnalysisConfig.minBreathMs]보다 짧은 구간은 이웃과 merge
///   ⑤ padding 적용(무음을 나눠 갖는다 — 겹치지 않는다)
///   ⑥ [0, totalMs]로 clamp
BreathAnalysis analyzeBreaths(Uint8List pcm, BreathAnalysisConfig cfg) {
  final int alignedLength = pcm.length - (pcm.length.isOdd ? 1 : 0);
  if (alignedLength < 2) return BreathAnalysis.empty;

  final int totalMs =
      pcm16DurationMs(alignedLength, sampleRate: cfg.sampleRate);
  final frames = voicedFrames(pcm, cfg);
  if (frames.isEmpty) {
    return BreathAnalysis(
        totalMs: totalMs, segments: const <BreathSegment>[], gaps: const []);
  }

  // ② 발성 run. 프레임 i는 [i*frameMs, (i+1)*frameMs)를 덮는다.
  final runs = <List<int>>[]; // [startMs, endMs]
  int? runStartFrame;
  for (int i = 0; i < frames.length; i++) {
    if (frames[i]) {
      runStartFrame ??= i;
    } else if (runStartFrame != null) {
      runs.add(<int>[runStartFrame * cfg.frameMs, i * cfg.frameMs]);
      runStartFrame = null;
    }
  }
  if (runStartFrame != null) {
    runs.add(<int>[runStartFrame * cfg.frameMs, frames.length * cfg.frameMs]);
  }
  if (runs.isEmpty) {
    return BreathAnalysis(
        totalMs: totalMs, segments: const <BreathSegment>[], gaps: const []);
  }

  // ③ 짧은 무음 흡수. 음소 사이의 미세한 gap을 호흡으로 오인하지 않는다.
  final merged = <List<int>>[
    <int>[runs.first[0], runs.first[1]]
  ];
  for (int i = 1; i < runs.length; i++) {
    final int gap = runs[i][0] - merged.last[1];
    if (gap < cfg.minSilenceMs) {
      merged.last[1] = runs[i][1];
    } else {
      merged.add(<int>[runs[i][0], runs[i][1]]);
    }
  }

  // ④ 너무 짧은 구간 merge. **더 짧은 무음으로 이어진 쪽**과 합친다 —
  //    무음이 짧다는 건 원래 한 호흡이었을 가능성이 높다는 뜻이다.
  //    텍스트는 보지 않는다.
  while (merged.length > 1) {
    int shortIdx = -1;
    for (int i = 0; i < merged.length; i++) {
      if (merged[i][1] - merged[i][0] < cfg.minBreathMs) {
        shortIdx = i;
        break;
      }
    }
    if (shortIdx < 0) break;

    final int target;
    if (shortIdx == 0) {
      target = 1;
    } else if (shortIdx == merged.length - 1) {
      target = merged.length - 2;
    } else {
      final int gapPrev = merged[shortIdx][0] - merged[shortIdx - 1][1];
      final int gapNext = merged[shortIdx + 1][0] - merged[shortIdx][1];
      target = gapPrev <= gapNext ? shortIdx - 1 : shortIdx + 1;
    }
    final int lo = math.min(shortIdx, target);
    final int hi = math.max(shortIdx, target);
    merged[lo] = <int>[merged[lo][0], merged[hi][1]];
    merged.removeAt(hi);
  }

  // ⑤ padding. 무음을 지우지 않고 앞뒤가 나눠 갖는다.
  //    trail과 lead를 **같은 식으로** 계산하므로 trail + lead <= gap이
  //    항상 성립한다 → segment가 겹칠 수 없다.
  final segments = <BreathSegment>[];
  for (int i = 0; i < merged.length; i++) {
    final int speechStart = merged[i][0];
    final int speechEnd = merged[i][1];

    final int start;
    if (i == 0) {
      start = math.max(0, speechStart - cfg.padMs);
    } else {
      final int gap = speechStart - merged[i - 1][1];
      final int trail = math.min(cfg.padMs, gap ~/ 2);
      final int lead = math.min(cfg.padMs, gap - trail);
      start = speechStart - lead;
    }

    final int end;
    if (i == merged.length - 1) {
      end = math.min(totalMs, speechEnd + cfg.padMs);
    } else {
      final int gap = merged[i + 1][0] - speechEnd;
      final int trail = math.min(cfg.padMs, gap ~/ 2);
      end = speechEnd + trail;
    }

    // ⑥ clamp. 위 계산상 범위를 벗어날 수 없지만, 상수를 바꿨을 때를 대비해
    //    마지막 방어를 둔다.
    final int safeStart = start.clamp(0, totalMs);
    final int safeEnd = end.clamp(safeStart, totalMs);
    if (safeEnd <= safeStart) continue;

    segments.add(BreathSegment(
      startMs: safeStart,
      endMs: safeEnd,
      speechStartMs: speechStart.clamp(0, totalMs),
      speechEndMs: speechEnd.clamp(0, totalMs),
    ));
  }

  final gaps = <SilenceRun>[];
  for (int i = 0; i + 1 < segments.length; i++) {
    gaps.add(SilenceRun(
      startMs: segments[i].speechEndMs,
      endMs: segments[i + 1].speechStartMs,
    ));
  }

  return BreathAnalysis(totalMs: totalMs, segments: segments, gaps: gaps);
}

/// 구간 하나를 **재생 가능한 WAV**로 잘라낸다.
///
/// 24kHz·16bit·mono에서 1ms는 정확히 [kStealthVoxSttBytesPerMs](=48)바이트다.
/// seek이 아니라 바이트를 직접 자르므로 샘플 단위로 정확하고, TTS 재호출도
/// 재인코딩도 없다.
Uint8List sliceToWav(
  Uint8List pcm,
  BreathSegment segment, {
  int sampleRate = kStealthVoxSttSampleRate,
}) {
  final int bytesPerMs = sampleRate * 2 ~/ 1000;
  int start = segment.startMs * bytesPerMs;
  int end = segment.endMs * bytesPerMs;
  start = start.clamp(0, pcm.length);
  end = end.clamp(start, pcm.length);
  // 샘플(2바이트) 경계로 맞춘다. 홀수 오프셋이면 좌우 채널이 밀려 잡음이 된다.
  start -= start % 2;
  end -= end % 2;
  if (end <= start) return pcm16ToWav(Uint8List(0), sampleRate: sampleRate);
  return pcm16ToWav(
    Uint8List.sublistView(pcm, start, end),
    sampleRate: sampleRate,
  );
}

/// WAV 컨테이너에서 PCM 본문만 떼어낸다.
///
/// Lab 캐시에는 재생 편의를 위해 WAV로 저장하지만, 분석과 slice는 raw PCM
/// 오프셋으로 해야 한다. 표준 44바이트 헤더만 가정한다 — 우리가
/// [pcm16ToWav]로 만든 것만 넣기 때문이다.
Uint8List pcmFromWav(Uint8List wav) {
  if (wav.length <= 44) return Uint8List(0);
  return Uint8List.sublistView(wav, 44);
}
