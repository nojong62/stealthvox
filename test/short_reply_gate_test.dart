import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/short_reply_gate.dart';

void main() {
  group('🗣️ [SHORT-REPLY] 소리 난 시간이 짧은 대답을 살린다', () {
    test('문턱은 800ms에서 출발한다', () {
      expect(kShortReplyMinVoicedMs, 800);
    });

    test('2026-09-16 시나리오톡 "네."(1260ms)는 살아난다', () {
      expect(shortReplyRescuedByVoice(1260), isTrue);
    });

    test('경계: 800은 살고 799는 죽는다', () {
      expect(shortReplyRescuedByVoice(800), isTrue);
      expect(shortReplyRescuedByVoice(799), isFalse);
    });

    test('값을 못 쟀으면(null) 예전대로 환청 목록이 이긴다', () {
      expect(shortReplyRescuedByVoice(null), isFalse);
    });

    test('문턱은 호출부가 바꿀 수 있다', () {
      expect(shortReplyRescuedByVoice(500, minMs: 400), isTrue);
      expect(shortReplyRescuedByVoice(500, minMs: 600), isFalse);
    });
  });
}
