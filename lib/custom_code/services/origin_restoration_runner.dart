// ====================================================================
// 🔍 [ORIGIN-RESTORE] 복원 한 판을 실제로 돌리는 자리
// --------------------------------------------------------------------
// 판정은 전부 `origin_restoration.dart`에 있다. 이 파일이 하는 일은 셋뿐이다.
//
//   · 모델과 창고에 실제로 말을 건다
//   · Firestore에서 대화를 읽고 고쳐진 줄만 되쓴다
//   · 한 방에 두 판이 겹치지 않게 지킨다
//
// **대화가 끝나는 자리에서 시작하고**(`_handleAutoSaveAndExit`), 공부방이
// 열릴 때 그 결과를 기다린다([awaitIfRunning]). 사용자를 세워 두지 않으면서
// 검수 화면에는 복원된 글이 뜬다.
//
// ⚠️ **사용자가 확정하기 전에 끝나야 한다.** 확정본 방은 원문을 한 글자도
//    고치지 않는다는 것이 기존 결정이고, 그 결정을 뒤집지 않으려면 복원은
//    사람의 검수보다 앞에 서야 한다.
// ====================================================================

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'duo_study_state.dart';
import 'history_finalize.dart';
import 'history_text_model.dart';
import 'openai_transcribe_service.dart';
import 'origin_pcm_store.dart';
import 'pcm_audio_utils.dart';
import 'origin_restoration.dart';

enum OriginRestorationWaitResult {
  notRunning,
  completed,
  failed,
  timedOut,
}

class OriginRestorationRunner {
  OriginRestorationRunner._();

  static final OriginRestorationRunner instance = OriginRestorationRunner._();

  /// 복원을 아예 끈다. 실기기에서 문제가 생기면 여기를 내린다.
  static bool enabled = true;

  static const Duration _timeout = Duration(seconds: 30);
  static const Duration waitTimeout = Duration(minutes: 3);

  /// 방마다 도는 판. 같은 방에 두 판이 겹치면 같은 줄을 두 번 고친다.
  final Map<String, Future<void>> _running = <String, Future<void>>{};

  /// 🔎 [계측 전용] 판마다 붙는 일련번호와, 지금 등록된 판이 몇 번인지.
  ///   동작에 쓰이지 않는다 — 로그에서 판을 가리기 위한 이름표다.
  int _runSeq = 0;
  final Map<String, int> _registeredRunId = <String, int>{};

  String _fid(Future<void>? f) =>
      f == null ? 'null' : identityHashCode(f).toString();

