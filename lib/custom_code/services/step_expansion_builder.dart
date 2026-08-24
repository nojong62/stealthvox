// ====================================================================
// 🌱 [STEP-EXPANSION] 대화가 끝난 뒤 생각의 성장을 영어 문장으로 재구성한다
// --------------------------------------------------------------------
// 지금까지 Step Expand는 **방 안에서** 매 턴 영어 사다리를 만들어 말풍선에
// 띄웠다. 5턴이 정해져 있었고, 유저는 대화를 하는 게 아니라 문장 제작 절차를
// 밟았다.
//
// 이 파일은 그 순서를 뒤집는다. 방은 유저의 언어로 상담만 하고, 영어는
// **대화가 끝난 뒤 transcript 전체를 읽고** 여기서 한 번에 재구성된다.
//
//   방(원어 상담) → transcript 저장 → [여기] → 히스토리 P2 → P3
//
// **대화 턴 수와 확장 단계 수는 1:1이 아니다.** 8턴을 이야기했어도 생각이
// 세 번 자랐으면 단계는 셋이다. 맞장구와 잡담은 단계가 되지 않는다.
//
// ⚠️ **transcript가 먼저 저장된 뒤에 불린다.** 여기서 실패해도 유저가 나눈
// 대화는 이미 히스토리에 있다. 그래서 이 함수는 실패를 숨기지 않고 null과
// [StepExpansionFailure]로 돌려준다 — 호출부가 재시도하거나 P2 없이 방을
// 남길 수 있어야 한다.
// ====================================================================

import 'dart:async';
import 'dart:convert';

import 'ai_style.dart';
import 'openai_connection_pool.dart';
import 'p2_chunk_mapping.dart';

/// 재구성이 실패한 이유. [none]이면 모델이 실제로 결과를 냈다는 뜻이다.
///
/// 로그에서 "모델이 만든 단계"와 "장애라서 비어 있는 단계"가 섞이면 P2가 왜
/// 비었는지 영영 추적할 수 없다. 그래서 값으로 갈라 둔다.
enum StepExpansionFailure {
  none,
  apiKeyMissing,
  emptyTranscript,
  timeout,
  httpError,
  parseError,
  validationError,
  transportError,
}

/// 한 사람의 한 턴. 화면 라벨이 아니라 **누구의 의미인지**만 남긴다.
class StepExpansionTurn {
  const StepExpansionTurn({required this.isUser, required this.text});

  final bool isUser;
  final String text;
}

/// 확장 사다리의 한 칸.
///
/// [chunks]는 **직전 칸에 대고** 잰 변화다. 예전 P2는 같은 턴의 번역문에
/// 대고 쟀지만, 이제 비교 대상은 이전 단계 문장이다 — 유저가 보게 될 것이
/// "이번에 무엇이 들어왔나"이기 때문이다.
class StepExpansionStep {
  const StepExpansionStep({
    required this.step,
    required this.text,
    required this.addedMeaning,
    required this.chunks,
    required this.primaryMorph,
    this.previousText = '',
  });

  /// 1부터 센다.
  final int step;

  /// 이 단계까지 자란 영어 문장. 누적형이다.
  final String text;

  /// 이 단계에서 새로 들어온 핵심 의미. **유저의 언어**로 한 줄이다.
  /// 화면에 띄울지는 P2가 정한다 — 여기서는 근거로만 들고 있는다.
  final String addedMeaning;

  /// 직전 단계 대비 kept / evolved / new.
  final List<P2Chunk> chunks;

  /// 이 단계에서 **가장 중요한 변화 한 곳**. [text] 안의 실제 부분 문자열이다.
  /// 여러 군데를 칠하면 무엇이 들어왔는지가 오히려 안 보인다(§20).
  final String primaryMorph;

  /// 직전 칸의 문장. [chunks]의 `from`이 가리키는 원본이다.
  /// 첫 칸은 비교 대상이 없어 빈 문자열이다.
  final String previousText;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'step': step,
        'text': text,
        'added_meaning': addedMeaning,
        'primary_morph': primaryMorph,
        'chunks': chunks.map((chunk) => chunk.toJson()).toList(),
      };
}

/// 한 세션의 재구성 결과.
class StepExpansionResult {
  const StepExpansionResult({
    required this.steps,
    required this.failure,
  });

  const StepExpansionResult.failed(StepExpansionFailure reason)
      : steps = const <StepExpansionStep>[],
        failure = reason;

