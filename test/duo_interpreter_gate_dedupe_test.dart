// 🔵 [INTERP-LIVE] 만능 통역 always-on의 "한 발화는 한 번만" 계약.
//
// 상대 말이 재생되기 직전 게이트를 닫으면서, 그때 진행 중이던 내 발화를
// `flushPendingUtterance`로 강제 확정한다. 여기서 반드시 확인해야 할 것은
// **강제 확정이 전사문을 하나 더 만들지 않는가**다. 하나 더 만든다면 같은
// 발화가 두 번 번역되고 두 번 Firestore에 실린다.
//
// 결론부터 적어 두면: flush는 `input_audio_buffer.commit`만 보낸다. 전사문은
// 여전히 서버가 한 번만 돌려준다. 대신 **세션이 `completed`와 `done`을 같은
// 자리에서 콜백으로 흘려보내므로**, 그 둘이 다 오는 경우의 중복은 호출부가
// item_id로 막아야 한다 — `routine_mode_duo.dart`의 `_interpHandledItemIds`가
// 그 자리다. 아래 테스트가 그 필요성의 근거다.
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/openai_streaming_transcribe_session.dart';

OpenAiStreamingTranscribeSession _session() =>
    OpenAiStreamingTranscribeSession(apiKey: 'test-key', languageCode: 'ko');

Map<String, dynamic> _speechStarted() =>
    <String, dynamic>{'type': 'input_audio_buffer.speech_started'};

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

Map<String, dynamic> _done(String itemId, String text) => <String, dynamic>{
      'type': 'conversation.item.input_audio_transcription.done',
      'item_id': itemId,
      'transcript': text,
    };

void main() {
  group('TTS 직전 강제 확정과 중복', () {
    test('flush 자체는 전사문을 만들지 않는다 — completed가 와야 한 번 온다', () async {
      final s = _session();
      final List<String> received = [];
      s.onTranscriptCompleted = (itemId, text) => received.add(text);

      s.openAudioGate(reason: 'capture_started');
      s.debugHandleEvent(_speechStarted());

      // 상대 TTS가 시작되면서 게이트를 닫고 강제 확정한다.
      final flush = s.flushPendingUtterance(reason: 'tts_playing');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // flush를 걸었다는 이유만으로 전사문이 생기지는 않는다.
      expect(received, isEmpty);

      // 서버가 확정하고 전사문을 돌려준 뒤에야 하나 온다.
      s.debugHandleEvent(_committed('item_1'));
      s.debugHandleEvent(_completed('item_1', '내가 하던 말'));

      expect(await flush, isTrue);
      expect(received, ['내가 하던 말']);
      expect(s.hasPendingUtterance, isFalse);
    });

    test('flush는 게이트를 닫는다 — 확정 직후 PCM이 다음 발화를 열면 안 된다', () async {
      final s = _session();
      s.openAudioGate(reason: 'capture_started');
      s.debugHandleEvent(_speechStarted());

      final flush = s.flushPendingUtterance(reason: 'tts_playing');
      expect(s.audioGateOpen, isFalse);

      s.debugHandleEvent(_committed('item_2'));
      s.debugHandleEvent(_completed('item_2', '문장'));
      await flush;
    });

    test('completed와 done이 둘 다 오면 콜백은 두 번이다 — 호출부 dedupe가 필요한 이유', () {
      final s = _session();
      final List<String> itemIds = [];
      s.onTranscriptCompleted = (itemId, text) => itemIds.add(itemId);

      s.debugHandleEvent(_speechStarted());
      s.debugHandleEvent(_committed('item_3'));
      s.debugHandleEvent(_completed('item_3', '같은 문장'));
      s.debugHandleEvent(_done('item_3', '같은 문장'));

      // 세션은 거르지 않는다. **같은 item_id로** 두 번 준다.
      expect(itemIds, ['item_3', 'item_3']);
      // 그래서 호출부는 item_id 하나만 보면 중복을 확실히 막을 수 있다.
      expect(itemIds.toSet(), hasLength(1));
    });

    test('강제 확정한 발화의 전사문이 늦게 와도 item_id는 그대로다', () async {
      // "flush로 확정한 item"과 "뒤늦게 도착한 completed"가 서로 다른 발화로
      // 보이면 dedupe가 무력해진다. 같은 id인지 확인한다.
      final s = _session();
      final List<String> itemIds = [];
      s.onTranscriptCompleted = (itemId, text) => itemIds.add(itemId);

      s.debugHandleEvent(_speechStarted());
      final flush = s.flushPendingUtterance(reason: 'tts_playing');

      // 서버는 flush로 받은 commit을 처리해 자기 item_id로 확정한다.
      s.debugHandleEvent(_committed('item_server'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      s.debugHandleEvent(_completed('item_server', '앞부분'));
      await flush;

      expect(itemIds, ['item_server']);
    });

    test('전사 실패로 끝나도 대기가 풀린다 — 게이트가 닫힌 채 굳지 않는다', () async {
      final s = _session();
      s.debugHandleEvent(_speechStarted());
      s.debugHandleEvent(_committed('item_4'));

      final flush = s.flushPendingUtterance(reason: 'tts_playing');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      s.debugHandleEvent(<String, dynamic>{
        'type': 'conversation.item.input_audio_transcription.failed',
        'item_id': 'item_4',
      });

      await flush;
      // 이것이 참이어야 `isUserSpeaking`이 굳지 않고 과금 유휴 판정이 선다.
      expect(s.hasPendingUtterance, isFalse);
      expect(s.isUserSpeaking, isFalse);
    });
  });
}
