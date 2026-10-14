// 🚦 [DUO-GATE] 직접 대화 전사문이 **어떤 사유로** 버려지는지 고정한다.
//
// 이 시험의 목적은 "필터가 옳다"를 주장하는 것이 아니라, 지금 필터가
// 실제로 무엇을 버리는지 글로 남기는 것이다. 실기기 로그의
// `[DuoSTT-DECISION] reason=` 값과 여기 기대값이 같은 문자열이다.

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_transcript_gate.dart';

void main() {
  group('noiseTranscriptReason — 통과해야 하는 한국어', () {
    // 실장님이 지목한 짧은 한국어. 글자 수로 버리지 않는다는 정책의 근거.
    for (final String word in <String>[
      '네',
      '네.',
      '응',
      '왜',
      '왜?',
      '뭐',
      '안',
      '또',
      '음',
      '아',
      '그래',
      '맞아요',
      '아니요',
    ]) {
      test('"$word" 는 잡음이 아니다', () {
        expect(noiseTranscriptReason(word), isNull);
      });
    }

    test('문장 끝 조사·짧은 어미가 붙어도 통과한다', () {
      expect(noiseTranscriptReason('오늘 저녁에 집에 갈 거예요.'), isNull);
      expect(noiseTranscriptReason('그건 좀 그렇죠?'), isNull);
      expect(noiseTranscriptReason('밥은 먹었니'), isNull);
      expect(noiseTranscriptReason('갔다니까요!'), isNull);
    });

    test('영어·숫자 섞인 문장도 통과한다', () {
      expect(noiseTranscriptReason('okay 3시에 봐요'), isNull);
    });
  });

  group('noiseTranscriptReason — 버리는 사유', () {
    test('빈 문자열 / 공백만', () {
      expect(noiseTranscriptReason(''), DuoDropReason.emptyText);
      expect(noiseTranscriptReason('   \n '), DuoDropReason.emptyText);
    });

    test('문장부호만 남은 줄', () {
      expect(noiseTranscriptReason('...'), DuoDropReason.emptyAfterClean);
      expect(noiseTranscriptReason('?!'), DuoDropReason.emptyAfterClean);
    });

    test('자막 관용구는 환청으로 본다', () {
      expect(noiseTranscriptReason('Thank you for watching!'),
          DuoDropReason.hardGhost);
      expect(noiseTranscriptReason('시청해 주셔서 감사합니다'),
          DuoDropReason.hardGhost);
    });
  });

  group('모든 문자 체계를 글자로 본다 (2026-10-14 수정)', () {
    // 예전에는 `\w`(ASCII)와 가-힣만 남겨 아래가 전부 empty_after_clean이었다.
    // 실기기에서 일본어 발화가 통째로 버려진 뒤 유니코드 문자 기준으로 바꿨다.
    test('한글 자모도 글자다 — 잡음 판정은 소리 시간이 한다', () {
      expect(noiseTranscriptReason('ㅋㅋ'), isNull);
      expect(noiseTranscriptReason('ㅇㅇ'), isNull);
    });

    test('일본어·중국어 발화는 살아남는다', () {
      expect(noiseTranscriptReason('はい'), isNull);
      expect(noiseTranscriptReason('好的'), isNull);
      expect(noiseTranscriptReason('こんにちは'), isNull);
    });

    test('키릴·아랍 문자도 마찬가지다', () {
      expect(noiseTranscriptReason('да'), isNull);
      expect(noiseTranscriptReason('نعم'), isNull);
    });

    test('라틴 글자가 섞여도 그대로 산다', () {
      expect(noiseTranscriptReason('はい ok'), isNull);
    });
  });

  group('belowVoicedGate — 150ms 문턱', () {
    const int minMs = 150;

    test('문턱 미만은 버린다', () {
      expect(belowVoicedGate(44, minMs: minMs), isTrue);
      expect(belowVoicedGate(149, minMs: minMs), isTrue);
    });

    test('문턱 이상은 통과한다', () {
      expect(belowVoicedGate(150, minMs: minMs), isFalse);
      expect(belowVoicedGate(1164, minMs: minMs), isFalse);
    });

    test('null은 "짧았다"가 아니라 "모른다" — 통과시킨다', () {
      expect(belowVoicedGate(null, minMs: minMs), isFalse);
    });

    test('짧은 한국어 응답의 실측 구간(200~300ms)은 살아남는다', () {
      expect(belowVoicedGate(200, minMs: minMs), isFalse);
      expect(belowVoicedGate(300, minMs: minMs), isFalse);
    });

    test('실측 클릭 잡음(41~44ms)은 걸린다', () {
      for (final int ms in <int>[41, 42, 44]) {
        expect(belowVoicedGate(ms, minMs: minMs), isTrue);
      }
    });
  });

  group('사유 이름은 로그와 같은 문자열이어야 한다', () {
    test('reason 값 목록', () {
      expect(DuoDropReason.accepted, 'accepted');
      expect(DuoDropReason.staleGeneration, 'stale_generation');
      expect(DuoDropReason.voicedMs, 'voiced_ms');
      expect(DuoDropReason.emptyText, 'empty_text');
      expect(DuoDropReason.emptyAfterClean, 'empty_after_clean');
      expect(DuoDropReason.hardGhost, 'hard_ghost');
      expect(DuoDropReason.duplicateItem, 'duplicate_item');
      expect(DuoDropReason.historyWriteFailed, 'history_write_failed');
    });
  });
}
