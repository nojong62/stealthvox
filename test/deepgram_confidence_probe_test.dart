import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/widgets/deepgram_confidence_probe.dart';

void main() {
  group('Korean probe candidates', () {
    test('keeps short Korean loanword as a confirmation candidate', () {
      final result = _evaluate(
        transcript: '드랍 커피를 좋아하지',
        tokens: const ['드랍', '커피를', '좋아하지'],
        confidences: const [0.300, 0.731, 0.999],
        languageCode: 'ko',
      );
      expect(result.predictedDecision, 'WORD_CONFIRM_CANDIDATE');
      expect(result.reasonCode, 'LOW_CONFIDENCE_SHORT_KOREAN_TOKEN');
      expect(result.suspectWord, '드랍');
      expect(result.suspectPhrase, '드랍 커피를');
      expect(result.reason, isNot(contains('function word')));
    });

    test('does not classify one-syllable Korean content candidate by length',
        () {
      final result = _evaluate(
        transcript: '큰 수 생기는데',
        tokens: const ['큰', '수', '생기는데'],
        confidences: const [0.990, 0.512, 0.887],
        languageCode: 'ko',
      );
      expect(result.predictedDecision, 'WORD_CONFIRM_CANDIDATE');
      expect(result.reasonCode, 'LOW_CONFIDENCE_SHORT_KOREAN_TOKEN');
      expect(result.suspectWord, '수');
      expect(result.suspectPhrase, '큰 수');
    });

    test('does not reframe for only low-impact ending candidates', () {
      final result = _evaluate(
        transcript: '나는 원자재가 좋은 거 같은데',
        tokens: const ['나는', '원자재가', '좋은', '거', '같은데'],
        confidences: const [0.993, 0.986, 0.999, 0.497, 0.498],
        languageCode: 'ko',
      );
      expect(result.predictedDecision, 'PASS');
      expect(result.reasonCode, 'LOW_CONFIDENCE_LOW_IMPACT_TOKEN');
      expect(result.suspectWord, '거');
    });

    test('keeps short place, app, and car tokens observable', () {
      for (final sample in const [
        (['서울에', '갈', '거야'], [0.400, 0.990, 0.990]),
        (['그', '앱을', '써', '봤어'], [0.990, 0.400, 0.990, 0.990]),
        (['차를', '바꿀', '생각이야'], [0.400, 0.990, 0.990]),
        (
          ['큰', '수익을', '내는', '데', '초점을', '맞춰야지'],
          [0.990, 0.400, 0.990, 0.990, 0.990, 0.990]
        ),
      ]) {
        final result = _evaluate(
          transcript: sample.$1.join(' '),
          tokens: sample.$1,
          confidences: sample.$2,
          languageCode: 'ko',
        );
        expect(result.predictedDecision, 'WORD_CONFIRM_CANDIDATE');
        expect(
          result.reasonCode,
          isIn({
            'LOW_CONFIDENCE_SHORT_KOREAN_TOKEN',
            'LOW_CONFIDENCE_CONTENT_TOKEN',
          }),
        );
      }
    });

    test('passes another low-impact Korean ending example', () {
      final result = _evaluate(
        transcript: '그건 조금 아닌 것 같은데',
        tokens: const ['그건', '조금', '아닌', '것', '같은데'],
        confidences: const [0.980, 0.980, 0.980, 0.400, 0.410],
        languageCode: 'ko',
      );
      expect(result.predictedDecision, 'PASS');
      expect(result.reasonCode, 'LOW_CONFIDENCE_LOW_IMPACT_TOKEN');

      final today = _evaluate(
        transcript: '오늘은 집에 갈 거야',
        tokens: const ['오늘은', '집에', '갈', '거야'],
        confidences: const [0.98, 0.98, 0.98, 0.40],
        languageCode: 'ko',
      );
      expect(today.predictedDecision, 'PASS');
      expect(today.reasonCode, 'LOW_CONFIDENCE_LOW_IMPACT_TOKEN');
    });
  });

  test('applies English function-word rules only to English', () {
    final english = _evaluate(
      transcript: 'I went to the store',
      tokens: const ['I', 'went', 'to', 'the', 'store'],
      confidences: const [0.99, 0.99, 0.40, 0.41, 0.99],
      languageCode: 'en',
    );
    expect(english.predictedDecision, 'PASS');
    expect(english.reasonCode, 'LOW_CONFIDENCE_LOW_IMPACT_TOKEN');

    final nonEnglish = _evaluate(
      transcript: 'I went to the store',
      tokens: const ['I', 'went', 'to', 'the', 'store'],
      confidences: const [0.99, 0.99, 0.40, 0.41, 0.99],
      languageCode: 'es',
    );
    expect(nonEnglish.predictedDecision, 'QUESTION_REFRAME_CANDIDATE');
    expect(nonEnglish.reasonCode, 'MULTIPLE_LOW_CONFIDENCE_TOKENS');
  });

  test('optimized low-confidence path and log formatting stay measurable', () {
    final turn = _turn(
      transcript: '드립 커피를 좋아하지',
      tokens: const ['드립', '커피를', '좋아하지'],
      confidences: const [0.300, 0.731, 0.999],
    );
    DeepgramConfidenceProbe.evaluate(turn, languageCode: 'ko');
    final timings = <int>[];
    for (var i = 0; i < 200; i++) {
      timings.add(
        DeepgramConfidenceProbe.evaluate(turn, languageCode: 'ko')
            .totalDecisionUs,
      );
    }
    final result = DeepgramConfidenceProbe.evaluate(turn, languageCode: 'ko');
    expect(result.predictedDecision, 'WORD_CONFIRM_CANDIDATE');
    expect(result.suspectWord, '드립');
    final log = DeepgramConfidenceProbe.formatLog(
      mode: 'TEST',
      languageCode: 'ko',
      turn: turn,
      probe: result,
    );
    final sorted = [...timings]..sort();
    final p95 =
        sorted[math.min(sorted.length - 1, (sorted.length * .95).ceil() - 1)];
    // ignore: avoid_print
    print(
        '[OPTIMIZED-PROFILE] meanUs=${timings.reduce((a, b) => a + b) / timings.length} maxUs=${timings.reduce(math.max)} p95Us=$p95');
    expect(timings.reduce(math.max), lessThan(30000));
    expect(log, contains('normalizeMs='));
    expect(log, contains('classificationMs='));
    expect(log, contains('suspectSelectionMs='));
    expect(log, contains('phraseBuildMs='));
    expect(log, contains('statsMs='));
    expect(log, contains('totalDecisionMs='));
    expect(log, contains('logFormatMs='));
  });
}

MeaningDecisionProbeResult _evaluate({
  required String transcript,
  required List<String> tokens,
  required List<double> confidences,
  required String languageCode,
}) =>
    DeepgramConfidenceProbe.evaluate(
      _turn(transcript: transcript, tokens: tokens, confidences: confidences),
      languageCode: languageCode,
    );

DeepgramTurnResult _turn({
  required String transcript,
  required List<String> tokens,
  required List<double> confidences,
}) {
  assert(tokens.length == confidences.length);
  return DeepgramTurnResult(
    transcript: transcript,
    words: [
      for (var i = 0; i < tokens.length; i++)
        DeepgramWordResult(
          word: tokens[i],
          punctuatedWord: tokens[i],
          confidence: confidences[i],
          start: i.toDouble(),
          end: i + .5,
        ),
    ],
    chunkTranscriptConfidences: const [0.95],
    finalizedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}
