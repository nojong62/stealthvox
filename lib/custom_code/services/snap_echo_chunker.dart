// ⚡ [SNAP-CHUNK] Snap Echoing을 **한 호흡 의미 단위**로 끊는다.
//
//   몇 단어씩 쪼개는 것이 아니다. 뜻이 한 덩어리로 완결되고, 한 숨에 리듬을
//   타며 읽을 만한 길이로 끊는다. 이웃 덩어리끼리 길이가 비슷해 박자가 고르게
//   흐르도록 한다. 길이는 둘 중에서 고른다([SnapUnitSize]):
//     · Quick Snap — 강세 1개 중심의 한 덩어리
//     · Full Breath — 강세 2개 중심의 한 덩어리
//   영어는 단어 수를 세지 않고 강세 박자로만 나눈다. 다른 언어는 글자 길이 기준.
//   (실장님 지시, 2026-10-15; 영어 강세 기준은 2026-11-22 변경).
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
/// v4(2026-11-08): MY STORY의 줄바꿈(한 줄 = 한 호흡)을 넘어 단위를 잇지 않는다.
const String kSnapChunkVersion = 'snap_chunk_v4';

/// 영어 전용 강세 박자 규칙으로 만든 소리의 캐시 판. 영어 규칙을 바꾸면 올린다.
/// 다른 언어는 [kSnapChunkVersion]을 그대로 써서 기존 소리가 유지된다.
const String kSnapChunkEnglishStressVersion = 'snap_chunk_en_stress_v2';

/// ✨ 영어 Snap Echoing 소리를 Gemini TTS로 만든다. Gateway가 실패하거나 꺼져
/// 있으면 Chirp 3 HD가 대신 읽는다. 끄려면 빌드에
/// `--dart-define=SNAP_GEMINI_TTS=false`.
const bool kSnapGeminiTts =
    bool.fromEnvironment('SNAP_GEMINI_TTS', defaultValue: true);

/// Gemini로 만든 소리의 캐시 판 꼬리표. 지시문을 바꾸면 올린다.
const String kSnapGeminiCacheTag = 'gem4';

/// Gemini에게 주는 낭독 지시(소리에 실린다). 속도는 정상 대화 속도의 95%.
/// 네이티브 화자처럼 자연스럽게, 강세 중심의 리듬으로 한 호흡에 읽게 한다.
const String kSnapGeminiStylePrompt =
    'Read this short phrase the way a native English speaker would say it '
    'naturally in conversation, with a lively, natural rhythm. Speak at about '
    '95 percent of normal speed, in one breath. Center the rhythm on the '
    'stressed syllables: each stressed syllable is a beat, and the unstressed '
    'words in between are light and quick, leaning into the stress that follows '
    'them. Sound like a native speaker, not a textbook reader. Do not pause '
    'inside the phrase, do not slow down, do not exaggerate, and do not add '
    'anything.';

/// 이 언어 이름으로 만든 소리가 쓸 캐시 판.
String snapChunkVersionFor(String languageName) =>
    SnapEchoChunker.isEnglish(languageName)
        ? kSnapChunkEnglishStressVersion
        : kSnapChunkVersion;

/// 한 호흡 의미 단위의 길이.
enum SnapUnitSize { quick, full }

extension SnapUnitSizeLabel on SnapUnitSize {
  /// 화면 이름. 고유명사처럼 쓰므로 번역하지 않는다.
  String get label => this == SnapUnitSize.quick ? 'Quick Snap' : 'Full Beat';
}

class SnapEchoChunker {
  SnapEchoChunker._();

  static String _lengthRule(SnapUnitSize size) => size == SnapUnitSize.quick
      ? '- Usually 2 stressed beats, about 3 to 5 words (in languages written without spaces, about 5 to 10 characters). Never under 2 words unless the passage leaves no choice. Never over 6 words.'
      : '- Usually 3 to 4 stressed beats, about 6 to 9 words (in languages written without spaces, about 10 to 18 characters). Never under 4 words unless the passage leaves no choice. Never over 11 words.';

