// 🧩 [DUO-CANONICAL] 정돈은 한 곳에서 하고, 그 결과가 곧 히스토리다
//
// 2026-09-04 실장님 정정으로 `Conversation Replay` 계층을 걷어냈다. 손봐야 할
// 것은 원본 자체이지 그 옆에 두는 사본이 아니었다. 그래서 Replay가 하려던 두
// 가지를 canonical이 맡는다.
//
//   ① 맥락상 명백한 STT 오류 제거 — `artifact`
//   ② 두 폰의 시계가 어긋나 뒤엉킨 순서를 실제 대화 순서로 복원
//
// 🚫 넓히면 안 되는 선은 그대로다([[duo-history-cleanup-principle]]):
//   사람이 실제로 한 말을 "중요하지 않다"거나 "덜 예쁘다"는 이유로 빼거나
//   새로 쓰지 않는다. 애매하면 언제나 보이는 쪽이다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_study_state.dart';

const String _canon = 'lib/custom_code/services/duo_canonical.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final String canon = _read(_canon);

  // ==========================================================================
  group('① 맥락상 명백한 STT 오류를 뺀다', () {
    test('artifact를 모델이 고를 수 있다', () {
      expect(canon,
          contains("  artifact    - not something either speaker said into their own phone."),
          reason: '프롬프트에 상태가 없으면 모델이 절대 안 고른다');
    });

    test('artifact가 네 갈래를 다 덮는다', () {
      for (final String kind in <String>[
        'words the recognizer invented out of silence',
        'a television, a radio, or another person in the room',
        'a fragment cut so short that it carries no meaning',
        'a plain mis-recognition that connects to nothing anywhere in the call',
      ]) {
        expect(canon, contains(kind), reason: '빼야 할 갈래가 빠졌다: \$kind');
      }
    });

    test('artifact가 상태로 매핑된다', () {
      expect(canon, contains("    case 'artifact':\n      return kStudyStateHiddenArtifact;"),
          reason: '매핑이 없으면 included로 조용히 떨어진다');
    });

    test('숨기는 상태이지 삭제가 아니다', () {
      // 실제 발화를 Firestore에서 지우지 않는다는 원칙은 그대로다.
      expect(kStudyStateHiddenArtifact, 'hidden_artifact');
      expect(canon, isNot(contains('batch.delete')));
    });

    test('근거를 좁게 요구한다 — 뜬금없다는 이유로는 못 뺀다', () {
      expect(canon, contains('connects to nothing, answers nothing, is answered by nothing'));
      expect(
          canon,
          contains('Awkward wording is not a reason to remove anything, '
              'and neither is changing the subject'),
          reason: '이 문장이 없으면 사람 말이 환청으로 지워진다');
    });

    test('애매하면 남기고 그 자리에 둔다', () {
      expect(canon,
          contains('When you cannot tell, keep the line and leave it where it is.'));
    });

    test('줄 단위가 아니라 전체 맥락을 먼저 본다', () {
      expect(canon, contains('READ THE WHOLE CALL BEFORE YOU DECIDE ANYTHING'));
      expect(canon, contains('Never judge a line on its own'));
    });

    test('판단 기준이 한 문장으로 서 있다', () {
      expect(
          canon,
          contains('"Does this stand as something a real person actually '
              'said in THIS conversation?"'));
    });
  });

  // ==========================================================================
  group('② 실제 대화 순서를 복원한다', () {
    test('순서를 바꾸지 말라는 옛 금지가 없다', () {
      expect(canon, isNot(contains('never reorder the call')),
          reason: '이 문장이 남아 있으면 시켜 놓고 못 하게 하는 것이다');
    });

    test('시계가 어긋난다는 사실을 모델에게 알려 준다', () {
      expect(canon, contains('two different phones whose clocks do not agree'));
      expect(canon, contains('a question comes before its answer'));
    });

    test('근거가 분명할 때만 옮기게 한다', () {
      expect(canon, contains('Move a turn ONLY when the conversation makes the true position plain'));
      expect(canon, contains('If you cannot tell, leave it exactly where it is'));
    });

    test('모델이 세운 순서를 코드가 도로 지우지 않는다', () {
      // 예전에는 GPT 응답을 받아 놓고 spokenAtMs로 다시 정렬했다.
      expect(
          canon,
          isNot(contains(
              'turns.sort((a, b) => (a.spokenAtMs ?? 0).compareTo(b.spokenAtMs ?? 0));')),
          reason: '다시 정렬하면 맥락으로 바로잡은 순서가 그 자리에서 사라진다');
    });

    test('빠진 줄만 시각으로 자리를 찾는다', () {
      expect(canon, contains('int _insertionIndexByTime('));
      expect(canon, contains('turns.insert(_insertionIndexByTime(turns, m.spokenAtMs), m)'));
    });

    test('얼마나 옮겼는지 로그에 남는다', () {
      expect(canon, contains('int _countOutOfTimeOrder('));
      expect(canon, contains("reordered="));
    });
  });

  // ==========================================================================
  group('넓히면 안 되는 선은 그대로다', () {
    test('짧거나 평범하다는 이유로 빼지 않는다', () {
      // 2026-09-04: "Importance is not yours to judge"를 글자 그대로 지키다
      // 명백한 기계 오인식까지 살리고 있었다. 기준을 "사람이 실제로 한 말로
      // 성립하는가"로 바꾸되, 스타일을 이유로 빼는 길은 그대로 막는다.
      expect(canon,
          contains('however short, ordinary, blunt, or off-topic'));
      expect(canon, contains('people do both all the time'));
    });

    test('화자를 섞지 않는다', () {
      expect(canon, contains('- Merge different speakers.'));
    });

    test('없던 말을 지어내지 않는다', () {
      expect(canon, contains('Add a fact, a plan, a reason or a feeling that was never spoken'));
      expect(canon, contains('- Summarise, compress, or translate.'));
    });

    test('모델이 빠뜨린 줄은 원문 그대로 되살린다', () {
      expect(canon, contains('[FAIL-OPEN]'));
      expect(canon, contains('restored_missing='));
    });
  });

  // ==========================================================================
  group('결과가 곧 히스토리다 — 두 번째 판이 없다', () {
    test('Replay를 부르지 않는다', () {
      for (final String gone in <String>[
        'buildDuoReplay',
        'replay/current',
        'DuoReplayScript',
      ]) {
        expect(canon, isNot(contains(gone)));
      }
    });

    test('원문이 바뀌면 옛 배울글을 비운다', () {
      // 안 비우면 원문과 배울글이 서로 다른 문장을 가리킨 채 남는다.
      // 비우면 공부방이 `_historyTargetNeedsWork`로 최종 원문에서 다시 만든다.
      expect(canon, contains("if (textChanged) 'translated_text': '',"));
      expect(canon, contains('final bool textChanged ='));
    });

    test('안 바뀐 줄의 배울글은 건드리지 않는다', () {
      // 통째로 비우면 안 바뀐 줄까지 GPT를 다시 부른다.
      expect(canon, contains("curText.isNotEmpty && curText != turn.text"));
    });

    test('바뀌기 직전 글자를 맨 처음 원문과 구별해 든다', () {
      // 두 번째 정돈에서 original_text_raw는 맨 처음 것이라 지금 글자와 다르다.
      expect(canon, contains('final curTextById = <String, String>{};'));
      expect(canon, contains('curTextById[channelId] = currentText;'));
    });

    test('개인 히스토리 줄에 그대로 쓴다', () {
      // original_text / translated_text 구조는 안 바뀐다 — 공부방의 배울글·
      // 소리·연습이 평소처럼 붙어야 한다.
      expect(canon, contains('applyDuoCanonicalToHistory'));
      expect(canon, contains("'original_text': turn.text,"),
          reason: '오리지널이 평소 자리에 안 들어가면 공부방이 못 읽는다');
      // 갈아 끼우기 전 글자는 따로 남겨 둔다 — 되돌릴 근거다.
      expect(canon, contains('kOriginalRawField'));
      expect(kOriginalRawField, 'original_text_raw');
    });
  });
}
