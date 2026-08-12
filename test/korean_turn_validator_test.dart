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
      // 빈 전사는 장애가 아니라 확정된 로컬 판정이다.
      expect(result.failure, KoreanTurnValidatorFailure.none);
      expect(result.failedOpen, isFalse);
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
      // 장애로 통과시킨 턴은 모델이 승인한 턴과 값으로 구분돼야 한다.
      expect(result.failure, KoreanTurnValidatorFailure.apiKeyMissing);
      expect(result.failedOpen, isTrue);
    });

    test('marks a model verdict as not failed open', () {
      const verdict = KoreanTurnValidationResult(
        accepted: true,
        text: '오늘 회의 어땠어요?',
        reason: 'accepted',
      );

      expect(verdict.failure, KoreanTurnValidatorFailure.none);
      expect(verdict.failedOpen, isFalse);
    });

    // 문구는 badd82a6에서 의도적으로 바꿨다 — 발화 전체가 아니라 일부만 못
    // 알아들었다는 쪽이 실제 반려 상황에 가깝다. 3모드가 이 상수 하나를 쓴다.
    test('uses the shared Korean retry line', () {
      expect(
        KoreanTurnValidator.retryLine,
        '제가 잘못들은 부분이 있는 것 같아요. 다시 말씀해 주세요.',
      );
    });
  });
}
