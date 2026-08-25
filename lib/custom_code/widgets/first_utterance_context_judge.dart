import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const String kFirstUtteranceJudgeModel = 'gpt-4.1';
const int kFirstUtteranceJudgeMaxOutputTokens = 160;
const Duration kFirstUtteranceJudgeTimeout = Duration(milliseconds: 2500);

typedef FirstUtteranceJudgeLogger = void Function(String event, String details);

enum FirstUtteranceRoute { excluded, judge, bypass }

const Duration kDuplicateFinalTranscriptWindow = Duration(milliseconds: 250);

/// 언어와 무관한 내부 되묻기 제어 신호. 모델 출력의 첫 줄에서만 판정하고,
/// 화면·TTS·히스토리에는 반드시 제거한 실제 질문만 전달한다.
const String kHeardConfirmSignal = '[HEARD_CONFIRM]';

bool hasHeardConfirmSignal(String text) =>
    text.trimLeft().startsWith(kHeardConfirmSignal);

bool isHeardConfirmSignalPrefix(String text) {
  final prefix = text.trimLeft();
  return prefix.isNotEmpty && kHeardConfirmSignal.startsWith(prefix);
}

String stripHeardConfirmSignal(String text) {
  final trimmed = text.trimLeft();
  if (!trimmed.startsWith(kHeardConfirmSignal)) return text.trim();
  return trimmed
      .substring(kHeardConfirmSignal.length)
      .replaceFirst(RegExp(r'^\s*'), '')
      .trim();
}

String buildHeardConfirmOutputRule(String originLanguage) {
  final language = resolveNativeLanguageName(originLanguage);
  return '''Output exactly two lines:
$kHeardConfirmSignal
<one short, specific confirmation question in $language>
The first line is an internal control signal. Put the complete user-facing question on the second line.''';
}

/// 모델 결과를 쓸 수 없는 오류 경로용 짧은 재시도 문장.
/// 로비가 제공하는 12개 ORIGIN만 관리하며 알 수 없는 값은 English로 안전 폴백한다.
String originRetryLine(String originLanguage) {
  switch (resolveNativeLanguageName(originLanguage).toLowerCase()) {
    case 'korean':
      return '제가 잘못 들은 것 같아요. 다시 말씀해 주세요.';
    case 'japanese':
      return '聞き間違えたかもしれません。もう一度お願いします。';
    case 'chinese':
      return '我可能听错了，请再说一遍。';
    case 'spanish':
      return 'Puede que haya oído mal. Repítalo, por favor.';
    case 'french':
      return 'J’ai peut-être mal entendu. Pouvez-vous répéter ?';
    case 'german':
      return 'Vielleicht habe ich Sie falsch verstanden. Bitte sagen Sie es noch einmal.';
    case 'hindi':
      return 'शायद मैंने गलत सुना। कृपया फिर से कहें।';
    case 'russian':
      return 'Возможно, я неправильно расслышал. Пожалуйста, повторите.';
    case 'portuguese':
      return 'Talvez eu tenha ouvido errado. Por favor, diga novamente.';
    case 'italian':
      return 'Forse ho capito male. Per favore, ripeta.';
    case 'dutch':
      return 'Misschien heb ik u verkeerd verstaan. Zeg het alstublieft nog eens.';
    case 'english':
    default:
      return 'I may have misheard you. Please say that again.';
  }
}

/// 👂 [HEARD-CONFIRM] 되묻기에 대한 유저의 답이 셋 중 무엇인가.
enum HeardConfirmReply {
  /// "네" — 제대로 들은 게 맞다. 보류해 둔 발화를 그대로 재개한다.
  affirmed,

  /// "아니요" — 틀렸는데 고쳐 주지는 않았다. 보류 발화를 버리고 다시 듣는다.
  denied,

  /// 내용을 담아 다시 말했다. 이것을 새 발화로 본다.
  corrected,
}

const Set<String> _kHeardConfirmAffirmatives = <String>{
  '네',
  '예',
  '응',
  '어',
  '맞아',
  '맞아요',
  '맞습니다',
  '그래',
  '그래요',
  'yes',
  'yeah',
  'yep',
  'right',
  'correct',
};

