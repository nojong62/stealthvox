import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/widgets/first_utterance_context_judge.dart';

void main() {
  group('FirstUtteranceContext', () {
    test('accepts a complete valid judgment', () {
      final result = FirstUtteranceContext.fromJson({
        'actor': 'user',
        'target': 'third_person',
        'omitted_subject': '나',
        'tense': 'past',
        'relationship': 'friend',
        'confidence': 0.9,
        'ambiguity_reason': '',
      });

      expect(result, isNotNull);
      expect(result!.confidenceBand, 'high');
      expect(result.toInternalPromptContext(), contains('NEVER EXPOSE'));
    });

    test('rejects missing fields and invalid confidence', () {
      expect(
        FirstUtteranceContext.fromJson({
          'actor': 'user',
          'target': 'none',
          'omitted_subject': '나',
          'tense': 'past',
          'relationship': 'unknown',
          'confidence': 1.2,
        }),
        isNull,
      );
    });
  });

  group('FirstUtteranceContextJudgeSession eligibility', () {
    test('routes excluded, judged, and bypass utterances before speculation',
        () async {
      final session = FirstUtteranceContextJudgeSession();

      expect(session.previewRoute('안녕하세요'), FirstUtteranceRoute.excluded);
      expect(
        session.previewRoute('어제 친구를 만났어'),
        FirstUtteranceRoute.judge,
      );
      expect(session.previewRoute('I went home'), FirstUtteranceRoute.bypass);

      await session.judgeIfNeeded(
        apiKey: 'unused',
        transcript: 'I went home',
        mode: 'ANYONE',
      );
      expect(session.previewRoute('안녕하세요'), FirstUtteranceRoute.bypass);
    });

    test('routes every meaningful Korean first utterance to the judge', () {
      final session = FirstUtteranceContextJudgeSession();

      expect(
        session.shouldDeferSpeculativeTranslation('어제 친구를 만났어'),
        isTrue,
      );
      expect(
        session.shouldDeferSpeculativeTranslation('민수가 병원에 갔어요'),
        isTrue,
      );
      expect(
        session.shouldDeferSpeculativeTranslation('나는 친구를 만났어'),
        isTrue,
      );
      expect(
        session.shouldDeferSpeculativeTranslation('나는 집에 갔어'),
        isTrue,
      );
      expect(session.shouldDeferSpeculativeTranslation('네'), isFalse);
      expect(session.shouldDeferSpeculativeTranslation('안녕하세요'), isFalse);
    });

    test('does not depend on pronoun, name, or participant patterns', () {
      final session = FirstUtteranceContextJudgeSession();

      expect(
        session.shouldDeferSpeculativeTranslation('제가 엄마를 만났어요'),
        isTrue,
      );
      expect(
        session.shouldDeferSpeculativeTranslation('내가 친구에게 전화했어'),
        isTrue,
      );
      expect(
        session.shouldDeferSpeculativeTranslation('나는 민수와 지수를 만났어'),
        isTrue,
      );
    });

    test('does not depend on a relation-sensitive verb list', () {
      final session = FirstUtteranceContextJudgeSession();

      expect(
        session.shouldDeferSpeculativeTranslation('나는 어제 전화했어'),
        isTrue,
      );
      expect(
        session.shouldDeferSpeculativeTranslation('저는 선물을 보냈어요'),
        isTrue,
      );
      expect(
        session.shouldDeferSpeculativeTranslation('나는 집에 갔어'),
        isTrue,
      );
    });

    test('lets the model judge all two-syllable Korean content', () {
      final session = FirstUtteranceContextJudgeSession();

      for (final utterance in ['좋아', '싫어', '가자', '몰라', '맞아']) {
        expect(
          session.shouldDeferSpeculativeTranslation(utterance),
          isTrue,
          reason: utterance,
        );
      }
      expect(session.shouldDeferSpeculativeTranslation('전화'), isTrue);
    });

    test('does not mistake topic and modifier endings for subjects', () {
      final session = FirstUtteranceContextJudgeSession();

      expect(
        session.shouldDeferSpeculativeTranslation('어제는 친구를 만났어'),
        isTrue,
      );
      expect(
        session.shouldDeferSpeculativeTranslation('병원에서는 많이 기다렸어요'),
        isTrue,
      );
      expect(
        session.shouldDeferSpeculativeTranslation('매일 먹는 편이에요'),
        isTrue,
      );
    });

    test('excluded utterance does not consume the first normal slot', () async {
      final session = FirstUtteranceContextJudgeSession();

      final result = await session.judgeIfNeeded(
        apiKey: 'unused',
        transcript: '네',
        mode: 'ANYONE',
      );

      expect(result, isNull);
      expect(session.firstNormalUtteranceSeen, isFalse);
      expect(session.requestStarted, isFalse);
    });

    test('marks first exceptions to preserve the mode turn counter', () {
      final session = FirstUtteranceContextJudgeSession();

      expect(
        session.shouldIgnoreWithoutConsumingFirstTurn('안녕하세요'),
        isTrue,
      );
      expect(
        session.shouldIgnoreWithoutConsumingFirstTurn(
          '어제 친구를 만났어',
          sttConfidence: 0.3,
        ),
        isTrue,
      );
      expect(
        session.shouldIgnoreWithoutConsumingFirstTurn('좋아'),
        isFalse,
      );
    });

    test('very low STT confidence does not consume the slot', () async {
      final session = FirstUtteranceContextJudgeSession();

      final result = await session.judgeIfNeeded(
        apiKey: 'unused',
        transcript: '어제 친구를 만났어',
        mode: 'STEP_EXPAND',
        sttConfidence: 0.3,
      );

      expect(result, isNull);
      expect(session.firstNormalUtteranceSeen, isFalse);
      expect(session.requestStarted, isFalse);
    });

    test('meaningful non-Korean first utterance consumes without a request',
        () async {
      final session = FirstUtteranceContextJudgeSession();

      final result = await session.judgeIfNeeded(
        apiKey: 'unused',
        transcript: 'I went home',
        mode: 'ANYONE',
        sttConfidence: 0.95,
      );

      expect(result, isNull);
      expect(session.firstNormalUtteranceSeen, isTrue);
      expect(session.requestStarted, isFalse);
      expect(
        session.shouldDeferSpeculativeTranslation('어제 친구를 만났어'),
        isFalse,
      );
    });
  });

  group('final transcript deduplication', () {
    test('ignores only an identical normalized final transcript', () {
      expect(
        isDuplicateFinalTranscript(
          '어제  친구를 만났어',
          ' 어제 친구를 만났어 ',
          sincePreviousFinal: const Duration(milliseconds: 100),
        ),
        isTrue,
      );
      expect(
        isDuplicateFinalTranscript(
          '어제 친구를',
          '만났어',
          sincePreviousFinal: const Duration(milliseconds: 100),
        ),
        isFalse,
      );
      expect(
        isDuplicateFinalTranscript(
          '',
          '안녕하세요',
          sincePreviousFinal: const Duration(milliseconds: 100),
        ),
        isFalse,
      );
    });

    test(
        'preserves an intentional repeated utterance outside the dedupe window',
        () {
      expect(
        isDuplicateFinalTranscript(
          '정말',
          '정말',
          sincePreviousFinal: const Duration(milliseconds: 400),
        ),
        isFalse,
      );
      expect(
        isDuplicateFinalTranscript(
          '정말',
          '정말',
          sincePreviousFinal: null,
        ),
        isFalse,
      );
    });
  });

  group('pipeline generation guard', () {
    test('accepts only the active mounted generation', () {
      expect(
        isActivePipelineGeneration(
          expected: 3,
          current: 3,
          mounted: true,
          conversationActive: true,
        ),
        isTrue,
      );
      expect(
        isActivePipelineGeneration(
          expected: 2,
          current: 3,
          mounted: true,
          conversationActive: true,
        ),
        isFalse,
      );
      expect(
        isActivePipelineGeneration(
          expected: 3,
          current: 3,
          mounted: true,
          conversationActive: false,
        ),
        isFalse,
      );
      expect(
        isActivePipelineGeneration(
          expected: 3,
          current: 3,
          mounted: false,
          conversationActive: true,
        ),
        isFalse,
      );
    });
  });

  group('Step Expand first-turn seed policy', () {
    test('opening text stays a single short question', () {
      expect(kStepExpandOpeningNudgeText, '오늘은 어떤 순간을 영어로 풀어 볼까요?');
    });

    test('turns any recoverable first input into a short grounded seed', () {
      final policy = buildStepExpandFirstTurnSeedPolicy('English');
      expect(policy, contains('CREATE A SEED'));
      expect(policy, contains('Whatever meaningful'));
      expect(policy, contains('seed sentence in English'));
      expect(policy, contains('brief, simple clause'));
      expect(policy, contains('minimum grammatical'));
      expect(policy, contains('Never invent'));
      expect(policy, contains('Output ONLY'));
    });

    test('keeps first-turn control tags from replacing a recoverable seed', () {
      final policy = buildStepExpandFirstTurnSeedPolicy('English');
      for (final tag in [
        '[DISSATISFIED]',
        '[CORRECTION]',
        '[MISHEARD]',
        '[CLARIFY]',
        '[RESTATE]',
        '[GARBLED]',
      ]) {
        expect(policy, contains(tag), reason: tag);
      }
      expect(
        policy,
        contains('when any coherent topic or intent is recoverable'),
      );
    });

    test('builds the seed in the selected target language', () {
      expect(
        buildStepExpandFirstTurnSeedPolicy('Japanese'),
        contains('seed sentence in Japanese'),
      );
    });

    test('runs question dissatisfaction only after an actual AI question', () {
      expect(
        shouldRunStepQuestionDissatisfactionFastLane(
          hasPriorAiQuestion: false,
          rawDissatisfactionMatch: true,
        ),
        isFalse,
      );
      expect(
        shouldRunStepQuestionDissatisfactionFastLane(
          hasPriorAiQuestion: true,
          rawDissatisfactionMatch: true,
        ),
        isTrue,
      );
      expect(
        shouldRunStepQuestionDissatisfactionFastLane(
          hasPriorAiQuestion: true,
          rawDissatisfactionMatch: false,
        ),
        isFalse,
      );
    });
  });
}
