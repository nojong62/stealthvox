// ====================================================================
// 🎟️🔊 [STUDY-TRIAL-AUDIO] 공부방 체험의 에코잉·쉐도잉 소리를 모두가 함께 쓴다.
// --------------------------------------------------------------------
// 체험의 연습 설정은 고정이다(에코잉 여성 ×2, 쉐도잉 남성 0.87x). 그러면 한
// 줄의 소리는 한 벌뿐이라, 관리자가 원본에서 한 번 만들어 Storage에 올려
// 두면 체험자는 TTS를 부르지 않고 받아서 쓴다.
//
//   · 키 = 폰 캐시와 같은 (캐시 칸 이름 | 문장). 경로에는 해시만 쓴다.
//   · 올리기는 관리자만(storage.rules), 받기는 로그인한 사람(익명 포함).
//   · 실패해도 조용히 null — 그러면 원래대로 TTS를 만든다.
// ====================================================================

import 'dart:convert';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

class StudyTrialAudio {
  StudyTrialAudio._();

  static const int _maxBytes = 10 * 1024 * 1024;

  /// 폰마다 같은 값이 나와야 한다 — `String.hashCode`는 그 약속이 없어서
  /// 쓰지 않는다. FNV-1a 64비트 + 바이트 길이.
  static String objectPath(String namespace, String text) {
    final bytes = utf8.encode('$namespace|$text');
    var hash = 0xcbf29ce484222325;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    // Dart int는 부호가 있다. 64비트를 그대로 찍으면 '-'가 붙어 두 반쪽으로 낸다.
    final hi = ((hash >> 32) & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    final lo = (hash & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    final hex = '$hi$lo';
    return 'study_trial_audio/${hex}_${bytes.length}.wav';
  }

  static Future<Uint8List?> download(String namespace, String text) async {
    final path = objectPath(namespace, text);
    try {
      final bytes =
          await FirebaseStorage.instance.ref(path).getData(_maxBytes);
      debugPrint('[TRIAL-AUDIO] hit=${bytes != null} path=$path');
      return bytes;
    } catch (e) {
      debugPrint('[TRIAL-AUDIO] miss path=$path ${e.runtimeType}');
      return null;
    }
  }

  static Future<void> upload(
      String namespace, String text, Uint8List wav) async {
    final path = objectPath(namespace, text);
    try {
      await FirebaseStorage.instance
          .ref(path)
          .putData(wav, SettableMetadata(contentType: 'audio/wav'));
      debugPrint('[TRIAL-AUDIO] uploaded path=$path bytes=${wav.length}');
    } catch (e) {
      debugPrint('[TRIAL-AUDIO] upload failed path=$path $e');
    }
  }
}
