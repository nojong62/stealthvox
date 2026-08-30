// 🎬 [DUO-REPLAY] 맥락 기반 복원이 실제로 성립하는지 지키는 시험.
//
// 모델을 부르지 않는다. 모델이 **규칙대로 답했을 때** 우리 쪽 빗장·정리·판정이
// 그 답을 그대로 살리는지, 그리고 규칙을 어긴 답을 되돌리는지만 본다.
// (프롬프트 문구 자체는 `duo_replay_rules_test.dart`가 지킨다)
//
// 지시받은 네 케이스가 이 파일의 뼈대다.
//   A. 문맥에서 고립된 "안녕하세요."는 빠진다
//   B. 대화의 주제인 "러시아"는 절대 안 빠진다
//   C. 같은 화자의 토막 둘이 한 문장으로 합쳐진다
//   D. 정상 8줄 + 고립 2줄 → 전체 fallback 없이 Replay가 만들어진다

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_canonical.dart';
import 'package:stealth_vox/custom_code/services/duo_replay.dart';
import 'package:stealth_vox/custom_code/services/duo_replay_rules.dart';
import 'package:stealth_vox/custom_code/services/duo_study_state.dart';

ReplaySourceLine line(
  String id,
  String role,
  String text, {
  int? spokenAtMs,
  String? state,
  double? rmsDbfs,
  String? sttSource,
}) =>
    ReplaySourceLine(
      id: id,
      role: role,
      text: text,
      spokenAtMs: spokenAtMs,
      state: state,
      rmsDbfs: rmsDbfs,
      sttSource: sttSource,
    );

/// 모델이 돌려줬다고 가정할 JSON.
String reply(List<Map<String, dynamic>> turns,
        [List<Map<String, String>> dropped = const []]) =>
    jsonEncode(<String, dynamic>{'turns': turns, 'dropped': dropped});

