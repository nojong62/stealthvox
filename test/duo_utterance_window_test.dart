// 🎧 [DUO-WINDOW] 한 발화를 **온전히** 담는 두 개의 창을 값으로 고정한다
//
// 구조는 이미 서 있다(`duo_stt_endpoint_test.dart`가 그 규칙을 지킨다).
// 여기서 지키는 것은 그 구조가 쓰는 **두 개의 시간**뿐이다.
//
//   앞 창  [kDuoCapturePreRollMs]  SpeechStarted가 늦게 와도 첫 음절을 지킨다
//   뒤 창  [kDuoUtteranceEndMs]    문장 안의 숨 고르기에서 끊기지 않는다
//
// 두 값 모두 실기기 실측에서 나왔다. 다음 사람이 "느리다"며 되돌리는 것을
// 막으려고 근거를 값 옆(각 상수의 주석)과 여기 시험 양쪽에 적어 둔다.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_deepgram_endpoint.dart';
import 'package:stealth_vox/custom_code/services/duo_utterance_capture.dart';
import 'package:stealth_vox/custom_code/services/pcm_audio_utils.dart';

/// [ms] 길이의 조각 하나. [fill]로 조각마다 다른 소리를 흉내 낸다 —
/// 발화 두 개가 섞이지 않았음을 바이트로 확인하기 위해서다.
Uint8List frame(int ms, {int fill = 0}) {
  final int bytes = ms * kStealthVoxSttSampleRate * 2 ~/ 1000;
  return Uint8List(bytes)..fillRange(0, bytes, fill);
}

String utteranceEnd({num lastWordEnd = 3.2}) => jsonEncode(<String, dynamic>{
      'type': 'UtteranceEnd',
      'last_word_end': lastWordEnd,
    });

/// Deepgram이 글자를 확정하며 보내는 이벤트. **커밋 신호가 아니다.**
String results({bool speechFinal = false}) => jsonEncode(<String, dynamic>{
      'type': 'Results',
      'is_final': true,
      'speech_final': speechFinal,
      'channel': <String, dynamic>{
        'alternatives': <dynamic>[
          <String, dynamic>{'transcript': '오늘 저녁에'}
        ]
      },
    });

const String speechStarted = '{"type":"SpeechStarted"}';

