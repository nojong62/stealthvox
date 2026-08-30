// 🔬 [DUO-AB] "같은 소리를 두 경로에 넣는다"를 지키는 시험.
//
// 비교가 성립하려면 세 가지가 참이어야 한다.
//   ① 파일 쪽에 들어가는 PCM이 스트리밍에 들어간 것과 **같은 바이트**다
//   ② 발화 앞소리(pre-roll)가 파일 쪽에도 붙는다 — 안 붙이면 파일만 첫 음절이 잘린다
//   ③ 언어 값이 두 경로에 같이 박힌다
// 하나라도 어긋나면 "무엇이 달랐는가"의 답이 소리가 아니라 우리 손질이 된다.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_stt_ab_probe.dart';
import 'package:stealth_vox/custom_code/services/pcm_audio_utils.dart';

/// 값이 채워진 PCM16 조각. 바이트 값으로 어느 조각인지 구별한다.
Uint8List _frame(int bytes, int fill) =>
    Uint8List.fromList(List<int>.filled(bytes, fill));

/// 24kHz mono 기준 [ms] 밀리초 분량의 바이트 수.
int _bytesFor(int ms) => ms * (kStealthVoxSttSampleRate * 2 ~/ 1000);

/// 파일 전사를 가로채 무엇이 들어왔는지 기록한다.
class _FakeTranscriber {
  final List<Uint8List> received = <Uint8List>[];
  final List<String?> languages = <String?>[];
  final List<bool> trimFlags = <bool>[];
  final List<int> sampleRates = <int>[];
  String? reply = '파일 전사 결과';
  Object? throwThis;

  Future<String?> call({
    required String apiKey,
    required Uint8List pcm,
    int sampleRate = 16000,
    String? language,
    String model = 'gpt-4o-transcribe',
    Duration timeout = const Duration(seconds: 3),
    void Function(String tag, String msg)? onLog,
    bool trimLeadingSilence = true,
  }) async {
    received.add(pcm);
    languages.add(language);
    trimFlags.add(trimLeadingSilence);
    sampleRates.add(sampleRate);
    final Object? boom = throwThis;
    if (boom != null) throw boom;
    return reply;
  }
}

DuoSttAbProbe _probe(
  _FakeTranscriber fake, {
  String role = 'HOST',
  String language = 'ko',
  List<String>? logs,
}) =>
    DuoSttAbProbe(
      apiKey: 'test-key',
      speakerRole: role,
      languageCode: language,
      onLog: logs == null ? null : (tag, msg) => logs.add('$tag $msg'),
      transcribeFile: fake.call,
    );

