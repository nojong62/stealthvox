// 💬 Duo 통역 말투 문맥 — 도착 언어에 존댓말·경어가 있을 때만 최근 대화를 붙인다.
//
// 근거: 2026-11-07 실기기 A/B. 영→한 20턴 중 6턴이 반말로 섞였고, 문맥 6줄을
// 붙이자 10턴 모두 존댓말이 됐다. 영어 도착은 차이가 없어 붙이지 않는다.
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/widgets/routine_mode_duo.dart';

void main() {
  setUp(DuoBrain.clearContext);

  test('기억한 줄이 없으면 붙이지 않는다', () {
    expect(DuoBrain.contextBlock('Korean'), isEmpty);
  });

  test('도착 언어가 한국어·일본어면 최근 대화를 붙인다', () {
    DuoBrain.rememberContextLine('Me', '내일 저녁에 같이 밥 먹을래요?');
    DuoBrain.rememberContextLine('Partner', "Sure, I'd love to.");
    for (final lang in ['Korean', 'Japanese']) {
      final block = DuoBrain.contextBlock(lang);
      expect(block, contains('RECENT CONVERSATION'));
      expect(block, contains('Me: 내일 저녁에 같이 밥 먹을래요?'));
      expect(block, contains("Partner: Sure, I'd love to."));
      expect(block, contains('Do NOT translate, answer, or repeat'));
    }
  });

  test('말투 구분이 없는 도착 언어에는 붙이지 않는다', () {
    DuoBrain.rememberContextLine('Me', '내일 저녁에 같이 밥 먹을래요?');
    for (final lang in ['English', 'Spanish', 'Chinese']) {
      expect(DuoBrain.contextBlock(lang), isEmpty, reason: lang);
    }
  });

  test('최근 6줄만 남긴다', () {
    for (var i = 1; i <= 9; i++) {
      DuoBrain.rememberContextLine(i.isEven ? 'Me' : 'Partner', '문장$i');
    }
    final block = DuoBrain.contextBlock('Korean');
    expect(block, isNot(contains('문장1')));
    expect(block, isNot(contains('문장3')));
    expect(block, contains('문장4'));
    expect(block, contains('문장9'));
  });

  test('빈 줄은 기억하지 않고, 비우면 다음 통화로 새지 않는다', () {
    DuoBrain.rememberContextLine('Me', '   ');
    expect(DuoBrain.contextBlock('Korean'), isEmpty);
    DuoBrain.rememberContextLine('Me', '안녕하세요');
    expect(DuoBrain.contextBlock('Korean'), contains('안녕하세요'));
    DuoBrain.clearContext();
    expect(DuoBrain.contextBlock('Korean'), isEmpty);
  });
}
