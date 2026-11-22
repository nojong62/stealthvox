import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/snap_echo_voice.dart';

void main() {
  group('Snap Echoing voice', () {
    test('only English counts as English', () {
      expect(snapIsEnglish('English'), isTrue);
      expect(snapIsEnglish(' english '), isTrue);
      expect(snapIsEnglish('en-GB'), isTrue);
      expect(snapIsEnglish('Korean'), isFalse);
      expect(snapIsEnglish('Japanese'), isFalse);
    });

    test('Gemini prompt asks for 95% pace and stress-centered rhythm', () {
      for (final size in SnapUnitSize.values) {
        final prompt = snapGeminiStylePrompt(size);
        expect(prompt, contains('95 percent'));
        expect(prompt, contains('stressed syllable'));
        expect(prompt, contains('native English speaker'));
        // Gateway cuts the prompt at 800 characters.
        expect(prompt.length, lessThanOrEqualTo(800));
      }
    });

    test('quick asks for one stressed beat, full for two', () {
      expect(snapGeminiStylePrompt(SnapUnitSize.quick),
          contains('exactly one stressed beat'));
      expect(snapGeminiStylePrompt(SnapUnitSize.full),
          contains('exactly two stressed beats'));
    });

    test('Gemini cache tag is set', () {
      expect(kSnapGeminiCacheTag, isNotEmpty);
    });
  });
}
