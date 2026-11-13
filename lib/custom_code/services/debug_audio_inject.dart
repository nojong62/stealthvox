// 🧪 [AUDIO-INJECT] 마이크 없이 "소리"를 넣는 개발 전용 통로 (Practice용).
//
// 글자 주입(debug_stt_inject)은 STT를 건너뛴다. 이 통로는 PC에서 미리 만든
// WAV(PCM16 mono)를 앱 문서 폴더의 stt_inject.wav 로 받아, 녹음 파일 대신
// 전사에 보낸다. 소리를 만드는 시간은 앱 밖(PC)에서 끝나 있다.
//
//   adb push line.wav /data/local/tmp/stt_inject.wav
//   adb shell run-as com.aienglishpractice.stealthvox \
//       cp /data/local/tmp/stt_inject.wav app_flutter/stt_inject.wav
//
// 릴리스에는 없다 — 판정은 [kDebugAudioInjectAvailable] 한 곳이다.
import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

const bool kDebugAudioInjectAvailable = kDebugMode;

class DebugInjectedAudio {
  const DebugInjectedAudio(this.path, this.durationMs);
  final String path;
  final int durationMs;
}

/// 주입 WAV가 있으면 임시 폴더로 옮겨 돌려준다. 없으면 null. 릴리스면 항상 null.
Future<DebugInjectedAudio?> takeDebugInjectedAudio({bool playNow = true}) async {
  if (!kDebugAudioInjectAvailable) return null;
  try {
    final docs = await getApplicationDocumentsDirectory();
    final src = File('${docs.path}/stt_inject.wav');
    if (!await src.exists()) return null;
    final bytes = await src.readAsBytes();
    await src.delete();
    if (bytes.length < 44) return null;
    final h = ByteData.sublistView(bytes);
    final sampleRate = h.getUint32(24, Endian.little);
    final channels = h.getUint16(22, Endian.little);
    final bits = h.getUint16(34, Endian.little);
    final bytesPerSec = sampleRate * channels * (bits ~/ 8);
    if (bytesPerSec <= 0) return null;
    final ms = ((bytes.length - 44) * 1000 / bytesPerSec).round();
    final tmp = await getTemporaryDirectory();
    final dst = '${tmp.path}/inject_${DateTime.now().millisecondsSinceEpoch}.wav';
    await File(dst).writeAsBytes(bytes);
    debugPrint('🧪 [AUDIO-INJECT] taken ${ms}ms ($sampleRate Hz)');
    // 영상용: 전사로 보내는 것과 같은 소리를 폰 스피커로도 낸다(화면 녹화에 담긴다).
    if (playNow) unawaited(_playThroughSpeaker(dst));
    return DebugInjectedAudio(dst, ms);
  } catch (error) {
    debugPrint('🧪 [AUDIO-INJECT] read failed: $error');
    return null;
  }
}

Future<void> _playThroughSpeaker(String path) async {
  final player = AudioPlayer();
  try {
    player.onPlayerComplete.listen((_) => player.dispose());
    await player.play(DeviceFileSource(path));
    debugPrint('🧪 [AUDIO-INJECT] speaker playback started');
  } catch (error) {
    debugPrint('🧪 [AUDIO-INJECT] speaker playback failed: $error');
    await player.dispose();
  }
}

/// 주입한 소리를 스피커로 낸다(영상 녹화에 담긴다).
void playDebugInjectedAudio(String path) {
  if (!kDebugAudioInjectAvailable) return;
  unawaited(_playThroughSpeaker(path));
}

/// WAV(PCM16)를 읽어 24kHz 모노 PCM16 바이트로 바꾼다. 통역 마이크 경로가 이 형식이다.
Future<Uint8List?> readDebugWavAsPcm24k(String path) async {
  if (!kDebugAudioInjectAvailable) return null;
  try {
    final bytes = await File(path).readAsBytes();
    if (bytes.length < 44) return null;
    final h = ByteData.sublistView(bytes);
    final channels = h.getUint16(22, Endian.little);
    final rate = h.getUint32(24, Endian.little);
    final bits = h.getUint16(34, Endian.little);
    if (bits != 16 || channels < 1 || rate <= 0) return null;
    final frames = (bytes.length - 44) ~/ (2 * channels);
    final src = List<double>.filled(frames, 0);
    for (var i = 0; i < frames; i++) {
      src[i] = h.getInt16(44 + i * 2 * channels, Endian.little).toDouble();
    }
    const outRate = 24000;
    final outLen = (frames * outRate / rate).floor();
    final out = Uint8List(outLen * 2);
    final ob = ByteData.sublistView(out);
    for (var i = 0; i < outLen; i++) {
      final pos = i * rate / outRate;
      final i0 = pos.floor();
      final i1 = i0 + 1 < frames ? i0 + 1 : i0;
      final f = pos - i0;
      final v = (src[i0] * (1 - f) + src[i1] * f).round().clamp(-32768, 32767);
      ob.setInt16(i * 2, v, Endian.little);
    }
    return out;
  } catch (error) {
    debugPrint('🧪 [AUDIO-INJECT] wav->pcm24k failed: $error');
    return null;
  }
}
