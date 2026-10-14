import '/custom_code/services/secure_ai_gateway.dart';
// ====================================================================
// 🎧 [STEP-2 → ORIGIN] AI가 배울 언어로 한 말을 대화 언어로 옮겨 원문 자리에 둔다.
// --------------------------------------------------------------------
// 공부방 대사는 **전부 대화 언어**여야 한다(실장님 2026-09-12). Step 2는 두
// 오리지널이다 — 내가 말하는 오리지널(로비 설정)과 내가 듣는 말(배울 언어를
// 빌려 옴). 공부방 첫 페이지도 확정 전이라 그냥 저장된 글자를 보여 주므로,
// 배울글을 만드는 확정 단계까지 기다리면 그 사이 영어가 그대로 보인다.
// 그래서 **방을 나갈 때** 바로 옮긴다. 기다리지 않는다 — 공부방은 Firestore
// 스트림이라 옮겨지는 대로 화면이 바뀐다.
//
// 결과 줄:
//   original_text      대화 언어로 옮긴 문장   ← 공부방 원문 자리
//   translated_text    AI가 실제로 한 문장     ← 배울글 자리 (이미 배울 언어)
//   original_text_raw  AI가 실제로 한 문장     (근거)
//   source_lang        대화 언어
//   target_generated_by 'step2_native_render'
// ====================================================================

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'completion_budget.dart';
import 'history_text_model.dart';

const String kStep2NativeRenderMarker = 'step2_native_render';

/// 이 줄이 Step 2에서 AI가 배울 언어로 한 말인가.
bool isStep2AiLine(Map<String, dynamic>? data) {
  if (data == null) return false;
  final role = (data['role'] ?? '').toString().toUpperCase();
  return role == 'SYSTEM' && data['step'] == 2;
}

/// 아직 대화 언어로 안 옮긴 Step 2 AI 줄인가.
bool step2AiLineNeedsNativeRender(Map<String, dynamic>? data) {
  if (!isStep2AiLine(data)) return false;
  return (data!['target_generated_by'] ?? '').toString() !=
      kStep2NativeRenderMarker;
}

/// 한 줄을 대화 언어로 옮긴다. 실패하면 null.
Future<String?> renderStep2LineToNative({
  required String apiKey,
  required String source,
  required String nativeLang,
  required String targetLang,
  String context = '',
}) async {
  if (apiKey.isEmpty || source.trim().isEmpty) return null;
  final String registerRule = nativeLang == 'Korean'
      ? 'Korean must be 해요체 존댓말 (-요/-세요/-네요/-죠), warm and spoken, never -습니다.'
      : 'Use the everyday polite spoken register of $nativeLang.';
  try {
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
            'max_completion_tokens': 1000,
            'response_format': <String, String>{'type': 'json_object'},
            'messages': <Map<String, String>>[
              <String, String>{
                'role': 'system',
                'content':
                    '''You are preparing ONE line of a saved voice conversation for a language-learning review screen.

During listening practice the AI conversation partner spoke this line in $targetLang while the user answered in $nativeLang. The review screen shows every line in $nativeLang, so render this line into natural spoken $nativeLang — what the same partner would have said in $nativeLang at that moment.
- Same meaning, same tone, same viewpoint: the partner speaking is "I", the user being spoken to is "you".
- Do not add, drop, or explain anything. One line in, one line out.
- $registerRule
Reply as JSON: {"native": "<the line in $nativeLang>"}''',
              },
              <String, String>{
                'role': 'user',
                'content': context.trim().isEmpty
                    ? 'LINE: $source'
                    : 'SURROUNDING CONVERSATION:\n$context\n\nLINE: $source',
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      debugPrint('[STEP2-NATIVE] status=${response.statusCode}');
      return null;
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    logCompletionBudget('[STEP2-NATIVE]', body);
    final choices = body['choices'] as List? ?? const <dynamic>[];
    if (choices.isEmpty) return null;
    final message = (choices.first as Map<String, dynamic>)['message']
        as Map<String, dynamic>?;
    final content = (message?['content'] ?? '').toString().trim();
    String native = '';
    try {
      native = ((jsonDecode(content) as Map<String, dynamic>)['native'] ?? '')
          .toString()
          .trim();
    } catch (_) {
      native = content;
    }
    return native.isEmpty ? null : native;
  } catch (e) {
    debugPrint('[STEP2-NATIVE] failed=${e.runtimeType}');
    return null;
  }
}

/// 문서 하나를 옮겨 쓴다. 대화 언어 == 배울 언어면 호출 없이 배울글만 채운다.
Future<bool> renderStep2MessageToNative({
  required DocumentReference messageRef,
  required String source,
  required String apiKey,
  required String nativeLang,
  required String targetLang,
  String context = '',
}) async {
  if (nativeLang.trim().toLowerCase() == targetLang.trim().toLowerCase()) {
    await messageRef.update(<String, dynamic>{
      'translated_text': source,
      'target_generated_by': 'copy',
      'target_generated_at': FieldValue.serverTimestamp(),
    });
    return true;
  }
  final String? native = await renderStep2LineToNative(
    apiKey: apiKey,
    source: source,
    nativeLang: nativeLang,
    targetLang: targetLang,
    context: context,
  );
  if (native == null) return false;
  await messageRef.update(<String, dynamic>{
    'original_text': native,
    'original_text_raw': source,
    'translated_text': source,
    'source_lang': nativeLang.trim(),
    'target_generated_by': kStep2NativeRenderMarker,
    'target_generated_at': FieldValue.serverTimestamp(),
  });
  debugPrint('[STEP2-NATIVE] rendered msg=${messageRef.id} '
      '$targetLang→$nativeLang "$native"');
  return true;
}

/// 방을 나갈 때 — 아직 안 옮긴 Step 2 AI 줄을 전부 옮긴다. 앞뒤 대화를
/// 문맥으로 같이 준다. 실패한 줄은 공부방 확정 때 한 번 더 시도된다.
Future<void> renderRoomStep2LinesToNative({
  required DocumentReference historyRef,
  required String apiKey,
  required String nativeLang,
  required String targetLang,
}) async {
  if (apiKey.isEmpty) return;
  try {
    final snap =
        await historyRef.collection('messages').orderBy('created_at').get();
    final docs = snap.docs;
    final pending = docs.where((d) => step2AiLineNeedsNativeRender(d.data()));
    if (pending.isEmpty) return;
    final String context = docs
        .map((d) {
          final data = d.data();
          final text = (data['original_text'] ?? '').toString().trim();
          if (text.isEmpty) return '';
          final role = (data['role'] ?? '').toString().toUpperCase();
          return '${role == 'HOST' ? 'USER' : 'AI'}: $text';
        })
        .where((line) => line.isNotEmpty)
        .join('\n');
    int done = 0;
    for (final doc in pending) {
      final ok = await renderStep2MessageToNative(
        messageRef: doc.reference,
        source: (doc.data()['original_text'] ?? '').toString().trim(),
        apiKey: apiKey,
        nativeLang: nativeLang,
        targetLang: targetLang,
        context: context,
      );
      if (ok) done++;
    }
    debugPrint('[STEP2-NATIVE] room=${historyRef.id} '
        'rendered=$done/${pending.length}');
  } catch (e) {
    debugPrint('[STEP2-NATIVE] room failed=${e.runtimeType}');
  }
}
