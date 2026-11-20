import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'shorts_scenario_service.dart';

/// 녹음 가져오기 → 공부방 (서버 `extractRecordingScenario`,
/// firebase/functions/recording_scenario.js).
///
/// 유저가 고른 통화 녹음(앞 3분)을 서버가 듣고, 그 상황을 바탕으로 두 사람
/// 대화를 새로 써서 돌려준다. 그 대화로 유저 공부방에 방을 하나 만든다.
/// 대화 해석과 방 만들기는 쇼츠 링크와 같은 코드를 쓴다(방의 `source`만
/// 'recording'). 오디오는 서버에 남지 않는다.
///
/// 실패 이유는 [ShortsScenarioException.code]:
///   badFile(읽을 수 없는 파일·지원 안 하는 형식) · tooBig(너무 큼)
///   unusable(들을 말이 없음) · limit · noTime · adultOnly · failed

/// 서버가 받는 오디오 한도(바이트). 서버 값과 같게 둔다.
const int kRecordingMaxBytes = 6 * 1024 * 1024;

/// 앞 3분. 앱이 올리기 전에 이 길이로 자른다(서버는 못 자른다).
const int kRecordingMaxSeconds = 180;

/// 파일 확장자 → 서버가 아는 mimeType. 모르면 null.
@visibleForTesting
String? recordingMimeTypeFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return null;
  switch (fileName.substring(dot + 1).toLowerCase()) {
    case 'm4a':
    case 'mp4':
      return 'audio/mp4';
    case 'aac':
      return 'audio/aac';
    case 'mp3':
      return 'audio/mpeg';
    case 'wav':
      return 'audio/wav';
    case 'ogg':
    case 'oga':
      return 'audio/ogg';
    case 'flac':
      return 'audio/flac';
    // 3gp·amr(옛 통화 녹음)는 Gemini가 못 듣는다 — 올리기 전에 막는다.
    default:
      return null;
  }
}

@visibleForTesting
String recordingErrorCodeFor(String functionsCode) {
  switch (functionsCode) {
    case 'invalid-argument':
      return 'badFile';
    case 'resource-exhausted':
      return 'limit';
    case 'permission-denied':
      return 'noTime';
    case 'out-of-range':
      return 'adultOnly';
    default:
      return 'failed';
  }
}

class RecordingScenarioService {
  RecordingScenarioService._();

  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// 녹음 → 대화 → 공부방. 만든 방의 문서 참조와(서버가 시간을 뺐다면) 남은 시간.
  static Future<ShortsRoomResult> createStudyRoom({
    required Uint8List audio,
    required String fileName,
    required String originLanguage,
    required String targetLanguage,
  }) async {
    final mimeType = recordingMimeTypeFor(fileName);
    if (mimeType == null || audio.isEmpty) {
      throw const ShortsScenarioException('badFile');
    }
    if (audio.length > kRecordingMaxBytes) {
      throw const ShortsScenarioException('tooBig');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const ShortsScenarioException('failed');
    final sw = Stopwatch()..start();
    final ShortsDialogue dialogue;
    try {
      final response = await _functions
          .httpsCallable(
            'extractRecordingScenario',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
          )
          .call(<String, dynamic>{
        'audio': base64Encode(audio),
        'mimeType': mimeType,
        'originLanguage': originLanguage,
        'targetLanguage': targetLanguage,
      });
      dialogue = parseShortsDialogue(response.data);
    } on FirebaseFunctionsException catch (error) {
      debugPrint('[RECORDING-SCENARIO] failed code=${error.code} '
          'ms=${sw.elapsedMilliseconds}');
      throw ShortsScenarioException(recordingErrorCodeFor(error.code));
    } on ShortsScenarioException catch (error) {
      debugPrint('[RECORDING-SCENARIO] failed code=${error.code} '
          'ms=${sw.elapsedMilliseconds}');
      rethrow;
    } catch (error) {
      debugPrint('[RECORDING-SCENARIO] failed code=failed '
          'reason=${error.runtimeType} ms=${sw.elapsedMilliseconds}');
      throw const ShortsScenarioException('failed');
    }
    return ShortsScenarioService.writeStudyRoom(
      dialogue,
      uid: user.uid,
      originLanguage: originLanguage,
      targetLanguage: targetLanguage,
      source: 'recording',
    );
  }
}
