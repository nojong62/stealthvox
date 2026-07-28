import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const String kFirstUtteranceJudgeModel = 'gpt-4.1';
const int kFirstUtteranceJudgeMaxOutputTokens = 160;
const Duration kFirstUtteranceJudgeTimeout = Duration(milliseconds: 2500);
const int kFirstTurnTranslationReviewMaxOutputTokens = 180;
const Duration kFirstTurnTranslationReviewTimeout =
    Duration(milliseconds: 2500);

typedef FirstUtteranceJudgeLogger = void Function(String event, String details);

enum FirstUtteranceRoute { excluded, judge, bypass }

const Duration kDuplicateFinalTranscriptWindow = Duration(milliseconds: 250);

const String kStepExpandOpeningNudgeText = '오늘은 어떤 순간을 영어로 풀어 볼까요?';

/// Anyone 자유대화 답변 전 내부 숙고 지시.
/// 응답이 1초 정도 느려지더라도 어중간한 답 대신 구체적인 답과 질문을 뽑는다.
const String kAnyoneDeliberateReplyPolicy = '''[THINK TWICE BEFORE YOU SPEAK]
- Take an extra beat. A slightly slower reply that lands is far better than a fast, vague one.
- Silently draft two different replies, compare them, then say only the better one.
- Throw away any draft that is hedging or generic — anything that could have been said to anyone by anyone ("That sounds tough.", "I see.", "How do you feel about that?"). Commit to a real reaction instead.
- Keep the draft that reacts to the specific thing the user just said, in the voice of the specific person you are.
- Your question must earn its place: ask about the one concrete detail you most want to know next — what happened, what they did, what the other person said back. One sharp, specific question. Never a vague or generic one.
- Never show your drafts, your comparison, or any reasoning. Output only the final reply.''';

String buildStepExpandFirstTurnSeedPolicy(String targetLanguage) {
  final language = targetLanguage.trim().isEmpty
      ? 'the requested target language'
      : targetLanguage.trim();
  return '''[CASE 1] History is empty (USER'S FIRST TURN — CREATE A SEED)
- Whatever meaningful content the user gives, turn its core meaning into ONE short, complete, natural spoken seed sentence in $language that can grow in later turns.
- Keep one clear subject and one main idea. Prefer a brief, simple clause over details or complex grammar.
- If the input is already a complete sentence, preserve its meaning and simplify only when useful.
- If it is a fragment, question, reaction, or vague thought, add only the minimum grammatical framing needed to make a usable seed.
- Never invent a name, event, reason, relationship, feeling, or factual detail that the user did not provide.
- On this first turn, do not output [DISSATISFIED], [CORRECTION], [MISHEARD], [CLARIFY], [RESTATE], or [GARBLED] when any coherent topic or intent is recoverable. Use [EVAPORATE] only when there is no recoverable meaning.
- Output ONLY the seed sentence in $language.''';
}

String normalizeTranscriptForDuplicateCheck(String transcript) {
  return transcript.trim().replaceAll(RegExp(r'\s+'), ' ');
}

bool isDuplicateFinalTranscript(
  String pending,
  String incoming, {
  required Duration? sincePreviousFinal,
}) {
  if (sincePreviousFinal == null ||
      sincePreviousFinal.isNegative ||
      sincePreviousFinal > kDuplicateFinalTranscriptWindow) {
    return false;
  }
  final normalizedPending = normalizeTranscriptForDuplicateCheck(pending);
  final normalizedIncoming = normalizeTranscriptForDuplicateCheck(incoming);
  return normalizedPending.isNotEmpty &&
      normalizedPending == normalizedIncoming;
}

bool isActivePipelineGeneration({
  required int expected,
  required int current,
  required bool mounted,
  required bool conversationActive,
}) {
  return mounted && conversationActive && expected == current;
}

bool shouldRunStepQuestionDissatisfactionFastLane({
  required bool hasPriorAiQuestion,
  required bool rawDissatisfactionMatch,
}) {
  return hasPriorAiQuestion && rawDissatisfactionMatch;
}

class FirstUtteranceContext {
  const FirstUtteranceContext({
    required this.actor,
    required this.target,
    required this.omittedSubject,
    required this.tense,
    required this.relationship,
    required this.confidence,
    required this.ambiguityReason,
  });

