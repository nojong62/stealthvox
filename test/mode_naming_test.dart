import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 모드 이름은 이제 **한 층**이다. 코드·화면·저장 id가 모두 같다.
///
/// * Circle Talk   → `circle_talk`   / room_name "Circle Talk · …"
/// * Scenario Talk → `scenario_talk` / room_name "Scenario Talk Mode"
///
/// 2026-08-26에 코드와 화면을 표시명으로 통일하면서 저장 id만 얼려 두었다.
/// 과거 기록의 분류 키였기 때문이다. 그런데 층이 갈려 있는 동안 읽는 사람마다
/// 다른 이름을 기억해야 했고 실제로 오독이 났다.
///
/// 2026-09-07에 테스트 기간이라 보존할 기록이 없다는 판단으로 저장 id까지
/// 맞췄다(실장님 결정). **그 전에 저장된 방은 미분류로 떨어진다** — 옛 별칭을
/// 남기지 않았다는 뜻이고, 그것이 이 파일이 지키는 규칙이다.
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
      // 화면에 실제로 뜨는 자리는 히스토리의 방 이름 표시다. store_master에
      // 있던 매퍼는 아무도 부르지 않는 죽은 코드라 2026-08-27에 지웠다.
      final history = File('lib/custom_code/widgets/chat_history_master.dart')
          .readAsStringSync();
      expect(history, contains("display = 'Scenario Talk'"));
      expect(history, contains("display = 'Circle Talk'"));
      for (final file in libFiles) {
        expect(file.readAsStringSync(), isNot(contains("'🎬 Roleplay'")),
            reason: file.path);
      }
    });
  });

  group('저장 id도 표시명을 따른다', () {
    final circle = File('lib/custom_code/widgets/routine_mode_circle_talk.dart')
        .readAsStringSync();
    final scenario =
        File('lib/custom_code/widgets/routine_mode_scenario_talk.dart')
            .readAsStringSync();
    final history = File('lib/custom_code/widgets/chat_history_master.dart')
        .readAsStringSync();

    test('Circle Talk은 circle_talk으로 저장한다', () {
      expect(circle, contains("'mode': 'circle_talk'"));
      expect(circle, contains("billingModeName => 'circle_talk'"));
      expect(circle, isNot(contains("'free_talk'")));
    });

    test('Scenario Talk은 scenario_talk / "Scenario Talk Mode"로 저장한다', () {
      expect(scenario, contains("'mode': 'scenario_talk'"));
      expect(scenario,
          contains("'room_name': \"Scenario Talk Mode\""));
      expect(scenario, contains("billingModeName => 'scenario_talk'"));
      expect(scenario, isNot(contains("'roleplay'")));
    });

    test('별칭표가 새 이름을 읽는다', () {
      expect(history,
          contains("if (room == 'Scenario Talk Mode') return 'scenario_talk';"));
      expect(history, contains("room.startsWith('Circle Talk')"));
    });

    test('옛 별칭은 남기지 않았다 — 그 시기 방은 미분류로 떨어진다', () {
      // 되살리고 싶어지면 그건 결정을 뒤집는 것이다. 여기서 막는다.
      expect(history, isNot(contains("return 'free_talk'")));
      expect(history, isNot(contains("return 'roleplay'")));
      expect(history, isNot(contains("room == 'Anyone'")));
    });

    test('필터칩 키가 곧 화면에 뜨는 이름이다', () {
      // 예전에는 키를 옛 이름으로 두고 표시명만 바꿔 주는 함수가 있었다.
      // 이름이 한 층이 되면서 그 층이 사라졌다.
      final list = File('lib/custom_code/widgets/chat_history_list_master.dart')
          .readAsStringSync();
      expect(list, contains("'Circle', 'Circle', Icons.forum"));
      expect(list, contains("'Scenario', 'Scenario', Icons.smart_toy"));
      expect(list, isNot(contains('_filterLabel')));
    });

    test('시나리오 커서 키도 새 이름을 쓴다', () {
      // 바뀌면 보던 시나리오 순번이 처음으로 되감긴다. 테스트 기간이라
      // 받아들인 대가다.
      expect(scenario, contains("'scenario_talk_cursor_'"));
      expect(scenario, isNot(contains("'roleplay_scenario_cursor")));
    });
  });
}
