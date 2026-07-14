// Deepgram confidence instrumentation shared by Anyone and Step Expand.
// Measurement-only: never branch UI, History, Turn, GPT, TTS, or microphone flow.

import 'dart:math' as math;

class DeepgramWordResult {
  const DeepgramWordResult(
      {required this.word,
      required this.punctuatedWord,
      required this.confidence,
      required this.start,
      required this.end});
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
        end: end);
  }
}

class DeepgramTurnResult {
  const DeepgramTurnResult(
      {required this.transcript,
      required this.words,
      required this.chunkTranscriptConfidences,
      required this.finalizedAt});
  final String transcript;
  final List<DeepgramWordResult> words;
  final List<double> chunkTranscriptConfidences;
  final DateTime finalizedAt;

  double? get transcriptConfidence => chunkTranscriptConfidences.length == 1
      ? chunkTranscriptConfidences.single
      : null;

  static DeepgramTurnResult merge(
      {required String transcript, required List<DeepgramTurnResult> results}) {
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
        for (final result in results) ...result.chunkTranscriptConfidences
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
    required this.normalizeUs,
    required this.classificationUs,
    required this.suspectSelectionUs,
    required this.phraseBuildUs,
    required this.statsUs,
    required this.totalDecisionUs,
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
  final int normalizeUs;
  final int classificationUs;
  final int suspectSelectionUs;
  final int phraseBuildUs;
  final int statsUs;
  final int totalDecisionUs;
  int get decisionMs => totalDecisionUs ~/ 1000;
}

enum _ProbeTokenKind { lowImpact, shortKorean, properNounCandidate, content }

class _ProbeTokenAssessment {
  const _ProbeTokenAssessment({required this.index, required this.kind});
  final int index;
  final _ProbeTokenKind kind;
}

class DeepgramConfidenceProbe {
  DeepgramConfidenceProbe._();

  // Probe-only thresholds. They never control conversation behavior.
  static const double lowWordConfidenceThreshold = 0.65;
  static const double lowChunkConfidenceThreshold = 0.70;
  static const double veryLowChunkConfidenceThreshold = 0.50;