  /// 대화가 끝나는 자리에서 부른다. **기다리지 않는다.**
  void start({
    required DocumentReference<Object?> roomRef,
    required String apiKey,
    required String sourceName,
    required String targetLanguage,
    bool targetSubjectOnly = false,
    String caller = 'unknown',
  }) {
    final id = roomRef.id;
    debugPrint('[ORIGIN-RUNNER] start_enter room=$id caller=$caller '
        'enabled=$enabled apiKey=${apiKey.isEmpty ? 'empty' : 'present'} '
        'existing=${_running.containsKey(id)} '
        'existingFuture=${_fid(_running[id])} '
        'existingRunId=${_registeredRunId[id]} '
        'runner=${identityHashCode(this)}');
    if (!enabled || apiKey.isEmpty) {
      debugPrint('[ORIGIN-RUNNER] start_bail room=$id caller=$caller '
          'reason=${!enabled ? 'disabled' : 'no_api_key'}');
      return;
    }
    if (_running.containsKey(id)) {
      debugPrint('[ORIGIN-RUNNER] start_reuse room=$id caller=$caller '
          'runId=${_registeredRunId[id]} future=${_fid(_running[id])}');
      return;
    }
    final int runId = ++_runSeq;
    final Future<void> raw = _run(
      roomRef: roomRef,
      apiKey: apiKey,
      sourceName: sourceName,
      targetLanguage: targetLanguage,
      targetSubjectOnly: targetSubjectOnly,
      runId: runId,
    );
    late final Future<void> task;

    // ⚠️ **이 정리는 값을 돌려주면 안 된다. 한 줄로 줄이지 말 것.**
    //
    //   `whenComplete`는 콜백이 Future를 돌려주면 **그것이 끝날 때까지 자기
    //   완료를 미룬다.** 그런데 `Map.remove`는 지운 값을 돌려주고, 여기서
    //   지우는 값이 바로 지금 만들고 있는 `task`다. 그래서
    //
    //       .whenComplete(() => _running.remove(id))
    //
    //   라고 쓰면 task가 **자기 자신을 기다리며** 영원히 끝나지 않는다.
    //   `_run`은 멀쩡히 끝나고 맵에서도 지워지는데 기다리는 쪽만 안 풀려서,
    //   통화를 끝내고 공부방을 처음 열면 3분을 멈춰 있다가 "오래 걸리고
    //   있습니다"로 떨어졌다(실기기 2026-09-10, 호스트·게스트 양쪽 재현).
    //
    //   반환형이 `void`인 **이름 붙인 함수**로 두는 것이 그 방어다. 화살표
    //   본문으로 되돌리는 순간 같은 결함이 그대로 살아난다.
    void cleanup() {
      debugPrint('[ORIGIN-RUNNER] finally_enter room=$id runId=$runId '
          'thisFuture=${_fid(task)} rawFuture=${identityHashCode(raw)} '
          'mapFuture=${_fid(_running[id])} '
          'same=${identical(_running[id], task)} '
          'mapRunId=${_registeredRunId[id]}');
      // 🧹 **내 판이 아직 등록돼 있을 때만 지운다.** 같은 방에 새 판이 올라온
      //   뒤 늦게 도착한 정리가 그 판을 지워 버리면, 기다리던 쪽은 시작된 적
      //   없는 판을 기다리게 된다.
      if (identical(_running[id], task)) {
        _running.remove(id);
        _registeredRunId.remove(id);
      }
      debugPrint('[ORIGIN-RUNNER] finally_exit room=$id runId=$runId '
          'mapAfter=${_fid(_running[id])}');
    }

    task = raw.whenComplete(cleanup);
    debugPrint('[ORIGIN-RUNNER] start_new room=$id caller=$caller runId=$runId '
        'rawFuture=${identityHashCode(raw)} wrappedFuture=${_fid(task)}');
    _running[id] = task;
    _registeredRunId[id] = runId;
    debugPrint('[ORIGIN-RUNNER] registered room=$id runId=$runId '
        'future=${_fid(task)} mapFuture=${_fid(_running[id])} '
        'same=${identical(_running[id], task)}');
    unawaited(task);
  }

