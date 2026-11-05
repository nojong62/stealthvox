import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'history_finalize.dart';

/// 쇼츠 링크 → 공부방 (서버 `extractShortsScenario`,
/// firebase/functions/shorts_scenario.js).
///
/// 서버가 영상 속 장면을 두 사람 대화로 정리해 돌려주면, 그 대화로 유저
/// 공부방에 방을 하나 만든다. 대화방을 거치지 않는다.
///
/// 줄마다 Target 문장(쇼츠 속 말)은 `translated_text`, Origin 뜻은
/// `original_text`에 넣는다. 공부방은 `translated_text`가 채워진 줄을 다시
/// 번역하지 않으므로(`_historyTargetNeedsWork`) 쇼츠 원래 문장이 그대로
/// 공부 자료가 된다. 방은 다른 방처럼 검수 단계(DRAFT)로 시작한다.
class ShortsLine {
  const ShortsLine({
    required this.isUser,
    required this.text,
    required this.meaning,
  });

  /// 내가 말할 줄(HOST)인가, 상대 줄(SYSTEM)인가.
  final bool isUser;

  /// Target 언어 문장 — 공부방 위.
  final String text;

  /// Origin 언어 뜻 — 공부방 아래.
  final String meaning;

  static ShortsLine? fromMap(Object? value) {
    if (value is! Map) return null;
    final text = (value['text'] ?? '').toString().trim();
    final meaning = (value['meaning'] ?? '').toString().trim();
    if (text.isEmpty || meaning.isEmpty) return null;
    return ShortsLine(
      isUser: value['speaker'] == 'user',
      text: text,
      meaning: meaning,
    );
  }
}

class ShortsDialogue {
  const ShortsDialogue({
    required this.title,
    required this.userRole,
    required this.partnerRole,
    required this.lines,
    this.sourceUrl = '',
    this.remainingSeconds,
  });

  /// 장면 한 줄(Origin) — 공부방 목록의 상황 자리.
  final String title;
  final String userRole;
  final String partnerRole;
  final List<ShortsLine> lines;

  /// 출처 표시용 원본 링크(서버가 검증한 ID로 만든 것).
  final String sourceUrl;

  /// 서버가 링크 한 번에 시간을 뺀 경우, 뺀 뒤 남은 초(없으면 차감이 꺼져 있다).
  final int? remainingSeconds;
}

/// 만든 공부방과, 서버가 시간을 뺐다면 남은 시간.
class ShortsRoomResult {
  const ShortsRoomResult({required this.ref, this.remainingSeconds});
  final DocumentReference<Map<String, dynamic>> ref;
  final int? remainingSeconds;
}

/// 실패 이유. 화면 문구는 [code]로 고른다.
///   notYoutube · unavailable(비공개·삭제) · unusable(대화 없는 영상)
///   limit(하루 상한) · noTime(시간 없음) · adultOnly(만 18세 미만) · failed(그 밖)
class ShortsScenarioException implements Exception {
  const ShortsScenarioException(this.code);
  final String code;
  @override
  String toString() => 'ShortsScenarioException($code)';
}

/// 서버 결과 맵 → 대화. 쓸 수 없는 영상이면 unusable 예외.
@visibleForTesting
ShortsDialogue parseShortsDialogue(Object? data) {
  if (data is! Map) throw const ShortsScenarioException('failed');
  if (data['usable'] != true) throw const ShortsScenarioException('unusable');
  String field(String key) => (data[key] ?? '').toString().trim();
  final raw = data['lines'];
  final lines = raw is List
      ? raw.map(ShortsLine.fromMap).whereType<ShortsLine>().toList()
      : <ShortsLine>[];
  final title = field('title');
  final userRole = field('userRole');
  final partnerRole = field('partnerRole');
  if (title.isEmpty ||
      userRole.isEmpty ||
      partnerRole.isEmpty ||
      lines.length < 2 ||
      !lines.any((l) => l.isUser)) {
    throw const ShortsScenarioException('unusable');
  }
  return ShortsDialogue(
    title: title,
    userRole: userRole,
    partnerRole: partnerRole,
    lines: lines,
    sourceUrl: field('sourceUrl'),
    remainingSeconds: data['remainingSeconds'] is num
        ? (data['remainingSeconds'] as num).toInt()
        : null,
  );
}

