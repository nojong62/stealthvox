import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/ai_style.dart';

/// NATURAL & SHARP(저장 칸은 `native_english`) 지시문을 고정한다.
///
/// **2026-09-09 두 축이 갈렸다.** Trevor Noah reference는 생각을 푸는 방식·리듬·
/// 흐름만 지배하고, 어휘·철자·지역 어투는 로비 AI STYLE이 쥔다. 예전에는 이
/// 프롬프트에 `aiStyleInstruction('Native')`가 하드코딩돼 있어서, 유저가
/// British를 골라도 "미국식으로 다시 짜라"가 들어갔다. 그 하드코딩을 걷어낸
/// 것이 이 파일이 지키는 첫 번째 약속이다.
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

  group('화자와 스타일은 서로 다른 축이다', () {
    test('로비 AI STYLE을 실제로 싣는다', () {
      // 예전에는 이 자리에 'Native'가 박혀 있어서 유저의 선택이 닿지 않았다.
      expect(prompt, contains('[ENGLISH STYLE'));
      expect(prompt, contains('STYLE — '));
    });

    test('인물은 dialect를 강제하지 않는다', () {
      // Trevor Noah는 thought-organization reference이지 미국 어투의 근거가
      // 아니다. British를 고른 유저는 British 어휘 그대로 이 패턴을 탄다.
      expect(prompt, contains('Use Trevor Noah only as a reference'));
      expect(
        prompt,
        contains(
            'It does not govern dialect, spelling, regional vocabulary, or regional wording.'),
      );
      expect(prompt, contains('If the active style is British, stay British'));
      expect(prompt, isNot(contains('Use everyday US spoken English')));
      expect(prompt, isNot(contains('decorative American vocabulary')));
    });

    test('스타일 블록이 없는 방에서는 그것을 가리키지 않는다', () {
      // 비영어 타겟이면 스타일 블록이 빈 문자열이다. 그때도 "ENGLISH STYLE을
      // 지키라"고 적으면 프롬프트가 없는 절을 가리킨다.
      final noStyle =
          buildNativeEnglishSpeechInstructions(targetLang: 'Japanese');
      expect(noStyle, isNot(contains('[ENGLISH STYLE')));
      expect(noStyle, isNot(contains('ENGLISH STYLE section')));
      expect(noStyle,
          isNot(contains('while preserving the active ENGLISH STYLE')));
      // 화자 정체성 자체는 그대로 선다.
      expect(noStyle, contains('SPEAKER IDENTITY — NATURAL & SHARP'));
    });

    test('화자 안내가 앞 문장에 달라붙지 않는다', () {
      // `'''` 바로 뒤의 개행은 Dart가 먹는다. 그대로 두면 "…and paced.It
      // does NOT…"이 되어 두 문장이 한 줄로 뭉친다.
      expect(prompt, isNot(contains('moves.If the active style')));
      expect(prompt, contains('moves.\nIf the active style'));
    });
  });

  group('생각의 연결과 맥락', () {
    test('상황에서 의미와 연결을 거쳐 자연스럽게 결론에 닿는다', () {
      expect(
        prompt,
        contains('Start from the concrete situation.'),
      );
      expect(
        prompt,
        contains('Let the listener understand why it matters.'),
      );
      expect(prompt, contains('Look for the natural connection'));
      expect(prompt, contains('This is a guide, not a fixed formula.'));
      expect(
        prompt,
        contains('What is really happening here, why does it matter to me'),
      );
    });

    test('인물 이름을 부르지 않는다', () {
      expect(prompt, contains('Never mention Trevor Noah.'));
      expect(
        prompt,
        contains(
            'Never reproduce his quotations, jokes, catchphrases, or uniquely identifiable wording.'),
      );
    });

    test('억지 유머와 과장된 성격을 만들지 않는다', () {
      expect(prompt, contains('do not invent a joke or force humor'));
      expect(
        prompt,
        contains('Do not make the user funnier, smarter, more dramatic'),
      );
    });

    test('어휘 수준을 올리지 않는다', () {
      // Clear & Easy와의 차이가 어휘라면 두 카드의 구분이 무너진다.
      expect(
        prompt,
        contains('Keep the vocabulary familiar and easy to say aloud.'),
      );
      expect(
        prompt,
        contains(
            'Sophistication should come from the relationship between ideas'),
      );
    });

    test('분량을 줄이는 자리가 아니다', () {
      expect(prompt, contains('THIS IS NOT A CONDENSED VERSION'));
      expect(
        prompt,
        contains(
            'Never shorten the speech, never summarize it, and never drop material to sound more refined.'),
      );
      expect(
        prompt,
        contains(
            'Never make the speech shorter or thinner than what you were given.'),
      );
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

  group('구어체이되 장식은 아니다', () {
    test('어려운 단어와 문어체를 막는다', () {
      expect(prompt, contains('Avoid SAT vocabulary'));
      expect(
        prompt,
        contains(
            'Polish means native thought organization, not decorative vocabulary.'),
      );
      expect(
        prompt,
        contains(
            'Which vocabulary and which regional wording to use is decided by the ENGLISH STYLE'),
      );
    });

    test('한글이 남으면 안 된다', () {
      expect(prompt, contains('must NOT contain any Hangul characters.'));
    });

    test('설명·라벨·따옴표 없이 발화만 낸다', () {
      expect(prompt, contains('Output only the Natural & Sharp speech.'));
      expect(prompt, contains('No explanation. No labels.'));
    });
  });
}