const Set<String> _kHeardConfirmBareNegatives = <String>{
  '아니',
  '아니요',
  '아뇨',
  '아닙니다',
  '틀려',
  '틀렸어',
  '틀렸어요',
  'no',
  'nope',
  'wrong',
};

/// 되묻기에 대한 답을 셋으로 가른다.
///
/// **모드마다 따로 두면 반드시 어긋난다.** 서클톡과 시나리오톡이 같은 표를
/// 보도록 여기 한 곳에만 둔다.
HeardConfirmReply classifyHeardConfirmReply(String transcript) {
  final reply =
      transcript.trim().toLowerCase().replaceAll(RegExp(r'[\s.!?~,]'), '');
  if (_kHeardConfirmAffirmatives.contains(reply)) {
    return HeardConfirmReply.affirmed;
  }
  if (_kHeardConfirmBareNegatives.contains(reply)) {
    return HeardConfirmReply.denied;
  }
  return HeardConfirmReply.corrected;
}

/// 👂 [ASK-BACK] 되묻기로 대화에 반영되지 않은 유저 말풍선에 붙는 한 줄.
///
/// 말풍선 자체는 화면에 남긴다 — 자기가 한 말이 흔적도 없이 사라지면 유저는
/// 무엇을 고쳐 말해야 할지 알 수 없다. 이 문구는 "적히긴 했지만 대화에는
/// 안 들어갔다"를 알려 준다.
String unheardBubbleHintLine(String originLanguage) {
  switch (resolveNativeLanguageName(originLanguage).toLowerCase()) {
    case 'korean':
      return '이렇게 들었어요 — 다시 말씀해 주세요';
    case 'japanese':
      return 'こう聞こえました — もう一度お願いします';
    case 'chinese':
      return '我听成了这样 — 请再说一遍';
    case 'spanish':
      return 'Esto es lo que oí — dígalo otra vez, por favor';
    case 'french':
      return 'Voici ce que j’ai entendu — répétez, s’il vous plaît';
    case 'german':
      return 'So habe ich es verstanden — bitte noch einmal';
    case 'hindi':
      return 'मैंने ऐसा सुना — कृपया फिर से कहें';
    case 'russian':
      return 'Вот что я услышал — повторите, пожалуйста';
    case 'portuguese':
      return 'Foi isto que ouvi — diga novamente, por favor';
    case 'italian':
      return 'Ho sentito così — ripeta, per favore';
    case 'dutch':
      return 'Dit hoorde ik — zeg het alstublieft nog eens';
    case 'english':
    default:
      return 'This is what I heard — please say it again';
  }
}

/// Step Expand의 첫 씨앗이 불명확할 때 쓰는 짧은 유도 질문.
/// 같은 문구 표를 ORIGIN 음성과 TARGET 화면 폴백에 함께 사용한다.
String localizedSeedGuidanceLine(String language) {
  switch (resolveNativeLanguageName(language).toLowerCase()) {
    case 'korean':
      return '어떤 구체적인 순간을 말해 볼까요?';
    case 'japanese':
      return 'どんな具体的な出来事について話したいですか？';
    case 'chinese':
      return '您想描述哪个具体的时刻？';
    case 'spanish':
      return '¿Qué momento concreto le gustaría describir?';
    case 'french':
      return 'Quel moment précis aimeriez-vous décrire ?';
    case 'german':
      return 'Welchen konkreten Moment möchten Sie beschreiben?';
    case 'hindi':
      return 'आप किस खास पल का वर्णन करना चाहेंगे?';
    case 'russian':
      return 'Какой конкретный момент вы хотели бы описать?';
    case 'portuguese':
      return 'Que momento específico você gostaria de descrever?';
    case 'italian':
      return 'Quale momento specifico vorrebbe descrivere?';
    case 'dutch':
      return 'Welk specifiek moment wilt u beschrijven?';
    case 'english':
    default:
      return 'What specific moment would you like to describe?';
  }
}

