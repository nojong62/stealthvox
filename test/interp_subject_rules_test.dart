// 🧭 [INTERP-SUBJECT] 통역이 상대를 3인칭으로 부르지 않게 한다
//
// 통역은 번역문 **한 문장**이 두 곳으로 간다.
//
//   translateForSpeech(...) → spoken
//        ├→ TTS가 읽는다     (상대가 그 순간 듣는 소리)
//        └→ History에 저장   (공부방의 배울글)
//
// 소리와 글자가 갈라지지 않으므로, 이 프롬프트 하나를 고치면 둘 다 고쳐진다.
// 정돈(canonical)이 나중에 글자를 손봐 주긴 하지만 **들린 소리는 되돌릴 수
// 없다.** 그래서 규칙이 여기 있어야 한다.
//
// 이 번역기는 문맥을 하나도 안 본다(시스템 프롬프트 + 그 발화 한 줄이 전부).
// 그래도 규칙이 성립하는 이유는 셋 다 문맥이 필요 없기 때문이다.
//   · 두 사람은 나 아니면 너      — 통화 구조에서 나온다
//   · 한국어가 3자를 소리 내어 말함 — 그 발화 안에 이미 있다
//   · 성별은 지어내지 않음         — 그 발화의 낱말만 보면 된다
//
// ⚠️ 프롬프트가 **두 벌**이다(스트리밍/비스트리밍). 코드에 "한 글자도 다르지
//   않아야 한다"고 적혀 있고, 이 파일이 그것을 값으로 지킨다 — 한쪽만 고치면
//   실기기에서 스트리밍이 켜졌는지에 따라 결과가 달라진다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _duo = 'lib/custom_code/widgets/routine_mode_duo.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// 프롬프트를 이루는 조각들. 두 함수 모두 이 줄들을 그대로 들고 있어야 한다.
const List<String> _rule = <String>[
  r'"WHO THE UTTERANCE IS ABOUT: $srcLang leaves out a subject that is "',
  r'"already understood; $toLang cannot. Two people are talking, so almost "',
  r'"every utterance is about one of them. The speaker is \"I\". The one "',
  r'"being spoken to is \"you\". NEVER call either of them \"he\", \"she\", "',
  r'"or \"they\".\n"',
  r'"When the utterance really is about somebody else, $srcLang says so out "',
  r'"loud, so name that person the way it named them: the teacher, my "',
  r'"friend, your mom, or their name. Never invent a gender. Use \"he\" or "',
  r'"\"she\" only when the utterance says which one, and \"they\" only when "',
  r'"it gives you no such word to reuse.\n"',
];

void main() {
  final String duo = _read(_duo);

  group('🧭 통역도 두 사람을 나·너로 부른다', () {
    test('규칙이 프롬프트에 들어 있다', () {
      expect(duo, contains('WHO THE UTTERANCE IS ABOUT'));
    });

    test('통화 중인 두 사람은 he·she·they가 아니다', () {
      expect(duo, contains(r'The speaker is \"I\"'));
      expect(duo, contains(r'The one "'));
      expect(duo,
          contains(r'NEVER call either of them \"he\", \"she\", "'));
    });

    test('3자는 발화가 부른 그대로 부른다', () {
      expect(duo, contains('name that person the way it named them'));
      expect(duo, contains('the teacher, my '));
    });

    test('성별은 지어내지 않는다', () {
      expect(duo, contains('Never invent a gender'));
      expect(duo, contains('only when the utterance says which one'));
    });
  });

  group('🔁 프롬프트 두 벌이 한 글자도 다르지 않다', () {
    test('규칙의 모든 줄이 정확히 두 번씩 나온다', () {
      // 한쪽만 고치면 스트리밍이 켜졌는지에 따라 결과가 갈린다.
      for (final String line in _rule) {
        expect(line.allMatches(duo).length, 2, reason: line);
      }
    });

    test('규칙 첫 줄과 끝 줄이 각각 두 번씩 있다', () {
      int countOf(String needle) =>
          needle.allMatches(duo).length;
      expect(countOf(_rule.first), 2);
      expect(countOf(_rule.last), 2);
    });

    test('기존 규칙("한 글자도 다르지 않아야 한다")이 그대로 있다', () {
      expect(duo, contains('프롬프트는 위 함수와 **한 글자도 다르지 않아야 한다.**'));
    });
  });

  group('🔒 통역 번역기의 성질은 그대로다', () {
    test('여전히 번역기이지 대화 상대가 아니다', () {
      expect(duo, contains('You are NOT a chat assistant'));
      expect(duo, contains('NEVER continue the conversation'));
    });

    test('조각이라도 옮긴다는 규칙은 살아 있다', () {
      expect(duo, contains('Always translate whatever words are present'));
    });

    test('번역문만 돌려준다는 규칙도 살아 있다', () {
      expect(duo, contains('Return ONLY the translated sentence'));
    });
  });
}
