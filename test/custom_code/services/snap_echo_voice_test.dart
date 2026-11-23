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

    test('Korean is recognised so it can stay on Chirp', () {
      expect(snapIsKorean('Korean'), isTrue);
      expect(snapIsKorean(' korean '), isTrue);
      expect(snapIsKorean('ko-KR'), isTrue);
      expect(snapIsKorean('한국어'), isTrue);
      expect(snapIsKorean('English'), isFalse);
      expect(snapIsKorean('Japanese'), isFalse);
    });

    test('other languages get a native-rhythm prompt at 95%', () {
      final prompt =
          snapGeminiStylePrompt(SnapUnitSize.quick, languageName: 'Japanese');
      expect(prompt, contains('native Japanese speaker'));
      expect(prompt, contains('95 percent'));
      expect(prompt, isNot(contains('stressed syllable')));
      expect(prompt.length, lessThanOrEqualTo(800));
    });

    test('English prompt asks for 100% pace and short one-breath phrases', () {
      for (final size in SnapUnitSize.values) {
        final prompt = snapGeminiStylePrompt(size);
        expect(prompt, contains('100 percent'));
        expect(prompt, contains('three to six words'));
        expect(prompt, contains('do not add or repeat'));
        expect(prompt, contains('native English speaker'));
        // Gateway cuts the prompt at 800 characters.
        expect(prompt.length, lessThanOrEqualTo(800));
      }
    });

    test('quick stresses one word per phrase, full stresses two', () {
      expect(snapGeminiStylePrompt(SnapUnitSize.quick),
          contains('exactly one important word'));
      expect(snapGeminiStylePrompt(SnapUnitSize.full),
          contains('exactly two important words'));
    });

    test('role-play prompt keeps normal speed and rhythm', () {
      final prompt = rolePlayGeminiStylePrompt(languageName: 'English');
      expect(prompt, contains('100 percent'));
      expect(prompt, contains('rhythm'));
      expect(prompt.length, lessThanOrEqualTo(800));
    });

    test('Snap Echoing leaves out Vietnamese only', () {
      for (final name in <String>[
        'Vietnamese',
        ' vietnamese ',
        'vi',
        'vi-VN',
      ]) {
        expect(snapEchoingSupported(name), isFalse, reason: name);
      }
      for (final name in <String>[
        'Indonesian',
        'id',
        'Bahasa Indonesia',
        'English',
        'Korean',
        'Japanese',
        'Chinese',
        'Spanish',
        'Hindi',
        'Dutch',
        '',
      ]) {
        expect(snapEchoingSupported(name), isTrue, reason: name);
      }
    });

    test('Gemini cache tag is set', () {
      expect(kSnapGeminiCacheTag, isNotEmpty);
    });
  });
}