@visibleForTesting
String shortsErrorCodeFor(String functionsCode) {
  switch (functionsCode) {
    case 'invalid-argument':
      return 'notYoutube';
    case 'not-found':
      return 'unavailable';
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

/// 링크처럼 보이는지 앱에서 먼저 거른다(서버도 다시 본다).
bool looksLikeYoutubeLink(String value) {
  final v = value.trim().toLowerCase();
  return v.contains('youtube.com/') || v.contains('youtu.be/');
}

/// 공부방 방 문서. 시나리오톡 대화방이 만드는 방(`_ensureHistoryRef`)과 같은
/// 모양이라 목록·공부방이 따로 알 것이 없다. [createdAt]·[lastActive]는
/// 호출부가 넘긴다(이 함수는 Firestore 서버 시각을 모른다).
@visibleForTesting
Map<String, dynamic> shortsRoomDoc(
  ShortsDialogue dialogue, {
  required String nativeLang,
  required String targetLang,
  required Object createdAt,
  bool freeTalk = false,
}) {
  return <String, dynamic>{
    'created_at': createdAt,
    'last_active': createdAt,
    'room_name': 'Scenario Talk Mode',
    'mode': 'scenario_talk',
    'scenario_situation': dialogue.title,
    'scenario_keyword': dialogue.title,
    'user_role': dialogue.userRole,
    'ai_role': dialogue.partnerRole,
    'user_label': dialogue.userRole,
    'partner_label': dialogue.partnerRole,
    'is_pinned': false,
    'msg_count': dialogue.lines.length,
    // 목록은 last_message가 없는 방을 숨긴다(chat_history_list_master).
    'last_message': dialogue.lines.last.meaning,
    'native_lang': nativeLang,
    'target_lang': targetLang,
    'source': 'shorts',
    // 만들 때 고른 Free Talk 여부. 대사는 이미 완성돼 있어 방 모양은 안 바꾸고 표시만 남긴다
    // (`free_talk`는 일부러 쓰지 않는다 — 그 값이 있으면 뒤집기가 한 번 더 돈다).
    'shorts_free_talk': freeTalk,
    if (dialogue.sourceUrl.isNotEmpty) 'shorts_source_url': dialogue.sourceUrl,
    ...historyDraftSeed(),
  };
}

/// 공부방 줄 문서들. 공부방은 `created_at` 순서로 줄을 세우므로 1초씩 띄운다
/// (한 batch에 서버 시각을 쓰면 모든 줄이 같은 시각이 된다).
@visibleForTesting
List<Map<String, dynamic>> shortsMessageDocs(
  ShortsDialogue dialogue, {
  required DateTime base,
}) {
  return [
    for (var i = 0; i < dialogue.lines.length; i++)
      <String, dynamic>{
        'role': dialogue.lines[i].isUser ? 'HOST' : 'SYSTEM',
        'original_text': dialogue.lines[i].meaning,
        'translated_text': dialogue.lines[i].text,
        'target_generated_at':
            Timestamp.fromDate(base.add(Duration(seconds: i))),
        'created_at': Timestamp.fromDate(base.add(Duration(seconds: i))),
        'source': 'shorts',
      },
  ];
}

class ShortsScenarioService {
  ShortsScenarioService._();

  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// 링크 → 대화 → 공부방. 만든 방의 문서 참조와(서버가 시간을 뺐다면) 남은 시간을 돌려준다.
  static Future<ShortsRoomResult> createStudyRoom({
    required String url,
    required String originLanguage,
    required String targetLanguage,
    bool freeTalk = false,
  }) async {
    if (!looksLikeYoutubeLink(url)) {
      throw const ShortsScenarioException('notYoutube');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const ShortsScenarioException('failed');
    final sw = Stopwatch()..start();
    final ShortsDialogue dialogue;
    try {
      final response = await _functions
          .httpsCallable(
            'extractShortsScenario',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
          )
          .call(<String, dynamic>{
        'url': url.trim(),
        'originLanguage': originLanguage,
        'targetLanguage': targetLanguage,
      });
      dialogue = parseShortsDialogue(response.data);
    } on FirebaseFunctionsException catch (error) {
      debugPrint('[SHORTS-SCENARIO] failed code=${error.code} '
          'ms=${sw.elapsedMilliseconds}');
      throw ShortsScenarioException(shortsErrorCodeFor(error.code));
    } on ShortsScenarioException catch (error) {
      debugPrint('[SHORTS-SCENARIO] failed code=${error.code} '
          'ms=${sw.elapsedMilliseconds}');
      rethrow;
    } catch (error) {
      debugPrint('[SHORTS-SCENARIO] failed code=failed '
          'reason=${error.runtimeType} ms=${sw.elapsedMilliseconds}');
      throw const ShortsScenarioException('failed');
    }

    try {
      final db = FirebaseFirestore.instance;
      final roomRef =
          db.collection('users').doc(user.uid).collection('chat_history').doc();
      final batch = db.batch();
      batch.set(
        roomRef,
        shortsRoomDoc(
          dialogue,
          nativeLang: originLanguage,
          targetLang: targetLanguage,
          createdAt: FieldValue.serverTimestamp(),
          freeTalk: freeTalk,
        ),
      );
      for (final message
          in shortsMessageDocs(dialogue, base: DateTime.now())) {
        batch.set(roomRef.collection('messages').doc(), message);
      }
      await batch.commit();
      debugPrint('[SHORTS-SCENARIO] room=${roomRef.id} '
          'lines=${dialogue.lines.length} ms=${sw.elapsedMilliseconds}');
      return ShortsRoomResult(
        ref: roomRef,
        remainingSeconds: dialogue.remainingSeconds,
      );
    } catch (error) {
      debugPrint('[SHORTS-SCENARIO] room write failed '
          'reason=${error.runtimeType}');
      throw const ShortsScenarioException('failed');
    }
  }
}
