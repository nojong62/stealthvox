import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/transcript_repair_guard.dart';

void main() {
  group('isMinimalTranscriptRepair', () {
    test('손대지 않은 문장은 그대로 통과한다', () {
      const line = '이번 주 토요일에 연구회 모임이 한강공원에서 있다더라!';
      expect(isMinimalTranscriptRepair(line, line), isTrue);
    });

    test('잘못 들은 낱말 하나는 교정으로 인정한다', () {
      expect(isMinimalTranscriptRepair('우리 병 중에서', '우리 반 중에서'), isTrue);
    });

    test('문장을 다시 쓴 것은 교정이 아니다 — 실기기에서 나온 그 줄', () {
      expect(
        isMinimalTranscriptRepair(
          '이번 주 토요일에 연구회 모임이 한강공원에서 있다더라!',
          '이번 주 토요일에 연구회가 한강공원으로 옮겨진다더라!',
        ),
        isFalse,
      );
    });

    test('낱말이 줄면 거절한다 — 지우는 것은 교정이 아니다', () {
      expect(
        isMinimalTranscriptRepair('그 소식은 언제 나온 얘긴데?', '그 소식은 언제 나왔는데?'),
        isFalse,
      );
    });

    test('낱말이 늘어도 거절한다', () {
      expect(
        isMinimalTranscriptRepair('내일 보자', '내일 다시 보자'),
        isFalse,
      );
    });

    test('긴 줄에서는 두 낱말까지 고칠 수 있다', () {
      expect(
        isMinimalTranscriptRepair(
          '어제 친구랑 종로에서 밥 먹고 영화 봤어 그리고 집에 갔어',
          '어제 친구랑 종로에서 밥 먹고 연극 봤어 그리고 집에 왔어',
        ),
        isTrue,
      );
    });

    test('낱말 수가 같아도 절반을 바꾸면 다시 쓴 것이다', () {
      expect(
        isMinimalTranscriptRepair(
          '어제 친구랑 종로에서 밥 먹고 영화 봤어 그리고 집에 갔어',
          '오늘 동생이랑 강남에서 술 먹고 영화 봤어 그리고 집에 갔어',
        ),
        isFalse,
      );
    });

    test('빈 교정문은 받지 않는다 — 줄이 통째로 사라진다', () {
      expect(isMinimalTranscriptRepair('내일 보자', '   '), isFalse);
    });

    test('앞뒤 공백 차이는 손댄 것으로 치지 않는다', () {
      expect(isMinimalTranscriptRepair('내일 보자', '  내일 보자 '), isTrue);
    });
  });
}
