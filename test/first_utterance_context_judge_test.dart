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
        session.previewRoute('내일 출장 어디로 가?'),
        FirstUtteranceRoute.judge,
      );
      expect(
        session.previewRoute('어제 친구를 만났어'),
        FirstUtteranceRoute.bypass,
      );
      expect(session.previewRoute('I went home'), FirstUtteranceRoute.bypass);

      await session.judgeIfNeeded(
        apiKey: 'unused',
        transcript: 'I went home',
        mode: 'ANYONE',
      );
      expect(session.previewRoute('안녕하세요'), FirstUtteranceRoute.bypass);
    });

    test('routes only actor-ambiguous Korean questions to the judge', () {
      final session = FirstUtteranceContextJudgeSession();

      expect(
        session.shouldDeferSpeculativeTranslation('내일 출장 어디로 가?'),
        isTrue,
      );
      expect(
        session.shouldDeferSpeculativeTranslation('내일은 경주 갈까?'),
        isTrue,
      );
      expect(
        session.shouldDeferSpeculativeTranslation('어제 친구를 만났어'),
        isFalse,
      );
      expect(
        session.shouldDeferSpeculativeTranslation('나는 집에 갔어'),
        isFalse,
      );
      expect(session.shouldDeferSpeculativeTranslation('네'), isFalse);
      expect(session.shouldDeferSpeculativeTranslation('안녕하세요'), isFalse);
    });

    test('bypasses questions with an explicit actor or participant', () {
      final session = FirstUtteranceContextJudgeSession();

      expect(
        session.shouldDeferSpeculativeTranslation('너는 내일 어디로 가?'),
        isFalse,
      );
      expect(
        session.shouldDeferSpeculativeTranslation('제가 어디로 가면 돼요?'),
        isFalse,
      );
      expect(
        session.shouldDeferSpeculativeTranslation('친구는 언제 와?'),
        isFalse,
      );
    });

    test('bypasses ordinary Korean statements', () {
      final session = FirstUtteranceContextJudgeSession();

      expect(
        session.shouldDeferSpeculativeTranslation('나는 어제 전화했어'),
        isFalse,
      );
      expect(
        session.shouldDeferSpeculativeTranslation('저는 선물을 보냈어요'),
        isFalse,
      );
      expect(
        session.shouldDeferSpeculativeTranslation('어제 친구를 만났어'),
        isFalse,
      );
    });

    test('bypasses short reactions and statements', () {
      final session = FirstUtteranceContextJudgeSession();

      for (final utterance in ['좋아', '싫어', '가자', '몰라', '맞아']) {
        expect(
          session.shouldDeferSpeculativeTranslation(utterance),
          isFalse,
          reason: utterance,
        );
      }
      expect(session.shouldDeferSpeculativeTranslation('전화'), isFalse);
    });

    test('still judges questions with only time or place topics', () {
      final session = FirstUtteranceContextJudgeSession();

      expect(
        session.shouldDeferSpeculativeTranslation('내일은 어디로 가?'),
        isTrue,
      );
      expect(
        session.shouldDeferSpeculativeTranslation('회사에서는 누구를 만나?'),
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

    test('adopts a successful prefetched judgment only at handoff', () {
      final session = FirstUtteranceContextJudgeSession();
      const context = FirstUtteranceContext(
        actor: 'user',
        target: 'listener',
        omittedSubject: '나',
        tense: 'past',
        relationship: 'unknown',
        confidence: 0.9,
        ambiguityReason: '',
      );

      expect(session.firstNormalUtteranceSeen, isFalse);
      session.adoptPrefetchedResult(context, requestFailed: false);

      expect(session.firstNormalUtteranceSeen, isTrue);
      expect(session.requestStarted, isTrue);
      expect(session.requestCompleted, isTrue);
      expect(session.requestFailed, isFalse);
    });

    test('adopts a failed prefetch as a normal fallback', () {
      final session = FirstUtteranceContextJudgeSession();

      session.adoptPrefetchedResult(null, requestFailed: true);

      expect(session.firstNormalUtteranceSeen, isTrue);
      expect(session.requestStarted, isTrue);
      expect(session.requestCompleted, isFalse);
      expect(session.requestFailed, isTrue);
    });
  });

  group('language-neutral heard confirmation', () {
    test('detects only the structural first-line signal', () {
      expect(
        hasHeardConfirmSignal('[HEARD_CONFIRM]\nもう一度お願いします。'),
        isTrue,
      );
      expect(hasHeardConfirmSignal('제가 잘못 들었나요?'), isFalse);
      expect(hasHeardConfirmSignal('I may have misheard you.'), isFalse);
      expect(
        hasHeardConfirmSignal('Normal text [HEARD_CONFIRM]\nquestion'),
        isFalse,
      );
      expect(
        hasHeardConfirmSignal('\n  [HEARD_CONFIRM]\r\nQuestion?'),
        isTrue,
      );
    });

    test('hides partial streamed signal and strips the complete signal', () {
      expect(isHeardConfirmSignalPrefix('['), isTrue);
      expect(isHeardConfirmSignalPrefix('[HEARD_'), isTrue);
      expect(isHeardConfirmSignalPrefix('[HEARD_CONFIRM'), isTrue);
      expect(isHeardConfirmSignalPrefix('[HEARD_CONFIRM]'), isTrue);
      expect(isHeardConfirmSignalPrefix('\r\n [HEARD_'), isTrue);
      expect(isHeardConfirmSignalPrefix('普通の文です。'), isFalse);
      expect(
        stripHeardConfirmSignal('[HEARD_CONFIRM]\nDid you say "train"?'),
        'Did you say "train"?',
      );
      expect(
        stripHeardConfirmSignal('\r\n [HEARD_CONFIRM]\r\nもう一度お願いします。'),
        'もう一度お願いします。',
      );
      expect(stripHeardConfirmSignal('[HEARD_CONFIRM]'), isEmpty);
    });

    test('waits for the completed stream before exposing the question', () {
      final chunks = ['[', 'HEARD_', 'CONFIRM]', '\r\nDid you ', 'say train?'];
      var accumulated = '';
      for (var index = 0; index < chunks.length - 1; index++) {
        accumulated += chunks[index];
        expect(
          isHeardConfirmSignalPrefix(accumulated) ||
              hasHeardConfirmSignal(accumulated),
          isTrue,
        );
      }
      accumulated += chunks.last;
      expect(hasHeardConfirmSignal(accumulated), isTrue);
      expect(stripHeardConfirmSignal(accumulated), 'Did you say train?');
    });

    test('provides non-empty retry lines for all 12 lobby origins', () {
      const supportedOrigins = <String>[
        'English',
        'Japanese',
        'Chinese',
        'Spanish',
        'French',
        'German',
        'Korean',
        'Hindi',
        'Russian',
        'Portuguese',
        'Italian',
        'Dutch',
      ];
      final lines = supportedOrigins.map(originRetryLine).toList();
      expect(lines, everyElement(isNotEmpty));
      expect(lines.toSet(), hasLength(supportedOrigins.length));
      expect(originRetryLine('Korean'), contains('다시'));
      expect(originRetryLine('Japanese'), contains('もう一度'));
      expect(originRetryLine('English'), contains('Please'));
      expect(originRetryLine('unknown'), originRetryLine('English'));
      expect(originRetryLine(''), originRetryLine('Korean'));
      expect(localizedSeedGuidanceLine('Japanese'), contains('出来事'));
      expect(
        localizedSeedGuidanceLine('unknown'),
        localizedSeedGuidanceLine('English'),
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

  group('Anyone deliberate reply policy', () {
    test('trades a beat of latency for a committed, specific reply', () {
      expect(kAnyoneDeliberateReplyPolicy, contains('Take an extra beat'));
      expect(kAnyoneDeliberateReplyPolicy, contains('two different replies'));
      expect(kAnyoneDeliberateReplyPolicy, contains('hedging or generic'));
    });

    test('demands one sharp question instead of a vague one', () {
      expect(kAnyoneDeliberateReplyPolicy, contains('must earn its place'));
      expect(kAnyoneDeliberateReplyPolicy, contains('One sharp, specific'));
      expect(kAnyoneDeliberateReplyPolicy, contains('Never a vague'));
    });

    test('keeps the deliberation hidden from the streamed output', () {
      expect(kAnyoneDeliberateReplyPolicy, contains('Never show your drafts'));
      expect(kAnyoneDeliberateReplyPolicy, contains('only the final reply'));
    });
  });
}
