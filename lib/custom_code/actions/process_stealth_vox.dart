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

import '/custom_code/actions/index.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

Future<dynamic> processStealthVox(
  String? audioFile,
  String? targetLang,
  String? tone,
  String? apiKey,
) async {
  // 1. 안전장치: API 키 확인
  if (apiKey == null || apiKey.isEmpty) {
    return {
      "translatedText": "Error",
      "originalText": "API Key Missing",
      "duration": 0.0
    };
  }

  // 기본값 설정
  String finalLang =
      (targetLang == null || targetLang.isEmpty) ? "English" : targetLang;
  String finalTone = (tone == null || tone.isEmpty) ? "Tactical" : tone;

  try {
    // -------------------------------------------------------
    // [Step 1] Whisper API (음성 -> 텍스트 변환 + 시간 측정)
    // -------------------------------------------------------
    var uri = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
    var request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields['model'] = 'whisper-1';
    // language 파라미터를 제거하여 Whisper가 언어를 자동 감지하도록 함
    request.fields['response_format'] = 'verbose_json'; // 시간 측정을 위해 필수

    // 파일 첨부 로직
    if (kIsWeb) {
      if (audioFile == null || audioFile.isEmpty)
        return {
          "translatedText": "Error",
          "originalText": "No Audio",
          "duration": 0.0
        };

      var audioResponse = await http.get(Uri.parse(audioFile));
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        audioResponse.bodyBytes,
        filename: 'recording.mp3',
        contentType: MediaType('audio', 'mpeg'),
      ));
    } else {
      if (audioFile == null || audioFile.isEmpty)
        return {
          "translatedText": "Error",
          "originalText": "No Audio",
          "duration": 0.0
        };
      request.files.add(await http.MultipartFile.fromPath('file', audioFile));
    }

    var response = await request.send();

    if (response.statusCode != 200) {
      var errorBody = await response.stream.bytesToString();
      return {
        "translatedText": "STT Error",
        "originalText": errorBody,
        "duration": 0.0
      };
    }

    // 결과 파싱
    var responseBody = await response.stream.bytesToString();
    var jsonResponse = jsonDecode(responseBody);
    String originalTextFromWhisper = jsonResponse['text'];
    double duration = jsonResponse['duration']?.toDouble() ?? 0.0;

    // -------------------------------------------------------
    // [Step 2] GPT-4o-mini (인식된 언어 -> 목표 언어 번역)
    // -------------------------------------------------------
    var chatUrl = Uri.parse('https://api.openai.com/v1/chat/completions');
    var chatResponse = await http.post(
      chatUrl,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey'
      },
      body: jsonEncode({
        'model': 'gpt-4o-mini',
        'temperature': 0.2, // 냉철한 번역
        'messages': [
          {
            'role': 'system',
            'content':
                'Translate to $finalLang ($finalTone tone). Return ONLY JSON format: {"translatedText": "translated result...", "originalText": "$originalTextFromWhisper"}. Do NOT add any explanations.'
          },
          {'role': 'user', 'content': originalTextFromWhisper}
        ],
      }),
    );

    if (chatResponse.statusCode != 200) {
      return {
        "translatedText": "GPT Error",
        "originalText": "Translation Failed",
        "duration": duration
      };
    }

    var chatBody = utf8.decode(chatResponse.bodyBytes);
    var chatJson = jsonDecode(chatBody);
    String content = chatJson['choices'][0]['message']['content'];

    content = content.replaceAll('```json', '').replaceAll('```', '').trim();

    Map<String, dynamic> result = jsonDecode(content);
    result['duration'] = duration; // 시간 정보 포함

    return result;
  } catch (e) {
    return {
      "translatedText": "System Error",
      "originalText": "Exception: $e",
      "duration": 0.0
    };
  }
}