void main() {
  // ── A. 값 ────────────────────────────────────────────────────────────
  group('🕰️ 두 창의 값', () {
    test('뒤 창은 1800ms다 — 실측된 가장 긴 숨 고르기(1164ms) 위로 636ms', () {
      expect(kDuoUtteranceEndMs, 1800);
    });

    test('Deepgram 지원 범위(1000~5000ms) 안이다', () {
      expect(kDuoUtteranceEndMs, greaterThanOrEqualTo(1000));
      expect(kDuoUtteranceEndMs, lessThanOrEqualTo(5000));
    });

    test('그 값이 소켓 주소에 그대로 실린다', () {
      expect(buildDuoDeepgramEndpointUri('ko')
          .queryParameters['utterance_end_ms'], '1800');
    });

    test('앞 창은 1000ms다 — SpeechStarted가 늦어도 첫 음절을 잃지 않는다', () {
      expect(kDuoCapturePreRollMs, 1000);
    });

    test('발화 상한은 그대로 30초다 — 이번 작업의 범위가 아니다', () {
      expect(kDuoCaptureMaxUtteranceMs, 30000);
    });
  });

  // ── B. pre-roll ──────────────────────────────────────────────────────
  group('🎙️ 앞 창은 시작 신호가 늦어도 첫 음절을 지킨다', () {
    test('시작 신호 앞의 소리가 최대 1000ms까지 발화에 붙는다', () {
      final capture = DuoUtteranceCapture(idPrefix: 'duo_direct');
      // 통화 내내 소리는 들어온다. 고리는 그중 뒤쪽 1000ms만 들고 있는다.
      for (var i = 0; i < 15; i++) {
        capture.addPcm(frame(100));
      }
      expect(capture.preRollBufferedMs, 1000);
      capture.begin();
      capture.addPcm(frame(500));
      final u = capture.commit()!;
      expect(u.preRollMs, 1000);
      expect(u.bodyMs, 500);
      expect(u.durationMs, 1500);
    });

    test('900ms 늦게 온 신호에서도 앞이 통째로 남는다 — 600ms였다면 잘렸다', () {
      final capture = DuoUtteranceCapture(idPrefix: 'duo_direct');
      for (var i = 0; i < 9; i++) {
        capture.addPcm(frame(100));
      }
      capture.begin();
      capture.addPcm(frame(200));
      final u = capture.commit()!;
      expect(u.preRollMs, 900, reason: '앞 창이 600이면 여기서 300ms를 잃었다');
    });

    test('고리는 1000ms를 넘지 않는다 — 통화가 길어도 메모리가 평평하다', () {
      final capture = DuoUtteranceCapture(idPrefix: 'duo_direct');
      for (var i = 0; i < 200; i++) {
        capture.addPcm(frame(100));
      }
      expect(capture.preRollBufferedMs, lessThanOrEqualTo(kDuoCapturePreRollMs));
    });
  });

  // ── C·D. 커밋은 UtteranceEnd 하나에서 한 번만 ─────────────────────────
  group('📡 커밋은 UtteranceEnd 한 번에 한 번뿐이다', () {
    late DuoDeepgramEndpointSensor sensor;
    late DuoUtteranceCapture capture;
    late List<DuoCapturedUtterance> committed;

    setUp(() {
      committed = <DuoCapturedUtterance>[];
      capture = DuoUtteranceCapture(idPrefix: 'duo_direct');
      // 본선과 같은 배선이다(`DuoSttPipeline`). 경계가 담기를 시키고,
      // 담기가 소리를 확정한다.
      sensor = DuoDeepgramEndpointSensor(apiKey: 'k', languageCode: 'ko')
        ..onSpeechStarted = capture.begin
        ..onUtteranceEnd = (() {
          final u = capture.commit();
          if (u != null) committed.add(u);
        });
    });

    test('한 발화에 확정도 한 번이다', () {
      sensor.handleMessageForTest(speechStarted);
      capture.addPcm(frame(400));
      sensor.handleMessageForTest(utteranceEnd());
      expect(committed.length, 1);
      expect(committed.single.bodyMs, 400);
    });

    test('speech_final이 와도 추가로 확정되지 않는다', () {
      sensor.handleMessageForTest(speechStarted);
      capture.addPcm(frame(400));
      sensor.handleMessageForTest(results(speechFinal: true));
      expect(committed, isEmpty, reason: 'speech_final은 커밋 신호가 아니다');
      sensor.handleMessageForTest(utteranceEnd());
      expect(committed.length, 1);
    });

    test('글자(Results)가 여러 번 와도 확정 횟수는 그대로다', () {
      sensor.handleMessageForTest(speechStarted);
      capture.addPcm(frame(200));
      for (var i = 0; i < 5; i++) {
        sensor.handleMessageForTest(results());
      }
      capture.addPcm(frame(200));
      sensor.handleMessageForTest(utteranceEnd());
      expect(committed.length, 1);
      expect(committed.single.bodyMs, 400,
          reason: '글자가 오가는 동안에도 소리는 계속 담긴다');
    });

    test('UtteranceEnd가 두 번 와도 한 번만 확정한다', () {
      sensor.handleMessageForTest(speechStarted);
      capture.addPcm(frame(300));
      sensor.handleMessageForTest(utteranceEnd());
      sensor.handleMessageForTest(utteranceEnd());
      expect(committed.length, 1);
    });
  });

  // ── E. 발화 독립성 ───────────────────────────────────────────────────
  group('🧊 확정된 발화는 서로 섞이지 않는다', () {
    test('앞 발화의 전사가 도는 동안 다음 발화가 시작돼도 바이트가 안 섞인다', () {
      final capture = DuoUtteranceCapture(idPrefix: 'duo_direct');
      capture.begin();
      capture.addPcm(frame(200, fill: 0x11));
      // 첫 발화 확정. 본선은 이 스냅샷을 들고 gpt-transcribe로 간다.
      final first = capture.commit()!;
      final int firstLength = first.pcm.length;

      // 전사가 아직 도는 사이에 다음 말이 시작된다.
      capture.begin();
      capture.addPcm(frame(300, fill: 0x22));
      final second = capture.commit()!;

      expect(first.pcm.length, firstLength, reason: '앞 스냅샷은 자라지 않는다');
      expect(first.pcm.every((b) => b == 0x11), isTrue);
      expect(second.pcm.every((b) => b == 0x22), isTrue);
      expect(first.utteranceId, isNot(second.utteranceId));
    });

    test('다음 발화의 조각이 이미 확정된 스냅샷을 건드리지 못한다', () {
      final capture = DuoUtteranceCapture(idPrefix: 'duo_direct');
      capture.begin();
      capture.addPcm(frame(100, fill: 0x33));
      final snapshot = capture.commit()!;
      final Uint8List copy = Uint8List.fromList(snapshot.pcm);

      capture.begin();
      capture.addPcm(frame(100, fill: 0x44));
      capture.addPcm(frame(100, fill: 0x44));
      capture.commit();

      expect(snapshot.pcm, copy);
    });

    test('버려진 발화의 소리도 다음 발화로 새지 않는다', () {
      final capture = DuoUtteranceCapture(idPrefix: 'duo_direct');
      capture.begin();
      capture.addPcm(frame(500, fill: 0x55));
      capture.abort();
      capture.begin();
      capture.addPcm(frame(100, fill: 0x66));
      final u = capture.commit()!;
      expect(u.bodyMs, 100);
      expect(u.pcm.every((b) => b == 0x66), isTrue);
    });
  });

  // ── §10. 짧은 대답이 담기는 단계에서 사라지지 않는다 ──────────────────
  group('🗣️ 짧은 대답도 그대로 담긴다', () {
    test('"응"·"네" 길이의 발화도 확정된다 — 담기에는 문턱이 없다', () {
      for (final int ms in <int>[200, 300, 400]) {
        final capture = DuoUtteranceCapture(idPrefix: 'duo_direct');
        capture.begin();
        capture.addPcm(frame(ms));
        final u = capture.commit();
        expect(u, isNotNull, reason: '$ms ms 발화가 담기 단계에서 사라졌다');
        expect(u!.bodyMs, ms);
      }
    });

    test('조용한 소리도 버리지 않는다 — 여기는 귀가 아니라 손이다', () {
      // 전부 0인 조각(삼성 AEC가 누른 구간)도 담는다. 무엇이 말인지는
      // 바깥(Deepgram)이 정하고, 세기 판정은 게이트가 따로 한다.
      final capture = DuoUtteranceCapture(idPrefix: 'duo_direct');
      capture.begin();
      capture.addPcm(frame(250, fill: 0));
      expect(capture.commit(), isNotNull);
    });
  });

  // ── F. 오디오 규격은 그대로다 ─────────────────────────────────────────
  group('🎚️ 24kHz · mono · PCM16은 그대로다', () {
    test('앱 전체가 쓰는 샘플레이트가 그대로다', () {
      expect(kStealthVoxSttSampleRate, 24000);
      expect(kStealthVoxSttBytesPerMs, 48);
    });

    test('소켓 주소의 규격이 마이크와 같다', () {
      final uri = buildDuoDeepgramEndpointUri('ko');
      expect(uri.queryParameters['sample_rate'], '$kStealthVoxSttSampleRate');
      expect(uri.queryParameters['encoding'], 'linear16');
      expect(uri.queryParameters['channels'], '1');
    });

    test('확정된 스냅샷의 길이 셈이 24k·mono·16bit 그대로다', () {
      final capture = DuoUtteranceCapture(idPrefix: 'duo_direct');
      capture.begin();
      capture.addPcm(frame(1000));
      final u = capture.commit()!;
      expect(u.sampleRate, 24000);
      expect(u.pcm.length, 48000);
      expect(u.durationMs, 1000);
    });

    test('WAV 포장의 머리글이 같은 값을 적는다', () {
      final wav = pcm16ToWav(frame(100), sampleRate: kStealthVoxSttSampleRate);
      final view = ByteData.sublistView(wav);
      expect(view.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(view.getUint32(24, Endian.little), 24000);
      expect(view.getUint16(34, Endian.little), 16, reason: 'PCM16');
    });
  });
}
