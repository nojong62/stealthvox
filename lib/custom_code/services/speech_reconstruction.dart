// ════════════════════════════════════════════════════════════════════
// 🗣️ [SPEECH] MY SPEECH → NATIVE ENGLISH
// --------------------------------------------------------------------
// 대화가 끝난 뒤 그 대화를 **개인 말하기 교재**로 바꾸는 두 단계다.
// Duo · Circle Talk · Scenario Talk 셋이 이 파일 하나를 함께 쓴다 —
// 모드마다 프롬프트를 따로 두면 같은 이름의 결과가 방마다 다른 물건이 된다.
// 모드별로 다른 것은 **transcript를 어떻게 긁어오는가**뿐이다.
//
//   Conversation → My Speech → Native English
//
// 순서를 지키는 이유는 경계 때문이다. Native English를 대화 원문에서 바로
// 만들면 상대방이 한 말이 슬쩍 섞여 들어올 길이 열린다. My Speech를 한 번
// 거치면 "유저 의미만 쓴다"는 경계가 데이터에서도 눈에 보인다.
//
// ⚠️ 실패는 실패로 남긴다. 한쪽이 실패했다고 다른 쪽 문장을 복사해 채우지
//    않는다. 두 카드에 같은 글자가 뜨면 비교할 것이 사라져 학습이 죽는다.
// ════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_style.dart';

/// 왜 못 만들었는가. 화면이 "다시 시도"를 걸지 말지를 여기서 가른다.
enum SpeechBuildFailure {
  none,
  apiKeyMissing,
  emptyTranscript,
  httpError,
  emptyReply,
  timeout,
  transportError,
}

/// 한 단계의 결과. 성공이면 [text]가 차 있고, 실패면 비어 있다.
@immutable
class SpeechBuildResult {
  const SpeechBuildResult.ok(this.text) : failure = SpeechBuildFailure.none;
  const SpeechBuildResult.failed(this.failure) : text = '';

  final String text;
  final SpeechBuildFailure failure;

  bool get isUsable =>
      failure == SpeechBuildFailure.none && text.trim().isNotEmpty;
}

/// transcript 한 줄. 누가 말했는지가 이 단계의 전부다 —
/// **유저 줄과 상대 줄을 섞으면 My Speech의 정의가 무너진다.**
@immutable
class SpeechTranscriptTurn {
  const SpeechTranscriptTurn({required this.isUser, required this.text});

  final bool isUser;
  final String text;
}

/// 모델에 넘길 대화록. 화자 표시는 **고정 라벨**이다.
///
/// 이름을 그대로 쓰면 모델이 "Minsu가 이런 말을 했다"를 서술로 바꾸기 쉽다.
/// 누가 유저인지만 분명하면 되므로 `USER` / `OTHER`로 못 박고, 실제 이름은
/// 프롬프트 본문에서 한 번만 알려 준다.
String formatSpeechTranscript(List<SpeechTranscriptTurn> turns) {
  final lines = <String>[];
  for (final turn in turns) {
    final text = turn.text.trim();
    if (text.isEmpty) continue;
    lines.add('${turn.isUser ? 'USER' : 'OTHER'}: $text');
  }
  return lines.join('\n');
}

/// 대화록에 유저 줄이 하나라도 있는가. 없으면 My Speech는 성립하지 않는다 —
/// 그때 상대 줄로 때우면 그건 대화 요약이지 내 말이 아니다.
bool hasUserTurn(List<SpeechTranscriptTurn> turns) =>
    turns.any((t) => t.isUser && t.text.trim().isNotEmpty);

/// 모델이 붙여 보내는 따옴표·라벨을 걷어낸다.
String sanitizeSpeechOutput(String raw) {
  var text = raw.trim();
  // "MY SPEECH:" / "Native English:" 같은 머리표를 지운다.
  text = text.replaceFirst(
    RegExp(r'^\s*(my\s*speech|native\s*english|output)\s*[:\-–]\s*',
        caseSensitive: false),
    '',
  );
  text = text.trim();
  while (text.length >= 2 &&
      ((text.startsWith('"') && text.endsWith('"')) ||
          (text.startsWith('“') && text.endsWith('”')) ||
          (text.startsWith("'") && text.endsWith("'")))) {
    text = text.substring(1, text.length - 1).trim();
  }
  return text;
}

// ════════════════════════════════════════════════════════════════════
// 1단계 — MY SPEECH
// ════════════════════════════════════════════════════════════════════

