import 'dart:convert';

import 'package:http/http.dart' as http;

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
  });

  final bool accepted;
  final String text;
  final String reason;
}

class KoreanTurnValidator {
  KoreanTurnValidator._();

  static const String retryLine = '제가 잘 못 들은 것 같아요. 다시 말씀해 주세요.';

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
      );
    }

    final client = http.Client();
    try {
      final response = await client
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
Decide whether the PCM transcription is usable as the user's actual next turn.

Reject ONLY when it is clearly garbled or semantically impossible in the
supplied mode and conversation context.

Accept short answers, fragments, names, numbers, slang, corrections, topic
changes, imperfect grammar, and surprising but still plausible speech. Do not
police style. Do not rewrite, normalize, correct, or guess the user's words.
When uncertain, accept. The application will use the original PCM transcription
verbatim.

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
      if (response.statusCode != 200) {
        return KoreanTurnValidationResult(
          accepted: true,
          text: transcript,
          reason: 'validator_http_${response.statusCode}_fail_open',
        );
      }

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
      return KoreanTurnValidationResult(
        accepted: true,
        text: transcript,
        reason: 'validator_${error.runtimeType}_fail_open',
      );
    } finally {
      client.close();
    }
  }
}
