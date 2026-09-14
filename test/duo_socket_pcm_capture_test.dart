// 🎙️ [SOCKET-PCM] 소켓 전사 갈래에서도 발화 소리가 남는가.
//
// 이 갈래는 PCM을 소켓으로 흘려보내고 앱에 한 조각도 안 남겼다. 그래서
// 로비값 재확인(origin probe)도, 통화 후 History 재전사도 설 자리가 없었다.
// **경계는 여전히 서버가 준다** — 여기서 새로 판정하는 것은 하나도 없다.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_socket_pcm_capture.dart';
import 'package:stealth_vox/custom_code/services/duo_utterance_capture.dart';
import 'package:stealth_vox/custom_code/services/pcm_audio_utils.dart';

/// 24kHz·16bit 기준 [ms]만큼의 조각. 값은 0이 아니어야 한다 — 빈 발화 판정에
/// 걸리지 않게 한다.
Uint8List frame(int ms) =>
    Uint8List.fromList(List<int>.filled(kStealthVoxSttSampleRate * 2 * ms ~/ 1000, 7));

/// 실제 마이크처럼 **잘게 나눠** 넣는다.
///
/// 고리는 조각 단위로만 자르므로(`_preRoll.removeAt(0)`), 한 덩이로 넣으면
/// 잘라 낼 수가 없다. 실기기는 20ms 안팎으로 올라오니 그 모양을 따른다.
void feed(DuoSocketPcmCapture cap, int totalMs, {int chunkMs = 20}) {
  for (var sent = 0; sent < totalMs; sent += chunkMs) {
    cap.addPcm(frame(chunkMs));
  }
}

void main() {
  late DuoSocketPcmCapture cap;

  setUp(() => cap = DuoSocketPcmCapture());

  group('서버 경계에 맞춰 한 덩이를 만든다', () {
    test('begin → commit 이 서버가 준 item_id를 단다', () {
      cap.addPcm(frame(100));
      cap.beginSpeech();
      cap.addPcm(frame(500));
      final u = cap.commitSpeech('item_abc');
      expect(u, isNotNull);
      // 창고 열쇠와 히스토리 pcm_key가 이 값이다. 우리가 매긴 번호를 쓰면
      // 나중에 그 소리를 찾을 수 없다.
      expect(u!.utteranceId, 'item_abc');
      expect(u.pcm.isNotEmpty, isTrue);
      expect(cap.committedCount, 1);
    });

    test('서버 id가 비어 오면 우리 번호로 떨어진다', () {
      cap.beginSpeech();
      cap.addPcm(frame(300));
      final u = cap.commitSpeech('');
      expect(u, isNotNull);
      expect(u!.utteranceId, startsWith('duo_interp_utt_'));
    });

    test('담은 적 없으면 null이다 — 빈 덩이를 내보내지 않는다', () {
      expect(cap.commitSpeech('item_x'), isNull);
      expect(cap.droppedCount, 1);
    });
  });

  group('앞 여유가 첫 음절을 되살린다', () {
    test('begin 전에 들어온 소리가 발화 앞에 붙는다', () {
      // 서버의 speech_started는 왕복을 거쳐 늦게 온다. 그 사이 소리가
      // 고리에 있어야 첫 음절이 산다.
      cap.addPcm(frame(400));
      cap.beginSpeech();
      cap.addPcm(frame(600));
      final u = cap.commitSpeech('item_1')!;
      expect(u.preRollMs, greaterThan(0),
          reason: '앞 여유가 0이면 첫 음절을 잃은 것이다');
      expect(u.durationMs, greaterThanOrEqualTo(900));
    });

    test('앞 여유는 기본 고리 길이를 넘지 않는다', () {
      feed(cap, kDuoCapturePreRollMs * 3);
      cap.beginSpeech();
      cap.addPcm(frame(200));
      final u = cap.commitSpeech('item_1')!;
      expect(u.preRollMs, lessThanOrEqualTo(kDuoCapturePreRollMs + 50));
    });
  });

  group('문은 소리 보존을 막지 않는다', () {
    test('문이 닫힌 동안에도 계속 담는다', () {
      cap.onGateClosed();
      feed(cap, 3000);
      expect(cap.preRollBufferedMs, greaterThan(kDuoCapturePreRollMs),
          reason: '문이 닫히면 소리를 버리고 있다');
    });

    test('문이 닫힌 고리는 상한에서 멈춘다 — 무한 가변이 아니다', () {
      cap.onGateClosed();
      feed(cap, kDuoCaptureGateClosedRingMs * 2);
      expect(cap.preRollBufferedMs,
          lessThanOrEqualTo(kDuoCaptureGateClosedRingMs + 100));
    });

    test('문이 열리면 곧바로 평소 길이로 돌아온다', () {
      cap.onGateClosed();
      feed(cap, 8000);
      cap.onGateOpened();
      expect(cap.preRollBufferedMs, lessThanOrEqualTo(kDuoCapturePreRollMs + 100),
          reason: '늘어난 고리가 남아 다음 발화 앞에 몇 초가 붙는다');
    });
  });

  group('abort는 발화만 버리고 고리는 지킨다', () {
    test('담던 발화는 사라지고 그 뒤 소리는 다음 발화의 앞 여유가 된다', () {
      cap.beginSpeech();
      cap.addPcm(frame(500));
      cap.abortSpeech('tts_playing');
      expect(cap.isCapturing, isFalse);
      // 버린 뒤에 들어온 소리는 고리에 쌓인다.
      cap.addPcm(frame(400));
      cap.beginSpeech();
      cap.addPcm(frame(300));
      final u = cap.commitSpeech('item_next')!;
      expect(u.preRollMs, greaterThan(0),
          reason: 'abort가 고리까지 비웠다 — 다음 발화의 첫 음절을 잃는다');
    });

    test('담고 있지 않을 때 abort는 아무 일도 안 한다', () {
      cap.addPcm(frame(400));
      cap.abortSpeech('idle');
      cap.beginSpeech();
      cap.addPcm(frame(200));
      expect(cap.commitSpeech('item_1'), isNotNull);
    });
  });

  group('통화 한 통짜리다', () {
    test('reset 뒤에는 고리도 비어 있다', () {
      cap.addPcm(frame(800));
      cap.reset();
      cap.beginSpeech();
      cap.addPcm(frame(200));
      final u = cap.commitSpeech('item_1')!;
      expect(u.preRollMs, 0,
          reason: '이전 통화의 소리가 다음 통화 첫 발화에 붙는다');
    });
  });
}
