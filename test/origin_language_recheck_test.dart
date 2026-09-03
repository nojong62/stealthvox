// 🌐 [ORIGIN-RECHECK] 로비 설정과 다른 언어로 말을 시작했을 때.
//
// 로비에서 대화 언어(ORIGIN)를 미리 고르지만, 유저가 그 설정과 다른 말로
// 시작하는 일은 흔하다(기본값 Korean을 그대로 둔 채 영어를 말한다).
//
// 여기서 지키는 것 셋:
//   ① 세 모드 모두 **말풍선이 아니라 창**을 띄운다 — 말풍선은 "다음에는
//      로비에서 맞춰 주세요"밖에 못 한다. 로비로 가려면 방을 나가야 하고,
//      나가면 이 대화는 사라진다.
//   ② 창의 글자는 전부 **감지된 언어**로 적힌다 — 읽어야 할 사람이 못 읽으면
//      창을 띄운 뜻이 없다.
//   ③ 확정하면 로비 설정까지 바꾸고 **히스토리 방 문서의 언어값도 같이**
//      맞춘다 — 그 값이 어긋나면 히스토리가 엉뚱한 언어로 배울글을 만든다.
//   ④ **기준은 언제나 유저가 확정한 ORIGIN이다.** 감지된 언어는 창을 띄우려고
//      쓰는 정보일 뿐이라, "그대로 두기"를 누르면 세션에도 히스토리에도 한
//      글자도 남지 않는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/origin_language_session.dart';
import 'package:stealth_vox/custom_code/widgets/first_utterance_context_judge.dart'
    show
        originLanguageApplyLabel,
        originLanguageCheckPromptLine,
        originLanguageKeepLabel,
        originLanguageResetHintLine;

const String _dialog =
    'lib/custom_code/widgets/origin_language_recheck_dialog.dart';
const String _circle = 'lib/custom_code/widgets/routine_mode_circle_talk.dart';
const String _scenario =
    'lib/custom_code/widgets/routine_mode_scenario_talk.dart';
const String _duo = 'lib/custom_code/widgets/routine_mode_duo.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// [start] 선언부터 다음 선언 [end] 직전까지의 소스 조각.
///
/// group() 본문에서도 부르므로 `expect`를 쓰지 않는다 — 테스트 밖에서 부르면
/// 파일이 통째로 로드 실패한다.
String _region(String src, String start, String end) {
  final int a = src.indexOf(start);
  if (a < 0) throw StateError('없는 선언: $start');
  final int b = src.indexOf(end, a + 1);
  if (b < a) throw StateError('없는 선언: $end');
  return src.substring(a, b);
}

