// 🤖 [DUO-ROBOT] 로봇이 실제 상대와 같은 모양으로 앉는가.
//
// 이 층에서 지켜야 할 것은 둘이다.
//
//   1. **payload가 실제 Peer 메시지와 같아야 한다.** 그래야 `_incomingQueue`
//      아래가 로봇인지 사람인지 모른 채 기존 경로를 그대로 태운다.
//   2. **자리는 내 반대편이어야 한다.** 내가 HOST면 로봇은 GUEST다. 같은
//      자리로 앉으면 내 기록에 내가 두 번 나온다.
//
// 답변 생성은 네트워크를 타므로 여기서 시험하지 않는다. 그쪽이 실패해도
// 통화는 이어져야 한다는 규칙은 위젯이 지고 있다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_robot.dart';

void main() {
  group('payload — 실제 Peer와 같은 모양', () {
    test('필요한 칸을 모두 채운다', () {
      final p = DuoRobot.payload(
        text: 'Sounds good.',
        srcLang: 'English',
        duoMode: 'duo_interpreter',
        myRole: 'HOST',
        seq: 3,
      );
      // `_handleIncomingMessage`가 실제로 읽는 칸들이다.
      expect(p['text'], 'Sounds good.');
      expect(p['srcLang'], 'English');
      expect(p['duoMode'], 'duo_interpreter');
      expect(p['seq'], 3);
      expect(p['senderUid'], kDuoRobotSenderUid);
      expect(p['spokenAt'], isA<int>());
      expect(p['__channelMsgId'], 'robot_3');
    });

    test('자리는 언제나 내 반대편이다', () {
      expect(
        DuoRobot.payload(
          text: 'x',
          srcLang: 'Korean',
          duoMode: 'd',
          myRole: 'HOST',
          seq: 1,
        )['senderRole'],
        'GUEST',
      );
      expect(
        DuoRobot.payload(
          text: 'x',
          srcLang: 'Korean',
          duoMode: 'd',
          myRole: 'GUEST',
          seq: 1,
        )['senderRole'],
        'HOST',
      );
    });

    test('발신자 id가 실제 uid와 겹치지 않는다', () {
      // Firebase uid는 28자 영숫자다. 이 값은 그 모양이 아니어서, 나중에
      // 기록을 보면 로봇 시험이었음을 알 수 있다.
      expect(kDuoRobotSenderUid, contains('robot'));
      expect(kDuoRobotSenderUid, contains('debug'));
    });

    test('발화마다 다른 채널 id를 준다', () {
      final a = DuoRobot.payload(
          text: 'a', srcLang: 'Korean', duoMode: 'd', myRole: 'HOST', seq: 1);
      final b = DuoRobot.payload(
          text: 'b', srcLang: 'Korean', duoMode: 'd', myRole: 'HOST', seq: 2);
      expect(a['__channelMsgId'], isNot(b['__channelMsgId']));
    });
  });

  group('대화 기억', () {
    test('릴리스에서도 혼자 연습을 제공한다', () {
      expect(kDuoRobotAvailable, isTrue);
    });

    test('번호는 1부터 이어진다', () {
      final robot = DuoRobot(apiKey: 'k');
      expect(robot.nextSeq(), 1);
      expect(robot.nextSeq(), 2);
      expect(robot.nextSeq(), 3);
    });

    test('reset이 번호와 기억을 함께 비운다', () {
      final robot = DuoRobot(apiKey: 'k');
      robot.nextSeq();
      robot.nextSeq();
      robot.reset();
      expect(robot.nextSeq(), 1);
      expect(robot.turnCount, 0);
    });

    test('열쇠가 없으면 답하지 않는다', () async {
      // 네트워크를 타기 전에 막힌다.
      final robot = DuoRobot(apiKey: '');
      expect(
        await robot.reply(userText: '안녕', language: 'Korean', isDirect: true),
        isNull,
      );
      expect(robot.turnCount, 0, reason: '부르지도 못한 말은 기억에 남지 않는다');
    });

    test('빈 말에는 답하지 않는다', () async {
      final robot = DuoRobot(apiKey: 'k');
      expect(
        await robot.reply(userText: '   ', language: 'Korean', isDirect: true),
        isNull,
      );
      expect(robot.turnCount, 0);
    });
  });

  group('만능 통역 연결', () {
    final duo = File('lib/custom_code/widgets/routine_mode_duo.dart')
        .readAsStringSync();

    test('로봇도 통역 상대가 되어 통역 캡처를 시작한다', () {
      expect(duo, contains('_hasConversationPartner =>'));
      expect(duo, contains('_isPartnerOnline || _robotActive'));
      expect(duo, contains('_maybeAutoStartInterpreter'));
      expect(duo, contains('robot_on'));
    });

    test('통역 로봇 언어쌍과 로컬 전사 경로를 고정한다', () {
      expect(duo, contains('nativeLang ='));
      expect(duo, contains('targetLang ='));
      expect(duo, contains('_partnerChatLang ='));
      expect(duo, contains('_syncHistoryRoomLanguages()'));
      expect(duo, contains('_interpTransport = kDuoInterpTransportFirestore'));
    });
  });

  group('무음 진단 계측', () {
    final duo = File('lib/custom_code/widgets/routine_mode_duo.dart')
        .readAsStringSync();
    final tts =
        File('lib/custom_code/services/tts_adapter.dart').readAsStringSync();
    final android = File(
            'android/app/src/main/kotlin/com/example/my_project/MainActivity.kt')
        .readAsStringSync();

    test('호출·guard·완료 결과를 구분한다', () {
      expect(duo, contains('ENTER active='));
      expect(duo, contains('GUARD_SKIP active='));
      expect(duo, contains('DONE ok='));
      expect(duo, contains('jitterAlive='));
    });

    test('HTTP·PCM·player·Android route를 기록한다', () {
      expect(tts, contains('TTS_HTTP_STATUS'));
      expect(tts, contains('TTS_FIRST_CHUNK'));
      expect(tts, contains('chunkBytes='));
      expect(tts, contains('playback_start speaker='));
      expect(android, contains('"diagnostics" ->'));
      expect(android, contains('"audioFocusResult"'));
      expect(android, contains('"communicationDevice"'));
    });
  });
}
