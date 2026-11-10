import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stealth_vox/app_state.dart';
import 'package:stealth_vox/custom_code/services/other_chat_language.dart';
import 'package:stealth_vox/custom_code/services/tts_model_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await FFAppState().initializePersistedState();
  });

  test('a listed chat language is returned as is', () {
    FFAppState().chatLang = 'Korean';
    expect(isOtherChatLanguageSelected, isFalse);
    expect(FFAppState().chatLang, 'Korean');
    expect(FFAppState().chatLangRaw, 'Korean');
    expect(ttsLanguageFor('Korean'), 'Korean');
  });

  test('"Other" returns the detected language and sends its ISO code to TTS',
      () {
    FFAppState().chatLang = kOtherChatLanguage;
    rememberOtherChatLanguage((name: 'Thai', code: 'th'));
    expect(isOtherChatLanguageSelected, isTrue);
    expect(FFAppState().chatLangRaw, kOtherChatLanguage);
    expect(FFAppState().chatLang, 'Thai');
    expect(ttsLanguageFor('Thai'), 'th');
    // 배울 언어 쪽 음성은 그대로 이름으로 간다.
    expect(ttsLanguageFor('Japanese'), 'Japanese');
  });

  test('"Other" before any detection falls back to a real name', () {
    FFAppState().chatLang = kOtherChatLanguage;
    expect(FFAppState().chatLang, isNot(kOtherChatLanguage));
    expect(FFAppState().chatLang, isNotEmpty);
    expect(FFAppState().otherChatLangCode, matches(RegExp(r'^[a-z]{2,3}$')));
  });
}
