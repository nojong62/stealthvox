import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_invite_localization.dart';

const _languages = <String>[
  'Korean', 'Japanese', 'Chinese', 'Spanish', 'French', 'German',
  'Hindi', 'Russian', 'Portuguese', 'Italian', 'Dutch',
];

void main() {
  group('Duo invite WhatsApp option', () {
    test('every UI language has its own WhatsApp label', () {
      final english = DuoInviteCopy.forLanguage('English')['whatsapp'];
      expect(english, 'Send via WhatsApp');
      for (final language in _languages) {
        final label = DuoInviteCopy.forLanguage(language)['whatsapp'];
        expect(label, contains('WhatsApp').or(contains('왓츠앱')),
            reason: language);
        expect(label, isNot(english), reason: language);
      }
    });

    test('WhatsApp falls back to the system share sheet', () {
      final duo = File('lib/custom_code/widgets/routine_mode_duo.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      expect(duo, contains("Navigator.pop(sheetContext, 'whatsapp')"));
      expect(duo, contains("Uri.parse('https://wa.me/')"));
      expect(duo, contains('if (!sentByWhatsApp)'));
    });
  });
}

extension on Matcher {
  Matcher or(Matcher other) => anyOf(this, other);
}
