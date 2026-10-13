// 🧪 [STT-INJECT] 마이크 없이 유저 발화를 넣는 개발 전용 통로.
//
// PC 스피커 소리는 폰 마이크의 서버 VAD에 말로 잡히지 않았다(2026-10-13,
// speech_started 0건). 대화 파이프라인을 시험하려면 마이크가 아니라 "전사가
// 끝난 한 줄"이 필요하다. 이 통로는 그 한 줄을 파일로 받는다.
//
// 넣는 법 (디버그 빌드, PC에서):
//   adb push line.txt /data/local/tmp/stt_inject.txt
//   adb shell run-as com.aienglishpractice.stealthvox \
//       cp /data/local/tmp/stt_inject.txt app_flutter/stt_inject.txt
//
// 파일은 읽자마자 지운다. 릴리스에는 없다 — 판정은 이 파일의
// [kDebugSttInjectAvailable] 한 곳이다.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

const bool kDebugSttInjectAvailable = kDebugMode;

/// [onText]를 0.5초마다 파일 한 줄로 부른다. 릴리스면 아무것도 안 하고 null.
Timer? startDebugSttInject(void Function(String text) onText) {
  if (!kDebugSttInjectAvailable) return null;
  var busy = false;
  return Timer.periodic(const Duration(milliseconds: 500), (_) async {
    if (busy) return;
    busy = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/stt_inject.txt');
      if (!await file.exists()) return;
      final text = (await file.readAsString()).trim();
      await file.delete();
      if (text.isNotEmpty) onText(text);
    } catch (error) {
      debugPrint('🧪 [STT-INJECT] read failed: $error');
    } finally {
      busy = false;
    }
  });
}
