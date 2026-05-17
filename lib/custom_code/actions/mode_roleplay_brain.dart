// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import '/custom_code/widgets/index.dart'; // Imports other custom widgets
import '/custom_code/actions/index.dart'; // Imports custom actions

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// ⭐️ 플러터플로우 에러 방지용 필수 함수 (이름을 반드시 Action Name과 맞춰야 함)
Future modeRoleplayBrain() async {
  // 이 함수 자체는 비워둡니다. 실제 기능은 아래 클래스에서 수행합니다.
}

// ============================================================================
// 🧠 [실제 두뇌 가동 클래스] - 앱 어디서든 불러다 쓸 수 있습니다.
// ============================================================================
class ModeRoleplayBrain {
  /// 유저의 STT 텍스트를 받아 Fast-Track과 Slow-Track을 병렬로 돌립니다.
  static Future<void> executeTurn({
    required String openAiKey,
    required String userText,
    required String contextStr,
    required String role,
    required String myTarget,
    required String myNative,
    required Function(String aiReplyEn, int elapsedMs) onFastTrack,
    required Function(String userEn, String userKo, String aiKo, int elapsedMs)
        onSlowTrack,
  }) async {
    Stopwatch totalTimer = Stopwatch()..start();

    // 🚀 [Track 1: Fast-Track] AI 영어 대답 최우선 생성
    String fastPrompt = '''
Roleplay as: $role
Target Language: $myTarget
Recent Context: $contextStr
User said: "$userText"
Rule: Reply naturally and concisely in EXACTLY 1 sentence. 
Output ONLY valid JSON: {"reply": "..."}
''';

    // 🐢 [Track 2: Slow-Track 1] 유저 발화 분석 및 교정
    String slowPrompt1 = '''
Original Language: $myNative
Target Language: $myTarget
User said: "$userText"
Rule: Translate or politely correct the user's sentence. 
Output ONLY valid JSON: {"user_target": "[Corrected English]", "user_native": "($myNative meaning)"}
''';

    // ⚡️ 병렬 실행 (두 API를 동시에 쏴버립니다)
    Future<String?> fastFuture =
        _callGPTForString(openAiKey, fastPrompt, "reply");
    Future<Map<String, String>?> slowFuture1 =
        _callGPTForMap(openAiKey, slowPrompt1);

    // 1. Fast-Track 결과가 나오면 즉시 콜백 발송!
    String aiReplyEn = (await fastFuture) ?? "I see.";

    // 🎯 엔진의 TTS가 켜지고 UI에 AI 대답이 뜹니다.
    onFastTrack(aiReplyEn, totalTimer.elapsedMilliseconds);

    // 🐢 [Track 2: Slow-Track 2] AI 영어 대답을 한국어로 번역 (AI가 말하고 있는 동안 돌아감)
    String slowPrompt2 = '''
Translate this English sentence to $myNative naturally: "$aiReplyEn"
Output ONLY valid JSON: {"translation": "..."}
''';

    Future<String?> slowFuture2 =
        _callGPTForString(openAiKey, slowPrompt2, "translation");

    // 2. 나머지 Slow-Track 작업들이 다 끝날 때까지 기다림
    Map<String, String>? slowResult1 = await slowFuture1;
    String aiReplyKo = (await slowFuture2) ?? "";

    totalTimer.stop();

    // 🎯 UI의 로딩이 사라지고 유저 교정본과 한국어 해석이 나타납니다.
    onSlowTrack(
        slowResult1?['user_target'] ?? userText,
        slowResult1?['user_native'] ?? "",
        aiReplyKo,
        totalTimer.elapsedMilliseconds);
  }

  // 내부 통신 유틸리티 함수들
  static Future<String?> _callGPTForString(
      String key, String prompt, String jsonKey) async {
    try {
      var res = await http.post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json; charset=utf-8'
          },
          body: jsonEncode({
            'model': 'gpt-4o-mini',
            'temperature': 0.2,
            'response_format': {'type': 'json_object'},
            'messages': [
              {'role': 'user', 'content': prompt}
            ]
          }));
      if (res.statusCode == 200) {
        var data = jsonDecode(utf8.decode(res.bodyBytes));
        String text = data['choices'][0]['message']['content'];
        String clean = _cleanJsonString(text);
        return jsonDecode(clean)[jsonKey]?.toString();
      }
    } catch (e) {
      print("GPT Fast Error: $e");
    }
    return null;
  }

  static Future<Map<String, String>?> _callGPTForMap(
      String key, String prompt) async {
    try {
      var res = await http.post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json; charset=utf-8'
          },
          body: jsonEncode({
            'model': 'gpt-4o-mini',
            'temperature': 0.2,
            'response_format': {'type': 'json_object'},
            'messages': [
              {'role': 'user', 'content': prompt}
            ]
          }));
      if (res.statusCode == 200) {
        var data = jsonDecode(utf8.decode(res.bodyBytes));
        String text = data['choices'][0]['message']['content'];
        String clean = _cleanJsonString(text);
        var parsed = jsonDecode(clean);
        return {
          'user_target': parsed['user_target']?.toString() ?? "",
          'user_native': parsed['user_native']?.toString() ?? "",
        };
      }
    } catch (e) {
      print("GPT Slow Error: $e");
    }
    return null;
  }

  static String _cleanJsonString(String text) {
    String clean = text.trim();
    if (clean.startsWith('```json'))
      clean = clean.substring(7);
    else if (clean.startsWith('```')) clean = clean.substring(3);
    if (clean.endsWith('```')) clean = clean.substring(0, clean.length - 3);
    return clean.trim();
  }
}
