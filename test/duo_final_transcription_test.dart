// 🎧 [DUO-FINAL] 통화가 끝난 뒤 보존해 둔 소리로 원문을 다시 확정한다.
//
// 통화 중 전사는 빨라야 한다 — 그 글자가 곧바로 번역돼 상대에게 간다.
// History에 남는 글자는 그럴 이유가 없다. 같은 소리를 한 번 더, 급하지 않게
// 들어서 확정한다.
//
// 이 판이 지키는 경계 넷:
//   ① `original_text_raw` = 실시간 전사, `original_text` = 재전사 결과
//   ② `translated_text`는 건드리지 않는다
//   ③ 발화의 정체(순서·화자·utteranceId)는 안 바뀐다
//   ④ PCM이 없거나 재전사가 실패하면 실시간 원문이 그대로 남는다

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_final_transcription.dart';

String _read(String p) =>
    File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// 주석을 뺀 **코드만**. 이 파일들은 "무엇을 안 하는지"를 주석에 적어 두므로,
/// 그대로 찾으면 설명 문장이 걸려 단언이 거짓 양성이 된다.
String _codeOnly(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

DuoFinalRow row({
  String docId = 'd1',
  String pcmKey = 'item_1',
  String originalText = '아까 뒷지표를 예매했어',
  String originalRaw = '',
  String sourceLang = 'Korean',
  bool alreadyFinal = false,
  bool userEdited = false,
}) =>
    DuoFinalRow(
      docId: docId,
      pcmKey: pcmKey,
      originalText: originalText,
      originalRaw: originalRaw,
      sourceLang: sourceLang,
      alreadyFinal: alreadyFinal,
      userEdited: userEdited,
    );

/// 실제 표와 같은 모양의 가짜. 모르는 이름은 빈 값이다.
String langOf(String name) => name == 'Korean' ? 'ko' : '';

DuoFinalPlan plan(DuoFinalRow r) =>
    planDuoFinalRow(r, languageCodeOf: langOf);

void main() {
  group('어느 줄을 다시 들을 것인가', () {
    test('소리가 있는 내 발화는 다시 듣는다', () {
      final p = plan(row());
      expect(p.shouldRetranscribe, isTrue);
      expect(p.pcmKey, 'item_1');
      expect(p.languageCode, 'ko',
          reason: '언어를 안 박으면 짧은 발화에서 흔들린다');
    });

    test('상대 발화는 건너뛴다 — 그 소리는 내 폰에 없다', () {
      final p = plan(row(pcmKey: ''));
      expect(p.shouldRetranscribe, isFalse);
      expect(p.skipReason, DuoFinalSkip.noPcm);
    });

    test('이미 끝난 줄은 두 번 안 한다', () {
      final p = plan(row(alreadyFinal: true));
      expect(p.skipReason, DuoFinalSkip.alreadyFinal);
    });

    test('사람이 손댄 줄은 기계가 덮지 않는다', () {
      final p = plan(row(userEdited: true));
      expect(p.skipReason, DuoFinalSkip.userEdited);
    });

    test('본문이 통째로 빈 줄은 대상이 아니다', () {
      final p = plan(row(originalText: '', originalRaw: ''));
      expect(p.skipReason, DuoFinalSkip.emptyText);
    });

    test('표에 없는 언어면 안 박는다 — 틀린 언어를 박느니 안 박는다', () {
      final p = plan(row(sourceLang: 'Klingon'));
      expect(p.shouldRetranscribe, isTrue);
      expect(p.languageCode, '');
    });
  });

  group('① 실시간과 최종을 둘 다 남긴다', () {
    test('재전사가 원문을 갈아 끼우고 실시간은 raw로 간다', () {
      final u = buildDuoFinalUpdate(
        liveText: '아까 뒷지표를 예매했어',
        existingRaw: '',
        finalText: '아까 기차표를 예매했어',
        finalizedAt: 'T',
      );
      expect(u['original_text'], '아까 기차표를 예매했어');
      expect(u['original_text_raw'], '아까 뒷지표를 예매했어');
      expect(u[kDuoFinalTranscribedAtField], 'T');
      expect(u[kDuoFinalChangedField], isTrue,
          reason: '이 수가 곧 "실시간이 틀렸던 줄"의 수다');
    });

    test('이미 raw가 있으면 덮지 않는다 — 가장 처음 것이 원문이다', () {
      final u = buildDuoFinalUpdate(
        liveText: '두 번째 판의 글자',
        existingRaw: '맨 처음 들린 글자',
        finalText: '최종',
        finalizedAt: 'T',
      );
      expect(u.containsKey('original_text_raw'), isFalse);
    });

    test('글자가 그대로면 changed를 안 찍는다', () {
      final u = buildDuoFinalUpdate(
        liveText: '같은 말',
        existingRaw: '',
        finalText: '같은 말',
        finalizedAt: 'T',
      );
      expect(u['original_text'], '같은 말');
      expect(u.containsKey(kDuoFinalChangedField), isFalse);
      // 그래도 끝났다는 표시는 남는다 — 두 번 돌지 않게.
      expect(u[kDuoFinalTranscribedAtField], 'T');
    });
  });

  group('④ 실패하면 실시간 원문이 남는다', () {
    test('재전사가 null이면 아무것도 쓰지 않는다', () {
      final u = buildDuoFinalUpdate(
          liveText: '살아남아야 한다',
          existingRaw: '',
          finalText: null,
          finalizedAt: 'T');
      expect(u, isEmpty, reason: '빈 글로 덮으면 그 줄이 사라진다');
    });

    test('빈 글을 돌려줘도 마찬가지다', () {
      final u = buildDuoFinalUpdate(
          liveText: '살아남아야 한다',
          existingRaw: '',
          finalText: '   ',
          finalizedAt: 'T');
      expect(u, isEmpty);
    });
  });

  group('②③ 범위를 넘지 않는다', () {
    final String svc =
        _codeOnly(_read('lib/custom_code/services/duo_final_transcription.dart'));
    final String runner = _codeOnly(
        _read('lib/custom_code/services/duo_final_transcription_runner.dart'));
    // 앞 여유·싱글턴 단언은 코드 줄을 보므로 같은 문자열로 충분하다.

    test('번역문을 건드리지 않는다', () {
      for (final src in <String>[svc, runner]) {
        expect(src.contains('translated_text'), isFalse,
            reason: '번역을 다시 만들면 상대가 들은 것과 내 기록이 갈린다');
      }
    });

    test('발화의 정체를 바꾸지 않는다', () {
      for (final gone in <String>[
        'speaker_role',
        'speaker_seq',
        'spoken_at_ms',
        'channel_msg_id',
      ]) {
        expect(runner.contains(gone), isFalse,
            reason: '$gone 를 건드린다 — 순서·화자가 바뀐다');
      }
    });

    test('문맥 교정·원문 복원을 섞지 않는다', () {
      for (final gone in <String>[
        'correctDuoOriginTexts',
        'OriginRestorationRunner',
        'buildDuoCanonical',
      ]) {
        expect(runner.contains(gone), isFalse,
            reason: '$gone 를 부른다 — 어느 층이 고쳤는지 못 가리게 된다');
      }
    });

    test('앞 여유를 다시 깎지 않는다', () {
      expect(runner, contains('trimLeadingSilence: false'),
          reason: '1000ms 앞 여유를 확보해 놓고 여기서 자르면 헛것이 된다');
    });

    test('기다리지 않는 싱글턴이다', () {
      expect(runner, contains('static final DuoFinalTranscriptionRunner instance'));
      expect(runner, contains('void start('),
          reason: 'Future를 돌려주면 호출부가 나가는 길에 기다리게 된다');
    });
  });

  group('🔌 통화 종료에 걸려 있다', () {
    final String duo =
        _read('lib/custom_code/widgets/routine_mode_duo.dart');

    test('통역 종료에서 시작한다', () {
      expect(duo, contains('DuoFinalTranscriptionRunner.instance.start('));
      expect(duo, contains("caller: 'room_exit'"));
    });

    test('직접 대화에는 안 건다 — canonical이 먼저다', () {
      expect(duo, contains('if (!_isDirectMode && _myHistoryRef != null'),
          reason: '직접 대화에 걸면 canonical이 곧 덮을 글을 고치게 된다');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 직접통화 1차 범위에서 확정한 넷
  // ══════════════════════════════════════════════════════════════════

  group('🚫 성공 1줄 이상이면 원문 복원을 건너뛴다', () {
    test('끝났고 성공이 있으면 건너뛴다', () {
      expect(
          duoFinalSupersedesRestoration(<String, dynamic>{
            kDuoFinalRoomCompletedField: 'T',
            kDuoFinalRoomSuccessField: 1,
          }),
          isTrue);
    });

    test('성공 0줄이면 건너뛰지 않는다 — 있던 방어선을 잃으면 안 된다', () {
      expect(
          duoFinalSupersedesRestoration(<String, dynamic>{
            kDuoFinalRoomCompletedField: 'T',
            kDuoFinalRoomSuccessField: 0,
            kDuoFinalRoomFailField: 3,
          }),
          isFalse);
    });

    test('끝까지 안 돈 판은 건너뛰지 않는다', () {
      expect(
          duoFinalSupersedesRestoration(<String, dynamic>{
            kDuoFinalRoomSuccessField: 5,
          }),
          isFalse,
          reason: '완료 표시 없이 성공 수만 있으면 중간에 끊긴 판이다');
    });

    test('부분 실패는 건너뛰는 쪽이다', () {
      expect(
          duoFinalSupersedesRestoration(<String, dynamic>{
            kDuoFinalRoomCompletedField: 'T',
            kDuoFinalRoomSuccessField: 4,
            kDuoFinalRoomFailField: 2,
          }),
          isTrue,
          reason: '몇 줄 때문에 복원 전체를 다시 도는 것이 걷어내려던 구조다');
    });

    test('옛 방(표시 없음)은 예전대로 복원이 돈다', () {
      expect(duoFinalSupersedesRestoration(<String, dynamic>{}), isFalse);
      expect(duoFinalSupersedesRestoration(null), isFalse);
    });
  });

  group('🧹 PCM 청소 주인이 재전사로 넘어왔다', () {
    final String runner = _codeOnly(
        _read('lib/custom_code/services/duo_final_transcription_runner.dart'));

    test('한 판이 끝까지 돈 뒤에만 지운다', () {
      final int completed = runner.indexOf('kDuoFinalRoomCompletedField');
      final int discard = runner.indexOf('OriginPcmStore.instance.discard');
      expect(completed, greaterThan(0));
      expect(discard, greaterThan(completed),
          reason: 'History 저장·방 표시보다 먼저 지우면 되돌릴 근거가 사라진다');
    });

    test('예외로 끝난 판은 지우지 않는다', () {
      final int discard = runner.indexOf('OriginPcmStore.instance.discard');
      final int catchAt = runner.indexOf('} catch (e) {', discard);
      expect(catchAt, greaterThan(discard),
          reason: 'discard가 catch 안에 있으면 실패한 판도 소리를 버린다');
    });
  });

  group('⏳ 공부방이 기다릴 수 있다', () {
    final String runner = _codeOnly(
        _read('lib/custom_code/services/duo_final_transcription_runner.dart'));
    final String study =
        _codeOnly(_read('lib/custom_code/widgets/chat_history_master.dart'));

    test('대기 API가 있고 상한이 복원과 같다', () {
      expect(runner, contains('Future<DuoFinalWaitResult> awaitIfRunning('));
      expect(runner, contains('static const Duration waitTimeout = Duration(minutes: 3)'));
    });

    test('공부방이 canonical 직후에 걸고 기다린다', () {
      // ⚠️ `awaitIfRunning(`만으로 찾으면 안 된다 — 이 파일에는 원문 복원
      //   쪽 대기 호출이 여러 개 있다. 이 판의 대기는 로그 한 줄로 가린다.
      final int start = study.indexOf('DuoFinalTranscriptionRunner.instance.start(');
      final int wait = study.indexOf('[DUO-FINAL] study_wait');
      final int restore = study.indexOf("_recoverOriginRestoration(caller: 'sync_canonical')");
      expect(start, greaterThan(0));
      expect(wait, greaterThan(start));
      expect(restore, greaterThan(wait),
          reason: '복원보다 먼저 끝나야 복원을 건너뛸지 판단할 수 있다');
    });
  });

  group('🔁 끝난 방을 두 번 돌지 않는다', () {
    // 🩺 2026-09-15 실기기. 공부방에 **두 번째로** 들어가자 이렇게 됐다.
    //
    //   1회차: retranscribed=2 → recover skipped reason=duo_final_applied success=2
    //   2회차: retranscribed=0 skippedOther=2 → 그 0이 방 표시를 덮어썼다
    //          → 우회가 풀리고, 소리도 없는데 원문 복원이 3.3초 헛돌았다
    //
    //   끝까지 돈 판은 마지막에 소리를 지운다. 두 번째 판은 더 할 일이 없다.
    final String runner = _codeOnly(
        _read('lib/custom_code/services/duo_final_transcription_runner.dart'));

    test('완료 표시가 있으면 끝난 방이다', () {
      expect(duoFinalRoomAlreadyDone(<String, dynamic>{
        kDuoFinalRoomCompletedField: 'ts',
        kDuoFinalRoomSuccessField: 2,
      }), isTrue);
    });

    test('성공이 0줄이어도 끝난 판은 끝난 것이다', () {
      // 소리는 이미 지워졌다. 다시 열어 봐야 같은 0이 나온다.
      expect(duoFinalRoomAlreadyDone(<String, dynamic>{
        kDuoFinalRoomCompletedField: 'ts',
        kDuoFinalRoomSuccessField: 0,
      }), isTrue);
    });

    test('중간에 끊긴 판은 다시 시도할 값이 있다', () {
      // 표시가 없다 = 소리도 남아 있다.
      expect(duoFinalRoomAlreadyDone(<String, dynamic>{}), isFalse);
      expect(duoFinalRoomAlreadyDone(null), isFalse);
    });

    test('러너가 줄을 읽기 전에 방 표시를 먼저 본다', () {
      final int run = runner.indexOf('Future<void> _run(');
      final int guard = runner.indexOf('duoFinalRoomAlreadyDone(', run);
      final int rows = runner.indexOf("collection('messages').get()", run);
      expect(run, greaterThan(0));
      expect(guard, greaterThan(run));
      expect(guard, lessThan(rows),
          reason: '줄을 다 돌고 나서 막으면 이미 0을 써 버린 뒤다');
    });

    test('막을 때는 방 표시를 쓰지 않고 그냥 나간다', () {
      final int guard = runner.indexOf('duoFinalRoomAlreadyDone(');
      final int ret = runner.indexOf('return;', guard);
      final int marker = runner.indexOf('kDuoFinalRoomCompletedField', guard);
      expect(ret, greaterThan(guard));
      expect(marker, greaterThan(ret),
          reason: '한 번 올라간 success는 내려가면 안 된다');
    });
  });

  group('🎧 창고에서 꺼낸 것은 이미 PCM16이다', () {
    // 🩺 2026-09-15 실기기에서 잡혔다. 러너가 `readKeyed`의 결과를 WAV로 알고
    //   머리말을 **한 번 더** 벗겼다 — RIFF가 없으니 null이 나왔고, 한 판이
    //   통째로 `wav_unreadable`로 떨어졌다(`failed=2 retranscribed=0`).
    //
    //   창고의 계약은 하나다: **파일에는 WAV로 쓰고, 꺼낼 때 PCM16으로 준다.**
    //   벗기는 일은 창고가 한다. 꺼내 쓰는 쪽은 그대로 전사기에 올린다.
    final String store =
        _codeOnly(_read('lib/custom_code/services/origin_pcm_store.dart'));
    final String runner = _codeOnly(
        _read('lib/custom_code/services/duo_final_transcription_runner.dart'));

    test('readKeyed가 머리말을 벗겨서 돌려준다', () {
      final int read = store.indexOf('Future<Uint8List?> readKeyed(');
      final int unwrap = store.indexOf('wavToPcm16(', read);
      final int close = store.indexOf('Future<OriginPcmManifest> manifest(', read);
      expect(read, greaterThan(0));
      expect(unwrap, greaterThan(read));
      expect(unwrap, lessThan(close),
          reason: '창고가 안 벗기면 꺼내 쓰는 쪽마다 벗겨야 한다');
    });

    test('재전사 러너는 두 번 벗기지 않는다', () {
      expect(runner.contains('wavToPcm16('), isFalse,
          reason: 'readKeyed가 이미 PCM16을 준다 — 또 벗기면 전량 실패한다');
    });

    test('기존 원문 복원과 같은 방식으로 전사기에 올린다', () {
      final String restore = _codeOnly(
          _read('lib/custom_code/services/origin_restoration_runner.dart'));
      // 먼저 선 쪽이 계약이다. 새 러너가 그 모양을 따라가야 한다.
      expect(restore.contains('wavToPcm16('), isFalse);
      for (final String code in <String>[restore, runner]) {
        final int r = code.indexOf('readKeyed(');
        final int t = code.indexOf('transcribePcm16(', r);
        expect(r, greaterThan(0));
        expect(t, greaterThan(r));
      }
    });
  });

  group('💾 직접통화 PCM은 게이트 앞에서 담는다', () {
    final String duo =
        _codeOnly(_read('lib/custom_code/widgets/routine_mode_duo.dart'));

    test('onUtteranceClosed에서 담는다', () {
      final int closed = duo.indexOf('session.onUtteranceClosed = (utteranceId, utterance, voicedMs)');
      final int stash = duo.indexOf('_stashDuoPcm(', closed);
      final int transcript = duo.indexOf('session.onTranscript = (result)', closed);
      expect(closed, greaterThan(0));
      expect(stash, greaterThan(closed));
      expect(stash, lessThan(transcript),
          reason: '게이트 뒤에서 담으면 실시간 판정이 최종 기록을 가른다');
    });

    test('수용 판정 자리에서는 더 이상 담지 않는다', () {
      final int handle = duo.indexOf('Future<void> _handleDirectTranscript(');
      final int end = duo.indexOf('Future<void> _stopDirectCall(', handle);
      expect(handle, greaterThan(0));
      expect(duo.substring(handle, end).contains('_stashDuoPcm('), isFalse,
          reason: '두 곳에서 담으면 같은 소리를 두 번 쓴다');
    });
  });
}
