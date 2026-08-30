// ====================================================================
// 🧪 [DUO-AB-SIM] 진단 배선을 **실제 소리 파일 하나로** 돌려 보는 자리.
// --------------------------------------------------------------------
//   flutter test tool/duo_stt_ab_sim.dart
//   flutter test tool/duo_stt_ab_sim.dart --dart-define=SIM_WAV=C:/path/to.wav
//
// 왜 필요한가.
//
//   실기기 로그를 믿으려면 **로그를 만드는 장치부터 믿을 수 있어야 한다.**
//   `[DuoSTT-AB] match=false`를 보고 "스트리밍이 문제구나" 하려면, 그 전에
//   "파일 쪽에 들어간 소리가 정말 마이크가 낸 그 소리였다"가 참이어야 한다.
//   여기서 증명하는 것이 그것이다.
//
// 무엇을 증명하는가 / 못 하는가.
//
//   ✅ 증명한다 — 마이크 조각이 통화·전사·진단 세 갈래에 같은 바이트로 간다
//   ✅ 증명한다 — 진단기가 모은 발화 PCM이 원본과 **바이트 단위로 같다**
//   ✅ 증명한다 — pre-roll이 발화 앞에 정확히 붙는다(샘플 어긋남 없음)
//   ✅ 증명한다 — 통짜 녹음 WAV가 원본과 같고 헤더가 올바르다
//   ✅ 증명한다 — 리샘플링이 앱 안에서 한 번도 안 일어난다
//   ❌ 못 한다  — GPT가 한국어를 옳게 듣는가. 그건 실제 발화 + 실제 API가 필요하다
//
// 즉 이 파일이 통과하면 실기기 로그의 숫자와 글자를 **그대로 믿어도 된다**.
// 통과하지 않는데 실기기에서 판단하면, 장치가 틀린 것을 소리 탓으로 읽게 된다.
// ====================================================================

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_direct_audio.dart';
import 'package:stealth_vox/custom_code/services/duo_stt_ab_probe.dart';
import 'package:stealth_vox/custom_code/services/pcm_audio_utils.dart';

/// 넣어 볼 소리 파일. 없으면 아래에서 만들어 쓴다.
const String kSimWavPath = String.fromEnvironment('SIM_WAV', defaultValue: '');

/// 마이크가 한 번에 내주는 조각의 크기. 실기기 `[PCM_CAPTURE] first_frame_bytes`
/// 와 같은 자리다. 20ms = 24kHz mono PCM16에서 960바이트.
const int kSimFrameMs = 20;

// ── WAV 읽기 ─────────────────────────────────────────────────────────

class _Wav {
  _Wav(this.pcm, this.sampleRate, this.channels, this.bitsPerSample);
  final Uint8List pcm;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
}

/// 최소한의 RIFF 파서. fmt/data 청크만 찾는다.
_Wav _readWav(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  if (bytes.length < 12 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    throw StateError('RIFF/WAVE가 아니다');
  }
  int offset = 12;
  int sampleRate = 0, channels = 0, bits = 0;
  Uint8List? data;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = view.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ') {
      channels = view.getUint16(body + 2, Endian.little);
      sampleRate = view.getUint32(body + 4, Endian.little);
      bits = view.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      final end = (body + size).clamp(0, bytes.length);
      data = Uint8List.sublistView(bytes, body, end);
    }
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  if (data == null) throw StateError('data 청크가 없다');
  return _Wav(data, sampleRate, channels, bits);
}

