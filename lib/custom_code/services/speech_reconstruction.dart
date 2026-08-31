// ════════════════════════════════════════════════════════════════════
// 🗣️ [SPEECH] MY ENGLISH → NATIVE ENGLISH
// --------------------------------------------------------------------
// 대화가 끝난 뒤 그 대화를 **개인 말하기 교재**로 바꾸는 두 단계다.
// Duo · Circle Talk · Scenario Talk 셋이 이 파일 하나를 함께 쓴다 —
// 모드마다 프롬프트를 따로 두면 같은 이름의 결과가 방마다 다른 물건이 된다.
// 모드별로 다른 것은 **transcript를 어떻게 긁어오는가**뿐이다.
//
//   Conversation Seed → My English → Native English
//
// 순서를 지키는 이유는 경계 때문이다. My English가 대화를 **재료로 삼아**
// 학습용 스피치 하나를 세우고, Native English는 그 완성된 스피치의 의미를
// 그대로 둔 채 표현만 다시 짠다. Native English를 대화 원문에서 바로 만들면
// 두 단계가 같은 일을 하게 되고, 나란히 놓을 이유가 사라진다.
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
/// **유저 줄과 상대 줄을 섞으면 My English의 seed가 무너진다.**
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

/// 대화록에 유저 줄이 하나라도 있는가. 없으면 My English는 성립하지 않는다 —
/// 유저가 한마디도 안 한 방에서 상대 줄로 seed를 잡으면 그건 대화 요약이다.
bool hasUserTurn(List<SpeechTranscriptTurn> turns) =>
    turns.any((t) => t.isUser && t.text.trim().isNotEmpty);

