// 🎙️ [DUO-FANOUT] 마이크 PCM이 어디로 갈라지는가를 지키는 시험.
//
// 성공 기준 한 문장:
//   "각 사용자의 음성을 자기 단말에서 local microphone PCM으로 전사하고,
//    상대에게는 PCM이 아니라 그 transcript 결과를 공유하며, 기존 Duo 실시간
//    통화 PCM relay는 그대로 유지한다."
//
// 여기서 지키는 것은 그 문장의 앞 두 조각이다. 릴레이 수신 PCM이 전사로
// 흘러들 수 있는 유일한 길은 `DuoMicPcmFanout.add`인데, 그 자리에 실제로
// 물리는 스트림은 위젯에서 `PreparedAudioCapture`(로컬 마이크) 하나뿐이다.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_direct_audio.dart';
import 'package:stealth_vox/custom_code/services/pcm_audio_utils.dart';

Uint8List _frame(int len, [int fill = 7]) =>
    Uint8List.fromList(List<int>.filled(len, fill));

void main() {
  group('DuoMicPcmFanout — 로컬 마이크 한 줄기가 두 갈래로', () {
    test('마이크 조각은 통화와 전사 양쪽으로 그대로 간다', () {
      final call = <Uint8List>[];
      final stt = <Uint8List>[];
      final fanout = DuoMicPcmFanout(
        speakerRole: 'HOST',
        toCall: call.add,
        toStt: stt.add,
      );

      final a = _frame(480);
      final b = _frame(960, 3);
      fanout.add(a);
      fanout.add(b);

      expect(call, <Uint8List>[a, b]);
      expect(stt, <Uint8List>[a, b]);
      // 같은 바이트다. 전사 갈래에서 다시 만지지 않는다(재샘플링 없음).
      expect(identical(call.first, stt.first), isTrue);
      expect(fanout.callBytes, 1440);
      expect(fanout.sttBytes, 1440);
      expect(fanout.sampleRate, kStealthVoxSttSampleRate);
    });

    test('전사 갈래가 무엇을 하든 통화 갈래는 이미 지나갔다', () {
      final call = <Uint8List>[];
      var sttCalls = 0;
      final fanout = DuoMicPcmFanout(
        speakerRole: 'GUEST',
        toCall: call.add,
        toStt: (_) {
          sttCalls++;
          throw StateError('transcribe socket down');
        },
      );

      for (var i = 0; i < 3; i++) {
        fanout.add(_frame(480));
      }

      // STT가 매번 던져도 통화 PCM은 세 조각 전부 나갔다.
      expect(call.length, 3);
      expect(sttCalls, 3);
      expect(fanout.callFrames, 3);
      expect(fanout.sttFrames, 0);
      expect(fanout.sttErrors, 3);
    });

    test('전사 게이트가 닫혀 있어도 통화 PCM은 계속 나간다', () {
      final call = <Uint8List>[];
      final stt = <Uint8List>[];
      var open = false;
      final fanout = DuoMicPcmFanout(
        speakerRole: 'HOST',
        toCall: call.add,
        toStt: stt.add,
        isSttOpen: () => open,
      );

      fanout.add(_frame(480));
      open = true;
      fanout.add(_frame(480));

      expect(call.length, 2);
      expect(stt.length, 1);
    });

    test('음소거는 두 갈래를 다 막는다 — 음소거 중 발화는 History에 안 남는다', () {
      final call = <Uint8List>[];
      final stt = <Uint8List>[];
      var muted = true;
      final fanout = DuoMicPcmFanout(
        speakerRole: 'HOST',
        toCall: call.add,
        toStt: stt.add,
        isMuted: () => muted,
      );

      fanout.add(_frame(480));
      expect(call, isEmpty);
      expect(stt, isEmpty);
      expect(fanout.mutedFrames, 1);

      muted = false;
      fanout.add(_frame(480));
      expect(call.length, 1);
      expect(stt.length, 1);
    });

    test('빈 조각은 어느 갈래로도 가지 않는다', () {
      final call = <Uint8List>[];
      final stt = <Uint8List>[];
      DuoMicPcmFanout(
        speakerRole: 'HOST',
        toCall: call.add,
        toStt: stt.add,
      ).add(Uint8List(0));
      expect(call, isEmpty);
      expect(stt, isEmpty);
    });

    test('진단 로그는 화자·출처·샘플레이트를 달고 나온다 (내용은 없다)', () {
      final logs = <String>[];
      final fanout = DuoMicPcmFanout(
        speakerRole: 'GUEST',
        toCall: (_) {},
        toStt: (_) {},
        logEveryFrames: 2,
        onLog: (tag, msg) => logs.add('$tag $msg'),
      );

      fanout.add(_frame(480));
      expect(logs, isEmpty);
      fanout.add(_frame(480));

      expect(logs.length, 1);
      expect(logs.single, startsWith('[DuoSTT] '));
      expect(logs.single, contains('speaker=GUEST'));
      expect(logs.single, contains('source=$kDuoSttPcmSourceLocalMic'));
      expect(logs.single, contains('sampleRate=$kStealthVoxSttSampleRate'));
      expect(logs.single, contains('bytes=960'));
      expect(logs.single, contains('seq=2'));
      // 오디오 내용(바이트 값)은 로그에 없다.
      expect(logs.single, isNot(contains('[7, 7')));
    });

    test('종료 요약에도 화자와 출처가 남는다', () {
      final fanout = DuoMicPcmFanout(
        speakerRole: 'HOST',
        toCall: (_) {},
        toStt: (_) {},
      );
      fanout.add(_frame(480));
      final summary = fanout.summary();
      expect(summary, contains('speaker=HOST'));
      expect(summary, contains('source=$kDuoSttPcmSourceLocalMic'));
      expect(summary, contains('callFrames=1'));
      expect(summary, contains('sttFrames=1'));
    });
  });

  group('갈래 3 — 진단 비교기(개발 빌드 전용)', () {
    test('물리지 않으면 아무 일도 없다 — release가 이 상태다', () {
      final call = <Uint8List>[];
      final stt = <Uint8List>[];
      final fanout = DuoMicPcmFanout(
        speakerRole: 'HOST',
        toCall: call.add,
        toStt: stt.add,
      );
      fanout.add(_frame(480));
      expect(call.length, 1);
      expect(stt.length, 1);
      expect(fanout.probeFrames, 0);
      expect(fanout.probeErrors, 0);
    });

    test('물리면 같은 조각을 세 갈래가 모두 받는다', () {
      final call = <Uint8List>[];
      final stt = <Uint8List>[];
      final probe = <Uint8List>[];
      final fanout = DuoMicPcmFanout(
        speakerRole: 'HOST',
        toCall: call.add,
        toStt: stt.add,
        toProbe: probe.add,
      );
      final a = _frame(480);
      fanout.add(a);
      expect(identical(call.single, a), isTrue);
      expect(identical(stt.single, a), isTrue);
      expect(identical(probe.single, a), isTrue);
      expect(fanout.probeFrames, 1);
    });

    test('전사 게이트가 닫혀 있어도 진단기는 계속 받는다', () {
      // pre-roll을 모으려면 게이트와 무관하게 소리가 들어와야 한다.
      final call = <Uint8List>[];
      final stt = <Uint8List>[];
      final probe = <Uint8List>[];
      final fanout = DuoMicPcmFanout(
        speakerRole: 'HOST',
        toCall: call.add,
        toStt: stt.add,
        toProbe: probe.add,
        isSttOpen: () => false,
      );
      fanout.add(_frame(480));
      expect(stt, isEmpty);
      expect(call.length, 1);
      expect(probe.length, 1);
    });

    test('진단기가 던져도 통화·전사는 이미 지나간 뒤다', () {
      final call = <Uint8List>[];
      final stt = <Uint8List>[];
      final fanout = DuoMicPcmFanout(
        speakerRole: 'HOST',
        toCall: call.add,
        toStt: stt.add,
        toProbe: (_) => throw StateError('probe blew up'),
      );
      fanout.add(_frame(480));
      fanout.add(_frame(480));
      expect(call.length, 2);
      expect(stt.length, 2);
      expect(fanout.probeErrors, 2);
      expect(fanout.probeFrames, 0);
    });

    test('음소거 중에는 진단기도 받지 않는다', () {
      final probe = <Uint8List>[];
      final fanout = DuoMicPcmFanout(
        speakerRole: 'HOST',
        toCall: (_) {},
        toStt: (_) {},
        toProbe: probe.add,
        isMuted: () => true,
      );
      fanout.add(_frame(480));
      expect(probe, isEmpty);
    });

    test('종료 요약에 진단 갈래도 실린다', () {
      final fanout = DuoMicPcmFanout(
        speakerRole: 'HOST',
        toCall: (_) {},
        toStt: (_) {},
        toProbe: (_) {},
      );
      fanout.add(_frame(480));
      expect(fanout.summary(), contains('probeFrames=1'));
      expect(fanout.summary(), contains('probeErrors=0'));
    });
  });

  group('DuoRemotePcmMeter — 상대 PCM은 재생까지만', () {
    test('계측기에는 전사로 나가는 출구가 없다', () {
      final logs = <String>[];
      final meter = DuoRemotePcmMeter(
        logEveryFrames: 2,
        onLog: (tag, msg) => logs.add('$tag $msg'),
      );

      meter.note(_frame(480));
      meter.note(_frame(480));

      expect(meter.frames, 2);
      expect(meter.bytes, 960);
      expect(logs.single, startsWith('[DuoAudio] '));
      expect(logs.single, contains('direction=remote_playback'));
      expect(logs.single, contains('bytes=960'));
      expect(logs.single, contains('seq=2'));
      // 이 클래스가 내보내는 건 숫자뿐이다. PCM을 넘겨받는 콜백이 없다.
      expect(logs.single, isNot(contains('source=$kDuoSttPcmSourceLocalMic')));
    });

    test('빈 조각은 세지 않는다', () {
      final meter = DuoRemotePcmMeter();
      meter.note(Uint8List(0));
      expect(meter.frames, 0);
      expect(meter.bytes, 0);
    });
  });
}
