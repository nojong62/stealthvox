// Deepgram confidence instrumentation shared by Anyone and Step Expand.
//
// This file is intentionally measurement-only. Its results must never branch
// the conversation pipeline or change UI, History, Turn, TTS, or microphone
// behavior.

import 'dart:math' as math;

class DeepgramWordResult {
  const DeepgramWordResult({
    required this.word,
    required this.punctuatedWord,
    required this.confidence,
    required this.start,
    required this.end,
  });

  final String word;
  final String punctuatedWord;
  final double confidence;
  final double start;
  final double end;

  static DeepgramWordResult? fromJson(dynamic value) {
    if (value is! Map) return null;
    final rawWord = value['word']?.toString().trim() ?? '';
    final punctuated = value['punctuated_word']?.toString().trim() ?? rawWord;
    final confidence = _asDouble(value['confidence']);
    final start = _asDouble(value['start']);
    final end = _asDouble(value['end']);
    if (rawWord.isEmpty || confidence == null || start == null || end == null) {
      return null;
    }
    return DeepgramWordResult(
      word: rawWord,
      punctuatedWord: punctuated.isEmpty ? rawWord : punctuated,
      confidence: confidence,
      start: start,
      end: end,
    );
  }
}

class DeepgramTurnResult {
  const DeepgramTurnResult({
    required this.transcript,
    required this.words,
    required this.chunkTranscriptConfidences,
    required this.finalizedAt,
  });

  final String transcript;
  final List<DeepgramWordResult> words;
  final List<double> chunkTranscriptConfidences;
  final DateTime finalizedAt;

  /// A Deepgram transcript confidence is a final-chunk value, not a whole-turn
  /// sentence score. Expose it only when this turn contains exactly one chunk.
  double? get transcriptConfidence => chunkTranscriptConfidences.length == 1
      ? chunkTranscriptConfidences.single
      : null;

  static DeepgramTurnResult merge({
    required String transcript,
    required List<DeepgramTurnResult> results,
  }) {
    if (results.isEmpty) {
      return DeepgramTurnResult(
        transcript: transcript,
        words: const [],
        chunkTranscriptConfidences: const [],
        finalizedAt: DateTime.now(),
      );
    }
    return DeepgramTurnResult(
      transcript: transcript,
      words: [for (final result in results) ...result.words],
      chunkTranscriptConfidences: [
        for (final result in results) ...result.chunkTranscriptConfidences,
      ],
      finalizedAt: results
          .map((result) => result.finalizedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b),
    );
  }
}

class MeaningDecisionProbeResult {
  const MeaningDecisionProbeResult({
    required this.predictedDecision,
    required this.suspectWord,
    required this.suspectPhrase,
    required this.suspectWordConfidence,
    required this.reasonCode,
    required this.reason,
    required this.transcriptConfidence,
    required this.wordConfidenceMean,
    required this.wordConfidenceMedian,
    required this.wordConfidenceMin,
    required this.lowConfidenceWordCount,
    required this.totalWordCount,
    required this.chunkTranscriptConfidenceMean,
    required this.chunkTranscriptConfidenceMin,
    required this.decisionMs,
  });

  final String predictedDecision;
  final String suspectWord;
  final String suspectPhrase;
  final double? suspectWordConfidence;
  final String reasonCode;
  final String reason;
  final double? transcriptConfidence;
  final double? wordConfidenceMean;
  final double? wordConfidenceMedian;
  final double? wordConfidenceMin;
  final int lowConfidenceWordCount;
  final int totalWordCount;
  final double? chunkTranscriptConfidenceMean;
  final double? chunkTranscriptConfidenceMin;
  final int decisionMs;
}

class DeepgramConfidenceProbe {
  DeepgramConfidenceProbe._();

  // Candidate-detection thresholds only. They do not control user behavior.
  static const double lowWordConfidenceThreshold = 0.65;
  static const double lowChunkConfidenceThreshold = 0.70;
  static const double garbledChunkConfidenceThreshold = 0.50;