/// 스테레오를 모노로 섞고, 필요하면 24kHz로 **한 번만** 맞춘다.
///
/// ⚠️ 이 손질은 **시뮬레이터가 파일을 마이크처럼 만들기 위해** 하는 것이다.
///   앱은 이 일을 하지 않는다 — 마이크가 처음부터 24kHz mono로 내준다.
Uint8List _toMono24k(_Wav wav) {
  if (wav.bitsPerSample != 16) {
    throw StateError('PCM16만 다룬다 (bits=${wav.bitsPerSample})');
  }
  final src = ByteData.sublistView(wav.pcm);
  final int frames = wav.pcm.lengthInBytes ~/ (2 * wav.channels);

  // ① 모노로 섞는다.
  final mono = Int16List(frames);
  for (var i = 0; i < frames; i++) {
    var sum = 0;
    for (var c = 0; c < wav.channels; c++) {
      sum += src.getInt16((i * wav.channels + c) * 2, Endian.little);
    }
    mono[i] = (sum / wav.channels).round().clamp(-32768, 32767);
  }
  if (wav.sampleRate == kStealthVoxSttSampleRate) {
    return Uint8List.sublistView(mono);
  }

  // ② 선형 보간으로 24kHz에 맞춘다. 한 번만 지난다.
  final double ratio = wav.sampleRate / kStealthVoxSttSampleRate;
  final int outFrames = (frames / ratio).floor();
  final out = Int16List(outFrames);
  for (var i = 0; i < outFrames; i++) {
    final double pos = i * ratio;
    final int a = pos.floor();
    final int b = (a + 1 < frames) ? a + 1 : a;
    final double t = pos - a;
    out[i] = (mono[a] * (1 - t) + mono[b] * t).round().clamp(-32768, 32767);
  }
  return Uint8List.sublistView(out);
}

/// 파일이 없을 때 쓸 소리. **말소리 흉내**다 — 기본 주파수에 배음을 얹고
/// 포락선을 씌워, 세기 계측이 무음이나 순음이 아닌 값으로 나오게 한다.
Uint8List _synthesizeSpeechLike({int ms = 1500}) {
  final int samples = ms * kStealthVoxSttSampleRate ~/ 1000;
  final out = Int16List(samples);
  const double f0 = 130; // 남성 음역대 기본 주파수
  for (var i = 0; i < samples; i++) {
    final double t = i / kStealthVoxSttSampleRate;
    // 음절 흉내: 초당 4번 열렸다 닫히는 포락선.
    final double env = 0.5 - 0.5 * math.cos(2 * math.pi * 4 * t);
    double v = 0;
    for (var h = 1; h <= 6; h++) {
      v += math.sin(2 * math.pi * f0 * h * t) / h;
    }
    out[i] = (v * env * 0.22 * 32767).round().clamp(-32768, 32767);
  }
  return Uint8List.sublistView(out);
}


// ── 실행 ─────────────────────────────────────────────────────────────