  final String actor;
  final String target;
  final String omittedSubject;
  final String tense;
  final String relationship;
  final double confidence;
  final String ambiguityReason;

  String get confidenceBand {
    if (confidence >= 0.85) return 'high';
    if (confidence >= 0.65) return 'medium';
    return 'low';
  }

  String toInternalPromptContext() {
    final payload = jsonEncode({
      'actor': actor,
      'target': target,
      'omitted_subject': omittedSubject,
      'tense': tense,
      'relationship': relationship,
      'confidence': confidence,
      'ambiguity_reason': ambiguityReason,
    });
    return '''[INTERNAL FIRST-UTTERANCE CONTEXT — NEVER EXPOSE]
This structured judgment only helps resolve the hidden subject, action target, and person relationship in the first Korean utterance.
- Use it only where it does not conflict with the original utterance.
- confidence >= 0.85: strong supporting context.
- confidence >= 0.65 and < 0.85: reference only; prefer the original wording and conversation context.
- confidence < 0.65: ignore this judgment entirely and translate the original utterance as it stands. Never blur or water down the translation because the judgment was uncertain.
- The final translation and reply must still follow the original utterance and all existing conversation rules.
- Never reveal, quote, or describe this internal judgment to the user.
Judgment: $payload''';
  }

  static FirstUtteranceContext? fromJson(dynamic value) {
    if (value is! Map<String, dynamic>) return null;
    const actors = {'user', 'listener', 'third_person', 'group', 'unknown'};
    const targets = {'listener', 'third_person', 'user', 'none', 'unknown'};
    const tenses = {'past', 'present', 'future', 'ongoing', 'mixed', 'unknown'};
    const relationships = {
      'friend',
      'coworker',
      'workplace_superior',
      'family',
      'teacher',
      'customer',
      'stranger',
      'unknown'
    };
    final actor = value['actor']?.toString() ?? '';
    final target = value['target']?.toString() ?? '';
    final omittedSubject = value['omitted_subject']?.toString().trim() ?? '';
    final tense = value['tense']?.toString() ?? '';
    final relationship = value['relationship']?.toString() ?? '';
    final rawConfidence = value['confidence'];
    final confidence = rawConfidence is num
        ? rawConfidence.toDouble()
        : double.tryParse(rawConfidence?.toString() ?? '');
    final ambiguityReason = value['ambiguity_reason']?.toString().trim() ?? '';
    if (!actors.contains(actor) ||
        !targets.contains(target) ||
        omittedSubject.isEmpty ||
        !tenses.contains(tense) ||
        !relationships.contains(relationship) ||
        confidence == null ||
        confidence.isNaN ||
        confidence < 0 ||
        confidence > 1) {
      return null;
    }
    return FirstUtteranceContext(
      actor: actor,
      target: target,
      omittedSubject: omittedSubject,
      tense: tense,
      relationship: relationship,
      confidence: confidence,
      ambiguityReason: ambiguityReason,
    );
  }
}

enum FirstTurnTranslationReviewVerdict {
  accepted,
  polished,
  retranslated,
}

class FirstTurnTranslationReview {
  const FirstTurnTranslationReview({
    required this.verdict,
    required this.finalText,
  });

  final FirstTurnTranslationReviewVerdict verdict;
  final String finalText;

  static FirstTurnTranslationReview? fromJson(dynamic value) {
    if (value is! Map<String, dynamic> ||
        value.length != 2 ||
        !value.containsKey('verdict') ||
        !value.containsKey('final_text')) {
      return null;
    }
    final verdictName = value['verdict']?.toString();
    final finalText = value['final_text']?.toString().trim() ?? '';
    final verdict = switch (verdictName) {
      'accepted' => FirstTurnTranslationReviewVerdict.accepted,
      'polished' => FirstTurnTranslationReviewVerdict.polished,
      'retranslated' => FirstTurnTranslationReviewVerdict.retranslated,
      _ => null,
    };
    if (verdict == null || finalText.isEmpty) return null;
    return FirstTurnTranslationReview(
      verdict: verdict,
      finalText: finalText,
    );
  }
}

