// ⏱️ [INTERP-LATENCY] "정말 겹쳤는가"를 판정하는 규칙의 시험.
//
// 이번 작업의 목적은 번역과 TTS를 **시간상 겹치게** 하는 것이다. 그런데
// 겹쳤는지는 귀로 알 수 없다 — 소리는 어느 쪽이든 결국 나기 때문이다.
// 그래서 판정을 숫자로 하고, 그 규칙을 여기서 못 박는다.
//
// 판정 기준 한 줄:
//   **재생이 번역 완료보다 먼저 시작했으면 겹친 것이다.**
// 기존 경로는 번역이 끝나야 TTS를 부르므로 정의상 절대 참이 될 수 없다.

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_interp_latency.dart';

void main() {
  group('겹침 판정', () {
    test('재생이 번역보다 먼저 시작하면 겹친 것이다 (스트리밍 경로)', () {
      final lat = DuoInterpLatency(turnId: 't1', path: 'stream');
      final t0 = lat.incomingMessageReceived;
      lat.playbackStart = t0.add(const Duration(milliseconds: 900));
      lat.translationComplete = t0.add(const Duration(milliseconds: 1500));

      expect(lat.overlapped, isTrue);
      expect(lat.overlapMs, 600, reason: '겹친 만큼이 아낀 시간이다');
    });

    test('번역이 끝난 뒤에 재생이 시작하면 안 겹친 것이다 (기존 경로)', () {
      final lat = DuoInterpLatency(turnId: 't2', path: 'blocking');
      final t0 = lat.incomingMessageReceived;
      lat.translationComplete = t0.add(const Duration(milliseconds: 1200));
      lat.playbackStart = t0.add(const Duration(milliseconds: 2200));

      expect(lat.overlapped, isFalse);
      expect(lat.overlapMs, 0);
    });

    test('한쪽 시각이 없으면 겹쳤다고 말하지 않는다', () {
      final lat = DuoInterpLatency(turnId: 't3', path: 'stream');
      lat.playbackStart = DateTime.now();
      // translationComplete 없음 (번역이 실패했거나 아직 안 끝남)
      expect(lat.overlapped, isFalse);
      expect(lat.overlapMs, 0);
    });
  });

  group('KPI — 상대 말 도착 → 내 귀에 소리', () {
    test('두 시각의 차이가 KPI다', () {
      final lat = DuoInterpLatency(turnId: 't4', path: 'stream');
      lat.playbackStart =
          lat.incomingMessageReceived.add(const Duration(milliseconds: 850));
      expect(lat.toPlaybackMs, 850);
    });

    test('재생이 없으면 null이다 — 0으로 속이지 않는다', () {
      final lat = DuoInterpLatency(turnId: 't5', path: 'stream');
      expect(lat.toPlaybackMs, isNull);
    });
  });

  group('구간 분해', () {
    test('각 구간이 따로 계산된다', () {
      final lat = DuoInterpLatency(turnId: 't6', path: 'stream');
      final t0 = lat.incomingMessageReceived;
      lat.translationRequestStart = t0.add(const Duration(milliseconds: 20));
      lat.firstTranslationDelta = t0.add(const Duration(milliseconds: 420));
      lat.firstTtsChunkCommitted = t0.add(const Duration(milliseconds: 700));
      lat.firstTtsRequestStart = t0.add(const Duration(milliseconds: 705));
      lat.firstTtsAudioReady = t0.add(const Duration(milliseconds: 1050));
      lat.playbackStart = t0.add(const Duration(milliseconds: 1100));
      lat.translationComplete = t0.add(const Duration(milliseconds: 1400));
      lat.lastPlaybackComplete = t0.add(const Duration(milliseconds: 3000));

      expect(lat.translateTtfbMs, 400);
      expect(lat.deltaToChunkMs, 280);
      expect(lat.ttsTtfbMs, 345);
      expect(lat.translateTotalMs, 1380);
      expect(lat.toPlaybackMs, 1100);
      expect(lat.totalMs, 3000);
      expect(lat.overlapped, isTrue);
    });
  });

  group('로그 한 줄', () {
    test('숫자만 남고 전사문·오디오는 없다', () {
      final lat = DuoInterpLatency(turnId: 'duo-partner-3', path: 'stream')
        ..ttsChunks = 2
        ..playbackStart = DateTime.now();
      final line = lat.summary();
      for (final field in <String>[
        'turn=duo-partner-3',
        'path=stream',
        'toPlaybackMs=',
        'ttsChunks=2',
        'overlapped=',
        'overlapMs=',
      ]) {
        expect(line, contains(field));
      }
    });

    test('안 잰 값은 -1로 남는다 — 0으로 보이면 빠른 줄 안다', () {
      final line = DuoInterpLatency(turnId: 't7', path: 'blocking').summary();
      expect(line, contains('toPlaybackMs=-1'));
      expect(line, contains('ttsChunks=0'));
    });

    test('두 경로가 같은 모양으로 남는다 — 그래야 견줄 수 있다', () {
      final a = DuoInterpLatency(turnId: 'x', path: 'stream').summary();
      final b = DuoInterpLatency(turnId: 'x', path: 'blocking').summary();
      String shape(String s) =>
          s.split(' ').map((kv) => kv.split('=').first).join(' ');
      expect(shape(a), shape(b));
    });
  });

  group('같은 언어 건너뛰기', () {
    test('번역을 건너뛴 턴이 로그에 드러난다', () {
      final lat = DuoInterpLatency(turnId: 't8', path: 'blocking')
        ..sameLangSkip = true;
      expect(lat.summary(), contains('sameLangSkip=true'));
      // 번역을 안 했으므로 겹칠 것도 없다.
      expect(lat.overlapped, isFalse);
    });
  });
}
