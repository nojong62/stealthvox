// ====================================================================
// 🌱 [STEP-EXPANSION] 방이 확정한 사다리를 배울글로 옮긴다
// --------------------------------------------------------------------
// **이 파일은 더 이상 "생각이 어디서 자랐는지"를 찾지 않는다.**
//
// 예전에는 방이 상담만 하고, 대화가 끝난 뒤 여기서 transcript 전체를 읽어
// 사다리를 사후 재구성했다. 그럴 수밖에 없었던 이유는 하나였다 — 유저가
// 자기 말로 답했으니 무엇이 글에 들어갔는지 방도 몰랐다.
//
// 지금은 방이 안다. AI가 이어 붙일 문장 셋을 써 주고 유저가 고르므로,
// 무엇이 붙었는지가 매 턴 값으로 확정된다. 그 값이 `expanded_sentence`로
// 줄마다 저장되고, 이 파일은 그걸 받아 **옮기기만** 한다.
//
//   방(원어, 매 턴 확정) → expanded_sentence → [여기: 번역] → P2 → P3
//
// 그래서 청크도 모델에게 묻지 않는다. 사다리가 누적형이라 앞 칸이 뒤 칸의
// 접두사이고, 무엇이 새로 들어왔는지는 계산으로 정확히 나온다.
//
// ⚠️ 실패는 숨기지 않는다. 배울글이 없으면 P2에 걸 것이 없으므로
// [StepExpansionFailure]로 돌려주고, 호출부가 재시도하거나 P2 없이 방을
// 남긴다.
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

/// 단계 수 상한. 방이 다섯 번쯤에서 닫으므로 여유를 하나 더 둔 값이다.
const int kMaxStepExpansions = 6;

/// 이 미만이면 사다리라고 보지 않는다.
const int kMinUserTurnsForExpansion = 1;

final RegExp _hangul = RegExp(r'[가-힣]');

class StepExpansionBuilder {
  StepExpansionBuilder._();

  /// 방이 확정해 둔 원어 사다리를 배울글 사다리로 옮긴다.
  ///
  /// **여기는 더 이상 "생각이 어디서 자랐는지"를 찾지 않는다.** 유저가 번호를
  /// 고를 때마다 무엇이 붙었는지는 방이 이미 알고 있고, 그 값이 [ladder]다.
  /// 남은 일은 옮기는 것뿐이다.
  ///
  /// [ladder]는 **누적형**이다. 다음 칸이 앞 칸을 통째로 품는다.
  static Future<StepExpansionResult> build({
    required String apiKey,
    required List<String> ladder,
    required String originLang,
    required String targetLang,
    String model = 'gpt-4.1-mini',
    Duration timeout = const Duration(seconds: 40),
  }) async {
    if (apiKey.trim().isEmpty) {
      return const StepExpansionResult.failed(
          StepExpansionFailure.apiKeyMissing);
    }
    final steps = normalizeLadder(ladder);
    if (steps.isEmpty) {
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
              // 옮기는 일이다. 같은 사다리에서 매번 다른 영어가 나오면 유저는
              // 자기 글이 자란 과정이 아니라 모델의 기분을 보게 된다.
              'temperature': 0.2,
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
                  'content': formatLadder(steps),
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
      return parseResponse(content, ladder: steps);
    } on TimeoutException {
      return const StepExpansionResult.failed(StepExpansionFailure.timeout);
    } catch (_) {
      return const StepExpansionResult.failed(
          StepExpansionFailure.transportError);
    }
  }

  /// 빈 칸과 제자리걸음을 걷어낸 사다리. 상한도 여기서 건다.
  static List<String> normalizeLadder(List<String> ladder) {
    final steps = <String>[];
    for (final raw in ladder) {
      final text = raw.trim();
      if (text.isEmpty) continue;
      // 같은 글이 두 칸이면 유저는 아무 변화도 못 본다.
      if (steps.isNotEmpty && steps.last == text) continue;
      steps.add(text);
      if (steps.length >= kMaxStepExpansions) break;
    }
    return steps;
  }

  /// 모델에 넘길 원어 사다리.
  static String formatLadder(List<String> ladder) {
    final buffer = StringBuffer();
    for (var i = 0; i < ladder.length; i++) {
      buffer.writeln('${i + 1}. ${ladder[i]}');
    }
    return buffer.toString().trimRight();
  }

  /// 모델이 돌려준 JSON을 검증해 사다리로 만든다.
  ///
  /// HTTP와 떼어 둔 이유는 하나다 — **여기가 실제로 틀리는 자리**다. 누적이
  /// 깨졌는지, 한글이 섞였는지, 칸 수가 안 맞는지는 네트워크 없이 시험할 수
  /// 있어야 한다.
  ///
  /// 청크는 **모델에게 묻지 않는다.** 사다리가 누적형이라 앞 칸이 뒤 칸의
  /// 접두사이고, 그러면 무엇이 새로 들어왔는지는 계산으로 정확히 나온다.
  /// 예전에 모델이 청크를 만들던 시절에는 문장을 못 덮는 청크가 화면까지
  /// 새어 나갔다.
  static StepExpansionResult parseResponse(
    String content, {
    required List<String> ladder,
  }) {
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return const StepExpansionResult.failed(StepExpansionFailure.parseError);
    }
    final raw = decoded['steps'];
    if (raw is! List || raw.isEmpty) {
      return const StepExpansionResult.failed(
          StepExpansionFailure.validationError);
    }