class FirstUtteranceContextJudgeSession {
  bool firstNormalUtteranceSeen = false;
  bool requestStarted = false;
  bool requestCompleted = false;
  bool requestFailed = false;
  bool resultDelivered = false;

  http.Client? _activeClient;
  bool _ownsActiveClient = false;
  int _generation = 0;
  http.Client? _activeReviewClient;
  bool _ownsActiveReviewClient = false;
  FirstUtteranceJudgeLogger? _activeReviewLogger;
  int _reviewGeneration = 0;

  FirstUtteranceRoute previewRoute(String transcript) {
    if (firstNormalUtteranceSeen || requestStarted) {
      return FirstUtteranceRoute.bypass;
    }
    final eligibility = _classify(transcript);
    if (!eligibility.isNormal) return FirstUtteranceRoute.excluded;
    if (eligibility.shouldJudge) return FirstUtteranceRoute.judge;
    return FirstUtteranceRoute.bypass;
  }

  bool shouldDeferSpeculativeTranslation(String transcript) {
    return previewRoute(transcript) == FirstUtteranceRoute.judge;
  }

  bool shouldIgnoreWithoutConsumingFirstTurn(
    String transcript, {
    double? sttConfidence,
  }) {
    if (firstNormalUtteranceSeen || requestStarted) return false;
    if (sttConfidence != null && sttConfidence < 0.50) return true;
    return !_classify(transcript).isNormal;
  }

