import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Step Expand는 제품에서 사라졌다.
///
/// 대화는 Duo · Circle Talk · Scenario Talk 셋에서만 한다. 그 뒤에 오는
/// 학습은 PRACTICE → MY ENGLISH → NATIVE ENGLISH다.
///
/// 이 시험은 **되살아나는 것**을 막는다. 모드 하나를 지우는 일은 대화방·라우터·
/// 서비스·히스토리 분기가 함께 걸려 있어, 한 곳만 남아도 죽은 문이 화면에
/// 다시 뜬다. 그래서 소스에 흔적이 남았는지를 직접 본다.
void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  group('Step Expand 대화 모드가 남아 있지 않다', () {
    test('전용 파일이 없다', () {
      for (final path in <String>[
        'lib/custom_code/widgets/routine_mode_step_expand.dart',
        'lib/custom_code/services/step_expand_p1.dart',
        'lib/custom_code/services/step_expansion_builder.dart',
        'lib/custom_code/services/step_expansion_finalizer.dart',
        'lib/custom_code/services/p2_chunk_mapping.dart',
      ]) {
        expect(File(path).existsSync(), isFalse, reason: path);
      }
    });

    test('어느 파일도 Step Expand 이름을 부르지 않는다', () {
      final offenders = <String>[];
      for (final file in libFiles) {
        final text = file.readAsStringSync();
        for (final needle in <String>[
          'RoutineModeStepExpand',
          'step_expand',
          'StepExpand',
          'Step.Ex',
        ]) {
          if (text.contains(needle)) {
            offenders.add('${file.path} → $needle');
          }
        }
      }
      expect(offenders, isEmpty);
    });

    test('P1 · P2 사다리 개념이 남아 있지 않다', () {
      final offenders = <String>[];
      for (final file in libFiles) {
        final text = file.readAsStringSync();
        for (final needle in <String>[
          'part1Practice',
          'part2Practice',
          'p1_pairs',
          'expansion_status',
          'final_sentence',
        ]) {
          if (text.contains(needle)) {
            offenders.add('${file.path} → $needle');
          }
        }
      }
      expect(offenders, isEmpty);
    });
  });

  group('새 학습 흐름의 이름을 쓴다', () {
    final history = File('lib/custom_code/widgets/chat_history_master.dart')
        .readAsStringSync();

    test('유저에게 보이는 이름은 PRACTICE · Clear & Easy · Natural & Sharp다', () {
      // 2026-09-08 뒤 두 카드가 화자 라벨을 쓴다. 저장 칸(`my_speech` /
      // `native_english`)은 그대로이고 화면 이름만 바뀌었다.
      expect(history, contains('"Clear & Easy"'));
      expect(history, contains('"Natural & Sharp"'));
      expect(history, contains('"Practice"'));
    });

    test('카드 윗줄은 어떤 화자를 기준으로 만든 영어인지 밝힌다', () {
      expect(history, contains('Larry King–style Plain Spoken English'));
      expect(
        history,
        contains('Trevor Noah–style Natural Conversational English'),
      );
    });

    test('옛 Anderson 결과를 Trevor 기준 결과로 다시 만든다', () {
      expect(history, contains('natural_sharp_trevor_v1'));
      expect(history, contains('native_english_schema_version'));
    });

    test('British를 고른 방에서는 인물 이름을 감춘다', () {
      // 영국 영어를 고른 사람에게 미국 인물을 내걸면 카드가 제 내용과
      // 어긋나 보인다. **표시만 접고 프롬프트는 그대로다.**
      expect(history, contains('_hidesPersonaNames'));
      expect(history, contains("== 'British'"));
    });

    test('옛 카드 이름은 화면에서 사라졌다', () {
      for (final gone in <String>[
        'Final Sentence',
        'Polished Sentence',
        'Expanded Sentence',
        'Complete Sentence',
      ]) {
        expect(history, isNot(contains(gone)), reason: gone);
      }
    });

    test('세 경로는 나란하다 — 어느 하나가 다른 하나의 관문이 아니다', () {
      // History Study의 첫 화면이 경로를 고르는 자리다. Practice로 곧장
      // 들어가 버리면 My English가 다시 "Practice 다음 단계"가 된다.
      expect(history, contains('ShadowingPhase.studySelect'));
      expect(history, contains('_buildStudySelectScreen'));
      for (final opener in <String>[
        '_openPracticeStudy',
        '_openMySpeechStudy',
        '_openNativeEnglishStudy',
      ]) {
        expect(history, contains(opener), reason: opener);
      }
      // Practice 완료 여부에 묶인 문이 없어야 한다.
      expect(history, isNot(contains('isComplete ? _open')));
    });

    test('Native English는 My English를 거치지 않고 만들어지지 않는다', () {
      final start = history.indexOf('Future<void> _openNativeEnglishStudy');
      expect(start, greaterThan(-1));
      final block = history.substring(start, start + 600);
      expect(block, contains('_ensureMySpeech'));
      expect(block, contains('_ensureNativeEnglish'));
      // 생성기 자체가 transcript를 받을 수 없는 서명이라 한 번 더 막힌다.
      final builder =
          File('lib/custom_code/services/speech_reconstruction.dart')
              .readAsStringSync();
      final ne = builder
          .substring(builder.indexOf('class NativeEnglishSpeechBuilder'));
      expect(ne, isNot(contains('SpeechTranscriptTurn')));
      expect(ne, isNot(contains('formatSpeechTranscript')));
    });

    // 저장 칸 이름은 화면 이름과 따로 간다. 화면은 MY ENGLISH지만 칸은
    // `my_speech` 그대로다 — 저장 id를 바꾸면 옛 방이 전부 끊긴다.
    test('저장 칸은 my_speech · native_english다', () {
      expect(history, contains("'my_speech'"));
      expect(history, contains("'native_english'"));
      // 옛 칸에 새 결과를 싣지 않는다.
      expect(history, isNot(contains("'polished_sentence'")));
      expect(history, isNot(contains("'expanded_sentence'")));
    });
  });

  group('세 대화 모드는 그대로다', () {
    test('대화방 파일 셋이 살아 있다', () {
      for (final path in <String>[
        'lib/custom_code/widgets/routine_mode_duo.dart',
        'lib/custom_code/widgets/routine_mode_circle_talk.dart',
        'lib/custom_code/widgets/routine_mode_scenario_talk.dart',
      ]) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }
    });

    test('셋 다 MY ENGLISH / NATIVE ENGLISH를 만들 수 있다', () {
      final history = File('lib/custom_code/widgets/chat_history_master.dart')
          .readAsStringSync();
      final start = history.indexOf('_kSpeechPracticeModes');
      expect(start, greaterThan(-1));
      final block = history.substring(start, start + 220);
      for (final mode in <String>['duo', 'circle_talk', 'scenario_talk']) {
        expect(block, contains("'$mode'"), reason: mode);
      }
    });

    test('대화방은 MY ENGLISH를 의식하지 않는다', () {
      // 대화는 대화대로 끝까지 자연스럽게 흘러야 한다. 좋은 문장을 만들려고
      // 유도하거나 재료를 모으려 들면 그건 다시 Step Expand다.
      for (final path in <String>[
        'lib/custom_code/widgets/routine_mode_duo.dart',
        'lib/custom_code/widgets/routine_mode_circle_talk.dart',
        'lib/custom_code/widgets/routine_mode_scenario_talk.dart',
      ]) {
        final text = File(path).readAsStringSync();
        expect(text, isNot(contains('My Speech')), reason: path);
        expect(text, isNot(contains('my_speech')), reason: path);
        expect(text, isNot(contains('MySpeechBuilder')), reason: path);
      }
    });
  });
}
