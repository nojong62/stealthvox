import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/tts_model_policy.dart';

void main() {
  group('TtsModelProfile speech payload', () {
    test('speed profile sends speed and omits instructions', () {
      const profile = TtsModelProfile(
        model: 'tts-1',
        optionMode: TtsOptionMode.speed,
        cacheVersion: 'v1',
      );

      final payload = profile.speechPayload(
        input: 'hello',
        voice: 'nova',
        speed: 0.9,
        instructions: 'ignored for this contract',
        responseFormat: 'pcm',
      );

      expect(payload['model'], 'tts-1');
      expect(payload['speed'], 0.9);
      expect(payload['response_format'], 'pcm');
      expect(payload.containsKey('instructions'), isFalse);
    });

    test('instructions profile sends instructions and omits speed', () {
      const profile = TtsModelProfile(
        model: 'future-tts',
        optionMode: TtsOptionMode.instructions,
        cacheVersion: 'v2',
      );

      final payload = profile.speechPayload(
        input: 'hello',
        voice: 'coral',
        speed: 0.8,
        instructions: ' Speak warmly. ',
      );

      expect(payload['instructions'], 'Speak warmly.');
      expect(payload.containsKey('speed'), isFalse);
    });

    test('language rides along for the gateway and is omitted when blank', () {
      const profile = TtsModelProfile(
        model: 'tts-1',
        optionMode: TtsOptionMode.speed,
        cacheVersion: 'v1',
      );

      expect(
        profile.speechPayload(
            input: 'hola', voice: 'echo', language: ' Spanish ')['language'],
        'Spanish',
      );
      expect(
        profile
            .speechPayload(input: 'hola', voice: 'echo', language: '  ')
            .containsKey('language'),
        isFalse,
      );
      expect(
        profile
            .speechPayload(input: 'hola', voice: 'echo')
            .containsKey('language'),
        isFalse,
      );
    });

    test('none profile sends no model-specific option', () {
      const profile = TtsModelProfile(
        model: 'future-tts',
        optionMode: TtsOptionMode.none,
        cacheVersion: 'v3',
      );

      final payload = profile.speechPayload(
        input: 'hello',
        voice: 'alloy',
        speed: 0.7,
        instructions: 'unused',
      );

      expect(payload.containsKey('speed'), isFalse);
      expect(payload.containsKey('instructions'), isFalse);
    });
  });
}
