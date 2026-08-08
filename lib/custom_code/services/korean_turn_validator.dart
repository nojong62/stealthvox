import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// validator가 판정을 내리지 못한 이유.
///
/// [none]이면 모델이 실제로 판정을 내렸다는 뜻이다. 나머지는 전부 장애이고,
/// 그때 통과한 턴은 "모델이 승인한 발화"가 아니라 "장애라서 통과시킨 발화"다.
/// 로그에서 이 둘이 섞이면 오작동을 추적할 수 없어 값으로 갈라 둔다.
enum KoreanTurnValidatorFailure {
  none,
  apiKeyMissing,
  timeout,
  httpError,
  parseError,
  transportError,
}

/// Three-mode Korean speech gate used after PCM retranscription.
///
/// Deepgram owns only the speech boundary. [transcribedText] is the sentence
/// produced from the recorded PCM by gpt-4o-transcribe. The model may reject an
/// obviously broken/contextually impossible transcript, but it must never
/// rewrite or "repair" the user's words.
class KoreanTurnValidationResult {
  const KoreanTurnValidationResult({
    required this.accepted,
    required this.text,
    required this.reason,
    this.failure = KoreanTurnValidatorFailure.none,
  });

  final bool accepted;
  final String text;
  final String reason;

  /// 판정을 못 내린 이유. [KoreanTurnValidatorFailure.none]이면 모델 판정이다.
  final KoreanTurnValidatorFailure failure;

  /// 장애 때문에 통과시킨 턴인지. 모델이 승인한 것과 구분해서 봐야 한다.
  bool get failedOpen =>
      accepted && failure != KoreanTurnValidatorFailure.none;
}

class KoreanTurnValidator {
  KoreanTurnValidator._();

  static const String retryLine = '제가 잘 못 들은 것 같아요. 다시 말씀해 주세요.';

  /// 연속 반려 탈출구. 이만큼 연달아 막히면 다음 턴은 판정과 무관하게 통과시킨다.
  ///
  /// 실측(2026-08-08)에서 멀쩡한 한국어 "왜 오지 않았어?"가 문맥 불일치로 세 번
  /// 연달아 막혀 유저가 같은 말을 세 번 하고도 못 넘어갔고, 그동안 과금은 계속
  /// 나갔다. 문장 하나가 틀리는 것보다 대화가 막히는 쪽이 나쁘다.
  static const int maxConsecutiveRejects = 2;

  static Future<KoreanTurnValidationResult> validate({
    required String apiKey,
    required String transcribedText,
    required String mode,
    required String modeContext,
    String recentConversation = '',
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final transcript = transcribedText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (transcript.isEmpty) {
      return const KoreanTurnValidationResult(
        accepted: false,
        text: '',
        reason: 'empty_transcript',
      );
    }

    // A validation outage must not turn a healthy transcription into a dead
    // microphone. Network/model failures therefore fail open while local hard
    // failures (empty text) fail closed.
    if (apiKey.isEmpty) {
      return KoreanTurnValidationResult(
        accepted: true,
        text: transcript,
        reason: 'validator_key_unavailable_fail_open',
        failure: KoreanTurnValidatorFailure.apiKeyMissing,
      );
    }

    // 장애 유형을 갈라 두면 로그에서 "모델이 승인함"과 "장애라서 통과시킴"이
    // 섞이지 않는다. 응답 본문·원문·키는 어디에도 싣지 않는다 — 상태 코드와
    // 예외 타입 이름까지만 남긴다.
    KoreanTurnValidationResult failOpen(
      KoreanTurnValidatorFailure failure,
      String reason,
    ) =>
        KoreanTurnValidationResult(
          accepted: true,
          text: transcript,
          reason: reason,
          failure: failure,
        );

    final client = http.Client();
    try {
      final http.Response response;
      try {
        response = await client
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: <String, String>{
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(<String, dynamic>{
              'model': 'gpt-4o-mini',
              'temperature': 0,
              'max_tokens': 100,
              'response_format': <String, String>{'type': 'json_object'},
              'messages': <Map<String, String>>[
                <String, String>{
                  'role': 'system',
                  'content':
                      '''You are a conservative Korean speech-transcript gate.
Judge ONE thing: is this text readable as a real Korean utterance?

Reject ONLY when the text itself is broken — mangled syllables, word salad, or
a stump no Korean speaker would produce ("밟", "트리거나기 전에").

NEVER reject for context. Grammatical Korean is accepted even when it does not
fit the mode, the topic, or the previous turn. Off-topic questions, abrupt
subject changes, complaints, jokes, and non sequiturs are all valid turns — a
person may say anything next. MODE and RECENT CONVERSATION are reference only,
for telling a real proper noun from a mangled one. They are never grounds to
reject.

Accept short answers, fragments, names, numbers, slang, corrections, imperfect
grammar, and surprising but plausible speech. Do not police style. Do not
rewrite, normalize, correct, or guess the user's words. When uncertain, accept.
The application will use the original PCM transcription verbatim.

Return JSON only:
{"accepted":true|false,"reason":"brief_machine_reason"}''',
                },
                <String, String>{
                  'role': 'user',
                  'content': '''MODE: $mode
MODE CONTEXT:
$modeContext

RECENT CONVERSATION:
${recentConversation.trim().isEmpty ? '(none)' : recentConversation.trim()}

PCM TRANSCRIPTION:
$transcript''',
                },
              ],
            }),
          )
          .timeout(timeout);
      } on TimeoutException catch (error) {
        return failOpen(KoreanTurnValidatorFailure.timeout,
            'validator_${error.runtimeType}_fail_open');
      } catch (error) {
        // 소켓 끊김·DNS 실패 등 전송 계층 오류.
        return failOpen(KoreanTurnValidatorFailure.transportError,
            'validator_${error.runtimeType}_fail_open');
      }

      if (response.statusCode != 200) {
        return failOpen(KoreanTurnValidatorFailure.httpError,
            'validator_http_${response.statusCode}_fail_open');
      }

      try {
        final envelope =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final content =
            envelope['choices']?[0]?['message']?['content']?.toString() ?? '';
        final decision = jsonDecode(content) as Map<String, dynamic>;
        final accepted = decision['accepted'] == true;
        return KoreanTurnValidationResult(
          accepted: accepted,
          text: accepted ? transcript : '',
          reason: decision['reason']?.toString().trim().isNotEmpty == true
              ? decision['reason'].toString().trim()
              : (accepted ? 'accepted' : 'rejected'),
        );
      } catch (error) {
        // 응답이 200인데 JSON이 아니거나 모양이 다르다. 본문은 남기지 않는다.
        return failOpen(KoreanTurnValidatorFailure.parseError,
            'validator_${error.runtimeType}_fail_open');
      }
    } finally {
      client.close();
    }
  }
}
