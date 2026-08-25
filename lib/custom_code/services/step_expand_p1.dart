// ====================================================================
// 🗂️ [P1-PAIRS] 공부방 P1 — 유저가 자기 글을 한 조각씩 쌓은 기록
// --------------------------------------------------------------------
// 실장님 예시(2026-08-25)가 이 파일의 전부다.
//
//   유저: 회사 그만두고 싶어.
//   AI:   연결하고 싶은 당신의 생각을 말해보세요.
//   유저: 매일 똑같은 일을 반복하는 게 너무 지쳐.
//   AI:   다음 연결할 말을 결정했나요?
//   유저: 뭔가 새로운 일을 하면서 다시 의욕을 느끼고 싶어.
//   ...  유저의 다섯 번째 답으로 끝난다.
//
// 읽어야 할 것이 셋이다.
//   1. **유저가 먼저 시작한다.** 씨앗 앞에는 AI 줄이 없다.
//   2. **AI 줄은 짧은 권유다.** 방에서 코치가 늘어놓은 후보 셋도, 추천도,
//      "무엇이 됐다"도 여기 오지 않는다. 남으면 나중에 다시 봤을 때
//      "AI가 답을 만들어 줬다"로 보인다.
//   3. **유저 줄은 그 턴에 실제로 붙은 문장이다.** "2번이 좋아"가 아니다.
//      유저가 번호로 골랐든 자기 말로 했든, 글에 들어간 것은 그 문장이다.
//
// 그래서 이 파일은 **유저 줄을 만들지 않는다.** 방이 매 턴 확정해 둔 누적
// 글(`expanded_sentence`)의 차이가 곧 그 턴에 붙은 문장이라, 계산으로 나온다.
// 모델이 하는 일은 둘뿐이다 — AI 권유 한 줄씩, 그리고 배울글 번역.
// ====================================================================

import 'dart:async';
import 'dart:convert';

import 'ai_style.dart';
import 'openai_connection_pool.dart';

/// P1 제작이 실패한 이유. [none]이면 걸 수 있는 결과가 나왔다는 뜻이다.
///
/// 모델이 죽어도 P1은 선다 — 유저 줄은 이미 다 있고 없는 건 권유와 배울글
/// 뿐이다. 그래서 실패로 끝나는 갈래는 사다리가 비었을 때 하나뿐이다.
enum StepExpandP1Failure {
  none,
  emptyLadder,
}

/// 줄 수 상한. 이보다 길어지면 P1이 대화 재생이 되어 버린다.
const int kMaxStepExpandP1Pairs = 8;

/// AI 권유 한 줄의 길이 상한(글자). 넘으면 설명이 딸려 온 것이다.
const int kMaxStepExpandP1PromptChars = 60;

/// P1 한 줄.
///
/// [prompt]가 비어 있으면 **앞에 AI 줄이 없다**는 뜻이다. 씨앗이 그렇다 —
/// 아무도 그걸 요구하지 않았고, 유저가 먼저 꺼낸 말이다.
class StepExpandP1Pair {
  const StepExpandP1Pair({
    required this.answer,
    this.prompt = '',
    this.promptTarget = '',
    this.answerTarget = '',
  });

  /// 이 턴에 글에 붙은 문장. **대화 언어(원어)**다.
  /// 방이 확정해 둔 사다리에서 그대로 나온다 — 모델이 쓰지 않는다.
  final String answer;

  /// 그 앞에 오는 AI 권유 한 줄. 씨앗 줄에서는 비어 있다.
  final String prompt;

  /// [prompt]의 학습 언어판.
  final String promptTarget;

  /// [answer]의 학습 언어판.
  final String answerTarget;

  bool get hasPrompt => prompt.trim().isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'answer': answer,
        if (prompt.isNotEmpty) 'prompt': prompt,
        if (promptTarget.isNotEmpty) 'prompt_target': promptTarget,
        if (answerTarget.isNotEmpty) 'answer_target': answerTarget,
      };
}

/// 한 세션의 P1 결과.
class StepExpandP1Result {
  const StepExpandP1Result({required this.pairs, required this.failure});

  const StepExpandP1Result.failed(StepExpandP1Failure reason)
      : pairs = const <StepExpandP1Pair>[],
        failure = reason;

  final List<StepExpandP1Pair> pairs;
  final StepExpandP1Failure failure;

  bool get isUsable => pairs.isNotEmpty && failure == StepExpandP1Failure.none;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'p1_pairs': pairs.map((pair) => pair.toJson()).toList(),
      };
}

