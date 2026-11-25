import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/tts_adapter.dart';
import 'package:stealth_vox/custom_code/services/voice_ids.dart';

void main() {
  group('neutral voice ids', () {
    test('the two ids carry gender only', () {
      expect(kVoiceFemale, 'female');
      expect(kVoiceMale, 'male');
    });

    test('adapter defaults use the neutral ids', () {
      expect(TtsAdapterConfig.aiVoice, kVoiceFemale);
      expect(TtsAdapterConfig.userVoice, kVoiceMale);
      expect(TtsAdapterConfig.fallbackVoice, kVoiceFemale);
    });

    test('adapter passes neutral ids through and still accepts old names', () {
      expect(TtsAdapterConfig.mapVoice('female'), 'female');
      expect(TtsAdapterConfig.mapVoice(' MALE '), 'male');
      expect(TtsAdapterConfig.mapVoice('nova'), 'nova');
      expect(TtsAdapterConfig.mapVoice('verse'), 'verse');
      expect(TtsAdapterConfig.mapVoice('not-a-voice'), kVoiceFemale);
    });
  });

  group('wireVoiceFor', () {
    test('old male names become male (same list the gateway reads as male)', () {
      for (final v in ['ash', 'ballad', 'cedar', 'echo', 'fable', 'onyx', 'verse']) {
        expect(wireVoiceFor(v), kVoiceMale, reason: v);
      }
    });

    test('old female names become female', () {
      for (final v in ['alloy', 'coral', 'marin', 'nova', 'sage', 'shimmer']) {
        expect(wireVoiceFor(v), kVoiceFemale, reason: v);
      }
    });

    test('neutral and google ids pass through untouched', () {
      expect(wireVoiceFor('female'), 'female');
      expect(wireVoiceFor('male'), 'male');
      expect(wireVoiceFor('google-female'), 'google-female');
      expect(wireVoiceFor('google-male'), 'google-male');
    });
  });

  group('legacyCacheVoiceFor keeps saved audio reachable', () {
    test('neutral ids map back to the keys the caches were written with', () {
      expect(legacyCacheVoiceFor('female'), 'nova');
      expect(legacyCacheVoiceFor('male'), 'verse');
    });

    test('old names and google ids are already the key', () {
      expect(legacyCacheVoiceFor('verse'), 'verse');
      expect(legacyCacheVoiceFor('echo'), 'echo');
      expect(legacyCacheVoiceFor('google-female'), 'google-female');
    });

    test('per-mode constants match the keys written before the rename', () {
      expect(LegacyVoiceCacheKey.historyFemale, 'nova');
      expect(LegacyVoiceCacheKey.historyMale, 'verse');
      expect(LegacyVoiceCacheKey.circleFemale, 'shimmer');
      expect(LegacyVoiceCacheKey.scenarioMale, 'echo');
    });
  });
}
