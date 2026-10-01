import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '/app_state.dart';

const Map<String, String> _languageCodeToName = {
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

const Map<String, TranslateLanguage> _translateLanguages = {
  'English': TranslateLanguage.english,
  'Korean': TranslateLanguage.korean,
  'Japanese': TranslateLanguage.japanese,
  'Chinese': TranslateLanguage.chinese,
  'Spanish': TranslateLanguage.spanish,
  'French': TranslateLanguage.french,
  'German': TranslateLanguage.german,
  'Hindi': TranslateLanguage.hindi,
  'Russian': TranslateLanguage.russian,
  'Portuguese': TranslateLanguage.portuguese,
  'Italian': TranslateLanguage.italian,
  'Dutch': TranslateLanguage.dutch,
};

/// Uses the explicit Chat Language when one was chosen. Before that, including
/// anonymous first entry, it follows the phone's system language.
String duoBoardViewerLanguage() {
  final app = FFAppState();
  if (app.prefs.containsKey('ff_chatLang') &&
      _translateLanguages.containsKey(app.chatLang)) {
    return app.chatLang;
  }
  final code = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
  return _languageCodeToName[code] ?? 'English';
}

/// Only show translation attribution when this card can genuinely be translated.
/// Older board posts did not persist their source language and remain original.
bool duoBoardNeedsTranslation({
  required String sourceLanguage,
  required String targetLanguage,
}) =>
    sourceLanguage != targetLanguage &&
    _translateLanguages.containsKey(sourceLanguage) &&
    _translateLanguages.containsKey(targetLanguage);

class DuoBoardTopicTranslation {
  DuoBoardTopicTranslation._();

  static final _manager = OnDeviceTranslatorModelManager();
  static final Map<String, Future<String>> _cache = {};
  static final Map<String, Future<bool>> _modelDownloads = {};

  static Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    final clean = text.trim();
    if (clean.isEmpty || sourceLanguage == targetLanguage || kIsWeb) {
      return Future.value(clean);
    }
    final source = _translateLanguages[sourceLanguage];
    final target = _translateLanguages[targetLanguage];
    if (source == null || target == null) return Future.value(clean);
    final key = '$sourceLanguage|$targetLanguage|$clean';
    return _cache.putIfAbsent(
      key,
      () => _translate(clean, source, target).catchError((_) => clean),
    );
  }

  static Future<bool> _ensureModel(TranslateLanguage language) {
    return _modelDownloads.putIfAbsent(language.bcpCode, () async {
      if (await _manager.isModelDownloaded(language.bcpCode)) return true;
      // Models are roughly 30 MB, so never consume mobile data silently.
      return _manager.downloadModel(language.bcpCode, isWifiRequired: true);
    });
  }

  static Future<String> _translate(
      String text, TranslateLanguage source, TranslateLanguage target) async {
    final ready = await Future.wait([
      _ensureModel(source),
      _ensureModel(target),
    ]);
    if (ready.any((value) => !value)) return text;
    final translator = OnDeviceTranslator(
      sourceLanguage: source,
      targetLanguage: target,
    );
    try {
      final translated = (await translator.translateText(text)).trim();
      return translated.isEmpty ? text : translated;
    } finally {
      await translator.close();
    }
  }
}
