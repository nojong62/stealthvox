// 🧭 [SUBJECT-HINT] 이 줄이 **누구 얘기인가**를 줄 옆에 적어 둔다
//
// 한국어는 이미 통하는 주어를 생략하고 영어는 못 한다. 그래서 배울글을 만들 때
// 누군가는 그 자리를 채워야 하는데, 번역은 **줄마다 호출이 따로 돈다.** 호출끼리
// 서로 뭘 골랐는지 모르니 같은 사람이 he·they로 갈렸다.
//
// 정돈(canonical)은 대화 전체를 한 번에 읽는다. 거기서 3자가 나오는 줄에만
// 참고 주어를 달아 두고, 번역 호출이 그 값을 받아 쓴다. 줄마다 다시 찍을 일이
// 없어진다.
//
// 이 파일이 지키는 것 넷이다.
//   1. 참고 주어는 **원문에 섞이지 않는다** (배울글·Practice의 재료가 원문이다)
//   2. 3자가 나오는 줄에만 붙는다 ("(나는)"으로 화면을 덮지 않는다)
//   3. 값이 바뀌면 그 줄 배울글을 비운다 (옛 번역은 다른 사람 얘기다)
//   4. 사용자가 고친 주어를 정돈이 덮지 않는다

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_canonical.dart';
import 'package:stealth_vox/custom_code/services/duo_study_state.dart';
import 'package:stealth_vox/custom_code/services/history_finalize.dart';

const String _canon = 'lib/custom_code/services/duo_canonical.dart';
const String _master = 'lib/custom_code/widgets/chat_history_master.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final String canon = _read(_canon);
  final String master = _read(_master);

  group('🧭 값이 오가는 길', () {
    test('정돈 결과가 참고 주어를 들고 다닌다', () {
      const turn = DuoCanonicalTurn(
        role: 'HOST',
        text: '지금 취업 준비 중이야',
        sourceIds: <String>['a'],
        state: kStudyStateIncluded,
        subject: '그 학생은',
      );
      expect(turn.subject, '그 학생은');
      expect(turn.toMap()['subject'], '그 학생은');
    });

    test('저장한 모양 그대로 되읽는다', () {
      final turn = DuoCanonicalTurn.fromMap(<String, dynamic>{
        'role': 'GUEST',
        'text': '아직 안 왔어',
        'source_ids': <String>['b'],
        'state': kStudyStateIncluded,
        'subject': '선생님이',
      });
      expect(turn!.subject, '선생님이');
    });

    test('3자가 없는 줄은 비어 있다 — 기본값이 빈 문자열이다', () {
      const turn = DuoCanonicalTurn(
        role: 'HOST',
        text: '나 지금 가',
        sourceIds: <String>['c'],
        state: kStudyStateIncluded,
      );
      expect(turn.subject, '');
      // 비어 있으면 저장 자체를 안 한다 — 빈 항목이 문서마다 쌓이지 않는다.
      expect(turn.toMap().containsKey('subject'), isFalse);
    });
  });

  group('🚫 원문에 섞이지 않는다', () {
    test('참고 주어는 text가 아니라 별도 자리에 산다', () {
      expect(canon,
          contains('"subject" is a note beside the turn, never part of it'));
      expect(canon, contains('Never put it into "text"'));
    });

    test('줄 문서에도 original_text가 아닌 제 자리에 쓴다', () {
      expect(canon, contains('kMessageSubjectHintField: turn.subject'));
      expect(kMessageSubjectHintField, 'subject_hint');
    });
  });

  group('🙅 나·너에는 안 붙인다', () {
    test('두 사람 얘기인 줄에는 아무것도 안 남긴다', () {
      expect(canon,
          contains('Leave "subject" out entirely for every turn about the speaker or the listener'));
      expect(canon, contains('Do not write "나는" or "너는"'));
    });

    test('누구 얘기인지 모르면 비워 둔다', () {
      expect(canon, contains('Leave it out too when you cannot tell'));
    });

    test('화면도 빈 값이면 아무것도 그리지 않는다', () {
      expect(master, contains("if (hint.isEmpty) return const SizedBox.shrink();"));
    });
  });

  group('🔄 값이 바뀌면 배울글을 다시 만든다', () {
    test('주어만 고쳐도 그 줄 배울글은 비워진다', () {
      final patch = historySubjectHintEditPatch(
        subject: '그 선생님은',
        editedAt: 'now',
      );
      expect(patch[kMessageSubjectHintField], '그 선생님은');
      expect(patch['translated_text'], '');
      expect(patch[kMessageSubjectHintEditedField], 'now');
    });

    test('원문은 건드리지 않는다 — 말은 그대로 둔다', () {
      final patch =
          historySubjectHintEditPatch(subject: '친구들이', editedAt: 'now');
      expect(patch.containsKey('original_text'), isFalse);
      expect(patch.containsKey(kMessageUserEditedAtField), isFalse);
    });

    test('앞뒤 공백은 떼고 저장한다', () {
      final patch =
          historySubjectHintEditPatch(subject: '  그 학생은  ', editedAt: 'now');
      expect(patch[kMessageSubjectHintField], '그 학생은');
    });
  });

  group('🔒 사용자가 고친 주어는 정돈이 덮지 않는다', () {
    test('따로 잠근다 — 줄을 안 고쳤어도 주어는 고쳤을 수 있다', () {
      expect(canon, contains('userLockedSubject'));
      expect(canon, contains('if (data[kMessageSubjectHintEditedField] != null)'));
      expect(canon,
          contains('if (!userLockedSubject.contains(turn.sourceIds.first))'));
    });
  });

  group('🎯 번역이 그 값을 쓴다', () {
    test('정해진 주어를 요청에 싣는다', () {
      expect(master, contains('final String subjectHint = _subjectHintOf('));
      expect(master, contains("'SUBJECT: "));
    });

    test('실린 주어는 이미 정해진 것으로 다룬다', () {
      expect(master,
          contains('who this line is about has already been settled'));
      expect(master,
          contains('do not go hunting through the surrounding lines for someone else'));
    });
  });
}
