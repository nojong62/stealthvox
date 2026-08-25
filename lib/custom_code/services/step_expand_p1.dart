// ====================================================================
// 🗂️ [P1-PAIRS] 대화가 끝난 뒤 History P1이 보여 줄 "질문 ↔ 답"을 만든다
// --------------------------------------------------------------------
// 방 안에서 코치는 소리 내어 많은 일을 한다. 생각이 무엇이 됐는지 말하고,
// 발전 방향 두셋을 늘어놓고, 그중 하나를 이유와 함께 추천하고, 고르라고 한다.
// **그 제안문은 History에 남기지 않는다.** 남으면 나중에 다시 봤을 때
// "AI가 답을 만들어 줬다"로 보이고, 유저가 스스로 생각한 기록이 사라진다.
//
// 그래서 P1은 이렇게 정리된다(실장님 지시, 2026-08-25):
//
//   **P1 = 실제 AI 턴에서 '유저에게 답을 요구한 마지막 질문/요청' +
//         그에 대응하는 실제 User 답변. 후보·추천·설명은 제거.**
//
// ⚠️ **질문을 세션 종료 후에 새로 창작하면 안 된다.** 라이브에서 실제로 건넨
// 질문의 핵심을 정리해 저장하는 것이다. 안 그러면 History가 실제 학습 과정과
// 다른 가짜 대화 기록이 된다.
//
// 그 규칙을 말로만 적어 두면 지켜지지 않으므로, **구조로 두 겹 박아 둔다.**
//   1. 유저 답변은 모델이 쓰지 않는다. 모델은 "몇 번 줄"인지만 고르고,
//      글자는 transcript에서 그대로 꺼낸다. 유저의 말은 한 글자도 안 바뀐다.
//   2. 질문은 모델이 줄이지만, **어느 AI 턴을 줄인 것인지 번호로 대야 한다.**
//      그 번호가 실제 AI 턴이고 그 답변 바로 앞이어야 통과한다.
//
// 사다리(step_expansion_builder.dart)와 같은 transcript를 읽지만 하는 일이
// 다르다 — 사다리는 **문장이 어떻게 자랐나**, 여기는 **생각을 어떻게 골랐나**.
// ====================================================================

import 'dart:async';
import 'dart:convert';

import 'ai_style.dart';
import 'openai_connection_pool.dart';
import 'step_expansion_builder.dart';

/// P1 제작이 실패한 이유. [none]이면 모델이 실제로 결과를 냈다는 뜻이다.
enum StepExpandP1Failure {
  none,
  apiKeyMissing,
  emptyTranscript,
  timeout,
  httpError,
  parseError,
  validationError,
  transportError,
}

/// 쌍 수 상한. 이보다 길어지면 P1이 대화 재생이 되어 버린다.
const int kMaxStepExpandP1Pairs = 8;

/// 질문 길이 상한(글자). 넘으면 코치의 설명이 딸려 온 것이다.
const int kMaxStepExpandP1QuestionChars = 120;

/// 학습 언어 질문의 길이 상한. 언어에 따라 원어보다 길어지므로 여유를 둔다.
/// 넘으면 **그 줄만 버린다** — 쌍은 원어 질문만으로도 성립한다.
const int kMaxStepExpandP1QuestionTargetChars = 200;

/// P1 한 쌍. 화면에서는 AI 질문이 먼저, 유저 답이 뒤에 온다.
///
/// **네 글자가 한 쌍을 이룬다** — 질문의 Original/Target, 답의 Original/Target.
/// 저장되는 건 셋뿐이다. 답의 Target은 저장하지 않는다 — 그건 교정된
/// Original에서 나와야 하는데, 교정은 이 쌍이 만들어진 뒤에 일어난다. 그래서
/// 화면에서 그때그때 붙인다([resolveP1PairAnswers]).
class StepExpandP1Pair {
  const StepExpandP1Pair({
    required this.question,
    required this.answer,
    this.questionTarget = '',
    this.answerTarget = '',
    this.userTurnIndex = -1,
  });