  final List<StepExpansionStep> steps;
  final StepExpansionFailure failure;

  bool get isUsable => steps.isNotEmpty && failure == StepExpansionFailure.none;

  /// 마지막 단계가 곧 이 세션의 최종문장이다(§15). P3가 이걸 받는다.
  String get finalSentence => steps.isEmpty ? '' : steps.last.text;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'expansions': steps.map((step) => step.toJson()).toList(),
        'final_sentence': finalSentence,
      };
}

/// Firestore에 저장해 둔 `expansions` 배열을 다시 사다리로 읽는다.
///
/// 저장할 때 이미 검증했지만 여기서 한 번 더 [parseP2Chunks]를 태운다.
/// 문서는 손으로도 고쳐지고 예전 빌드가 쓴 것도 섞인다 — 청크가 문장을 못
/// 덮는 채로 화면까지 가면 강조가 엉뚱한 곳에 붙는다.
List<StepExpansionStep> parseStoredExpansions(dynamic raw) {
  if (raw is! List) return const <StepExpansionStep>[];
  final steps = <StepExpansionStep>[];
  var previous = '';
  for (final item in raw) {
    if (item is! Map) continue;
    final text = (item['text'] ?? '').toString().trim();
    if (text.isEmpty) continue;
    final chunks = previous.isEmpty
        ? <P2Chunk>[P2Chunk(text: text, type: 'new')]
        : parseP2Chunks(item['chunks'], text, part1Text: previous);
    final rawMorph = (item['primary_morph'] ?? '').toString().trim();
    steps.add(StepExpansionStep(
      step: steps.length + 1,
      text: text,
      addedMeaning: (item['added_meaning'] ?? '').toString().trim(),
      chunks: chunks,
      // 문장 안에 실제로 없는 강조는 좌표가 아니다. 버린다.
      primaryMorph: text.contains(rawMorph) ? rawMorph : '',
      previousText: previous,
    ));
    previous = text;
  }
  return steps;
}

/// 단계 수 상한.
///
/// 개편안은 단계를 고정하지 말라고 하지만(§14), 상한마저 없으면 잡담이 긴
/// 세션에서 모델이 열 몇 칸을 만들어 P2가 스크롤 지옥이 된다. 의미가 정말
/// 여섯 번 자란 대화는 드물다.
const int kMaxStepExpansions = 6;

/// 이 미만이면 대화라고 보지 않는다. 유저 턴 기준이다.
const int kMinUserTurnsForExpansion = 1;

final RegExp _hangul = RegExp(r'[가-힣]');

class StepExpansionBuilder {
  StepExpansionBuilder._();

  /// 전체 transcript를 읽고 누적 확장 사다리를 만든다.
  ///
  /// [transcript]는 방에서 나눈 **원어** 대화 전체다. 요약해서 넘기지 않는다 —
  /// 어떤 생각이 유저 것이고 어떤 게 AI 제안이었는지는 원문에만 남아 있다.
  static Future<StepExpansionResult> build({
    required String apiKey,
    required List<StepExpansionTurn> transcript,
    required String originLang,
    required String targetLang,
    String model = 'gpt-4.1-mini',
    Duration timeout = const Duration(seconds: 40),
  }) async {
    if (apiKey.trim().isEmpty) {
      return const StepExpansionResult.failed(
          StepExpansionFailure.apiKeyMissing);
    }
    final turns = transcript
        .where((turn) => turn.text.trim().isNotEmpty)
        .toList(growable: false);
    final userTurns = turns.where((turn) => turn.isUser).length;
    if (userTurns < kMinUserTurnsForExpansion) {
      return const StepExpansionResult.failed(
          StepExpansionFailure.emptyTranscript);
    }

    final client = OpenAiConnectionPool.instance.client;
    try {
      final response = await client
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: <String, String>{
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(<String, dynamic>{
              'model': model,
              // 재구성은 창작이 아니다. 같은 대화에서 매번 다른 사다리가
              // 나오면 유저는 자기 생각이 자란 과정이 아니라 모델의 기분을
              // 보게 된다.
              'temperature': 0.3,
              'max_tokens': 1600,
              'response_format': <String, String>{'type': 'json_object'},
              'messages': <Map<String, String>>[
                <String, String>{
                  'role': 'system',
                  'content': buildSysPrompt(
                    originLang: originLang,
                    targetLang: targetLang,
                  ),
                },
                <String, String>{
                  'role': 'user',
                  'content': formatTranscript(turns),
                },
              ],
            }),
          )
          .timeout(timeout);
      if (response.statusCode != 200) {
        return const StepExpansionResult.failed(StepExpansionFailure.httpError);
      }
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final choices = body['choices'] as List? ?? const <dynamic>[];
      if (choices.isEmpty) {
        return const StepExpansionResult.failed(
            StepExpansionFailure.parseError);
      }
      final content =
          ((choices.first as Map)['message'] as Map?)?['content']?.toString() ??
              '';
      return parseResponse(content);
    } on TimeoutException {
      return const StepExpansionResult.failed(StepExpansionFailure.timeout);
    } catch (_) {
      return const StepExpansionResult.failed(
          StepExpansionFailure.transportError);
    }
  }

