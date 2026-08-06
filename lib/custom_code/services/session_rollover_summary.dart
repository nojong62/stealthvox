import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 30분 세션이 교체될 때 직전 세션을 한 문단으로 압축한다.
///
/// 대화방은 30분마다 기록·과금 묶음을 새로 열지만 화면은 끊기지 않는다. 문맥을
/// 통째로 버리면 AI가 방금까지 하던 얘기를 모르는 사람이 되고, 통째로 들고 가면
/// 입력 토큰이 시간에 비례해 늘어난다. 그 사이를 메우는 것이 이 요약이다.
///
/// **실패는 롤오버를 막지 않는다.** 요약이 필요한 시점에는 정산이 이미 끝나 있어,
/// 여기서 되돌리면 과금 구간과 History가 어긋난다. 그래서 어떤 실패든 빈 문자열을
/// 돌려주고 호출부는 최근 턴만 들고 다음 세션을 연다.
class SessionRolloverSummary {
  SessionRolloverSummary._();

  /// 실패하면 빈 문자열. 호출부는 요약 없이 진행한다.
  static Future<String> summarize({
    required String apiKey,
    required List<Map<String, String>> recentTurns,
    required String modeContext,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (apiKey.isEmpty) return '';

    final transcript = recentTurns
        .map((turn) {
          final role = (turn['role'] ?? '').trim();
          final content = (turn['content'] ?? '').trim();
          if (content.isEmpty) return '';
          final speaker = role == 'assistant' ? 'AI' : '사용자';
          return '$speaker: $content';
        })
        .where((line) => line.isNotEmpty)
        .join('\n');
    if (transcript.trim().isEmpty) return '';

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
                'temperature': 0.3,
                'max_tokens': 220,
                'messages': <Map<String, String>>[
                  <String, String>{
                    'role': 'system',
                    'content':
                        '''You compress the previous stretch of a spoken Korean
conversation so it can be handed to the next session.

Write ONE short Korean paragraph (3 sentences at most) covering only:
- what the user talked about and what matters to them in it
- anything already established about the user (plans, people, situation)
- where the conversation was heading when it was cut

RULES
- Only what was actually said. Never invent, guess, or fill gaps.
- No greetings, no meta ("이전 대화에서는"), no bullet points, no labels.
- Plain Korean prose. Nothing else in the output.''',
                  },
                  <String, String>{
                    'role': 'user',
                    'content': 'ROOM: $modeContext\n\nCONVERSATION:\n$transcript',
                  },
                ],
              }),
            )
            .timeout(timeout);
      } catch (_) {
        // 타임아웃·소켓 오류 모두 요약 없이 진행한다.
        return '';
      }

      if (response.statusCode != 200) return '';

      try {
        final envelope =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final content =
            envelope['choices']?[0]?['message']?['content']?.toString() ?? '';
        return content.replaceAll(RegExp(r'\s+'), ' ').trim();
      } catch (_) {
        return '';
      }
    } finally {
      client.close();
    }
  }
}
