import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/step_expand_p1.dart';
import 'package:stealth_vox/custom_code/services/step_expansion_builder.dart';

/// History P1이 **실제 학습 기록**으로 남는지를 지킨다.
///
/// P1의 규칙은 한 줄이다 —
/// **실제 AI 턴에서 '유저에게 답을 요구한 질문' + 그에 대응하는 실제 User 답변.
/// AI가 앞에서 제시한 후보·추천·설명은 제거.**
///
/// 여기서 가장 중요한 시험은 "유저 답변을 모델이 못 바꾼다"는 것이다. 그게
/// 무너지면 History가 실제로 오간 대화와 다른 가짜 기록이 된다.
void main() {
  // 실제 방에서 나오는 모양 그대로다 — 코치가 방향 셋을 늘어놓고 추천까지 한다.
  final transcript = <StepExpansionTurn>[
    const StepExpansionTurn(isUser: true, text: '회사 그만두고 싶어.'),
    const StepExpansionTurn(
      isUser: false,
      text: '이 생각은 몇 가지 방향으로 키울 수 있어요. 첫 번째는 왜 그만두고 싶은지 이유를 붙이는 쪽, '
          '두 번째는 그만두고 싶은데 망설이는 이유를 넣는 쪽, 세 번째는 그만둔 뒤 원하는 삶까지 잇는 쪽이에요. '
          '지금 생각에는 두 번째가 이야기가 가장 살아날 것 같은데, 어느 쪽으로 가볼까요?',
    ),
    const StepExpansionTurn(
      isUser: true,
      text: '그만두고 싶기는 한데 나이가 있어서 새 직장을 찾기가 걱정돼.',
    ),
    const StepExpansionTurn(
      isUser: false,
      text: '이제 단순히 그만두고 싶다가 아니라, 바꾸고 싶은데 현실이 걸려서 망설이는 생각이 됐어요. '
          '여기서는 불만을 더 늘어놓기보다 원하는 변화를 한 조각 넣는 쪽이 좋겠어요. '
          '지금은 어떤 변화가 가장 필요하다고 느끼세요?',
    ),
    const StepExpansionTurn(
      isUser: true,
      text: '돈을 더 버는 것보다 여유 있는 삶을 원해요.',
    ),
  ];

  String json(List<Map<String, dynamic>> pairs) =>
      jsonEncode(<String, dynamic>{'pairs': pairs});

  group('AI 제안문은 남지 않는다', () {
    test('질문과 유저 답변만 한 쌍으로 정리된다', () {
      final result = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[
          {
            'ai_index': 1,
            'user_index': 2,
            'question': '그만두고 싶은 마음을 붙잡는 게 뭐예요?',
          },
          {
            'ai_index': 3,
            'user_index': 4,
            'question': '지금은 어떤 변화가 가장 필요하다고 느끼세요?',
          },
        ]),
        transcript: transcript,
      );

      expect(result.isUsable, isTrue);
      expect(result.pairs.length, 2);
      expect(result.pairs[1].question, '지금은 어떤 변화가 가장 필요하다고 느끼세요?');
      expect(result.pairs[1].answer, '돈을 더 버는 것보다 여유 있는 삶을 원해요.');

      // 코치가 늘어놓은 후보·추천은 어디에도 실리지 않는다.
      final everything =
          result.pairs.map((p) => '${p.question} ${p.answer}').join(' ');
      expect(everything, isNot(contains('첫 번째')));
      expect(everything, isNot(contains('두 번째가')));
      expect(everything, isNot(contains('방향으로 키울')));
    });

    test('씨앗 발화는 쌍이 되지 않는다 — 아무것도 그걸 요구하지 않았다', () {
      final result = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[
          {'ai_index': 1, 'user_index': 0, 'question': '무슨 생각이세요?'},
        ]),
        transcript: transcript,
      );
      // 물음보다 앞선 답은 그 물음의 답이 아니다.
      expect(result.isUsable, isFalse);
      expect(result.failure, StepExpandP1Failure.validationError);
    });
  });

  group('유저의 말은 모델이 못 건드린다', () {
    test('모델이 답변을 적어 보내도 무시하고 transcript에서 꺼낸다', () {
      final result = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[
          {
            'ai_index': 3,
            'user_index': 4,
            'question': '지금은 어떤 변화가 가장 필요하다고 느끼세요?',
            // 모델이 "더 좋게" 다듬어 보낸 답. 이게 새어 나가면 가짜 기록이다.
            'answer': '저는 금전적 보상보다 시간적 여유가 있는 삶을 지향합니다.',
          },
        ]),
        transcript: transcript,
      );
      expect(result.pairs.single.answer, '돈을 더 버는 것보다 여유 있는 삶을 원해요.');
    });
  });

  group('없는 턴을 가리키면 버린다', () {
    test('범위 밖 번호', () {
      final result = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[
          {'ai_index': 9, 'user_index': 12, 'question': '어떤 변화를 원하세요?'},
        ]),
        transcript: transcript,
      );
      expect(result.isUsable, isFalse);
    });

    test('역할이 뒤집힌 번호 — 유저 줄을 AI 자리에 대면 버린다', () {
      final result = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[
          {'ai_index': 2, 'user_index': 4, 'question': '어떤 변화를 원하세요?'},
        ]),
        transcript: transcript,
      );
      expect(result.isUsable, isFalse);
    });

    test('사이에 다른 유저 발화가 끼면 그 답은 그 물음의 답이 아니다', () {
      final result = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[
          // [1] AI가 물었고 [2]에서 이미 답했다. [4]는 [3]의 답이다.
          {'ai_index': 1, 'user_index': 4, 'question': '어느 쪽으로 갈까요?'},
        ]),
        transcript: transcript,
      );
      expect(result.isUsable, isFalse);
    });

    test('한 유저 발화를 두 번 쓰지 않는다', () {
      final result = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[
          {'ai_index': 3, 'user_index': 4, 'question': '어떤 변화가 필요하세요?'},
          {'ai_index': 3, 'user_index': 4, 'question': '무엇을 원하세요?'},
        ]),
        transcript: transcript,
      );
      expect(result.pairs.length, 1);
    });

    test('순서가 거꾸로 온 쌍은 버린다', () {
      final result = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[
          {'ai_index': 3, 'user_index': 4, 'question': '어떤 변화가 필요하세요?'},
          {'ai_index': 1, 'user_index': 2, 'question': '무엇이 망설이게 하나요?'},
        ]),
        transcript: transcript,
      );
      expect(result.pairs.length, 1);
      expect(result.pairs.single.answer, '돈을 더 버는 것보다 여유 있는 삶을 원해요.');
    });
  });

  group('질문이 설명을 달고 오면 버린다', () {
    test('상한을 넘는 질문은 잘라 붙이지 않고 그 쌍을 버린다', () {
      final long = '지금은 어떤 변화가 가장 필요하다고 느끼세요? ${'그리고 그 이유도 함께 말씀해 주세요. ' * 5}';
      expect(long.length, greaterThan(kMaxStepExpandP1QuestionChars));
      final result = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[
          {'ai_index': 3, 'user_index': 4, 'question': long},
        ]),
        transcript: transcript,
      );
      expect(result.isUsable, isFalse);
    });

    test('빈 질문은 버린다', () {
      final result = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[
          {'ai_index': 3, 'user_index': 4, 'question': '   '},
        ]),
        transcript: transcript,
      );
      expect(result.isUsable, isFalse);
    });
  });

  group('망가진 응답', () {
    test('JSON이 아니면 parseError', () {
      final result = StepExpandP1Builder.parseResponse(
        '전부 잘 정리했습니다.',
        transcript: transcript,
      );
      expect(result.failure, StepExpandP1Failure.parseError);
    });

    test('pairs가 없으면 validationError', () {
      final result = StepExpandP1Builder.parseResponse(
        '{"result":[]}',
        transcript: transcript,
      );
      expect(result.failure, StepExpandP1Failure.validationError);
    });

    test('번호가 문자열로 와도 받아 준다', () {
      final result = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[
          {'ai_index': '3', 'user_index': '4', 'question': '어떤 변화가 필요하세요?'},
        ]),
        transcript: transcript,
      );
      expect(result.pairs.single.answer, '돈을 더 버는 것보다 여유 있는 삶을 원해요.');
    });

    test('쌍 수 상한을 넘기지 않는다', () {
      final long = <StepExpansionTurn>[];
      for (var i = 0; i < kMaxStepExpandP1Pairs + 4; i++) {
        long.add(StepExpansionTurn(isUser: false, text: 'AI 물음 $i'));
        long.add(StepExpansionTurn(isUser: true, text: '유저 답 $i'));
      }
      final pairs = <Map<String, dynamic>>[];
      for (var i = 0; i < kMaxStepExpandP1Pairs + 4; i++) {
        pairs.add({
          'ai_index': i * 2,
          'user_index': i * 2 + 1,
          'question': '무엇을 원하세요 $i?',
        });
      }
      final result =
          StepExpandP1Builder.parseResponse(json(pairs), transcript: long);
      expect(result.pairs.length, kMaxStepExpandP1Pairs);
    });
  });

  group('번호 붙인 대화록', () {
    test('프롬프트와 검증이 같은 목록을 본다', () {
      final turns = StepExpandP1Builder.normalizeTranscript(<StepExpansionTurn>[
        const StepExpansionTurn(isUser: true, text: '  회사 그만두고 싶어.  '),
        const StepExpansionTurn(isUser: false, text: '   '),
        const StepExpansionTurn(isUser: false, text: '어느 쪽으로 갈까요?'),
      ]);
      expect(turns.length, 2);
      expect(
        StepExpandP1Builder.formatTranscript(turns),
        '[0] USER: 회사 그만두고 싶어.\n[1] AI: 어느 쪽으로 갈까요?',
      );
    });
  });

  group('지시문', () {
    test('제안문을 남기지 말라고 못 박는다', () {
      final prompt = StepExpandP1Builder.buildSysPrompt(
          originLang: 'Korean', targetLang: 'English');
      expect(prompt, contains('**None of that belongs in the record.**'));
      expect(prompt, contains('which one it recommended, and why'));
      expect(prompt, contains('the candidate directions it listed'));
    });

    test('질문을 창작하지 말라고 못 박는다', () {
      final prompt = StepExpandP1Builder.buildSysPrompt(
          originLang: 'Korean', targetLang: 'English');
      expect(prompt, contains('THE QUESTION IS NOT YOURS TO INVENT'));
      expect(prompt,
          contains('Never ask about something that AI turn did not ask about.'));
      expect(prompt, contains('the thing it actually asked the user for'));
    });

    test('유저 답변은 모델이 쓰는 것이 아니라고 적혀 있다', () {
      final prompt = StepExpandP1Builder.buildSysPrompt(
          originLang: 'Korean', targetLang: 'English');
      expect(prompt, contains('Never write the user\'s answer.'));
      expect(prompt, contains('taken from the transcript, not from you'));
    });

    test('질문 Target도 함께 만들라고 적혀 있다', () {
      final prompt = StepExpandP1Builder.buildSysPrompt(
          originLang: 'Korean', targetLang: 'English');
      expect(prompt, contains('"question_target"'));
      expect(prompt, contains('the SAME question in English'));
      expect(prompt, contains('nothing added, nothing narrowed'));
    });

    test('로비 스타일은 Target 줄에만, 어휘까지만 닿는다', () {
      final prompt = StepExpandP1Builder.buildSysPrompt(
          originLang: 'Korean', targetLang: 'English');
      // P1은 기록이다. Native를 골랐다고 실제로 건넨 질문이 다시 짜이면 안 된다.
      expect(prompt, contains('the "question_target" line only'));
      expect(prompt, contains('Style reaches the WORDING only.'));
      expect(prompt, isNot(contains('You may reorder the information')));
    });

    test('출력 언어가 유저의 언어로 고정된다', () {
      expect(StepExpandP1Builder.buildSysPrompt(
              originLang: 'Japanese', targetLang: 'English'),
          contains('one question in Japanese'));
    });
  });

  group('유저 발화 번호를 실어 둔다', () {
    test('전체 번호가 아니라 유저 발화만 세는 번호다', () {
      final result = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[
          {'ai_index': 1, 'user_index': 2, 'question': '무엇이 망설이게 하나요?'},
          {'ai_index': 3, 'user_index': 4, 'question': '어떤 변화가 필요하세요?'},
        ]),
        transcript: transcript,
      );
      // [0]이 0번째, [2]가 1번째, [4]가 2번째 유저 발화다.
      expect(result.pairs.map((p) => p.userTurnIndex), <int>[1, 2]);
    });

    test('번호가 저장 모양에 실린다', () {
      final pair = StepExpandP1Pair(
        question: '어떤 변화가 필요하세요?',
        answer: '여유 있는 삶이요.',
        userTurnIndex: 2,
      );
      expect(pair.toJson()['user_turn'], 2);
      // 모르는 번호는 아예 안 싣는다.
      expect(
        const StepExpandP1Pair(question: 'q', answer: 'a').toJson(),
        isNot(contains('user_turn')),
      );
    });
  });

  group('질문은 Target/Original 두 글로 남는다', () {
    test('모델이 준 두 글이 그대로 실린다', () {
      final result = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[
          {
            'ai_index': 3,
            'user_index': 4,
            'question': '지금은 어떤 변화가 가장 필요하다고 느끼세요?',
            'question_target': 'What kind of change do you want most right now?',
          },
        ]),
        transcript: transcript,
      );
      final pair = result.pairs.single;
      expect(pair.question, '지금은 어떤 변화가 가장 필요하다고 느끼세요?');
      expect(pair.questionTarget,
          'What kind of change do you want most right now?');
      expect(pair.toJson()['question_target'],
          'What kind of change do you want most right now?');
    });

    test('Target이 없어도 쌍은 살아 있다 — 원어 질문만으로 성립한다', () {
      final result = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[
          {'ai_index': 3, 'user_index': 4, 'question': '어떤 변화가 필요하세요?'},
        ]),
        transcript: transcript,
      );
      expect(result.isUsable, isTrue);
      expect(result.pairs.single.questionTarget, '');
      expect(result.pairs.single.toJson(), isNot(contains('question_target')));
    });

    test('Target이 설명을 달고 길게 오면 그 줄만 버린다', () {
      final long = 'a' * (kMaxStepExpandP1QuestionTargetChars + 1);
      final result = StepExpandP1Builder.parseResponse(
        json(<Map<String, dynamic>>[
          {
            'ai_index': 3,
            'user_index': 4,
            'question': '어떤 변화가 필요하세요?',
            'question_target': long,
          },
        ]),
        transcript: transcript,
      );
      expect(result.isUsable, isTrue);
      expect(result.pairs.single.questionTarget, '');
    });
  });

  group('교정된 원문을 따라간다', () {
    // ORIGIN-REPAIR가 "공약"을 "공격"으로 잘못 들은 것을 고친 상황이다.
    final stored = <StepExpandP1Pair>[
      const StepExpandP1Pair(
        question: '무엇이 망설이게 하나요?',
        answer: '나이가 있어서 새 직장 찾기가 걱정돼.',
        userTurnIndex: 1,
      ),
      const StepExpandP1Pair(
        question: '어떤 변화가 필요하세요?',
        answer: '돈보다 여유 있는 삶을 원해요.',
        userTurnIndex: 2,
      ),
    ];

    test('지금 남아 있는 원어로 답을 다시 붙인다', () {
      final resolved = resolveP1PairAnswers(stored, <String>[
        '회사 그만두고 싶어.',
        '나이가 있어서 새 직장 찾기가 걱정돼요.',
        '돈보다 여유 있는 삶을 원해요.',
      ]);
      expect(resolved[0].answer, '나이가 있어서 새 직장 찾기가 걱정돼요.');
      expect(resolved[1].answer, '돈보다 여유 있는 삶을 원해요.');
      // 질문은 저장된 그대로다. 교정은 유저의 말에만 걸린다.
      expect(resolved[0].question, '무엇이 망설이게 하나요?');
    });

    test('답변 Target은 저장하지 않고 화면에서 붙인다', () {
      final resolved = resolveP1PairAnswers(
        stored,
        <String>[
          '회사 그만두고 싶어.',
          '나이가 있어서 새 직장 찾기가 걱정돼요.',
          '돈보다 여유 있는 삶을 원해요.',
        ],
        currentUserTargets: <String>[
          'I want to quit my job.',
          "I'm worried about finding a new job at my age.",
          'I want a life with room to breathe more than more money.',
        ],
      );
      expect(resolved[1].answer, '돈보다 여유 있는 삶을 원해요.');
      expect(resolved[1].answerTarget,
          'I want a life with room to breathe more than more money.');
      // 저장 모양에는 답변 Target이 들어가지 않는다 — 교정된 원문에서 다시 나온다.
      expect(resolved[1].toJson(), isNot(contains('answer_target')));
    });

    test('배울글이 아직 없으면 Target 없이 원어만 붙는다', () {
      final resolved = resolveP1PairAnswers(
        stored,
        <String>['a', 'b', '돈보다 여유 있는 삶을 원해요.'],
        currentUserTargets: const <String>['', '', ''],
      );
      expect(resolved[1].answerTarget, '');
      expect(resolved[1].answer, '돈보다 여유 있는 삶을 원해요.');
    });

    test('질문 Target은 답을 다시 맞춰도 그대로다', () {
      final withTarget = <StepExpandP1Pair>[
        const StepExpandP1Pair(
          question: '어떤 변화가 필요하세요?',
          questionTarget: 'What change do you need?',
          answer: '옛 답',
          userTurnIndex: 0,
        ),
      ];
      final resolved = resolveP1PairAnswers(withTarget, <String>['새 답']);
      expect(resolved.single.questionTarget, 'What change do you need?');
      expect(resolved.single.answer, '새 답');
    });

    test('번호를 모르는 옛 방은 저장된 답을 그대로 쓴다', () {
      final old = <StepExpandP1Pair>[
        const StepExpandP1Pair(question: 'q', answer: '옛 답'),
      ];
      final resolved = resolveP1PairAnswers(old, <String>['전혀 다른 말']);
      expect(resolved.single.answer, '옛 답');
    });

    test('번호가 범위를 벗어나거나 그 자리가 비면 손대지 않는다', () {
      expect(
        resolveP1PairAnswers(stored, <String>['하나뿐']).map((p) => p.answer),
        stored.map((p) => p.answer),
      );
      expect(
        resolveP1PairAnswers(stored, <String>['a', '   ', '  '])
            .map((p) => p.answer),
        stored.map((p) => p.answer),
      );
    });

    test('맞출 것이 없으면 그대로 돌려준다', () {
      expect(resolveP1PairAnswers(stored, const <String>[]), stored);
      expect(
          resolveP1PairAnswers(const <StepExpandP1Pair>[], <String>['a']),
          isEmpty);
    });
  });

  group('저장값 다시 읽기', () {
    test('한쪽이 빈 쌍은 버린다', () {
      final pairs = parseStoredP1Pairs(<dynamic>[
        {'question': '어떤 변화가 필요하세요?', 'answer': '여유 있는 삶이요.'},
        {'question': '', 'answer': '네.'},
        {'question': '왜 그렇게 느끼세요?', 'answer': ''},
        'not a map',
      ]);
      expect(pairs.length, 1);
      expect(pairs.single.answer, '여유 있는 삶이요.');
    });

    test('질문 Target을 함께 읽는다', () {
      final pairs = parseStoredP1Pairs(<dynamic>[
        {
          'question': '어떤 변화가 필요하세요?',
          'question_target': 'What change do you need?',
          'answer': '여유 있는 삶이요.',
        },
        {'question': 'q', 'answer': 'a'},
      ]);
      expect(pairs[0].questionTarget, 'What change do you need?');
      expect(pairs[1].questionTarget, '');
    });

    test('번호를 함께 읽는다', () {
      final pairs = parseStoredP1Pairs(<dynamic>[
        {'question': 'q1', 'answer': 'a1', 'user_turn': 2},
        {'question': 'q2', 'answer': 'a2', 'user_turn': '3'},
        {'question': 'q3', 'answer': 'a3'},
      ]);
      expect(pairs.map((p) => p.userTurnIndex), <int>[2, 3, -1]);
    });

    test('배열이 아니면 빈 목록이다', () {
      expect(parseStoredP1Pairs(null), isEmpty);
      expect(parseStoredP1Pairs('p1'), isEmpty);
    });
  });
}