/// 방 문서에 저장해 둔 `p1_pairs`를 다시 읽는다.
///
/// 유저 줄이 없는 항목은 버린다 — P1의 한 줄은 유저가 붙인 문장이고,
/// AI 권유는 그 앞에 얹히는 것일 뿐이다.
List<StepExpandP1Pair> parseStoredP1Pairs(dynamic raw) {
  if (raw is! List) return const <StepExpandP1Pair>[];
  final pairs = <StepExpandP1Pair>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final answer = (item['answer'] ?? '').toString().trim();
    if (answer.isEmpty) continue;
    pairs.add(StepExpandP1Pair(
      answer: answer,
      prompt: (item['prompt'] ?? '').toString().trim(),
      promptTarget: (item['prompt_target'] ?? '').toString().trim(),
      answerTarget: (item['answer_target'] ?? '').toString().trim(),
    ));
    if (pairs.length >= kMaxStepExpandP1Pairs) break;
  }
  return pairs;
}

/// 누적 글의 사다리에서 **각 턴에 붙은 문장**만 꺼낸다.
///
/// 사다리는 누적형이라 다음 칸이 앞 칸을 통째로 품고 있다. 그 차이가 곧
/// 그 턴에 유저가 붙인 문장이다.
///
///   ["회사 그만두고 싶어.",
///    "회사 그만두고 싶어. 매일 똑같은 일을 반복하는 게 너무 지쳐."]
///   -> ["회사 그만두고 싶어.", "매일 똑같은 일을 반복하는 게 너무 지쳐."]
///
/// 앞 칸을 품고 있지 않으면(모델이 이미 들어간 부분을 손댄 경우) 그 칸을
/// 통째로 쓴다. 잘못 잘라 문장 조각을 남기느니 한 번 길게 나오는 쪽이 낫다.
List<String> stepExpandAddedParts(List<String> ladder) {
  final parts = <String>[];
  var previous = '';
  for (final raw in ladder) {
    final current = raw.trim();
    if (current.isEmpty) continue;
    // 같은 글이 두 칸이면 그 턴에는 아무것도 안 붙었다.
    if (current == previous) continue;
    var added = current;
    if (previous.isNotEmpty && current.startsWith(previous)) {
      added = current.substring(previous.length).trim();
    }
    if (added.isEmpty) continue;
    parts.add(added);
    previous = current;
  }
  return parts;
}

class StepExpandP1Builder {
  StepExpandP1Builder._();

