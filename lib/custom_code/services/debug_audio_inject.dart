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
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

const bool kDebugAudioInjectAvailable = kDebugMode;

class DebugInjectedAudio {
  const DebugInjectedAudio(this.path, this.durationMs);
  final String path;
  final int durationMs;
}

/// 주입 WAV가 있으면 임시 폴더로 옮겨 돌려준다. 없으면 null. 릴리스면 항상 null.
Future<DebugInjectedAudio?> takeDebugInjectedAudio() async {
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
    return DebugInjectedAudio(dst, ms);
  } catch (error) {
    debugPrint('🧪 [AUDIO-INJECT] read failed: $error');
    return null;
  }
}
