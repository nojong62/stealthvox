import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../tool/duo_replay_rules.dart';

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
          {'ids': ['1'], 'role': 'HOST', 'text': '내일 몇 시쯤 올 거야?'},
          {'ids': ['2'], 'role': 'GUEST', 'text': 'Probably around six?'},
          {'ids': ['3', '4'], 'role': 'HOST', 'text': '아 그래? 그러면 저녁 같이 먹자.'},
          {'ids': ['5'], 'role': 'GUEST', 'text': 'Sounds good to me.'},
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
          {'ids': ['1'], 'role': 'HOST', 'text': '내일 몇 시쯤 올 거야?'},
          {'ids': ['2'], 'role': 'GUEST', 'text': 'Probably around six?'},
          {'ids': ['3', '4'], 'role': 'HOST', 'text': '아 그래? 그러면 저녁 같이 먹자.'},
          {'ids': ['5'], 'role': 'GUEST', 'text': 'Sounds good to me.'},
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
          {'ids': ['1'], 'role': 'GUEST', 'text': '내일 몇 시쯤 올 거야?'},
        ]),
        source: <ReplaySourceLine>[source.first],
      );
      expect(result.turns.single.role, 'HOST');
      expect(result.warnings.map((w) => w.kind), contains('speaker_moved'));
    });

    test('서로 다른 화자를 한 줄로 묶으면 경고가 남는다', () {
      final result = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {'ids': ['1', '2'], 'role': 'HOST', 'text': '내일 몇 시? Around six.'},
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
            'text': 'Sounds good to me, I have been looking forward to it all week.'
          },
        ]),
        source: <ReplaySourceLine>[source.last],
      );
      expect(result.warnings.map((w) => w.kind), contains('expanded'));
    });
  });

  group('🧭 잃지 않는 쪽으로 기운다', () {
    test('응답에서 빠진 원본은 원문 그대로 되살린다', () {
      final result = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {'ids': ['1'], 'role': 'HOST', 'text': '내일 몇 시쯤 올 거야?'},
        ]),
        source: source,
      );
      expect(result.turns.length, source.length);
      expect(result.turns.map((t) => t.text), contains('Sounds good to me.'));
      expect(result.warnings.map((w) => w.kind), contains('restored_missing'));
    });

    test('아는 이유로만 지운다 — 모르는 이유는 되살린다', () {
      final result = parseReplayResponse(
        content: reply(
          <Map<String, dynamic>>[
            {'ids': ['1'], 'role': 'HOST', 'text': '내일 몇 시쯤 올 거야?'},
          ],
          <Map<String, dynamic>>[
            {'id': '5', 'reason': 'not_useful'},
          ],
        ),
        source: source,
      );
      expect(result.dropped, isEmpty);
      expect(result.turns.map((t) => t.text), contains('Sounds good to me.'));
      expect(result.warnings.map((w) => w.kind), contains('unknown_reason'));
    });

    test('잡음·추임새·중복 셋만 지울 수 있다', () {
      expect(kReplayDropReasons, <String>{'noise', 'filler', 'duplicate'});
    });

    test('응답이 JSON이 아니면 원본을 그대로 쓴다', () {
      final result =
          parseReplayResponse(content: '미안 못 하겠어', source: source);
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
        {'ids': ['1'], 'role': 'HOST', 'text': '내일 몇 시쯤 올 거야?'},
        {'ids': ['2'], 'role': 'GUEST', 'text': 'Probably around six?'},
        {'ids': ['3', '4'], 'role': 'HOST', 'text': '아 그래? 그러면 저녁 같이 먹자.'},
        {'ids': ['5'], 'role': 'GUEST', 'text': 'Sounds good to me.'},
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
        {'ids': ['1'], 'role': 'HOST', 'text': '내일 몇 시쯤 올 거야?'},
        {'ids': <String>[], 'role': 'HOST', 'text': '그럼 일곱 시에 보자.'},
      ]);
      expect(judgeReplay(result: r, sourceCount: source.length).reasons,
          contains('invented_turn'));
    });

    test('원본의 절반 가까이를 지우면 되돌린다', () {
      final r = res(
        <Map<String, dynamic>>[
          {'ids': ['1'], 'role': 'HOST', 'text': '내일 몇 시쯤 올 거야?'},
          {'ids': ['2'], 'role': 'GUEST', 'text': 'Probably around six?'},
        ],
        <Map<String, dynamic>>[
          {'id': '3', 'reason': 'filler'},
          {'id': '4', 'reason': 'filler'},
          {'id': '5', 'reason': 'duplicate'},
        ],
      );
      expect(judgeReplay(result: r, sourceCount: source.length).reasons,
          contains('too_much_dropped'));
    });

    test('모델이 절반을 흘리면 — 되살아나더라도 — 되돌린다', () {
      final r = res(<Map<String, dynamic>>[
        {'ids': ['1'], 'role': 'HOST', 'text': '내일 몇 시쯤 올 거야?'},
      ]);
      expect(judgeReplay(result: r, sourceCount: source.length).reasons,
          contains('model_lost_lines'));
    });

    test('길어짐·화자 뒤바뀜은 되돌리지 않는다 — 경고로만 남는다', () {
      final r = res(<Map<String, dynamic>>[
        {'ids': ['1'], 'role': 'GUEST', 'text': '내일 몇 시쯤 올 거야?'},
        {'ids': ['2'], 'role': 'GUEST', 'text': 'Probably around six?'},
        {'ids': ['3', '4'], 'role': 'HOST', 'text': '아 그래? 그러면 저녁 같이 먹자.'},
        {
          'ids': ['5'],
          'role': 'GUEST',
          'text': 'Sounds good to me, that works perfectly for my schedule.'
        },
      ]);
      expect(r.warnings.map((w) => w.kind),
          containsAll(<String>['speaker_moved', 'expanded']));
      expect(judgeReplay(result: r, sourceCount: source.length).useReplay,
          isTrue);
    });
  });

  group('고친 줄만 따로 본다 (A. 의미 보존)', () {
    test('손대지 않은 줄은 목록에 오르지 않는다', () {
      final r = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {'ids': ['1'], 'role': 'HOST', 'text': '내일... 어, 내일 몇 시쯤 올 거야?'},
          {'ids': ['2'], 'role': 'GUEST', 'text': 'Well, um... probably around six?'},
          {'ids': ['3'], 'role': 'HOST', 'text': '아 그래? 그러면'},
          {'ids': ['4'], 'role': 'HOST', 'text': '저녁 같이 먹자.'},
          {'ids': ['5'], 'role': 'GUEST', 'text': 'Sounds good to me.'},
        ]),
        source: source,
      );
      expect(replayEdits(result: r, source: source), isEmpty);
    });

    test('이은 줄과 고친 줄은 앞뒤가 함께 보인다', () {
      final r = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {'ids': ['1'], 'role': 'HOST', 'text': '내일 몇 시쯤 올 거야?'},
          {'ids': ['2'], 'role': 'GUEST', 'text': 'Probably around six?'},
          {'ids': ['3', '4'], 'role': 'HOST', 'text': '아 그래? 그러면 저녁 같이 먹자.'},
          {'ids': ['5'], 'role': 'GUEST', 'text': 'Sounds good to me.'},
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
    test('번역 금지가 명시되어 있다', () {
      expect(kReplayPrompt, contains('NOT translation'));
      expect(kReplayPrompt, contains('Never translate a turn'));
    });

    test('세련되게 다듬기·요약·화자 옮기기가 금지되어 있다', () {
      expect(kReplayPrompt, contains('more native'));
      expect(kReplayPrompt, contains('Summarise'));
      expect(kReplayPrompt, contains('Move words from one speaker'));
    });

    test('애매하면 그대로 두는 것이 기본이다', () {
      expect(kReplayPrompt, contains('WHEN IN DOUBT, KEEP THE LINE EXACTLY AS IT IS'));
    });
  });
}
