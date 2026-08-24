import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/step_expansion_builder.dart';

/// 대화가 끝난 뒤 확장 사다리를 재구성하는 자리의 검증 테스트.
///
/// 네트워크를 태우지 않는다. 여기서 잡으려는 건 모델이 **틀린 모양으로**
/// 돌려줬을 때 P2가 깨지지 않는지다 — 한글이 섞이거나, 청크가 문장을 덮지
/// 못하거나, 강조 좌표가 문장 안에 없는 경우.
String _json(List<Map<String, dynamic>> steps) =>
    jsonEncode(<String, dynamic>{'steps': steps});

void main() {
  group('정상 사다리', () {
    const seed = 'I have been thinking about leaving my job.';
    const second =
        'I have been thinking about leaving my job, not because I hate it.';

    final content = _json(<Map<String, dynamic>>[
      <String, dynamic>{
        'text': seed,
        'added_meaning': '회사를 그만둘 생각이 있다',
        'primary_morph': '',
      },
      <String, dynamic>{
        'text': second,
        'added_meaning': '일이 싫어서는 아니다',
        'primary_morph': 'not because I hate it',
        'chunks': <Map<String, dynamic>>[
          <String, dynamic>{
            'text': 'I have been thinking about leaving my job,',
            'type': 'evolved',
            'from': 'I have been thinking about leaving my job.',
          },
          <String, dynamic>{
            'text': 'not because I hate it.',
            'type': 'new',
          },
        ],
      },
    ]);

    test('단계 번호는 1부터, 마지막이 최종문장이다', () {
      final result = StepExpansionBuilder.parseResponse(content);
      expect(result.isUsable, isTrue);
      expect(result.failure, StepExpansionFailure.none);
      expect(result.steps.map((s) => s.step), <int>[1, 2]);
      expect(result.finalSentence, second);
    });

    test('첫 칸은 비교 대상이 없어 통째로 new이고 강조가 없다', () {
      final first = StepExpansionBuilder.parseResponse(content).steps.first;
      expect(first.chunks, hasLength(1));
      expect(first.chunks.single.type, 'new');
      expect(first.chunks.single.text, seed);
      expect(first.primaryMorph, isEmpty);
    });

    test('둘째 칸은 직전 문장에 대고 잰다', () {
      final step2 = StepExpansionBuilder.parseResponse(content).steps[1];
      expect(step2.chunks.map((c) => c.type), <String>['evolved', 'new']);
      expect(step2.chunks.first.from, contains('leaving my job'));
      expect(step2.primaryMorph, 'not because I hate it');
      expect(step2.addedMeaning, '일이 싫어서는 아니다');
    });

    test('Firestore로 나갈 모양에 최종문장이 함께 실린다', () {
      final json = StepExpansionBuilder.parseResponse(content).toJson();
      expect(json['final_sentence'], second);
      expect((json['expansions'] as List), hasLength(2));
    });
  });

  group('망가진 응답을 걸러낸다', () {
    test('JSON이 아니면 parseError', () {
      expect(
        StepExpansionBuilder.parseResponse('sorry, I cannot do that').failure,
        StepExpansionFailure.parseError,
      );
    });

    test('steps가 비면 validationError', () {
      expect(
        StepExpansionBuilder.parseResponse('{"steps":[]}').failure,
        StepExpansionFailure.validationError,
      );
    });

    test('영어 자리에 한글이 남은 칸은 버린다', () {
      final result = StepExpansionBuilder.parseResponse(_json(
        <Map<String, dynamic>>[
          <String, dynamic>{'text': 'I want to travel alone.'},
          <String, dynamic>{'text': '혼자 여행을 가고 싶다.'},
        ],
      ));
      expect(result.steps, hasLength(1));
      expect(result.finalSentence, 'I want to travel alone.');
    });

    test('한 칸도 못 건지면 validationError로 떨어진다', () {
      expect(
        StepExpansionBuilder.parseResponse(
          _json(<Map<String, dynamic>>[
            <String, dynamic>{'text': '전부 한국어입니다.'}
          ]),
        ).failure,
        StepExpansionFailure.validationError,
      );
    });

    test('같은 문장이 두 칸을 차지하지 못한다', () {
      final result = StepExpansionBuilder.parseResponse(_json(
        <Map<String, dynamic>>[
          <String, dynamic>{'text': 'I want to travel alone.'},
          <String, dynamic>{'text': 'I want to travel alone!'},
          <String, dynamic>{
            'text': 'I want to travel alone because I need some quiet.',
            'chunks': <Map<String, dynamic>>[
              <String, dynamic>{
                'text': 'I want to travel alone',
                'type': 'kept',
                'from': 'I want to travel alone.',
              },
              <String, dynamic>{
                'text': 'because I need some quiet.',
                'type': 'new',
              },
            ],
          },
        ],
      ));
      expect(result.steps, hasLength(2));
      expect(result.steps.last.chunks.last.type, 'new');
    });

    test('단계 상한을 넘으면 거기서 끊는다', () {
      final many = List<Map<String, dynamic>>.generate(
        kMaxStepExpansions + 3,
        (i) => <String, dynamic>{'text': 'Sentence number $i is here.'},
      );
      expect(
        StepExpansionBuilder.parseResponse(_json(many)).steps,
        hasLength(kMaxStepExpansions),
      );
    });
  });

  group('강조 좌표', () {
    test('문장에 없는 강조는 새로 들어온 청크로 갈아 끼운다', () {
      final result = StepExpansionBuilder.parseResponse(_json(
        <Map<String, dynamic>>[
          <String, dynamic>{'text': 'I need a break.'},
          <String, dynamic>{
            'text': 'I need a break because work has been draining.',
            // 문장 어디에도 없는 문자열이다 — 그대로 쓰면 P2가 못 칠한다.
            'primary_morph': 'totally exhausted',
            'chunks': <Map<String, dynamic>>[
              <String, dynamic>{
                'text': 'I need a break',
                'type': 'kept',
                'from': 'I need a break.',
              },
              <String, dynamic>{
                'text': 'because work has been draining.',
                'type': 'new',
              },
            ],
          },
        ],
      ));
      expect(result.steps.last.primaryMorph, 'because work has been draining.');
    });

    test('청크가 문장을 덮지 못하면 통짜 fallback으로 내려간다', () {
      final result = StepExpansionBuilder.parseResponse(_json(
        <Map<String, dynamic>>[
          <String, dynamic>{'text': 'I need a break.'},
          <String, dynamic>{
            'text': 'I need a break because work has been draining.',
            'chunks': <Map<String, dynamic>>[
              // 뒷부분이 통째로 빠져 있다.
              <String, dynamic>{
                'text': 'I need a break',
                'type': 'kept',
                'from': 'I need a break.',
              },
            ],
          },
        ],
      ));
      final last = result.steps.last;
      expect(last.chunks, hasLength(1));
      expect(last.chunks.single.text, last.text);
    });
  });

  group('transcript 정리', () {
    test('라벨은 USER / AI 둘뿐이고 줄바꿈은 한 줄로 눕는다', () {
      final formatted =
          StepExpansionBuilder.formatTranscript(<StepExpansionTurn>[
        const StepExpansionTurn(isUser: true, text: '회사\n그만두고  싶어.'),
        const StepExpansionTurn(isUser: false, text: '어떤 점이 제일 힘드세요?'),
      ]);
      expect(formatted, 'USER: 회사 그만두고 싶어.\nAI: 어떤 점이 제일 힘드세요?');
    });
  });

  group('지시문', () {
    test('유저가 받아들이지 않은 AI 제안을 빼라고 적혀 있다', () {
      final prompt = StepExpansionBuilder.buildSysPrompt(
          originLang: 'Korean', targetLang: 'English');
      expect(prompt, contains('the AI raised and the user did not take up'));
      expect(prompt, contains("Improve the expression, not the user's story."));
    });

    test('턴 수와 단계 수가 1:1이 아니라고 못 박는다', () {
      final prompt = StepExpansionBuilder.buildSysPrompt(
          originLang: 'Korean', targetLang: 'English');
      expect(prompt, contains('NOT one-to-one'));
    });

    test('영어 TARGET이면 로비 스타일 지시가 함께 실린다', () {
      final prompt = StepExpansionBuilder.buildSysPrompt(
          originLang: 'Korean', targetLang: 'English');
      expect(prompt, contains('[ENGLISH STYLE'));
    });

    test('영어가 아니면 스타일이 붙지 않는다', () {
      final prompt = StepExpansionBuilder.buildSysPrompt(
          originLang: 'Korean', targetLang: 'Japanese');
      expect(prompt, isNot(contains('[ENGLISH STYLE')));
    });
  });
}