/// 🗣️ [MY-SPEECH] 대화 전체에서 **유저가 실제로 표현한 것만** 모아 하나의
/// 완결된 발화로 다시 세운다.
///
/// 요약이 아니다. 이어 붙이기도 아니다. 상대가 아무리 좋은 말을 했어도
/// 유저가 자기 말로 받아들이지 않았으면 들어오지 않는다.
///
/// 로비 AI STYLE은 [AiStyleReach.wording]으로만 닿는다 — 어휘와 말맛까지다.
/// 로비에서 Native를 골랐어도 **여기서 사고 배열을 다시 짜지 않는다.** 그건
/// 다음 단계인 Native English의 일이고, 여기서 미리 해 버리면 두 카드를
/// 나란히 놓을 이유가 사라진다.
String buildMySpeechInstructions({
  required String targetLang,
  String userLabel = '',
  String partnerLabel = '',
  String situation = '',
}) {
  final language = targetLang.trim().isEmpty ? 'English' : targetLang.trim();
  final user = userLabel.trim();
  final partner = partnerLabel.trim();
  final whoLine =
      StringBuffer('The transcript marks every line as USER or OTHER. '
          'USER is the person whose speech you are rebuilding.');
  if (user.isNotEmpty) whoLine.write(' USER is $user.');
  if (partner.isNotEmpty) whoLine.write(' OTHER is $partner.');
  final situationLine = situation.trim().isEmpty
      ? ''
      : '\nSituation: ${situation.trim()}. Use it only if the USER lines support it.';

  return '''You are reconstructing the USER'S side of an entire conversation into one complete personal speech.

The conversation may contain many turns between the user and another person or AI.
$whoLine$situationLine

Your job is NOT to summarize the conversation.
Your job is to reconstruct what the USER themselves expressed across the whole conversation as if the USER had said it clearly and continuously in one complete turn.

[SOURCE OF MEANING]
Use only meaning that the USER actually expressed.
Never import an idea merely because the other speaker said it.
A suggestion, interpretation, opinion, reason, feeling, or conclusion from the other speaker belongs in My Speech only if the USER later clearly adopted or expressed it themselves.

[RECONSTRUCT, DO NOT CONCATENATE]
Do not simply join the user's sentences in chronological order.
Read the whole conversation and organize the user's own material into one coherent spoken thought.
You may:
- remove repetition
- merge overlapping ideas
- reorder the user's own points for clarity
- repair references and pronouns
- make transitions natural
- remove conversational filler that adds no meaning
But never change what the user meant.

[HARD LIMITS]
Never add a fact, an opinion, a reason, an emotion, a motivation, a decision, a plan, or a conclusion that the user did not express.
Never make the user's position stronger, weaker, more positive, or more negative than it actually was.
Do not turn uncertainty into certainty.
Do not turn a possibility into a decision.
Do not turn another speaker's idea into the user's idea.

[OUTPUT STYLE]
Make it sound like one person speaking naturally.
It may be several sentences. Do not force it into one grammatical sentence.
The goal is one complete speech, not one sentence.
Use natural spoken $language suitable for saying aloud and practicing.
Write it in $language only. Render any name, role label, or situation that appears in another language into natural $language (translate role or description phrases; romanize real personal names).
Do not explain what you changed.
Do not add headings, quotation marks, commentary, or analysis.
Output only My Speech.${aiStylePromptBlock(targetLang: language, scope: 'the My Speech text you output', reach: AiStyleReach.wording)}''';
}

/// My Speech 한 벌을 만든다. 실패하면 [SpeechBuildResult.failed]다 —
/// **아무 문장이나 지어 채우지 않는다.**
class MySpeechBuilder {
  MySpeechBuilder._();

  static const String model = 'gpt-4.1-mini';
  static const Duration timeout = Duration(seconds: 25);

