import '/custom_code/services/secure_ai_gateway.dart';
// ====================================================================
// 🔁 [FREE-TALK-FLIP] Free Talk 방을 공부방에 넘기기 전에 평소 방으로 바꾼다.
// --------------------------------------------------------------------
// Free Talk 방은 대화를 로비 Target으로 하지만, 공부방은 평소 방과 **똑같다**
// (실장님, 2026-10-25). 처음에는 로비 Origin 원문만 보이고, 유저가 그 글을
// "내가 하려던 말"로 고쳐 확정하면 위에 Target, 아래에 작게 Origin이 나온다.
// 아직 서툰 Target 말을 모국어 뜻으로 바로잡고, 거기서 바른 Target을 만든다.
//
// 그래서 대화가 끝나면 한 번 바꾼다.
//
//   original_text  Target으로 한 말 → 그 뜻의 Origin 문장
//   spoken_text    실제로 한 Target 말(새 칸, 화면엔 안 나온다)
//   translated_text 비운다 — 공부방이 Origin에서 다시 만든다
//   native_lang / target_lang  맞바꿔 로비 Origin / Target으로
//
// 원문 복원(소리로 다시 듣기)은 **Target 말을 고치는 일**이라 이보다 앞에
// 선다. 바꾼 뒤에는 원문이 다른 언어라 다시 돌면 안 되므로 완료로 닫는다.
// ====================================================================

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'completion_budget.dart';
import 'free_talk.dart';
import 'history_finalize.dart';
import 'history_preview_summary.dart';
import 'history_text_model.dart';
import 'origin_pcm_store.dart';
import 'origin_restoration.dart';

/// 바꾼 시각. 있으면 이미 평소 방이다.
const String kFreeTalkFlippedAtField = 'free_talk_flipped_at';

/// 실제로 한 Target 말. 원문 칸이 Origin 뜻으로 바뀐 뒤의 근거다.
const String kMessageSpokenTextField = 'spoken_text';

/// 아직 바꾸지 않은 Free Talk 방인가. **검수 중인 방만** — 확정한 원문은
/// 어떤 자동 처리도 다시 쓰지 않는다. 바꾸기가 실패한 채 확정된 방은 그대로 둔다.
bool freeTalkRoomNeedsFlip(Map<String, dynamic>? room) =>
    isFreeTalkRoom(room) &&
    room?[kFreeTalkFlippedAtField] == null &&
    historyEditAllowed(room);

String buildFreeTalkFlipInstructions({
  required String spokenLang,
  required String baseLang,
}) =>
    '''You receive a conversation in $spokenLang. The USER is still learning $spokenLang, so their lines may be broken or unnatural.
Rewrite every line in $baseLang so the USER can read what was meant in their own language.
- USER lines: write what the user meant, as natural $baseLang. Do not fix the meaning, add, or drop anything.
- AI lines: translate faithfully into natural $baseLang.
- Keep every id. One output line per input line, same order.
Return JSON only: {"lines":[{"id":"...","text":"..."}]}''';

/// 모델 답을 줄별로 읽는다. **한 줄이라도 빠지면 null** — 반만 바꾼 방은
/// 두 언어가 섞여 공부방이 엉뚱한 배울글을 만든다.
Map<String, String>? parseFreeTalkFlipLines(
    String content, Set<String> ids) {
  try {
    final parsed = jsonDecode(content);
    if (parsed is! Map<String, dynamic>) return null;
    final lines = parsed['lines'];
    if (lines is! List) return null;
    final out = <String, String>{};
    for (final line in lines) {
      if (line is! Map) continue;
      final id = (line['id'] ?? '').toString();
      final text = (line['text'] ?? '').toString().trim();
      if (ids.contains(id) && text.isNotEmpty) out[id] = text;
    }
    return out.length == ids.length ? out : null;
  } catch (_) {
    return null;
  }
}

class FreeTalkHistoryFlip {
  FreeTalkHistoryFlip._();

  static final FreeTalkHistoryFlip instance = FreeTalkHistoryFlip._();

  static const Duration _timeout = Duration(seconds: 40);

  /// 방마다 한 판. 대화방 종료와 공부방 열기가 겹쳐도 한 번만 돈다.
  final Map<String, Future<bool>> _running = <String, Future<bool>>{};

  /// 필요하면 바꾸고 끝날 때까지 기다린다. 바뀌었거나 바꿀 게 없으면 true.
  Future<bool> ensure(DocumentReference<Object?> roomRef, String apiKey) {
    final id = roomRef.id;
    final running = _running[id];
    if (running != null) return running;
    final task = _flip(roomRef, apiKey);
    _running[id] = task;
    void cleanup() {
      if (identical(_running[id], task)) _running.remove(id);
    }

    task.whenComplete(cleanup);
    return task;
  }

