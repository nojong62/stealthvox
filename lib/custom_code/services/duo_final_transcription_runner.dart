// ====================================================================
// 🎧 [DUO-FINAL] 재전사 한 판을 실제로 돌리는 자리
// --------------------------------------------------------------------
// 판정은 전부 `duo_final_transcription.dart`에 있다. 이 파일이 하는 일은 셋뿐이다.
//
//   · 창고에서 그 발화의 소리를 꺼내 전사기에 올린다
//   · 바뀐 줄만 Firestore에 되쓴다
//   · 한 방에 두 판이 겹치지 않게 지킨다
//
// **통화가 끝나는 자리에서 시작하고 기다리지 않는다.** 화면은 이미 나가 있고,
// 이 일은 몇 초에서 몇십 초가 걸린다. 싱글턴이라 위젯이 사라져도 계속 돈다
// (`OriginRestorationRunner`와 같은 모양이다).
//
// ⚠️ **번역문을 만들지 않는다.** 이 판이 바꾸는 것은 원문 한 칸뿐이다.
// ⚠️ **문맥을 보지 않는다.** 같은 소리를 다시 들을 뿐이다.
// ====================================================================

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'duo_final_transcription.dart';
import 'duo_study_state.dart';
import 'history_finalize.dart';
import 'openai_transcribe_service.dart';
import 'origin_pcm_store.dart';
import 'origin_restoration.dart'
    show kMessagePcmKeyField, restorationLanguageCode;
import 'pcm_audio_utils.dart';

/// 공부방이 기다린 결과.
enum DuoFinalWaitResult { notRunning, completed, timedOut }

class DuoFinalTranscriptionRunner {
  DuoFinalTranscriptionRunner._();

  static final DuoFinalTranscriptionRunner instance =
      DuoFinalTranscriptionRunner._();

  /// 재전사를 아예 끈다. 실기기에서 문제가 생기면 여기를 내린다.
  static bool enabled = true;

  /// 발화 하나를 다시 듣는 데 주는 상한.
  static const Duration perUtteranceTimeout = Duration(seconds: 30);

  /// 공부방이 한 판을 기다리는 상한. 기존 원문 복원이 쓰던 값과 같다 —
  /// 그 대기 자리를 이 판이 물려받는다.
  static const Duration waitTimeout = Duration(minutes: 3);

  /// 방마다 도는 판. 같은 방에 두 판이 겹치면 같은 줄을 두 번 고친다.
  final Map<String, Future<void>> _running = <String, Future<void>>{};

  bool isRunning(String roomId) => _running.containsKey(roomId);

  /// 🕰️ 도는 판이 있으면 끝날 때까지 기다린다.
  ///
  /// **공부방이 화면을 띄우기 전에 부른다.** 통화가 끝나는 자리에서 시작한
  /// 판이 아직 돌고 있으면 그 결과를 보고 그려야, 사용자가 실시간 전사를
  /// 봤다가 몇 초 뒤에 글자가 바뀌는 일이 없다.
  ///
  /// 도는 판이 없으면 곧바로 돌아온다.
  Future<DuoFinalWaitResult> awaitIfRunning(
    String roomId, {
    Duration timeout = waitTimeout,
  }) async {
    final Future<void>? task = _running[roomId];
    if (task == null) return DuoFinalWaitResult.notRunning;
    try {
      await task.timeout(timeout);
      return DuoFinalWaitResult.completed;
    } on TimeoutException {
      debugPrint('[DUO-FINAL] wait_timeout room=$roomId');
      return DuoFinalWaitResult.timedOut;
    } catch (_) {
      // 판이 예외로 끝났어도 기다림은 끝난 것이다. 결과는 방 문서가 말한다.
      return DuoFinalWaitResult.completed;
    }
  }

  /// 통화가 끝나는 자리에서 부른다. **기다리지 않는다.**
  void start({
    required DocumentReference<Object?> historyRef,
    required String apiKey,
    String caller = 'unknown',
  }) {
    final String id = historyRef.id;
    if (!enabled || apiKey.isEmpty) {
      debugPrint('[DUO-FINAL] start_bail room=$id caller=$caller '
          'reason=${!enabled ? 'disabled' : 'no_api_key'}');
      return;
    }
    if (_running.containsKey(id)) {
      debugPrint('[DUO-FINAL] start_reuse room=$id caller=$caller');
      return;
    }
    final Future<void> task =
        _run(historyRef: historyRef, apiKey: apiKey, caller: caller);
    _running[id] = task;
    // ⚠️ 정리는 값을 돌려주면 안 된다. `Map.remove`가 지운 값을 돌려주는데
    //   그것이 지금 등록한 task라, 한 줄로 줄이면 자기 자신을 기다리게 된다
    //   (`OriginRestorationRunner`가 같은 자리에서 겪은 일이다).
    unawaited(task.whenComplete(() {
      _running.remove(id);
    }));
  }

