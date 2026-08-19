// 🌬️ [BREATH-ANALYZER] 합성 PCM으로 경계 계산을 검증한다.
//
//   여기서 판단하는 것은 **알고리즘의 불변식**뿐이다 — merge가 도는지,
//   padding이 버퍼를 넘지 않는지, segment가 겹치지 않는지.
//   "Smooth Jazz의 호흡이 좋은가"는 여기서 판정하지 않는다. 그건 실기기
//   청취로만 알 수 있다.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/audio_silence_analyzer.dart';
import 'package:stealth_vox/custom_code/services/breath_segment.dart';

const int _sampleRate = 24000;
const int _bytesPerMs = _sampleRate * 2 ~/ 1000; // 48

/// 무음 [ms].
Uint8List _silence(int ms) => Uint8List(ms * _bytesPerMs);

/// 확실히 발성으로 잡히는 톤 [ms]. 진폭을 임계값(peak 1200) 위로 크게 잡는다.
Uint8List _speech(int ms, {int amplitude = 8000}) {
  final bytes = Uint8List(ms * _bytesPerMs);
  final data = ByteData.sublistView(bytes);
  final samples = bytes.length ~/ 2;
  for (int i = 0; i < samples; i++) {
    // 200Hz 사인파. 프레임 평균 절댓값이 임계값을 확실히 넘는다.
    final v = (amplitude * math.sin(2 * math.pi * 200 * i / _sampleRate));
    data.setInt16(i * 2, v.round().clamp(-32768, 32767), Endian.little);
  }
  return bytes;
}

Uint8List _concat(List<Uint8List> parts) {
  final total = parts.fold<int>(0, (sum, p) => sum + p.length);
  final out = Uint8List(total);
  int offset = 0;
  for (final p in parts) {
    out.setRange(offset, offset + p.length, p);
    offset += p.length;
  }
  return out;
}

void _assertInvariants(BreathAnalysis analysis) {
  for (int i = 0; i < analysis.segments.length; i++) {
    final s = analysis.segments[i];
    expect(s.startMs, greaterThanOrEqualTo(0),
        reason: 'segment $i start가 음수다');
    expect(s.endMs, lessThanOrEqualTo(analysis.totalMs),
        reason: 'segment $i end가 버퍼를 넘는다');
    expect(s.endMs, greaterThan(s.startMs), reason: 'segment $i 길이가 0 이하다');
    if (i > 0) {
      expect(s.startMs, greaterThanOrEqualTo(analysis.segments[i - 1].endMs),
          reason: 'segment ${i - 1}과 $i가 겹친다');
    }
  }
}