  /// 방이 확정해 둔 사다리로 P1을 만든다.
  ///
  /// [ladder]는 턴마다 자란 누적 글이다. 유저 줄은 여기서 계산으로 나오고,
  /// 모델은 AI 권유와 배울글 번역만 채운다.
  static Future<StepExpandP1Result> build({
    required String apiKey,
    required List<String> ladder,
    required String originLang,
    required String targetLang,
    String model = 'gpt-4.1-mini',
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final answers = stepExpandAddedParts(ladder);
    if (answers.isEmpty) {
      return const StepExpandP1Result.failed(StepExpandP1Failure.emptyLadder);
    }
    final capped = answers.length > kMaxStepExpandP1Pairs
        ? answers.sublist(0, kMaxStepExpandP1Pairs)
        : answers;

    // 🔒 키가 없어도 P1은 선다. 유저 줄은 이미 다 있고, 없는 건 AI 권유와
    //   배울글뿐이다. 원어만으로도 "내가 이렇게 쌓았다"는 기록은 남는다.
    if (apiKey.trim().isEmpty) return _bareResult(capped);

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
              // 권유 한 줄은 매번 달라야 하지만(같은 말이 다섯 번 반복되면
              // 기록이 아니라 자동응답으로 보인다), 번역은 흔들리면 안 된다.
              'temperature': 0.5,
              'max_tokens': 900,
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
                  'content': formatAnswers(capped),
                },
              ],
            }),
          )
          .timeout(timeout);
      if (response.statusCode != 200) return _bareResult(capped);
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final choices = body['choices'] as List? ?? const <dynamic>[];
      final content = choices.isEmpty
          ? ''
          : ((choices.first as Map)['message'] as Map?)?['content']
                  ?.toString() ??
              '';
      return parseResponse(content, answers: capped);
    } on TimeoutException {
      return _bareResult(capped);
    } catch (_) {
      return _bareResult(capped);
    }
  }

  /// 모델 없이 세우는 P1. 유저 줄만 있고 AI 권유도 배울글도 없다.
  static StepExpandP1Result _bareResult(List<String> answers) =>
      StepExpandP1Result(
        pairs: answers
            .map((answer) => StepExpandP1Pair(answer: answer))
            .toList(growable: false),
        failure: StepExpandP1Failure.none,
      );

  /// 모델에 넘길 유저 줄 목록.
  static String formatAnswers(List<String> answers) {
    final buffer = StringBuffer();
    for (var i = 0; i < answers.length; i++) {
      buffer.writeln('${i + 1}. ${answers[i]}');
    }
    return buffer.toString().trimRight();
  }

  /// 모델이 돌려준 JSON을 검증해 P1 줄로 만든다.
  ///
  /// **유저 줄은 [answers]에서만 나온다.** 모델이 무엇을 돌려주든 그 자리는
  /// 건드리지 못한다 — 그게 이 기록이 진짜인 유일한 근거다.
  static StepExpandP1Result parseResponse(
    String content, {
    required List<String> answers,
  }) {
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return _bareResult(answers);
    }
    final raw = decoded['lines'];
    final rows = raw is List ? raw : const <dynamic>[];

    final pairs = <StepExpandP1Pair>[];
    for (var i = 0; i < answers.length; i++) {
      final row =
          i < rows.length && rows[i] is Map ? rows[i] as Map : const {};
      var prompt = (row['prompt'] ?? '').toString().trim();
      var promptTarget = (row['prompt_target'] ?? '').toString().trim();
      // 첫 줄 앞에는 AI가 없다. 모델이 채워 보내도 버린다 — 씨앗은 아무도
      // 요구하지 않았고, 요구한 것처럼 적으면 기록이 거짓이 된다.
      if (i == 0) {
        prompt = '';
        promptTarget = '';
      }
      // 길면 설명이 딸려 온 것이다. 자르지 않고 그 줄만 비운다.
      if (prompt.length > kMaxStepExpandP1PromptChars) {
        prompt = '';
        promptTarget = '';
      }
      if (prompt.isEmpty) promptTarget = '';
      pairs.add(StepExpandP1Pair(
        answer: answers[i],
        prompt: prompt,
        promptTarget: promptTarget,
        answerTarget: (row['answer_target'] ?? '').toString().trim(),
      ));
    }

    return StepExpandP1Result(
      pairs: pairs,
      failure: StepExpandP1Failure.none,
    );
  }

  /// P1 정리 지시문.
  ///
  /// 이 프롬프트가 지키려는 한 줄은 이것이다 —
  /// **"You do not write what the user said. You only write the invitations."**
  static String buildSysPrompt({
    required String originLang,
    required String targetLang,
  }) {
    // 🎨 [AI-STYLE] P1은 기록이다. 로비에서 Native를 골랐다고 유저가 실제로
    //   쌓은 문장이 다른 생각으로 다시 짜이면 안 된다 — 어휘까지만 묶는다.
    final styleBlock = aiStylePromptBlock(
      targetLang: targetLang,
      scope: 'the "prompt_target" and "answer_target" lines',
      reach: AiStyleReach.wording,
    );
    return '''You are laying out a finished $originLang writing session as a clean study record.

The user built one piece of writing by adding one sentence at a time. You are given those sentences, in order. In the record they read as the user's own turns, and between them a short line where the coach invites the next one.

[WHAT YOU WRITE]
For each numbered sentence, one row:
- "prompt": a SHORT $originLang line inviting the user to add the next piece. Leave it "" for line 1 — nothing invited the opening line, the user brought it.
- "prompt_target": the same invitation in $targetLang. "" when "prompt" is "".
- "answer_target": that user sentence in $targetLang.

[THE INVITATIONS]
- Short and spoken. At most $kMaxStepExpandP1PromptChars characters.
    "연결하고 싶은 당신의 생각을 말해보세요."
    "다음 연결할 말을 결정했나요?"
    "이어서 무슨 말을 붙이고 싶으세요?"
  The examples show LENGTH and TONE only. Never use the same wording twice in a row.
- Vary them across the record. The same line five times reads as a machine, not a session.
- They invite; they never carry content. Never name a topic, never hint at what to add, never mention what the user went on to say, and never react to it.
- Never offer choices, never recommend, never explain, never praise.

[THE USER'S SENTENCES ARE NOT YOURS]
You are not given them so you can improve them. Do not repeat them back, do not correct them, and do not comment on them. Only "answer_target" touches them, and that is a translation:
- Same meaning, same viewpoint, same tense, same politeness level.
- Never add a fact, a feeling, or a reason. Never drop one.
- Everyday spoken $targetLang the user could say out loud.

Reply as JSON only, one row per numbered sentence, in the same order:
{"lines":[{"prompt":"<$originLang invitation or empty>","prompt_target":"<$targetLang invitation or empty>","answer_target":"<the sentence in $targetLang>"}]}$styleBlock''';
  }
}
