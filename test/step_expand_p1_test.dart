import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/step_expand_p1.dart';

/// 공부방 P1이 **실제 학습 기록**으로 남는지를 지킨다.
///
///   유저: 회사 그만두고 싶어.
///   AI:   연결하고 싶은 당신의 생각을 말해보세요.
///   유저: 매일 똑같은 일을 반복하는 게 너무 지쳐.
///
/// 가장 중요한 시험은 하나다 — **유저 줄을 모델이 못 만든다.** 유저 줄은
/// 방이 확정해 둔 사다리에서 계산으로 나온다. 그게 무너지면 History가
/// 실제로 오간 것과 다른 가짜 기록이 된다.
void main() {
  // 방이 턴마다 확정한 누적 글. 다음 칸이 앞 칸을 통째로 품는다.
  final ladder = <String>[
    '회사 그만두고 싶어.',
    '회사 그만두고 싶어. 매일 똑같은 일을 반복하는 게 너무 지쳐.',
    '회사 그만두고 싶어. 매일 똑같은 일을 반복하는 게 너무 지쳐. '
        '뭔가 새로운 일을 하면서 다시 의욕을 느끼고 싶어.',
  ];

  final answers = <String>[
    '회사 그만두고 싶어.',
    '매일 똑같은 일을 반복하는 게 너무 지쳐.',
    '뭔가 새로운 일을 하면서 다시 의욕을 느끼고 싶어.',
  ];

  String json(List<Map<String, dynamic>> lines) =>
      jsonEncode(<String, dynamic>{'lines': lines});

  group('유저 줄은 사다리에서 계산으로 나온다', () {
    test('누적 글의 차이가 그 턴에 붙은 문장이다', () {
      expect(stepExpandAddedParts(ladder), answers);
    });

    test('같은 글이 두 칸이면 그 턴엔 아무것도 안 붙었다', () {
      expect(
        stepExpandAddedParts(<String>['가.', '가.', '가. 나.']),
        <String>['가.', '나.'],
      );
    });

    test('앞 칸을 품고 있지 않으면 그 칸을 통째로 쓴다', () {
      // 모델이 이미 들어간 부분을 손댄 경우다. 잘못 잘라 조각을 남기느니
      // 한 번 길게 나오는 쪽이 낫다.
      expect(
        stepExpandAddedParts(<String>['가.', '완전히 다른 글.']),
        <String>['가.', '완전히 다른 글.'],
      );
    });

    test('빈 칸과 빈 사다리', () {
      expect(stepExpandAddedParts(<String>['', '  ']), isEmpty);
      expect(stepExpandAddedParts(const <String>[]), isEmpty);
    });
  });

  group('유저가 먼저 시작한다', () {
    test('씨앗 앞에는 AI 줄이 없다', () {
      final result = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[
          // 모델이 첫 줄에도 권유를 채워 보냈다. 버려야 한다.
          {'prompt': '무슨 생각이세요?', 'prompt_target': 'What are you thinking?'},
          {'prompt': '연결하고 싶은 당신의 생각을 말해보세요.'},
          {'prompt': '다음 연결할 말을 결정했나요?'},
        ]),
        answers: answers,
      );
      expect(result.pairs.first.hasPrompt, isFalse);
      expect(result.pairs.first.prompt, isEmpty);
      expect(result.pairs.first.promptTarget, isEmpty);
      expect(result.pairs[1].prompt, '연결하고 싶은 당신의 생각을 말해보세요.');
      expect(result.pairs[2].prompt, '다음 연결할 말을 결정했나요?');
    });

    test('줄 수는 언제나 유저 문장 수와 같다', () {
      // 모델이 두 줄만 보내도, 다섯 줄을 보내도 유저 문장 수가 기준이다.
      final short = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[{}, {}]),
        answers: answers,
      );
      expect(short.pairs.map((p) => p.answer), answers);
      final long = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[{}, {}, {}, {}, {}]),
        answers: answers,
      );
      expect(long.pairs.map((p) => p.answer), answers);
    });
  });

  group('유저의 말은 모델이 못 건드린다', () {
    test('모델이 유저 문장을 적어 보내도 무시한다', () {
      final result = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[
          {'answer': '저는 퇴사를 고려하고 있습니다.'},
          {'answer': '반복 업무에 피로를 느낍니다.'},
          {'answer': '새로운 도전을 원합니다.'},
        ]),
        answers: answers,
      );
      expect(result.pairs.map((p) => p.answer), answers);
    });

    test('응답이 망가져도 유저 줄만으로 P1은 선다', () {
      final broken =
          StepExpandP1Builder.parseResponse('전부 정리했습니다.', answers: answers);
      expect(broken.isUsable, isTrue);
      expect(broken.pairs.map((p) => p.answer), answers);
      expect(broken.pairs.every((p) => !p.hasPrompt), isTrue);
    });
  });

  group('AI 권유는 짧은 한 줄이다', () {
    test('설명이 딸려 오면 그 줄만 비운다', () {
      final long = '가' * (kMaxStepExpandP1PromptChars + 1);
      final result = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[
          {},
          {'prompt': long, 'prompt_target': 'something'},
        ]),
        answers: answers,
      );
      // 줄은 살아 있고 유저 문장도 그대로다. 권유만 사라진다.
      expect(result.pairs[1].answer, answers[1]);
      expect(result.pairs[1].prompt, isEmpty);
      expect(result.pairs[1].promptTarget, isEmpty);
    });

    test('권유가 없으면 그 배울글도 없다', () {
      final result = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[
          {},
          {'prompt': '', 'prompt_target': 'Tell me the next part.'},
        ]),
        answers: answers,
      );
      expect(result.pairs[1].promptTarget, isEmpty);
    });
  });

  group('Target과 Original 두 글', () {
    test('배울글이 함께 실린다', () {
      final result = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[
          {'answer_target': 'I want to quit my job.'},
          {
            'prompt': '연결하고 싶은 당신의 생각을 말해보세요.',
            'prompt_target': 'Tell me what you want to add.',
            'answer_target': "I'm worn out from doing the same thing every day.",
          },
        ]),
        answers: answers,
      );
      expect(result.pairs[0].answerTarget, 'I want to quit my job.');
      expect(result.pairs[1].promptTarget, 'Tell me what you want to add.');
      expect(result.pairs[1].answerTarget,
          "I'm worn out from doing the same thing every day.");
    });

    test('저장 모양에는 있는 것만 실린다', () {
      const seed = StepExpandP1Pair(answer: '회사 그만두고 싶어.');
      expect(seed.toJson(), <String, dynamic>{'answer': '회사 그만두고 싶어.'});
    });
  });

  group('지시문', () {
    test('유저 문장을 손대지 말라고 못 박는다', () {
      final prompt = StepExpandP1Builder.buildSysPrompt(
          originLang: 'Korean', targetLang: 'English');
      expect(prompt, contains("THE USER'S SENTENCES ARE NOT YOURS"));
      expect(prompt, contains('Do not repeat them back, do not correct them'));
    });

    test('첫 줄에는 권유가 없다고 적혀 있다', () {
      final prompt = StepExpandP1Builder.buildSysPrompt(
          originLang: 'Korean', targetLang: 'English');
      expect(prompt,
          contains('nothing invited the opening line, the user brought it'));
    });

    test('권유는 내용을 나르지 않는다', () {
      final prompt = StepExpandP1Builder.buildSysPrompt(
          originLang: 'Korean', targetLang: 'English');
      expect(prompt, contains('They invite; they never carry content.'));
      expect(prompt, contains('never mention what the user went on to say'));
      expect(prompt, contains('Never offer choices, never recommend'));
    });

    test('같은 말이 반복되지 않게 한다', () {
      final prompt = StepExpandP1Builder.buildSysPrompt(
          originLang: 'Korean', targetLang: 'English');
      expect(prompt, contains('Never use the same wording twice in a row.'));
      expect(prompt, contains('reads as a machine, not a session'));
    });

    test('로비 스타일은 배울글 줄에만, 어휘까지만 닿는다', () {
      final prompt = StepExpandP1Builder.buildSysPrompt(
          originLang: 'Korean', targetLang: 'English');
      expect(prompt, contains('the "prompt_target" and "answer_target" lines'));
      expect(prompt, contains('Style reaches the WORDING only.'));
      expect(prompt, isNot(contains('You may reorder the information')));
    });

    test('출력 언어가 두 언어로 고정된다', () {
      final prompt = StepExpandP1Builder.buildSysPrompt(
          originLang: 'Japanese', targetLang: 'English');
      expect(prompt, contains('a SHORT Japanese line inviting'));
      expect(prompt, contains('that user sentence in English'));
    });
  });

  group('저장값 다시 읽기', () {
    test('네 칸을 그대로 읽는다', () {
      final pairs = parseStoredP1Pairs(<dynamic>[
        {'answer': '회사 그만두고 싶어.', 'answer_target': 'I want to quit my job.'},
        {
          'answer': '매일 똑같은 일을 반복하는 게 너무 지쳐.',
          'prompt': '연결하고 싶은 당신의 생각을 말해보세요.',
          'prompt_target': 'Tell me what you want to add.',
          'answer_target': "I'm worn out.",
        },
      ]);
      expect(pairs, hasLength(2));
      expect(pairs[0].hasPrompt, isFalse);
      expect(pairs[1].hasPrompt, isTrue);
      expect(pairs[1].promptTarget, 'Tell me what you want to add.');
    });

    test('유저 줄이 없는 항목은 버린다', () {
      final pairs = parseStoredP1Pairs(<dynamic>[
        {'prompt': '이어서 말해보세요.'},
        {'answer': '   '},
        'not a map',
        {'answer': '남는 줄.'},
      ]);
      expect(pairs.map((p) => p.answer), <String>['남는 줄.']);
    });

    test('배열이 아니면 빈 목록이다', () {
      expect(parseStoredP1Pairs(null), isEmpty);
      expect(parseStoredP1Pairs('p1'), isEmpty);
    });
  });
}
