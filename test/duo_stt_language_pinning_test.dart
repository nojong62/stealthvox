// 🌐 [DUO-LANG] Duo 전사 세션에 **실제로 어떤 language 값이 들어가는지**를
// 원문에서 확인한다.
//
// 이 시험은 "옳다"를 주장하지 않는다. 지금 동작을 글로 못 박아, 나중에
// 누가 바꾸면 그 사실이 드러나게 하는 것이 목적이다. 실기기 로그의
// `[DuoSTT-RAW] language=` 값이 여기서 추적한 그 값이다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/deepgram_prewarm_session.dart';

const String _duo = 'lib/custom_code/widgets/routine_mode_duo.dart';
const String _circle = 'lib/custom_code/widgets/routine_mode_circle_talk.dart';
const String _scenario = 'lib/custom_code/widgets/routine_mode_scenario_talk.dart';

void main() {
  // 원문은 CRLF다. 줄바꿈을 걸쳐 비교하는 곳이 있으므로 먼저 맞춰 둔다.
  String read(String path) => File(path)
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  final String duo = read(_duo);
  final String circle = read(_circle);
  final String scenario = read(_scenario);

  // ✅ **이제 Duo 두 모드가 같은 규칙을 쓴다**(2026-09-14).
  //
  //   2026-09-03에는 만능 통역만 첫 발화를 자동 감지로 열었다. 그때는 그것이
  //   "로비값이 틀렸는지 알아내는" 유일한 방법이었는데, 그 대가로 **첫 발화의
  //   글자 자체가 판정에 희생됐다** — 감지가 흔들리면 유저가 한 말이 다른
  //   언어 문장으로 기록되고 상대에게도 그대로 건너갔다.
  //
  //   지금은 기록·전달과 판정을 갈라 두 모드 다 로비값을 박는다. 판정은
  //   같은 소리를 언어 없이 한 번 더 들어서 따로 한다.
  //
  //   아래 두 그룹은 그래서 **같은 것을 지킨다** — 전사에 들어가는 language는
  //   언제나 유저가 확정한 ORIGIN이다.

  group('직접 대화는 로비값을 그대로 박는다 (무변경)', () {
    /// `_startDirectStt` 안만 본다 — 만능 통역 쪽 코드에 걸리면 안 된다.
    String directSttRegion() {
      final start = duo.indexOf('Future<void> _startDirectStt(');
      expect(start, greaterThan(-1));
      final end = duo.indexOf('Future<void> _handleDirectTranscript(', start);
      expect(end, greaterThan(start),
          reason: '구역 경계를 못 잡았다 — 함수 순서가 바뀌었는지 확인할 것');
      return duo.substring(start, end);
    }

    test('연결 시점에 로비값(_myNative)을 그대로 박는다', () {
      // 진단기와 소켓이 **같은 값**을 봐야 A/B 비교가 성립하므로 지역변수를
      // 한 번 거친다. 그 변수의 출처가 로비값이라는 것이 여기서 지킬 사실이다.
      final region = directSttRegion();
      expect(region,
          contains('final String sttLanguageCode = _mapLanguageToCode(_myNative());'));
      // 옛 경로는 소켓을 열 때 한 번 굳혔다. 새 경로는 발화마다 읽지만
      // **돌려주는 값은 언제나 그 지역변수**다 — 직접 대화는 로비값 고정이다.
      expect(region, contains('originLanguageCode: () => sttLanguageCode'));
    });

    test('직접 대화는 자동 감지로 열지 않는다', () {
      // 첫 발화부터 로비 언어가 박힌다. 판정 장치가 이 구역에 없어야 한다.
      expect(directSttRegion(), isNot(contains('OriginLanguageSession')));
    });

    test('직접 대화는 언어를 갈아 끼우지 않는다', () {
      expect(directSttRegion(), isNot(contains('switchLanguage(')));
    });
  });

  // ⚠️ 언어 확인 기능은 플래그 뒤에 있다(`DUO_INTERP_ORIGIN_CHECK`, v150부터
  //   기본 true). 끄면(`=false`) 만능 통역 STT가 v147과 한 글자도 다르지 않아야
  //   한다 — 아래 검사가 그 갈래를 지킨다.
  group('🚧 플래그 OFF — 만능 통역 STT가 기존 동작 그대로다', () {
    test('꺼져 있으면 로비값으로 고정한다 (자동 감지 없음)', () {
      // `!kDuoInterpOriginCheck ||` 가 앞에 있어야 꺼진 빌드에서 항상
      // 로비값 갈래로 간다. 이 조건이 빠지면 v147이 기존 동작이 아니게 된다.
      expect(
          duo,
          contains('(!kDuoInterpOriginCheck || '
              'OriginLanguageSession.instance.settled)'),
          reason: '꺼진 빌드에서 자동 감지로 열릴 수 있다');
    });

    test('기본값이 true다', () {
      // v150부터 켜짐이 기본이다. 지연 개선은 실기기 확인이 끝났고, 꺼져
      // 있는 동안에는 언어 확인 창이 아무 빌드에도 뜨지 않았다.
      expect(
          duo,
          contains("bool.fromEnvironment('DUO_INTERP_ORIGIN_CHECK', "
              "defaultValue: true)"),
          reason: '기본이 꺼져 있으면 언어 확인 창을 아무도 못 본다');
    });

    test('판정 함수가 맨 앞에서 빠져나온다', () {
      // GPT 판정도 세션 상태도 switchLanguage도 여기서 멈춰야 한다.
      final int start = duo.indexOf('Future<void> _settleInterpreterOrigin(');
      expect(start, greaterThan(-1));
      final String head = duo.substring(start, start + 400);
      expect(head, contains('if (!kDuoInterpOriginCheck) return;'));
      // 그 return이 GPT 호출보다 **앞**에 있어야 한다.
      final int guard = head.indexOf('if (!kDuoInterpOriginCheck) return;');
      final int call = head.indexOf('resolveOriginFromFirstUtterance');
      expect(guard, greaterThan(-1));
      if (call > -1) {
        expect(guard, lessThan(call), reason: '가드보다 GPT 호출이 먼저다');
      }
    });

    test('꺼져 있으면 서클톡의 세션 상태를 건드리지 않는다', () {
      // 싱글턴이라 남의 판정을 비우고 다니면 안 된다.
      expect(duo,
          contains('if (kDuoInterpOriginCheck) OriginLanguageSession.instance.begin()'));
    });

    test('꺼져 있으면 확인 창이 그려지지 않는다', () {
      expect(duo,
          contains('if (kDuoInterpOriginCheck && _originMismatchDetected != null)'));
    });
  });

  // 🔄 2026-09-14에 뒤집혔다. 예전에는 첫 발화를 **판정용으로 쓰느라**
  //   자동 감지로 열었고, 그 글자가 그대로 기록과 상대 전달에 쓰였다.
  //   감지가 흔들리면 유저가 한 말이 다른 언어 문장으로 적혔다(실기기: 호스트
  //   첫 문장만 타겟 언어로 기록, 2번째부터 정상).
  //
  //   판정하려고 들어보는 일과 그 결과를 기록으로 삼는 일은 별개다.
  group('🌐 플래그 ON — 기록은 로비 언어, 판정은 따로 한 번 더 듣는다', () {
    // ⚠️ **들여쓰기로 단언하지 않는다.** 2026-09-14에 그렇게 썼다가 소켓
    //   갈래를 통째로 놓쳤다 — 같은 조건문이 들여쓰기만 다르게 두 곳에
    //   있었고, 단언은 한 곳만 짚었다. 실제로 도는 갈래(기본값 socket)가
    //   안 고쳐진 채로 "고쳤다"고 보고했다.
    //
    //   그래서 여기서는 **공백을 지운 뒤 의미로** 본다.
    String squashed(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

    test('두 STT 갈래 **모두** 첫 발화부터 로비 언어를 박는다', () {
      final String flat = squashed(duo);

      // ① Deepgram 갈래 — DuoSttPipeline
      expect(flat,
          contains('originLanguageCode: () => _mapLanguageToCode(_myNative())'),
          reason: 'Deepgram 갈래에 로비 언어가 안 박힌다');

      // ② 소켓 갈래 — OpenAiStreamingTranscribeSession (기본값)
      expect(flat, contains('languageCode: _mapLanguageToCode(_myNative())'),
          reason: '소켓 갈래에 로비 언어가 안 박힌다');

      // ③ 판정 상태로 언어를 가르던 조건이 **어느 갈래에도** 남으면 안 된다.
      //    공백을 지웠으므로 들여쓰기가 어떻든 걸린다.
      expect(
          flat,
          isNot(contains(
              "OriginLanguageSession.instance.settled) ? _mapLanguageToCode(_myNative()) : ''")),
          reason: '첫 발화가 다시 자동 감지로 나가는 갈래가 남아 있다');
    });

    test('소켓 갈래는 되들을 소리가 없다는 사실을 남긴다', () {
      // 이 갈래의 origin-check는 지금 반쪽이다. 그 사실이 로그로 보여야
      // 실기기에서 "판정이 왜 항상 맞다고 나오나"를 물을 수 있다.
      expect(duo, contains('kind=socket mode=pinned probe=none'));
      expect(
          squashed(duo),
          contains('원문 PCM은 남기지 않는다'),
          reason: '소켓 갈래가 PCM을 안 남긴다는 근거 주석이 사라졌다');
    });

    test('판정은 같은 소리를 언어 없이 다시 들어서 한다', () {
      expect(duo, contains('OriginLanguageSession.instance.settled'));
      expect(duo, contains('_interpOriginProbe'),
          reason: '판정용 소리를 들고 있는 자리가 없다');
      expect(duo, contains("probe=auto"),
          reason: '판정용 자동 감지 전사가 없다');
    });

    test('판정용 글자는 어디에도 저장하지 않는다', () {
      final int start = duo.indexOf('Future<void> _settleInterpreterOrigin(');
      final int end = duo.indexOf('Future<void> _applyOriginChange(');
      expect(start, greaterThan(0));
      final String region = duo.substring(start, end);
      // 판정 영역이 기록·전달 경로를 부르면 안 된다.
      for (final gone in <String>[
        '_saveHistoryMessage(',
        '_uploadMyMessage(',
        '_processRelayPipeline(',
      ]) {
        expect(region, isNot(contains(gone)),
            reason: '판정 글자가 $gone 로 새어 나간다');
      }
    });

    test('판정이 끝났다고 소켓을 다시 열지 않는다', () {
      // 이미 로비 언어로 열려 있다. 같은 언어로 끊었다 다시 열면 그 사이에
      // 한 말이 경계를 못 받는다. 언어가 실제로 바뀌는 자리는 Apply뿐이다.
      final int start = duo.indexOf('Future<void> _settleInterpreterOrigin(');
      final int end = duo.indexOf('Future<void> _applyOriginChange(');
      final String region = duo.substring(start, end);
      expect(region, isNot(contains('switchLanguage(')));
      expect(duo, contains('_settleInterpreterOrigin'));
      // Apply 쪽에는 그대로 남아 있어야 한다.
      expect(duo, contains('switchLanguage(_mapLanguageToCode(native))'));
    });

    test('로비값이 틀렸으면 첫 발화를 새 언어로 다시 전사한다', () {
      expect(duo, contains('_retranscribeOriginProbe('),
          reason: '언어를 바꿔도 첫 발화가 틀린 언어로 남는다');
      expect(duo, contains('retranscribe_applied'));
      // 빈 글자로 덮으면 그 줄이 사라진다.
      expect(duo, contains('retranscribe_failed'));
    });

    test('판정용 소리를 계속 들고 있지 않는다', () {
      // 발화 하나가 최대 1.4MB다.
      for (final reason in <String>[
        'no_mismatch',
        'keep_current',
        'room_exit',
      ]) {
        expect(duo, contains("_releaseOriginProbe('$reason')"),
            reason: '$reason 경로에서 소리를 안 놓는다');
      }
    });

    test('방마다 판정을 새로 시작한다', () {
      // 안 비우면 직전 서클톡 세션의 판정이 남아 첫 발화를 그냥 지나친다.
      expect(duo, contains('OriginLanguageSession.instance.begin()'));
    });

    test('서클톡·시나리오톡의 기존 정책은 그대로다', () {
      expect(circle, contains('OriginLanguageSession.instance.settled'));
      expect(circle, contains('switchLanguage('));
      expect(scenario, contains('switchLanguage('));
    });
  });

  group('언어 이름 → 코드 표가 모드마다 다르다', () {
    // 게스트 오버레이가 고를 수 있는 12개 언어. Duo의 표가 이 12개를
    // 전부 덮어야 조용히 'en'으로 떨어지는 언어가 없다.
    const List<String> guestLangs = <String>[
      'English', 'Japanese', 'Chinese', 'Spanish', 'French', 'German',
      'Korean', 'Hindi', 'Russian', 'Portuguese', 'Italian', 'Dutch',
    ];

    test('Duo 표는 게스트가 고를 수 있는 12개 언어를 모두 덮는다', () {
      for (final String lang in guestLangs) {
        if (lang == 'English') continue; // default 갈래로 맞는다
        expect(duo.contains("case '${lang.toLowerCase()}':"), isTrue,
            reason: '$lang 이 Duo 언어 표에 없다 → 조용히 en으로 전사된다');
      }
    });

    test('⚠️ Duo 표에는 서클톡이 아는 언어 넷이 빠져 있다', () {
      // 서클톡(deepgramLanguageCode)은 알지만 Duo는 모르는 언어.
      // Duo에서 이 언어를 쓰면 default 갈래로 떨어져 'en'이 박힌다.
      for (final String lang in <String>[
        'vietnamese',
        'thai',
        'indonesian',
        'arabic',
      ]) {
        expect(deepgramLanguageCode(lang), isNot('en'),
            reason: '서클톡은 $lang 을 안다');
        expect(duo.contains("case '$lang':"), isFalse,
            reason: 'Duo가 $lang 을 알게 됐다면 이 시험을 갱신할 것');
      }
    });

    test('두 표 모두 모르는 언어는 en으로 떨어진다', () {
      expect(deepgramLanguageCode('Swahili'), 'en');
      expect(duo, contains("default:\n        return 'en';"));
    });
  });

  group('게스트 기본 언어', () {
    test('⚠️ 폰 언어를 모르면 ORIGIN 기본값이 English다', () {
      // 한국어를 말하는 게스트가 언어 오버레이를 그냥 넘기면 language=en으로
      // 한국어를 전사하게 되는 경로가 여기서 열린다.
      expect(duo, contains("_kGuestDefaultNativeLang = 'English'"));
    });

    test('게스트는 통화 시작 전에 언어를 확정한다', () {
      // Enter를 눌러 언어를 박은 뒤에야 _joinAsGuest → 통화 → STT 연결이다.
      final int enter = duo.indexOf("_lgDuo('[GUEST-LANG]',\n                          'entered");
      final int join = duo.indexOf('_joinAsGuest(roomId);');
      expect(enter, greaterThan(-1));
      expect(join, greaterThan(enter),
          reason: '언어 확정이 방 입장보다 먼저여야 STT가 옳은 언어로 열린다');
    });
  });
}