    // 원어 쪽에서 이번 칸에 무엇이 붙었는지. 화면에 근거로 실린다.
    final addedNative = <String>[];
    var previousNative = '';
    for (final step in ladder) {
      addedNative.add(step.startsWith(previousNative) && previousNative.isNotEmpty
          ? step.substring(previousNative.length).trim()
          : step);
      previousNative = step;
    }

    final steps = <StepExpansionStep>[];
    var previousText = '';
    for (var i = 0; i < raw.length && i < ladder.length; i++) {
      final item = raw[i];
      final text = (item is Map ? (item['text'] ?? '') : item).toString().trim();
      // 배울글 자리에 원어가 남아 있으면 그 칸은 학습 자료가 아니다.
      if (text.isEmpty || _hangul.hasMatch(text)) continue;
      if (previousText.isNotEmpty && _sameSentence(previousText, text)) continue;

      steps.add(StepExpansionStep(
        step: steps.length + 1,
        text: text,
        addedMeaning: i < addedNative.length ? addedNative[i] : '',
        chunks: _chunksFor(previous: previousText, text: text),
        primaryMorph: _addedPart(previous: previousText, text: text),
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

  /// 이번 칸에 새로 들어온 부분. 앞 칸을 품고 있지 않으면 빈 문자열이다.
  static String _addedPart({required String previous, required String text}) {
    if (previous.isEmpty) return '';
    if (!text.startsWith(previous)) return '';
    return text.substring(previous.length).trim();
  }

  /// 직전 칸에 대고 잰 변화. 누적형이라 두 조각으로 갈린다.
  static List<P2Chunk> _chunksFor({
    required String previous,
    required String text,
  }) {
    // 첫 칸에는 비교 대상이 없다. 통째로 새 문장이다.
    if (previous.isEmpty) {
      return <P2Chunk>[P2Chunk(text: text, type: 'new')];
    }
    if (!text.startsWith(previous)) {
      // 모델이 앞 칸을 손댔다. 어디가 새것인지 자신할 수 없으므로 통짜로 둔다.
      return fallbackP2Chunks(text);
    }
    final added = text.substring(previous.length);
    if (added.trim().isEmpty) return fallbackP2Chunks(text);
    return <P2Chunk>[
      P2Chunk(text: previous, type: 'kept', from: previous),
      P2Chunk(text: added, type: 'new'),
    ];
  }

  static bool _sameSentence(String a, String b) =>
      _normalize(a) == _normalize(b);

  static String _normalize(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  /// 옮기기 지시문.
  ///
  /// 이 프롬프트가 지키려는 한 줄은 이것이다 —
  /// **"Each step must contain the previous one, word for word."**
  static String buildSysPrompt({
    required String originLang,
    required String targetLang,
  }) {
    final styleBlock = aiStylePromptBlock(
      targetLang: targetLang,
      scope: 'every step you produce',
      // 🎨 사다리는 **유저 글의 배열 그 자체**다. 로비에서 Native를 골랐다고
      //   여기서 정보 순서를 갈아엎으면, P3의 Native English가 보여 줄 차이가
      //   P2에서 미리 소진된다. 스타일은 어휘까지만 닿는다.
      reach: AiStyleReach.wording,
    );
    return '''The user built one piece of writing in $originLang, one sentence at a time. You are given it as a ladder: each numbered step is the whole text as it stood after that turn, so every step contains the one before it and adds one more sentence at the end.

Put that same ladder into $targetLang.

[THE ONE RULE]
Step 2 must begin with your step 1, word for word. Step 3 must begin with your step 2, word for word. And so on.
The user watches this text grow on screen. If an earlier part changes wording between steps, they cannot see what they just added — the whole screen moves instead.
So: translate the NEW sentence at each step, and carry everything before it over unchanged.

[HOW TO TRANSLATE EACH NEW SENTENCE]
- Everyday spoken $targetLang the user could actually say out loud. Not written prose, not showy vocabulary.
- Keep their meaning, viewpoint, tense, and how strongly they put it.
- Never add a fact, a feeling, or a reason. Never drop one.
- Keep it short. They said one short sentence; give back one short sentence.
- Do not join the sentences into one long one. It stays a series of short sentences, the way they built it.

[NEVER]
- Never reorganise the writing, and never improve on it.
- Never leave $originLang characters in a step.
- Never produce more or fewer steps than you were given.

Reply as JSON only, one entry per numbered step, in the same order:
{"steps":[{"text":"<the whole text so far, in $targetLang>"}]}$styleBlock''';
  }
}
