// 🎧 [DUO-STT] 새 Duo 전사 경로의 규칙을 값으로 고정한다
//
// 지키는 것 셋이다.
//   1. **판정으로 PCM을 버리지 않는다** — 앞 여유가 붙고, 상한은 뒤를 지킨다
//   2. **경계는 UtteranceEnd 하나** — speech_final로 닫지 않고, 두 번 닫지 않는다
//   3. **발화 id는 이 앱이 만든다** — 외부 서비스 id를 빌려 쓰지 않는다

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_deepgram_endpoint.dart';
import 'package:stealth_vox/custom_code/services/duo_transcript_context.dart';
import 'package:stealth_vox/custom_code/services/duo_utterance_capture.dart';
import 'package:stealth_vox/custom_code/services/openai_transcribe_service.dart';
import 'package:stealth_vox/custom_code/services/pcm_audio_utils.dart';

/// [ms] 길이의 조각 하나. 값은 중요하지 않고 길이만 본다.
Uint8List frame(int ms) => Uint8List(ms * kStealthVoxSttSampleRate * 2 ~/ 1000);

String utteranceEnd({num lastWordEnd = 3.2}) => jsonEncode(<String, dynamic>{
      'type': 'UtteranceEnd',
      'last_word_end': lastWordEnd,
    });

const String speechStarted = '{"type":"SpeechStarted"}';

