import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/dialog_brain_model.dart';

void main() {
  group('Dialog Brain reasoning selection', () {
    test('ordinary turns stay low regardless of sentence length', () {
      final short = selectDialogBrainReasoning(userText: '오늘은 괜찮아요.');
      final long = selectDialogBrainReasoning(
        userText: '오늘은 오전에 회의가 있었고 점심에는 동료를 만났지만 '
            '저녁에는 집에서 편하게 쉬려고 해요.',
        hasConversationContext: true,
      );

      expect(short.effort, 'low');
      expect(short.reason, 'normal_turn');
      expect(long.effort, 'low');
      expect(long.reason, 'normal_turn');
    });

    test('explicit correction is medium', () {
      final decision = selectDialogBrainReasoning(
        userText: '아니, 제가 말한 건 그게 아니고 매그예요.',
        hasConversationContext: true,
      );

      expect(decision.effort, 'medium');
      expect(decision.reason, 'user_correction');
    });

    test('correction retry remains medium after the prefix was removed', () {
      final decision = selectDialogBrainReasoning(
        userText: '매그예요.',
        hasConversationContext: true,
        isCorrectionRetry: true,
      );

      expect(decision.effort, 'medium');
      expect(decision.reason, 'user_correction');
    });

    test('reference to earlier dialogue is medium only when context exists',
        () {
      final contextual = selectDialogBrainReasoning(
        userText: '아까 말한 그 사람이요.',
        hasConversationContext: true,
      );
      final firstTurn = selectDialogBrainReasoning(
        userText: '그 사람이요.',
      );

      expect(contextual.effort, 'medium');
      expect(contextual.reason, 'context_reference');
      expect(firstTurn.effort, 'low');
    });

    test('ambiguous meaning target is medium', () {
      final decision = selectDialogBrainReasoning(
        userText: '그 말이 무슨 뜻이에요?',
        hasConversationContext: true,
      );

      expect(decision.effort, 'medium');
      expect(decision.reason, 'meaning_scope');
    });

    test('explicit word meaning and ordinary negative answers stay low', () {
      final wordMeaning = selectDialogBrainReasoning(
        userText: '이 단어 뜻이 뭐예요?',
        hasConversationContext: true,
      );
      final negativeAnswer = selectDialogBrainReasoning(
        userText: '아니요, 그건 안 팔아요.',
        hasConversationContext: true,
      );

      expect(wordMeaning.effort, 'low');
      expect(negativeAnswer.effort, 'low');
    });

    test('known STT and USER_FIX context elevate one call', () {
      final stt = selectDialogBrainReasoning(
        userText: '네, 그 내용으로 계속해 주세요.',
        hasSttCorrectionContext: true,
      );
      final userFix = selectDialogBrainReasoning(
        userText: '그래서 어떻게 됐어요?',
        previousTurnHadUserFix: true,
      );

      expect(stt.reason, 'stt_correction');
      expect(userFix.reason, 'user_fix_context');
    });

    test('Step 2 partial multi-part answer is medium', () {
      final partial = selectDialogBrainReasoning(
        userText: '글쎄요.',
        previousAssistantText: '언제 갔어요? 그리고 왜 갔어요?',
        hasConversationContext: true,
        isStep2: true,
      );
      final directShortAnswer = selectDialogBrainReasoning(
        userText: '커피요.',
        previousAssistantText: '무엇을 마실래요?',
        hasConversationContext: true,
        isStep2: true,
      );

      expect(partial.effort, 'medium');
      expect(partial.reason, 'step2_partial_answer');
      expect(directShortAnswer.effort, 'low');
    });

    test('medium never persists into a normal next turn', () {
      final difficult = selectDialogBrainReasoning(
        userText: '그 사람이 아니라 전에 말한 사람이요.',
        hasConversationContext: true,
      );
      final next = selectDialogBrainReasoning(
        userText: '오늘 날씨가 좋네요.',
        hasConversationContext: true,
      );

      expect(difficult.effort, 'medium');
      expect(next.effort, 'low');
      expect(next.reason, 'normal_turn');
    });
  });

  group('Origin이 한국어·영어가 아닐 때 (2026-10-14)', () {
    String reasonOf(String text) => selectDialogBrainReasoning(
          userText: text,
          hasConversationContext: true,
        ).reason;

    test('실기기에서 low에 머물던 일본어 지시어가 이제 medium이다', () {
      expect(reasonOf('さっきの話ですけど、指揮者の先生は厳しい方なんですか？'),
          'context_reference');
    });

    test('앞 대화를 가리키는 말', () {
      for (final text in <String>[
        '先ほど言った件ですが',
        '刚才说的那家餐厅在哪里？',
        'Lo que dijiste sobre el restaurante me interesa.',
        'Ce que tu as dit tout à l’heure, c’était vrai ?',
        'Was du vorhin gesagt hast, stimmt das?',
        'आपने पहले कहा था कि आप दिल्ली में रहते हैं।',
        'То, что ты говорил раньше, правда?',
        'O que você disse sobre o hotel é verdade?',
        'Quello che hai detto prima era interessante.',
        'Wat je net zei over het weer klopt.',
      ]) {
        expect(reasonOf(text), 'context_reference', reason: text);
      }
    });

    test('정정하는 말', () {
      for (final text in <String>[
        'いや、そういう意味じゃなくて、明日です。',
        '我不是那个意思，我说的是明天。',
        'No, quiero decir mañana.',
        'Non, je veux dire demain.',
        'Nein, ich meine morgen.',
        'मेरा मतलब यह नहीं था।',
        'Нет, я имею в виду завтра.',
        'Não, quero dizer amanhã.',
        'No, intendo domani.',
        'Nee, ik bedoel morgen.',
      ]) {
        expect(reasonOf(text), 'user_correction', reason: text);
      }
    });

    test('그게 무슨 뜻이냐고 묻는 말', () {
      for (final text in <String>[
        'それはどういう意味ですか？',
        '这是什么意思？',
        '¿Qué quieres decir?',
        'Qu’est-ce que ça veut dire ?',
        'Was meinst du damit?',
        'इसका क्या मतलब है?',
        'Что это значит?',
        'O que isso significa?',
        'Cosa significa?',
        'Wat bedoel je?',
      ]) {
        expect(reasonOf(text), 'meaning_scope', reason: text);
      }
    });

    test('평범한 문장은 그대로 low다 — 대답이 느려지면 안 된다', () {
      for (final text in <String>[
        '明日は友達と映画を見に行きます。',
        '我今天想吃那个饺子。',
        'Eso es muy interesante, me gusta mucho.',
        'Je vais au marché ce matin.',
        'Ich gehe heute Abend ins Kino.',
        'मैं कल बाज़ार जाऊँगा।',
        'Я сегодня иду в кино.',
        'Eu gosto muito de café.',
        'Oggi vado al mare con la famiglia.',
        'Ik ga morgen naar de markt.',
      ]) {
        expect(reasonOf(text), 'normal_turn', reason: text);
      }
    });
  });
}
