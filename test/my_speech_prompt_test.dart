import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/ai_style.dart';
import 'package:stealth_vox/custom_code/services/speech_reconstruction.dart';

/// MY SPEECH의 정의를 고정한다.
///
/// My Speech는 **대화 요약이 아니다.** 대화 전체에서 유저가 실제로 표현한
/// 의미·생각·사실·감정·입장만 모아, 유저 한 사람이 처음부터 끝까지 하나의
/// 완결된 발화로 말했다면 어땠을지를 만드는 것이다.
///
/// 여기서 지키는 것은 그 경계다 — 상대방 말이 새어 들어오는 것, 없던 사실이
/// 생기는 것, 그리고 다음 단계인 Native English와 하는 일이 겹치는 것.
void main() {
  final prompt = buildMySpeechInstructions(targetLang: 'English');

  group('요약이 아니라 재구성이다', () {
    test('요약하지 말라고 못 박는다', () {
      expect(
          prompt, contains('Your job is NOT to summarize the conversation.'));
      expect(
        prompt,
        contains("reconstruct what the USER themselves expressed"),
      );
      expect(prompt, contains('one complete turn'));
    });

    test('시간 순서대로 이어 붙이지 않는다', () {
      expect(
        prompt,
        contains(
            "Do not simply join the user's sentences in chronological order."),
      );
      expect(prompt, contains('one coherent spoken thought'));
    });

    test('중복 제거·순서 정리·대명사 손질은 허락한다', () {
      for (final allowed in <String>[
        'remove repetition',
        'merge overlapping ideas',
        "reorder the user's own points for clarity",
        'repair references and pronouns',
        'make transitions natural',
        'remove conversational filler that adds no meaning',
      ]) {
        expect(prompt, contains(allowed), reason: allowed);
      }
      expect(prompt, contains('But never change what the user meant.'));
    });
  });

  group('유저 의미만 쓴다', () {
    test('상대가 말했다는 이유만으로 가져오지 않는다', () {
      expect(
        prompt,
        contains('Use only meaning that the USER actually expressed.'),
      );
      expect(
        prompt,
        contains(
            'Never import an idea merely because the other speaker said it.'),
      );
      expect(
        prompt,
        contains(
            'only if the USER later clearly adopted or expressed it themselves'),
      );
    });

    test('없던 사실·감정·결론을 만들지 않는다', () {
      expect(
        prompt,
        contains(
            'Never add a fact, an opinion, a reason, an emotion, a motivation, a decision, a plan, or a conclusion that the user did not express.'),
      );
      expect(prompt, contains('Do not turn uncertainty into certainty.'));
      expect(prompt, contains('Do not turn a possibility into a decision.'));
      expect(
        prompt,
        contains("Do not turn another speaker's idea into the user's idea."),
      );
    });

    test('입장의 세기를 바꾸지 않는다', () {
      expect(
        prompt,
        contains(
            "Never make the user's position stronger, weaker, more positive, or more negative than it actually was."),
      );
    });
  });

  group('한 문장이 아니라 한 발화다', () {
    test('여러 문장이어도 된다고 적혀 있다', () {
      expect(prompt, contains('It may be several sentences.'));
      expect(
        prompt,
        contains('Do not force it into one grammatical sentence.'),
      );
      expect(prompt, contains('one complete speech, not one sentence'));
    });

    test('설명·라벨·따옴표 없이 발화만 낸다', () {
      expect(prompt, contains('Output only My Speech.'));
      expect(
        prompt,
        contains(
            'Do not add headings, quotation marks, commentary, or analysis.'),
      );
    });
  });

  group('로비 AI STYLE은 어휘까지만 닿는다', () {
    test('Native를 골라도 사고 배열을 다시 짜지 않는다', () {
      final native =
          buildMySpeechInstructions(targetLang: 'English', userLabel: '');
      // 로비 스타일 블록 자체는 붙지만, wording 도달 범위로 묶여 있어야 한다.
      expect(native, contains('[ENGLISH STYLE'));
      expect(native, contains('Style reaches the WORDING only.'));
      expect(native, contains('Never reorganise the thought.'));
    });

    test('사고 배열 재구성은 Native English 쪽에만 있다', () {
      // 두 단계가 같은 일을 하면 나란히 놓을 이유가 사라진다.
      final nativeEnglish = buildNativeEnglishSpeechInstructions();
      expect(nativeEnglish, contains('[THINK IN ENGLISH]'));
      expect(prompt, isNot(contains('[THINK IN ENGLISH]')));
    });
  });

  group('타겟 언어를 따른다', () {
    test('영어가 아니면 그 언어로 적으라고 지시한다', () {
      final japanese = buildMySpeechInstructions(targetLang: 'Japanese');
      expect(japanese, contains('natural spoken Japanese'));
      expect(japanese, contains('Write it in Japanese only.'));
      // 영어 타겟이 아니면 로비 스타일 블록은 붙지 않는다.
      expect(japanese, isNot(contains('[ENGLISH STYLE')));
    });
  });

  group('참가자 라벨', () {
    test('이름을 주면 누가 USER인지 알려 준다', () {
      final named = buildMySpeechInstructions(
        targetLang: 'English',
        userLabel: 'Minsu',
        partnerLabel: 'Mina',
      );
      expect(named, contains('USER is Minsu.'));
      expect(named, contains('OTHER is Mina.'));
    });

    test('상황은 유저 줄이 뒷받침할 때만 쓴다', () {
      final withSituation = buildMySpeechInstructions(
        targetLang: 'English',
        situation: 'a job interview',
      );
      expect(withSituation, contains('Situation: a job interview.'));
      expect(
          withSituation, contains('Use it only if the USER lines support it.'));
    });

    test('상황이 없으면 그 줄 자체가 없다', () {
      expect(prompt, isNot(contains('Situation:')));
    });
  });

  group('대화록 만들기', () {
    test('유저 줄과 상대 줄이 라벨로 갈린다', () {
      final transcript = formatSpeechTranscript(const <SpeechTranscriptTurn>[
        SpeechTranscriptTurn(isUser: true, text: '회사 그만두고 싶어.'),
        SpeechTranscriptTurn(isUser: false, text: '무슨 일 있었어요?'),
        SpeechTranscriptTurn(isUser: true, text: '매일 똑같은 일이 지쳐.'),
      ]);
      expect(
          transcript,
          'USER: 회사 그만두고 싶어.\n'
          'OTHER: 무슨 일 있었어요?\n'
          'USER: 매일 똑같은 일이 지쳐.');
    });

    test('빈 줄은 버린다', () {
      final transcript = formatSpeechTranscript(const <SpeechTranscriptTurn>[
        SpeechTranscriptTurn(isUser: true, text: '   '),
        SpeechTranscriptTurn(isUser: false, text: '안녕하세요.'),
      ]);
      expect(transcript, 'OTHER: 안녕하세요.');
    });

    test('유저 줄이 하나도 없으면 My Speech는 성립하지 않는다', () {
      expect(
        hasUserTurn(const <SpeechTranscriptTurn>[
          SpeechTranscriptTurn(isUser: false, text: '안녕하세요.'),
        ]),
        isFalse,
      );
      expect(
        hasUserTurn(const <SpeechTranscriptTurn>[
          SpeechTranscriptTurn(isUser: true, text: '  '),
        ]),
        isFalse,
      );
      expect(
        hasUserTurn(const <SpeechTranscriptTurn>[
          SpeechTranscriptTurn(isUser: true, text: '그만두고 싶어.'),
        ]),
        isTrue,
      );
    });
  });

  group('모델이 붙인 껍데기를 걷어낸다', () {
    test('머리표를 지운다', () {
      expect(sanitizeSpeechOutput('My Speech: I want to leave my job.'),
          'I want to leave my job.');
      expect(
          sanitizeSpeechOutput('Native English: I am tired.'), 'I am tired.');
    });

    test('따옴표를 벗긴다', () {
      expect(sanitizeSpeechOutput('"I want to leave."'), 'I want to leave.');
      expect(sanitizeSpeechOutput('“I want to leave.”'), 'I want to leave.');
    });

    test('본문 안의 따옴표는 건드리지 않는다', () {
      expect(
        sanitizeSpeechOutput('He said "no" and I left.'),
        'He said "no" and I left.',
      );
    });
  });

  group('실패는 실패로 남는다', () {
    test('빈 결과는 쓸 수 없다', () {
      const failed = SpeechBuildResult.failed(SpeechBuildFailure.httpError);
      expect(failed.isUsable, isFalse);
      expect(failed.text, isEmpty);
      expect(const SpeechBuildResult.ok('   ').isUsable, isFalse);
      expect(const SpeechBuildResult.ok('I quit.').isUsable, isTrue);
    });

    test('응답을 못 읽으면 빈 문자열이다 — 아무 문장이나 만들지 않는다', () {
      expect(MySpeechBuilder.parseResponse('not json'), isEmpty);
      expect(MySpeechBuilder.parseResponse('{"choices":[]}'), isEmpty);
      expect(
        MySpeechBuilder.parseResponse(
            '{"choices":[{"message":{"content":"  I quit.  "}}]}'),
        'I quit.',
      );
    });

    test('API 키가 없으면 네트워크를 타지 않고 실패한다', () async {
      final result = await MySpeechBuilder.build(
        apiKey: '',
        turns: const <SpeechTranscriptTurn>[
          SpeechTranscriptTurn(isUser: true, text: '그만두고 싶어.'),
        ],
        targetLang: 'English',
      );
      expect(result.failure, SpeechBuildFailure.apiKeyMissing);
    });

    test('유저 줄이 없으면 상대 말로 때우지 않고 실패한다', () async {
      final result = await MySpeechBuilder.build(
        apiKey: 'sk-test',
        turns: const <SpeechTranscriptTurn>[
          SpeechTranscriptTurn(isUser: false, text: '안녕하세요.'),
        ],
        targetLang: 'English',
      );
      expect(result.failure, SpeechBuildFailure.emptyTranscript);
    });

    test('Native English는 My Speech가 없으면 만들지 않는다', () async {
      final result = await NativeEnglishSpeechBuilder.build(
        apiKey: 'sk-test',
        mySpeech: '   ',
      );
      expect(result.failure, SpeechBuildFailure.emptyTranscript);
    });
  });
}
