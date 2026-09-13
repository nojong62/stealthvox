import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_canonical.dart';
import 'package:stealth_vox/custom_code/services/duo_study_state.dart';

/// 정돈 프롬프트는 private이라 소스를 읽어 규칙의 존재를 붙잡는다.
/// (`duo_keep_all_test.dart`와 같은 방식이다.)
/// 줄바꿈은 맞춰 읽는다 — 작업 트리는 CRLF인데 규칙 문장은 여러 줄에 걸쳐 있다
/// (`origin_restoration_runner_lifecycle_test.dart`와 같은 방식이다).
String _canonSource() => File('lib/custom_code/services/duo_canonical.dart')
    .readAsStringSync()
    .replaceAll('\r\n', '\n');

DuoSourceUtterance u(String id, String role, String text, int ms) =>
    DuoSourceUtterance(
      id: id,
      role: role,
      text: text,
      spokenAtMs: ms,
      seq: 0,
      srcLang: 'Korean',
    );

void main() {
  group('canonical은 글자를 소유하지 않는다', () {
    final String src = _canonSource();

    test('GPT Transcribe 원문은 immutable이라고 명시한다', () {
      expect(src, contains('Every source text is immutable.'));
      expect(src, contains('THIS PASS DOES NOT TRANSCRIBE OR EDIT SPEECH.'));
      expect(src, contains('Never return a text field.'));
    });

    test('문장 완성·이름·단어·어미·말투 교정을 금지한다', () {
      expect(src, contains('do not finish fragments, fix names or words, change endings'));
      expect(src, contains('normalize\nhonorific speech'));
      expect(src, isNot(contains('SPEECH LEVEL:')));
      expect(src, isNot(contains('Repair the ENDING ONLY')));
    });

    test('모델 text를 읽지 않고 source text를 그대로 쓴다', () {
      expect(src, contains('text: original.text'));
      expect(src, contains('sourceIds: <String>[id]'));
      expect(src, isNot(contains("final text = (item['text']")));
    });

    test('한 output은 source id 하나라 PCM 연결을 보존한다', () {
      expect(src, contains('Do not merge source ids.'));
      expect(src, contains('One output turn must contain exactly one source id.'));
    });
  });
  group('fallbackCanonical', () {
    test('GPT가 없어도 오간 말을 하나도 잃지 않는다', () {
      final source = <DuoSourceUtterance>[
        u('a', 'HOST', '여보세요?', 100),
        u('b', 'GUEST', '응.', 200),
        u('c', 'HOST', '지금 어디야?', 300),
      ];
      final turns = fallbackCanonical(source);
      expect(turns.length, 3);
      expect(turns.map((t) => t.text), <String>['여보세요?', '응.', '지금 어디야?']);
    });

    test('폴백은 아무것도 감추지 않는다 — 정돈이 안 됐을 뿐이다', () {
      final turns = fallbackCanonical(<DuoSourceUtterance>[
        u('a', 'HOST', '음.', 100),
        u('b', 'GUEST', '어?', 200),
      ]);
      for (final t in turns) {
        expect(t.state, kStudyStateIncluded);
        expect(isStudyVisible(t.state), isTrue);
      }
    });

    test('줄마다 어느 원본에서 왔는지 남는다', () {
      final turns = fallbackCanonical(<DuoSourceUtterance>[
        u('msg1', 'HOST', '안녕.', 100),
      ]);
      expect(turns.single.sourceIds, <String>['msg1']);
    });
  });

  group('DuoCanonicalTurn.fromMap', () {
    test('저장한 모양 그대로 되읽는다', () {
      const turn = DuoCanonicalTurn(
        role: 'HOST',
        text: '지금 어디야?',
        sourceIds: <String>['m1', 'm2'],
        state: kStudyStateMerged,
        spokenAtMs: 1234,
      );
      final back = DuoCanonicalTurn.fromMap(turn.toMap());
      expect(back, isNotNull);
      expect(back!.role, 'HOST');
      expect(back.text, '지금 어디야?');
      expect(back.sourceIds, <String>['m1', 'm2']);
      expect(back.state, kStudyStateMerged);
      expect(back.spokenAtMs, 1234);
    });

    test('글이 없으면 줄로 치지 않는다', () {
      expect(DuoCanonicalTurn.fromMap(<String, dynamic>{'text': '   '}), isNull);
      expect(DuoCanonicalTurn.fromMap(null), isNull);
    });

    test('상태가 없으면 보이는 쪽으로 읽는다', () {
      final back = DuoCanonicalTurn.fromMap(<String, dynamic>{'text': '응.'});
      expect(back!.state, kStudyStateIncluded);
      expect(isStudyVisible(back.state), isTrue);
    });
  });

  group('상태 이름', () {
    test('감추는 상태에 중요도 뜻이 섞이지 않는다', () {
      for (final state in kStudyStateHidden) {
        for (final banned in <String>['value', 'important', 'key', 'core']) {
          expect(state.contains(banned), isFalse,
              reason: '$state — 말의 가치로 감추는 상태를 만들면 안 된다');
        }
      }
    });
  });
}