  Future<bool> _flip(DocumentReference<Object?> roomRef, String apiKey) async {
    final roomId = roomRef.id;
    try {
      final room = await roomRef.get();
      final raw = room.data();
      final data = raw is Map<String, dynamic> ? raw : null;
      if (!freeTalkRoomNeedsFlip(data)) return true;
      if (apiKey.isEmpty) {
        debugPrint('[FREE-TALK-FLIP] skip room=$roomId reason=no_api_key');
        return false;
      }
      // 대화방이 저장한 짝: native = 말한 언어(로비 Target), target = 뜻(로비 Origin).
      final spokenLang = (data!['native_lang'] ?? '').toString().trim();
      final baseLang = (data['target_lang'] ?? '').toString().trim();
      if (spokenLang.isEmpty || baseLang.isEmpty) {
        debugPrint('[FREE-TALK-FLIP] skip room=$roomId reason=no_lang');
        return false;
      }

      final snap =
          await roomRef.collection('messages').orderBy('created_at').get();
      final docs = snap.docs
          .where((d) =>
              (d.data()['original_text'] ?? '').toString().trim().isNotEmpty)
          .toList();
      final started = DateTime.now();
      Map<String, String> meanings = const <String, String>{};
      if (docs.isNotEmpty) {
        final ids = docs.map((d) => d.id).toSet();
        final transcript = docs.map((d) {
          final who = d.data()['role'] == 'HOST' ? 'USER' : 'AI';
          final text = d.data()['original_text'].toString().trim();
          return '${d.id}\t$who\t$text';
        }).join('\n');
        final response = await http
            .post(
              SecureAiGateway.openAiUri('/v1/chat/completions'),
              headers: <String, String>{
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json; charset=utf-8',
              },
              body: jsonEncode(<String, dynamic>{
                'model': kHistoryRepairModel,
                'reasoning_effort': kHistoryTextReasoningEffort,
                'max_completion_tokens': 6000,
                'response_format': <String, String>{'type': 'json_object'},
                'messages': <Map<String, String>>[
                  <String, String>{
                    'role': 'system',
                    'content': buildFreeTalkFlipInstructions(
                        spokenLang: spokenLang, baseLang: baseLang),
                  },
                  <String, String>{
                    'role': 'user',
                    'content': 'id\tspeaker\ttext\n$transcript',
                  },
                ],
              }),
            )
            .timeout(_timeout);
        if (response.statusCode != 200) {
          debugPrint('[FREE-TALK-FLIP] failed room=$roomId '
              'status=${response.statusCode}');
          return false;
        }
        final body = jsonDecode(utf8.decode(response.bodyBytes))
            as Map<String, dynamic>;
        logCompletionBudget('[FREE-TALK-FLIP]', body);
        final choices = body['choices'] as List? ?? const <dynamic>[];
        final message = choices.isEmpty
            ? null
            : (choices.first as Map<String, dynamic>)['message']
                as Map<String, dynamic>?;
        final parsed = parseFreeTalkFlipLines(
            (message?['content'] ?? '').toString(), ids);
        if (parsed == null) {
          debugPrint('[FREE-TALK-FLIP] failed room=$roomId reason=incomplete');
          return false;
        }
        meanings = parsed;
      }

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in docs) {
        batch.update(doc.reference, <String, dynamic>{
          'original_text': meanings[doc.id],
          kMessageSpokenTextField: doc.data()['original_text'],
          'translated_text': FieldValue.delete(),
        });
      }
      final orderedMeanings = docs
          .map((d) => meanings[d.id] ?? '')
          .where((t) => t.isNotEmpty)
          .toList(growable: false);
      batch.update(roomRef, <String, dynamic>{
        if (orderedMeanings.isNotEmpty) 'last_message': orderedMeanings.last,
        'native_lang': baseLang,
        'target_lang': spokenLang,
        kFreeTalkFlippedAtField: FieldValue.serverTimestamp(),
        // 원문이 이제 다른 언어다. 소리로 다시 듣는 복원이 돌면 Target 말로
        // 덮어쓴다.
        kOriginRestoreStateField: kOriginRestoreCompleted,
      });
      await batch.commit();
      unawaited(OriginPcmStore.instance.discard(roomId).catchError((_) {}));
      // 🗂️ 목록 요약도 여기서 쓴다. 대화방에서 Target 줄로 요약하면 모델이
      //   "Origin으로 쓰라"를 무시하고 Target으로 썼다(2026-10-25 실기기).
      unawaited(writeHistoryPreviewSummary(
        ref: roomRef,
        apiKey: apiKey,
        lines: orderedMeanings,
        nativeLang: baseLang,
      ));
      debugPrint('[FREE-TALK-FLIP] done room=$roomId lines=${docs.length} '
          'native=$baseLang target=$spokenLang '
          'elapsedMs=${DateTime.now().difference(started).inMilliseconds}');
      return true;
    } catch (error) {
      debugPrint('[FREE-TALK-FLIP] failed room=$roomId '
          'reason=${error.runtimeType}');
      return false;
    }
  }
}
