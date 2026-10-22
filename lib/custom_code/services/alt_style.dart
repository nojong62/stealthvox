import '/custom_code/services/secure_ai_gateway.dart';
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
import 'history_text_model.dart';

/// 지금 적용 중인 스타일을 뺀 나머지. 팝업이 보여 줄 목록이다.
///
/// 영어가 타겟일 때만 American/British가 존재한다(로비와 같은 규칙).
/// 순서는 Standard → American → British → Native로 고정한다.
List<String> otherAiStyles(String targetLang) {
  final current = effectiveAiStyle(targetLang: targetLang);
  return allAltStyles(targetLang).where((style) => style != current).toList();
}

/// 이 타겟 언어에서 고를 수 있는 스타일 전부.
List<String> allAltStyles(String targetLang) =>
    isAiStyleTargetLanguage(targetLang)
        ? kAiStyles
        : const <String>['Standard', 'Native'];

/// 스타일 지시문. 영어 타겟이면 [aiStyleInstruction] 그대로다.
///
/// 그 지시문은 영어 전용이다("US native speaker", "international English").
/// 타겟이 한국어인 방에 그대로 붙이자 Native가 영어로 나왔다(2026-10-22
/// 실기기, 일본어→한국어 방). 비영어 타겟은 Standard·Native 둘뿐이라 그
/// 둘만 타겟 언어로 다시 적는다.
String altStyleInstruction(String style, String targetLang) {
  final lang = targetLang.trim().isEmpty ? 'English' : targetLang.trim();
  if (lang == 'English') return aiStyleInstruction(style);
  if (normalizeAiStyle(style) == 'Native') {
    return '''STYLE — Native
Do not hand back a more polished or more difficult version of the sentence. Work out the thought first, then say it the way a native $lang speaker naturally would.
- Start from what the speaker actually means, intends, feels, and is dealing with right now.
- Build the $lang fresh from that. Do not follow the source's word order or sentence structure.
- Keep the core meaning, the speaker's intent, the situation, the feeling, and the facts that matter.
- Never invent a fact or a feeling the speaker did not express.
- Native does not mean hard words, slang, or piled-up idioms. It means the easy spoken $lang that comes out of a native speaker's mouth.
Write it in $lang. Never switch to another language.''';
  }
  return '''STYLE — Standard
Write clear, natural, standard $lang.
- Grammatically accurate and easy for a learner of $lang to follow.
- Keep slang and strong regional expressions out.
- Preserve the speaker's meaning and intent faithfully.
Write it in $lang. Never switch to another language.''';
}

/// 💾 [ALT-CACHE] 줄 문서에 남긴 다른 표현. 이 줄의 배울글이 그때와 같을
/// 때만 쓴다 — 고친 줄에 옛 문장을 띄우지 않는다.
const String kAltStylesField = 'alt_styles';
const String kAltStylesBaseField = 'alt_styles_base';

Map<String, String> cachedAltStyles(Map<String, dynamic>? data, String base) {
  if (data == null) return const <String, String>{};
  if ((data[kAltStylesBaseField] ?? '').toString().trim() != base.trim()) {
    return const <String, String>{};
  }
  final raw = data[kAltStylesField];
  if (raw is! Map) return const <String, String>{};
  return <String, String>{
    for (final e in raw.entries)
      if (e.value is String && (e.value as String).trim().isNotEmpty)
        e.key.toString(): (e.value as String).trim(),
  };
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
  final guide = styles
      .map((s) => '### "$s"\n${altStyleInstruction(s, targetLanguage)}')
      .join('\n\n');
  try {
    final response = await http
        .post(
          SecureAiGateway.openAiUri('/v1/chat/completions'),
          headers: <String, String>{
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(<String, dynamic>{
            'model': kPostProcessModel,
            'reasoning_effort': kPostProcessReasoningEffort,
            'max_completion_tokens': 400,
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
