import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/ai_style.dart';

/// P3 두 번째 문장을 만드는 지시문을 고정한다.
///
/// **Native = 영어처럼 번역하는 것이 아니라, 영어로 다시 생각해서 표현하는 것.**
/// 이 정의가 로비 AI STYLE의 `STYLE — Native`와 갈라지는 순간, 앱 안에서
/// Native가 서로 다른 두 가지 뜻을 갖게 된다. 그래서 두 지시문이 실제로 같은
/// 글자를 공유하는지를 여기서 지킨다.
void main() {
  final prompt = buildNativeEnglishSentenceInstructions();

  group('Polished가 아니라 재구성이다', () {
    test('번역도 다듬기도 아니라고 못 박는다', () {
      expect(prompt, contains('NOT to translate it, and NOT to polish it'));
      expect(
          prompt,
          contains(
              'thought out in English,\nnot carried over into English'));
    });

    test('배열을 바꿔도 된다고 허락한다', () {
      expect(prompt, contains('Reorder, merge, or split as needed.'));
      expect(prompt, contains('The sentence count may change.'));
      expect(prompt, contains('One to three short spoken sentences.'));
    });
  });

  group('로비 Native와 같은 철학을 공유한다', () {
    test('로비 스타일 지시문을 통째로 안고 있다', () {
      // 두 곳에 따로 적히기 시작하면 이 시험이 먼저 깨진다.
      expect(prompt, contains(aiStyleInstruction('Native')));
      expect(prompt, contains('STYLE — Native'));
    });

    test('다른 스타일이 섞여 들어오지 않는다', () {
      // 로비에서 British를 골랐다고 "Native English" 카드가 영국식이 되면
      // 카드 이름이 거짓말이 된다.
      expect(prompt, isNot(contains('STYLE — British')));
      expect(prompt, isNot(contains('STYLE — American')));
      expect(prompt, isNot(contains('[ENGLISH STYLE')));
    });
  });

  group('유저가 말하지 않은 것은 만들지 않는다', () {
    test('사실·이유·결론을 더하지 않는다', () {
      expect(
          prompt,
          contains(
              'Never add a fact, reason, feeling, or conclusion the user did not express.'));
      expect(prompt, contains('never flip or soften their position'));
      expect(prompt, contains('Never manufacture a conclusion to close on.'));
    });

    test('한글이 남으면 안 된다', () {
      expect(prompt, contains('must NOT contain any Hangul characters.'));
    });
  });

  group('상대 이름은 AI로 바꿔치기되지 않는다', () {
    test('이름을 주면 그 이름을 지키라고 적힌다', () {
      final named = buildNativeEnglishSentenceInstructions(partnerLabel: 'Mina');
      expect(named,
          contains('Do not replace Mina with AI, assistant, chatbot, or bot.'));
    });

    test('이름이 없으면 그 줄 자체가 없다', () {
      expect(prompt, isNot(contains('Do not replace')));
      expect(buildNativeEnglishSentenceInstructions(partnerLabel: '   '),
          isNot(contains('Do not replace')));
    });
  });
}
