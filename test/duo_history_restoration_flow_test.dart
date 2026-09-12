import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final duo = read('lib/custom_code/widgets/routine_mode_duo.dart');
  final history = read('lib/custom_code/widgets/chat_history_master.dart');
  final runner =
      read('lib/custom_code/services/origin_restoration_runner.dart');

  group('Duo Direct PCM과 빈 대화', () {
    test('버릴 발화 판정 뒤에 수용된 PCM만 저장한다', () {
      final handler = duo.indexOf('Future<void> _handleDirectTranscript(');
      final noiseGate = duo.indexOf('noiseTranscriptReason(trimmed)', handler);
      final pcmStore = duo.indexOf('_stashDuoPcm(pcmResult)', handler);
      final historySave = duo.indexOf('await _saveHistoryMessage(', handler);
      expect(handler, greaterThanOrEqualTo(0));
      expect(noiseGate, greaterThan(handler));
      expect(pcmStore, greaterThan(noiseGate));
      expect(historySave, greaterThan(pcmStore));
    });

    test('첫 발화 PCM은 방 생성 뒤 pending에서 입양한다', () {
      expect(duo, contains("putKeyed(ref?.id ?? '', result.utteranceId, pcm)"));
      expect(duo, contains('await _pendingDuoPcmWrite;'));
      expect(duo, contains('await OriginPcmStore.instance.adoptPending('));
    });
  });

  group('첫 History 진입 준비 상태', () {
    test('상세 진입을 풀고 preparation을 background에서 시작한다', () {
      final fetch = history.indexOf('Future<void> _fetchRoomData() async');
      final release = history.indexOf('isLoadingRoom = false;', fetch);
      final start =
          history.indexOf('unawaited(_prepareDuoHistory(data));', fetch);
      expect(release, greaterThan(fetch));
      expect(start, greaterThan(release));
    });

    test('canonical과 restoration 상태를 순서대로 전이한다', () {
      final prepare = history.indexOf('Future<void> _prepareDuoHistory(');
      final building = history.indexOf(
          '_HistoryPreparationStage.canonicalBuilding', prepare);
      final sync =
          history.indexOf('await _syncDuoCanonical(initialRoom);', prepare);
      final applied =
          history.indexOf('_HistoryPreparationStage.canonicalApplied', sync);
      final restoring =
          history.indexOf('_HistoryPreparationStage.restoring', applied);
      final ready =
          history.indexOf('_HistoryPreparationStage.ready', restoring);
      expect(building, greaterThan(prepare));
      expect(sync, greaterThan(building));
      expect(applied, greaterThan(sync));
      expect(restoring, greaterThan(applied));
      expect(ready, greaterThan(restoring));
    });

    test('ready 전에는 raw message StreamBuilder를 만들지 않는다', () {
      final build = history.indexOf('Widget build(BuildContext context)');
      final gate = history.indexOf(
          '_duoPreparationStage != _HistoryPreparationStage.ready', build);
      final stream =
          history.indexOf('child: StreamBuilder<QuerySnapshot>', build);
      expect(gate, greaterThan(build));
      expect(stream, greaterThan(gate));
    });

    test('canonical 적용 뒤 stale room을 다시 읽는다', () {
      expect(history,
          contains('final refreshed = await widget.historyDoc.get();'));
      expect(history, contains('if (freshData is Map<String, dynamic>)'));
      expect(history, contains('_cacheRoomData(freshData);'));
    });

    test('Duo Direct만 임시 Target 주어 검사 모드를 켠다', () {
      expect(
          history,
          contains(
              "targetSubjectOnly: (data[kDuoModeField] ?? '').toString() == 'direct'"));
      expect(runner, contains('subjectOnly: targetSubjectOnly'));
    });

    test('canonical은 snapshot을 관찰하고 전체 대기는 terminal timeout이 있다', () {
      expect(history, contains('.snapshots()'));
      expect(history, contains('_HistoryPreparationStage.timedOut'));
      expect(history, contains('_duoPreparationTimeout'));
      expect(runner, contains('task.timeout(timeout)'));
      expect(runner, contains('OriginRestorationWaitResult.timedOut'));
    });

    test('최종 완료도 실행 중인 복원을 먼저 기다린다', () {
      final finalize = history.indexOf('Future<void> _finalizeHistory() async');
      final wait =
          history.indexOf('.awaitIfRunning(widget.historyDoc.id);', finalize);
      final update =
          history.indexOf('await widget.historyDoc.update(', finalize);
      expect(wait, greaterThan(finalize));
      expect(update, greaterThan(wait));
    });
  });
}