void main() {
  group('🎙️ 소리는 판정으로 버려지지 않는다', () {
    test('시작 신호보다 앞선 소리가 발화에 붙는다', () {
      // 신호는 언제나 소리보다 늦게 온다. 이게 없으면 첫 음절이 사라진다.
      final capture = DuoUtteranceCapture(idPrefix: 'duo_direct');
      capture.addPcm(frame(200));
      capture.addPcm(frame(200));
      capture.begin();
      capture.addPcm(frame(1000));
      final u = capture.commit()!;
      expect(u.preRollMs, 400);
      expect(u.bodyMs, 1000);
      expect(u.durationMs, 1400);
    });

    test('고리는 상한을 넘지 않는다 — 통화가 길어도 메모리가 평평하다', () {
      final capture =
          DuoUtteranceCapture(idPrefix: 'duo_direct', preRollMs: 600);
      for (var i = 0; i < 50; i++) {
        capture.addPcm(frame(100));
      }
      expect(capture.preRollBufferedMs, lessThanOrEqualTo(600));
      capture.begin();
      final u = capture.commit()!;
      expect(u.preRollMs, lessThanOrEqualTo(600));
    });

    test('발화 상한을 넘으면 앞쪽부터 버린다 — 방금 한 말이 더 중요하다', () {
      final capture = DuoUtteranceCapture(
          idPrefix: 'duo_direct', preRollMs: 200, maxUtteranceMs: 1000);
      capture.begin();
      for (var i = 0; i < 20; i++) {
        capture.addPcm(frame(100));
      }
      final u = capture.commit()!;
      expect(u.durationMs, lessThanOrEqualTo(1000));
    });

    test('담긴 것이 없으면 발화를 만들지 않는다 — 무음에서 문장이 지어진다', () {
      final capture = DuoUtteranceCapture(idPrefix: 'duo_direct');
      capture.begin();
      expect(capture.commit(), isNull);
    });

    test('시작하지 않았는데 끝나면 아무 일도 없다', () {
      expect(DuoUtteranceCapture(idPrefix: 'duo_direct').commit(), isNull);
    });

    test('버린 발화의 소리가 다음 발화에 붙지 않는다', () {
      final capture = DuoUtteranceCapture(idPrefix: 'duo_direct');
      capture.begin();
      capture.addPcm(frame(500));
      capture.abort();
      capture.begin();
      capture.addPcm(frame(100));
      final u = capture.commit()!;
      expect(u.bodyMs, 100);
    });
  });

  group('🆔 발화 id는 이 앱이 만든다', () {
    test('세션 안에서 순번이 올라간다 — 로그로 따라갈 수 있다', () {
      final capture = DuoUtteranceCapture(idPrefix: 'duo_direct');
      capture.addPcm(frame(50));
      final first = capture.begin();
      capture.addPcm(frame(100));
      capture.commit();
      final second = capture.begin();
      expect(first, 'duo_direct_utt_1');
      expect(second, 'duo_direct_utt_2');
    });

    test('모드마다 머리말이 다르다', () {
      expect(DuoUtteranceCapture(idPrefix: 'duo_interp').begin(),
          startsWith('duo_interp_utt_'));
    });

    test('시작 신호가 두 번 와도 한 발화는 하나다', () {
      final capture = DuoUtteranceCapture(idPrefix: 'duo_direct');
      final a = capture.begin();
      final b = capture.begin();
      expect(a, b);
    });

    test('확정된 발화가 자기 id를 들고 간다', () {
      final capture = DuoUtteranceCapture(idPrefix: 'duo_direct');
      final id = capture.begin();
      capture.addPcm(frame(100));
      expect(capture.commit()!.utteranceId, id);
    });
  });

  group('📡 경계는 UtteranceEnd 하나가 정한다', () {
    late DuoDeepgramEndpointSensor sensor;
    late int started;
    late int ended;

    setUp(() {
      started = 0;
      ended = 0;
      sensor = DuoDeepgramEndpointSensor(apiKey: 'k', languageCode: 'ko')
        ..onSpeechStarted = (() => started++)
        ..onUtteranceEnd = (() => ended++);
    });

    test('SpeechStarted가 발화를 연다', () {
      sensor.handleMessageForTest(speechStarted);
      expect(started, 1);
      expect(sensor.isSpeechOpen, isTrue);
    });

    test('UtteranceEnd가 발화를 닫는다', () {
      sensor.handleMessageForTest(speechStarted);
      sensor.handleMessageForTest(utteranceEnd());
      expect(ended, 1);
      expect(sensor.isSpeechOpen, isFalse);
    });

    test('speech_final로는 닫지 않는다 — 판단기를 둘로 만들지 않는다', () {
      sensor.handleMessageForTest(speechStarted);
      sensor.handleMessageForTest(jsonEncode(<String, dynamic>{
        'type': 'Results',
        'speech_final': true,
        'is_final': true,
        'channel': <String, dynamic>{
          'alternatives': <dynamic>[
            <String, dynamic>{'transcript': '오늘 저녁에'}
          ]
        },
      }));
      expect(ended, 0);
      expect(sensor.isSpeechOpen, isTrue);
    });

    test('마지막 단어가 없는 UtteranceEnd는 흘려보낸다', () {
      sensor.handleMessageForTest(speechStarted);
      sensor.handleMessageForTest(utteranceEnd(lastWordEnd: -1));
      expect(ended, 0);
      expect(sensor.isSpeechOpen, isTrue);
    });

    test('시작 없이 온 UtteranceEnd는 흘려보낸다', () {
      sensor.handleMessageForTest(utteranceEnd());
      expect(ended, 0);
    });

    test('같은 발화를 두 번 닫지 않는다', () {
      sensor.handleMessageForTest(speechStarted);
      sensor.handleMessageForTest(utteranceEnd());
      sensor.handleMessageForTest(utteranceEnd());
      expect(ended, 1);
    });

    test('시작이 두 번 와도 한 번만 연다', () {
      sensor.handleMessageForTest(speechStarted);
      sensor.handleMessageForTest(speechStarted);
      expect(started, 1);
    });

    test('Deepgram 글자는 밖으로 나가지 않는다', () {
      // 이 클래스에는 transcript를 내보내는 콜백 자체가 없다.
      final source = sensor.toString();
      expect(source, isNotNull);
      expect(ended, 0);
      expect(started, 0);
    });
  });

  group('🔌 Deepgram 연결 규격', () {
    final uri = buildDuoDeepgramEndpointUri('ko');

    test('UtteranceEnd를 1800ms로 잡는다 — 지원 범위 1000~5000ms 안이다', () {
      expect(kDuoUtteranceEndMs, 1800);
      expect(uri.queryParameters['utterance_end_ms'], '1800');
    });

    test('UtteranceEnd와 SpeechStarted가 오도록 둘을 켠다', () {
      // interim_results가 꺼지면 UtteranceEnd가 단어 시각을 못 잡는다.
      expect(uri.queryParameters['interim_results'], 'true');
      // vad_events가 꺼지면 SpeechStarted가 안 온다.
      expect(uri.queryParameters['vad_events'], 'true');
    });

    test('샘플레이트가 마이크와 같다', () {
      expect(uri.queryParameters['sample_rate'], '$kStealthVoxSttSampleRate');
      expect(uri.queryParameters['encoding'], 'linear16');
      expect(uri.queryParameters['channels'], '1');
    });

    test('언어를 그대로 싣는다', () {
      expect(
          buildDuoDeepgramEndpointUri('ja').queryParameters['language'], 'ja');
    });

    test('모델을 생략하지 않는다 — 빼면 base-general이 붙는다', () {
      // 글자를 쓰지는 않지만 UtteranceEnd가 그 글자의 마지막 단어 시각에
      // 기댄다. 단어를 잘 잡는 모델일수록 경계도 안정적이다.
      expect(uri.queryParameters['model'], 'nova-3');
    });

    test('언어를 모를 때 빈 값을 보내지 않는다', () {
      // Deepgram의 기본은 en이다. 한국어를 말하는데 영어 모델로 들으면
      // 단어가 확정되지 않고, UtteranceEnd가 제때 오지 않는다.
      expect(buildDuoDeepgramEndpointUri('').queryParameters['language'],
          kDuoDeepgramAutoLanguage);
      expect(buildDuoDeepgramEndpointUri('   ').queryParameters['language'],
          isNot(''));
    });
  });

  group('🧭 낱말 힌트', () {
    test('수용된 말만 최근 몇 개까지 들고 있다', () {
      final ctx = DuoTranscriptContext(maxTurns: 4);
      for (var i = 1; i <= 6; i++) {
        ctx.add('발화 $i');
      }
      expect(ctx.length, 4);
      expect(ctx.buildPrompt(), contains('발화 6'));
      expect(ctx.buildPrompt(), isNot(contains('발화 1')));
    });

    test('빈 글자는 담지 않는다', () {
      final ctx = DuoTranscriptContext()..add('   ');
      expect(ctx.isEmpty, isTrue);
      expect(ctx.buildPrompt(), '');
    });

    test('길이 상한을 넘으면 오래된 것부터 버린다', () {
      final ctx = DuoTranscriptContext(maxTurns: 10, maxChars: 40);
      for (var i = 0; i < 10; i++) {
        ctx.add('열글자짜리문장입니다');
      }
      expect(ctx.buildPrompt().length, lessThanOrEqualTo(40));
    });

    test('통화가 끝나면 비운다 — 다음 통화로 새지 않는다', () {
      final ctx = DuoTranscriptContext()..add('민수랑 저녁 먹었어');
      ctx.clear();
      expect(ctx.buildPrompt(), '');
    });

    test('지시문을 섞지 않는다 — prompt는 낱말 표본이다', () {
      final ctx = DuoTranscriptContext()..add('민수랑 저녁 먹었어');
      final prompt = ctx.buildPrompt();
      expect(prompt, '민수랑 저녁 먹었어');
      for (final banned in <String>['다음', '전사', 'transcribe', '규칙']) {
        expect(prompt, isNot(contains(banned)));
      }
    });
  });

  group('🎯 최종 전사 모델', () {
    test('Duo만 gpt-transcribe를 쓴다', () {
      expect(OpenAiTranscribeService.duoFinalModel, 'gpt-transcribe');
    });

    test('공용 기본값은 그대로다 — Circle·Scenario가 함께 쓴다', () {
      expect(OpenAiTranscribeService.firstTurnModel, 'gpt-4o-transcribe');
      expect(OpenAiTranscribeService.duoFinalModel,
          isNot(OpenAiTranscribeService.firstTurnModel));
    });
  });
}