/// 로비 ORIGIN과 실제 발화 언어가 달라 이 세션만 ORIGIN을 갈아 끼웠을 때 뜨는
/// 안내 말풍선. **감지된 언어로** 적는다 — 로비값으로 적으면 정작 읽어야 할
/// 사람이 못 읽는다.
///
/// 이 전환은 방을 나가면 사라지므로, 다음부터는 로비에서 직접 맞춰 달라고
/// 부탁하는 것이 이 문구의 전부다.
String originLanguageSwitchedNoticeLine(String detectedLanguage) {
  switch (resolveNativeLanguageName(detectedLanguage).toLowerCase()) {
    case 'korean':
      return '한국어로 말씀하시는 것 같아 이번 대화는 한국어로 진행할게요. '
          '다음에는 로비에서 대화 언어를 한국어로 맞춰 주세요.';
    case 'japanese':
      return '日本語でお話しのようなので、今回の会話は日本語で進めます。'
          '次回はロビーで会話の言語を日本語に設定してください。';
    case 'chinese':
      return '看起来您在说中文，本次对话将使用中文。'
          '下次请在大厅将对话语言设置为中文。';
    case 'spanish':
      return 'Parece que habla español, así que esta conversación será en español. '
          'La próxima vez, seleccione español como idioma de conversación en el lobby.';
    case 'french':
      return 'Vous semblez parler français, cette conversation se fera donc en français. '
          'La prochaine fois, choisissez le français comme langue de conversation dans le lobby.';
    case 'german':
      return 'Sie sprechen offenbar Deutsch, daher läuft dieses Gespräch auf Deutsch. '
          'Bitte stellen Sie die Gesprächssprache beim nächsten Mal in der Lobby auf Deutsch.';
    case 'hindi':
      return 'लगता है आप हिंदी बोल रहे हैं, इसलिए यह बातचीत हिंदी में होगी। '
          'अगली बार लॉबी में बातचीत की भाषा हिंदी चुनें।';
    case 'russian':
      return 'Похоже, вы говорите по-русски, поэтому этот разговор будет на русском. '
          'В следующий раз выберите русский язык общения в лобби.';
    case 'portuguese':
      return 'Parece que você fala português, então esta conversa será em português. '
          'Da próxima vez, selecione português como idioma de conversa no lobby.';
    case 'italian':
      return 'Sembra che parli italiano, quindi questa conversazione sarà in italiano. '
          'La prossima volta seleziona l\'italiano come lingua di conversazione nella lobby.';
    case 'dutch':
      return 'U lijkt Nederlands te spreken, dus dit gesprek gaat in het Nederlands verder. '
          'Stel de gesprekstaal de volgende keer in de lobby in op Nederlands.';
    case 'english':
    default:
      return 'You seem to be speaking English, so this conversation will continue in English. '
          'Next time, please set your chat language to English in the lobby.';
  }
}

/// Anyone 자유대화 답변 전 내부 숙고 지시.
/// 응답이 1초 정도 느려지더라도 어중간한 답 대신 구체적인 답과 질문을 뽑는다.
const String kAnyoneDeliberateReplyPolicy = '''[THINK TWICE BEFORE YOU SPEAK]
- Take an extra beat. A slightly slower reply that lands is far better than a fast, vague one.
- Silently draft two different replies, compare them, then say only the better one.
- Throw away any draft that is hedging or generic — anything that could have been said to anyone by anyone ("That sounds tough.", "I see.", "How do you feel about that?"). Commit to a real reaction instead.
- Keep the draft that reacts to the specific thing the user just said, in the voice of the specific person you are.
- Your question must earn its place: ask about the one concrete detail you most want to know next — what happened, what they did, what the other person said back. One sharp, specific question. Never a vague or generic one.
- Never show your drafts, your comparison, or any reasoning. Output only the final reply.''';

