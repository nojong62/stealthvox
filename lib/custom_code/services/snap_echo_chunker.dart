// ⚡ [SNAP-CHUNK] Snap Echoing을 **한 호흡 의미 단위**로 끊는다.
//
//   몇 단어씩 쪼개는 것이 아니다. 뜻이 한 덩어리로 완결되고, 한 숨에 리듬을
//   타며 읽을 만한 길이로 끊는다. 이웃 덩어리끼리 길이가 비슷해 박자가 고르게
//   흐르도록 한다. 길이는 둘 중에서 고른다([SnapUnitSize]):
//     · Quick Snap — 박자 2개, 대개 3~5단어
//     · Full Breath — 박자 3~4개, 대개 6~9단어
//   (실장님 지시, 2026-10-15).
//
//   역할 분담:
//     · 어디서 끊을지 — 여기(글자). 모델이 단위만 나누고 글자는 안 바꾼다.
//     · 끊긴 자리의 쉼 — Chirp. 단위 사이마다 `[pause short]`를 넣는다.
//       듣기용 쉼이 아니라 소리에서 경계를 찾게 하는 표시다.
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
const String kSnapChunkVersion = 'snap_chunk_v3';

/// 한 호흡 의미 단위의 길이.
enum SnapUnitSize { quick, full }

extension SnapUnitSizeLabel on SnapUnitSize {
  /// 화면 이름. 고유명사처럼 쓰므로 번역하지 않는다.
  String get label => this == SnapUnitSize.quick ? 'Quick Snap' : 'Full Breath';
}

class SnapEchoChunker {
  SnapEchoChunker._();

  static String _lengthRule(SnapUnitSize size) => size == SnapUnitSize.quick
      ? '- Usually 2 stressed beats, about 3 to 5 words (in languages written without spaces, about 5 to 10 characters). Never under 2 words unless the passage leaves no choice. Never over 6 words.'
      : '- Usually 3 to 4 stressed beats, about 6 to 9 words (in languages written without spaces, about 10 to 18 characters). Never under 4 words unless the passage leaves no choice. Never over 11 words.';

  static String instructions(String languageName, SnapUnitSize size) => '''
You divide a $languageName passage into breath groups for rhythmic read-aloud practice. A learner hears one group, then says it back.

Each group is one complete unit of meaning that can be spoken in a single comfortable breath with a clear, steady rhythm — the way a skilled teacher reads aloud for learners, ideally phrased and evenly paced. It is not word-by-word chopping, and it is not the long, fast run a fluent native speaker might say in one go.

Rules:
- One group = one idea that makes sense on its own: a short clause, or a phrase that carries a complete piece of meaning.
${_lengthRule(size)}
- Keep neighbouring groups similar in length so the reading keeps an even beat.
- Prefer to cut at punctuation and at clause boundaries; otherwise before a prepositional phrase or after a conjunction — wherever the meaning naturally rests.
- Never cut inside a fixed expression, phrasal verb, name, number with its unit, or a noun phrase.
- Keep every character of the passage, in order. Do not add, drop, reorder, or change any word or punctuation mark. Punctuation stays attached to the word before it.

Return JSON only: {"chunks": ["...", "..."]}''';

  /// [text]를 의미 단위로 나눈다. 실패하거나 글자가 바뀌면 null이다.
  static Future<List<String>?> chunk({
    required String apiKey,
    required String text,
    required String languageName,
    required SnapUnitSize size,
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
                  'content': instructions(languageName, size),
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
