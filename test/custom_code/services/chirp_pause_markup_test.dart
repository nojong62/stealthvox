import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/chirp_pause_markup.dart';

void main() {
  group('chirpPauseMarkup', () {
    test('puts the chosen tag after each clause break, never at the end', () {
      expect(
        chirpPauseMarkup('Well, I think so. Do you?', ChirpPause.medium),
        'Well, [pause] I think so. [pause] Do you?',
      );
      expect(
        chirpPauseMarkup('Yes, sure.', ChirpPause.short),
        'Yes, [pause short] sure.',
      );
      expect(
        chirpPauseMarkup('Yes, sure.', ChirpPause.long),
        'Yes, [pause long] sure.',
      );
    });

    test('decimals and text without breaks are left alone', () {
      expect(chirpPauseMarkup('It costs 3.5 dollars', ChirpPause.medium),
          'It costs 3.5 dollars');
    });

    test('full-width punctuation does not need a space', () {
      expect(chirpPauseMarkup('はい、そうです。行きましょう', ChirpPause.short),
          'はい、 [pause short] そうです。 [pause short] 行きましょう');
    });

    test('MY STORY: every line end pauses once, with or without punctuation', () {
      expect(
          chirpPauseMarkup(
              'So I was talking\nabout my job, \nand it went well.',
              ChirpPause.long),
          'So I was talking [pause long] about my job, [pause long] and it went well.');
      expect(chirpPauseMarkup('今日は\n話しました。\nよかったです', ChirpPause.short),
          '今日は [pause short] 話しました。 [pause short] よかったです');
    });

    test('text that already has brackets is not touched', () {
      expect(chirpPauseMarkup('Say [this], then go.', ChirpPause.medium),
          'Say [this], then go.');
    });
  });
}
