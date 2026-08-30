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

  group('Duo 직접 대화의 전사 언어는 로비값으로 박힌다', () {
    test('연결 시점에 _mapLanguageToCode(_myNative())를 박는다', () {
      expect(duo, contains('languageCode: _mapLanguageToCode(_myNative())'));
    });

    test('⚠️ Duo는 자동 감지로 열지 않는다 — 첫 발화부터 언어가 박힌다', () {
      // 서클톡/시나리오톡은 판정 전까지 빈 문자열(=자동 감지)로 연다.
      expect(circle, contains("OriginLanguageSession.instance.settled"));
      // Duo에는 그 장치가 없다.
      expect(duo, isNot(contains('OriginLanguageSession')));
    });

    test('⚠️ Duo는 switchLanguage를 한 번도 부르지 않는다', () {
      // 서클톡·시나리오톡은 첫 발화 판정 뒤 소켓 언어를 갈아 끼운다.
      expect(circle, contains('switchLanguage('));
      expect(scenario, contains('switchLanguage('));
      // Duo는 통화 내내 처음 박은 언어 그대로다. 로비 ORIGIN이 실제 발화
      // 언어와 어긋나면 통화가 끝날 때까지 어긋난 채로 전사된다.
      expect(duo, isNot(contains('switchLanguage(')));
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
