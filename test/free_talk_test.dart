import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/free_talk.dart';

String _read(String path) => File(path).readAsStringSync();

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

  group('배선', () {
    final hist = _read('lib/custom_code/widgets/chat_history_master.dart');

    test('새 방 네 곳이 모두 표시를 남긴다', () {
      for (final path in [
        'lib/custom_code/widgets/lobby_master.dart',
        'lib/custom_code/widgets/routine_mode_circle_talk.dart',
        'lib/custom_code/widgets/routine_mode_scenario_talk.dart',
        'lib/custom_code/widgets/routine_mode_duo.dart',
      ]) {
        expect(_read(path),
            contains('...freeTalkRoomFields(FFAppState().freeTalk),'),
            reason: path);
      }
    });

    test('서클톡·시나리오톡은 Free Talk에서 Step 단추를 그리지 않는다', () {
      for (final path in [
        'lib/custom_code/widgets/routine_mode_circle_talk.dart',
        'lib/custom_code/widgets/routine_mode_scenario_talk.dart',
      ]) {
        expect(_read(path), contains('if (!FFAppState().freeTalk)'),
            reason: path);
      }
    });

    test('History는 방 문서에서 Free Talk 여부를 읽는다', () {
      expect(hist, contains('_sessionFreeTalk = isFreeTalkRoom(data);'));
    });

    test('공부방 연습 재료는 Free Talk 방에서 원문이다', () {
      expect(hist, contains('_sessionFreeTalk ? original : translated;'));
      expect(hist,
          contains("? (d['original_text'] ?? d['translated_text'] ?? '')"));
    });
  });
}
