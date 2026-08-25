import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/widgets/routine_mode_step_expand.dart';

/// Step Expand 대화방이 **실제로** AI에게 보내는 지시문과, 그 응답을 화면에
/// 거는 길을 고정한다.
///
/// 이 방의 모양은 하나다 —
/// **AI가 이어 붙일 완성 문장 셋을 직접 써서 내밀고, 유저는 번호로 고르거나
/// 자기 생각을 말한다. 자기 생각을 말하면 제안 셋은 폐기된다.**
///
/// 여기 적힌 규칙은 구현 세부가 아니라 제품 정의라서, 누가 프롬프트를 손보다
/// 하나를 흘리면 방이 다시 "질문하는 AI"로 되돌아간다.
void main() {
  final ko = buildStepExpandConsultInstructions('Korean');
  final ja = buildStepExpandConsultInstructions('Japanese');

  group('제안은 설명이 아니라 완성 문장이다', () {
    test('유저가 그대로 말할 수 있는 문장을 쓰라고 적혀 있다', () {
      expect(ko, contains('THE THREE SENTENCES YOU OFFER'));
      expect(ko, contains('COMPLETE sentence the user could say out loud'));
      expect(ko, contains('first person'));
      expect(ko, contains('no labels, no explanation'));
    });

    test('셋이 서로 다른 방향이어야 한다', () {
      expect(ko, contains('the three go in DIFFERENT'));
      expect(ko, contains('Never three shades of one idea.'));
      expect(ko, contains('Never two sentences in one option.'));
    });

    test('없는 사실을 끌어들이지 않는다', () {
      expect(
          ko,
          contains(
              'Never introduce a fact, a job,\n  a family member, a place, or an event they did not mention.'));
    });
  });

  group('붙는 것은 유저가 고른 문장이다', () {
    test('번호를 고르면 그 문장을 글자 그대로 붙인다', () {
      expect(ko, contains('HOW THE TEXT GROWS THIS TURN'));
      expect(ko, contains('append the\n   sentence you offered under that number, word for word'));
    });

    test('자기 생각을 말하면 제안 셋은 폐기된다', () {
      expect(ko, contains('**your three offers are dead.**'));
      expect(ko, contains('Keep their meaning and their\n   words'));
      expect(
          ko,
          contains(
              'Never swap in one of your offers\n   because it was close.'));
    });

    test('다 거절하면 아무것도 안 붙이고 다른 각도로 다시 낸다', () {
      expect(ko, contains('append nothing'));
      expect(ko, contains('from a different angle than the ones they refused'));
    });
  });

  group('누적 글은 짧은 문장이 이어 붙는 것이다', () {
    test('한 문장이 길어지는 게 아니라고 못 박는다', () {
      expect(ko, contains('SHORT SENTENCES JOINED, not one sentence getting longer'));
      expect(ko, contains('"회사 그만두고 싶어. 매일 똑같은 일을 반복하는 게 너무 지쳐."'));
    });

    test('이미 들어간 부분은 손대지 않는다', () {
      expect(ko, contains('Never reword, polish, shorten, or reorder a part'));
      expect(ko, contains('It only\n  grows at the end.'));
    });
  });

  group('미국식은 단어가 아니라 순서다', () {
    test('사고 순서가 후보를 고르는 기준이다', () {
      expect(
          ko,
          contains(
              'Point -> Why -> Contrast or Detail -> Personal meaning -> Direction'));
      expect(ko, contains('the ORDER a thought gets built in'));
      expect(ko, contains('never\n  American words or slang'));
      expect(ko, contains('Nothing in this room leaves Korean.'));
      expect(ja, contains('Nothing in this room leaves Japanese.'));
    });

    test('모든 단계를 다 거치지 않는다', () {
      expect(ko, contains('Not every\n  stage is needed'));
      expect(ko, contains('never walk them in order like a form'));
    });
  });

  group('추천은 한 줄로 남는다', () {
    test('고르지 않으면 코치가 아니라 문제지라고 적혀 있다', () {
      expect(ko, contains('SAY WHICH ONE YOU WOULD TAKE'));
      expect(ko, contains('A menu with no recommendation is not coaching'));
      expect(ko, contains('never talk them out of their own choice'));
    });
  });

  group('출력 틀', () {
    test('틀이 정확히 못 박혀 있다', () {
      expect(ko, contains('[OUTPUT — EXACTLY THIS SHAPE, NOTHING ELSE]'));
      expect(ko, contains('[TEXT]'));
      expect(ko, contains('[OPTIONS]'));
      expect(ko, contains('[PICK]'));
      expect(ko, contains('[DONE]'));
      expect(ko, contains('Never write anything outside this shape'));
    });

    test('유저가 듣는 틀 문장은 모델이 쓰지 않는다', () {
      // "그럼, '...' 라는 말이 되는군요"는 코드가 붙인다. 모델에게 맡기면
      // 매 턴 조금씩 다른 말로 흘러 화면을 못 읽게 된다.
      expect(ko, contains('The frame sentences the user hears are added afterwards'));
    });
  });

  group('방은 영어를 만들지 않는다', () {
    test('영어 생성이 여기가 아니라고 못 박는다', () {
      expect(ko, contains('build an English version here'));
      expect(ko, contains('that happens later, somewhere else'));
    });

    test('출력 언어는 유저의 언어로 고정된다', () {
      expect(ko, contains('Everything you write stays in Korean.'));
      expect(ja, contains('Everything you write stays in Japanese.'));
    });
  });

  group('충분해지면 멈춘다', () {
    test('더 붙이면 중심이 흐려질 때 [DONE]을 낸다', () {
      expect(ko, contains('WHEN THE TEXT IS FULL'));
      expect(ko, contains('blur the center instead of sharpening it'));
      expect(ko, contains('after about five things have been added'));
      expect(ko, contains('Output [DONE] instead of'));
    });
  });

  group('로비 AI STYLE은 대화방에 닿지 않는다', () {
    test('스타일 지시 블록이 붙지 않는다', () {
      for (final p in <String>[ko, ja]) {
        expect(p, isNot(contains('[ENGLISH STYLE')));
        expect(p, isNot(contains('STYLE — Native')));
        expect(p, isNot(contains('STYLE — American')));
      }
    });
  });

  group('응답 틀 읽기', () {
    const reply = '''
[TEXT]
회사 그만두고 싶어. 매일 똑같은 일을 반복하는 게 너무 지쳐.
[OPTIONS]
1. 뭔가 새로운 일을 하면서 다시 의욕을 느끼고 싶어.
2. 문제는 지금 나이에 새로 시작하는 게 쉽지 않을 것 같다는 거야.
3. 요즘은 돈보다 내 시간을 좀 더 중요하게 생각하게 됐어.
[PICK]
1
''';

    test('누적 글과 후보 셋과 추천을 갈라 읽는다', () {
      final turn = parseStepExpandMenuTurn(reply);
      expect(turn.isUsable, isTrue);
      expect(turn.text, '회사 그만두고 싶어. 매일 똑같은 일을 반복하는 게 너무 지쳐.');
      expect(turn.options, hasLength(3));
      expect(turn.options[1], '문제는 지금 나이에 새로 시작하는 게 쉽지 않을 것 같다는 거야.');
      expect(turn.pick, 1);
      expect(turn.done, isFalse);
    });

    test('되묻기가 오면 나머지는 쳐다보지 않는다', () {
      final turn = parseStepExpandMenuTurn(
          '[HEARD_CONFIRM]\n혹시 "퇴사"라고 하신 건가요?\n[TEXT]\n엉뚱한 글');
      expect(turn.askBack, isNotEmpty);
      expect(turn.isUsable, isFalse);
      expect(turn.text, isEmpty);
      expect(turn.options, isEmpty);
    });

    test('[DONE]이면 후보 없이 마무리다', () {
      final turn = parseStepExpandMenuTurn('[TEXT]\n다 자란 글이다.\n[DONE]');
      expect(turn.done, isTrue);
      expect(turn.isUsable, isTrue);
      expect(turn.options, isEmpty);
    });

    test('번호 없는 줄은 후보가 아니다', () {
      // 모델이 흘린 설명을 후보로 실으면 유저가 설명문을 자기 문장으로 고른다.
      final turn = parseStepExpandMenuTurn(
          '[TEXT]\n글.\n[OPTIONS]\n다음은 세 가지입니다.\n1. 첫째 문장.\n2. 둘째 문장.');
      expect(turn.options, <String>['첫째 문장.', '둘째 문장.']);
    });

    test('넷째 후보는 버린다', () {
      final turn = parseStepExpandMenuTurn(
          '[TEXT]\n글.\n[OPTIONS]\n1. 하나.\n2. 둘.\n3. 셋.\n4. 넷.');
      expect(turn.options, hasLength(3));
    });

    test('없는 번호를 추천하면 추천을 버린다', () {
      final turn = parseStepExpandMenuTurn(
          '[TEXT]\n글.\n[OPTIONS]\n1. 하나.\n2. 둘.\n[PICK]\n3');
      expect(turn.pick, 0);
    });

    test('틀을 아예 안 쓴 응답은 걸 수 없다', () {
      final turn = parseStepExpandMenuTurn('그냥 이런저런 이야기를 했습니다.');
      expect(turn.isUsable, isFalse);
    });

    test('빈 응답', () {
      expect(parseStepExpandMenuTurn('   ').isUsable, isFalse);
    });
  });

  group('유저가 듣는 대사 조립', () {
    final turn = parseStepExpandMenuTurn('''
[TEXT]
회사 그만두고 싶어. 매일 똑같은 일을 반복하는 게 너무 지쳐.
[OPTIONS]
1. 하나.
2. 둘.
3. 셋.
[PICK]
2
''');

    test('첫 턴은 되짚지 않는다 — 방금 한 말의 메아리가 된다', () {
      final speech = composeStepExpandMenuSpeech(turn, isFirstTurn: true);
      expect(speech, startsWith('3가지 제안 중에서 연결하고 싶은 말이나 다른 당신의 생각을 말해보세요.'));
      expect(speech, isNot(contains('라는 말이 되는군요')));
      expect(speech, contains('1. 하나.'));
      expect(speech, contains('저는 2번이'));
    });

    test('두 번째 턴부터는 누적 글을 먼저 읽어 준다', () {
      final speech = composeStepExpandMenuSpeech(turn, isFirstTurn: false);
      expect(
          speech,
          startsWith(
              "그럼, '회사 그만두고 싶어. 매일 똑같은 일을 반복하는 게 너무 지쳐.' 라는 말이 되는군요."));
      expect(speech, contains('그 다음 연결할 말을 선택하거나, 혹은 당신의 생각을 말해보세요.'));
    });

    test('마무리 턴은 누적 글을 읽고 공부방으로 보낸다', () {
      final done = parseStepExpandMenuTurn('[TEXT]\n다 자란 글이다.\n[DONE]');
      final speech = composeStepExpandMenuSpeech(done, isFirstTurn: false);
      expect(speech, contains("그럼, '다 자란 글이다.' 라는 말이 되는군요."));
      expect(speech, endsWith('이제 공부방에서 점진적 확장 문장을 다양하게 연습해 보세요.'));
      expect(speech, isNot(contains('1.')));
    });

    test('추천이 없으면 그 줄도 없다', () {
      final noPick =
          parseStepExpandMenuTurn('[TEXT]\n글.\n[OPTIONS]\n1. 하나.\n2. 둘.');
      expect(composeStepExpandMenuSpeech(noPick, isFirstTurn: false),
          isNot(contains('저는 ')));
    });
  });

  group('모델에게 넘기는 상태', () {
    test('직전 후보 셋을 반드시 함께 넘긴다', () {
      // 이게 빠지면 "2번이 좋아"가 무슨 문장인지 모델이 몰라 지어낸다.
      final state = buildStepExpandMenuState(
        growingText: '회사 그만두고 싶어.',
        lastOptions: <String>['하나.', '둘.', '셋.'],
        userLine: '2번이 좋아',
      );
      expect(state, contains('[TEXT SO FAR]'));
      expect(state, contains('회사 그만두고 싶어.'));
      expect(state, contains('[THE THREE YOU OFFERED LAST TURN]'));
      expect(state, contains('2. 둘.'));
      expect(state, contains('[WHAT THEY JUST SAID]'));
      expect(state, contains('2번이 좋아'));
    });

    test('첫 턴은 누적 글이 없다고 알린다', () {
      final state = buildStepExpandMenuState(
        growingText: '',
        lastOptions: const <String>[],
        userLine: '회사 그만두고 싶어.',
      );
      expect(state, contains('(nothing yet'));
      expect(state, isNot(contains('OFFERED LAST TURN')));
    });
  });
}
