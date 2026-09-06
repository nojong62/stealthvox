// 🔬 [DUO-OBSERVE] "GPT에 실제로 보낸 그 소리"를 관찰하는 장치의 시험.
//
// 예전에는 A/B 비교(스트리밍 vs 파일)였고, 그래서 이 장치가 소리도 **자기가
// 따로** 모았다. 전사 경로가 하나로 줄면서 비교할 상대가 없어졌고, 소리를
// 모으는 일도 본선(`DuoUtteranceCapture`)으로 옮겼다.
//
// 그래서 여기서 지키는 것은 하나다.
//   **진단이 보는 PCM = 본선이 gpt-transcribe에 보낸 PCM**
// 둘이 갈라지면 "WAV는 멀쩡한데 전사만 틀렸다"는 관찰을 믿을 수 없게 된다.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_stt_ab_probe.dart';
import 'package:stealth_vox/custom_code/services/duo_utterance_capture.dart';
import 'package:stealth_vox/custom_code/services/pcm_audio_utils.dart';

/// 값이 채워진 PCM16 조각. 바이트 값으로 어느 조각인지 구별한다.
Uint8List _frame(int bytes, int fill) =>
    Uint8List.fromList(List<int>.filled(bytes, fill));

/// 24kHz mono 기준 [ms] 밀리초 분량의 바이트 수.
int _bytesFor(int ms) => ms * (kStealthVoxSttSampleRate * 2 ~/ 1000);

void main() {
  late List<String> logs;

  setUp(() => logs = <String>[]);


  // 🔬 [DUO-OBSERVE] 진단은 이제 **소리를 모으지 않는다.**
  //
  //   pre-roll·발화 버퍼·상한은 본선(`DuoUtteranceCapture`)으로 옮겼고,
  //   그 규칙은 `duo_stt_endpoint_test.dart`가 값으로 지킨다. 여기서는
  //   진단이 **본선이 확정한 바로 그 PCM**을 건네받는지만 본다.
  group('🔬 본선이 확정한 그 소리를 그대로 관찰한다', () {
    test('건네받은 발화의 바이트가 그대로 남는다', () async {
      final probe = DuoSttAbProbe(
        speakerRole: 'HOST',
        languageCode: 'ko',
        onLog: (tag, msg) => logs.add('$tag $msg'),
      );
      final capture = DuoUtteranceCapture(idPrefix: 'duo_direct');
      capture.begin();
      capture.addPcm(Uint8List.fromList(<int>[1, 2, 3, 4]));
      capture.addPcm(Uint8List.fromList(<int>[5, 6]));
      final u = capture.commit()!;
      probe.observe(u, voicedMs: 900);
      expect(probe.pendingCount, 1);
      await probe.noteTranscript(u.utteranceId, '안녕하세요');
      expect(probe.pendingCount, 0);
      // 소리의 상태와 글자가 같은 발화 id로 남는다.
      expect(logs.any((l) => l.contains('DuoSTT-PCM') && l.contains(u.utteranceId)),
          isTrue);
      expect(
          logs.any((l) =>
              l.contains('DuoSTT-OBS') && l.contains('text="안녕하세요"')),
          isTrue);
    });

    test('소리를 못 받은 발화는 조용히 건너뛴다', () async {
      final probe = DuoSttAbProbe(
        speakerRole: 'HOST',
        languageCode: 'ko',
        onLog: (tag, msg) => logs.add('$tag $msg'),
      );
      await probe.noteTranscript('duo_direct_utt_9', '무슨 말');
      expect(logs.any((l) => l.contains('reason=no_audio')), isTrue);
    });

    test('기다리는 발화가 상한을 넘으면 오래된 것부터 버린다', () {
      final probe = DuoSttAbProbe(speakerRole: 'HOST', languageCode: 'ko');
      for (var i = 0; i < kDuoAbMaxPending + 3; i++) {
        final capture = DuoUtteranceCapture(idPrefix: 'duo_direct_$i');
        capture.begin();
        capture.addPcm(Uint8List.fromList(<int>[1, 2]));
        probe.observe(capture.commit()!);
      }
      expect(probe.pendingCount, kDuoAbMaxPending);
    });

    test('빈 발화는 담지 않는다', () {
      final probe = DuoSttAbProbe(speakerRole: 'HOST', languageCode: 'ko');
      final capture = DuoUtteranceCapture(idPrefix: 'duo_direct');
      capture.begin();
      expect(capture.commit(), isNull);
      expect(probe.pendingCount, 0);
    });
  });

  group('measurePcm16 — 소리의 상태를 잰다', () {
    Uint8List tone(int samples, int amplitude) {
      final data = ByteData(samples * 2);
      for (var i = 0; i < samples; i++) {
        data.setInt16(i * 2, i.isEven ? amplitude : -amplitude, Endian.little);
      }
      return data.buffer.asUint8List();
    }

    test('무음은 조용하고 무음 비율이 100%다', () {
      final stats = measurePcm16(Uint8List(2000));
      expect(stats.rmsDbfs, lessThan(-100));
      expect(stats.silentPercent, 100);
      expect(stats.clippedPercent, 0);
    });

    test('꽉 찬 소리는 클리핑으로 잡힌다', () {
      final stats = measurePcm16(tone(1000, 32760));
      expect(stats.clippedPercent, greaterThan(99));
      expect(stats.peakDbfs, greaterThan(-0.1));
    });

    test('보통 말소리 세기는 -30~-15 언저리로 나온다', () {
      // 0.1 진폭 ≒ -20dBFS.
      final stats = measurePcm16(tone(1000, 3277));
      expect(stats.rmsDbfs, greaterThan(-25));
      expect(stats.rmsDbfs, lessThan(-15));
      expect(stats.clippedPercent, 0);
      expect(stats.silentPercent, 0);
    });

    test('빈 버퍼도 죽지 않는다', () {
      final stats = measurePcm16(Uint8List(0));
      expect(stats.silentPercent, 100);
    });
  });

  group('통화를 방해하지 않는다', () {
    test('dispose 뒤에는 아무것도 받지 않는다', () async {
      final probe = DuoSttAbProbe(
        speakerRole: 'HOST',
        languageCode: 'ko',
        onLog: (tag, msg) => logs.add('$tag $msg'),
      );
      final capture = DuoUtteranceCapture(idPrefix: 'duo_direct');
      capture.begin();
      capture.addPcm(_frame(480, 1));
      final u = capture.commit()!;
      probe.dispose();

      probe.observe(u);
      await probe.noteTranscript(u.utteranceId, '네');
      expect(probe.pendingCount, 0);
      expect(logs, isEmpty);
    });
  });

  _callRecorderTests();
}

