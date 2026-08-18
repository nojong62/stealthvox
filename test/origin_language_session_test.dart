import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/origin_language_session.dart';

void main() {
  group('detectOriginScript', () {
    void expectDecisive(String text, String language) {
      final v = detectOriginScript(text);
      expect(v.decisive, isTrue, reason: '"$text" → ${v.reason}');
      expect(v.language, language, reason: '"$text" → ${v.reason}');
    }

    void expectUndecided(String text, String reason) {
      final v = detectOriginScript(text);
      expect(v.decisive, isFalse, reason: '"$text" → ${v.reason}');
      expect(v.reason, reason);
    }

    test('한글은 한국어로 확정된다', () {
      expectDecisive('어제 친구랑 카페에 갔어요', 'Korean');
    });

    test('가나가 섞이면 한자가 있어도 일본어다', () {
      expectDecisive('昨日は友達とカフェに行きました', 'Japanese');
    });

    test('가나 없이 한자만이면 중국어다', () {
      expectDecisive('我昨天和朋友去了咖啡馆', 'Chinese');
    });

    test('키릴 문자는 러시아어다', () {
      expectDecisive('Вчера я ходил в кафе с другом', 'Russian');
    });

    test('데바나가리는 힌디어다', () {
      expectDecisive('मैं कल दोस्त के साथ कैफे गया', 'Hindi');
    });

    test('라틴 문자는 문자만으로 못 가른다', () {
      expectUndecided('I went to a cafe with a friend', 'latin_needs_judge');
      expectUndecided('Ayer fui a un café con un amigo', 'latin_needs_judge');
    });

    test('짧은 한마디로는 언어를 뒤집지 않는다', () {
      expectUndecided('네', 'too_short');
      expectUndecided('응', 'too_short');
      expectUndecided('はい', 'too_short');
    });

    test('숫자·문장부호만이면 근거가 없다', () {
      expectUndecided('... 123 !!', 'no_countable_chars');
    });

    test('한글 문장에 외래어가 섞여도 한국어다', () {
      expectDecisive('오늘 meeting 끝나고 집에 갔어요', 'Korean');
      expectDecisive('넷플릭스에서 Stranger Things 봤어요', 'Korean');
    });

    test('영어 문장에 한두 글자만 섞이면 라틴 판정으로 넘어간다', () {
      expectUndecided('hello world how are you 안녕', 'latin_needs_judge');
    });

    test('일본어에 영어가 섞여도 일본어다', () {
      expectDecisive('今日の meeting は長かったです', 'Japanese');
    });
  });

  group('OriginLanguageSession', () {
    setUp(() => OriginLanguageSession.instance.begin());

    test('판정 전에는 로비값을 그대로 쓴다', () {
      final s = OriginLanguageSession.instance;
      expect(s.settled, isFalse);
      expect(s.resolve('Korean'), 'Korean');
    });

    test('null 채택은 로비값 유지로 확정된다', () {
      final s = OriginLanguageSession.instance;
      s.adopt(null);
      expect(s.settled, isTrue);
      expect(s.switched, isFalse);
      expect(s.resolve('Korean'), 'Korean');
    });

    test('채택하면 그 언어가 로비값을 이긴다', () {
      final s = OriginLanguageSession.instance;
      s.adopt('Japanese');
      expect(s.resolve('Korean'), 'Japanese');
    });

    test('로비 목록 밖 언어는 채택하지 않는다', () {
      final s = OriginLanguageSession.instance;
      s.adopt('Klingon');
      expect(s.switched, isFalse);
      expect(s.resolve('Korean'), 'Korean');
    });

    test('안내 말풍선은 세션당 한 번만 나간다', () {
      final s = OriginLanguageSession.instance;
      s.adopt('Japanese');
      expect(s.takeNoticeSlot(), isTrue);
      expect(s.takeNoticeSlot(), isFalse);
    });

    test('전환이 없으면 안내도 없다', () {
      final s = OriginLanguageSession.instance;
      s.adopt(null);
      expect(s.takeNoticeSlot(), isFalse);
    });

    test('begin()이 세션 전환을 되돌린다 — 다음 입장은 로비값에서 시작한다', () {
      final s = OriginLanguageSession.instance;
      s.adopt('Japanese');
      s.begin();
      expect(s.settled, isFalse);
      expect(s.switched, isFalse);
      expect(s.resolve('Korean'), 'Korean');
    });
  });
}
