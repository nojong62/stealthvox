import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/origin_surface_localization.dart';
import 'package:stealth_vox/custom_code/services/system_ui_language.dart';
import 'package:stealth_vox/custom_code/services/talk_ui_localization.dart';

void main() {
  test('supported device language codes map to UI language names', () {
    expect(systemUiLanguageNameForCode('en'), 'English');
    expect(systemUiLanguageNameForCode('ko'), 'Korean');
    expect(systemUiLanguageNameForCode('ja'), 'Japanese');
    expect(systemUiLanguageNameForCode('zh'), 'Chinese');
    expect(systemUiLanguageNameForCode('pt'), 'Portuguese');
    expect(systemUiLanguageNameForCode('NL'), 'Dutch');
  });

  test('unsupported device language falls back to English', () {
    expect(systemUiLanguageNameForCode(''), 'English');
    expect(systemUiLanguageNameForCode('xx'), 'English');
  });

  test('Flutter exposes every translated UI locale', () {
    expect(
      kSupportedSystemUiLocales,
      const <Locale>[
        Locale('en'),
        Locale('ko'),
        Locale('ja'),
        Locale('zh'),
        Locale('es'),
        Locale('fr'),
        Locale('de'),
        Locale('hi'),
        Locale('ru'),
        Locale('pt'),
        Locale('it'),
        Locale('nl'),
      ],
    );
  });

  test('new common screen messages exist in every supported language', () {
    const languages = <String>[
      'English',
      'Korean',
      'Japanese',
      'Chinese',
      'Spanish',
      'French',
      'German',
      'Hindi',
      'Russian',
      'Portuguese',
      'Italian',
      'Dutch',
    ];
    for (final language in languages) {
      final copy = OriginSurfaceCopy.forLanguage(language);
      expect(copy['duoRoomReopenFailed'], isNotEmpty, reason: language);
      expect(copy['guestWaiting'], isNotEmpty, reason: language);
      expect(copy['noConversationContent'], isNotEmpty, reason: language);
      expect(
          TalkUiCopy.forLanguage(language)['finishFinalEditsFirst'], isNotEmpty,
          reason: language);
    }
  });
}
