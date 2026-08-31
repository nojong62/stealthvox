import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/ai_style.dart';

/// NATIVE ENGLISH 지시문을 고정한다.
///
/// **Native = 영어처럼 번역하는 것이 아니라, 같은 생각을 미국 영어 화자가
/// 처음부터 영어로 짰다면 어떻게 말했을지를 다시 만드는 것.**
/// 이 정의가 로비 AI STYLE의 `STYLE — Native`와 갈라지는 순간, 앱 안에서
/// Native가 서로 다른 두 가지 뜻을 갖게 된다. 그래서 두 지시문이 실제로 같은
/// 글자를 공유하는지를 여기서 지킨다.
void main() {
  final prompt = buildNativeEnglishSpeechInstructions();

  group('입력은 문장 하나가 아니라 My English 한 벌이다', () {
    test('My English를 입력으로 받는다고 적혀 있다', () {
      expect(prompt, contains('ONE complete personal speech'));
      expect(prompt, contains('What you are given is My English'));
    });

    test('입력을 "유저가 실제로 한 말"로 설명하지 않는다', () {
      // My English는 학습용으로 지어낸 확장문이다. 이 단계가 그것을 실제
      // 발화로 알면 원문에 필요 이상으로 붙는다.
      expect(prompt, isNot(contains('faithful reconstruction')));
      expect(prompt, contains('It is a\nlearning text, not a transcript.'));
      expect(prompt, contains('already complete and settled'));
    });

    test('번역도 다듬기도 아니라고 못 박는다', () {
      expect(prompt, contains('NOT to translate it and NOT to polish it'));
      expect(
        prompt,
        contains('originally been formed in English from the start'),
      );
    });

    test('배열을 바꿔도 되고 문장 수도 바뀔 수 있다', () {
      expect(prompt, contains('reorder ideas, merge ideas, split sentences'));
      expect(prompt, contains('change the number of sentences'));
    });

    test('정해진 틀을 강요하지 않는다', () {
      expect(prompt, contains('These are not mandatory stages.'));
      expect(
        prompt,
        contains('Never force every speech through the same formula.'),
      );
    });
  });

  group('로비 Native와 같은 철학을 공유한다', () {
    test('로비 스타일 지시문을 통째로 안고 있다', () {
      // 두 곳에 따로 적히기 시작하면 이 시험이 먼저 깨진다.
      expect(prompt, contains(aiStyleInstruction('Native')));
      expect(prompt, contains('STYLE — Native'));
    });

    test('로비에서 고른 다른 스타일은 절대 섞이지 않는다', () {
      // 로비에서 British를 골랐다고 NATIVE ENGLISH 카드가 영국식이 되면
      // 카드 이름이 거짓말이 된다.
      expect(prompt, isNot(contains('STYLE — British')));
      expect(prompt, isNot(contains('STYLE — American')));
      expect(prompt, isNot(contains('STYLE — Standard')));
      expect(prompt, isNot(contains('[ENGLISH STYLE')));
    });
  });

  group('유저가 말하지 않은 것은 만들지 않는다', () {
    test('My English에 있는 의미만 쓴다', () {
      expect(
        prompt,
        contains('Use only meaning already contained in My English.'),
      );
      expect(
        prompt,
        contains(
            'Never add a new fact, reason, feeling, opinion, motivation, plan, or conclusion.'),
      );
    });

    test('입장을 바꾸거나 흐리지 않는다', () {
      expect(prompt, contains("Never change or soften the user's stance."));
      expect(prompt, contains('Never turn uncertainty into certainty.'));
      expect(
        prompt,
        contains(
            'Never manufacture a conclusion merely to make the speech sound complete.'),
      );
    });

    test('유저가 말한 중요한 의미를 빼지 않는다', () {
      expect(
        prompt,
        contains('Never remove an important meaning the user expressed.'),
      );
    });
  });

  group('미국 구어체이되 장식은 아니다', () {
    test('어려운 단어와 문어체를 막는다', () {
      expect(prompt, contains('Avoid SAT vocabulary'));
      expect(
        prompt,
        contains(
            'Native means native thought organization, not decorative American vocabulary.'),
      );
    });

    test('한글이 남으면 안 된다', () {
      expect(prompt, contains('must NOT contain any Hangul characters.'));
    });

    test('설명·라벨·따옴표 없이 발화만 낸다', () {
      expect(prompt, contains('Output only the Native English speech.'));
      expect(prompt, contains('No explanation. No labels.'));
    });
  });
}