void main() {
  final String dialog = _read(_dialog);
  final String duo = _read(_duo);

  const Map<String, String> modes = <String, String>{
    '서클톡': _circle,
    '시나리오톡': _scenario,
  };

  // ==========================================================================
  group('① 세 모드가 같은 창을 쓴다', () {
    for (final entry in modes.entries) {
      final String src = _read(entry.value);

      test('${entry.key}은 말풍선이 아니라 창을 띄운다', () {
        expect(src, contains('showOriginLanguageRecheckDialog('),
            reason: '${entry.key}이 언어 확인 창을 안 띄운다');
        expect(src, isNot(contains('originLanguageSwitchedNoticeLine')),
            reason: '${entry.key}에 옛 말풍선이 남아 있다');
      });

      test('${entry.key}은 세션당 한 번만 묻는다', () {
        final String region = _region(src, 'Future<void> _promptOriginRecheck(',
            'Future<void> _applyOriginRecheck(');
        expect(
            region,
            contains(
                'if (!OriginLanguageSession.instance.takeNoticeSlot()) return;'),
            reason: '${entry.key}이 매 턴 물을 수 있다');
      });
    }

    test('만능 통역은 제 오버레이를 그대로 쓴다 (통화를 안 끊는 막)', () {
      expect(duo, contains('_buildOriginMismatchOverlay('));
      expect(duo, contains('originLanguageCheckPromptLine(detected)'));
    });
  });

  // ==========================================================================
  group('② 창의 글자는 감지된 언어로 적힌다', () {
    test('안내·부제·버튼이 모두 감지된 언어를 받는다', () {
      for (final String call in <String>[
        'originLanguageCheckPromptLine(detected)',
        'originLanguageResetHintLine(detected)',
        'originLanguageApplyLabel(detected)',
        'originLanguageKeepLabel(detected)',
      ]) {
        expect(dialog, contains(call), reason: '창에 $call 이 없다');
      }
    });

    test('만능 통역 오버레이의 부제도 영어로 박혀 있지 않다', () {
      expect(duo, contains('originLanguageResetHintLine(detected)'));
      expect(duo, isNot(contains('this only changes ')),
          reason: '영어로 박아 둔 옛 부제가 남아 있다');
    });

    test('부제는 "재설정하셔도 된다"는 권유다 — 이미 바꿨다는 통보가 아니다', () {
      expect(originLanguageResetHintLine('Korean'), contains('재설정'));
      // 이 창은 아직 아무것도 바꾸지 않았다.
      expect(originLanguageResetHintLine('Korean'), isNot(contains('진행할게요')));
    });

    test('로비 ORIGIN 12개 모두 빈 문구가 없다', () {
      for (final String lang in kOriginLanguageOptions) {
        for (final String line in <String>[
          originLanguageResetHintLine(lang),
          originLanguageApplyLabel(lang),
          originLanguageKeepLabel(lang),
          originLanguageCheckPromptLine(lang),
        ]) {
          expect(line.trim(), isNotEmpty, reason: '$lang 문구가 비어 있다');
        }
      }
    });

    test('알 수 없는 언어는 영어로 떨어진다', () {
      expect(originLanguageResetHintLine('Swahili'),
          originLanguageResetHintLine('English'));
    });
  });

  // ==========================================================================
  group('③ 확정하면 설정과 히스토리가 함께 바뀐다', () {
    for (final entry in modes.entries) {
      final String src = _read(entry.value);
      final String region = _region(src, 'Future<void> _applyOriginRecheck(',
          'Future<void> _syncHistoryRoomLanguages(');

      test('${entry.key}: ORIGIN을 로비 설정에 저장한다', () {
        expect(region, contains('FFAppState().nativeLang = native'));
      });

      test('${entry.key}: 만지지 않은 TARGET은 건드리지 않는다', () {
        expect(region,
            contains('if (target != null) FFAppState().targetLang = target;'));
      });

      test('${entry.key}: 이 방의 ORIGIN도 고른 값으로 다시 잡는다', () {
        expect(region,
            contains('OriginLanguageSession.instance.override(native)'),
            reason: '판정값과 다른 언어를 골랐을 때 전사기가 판정값에 묶인다');
      });

      test('${entry.key}: 히스토리 방 문서의 언어값을 같이 맞춘다', () {
        expect(region, contains('_syncHistoryRoomLanguages()'));
      });

      test('${entry.key}: 대화를 끊는 코드가 없다', () {
        for (final String forbidden in <String>[
          '_handleAutoSaveAndExit',
          'dispose()',
          'StealthRoomMaster.exitCurrentMode',
        ]) {
          expect(region, isNot(contains(forbidden)),
              reason: '확정이 대화를 끊는다: $forbidden');
        }
      });
    }

    test('만능 통역도 확정할 때 히스토리 언어값을 맞춘다', () {
      final String region = _region(duo, 'Future<void> _applyOriginChange(',
          'Future<void> _syncHistoryRoomLanguages(');
      expect(
          region, contains('OriginLanguageSession.instance.override(native)'));
      expect(region, contains('_syncHistoryRoomLanguages()'));
    });

    test('만능 통역 히스토리 방은 로비값이 아니라 통역이 쓰는 언어로 만든다', () {
      // `_myNative()`는 확정 뒤의 설정을 그대로 읽는다. 여기가 어긋나면
      // 원문이 배울글 자리에 그대로 복사된다.
      expect(duo, contains("'native_lang': _myNative(),"));
      expect(duo, isNot(contains("'native_lang': FFAppState().nativeLang,")));
    });
  });

  // ==========================================================================
  // ④ 여기가 이 파일의 핵심이다. 2026-09-04 이전에는 판정만으로 ORIGIN이
  //    갈아 끼워졌고, 그래서 **유저가 고르지도 않은 언어가 히스토리
  //    `native_lang`에 남았다.** 아래 두 시나리오가 그 반대편이다.
  group('④ 기준은 유저가 확정한 ORIGIN이다', () {
    setUp(() => OriginLanguageSession.instance.begin());

    /// 세 모드가 히스토리에 적는 값과 **같은 식**이다.
    ///   서클톡·시나리오톡 `_nativeLangName()` → `session.resolve(로비값)`
    ///   만능통역 `_myNative()`               → 확정값(`FFAppState().nativeLang`)
    /// 확정하면 호출부가 두 곳에 같은 값을 적으므로 결국 하나로 모인다.
    String historyNativeLang(String lobbyOrigin) =>
        OriginLanguageSession.instance.resolve(lobbyOrigin);

    test('English 감지 + 로비 Korean + 그대로 두기 → Korean 유지', () {
      final s = OriginLanguageSession.instance;
      s.adopt('English'); // 첫 발화가 영어였다 → 창을 띄운다
      expect(s.takeNoticeSlot(), isTrue, reason: '물어보기는 해야 한다');
      // "그대로 두기" — 호출부는 아무것도 하지 않는다(override 없음).
      expect(historyNativeLang('Korean'), 'Korean',
          reason: '유저가 고르지도 않은 English가 히스토리에 남으면 안 된다');
      expect(s.switched, isFalse);
      // sourceLang의 마지막 폴백도 같은 값이다.
      expect(s.resolve('Korean'), 'Korean');
    });

    test('English 감지 + English로 변경 → English로 바뀐다', () {
      final s = OriginLanguageSession.instance;
      s.adopt('English');
      s.override('English'); // 유저가 창에서 확정했다
      expect(historyNativeLang('Korean'), 'English');
      expect(s.switched, isTrue);
    });

    test('유저는 판정과 다른 언어로도 확정할 수 있다', () {
      final s = OriginLanguageSession.instance;
      s.adopt('English');
      s.override('Japanese'); // 일부러 다른 언어를 연습하는 경우
      expect(historyNativeLang('Korean'), 'Japanese');
    });

    test('목록 밖의 언어로는 확정되지 않는다', () {
      final s = OriginLanguageSession.instance;
      s.override('Swahili');
      expect(historyNativeLang('Korean'), 'Korean');
    });

    test('확정해도 판정은 끝난 것으로 본다 (매 턴 다시 묻지 않는다)', () {
      final s = OriginLanguageSession.instance;
      s.override('English');
      expect(s.settled, isTrue);
    });
  });

  // ==========================================================================
  group('④-b 감지값이 몰래 새어 나가지 않는다', () {
    test('서클톡·시나리오톡은 전사 소켓에 로비 ORIGIN을 박는다', () {
      for (final entry in modes.entries) {
        final String src = _read(entry.value);
        final String region = _region(src,
            'Future<void> _settleOriginLanguage(', 'Future<void> _promptOriginRecheck(');
        expect(region, contains('switchLanguage(_nativeLangCode())'),
            reason: '${entry.key}: 소켓에 박는 값이 로비 ORIGIN이 아니다');
        expect(region, isNot(contains('switchLanguage(detected')),
            reason: '${entry.key}: 감지값을 소켓에 박고 있다');
      }
    });

    test('만능 통역도 감지값이 아니라 확정 ORIGIN을 박는다', () {
      final String region = _region(duo,
          'Future<void> _settleInterpreterOrigin(', 'Future<void> _applyOriginChange(');
      expect(region,
          contains('switchLanguage(_mapLanguageToCode(_myNative()))'));
      expect(region, isNot(contains('detected ?? lobbyOrigin')),
          reason: '감지값이 통역의 전사 언어를 갈아 끼우고 있다');
    });

    test('세션의 adopt()는 ORIGIN을 바꾸지 않는다', () {
      final String svc =
          _read('lib/custom_code/services/origin_language_session.dart');
      final String region =
          _region(svc, 'void adopt(String? languageName)', 'void override(');
      expect(region, contains('_detected = languageName;'));
      expect(region, isNot(contains('_override =')),
          reason: '판정이 ORIGIN을 덮으면 유저가 안 고른 언어가 기록에 남는다');
    });
  });
}
