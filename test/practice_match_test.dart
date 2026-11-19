import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/practice_match.dart';

void main() {
  group('영어(라틴 글자)는 기존 동작 그대로', () {
    test('8단어 미만은 인식만 되면 통과', () {
      expect(
          practiceReadThroughPass(
              targetText: 'I cried last night.', transcript: 'i cry last night'),
          isTrue);
    });
    test('8단어 이상은 60% 미만이면 불합격', () {
      const target =
          'Yesterday after work I had chicken with a friend and laughed so hard';
      expect(
          practiceReadThroughPass(targetText: target, transcript: 'yesterday work'),
          isFalse);
      expect(
          practiceReadThroughPass(
              targetText: target,
              transcript:
                  'yesterday after work i had chicken with a friend and laughed'),
          isTrue);
    });
    test('빈 인식 결과는 불합격', () {
      expect(practiceReadThroughPass(targetText: 'Hello there', transcript: ''),
          isFalse);
    });
  });

  group('한국어 대본', () {
    test('한글이 정규화에서 지워지지 않는다', () {
      expect(normalizePracticeMatchText('어젯밤 라이브 방송을 봤는데, 울었어.'),
          '어젯밤 라이브 방송을 봤는데 울었어');
    });
    test('짧은 줄은 인식만 되면 통과', () {
      expect(
          practiceReadThroughPass(
              targetText: '어젯밤 라이브 방송을 봤는데, 울었어.',
              transcript: '어젯밤 라이브 방송을 봤는데 울었어'),
          isTrue);
    });
    test('인식 결과가 비면 불합격', () {
      expect(
          practiceReadThroughPass(targetText: '어젯밤 라이브 방송을 봤는데, 울었어.', transcript: ''),
          isFalse);
    });
    test('긴 줄은 띄어쓰기가 달라도 통과', () {
      const target = '제가 모두와 함께 바로 그곳에 있는 것처럼 느껴졌어요.';
      expect(
          practiceReadThroughPass(
              targetText: target, transcript: '제가 모두와 함께 바로 그 곳에 있는 것처럼 느껴졌어요'),
          isTrue);
    });
    test('긴 줄에서 일부만 읽으면 불합격', () {
      const target = '제가 모두와 함께 바로 그곳에 있는 것처럼 느껴졌어요.';
      expect(practiceReadThroughPass(targetText: target, transcript: '제가 모두와'),
          isFalse);
    });
    test('엉뚱한 영어로 인식되면 긴 줄은 불합격', () {
      const target = '제가 모두와 함께 바로 그곳에 있는 것처럼 느껴졌어요.';
      expect(
          practiceReadThroughPass(
              targetText: target, transcript: 'jeiga moduwa hamkke'),
          isFalse);
    });
  });

  group('일본어·러시아어도 글자가 지워지지 않는다', () {
    test('일본어', () {
      expect(
          practiceReadThroughPass(
              targetText: '昨夜はライブ配信を見て泣きました。', transcript: '昨夜はライブ配信を見て泣きました'),
          isTrue);
    });
    test('러시아어는 라틴이 아니므로 글자 단위로 본다', () {
      expect(normalizePracticeMatchText('Я вчера плакал.'), 'я вчера плакал');
    });
  });
}
