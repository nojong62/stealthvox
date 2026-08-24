import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/ai_style.dart';

/// 로비 AI STYLE이 실제 영어 생성 프롬프트에 닿는지 지키는 테스트.
///
/// 여기서 잡으려는 사고는 둘이다.
/// 1. **American과 Native가 같은 지시문으로 수렴하는 것.** 그러면 넷 중 둘이
///    죽는데, 화면에는 여전히 넷이 떠 있어 아무도 눈치채지 못한다.
/// 2. **영어가 아닌 TARGET에 스타일이 새는 것.** 일본어 방 프롬프트에
///    "미국식으로 말해라"가 붙으면 그 방은 조용히 망가진다.
void main() {
  group('normalizeAiStyle', () {
    test('대소문자가 달라도 넷 중 하나로 접힌다', () {
      expect(normalizeAiStyle('nAtIvE'), 'Native');
      expect(normalizeAiStyle('  american '), 'American');
    });

    test('모르는 값과 빈 값은 Standard다', () {
      expect(normalizeAiStyle('Klingon'), kDefaultAiStyle);
      expect(normalizeAiStyle(''), kDefaultAiStyle);
      expect(normalizeAiStyle(null), kDefaultAiStyle);
    });
  });

  group('aiStylePromptBlock', () {
    test('영어 TARGET에서만 붙는다', () {
      for (final target in <String>['Japanese', 'Korean', 'Spanish', '']) {
        expect(
          aiStylePromptBlock(targetLang: target, style: 'Native'),
          isEmpty,
          reason: '$target 방에 영어 스타일이 새면 안 된다',
        );
      }
      expect(
        aiStylePromptBlock(targetLang: 'English', style: 'Native'),
        isNotEmpty,
      );
    });

    test('scope가 지시문에 그대로 박힌다', () {
      final block = aiStylePromptBlock(
        targetLang: 'English',
        style: 'Native',
        scope: 'the PART 1 sentence only, never the Korean PART 2',
      );
      expect(block, contains('the PART 1 sentence only'));
    });

    test('주변 프롬프트의 형식 규칙을 밀어내지 않는다고 못 박는다', () {
      final block = aiStylePromptBlock(targetLang: 'English', style: 'Native');
      expect(block, contains('never override'));
      expect(block, contains('exactly one sentence'));
    });
  });

  group('aiStyleInstruction', () {
    test('네 스타일의 지시문이 서로 다르다', () {
      final seen = kAiStyles.map(aiStyleInstruction).toSet();
      expect(seen.length, kAiStyles.length,
          reason: '두 스타일이 같은 지시문을 쓰면 화면의 선택지가 거짓말이 된다');
    });

    test('American은 문장의 뼈대를 유지하고, Native는 다시 짓는다', () {
      final american = aiStyleInstruction('American');
      final native = aiStyleInstruction('Native');

      // American = "같은 말을 미국식으로". 뼈대는 그대로 둔다.
      expect(american, contains('Keep the shape of what the speaker said'));
      // Native = "하려던 생각을 원어민이라면 어떻게 꺼냈을지".
      expect(native, contains('Do not follow the source'));
      expect(native, isNot(contains('Keep the shape of what the speaker said')));
    });

    test('Native를 "어려운 영어"로 오해하지 않게 막아 둔다', () {
      final native = aiStyleInstruction('Native');
      expect(native, contains('does not mean hard words'));
      expect(native, contains('Never invent a fact'));
    });

    test('American·British는 철자만 바꾸는 스타일이 아니라고 적혀 있다', () {
      expect(aiStyleInstruction('American'),
          contains('not just American spelling'));
      expect(
          aiStyleInstruction('British'), contains('not just British spelling'));
    });
  });

  group('effectiveAiStyle', () {
    test('영어가 아니면 저장값과 무관하게 Standard로 접힌다', () {
      expect(
        effectiveAiStyle(targetLang: 'Japanese', style: 'Native'),
        kDefaultAiStyle,
      );
    });

    test('영어면 저장값을 그대로 쓴다', () {
      expect(
        effectiveAiStyle(targetLang: 'English', style: 'British'),
        'British',
      );
    });
  });
}