void main() {
  final logs = <String>[];
  void log(String tag, String msg) {
    logs.add('$tag $msg');
    // ignore: avoid_print
    print('$tag $msg');
  }

  test('🧪 소리 파일 하나를 Duo 진단 배선에 통째로 흘려 본다', () async {
    // ── 1. 소리를 마련한다 ──────────────────────────────────────────
    Uint8List mic;
    String origin;
    if (kSimWavPath.isNotEmpty && File(kSimWavPath).existsSync()) {
      final wav = _readWav(File(kSimWavPath).readAsBytesSync());
      // ignore: avoid_print
      print('📂 입력 WAV: $kSimWavPath '
          '(${wav.sampleRate}Hz ${wav.channels}ch ${wav.bitsPerSample}bit, '
          '${wav.pcm.length} bytes)');
      mic = _toMono24k(wav);
      origin = kSimWavPath;
    } else {
      mic = _synthesizeSpeechLike(ms: 3000);
      origin = '합성 음성(말소리 흉내 3000ms)';
      // ignore: avoid_print
      print('📂 입력 WAV 없음 → $origin');
    }
    final int micDurationMs =
        pcm16DurationMs(mic.length, sampleRate: kStealthVoxSttSampleRate);
    // ignore: avoid_print
    print('🎙️ 마이크 스트림으로 삼을 PCM: ${mic.length} bytes '
        '= ${micDurationMs}ms @ ${kStealthVoxSttSampleRate}Hz mono PCM16');
    // ignore: avoid_print
    print('   상태: ${measurePcm16(mic)}\n');

    // ── 2. 실제 배선을 세운다. 가짜는 "GPT 응답" 하나뿐이다 ──────────
    final tmp = await Directory.systemTemp.createTemp('duo_ab_sim_');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    final relaySent = <Uint8List>[]; // 갈래 1 — 상대에게 갈 소리
    final liveSent = <Uint8List>[]; // 갈래 2 — 스트리밍 소켓에 갈 소리
    Uint8List? fileSent; // 갈래 3 — 파일 전사에 갈 소리

    final probe = DuoSttAbProbe(
      apiKey: 'sim-key',
      speakerRole: 'HOST',
      languageCode: 'ko',
      saveWavDir: tmp,
      onLog: log,
      transcribeFile: ({
        required String apiKey,
        required Uint8List pcm,
        int sampleRate = 16000,
        String? language,
        String model = 'gpt-4o-transcribe',
        Duration timeout = const Duration(seconds: 3),
        void Function(String tag, String msg)? onLog,
        bool trimLeadingSilence = true,
      }) async {
        fileSent = pcm;
        // 실제 API 대신, 무엇이 들어왔는지 되비추는 응답.
        return '오늘 저녁에 집에 갈 거예요.';
      },
    );

    final callWav = File('${tmp.path}${Platform.pathSeparator}_call.wav');
    final recorder = DuoAbCallRecorder(file: callWav, onLog: log);
    expect(await recorder.start(), isTrue);

    final fanout = DuoMicPcmFanout(
      speakerRole: 'HOST',
      toCall: relaySent.add,
      toStt: liveSent.add,
      toProbe: (bytes) {
        probe.addPcm(bytes);
        recorder.add(bytes);
      },
      onLog: log,
      logEveryFrames: 25,
    );

    // ── 3. 마이크처럼 20ms씩 흘린다 ────────────────────────────────
    const int frameBytes =
        kSimFrameMs * (kStealthVoxSttSampleRate * 2 ~/ 1000);
    // Server VAD 흉내: 1200ms 지점에서 speech_started, 끝에서 committed.
    //
    // ⚠️ **pre-roll(600ms)보다 뒤에 잡아야 검증이 성립한다.** 앞이면 고리가
    //   통째로 들어가 버려 "정확히 600ms만 앞에 붙는가"를 못 본다.
    final int speechStartFrame = (1200 / kSimFrameMs).round();

    var fed = 0;
    for (var off = 0; off < mic.length; off += frameBytes) {
      final end = (off + frameBytes).clamp(0, mic.length);
      if (fed == speechStartFrame) {
        probe.beginUtterance(); // ← 서버가 speech_started를 준 순간
      }
      fanout.add(Uint8List.sublistView(mic, off, end));
      fed++;
    }
    probe.commitUtterance('sim_item_1', micDurationMs - 1200, 'server');
    // ignore: avoid_print
    print('');
    await probe.compare('sim_item_1', '오늘 저녁에 집에 가려고요.');
    final String? callPath = await recorder.stop();
    // ignore: avoid_print
    print('');

    // ── 4. 무엇이 참인지 확인한다 ───────────────────────────────────

    // (1) 세 갈래가 같은 바이트를 받았다.
    Uint8List join(List<Uint8List> parts) {
      final total = parts.fold<int>(0, (a, b) => a + b.length);
      final out = Uint8List(total);
      var o = 0;
      for (final p in parts) {
        out.setRange(o, o + p.length, p);
        o += p.length;
      }
      return out;
    }

    expect(join(relaySent), equals(mic),
        reason: '릴레이로 간 소리가 마이크와 다르면 통화가 이미 망가진 것이다');
    expect(join(liveSent), equals(mic),
        reason: '스트리밍으로 간 소리가 마이크와 다르면 전사가 딴 소리를 듣는다');
    // ignore: avoid_print
    print('✅ 갈래 1(릴레이) = 갈래 2(스트리밍) = 마이크 원본, ${mic.length} bytes 완전 일치');

    // (2) 파일 전사에 간 소리가 원본의 정확한 부분집합이다(pre-roll 포함).
    final Uint8List sentToFile = fileSent!;
    const int preRollBytes =
        kDuoAbPreRollMs * (kStealthVoxSttSampleRate * 2 ~/ 1000);
    final int speechStartByte = speechStartFrame * frameBytes;
    final int expectedStart =
        (speechStartByte - preRollBytes).clamp(0, mic.length);
    expect(sentToFile, equals(Uint8List.sublistView(mic, expectedStart)),
        reason: 'pre-roll이 어긋나면 파일 쪽만 첫 음절이 달라져 비교가 무의미해진다');
    expect(expectedStart, greaterThan(0),
        reason: 'pre-roll이 실제로 잘리는 조건이어야 이 확인이 뜻을 갖는다');
    // ignore: avoid_print
    print('✅ 갈래 3(파일 전사) = 마이크 원본의 [$expectedStart..${mic.length}] 구간, '
        '${sentToFile.length} bytes 완전 일치');
    // ignore: avoid_print
    print('   (발화 시작 ${speechStartByte ~/ (kStealthVoxSttSampleRate * 2 ~/ 1000)}ms '
        '− pre-roll ${kDuoAbPreRollMs}ms = ${expectedStart ~/ (kStealthVoxSttSampleRate * 2 ~/ 1000)}ms 부터)');

    // (3) 통짜 녹음 WAV가 원본과 같고 헤더가 올바르다.
    expect(callPath, isNotNull);
    final Uint8List wavBytes = await callWav.readAsBytes();
    final _Wav parsed = _readWav(wavBytes);
    expect(parsed.sampleRate, kStealthVoxSttSampleRate);
    expect(parsed.channels, 1);
    expect(parsed.bitsPerSample, 16);
    expect(parsed.pcm, equals(mic),
        reason: '귀로 들어 볼 파일이 원본과 다르면 그 확인 자체가 거짓말이 된다');
    // ignore: avoid_print
    print('✅ 통짜 WAV = 마이크 원본, 헤더 ${parsed.sampleRate}Hz '
        '${parsed.channels}ch ${parsed.bitsPerSample}bit, '
        'data ${parsed.pcm.length} bytes 완전 일치');

    // (4) 발화별 WAV도 남았다.
    final saved = tmp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.wav') && !f.path.contains('_call'))
        .toList();
    expect(saved, isNotEmpty);
    // ignore: avoid_print
    print('✅ 발화별 WAV ${saved.length}개 저장됨: '
        '${saved.map((f) => f.uri.pathSegments.last).join(', ')}');

    // (5) 앱 안에서 리샘플링이 한 번도 없었다.
    expect(fanout.callBytes, mic.length);
    expect(fanout.sttBytes, mic.length);
    expect(recorder.dataBytes, mic.length);
    // ignore: avoid_print
    print('✅ 리샘플링 0회 — 세 갈래 모두 ${mic.length} bytes 그대로');
    // ignore: avoid_print
    print('   ${fanout.summary()}');

    // (6) 로그가 판독표대로 나왔다.
    final ab = logs.firstWhere((l) => l.contains('[DuoSTT-AB]'));
    expect(ab, contains('match=false'));
    expect(ab, contains('language=ko'));
    expect(ab, contains('speaker=HOST'));
    final pcmLine = logs.firstWhere((l) => l.contains('[DuoSTT-PCM]'));
    expect(pcmLine, contains('rate=24000'));
    // ignore: avoid_print
    print('✅ 로그 형식 확인 — [DuoSTT-PCM], [DuoSTT-WAV], [DuoSTT-AB] 모두 출력됨\n');
    // ignore: avoid_print
    print('── 결론 ──────────────────────────────────────────────');
    // ignore: avoid_print
    print('진단 배선은 소리를 손대지 않는다. 실기기 [DuoSTT-AB]가 match=false를');
    // ignore: avoid_print
    print('내면 그것은 전달 방식 또는 GPT의 차이이지, 우리 코드가 만든 차이가 아니다.');
    // ignore: avoid_print
    print('입력: $origin');
  });
}
