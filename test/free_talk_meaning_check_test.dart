import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/free_talk_meaning_check.dart';

void main() {
  group('meaningCheckAllowed', () {
    test('평소 방에서는 묻지 않는다', () {
      expect(meaningCheckAllowed(freeTalk: false), isFalse);
    });

    test('Free Talk은 언제나 묻는다', () {
      expect(meaningCheckAllowed(freeTalk: true), isTrue);
    });

    test('확인 중이거나 확인된 턴에서는 묻지 않는다', () {
      expect(meaningCheckAllowed(freeTalk: true, alreadyConfirmed: true),
          isFalse);
    });
  });

  group('parseMeaningCheck', () {
    test('되묻기 질문을 한 줄로 꺼낸다', () {
      final check = parseMeaningCheck(
          '[MEANING_CHECK]\nDo you mean the meeting is over?\nOr you want to end it? Please say it again.');
      expect(check!.question,
          'Do you mean the meeting is over? Or you want to end it? Please say it again.');
    });

    test('형식이 아니면 null', () {
      expect(parseMeaningCheck('Sounds good, see you Saturday.'), isNull);
      expect(parseMeaningCheck('[MEANING_CHECK]\n  '), isNull);
    });
  });

  group('parseMeaningConfirm', () {
    test('확인 질문과 문장을 가른다', () {
      final confirm = parseMeaningConfirm(
          '[MEANING_CONFIRM]\nSo you want to say this?\n[SENTENCE]\n"I was late for the meeting."');
      expect(confirm!.question, 'So you want to say this?');
      expect(confirm.sentence, 'I was late for the meeting.');
      expect(meaningConfirmLine(confirm),
          'So you want to say this?\n"I was late for the meeting."');
    });

    test('문장이 없으면 null', () {
      expect(parseMeaningConfirm('[MEANING_CONFIRM]\nSo you mean this?'),
          isNull);
    });

    test('제어 형식 판별', () {
      expect(looksLikeMeaningControl('[MEANING_CONFIRM] broken'), isTrue);
      expect(looksLikeMeaningControl('Nice, see you then.'), isFalse);
    });
  });

  group('classifyMeaningConfirmReply', () {
    test('긍정은 배울 언어·대화언어 모두 받는다', () {
      expect(classifyMeaningConfirmReply('네'), MeaningConfirmReply.yes);
      expect(classifyMeaningConfirmReply('네, 맞아요.'), MeaningConfirmReply.yes);
      expect(classifyMeaningConfirmReply('Yes.'), MeaningConfirmReply.yes);
      expect(classifyMeaningConfirmReply('Yeah, right.'),
          MeaningConfirmReply.yes);
      expect(classifyMeaningConfirmReply('はい'), MeaningConfirmReply.yes);
    });

    test('짧은 부정', () {
      expect(classifyMeaningConfirmReply('아니요'), MeaningConfirmReply.no);
      expect(classifyMeaningConfirmReply('No.'), MeaningConfirmReply.no);
    });

    test('설명이 붙으면 새 설명이다', () {
      expect(classifyMeaningConfirmReply('아니, 회의에 늦었다는 말이었어'),
          MeaningConfirmReply.other);
      expect(
          classifyMeaningConfirmReply(
              'No, I wanted to say that I was late for it.'),
          MeaningConfirmReply.other);
    });
  });

  group('직접 따라 말하기', () {
    const sentence =
        'Yesterday my boss called me to his office, and he said my report had many mistakes.';

    test('제안 문장을 따라 말하면 교정 완료', () {
      expect(
          classifyMeaningConfirmReply(
              'Um, yesterday my boss called me to his office and he said my report had many mistakes.',
              sentence: sentence),
          MeaningConfirmReply.repeated);
    });

    test('네만 하면 아직 아니다', () {
      expect(classifyMeaningConfirmReply('Yes.', sentence: sentence),
          MeaningConfirmReply.yes);
    });

    test('다른 설명은 새 설명', () {
      expect(
          classifyMeaningConfirmReply(
              'No, I mean my boss was angry about the meeting time.',
              sentence: sentence),
          MeaningConfirmReply.other);
    });

    test('직접 말해 보라는 한 줄', () {
      expect(meaningSayItLine('English'), 'Great. Now try saying it yourself.');
    });
  });

  test('대답 대기 중 엉뚱한 언어 받아쓰기는 거른다', () {
    expect(transcriptFitsLanguages('how to say わかこ家庭。', 'English', 'Korean'),
        isFalse);
    expect(transcriptFitsLanguages('Yes, 맞아요!', 'English', 'Korean'), isTrue);
    expect(transcriptFitsLanguages('はい、そうです', 'English', 'Japanese'), isTrue);
  });

  test('메모는 문장을 한 줄로 담는다', () {
    final resolved = buildMeaningResolvedNote(
        spokenLang: 'English', sentence: 'The meeting\nis over.');
    expect(resolved, contains('"The meeting is over."'));
    final clarify = buildMeaningClarifyNote(
        spokenLang: 'English', chatLang: 'Korean', attempt: 'meeting\nfinish me');
    expect(clarify, contains('"meeting finish me"'));
    expect(clarify, contains('Korean'));
  });
}
