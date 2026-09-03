// ✂️ [DUO-CHUNK] 번역 스트림을 어디서 끊어 읽을지 정하는 규칙의 시험.
//
// 여기서 지키는 것은 두 가지이고, 서로 반대 방향으로 당긴다.
//
//   ① 짧은 발화는 나누지 않는다.
//      2026-09-03 실기기 발화가 한국어 8~17자(영어 번역 25~60자)였다.
//      그런 말을 쪼개면 TTS 호출만 두 배가 되고 억양이 끊긴다.
//
//   ② 나눌 만한 말은 **기다리지 않고** 바로 뗀다.
//      쉼표가 이미 완성됐는데 누적 길이를 더 기다리면, 자를 위치는 그대로인
//      채 조기 재생만 늦어진다. 그건 이 작업의 목적을 스스로 깎는 것이다.
//
// 두 요구를 가르는 것은 누적 길이가 아니라 **첫 조각 자체의 길이**다.
// 값의 근거는 `tool/duo_chunk_sim.dart`의 비교표에 있다.

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_speech_chunker.dart';

/// 델타를 잘게 흘려 넣어 실제 스트리밍을 흉내 낸다.
List<String> streamThrough(DuoSpeechChunker c, String text, {int step = 3}) {
  final out = <String>[];
  for (var i = 0; i < text.length; i += step) {
    final end = (i + step > text.length) ? text.length : i + step;
    out.addAll(c.add(text.substring(i, end)));
  }
  final tail = c.flush();
  if (tail != null) out.add(tail);
  return out;
}

