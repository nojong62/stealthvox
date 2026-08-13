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

  group('발화 순번 (transcription.completed 도착 순서와 별개)', () {
    test('committed 순서가 곧 발화 순서다', () {
      final s = _session();
      s.debugHandleEvent(_speechStarted());
      s.debugHandleEvent(_committed('item_A'));
      s.debugHandleEvent(_speechStarted());
      s.debugHandleEvent(_committed('item_B'));

      final a = s.utteranceOrderOf('item_A');
      final b = s.utteranceOrderOf('item_B');
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(a! < b!, isTrue, reason: '먼저 말한 쪽의 순번이 작아야 한다');
    });

    test('전사가 역순으로 도착해도 순번은 발화 순서를 지킨다', () {
      final s = _session();
      final arrived = <String>[];
      s.onTranscriptCompleted = (itemId, _) => arrived.add(itemId);

      s.debugHandleEvent(_speechStarted());
      s.debugHandleEvent(_committed('item_A'));
      s.debugHandleEvent(_speechStarted());
      s.debugHandleEvent(_committed('item_B'));
      // 뒷말이 짧아 전사가 먼저 끝났다.
      s.debugHandleEvent(_completed('item_B', '야구장에 가려고 해요'));
      s.debugHandleEvent(_completed('item_A', '주말에는 친구하고'));

      expect(arrived, ['item_B', 'item_A'], reason: '도착은 역순이었다');
      expect(s.utteranceOrderOf('item_A')! < s.utteranceOrderOf('item_B')!,
          isTrue, reason: '순번은 여전히 발화 순서다');
    });

    test('같은 item의 순번은 몇 번을 봐도 그대로다', () {
      final s = _session();
      s.debugHandleEvent(_committed('item_A'));
      final first = s.utteranceOrderOf('item_A');
      s.debugHandleEvent(_completed('item_A', '한 번만'));
      expect(s.utteranceOrderOf('item_A'), first);
    });

    test('committed를 못 본 item도 완료 시점에 순번을 받는다', () {
      final s = _session();
      s.debugHandleEvent(_completed('item_orphan', '고아 전사'));
      expect(s.utteranceOrderOf('item_orphan'), isNotNull);
    });

    test('dispose하면 순번 장부를 놓는다', () async {
      final s = _session();
      s.debugHandleEvent(_committed('item_A'));
      await s.dispose();
      expect(s.utteranceOrderOf('item_A'), isNull);
    });
  });

  group('발화 길이 (환청과 실제 발화를 가르는 근거)', () {
    // 2026-08-13 Duo 실측: 실제 말 1,323~2,999ms / 클릭 잡음 41~44ms.
    // 이벤트 사이 시간을 실제로 흘려보내며 잰다.
    test('짧은 클릭은 로컬 폴백에서도 150ms 미만으로 나온다', () async {
      final s = _session();
      s.debugHandleEvent(_speechStarted());
      // VAD는 침묵 600ms를 확인한 뒤에 commit한다. 그래서 40ms짜리 클릭의
      // 실제 span은 640ms다 — 40ms가 아니다.
      await Future<void>.delayed(
        const Duration(milliseconds: kStreamingSttVadSilenceDurationMs + 40),
      );
      s.debugHandleEvent(_committed('item_click'));

      final voiced = s.utteranceVoicedMsOf('item_click');
      expect(voiced, isNotNull);
      expect(voiced, lessThan(150), reason: '150ms 게이트에 걸려야 하는 값이다');
      expect(s.utteranceVoicedSourceOf('item_click'), 'local');
    });

    test('실제 발화 길이는 침묵 시간을 뺀 값으로 나온다', () async {
      final s = _session();
      s.debugHandleEvent(_speechStarted());
      // 침묵 판정(600ms) + 실제 음성 250ms를 흉내 낸다.
      await Future<void>.delayed(
        const Duration(milliseconds: kStreamingSttVadSilenceDurationMs + 250),
      );
      s.debugHandleEvent(_committed('item_speech'));

      final voiced = s.utteranceVoicedMsOf('item_speech')!;
      expect(voiced, greaterThanOrEqualTo(150),
          reason: '짧은 실제 응답("네")도 살아야 한다');
      expect(voiced, lessThan(600), reason: '침묵 시간이 빠졌다');
    });

    test('committed를 못 본 item은 길이를 모른다 — 게이트를 태우지 않는다', () {
      final s = _session();
      s.debugHandleEvent(_completed('item_orphan', '고아 전사'));
      expect(s.utteranceVoicedMsOf('item_orphan'), isNull);
    });

    test('speech_started 없이 committed만 오면 길이를 지어내지 않는다', () {
      final s = _session();
      s.debugHandleEvent(_committed('item_bare'));
      expect(s.utteranceVoicedMsOf('item_bare'), isNull);
    });

    test('발화가 이어져도 각 item의 길이가 섞이지 않는다', () async {
      final s = _session();
      s.debugHandleEvent(_speechStarted());
      await Future<void>.delayed(
        const Duration(milliseconds: kStreamingSttVadSilenceDurationMs + 30),
      );
      s.debugHandleEvent(_committed('item_a'));
      s.debugHandleEvent(_speechStarted());
      await Future<void>.delayed(
        const Duration(milliseconds: kStreamingSttVadSilenceDurationMs + 200),
      );
      s.debugHandleEvent(_committed('item_b'));

      expect(s.utteranceVoicedMsOf('item_a')!, lessThan(150));
      expect(s.utteranceVoicedMsOf('item_b')!, greaterThanOrEqualTo(150));
    });

    test('서버 값은 audio_end_ms - audio_start_ms 순서로 잰다', () {
      final s = _session();
      s.debugHandleEvent(<String, dynamic>{
        'type': 'input_audio_buffer.speech_started',
        'audio_start_ms': 10000,
      });
      s.debugHandleEvent(<String, dynamic>{
        'type': 'input_audio_buffer.speech_stopped',
        'audio_end_ms': 11800,
      });
      s.debugHandleEvent(_committed('item_server'));

      expect(s.utteranceVoicedMsOf('item_server'), 1800,
          reason: '끝 - 시작. 뒤집히면 음수가 나온다');
      expect(s.utteranceVoicedSourceOf('item_server'), 'server');
    });

    test('서버 값이 짧으면 그대로 짧게 나온다 (침묵 시간을 빼지 않는다)', () {
      final s = _session();
      s.debugHandleEvent(<String, dynamic>{
        'type': 'input_audio_buffer.speech_started',
        'audio_start_ms': 5000,
      });
      s.debugHandleEvent(<String, dynamic>{
        'type': 'input_audio_buffer.speech_stopped',
        'audio_end_ms': 5042,
      });
      s.debugHandleEvent(_committed('item_click'));

      expect(s.utteranceVoicedMsOf('item_click'), 42,
          reason: '실측 클릭 잡음과 같은 값');
    });

    test('서버 타임스탬프가 뒤집혀 오면 그 값을 쓰지 않는다 — 근거 없는 차단 금지', () {
      final s = _session();
      s.debugHandleEvent(<String, dynamic>{
        'type': 'input_audio_buffer.speech_started',
        'audio_start_ms': 9000,
      });
      s.debugHandleEvent(<String, dynamic>{
        'type': 'input_audio_buffer.speech_stopped',
        'audio_end_ms': 3000, // 끝이 시작보다 앞이다 = 비정상
      });
      s.debugHandleEvent(_committed('item_bad'));

      // 0으로 눌러 저장하면 길이 게이트가 정상 발화를 잡음으로 버린다.
      expect(s.utteranceVoicedSourceOf('item_bad'), isNot('server'));
      final v = s.utteranceVoicedMsOf('item_bad');
      expect(v == null || v >= 0, isTrue);
    });

    test('길이를 모르면 null이다 — 호출부가 게이트를 태우지 않는다', () {
      final s = _session();
      // speech_started 없이 speech_stopped만 온 경우(이벤트 유실).
      s.debugHandleEvent(<String, dynamic>{
        'type': 'input_audio_buffer.speech_stopped',
        'audio_end_ms': 3000,
      });
      s.debugHandleEvent(_committed('item_unknown'));
      expect(s.utteranceVoicedMsOf('item_unknown'), isNull);
    });

    test('dispose하면 길이 장부도 놓는다', () async {
      final s = _session();
      s.debugHandleEvent(_speechStarted());
      s.debugHandleEvent(_committed('item_a'));
      await s.dispose();
      expect(s.utteranceVoicedMsOf('item_a'), isNull);
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