void main() {
  group('A. 문맥에서 고립된 줄은 빠진다', () {
    final source = <ReplaySourceLine>[
      line('1', 'HOST', '오늘 뭐 먹을까?'),
      line('2', 'GUEST', '김치찌개 어때?'),
      line('3', 'HOST', '안녕하세요.'), // ← 앞뒤 어디와도 안 이어진다
      line('4', 'GUEST', '좋아. 그거 먹자.'),
    ];

    test('"안녕하세요."가 context 사유로 빠지고 나머지는 그대로 남는다', () {
      final result = parseReplayResponse(
        content: reply(
          <Map<String, dynamic>>[
            {
              'ids': ['1'],
              'role': 'HOST',
              'text': '오늘 뭐 먹을까?'
            },
            {
              'ids': ['2'],
              'role': 'GUEST',
              'text': '김치찌개 어때?'
            },
            {
              'ids': ['4'],
              'role': 'GUEST',
              'text': '좋아. 그거 먹자.'
            },
          ],
          <Map<String, String>>[
            {'id': '3', 'reason': 'context'},
          ],
        ),
        source: source,
      );

      expect(result.turns.map((t) => t.text), <String>[
        '오늘 뭐 먹을까?',
        '김치찌개 어때?',
        '좋아. 그거 먹자.',
      ]);
      expect(result.dropped.single.id, '3');
      expect(result.dropped.single.reason, 'context');
      // 지어낸 줄이 없으니 경고도 없다.
      expect(result.warnings, isEmpty);
    });

    test('그 판을 그대로 쓴다 — 한 줄 뺐다고 되돌리지 않는다', () {
      final result = parseReplayResponse(
        content: reply(
          <Map<String, dynamic>>[
            {
              'ids': ['1'],
              'role': 'HOST',
              'text': '오늘 뭐 먹을까?'
            },
            {
              'ids': ['2'],
              'role': 'GUEST',
              'text': '김치찌개 어때?'
            },
            {
              'ids': ['4'],
              'role': 'GUEST',
              'text': '좋아. 그거 먹자.'
            },
          ],
          <Map<String, String>>[
            {'id': '3', 'reason': 'context'},
          ],
        ),
        source: source,
      );
      final verdict = judgeReplay(result: result, sourceCount: source.length);
      expect(verdict.useReplay, isTrue, reason: verdict.reasons.join(','));
    });

    test('context는 아는 사유다 — 모르는 사유였다면 되살아난다', () {
      final bad = parseReplayResponse(
        content: reply(
          <Map<String, dynamic>>[
            {
              'ids': ['1'],
              'role': 'HOST',
              'text': '오늘 뭐 먹을까?'
            },
          ],
          <Map<String, String>>[
            {'id': '3', 'reason': 'looked_weird'},
          ],
        ),
        source: source,
      );
      expect(bad.warnings.map((w) => w.kind), contains('unknown_reason'));
      // 되살아난 줄은 unlisted로 넘어간다 — 아무 이유로나 지우지 못한다.
      expect(bad.dropped.firstWhere((d) => d.id == '3').reason, 'unlisted');
    });
  });

  group('B. 대화의 주제인 낱말은 절대 안 빠진다', () {
    final source = <ReplaySourceLine>[
      line('1', 'HOST', '러시아 가 본 적 있어?'),
      line('2', 'GUEST', '아니, 아직 없어.'),
    ];

    test('"러시아"가 그대로 남고 아무것도 안 빠진다', () {
      final result = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {
            'ids': ['1'],
            'role': 'HOST',
            'text': '러시아 가 본 적 있어?'
          },
          {
            'ids': ['2'],
            'role': 'GUEST',
            'text': '아니, 아직 없어.'
          },
        ]),
        source: source,
      );
      expect(result.turns.first.text, contains('러시아'));
      expect(result.dropped, isEmpty);
      expect(judgeReplay(result: result, sourceCount: 2).useReplay, isTrue);
    });

    test('두 줄짜리 통화도 대화로 성립한다 — 짧다고 되돌리지 않는다', () {
      final result = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {
            'ids': ['1'],
            'role': 'HOST',
            'text': '러시아 가 본 적 있어?'
          },
          {
            'ids': ['2'],
            'role': 'GUEST',
            'text': '아니, 아직 없어.'
          },
        ]),
        source: source,
      );
      expect(result.turns.length, kReplayMinTurns);
      expect(judgeReplay(result: result, sourceCount: 2).useReplay, isTrue);
    });
  });

  group('C. 같은 화자의 토막은 한 문장으로 합쳐진다', () {
    final source = <ReplaySourceLine>[
      line('1', 'HOST', '오늘 저녁에'),
      line('2', 'HOST', '집에 갈 거예요.'),
      line('3', 'GUEST', '아, 그래요?'),
    ];

    test('두 id가 한 줄이 되고 원본 고리가 둘 다 남는다', () {
      final result = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {
            'ids': ['1', '2'],
            'role': 'HOST',
            'text': '오늘 저녁에 집에 갈 거예요.'
          },
          {
            'ids': ['3'],
            'role': 'GUEST',
            'text': '아, 그래요?'
          },
        ]),
        source: source,
      );
      expect(result.turns.first.text, '오늘 저녁에 집에 갈 거예요.');
      expect(result.turns.first.sourceIds, <String>['1', '2']);
      // 합친 것은 화자가 같으므로 화자 경고가 없어야 한다.
      expect(result.warnings.map((w) => w.kind), isNot(contains('speaker_merge')));
      expect(result.dropped, isEmpty);
    });

    test('합친 줄은 "고친 줄" 목록에 오른다 — 무엇이 바뀌었는지 볼 수 있다', () {
      final result = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {
            'ids': ['1', '2'],
            'role': 'HOST',
            'text': '오늘 저녁에 집에 갈 거예요.'
          },
          {
            'ids': ['3'],
            'role': 'GUEST',
            'text': '아, 그래요?'
          },
        ]),
        source: source,
      );
      // 토막을 공백으로 이은 것과 결과가 **글자까지 같다** = 손댄 것이 없다.
      // 잇기만 한 병합은 "고친 줄"이 아니다 — 의미가 바뀔 수 없기 때문이다.
      expect(replayEdits(result: result, source: source), isEmpty);
    });

    test('잇는 김에 글자를 바꾸면 그 줄만 "고친 줄"로 잡힌다', () {
      final result = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {
            'ids': ['1', '2'],
            'role': 'HOST',
            // 어미를 손봤다 → 무엇이 바뀌었는지 사람이 볼 수 있어야 한다.
            'text': '오늘 저녁에 집에 갈게요.'
          },
          {
            'ids': ['3'],
            'role': 'GUEST',
            'text': '아, 그래요?'
          },
        ]),
        source: source,
      );
      final edits = replayEdits(result: result, source: source);
      expect(edits.length, 1, reason: '손대지 않은 줄은 목록에 오르지 않는다');
      expect(edits.single.ids, <String>['1', '2']);
      expect(edits.single.before, '오늘 저녁에 집에 갈 거예요.');
      expect(edits.single.after, '오늘 저녁에 집에 갈게요.');
    });

    test('서로 다른 화자를 묶으면 경고가 남고 화자는 원본으로 되돌아간다', () {
      final result = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {
            'ids': ['2', '3'],
            'role': 'GUEST',
            'text': '집에 갈 거예요. 아, 그래요?'
          },
        ]),
        source: source,
      );
      expect(result.warnings.map((w) => w.kind), contains('speaker_merge'));
      expect(result.turns.single.role, 'HOST', reason: '원본 첫 id의 화자로 되돌린다');
    });
  });

  group('D. 정상 8줄 + 고립 2줄 → 전체 fallback 없이 만들어진다', () {
    final source = <ReplaySourceLine>[
      line('1', 'HOST', '주말에 뭐 했어?'),
      line('2', 'GUEST', '그냥 집에 있었어.'),
      line('3', 'HOST', '검은색'), // ← 고립
      line('4', 'GUEST', '너는?'),
      line('5', 'HOST', '나는 등산 갔어.'),
      line('6', 'GUEST', '어디로?'),
      line('7', 'HOST', '북한산.'),
      line('8', 'GUEST', '그녀는'), // ← 고립
      line('9', 'HOST', '사람 진짜 많더라.'),
      line('10', 'GUEST', '다음엔 나도 갈래.'),
    ];

    ReplayResult run() => parseReplayResponse(
          content: reply(
            <Map<String, dynamic>>[
              for (final s in source)
                if (s.id != '3' && s.id != '8')
                  {
                    'ids': [s.id],
                    'role': s.role,
                    'text': s.text
                  },
            ],
            <Map<String, String>>[
              {'id': '3', 'reason': 'context'},
              {'id': '8', 'reason': 'context'},
            ],
          ),
          source: source,
        );

    test('고립 2줄만 빠지고 8줄이 남는다', () {
      final result = run();
      expect(result.turns.length, 8);
      expect(result.dropped.map((d) => d.id).toSet(), <String>{'3', '8'});
      expect(result.dropped.every((d) => d.reason == 'context'), isTrue);
    });

    test('**전체 fallback이 걸리지 않는다** — 이번 작업의 핵심 기준', () {
      final verdict = judgeReplay(result: run(), sourceCount: source.length);
      expect(verdict.useReplay, isTrue,
          reason: '고립 두 줄 때문에 대본 전체를 포기하면 안 된다: ${verdict.reasons}');
      expect(verdict.reasons, isEmpty);
    });

    test('20%를 지워도 되돌릴 이유가 아니다', () {
      final result = run();
      final double droppedRatio = result.dropped.length / source.length;
      expect(droppedRatio, greaterThanOrEqualTo(0.2));
      expect(judgeReplay(result: result, sourceCount: source.length).useReplay,
          isTrue);
    });
  });

  group('되돌리는 경우는 그대로 좁다', () {
    final source = <ReplaySourceLine>[
      line('1', 'HOST', '갈까?'),
      line('2', 'GUEST', '응.'),
    ];

    test('원본에 없는 줄을 지어내면 되돌린다', () {
      final result = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {
            'ids': <String>[],
            'role': 'HOST',
            'text': '내일 세 시에 만나기로 했어.'
          },
        ]),
        source: source,
      );
      expect(result.warnings.map((w) => w.kind), contains('invented'));
      expect(judgeReplay(result: result, sourceCount: 2).fallsBack, isTrue);
    });

    test('한 사람 말만 남으면 되돌린다', () {
      final result = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {
            'ids': ['1'],
            'role': 'HOST',
            'text': '갈까?'
          },
        ], <Map<String, String>>[
          {'id': '2', 'reason': 'context'},
        ]),
        source: source,
      );
      final verdict =
          judgeReplay(result: result, sourceCount: 2, sourceSpeakers: 2);
      expect(verdict.fallsBack, isTrue);
      expect(verdict.reasons, contains('speaker_collapsed'));
    });

    test('남은 줄이 대화라 부를 수 없을 만큼 적으면 되돌린다', () {
      final long = <ReplaySourceLine>[
        for (var i = 0; i < 6; i++) line('$i', i.isEven ? 'HOST' : 'GUEST', '말$i'),
      ];
      final result = parseReplayResponse(
        content: reply(<Map<String, dynamic>>[
          {
            'ids': ['0'],
            'role': 'HOST',
            'text': '말0'
          },
        ], <Map<String, String>>[
          for (var i = 1; i < 6; i++) {'id': '$i', 'reason': 'context'},
        ]),
        source: long,
      );
      final verdict = judgeReplay(result: result, sourceCount: long.length);
      expect(verdict.fallsBack, isTrue);
      expect(verdict.reasons, contains('too_few_turns'));
    });
  });

  group('입력 정리 — 모델에게 묻기 전에 기계가 먼저 치운다', () {
    test('canonical이 이미 흡수·감춘 줄은 넣지 않는다', () {
      final prepared = prepareReplaySource(<ReplaySourceLine>[
        line('1', 'HOST', '오늘 저녁에', state: kStudyStateIncluded),
        line('2', 'HOST', '집에 갈 거예요.', state: kStudyStateMerged),
        line('3', 'GUEST', '메아리', state: kStudyStateHiddenEcho),
        line('4', 'GUEST', '같은 말', state: kStudyStateHiddenDuplicate),
        line('5', 'GUEST', '아, 그래요?', state: kStudyStateIncluded),
      ]);
      expect(prepared.map((l) => l.id), <String>['1', '5']);
    });

    test('망설임은 남긴다 — 뺄지 말지는 앞뒤를 보고 정할 일이다', () {
      final prepared = prepareReplaySource(<ReplaySourceLine>[
        line('1', 'HOST', '음...', state: kStudyStateHiddenHesitation),
        line('2', 'HOST', '갈까?', state: kStudyStateIncluded),
      ]);
      expect(prepared.map((l) => l.id), <String>['1', '2']);
    });

    test('빈 줄과 중복 id는 걸러진다', () {
      final prepared = prepareReplaySource(<ReplaySourceLine>[
        line('1', 'HOST', '  '),
        line('2', 'HOST', '갈까?'),
        line('2', 'HOST', '갈까?'),
      ]);
      expect(prepared.length, 1);
      expect(prepared.single.id, '2');
    });

    test('low_level로 걸린 발화는 애초에 오지 않는다 — 여기서 거를 것이 없다', () {
      // 게이트가 저장 전에 막으므로 canonical에 아예 없다. 그래도 세기 값이
      // 실려 오면 그대로 통과시킨다 — 세기만으로는 지우지 않는다.
      final prepared = prepareReplaySource(<ReplaySourceLine>[
        line('1', 'HOST', '네.', state: kStudyStateIncluded, rmsDbfs: -46.0),
      ]);
      expect(prepared.length, 1,
          reason: '세기만 보고 Replay에서 추가로 지우지 않는다');
    });
  });

  group('payload — 통화 전체와 보조 신호를 함께 준다', () {
    test('있는 신호만 싣는다', () {
      final payload = buildReplayPayload(<ReplaySourceLine>[
        line('1', 'HOST', '갈까?',
            spokenAtMs: 1000,
            state: kStudyStateIncluded,
            rmsDbfs: -23.84,
            sttSource: 'local_mic'),
        line('2', 'GUEST', '응.'),
      ]);
      final turns = payload['turns'] as List;
      final first = turns.first as Map<String, dynamic>;
      expect(first['id'], '1');
      expect(first['role'], 'HOST');
      expect(first['text'], '갈까?');
      expect(first['spoken_at_ms'], 1000);
      expect(first['state'], kStudyStateIncluded);
      expect(first['rms_dbfs'], -23.8);
      expect(first['stt_source'], 'local_mic');

      // 없는 신호는 키 자체가 없다 — 빈 값을 근거로 읽히면 안 된다.
      final second = turns.last as Map<String, dynamic>;
      expect(second.containsKey('rms_dbfs'), isFalse);
      expect(second.containsKey('state'), isFalse);
      expect(second.containsKey('stt_source'), isFalse);
    });

    test('줄을 따로 쪼개 보내지 않는다 — 통화 한 벌이 통째로 간다', () {
      final payload = buildReplayPayload(<ReplaySourceLine>[
        line('1', 'HOST', 'a'),
        line('2', 'GUEST', 'b'),
        line('3', 'HOST', 'c'),
      ]);
      expect((payload['turns'] as List).length, 3);
    });
  });

  group('canonical에서 입력을 만든다 — raw transcript를 직접 읽지 않는다', () {
    test('canonical 문서의 turns를 시간순으로 읽는다', () {
      final lines = replaySourceFromCanonical(<String, dynamic>{
        'turns': <Map<String, dynamic>>[
          {
            'role': 'GUEST',
            'text': '나중 말',
            'source_ids': ['b'],
            'spoken_at_ms': 2000,
            'state': kStudyStateIncluded,
          },
          {
            'role': 'HOST',
            'text': '먼저 말',
            'source_ids': ['a'],
            'spoken_at_ms': 1000,
            'state': kStudyStateIncluded,
          },
        ],
      });
      expect(lines.map((l) => l.text), <String>['먼저 말', '나중 말']);
      expect(lines.first.id, 'a', reason: '원본 고리가 그대로 따라와야 Original Call과 이어진다');
    });

    test('turns가 없거나 빈 문서는 빈 목록이다', () {
      expect(replaySourceFromCanonical(<String, dynamic>{}), isEmpty);
      expect(
          replaySourceFromCanonical(
              <String, dynamic>{'turns': <dynamic>[]}),
          isEmpty);
    });
  });

  group('canonical과 Replay는 서로 다른 자리에 산다', () {
    test('문서 경로가 겹치지 않는다', () {
      expect(kDuoReplayCollection, 'replay');
      expect(kDuoReplayCollection, isNot(kDuoCanonicalCollection));
      expect(kDuoReplayDoc, kDuoCanonicalDoc); // 둘 다 'current'
    });

    test('직접 대화 방에만 Replay가 걸린다', () {
      expect(
          duoRoomHasReplay(<String, dynamic>{
            kDuoModeField: 'direct',
            kDuoRoomIdField: 'room1',
          }),
          isTrue);
      expect(
          duoRoomHasReplay(<String, dynamic>{
            kDuoModeField: 'interpreter',
            kDuoRoomIdField: 'room1',
          }),
          isFalse);
      // 공유 고리가 없는 옛 방은 소급하지 않는다.
      expect(
          duoRoomHasReplay(<String, dynamic>{kDuoModeField: 'direct'}), isFalse);
    });

    test('화면이 쓰는 두 이름이 정해져 있다', () {
      expect(kOriginalCallLabel, 'Original Call');
      expect(kConversationReplayLabel, 'Conversation Replay');
    });
  });
}