void main() {
  group('짧은 발화는 나누지 않는다 (기존 경로와 같은 동작)', () {
    const List<String> shortOnes = <String>[
      'Hello.',
      'Really?',
      'Sounds good.',
      'Where are you going?',
      'Just a moment, please.',
      "It's the 144th test now.",
    ];

    for (final text in shortOnes) {
      test('"$text" (${text.length}자) → 조각 1개', () {
        final c = DuoSpeechChunker();
        final chunks = streamThrough(c, text);
        expect(chunks.length, 1,
            reason: '짧은 말을 나누면 TTS 호출만 늘고 억양이 끊긴다');
        expect(chunks.single, text);
        expect(c.didSplit, isFalse);
      });
    }

    test('문장이 둘이어도 짧으면 통짜로 둔다', () {
      // "Yes. I see." 는 마침표가 둘이지만 전체가 짧다 — 나눌 이유가 없다.
      final c = DuoSpeechChunker();
      final chunks = streamThrough(c, 'Yes. I see.');
      expect(chunks.length, 1);
      expect(c.didSplit, isFalse);
    });
  });

  group('긴 번역만 조기 재생을 위해 나눈다', () {
    test('쉼표가 있는 중간 길이 문장은 두 조각', () {
      // 지시문에 나온 바로 그 예다.
      const text =
          "If you're free this afternoon, do you want to grab a coffee together?";
      final c = DuoSpeechChunker();
      final chunks = streamThrough(c, text);
      expect(c.didSplit, isTrue);
      expect(chunks.length, 2, reason: '한두 조각 안에서 끝나야 한다');
      expect(chunks.first, "If you're free this afternoon,");
      expect(chunks.last, 'do you want to grab a coffee together?');
    });

    test('첫 조각이 한 호흡으로 읽을 만한 길이다', () {
      const text =
          "If you're free this afternoon, do you want to grab a coffee together?";
      final chunks = streamThrough(DuoSpeechChunker(), text);
      expect(chunks.first.length, greaterThanOrEqualTo(kDuoMinClauseChunkChars),
          reason: '"If you\'re" 같은 토막이 나가면 안 된다');
    });

    test('첫 조각을 뗀 뒤에는 짧은 조각도 곧바로 나간다', () {
      // 앞을 이미 읽고 있는데 뒤를 첫 조각만큼 모으면 그만큼 공백이 생긴다.
      const text =
          'One two three four five six seven eight nine ten eleven twelve, '
          'yes. no.';
      final c = DuoSpeechChunker();
      final chunks = streamThrough(c, text, step: 2);
      expect(c.didSplit, isTrue);
      expect(chunks.length, greaterThanOrEqualTo(2));
      expect(chunks.skip(1).any((s) => s.length < kDuoMinFirstChunkChars),
          isTrue,
          reason: '뒤 조각이 첫 조각 문턱을 다시 기다리면 조기 재생의 뜻이 없다: $chunks');
    });

    test('누적 60자를 기다리지 않는다 — 쉼표가 오면 바로 뗀다', () {
      // 이 문장의 쉼표는 30자에 있다. 누적 문턱 방식이었다면 60자가 찰
      // 때까지 기다렸고, 그만큼 조기 재생이 늦어졌다.
      const text =
          "If you're free this afternoon, do you want to grab a coffee together?";
      final c = DuoSpeechChunker();
      final out = <String>[];
      // 쉼표 직후(30자)까지만 흘려 넣는다.
      out.addAll(c.add(text.substring(0, 30)));
      expect(out.length, 1,
          reason: '쉼표가 완성됐는데 더 기다렸다 — 조기 재생의 이득을 버린 것이다');
      expect(out.single, "If you're free this afternoon,");
    });

    test('경계가 없는 긴 문장도 결국 끊어 읽는다', () {
      final text = List<String>.filled(40, 'word').join(' '); // 199자
      final chunks = streamThrough(DuoSpeechChunker(), text);
      expect(chunks.length, greaterThan(1),
          reason: '마침표가 없다고 끝까지 조용하면 안 된다');
      for (final ch in chunks) {
        expect(ch.length, lessThanOrEqualTo(kDuoMaxChunkChars + 1));
      }
    });
  });

  group('내용이 보존된다', () {
    test('조각을 합치면 원문과 같다 (공백 정규화 기준)', () {
      const List<String> texts = <String>[
        "If you're free this afternoon, do you want to grab a coffee together?",
        'Hello.',
        'One two three four five six seven eight nine ten, yes. no. maybe.',
      ];
      for (final text in texts) {
        final chunks = streamThrough(DuoSpeechChunker(), text);
        final joined = chunks.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        final want = text.replaceAll(RegExp(r'\s+'), ' ').trim();
        expect(joined, want, reason: '글자가 사라지거나 겹치면 안 된다');
      }
    });

    test('델타 크기가 달라도 읽히는 내용은 같다', () {
      // ⚠️ 조각 **경계**는 델타 크기에 따라 달라진다. 그게 정상이다 —
      //   번역이 통째로 도착하면 나눌 이유가 없어 한 조각으로 읽고,
      //   찔끔찔끔 오면 쉼표에서 먼저 떨어진다. 지켜야 하는 것은 경계가
      //   아니라 **글자가 하나도 사라지거나 겹치지 않는다**는 것이다.
      const text =
          "If you're free this afternoon, do you want to grab a coffee together?";
      String norm(List<String> c) =>
          c.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      final a = norm(streamThrough(DuoSpeechChunker(), text, step: 1));
      final b = norm(streamThrough(DuoSpeechChunker(), text, step: 7));
      final c = norm(streamThrough(DuoSpeechChunker(), text, step: 999));
      expect(a, text);
      expect(b, text);
      expect(c, text);
    });

    test('번역이 통째로 도착하면 나누지 않는다', () {
      // 스트리밍이 아주 빠르거나 응답이 짧으면 델타 하나로 끝난다.
      // 그때 굳이 쪼개면 TTS 호출만 늘어난다.
      const text =
          "If you're free this afternoon, do you want to grab a coffee together?";
      final c = DuoSpeechChunker();
      final chunks = streamThrough(c, text, step: 999);
      expect(chunks.length, 1, reason: '나눌 이유가 없는데 나눴다: $chunks');
    });
  });

  group('잘못 끊지 않는다', () {
    test('소수점에서 끊지 않는다', () {
      const text = 'The total is 3.5 kilograms and the price is 1,200 won '
          'for each item you ordered.';
      final chunks = streamThrough(DuoSpeechChunker(), text);
      for (final ch in chunks) {
        expect(ch.endsWith('3.'), isFalse);
        expect(ch.endsWith('1,'), isFalse);
      }
    });

    test('경계 부호가 잘려 나가지 않는다', () {
      // 물음표가 다음 조각으로 넘어가면 억양이 바뀐다.
      const text = 'Are you coming with us today? '
          'We are leaving in about ten minutes from the front gate.';
      final chunks = streamThrough(DuoSpeechChunker(), text);
      expect(chunks.first.endsWith('?'), isTrue,
          reason: '물음표는 앞 조각에 붙어야 한다: $chunks');
      expect(chunks.length, greaterThan(1));
    });

    test('닫는 따옴표까지 앞 조각에 포함된다', () {
      const text = 'He said "we are leaving now." '
          'Everyone started walking toward the parking lot together.';
      final chunks = streamThrough(DuoSpeechChunker(), text);
      expect(chunks.first.endsWith('."'), isTrue,
          reason: '따옴표가 뒤 조각 머리로 가면 안 된다: $chunks');
    });
  });

  group('빈 입력', () {
    test('빈 델타는 아무것도 내보내지 않는다', () {
      final c = DuoSpeechChunker();
      expect(c.add(''), isEmpty);
      expect(c.flush(), isNull);
    });

    test('공백만 있으면 조각이 없다', () {
      final c = DuoSpeechChunker();
      c.add('   ');
      expect(c.flush(), isNull);
    });
  });
}
