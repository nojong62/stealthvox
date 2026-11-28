import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/free_talk_meaning_check.dart';

void main() {
  group('learnerLineFixIsPlausible', () {
    test('단어 나열을 질문 두 개로 푼 교정은 받는다', () {
      expect(
          learnerLineFixIsPlausible(
              original: 'morning, many people, crowded?',
              fixed: 'Are there many people in the morning? Is it crowded?'),
          isTrue);
    });
    test('유저 낱말이 거의 안 남은 다시 쓰기는 막는다', () {
      expect(
          learnerLineFixIsPlausible(
              original: 'morning, many people, crowded?',
              fixed: 'What time does the park usually open for runners?'),
          isFalse);
    });
  });

  group('buildMeaningClarifyNote 회차', () {
    test('첫 대답이면 한 번 더 물을 수 있다', () {
      final n = buildMeaningClarifyNote(
          spokenLang: 'English', chatLang: 'Korean', attempt: 'money... so', round: 1);
      expect(n, contains('one more easy question'));
      expect(n, isNot(contains('Do NOT ask another')));
    });
    test('두 번 물었으면 더 묻지 않고 예문만, 원래 말에 대해서만', () {
      final n = buildMeaningClarifyNote(
          spokenLang: 'English', chatLang: 'Korean', attempt: 'money... so', round: 2);
      expect(n, contains('Do NOT ask another'));
      expect(n, contains('never about an older topic'));
      expect(
          buildMeaningFinalNote(
              spokenLang: 'English', clarifying: true, allowCheck: false, round: 2),
          contains('no more questions'));
    });
  });

  group('freeTalkLineNeedsThought', () {
    test('말끝이 흐리거나 머뭇거리면 medium', () {
      expect(freeTalkLineNeedsThought('um... interview... tomorrow... but...'), isTrue);
      expect(freeTalkLineNeedsThought('the company and'), isTrue);
    });
    test('보통 문장·단어 나열은 low', () {
      expect(freeTalkLineNeedsThought('very nervous, English question'), isFalse);
      expect(freeTalkLineNeedsThought('I went to Busan last week.'), isFalse);
    });
  });

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

  group('넘어가기·턴별 지시', () {
    test('넘어가자는 말은 교정 문장이 아니라 skip이다', () {
      const s = 'I went there yesterday.';
      expect(classifyMeaningConfirmReply('그냥 넘어가', sentence: s),
          MeaningConfirmReply.skip);
      expect(classifyMeaningConfirmReply("I don't know. pass", sentence: s),
          MeaningConfirmReply.skip);
      expect(classifyMeaningConfirmReply('No, I am right.', sentence: s),
          MeaningConfirmReply.skip);
      expect(
          classifyMeaningConfirmReply(
              "I don't know how to say it, I went with my friend", sentence: s),
          MeaningConfirmReply.other);
    });

    test('말 양도 수준을 따른다: 단어만 말하면 짧게, 절로 길게 말하면 유저가 이끈다', () {
      final short = buildFreeTalkTurnNote(userLines: ['um... weekend'], spokenLang: 'English');
      expect(short, contains('LEVEL 1'));
      expect(short, contains('at most 2 very short sentences'));
      final long = 'So I started tennis and it is harder than I expected because my coach is strict';
      expect(buildFreeTalkTurnNote(userLines: [long, long, long], spokenLang: 'English'),
          contains('The user is leading'));
    });

    test('몇 단어에 막혀도 낱말 수로 정하지 않고, 짧은 말도 쉬운 예 보여 주기 대상', () {
      final note = buildFreeTalkTurnNote(
          userLines: ['um... sleep', 'Saturday'], spokenLang: 'English');
      expect(note, isNot(contains('stuck at a few words')));
      expect(meaningCheckWorthIt('um... sleep'), isTrue);
      expect(meaningCheckWorthIt('  '), isFalse);
      expect(buildMeaningCheckPolicy(spokenLang: 'English'),
          contains('ONE missing piece'));
    });

    test('그만 고치라고 했으면 끝까지 말로 교정하지 않는다(줄 고치기는 조용히 남는다)', () {
      final note = buildFreeTalkTurnNote(
          userLines: ['Just talk, please. I am tired of corrections and I want to talk now ok'],
          spokenLang: 'English',
          noCorrection: true);
      expect(note, contains('Never talk about their mistakes'));
      expect(note, contains('[USER_FIX] is silent'));
    });

    test('세 턴 연속 절로 길게 말하면(3단계) 한 단계 위로', () {
      final long = 'I went to the park with my friends because the weather was nice and we played soccer';
      final note = buildFreeTalkTurnNote(
          userLines: [long, long, long], spokenLang: 'English');
      expect(note, contains('Stretch them'));
      expect(note, contains('I went'));
    });
  });
}
