import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 모드 이름은 **두 층**이고, 층마다 규칙이 반대다.
///
/// * 코드·화면 — Circle Talk / Scenario Talk 로 통일한다(2026-08-26).
/// * Firestore 저장 id·room_name — `free_talk` / `roleplay` / `Roleplay Mode`
///   그대로 얼린다. 과거 대화 기록의 분류 키라서, 바꾸면 이미 저장된 방이
///   미분류로 떨어진다.
///
/// 두 규칙이 반대라 한쪽만 기억하면 반드시 다른 쪽을 깬다. 그래서 둘 다
/// 여기에 못 박는다.
void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  group('코드는 표시명으로 통일한다', () {
    test('대화방 파일 이름이 표시명을 따른다', () {
      for (final path in <String>[
        'lib/custom_code/widgets/routine_mode_circle_talk.dart',
        'lib/custom_code/widgets/routine_mode_scenario_talk.dart',
        'lib/custom_code/widgets/trial/trial_circle_talk_timer_mixin.dart',
      ]) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }
      for (final gone in <String>[
        'lib/custom_code/widgets/routine_mode_anyone.dart',
        'lib/custom_code/widgets/routine_mode_roleplay.dart',
        'lib/custom_code/widgets/trial/trial_anyone_timer_mixin.dart',
      ]) {
        expect(File(gone).existsSync(), isFalse, reason: gone);
      }
    });

    test('옛 코드명을 쓰는 식별자가 남아 있지 않다', () {
      final offenders = <String>[];
      for (final file in libFiles) {
        final text = file.readAsStringSync();
        for (final needle in <String>[
          'RoutineModeAnyone',
          'RoutineModeRoleplay',
          'RoleplayBrain',
          'RoleplayScenarioStore',
          'AnyonePreparedAudioCapture',
          'AnyoneMicOwner',
          'AnyoneCostTracker',
          'TrialAnyoneTimerMixin',
          'kAnyoneDeliberateReplyPolicy',
        ]) {
          if (text.contains(needle)) offenders.add('${file.path} → $needle');
        }
      }
      expect(offenders, isEmpty);
    });

    test('유저에게 보이는 이름에 Roleplay가 없다', () {
      final store =
          File('lib/custom_code/widgets/store_master.dart').readAsStringSync();
      expect(store, contains("'🎬 Scenario Talk'"));
      expect(store, isNot(contains("'🎬 Roleplay'")));
    });
  });

  group('저장 id는 얼려 둔다', () {
    final circle = File('lib/custom_code/widgets/routine_mode_circle_talk.dart')
        .readAsStringSync();
    final scenario =
        File('lib/custom_code/widgets/routine_mode_scenario_talk.dart')
            .readAsStringSync();
    final history = File('lib/custom_code/widgets/chat_history_master.dart')
        .readAsStringSync();

    test('Circle Talk은 free_talk으로 저장한다', () {
      expect(circle, contains("'mode': 'free_talk'"));
      expect(circle, contains("billingModeName => 'free_talk'"));
      // 표시명으로 바꿔 쓰면 과거 기록이 미분류로 떨어진다.
      expect(circle, isNot(contains("'mode': 'circle_talk'")));
    });

    test('Scenario Talk은 roleplay / "Roleplay Mode"로 저장한다', () {
      expect(scenario, contains("'mode': 'roleplay'"));
      expect(scenario, contains("'room_name': \"Roleplay Mode\""));
      expect(scenario, contains("billingModeName => 'roleplay'"));
      expect(scenario, isNot(contains("'mode': 'scenario_talk'")));
    });

    test('저장된 방을 읽는 별칭표가 옛 이름을 계속 받는다', () {
      // 이 조건들을 지우면 그 시기에 저장된 기록이 통째로 미분류가 된다.
      expect(
          history, contains("if (room == 'Roleplay Mode') return 'roleplay';"));
      expect(history, contains("room == 'Free Talk Mode'"));
      expect(history, contains("room == 'Anyone'"));
      expect(history, contains("room.startsWith('Circle Talk')"));
    });

    test('히스토리 필터칩 키는 room_name 매칭용이라 옛 이름이다', () {
      final list = File('lib/custom_code/widgets/chat_history_list_master.dart')
          .readAsStringSync();
      expect(list, contains("case 'Anyone':\n        return 'Circle';"));
      expect(list, contains("case 'Roleplay':\n        return 'Scenario';"));
    });

    test('시나리오 커서 저장 키를 바꾸지 않는다', () {
      // 바꾸면 유저가 보던 시나리오 순번이 처음으로 되감긴다.
      expect(scenario, contains("'roleplay_scenario_cursor"));
    });
  });
}
