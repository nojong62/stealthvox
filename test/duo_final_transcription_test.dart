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
}