  /// 공부방이 열릴 때 부른다. 돌고 있으면 끝날 때까지, 아니면 즉시.
  Future<OriginRestorationWaitResult> awaitIfRunning(
    String roomId, {
    Duration? timeout,
  }) async {
    debugPrint('[ORIGIN-RUNNER-WAIT] enter room=$roomId '
        'existing=${_running.containsKey(roomId)} '
        'mapFuture=${_fid(_running[roomId])} '
        'runId=${_registeredRunId[roomId]} '
        'timeoutSec=${timeout?.inSeconds ?? -1} '
        'runner=${identityHashCode(this)}');
    final task = _running[roomId];
    if (task == null) {
      debugPrint('[ORIGIN-RUNNER-WAIT] not_running room=$roomId');
      return OriginRestorationWaitResult.notRunning;
    }
    debugPrint('[ORIGIN-RUNNER-WAIT] captured room=$roomId '
        'capturedFuture=${_fid(task)} mapFuture=${_fid(_running[roomId])} '
        'same=${identical(_running[roomId], task)} '
        'runId=${_registeredRunId[roomId]}');
    // 🔎 [계측] timeout 포장을 거치지 않고 **원본 Future에 직접** 귀를 댄다.
    //   이 줄이 찍히는데 아래 completed가 안 찍히면 문제는 대기 포장에 있고,
    //   이 줄조차 안 찍히면 Future 자체가 끝나지 않는 것이다.
    unawaited(task.then(
      (_) => debugPrint('[ORIGIN-RUNNER-WAIT] probe_then room=$roomId '
          'capturedFuture=${_fid(task)}'),
      onError: (Object error) =>
          debugPrint('[ORIGIN-RUNNER-WAIT] probe_error room=$roomId '
              'capturedFuture=${_fid(task)} reason=${error.runtimeType}'),
    ));
    try {
      if (timeout == null) {
        await task;
      } else {
        await task.timeout(timeout);
      }
      debugPrint('[ORIGIN-RUNNER-WAIT] completed room=$roomId '
          'capturedFuture=${_fid(task)}');
      return OriginRestorationWaitResult.completed;
    } on TimeoutException {
      debugPrint('[ORIGIN-RUNNER-WAIT] timeout room=$roomId '
          'capturedFuture=${_fid(task)} '
          'currentMapFuture=${_fid(_running[roomId])} '
          'stillRegistered=${_running.containsKey(roomId)} '
          'currentRunId=${_registeredRunId[roomId]}');
      debugPrint('[ORIGIN-RESTORE] wait_timeout room=$roomId '
          'seconds=${timeout?.inSeconds ?? -1}');
      return OriginRestorationWaitResult.timedOut;
    } catch (error) {
      debugPrint('[ORIGIN-RUNNER-WAIT] failed room=$roomId '
          'capturedFuture=${_fid(task)} reason=${error.runtimeType}');
      return OriginRestorationWaitResult.failed;
    }
  }

  bool isRunning(String roomId) => _running.containsKey(roomId);

