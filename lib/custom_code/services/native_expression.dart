// ════════════════════════════════════════════════════════════════════
// 💡 [NATIVE-EXPR] "현지인 표현" — 확정된 대사에서 쓸 만한 표현 하나
// --------------------------------------------------------------------
// 최종 수정이 끝난 방에서 줄마다 연필 자리에 붙는다. 그 대사에서 유추한,
// 현지인이 실제로 입에 올리는 표현 하나와 뜻·쓰는 상황을 준다.
//
// 누를 때마다 **다른 표현**이 나와야 한다. 그래서 이 줄에서 이미 보여 준
// 표현을 함께 보내 피하게 한다. 실패하면 null — 지어 채우지 않는다.
// ════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'history_text_model.dart';
import 'secure_ai_gateway.dart';

class NativeExpression {
  const NativeExpression({
    required this.expression,
    required this.meaning,
    required this.usage,
  });

  /// 배울 언어로 적힌 표현.
  final String expression;

  /// 대화 언어로 적은 뜻.
  final String meaning;

  /// 대화 언어로 적은, 언제 쓰는지.
  final String usage;
}

Future<NativeExpression?> fetchNativeExpression({
  required String apiKey,
  required String line,
  required String originalLine,
  required String targetLang,
  required String nativeLang,
  required String explainLang,
  List<String> avoid = const <String>[],
}) async {
  final source = line.trim();
  if (apiKey.isEmpty || source.isEmpty) return null;
  final target = targetLang.trim().isEmpty ? 'English' : targetLang.trim();
  final native = nativeLang.trim().isEmpty ? 'English' : nativeLang.trim();
  final explain = explainLang.trim().isEmpty ? 'English' : explainLang.trim();
  final avoidBlock = avoid.isEmpty
      ? ''
      : '\nAlready shown for this line — give something DIFFERENT from all of these '
          '(not a small variation of them):\n'
          '${avoid.map((e) => '- $e').join('\n')}\n';
  final user = StringBuffer('Line ($target): $source');
  if (originalLine.trim().isNotEmpty && originalLine.trim() != source) {
    user.write('\nSame line in $native: ${originalLine.trim()}');
  }
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
            'max_completion_tokens': 300,
            'response_format': <String, String>{'type': 'json_object'},
            'messages': <Map<String, String>>[
              <String, String>{
                'role': 'system',
                'content':
                    'A learner of $target is studying one line from their own conversation. '
                        'From what that line is about, pick ONE useful expression that native $target speakers '
                        'really say in everyday life in this kind of situation — an idiom, a set phrase, '
                        'or a natural spoken chunk the learner can reuse.\n'
                        '- It must fit the topic or feeling of the line. Not a random idiom.\n'
                        '- Prefer common spoken expressions over rare, dated, or bookish ones.\n'
                        '- Keep it short: a phrase or one short sentence, written in $target.\n'
                        '$avoidBlock\n'
                        'Return ONLY JSON: {"expression": "...", "meaning": "...", "usage": "..."}\n'
                        '"expression": the expression in $target.\n'
                        '"meaning": what it means, in $explain, one short line.\n'
                        '"usage": when and how people use it, in $explain, one or two short sentences. '
                        'You may include a tiny example in $target.',
              },
              <String, String>{'role': 'user', 'content': user.toString()},
            ],
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      debugPrint('[NATIVE-EXPR] status=${response.statusCode}');
      return null;
    }
    return parseNativeExpressionResponse(utf8.decode(response.bodyBytes));
  } catch (e) {
    debugPrint('[NATIVE-EXPR] failed: $e');
    return null;
  }
}

/// chat/completions 응답 → 표현. 표현이 비었으면 null이다.
NativeExpression? parseNativeExpressionResponse(String body) {
  try {
    final content =
        jsonDecode(body)['choices'][0]['message']['content'].toString();
    final parsed = jsonDecode(content) as Map<String, dynamic>;
    final expression = (parsed['expression'] ?? '').toString().trim();
    if (expression.isEmpty) return null;
    return NativeExpression(
      expression: expression,
      meaning: (parsed['meaning'] ?? '').toString().trim(),
      usage: (parsed['usage'] ?? '').toString().trim(),
    );
  } catch (e) {
    debugPrint('[NATIVE-EXPR] parse failed: $e');
    return null;
  }
}
