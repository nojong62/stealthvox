import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_canonical.dart';
import 'package:stealth_vox/custom_code/services/duo_study_state.dart';

/// 정돈 프롬프트는 private이라 소스를 읽어 규칙의 존재를 붙잡는다.
/// (`duo_keep_all_test.dart`와 같은 방식이다.)
String _canonSource() =>
    File('lib/custom_code/services/duo_canonical.dart').readAsStringSync();

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
  // ── 🙇 말투는 사람마다 하나다 ─────────────────────────────────────────
  group('🙇 말투는 화자마다 하나로 유지된다', () {
    final String src = _canonSource();

    test('정돈이 말투를 되돌릴 수 있다고 적혀 있다', () {
      expect(src, contains('SPEECH LEVEL:'));
      expect(src, contains('Put a speech level back where that speaker plainly held it'));
    });

    test('화자마다 하나이고 통화 내내 유지된다고 적혀 있다', () {
      expect(src, contains('each speaker holds ONE level toward the other for the whole call'));
      expect(src, contains('존댓말'));
      expect(src, contains('반말'));
    });

    test('확실히 들린 줄이 기준이고, 어긋난 하나가 잘못 들린 것이다', () {
      expect(src, contains('take the level their clear turns agree on'));
      expect(src, contains('the odd turn out is a misheard ending, not a change of heart'));
    });

    test('어미만 고친다 — 말과 뜻은 그대로다', () {
      expect(src, contains('Repair the ENDING ONLY'));
    });

    test('화자를 각각 따로 본다 — 둘이 서로 다른 말투일 수 있다', () {
      expect(src, contains('Judge each speaker on their own turns alone'));
    });

    test('진짜로 말을 놓은 경우까지 뭉개지 않는다', () {
      expect(src, contains('when the call itself shows a real switch'));
      expect(src, contains('A real switch holds from that point on'));
    });

    test('"style 손대지 말라"와 부딪히지 않게 예외를 밝혀 뒀다', () {
      // 이 한 줄이 없으면 두 규칙이 싸워서 모델이 아무것도 안 고친다.
      expect(src, contains('Repairing a broken speech level under SPEECH LEVEL is not polish'));
    });

    test('원본(SOURCE)은 그대로다 — 고치는 것은 정돈 결과뿐이다', () {
      expect(src, contains('canonical을 만들면서 고치지도 지우지도 않는다'));
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