/// 모델이 붙여 보내는 따옴표·라벨을 걷어낸다.
String sanitizeSpeechOutput(String raw) {
  var text = raw.trim();
  // "MY ENGLISH:" / "Native English:" 같은 머리표를 지운다.
  // 옛 이름("My Speech:")도 함께 걷는다 — 모델이 종종 옛 라벨을 붙인다.
  text = text.replaceFirst(
    RegExp(
        r'^\s*(my\s*speech|my\s*english|native\s*english|output)\s*[:\-–]\s*',
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
// 1단계 — MY ENGLISH
// ════════════════════════════════════════════════════════════════════

/// 🗣️ [MY-ENGLISH] 대화에서 고른 소재를 **말하기 연습용 확장 스피치**로 세운다.
///
/// **실제 발화의 복원이 아니다**(실장님 결정, 2026-08-31). 예전 My Speech는
/// "유저가 실제로 표현한 것만" 모으는 자리였다. 그 결과는 충실했지만 대화가
/// 짧으면 연습할 것도 짧았고, 에코잉·쉐도잉에 얹을 살이 없었다.
///
/// 이제 대화는 **재료(seed)**다. 소재 한둘을 골라 중심 생각 하나를 세우고,
/// 원 대화에 없던 이유·상황·예시·생각까지 학습 목적으로 붙여, 한 사람이
/// 자연스럽게 이어 말하는 스피치를 만든다.
///
/// 넓힌 만큼 경계는 좁게 셋만 남는다.
///   · 원 대화와 **모순되는** 것은 만들지 않는다.
///   · 유저의 민감하거나 구체적인 사실을 지어내지 않는다.
///   · 대화 요약도, 질문-답변을 이어 붙인 것도 아니다.
///
/// 저장 칸은 `my_speech` 그대로다 — 이름만 바뀌었고 자리는 같다.
///
/// ⚠️ **호흡·분절은 여기서 설계하지 않는다.** 글을 청크에 맞추지 않고, 완성된
/// 글을 읽은 **실제 소리**를 나눈다 — TTS 전체 음성을 `audio_silence_analyzer`가
/// 훑고 `BreathEchoingEngine`이 그 분절로 에코잉·쉐도잉을 돌린다. 이 프롬프트는
/// 자연스러운 spoken English 하나에만 집중한다.
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
          'USER is the learner you are writing this speech for.');
  if (user.isNotEmpty) whoLine.write(' USER is $user.');
  if (partner.isNotEmpty) whoLine.write(' OTHER is $partner.');
  final situationLine = situation.trim().isEmpty
      ? ''
      : '\nSituation: ${situation.trim()}. Use it as background when it fits the seed you pick.';

  return '''You are writing ONE speaking-practice speech for a language learner, using their own conversation as the seed.

The conversation may contain many turns between the user and another person or AI.
$whoLine$situationLine

This is NOT a record of the conversation and NOT a summary of it.
Read the whole conversation, pick ONE or TWO topics from it that are worth practising out loud, and build a single connected speech the USER could actually say.

[PICK A SEED, THEN BUILD]
Choose material the USER engaged with — something they said, asked, decided, or reacted to.
Settle on ONE central point, then develop it.
A natural shape is: the point, why it is so, a concrete detail, an example or a contrast, what the user personally makes of it, and where the thought lands.
These are not mandatory stages. Use only the ones this material actually needs, and never force every speech through the same formula.

[YOU MAY ADD]
This is a learning text, not a transcript, so you may write what the conversation never said:
- a reason or motivation that fits what the user expressed
- ordinary situational detail
- a common everyday example
- a natural personal thought, or a small conclusion

[HARD LIMITS]
Never contradict the conversation. Nothing you add may conflict with what the user said, decided, or felt.
Never invent a specific or sensitive fact about the user. No names, places, employers, numbers, dates, health details, money, or relationships that the conversation did not supply.
Never summarize the conversation, and never report what the other speaker said.
Never write a dialogue, a question-and-answer, or a string of exchanged turns. It is ONE person speaking continuously.
Never reverse the user's stance or make it stronger or weaker than it was.

[OUTPUT STYLE]
One person, speaking naturally and continuously.
Several sentences that connect into a single thought. Do not force it into one grammatical sentence, and do not stretch one sentence to make it long.
Keep it something the user could genuinely use again in their own life.
Plain, everyday spoken $language. No literary phrasing, no heavy idioms, no showy vocabulary.
Write it in $language only. Render any name, role label, or situation that appears in another language into natural $language (translate role or description phrases; romanize real personal names).
Do not explain what you changed.
Do not add headings, quotation marks, commentary, or analysis.
Output only My English.${aiStylePromptBlock(targetLang: language, scope: 'the My English text you output', reach: AiStyleReach.wording)}''';
}

/// My English 한 벌을 만든다. 실패하면 [SpeechBuildResult.failed]다 —
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
              // 🌡️ 확장 생성이라 0.3은 원문에 붙어 버린다. 그렇다고 자유
              //   창작도 아니라 0.7은 대화와 무관한 디테일을 늘린다.
              //   0.6에서 시작하고 실기기 결과를 보고 조정한다(실장님 지시).
              'temperature': 0.6,
              'max_tokens': 600,
              'messages': <Map<String, String>>[
                <String, String>{'role': 'system', 'content': sysPrompt},
                <String, String>{
                  'role': 'user',
                  'content': 'Conversation:\n$transcript\n\nMy English:',
                },
              ],
            }),
          )
          .timeout(timeout);
      if (response.statusCode != 200) {
        onLog?.call('🗣️ [MY-ENGLISH]', 'status=${response.statusCode}');
        return const SpeechBuildResult.failed(SpeechBuildFailure.httpError);
      }
      final text = parseResponse(utf8.decode(response.bodyBytes));
      if (text.isEmpty) {
        return const SpeechBuildResult.failed(SpeechBuildFailure.emptyReply);
      }
      onLog?.call('🗣️ [MY-ENGLISH]', 'ok len=${text.length}');
      return SpeechBuildResult.ok(text);
    } on Exception catch (error) {
      final failure = error.toString().contains('TimeoutException')
          ? SpeechBuildFailure.timeout
          : SpeechBuildFailure.transportError;
      onLog?.call('🗣️ [MY-ENGLISH]', 'failed reason=${error.runtimeType}');
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

/// 🇺🇸 [NATIVE-ENGLISH] My English와 같은 의미를 **미국 영어 화자가 처음부터
/// 영어로 생각했다면 어떻게 짰을지**로 다시 만든다.
///
/// 입력은 언제나 My English다. 대화 원문에서 직접 만들지 않는다 — 그러면
/// 두 단계가 같은 일을 하게 된다. 여기서 새 내용을 더하지도 않는다. 넓히는
/// 일은 앞 단계가 이미 끝냈고, 이 단계가 바꾸는 것은 **표현뿐이다.**
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
                  'content': 'My English:\n$source',
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