  /// 실제 AI 턴이 유저에게 요구한 것 한 문장. **대화 언어(원어)**다.
  final String question;

  /// 같은 질문을 학습 언어로 옮긴 것. 세션이 끝날 때 함께 만들어 저장한다.
  final String questionTarget;

  /// 유저가 실제로 한 말. transcript에서 그대로 꺼낸 글자다.
  final String answer;

  /// [answer]를 학습 언어로 옮긴 것. **저장하지 않는다.**
  /// 줄마다 만들어 두는 `translated_text`에서 화면이 붙인다.
  final String answerTarget;

  /// 이 답이 대화에서 **몇 번째 유저 발화**였는가(0부터). 모르면 -1이다.
  ///
  /// 이게 있어야 [resolveP1PairAnswers]가 나중에 교정된 원문과 그 번역을 다시
  /// 찾아 붙일 수 있다. 글자로 맞추면 정작 교정된 줄만 못 찾는다 — 교정됐다는
  /// 건 글자가 달라졌다는 뜻이니까.
  final int userTurnIndex;

  StepExpandP1Pair withAnswer(String next, {String target = ''}) =>
      StepExpandP1Pair(
        question: question,
        questionTarget: questionTarget,
        answer: next,
        answerTarget: target,
        userTurnIndex: userTurnIndex,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'question': question,
        if (questionTarget.isNotEmpty) 'question_target': questionTarget,
        'answer': answer,
        if (userTurnIndex >= 0) 'user_turn': userTurnIndex,
      };
}

/// 저장해 둔 답변을 **지금 히스토리에 있는 글자**로 다시 맞춘다.
///
/// `p1_pairs`는 세션이 끝나는 순간의 전사를 얼린다. 그런데 유저가 히스토리
/// 대화 화면을 열면 그때서야 ORIGIN-REPAIR가 돌아, 전사가 잘못 들은 낱말을
/// 문맥으로 고쳐 `original_text`를 덮어쓰고 그 교정본으로 `translated_text`를
/// 만든다. 그대로 두면 P1만 잘못 들린 문장을 붙들고 있게 되고, 유저는 그걸
/// 보고 외운다.
///
/// **여기서 하는 일은 "다시 찾아 붙이기"뿐이다.** 요약도, 재작성도, 번역도
/// 하지 않는다 — 저 자리에 지금 무슨 글자가 있는지만 보고 그대로 가져온다.
///
/// [currentUserTexts]는 지금 방에 남아 있는 **유저 발화의 원어**를,
/// [currentUserTargets]는 같은 자리의 **학습 언어 문장**을 대화 순서 그대로
/// 담은 목록이다. 번호가 범위를 벗어나거나 그 자리가 비었으면 저장해 둔 답을
/// 그대로 쓴다 — 빈 말풍선보다는 옛 글자가 낫다.
List<StepExpandP1Pair> resolveP1PairAnswers(
  List<StepExpandP1Pair> pairs,
  List<String> currentUserTexts, {
  List<String> currentUserTargets = const <String>[],
}) {
  if (pairs.isEmpty) return pairs;
  if (currentUserTexts.isEmpty && currentUserTargets.isEmpty) return pairs;
  return pairs.map((pair) {
    final index = pair.userTurnIndex;
    if (index < 0) return pair;
    final current = index < currentUserTexts.length
        ? currentUserTexts[index].trim()
        : '';
    final target = index < currentUserTargets.length
        ? currentUserTargets[index].trim()
        : '';
    if (current.isEmpty && target.isEmpty) return pair;
    return pair.withAnswer(
      current.isEmpty ? pair.answer : current,
      target: target,
    );
  }).toList(growable: false);
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
/// 한쪽이 비어 있는 쌍은 버린다 — 질문만 있는 줄은 유저가 대답하지 않은
/// 자리고, 답만 있는 줄은 P1이 아니라 그냥 발화다.
List<StepExpandP1Pair> parseStoredP1Pairs(dynamic raw) {
  if (raw is! List) return const <StepExpandP1Pair>[];
  final pairs = <StepExpandP1Pair>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final question = (item['question'] ?? '').toString().trim();
    final questionTarget = (item['question_target'] ?? '').toString().trim();
    final answer = (item['answer'] ?? '').toString().trim();
    if (question.isEmpty || answer.isEmpty) continue;
    // 번호가 없는 것은 이 필드가 생기기 전에 저장된 방이다. -1로 두면
    // [resolveP1PairAnswers]가 손대지 않고 저장된 답을 그대로 쓴다.
    final rawTurn = item['user_turn'];
    final userTurn = rawTurn is int
        ? rawTurn
        : (rawTurn is num
            ? rawTurn.toInt()
            : int.tryParse((rawTurn ?? '').toString().trim()) ?? -1);
    pairs.add(StepExpandP1Pair(
      question: question,
      questionTarget:
          questionTarget.length > kMaxStepExpandP1QuestionTargetChars
              ? ''
              : questionTarget,
      answer: answer,
      userTurnIndex: userTurn < 0 ? -1 : userTurn,
    ));
    if (pairs.length >= kMaxStepExpandP1Pairs) break;
  }
  return pairs;
}

