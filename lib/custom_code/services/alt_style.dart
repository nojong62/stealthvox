// ════════════════════════════════════════════════════════════════════
// 🔀 [ALT-STYLE] "다른 표현 보기" — 같은 뜻을 스타일만 바꿔 다시 쓴다
// --------------------------------------------------------------------
// 히스토리 말풍선과 Keepers 카드가 **같은 물건**을 보여 준다. 두 화면에
// 따로 적어 두면 같은 이름의 Native가 화면마다 다른 문장이 된다 —
// `ai_style.dart`가 스타일 정의를 한곳에 모은 것과 같은 이유다.
//
// 스타일 정의는 여기에도 한 줄 없다. 전부 [aiStyleInstruction]에서 온다.
// ════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_style.dart';

/// 지금 적용 중인 스타일을 뺀 나머지. 팝업이 보여 줄 목록이다.
///
/// 영어가 타겟일 때만 American/British가 존재한다(로비와 같은 규칙).
/// 순서는 Standard → American → British → Native로 고정한다.
List<String> otherAiStyles(String targetLang) {
  final available = isAiStyleTargetLanguage(targetLang)
      ? kAiStyles
      : const <String>['Standard', 'Native'];
  final current = effectiveAiStyle(targetLang: targetLang);
  return available.where((style) => style != current).toList();
}

/// 같은 뜻을 스타일만 바꿔 다시 쓴다.
///
/// 뜻·화자 시점·존댓말 정도는 그대로 두고 어휘와 결만 바꾼다. 실패하면
/// **빈 map이다** — 아무 문장이나 지어 채우지 않는다.
Future<Map<String, String>> fetchAltStyleSentences({
  required String apiKey,
  required String baseText,
  required List<String> styles,
  required String targetLang,
}) async {
  final source = baseText.trim();
  if (apiKey.isEmpty || source.isEmpty || styles.isEmpty) {
    return <String, String>{};
  }
  final targetLanguage =
      targetLang.trim().isEmpty ? 'English' : targetLang.trim();
  // 팝업은 여러 스타일을 한 번에 요청하므로, 스타일마다 지시문 전체를
  // 붙인다. 한 줄 요약만 주면 American과 Native가 같은 문장으로 돌아온다.
  final guide =
      styles.map((s) => '### "$s"\n${aiStyleInstruction(s)}').join('\n\n');
  try {
    final response = await http
        .post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: <String, String>{
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(<String, dynamic>{
            'model': 'gpt-4o-mini',
            'temperature': 0.4,
            'max_tokens': 400,
            'response_format': <String, String>{'type': 'json_object'},
            'messages': <Map<String, String>>[
              <String, String>{
                'role': 'system',
                'content': 'Rewrite ONE $targetLanguage sentence, once per style below.\n'
                    'Keep the meaning, the speaker viewpoint, and the politeness level identical in every version. '
                    'The wording and flavour change; the meaning does not.\n'
                    'The versions must be clearly different from each other — if two styles come out the same, you have not applied them.\n\n'
                    'Styles requested:\n\n$guide\n\n'
                    'Return ONLY valid JSON whose keys are exactly the style names above '
                    'and whose values are the rewritten sentences. No labels, no explanation.',
              },
              <String, String>{'role': 'user', 'content': source},
            ],
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      debugPrint('[ALT-STYLE] status=${response.statusCode}');
      return <String, String>{};
    }
    return parseAltStyleResponse(utf8.decode(response.bodyBytes), styles);
  } catch (e) {
    debugPrint('[ALT-STYLE] failed: $e');
    return <String, String>{};
  }
}

/// chat/completions 응답 → 스타일별 문장. 못 읽으면 빈 map이다.
Map<String, String> parseAltStyleResponse(String body, List<String> styles) {
  try {
    final content =
        jsonDecode(body)['choices'][0]['message']['content'].toString();
    final parsed = jsonDecode(content) as Map<String, dynamic>;
    final result = <String, String>{};
    for (final style in styles) {
      final line = parsed[style]?.toString().trim() ?? '';
      if (line.isNotEmpty) result[style] = line;
    }
    return result;
  } catch (e) {
    debugPrint('[ALT-STYLE] parse failed: $e');
    return <String, String>{};
  }
}
