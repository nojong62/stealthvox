import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/ai_style.dart';
import 'package:stealth_vox/custom_code/services/speech_reconstruction.dart';

/// ESSAY(저장 칸 `my_speech`)의 정의를 고정한다.
///
/// 2026-10-15 실장님 지시: **대화 내용을 벗어나지 않고, 유저 개인이 1인칭으로
/// 말하듯** 쓴다. 대화에 없던 이유·예시·생각을 붙이던 확장 규칙은 사라졌다.
/// 길이는 대화 길이를 따른다.
void main() {
  final prompt = buildMySpeechInstructions(targetLang: 'English');

  group('유저 1인칭으로 대화를 다시 들려준다', () {
    test('유저가 1인칭으로 말한다', () {
      expect(prompt,
          contains('**Write it as the USER, in the first person.**'));
      expect(prompt, contains('in the first person.'));
    });

    test('대화 기록도 3인칭 요약도 아니다', () {
      expect(prompt,
          contains('This is NOT a transcript and NOT a third-person summary.'));
    });
  });

  group('대화 밖으로 나가지 않는다', () {
    test('대화에 있는 것만 쓴다', () {
      expect(prompt,
          contains('Use only what the conversation actually contains.'));
      expect(
        prompt,
        contains(
            'Do not add reasons, examples, details, opinions, feelings, or conclusions that the conversation did not contain.'),
      );
    });

    test('옛 확장 허락은 사라졌다', () {
      expect(prompt,
          isNot(contains('you may write what the conversation never said')));
      expect(prompt, isNot(contains('pick ONE or TWO topics')));
      expect(prompt, isNot(contains('[YOU MAY ADD]')));
    });

    test('길이는 대화를 따른다 — 늘리지도 빼지도 않는다', () {
      expect(prompt, contains('[LENGTH FOLLOWS THE CONVERSATION]'));
      expect(
        prompt,
        contains(
            'Never pad it, and never drop a topic the user really talked about.'),
      );
    });
  });

  group('경계는 그대로 남는다', () {
    test('원 대화와 모순되지 않는다', () {
      expect(prompt, contains('Never contradict the conversation.'));
    });

    test('민감하거나 구체적인 사실은 지어내지 않는다', () {
      expect(
        prompt,
        contains('Never invent a specific or sensitive fact about the user.'),
      );
      // 무엇이 그런 사실인지 예를 들어 준다 — 안 그러면 모델이 자기 기준으로 판단한다.
      expect(
        prompt,
        contains(
            'No names, places, employers, numbers, dates, health details, money, or relationships that the conversation did not supply.'),
      );
    });

    test('대화문이 아니라 한 사람의 스피치다', () {
      expect(
        prompt,
        contains(
            'Never write a dialogue, a question-and-answer, or a string of exchanged turns.'),
      );
      expect(prompt, contains('It is ONE person speaking continuously.'));
      // 상대 말은 유저가 겪은 일로만 들어온다.
      expect(prompt, contains("only as part of the user's own experience"));
    });

    test('유저의 입장을 뒤집지 않는다', () {
      expect(
        prompt,
        contains(
            "Never reverse the user's stance or make it stronger or weaker than it was."),
      );
    });
  });

  group('호흡·분절은 이 단계가 설계하지 않는다', () {
    test('텍스트 단계에서 호흡 경계를 만들라고 시키지 않는다', () {
      // 글을 청크에 맞추지 않는다. 완성된 글을 읽은 실제 소리를
      // audio_silence_analyzer가 나누고 BreathEchoingEngine이 굴린다.
      for (final gone in <String>[
        'breath',
        'echo and shadow',
        'shadowing',
        'chunk',
      ]) {
        expect(prompt.toLowerCase(), isNot(contains(gone)), reason: gone);
      }
    });

    test('단어 수나 길이로 자르는 규칙이 없다', () {
      expect(prompt, isNot(contains('5-7')));
      expect(prompt, isNot(contains('5–7')));
      expect(prompt.toLowerCase(), isNot(contains('words per')));
    });

    test('실제로 다시 쓸 수 있는 쉬운 영어다', () {
      expect(
        prompt,
        contains('Keep it something the user could genuinely say again'),
      );
      expect(
        prompt,
        contains('No literary phrasing, no heavy idioms, no showy vocabulary.'),
      );
    });
  });

  group('한 문장이 아니라 한 발화다', () {
    test('여러 문장이어도 된다고 적혀 있다', () {
      expect(prompt,
          contains('Several sentences that connect into one flowing account.'));
      expect(
        prompt,
        contains('Do not force it into one grammatical sentence'),
      );
      expect(prompt,
          contains('One person, speaking naturally and continuously, in the first person.'));
      // 길이를 채우려고 한 문장을 늘이지도 않는다.
      expect(
        prompt,
        contains('do not stretch one sentence to make it long'),
      );
    });

    test('설명·라벨·따옴표 없이 발화만 낸다', () {
      expect(prompt, contains('Output only My English.'));
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
      expect(japanese, contains('everyday spoken Japanese'));
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
      expect(withSituation,
          contains('Use it only to understand the conversation; do not add details from it.'));
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

    test('유저 줄이 하나도 없으면 My English는 성립하지 않는다', () {
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
      expect(sanitizeSpeechOutput('My English: I want to leave my job.'),
          'I want to leave my job.');
      // 옛 라벨을 붙여 오는 응답도 그대로 걷는다.
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

    test('Native English는 My English가 없으면 만들지 않는다', () async {
      final result = await NativeEnglishSpeechBuilder.build(
        apiKey: 'sk-test',
        mySpeech: '   ',
      );
      expect(result.failure, SpeechBuildFailure.emptyTranscript);
    });
  });
}