class StepExpandP1Builder {
  StepExpandP1Builder._();

  /// transcript 전체를 읽고 P1 쌍을 만든다.
  ///
  /// [transcript]는 방에서 나눈 **원어** 대화 전체다. 요약해서 넘기지 않는다 —
  /// 어느 AI 턴이 무엇을 요구했는지는 원문에만 남아 있다.
  static Future<StepExpandP1Result> build({
    required String apiKey,
    required List<StepExpansionTurn> transcript,
    required String originLang,
    required String targetLang,
    String model = 'gpt-4.1-mini',
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (apiKey.trim().isEmpty) {
      return const StepExpandP1Result.failed(StepExpandP1Failure.apiKeyMissing);
    }
    final turns = normalizeTranscript(transcript);
    // AI가 묻고 유저가 답한 자리가 한 번도 없으면 P1에 걸 것이 없다.
    if (!turns.any((turn) => turn.isUser) || !turns.any((t) => !t.isUser)) {
      return const StepExpandP1Result.failed(
          StepExpandP1Failure.emptyTranscript);
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
              // 정리지 창작이 아니다. 같은 대화에서 매번 다른 질문이 나오면
              // 그건 이미 실제 학습 기록이 아니다.
              'temperature': 0.2,
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
                  'content': formatTranscript(turns),
                },
              ],
            }),
          )
          .timeout(timeout);
      if (response.statusCode != 200) {
        return const StepExpandP1Result.failed(StepExpandP1Failure.httpError);
      }
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final choices = body['choices'] as List? ?? const <dynamic>[];
      if (choices.isEmpty) {
        return const StepExpandP1Result.failed(StepExpandP1Failure.parseError);
      }
      final content =
          ((choices.first as Map)['message'] as Map?)?['content']?.toString() ??
              '';
      return parseResponse(content, transcript: turns);
    } on TimeoutException {
      return const StepExpandP1Result.failed(StepExpandP1Failure.timeout);
    } catch (_) {
      return const StepExpandP1Result.failed(
          StepExpandP1Failure.transportError);
    }
  }

  /// 빈 줄을 걷어낸 turns. **번호의 기준이 되는 목록**이라 프롬프트와
  /// 검증이 반드시 같은 것을 봐야 한다.
  static List<StepExpansionTurn> normalizeTranscript(
    List<StepExpansionTurn> transcript,
  ) =>
      transcript
          .where((turn) => turn.text.trim().isNotEmpty)
          .toList(growable: false);

  /// 모델에 넘길 번호 붙은 대화록.
  static String formatTranscript(List<StepExpansionTurn> turns) {
    final buffer = StringBuffer();
    for (var i = 0; i < turns.length; i++) {
      final turn = turns[i];
      final text = turn.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      buffer.writeln('[$i] ${turn.isUser ? 'USER' : 'AI'}: $text');
    }
    return buffer.toString().trimRight();
  }

  /// 모델이 돌려준 JSON을 검증해 쌍으로 만든다.
  ///
  /// HTTP와 떼어 둔 이유는 하나다 — **여기가 실제로 틀리는 자리**다. 없는 턴을
  /// 가리켰는지, 답변을 지어냈는지, 순서가 뒤집혔는지는 네트워크 없이 시험할
  /// 수 있어야 한다.
  ///
  /// [transcript]는 [formatTranscript]에 넘긴 것과 **같은 목록**이어야 한다.
  /// 번호가 어긋나면 다른 사람의 말이 붙는다.
  static StepExpandP1Result parseResponse(
    String content, {
    required List<StepExpansionTurn> transcript,
  }) {
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return const StepExpandP1Result.failed(StepExpandP1Failure.parseError);
    }
    final raw = decoded['pairs'];
    if (raw is! List || raw.isEmpty) {
      return const StepExpandP1Result.failed(
          StepExpandP1Failure.validationError);
    }

    final pairs = <StepExpandP1Pair>[];
    var lastUserIndex = -1;
    for (final item in raw) {
      if (pairs.length >= kMaxStepExpandP1Pairs) break;
      if (item is! Map) continue;

      final aiIndex = _asIndex(item['ai_index']);
      final userIndex = _asIndex(item['user_index']);
      if (aiIndex == null || userIndex == null) continue;
      if (aiIndex < 0 || aiIndex >= transcript.length) continue;
      if (userIndex < 0 || userIndex >= transcript.length) continue;
      // 역할이 맞아야 한다. AI 자리에 유저 줄을 대면 그 순간 기록이 뒤집힌다.
      if (transcript[aiIndex].isUser) continue;
      if (!transcript[userIndex].isUser) continue;
      // 답은 물음 뒤에 온다.
      if (aiIndex >= userIndex) continue;
      // 그 사이에 다른 유저 발화가 끼어 있으면, 이 답은 저 물음에 대한 답이
      // 아니다. 엉뚱한 질문에 유저의 진짜 말을 붙이는 것이 가장 나쁜 실패다.
      if (_hasUserTurnBetween(transcript, aiIndex, userIndex)) continue;
      // 대화 순서를 지키고, 한 발화를 두 번 쓰지 않는다.
      if (userIndex <= lastUserIndex) continue;

      final question = (item['question'] ?? '').toString().trim();
      if (question.isEmpty) continue;
      // 길면 코치의 설명이 딸려 온 것이다. 잘라 붙이지 않고 그 쌍을 버린다 —
      // 자르면 문장이 중간에서 끊긴 채 학습 자료로 남는다.
      if (question.length > kMaxStepExpandP1QuestionChars) continue;

      // 학습 언어 질문은 **있으면 좋은 것**이다. 없거나 길면 그 줄만 비우고
      // 쌍은 살린다 — 원어 질문만으로도 P1은 성립한다.
      final rawTarget = (item['question_target'] ?? '').toString().trim();
      final questionTarget =
          rawTarget.length > kMaxStepExpandP1QuestionTargetChars
              ? ''
              : rawTarget;

      // 🔒 답은 **모델이 준 글자를 쓰지 않는다.** transcript에서 꺼낸다.
      final answer = transcript[userIndex].text.trim();
      if (answer.isEmpty) continue;

      pairs.add(StepExpandP1Pair(
        question: question,
        questionTarget: questionTarget,
        answer: answer,
        userTurnIndex: _userTurnOrdinal(transcript, userIndex),
      ));
      lastUserIndex = userIndex;
    }

    if (pairs.isEmpty) {
      return const StepExpandP1Result.failed(
          StepExpandP1Failure.validationError);
    }
    return StepExpandP1Result(
      pairs: pairs,
      failure: StepExpandP1Failure.none,
    );
  }

  /// [index]가 **몇 번째 유저 발화**인가(0부터).
  ///
  /// transcript 전체 번호가 아니라 유저 발화만 세는 번호를 쓴다. 화면 쪽에는
  /// 유저 줄만 순서대로 있어서, AI 턴이 섞인 번호는 저쪽에서 다시 셀 수 없다.
  static int _userTurnOrdinal(List<StepExpansionTurn> transcript, int index) {
    var ordinal = -1;
    for (var i = 0; i <= index; i++) {
      if (transcript[i].isUser) ordinal++;
    }
    return ordinal;
  }

  static bool _hasUserTurnBetween(
    List<StepExpansionTurn> transcript,
    int aiIndex,
    int userIndex,
  ) {
    for (var i = aiIndex + 1; i < userIndex; i++) {
      if (transcript[i].isUser) return true;
    }
    return false;
  }

  /// 모델은 숫자를 문자열로도 돌려준다. 그것만 받아 주고 나머지는 버린다.
  static int? _asIndex(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  /// P1 정리 지시문.
  ///
  /// 이 프롬프트가 지키려는 한 줄은 이것이다 —
  /// **"State what was asked. Never invent what was asked."**
  static String buildSysPrompt({
    required String originLang,
    required String targetLang,
  }) {
    // 🎨 [AI-STYLE] P1은 기록이다. 로비에서 Native를 골랐다고 실제로 건넨
    //   질문이 다른 생각으로 다시 짜이면 안 된다 — 어휘까지만 닿게 묶는다.
    final styleBlock = aiStylePromptBlock(
      targetLang: targetLang,
      scope: 'the "question_target" line only, never the "question" line',
      reach: AiStyleReach.wording,
    );
    return '''You are turning a finished $originLang coaching conversation into a clean study record.

In the room the coach worked out loud. It said what the thought had become, listed two or three directions the thought could grow in, said which one it would take and why, and then asked the user to choose. **None of that belongs in the record.** The record keeps only what the user was asked for, and what the user answered.

[WHAT YOU PRODUCE]
For each AI turn that asked the user for something AND actually got an answer, produce one pair:
- "ai_index": the numbered line of that AI turn.
- "user_index": the numbered line of the USER turn that answered it.
- "question": ONE short question in $originLang saying what that AI turn asked the user for.
- "question_target": the SAME question in $targetLang. Not a looser paraphrase and not a longer one — the same thing asked, worded the way it would naturally be asked in $targetLang.

[THE QUESTION IS NOT YOURS TO INVENT]
This is the whole job. Read the AI turn at "ai_index" and state, as one question, the thing it actually asked the user for. Strip everything else:
- the candidate directions it listed,
- which one it recommended, and why,
- what it said the thought had become,
- any explanation, reassurance, or restatement.
Rules:
- Never ask about something that AI turn did not ask about.
- Never make the question narrower or more specific than that turn was, and never add a fact, a name, a feeling, or an option that is not in it.
- When the turn offered choices, ask for the user's own answer instead of listing them again.
    Not: "여유 있는 삶, 새로운 일, 지친 것 중에 어느 쪽이에요?"
    Yes: "지금은 어떤 변화가 가장 필요하다고 느끼세요?"
  The example shows METHOD only. Never reuse its facts or its topic.
- One sentence, in $originLang, at most $kMaxStepExpandP1QuestionChars characters.
- "question_target" carries the same rules: one sentence, nothing added, nothing narrowed. Write it in $targetLang only — never leave $originLang characters in it.

[WHICH TURNS BECOME PAIRS]
- Only where the USER turn is a real answer that carries meaning.
- Skip a pair when the user only agreed, said 네/응/맞아요, complained about the question, asked the AI something back, or said they wanted to stop.
- Skip the user's opening line. Nothing asked for it.
- Keep the pairs in conversation order, and never use the same USER line twice.
- At most $kMaxStepExpandP1Pairs pairs. Fewer honest pairs beat more shallow ones.

[NEVER]
- Never write the user's answer. It is taken from the transcript, not from you.
- Never point at a line number that is not in the numbered transcript.
- Never pair an AI turn with an answer that did not directly follow it.

Reply as JSON only:
{"pairs":[{"ai_index":<number>,"user_index":<number>,"question":"<one question in $originLang>","question_target":"<the same question in $targetLang>"}]}$styleBlock''';
  }
}
