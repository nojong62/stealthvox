// 통화 종료 직전 "마지막 발화" 처리 규칙 테스트.
//
// 실기기에서 확인된 결함이 출발점이다:
//   speech_started → (말하는 중) → 마이크 끄기 → 전사문이 영영 안 옴
// 원인은 종료가 진행 중 발화를 확정하지도, 기다리지도 않은 것이었다.
//
// 소켓 없이 이벤트 순서만으로 검증한다(`debugHandleEvent`).
// 여기서 보는 것은 세 가지다.
//   · 언제 "기다려야 하는 발화"가 있다고 보는가
//   · 없으면 즉시 끝나는가 (말 안 하고 끄기 · 완료 직후 끄기)
//   · 실패/에러로도 대기가 풀리는가 (상한까지 노는 일이 없어야 한다)

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/openai_streaming_transcribe_session.dart';

OpenAiStreamingTranscribeSession _session() =>
    OpenAiStreamingTranscribeSession(apiKey: 'test-key', languageCode: 'ko');

Map<String, dynamic> _speechStarted() =>
    <String, dynamic>{'type': 'input_audio_buffer.speech_started'};

Map<String, dynamic> _speechStopped() =>
    <String, dynamic>{'type': 'input_audio_buffer.speech_stopped'};

Map<String, dynamic> _committed(String itemId) => <String, dynamic>{
      'type': 'input_audio_buffer.committed',
      'item_id': itemId,
    };

Map<String, dynamic> _completed(String itemId, String text) =>
    <String, dynamic>{
      'type': 'conversation.item.input_audio_transcription.completed',
      'item_id': itemId,
      'transcript': text,
    };

void main() {
  group('진행 중 발화 판정', () {
    test('아무 말도 안 했으면 기다릴 발화가 없다', () {
      final s = _session();
      expect(s.hasPendingUtterance, isFalse);
    });

    test('말하는 중이면 기다려야 한다', () {
      final s = _session();
      s.debugHandleEvent(_speechStarted());
      expect(s.hasPendingUtterance, isTrue);
    });

    test('speech_stopped만으로는 대기가 풀리지 않는다 — 전사는 그 뒤에 온다', () {
      final s = _session();
      s.debugHandleEvent(_speechStarted());
      s.debugHandleEvent(_speechStopped());
      expect(s.hasPendingUtterance, isTrue);
    });

    test('committed면 말은 끝났지만 전사문을 아직 기다린다', () {
      final s = _session();
      s.debugHandleEvent(_speechStarted());
      s.debugHandleEvent(_speechStopped());
      s.debugHandleEvent(_committed('item_1'));
      expect(s.hasPendingUtterance, isTrue);
    });

    test('전사문이 오면 대기가 끝난다', () {
      final s = _session();
      s.debugHandleEvent(_speechStarted());
      s.debugHandleEvent(_speechStopped());
      s.debugHandleEvent(_committed('item_1'));
      s.debugHandleEvent(_completed('item_1', '안녕하세요'));
      expect(s.hasPendingUtterance, isFalse);
    });

    test('두 발화가 겹쳐 있으면 둘 다 끝나야 대기가 풀린다', () {
      final s = _session();
      s.debugHandleEvent(_speechStarted());
      s.debugHandleEvent(_committed('item_1'));
      s.debugHandleEvent(_speechStarted());
      s.debugHandleEvent(_committed('item_2'));
      s.debugHandleEvent(_completed('item_1', '첫 문장'));
      expect(s.hasPendingUtterance, isTrue);
      s.debugHandleEvent(_completed('item_2', '둘째 문장'));
      expect(s.hasPendingUtterance, isFalse);
    });
  });

  group('flushPendingUtterance', () {
    test('말하지 않고 끄면 기다리지 않고 즉시 끝난다', () async {
      final s = _session();
      final sw = Stopwatch()..start();
      final waited = await s.flushPendingUtterance(reason: 'user_tap');
      sw.stop();
      expect(waited, isFalse);
      expect(sw.elapsedMilliseconds, lessThan(200));
    });

    test('발화 완료 직후 끄면 기다리지 않는다', () async {
      final s = _session();
      s.debugHandleEvent(_speechStarted());
      s.debugHandleEvent(_speechStopped());
      s.debugHandleEvent(_committed('item_1'));
      s.debugHandleEvent(_completed('item_1', '다 말했다'));

      final waited = await s.flushPendingUtterance(reason: 'user_tap');
      expect(waited, isFalse);
    });

    test('flush는 오디오 게이트부터 닫는다 — 확정 뒤 새 발화가 열리면 안 된다', () async {
      final s = _session();
      s.openAudioGate(reason: 'direct_call');
      expect(s.audioGateOpen, isTrue);
      await s.flushPendingUtterance(reason: 'user_tap');
      expect(s.audioGateOpen, isFalse);
    });

    test('말하는 도중 끄면 기다리고, 전사문이 도착하면 그때 끝난다', () async {
      final s = _session();
      s.debugHandleEvent(_speechStarted());

      String? received;
      s.onTranscriptCompleted = (itemId, text) => received = text;

      final flush = s.flushPendingUtterance(reason: 'user_tap');
      // 종료 요청 뒤에 서버가 구간을 확정하고 전사문을 돌려주는 상황.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      s.debugHandleEvent(_committed('item_9'));
      s.debugHandleEvent(_completed('item_9', '마지막 문장입니다'));

      expect(await flush, isTrue);
      expect(s.hasPendingUtterance, isFalse);
      expect(received, '마지막 문장입니다');
    });

    test('전사가 실패해도 상한까지 놀지 않고 대기가 풀린다', () async {
      final s = _session();
      s.debugHandleEvent(_speechStarted());
      s.debugHandleEvent(_committed('item_x'));

      final sw = Stopwatch()..start();
      final flush = s.flushPendingUtterance(reason: 'user_tap');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      s.debugHandleEvent(<String, dynamic>{
        'type': 'conversation.item.input_audio_transcription.failed',
        'item_id': 'item_x',
        'error': 'whatever',
      });
      await flush;
      sw.stop();
      expect(sw.elapsedMilliseconds,
          lessThan(kStreamingSttFlushTimeout.inMilliseconds));
    });

    test('전사문이 끝내 안 오면 상한에서 끊고 종료를 진행한다', () async {
      final s = _session();
      s.debugHandleEvent(_speechStarted());
      s.debugHandleEvent(_committed('item_stuck'));

      final sw = Stopwatch()..start();
      final waited = await s.flushPendingUtterance(
        reason: 'user_tap',
        timeout: const Duration(milliseconds: 120),
      );
      sw.stop();
      expect(waited, isTrue);
      expect(s.hasPendingUtterance, isTrue); // 못 받은 채 끝났음을 남긴다
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(100));
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('연속 두 번 끄기 — 두 번째 flush는 기다리지 않는다', () async {
      final s = _session();
      s.debugHandleEvent(_speechStarted());
      s.debugHandleEvent(_committed('item_1'));

      final first = s.flushPendingUtterance(reason: 'user_tap');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      s.debugHandleEvent(_completed('item_1', '한 번만 저장돼야 한다'));
      expect(await first, isTrue);

      final second = await s.flushPendingUtterance(reason: 'user_tap');
      expect(second, isFalse);
    });

    test('dispose는 대기 중인 flush를 풀어 준다', () async {
      final s = _session();
      s.debugHandleEvent(_speechStarted());
      s.debugHandleEvent(_committed('item_1'));

      final flush = s.flushPendingUtterance(reason: 'room_exit');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await s.dispose();
      expect(await flush, isTrue);
    });
  });
}
