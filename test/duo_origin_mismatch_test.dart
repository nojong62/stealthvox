// 🌐 [INTERP-ORIGIN] 로비 ORIGIN이 실제 발화 언어와 어긋났을 때의 동작.
//
// **만능 통역 전용이다.** 직접 대화는 이번 변경에서 건드리지 않았다 —
// 그때 WebRTC 검증 중이어서 두 변수를 섞지 않으려 했다.
//
// 이 기능이 필요한 이유: ORIGIN이 틀리면 통역은 **번역 방향 자체가 틀린다.**
// 한국어로 설정한 사람이 영어를 말하면 상대는 영어를 영어로 옮긴 말을 듣는다.
//
// 여기서 지키는 것 셋:
//   ① 짧은 말·고유명사·한두 단어로는 판정하지 않는다
//   ② 판정은 세션당 한 번이고, Keep Current 뒤에는 다시 묻지 않는다
//   ③ 내 판정에 상대 발화가 섞이지 않는다

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/origin_language_session.dart';
import 'package:stealth_vox/custom_code/widgets/first_utterance_context_judge.dart'
    show originLanguageCheckPromptLine;

const String _duo = 'lib/custom_code/widgets/routine_mode_duo.dart';

void main() {
  final String duo =
      File(_duo).readAsStringSync().replaceAll('\r\n', '\n');

  // ==========================================================================
  group('① 짧은 말로는 판정하지 않는다', () {
    test('한국어 설정 → 충분한 한국어 발화 → 같은 언어라 물을 것이 없다', () {
      final v = detectOriginScript('오늘 오후에 시간이 괜찮으면 같이 커피 마시러 갈까요');
      expect(v.decisive, isTrue);
      expect(v.language, 'Korean');
    });

    test('한국어 설정 → 영어 한두 단어 → 판정 대상이 아니다', () {
      // "OK", "Sorry" 같은 코드스위칭. 라틴 문자가 너무 적어 판정이 안 선다.
      for (final String text in <String>['OK', 'Sorry', 'Really?']) {
        expect(detectOriginScript(text).decisive, isFalse,
            reason: '"$text" 로 언어를 단정하면 안 된다');
      }
    });

    test('고유명사 하나로는 판정하지 않는다', () {
      expect(detectOriginScript('Netflix').decisive, isFalse);
      expect(detectOriginScript('Amazon Prime').decisive, isFalse);
    });

    test('한국어에 영어 낱말이 섞여도 한국어다', () {
      final v = detectOriginScript('오늘 Netflix 에서 그 영화를 봤는데 정말 재미있었어요');
      expect(v.decisive, isTrue);
      expect(v.language, 'Korean');
    });

    test('충분한 영어 문장은 라틴으로 잡힌다 (GPT 판정으로 넘어간다)', () {
      // 라틴 문자권은 언어가 여럿이라 스크립트만으로는 못 가른다.
      // `resolveOriginFromFirstUtterance`가 GPT에게 물어보는 이유다.
      final v = detectOriginScript(
          'I finished the report this morning so I can help you now');
      expect(v.decisive, isFalse,
          reason: '라틴 문자는 스크립트만으로 언어를 단정하지 않는다');
    });

    test('영어 설정 → 충분한 한국어 발화 → 한국어로 잡힌다', () {
      final v = detectOriginScript('제가 지금 회의 중이라서 조금 이따가 다시 연락드릴게요');
      expect(v.decisive, isTrue);
      expect(v.language, 'Korean');
    });
  });

  // ==========================================================================
  group('② 세션당 한 번만 묻는다', () {
    setUp(() => OriginLanguageSession.instance.begin());

    test('판정 전에는 아직 확정되지 않았다', () {
      expect(OriginLanguageSession.instance.settled, isFalse);
    });

    test('한 번 확정하면 다시 판정하지 않는다', () {
      OriginLanguageSession.instance.adopt('English');
      expect(OriginLanguageSession.instance.settled, isTrue);
    });

    test('로비값과 같으면(null) 확정만 하고 묻지 않는다', () {
      OriginLanguageSession.instance.adopt(null);
      expect(OriginLanguageSession.instance.settled, isTrue);
      expect(OriginLanguageSession.instance.mismatched, isFalse);
      expect(OriginLanguageSession.instance.switched, isFalse);
      // 물을 슬롯이 아예 나오지 않는다.
      expect(OriginLanguageSession.instance.takeNoticeSlot(), isFalse);
    });

    test('판정만으로는 ORIGIN이 바뀌지 않는다 — 물을 거리가 생길 뿐이다', () {
      OriginLanguageSession.instance.adopt('English');
      expect(OriginLanguageSession.instance.mismatched, isTrue,
          reason: '물어볼 근거는 생겨야 한다');
      expect(OriginLanguageSession.instance.switched, isFalse,
          reason: '유저가 고르지도 않았는데 ORIGIN이 바뀌면 안 된다');
      expect(OriginLanguageSession.instance.resolve('Korean'), 'Korean');
    });

    test('Keep Current 뒤에는 같은 세션에서 다시 묻지 않는다', () {
      OriginLanguageSession.instance.adopt('English');
      expect(OriginLanguageSession.instance.takeNoticeSlot(), isTrue,
          reason: '첫 번째는 물어야 한다');
      expect(OriginLanguageSession.instance.takeNoticeSlot(), isFalse,
          reason: 'Keep Current 뒤 재경고가 뜨면 안 된다');
      expect(OriginLanguageSession.instance.takeNoticeSlot(), isFalse);
    });

    test('방을 새로 열면 다시 묻는다', () {
      OriginLanguageSession.instance.adopt('English');
      OriginLanguageSession.instance.takeNoticeSlot();
      OriginLanguageSession.instance.begin(); // 새 방
      expect(OriginLanguageSession.instance.settled, isFalse);
      expect(OriginLanguageSession.instance.mismatched, isFalse);
      expect(OriginLanguageSession.instance.switched, isFalse);
    });

    test('목록에 없는 언어는 판정으로 치지 않는다', () {
      OriginLanguageSession.instance.adopt('Swahili');
      expect(OriginLanguageSession.instance.mismatched, isFalse,
          reason: '문구표가 없는 언어로 물으면 안내가 영어로 떨어진다');
      expect(OriginLanguageSession.instance.switched, isFalse);
    });
  });

  // ==========================================================================
  group('③ 내 판정에 상대 발화가 섞이지 않는다', () {
    test('판정은 내 마이크 전사 경로에서만 불린다', () {
      // 상대 발화는 `_handleIncomingMessage`가 받는다. 그 구역에 판정
      // 호출이 있으면 상대 언어로 내 설정을 바꾸라고 묻게 된다.
      final int start =
          duo.indexOf('Future<void> _handleIncomingMessage(');
      // 바로 다음에 오는 멤버 앞까지가 이 함수의 몸통이다.
      final int end = duo.indexOf('String _pttLabel()', start);
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start),
          reason: '구역 경계를 못 잡았다 — 함수 순서가 바뀌었는지 확인할 것');
      expect(duo.substring(start, end),
          isNot(contains('_settleInterpreterOrigin')),
          reason: '상대 발화로 내 언어를 판정하고 있다');
    });

    test('판정 호출부는 내 전사 업로드 자리 하나뿐이다', () {
      final matches =
          RegExp(r'_settleInterpreterOrigin\(').allMatches(duo).toList();
      // 정의 1 + 호출 1
      expect(matches.length, 2,
          reason: '판정을 부르는 자리가 늘었다 — 출처가 내 마이크인지 확인할 것');
    });

    test('직접 대화에서는 판정하지 않는다', () {
      expect(duo, contains('if (_isDirectMode) return; // 직접 대화는 이번 범위가 아니다'));
    });
  });

  // ==========================================================================
  group('Apply — 영구 반영하고 통화는 잇는다', () {
    test('소켓 언어를 갈아 끼운다', () {
      expect(duo, contains('_interpStt?.switchLanguage('));
    });

    test('ORIGIN은 로비 설정에도 저장한다 (세션 한정이 아니다)', () {
      expect(duo, contains('FFAppState().nativeLang = native'));
    });

    test('🎯 Target은 사용자가 만졌을 때만 저장한다', () {
      // 안 만졌는데 되쓰면 두 가지가 조용히 망가진다.
      //   ① 목록(12개) 밖의 배울 언어가 기본값으로 덮인다
      //   ② 바꾸지도 않은 값이 prefs에 다시 쓰인다
      // 이 창은 ORIGIN을 고치자고 띄운 것이다.
      expect(duo, contains('if (target != null) FFAppState().targetLang = target;'),
          reason: 'Target을 무조건 저장하고 있다');
      expect(duo, contains('Future<void> _applyOriginChange(String native, String? target)'),
          reason: 'target이 nullable이어야 "안 만짐"을 표현할 수 있다');
    });

    test('만지지 않은 Target은 Apply에 넘어가지 않는다', () {
      expect(duo, contains('targetTouched ? target : null'));
      // 드롭다운을 만질 때만 표시가 선다.
      expect(duo, contains('targetTouched = true'));
    });

    test('통화를 끊는 코드가 없다', () {
      final int start = duo.indexOf('Future<void> _applyOriginChange(');
      final int end = duo.indexOf('void _keepCurrentOrigin(');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final region = duo.substring(start, end);
      for (final String forbidden in <String>[
        '_handleAutoSaveAndExit',
        '_stopInterpreter',
        'dispose()',
        'StealthRoomMaster.exitCurrentMode',
      ]) {
        expect(region, isNot(contains(forbidden)),
            reason: 'Apply가 통화를 끊는다: $forbidden');
      }
    });

    test('Keep Current는 아무 설정도 바꾸지 않는다', () {
      final int start = duo.indexOf('void _keepCurrentOrigin(');
      final int end = duo.indexOf('TtsAdapter? _ensureInterpreterTts(');
      expect(end, greaterThan(start));
      final region = duo.substring(start, end);
      expect(region, isNot(contains('FFAppState().nativeLang =')));
      expect(region, isNot(contains('switchLanguage(')));
    });
  });

  // ==========================================================================
  group('🚧 플래그 — 켜짐이 기본이고, 끄면 기존 동작 그대로다', () {
    test('기본값이 true다 — 꺼져 있으면 언어 확인 창이 아무 빌드에도 안 뜬다', () {
      expect(
          duo,
          contains("bool.fromEnvironment('DUO_INTERP_ORIGIN_CHECK', "
              "defaultValue: true)"));
    });

    test('꺼지면 UI만이 아니라 판정 자체가 안 돈다', () {
      // "UI만 숨김"이면 자동 감지·GPT 호출·switchLanguage가 그대로 돌아
      // v147이 두 변경을 함께 검증하게 된다.
      final int start = duo.indexOf('Future<void> _settleInterpreterOrigin(');
      final String head = duo.substring(start, start + 400);
      expect(head, contains('if (!kDuoInterpOriginCheck) return;'));
    });

    test('꺼지면 STT가 로비값으로 고정된다', () {
      expect(
          duo,
          contains('(!kDuoInterpOriginCheck || '
              'OriginLanguageSession.instance.settled)'));
    });

    test('꺼지면 서클톡이 쓰는 싱글턴을 건드리지 않는다', () {
      expect(
          duo,
          contains('if (kDuoInterpOriginCheck) '
              'OriginLanguageSession.instance.begin()'));
    });

    test('플래그를 보는 자리가 넷이다 — 하나라도 빠지면 반쪽만 꺼진다', () {
      final n = RegExp(r'kDuoInterpOriginCheck').allMatches(duo).length;
      // 선언 1 + 판정 가드 1 + STT 개방 1 + begin() 1 + 오버레이 1
      expect(n, greaterThanOrEqualTo(5),
          reason: '플래그를 보는 자리가 줄었다 — 어디가 빠졌는지 확인할 것');
    });
  });

  // ==========================================================================
  group('안내 문구', () {
    test('확인 문구는 감지된 언어로 적힌다', () {
      expect(originLanguageCheckPromptLine('Korean'), contains('한국어'));
      expect(originLanguageCheckPromptLine('English'),
          contains("You're speaking English"));
      expect(originLanguageCheckPromptLine('Japanese'), contains('日本語'));
    });

    test('확인 문구는 통보가 아니다 — 이 시점에는 아무것도 안 바뀌었다', () {
      // 자동 전환 통보 문구(`originLanguageSwitchedNoticeLine`)는 그 동작과
      // 함께 걷어냈다(2026-09-04). ORIGIN은 유저가 창에서 확정할 때만 바뀐다.
      final check = originLanguageCheckPromptLine('Korean');
      expect(check, isNot(contains('진행할게요')),
          reason: '아직 아무것도 안 바꿨는데 바꿨다고 말하면 안 된다');
      expect(check, contains('확인'), reason: '통보가 아니라 확인을 구해야 한다');
    });

    test('모르는 언어는 영어 문구로 떨어진다', () {
      expect(originLanguageCheckPromptLine('Swahili'),
          contains("You're speaking English"));
    });
  });

  // ==========================================================================
  // 실기기에서 이 기능이 무엇을 했는지는 로그 한 줄씩으로만 알 수 있다.
  // 태그를 하나로 모아 두어야 `logcat | grep INTERP-ORIGIN` 한 번에 전 과정이
  // 순서대로 나온다 — 다른 태그로 흩어지면 그 순간을 다시 짜맞춰야 한다.
  group('[INTERP-ORIGIN] 로그 — 한 태그로 전 과정이 보인다', () {
    test('다른 태그를 쓰지 않는다', () {
      expect(duo, isNot(contains('ORIGIN-CHECK')),
          reason: '옛 태그가 남으면 grep 한 번으로 안 모인다');
    });

    test('필요한 상태가 다 남는다', () {
      for (final String state in <String>[
        'stt_open ',
        'skipped reason=insufficient',
        'detected=',
        'mismatch=',
        'overlay_shown',
        'apply origin=',
        'keep_current',
        'suppressed reason=notice_already_used',
        'judge=script',
        'judge=gpt',
      ]) {
        expect(duo, contains(state), reason: '"$state" 줄이 없다');
      }
    });

    test('모든 상태 줄이 [INTERP-ORIGIN] 태그로 나간다', () {
      // 상태 문자열이 다른 태그에 붙어 있으면 위 시험은 통과해도 실기기에서는
      // 안 보인다. 각 상태 앞 가장 가까운 태그를 확인한다.
      for (final String state in <String>[
        'stt_open ',
        'skipped reason=insufficient',
        'overlay_shown',
        'apply origin=',
        'keep_current origin=',
        'suppressed reason=notice_already_used',
      ]) {
        final int at = duo.indexOf(state);
        expect(at, greaterThan(-1), reason: '"$state" 줄이 없다');
        final String before = duo.substring((at - 300).clamp(0, duo.length), at);
        expect(before.lastIndexOf("'[INTERP-ORIGIN]'"),
            greaterThan(before.lastIndexOf('_lgDuo(') - 1),
            reason: '"$state" 이(가) 다른 태그로 나간다');
      }
    });

    test('소켓을 연 상태(auto/pinned)와 선언값이 함께 찍힌다', () {
      final int at = duo.indexOf('stt_open ');
      final String block = duo.substring(at, at + 300);
      expect(block, contains('mode='));
      expect(block, contains('declared='));
      expect(block, contains('flag='));
    });

    test('판정 근거(script/gpt)가 어느 쪽인지 남는다', () {
      // GPT 왕복이면 지연이 생긴다. 어느 쪽이었는지 모르면 그 지연을
      // 프리롤 탓으로 잘못 읽는다.
      final int at = duo.indexOf('judge=gpt');
      expect(at, greaterThan(-1));
      expect(duo.substring(at, at + 200), contains('elapsedMs='));
    });

    test('Apply는 실제로 반영됐는지까지 남긴다', () {
      final int at = duo.indexOf('apply origin=');
      final String block = duo.substring(at, at + 300);
      expect(block, contains('switchLanguage='),
          reason: '소켓 언어가 실제로 갈렸는지가 이 줄의 핵심이다');
      expect(block, contains('persisted='));
      expect(block, contains('target='));
    });

    test('발화 원문을 로그에 싣지 않는다 — 길이만', () {
      // 통화 내용은 진단 로그에 남기지 않는다.
      final int at = duo.indexOf('skipped reason=insufficient');
      final String block = duo.substring(at, at + 200);
      expect(block, contains('textLen='));
      expect(block, isNot(contains(r'$text ')));
      expect(block, isNot(contains('transcript')));
    });

    test('짧은 말은 GPT에 묻기 전에 접는다', () {
      // 로그만 남기고 호출은 그대로면 돈과 지연이 그대로 나간다.
      final int start = duo.indexOf('Future<void> _settleInterpreterOrigin(');
      final int end = duo.indexOf('Future<void> _applyOriginChange(');
      final String body = duo.substring(start, end);
      final int guard = body.indexOf('skipped reason=insufficient');
      final int call = body.indexOf('resolveOriginFromFirstUtterance(');
      expect(guard, greaterThan(-1));
      expect(call, greaterThan(-1));
      expect(guard, lessThan(call), reason: '짧은 말에도 GPT를 부르고 있다');
    });

    test('길이 문턱은 상대 발화 판정과 같은 값을 쓴다', () {
      // 두 곳이 다른 숫자를 쓰면 "왜 여기선 되고 저기선 안 되나"가 된다.
      final int start = duo.indexOf('Future<void> _settleInterpreterOrigin(');
      final int end = duo.indexOf('Future<void> _applyOriginChange(');
      expect(duo.substring(start, end),
          contains('kDuoSrcLangOverrideMinChars'));
    });
  });

  // ==========================================================================
  group('기존 기능 회귀 없음', () {
    test('History·Replay·billing 경로를 건드리지 않았다', () {
      final int start = duo.indexOf('Future<void> _settleInterpreterOrigin(');
      final int end = duo.indexOf('Future<void> _applyOriginChange(');
      expect(end, greaterThan(start));
      final region = duo.substring(start, end);
      for (final String forbidden in <String>[
        '_saveHistoryMessage',
        '_uploadMyMessage',
        'BillingTicker',
        'duoReplayRef',
        'canonical',
      ]) {
        expect(region, isNot(contains(forbidden)),
            reason: '판정이 $forbidden 을 건드린다');
      }
    });

    test('만능 통역 전용이라는 것이 코드에 드러난다', () {
      expect(duo, contains('_settleInterpreterOrigin'));
      // 직접 대화 전사 핸들러에서는 부르지 않는다.
      final int start = duo.indexOf('Future<void> _handleDirectTranscript(');
      final int end = duo.indexOf('Future<void> _stopDirectCall(');
      expect(end, greaterThan(start));
      expect(duo.substring(start, end),
          isNot(contains('_settleInterpreterOrigin')));
    });
  });
}