  /// 배울 언어가 영어인가. 영어만 강세 박자 규칙을 쓴다.
  static bool isEnglish(String languageName) {
    final name = languageName.trim().toLowerCase();
    return name == 'english' || name.startsWith('english ') ||
        name.startsWith('english(') || name == 'en' || name.startsWith('en-');
  }

  /// 영어는 단어 수를 세지 않는다. 강세 박자 수만 본다.
  static String _stressLengthRule(SnapUnitSize size) => size == SnapUnitSize.quick
      ? '- Exactly 1 stressed beat per group: one stressed syllable at the center, with its unstressed words around it. The number of words does not matter.'
      : '- Exactly 2 stressed beats per group, centered on two stressed syllables with their unstressed words between and around them. The number of words does not matter. Use 1 beat only if no other cut keeps the meaning intact.';

  /// 영어 전용: 강세 박자를 세어 끊는다. 뜻의 경계 안에서만 끊고, 그 안에서
  /// 박자 수를 고르게 맞춘다.
  static String englishStressInstructions(SnapUnitSize size) => '''
You divide an English passage into stress groups for rhythmic read-aloud practice. A learner hears one group, then says it back in one breath.

English is stress-timed: the stressed syllables fall on a steady beat, and the unstressed words between them are squeezed short. Count beats, not words.
- Stressed (a beat): content words — nouns, main verbs, adjectives, adverbs, numbers, negatives (not, never, no), question words, and demonstratives used alone.
- Unstressed (squeezed): articles, prepositions, auxiliaries and modals, pronouns, conjunctions, "to" before a verb.

Rules:
- One group = a set number of stressed beats, spoken in one comfortable breath at an even pace. Group length is decided by stress, never by word count.
${_stressLengthRule(size)}
- Unstressed words lean forward: they attach to the stressed word that FOLLOWS them ("to the STORE", "I NEEDED"), never trail onto the group before. A group may begin with unstressed words and should end on a stressed word.
- Never end a group on an article, preposition, conjunction, auxiliary, or pronoun.
- Cut only at a natural meaning boundary — punctuation, a clause edge, before a prepositional phrase, after a conjunction. Within that limit, choose the cuts that keep neighbouring groups at the same beat count.
- Never cut inside a fixed expression, phrasal verb, name, number with its unit, or a noun phrase.
- Keep every character of the passage, in order. Do not add, drop, reorder, or change any word or punctuation mark. Punctuation stays attached to the word before it.

Return JSON only: {"chunks": ["...", "..."]}''';

  /// 영어 Full: 한 박자뿐인 꼬리 조각은 앞 단위에 붙인다. 너무 길어지면 그대로 둔다.
  static List<String> mergeOrphanTail(List<String> chunks) {
    if (chunks.length < 2) return chunks;
    int words(String s) =>
        s.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final last = chunks.last;
    final prev = chunks[chunks.length - 2];
    if (words(last) >= 3 || words(prev) + words(last) > 11) return chunks;
    return <String>[
      ...chunks.sublist(0, chunks.length - 2),
      '$prev $last',
    ];
  }

  static String instructions(String languageName, SnapUnitSize size) =>
      isEnglish(languageName)
          ? englishStressInstructions(size)
          : _meaningInstructions(languageName, size);

  static String _meaningInstructions(String languageName, SnapUnitSize size) => '''
You divide a $languageName passage into breath groups for rhythmic read-aloud practice. A learner hears one group, then says it back.

Each group is one complete unit of meaning that can be spoken in a single comfortable breath with a clear, steady rhythm — the way a skilled teacher reads aloud for learners, ideally phrased and evenly paced. It is not word-by-word chopping, and it is not the long, fast run a fluent native speaker might say in one go.

Rules:
- One group = one idea that makes sense on its own: a short clause, or a phrase that carries a complete piece of meaning.
${_lengthRule(size)}
- Keep neighbouring groups similar in length so the reading keeps an even beat.
- If the passage has line breaks, each line break is a mandatory cut: a group never runs across a line break. A line that is already a good length stays one group; a long line may be split further.
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
      final parsed = parseChunks(utf8.decode(response.bodyBytes), input);
      if (parsed == null) return null;
      return parsed;
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
