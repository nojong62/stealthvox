// 🚪 [GATE-SYNC] 문이 닫히면 Deepgram의 열린 발화도 함께 버린다
//
// 통역은 상대 목소리를 트는 동안 마이크 문을 닫는다. 그때 앱은
// `_capture.abort()`로 담던 소리를 버리는데, Deepgram의 `_speechOpen`은 그대로
// 남았다. 문이 닫힌 동안에는 소리가 저쪽으로도 안 가므로 단어가 없고, 단어가
// 없으면 UtteranceEnd가 영영 안 온다. 그래서 다시 열렸을 때 **이미 끝난 발화가
// 아직 열려 있다고 믿는 상태**가 다음 구간으로 끌려갔다.
//
// 2026-09-10 실기기 통역에서 그 모습이 나왔다.
//
//   utt=- speech_stale capturedMs=0          앱은 담은 게 없는데 저쪽은 열려 있다
//   closing started=2 ended=2                3분 통화에 발화가 둘뿐
//   transcribe=failed reason=empty_text      7.56초 · 15.84초짜리 무음이 올라감
//   RETRANSCRIBE ok len=0                    API는 멀쩡했다
//
// ⚠️ **버리기만 하고 커밋하지 않는다.** 앱이 이미 소리를 버렸으므로 여기서
//   UtteranceEnd를 부르면 빈 종료만 남는다. 소켓도 그대로 둔다 — 다시 여는
//   값보다 잃는 시간이 크다.
//
// 🚫 직접 대화는 문을 닫지 않는다(`openAudioGate('direct_call')` 뒤로 닫는
//   자리가 없다). 그래서 이 어긋남이 생길 자리 자체가 없고, 이 시험이 지키는
//   것도 통역 쪽이다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_deepgram_endpoint.dart';

const String speechStarted = '{"type":"SpeechStarted"}';

String utteranceEnd({num lastWordEnd = 3.2}) => jsonEncode(<String, dynamic>{
      'type': 'UtteranceEnd',
      'last_word_end': lastWordEnd,
    });

String results(String transcript) => jsonEncode(<String, dynamic>{
      'type': 'Results',
      'is_final': false,
      'channel': <String, dynamic>{
        'alternatives': <dynamic>[
          <String, dynamic>{'transcript': transcript},
        ],
      },
    });

DuoDeepgramEndpointSensor makeSensor() => DuoDeepgramEndpointSensor(
      apiKey: 'test-key',
      languageCode: 'ko',
    );

void main() {
  group('문이 닫힐 때', () {
    test('열린 발화를 버린다 — 다음 구간으로 끌고 가지 않는다', () {
      final sensor = makeSensor();
      var ended = 0;
      sensor.onUtteranceEnd = () => ended++;

      sensor.handleMessageForTest(speechStarted);
      expect(sensor.isSpeechOpen, isTrue);

      sensor.abortOpenSpeech('tts_playing');

      expect(sensor.isSpeechOpen, isFalse,
          reason: '문이 닫힌 뒤에도 열려 있으면 다음 발화가 그 껍데기에 붙는다');
      expect(ended, 0, reason: '앱이 이미 소리를 버렸다. 여기서 커밋하면 빈 종료만 남는다');
    });

    test('"말하는 중" 표시도 함께 내린다', () {
      final sensor = makeSensor();
      sensor.handleMessageForTest(speechStarted);
      sensor.handleMessageForTest(results('여보세요'));
      expect(sensor.isUserSpeaking, isTrue);

      sensor.abortOpenSpeech('tts_playing');

      expect(sensor.isUserSpeaking, isFalse);
      expect(sensor.isSpeechOpen, isFalse);
    });

    test('버린 뒤 늦게 온 UtteranceEnd는 흘려보낸다', () {
      final sensor = makeSensor();
      var ended = 0;
      sensor.onUtteranceEnd = () => ended++;

      sensor.handleMessageForTest(speechStarted);
      sensor.abortOpenSpeech('tts_playing');
      sensor.handleMessageForTest(utteranceEnd());

      expect(ended, 0, reason: '시작 없이 끝만 오는 이벤트로 빈 발화를 만들지 않는다');
    });

    test('열린 발화가 없으면 아무 일도 하지 않는다', () {
      final sensor = makeSensor();
      expect(sensor.isSpeechOpen, isFalse);
      sensor.abortOpenSpeech('tts_playing');
      expect(sensor.isSpeechOpen, isFalse);
      expect(sensor.speechStartedCount, 0);
    });
  });

  group('문이 다시 열린 뒤', () {
    test('새 발화가 새로 열리고 정상으로 닫힌다', () {
      final sensor = makeSensor();
      var ended = 0;
      sensor.onUtteranceEnd = () => ended++;

      // 첫 구간 — 문이 닫히며 버려진다.
      sensor.handleMessageForTest(speechStarted);
      sensor.abortOpenSpeech('tts_playing');

      // 문이 다시 열리고 사람이 말한다.
      sensor.handleMessageForTest(speechStarted);
      expect(sensor.isSpeechOpen, isTrue, reason: '버린 뒤에도 새 발화는 열려야 한다');
      sensor.handleMessageForTest(results('오늘 날씨가 좋네요'));
      sensor.handleMessageForTest(utteranceEnd());

      expect(ended, 1, reason: '새 발화는 평소대로 한 번 확정된다');
      expect(sensor.isSpeechOpen, isFalse);
    });

    test('버린 판은 종료 수에 잡히지 않는다', () {
      final sensor = makeSensor();
      sensor.handleMessageForTest(speechStarted);
      sensor.abortOpenSpeech('tts_playing');
      sensor.handleMessageForTest(speechStarted);
      sensor.handleMessageForTest(results('네'));
      sensor.handleMessageForTest(utteranceEnd());

      expect(sensor.speechStartedCount, 2);
      expect(sensor.utteranceEndCount, 1,
          reason: 'started 2 / ended 1 — 버린 하나는 커밋되지 않았다');
    });
  });

  group('제품 코드가 그 자리에 있는가', () {
    final pipeline = File(
            'lib/custom_code/services/duo_stt_pipeline.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    test('게이트를 닫을 때 Deepgram도 함께 정리한다', () {
      final close = pipeline.indexOf('void closeAudioGate(');
      final abortCapture = pipeline.indexOf('_capture.abort();', close);
      final abortSpeech = pipeline.indexOf('abortOpenSpeech(', close);
      expect(close, greaterThanOrEqualTo(0));
      expect(abortCapture, greaterThan(close));
      expect(abortSpeech, greaterThan(abortCapture),
          reason: '앱만 버리고 저쪽을 두면 껍데기가 다음 구간으로 넘어간다');
    });

    test('소켓을 다시 열지는 않는다', () {
      final close = pipeline.indexOf('void closeAudioGate(');
      final end = pipeline.indexOf('}', pipeline.indexOf('_lg(', close));
      final body = pipeline.substring(close, end);
      expect(body.contains('connect('), isFalse);
      expect(body.contains('start('), isFalse);
    });
  });
}
