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

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart'; // 파일 저장용
import 'package:audioplayers/audioplayers.dart'; // 소리 재생용

Future speakText(
  String? textToSpeak,
  String? apiKey,
) async {
  // 1. 안전장치: 텍스트나 키가 없으면 조용히 종료
  if (textToSpeak == null ||
      textToSpeak.isEmpty ||
      apiKey == null ||
      apiKey.isEmpty) {
    return;
  }

  try {
    // 2. OpenAI TTS API 호출 (고성능 tts-1 모델)
    var url = Uri.parse('https://api.openai.com/v1/audio/speech');
    var response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'tts-1', // 고성능 모델
        'input': textToSpeak,
        'voice':
            'alloy', // 남녀 중성적인 깔끔한 톤 (alloy, echo, fable, onyx, nova, shimmer 중 선택 가능)
      }),
    );

    if (response.statusCode == 200) {
      // 3. 오디오 파일 생성 (mp3)
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/speech_output.mp3';
      final file = File(filePath);

      // 기존 파일이 있으면 삭제 (충돌 방지)
      if (await file.exists()) {
        await file.delete();
      }

      // 파일 쓰기
      await file.writeAsBytes(response.bodyBytes);

      // 4. 즉시 재생 (AudioPlayer)
      final player = AudioPlayer();
      // 모바일/웹 경로 호환 처리
      await player.play(DeviceFileSource(filePath));
    } else {
      print('TTS Error: ${response.statusCode} - ${response.body}');
    }
  } catch (e) {
    print('TTS Exception: $e');
  }
}
