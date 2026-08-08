// 🎧 Anyone 첫 유저 턴 전사 서비스.
//   마이크 원본 PCM(16kHz mono) 버퍼를 WAV로 포장해 multipart로 올린다.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'openai_connection_pool.dart';
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
    // 무음을 잘라낸 뒤 발화 앞에 남기는 여유. 감지 지점은 소리가 커진 곳이지
    // 말이 시작된 곳이 아니라서, 약한 첫 자음(ㅂ·ㅍ·ㅅ)이 이 여유 안에
    // 들어와야 한다. 잘리면 모델이 앞을 통째로 지어낸다("밥 먹지"→"밟").
    // 이미 녹음된 소리를 더 떼어 보내는 것이라 지연 대가는 없다.
    int leadingPaddingMs = 300,
    void Function(String tag, String msg)? onLog,
  }) async {
    if (apiKey.isEmpty || pcm.isEmpty) return null;
    final sw = Stopwatch()..start();
    try {
      final preparedPcm = trimLeadingSilencePcm16(
        pcm,
        sampleRate: sampleRate,
        paddingMs: leadingPaddingMs,
      );
      final originalAudioMs =
          pcm16DurationMs(pcm.length, sampleRate: sampleRate);
      final preparedAudioMs =
          pcm16DurationMs(preparedPcm.length, sampleRate: sampleRate);
      if (preparedPcm.length < pcm.length) {
        onLog?.call(
          '✂️ [RETRANSCRIBE-TRIM]',
          'leadingSilenceMs=${originalAudioMs - preparedAudioMs} '
              'audioMs=$originalAudioMs->$preparedAudioMs '
              'paddingMs=$leadingPaddingMs',
        );
      }
      final wav = pcm16ToWav(preparedPcm, sampleRate: sampleRate);
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

      // 방 입장 단계에서 예열한 app-lifetime Client를 재사용한다.
      // MultipartRequest.send()는 요청마다 새 Client를 만들어 DNS/TLS 비용이
      // 첫 유저 음성의 지연에 다시 붙을 수 있다.
      final streamed = await OpenAiConnectionPool.instance.client
          .send(request)
          .timeout(timeout);
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
            'audioMs=$preparedAudioMs '
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
