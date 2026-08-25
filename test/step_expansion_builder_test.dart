import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/step_expansion_builder.dart';

/// 방이 확정해 둔 원어 사다리를 배울글 사다리로 옮기는 자리를 고정한다.
///
/// **여기는 더 이상 "생각이 어디서 자랐는지"를 찾지 않는다.** 무엇이 붙었는지는
/// 방이 이미 알고 있고, 남은 일은 옮기는 것뿐이다. 그래서 지켜야 할 규칙도
/// 하나로 줄었다 — **다음 칸은 앞 칸으로 시작해야 한다.**
void main() {
  final ladder = <String>[
    '회사 그만두고 싶어.',
    '회사 그만두고 싶어. 매일 똑같은 일을 반복하는 게 너무 지쳐.',
  ];

  String json(List<String> steps) => jsonEncode(<String, dynamic>{
        'steps': steps.map((t) => <String, String>{'text': t}).toList(),
      });

  group('누적 사다리', () {
    test('칸마다 앞 칸을 품은 배울글이 나온다', () {
      final result = StepExpansionBuilder.parseResponse(
        json(<String>[
          'I want to quit my job.',
          "I want to quit my job. I'm worn out from doing the same thing every day.",
        ]),
        ladder: ladder,
      );
      expect(result.isUsable, isTrue);
      expect(result.steps, hasLength(2));
      expect(result.steps.first.text, 'I want to quit my job.');
      expect(result.finalSentence, endsWith('every day.'));
    });

    test('이번 칸에 붙은 원어가 근거로 실린다', () {
      final result = StepExpansionBuilder.parseResponse(
        json(<String>['A.', 'A. B.']),
        ladder: ladder,
      );
      expect(result.steps[0].addedMeaning, '회사 그만두고 싶어.');
      expect(result.steps[1].addedMeaning, '매일 똑같은 일을 반복하는 게 너무 지쳐.');
    });
  });

  group('청크는 계산으로 나온다', () {
    test('앞 칸은 kept, 새로 붙은 곳만 new다', () {
      final result = StepExpansionBuilder.parseResponse(
        json(<String>['A.', 'A. B.']),
        ladder: ladder,
      );
      final second = result.steps[1];
      expect(second.chunks.map((c) => c.type), <String>['kept', 'new']);
      expect(second.chunks.first.text, 'A.');
      expect(second.chunks.last.text.trim(), 'B.');
      // 청크를 이어 붙이면 그 칸 문장이 정확히 복원된다.
      expect(second.chunks.map((c) => c.text).join(), second.text);
    });

    test('첫 칸은 통째로 새 문장이다', () {
      final result = StepExpansionBuilder.parseResponse(
        json(<String>['A.']),
        ladder: <String>['가.'],
      );
      expect(result.steps.single.chunks.single.type, 'new');
      expect(result.steps.single.primaryMorph, isEmpty);
    });

    test('강조는 이번에 붙은 곳이다', () {
      final result = StepExpansionBuilder.parseResponse(
        json(<String>['A.', 'A. B.']),
        ladder: ladder,
      );
      expect(result.steps[1].primaryMorph, 'B.');
      expect(
          result.steps[1].text.contains(result.steps[1].primaryMorph), isTrue);
    });

    test('앞 칸을 손댄 칸은 강조를 포기하고 통짜로 둔다', () {
      // 어디가 새것인지 자신할 수 없다. 엉뚱한 곳을 칠하느니 안 칠한다.
      final result = StepExpansionBuilder.parseResponse(
        json(<String>['A.', 'Completely different.']),
        ladder: ladder,
      );
      expect(result.steps[1].primaryMorph, isEmpty);
      expect(result.steps[1].chunks.map((c) => c.text).join(),
          result.steps[1].text);
    });
  });

  group('망가진 응답을 걸러낸다', () {
    test('JSON이 아니면 parseError', () {
      final result =
          StepExpansionBuilder.parseResponse('전부 옮겼습니다.', ladder: ladder);
      expect(result.failure, StepExpansionFailure.parseError);
      expect(result.isUsable, isFalse);
    });

    test('steps가 없으면 validationError', () {
      final result =
          StepExpansionBuilder.parseResponse('{"result":[]}', ladder: ladder);
      expect(result.failure, StepExpansionFailure.validationError);
    });

    test('배울글 자리에 한글이 남은 칸은 버린다', () {
      // P2 한복판에 한국어 줄이 하나 끼는 것보다 칸을 버리는 쪽이 낫다.
      final result = StepExpansionBuilder.parseResponse(
        json(<String>['I want to quit my job.', '회사를 그만두고 싶다.']),
        ladder: ladder,
      );
      expect(result.steps, hasLength(1));
    });

    test('같은 문장이 두 칸을 차지하면 하나로 접는다', () {
      final result = StepExpansionBuilder.parseResponse(
        json(<String>['A.', 'A.']),
        ladder: ladder,
      );
      expect(result.steps, hasLength(1));
    });

    test('쓸 수 있는 칸이 하나도 없으면 validationError', () {
      final result = StepExpansionBuilder.parseResponse(
        json(<String>['회사를 그만두고 싶다.']),
        ladder: <String>['가.'],
      );
      expect(result.failure, StepExpansionFailure.validationError);
    });
  });

  group('사다리 정리', () {
    test('빈 칸과 제자리걸음을 걷어낸다', () {
      expect(
        StepExpansionBuilder.normalizeLadder(
            <String>['가.', '  ', '가.', '가. 나.']),
        <String>['가.', '가. 나.'],
      );
    });

    test('상한을 넘기지 않는다', () {
      final long = List<String>.generate(kMaxStepExpansions + 3, (i) => '칸 $i');
      expect(StepExpansionBuilder.normalizeLadder(long),
          hasLength(kMaxStepExpansions));
    });

    test('모델에 넘길 때 번호를 붙인다', () {
      expect(
        StepExpansionBuilder.formatLadder(<String>['가.', '가. 나.']),
        '1. 가.\n2. 가. 나.',
      );
    });
  });

  group('지시문', () {
    test('다음 칸은 앞 칸으로 시작해야 한다고 못 박는다', () {
      final prompt = StepExpansionBuilder.buildSysPrompt(
          originLang: 'Korean', targetLang: 'English');
      expect(prompt, contains('[THE ONE RULE]'));
      expect(prompt, contains('word for word'));
      expect(prompt, contains('carry everything before it over unchanged'));
    });

    test('한 문장으로 합치지 말라고 적혀 있다', () {
      final prompt = StepExpansionBuilder.buildSysPrompt(
          originLang: 'Korean', targetLang: 'English');
      expect(prompt, contains('Do not join the sentences into one long one.'));
      expect(prompt, contains('Never reorganise the writing'));
    });

    test('재구성 시절의 규칙이 남아 있지 않다', () {
      // 이게 살아 있으면 이 파일이 다시 "생각이 자란 자리를 찾는" 물건이 된다.
      final prompt = StepExpansionBuilder.buildSysPrompt(
          originLang: 'Korean', targetLang: 'English');
      expect(prompt, isNot(contains('WHOSE MEANING COUNTS')));
      expect(prompt, isNot(contains('NOT one-to-one')));
      expect(prompt, isNot(contains('primary_morph')));
    });

    test('영어 TARGET이면 로비 스타일이 어휘까지만 실린다', () {
      final prompt = StepExpansionBuilder.buildSysPrompt(
          originLang: 'Korean', targetLang: 'English');
      expect(prompt, contains('[ENGLISH STYLE'));
      expect(prompt, contains('Style reaches the WORDING only.'));
      expect(prompt, isNot(contains('You may reorder the information')));
    });

    test('영어가 아니면 스타일이 붙지 않는다', () {
      final prompt = StepExpansionBuilder.buildSysPrompt(
          originLang: 'Korean', targetLang: 'Japanese');
      expect(prompt, isNot(contains('[ENGLISH STYLE')));
    });
  });

  group('저장값 다시 읽기', () {
    test('저장해 둔 사다리를 그대로 되살린다', () {
      final result = StepExpansionBuilder.parseResponse(
        json(<String>['A.', 'A. B.']),
        ladder: ladder,
      );
      final stored = result.toJson()['expansions'];
      final reread = parseStoredExpansions(stored);
      expect(reread.map((s) => s.text), result.steps.map((s) => s.text));
      expect(reread[1].primaryMorph, 'B.');
    });
  });
}
