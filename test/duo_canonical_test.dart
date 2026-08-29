import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_canonical.dart';
import 'package:stealth_vox/custom_code/services/duo_study_state.dart';

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
