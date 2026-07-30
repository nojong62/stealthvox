// 🎧 Anyone 첫 유저 턴 전사 서비스.
//   마이크 원본 PCM(16kHz mono) 버퍼를 WAV로 포장해 multipart로 올린다.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'pcm_audio_utils.dart';

class OpenAiTranscribeService {
  OpenAiTranscribeService._();

  static const String firstTurnModel = 'gpt-4o-transcribe';

  /// PCM16 버퍼를 전사한다. 실패/타임아웃이면 null.
  static Future<String?> transcribePcm16({
    required String apiKey,
    required Uint8List pcm,
    int sampleRate = 16000,
    String? language,
    String model = firstTurnModel,
    Duration timeout = const Duration(seconds: 3),
    void Function(String tag, String msg)? onLog,
  }) async {
    if (apiKey.isEmpty || pcm.isEmpty) return null;
    final sw = Stopwatch()..start();
    try {
      final wav = pcm16ToWav(pcm, sampleRate: sampleRate);
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.openai.com/v1/audio/transcriptions'),
      );
      request.headers['Authorization'] = 'Bearer $apiKey';
      request.fields['model'] = model;
      request.fields['response_format'] = 'json';
      if (language != null && language.isNotEmpty) {
        request.fields['language'] = language;
      }
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        wav,
        filename: 'utterance.wav',
      ));

      final streamed = await request.send().timeout(timeout);
      final body = await streamed.stream.bytesToString().timeout(timeout);
      sw.stop();
      if (streamed.statusCode != 200) {
        onLog?.call('❌ [RETRANSCRIBE]',
            'status=${streamed.statusCode} elapsedMs=${sw.elapsedMilliseconds}');
        return null;
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final text = (decoded['text'] as String?)?.trim() ?? '';
      onLog?.call(
        '🎧 [RETRANSCRIBE]',
        'ok model=$model len=${text.length} '
            'audioMs=${pcm16DurationMs(pcm.length, sampleRate: sampleRate)} '
            'elapsedMs=${sw.elapsedMilliseconds}',
      );
      return text;
    } on TimeoutException {
      onLog?.call(
          '⚠️ [RETRANSCRIBE]', 'timeout elapsedMs=${sw.elapsedMilliseconds}');
      return null;
    } catch (e) {
      onLog?.call('❌ [RETRANSCRIBE]', 'failed reason=${e.runtimeType}');
      return null;
    }
  }
}
