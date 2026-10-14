import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_transcript_gate.dart';
import 'package:stealth_vox/custom_code/services/late_continuation.dart';
import 'package:stealth_vox/custom_code/services/transcript_text_clean.dart';

void main() {
  group('글자로 남길 것 — 모든 문자 체계', () {
    test('가나·한자·키릴·데바나가리·움라우트가 지워지지 않는다', () {
      for (final text in <String>[
        'わかります、うちの子も。',
        '我们明天见。',
        'Да, конечно.',
        'हाँ, ठीक है।',
        'Schön, danke!',
        '네, 좋아요.',
      ]) {
        final clean = text.replaceAll(kTranscriptNonLetterPattern, '').trim();
        expect(clean, isNotEmpty, reason: text);
      }
    });

    test('문장부호·기호만이면 빈 문자열이다', () {
      expect('…?! ~ 。、'.replaceAll(kTranscriptNonLetterPattern, '').trim(),
          isEmpty);
    });
  });

  group('2026-10-14 실기기에서 버려지던 발화', () {
    test('Duo: 중국어·일본어 발화는 잡음이 아니다', () {
      expect(noiseTranscriptReason('我们明天几点见面？'), isNull);
      expect(noiseTranscriptReason('はい'), isNull);
      expect(noiseTranscriptReason('Ja, genau.'), isNull);
    });

    test('Duo: 기호만인 전사는 여전히 버린다', () {
      expect(noiseTranscriptReason('…'), DuoDropReason.emptyAfterClean);
    });

    test('이어 말하기: 일본어 문장은 머뭇거림이 아니다', () {
      expect(isHesitationOnlyTranscript('さっきのおもちゃって何ですか'), isFalse);
      expect(isHesitationOnlyTranscript('음…'), isTrue);
    });
  });
}
