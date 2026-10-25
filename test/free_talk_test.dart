import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/free_talk.dart';
import 'package:stealth_vox/custom_code/services/free_talk_history_flip.dart';
import 'package:stealth_vox/custom_code/services/history_finalize.dart';

String _read(String path) => File(path).readAsStringSync();

const _modes = [
  'lib/custom_code/widgets/routine_mode_circle_talk.dart',
  'lib/custom_code/widgets/routine_mode_scenario_talk.dart',
];

void main() {
  group('방 문서 표시', () {
    test('Free Talk 방에만 free_talk가 붙는다', () {
      expect(freeTalkRoomFields(true), {kHistoryFreeTalkField: true});
      expect(freeTalkRoomFields(false), isEmpty);
    });

    test('필드가 없는 옛 방은 평소 방이다', () {
      expect(isFreeTalkRoom(null), isFalse);
      expect(isFreeTalkRoom(<String, dynamic>{}), isFalse);
      expect(isFreeTalkRoom({kHistoryFreeTalkField: true}), isTrue);
    });
  });

  group('언어 짝', () {
    test('평소 방은 로비 Origin으로 말하고 Target이 둘째 줄이다', () {
      expect(
          freeTalkSpokenLobbyLang(
              freeTalk: false, chatLang: 'Korean', targetLang: 'English'),
          'Korean');
      expect(
          freeTalkSecondLobbyLang(
              freeTalk: false, chatLang: 'Korean', targetLang: 'English'),
          'English');
    });

    test('Free Talk 방은 로비 Target으로 말하고 Origin이 뜻 줄이다', () {
      expect(
          freeTalkSpokenLobbyLang(
              freeTalk: true, chatLang: 'Korean', targetLang: 'English'),
          'English');
      expect(
          freeTalkSecondLobbyLang(
              freeTalk: true, chatLang: 'Korean', targetLang: 'English'),
          'Korean');
    });
  });

  group('공부방으로 넘길 때 평소 방으로 바꾼다', () {
    test('바꾸지 않은 Free Talk 방만 대상이다', () {
      expect(freeTalkRoomNeedsFlip(null), isFalse);
      expect(freeTalkRoomNeedsFlip(<String, dynamic>{}), isFalse);
      expect(
          freeTalkRoomNeedsFlip({
            kHistoryFreeTalkField: true,
            kHistoryStateField: kHistoryStateDraft,
          }),
          isTrue);
      // 확정한 원문은 다시 쓰지 않는다.
      expect(
          freeTalkRoomNeedsFlip({
            kHistoryFreeTalkField: true,
            kHistoryStateField: kHistoryStateFinalized,
          }),
          isFalse);
      expect(
          freeTalkRoomNeedsFlip({
            kHistoryFreeTalkField: true,
            kFreeTalkFlippedAtField: 'x',
          }),
          isFalse);
    });

    test('줄이 모두 오면 읽고, 하나라도 빠지면 바꾸지 않는다', () {
      const content =
          '{"lines":[{"id":"a","text":"공항에 가야 해요"},{"id":"b","text":"네"}]}';
      expect(parseFreeTalkFlipLines(content, {'a', 'b'}),
          {'a': '공항에 가야 해요', 'b': '네'});
      expect(parseFreeTalkFlipLines(content, {'a', 'b', 'c'}), isNull);
      expect(parseFreeTalkFlipLines('not json', {'a'}), isNull);
      expect(
          parseFreeTalkFlipLines('{"lines":[{"id":"a","text":" "}]}', {'a'}),
          isNull);
    });

    test('지시문은 말한 언어에서 뜻 언어로 옮긴다', () {
      final s = buildFreeTalkFlipInstructions(
          spokenLang: 'Portuguese', baseLang: 'Korean');
      expect(s, contains('conversation in Portuguese'));
      expect(s, contains('Rewrite every line in Korean'));
    });
  });

  group('배선', () {
    final hist = _read('lib/custom_code/widgets/chat_history_master.dart');

    test('서클톡·시나리오톡은 들어갈 때마다 묻고, 고른 값을 인자로 넘긴다', () {
      final room = _read('lib/custom_code/widgets/stealth_room_master.dart');
      expect('await _askFreeTalk('.allMatches(room).length, 2);
      expect('freeTalk: _freeTalkRoom,'.allMatches(room).length, 2);
      // 창을 닫으면 들어가지 않는다.
      expect('if (freeTalk == null || !mounted) return;'.allMatches(room).length,
          2);
    });

    test('로비·Duo·저장 설정은 Free Talk을 모른다', () {
      for (final path in [
        'lib/custom_code/widgets/lobby_master.dart',
        'lib/custom_code/widgets/routine_mode_duo.dart',
        'lib/app_state.dart',
      ]) {
        final src = _read(path);
        expect(src, isNot(contains('freeTalk')), reason: path);
        expect(src, isNot(contains('free_talk')), reason: path);
      }
    });

    test('두 모드는 방이 열릴 때 한 번 읽어 고정하고 방 문서에 남긴다', () {
      for (final path in _modes) {
        final src = _read(path);
        expect(src, contains('late final bool _freeTalk = widget.freeTalk;'),
            reason: path);
        expect(src, contains('...freeTalkRoomFields(_freeTalk),'),
            reason: path);
        expect(src, contains('OriginLanguageSession.instance.resolve(_lobbySpokenLang())'),
            reason: path);
      }
    });

    test('Free Talk 방에서는 Step 단추를 그리지 않는다', () {
      for (final path in _modes) {
        expect(_read(path), contains('if (!_freeTalk)'), reason: path);
      }
    });

    test('공부방은 Free Talk 방을 따로 다루지 않는다 — 평소 방으로 바꿔 받는다', () {
      expect(hist, isNot(contains('_sessionFreeTalk')));
      expect(hist, contains('freeTalkRoomNeedsFlip(data)'));
      expect(hist,
          contains('FreeTalkHistoryFlip.instance.ensure(widget.historyDoc, _apiKey)'));
    });

    test('목록 요약은 바꾼 뒤 Origin 원문으로 쓴다', () {
      final flip =
          _read('lib/custom_code/services/free_talk_history_flip.dart');
      expect(flip, contains('writeHistoryPreviewSummary('));
      expect(flip, contains('nativeLang: chatLang,'));
      for (final path in _modes) {
        expect(_read(path),
            contains('if (!_freeTalk) unawaited(writeHistoryPreviewSummary('),
            reason: path);
      }
    });

    test('복원이 끝난 뒤에 바꾼다', () {
      final runner =
          _read('lib/custom_code/services/origin_restoration_runner.dart');
      expect(runner,
          contains('.then((_) => FreeTalkHistoryFlip.instance.ensure(roomRef, apiKey))'));
    });
  });
}
