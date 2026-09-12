import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/circle_correction_intent.dart';

void main() {
  group('Circle Talk strong correction intent', () {
    test('retries when user rejects the words just recorded', () {
      for (final text in <String>[
        '아니야, 그 말이 아니야.',
        '내가 그런 말을 한 게 아니야.',
        '방금 내가 말한 게 잘못됐어.',
        '내 말을 잘못 들었어.',
        '잘못 알아들었어요.',
      ]) {
        expect(
          detectCircleCorrectionIntent(
            text,
            hasPreviousExchange: true,
          ).action,
          CircleCorrectionAction.retry,
          reason: text,
        );
      }
    });

    test('replaces previous exchange when corrected wording is included', () {
      final decision = detectCircleCorrectionIntent(
        '아니, 철물점에서 가장 많이 팔리는 물건이 뭐냐고요.',
        hasPreviousExchange: true,
      );
      expect(decision.action, CircleCorrectionAction.replace);
      expect(decision.replacement, '철물점에서 가장 많이 팔리는 물건이 뭐냐고요.');

      final directRestatement = detectCircleCorrectionIntent(
        '그 말이 아니라 형광등을 말한 거야.',
        hasPreviousExchange: true,
      );
      expect(directRestatement.action, CircleCorrectionAction.replace);
      expect(directRestatement.replacement, '형광등을 말한 거야.');
    });

    test('keeps an ordinary negative answer as a normal turn', () {
      for (final text in <String>[
        '아니, 안 갔어.',
        '아니요, 그건 안 팔아요.',
        '그런 뜻은 없어요.',
      ]) {
        expect(
          detectCircleCorrectionIntent(
            text,
            hasPreviousExchange: true,
          ).action,
          CircleCorrectionAction.none,
          reason: text,
        );
      }
    });

    test('never rewinds when no previous exchange exists', () {
      expect(
        detectCircleCorrectionIntent(
          '아니야, 그 말이 아니야.',
          hasPreviousExchange: false,
        ).action,
        CircleCorrectionAction.none,
      );
    });
  });
}