  Future<void> _run({
    required DocumentReference<Object?> historyRef,
    required String apiKey,
    required String caller,
  }) async {
    final String roomId = historyRef.id;
    final sw = Stopwatch()..start();
    var stats = const DuoFinalStats();
    try {
      // 🔁 이미 끝까지 돈 방은 열지 않는다. 그 판이 소리를 지우고 나갔으므로
      //   두 번째 판은 `retranscribed=0`만 찍고, 그 0이 방 표시를 덮어써서
      //   **한 번 얻은 복원 우회를 스스로 풀어 버린다**(2026-09-15 실기기).
      final Object? roomData = (await historyRef.get()).data();
      if (roomData is Map<String, dynamic> &&
          duoFinalRoomAlreadyDone(roomData)) {
        debugPrint('[DUO-FINAL] run_skip room=$roomId caller=$caller '
            'reason=already_done '
            'success=${roomData[kDuoFinalRoomSuccessField]}');
        return;
      }

      final snap = await historyRef.collection('messages').get();
      stats = stats.copyWith(rows: snap.docs.length);

      for (final doc in snap.docs) {
        final data = doc.data();
        final row = DuoFinalRow(
          docId: doc.id,
          pcmKey: (data[kMessagePcmKeyField] ?? '').toString(),
          originalText: (data['original_text'] ?? '').toString(),
          originalRaw: (data[kOriginalRawField] ?? '').toString(),
          sourceLang: (data['source_lang'] ?? '').toString(),
          alreadyFinal: data[kDuoFinalTranscribedAtField] != null,
          userEdited: data[kMessageUserEditedAtField] != null ||
              (data[kStudyStateField] ?? '').toString().trim() ==
                  kStudyStateDeletedByUser,
        );
        final plan = planDuoFinalRow(row,
            languageCodeOf: restorationLanguageCode);
        if (!plan.shouldRetranscribe) {
          stats = plan.skipReason == DuoFinalSkip.noPcm
              ? stats.copyWith(skippedNoPcm: stats.skippedNoPcm + 1)
              : stats.copyWith(skippedOther: stats.skippedOther + 1);
          continue;
        }

        final Uint8List? pcm =
            await OriginPcmStore.instance.readKeyed(roomId, plan.pcmKey);
        if (pcm == null || pcm.isEmpty) {
          // 소리가 없다. OS가 임시 폴더를 비웠거나 상한에 걸려 못 담았다.
          // **실시간 원문이 그대로 남는다.**
          stats = stats.copyWith(skippedNoPcm: stats.skippedNoPcm + 1);
          debugPrint('[DUO-FINAL] no_audio room=$roomId utt=${plan.pcmKey}');
          continue;
        }

        final String? finalText = await _transcribe(
          apiKey: apiKey,
          pcm: pcm,
          languageCode: plan.languageCode,
          utteranceId: plan.pcmKey,
        );
        if (finalText == null) {
          stats = stats.copyWith(failed: stats.failed + 1);
          continue;
        }

        final update = buildDuoFinalUpdate(
          liveText: row.originalText,
          existingRaw: row.originalRaw,
          finalText: finalText,
          finalizedAt: FieldValue.serverTimestamp(),
        );
        if (update.isEmpty) {
          stats = stats.copyWith(failed: stats.failed + 1);
          continue;
        }
        await doc.reference.update(Map<String, dynamic>.from(update));
        stats = stats.copyWith(retranscribed: stats.retranscribed + 1);
        if (update.containsKey(kDuoFinalChangedField)) {
          stats = stats.copyWith(changed: stats.changed + 1);
        }
        // 🔎 [계측] **글자는 싣지 않는다.** 길이만으로 "얼마나 달라졌나"를
        //   읽을 수 있고, 로그가 대화록이 되면 안 된다.
        debugPrint('[DUO-FINAL] row room=$roomId utt=${plan.pcmKey} '
            'lang=${plan.languageCode.isEmpty ? 'auto' : plan.languageCode} '
            'audioMs=${pcm16DurationMs(pcm.length, sampleRate: kStealthVoxSttSampleRate)} '
            'liveLen=${row.originalText.trim().length} '
            'finalLen=${finalText.trim().length} '
            'changed=${update.containsKey(kDuoFinalChangedField)}');
      }
      // 🏁 한 판이 **끝까지** 돌았다. 여기까지 와야 방에 표시한다 — 중간에
      //   예외로 빠진 판은 이 줄을 지나지 않는다.
      await historyRef.set(<String, dynamic>{
        kDuoFinalRoomCompletedField: FieldValue.serverTimestamp(),
        kDuoFinalRoomSuccessField: stats.retranscribed,
        kDuoFinalRoomFailField: stats.failed,
      }, SetOptions(merge: true));

      // 🧹 [PCM] **이제 이 방의 소리를 지운다.**
      //
      //   예전 주인은 원문 복원이었다(`OriginRestorationRunner`가 세 곳에서
      //   `discard`를 불렀다). 새 경로가 복원을 건너뛰게 되면서 지우는 코드가
      //   통째로 사라질 뻔했다 — 창고의 유일한 청소부가 그쪽이었다.
      //
      //   ⚠️ **History 저장이 끝난 뒤에만 지운다.** 위 `update`가 다 끝나고
      //   방 표시까지 찍힌 지금이 그 시점이다. 중간에 예외가 나면 이 줄에
      //   닿지 않으므로 소리가 남고, 다음에 다시 시도할 수 있다.
      //
      //   실패한 줄이 있어도 지운다 — 그 줄은 실시간 원문으로 확정됐고,
      //   같은 소리를 또 들어 봐야 같은 결과다.
      await OriginPcmStore.instance.discard(roomId);
      debugPrint('[DUO-FINAL] pcm_discarded room=$roomId');
    } catch (e) {
      // ⚠️ 여기서 소리를 지우지 않는다. 끝까지 못 간 판이라 다음 기회가 있다.
      debugPrint('[DUO-FINAL] run_failed room=$roomId ${e.runtimeType} '
          '— PCM은 남긴다');
    } finally {
      sw.stop();
      // 🔎 [계측] `skippedNoPcm`이 곧 **이 폰에 소리가 없는 줄**이다.
      //   직접 대화에서는 상대 발화가 전부 여기 들어간다 — 내 마이크 소리만
      //   내 창고에 있기 때문이다. 그래서 한 통화에서 호스트 폰은 호스트
      //   발화만, 게스트 폰은 게스트 발화만 좋아진다. **버그가 아니다.**
      //   실기기에서 이 수와 상대 발화 수가 맞는지로 확인한다.
      debugPrint('[DUO-FINAL] done room=$roomId caller=$caller '
          '$stats localPcmRows=${stats.retranscribed + stats.failed} '
          'remoteOrMissingRows=${stats.skippedNoPcm} '
          'elapsedMs=${sw.elapsedMilliseconds}');
    }
  }