  Future<void> _run({
    required DocumentReference<Object?> roomRef,
    required String apiKey,
    required String sourceName,
    required String targetLanguage,
    required bool targetSubjectOnly,
    int runId = -1,
  }) async {
    final roomId = roomRef.id;
    final started = DateTime.now();
    Map<String, dynamic>? roomData;
    debugPrint('[ORIGIN-RUNNER] run_enter room=$roomId runId=$runId');
    try {
      // **정상으로 마친 방만** 건너뛴다. 두 번째 판은 첫 판이 고친 글을
      // 원문으로 알고 또 고치기 시작하므로 완료된 방은 다시 돌면 안 되지만,
      // 네트워크가 한 번 끊겼다고 그 방을 영영 포기할 이유는 없다.
      final room = await roomRef.get();
      final raw = room.data();
      roomData = raw is Map<String, dynamic> ? raw : null;
      if (!shouldRunRestoration(roomData)) {
        debugPrint('[ORIGIN-RUNNER] run_completed room=$roomId runId=$runId '
            'reason=already_done');
        return;
      }

      // 🚪 마지막 발화의 쓰기가 아직 큐에 있을 수 있다. 여기서 딱 한 번
      //   기다린다 — 대화 중에는 절대 기다리지 않는다.
      await OriginPcmStore.instance.flush(roomId);

      final snap =
          await roomRef.collection('messages').orderBy('created_at').get();
      final turns = <RestorationTurn>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final text = (data['original_text'] ?? '').toString().trim();
        if (text.isEmpty) continue;
        // 🎧 소리를 가리키는 열쇠. Duo는 발화 id를, 나머지 모드는 순번을
        //   적는다. **비어 있으면 내 소리가 아니다** — Duo의 상대 발화가
        //   그렇고, 그래서 누구 줄인지 따로 판정하지 않아도 된다.
        final rawKey = data[kMessagePcmKeyField];
        final legacySeq = data['pcm_seq'];
        turns.add(RestorationTurn(
          id: doc.id,
          isUser: (data['role'] ?? '') == 'HOST',
          text: text,
          pcmKey: rawKey is String && rawKey.trim().isNotEmpty
              ? rawKey.trim()
              : (legacySeq is int && legacySeq > 0
                  ? 'turn_${legacySeq.toString().padLeft(3, '0')}'
                  : ''),
          subjectHint: (data[kMessageSubjectHintField] ?? '').toString(),
        ));
      }
      if (turns.isEmpty) {
        // 고칠 글이 없는 것은 실패가 아니다.
        await _markCompleted(roomRef);
        await OriginPcmStore.instance.discard(roomId);
        debugPrint('[ORIGIN-RUNNER] run_completed room=$roomId runId=$runId '
            'reason=no_turns');
        return;
      }

      final ids = turns.map((t) => t.id).toSet();
      final engine = OriginRestorationEngine(
        roomId: roomId,
        detectSuspects: (list) => _detect(
          apiKey: apiKey,
          turns: list,
          sourceName: sourceName,
          instructions: buildOriginSuspectInstructions(
            sourceName: sourceName,
            excludeProperNouns: targetSubjectOnly,
          ),
          knownTurnIds: ids,
          requireTargetEvidence: false,
        ),
        validateTarget: (list) => _detect(
          apiKey: apiKey,
          turns: list,
          sourceName: sourceName,
          instructions: buildTargetValidationInstructions(
            sourceName: sourceName,
            targetLanguage: targetLanguage,
            subjectOnly: targetSubjectOnly,
          ),
          knownTurnIds: ids,
          requireTargetEvidence: true,
        ),
        recheckAcoustic: (pcmKey) => _recheck(
          apiKey: apiKey,
          roomId: roomId,
          pcmKey: pcmKey,
        ),
        log: debugPrint,
      );

      final outcome = await engine.run(turns);

      // ── STEP 9 — Final Canonical Origin ─────────────────────────
      if (outcome.corrections.isNotEmpty) {
        await _persist(roomRef, snap.docs, outcome.corrections);
      }
      await _markCompleted(roomRef);

      // 🗑️ 원문이 확정됐으면 소리의 역할은 끝났다. Final Target은 순수
      //   텍스트 작업이라, 그 성공 여부와 삭제를 묶지 않는다.
      var discarded = true;
      try {
        await OriginPcmStore.instance.discard(roomId);
      } catch (_) {
        discarded = false;
      }
      debugPrint('[ORIGIN-RESTORE] final_changes=${outcome.corrections.length} '
          'elapsed_ms=${DateTime.now().difference(started).inMilliseconds} '
          'pcm_discarded=$discarded room=$roomId');
      debugPrint('[ORIGIN-RUNNER] run_completed room=$roomId runId=$runId '
          'reason=normal');
    } catch (error) {
      // 복원이 실패해도 대화는 그대로다. **완료로 찍지 않는다** — 한 번의
      // timeout이 그 방의 복원을 영영 닫아 버리면, 고칠 수 있었던 낱말이
      // 되살아날 기회가 사라진다.
      final last = isLastRestorationAttempt(roomData);
      debugPrint('[ORIGIN-RESTORE] failed room=$roomId '
          'reason=${error.runtimeType} last_attempt=$last '
          'elapsed_ms=${DateTime.now().difference(started).inMilliseconds}');
      try {
        await _markFailed(roomRef);
      } catch (_) {}
      // 🎧 **소리는 남긴다.** 다음 기회에 다시 들으려면 있어야 한다. 더 시도할
      //   일이 없을 때만 버린다(그때도 24시간 청소가 뒤를 받는다).
      if (last) {
        try {
          await OriginPcmStore.instance.discard(roomId);
        } catch (_) {}
      }
      debugPrint('[ORIGIN-RUNNER] run_failed room=$roomId runId=$runId '
          'reason=${error.runtimeType}');
    }
    debugPrint('[ORIGIN-RUNNER] run_exit room=$roomId runId=$runId');
  }

  /// 정상으로 마쳤다. **여기서만 완료 표시가 찍힌다.**
  Future<void> _markCompleted(DocumentReference<Object?> roomRef) =>
      roomRef.update(<String, dynamic>{
        kOriginRestoreStateField: kOriginRestoreCompleted,
        kOriginRestoredAtField: FieldValue.serverTimestamp(),
      });

  /// 실패했다. 시도 횟수를 올려 두고 다음 기회를 남긴다.
  Future<void> _markFailed(DocumentReference<Object?> roomRef) =>
      roomRef.update(<String, dynamic>{
        kOriginRestoreStateField: kOriginRestoreFailed,
        kOriginRestoreAttemptsField: FieldValue.increment(1),
      });

  /// 고쳐진 줄만 되쓴다.
  ///
  /// **`original_text_raw`는 히스토리 교정 경로가 이미 쓰던 칸이다.** 새 칸을
  /// 만들지 않는다 — 되돌릴 근거가 두 곳에 흩어지면 어느 것이 원본인지 알 수
  /// 없어진다.
  Future<void> _persist(
    DocumentReference<Object?> roomRef,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Map<String, String> corrections,
  ) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in docs) {
      final next = corrections[doc.id];
      if (next == null) continue;
      final data = doc.data();
      final raw = (data['original_text'] ?? '').toString();
      batch.update(doc.reference, <String, dynamic>{
        'original_text': next,
        // 이미 raw가 있으면 덮지 않는다. 가장 처음 들린 글이 원본이다.
        if ((data[kOriginalRawField] ?? '').toString().trim().isEmpty)
          kOriginalRawField: raw,
        'original_repaired_at': FieldValue.serverTimestamp(),
        // 이 줄로 만든 번역은 낡았다. 비워 두면 공부방이 다시 만든다.
        'translated_text': '',
      });
    }
    await batch.commit();
  }

  // ══════════════════════════════════════════════════════════════════
  // 모델
  // ══════════════════════════════════════════════════════════════════

  Future<List<OriginSuspect>> _detect({
    required String apiKey,
    required List<RestorationTurn> turns,
    required String sourceName,
    required String instructions,
    required Set<String> knownTurnIds,
    required bool requireTargetEvidence,
  }) async {
    final response = await http
        .post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: <String, String>{
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(<String, dynamic>{
            'model': kHistoryRepairModel,
            // 판정이라 흔들리면 안 된다. 같은 대화는 같은 의심점을 낸다.
            'temperature': 0.0,
            'max_tokens': 700,
            'response_format': <String, String>{'type': 'json_object'},
            'messages': <Map<String, String>>[
              <String, String>{'role': 'system', 'content': instructions},
              <String, String>{
                'role': 'user',
                'content': 'TRANSCRIPT ($sourceName):\n'
                    '${formatRestorationTranscript(turns)}',
              },
            ],
          }),
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      debugPrint('[ORIGIN-RESTORE] detect_status=${response.statusCode}');
      return const <OriginSuspect>[];
    }
    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final choices = body['choices'] as List? ?? const <dynamic>[];
    if (choices.isEmpty) return const <OriginSuspect>[];
    final message = (choices.first as Map<String, dynamic>)['message']
        as Map<String, dynamic>?;
    return parseOriginSuspects(
      (message?['content'] ?? '').toString(),
      knownTurnIds: knownTurnIds,
      requireTargetEvidence: requireTargetEvidence,
    );
  }

  /// 그 발화의 소리만 다시 듣는다. **전체 대화를 다시 전사하지 않는다.**
  Future<String?> _recheck({
    required String apiKey,
    required String roomId,
    required String pcmKey,
  }) async {
    final pcm = await OriginPcmStore.instance.readKeyed(roomId, pcmKey);
    if (pcm == null || pcm.isEmpty) return null;
    return OpenAiTranscribeService.transcribePcm16(
      apiKey: apiKey,
      pcm: pcm,
      sampleRate: kStealthVoxSttSampleRate,
      model: OpenAiTranscribeService.model,
      timeout: _timeout,
    );
  }
}
