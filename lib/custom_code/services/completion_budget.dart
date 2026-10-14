// 📏 [COMPLETION-BUDGET] 추론 모델이 출력 예산을 다 썼는지 남긴다.
//
// Luna는 추론 토큰도 `max_completion_tokens`에서 꺼내 쓴다. 예산이 바닥나면
// HTTP 200인데 본문이 비거나 JSON이 잘린다 — 호출부는 그걸 "결과 없음"으로
// 조용히 넘긴다. 대화 두뇌에서 256 예산이 실제로 바닥난 적이 있다.
// 이 줄이 찍히면 그 호출의 예산을 올린다.
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// [body]는 디코드한 Chat Completions 응답. `finish_reason=length`일 때만 찍는다.
void logCompletionBudget(String tag, Object? body) {
  if (body is! Map) return;
  final choices = body['choices'];
  if (choices is! List || choices.isEmpty) return;
  final first = choices.first;
  if (first is! Map || first['finish_reason'] != 'length') return;
  final usage = body['usage'];
  final details = usage is Map ? usage['completion_tokens_details'] : null;
  debugPrint('📏 [COMPLETION-BUDGET] $tag finish_reason=length '
      'completion=${usage is Map ? usage['completion_tokens'] : '?'} '
      'reasoning=${details is Map ? details['reasoning_tokens'] : '?'}');
}

/// 원문 문자열 응답용. 디코드에 실패하면 아무것도 안 한다.
void logCompletionBudgetRaw(String tag, String raw) {
  try {
    logCompletionBudget(tag, jsonDecode(raw));
  } catch (_) {}
}
