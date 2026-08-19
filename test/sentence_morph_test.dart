// 🔤 [SENTENCE-MORPH] 변화 탐지 고정 테스트.
//
//   여기 있는 11개 전이는 실장님이 P2 재구성 지시문에서 직접 든 예문이다.
//   기대 출력도 그 문서에 적힌 것을 그대로 옮겼다 — 알고리즘을 바꿀 때
//   이 결과가 흔들리면 그건 회귀다.
//
//   ⚠️ 실제 History ladder 10세트 검증은 **아직 하지 않았다.** 이 테스트가
//   통과한다고 파라미터가 제품 최종값이 되는 것은 아니다.

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/sentence_morph.dart';

/// 강조된 문구만 뽑아 비교하기 쉽게.
List<String> phrasesOf(String prev, String cur) =>
    computeMorph(prev, cur).phrases;

void main() {
  group('computeMorph — 지시문 예문', () {
    test('앞부분 추가 + 표현 교체 (구조 변경)', () {
      expect(
        phrasesOf("I didn't like the idea.",
            "At first, I wasn't sure I liked the idea."),
        <String>['At first,', "wasn't sure I liked"],
      );
    });

    test('앞부분 추가 + 중간 추가', () {
      expect(
        phrasesOf('I thought it was strange.',
            'At first, I thought it was a little strange.'),
        <String>['At first,', 'a little'],
      );
    });

    test('여러 곳 동시 추가', () {
      expect(
        phrasesOf('I was surprised.',
            'I was honestly a little surprised at first.'),
        <String>['honestly a little', 'at first.'],
      );
    });

    test('표현 교체', () {
      expect(
        phrasesOf("I didn't like it.", "I wasn't sure I liked it."),
        <String>["wasn't sure I liked"],
      );
    });

    test('suffix 확장', () {
      expect(
        phrasesOf('I thought it was strange.',
            'I thought it was strange, but after a while I got used to it.'),
        <String>['but after a while I got used to it.'],
      );
    });

    test('prefix reframing', () {
      // §6-D가 든 변화 그대로: `For a moment` 와 `honestly` 두 곳.
      // 사이에 낀 `I`(안 바뀐 단어)를 삼키지 않는다.
      expect(
        phrasesOf("I didn't know what to say.",
            "For a moment, I honestly didn't know what to say."),
        <String>['For a moment,', 'honestly'],
      );
    });

    test('한 단어 앞 추가', () {
      expect(
        phrasesOf("I didn't really expect that.",
            "Honestly, I didn't really expect that."),
        <String>['Honestly,'],
      );
    });

    test('절 확장', () {
      expect(
        phrasesOf("Honestly, I didn't really expect that.",
            "Honestly, I didn't really expect that, so I wasn't sure what to say."),
        <String>["so I wasn't sure what to say."],
      );
    });

    test('so → and for a moment 구조 변화 + 단어 삽입', () {
      expect(
        phrasesOf(
            "Honestly, I didn't really expect that, so I wasn't sure what to say.",
            "Honestly, I didn't really expect that, and for a moment, I wasn't quite sure what to say."),
        <String>['and for a moment,', 'quite'],
      );
    });

    test('한 단어만 변경', () {
      expect(
        phrasesOf('It was good.', 'It was better.'),
        <String>['better.'],
      );
    });

    test('대부분 재작성 → 강조 생략', () {
      expect(
        phrasesOf('I was surprised.',
            'Looking back on it now, the whole thing turned out completely differently.'),
        isEmpty,
      );
    });
  });

  group('computeMorph — 불변식', () {
    const samples = <List<String>>[
      ["I didn't like the idea.", "At first, I wasn't sure I liked the idea."],
      ['I was surprised.', 'I was honestly a little surprised at first.'],
      ["Honestly, I didn't really expect that, so I wasn't sure what to say.",
        "Honestly, I didn't really expect that, and for a moment, I wasn't quite sure what to say."],
      ['It was good.', 'It was better.'],
    ];

    test('range가 겹치지 않고 정렬돼 있다', () {
      for (final s in samples) {
        final ranges = computeMorph(s[0], s[1]).ranges;
        for (int i = 1; i < ranges.length; i++) {
          expect(ranges[i].start, greaterThanOrEqualTo(ranges[i - 1].end),
              reason: '${s[1]} 에서 구간이 겹친다');
        }
      }
    });

    test('range가 text 범위를 넘지 않는다', () {
      for (final s in samples) {
        final morph = computeMorph(s[0], s[1]);
        for (final r in morph.ranges) {
          expect(r.start, greaterThanOrEqualTo(0));
          expect(r.end, lessThanOrEqualTo(morph.text.length));
          expect(r.end, greaterThan(r.start));
        }
      }
    });

    test('maxRegions를 넘지 않는다', () {
      const cfg = MorphConfig(maxRegions: 2);
      final morph = computeMorph(
        'I was surprised.',
        'I was honestly a little surprised at first, and I said so.',
        config: cfg,
      );
      expect(morph.ranges.length, lessThanOrEqualTo(2));
    });

    test('identity는 결정적이다', () {
      const prev = "I didn't like it.";
      const cur = "I wasn't sure I liked it.";
      expect(computeMorph(prev, cur).identity,
          computeMorph(prev, cur).identity);
      expect(computeMorph(prev, cur).identity, isNot('none'));
    });

    test('첫 문장(이전 없음)은 강조가 없다', () {
      final morph = computeMorph('', 'I was surprised.');
      expect(morph.isEmpty, isTrue);
      expect(morph.identity, 'none');
      expect(morph.text, 'I was surprised.');
    });

    test('같은 문장이면 강조가 없다', () {
      expect(computeMorph('It was good.', 'It was good.').isEmpty, isTrue);
    });

    test('아포스트로피가 글자 단위로 부서지지 않는다', () {
      final p = phrasesOf("I did not like it.", "I didn't like it.");
      expect(p.length, 1);
      expect(p.first, "didn't");
    });

    test('빈 입력에서 crash하지 않는다', () {
      expect(computeMorph('', '').isEmpty, isTrue);
      expect(computeMorph('a', '').isEmpty, isTrue);
    });
  });

  group('morphEmphasisInstruction', () {
    test('강조가 없으면 빈 문자열', () {
      expect(morphEmphasisInstruction(computeMorph('', 'Hello.')), '');
    });

    test('강조 문구가 지시문에 인용된다', () {
      final morph = computeMorph("I didn't like it.", "I wasn't sure I liked it.");
      final instruction = morphEmphasisInstruction(morph);
      expect(instruction, contains("wasn't sure I liked"));
      expect(instruction, contains('understated'));
    });
  });
}
