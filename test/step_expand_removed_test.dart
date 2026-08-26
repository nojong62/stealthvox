import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Step Expand는 제품에서 사라졌다.
///
/// 대화는 Duo · Circle Talk · Scenario Talk 셋에서만 한다. 그 뒤에 오는
/// 학습은 PRACTICE → MY SPEECH → NATIVE ENGLISH다.
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

    test('유저에게 보이는 이름은 PRACTICE · MY SPEECH · NATIVE ENGLISH다', () {
      expect(history, contains('"MY SPEECH"'));
      expect(history, contains('"NATIVE ENGLISH"'));
      expect(history, contains('"Practice"'));
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
      // 들어가 버리면 My Speech가 다시 "Practice 다음 단계"가 된다.
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

    test('Native English는 My Speech를 거치지 않고 만들어지지 않는다', () {
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

    test('셋 다 MY SPEECH / NATIVE ENGLISH를 만들 수 있다', () {
      final history = File('lib/custom_code/widgets/chat_history_master.dart')
          .readAsStringSync();
      final start = history.indexOf('_kSpeechPracticeModes');
      expect(start, greaterThan(-1));
      final block = history.substring(start, start + 220);
      for (final mode in <String>['duo', 'free_talk', 'roleplay']) {
        expect(block, contains("'$mode'"), reason: mode);
      }
    });

    test('대화방은 MY SPEECH를 의식하지 않는다', () {
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
