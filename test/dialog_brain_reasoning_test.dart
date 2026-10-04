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
}
