import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/widgets/routine_mode_step_expand.dart';

/// Step Expand 대화방이 **실제로** AI에게 보내는 지시문을 고정한다.
///
/// 이 방의 한 문장은 이것이다 —
/// **"AI는 다음 질문을 찾지 않는다. 현재 생각을 더 좋은 문장으로 발전시킬 수
/// 있는 다음 방향을 찾아 제안한다."**
///
/// 여기 적힌 규칙은 구현 세부가 아니라 제품 정의라서, 누가 프롬프트를 손보다
/// 하나를 흘리면 방이 다시 "이야기를 들어주는 AI"나 "정보를 캐는 인터뷰어"로
/// 되돌아간다. 특히 **추천**이 빠지면 코치가 아니라 객관식 문제지가 된다.
///
/// ⚠️ 대상은 [buildStepExpandConsultInstructions] 하나다. 이 파일 안에는
/// 첫 마디 생성기의 비슷한 프롬프트가 따로 있고, 그건 여기 대상이 아니다.
void main() {
  final ko = buildStepExpandConsultInstructions('Korean');
  final ja = buildStepExpandConsultInstructions('Japanese');

  group('질문이 아니라 방향을 찾는다', () {
    test('한 문장 원칙이 맨 앞에 박혀 있다', () {
      expect(ko, contains('[THE ONE PRINCIPLE]'));
      expect(ko, contains('You do not look for the next question.'));
      expect(ko, contains('the next DIRECTION'));
      expect(ko, contains('It is never the point of the turn.'));
    });

    test('원칙 블록이 다른 무엇보다 먼저 나온다', () {
      // 뒤로 밀리면 모델이 앞쪽 페르소나만 읽고 다시 인터뷰어가 된다.
      expect(ko.indexOf('[THE ONE PRINCIPLE]'),
          lessThan(ko.indexOf('[WHO YOU ARE]')));
    });

    test('방향은 기법이 아니라 의미다', () {
      expect(ko, contains('A direction is a piece of MEANING'));
      expect(ko, contains('never a writing technique'));
      expect(ko, contains('Not a direction: "이유를 붙여 볼까요?"'));
      expect(ko, contains('A direction:     "왜 그만두고 싶은지 이유를 붙이는 쪽"'));
    });
  });

  group('방향을 내놓고 하나를 추천한다', () {
    test('네 단계 턴 구성이 적혀 있다', () {
      expect(ko, contains('OFFER DIRECTIONS, THEN RECOMMEND ONE'));
      expect(ko, contains('TWO or THREE directions it could grow in.'));
      expect(ko, contains('built out of'));
      expect(ko, contains('Hand it back'));
    });

    test('추천을 빼면 안 된다고 못 박는다', () {
      expect(ko, contains('Which one YOU would take, and why, in one clause.'));
      expect(
          ko,
          contains(
              'a menu with\n   no recommendation is not coaching, it is a form'));
    });

    test('번호는 소리내어 읽히므로 말로 부른다', () {
      // 방은 TTS로 읽힌다. ①②③가 그대로 나가면 낭독이 깨진다.
      expect(ko, contains('"첫 번째", "두 번째", "세 번째"'));
      expect(ko, contains('Never use ①②③'));
      expect(ko, contains('every word of this is read out loud'));
    });

    test('예전의 "혼자 정하라"가 남아 있지 않다', () {
      // 이게 살아 있으면 방향 제시와 정면으로 부딪힌다.
      expect(ko, isNot(contains('Choose the next move yourself.')));
      expect(ko, isNot(contains('Never ask "어느 방향으로 갈까요?"')));
    });

    test('바뀌지 않을 방향은 메뉴에 올리지 않는다', () {
      expect(ko, contains('A direction that\nwould not change it is not on the menu.'));
    });
  });

  group('미국식은 단어가 아니라 순서다', () {
    test('사고 순서가 그대로 적혀 있다', () {
      expect(ko, contains('[THE SHAPE A THOUGHT GROWS INTO]'));
      expect(
          ko,
          contains(
              'Point -> Why -> Contrast or Detail -> Personal meaning -> Direction'));
      expect(ko, contains('Put the point down first'));
    });

    test('슬랭·어휘가 아니라고 못 박는다', () {
      expect(ko, contains('It is NOT American words, slang, or'));
      expect(ko, contains('It is the ORDER a thought gets built in.'));
      expect(ko, contains('nothing here leaves Korean'));
      expect(ja, contains('nothing here leaves Japanese'));
    });

    test('모든 단계를 다 거치지 않는다', () {
      expect(ko, contains('Not every stage is needed.'));
      expect(ko, contains('Never walk the stages in order like a form.'));
      expect(ko, contains('Never name the stages to the user.'));
    });
  });

  group('무엇이 되었는지 말해 준다', () {
    test('요약이 아니라 변화를 말한다', () {
      expect(ko, contains('[SAY WHAT IT BECAME]'));
      expect(ko, contains('not a summary of it, the CHANGE in it'));
      expect(ko, contains('they hear the move they just made'));
    });
  });

  group('코치는 협업을 숨기지 않는다', () {
    test('드러내놓고 일한다고 적혀 있다', () {
      expect(
          ko, contains('seasoned writing coach and sentence-building expert'));
      expect(ko, contains('you work openly'));
      expect(ko, contains('Never hide what you are doing.'));
    });

    test('예전의 "숨겨라" 규칙이 남아 있지 않다', () {
      expect(ko, isNot(contains('Never say or hint that you write')));
      expect(ko, isNot(contains('They must never feel it')));
    });

    test('실력은 어휘가 아니라 판단에서 드러난다', () {
      expect(
          ko, contains('it shows in your JUDGEMENT, not in your vocabulary'));
      expect(ko, contains('Never literary, never academic.'));
    });
  });

  group('한 단어부터 문장을 세운다', () {
    test('맨 단어를 실패가 아니라 재료로 취급한다', () {
      expect(ko, contains('One meaningful word is enough.'));
      expect(ko, contains('raw word -> intended angle'));
      expect(ko,
          contains('Treat a raw word as material, not as a failed answer.'));
    });

    test('중심이 없으면 방향부터 묻지 않는다', () {
      // 맨 단어에는 아직 Point가 없다. 여기서 방향 셋을 내밀면 헛돈다.
      expect(ko, contains('A bare word has no point yet'));
      expect(ko, contains('Settle the\npoint first, in one question'));
      expect(ko, contains('Once the point stands, go to directions'));
    });

    test('노련한 편집 기준을 조용히 쓴다', () {
      expect(ko, contains("editor's ear"));
      expect(ko, contains('A precise subject and verb'));
      expect(ko, contains('Never lecture the user with the list.'));
    });

    test('글을 모르는 유저에게 편집 판단을 떠넘기지 않는다', () {
      expect(ko, contains('THE USER BRINGS MEANING; YOU CARRY THE WRITING'));
      expect(ko, contains('Never make them diagnose the writing'));
      expect(ko,
          contains('never\nask them to choose between abstract editorial strategies'));
      expect(ko, contains('already worded, already concrete, already ranked by you'));
      expect(ko, contains('You diagnose, you rank, you\nrecommend; they decide.'));
      expect(ko, contains('Their job is to answer honestly'));
    });

    test('상담가가 아니라 문장을 직접 만드는 강사다', () {
      expect(ko, contains('NOT a counselor, therapist'));
      expect(ko, contains('Do not merely request more information.'));
      expect(ko, contains('smallest honest provisional sentence'));
      expect(ko, contains('Never praise, reassure, mirror feelings'));
    });

    test('이오덕의 삶 중심 글쓰기 원리를 인물이 아닌 수업법으로 쓴다', () {
      expect(ko, contains("LEE O-DEOK'S LIFE-CENTERED WRITING PRINCIPLES"));
      expect(ko, contains('This is a teaching framework, NOT a persona'));
      expect(
          ko, contains("user's actual life, observation, action, or belief"));
      expect(ko, contains('concrete subject and active verb'));
      expect(ko, contains('honest everyday speech'));
      expect(ko, contains('never imitate his personal voice'));
    });

    test('매 답변 전에 방향을 고르고 순위를 매긴다', () {
      expect(ko, contains("SILENT EDITOR'S PREPARATION"));
      expect(ko, contains('Mark the exact material'));
      expect(ko, contains('Find the two or three directions worth offering, and rank them.'));
      expect(ko, contains('Decide which ONE you would take'));
      expect(ko, contains('Never print these steps or their labels.'));
    });
  });

  group('단계 라벨은 금지', () {
    test('완성본을 납품하지 말라고 적혀 있다', () {
      expect(ko, contains('1차 완성 / 2차 완성 / 최종본 / Expansion 3'));
      expect(
          ko,
          contains(
              'No numbered drafts, no stage labels, no progress reports.'));
    });

    test('되짚기 자체는 허용한다 — 금지되는 건 라벨이다', () {
      expect(ko, contains('You may say the thought back in Korean'));
      expect(ko, contains('That is ordinary collaboration.'));
    });
  });

  group('방은 영어를 만들지 않는다', () {
    test('영어 생성이 여기가 아니라고 못 박는다', () {
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
      expect(
          ko,
          contains(
              'Invent a fact, a feeling, or a reason they did not give you.'));
      expect(ko,
          contains('Tell them what they feel, or tell them what they meant.'));
    });

    test('물린 방향을 다시 들이밀지 않는다', () {
      expect(ko, contains('Offer again a direction they already declined'));
    });

    test('사람이 아니라 생각을 평가한다', () {
      expect(ko, contains('You assess the thought, never them.'));
    });
  });

  group('길이는 세네 문장이다', () {
    test('메뉴가 문장을 늘리지 못하게 막는다', () {
      expect(ko, contains('Three or four short spoken sentences, and no more.'));
      expect(ko, contains('ONE sentence, not one sentence each'));
      expect(ko, contains('No line breaks and no list markers.'));
    });
  });

  group('턴 수를 모르고, 끝내지도 않는다', () {
    test('남은 턴·마지막 턴 개념이 없다', () {
      expect(ko, isNot(contains('final turn')));
      expect(ko, isNot(contains('MAX_TURNS')));
      expect(ko, isNot(contains('of 5')));
    });

    test('충분해지면 방향 제시를 멈추고 완성으로 넘어간다', () {
      expect(ko, contains('Knowing where to stop is part of the craft.'));
      expect(ko, contains('여기서 더 붙이면 오히려 중심이 흐려질 것 같아요.'));
      expect(ko, contains('지금 정도에서 문장을 한번 완성해보죠.'));
      expect(ko, contains('a form they'));
    });

    test('종료 권한이 유저에게 있다', () {
      expect(ko, contains('You never close the conversation'));
      expect(ko, contains('they decide when this ends'));
    });
  });

  group('로비 AI STYLE은 대화방에 닿지 않는다', () {
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