  // Applied only to English utterances.
  static const Set<String> _englishFunctionWords = {
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

  // Low-impact candidates only, never semantic conclusions. They are accepted
  // only when a separate, confidently recognized Korean content token exists.
  static const Set<String> _koreanLowImpactCandidates = {
    '은',
    '는',
    '이',
    '가',
    '을',
    '를',
    '에',
    '에서',
    '로',
    '으로',
    '와',
    '과',
    '도',
    '만',
    '의',
    '게',
    '걸',
    '건',
    '거',
    '것',
  };
  static const Set<String> _koreanLowImpactTailCandidates = {
    '같은데',
    '아닌데',
    '거야',
    '거예요',
    '것같은데',
    '것이다',
  };

  static MeaningDecisionProbeResult evaluate(DeepgramTurnResult turn,
      {required String languageCode}) {
    final totalWatch = Stopwatch()..start();

    final statsWatch = Stopwatch()..start();
    final confidences = turn.words.map((word) => word.confidence).toList();
    final lowIndexes = <int>[
      for (var i = 0; i < turn.words.length; i++)
        if (turn.words[i].confidence < lowWordConfidenceThreshold) i
    ];
    final wordMean = _mean(confidences);
    final wordMedian = _median(confidences);
    final wordMin = confidences.isEmpty ? null : confidences.reduce(math.min);
    final chunkMean = _mean(turn.chunkTranscriptConfidences);
    final chunkMin = turn.chunkTranscriptConfidences.isEmpty
        ? null
        : turn.chunkTranscriptConfidences.reduce(math.min);
    statsWatch.stop();

    // Deepgram `word` is non-punctuated. Normalize each token exactly once and
    // avoid constructing a Unicode-property RegExp in the low-confidence path.
    final normalizeWatch = Stopwatch()..start();
    final normalized = [
      for (final word in turn.words) word.word.trim().toLowerCase()
    ];
    normalizeWatch.stop();

    final classificationWatch = Stopwatch()..start();
    final language = languageCode.toLowerCase();
    final isKorean = language.startsWith('ko');
    final isEnglish = language.startsWith('en');
    final hasReliableKoreanContent = isKorean &&
        _hasReliableKoreanContent(turn.words, normalized, lowIndexes);
    final assessments = <_ProbeTokenAssessment>[
      for (final index in lowIndexes)
        _ProbeTokenAssessment(
          index: index,
          kind: _classifyToken(
            words: turn.words,
            normalized: normalized,
            index: index,
            isKorean: isKorean,
            isEnglish: isEnglish,
            hasReliableKoreanContent: hasReliableKoreanContent,
          ),
        ),
    ];
    classificationWatch.stop();

    final selectionWatch = Stopwatch()..start();
    final content = assessments
        .where((item) => item.kind != _ProbeTokenKind.lowImpact)
        .toList();
    final selectionPool = content.isNotEmpty ? content : assessments;
    final suspectAssessment =
        _selectLowestConfidence(turn.words, selectionPool);
    selectionWatch.stop();

    var decision = 'PASS';
    var reasonCode = 'PASS_CLEAR';
    var reason = 'final word confidence values are above probe thresholds';
    if (turn.words.isEmpty) {
      reasonCode = 'INSUFFICIENT_WORD_DATA';
      reason =
          'Deepgram final result did not include usable word confidence data';
    } else if (chunkMean != null &&
        chunkMean < veryLowChunkConfidenceThreshold) {
      decision = 'QUESTION_REFRAME_CANDIDATE';
      reasonCode = 'LOW_TRANSCRIPT_CONFIDENCE';
      reason = 'final-chunk transcript confidence is very low';
    } else if (content.length >= 2) {
      decision = 'QUESTION_REFRAME_CANDIDATE';
      reasonCode = 'MULTIPLE_LOW_CONFIDENCE_TOKENS';
      reason = 'multiple non-low-impact tokens are below the probe threshold';
    } else if (content.length == 1) {
      decision = 'WORD_CONFIRM_CANDIDATE';
      switch (content.single.kind) {
        case _ProbeTokenKind.shortKorean:
          reasonCode = 'LOW_CONFIDENCE_SHORT_KOREAN_TOKEN';
          reason =
              'a short Korean token is below the probe threshold and remains a review candidate';
          break;
        case _ProbeTokenKind.properNounCandidate:
          reasonCode = 'LOW_CONFIDENCE_PROPER_NOUN_CANDIDATE';
          reason = 'a possible proper noun is below the probe threshold';
          break;
        case _ProbeTokenKind.content:
          reasonCode = 'LOW_CONFIDENCE_CONTENT_TOKEN';
          reason = 'a non-low-impact token is below the probe threshold';
          break;
        case _ProbeTokenKind.lowImpact:
          break;
      }
    } else if (assessments.isNotEmpty) {
      reasonCode = 'LOW_CONFIDENCE_LOW_IMPACT_TOKEN';
      reason = 'only low-impact token candidates are below the probe threshold';
    } else if (chunkMean != null && chunkMean < lowChunkConfidenceThreshold) {
      reasonCode = 'LOW_TRANSCRIPT_CONFIDENCE';
      reason =
          'final-chunk transcript confidence is low but not low enough to reframe';
    }

    final phraseWatch = Stopwatch()..start();
    final suspectIndex = suspectAssessment?.index ?? -1;
    final suspectWord = suspectIndex >= 0 ? turn.words[suspectIndex] : null;
    final suspectPhrase =
        suspectIndex >= 0 ? _buildSuspectPhrase(turn.words, suspectIndex) : '';
    phraseWatch.stop();
    totalWatch.stop();

    return MeaningDecisionProbeResult(
      predictedDecision: decision,
      suspectWord: suspectWord?.punctuatedWord ?? '',
      suspectPhrase: suspectPhrase,
      suspectWordConfidence: suspectWord?.confidence,
      reasonCode: reasonCode,
      reason: reason,
      transcriptConfidence: turn.transcriptConfidence,
      wordConfidenceMean: wordMean,
      wordConfidenceMedian: wordMedian,
      wordConfidenceMin: wordMin,
      lowConfidenceWordCount: lowIndexes.length,
      totalWordCount: turn.words.length,
      chunkTranscriptConfidenceMean: chunkMean,
      chunkTranscriptConfidenceMin: chunkMin,
      normalizeUs: normalizeWatch.elapsedMicroseconds,
      classificationUs: classificationWatch.elapsedMicroseconds,
      suspectSelectionUs: selectionWatch.elapsedMicroseconds,
      phraseBuildUs: phraseWatch.elapsedMicroseconds,
      statsUs: statsWatch.elapsedMicroseconds,
      totalDecisionUs: totalWatch.elapsedMicroseconds,
    );
  }

  static String formatLog(
      {required String mode,
      required String languageCode,
      required DeepgramTurnResult turn,
      required MeaningDecisionProbeResult probe}) {
    final watch = Stopwatch()..start();
    final distribution = turn.words
        .map((word) =>
            '${_quote(word.punctuatedWord)}:${_formatNumber(word.confidence)}')
        .join('|');
    final base =
        'mode=$mode language=$languageCode predictedDecision=${probe.predictedDecision} '
        'transcript="${_escape(turn.transcript)}" suspectPhrase="${_escape(probe.suspectPhrase)}" '
        'suspectWord="${_escape(probe.suspectWord)}" wordConfidence=${_formatNumber(probe.suspectWordConfidence)} '
        'wordConfidenceMean=${_formatNumber(probe.wordConfidenceMean)} wordConfidenceMedian=${_formatNumber(probe.wordConfidenceMedian)} '
        'wordConfidenceMin=${_formatNumber(probe.wordConfidenceMin)} lowConfidenceWordCount=${probe.lowConfidenceWordCount} '
        'totalWordCount=${probe.totalWordCount} transcriptConfidence=${_formatNumber(probe.transcriptConfidence)} '
        'chunkTranscriptConfidenceMean=${_formatNumber(probe.chunkTranscriptConfidenceMean)} '
        'chunkTranscriptConfidenceMin=${_formatNumber(probe.chunkTranscriptConfidenceMin)} reasonCode=${probe.reasonCode} '
        'reason="${_escape(probe.reason)}" decisionMs=${probe.decisionMs} normalizeMs=${_formatMicros(probe.normalizeUs)} '
        'classificationMs=${_formatMicros(probe.classificationUs)} suspectSelectionMs=${_formatMicros(probe.suspectSelectionUs)} '
        'phraseBuildMs=${_formatMicros(probe.phraseBuildUs)} statsMs=${_formatMicros(probe.statsUs)} '
        'totalDecisionMs=${_formatMicros(probe.totalDecisionUs)} wordDistribution="$distribution"';
    watch.stop();
    return '$base logFormatMs=${_formatMicros(watch.elapsedMicroseconds)}';
  }

  static bool _hasReliableKoreanContent(List<DeepgramWordResult> words,
      List<String> normalized, List<int> lowIndexes) {
    final low = lowIndexes.toSet();
    for (var i = 0; i < words.length; i++) {
      if (low.contains(i)) {
        continue;
      }
      final token = normalized[i];
      if (words[i].confidence < lowWordConfidenceThreshold ||
          !_containsHangul(token) ||
          _koreanLowImpactCandidates.contains(token) ||
          _koreanLowImpactTailCandidates.contains(token)) {
        continue;
      }
      if (token.runes.length >= 2) {
        return true;
      }
    }
    return false;
  }

  static _ProbeTokenKind _classifyToken({
    required List<DeepgramWordResult> words,
    required List<String> normalized,
    required int index,
    required bool isKorean,
    required bool isEnglish,
    required bool hasReliableKoreanContent,
  }) {
    final token = normalized[index];
    if (isKorean && _containsHangul(token)) {
      final lowImpact = hasReliableKoreanContent &&
          (_koreanLowImpactCandidates.contains(token) ||
              (index == words.length - 1 &&
                  _koreanLowImpactTailCandidates.contains(token)));
      if (lowImpact) return _ProbeTokenKind.lowImpact;
      if (token.runes.length <= 2) return _ProbeTokenKind.shortKorean;
      return _ProbeTokenKind.content;
    }
    if (isEnglish && _englishFunctionWords.contains(token)) {
      return _ProbeTokenKind.lowImpact;
    }
    if (_containsAsciiDigit(token) ||
        _looksLikeProperNoun(words[index], index)) {
      return _ProbeTokenKind.properNounCandidate;
    }
    return _ProbeTokenKind.content;
  }

  static _ProbeTokenAssessment? _selectLowestConfidence(
      List<DeepgramWordResult> words, List<_ProbeTokenAssessment> items) {
    if (items.isEmpty) {
      return null;
    }
    return items.reduce((a, b) =>
        words[a.index].confidence <= words[b.index].confidence ? a : b);
  }

  static bool _containsHangul(String value) {
    for (final rune in value.runes) {
      if ((rune >= 0xAC00 && rune <= 0xD7A3) ||
          (rune >= 0x1100 && rune <= 0x11FF) ||
          (rune >= 0x3130 && rune <= 0x318F)) {
        return true;
      }
    }
    return false;
  }

  static bool _containsAsciiDigit(String value) {
    for (final code in value.codeUnits) {
      if (code >= 0x30 && code <= 0x39) {
        return true;
      }
    }
    return false;
  }

  static bool _looksLikeProperNoun(DeepgramWordResult word, int index) {
    if (index == 0 || word.punctuatedWord.isEmpty) return false;
    final first = word.punctuatedWord.codeUnitAt(0);
    return first >= 0x41 && first <= 0x5A;
  }

  static String _buildSuspectPhrase(
      List<DeepgramWordResult> words, int suspectIndex) {
    var start = suspectIndex;
    var end = suspectIndex;
    if (suspectIndex == 0 && words.length > 1) {
      end = 1;
    } else if (suspectIndex == words.length - 1 && suspectIndex > 0) {
      start = suspectIndex - 1;
    } else if (suspectIndex > 0 && !_endsSentence(words[suspectIndex - 1])) {
      start = suspectIndex - 1;
    } else if (suspectIndex + 1 < words.length &&
        !_endsSentence(words[suspectIndex])) {
      end = suspectIndex + 1;
    }
    return words
        .sublist(start, end + 1)
        .map((word) => word.punctuatedWord.trim())
        .where((word) => word.isNotEmpty)
        .join(' ')
        .trim();
  }

  static bool _endsSentence(DeepgramWordResult word) {
    final value = word.punctuatedWord.trim();
    if (value.isEmpty) return false;
    const endings = {'.', '!', '?', '。', '！', '？'};
    return endings.contains(value.substring(value.length - 1));
  }
}

String _formatNumber(double? value) =>
    value == null ? 'n/a' : value.toStringAsFixed(3);
String _formatMicros(int value) => (value / 1000).toStringAsFixed(3);
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
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}
