// 🏷️ [LANG-LABEL] 화면에 적는 언어 이름은 방의 ChatLang/LearnLang에서 온다.
//
// 히스토리 언어 토글 툴팁이 '영어만 보기' / '한글만 보기'로 박혀 있었다.
// ChatLang이 한국어이고 LearnLang이 영어인 사람에게만 맞는 말이라,
// 일본어↔스페인어로 쓰는 사람에게는 **없는 언어를 말하고 있었다.**
//
// 여기서 지키는 것 셋:
//   ① 표는 `koreanLanguageDisplayName` 하나뿐이다 (화면마다 만들면 어긋난다)
//   ② 툴팁은 방 문서의 `native_lang`/`target_lang`을 읽어 짓는다
//   ③ 두 필드가 없는 옛 기록은 언어 이름 대신 필드 이름으로 적는다

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/origin_language_session.dart';

const String _history = 'lib/custom_code/widgets/chat_history_master.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final String history = _read(_history);

  // ==========================================================================
  group('① 표시명 표는 한 곳뿐이다', () {
    test('로비 12개가 모두 한국어 이름을 갖는다', () {
      const Map<String, String> expected = <String, String>{
        'Korean': '한국어',
        'English': '영어',
        'Japanese': '일본어',
        'Chinese': '중국어',
        'Spanish': '스페인어',
        'French': '프랑스어',
        'German': '독일어',
        'Hindi': '힌디어',
        'Russian': '러시아어',
        'Portuguese': '포르투갈어',
        'Italian': '이탈리아어',
        'Dutch': '네덜란드어',
      };
      for (final String lang in kOriginLanguageOptions) {
        expect(expected.containsKey(lang), isTrue,
            reason: '$lang 의 표시명이 표에 없다');
        expect(koreanLanguageDisplayName(lang), expected[lang]);
      }
    });

    test('대소문자·공백 차이를 흡수한다', () {
      expect(koreanLanguageDisplayName(' japanese '), '일본어');
      expect(koreanLanguageDisplayName('JAPANESE'), '일본어');
    });

    test('목록 밖의 값은 지어내지 않고 그대로 돌려준다', () {
      // 엉뚱한 언어 이름을 적느니 영문 이름이 보이는 편이 낫다.
      expect(koreanLanguageDisplayName('Swahili'), 'Swahili');
      expect(koreanLanguageDisplayName(''), '');
    });
  });

  // ==========================================================================
  group('② 툴팁은 방의 ChatLang/LearnLang으로 짓는다', () {
    test('한/영이 박힌 문구가 남아 있지 않다', () {
      final String code = history
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
          .join('\n');
      for (final String hard in <String>[
        "'영어만 보기'",
        "'한글만 보기'",
        "'영어+한글 보기'",
      ]) {
        expect(code, isNot(contains(hard)), reason: '$hard 가 아직 박혀 있다');
      }
    });

    test('툴팁이 두 필드를 읽는다', () {
      expect(history, contains('tooltip: _langToggleTooltip()'));
      final int a = history.indexOf('String _langToggleTooltip()');
      final int b = history.indexOf('bool? get _recordSameLang');
      expect(a, greaterThan(-1));
      expect(b, greaterThan(a));
      final String region = history.substring(a, b);
      expect(region, contains('_sessionNativeLang'), reason: 'ChatLang을 안 읽는다');
      expect(region, contains('_sessionTargetLang'), reason: 'LearnLang을 안 읽는다');
      expect(region, contains('koreanLanguageDisplayName(chat)'));
      expect(region, contains('koreanLanguageDisplayName(learn)'));
      // 저장 구조를 건드리지 않는다 — 읽기만 하는 함수다.
      expect(region, isNot(contains('.update(')));
      expect(region, isNot(contains('FFAppState()')),
          reason: '툴팁은 지금 로비 설정이 아니라 이 방에 저장된 값을 적어야 한다');
    });

    test('옛 기록(두 필드 없음)은 필드 이름으로 적는다', () {
      final int a = history.indexOf('String _langToggleTooltip()');
      final int b = history.indexOf('bool? get _recordSameLang');
      final String region = history.substring(a, b);
      expect(region, contains("'배울글만 보기'"));
      expect(region, contains("'원문만 보기'"));
      expect(region, contains("'원문+배울글 보기'"));
    });
  });

  // ==========================================================================
  group('③ 방어 로직은 그대로 있다', () {
    // 상대 선언값·저장된 글자를 표시 단계에서 보정하는 기존 장치다.
    // ChatLang 설정을 바꾸는 물건이 아니므로 걷어내지 않는다.
    test('_sourceLangForMessage가 살아 있다', () {
      expect(history, contains('String _sourceLangForMessage('));
      expect(history, contains('detectOriginScript(text)'));
    });

    test('_resolvePartnerSrcLang이 살아 있다', () {
      expect(_read('lib/custom_code/widgets/routine_mode_duo.dart'),
          contains('String _resolvePartnerSrcLang('));
    });
  });
}