  Future<FirstUtteranceContext?> judgeIfNeeded({
    required String apiKey,
    required String transcript,
    required String mode,
    double? sttConfidence,
    FirstUtteranceJudgeLogger? onLog,
    http.Client? client,
  }) async {
    if (firstNormalUtteranceSeen || requestStarted) return null;
    final eligibility = _classify(transcript);
    if (!eligibility.isNormal) {
      onLog?.call('skip', 'reason=excluded');
      return null;
    }
    // Very-low-confidence STT does not consume the first normal utterance slot.
    if (sttConfidence != null && sttConfidence < 0.50) {
      onLog?.call('skip', 'reason=low_stt_confidence');
      return null;
    }

    firstNormalUtteranceSeen = true;
    if (!eligibility.shouldJudge) {
      onLog?.call('skip', 'reason=clear_first_utterance');
      return null;
    }

    requestStarted = true;
    requestFailed = false;
    final generation = ++_generation;
    final stopwatch = Stopwatch()..start();
    final requestClient = client ?? http.Client();
    final ownsClient = client == null;
    _activeClient = requestClient;
    _ownsActiveClient = ownsClient;
    onLog?.call('start', 'model=$kFirstUtteranceJudgeModel mode=$mode');
    try {
      final response = await requestClient
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'model': kFirstUtteranceJudgeModel,
              'temperature': 0,
              'max_completion_tokens': kFirstUtteranceJudgeMaxOutputTokens,
              'response_format': {
                'type': 'json_schema',
                'json_schema': {
                  'name': 'first_utterance_context',
                  'strict': true,
                  'schema': {
                    'type': 'object',
                    'additionalProperties': false,
                    'properties': {
                      'actor': {
                        'type': 'string',
                        'enum': [
                          'user',
                          'listener',
                          'third_person',
                          'group',
                          'unknown'
                        ]
                      },
                      'target': {
                        'type': 'string',
                        'enum': [
                          'listener',
                          'third_person',
                          'user',
                          'none',
                          'unknown'
                        ]
                      },
                      'omitted_subject': {'type': 'string'},
                      'tense': {
                        'type': 'string',
                        'enum': [
                          'past',
                          'present',
                          'future',
                          'ongoing',
                          'mixed',
                          'unknown'
                        ]
                      },
                      'relationship': {
                        'type': 'string',
                        'enum': [
                          'friend',
                          'coworker',
                          'workplace_superior',
                          'family',
                          'teacher',
                          'customer',
                          'stranger',
                          'unknown'
                        ]
                      },
                      'confidence': {
                        'type': 'number',
                        'minimum': 0,
                        'maximum': 1
                      },
                      'ambiguity_reason': {'type': 'string'}
                    },
                    'required': [
                      'actor',
                      'target',
                      'omitted_subject',
                      'tense',
                      'relationship',
                      'confidence',
                      'ambiguity_reason'
                    ]
                  }
                }
              },
              'messages': [
                {
                  'role': 'system',
                  'content': '''You are a narrow Korean discourse context judge.
Return only the requested structured fields. Do not translate, correct grammar, answer the user, provide alternatives, or reveal reasoning.
The speaker is the user, but the action actor may be the listener or a third person.
Infer omitted subjects from Korean grammar and discourse only. Do not force user/listener when evidence is weak.
Record a relationship only when explicit or strongly signaled; otherwise use unknown.
Use ambiguity_reason only for a short reason when uncertain; otherwise return an empty string.'''
                },
                {
                  'role': 'user',
                  'content': 'Mode: $mode\nFirst Korean utterance: $transcript'
                }
              ]
            }),
          )
          .timeout(kFirstUtteranceJudgeTimeout);
      if (generation != _generation) return null;
      if (response.statusCode != 200) {
        requestFailed = true;
        onLog?.call('failure',
            'reason=http_status elapsed_ms=${stopwatch.elapsedMilliseconds}');
        return null;
      }
      final envelope = jsonDecode(utf8.decode(response.bodyBytes));
      final content = envelope['choices']?[0]?['message']?['content'];
      if (content is! String) {
        requestFailed = true;
        onLog?.call('failure',
            'reason=missing_content elapsed_ms=${stopwatch.elapsedMilliseconds}');
        return null;
      }
      final parsed = FirstUtteranceContext.fromJson(jsonDecode(content));
      if (parsed == null) {
        requestFailed = true;
        onLog?.call('failure',
            'reason=invalid_schema elapsed_ms=${stopwatch.elapsedMilliseconds}');
        return null;
      }
      requestCompleted = true;
      onLog?.call('success',
          'elapsed_ms=${stopwatch.elapsedMilliseconds} confidence_band=${parsed.confidenceBand}');
      return parsed;
    } on TimeoutException {
      if (generation == _generation) {
        requestFailed = true;
        onLog?.call('timeout', 'elapsed_ms=${stopwatch.elapsedMilliseconds}');
      }
      return null;
    } catch (_) {
      if (generation == _generation) {
        requestFailed = true;
        onLog?.call('failure',
            'reason=request_or_parse elapsed_ms=${stopwatch.elapsedMilliseconds}');
      }
      return null;
    } finally {
      stopwatch.stop();
      if (identical(_activeClient, requestClient)) {
        _activeClient = null;
        _ownsActiveClient = false;
      }
      if (ownsClient) requestClient.close();
    }
  }

  Future<FirstTurnTranslationReview?> reviewTranslationDraft({
    required String apiKey,
    required String sourceText,
    required String realtimeDraft,
    required String targetLanguage,
    FirstUtteranceContext? context,
    FirstUtteranceJudgeLogger? onLog,
    http.Client? client,
  }) async {
    final draft = realtimeDraft.trim();
    if (draft.isEmpty) {
      onLog?.call('fallback', 'reason=empty');
      return null;
    }

    final generation = ++_reviewGeneration;
    final requestClient = client ?? http.Client();
    final ownsClient = client == null;
    _activeReviewClient = requestClient;
    _ownsActiveReviewClient = ownsClient;
    _activeReviewLogger = onLog;
    onLog?.call('review_start', '');
    try {
      final contextPayload = context == null
          ? null
          : <String, dynamic>{
              'actor': context.actor,
              'target': context.target,
              'omitted_subject': context.omittedSubject,
              'tense': context.tense,
              'relationship': context.relationship,
              'confidence': context.confidence,
              'ambiguity_reason': context.ambiguityReason,
            };
      final response = await requestClient
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'model': kFirstUtteranceJudgeModel,
              'temperature': 0,
              'max_completion_tokens':
                  kFirstTurnTranslationReviewMaxOutputTokens,
              'response_format': {
                'type': 'json_schema',
                'json_schema': {
                  'name': 'first_turn_translation_review',
                  'strict': true,
                  'schema': {
                    'type': 'object',
                    'additionalProperties': false,
                    'properties': {
                      'verdict': {
                        'type': 'string',
                        'enum': [
                          'accepted',
                          'polished',
                          'retranslated'
                        ]
                      },
                      'final_text': {'type': 'string'}
                    },
                    'required': ['verdict', 'final_text']
                  }
                }
              },
              'messages': [
                {
                  'role': 'system',
                  'content': '''You are the final quality reviewer for the first user utterance in a live conversation.
The Deepgram source utterance is the authority. The Realtime draft is only a candidate translation.

Evaluate BOTH semantic fidelity and whether the result sounds natural in real spoken $targetLanguage.

First verify meaning:
- who the speaker is and who is being addressed
- subject, object, recipient, and named-person relationships
- omitted Korean subjects, objects, and pronouns, using the supplied first-utterance context when available
- tense, aspect, modality, question versus statement, intent, and positive versus negative meaning
- politeness, speech register, and the relationship between speakers
- whether any important meaning was omitted or any new meaning was invented

Then verify conversational naturalness:
- reject literal Korean-to-English calques, awkward collocations, unnatural prepositions, and textbook-like wording
- prefer concise, idiomatic language a native speaker would actually say in this situation
- preserve the source tone and level of formality
- do not embellish, over-explain, or make the sentence longer than needed

Choose exactly one verdict:
- "accepted": Meaning and conversational naturalness are both sufficient. Return the Realtime draft EXACTLY unchanged.
- "polished": The meaning is faithful, but the wording is literal, stiff, or unnatural in conversation. Make the smallest rewrite needed for idiomatic spoken $targetLanguage.
- "retranslated": The draft gets the subject, target, referent, tense, intent, question form, polarity/negation, or another material meaning wrong. Translate again from the source, using the supplied context.

Example:
Source: 오늘은 회사에서 좀 힘들었어요.
Draft: Today was a little hard at the company.
Correct result: {"verdict":"polished","final_text":"I had a bit of a rough day at work today."}

Never add new information or output explanations, alternatives, notes, or commentary.
Never create, delete, rename, or alter an existing control tag such as [EVAPORATE], [CORRECTION], [MISHEARD], [DISSATISFIED], or [CLARIFY].
Return only the requested JSON object.'''
                },
                {
                  'role': 'user',
                  'content': jsonEncode({
                    'source_text': sourceText,
                    'realtime_draft': draft,
                    'target_language': targetLanguage,
                    'first_utterance_context': contextPayload,
                  })
                }
              ]
            }),
          )
          .timeout(kFirstTurnTranslationReviewTimeout);
      if (generation != _reviewGeneration) return null;
      if (response.statusCode != 200) {
        onLog?.call('fallback', 'reason=http');
        return null;
      }

      dynamic envelope;
      dynamic content;
      try {
        envelope = jsonDecode(utf8.decode(response.bodyBytes));
        content = envelope['choices']?[0]?['message']?['content'];
        if (content is! String) throw const FormatException();
      } catch (_) {
        onLog?.call('fallback', 'reason=parse');
        return null;
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(content);
      } catch (_) {
        onLog?.call('fallback', 'reason=parse');
        return null;
      }
      final review = FirstTurnTranslationReview.fromJson(decoded);
      if (review == null) {
        final rawFinalText =
            decoded is Map ? decoded['final_text']?.toString().trim() : null;
        onLog?.call(
            'fallback', 'reason=${rawFinalText?.isEmpty == true ? 'empty' : 'parse'}');
        return null;
      }
      onLog?.call('review_done', 'verdict=${review.verdict.name}');
      return review;
    } on TimeoutException {
      if (generation == _reviewGeneration) {
        onLog?.call('fallback', 'reason=timeout');
      }
      return null;
    } catch (_) {
      if (generation == _reviewGeneration) {
        onLog?.call('fallback', 'reason=http');
      }
      return null;
    } finally {
      if (identical(_activeReviewClient, requestClient)) {
        _activeReviewClient = null;
        _ownsActiveReviewClient = false;
        _activeReviewLogger = null;
      }
      if (ownsClient) requestClient.close();
    }
  }

  void cancelTranslationReview() {
    final logger = _activeReviewLogger;
    final hadActiveReview = _activeReviewClient != null;
    _reviewGeneration++;
    if (_ownsActiveReviewClient) _activeReviewClient?.close();
    _activeReviewClient = null;
    _ownsActiveReviewClient = false;
    _activeReviewLogger = null;
    if (hadActiveReview) logger?.call('fallback', 'reason=cancelled');
  }

  /// Adopts a result that was requested speculatively during the transcript
  /// commit window. The live session remains untouched until the utterance has
  /// passed its final STT-confidence and ghost-word checks.
  void adoptPrefetchedResult(
    FirstUtteranceContext? context, {
    required bool requestFailed,
  }) {
    if (firstNormalUtteranceSeen || requestStarted) return;
    firstNormalUtteranceSeen = true;
    requestStarted = true;
    this.requestFailed = requestFailed || context == null;
    requestCompleted = context != null && !this.requestFailed;
  }

  void markDelivered(FirstUtteranceContext context) {
    if (requestCompleted && !requestFailed && !resultDelivered) {
      resultDelivered = true;
    }
  }

  void cancel() {
    cancelTranslationReview();
    if (requestStarted && !requestCompleted) requestFailed = true;
    _generation++;
    if (_ownsActiveClient) _activeClient?.close();
    _activeClient = null;
    _ownsActiveClient = false;
  }

  void reset() {
    cancel();
    firstNormalUtteranceSeen = false;
    requestStarted = false;
    requestCompleted = false;
    requestFailed = false;
    resultDelivered = false;
  }

  static _FirstUtteranceEligibility _classify(String transcript) {
    final text = transcript.trim();
    final compact = text.toLowerCase().replaceAll(RegExp(r'[\s.!?,~…。！？]'), '');
    if (compact.isEmpty ||
        RegExp(r'^\[[^\]]+\]$').hasMatch(text) ||
        text.startsWith('__') ||
        text.startsWith('<system')) {
      return const _FirstUtteranceEligibility(false, false);
    }
    const excluded = {
      '네',
      '아니요',
      '아니',
      '응',
      '음',
      '어',
      '아',
      '오',
      '와',
      '안녕',
      '안녕하세요',
      '반가워요',
      '반갑습니다',
      '감사합니다',
      '고마워요'
    };
    if (excluded.contains(compact)) {
      return const _FirstUtteranceEligibility(false, false);
    }
    final hasHangul = RegExp(r'[가-힣]').hasMatch(text);
    if (!hasHangul) {
      // A meaningful non-Korean first utterance consumes the slot but needs no
      // Korean context judgment.
      return _FirstUtteranceEligibility(compact.length > 2, false);
    }
    if (compact.runes.length <= 1) {
      return const _FirstUtteranceEligibility(false, false);
    }

    // 문맥 판정의 실익이 큰 경우만 GPT-4.1을 사용한다. 한국어 평서문의 생략
    // 주어는 보통 화자 자신이라 Realtime 번역만으로 충분하고, 첫 질문에서
    // 화자/청자 중 누가 행동 주체인지 불분명할 때만 별도 판정을 요청한다.
    //
    // 명시적 인칭/참여자가 있으면 질문이어도 로컬에서 안전하게 bypass한다.
    final hasExplicitActor = RegExp(
      r'(?:^|[\s,])(?:나|나는|난|내가|저|저는|전|제가|우리|우리는|우린|우리가|'
      r'너|너는|넌|네가|당신|당신은|당신이|그|그는|그가|그녀|그녀는|그녀가|'
      r'엄마|아빠|형|누나|언니|오빠|동생|친구|상사|팀장|선생님|남편|아내|'
      r'아이|고객)(?:은|는|이|가)?(?:[\s,]|$)',
    ).hasMatch(text);
    final hasQuestionWord =
        RegExp(r'(누구|뭐|무엇|어디|언제|왜|어떻게|어느|몇)').hasMatch(text);
    final hasQuestionEnding = RegExp(
      r'(?:니|냐|나요|까요|을까|ㄹ까|습니까)\s*[?？~.!]*$',
    ).hasMatch(text);
    final isQuestionLike = text.contains('?') ||
        text.contains('？') ||
        hasQuestionWord ||
        hasQuestionEnding;

    return _FirstUtteranceEligibility(
      true,
      isQuestionLike && !hasExplicitActor,
    );
  }
}

class _FirstUtteranceEligibility {
  const _FirstUtteranceEligibility(this.isNormal, this.shouldJudge);

  final bool isNormal;
  final bool shouldJudge;
}