  /// 모델이 돌려준 JSON을 검증해 사다리로 만든다.
  ///
  /// HTTP와 떼어 둔 이유는 하나다 — **여기가 실제로 틀리는 자리**다. 누적이
  /// 깨졌는지, 한글이 섞였는지, 강조가 문장 안에 없는지는 네트워크 없이
  /// 시험할 수 있어야 한다.
  static StepExpansionResult parseResponse(String content) {
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return const StepExpansionResult.failed(
          StepExpansionFailure.parseError);
    }
    final raw = decoded['steps'];
    if (raw is! List || raw.isEmpty) {
      return const StepExpansionResult.failed(
          StepExpansionFailure.validationError);
    }

    final steps = <StepExpansionStep>[];
    String previousText = '';
    for (final item in raw) {
      if (steps.length >= kMaxStepExpansions) break;
      if (item is! Map) continue;
      final text = (item['text'] ?? '').toString().trim();
      // 영어 자리에 한글이 남아 있으면 그 칸은 학습 자료가 아니다. P2 한복판에
      // 한국어 줄이 하나 끼는 것보다 칸을 버리는 쪽이 낫다.
      if (text.isEmpty || _hangul.hasMatch(text)) continue;
      // 같은 문장이 두 칸을 차지하면 유저는 아무 변화도 못 본다(§14).
      if (previousText.isNotEmpty && _sameSentence(previousText, text)) {
        continue;
      }

      final chunks = previousText.isEmpty
          // 첫 칸에는 비교 대상이 없다. 통째로 새 문장이다.
          ? <P2Chunk>[P2Chunk(text: text, type: 'new')]
          : parseP2Chunks(item['chunks'], text, part1Text: previousText);

      steps.add(StepExpansionStep(
        step: steps.length + 1,
        text: text,
        addedMeaning: (item['added_meaning'] ?? '').toString().trim(),
        chunks: chunks,
        primaryMorph: _resolvePrimaryMorph(
          raw: (item['primary_morph'] ?? '').toString().trim(),
          text: text,
          chunks: chunks,
          isFirstStep: previousText.isEmpty,
        ),
        previousText: previousText,
      ));
      previousText = text;
    }

