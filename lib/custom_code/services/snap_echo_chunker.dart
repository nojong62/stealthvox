// ⚡ [SNAP-CHUNK] Snap Echoing을 문장 구조로 짧게 끊는다.
//
//   현지인이 한 숨에 읽는 호흡이 아니라, **배우는 사람이 구조를 알아보게**
//   짧게 나눈 의미 단위다(실장님 지시, 2026-10-14). 주어 | 동사구 | 목적어 |
//   전치사구 | 절 머리처럼 문법 이음매에서 끊는다.
//
//   역할 분담:
//     · 어디서 끊을지 — 여기(글자). 모델이 단위만 나누고 글자는 안 바꾼다.
//     · 끊긴 자리의 쉼 — Chirp. 단위 사이마다 pause 태그를 넣는다.
//     · 소리를 자르는 자리 — 여전히 소리의 무음(`analyzeBreaths`).
//
//   모델이 글자를 한 자라도 바꾸면 결과를 버린다(null). 그때 화면은 문장부호
//   쉼([chirpPauseMarkup])으로 돌아간다.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'chirp_pause_markup.dart';
import 'history_text_model.dart';
import 'secure_ai_gateway.dart';

/// 이 규칙으로 만든 소리를 캐시에서 가르는 판. 규칙을 바꾸면 올린다.
const String kSnapChunkVersion = 'snap_chunk_v1';

class SnapEchoChunker {
  SnapEchoChunker._();

  static String instructions(String languageName) => '''
You split a $languageName passage into short sense groups for a language learner doing listen-and-repeat practice.

Goal: each group is something a learner can hear once and repeat at once without reading. Cut at grammatical seams so the structure is easy to see — not where a fluent native speaker would breathe.

Rules:
- Usually 2 to 4 words per group (in languages written without spaces, about 3 to 8 characters). Never more than 5 words.
- Cut between: subject | verb phrase | object or complement | each prepositional phrase | the start of a subordinate or relative clause | after a conjunction.
- Never cut inside: article/determiner + noun, adjective + noun, auxiliary + main verb, phrasal verb, fixed expression, name, number with its unit.
- Keep every character of the passage, in order. Do not add, drop, reorder, or change any word or punctuation mark. Punctuation stays attached to the word before it.

Return JSON only: {"chunks": ["...", "..."]}''';

  /// [text]를 의미 단위로 나눈다. 실패하거나 글자가 바뀌면 null이다.
  static Future<List<String>?> chunk({
    required String apiKey,
    required String text,
    required String languageName,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final input = text.trim();
    if (input.isEmpty || apiKey.isEmpty) return null;
    try {
      final response = await http
          .post(
            SecureAiGateway.openAiUri('/v1/chat/completions'),
            headers: <String, String>{
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(<String, dynamic>{
              'model': kSnapChunkModel,
              'reasoning_effort': kHistoryTextReasoningEffort,
              'max_completion_tokens': 4000,
              'response_format': <String, String>{'type': 'json_object'},
              'messages': <Map<String, String>>[
                <String, String>{
                  'role': 'system',
                  'content': instructions(languageName),
                },
                <String, String>{'role': 'user', 'content': input},
              ],
            }),
          )
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      return parseChunks(utf8.decode(response.bodyBytes), input);
    } catch (_) {
      return null;
    }
  }

  /// chat/completions 응답 → 단위 목록. 원문과 글자가 다르면 null이다.
  static List<String>? parseChunks(String body, String original) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final choices = decoded['choices'] as List? ?? const <dynamic>[];
      if (choices.isEmpty) return null;
      final message = (choices.first as Map<String, dynamic>)['message']
          as Map<String, dynamic>?;
      final content = jsonDecode((message?['content'] ?? '').toString())
          as Map<String, dynamic>;
      final chunks = (content['chunks'] as List? ?? const <dynamic>[])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      return chunksPreserveText(chunks, original) ? chunks : null;
    } catch (_) {
      return null;
    }
  }

  /// 단위를 이어 붙였을 때 원문과 글자가 같은가. 공백만 무시한다 — 띄어 쓰지
  /// 않는 언어도 같은 잣대로 본다.
  static bool chunksPreserveText(List<String> chunks, String original) {
    if (chunks.length < 2) return false;
    String squash(String s) => s.replaceAll(RegExp(r'\s+'), '');
    return squash(chunks.join()) == squash(original);
  }

  /// 단위 사이마다 [pause] 태그를 넣은 Chirp markup.
  static String markup(List<String> chunks, ChirpPause pause) =>
      chunks.join(' ${pause.tag} ');
}
