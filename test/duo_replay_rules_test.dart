import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:stealth_vox/custom_code/services/duo_replay_rules.dart';

ReplaySourceLine line(String id, String role, String text) =>
    ReplaySourceLine(id: id, role: role, text: text);

final source = <ReplaySourceLine>[
  line('1', 'HOST', '내일... 어, 내일 몇 시쯤 올 거야?'),
  line('2', 'GUEST', 'Well, um... probably around six?'),
  line('3', 'HOST', '아 그래? 그러면'),
  line('4', 'HOST', '저녁 같이 먹자.'),
  line('5', 'GUEST', 'Sounds good to me.'),
];

String reply(List<Map<String, dynamic>> turns,
        [List<Map<String, dynamic>> dropped = const []]) =>
    jsonEncode(<String, dynamic>{'turns': turns, 'dropped': dropped});

void main() {
  group('언어는 화자가 쓴 그대로 — 번역이 아니다', () {
    test('한국어와 영어가 섞인 통화는 섞인 채로 남는다', () {
      final result = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {
            'ids': ['1'],
            'role': 'HOST',
            'text': '내일 몇 시쯤 올 거야?'
          },
          {
            'ids': ['2'],
            'role': 'GUEST',
            'text': 'Probably around six?'
          },
          {
            'ids': ['3', '4'],
            'role': 'HOST',
            'text': '아 그래? 그러면 저녁 같이 먹자.'
          },
          {
            'ids': ['5'],
            'role': 'GUEST',
            'text': 'Sounds good to me.'
          },
        ]),
        source: source,
      );
      expect(result.turns.length, 4);
      expect(result.turns[0].text, contains('내일'));
      expect(result.turns[1].text, contains('six'));
      expect(result.warnings, isEmpty);
    });

    test('같은 화자의 토막은 한 줄로 이어지고, 어느 원본에서 왔는지 남는다', () {
      final result = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {
            'ids': ['1'],
            'role': 'HOST',
            'text': '내일 몇 시쯤 올 거야?'
          },
          {
            'ids': ['2'],
            'role': 'GUEST',
            'text': 'Probably around six?'
          },
          {
            'ids': ['3', '4'],
            'role': 'HOST',
            'text': '아 그래? 그러면 저녁 같이 먹자.'
          },
          {
            'ids': ['5'],
            'role': 'GUEST',
            'text': 'Sounds good to me.'
          },
        ]),
        source: source,
      );
      expect(result.turns[2].sourceIds, <String>['3', '4']);
    });
  });

  group('🔒 한 화자의 말을 다른 화자에게 옮기지 못한다', () {
    test('모델이 역할을 바꿔 보내면 원본 화자로 되돌리고 적어 둔다', () {
      final result = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {
            'ids': ['1'],
            'role': 'GUEST',
            'text': '내일 몇 시쯤 올 거야?'
          },
        ]),
        source: <ReplaySourceLine>[source.first],
      );
      expect(result.turns.single.role, 'HOST');
      expect(result.warnings.map((w) => w.kind), contains('speaker_moved'));
    });

    test('서로 다른 화자를 한 줄로 묶으면 경고가 남는다', () {
      final result = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {
            'ids': ['1', '2'],
            'role': 'HOST',
            'text': '내일 몇 시? Around six.'
          },
        ]),
        source: source,
      );
      expect(result.warnings.map((w) => w.kind), contains('speaker_merge'));
    });
  });

  group('🔒 없던 말을 만들지 못한다', () {
    test('원본 없는 줄은 버리고 지어냈다고 적는다', () {
      final result = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {'ids': <String>[], 'role': 'HOST', 'text': '그럼 일곱 시에 보자.'},
        ]),
        source: source,
      );
      expect(result.turns.where((t) => t.text == '그럼 일곱 시에 보자.'), isEmpty);
      expect(result.warnings.map((w) => w.kind), contains('invented'));
    });

    test('원본보다 크게 길어진 줄은 지어냈을 수 있다고 적는다', () {
      final result = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {
            'ids': ['5'],
            'role': 'GUEST',
            'text':
                'Sounds good to me, I have been looking forward to it all week.'
          },
        ]),
        source: <ReplaySourceLine>[source.last],
      );
      expect(result.warnings.map((w) => w.kind), contains('expanded'));
    });
  });

  group('빼는 것은 열고, 만드는 것은 닫는다', () {
    test('응답에 안 실린 줄은 뺀 것으로 본다 — 되살리지 않는다', () {
      // 원본은 canonical에 그대로 있다. 여기서 버려도 잃지 않는다.
      final result = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {
            'ids': ['1'],
            'role': 'HOST',
            'text': '내일 몇 시쯤 올 거야?'
          },
        ]),
        source: source,
      );
      expect(result.turns.length, 1);
      expect(result.dropped.length, 4);
      expect(result.dropped.every((d) => d.reason == 'unlisted'), isTrue);
      expect(result.warnings.map((w) => w.kind), contains('unlisted'));
    });

    test('모르는 이유로 지웠다고 해도 결국 뺀 줄로 남는다', () {
      final result = parseReplayResponse(
        content: reply(
          <Map<String, dynamic>>[
            {
              'ids': ['1'],
              'role': 'HOST',
              'text': '내일 몇 시쯤 올 거야?'
            },
          ],
          <Map<String, dynamic>>[
            {'id': '5', 'reason': 'not_useful'},
          ],
        ),
        source: source,
      );
      expect(result.warnings.map((w) => w.kind), contains('unknown_reason'));
      expect(result.dropped.firstWhere((d) => d.id == '5').reason, 'unlisted');
    });

    test('지울 수 있는 이유는 정해진 다섯뿐이다', () {
      // 'context' = 글자는 멀쩡한데 앞뒤 대화와 이어지지 않는 줄.
      // 모르는 이유로는 아무것도 지우지 않는다(아래 unknown_reason 시험).
      expect(kReplayDropReasons,
          <String>{'noise', 'filler', 'duplicate', 'context', 'unlisted'});
    });

    test('응답이 JSON이 아니면 원본을 그대로 쓴다', () {
      final result = parseReplayResponse(content: '미안 못 하겠어', source: source);
      expect(result.turns.length, source.length);
      expect(result.turns.map((t) => t.text), source.map((s) => s.text));
      expect(result.warnings.single.kind, 'parse');
    });
  });

  group('🛟 Replay는 원본을 대신하지 않는다 — 미더우면 쓰고 아니면 되돌린다', () {
    ReplayResult res(List<Map<String, dynamic>> turns,
            [List<Map<String, dynamic>> dropped = const []]) =>
        parseReplayResponse(content: reply(turns, dropped), source: source);

    test('규칙을 지킨 판은 그대로 쓴다', () {
      final r = res(<Map<String, dynamic>>[
        {
          'ids': ['1'],
          'role': 'HOST',
          'text': '내일 몇 시쯤 올 거야?'
        },
        {
          'ids': ['2'],
          'role': 'GUEST',
          'text': 'Probably around six?'
        },
        {
          'ids': ['3', '4'],
          'role': 'HOST',
          'text': '아 그래? 그러면 저녁 같이 먹자.'
        },
        {
          'ids': ['5'],
          'role': 'GUEST',
          'text': 'Sounds good to me.'
        },
      ]);
      final v = judgeReplay(result: r, sourceCount: source.length);
      expect(v.useReplay, isTrue);
      expect(v.reasons, isEmpty);
    });

    test('응답을 읽지 못하면 되돌린다', () {
      final r = parseReplayResponse(content: '못 하겠어', source: source);
      expect(judgeReplay(result: r, sourceCount: source.length).reasons,
          contains('parse_failed'));
    });

    test('지어낸 줄이 하나라도 있으면 되돌린다', () {
      final r = res(<Map<String, dynamic>>[
        {
          'ids': ['1'],
          'role': 'HOST',
          'text': '내일 몇 시쯤 올 거야?'
        },
        {'ids': <String>[], 'role': 'HOST', 'text': '그럼 일곱 시에 보자.'},
      ]);
      expect(judgeReplay(result: r, sourceCount: source.length).reasons,
          contains('invented_turn'));
    });

    test('많이 지운 것만으로는 되돌리지 않는다 — 걷어내는 것이 이 계층의 일이다', () {
      final r = res(
        <Map<String, dynamic>>[
          {
            'ids': ['1'],
            'role': 'HOST',
            'text': '내일 몇 시쯤 올 거야?'
          },
          {
            'ids': ['2'],
            'role': 'GUEST',
            'text': 'Probably around six?'
          },
        ],
        <Map<String, dynamic>>[
          {'id': '3', 'reason': 'filler'},
          {'id': '4', 'reason': 'filler'},
          {'id': '5', 'reason': 'duplicate'},
        ],
      );
      expect(
          judgeReplay(result: r, sourceCount: source.length).useReplay, isTrue);
    });

    test('한 사람 말만 남으면 되돌린다 — 대화가 아니게 됐다', () {
      final r = res(<Map<String, dynamic>>[
        {
          'ids': ['1'],
          'role': 'HOST',
          'text': '내일 몇 시쯤 올 거야?'
        },
        {
          'ids': ['3', '4'],
          'role': 'HOST',
          'text': '아 그래? 그러면 저녁 같이 먹자.'
        },
      ]);
      expect(judgeReplay(result: r, sourceCount: source.length).reasons,
          contains('speaker_collapsed'));
    });

    test('원본보다 줄이 늘면 되돌린다 — 없던 주고받기를 만든 것이다', () {
      final r = res(<Map<String, dynamic>>[
        for (var i = 0; i < 4; i++) ...<Map<String, dynamic>>[
          {
            'ids': ['1'],
            'role': 'HOST',
            'text': '내일 몇 시쯤 올 거야? $i'
          },
          {
            'ids': ['2'],
            'role': 'GUEST',
            'text': 'Around six. $i'
          },
        ]
      ]);
      expect(judgeReplay(result: r, sourceCount: source.length).reasons,
          contains('turn_inflation'));
    });

    test('길어짐·화자 뒤바뀜은 되돌리지 않는다 — 경고로만 남는다', () {
      final r = res(<Map<String, dynamic>>[
        {
          'ids': ['1'],
          'role': 'GUEST',
          'text': '내일 몇 시쯤 올 거야?'
        },
        {
          'ids': ['2'],
          'role': 'GUEST',
          'text': 'Probably around six?'
        },
        {
          'ids': ['3', '4'],
          'role': 'HOST',
          'text': '아 그래? 그러면 저녁 같이 먹자.'
        },
        {
          'ids': ['5'],
          'role': 'GUEST',
          'text': 'Sounds good to me, that works perfectly for my schedule.'
        },
      ]);
      expect(r.warnings.map((w) => w.kind),
          containsAll(<String>['speaker_moved', 'expanded']));
      expect(
          judgeReplay(result: r, sourceCount: source.length).useReplay, isTrue);
    });
  });

  group('고친 줄만 따로 본다 (A. 의미 보존)', () {
    test('손대지 않은 줄은 목록에 오르지 않는다', () {
      final r = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {
            'ids': ['1'],
            'role': 'HOST',
            'text': '내일... 어, 내일 몇 시쯤 올 거야?'
          },
          {
            'ids': ['2'],
            'role': 'GUEST',
            'text': 'Well, um... probably around six?'
          },
          {
            'ids': ['3'],
            'role': 'HOST',
            'text': '아 그래? 그러면'
          },
          {
            'ids': ['4'],
            'role': 'HOST',
            'text': '저녁 같이 먹자.'
          },
          {
            'ids': ['5'],
            'role': 'GUEST',
            'text': 'Sounds good to me.'
          },
        ]),
        source: source,
      );
      expect(replayEdits(result: r, source: source), isEmpty);
    });

    test('이은 줄과 고친 줄은 앞뒤가 함께 보인다', () {
      final r = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {
            'ids': ['1'],
            'role': 'HOST',
            'text': '내일 몇 시쯤 올 거야?'
          },
          {
            'ids': ['2'],
            'role': 'GUEST',
            'text': 'Probably around six?'
          },
          {
            'ids': ['3', '4'],
            'role': 'HOST',
            'text': '아 그래? 그러면 저녁 같이 먹자.'
          },
          {
            'ids': ['5'],
            'role': 'GUEST',
            'text': 'Sounds good to me.'
          },
        ]),
        source: source,
      );
      final edits = replayEdits(result: r, source: source);
      // 토막을 **잇기만** 한 줄(3+4)은 글자가 그대로라 고친 줄이 아니다.
      // 의미가 바뀔 수 있는 것은 글자가 달라진 둘뿐이다.
      expect(edits.length, 2);
      expect(edits.first.before, '내일... 어, 내일 몇 시쯤 올 거야?');
      expect(edits.first.after, '내일 몇 시쯤 올 거야?');
      expect(edits.last.before, 'Well, um... probably around six?');
      expect(edits.last.ids, <String>['2']);
    });
  });

  group('프롬프트가 정책을 그대로 담고 있다', () {
    test('번역 금지가 절대 규칙으로 적혀 있다', () {
      expect(kReplayPrompt, contains('LANGUAGE RULE - absolute'));
      expect(kReplayPrompt, contains('Never translate a turn'));
    });

    test('한 줄만 보지 말고 통화 전체를 먼저 읽으라고 되어 있다', () {
      expect(kReplayPrompt, contains('READ THE WHOLE CALL FIRST'));
      expect(kReplayPrompt, contains('before you judge any single line'));
    });

    test('판단 기준이 글자 모양이 아니라 대화에서의 자리다', () {
      expect(kReplayPrompt,
          contains('by its PLACE IN THE CONVERSATION, never by how it looks'));
      // 앞뒤 2~3턴을 같이 보라는 지시.
      expect(
          kReplayPrompt,
          contains(
              'two or three turns before it and the two or three turns after'));
      // 고립된 줄을 가리키는 이름.
      expect(kReplayPrompt, contains('stranded'));
      expect(kReplayPrompt, contains('Drop it as "context"'));
    });

    test('낱말 목록을 만들지 말라고 못 박혀 있다', () {
      expect(kReplayPrompt, contains('NEVER keep a list of suspicious words'));
      // 같은 낱말이 자리에 따라 달라진다는 예시가 둘 다 들어 있다.
      expect(kReplayPrompt, contains('안녕하세요'));
      expect(kReplayPrompt, contains('러시아'));
      expect(kReplayPrompt, contains('KEEP. Never drop it.'));
    });

    test('문맥에 안 맞으면 빼라고 되어 있다', () {
      // 2026-08-31 방향이 뒤집혔다. 첫 판은 "애매하면 남긴다"였는데, 그러면
      // 전사가 지어낸 문장이 학습용 대본에 그대로 남았다. 실제로 한 말은
      // canonical에 통째로 있으므로 여기서 빼도 잃지 않는다.
      expect(kReplayPrompt, contains('WHEN A LINE DOES NOT FIT, LEAVE IT OUT'));
      expect(kReplayPrompt, contains('STUDY SCRIPT, not a record of the call'));
      expect(kReplayPrompt, contains('do not keep it "just in case"'));
      expect(kReplayPrompt,
          contains('Build the script ONLY from the lines that hold together'));
      expect(kReplayPrompt, isNot(contains('WHEN IN DOUBT, KEEP')));
    });

    test('넓힌 것은 자리뿐이고 값어치가 아니다', () {
      // 짧다고 빼기 시작하면 canonical과 같은 잘못을 이 층에서 되풀이한다.
      expect(kReplayPrompt, contains('about FIT, not about WORTH'));
      expect(
        kReplayPrompt,
        contains(
            'Never leave a line out because it is short, plain, or looks unimportant'),
      );
      expect(kReplayPrompt,
          contains('Deciding which real remarks matter is not your job'));
    });

    test('완벽한 전사를 요구하지 않는다 — 일부가 망가져도 만든다', () {
      expect(kReplayPrompt, contains('YOU DO NOT NEED A CLEAN TRANSCRIPT'));
      expect(kReplayPrompt,
          contains('do not give up because some lines are uncertain'));
    });

    test('보조 신호는 맥락을 거들 때만 쓰라고 되어 있다', () {
      expect(kReplayPrompt, contains('rms_dbfs'));
      expect(kReplayPrompt, contains('stt_source'));
      expect(kReplayPrompt, contains('never drop a line on a signal alone'));
    });

    test('없는 질문을 만들지 말라고 되어 있다', () {
      expect(kReplayPrompt, contains('Add a question nobody asked'));
    });

    test('없던 사실·화자 이동·요약은 금지되어 있다', () {
      expect(kReplayPrompt, contains('Add a fact'));
      expect(kReplayPrompt, contains('Never move a line from one speaker'));
      expect(kReplayPrompt, contains('summary of itself'));
    });

    test('알아볼 수 없으면 원본을 그대로 두라고 되어 있다', () {
      expect(kReplayPrompt, contains('return the lines as they are'));
    });
  });
}
