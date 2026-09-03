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
      expect(s.mismatched, isFalse);
      expect(s.switched, isFalse);
      expect(s.resolve('Korean'), 'Korean');
    });

    // 🚫 2026-09-04: 판정이 ORIGIN을 이기던 시절의 반대편이다.
    //   그때는 유저가 고르지도 않은 언어가 히스토리 `native_lang`에 남았다.
    test('판정은 로비값을 이기지 못한다 — 물어볼 근거로만 남는다', () {
      final s = OriginLanguageSession.instance;
      s.adopt('Japanese');
      expect(s.detected, 'Japanese');
      expect(s.mismatched, isTrue);
      expect(s.switched, isFalse);
      expect(s.resolve('Korean'), 'Korean');
    });

    test('유저가 확정해야 ORIGIN이 바뀐다', () {
      final s = OriginLanguageSession.instance;
      s.adopt('Japanese');
      s.override('Japanese');
      expect(s.switched, isTrue);
      expect(s.resolve('Korean'), 'Japanese');
    });

    test('유저는 판정과 다른 언어로도 확정할 수 있다', () {
      final s = OriginLanguageSession.instance;
      s.adopt('Japanese');
      s.override('French'); // 일부러 다른 언어를 연습하는 경우
      expect(s.resolve('Korean'), 'French');
    });

    test('로비 목록 밖 언어는 판정으로 치지 않는다', () {
      final s = OriginLanguageSession.instance;
      s.adopt('Klingon');
      expect(s.mismatched, isFalse);
      expect(s.switched, isFalse);
      expect(s.resolve('Korean'), 'Korean');
    });

    test('확인 창은 세션당 한 번만 뜬다', () {
      final s = OriginLanguageSession.instance;
      s.adopt('Japanese');
      expect(s.takeNoticeSlot(), isTrue);
      expect(s.takeNoticeSlot(), isFalse);
    });

    test('어긋난 것이 없으면 묻지도 않는다', () {
      final s = OriginLanguageSession.instance;
      s.adopt(null);
      expect(s.takeNoticeSlot(), isFalse);
    });

    test('begin()이 확정까지 되돌린다 — 다음 입장은 로비값에서 시작한다', () {
      final s = OriginLanguageSession.instance;
      s.adopt('Japanese');
      s.override('Japanese');
      s.begin();
      expect(s.settled, isFalse);
      expect(s.mismatched, isFalse);
      expect(s.switched, isFalse);
      expect(s.resolve('Korean'), 'Korean');
    });
  });

  // 2026-08-28 실기기: 게스트 줄이 src=English로 실려 와 배울언어(English)와
  // 같아지는 바람에 한국어가 배울글 자리에 복사됐다. 선언이 아니라 글자를 본다.
  group('선언 대신 글자로 확인한다', () {
    test('한글 문장은 Korean이 맞고 English는 아니다', () {
      expect(textIsLanguage('책 얘기도 하고 그랬어', 'Korean'), isTrue);
      expect(textContradictsLanguage('책 얘기도 하고 그랬어', 'English'), isTrue);
    });

    test('라틴 문자는 글자로 못 가른다 — 선언을 뒤집지 않는다', () {
      expect(textIsLanguage('I deleted the old one', 'English'), isFalse);
      expect(
          textContradictsLanguage('I deleted the old one', 'Spanish'), isFalse);
    });

    test('짧은 맞장구로는 뒤집지 않는다', () {
      expect(textContradictsLanguage('네', 'English'), isFalse);
    });

    test('언어 이름이 비면 판정하지 않는다', () {
      expect(textIsLanguage('안녕하세요 반갑습니다', ''), isFalse);
      expect(textContradictsLanguage('안녕하세요 반갑습니다', '  '), isFalse);
    });

    test('대소문자는 무시한다', () {
      expect(textIsLanguage('어제 친구랑 카페에 갔어요', 'korean'), isTrue);
    });
  });
}
