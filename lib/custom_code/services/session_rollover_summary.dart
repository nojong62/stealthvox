import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;


/// 10분 세션이 교체될 때 지금까지의 대화를 한 문단으로 압축한다.
///
/// 대화방은 10분마다 기록·과금 묶음을 새로 열지만 화면은 끊기지 않는다. 문맥을
/// 통째로 버리면 AI가 방금까지 하던 얘기를 모르는 사람이 되고, 통째로 들고 가면
/// 입력 토큰이 시간에 비례해 늘어난다. 그 사이를 메우는 것이 이 요약이다.
///
/// **요약은 누적된다.** 직전 요약([previousSummary])과 방금 10분을 합쳐 다시
/// 한 문단으로 줄이므로, 방을 나가지 않는 한 AI는 대화 전체의 큰 줄기를 계속
/// 들고 간다. 예전에는 직전 10분만 요약해 그 앞 내용이 매번 사라졌다. 출력
/// 길이는 그대로라 매 턴 입력 토큰은 시간에 비례해 늘지 않는다.
///
/// **실패는 롤오버를 막지 않는다.** 요약이 필요한 시점에는 정산이 이미 끝나 있어,
/// 여기서 되돌리면 과금 구간과 History가 어긋난다. 그래서 어떤 실패든
/// [previousSummary]를 그대로 돌려주고 호출부는 그것만 들고 다음 세션을 연다 —
/// 빈 문자열을 돌려주면 여태 쌓은 줄기까지 같이 날아간다.
class SessionRolloverSummary {
  SessionRolloverSummary._();

  /// 누적 요약. 실패하면 [previousSummary]를 그대로 돌려준다.
  static Future<String> summarize({
    required String apiKey,
    required List<Map<String, String>> recentTurns,
    required String modeContext,
    String previousSummary = '',
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (apiKey.isEmpty) return previousSummary;

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
    if (transcript.trim().isEmpty) return previousSummary;

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
                'max_tokens': 260,
                'messages': <Map<String, String>>[
                  <String, String>{
                    'role': 'system',
                    'content':
                        '''You compress a spoken Korean conversation so it can be
handed to the next session. You may receive an EARLIER SUMMARY of everything
before the CONVERSATION; merge both into one summary of the whole conversation
so far.

Write ONE short Korean paragraph (4 sentences at most) covering only:
- what the user talked about and what matters to them in it
- anything already established about the user (plans, people, situation)
- where the conversation was heading when it was cut

RULES
- Keep what the EARLIER SUMMARY established unless the CONVERSATION changed it.
- Only what was actually said. Never invent, guess, or fill gaps.
- No greetings, no meta ("이전 대화에서는"), no bullet points, no labels.
- Plain Korean prose. Nothing else in the output.''',
                  },
                  <String, String>{
                    'role': 'user',
                    'content': previousSummary.isEmpty
                        ? 'ROOM: $modeContext\n\nCONVERSATION:\n$transcript'
                        : 'ROOM: $modeContext\n\nEARLIER SUMMARY:\n'
                            '$previousSummary\n\nCONVERSATION:\n$transcript',
                  },
                ],
              }),
            )
            .timeout(timeout);
      } catch (_) {
        // 타임아웃·소켓 오류 모두 직전 요약만 들고 진행한다.
        return previousSummary;
      }

      if (response.statusCode != 200) return previousSummary;

      try {
        final envelope =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final content =
            envelope['choices']?[0]?['message']?['content']?.toString() ?? '';
        final merged = content.replaceAll(RegExp(r'\s+'), ' ').trim();
        return merged.isEmpty ? previousSummary : merged;
      } catch (_) {
        return previousSummary;
      }
    } finally {
      client.close();
    }
  }
}
