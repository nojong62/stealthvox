import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/korean_turn_validator.dart';

void main() {
  group('KoreanTurnValidator local gates', () {
    test('rejects an empty PCM transcription', () async {
      final result = await KoreanTurnValidator.validate(
        apiKey: '',
        transcribedText: '   ',
        mode: 'circle_talk',
        modeContext: 'test circle',
      );

      expect(result.accepted, isFalse);
      expect(result.reason, 'empty_transcript');
      expect(result.text, isEmpty);
    });

    test('fails open without a key and preserves the transcribed words',
        () async {
      final result = await KoreanTurnValidator.validate(
        apiKey: '',
        transcribedText: '  오늘   회의 어땠어요?  ',
        mode: 'circle_talk',
        modeContext: '회사 동료 대화',
      );

      expect(result.accepted, isTrue);
      expect(result.text, '오늘 회의 어땠어요?');
      expect(result.reason, 'validator_key_unavailable_fail_open');
    });

    test('uses the shared Korean retry line', () {
      expect(
        KoreanTurnValidator.retryLine,
        '제가 잘 못 들은 것 같아요. 다시 말씀해 주세요.',
      );
    });
  });
}
