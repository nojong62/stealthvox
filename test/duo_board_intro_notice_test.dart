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

  test('every language explains the guest promotion: 3 minutes and reporting',
      () {
    for (final code in languageCodes) {
      final copy = DuoBoardIntroNoticeCopy.forLanguageCode(code);
      expect(copy.promoTitle.trim(), isNotEmpty, reason: code);
      expect(copy.promoBody, contains('3'), reason: code);
      expect(copy.promoBody, contains('30'), reason: code);
      expect('•'.allMatches(copy.promoBody).length, 5, reason: code);
    }
  });

  test('unsupported system languages fall back to English', () {
    expect(
      DuoBoardIntroNoticeCopy.forLanguageCode('xx').body,
      DuoBoardIntroNoticeCopy.forLanguageCode('en').body,
    );
  });
}