void main() {
  group('analyzeBreaths', () {
    test('발성 하나 → segment 하나', () {
      final pcm = _concat([_silence(100), _speech(2000), _silence(100)]);
      final result = analyzeBreaths(
        pcm,
        const BreathAnalysisConfig(minSilenceMs: 180, minBreathMs: 900),
      );
      expect(result.segments.length, 1);
      expect(result.gaps, isEmpty);
      _assertInvariants(result);
    });

    test('긴 무음으로 갈라지면 segment 둘', () {
      final pcm = _concat([
        _speech(1500),
        _silence(400), // minSilence 180 초과 → 경계
        _speech(1500),
      ]);
      final result = analyzeBreaths(
        pcm,
        const BreathAnalysisConfig(minSilenceMs: 180, minBreathMs: 900),
      );
      expect(result.segments.length, 2);
      expect(result.gaps.length, 1);
      expect(result.gaps.first.durationMs, greaterThan(300));
      _assertInvariants(result);
    });

    test('짧은 무음은 경계가 되지 않는다', () {
      final pcm = _concat([
        _speech(1500),
        _silence(80), // minSilence 180 미만 → 흡수
        _speech(1500),
      ]);
      final result = analyzeBreaths(
        pcm,
        const BreathAnalysisConfig(minSilenceMs: 180, minBreathMs: 900),
      );
      expect(result.segments.length, 1);
      _assertInvariants(result);
    });

    test('minBreathMs보다 짧은 조각은 이웃과 merge된다', () {
      // 300ms짜리 조각이 앞뒤로 긴 무음에 둘러싸여 있어도 살아남으면 안 된다.
      final pcm = _concat([
        _speech(1500),
        _silence(400),
        _speech(300), // 너무 짧다
        _silence(400),
        _speech(1500),
      ]);
      final result = analyzeBreaths(
        pcm,
        const BreathAnalysisConfig(minSilenceMs: 180, minBreathMs: 900),
      );
      for (final s in result.segments) {
        expect(s.durationMs, greaterThanOrEqualTo(900),
            reason: '짧은 segment가 남았다: $s');
      }
      _assertInvariants(result);
    });

    test('merge는 더 짧은 무음 쪽으로 붙는다', () {
      final pcm = _concat([
        _speech(1500),
        _silence(200), // 짧은 쪽
        _speech(300), // 너무 짧다 → 앞과 합쳐져야 한다
        _silence(600), // 긴 쪽
        _speech(1500),
      ]);
      final result = analyzeBreaths(
        pcm,
        const BreathAnalysisConfig(minSilenceMs: 180, minBreathMs: 900),
      );
      expect(result.segments.length, 2);
      // 첫 segment가 1500 + 200 + 300을 품어야 한다.
      expect(result.segments.first.speechDurationMs, greaterThan(1800));
      _assertInvariants(result);
    });

    test('padding이 buffer 밖으로 나가지 않는다', () {
      // 앞뒤 여백 없이 발성으로 시작하고 끝난다.
      final pcm = _concat([_speech(1200), _silence(400), _speech(1200)]);
      final result = analyzeBreaths(
        pcm,
        const BreathAnalysisConfig(
            minSilenceMs: 180, minBreathMs: 900, padMs: 500),
      );
      _assertInvariants(result);
      expect(result.segments.first.startMs, greaterThanOrEqualTo(0));
      expect(result.segments.last.endMs, lessThanOrEqualTo(result.totalMs));
    });

    test('padMs가 gap보다 커도 segment가 겹치지 않는다', () {
      final pcm = _concat([_speech(1200), _silence(200), _speech(1200)]);
      final result = analyzeBreaths(
        pcm,
        const BreathAnalysisConfig(
            minSilenceMs: 180, minBreathMs: 900, padMs: 400),
      );
      _assertInvariants(result);
    });

    test('빈 PCM에서 crash하지 않는다', () {
      final result = analyzeBreaths(Uint8List(0), const BreathAnalysisConfig());
      expect(result.segments, isEmpty);
      expect(result.totalMs, 0);
    });

    test('아주 짧은 PCM에서 crash하지 않는다', () {
      final result =
          analyzeBreaths(Uint8List(3), const BreathAnalysisConfig());
      expect(result.segments, isEmpty);
    });

    test('전부 무음이면 segment가 없다', () {
      final result =
          analyzeBreaths(_silence(3000), const BreathAnalysisConfig());
      expect(result.segments, isEmpty);
      expect(result.totalMs, greaterThan(0));
    });
  });

  group('sliceToWav', () {
    test('WAV 헤더 44바이트 + 요청 구간 길이', () {
      final pcm = _speech(2000);
      const segment = BreathSegment(
          startMs: 500, endMs: 1500, speechStartMs: 500, speechEndMs: 1500);
      final wav = sliceToWav(pcm, segment, sampleRate: _sampleRate);
      expect(wav.length, 44 + 1000 * _bytesPerMs);
      expect(wav[0], 0x52); // 'R'
      expect(wav[1], 0x49); // 'I'
    });

    test('범위를 넘는 구간을 요청해도 clamp된다', () {
      final pcm = _speech(500);
      const segment = BreathSegment(
          startMs: 0, endMs: 99999, speechStartMs: 0, speechEndMs: 99999);
      final wav = sliceToWav(pcm, segment, sampleRate: _sampleRate);
      expect(wav.length, 44 + pcm.length);
    });
  });

  group('buildGappedPcm', () {
    List<BreathSegment> threeSegments() => const <BreathSegment>[
          BreathSegment(
              startMs: 0, endMs: 1000, speechStartMs: 0, speechEndMs: 900),
          BreathSegment(
              startMs: 1000, endMs: 2000, speechStartMs: 1100, speechEndMs: 1900),
          BreathSegment(
              startMs: 2000, endMs: 3000, speechStartMs: 2100, speechEndMs: 3000),
        ];

    test('gap 0이면 원본을 그대로 돌려준다', () {
      final pcm = _speech(3000);
      final out = buildGappedPcm(pcm, threeSegments(),
          extraGapMs: 0, sampleRate: _sampleRate);
      expect(identical(out, pcm), isTrue);
    });

    test('호흡이 하나면 삽입 지점이 없어 원본 그대로', () {
      final pcm = _speech(2000);
      final out = buildGappedPcm(
        pcm,
        const <BreathSegment>[
          BreathSegment(
              startMs: 0, endMs: 2000, speechStartMs: 0, speechEndMs: 2000),
        ],
        extraGapMs: 500,
        sampleRate: _sampleRate,
      );
      expect(identical(out, pcm), isTrue);
    });

    test('호흡 3개 + gap 500 → 정확히 2회분이 늘어난다', () {
      final pcm = _speech(3000);
      final out = buildGappedPcm(pcm, threeSegments(),
          extraGapMs: 500, sampleRate: _sampleRate);
      expect(out.length, pcm.length + 2 * 500 * _bytesPerMs);
    });

    test('원본 샘플을 삭제하지 않는다 — 앞부분이 그대로 보존된다', () {
      final pcm = _speech(3000);
      final out = buildGappedPcm(pcm, threeSegments(),
          extraGapMs: 300, sampleRate: _sampleRate);
      // 첫 삽입 지점(1000ms) 전까지는 바이트가 동일해야 한다.
      const head = 1000 * _bytesPerMs;
      for (int i = 0; i < head; i += 997) {
        expect(out[i], pcm[i], reason: 'offset $i에서 원본이 바뀌었다');
      }
    });

    test('삽입된 구간은 무음(0)이다', () {
      final pcm = _speech(3000);
      const gap = 300;
      final out = buildGappedPcm(pcm, threeSegments(),
          extraGapMs: gap, sampleRate: _sampleRate);
      const start = 1000 * _bytesPerMs;
      for (int i = start; i < start + gap * _bytesPerMs; i += 101) {
        expect(out[i], 0, reason: '삽입 구간에 소리가 있다 (offset $i)');
      }
    });

    test('P3 gap 3단계(300/500/800)가 정확히 삽입된다', () {
      final pcm = _speech(3000);
      final segs = threeSegments();
      for (final gap in <int>[300, 500, 800]) {
        final out = buildGappedPcm(pcm, segs,
            extraGapMs: gap, sampleRate: _sampleRate);
        // 삽입 지점은 segment 수 - 1 곳
        expect(out.length, pcm.length + 2 * gap * _bytesPerMs,
            reason: 'gap $gap 삽입량이 어긋난다');
      }
    });

    test('gap을 바꿔도 원본 발성이 그대로 남는다', () {
      final pcm = _speech(3000);
      final segs = threeSegments();
      final tight = buildGappedPcm(pcm, segs,
          extraGapMs: 300, sampleRate: _sampleRate);
      final relaxed = buildGappedPcm(pcm, segs,
          extraGapMs: 800, sampleRate: _sampleRate);
      // 첫 삽입 지점 전까지는 셋 다 동일해야 한다(속도를 바꾸는 게 아니다).
      const head = 1000 * _bytesPerMs;
      for (int i = 0; i < head; i += 977) {
        expect(tight[i], pcm[i]);
        expect(relaxed[i], pcm[i]);
      }
    });

    test('빈 segment 목록에서 crash하지 않는다', () {
      final pcm = _speech(500);
      final out = buildGappedPcm(pcm, const <BreathSegment>[],
          extraGapMs: 500, sampleRate: _sampleRate);
      expect(identical(out, pcm), isTrue);
    });
  });

  group('pcmFromWav', () {
    test('헤더를 벗겨 원본 PCM을 돌려준다', () {
      final pcm = _speech(300);
      const segment = BreathSegment(
          startMs: 0, endMs: 300, speechStartMs: 0, speechEndMs: 300);
      final wav = sliceToWav(pcm, segment, sampleRate: _sampleRate);
      expect(pcmFromWav(wav).length, pcm.length);
    });

    test('헤더보다 짧으면 빈 결과', () {
      expect(pcmFromWav(Uint8List(10)).length, 0);
    });
  });
}
