import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/tts_model_policy.dart';

void main() {
  group('ttsLanguageFor', () {
    test('British 스타일이면 영어 소리는 en-GB다', () {
      expect(ttsLanguageFor('English', style: 'British'), 'en-GB');
      expect(ttsLanguageFor('english', style: 'british'), 'en-GB');
    });

    test('다른 스타일의 영어는 그대로 둔다', () {
      for (final style in ['Standard', 'American', 'Native']) {
        expect(ttsLanguageFor('English', style: style), 'English', reason: style);
      }
    });

    test('영어가 아닌 언어는 British여도 그대로다', () {
      expect(ttsLanguageFor('Korean', style: 'British'), 'Korean');
      expect(ttsLanguageFor('', style: 'British'), '');
    });
  });
}
