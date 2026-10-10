import '/custom_code/services/secure_ai_gateway.dart';
// ====================================================================
// 🗂️ [HISTORY PREVIEW] 공부방 목록의 날짜 밑 한 줄 — 대화 주제 요약.
// --------------------------------------------------------------------
// 서클톡·시나리오톡용. Duo는 같은 일을 `DuoBrain.summarizeConversation`이
// 먼저 하고 있었다(통화 뒤 `last_message`를 주제 한 줄로 덮어쓴다). 이 파일은
// 그 규칙을 두 대화방으로 넓힌 것이다.
//
// 요약은 **대화 언어(ORIGIN)** 로 쓴다. Step 2에서 AI가 배울 언어로 말한 줄이
// 섞여 있어도 요약은 내가 읽는 말이어야 방을 알아본다.
// 방을 나간 뒤 한 번 도는 호출이라 지연은 문제가 되지 않고, 실패하면
// `last_message`(마지막 대사)가 그대로 남는다.
// ====================================================================

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'history_text_model.dart';

/// 대화 전체를 목록 미리보기 한 줄로 줄인다. 실패하면 null.
Future<String?> summarizeConversationForList({
  required String apiKey,
  required List<String> lines,
  required String nativeLang,
}) async {
  if (apiKey.isEmpty || lines.isEmpty) return null;
  try {
    final String prompt =
        "You label a finished two-person conversation for a history list.\n"
        "Write ONE short phrase in $nativeLang naming what they talked about — "
        "the topic, not the wording. Aim for 6 to 15 words.\n"
        "Some lines may be in another language; still write the phrase in $nativeLang.\n"
        "Do not quote any line, do not name the speakers, do not translate "
        "the transcript, do not add commentary or punctuation at the end.\n"
        "If the conversation has no discernible topic, output nothing.\n"
        "Return ONLY the phrase.";
    final res = await http
        .post(
          SecureAiGateway.openAiUri('/v1/chat/completions'),
          headers: <String, String>{
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(<String, dynamic>{
            'model': kPostProcessModel,
            'reasoning_effort': kPostProcessReasoningEffort,
            'max_completion_tokens': 80,
            'messages': <Map<String, String>>[
              <String, String>{'role': 'system', 'content': prompt},
              <String, String>{'role': 'user', 'content': lines.join('\n')},
            ],
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      debugPrint('[HISTORY-PREVIEW] status=${res.statusCode}');
      return null;
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final choices = body['choices'] as List? ?? const <dynamic>[];
    if (choices.isEmpty) return null;
    final message = (choices.first as Map<String, dynamic>)['message']
        as Map<String, dynamic>?;
    return tidyPreviewLine((message?['content'] ?? '').toString());
  } catch (e) {
    debugPrint('[HISTORY-PREVIEW] failed=${e.runtimeType}');
    return null;
  }
}

/// 목록 카드는 한 줄만 그린다. 줄바꿈·따옴표를 걷고 80자에서 자른다.
String? tidyPreviewLine(String raw) {
  var out = raw
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r"""^["“”']|["“”']$"""), '')
      .trim();
  if (out.length > 80) out = '${out.substring(0, 80)}…';
  return out.isEmpty ? null : out;
}

/// 방 문서의 `last_message`를 주제 요약으로 덮어쓴다. 두세 마디짜리 방은
/// 요약해 봐야 원문보다 나을 게 없어 건너뛴다.
Future<void> writeHistoryPreviewSummary({
  required DocumentReference ref,
  required String apiKey,
  required List<String> lines,
  required String nativeLang,
}) async {
  if (apiKey.isEmpty || lines.length < 4) return;
  final String? summary = await summarizeConversationForList(
    apiKey: apiKey,
    lines: lines,
    nativeLang: nativeLang,
  );
  if (summary == null || summary.isEmpty) return;
  try {
    await ref.update(<String, dynamic>{
      'last_message': summary,
      'conversation_summary': summary,
    });
    debugPrint('[HISTORY-PREVIEW] written len=${summary.length} "$summary"');
  } catch (e) {
    debugPrint('[HISTORY-PREVIEW] write failed=${e.runtimeType}');
  }
}