  static const Set<String> _functionWords = {
    'a',
    'an',
    'the',
    'and',
    'or',
    'but',
    'to',
    'of',
    'in',
    'on',
    'at',
    'for',
    'from',
    'with',
    'by',
    'as',
    'is',
    'am',
    'are',
    'was',
    'were',
    'be',
    'been',
    'being',
    'do',
    'does',
    'did',
    'it',
    'this',
    'that',
    'these',
    'those',
    'i',
    'you',
    'he',
    'she',
    'we',
    'they',
    'my',
    'your',
    'his',
    'her',
    'our',
    'their',
  };

  static MeaningDecisionProbeResult evaluate(DeepgramTurnResult turn) {
    final stopwatch = Stopwatch()..start();
    final confidences = turn.words.map((word) => word.confidence).toList();
    final lowWordIndexes = <int>[
      for (var i = 0; i < turn.words.length; i++)
        if (turn.words[i].confidence < lowWordConfidenceThreshold) i,
    ];

    final wordMean = _mean(confidences);
    final wordMedian = _median(confidences);
    final wordMin = confidences.isEmpty ? null : confidences.reduce(math.min);
    final chunkMean = _mean(turn.chunkTranscriptConfidences);
    final chunkMin = turn.chunkTranscriptConfidences.isEmpty
        ? null
        : turn.chunkTranscriptConfidences.reduce(math.min);

    String predictedDecision = 'PASS';
    String reasonCode = 'PASS_CLEAR';
    String reason = 'final word confidence values are above probe thresholds';
    var suspectIndex = -1;

    if (turn.words.isEmpty) {
      reasonCode = 'INSUFFICIENT_WORD_DATA';
      reason =
          'Deepgram final result did not include usable word confidence data';
    } else {
      suspectIndex = _selectSuspectIndex(turn.words, lowWordIndexes);
      final lowRatio = lowWordIndexes.length / turn.words.length;
      final hasCriticalLowWord = suspectIndex >= 0 &&
          _isMeaningCritical(turn.words[suspectIndex], suspectIndex);

      if ((chunkMean != null && chunkMean < garbledChunkConfidenceThreshold) ||
          (lowWordIndexes.length >= 2 && lowRatio >= 0.5)) {
        predictedDecision = 'QUESTION_REFRAME_CANDIDATE';
        reasonCode = 'GARBLED_MEANING_CANDIDATE';
        reason =
            'multiple low-confidence words may make the utterance unreliable';
      } else if (lowWordIndexes.length >= 2) {
        predictedDecision = 'QUESTION_REFRAME_CANDIDATE';
        reasonCode = 'MULTIPLE_LOW_CONFIDENCE_WORDS';
        reason = 'multiple final words are below the probe-only threshold';
      } else if (chunkMean != null && chunkMean < lowChunkConfidenceThreshold) {
        predictedDecision = 'QUESTION_REFRAME_CANDIDATE';
        reasonCode = 'LOW_TRANSCRIPT_CONFIDENCE';
        reason =
            'mean final-chunk transcript confidence is below the probe threshold';
      } else if (hasCriticalLowWord) {
        predictedDecision = 'WORD_CONFIRM_CANDIDATE';
        reasonCode = 'LOW_WORD_CONFIDENCE_CONTEXT_CRITICAL';
        reason =
            'a likely meaning-bearing word is below the probe-only threshold';
      } else if (lowWordIndexes.isNotEmpty) {
        reasonCode = 'LOW_WORD_CONFIDENCE';
        reason = 'only a short function word is below the probe threshold';
      }
    }

    final suspectWord = suspectIndex >= 0 ? turn.words[suspectIndex] : null;
    final suspectPhrase =
        suspectIndex >= 0 ? _buildSuspectPhrase(turn.words, suspectIndex) : '';
    stopwatch.stop();

    return MeaningDecisionProbeResult(
      predictedDecision: predictedDecision,
      suspectWord: suspectWord?.punctuatedWord ?? '',
      suspectPhrase: suspectPhrase,
      suspectWordConfidence: suspectWord?.confidence,
      reasonCode: reasonCode,
      reason: reason,
      transcriptConfidence: turn.transcriptConfidence,
      wordConfidenceMean: wordMean,
      wordConfidenceMedian: wordMedian,
      wordConfidenceMin: wordMin,
      lowConfidenceWordCount: lowWordIndexes.length,
      totalWordCount: turn.words.length,
      chunkTranscriptConfidenceMean: chunkMean,
      chunkTranscriptConfidenceMin: chunkMin,
      decisionMs: stopwatch.elapsedMicroseconds ~/ 1000,
    );
  }

