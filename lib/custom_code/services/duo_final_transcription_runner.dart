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

class DuoFinalTranscriptionRunner {
  DuoFinalTranscriptionRunner._();

  static final DuoFinalTranscriptionRunner instance =
      DuoFinalTranscriptionRunner._();

  /// 재전사를 아예 끈다. 실기기에서 문제가 생기면 여기를 내린다.
  static bool enabled = true;

  /// 발화 하나를 다시 듣는 데 주는 상한.
  static const Duration perUtteranceTimeout = Duration(seconds: 30);

  /// 방마다 도는 판. 같은 방에 두 판이 겹치면 같은 줄을 두 번 고친다.
  final Map<String, Future<void>> _running = <String, Future<void>>{};

  bool isRunning(String roomId) => _running.containsKey(roomId);

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
          wav: pcm,
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
    } catch (e) {
      debugPrint('[DUO-FINAL] run_failed room=$roomId ${e.runtimeType}');
    } finally {
      sw.stop();
      debugPrint('[DUO-FINAL] done room=$roomId caller=$caller '
          '$stats elapsedMs=${sw.elapsedMilliseconds}');
    }
  }

  /// 창고에서 꺼낸 것은 **WAV**다(`OriginPcmStore`가 그렇게 써 둔다).
  /// 전사 서비스는 PCM16을 받으므로 머리말을 벗겨서 넘긴다.
  Future<String?> _transcribe({
    required String apiKey,
    required Uint8List wav,
    required String languageCode,
    required String utteranceId,
  }) async {
    try {
      final Uint8List? pcm = wavToPcm16(wav);
      if (pcm == null || pcm.isEmpty) {
        debugPrint('[DUO-FINAL] wav_unreadable utt=$utteranceId');
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