  static Future<SpeechBuildResult> build({
    required String apiKey,
    required List<SpeechTranscriptTurn> turns,
    required String targetLang,
    String userLabel = '',
    String partnerLabel = '',
    String situation = '',
    void Function(String tag, String message)? onLog,
  }) async {
    if (apiKey.isEmpty) {
      return const SpeechBuildResult.failed(SpeechBuildFailure.apiKeyMissing);
    }
    if (!hasUserTurn(turns)) {
      return const SpeechBuildResult.failed(SpeechBuildFailure.emptyTranscript);
    }
    final transcript = formatSpeechTranscript(turns);
    final sysPrompt = buildMySpeechInstructions(
      targetLang: targetLang,
      userLabel: userLabel,
      partnerLabel: partnerLabel,
      situation: situation,
    );
    try {
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: <String, String>{
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(<String, dynamic>{
              'model': model,
              'temperature': 0.3,
              'max_tokens': 600,
              'messages': <Map<String, String>>[
                <String, String>{'role': 'system', 'content': sysPrompt},
                <String, String>{
                  'role': 'user',
                  'content': 'Conversation:\n$transcript\n\nMy Speech:',
                },
              ],
            }),
          )
          .timeout(timeout);
      if (response.statusCode != 200) {
        onLog?.call('🗣️ [MY-SPEECH]', 'status=${response.statusCode}');
        return const SpeechBuildResult.failed(SpeechBuildFailure.httpError);
      }
      final text = parseResponse(utf8.decode(response.bodyBytes));
      if (text.isEmpty) {
        return const SpeechBuildResult.failed(SpeechBuildFailure.emptyReply);
      }
      onLog?.call('🗣️ [MY-SPEECH]', 'ok len=${text.length}');
      return SpeechBuildResult.ok(text);
    } on Exception catch (error) {
      final failure = error.toString().contains('TimeoutException')
          ? SpeechBuildFailure.timeout
          : SpeechBuildFailure.transportError;
      onLog?.call('🗣️ [MY-SPEECH]', 'failed reason=${error.runtimeType}');
      return SpeechBuildResult.failed(failure);
    }
  }

  /// chat/completions 응답 본문 → 문장. 못 읽으면 빈 문자열이다.
  static String parseResponse(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final choices = decoded['choices'] as List? ?? const <dynamic>[];
      if (choices.isEmpty) return '';
      final message = (choices.first as Map<String, dynamic>)['message']
          as Map<String, dynamic>?;
      return sanitizeSpeechOutput((message?['content'] ?? '').toString());
    } catch (_) {
      return '';
    }
  }
}

// ════════════════════════════════════════════════════════════════════
// 2단계 — NATIVE ENGLISH
// ════════════════════════════════════════════════════════════════════

/// 🇺🇸 [NATIVE-ENGLISH] My Speech와 같은 의미를 **미국 영어 화자가 처음부터
/// 영어로 생각했다면 어떻게 짰을지**로 다시 만든다.
///
/// 입력은 언제나 My Speech다. 대화 원문에서 직접 만들지 않는다 — 그러면
/// 상대방의 말이 들어올 길이 열린다.
class NativeEnglishSpeechBuilder {
  NativeEnglishSpeechBuilder._();

  /// 다듬기가 아니라 재구성이라, 값싼 모델은 원문 배열을 그대로 돌려준다.
  static const String model = 'gpt-4.1-mini';
  static const Duration timeout = Duration(seconds: 25);

  static Future<SpeechBuildResult> build({
    required String apiKey,
    required String mySpeech,
    void Function(String tag, String message)? onLog,
  }) async {
    if (apiKey.isEmpty) {
      return const SpeechBuildResult.failed(SpeechBuildFailure.apiKeyMissing);
    }
    final source = mySpeech.trim();
    if (source.isEmpty) {
      return const SpeechBuildResult.failed(SpeechBuildFailure.emptyTranscript);
    }
    try {
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: <String, String>{
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(<String, dynamic>{
              'model': model,
              'temperature': 0.5,
              'max_tokens': 600,
              'messages': <Map<String, String>>[
                <String, String>{
                  'role': 'system',
                  'content': buildNativeEnglishSpeechInstructions(),
                },
                <String, String>{
                  'role': 'user',
                  'content': 'My Speech:\n$source',
                },
              ],
            }),
          )
          .timeout(timeout);
      if (response.statusCode != 200) {
        onLog?.call('🇺🇸 [NATIVE-ENGLISH]', 'status=${response.statusCode}');
        return const SpeechBuildResult.failed(SpeechBuildFailure.httpError);
      }
      final text =
          MySpeechBuilder.parseResponse(utf8.decode(response.bodyBytes));
      if (text.isEmpty) {
        return const SpeechBuildResult.failed(SpeechBuildFailure.emptyReply);
      }
      onLog?.call('🇺🇸 [NATIVE-ENGLISH]', 'ok len=${text.length}');
      return SpeechBuildResult.ok(text);
    } on Exception catch (error) {
      final failure = error.toString().contains('TimeoutException')
          ? SpeechBuildFailure.timeout
          : SpeechBuildFailure.transportError;
      onLog?.call(
          '🇺🇸 [NATIVE-ENGLISH]', 'failed reason=${error.runtimeType}');
      return SpeechBuildResult.failed(failure);
    }
  }
}
