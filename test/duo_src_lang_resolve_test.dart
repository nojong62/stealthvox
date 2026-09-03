// 🌐 [SRC-LANG] 상대 발화가 무슨 언어인지 고르는 규칙의 시험.
//
// 이 판단 하나가 **번역을 할지 말지**를 가른다. 상대 언어를 내 언어로
// 잘못 고르면 `same=true`가 되어 번역을 통째로 건너뛰고, 상대 원문이 내
// 언어 목소리로 그대로 읽힌다. 유저에게는 "말이 전달 안 된다"로 보인다.
//
// 실제로 그렇게 됐다 — 2026-09-03 SM-S931N ↔ SM-F946N 통화:
//   호스트(ORIGIN=English)가 아주 작게 9글자를 말함 (rmsDbfs=-40.7)
//   → 전사기가 한글을 뱉음
//   → 게스트가 "한국어"로 확정 → same=true → 번역 건너뜀
//   → `[INTERP-TURN] incoming src=Korean mine=Korean same=true gptCalls=0`
// 같은 통화의 19·109글자 발화는 정상이었다.
//
// 고친 규칙 한 줄:
//   **짧은 글자로는 상대가 실어 보낸 선언값을 뒤집지 않는다.**

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/origin_language_session.dart';

const String _duo = 'lib/custom_code/widgets/routine_mode_duo.dart';

/// `_resolvePartnerSrcLang`와 **같은 규칙**을 떼어 낸 모형.
/// 위젯 안 private 메서드라 직접 못 부르므로, 규칙을 여기 두고 원문이
/// 그 모양을 유지하는지는 아래 소스 시험이 지킨다.
String resolveSrcLang({
  required String raw,
  required String declared,
  String partnerChatLang = '',
  String myNative = 'Korean',
  int minChars = 12,
}) {
  final text = raw.trim();
  if (text.length >= minChars || declared.isEmpty) {
    final v = detectOriginScript(text);
    if (v.decisive && v.language != null) return v.language!;
  }
  if (declared.isNotEmpty) return declared;
  if (partnerChatLang.isNotEmpty) return partnerChatLang;
  return myNative;
}

void main() {
  final String duo = File(_duo).readAsStringSync().replaceAll('\r\n', '\n');

  group('🔴 실기기에서 터진 그 상황', () {
    test('짧은 글자가 잘못 전사돼도 선언값을 뒤집지 않는다', () {
      // 호스트는 English로 선언했는데 9글자 한글이 실려 왔다.
      final got = resolveSrcLang(raw: '안녕하세요네네', declared: 'English');
      expect(got, 'English',
          reason: '짧은 전사 오류가 선언값을 이기면 번역을 건너뛴다');
    });

    test('그래서 번역을 건너뛰지 않는다 (same=false)', () {
      const myNative = 'Korean';
      final src = resolveSrcLang(raw: '안녕하세요네네', declared: 'English');
      expect(src == myNative, isFalse,
          reason: 'same=true가 되면 원문이 내 언어 목소리로 읽힌다');
    });

    test('한 글자·네 글자짜리 조각도 마찬가지다', () {
      // 같은 통화에서 len=1, len=4 조각도 올라왔다.
      expect(resolveSrcLang(raw: '네', declared: 'English'), 'English');
      expect(resolveSrcLang(raw: '음 그래', declared: 'English'), 'English');
    });
  });

  group('✅ 긴 글자는 여전히 선언값을 뒤집는다', () {
    test('로비에 영어라 적어 두고 한국어로 길게 말하면 한국어로 본다', () {
      // 이 뒤집기를 없애면 안 된다 — 그게 원래 이 코드가 있는 이유다.
      // 선언값을 그대로 저장하면 내 배울 언어와 같아져 공부방이
      // "번역할 게 없다"고 본다.
      const long = '저는 주말에 사람이 너무 많은 곳보다는 조용한 데서 쉬는 걸 좋아해요';
      expect(long.length, greaterThanOrEqualTo(12));
      expect(resolveSrcLang(raw: long, declared: 'English'), 'Korean');
    });

    test('실측된 정상 발화 길이(19·20·30·42·109)는 전부 판정을 허용한다', () {
      for (final int len in <int>[19, 20, 30, 42, 109]) {
        expect(len >= 12, isTrue, reason: '$len 자가 문턱에 걸리면 안 된다');
      }
    });

    test('실측된 오류 조각 길이(1·4·9)는 전부 막힌다', () {
      for (final int len in <int>[1, 4, 9]) {
        expect(len >= 12, isFalse, reason: '$len 자가 통과하면 그때 터진 버그다');
      }
    });
  });

  group('선언값이 없을 때는 글자를 믿는다', () {
    test('옛 방(srcLang 없음)은 짧아도 글자로 판정한다', () {
      // 달리 믿을 근거가 없다. 여기서 막으면 아무것도 못 고른다.
      expect(resolveSrcLang(raw: '안녕하세요네네', declared: ''), 'Korean');
    });

    test('글자로도 못 정하면 세션 문서 값을 쓴다', () {
      expect(
          resolveSrcLang(raw: 'OK', declared: '', partnerChatLang: 'Japanese'),
          'Japanese');
    });

    test('그것도 없으면 내 대화 언어다 — English로 넘겨짚지 않는다', () {
      expect(resolveSrcLang(raw: 'OK', declared: '', myNative: 'Korean'),
          'Korean');
    });
  });

  group('원문이 이 규칙을 유지한다', () {
    test('문턱 상수가 있고 12다', () {
      expect(duo, contains('const int kDuoSrcLangOverrideMinChars = 12;'));
    });

    test('길이 조건이 글자 판정보다 앞에 있다', () {
      final int start = duo.indexOf('String _resolvePartnerSrcLang(');
      expect(start, greaterThan(-1));
      final String body = duo.substring(start, start + 1800);
      final int guard = body.indexOf('kDuoSrcLangOverrideMinChars');
      final int detect = body.indexOf('detectOriginScript(');
      expect(guard, greaterThan(-1));
      expect(detect, greaterThan(-1));
      expect(guard, lessThan(detect),
          reason: '길이 확인 없이 글자 판정이 먼저 돌면 고친 것이 무의미하다');
    });

    test('선언값이 비었을 때는 길이와 무관하게 판정한다', () {
      final int start = duo.indexOf('String _resolvePartnerSrcLang(');
      final String body = duo.substring(start, start + 1800);
      expect(body, contains('|| declared.isEmpty'));
    });

    test('판정 근거가 로그에 남는다', () {
      // 틀렸을 때 이 한 줄이 유일한 단서다.
      expect(duo, contains("'[SRC-LANG]'"));
      expect(duo, contains('overrideAllowed='));
    });

    test('로그에 전사문을 싣지 않는다 — 길이와 근거만', () {
      final int at = duo.indexOf("'[SRC-LANG]'");
      expect(at, greaterThan(-1));
      final String block = duo.substring(at, at + 320);
      expect(block, contains('len='));
      expect(block, isNot(contains('text=')),
          reason: '진단 로그에 상대 발화 원문을 실으면 안 된다');
    });

    test('detectOriginScript 자체는 안 건드렸다', () {
      // 서클톡·시나리오톡이 같은 함수를 쓴다. 그쪽은 선언값이라는 대안이
      // 없어 지금 문턱(4글자)이 맞다.
      final String svc = File('lib/custom_code/services/origin_language_session.dart')
          .readAsStringSync();
      expect(svc, contains('const int _kMinNonLatinChars = 4;'));
    });
  });
}