  /// 창고는 파일에 **WAV로 쓰지만 꺼낼 때는 PCM16으로 준다** —
  /// 머리말을 벗기는 일은 `readKeyed`가 이미 끝냈다.
  ///
  /// ⚠️ 여기서 `wavToPcm16`을 또 부르면 **한 판이 통째로 실패한다.**
  ///   RIFF가 없는 바이트라 null이 나오고, 모든 줄이 실시간 원문에 머문다
  ///   (2026-09-15 실기기: `wav_unreadable` ×2, `retranscribed=0`).
  ///   먼저 선 `OriginRestorationRunner`도 꺼낸 것을 그대로 올린다.
  Future<String?> _transcribe({
    required String apiKey,
    required Uint8List pcm,
    required String languageCode,
    required String utteranceId,
  }) async {
    try {
      if (pcm.isEmpty) {
        debugPrint('[DUO-FINAL] empty_audio utt=$utteranceId');
        return null;
      }
      return await OpenAiTranscribeService.transcribePcm16(
        apiKey: apiKey,
        pcm: pcm,
        sampleRate: kStealthVoxSttSampleRate,
        language: languageCode.isEmpty ? null : languageCode,
        model: OpenAiTranscribeService.duoFinalModel,
        timeout: perUtteranceTimeout,
        // ✂️ **앞을 다시 깎지 않는다.** 앞 여유 1000ms를 일부러 확보해 둔 것이라
        //   여기서 잘라내면 그 작업이 통째로 헛것이 된다.
        trimLeadingSilence: false,
      );
    } catch (e) {
      debugPrint('[DUO-FINAL] transcribe_error utt=$utteranceId ${e.runtimeType}');
      return null;
    }
  }
}
