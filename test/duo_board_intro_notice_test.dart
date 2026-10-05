import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_board_intro_notice.dart';

void main() {
  const languageCodes = <String>[
    'ko',
    'en',
    'ja',
    'zh',
    'es',
    'fr',
    'de',
    'hi',
    'ru',
    'pt',
    'it',
    'nl',
  ];

  test('every system-language notice includes the public-board conduct text',
      () {
    for (final code in languageCodes) {
      final copy = DuoBoardIntroNoticeCopy.forLanguageCode(code);
      final paragraphs = copy.body.split('\n\n');
      expect(paragraphs.length, 4, reason: code);
      expect(paragraphs.last.trim(), isNotEmpty, reason: code);
    }
  });

  test('unsupported system languages fall back to English', () {
    expect(
      DuoBoardIntroNoticeCopy.forLanguageCode('xx').body,
      DuoBoardIntroNoticeCopy.forLanguageCode('en').body,
    );
  });
}