// ── 통짜 녹음 ──────────────────────────────────────────────────────
// 발화 조각이 다 같이 틀렸을 때 "소리가 나쁜가, 분절이 나쁜가"를 가르는 파일.

void _callRecorderTests() {
  group('DuoAbCallRecorder — 통화 한 통을 WAV 하나로', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('duo_ab_call_');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('헤더의 크기가 실제 쓴 만큼으로 채워진다', () async {
      final file = File('${dir.path}${Platform.pathSeparator}call.wav');
      final rec = DuoAbCallRecorder(file: file);
      expect(await rec.start(), isTrue);

      rec.add(_frame(_bytesFor(100), 12));
      rec.add(_frame(_bytesFor(100), 13));
      final String? path = await rec.stop();

      expect(path, file.path);
      final Uint8List bytes = await file.readAsBytes();
      final int dataBytes = _bytesFor(200);
      expect(bytes.length, 44 + dataBytes);

      final ByteData view = ByteData.sublistView(bytes);
      expect(view.getUint32(4, Endian.little), 36 + dataBytes,
          reason: 'RIFF 크기가 0이면 플레이어가 아무 소리도 안 낸다');
      expect(view.getUint32(40, Endian.little), dataBytes,
          reason: 'data 크기가 0이면 같은 문제');
      expect(view.getUint32(24, Endian.little), kStealthVoxSttSampleRate);
      expect(rec.durationMs, 200);
    });

    test('쓴 소리가 헤더 뒤에 순서대로 남는다', () async {
      final file = File('${dir.path}${Platform.pathSeparator}order.wav');
      final rec = DuoAbCallRecorder(file: file);
      await rec.start();
      rec.add(_frame(480, 1));
      rec.add(_frame(480, 2));
      await rec.stop();

      final Uint8List bytes = await file.readAsBytes();
      expect(bytes.sublist(44, 44 + 480), everyElement(1));
      expect(bytes.sublist(44 + 480), everyElement(2));
    });

    test('상한을 넘으면 더 쓰지 않고 한 번만 알린다', () async {
      final logs = <String>[];
      final file = File('${dir.path}${Platform.pathSeparator}cap.wav');
      final rec = DuoAbCallRecorder(
        file: file,
        maxMs: 100,
        onLog: (tag, msg) => logs.add(msg),
      );
      await rec.start();
      for (var i = 0; i < 5; i++) {
        rec.add(_frame(_bytesFor(100), 3));
      }
      await rec.stop();

      expect(rec.isCapped, isTrue);
      expect(rec.durationMs, 100);
      // 종료 로그에도 capped=true가 실리므로 '알림' 줄만 세어야 한다.
      expect(logs.where((l) => l.startsWith('capped at')).length, 1);
    });

    test('stop을 두 번 불러도 안전하다', () async {
      final file = File('${dir.path}${Platform.pathSeparator}twice.wav');
      final rec = DuoAbCallRecorder(file: file);
      await rec.start();
      rec.add(_frame(480, 1));
      expect(await rec.stop(), isNotNull);
      expect(await rec.stop(), isNull);
    });

    test('start 전에 들어온 조각은 조용히 무시한다', () async {
      final file = File('${dir.path}${Platform.pathSeparator}early.wav');
      final rec = DuoAbCallRecorder(file: file);
      rec.add(_frame(480, 1));
      expect(rec.dataBytes, 0);
      expect(await rec.stop(), isNull);
    });
  });
}
