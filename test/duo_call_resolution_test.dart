import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_call_resolution.dart';

void main() {
  group('Duo same-origin call resolution', () {
    test('board Origin language uses two-letter English abbreviations', () {
      expect(duoOriginLanguageAbbreviation('Korean'), 'Ko');
      expect(duoOriginLanguageAbbreviation('English'), 'En');
      expect(duoOriginLanguageAbbreviation('Chinese'), 'Zh');
      expect(duoOriginLanguageAbbreviation('Esperanto'), '--');
    });

    test('two capable peers with the same canonical Chat Lang use Direct', () {
      final result = chooseDuoCallResolution(
        hostLanguage: 'Korean',
        partnerLanguage: 'Korean',
        hostSameOriginDirectV1: true,
        partnerSameOriginDirectV1: true,
      );
      expect(result.mode, 'direct');
      expect(result.reason, kDuoResolutionSameOrigin);
    });

    test('different Chat Lang values keep Interpreter', () {
      final result = chooseDuoCallResolution(
        hostLanguage: 'Korean',
        partnerLanguage: 'English',
        hostSameOriginDirectV1: true,
        partnerSameOriginDirectV1: true,
      );
      expect(result.mode, 'interpreter');
      expect(result.reason, kDuoResolutionTranslationRequired);
    });

    for (final capabilities in <(bool, bool)>[
      (false, false),
      (false, true),
      (true, false),
    ]) {
      test('mixed-version peers $capabilities fail closed to Interpreter', () {
        final result = chooseDuoCallResolution(
          hostLanguage: 'Korean',
          partnerLanguage: 'Korean',
          hostSameOriginDirectV1: capabilities.$1,
          partnerSameOriginDirectV1: capabilities.$2,
        );
        expect(result.mode, 'interpreter');
        expect(result.reason, kDuoResolutionCompatibilityFallback);
      });
    }

    for (final languages in <(Object?, Object?)>[
      (null, 'Korean'),
      ('Korean', null),
      ('korean', 'korean'),
      ('Korean ', 'Korean '),
      ('Esperanto', 'Esperanto'),
    ]) {
      test('missing or non-canonical Chat Lang $languages stays Interpreter',
          () {
        final result = chooseDuoCallResolution(
          hostLanguage: languages.$1,
          partnerLanguage: languages.$2,
          hostSameOriginDirectV1: true,
          partnerSameOriginDirectV1: true,
        );
        expect(result.mode, 'interpreter');
        expect(result.reason, kDuoResolutionLanguageUnavailable);
      });
    }

    test('test build advertises the negotiation capability explicitly', () {
      expect(kDuoSameOriginDirectV1Enabled, isTrue);
      expect(duoSameOriginDirectCapability(), isTrue);
    });
  });
}