    if (steps.isEmpty) {
      return const StepExpansionResult.failed(
          StepExpansionFailure.validationError);
    }
    return StepExpansionResult(
      steps: steps,
      failure: StepExpansionFailure.none,
    );
  }

  /// 강조할 한 덩이를 정한다.
  ///
  /// 모델이 준 값을 먼저 믿되, **[text] 안에 실제로 있는 문자열일 때만**
  /// 쓴다. 없는 문자열을 강조 좌표로 쓰면 P2가 엉뚱한 곳을 칠하거나 아무
  /// 데도 못 칠한다. 못 믿을 때는 이번에 새로 들어온 청크로 돌아간다.
  static String _resolvePrimaryMorph({
    required String raw,
    required String text,
    required List<P2Chunk> chunks,
    required bool isFirstStep,
  }) {
    if (raw.isNotEmpty && text.contains(raw)) return raw;
    // 첫 칸은 문장 전체가 새것이라 강조할 "변화"가 없다.
    if (isFirstStep) return '';
    for (final type in const <String>['new', 'evolved']) {
      for (final chunk in chunks) {
        if (chunk.type == type && text.contains(chunk.text)) return chunk.text;
      }
    }
    return '';
  }

  static bool _sameSentence(String a, String b) => _normalize(a) == _normalize(b);

  static String _normalize(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  /// 모델에 넘길 대화록. 라벨은 둘뿐이다.
  ///
  /// 배역 이름이나 화면 라벨을 그대로 넘기지 않는다 — 모델이 정해야 하는 건
  /// "이 의미가 유저 것인가"뿐이고, 그 판단에 이름은 방해만 된다.
  static String formatTranscript(List<StepExpansionTurn> turns) => turns
      .map((turn) =>
          '${turn.isUser ? 'USER' : 'AI'}: ${turn.text.trim().replaceAll(RegExp(r'\s+'), ' ')}')
      .join('\n');

  /// 재구성 지시문.
  ///
  /// 이 프롬프트가 지키려는 한 줄은 이것이다 —
  /// **"Improve the expression, not the user's story."**
  static String buildSysPrompt({
    required String originLang,
    required String targetLang,
  }) {
    final styleBlock = aiStylePromptBlock(
      targetLang: targetLang,
      scope: 'every "text" sentence you produce',
    );
    return '''You are rebuilding a finished $originLang conversation into the growth of ONE English sentence.

The user talked through a thought with a conversation partner in $originLang. Your job is NOT to translate that conversation. Your job is to find how the user's thought actually grew, and to show that growth as a short ladder of cumulative $targetLang sentences.

[STEP 1 — WHOSE MEANING COUNTS]
- Keep only what the USER expressed, or clearly accepted when the AI offered it.
- An idea the AI raised and the user did not take up is NOT the user's meaning. Drop it.
- Drop small talk, agreement noises, repetitions, and anything the user explicitly rejected or removed.

[STEP 2 — WHERE THE THOUGHT ACTUALLY GREW]
- Conversation turns and ladder steps are NOT one-to-one. Eight turns with three real developments make THREE steps.
- A step exists only where a genuinely new piece of meaning enters — a reason, a feeling, a condition, a contrast, a consequence, a change of mind.
- Rewording the same meaning is not a step. Never pad the ladder.
- Produce between 1 and $kMaxStepExpansions steps. Fewer honest steps beat more shallow ones.

[STEP 3 — BUILD THE LADDER, CUMULATIVE]
- Step 1 is the seed: the smallest honest version of what the user was getting at.
- Every later step must CONTAIN the previous step's meaning and add the next piece:
    step 2 = step 1 + B
    step 3 = step 2 + C
- Steps are not alternative sentences. They are one sentence growing.
- The LAST step is the final sentence. There only, you may reorganise the whole sentence so it reads as one natural spoken English thought, as long as no meaning is lost or added.
- The final sentence must be something one person can say in a single comfortable breath-flow in real conversation. Do not let it sprawl.

[STEP 4 — ENGLISH, NOT TRANSLATED $originLang]
- Do not carry $originLang word order or connective habits into English.
- Organise the thought the way an English speaker would, using relations that fit: because, but, even though, not because A but because B, lately, part of me..., which is why..., it made me realize..., I guess..., I feel like...
- Everyday spoken English the user could actually say. Not written prose, not showy vocabulary.

[NEVER]
- Never invent an event, a feeling, a reason, or an attitude the user did not express.
- Never exaggerate what the user meant, and never soften or flip their stance.
- Improve the expression, not the user's story.

[FOR EACH STEP, ALSO REPORT]
- "added_meaning": ONE short line, written in $originLang, naming the new piece of meaning this step brings in. For step 1, describe the seed.
- "chunks": split THIS step's sentence into consecutive pieces covering it exactly once, in order. Classify each piece against the PREVIOUS step's sentence:
    "kept"    — carried over with little or no change
    "evolved" — same meaning as before but restructured or reworded
    "new"     — meaning that was not in the previous step
  For "kept" and "evolved", include "from": an exact contiguous substring of the PREVIOUS step's sentence. Omit "from" for "new".
  Concatenating every chunk's text must reproduce this step's sentence exactly. Step 1 has no previous sentence — give it a single "new" chunk holding the whole sentence.
- "primary_morph": the ONE piece of this step's sentence that best shows what just entered the thought. It must be an exact substring of this step's sentence. Choose a meaning-carrying piece, not a bare connective. Leave it "" for step 1.

Reply as JSON only:
{"steps":[{"text":"<$targetLang sentence>","added_meaning":"<one line in $originLang>","primary_morph":"<exact substring or empty>","chunks":[{"text":"<piece>","type":"kept|evolved|new","from":"<exact substring of previous step; kept/evolved only>"}]}]}$styleBlock''';
  }
}
