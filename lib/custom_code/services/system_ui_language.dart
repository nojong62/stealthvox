import 'dart:ui' show Locale, PlatformDispatcher;

const Map<String, String> _kSystemUiLanguageNames = <String, String>{
  'en': 'English',
  'ko': 'Korean',
  'ja': 'Japanese',
  'zh': 'Chinese',
  'es': 'Spanish',
  'fr': 'French',
  'de': 'German',
  'hi': 'Hindi',
  'ru': 'Russian',
  'pt': 'Portuguese',
  'it': 'Italian',
  'nl': 'Dutch',
};

const List<Locale> kSupportedSystemUiLocales = <Locale>[
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
];

String systemUiLanguageNameForCode(String languageCode) =>
    _kSystemUiLanguageNames[languageCode.trim().toLowerCase()] ?? 'English';

String systemUiLanguageName() => systemUiLanguageNameForCode(
      PlatformDispatcher.instance.locale.languageCode,
    );