  static String formatLog({
    required String mode,
    required DeepgramTurnResult turn,
    required MeaningDecisionProbeResult probe,
  }) {
    final wordDistribution = turn.words
        .map((word) =>
            '${_quote(word.punctuatedWord)}:${_formatNumber(word.confidence)}')
        .join('|');
    return 'mode=$mode '
        'predictedDecision=${probe.predictedDecision} '
        'transcript="${_escape(turn.transcript)}" '
        'suspectPhrase="${_escape(probe.suspectPhrase)}" '
        'suspectWord="${_escape(probe.suspectWord)}" '
        'wordConfidence=${_formatNumber(probe.suspectWordConfidence)} '
        'wordConfidenceMean=${_formatNumber(probe.wordConfidenceMean)} '
        'wordConfidenceMedian=${_formatNumber(probe.wordConfidenceMedian)} '
        'wordConfidenceMin=${_formatNumber(probe.wordConfidenceMin)} '
        'lowConfidenceWordCount=${probe.lowConfidenceWordCount} '
        'totalWordCount=${probe.totalWordCount} '
        'transcriptConfidence=${_formatNumber(probe.transcriptConfidence)} '
        'chunkTranscriptConfidenceMean='
        '${_formatNumber(probe.chunkTranscriptConfidenceMean)} '
        'chunkTranscriptConfidenceMin='
        '${_formatNumber(probe.chunkTranscriptConfidenceMin)} '
        'reasonCode=${probe.reasonCode} '
        'reason="${_escape(probe.reason)}" '
        'decisionMs=${probe.decisionMs} '
        'wordDistribution="$wordDistribution"';
  }

  static int _selectSuspectIndex(
    List<DeepgramWordResult> words,
    List<int> lowWordIndexes,
  ) {
    if (lowWordIndexes.isEmpty) return -1;
    final critical = lowWordIndexes
        .where((index) => _isMeaningCritical(words[index], index))
        .toList();
    final candidates = critical.isNotEmpty ? critical : lowWordIndexes;
    return candidates
        .reduce((a, b) => words[a].confidence <= words[b].confidence ? a : b);
  }

  static bool _isMeaningCritical(DeepgramWordResult word, int index) {
    final normalized = word.word.toLowerCase().replaceAll(
          RegExp(r'[^\p{L}\p{N}]', unicode: true),
          '',
        );
    if (normalized.isEmpty || _functionWords.contains(normalized)) return false;
    if (RegExp(r'\d').hasMatch(normalized)) return true;
    final punctuated = word.punctuatedWord;
    final looksLikeProperNoun = index > 0 &&
        punctuated.isNotEmpty &&
        punctuated[0] == punctuated[0].toUpperCase() &&
        punctuated[0] != punctuated[0].toLowerCase();
    return looksLikeProperNoun || normalized.length >= 3;
  }

  static String _buildSuspectPhrase(
    List<DeepgramWordResult> words,
    int suspectIndex,
  ) {
    var start = suspectIndex;
    var end = suspectIndex;
    if (suspectIndex > 0 && !_endsSentence(words[suspectIndex - 1])) {
      start = suspectIndex - 1;
    } else if (suspectIndex + 1 < words.length &&
        !_endsSentence(words[suspectIndex])) {
      end = suspectIndex + 1;
    }
    return words
        .sublist(start, end + 1)
        .map((word) => word.punctuatedWord)
        .join(' ')
        .trim();
  }

  static bool _endsSentence(DeepgramWordResult word) =>
      RegExp(r'[.!?。！？]$').hasMatch(word.punctuatedWord);
}

String _formatNumber(double? value) =>
    value == null ? 'n/a' : value.toStringAsFixed(3);

String _escape(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll('"', r'\"')
    .replaceAll('\n', r'\n');

String _quote(String value) => _escape(value).replaceAll('|', r'\|');
double? _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

double? _mean(List<double> values) {
  if (values.isEmpty) return null;
  return values.reduce((a, b) => a + b) / values.length;
}

double? _median(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}
