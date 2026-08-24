import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/widgets/routine_mode_step_expand.dart';

/// Step Expand 대화방이 **실제로** AI에게 보내는 지시문을 고정한다.
///
/// 이 방은 상담방이 아니라 작업실이다 — 코치가 자기가 무슨 일을 하는지
/// 드러내고, 무엇이 부족한지 말하고, 방향을 제안한다. 여기 적힌 규칙은
/// 구현 세부가 아니라 제품 정의라서, 누가 프롬프트를 손보다 하나를 흘리면
/// 방이 다시 "이야기를 들어주는 AI"나 "학습 절차"로 되돌아간다.
///
/// ⚠️ 대상은 [buildStepExpandConsultInstructions] 하나다. 이 파일 안에는
/// 첫 마디 생성기의 비슷한 프롬프트가 따로 있고, 그건 여기 대상이 아니다.
void main() {
  final ko = buildStepExpandConsultInstructions('Korean');
  final ja = buildStepExpandConsultInstructions('Japanese');

  group('코치는 협업을 숨기지 않는다', () {
    test('드러내놓고 일한다고 적혀 있다', () {
      expect(ko, contains('skilled writing coach and sentence-building expert'));
      expect(ko, contains('you work openly'));
      expect(ko, contains('Never hide what you are doing.'));
    });

    test('예전의 "숨겨라" 규칙이 남아 있지 않다', () {
      // 이 둘이 살아 있으면 코치가 다시 그냥 듣는 사람이 된다.
      expect(ko, isNot(contains('Never say or hint that you write')));
      expect(ko, isNot(contains('They must never feel it')));
    });

    test('실력은 어휘가 아니라 판단에서 드러난다', () {
      expect(ko, contains('it shows in your JUDGEMENT, not in your vocabulary'));
      expect(ko, contains('Never literary, never academic.'));
    });
  });

  group('묻지 말고 제안한다', () {
    test('부족한 것을 짚고 이유를 말하라고 적혀 있다', () {
      expect(ko,
          contains('Work out what the thought is actually missing, then propose it'));
      expect(ko, contains('Pick the ONE that would help most right now.'));
    });

    test('맨 질문과 제안의 차이를 예시로 못 박는다', () {
      expect(ko, contains('Not "왜요?" but'));
      expect(ko, contains('Not "어떤 기분이었어요?" but'));
    });

    test('덜어내는 것도 코치의 일이다', () {
      expect(ko, contains('Prune as well as add.'));
      expect(ko, contains('Rich, never scattered.'));
    });
  });

  group('단계 라벨은 금지', () {
    test('완성본을 납품하지 말라고 적혀 있다', () {
      expect(ko, contains('1차 완성 / 2차 완성 / 최종본 / Expansion 3'));
      expect(ko, contains('No numbered drafts, no stage labels, no progress reports.'));
    });

    test('되짚기 자체는 허용한다 — 금지되는 건 라벨이다', () {
      expect(ko, contains('You may say the thought back in Korean'));
      expect(ko, contains('That is ordinary collaboration.'));
    });
  });

  group('방은 영어를 만들지 않는다', () {
    test('영어 생성이 여기가 아니라고 못 박는다', () {
      expect(ko, contains('never'));
      expect(ko, contains('build an English version here'));
      expect(ko, contains('that happens later, somewhere else'));
    });

    test('출력 언어는 유저의 언어로 고정된다', () {
      expect(ko, contains('Everything you say stays in Korean.'));
      expect(ja, contains('Everything you say stays in Japanese.'));
    });

    test('PART 1 / PART 2 2단 출력 규약이 없다', () {
      expect(ko, isNot(contains('PART 1')));
      expect(ko, isNot(contains('PART 2')));
    });
  });

  group('생각의 주인은 유저다', () {
    test('코치가 낸 것은 유저가 집기 전까지 코치 것이다', () {
      expect(ko, contains('stays yours until they pick it up'));
      expect(ko, contains('never carry it on as something they said'));
    });

    test('수정·삭제하면 최신 의도가 즉시 이긴다', () {
      expect(ko, contains('that newest version wins'));
      expect(ko, contains('quietly keep it alive underneath'));
    });

    test('없는 사실·감정을 지어내지 않는다', () {
      expect(ko,
          contains('Invent a fact, a feeling, or a reason they did not give you.'));
      expect(ko, contains('Tell them what they feel, or tell them what they meant.'));
    });

    test('사람이 아니라 생각을 평가한다', () {
      expect(ko, contains('You assess the thought, never them.'));
    });
  });

  group('턴 수를 모르고, 끝내지도 않는다', () {
    test('남은 턴·마지막 턴 개념이 없다', () {
      expect(ko, isNot(contains('final turn')));
      expect(ko, isNot(contains('MAX_TURNS')));
      expect(ko, isNot(contains('of 5')));
    });

    test('충분해지면 한 번 말하고 멈춘다', () {
      expect(ko, contains('이 정도면 이야기가 충분히 됩니다.'));
      expect(ko, contains('a form they'));
    });

    test('종료 권한이 유저에게 있다', () {
      expect(ko, contains('You never close the conversation'));
      expect(ko, contains('they decide when this ends'));
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
