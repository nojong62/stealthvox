// 🕰️ [STALE-SPEECH] 헛 열린 발화가 상대 목소리를 막지 못하게 한다
//
// SpeechStarted는 VAD가 내는 신호라 잡음에도 열린다. 그런데 UtteranceEnd는
// **마지막으로 확정된 단어** 뒤의 공백을 재므로, 단어가 하나도 안 잡히면 종료
// 신호가 영영 오지 않는다. 그 발화는 열린 채로 굳는다.
//
// 2026-09-07 실기기 통역에서 그 일이 났다.
//
//   16:41:50  [INTERP-YIELD] deferred queued=1 reason=user_speaking
//   16:41:54  [INTERP-YIELD] deferred queued=2 reason=user_speaking
//   16:42:06  [INTERP-YIELD] deferred queued=3 reason=user_speaking
//   ...       ⚠️ 통화 마이크 무음  outLevel=0.000  (35초 내내)
//   16:42:31  [KEEP-ALL] queue_to_history reason=guest_left left=3
//   16:42:32  closing started=3 ended=2
//
// 마이크는 무음인데 발화가 열린 채 굳었고, "말하는 중"을 보고 상대 목소리를
// 미루는 INTERP-YIELD가 세 마디를 끝까지 안 틀었다.
//
// ⚠️ **소리는 버리지 않는다.** 내리는 것은 "말하는 중" 표시뿐이고 담기는
//   그대로 이어진다 — 조용히 말한 진짜 발화였다면 단어가 늦게라도 잡히고,
//   그때 UtteranceEnd가 평소대로 확정한다.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_deepgram_endpoint.dart';

const String speechStarted = '{"type":"SpeechStarted"}';

String utteranceEnd({num lastWordEnd = 3.2}) => jsonEncode(<String, dynamic>{
      'type': 'UtteranceEnd',
      'last_word_end': lastWordEnd,
    });

/// 단어가 실린 Results. Deepgram이 경계를 재는 재료다.
String results(String transcript) => jsonEncode(<String, dynamic>{
      'type': 'Results',
      'is_final': false,
      'channel': <String, dynamic>{
        'alternatives': <dynamic>[
          <String, dynamic>{'transcript': transcript}
        ]
      },
    });

/// 굳는 시각을 넘겨 기다린다.
Future<void> pastStale() =>
    Future<void>.delayed(const Duration(milliseconds: kDuoSpeechStaleMs + 250));

void main() {
  late DuoDeepgramEndpointSensor sensor;
  late int stale;
  late int ended;

  setUp(() {
    stale = 0;
    ended = 0;
    sensor = DuoDeepgramEndpointSensor(apiKey: 'k', languageCode: 'ko')
      ..onSpeechStale = (() => stale++)
      ..onUtteranceEnd = (() => ended++);
  });

  tearDown(() async {
    await sensor.close();
  });

  group('🕰️ 단어가 안 잡히면 말하는 중을 내린다', () {
    test('발화가 열린 직후에는 말하는 중이다', () {
      sensor.handleMessageForTest(speechStarted);
      expect(sensor.isSpeechOpen, isTrue);
      expect(sensor.isUserSpeaking, isTrue);
    });

    test('단어 없이 시간이 지나면 말하는 중이 내려간다', () async {
      sensor.handleMessageForTest(speechStarted);
      await pastStale();
      expect(sensor.isUserSpeaking, isFalse, reason: '굳은 발화는 말하는 중이 아니다');
      expect(stale, 1, reason: '통역이 미뤄 둔 소리를 풀 수 있어야 한다');
    });

    test('발화 자체는 닫지 않는다 — 소리는 계속 담긴다', () async {
      sensor.handleMessageForTest(speechStarted);
      await pastStale();
      expect(sensor.isSpeechOpen, isTrue,
          reason: '닫으면 늦게 잡힌 단어를 확정할 자리가 사라진다');
      expect(ended, 0, reason: '커밋은 UtteranceEnd 하나뿐이다');
    });

    test('굳은 뒤에도 UtteranceEnd가 오면 평소대로 확정한다', () async {
      sensor.handleMessageForTest(speechStarted);
      await pastStale();
      sensor.handleMessageForTest(utteranceEnd());
      expect(ended, 1);
      expect(sensor.isSpeechOpen, isFalse);
    });
  });

  group('🗣️ 단어가 잡히면 굳지 않는다', () {
    test('단어가 계속 오면 말하는 중이 유지된다', () async {
      sensor.handleMessageForTest(speechStarted);
      await Future<void>.delayed(
          const Duration(milliseconds: kDuoSpeechStaleMs ~/ 2));
      sensor.handleMessageForTest(results('오늘'));
      await Future<void>.delayed(
          const Duration(milliseconds: kDuoSpeechStaleMs ~/ 2 + 100));
      expect(sensor.isUserSpeaking, isTrue, reason: '단어가 감시를 다시 감는다');
      expect(stale, 0);
    });

    test('굳은 뒤에 단어가 잡히면 되살아난다', () async {
      sensor.handleMessageForTest(speechStarted);
      await pastStale();
      expect(sensor.isUserSpeaking, isFalse);
      sensor.handleMessageForTest(results('아직'));
      expect(sensor.isUserSpeaking, isTrue, reason: '늦게 말하기 시작한 경우다');
    });

    test('빈 글자는 단어로 치지 않는다', () async {
      sensor.handleMessageForTest(speechStarted);
      sensor.handleMessageForTest(results('   '));
      await pastStale();
      expect(sensor.isUserSpeaking, isFalse);
      expect(stale, 1);
    });
  });

  group('🚫 글자는 여전히 밖으로 안 나간다', () {
    test('Results를 받아도 전사 콜백이 없다', () async {
      // 이 클래스에는 transcript를 내보내는 콜백 자체가 없다. 단어의 **존재**만
      // 읽고 글자는 버린다.
      sensor.handleMessageForTest(speechStarted);
      sensor.handleMessageForTest(results('민수랑 저녁 먹었어'));
      expect(ended, 0);
      expect(sensor.isUserSpeaking, isTrue);
    });

    test('speech_final은 여전히 커밋 신호가 아니다', () async {
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
  });

  group('🕰️ 굳는 시각', () {
    test('3초다 — 진짜 발화는 그 안에 단어가 잡힌다', () {
      expect(kDuoSpeechStaleMs, 3000);
    });

    test('발화 종료를 재는 침묵보다 길어야 한다', () {
      // 정상 발화에서는 마지막 단어가 두 시계를 나란히 세운다.
      //   UtteranceEnd  마지막 단어 + 1800ms  → 여기서 확정된다
      //   stale         마지막 단어 + 3000ms  → 그 전에 취소된다
      // 이 순서가 뒤집히면 멀쩡한 발화가 확정되기 전에 굳었다고 판정되고,
      // 상대 목소리가 내 말 위로 끼어든다.
      expect(kDuoSpeechStaleMs, greaterThan(kDuoUtteranceEndMs));
    });
  });
}
