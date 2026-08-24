import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/widgets/routine_mode_step_expand.dart';

/// Step Expand 대화방이 **실제로** AI에게 보내는 지시문을 고정한다.
///
/// 이 모드의 성패는 영어 생성 능력이 아니라 대화의 질에 달려 있다. 그래서
/// 여기 적힌 규칙은 구현 세부가 아니라 제품 정의에 가깝다 — 누가 프롬프트를
/// 손보다 이 중 하나를 흘리면 방이 다시 설문지가 된다.
///
/// ⚠️ 대상은 [buildStepExpandConsultInstructions] 하나다. 이 파일 안에는
/// 첫 마디 생성기의 비슷한 프롬프트가 따로 있고, 그건 여기 대상이 아니다.
void main() {
  final ko = buildStepExpandConsultInstructions('Korean');
  final ja = buildStepExpandConsultInstructions('Japanese');

  group('방은 영어를 만들지 않는다', () {
    test('PART 1 / PART 2 2단 출력 규약이 없다', () {
      expect(ko, isNot(contains('PART 1')));
      expect(ko, isNot(contains('PART 2')));
    });

    test('영어·연습·학습을 입에 담지 말라고 적혀 있다', () {
      expect(ko, contains('Never mention writing, sentences, practice, or'));
      expect(ko, contains('learning'));
    });

    test('지금까지 합쳐진 문장을 읽어 주지 않는다', () {
      expect(
        ko,
        contains(
            'Read back a combined version of everything they have said so far.'),
      );
    });

    test('출력 언어는 유저의 언어로 고정된다', () {
      expect(ko, contains('Everything you say stays in Korean.'));
      expect(ja, contains('Everything you say stays in Japanese.'));
      expect(ko, contains('Never produce another language.'));
    });
  });

  group('턴 수를 모른다', () {
    test('남은 턴·마지막 턴 개념이 프롬프트에 없다', () {
      expect(ko, isNot(contains('final turn')));
      expect(ko, isNot(contains('MAX_TURNS')));
      expect(ko, isNot(contains('of 5')));
    });
  });

  group('AI는 대화를 끝내지 않는다', () {
    test('종료 권한이 유저에게 있다고 못 박는다', () {
      expect(ko, contains('You never close the conversation'));
      expect(ko, contains('They decide when this ends.'));
    });

    test('생각이 완성됐다고 선언하지 않는다', () {
      expect(
        ko,
        contains('never announce that their thinking is'),
      );
    });

    test('충분해지면 질문을 지어내지 말라고 적혀 있다', () {
      expect(ko, contains('Stop pushing.'));
      expect(ko, contains('a form'));
    });
  });

  group('질문을 위한 질문 금지', () {
    test('질문이 첫 수단이 아니다', () {
      expect(ko, contains('Do not reach for a question first.'));
      expect(ko, contains('Ask only when none of those fit.'));
    });

    test('열린 "왜"를 막는다', () {
      expect(ko, contains('Never an open "why".'));
    });

    test('같은 질문을 말만 바꿔 다시 묻지 않는다', () {
      expect(ko,
          contains('Repeat a question you already asked, in any wording.'));
    });
  });

  group('생각의 주인은 유저다', () {
    test('AI가 꺼낸 것은 유저가 집기 전까지 AI 것이다', () {
      expect(ko, contains('yours until they pick it up'));
      expect(ko, contains('never carry it on as something they said'));
    });

    test('수정·삭제하면 최신 의도가 즉시 이긴다', () {
      expect(ko, contains('that newest version wins'));
      expect(ko, contains('quietly keep it alive underneath'));
    });

    test('유저가 무슨 뜻이었는지 설명해 주지 않는다', () {
      expect(ko, contains('Never open by telling them what they meant.'));
    });

    test('감정을 단정하거나 묻지 않는다', () {
      expect(ko,
          contains('Tell them what they feel, or ask what they feel.'));
    });
  });

  group('확장은 유저가 눈치채지 못하게 일어난다', () {
    test('생각을 다듬는 일이 AI의 몫이고 드러나면 안 된다고 적혀 있다', () {
      expect(ko, contains('That is\nyour work and it stays yours.'));
      expect(ko, contains('They must never feel it.'));
    });
  });

  group('로비 AI STYLE은 상담에 닿지 않는다', () {
    test('스타일 지시 블록이 붙지 않는다', () {
      // Native를 골랐다고 유저가 꺼내는 생각이 달라지면 안 된다.
      for (final p in <String>[ko, ja]) {
        expect(p, isNot(contains('[ENGLISH STYLE')));
        expect(p, isNot(contains('STYLE — Native')));
        expect(p, isNot(contains('STYLE — American')));
      }
    });
  });
}