/// 3모드 공통 존댓말 규칙. AI가 내는 한국어는 글이든 소리든 전부 존댓말이다.
/// 모델은 유저 말투를 따라가려는 성질이 강해서, 유저가 반말로 말하면 몇 턴
/// 만에 같이 반말로 흘렀다(실기기 확인: "어떤 앱인지 궁금해."). 그래서 유저를
/// 따라가지 말라고 못을 박는다. 유저 자신의 문장은 이 규칙 밖이다 — 유저가
/// 만든 문장은 유저 말투 그대로 둔다.
const String kKoreanPoliteSpeechPolicy =
    '''[ALWAYS SPEAK KOREAN 존댓말 — NEVER MIRROR CASUAL SPEECH]
- Every Korean line you produce, on screen and in speech, must be 해요체 존댓말.
- End sentences politely: -요 / -세요 / -네요 / -죠 / -까요. Never -어/-아/-야/-지/-니/-거야/-겠어.
- The user may speak 반말. Do NOT match it. Stay 존댓말 no matter how they talk, and never comment on their speech level.
- Keep it warm and spoken, not stiff. Avoid formal -습니다/-습니까 written style.''';

/// 3모드(듀오·써클톡·시나리오톡) 공통 응답 길이 규칙.
/// 유저가 짧게 물으면 짧게 답한다. 가르치듯 길게 적는 것이 가장 흔한 실패라
/// 한 곳에서 관리하고 세 모드의 Realtime 지시문이 모두 이 상수를 가져다 쓴다.
const String kSpokenReplyLengthPolicy =
    '''[MATCH THE USER'S LENGTH — TALK, DON'T TEACH]
- Mirror the length of the user's turn. A short question gets a short answer: one sentence, sometimes just a few words.
- A one-line question never earns a paragraph. Answer what was actually asked, then stop.
- Do not add background, reasons, alternatives, tips, or caveats the user did not ask for.
- Never lecture, list, enumerate, or walk through steps. This is spoken conversation, not a written guide.
- Do not restate or summarize the user's words before answering.
- Go longer ONLY when the user explicitly asks for detail (자세히, 더 설명해줘, 왜 그런지, 예를 들어).
  Then give exactly the depth they asked for and nothing beyond it.''';

/// 로비에서 고른 원어 이름을 프롬프트용으로 정규화한다. 비어 있으면 Korean.
String resolveNativeLanguageName(String nativeLang) {
  final name = nativeLang.trim();
  return name.isEmpty ? 'Korean' : name;
}

/// 3모드 대화방 공통 출력 언어 규칙.
/// 대화방은 유저의 원어로만 말하고 적는다. 타겟 언어 연습은 History에서만
/// 일어난다 — 이게 StealthVox의 성격이라, 외국 유저도 대화방에서는 자기
/// 나라 말로 보고 듣는다.
String buildNativeOutputLanguagePolicy(String nativeLang) {
  final lang = resolveNativeLanguageName(nativeLang);
  return '''OUTPUT LANGUAGE: Natural spoken $lang only.
- The user's own language is $lang. Treat every incoming text as their actual $lang utterance.
- Speak and write $lang only. Never switch languages, never translate, never place a second language beside it.
- Do NOT use the user's target practice language in this room. Target-language practice happens later in History, never here.''';
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

class FirstUtteranceContextJudgeSession {
  bool firstNormalUtteranceSeen = false;
  bool requestStarted = false;
  bool requestCompleted = false;
  bool requestFailed = false;
  bool resultDelivered = false;

  http.Client? _activeClient;
  bool _ownsActiveClient = false;
  int _generation = 0;

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

  /// 네트워크 문맥 판정 없이 "첫 정상 발화를 봤다"는 상태만 로컬로 확정한다.
  /// GPT-4.1을 쓰지 않는 모드(Anyone)가 [judgeIfNeeded] 대신 호출한다.
  /// 판정 조건은 [judgeIfNeeded]의 로컬 검열부와 동일하다.
  void consumeFirstNormalUtterance(
    String transcript, {
    double? sttConfidence,
    FirstUtteranceJudgeLogger? onLog,
  }) {
    if (firstNormalUtteranceSeen) return;
    if (!_classify(transcript).isNormal) {
      onLog?.call('skip', 'reason=excluded');
      return;
    }
    if (sttConfidence != null && sttConfidence < 0.50) {
      onLog?.call('skip', 'reason=low_stt_confidence');
      return;
    }
    firstNormalUtteranceSeen = true;
    onLog?.call('first_normal_utterance', 'judge=off');
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
