import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/widgets/first_utterance_context_judge.dart';

void main() {
  group('classifyHeardConfirmReply', () {
    test('"네"류는 확인으로 본다 — 보류 발화가 재개된다', () {
      for (final yes in ['네', '네.', '예', '응', '맞아요', '맞습니다', 'Yes', 'yeah']) {
        expect(classifyHeardConfirmReply(yes), HeardConfirmReply.affirmed,
            reason: yes);
      }
    });

    test('"아니요"류는 부정으로 본다 — 보류 발화를 버리고 다시 듣는다', () {
      for (final no in ['아니', '아니요', '아뇨', '아닙니다', '틀렸어요', 'No', 'nope']) {
        expect(classifyHeardConfirmReply(no), HeardConfirmReply.denied,
            reason: no);
      }
    });

    test('내용을 담아 다시 말하면 새 발화로 본다', () {
      expect(classifyHeardConfirmReply('아니요, 도서관에서 만났어요'),
          HeardConfirmReply.corrected);
      expect(classifyHeardConfirmReply('네, 그런데 어제가 아니라 그저께예요'),
          HeardConfirmReply.corrected);
      expect(classifyHeardConfirmReply('카페에서 만났어요'),
          HeardConfirmReply.corrected);
    });

    test('구두점과 공백은 판정을 흔들지 않는다', () {
      expect(classifyHeardConfirmReply('  네!  '), HeardConfirmReply.affirmed);
      expect(classifyHeardConfirmReply('아니요...'), HeardConfirmReply.denied);
    });

    test('빈 문자열은 새 발화로 떨어진다 — 확인으로 오해하지 않는다', () {
      expect(classifyHeardConfirmReply(''), HeardConfirmReply.corrected);
      expect(classifyHeardConfirmReply('   '), HeardConfirmReply.corrected);
    });
  });

  group('되묻기 신호', () {
    test('신호는 첫 줄에서만 인정한다', () {
      expect(hasHeardConfirmSignal('[HEARD_CONFIRM]\n뭐라고 하셨죠?'), isTrue);
      expect(hasHeardConfirmSignal('그건 [HEARD_CONFIRM] 아니에요'), isFalse);
    });

    test('신호를 떼면 유저에게 보일 질문만 남는다', () {
      expect(stripHeardConfirmSignal('[HEARD_CONFIRM]\n뭐라고 하셨죠?'), '뭐라고 하셨죠?');
    });

    test('신호가 없으면 원문 그대로다', () {
      expect(stripHeardConfirmSignal('그래서 어떻게 됐어요?'), '그래서 어떻게 됐어요?');
    });
  });

  group('되묻기 안내 문구', () {
    test('로비 12개 언어가 모두 자기 언어로 나온다', () {
      const langs = [
        'Korean', 'Japanese', 'Chinese', 'Spanish', 'French', 'German',
        'Hindi', 'Russian', 'Portuguese', 'Italian', 'Dutch', 'English',
      ];
      final seen = <String>{};
      for (final lang in langs) {
        final line = unheardBubbleHintLine(lang);
        expect(line.trim(), isNotEmpty, reason: lang);
        seen.add(line);
      }
      // 12개가 전부 다른 문장이어야 한다 — 같으면 표에 빠진 언어가 있다는 뜻이다.
      expect(seen.length, langs.length);
    });

    test('모르는 언어는 영어로 떨어진다', () {
      expect(unheardBubbleHintLine('Klingon'), unheardBubbleHintLine('English'));
    });
  });
}