void main() {
  group('같은 소리가 파일 쪽에도 그대로 간다', () {
    test('발화 구간의 바이트가 순서대로 이어져 전달된다', () async {
      final fake = _FakeTranscriber();
      final probe = _probe(fake);

      probe.beginUtterance();
      probe.addPcm(_frame(480, 1));
      probe.addPcm(_frame(480, 2));
      probe.commitUtterance('item_a', 1200, 'server');
      await probe.compare('item_a', '실시간 전사 결과');

      expect(fake.received.length, 1);
      final Uint8List sent = fake.received.single;
      expect(sent.length, 960);
      expect(sent.sublist(0, 480), everyElement(1));
      expect(sent.sublist(480), everyElement(2));
    });

    test('스트리밍과 같은 24kHz·같은 언어로 올린다', () async {
      final fake = _FakeTranscriber();
      final probe = _probe(fake, language: 'ko');

      probe.beginUtterance();
      probe.addPcm(_frame(480, 3));
      probe.commitUtterance('item_a', 500, 'server');
      await probe.compare('item_a', '네');

      expect(fake.sampleRates.single, kStealthVoxSttSampleRate);
      expect(fake.languages.single, 'ko');
    });

    test('앞 무음을 깎지 않는다 — 스트리밍이 안 깎으므로', () async {
      final fake = _FakeTranscriber();
      final probe = _probe(fake);

      probe.beginUtterance();
      probe.addPcm(_frame(480, 4));
      probe.commitUtterance('item_a', 500, 'server');
      await probe.compare('item_a', '네');

      expect(fake.trimFlags.single, isFalse,
          reason: '파일 쪽만 앞을 깎으면 차이의 원인이 우리 손질이 되어 버린다');
    });

    test('언어가 비어 있으면(자동 감지) 파일 쪽에도 안 박는다', () async {
      final fake = _FakeTranscriber();
      final probe = _probe(fake, language: '');

      probe.beginUtterance();
      probe.addPcm(_frame(480, 5));
      probe.commitUtterance('item_a', 500, 'server');
      await probe.compare('item_a', '네');

      expect(fake.languages.single, isNull);
    });
  });

  group('pre-roll — 발화 시작 전 소리가 앞에 붙는다', () {
    test('speech_started 직전 조각들이 발화 앞에 실린다', () async {
      final fake = _FakeTranscriber();
      final probe = _probe(fake);

      // 아직 발화가 아니다. 고리에만 담긴다.
      probe.addPcm(_frame(480, 9));
      probe.addPcm(_frame(480, 9));
      expect(probe.isCapturing, isFalse);

      probe.beginUtterance();
      probe.addPcm(_frame(480, 1));
      probe.commitUtterance('item_a', 800, 'server');
      await probe.compare('item_a', '왜?');

      final Uint8List sent = fake.received.single;
      // 앞소리 두 조각 + 발화 한 조각.
      expect(sent.length, 1440);
      expect(sent.sublist(0, 960), everyElement(9));
      expect(sent.sublist(960), everyElement(1));
    });

    test('고리는 상한을 넘게 자라지 않는다', () async {
      final fake = _FakeTranscriber();
      final probe = _probe(fake);

      // 상한(600ms)의 다섯 배를 흘려 넣는다.
      final int chunk = _bytesFor(100);
      for (var i = 0; i < 30; i++) {
        probe.addPcm(_frame(chunk, 7));
      }
      probe.beginUtterance();
      probe.addPcm(_frame(480, 1));
      probe.commitUtterance('item_a', 800, 'server');
      await probe.compare('item_a', '응');

      final int preRollBytes = fake.received.single.length - 480;
      expect(preRollBytes, lessThanOrEqualTo(_bytesFor(kDuoAbPreRollMs)));
      expect(preRollBytes, greaterThan(0));
    });

    test('발화가 확정되면 고리는 비워지고 다음 발화에 새로 쌓인다', () async {
      final fake = _FakeTranscriber();
      final probe = _probe(fake);

      probe.addPcm(_frame(480, 9)); // 첫 발화의 앞소리
      probe.beginUtterance();
      probe.addPcm(_frame(480, 1));
      probe.commitUtterance('item_a', 800, 'server');

      probe.addPcm(_frame(480, 8)); // 둘째 발화의 앞소리
      probe.beginUtterance();
      probe.addPcm(_frame(480, 2));
      probe.commitUtterance('item_b', 800, 'server');

      await probe.compare('item_a', 'A');
      await probe.compare('item_b', 'B');

      expect(fake.received[0].sublist(0, 480), everyElement(9));
      expect(fake.received[1].sublist(0, 480), everyElement(8),
          reason: '첫 발화의 앞소리가 둘째 발화에 다시 실리면 안 된다');
    });
  });

  group('발화와 전사문을 item_id로 잇는다', () {
    test('전사문이 뒤바뀐 순서로 와도 각자 자기 소리와 만난다', () async {
      final fake = _FakeTranscriber();
      final probe = _probe(fake);

      probe.beginUtterance();
      probe.addPcm(_frame(480, 1));
      probe.commitUtterance('item_a', 800, 'server');

      probe.beginUtterance();
      probe.addPcm(_frame(480, 2));
      probe.commitUtterance('item_b', 800, 'server');

      // 짧은 뒷말이 먼저 끝나 먼저 도착하는 상황.
      await probe.compare('item_b', 'B');
      await probe.compare('item_a', 'A');

      expect(fake.received[0], everyElement(2));
      expect(fake.received[1], everyElement(1));
    });

    test('소리가 없는 item은 조용히 건너뛴다', () async {
      final fake = _FakeTranscriber();
      final logs = <String>[];
      final probe = _probe(fake, logs: logs);

      await probe.compare('item_ghost', '급습했다.');

      expect(fake.received, isEmpty);
      expect(logs.join(), contains('no_audio_buffered'));
    });

    test('기다리는 발화가 상한을 넘으면 오래된 것부터 버린다', () async {
      final fake = _FakeTranscriber();
      final probe = _probe(fake);

      for (var i = 0; i < kDuoAbMaxPending + 2; i++) {
        probe.beginUtterance();
        probe.addPcm(_frame(480, i + 1));
        probe.commitUtterance('item_$i', 800, 'server');
      }
      expect(probe.pendingCount, kDuoAbMaxPending);

      // 가장 오래된 둘은 이미 없다.
      await probe.compare('item_0', 'x');
      expect(fake.received, isEmpty);
    });

    test('빈 item_id는 담지 않는다', () async {
      final fake = _FakeTranscriber();
      final probe = _probe(fake);
      probe.beginUtterance();
      probe.addPcm(_frame(480, 1));
      probe.commitUtterance('', 800, 'server');
      expect(probe.pendingCount, 0);
    });
  });

  group('비교 결과 로그', () {
    test('두 전사문이 같으면 match=true', () async {
      final fake = _FakeTranscriber()..reply = '오늘 저녁에 집에 갈 거예요.';
      final logs = <String>[];
      final probe = _probe(fake, logs: logs);

      probe.beginUtterance();
      probe.addPcm(_frame(_bytesFor(1000), 40));
      probe.commitUtterance('item_a', 1000, 'server');
      await probe.compare('item_a', '오늘 저녁에 집에 갈 거예요.');

      final String ab = logs.firstWhere((l) => l.contains('[DuoSTT-AB]'));
      expect(ab, contains('match=true'));
      expect(ab, contains('live="오늘 저녁에 집에 갈 거예요."'));
      expect(ab, contains('file="오늘 저녁에 집에 갈 거예요."'));
      expect(ab, contains('language=ko'));
      expect(ab, contains('speaker=HOST'));
    });

    test('GPT가 다르게 들었으면 match=false로 두 문장이 나란히 남는다', () async {
      final fake = _FakeTranscriber()..reply = '오늘 저녁에 집에 갈 거예요.';
      final logs = <String>[];
      final probe = _probe(fake, logs: logs);

      probe.beginUtterance();
      probe.addPcm(_frame(_bytesFor(1000), 40));
      probe.commitUtterance('item_a', 1000, 'server');
      // 실시간 쪽만 틀린 경우 — 스트리밍/VAD 문제라는 신호다.
      await probe.compare('item_a', '오늘 저녁에 집에 가려고요.');

      final String ab = logs.firstWhere((l) => l.contains('[DuoSTT-AB]'));
      expect(ab, contains('match=false'));
      expect(ab, contains('live="오늘 저녁에 집에 가려고요."'));
      expect(ab, contains('file="오늘 저녁에 집에 갈 거예요."'));
    });

    test('공백·문장부호 차이는 다른 말로 보지 않는다', () {
      expect(sameTranscript('네.', '네'), isTrue);
      expect(sameTranscript('왜?', ' 왜 '), isTrue);
      expect(sameTranscript('갈 거예요', '갈거예요'), isTrue);
      expect(sameTranscript('가려고요', '갈 거예요'), isFalse);
    });

    test('파일 전사가 실패해도 live는 남고 통화는 안 죽는다', () async {
      final fake = _FakeTranscriber()..throwThis = StateError('network down');
      final logs = <String>[];
      final probe = _probe(fake, logs: logs);

      probe.beginUtterance();
      probe.addPcm(_frame(480, 40));
      probe.commitUtterance('item_a', 800, 'server');
      await probe.compare('item_a', '네');

      final String ab = logs.lastWhere((l) => l.contains('[DuoSTT-AB]'));
      expect(ab, contains('file=UNAVAILABLE'));
      expect(ab, contains('live="네"'));
    });

    test('PCM 상태는 파일 전사보다 먼저 남는다', () async {
      final fake = _FakeTranscriber()..throwThis = StateError('boom');
      final logs = <String>[];
      final probe = _probe(fake, logs: logs);

      probe.beginUtterance();
      probe.addPcm(_frame(_bytesFor(500), 40));
      probe.commitUtterance('item_a', 500, 'server');
      await probe.compare('item_a', '네');

      final String pcmLog = logs.firstWhere((l) => l.contains('[DuoSTT-PCM]'));
      for (final String field in <String>[
        'rate=24000',
        'durationMs=500',
        'voicedMs=500',
        'src=server',
        'frames=',
        'maxFrameGapMs=',
        'rmsDbfs=',
        'peakDbfs=',
        'clippedPct=',
        'silentPct=',
      ]) {
        expect(pcmLog, contains(field));
      }
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
    test('dispose 뒤에는 아무것도 받지 않고 아무것도 보내지 않는다', () async {
      final fake = _FakeTranscriber();
      final probe = _probe(fake);

      probe.beginUtterance();
      probe.addPcm(_frame(480, 1));
      probe.commitUtterance('item_a', 800, 'server');
      probe.dispose();

      probe.addPcm(_frame(480, 2));
      probe.beginUtterance();
      await probe.compare('item_a', '네');

      expect(fake.received, isEmpty);
      expect(probe.pendingCount, 0);
    });

    test('speech_started 없이 온 조각은 발화로 세지 않는다', () {
      final fake = _FakeTranscriber();
      final probe = _probe(fake);
      probe.addPcm(_frame(480, 1));
      probe.commitUtterance('item_a', 800, 'server');
      expect(probe.pendingCount, 0);
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
