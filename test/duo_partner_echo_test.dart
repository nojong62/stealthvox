// 📢 [PARTNER-ECHO] 상대 폰 스피커가 낸 소리를 전사문에서 골라낸다
//
// 2026-09-04 실기기(호스트 S25 / 게스트 Fold 5, 2m 거리):
//
//   13:32:47.5  →내가 보냄  seq=1 lang=English
//   13:32:53.7    ✕버림  rmsDbfs=-54.7   ← 상대 폰이 한국어 TTS를 트는 중
//   13:32:54.6    ✕버림  rmsDbfs=-60.9
//   13:32:59.4    ✕버림  rmsDbfs=-53.2  voicedMs=4556
//
// 내가 보낸 뒤 4~14초에만 몰려 있다. 상대 폰이 번역해서 소리 내는 시간대다.
// 2m라 −47~−60으로 들어와 세기 게이트(−42.0)가 다 걸렀지만, 마주 앉으면
// 그 문턱을 넘는다. 통역의 정상 사용이 마주 앉는 것이므로 이건 예외가 아니다.
//
// 그래서 두 번째 방어선을 둔다 — **마이크는 열어 두고, 들어온 글자를 보고
// 버린다.** 게이트로 막으면 그동안의 진짜 발화가 잘리고, 알림이 유실되면
// 마이크가 닫힌 채 남는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_partner_echo.dart';

const String _duo = 'lib/custom_code/widgets/routine_mode_duo.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _region(String src, String start, String end) {
  final int a = src.indexOf(start);
  if (a < 0) throw StateError('없는 자리: $start');
  final int b = src.indexOf(end, a + 1);
  if (b < a) throw StateError('없는 자리: $end');
  return src.substring(a, b);
}

void main() {
  final String duo = _read(_duo);
  final DateTime t0 = DateTime(2026, 9, 4, 13, 32, 52);

  PartnerEchoMemory withLine(String text) =>
      PartnerEchoMemory()..note(text, at: t0);

  group('상대 폰이 낸 소리를 알아본다', () {
    test('그대로 되돌아오면 걸린다', () {
      final m = withLine('안녕하세요, 반갑습니다');
      expect(m.matches('안녕하세요, 반갑습니다', now: t0), isTrue);
    });

    test('구두점이 달라도 걸린다 — STT는 문장부호를 다르게 찍는다', () {
      final m = withLine('안녕하세요, 반갑습니다.');
      expect(m.matches('안녕하세요 반갑습니다', now: t0), isTrue);
    });

    test('띄어쓰기가 달라도 걸린다', () {
      final m = withLine('날씨가 좋다');
      expect(m.matches('날씨가좋다', now: t0), isTrue);
    });

    test('일부만 주워도 걸린다 — 마이크가 앞뒤를 놓친다', () {
      final m = withLine('오늘 날씨가 정말 좋네요 산책하기 좋겠어요');
      expect(m.matches('날씨가 정말 좋네요', now: t0), isTrue);
    });

    test('낱말 하나가 어긋나도 걸린다 — 조사가 흔들린다', () {
      final m = withLine('the weather is really nice today outside');
      expect(m.matches('the weather is really nice today outdoors', now: t0),
          isTrue);
    });

    test('대소문자는 무시한다', () {
      final m = withLine('The Weather Is Nice');
      expect(m.matches('the weather is nice', now: t0), isTrue);
    });

    test('띄어쓰기 없는 언어도 포함 관계로 잡는다', () {
      // 자카드는 낱말이 하나로 뭉쳐 쓸모없어진다. 포함 관계가 받는다.
      final m = withLine('今日はいい天気ですね');
      expect(m.matches('今日はいい天気', now: t0), isTrue);
    });

    test('한글만 훑지 않는다 — 다른 문자도 납작해진다', () {
      // `[^\w가-힣]`로 지우면 일본어·중국어·태국어가 빈 문자열이 되어
      // 이 방어선이 조용히 꺼진다.
      expect(partnerEchoNormalize('今日は、いい天気。'), '今日はいい天気');
      expect(partnerEchoNormalize('สวัสดี ครับ'), 'สวัสดีครับ');
      expect(partnerEchoNormalize('Hola, ¿qué tal?'), 'holaquétal');
    });
  });

  group('진짜 발화는 살린다', () {
    test('전혀 다른 말은 안 걸린다', () {
      final m = withLine('안녕하세요, 반갑습니다');
      expect(m.matches('점심은 뭐 드셨어요', now: t0), isFalse);
    });

    test('절반만 겹치면 안 걸린다', () {
      final m = withLine('오늘 날씨가 좋네요');
      expect(m.matches('오늘 기분이 어떠세요', now: t0), isFalse);
    });

    test('짧은 말은 대조하지 않는다', () {
      // "네"·"그럼"은 누가 해도 비슷해서 긴 문장 아무 데나 걸린다.
      // 짧은 대답을 지키는 것이 이 앱의 원칙이고, 그 판정은 소리가 한다.
      final m = withLine('네 그럼 그렇게 하시죠');
      expect(m.matches('그럼', now: t0), isFalse);
      expect(m.matches('네', now: t0), isFalse);
    });

    test('짧은 조각이 긴 문장에 박혀 있어도 안 걸린다', () {
      final m = withLine('그러면 내일 오전에 다시 만나기로 하죠');
      expect(m.matches('내일', now: t0), isFalse,
          reason: '두 글자가 긴 문장에 들어 있다고 상대 폰 소리는 아니다');
    });

    test('아무것도 못 들었으면 아무것도 안 버린다', () {
      expect(PartnerEchoMemory().matches('안녕하세요 반갑습니다', now: t0), isFalse);
    });
  });

  group('창을 벗어나면 놓아 준다', () {
    test('8초 안에는 걸린다', () {
      final m = withLine('날씨가 좋네요');
      expect(m.matches('날씨가 좋네요', now: t0.add(const Duration(seconds: 7))),
          isTrue);
    });

    test('8초를 넘기면 안 걸린다', () {
      final m = withLine('날씨가 좋네요');
      expect(m.matches('날씨가 좋네요', now: t0.add(const Duration(seconds: 9))),
          isFalse,
          reason: '창이 길수록 비슷한 진짜 발화를 지운다');
    });

    test('창 값은 8초다', () {
      expect(kPartnerEchoWindow, const Duration(seconds: 8));
    });

    test('지나간 것은 목록에서도 사라진다', () {
      final m = withLine('날씨가 좋네요');
      expect(m.length, 1);
      m.prune(now: t0.add(const Duration(seconds: 9)));
      expect(m.length, 0);
    });
  });

  group('목록은 통화 한 번짜리다', () {
    test('다섯 개까지만 들고 있는다', () {
      final m = PartnerEchoMemory();
      for (int i = 0; i < 9; i++) {
        m.note('문장 번호 $i 입니다', at: t0);
      }
      expect(m.length, kPartnerEchoMaxItems);
      // 오래된 것부터 버린다 — 최근 것이 남아야 한다.
      expect(m.matches('문장 번호 8 입니다', now: t0), isTrue);
      expect(m.matches('문장 번호 0 입니다', now: t0), isFalse);
    });

    test('비우면 아무것도 안 버린다', () {
      final m = withLine('날씨가 좋네요');
      m.clear();
      expect(m.isEmpty, isTrue);
      expect(m.matches('날씨가 좋네요', now: t0), isFalse);
    });

    test('빈 문장은 담지 않는다', () {
      final m = PartnerEchoMemory()..note('   ', at: t0);
      expect(m.isEmpty, isTrue);
    });
  });

  group('유사도 문턱', () {
    test('0.75다', () {
      expect(kPartnerEchoSimilarity, 0.75);
    });

    test('완전히 같으면 1', () {
      expect(partnerEchoJaccard('the weather is nice', 'the weather is nice'),
          1.0);
    });

    test('겹치는 게 없으면 0', () {
      expect(partnerEchoJaccard('가나 다라', 'mono rail'), 0.0);
    });

    test('빈 문자열은 0 — 나누기가 터지지 않는다', () {
      expect(partnerEchoJaccard('', '무슨 말'), 0.0);
      expect(partnerEchoJaccard('무슨 말', ''), 0.0);
      expect(partnerEchoJaccard('', ''), 0.0);
    });
  });

  // ── 위젯 배선 ───────────────────────────────────────────────────────
  group('소리 내기 직전에 상대에게 알린다', () {
    test('재생하는 갈래가 둘이고, 둘 다 알린다', () {
      // ⚠️ 2026-09-04 실기기에서 한쪽만 걸어 두고 놓쳤다. 로그에
      //   `[INTERP-TURN] incoming ... gptCalls=1`은 나오는데 `path=stream`이
      //   없었다 — 실제로 도는 갈래는 훅이 없는 쪽이었고, 알림이 한 줄도
      //   안 나갔다. 둘 다 거는 것을 여기서 못 박는다.
      expect(
          RegExp(r'_announceSpokenToPartner\(spoken\);').allMatches(duo).length,
          2,
          reason: '재생하는 자리마다 알려야 한다');
      // 내 에코 목록에 넣는 그 자리다 — 같은 문장, 같은 순간.
      expect(
          RegExp(r'_rememberGenerated\(spoken\);\n'
                  r'    // 📢 \[PARTNER-ECHO\]')
              .allMatches(duo)
              .length,
          2);
    });

    test('실기기에서 도는 갈래에 붙어 있다', () {
      // `same=$sameLang gptCalls=${sameLang ? 0 : 1}`을 찍는 쪽이 그 갈래다.
      final int live = duo.indexOf(r'same=$sameLang gptCalls=');
      expect(live, greaterThan(-1));
      final String after = duo.substring(live);
      final int announce = after.indexOf('_announceSpokenToPartner(spoken);');
      expect(announce, greaterThan(-1),
          reason: '도는 갈래에 알림이 없으면 이 방어선 전체가 죽은 코드다');
    });

    test('이미 있는 글자 채널로 보낸다 — 새 통로가 없다', () {
      final String body = _region(duo, 'void _announceSpokenToPartner(String spoken) {',
          '/// ⚠️ **직접 대화 전용으로 남은 값이다.**');
      expect(body, contains('_interpCall?.sendData('));
      expect(body, contains("'kind': kInterpDataKindSpoke,"));
    });

    test('못 보내도 큐에 쌓지 않는다 — 늦은 알림은 해롭다', () {
      final String body = _region(duo, 'void _announceSpokenToPartner(String spoken) {',
          '/// ⚠️ **직접 대화 전용으로 남은 값이다.**');
      expect(body, isNot(contains('_queueInterpPendingSend')));
    });
  });

  group('받는 쪽은 알림을 발화로 착각하지 않는다', () {
    test('알림은 그 자리에서 끝난다', () {
      final String body = _region(duo, 'void _onInterpreterData(',
          'final String key = ');
      expect(body, contains("if (payload['kind']?.toString() == "
          'kInterpDataKindSpoke) {'));
      expect(body, contains('_notePartnerSpoke(text);'));
    });

    test('번역·재생·히스토리·과금 앞에서 끊는다', () {
      final String body = _region(duo, 'void _onInterpreterData(',
          'final String key = ');
      for (final String downstream in <String>[
        '_enqueueIncoming',
        'BillingTicker',
        '_processedMsgIds',
      ]) {
        expect(body, isNot(contains(downstream)),
            reason: '$downstream 가 알림보다 앞에 있으면 알림이 발화처럼 처리된다');
      }
    });
  });

  group('에코 판정에 상대 소리가 먼저 온다', () {
    test('내 TTS 시각을 보기 전에 확인한다', () {
      // 끝 앵커를 `return false;`로 잡으면 첫 줄(`t.length < 4`)에서 잘린다.
      final String body = _region(duo, 'bool _looksLikeEcho(String transcript) {',
          'bool _looksLikePartnerEcho(');
      final int partner = body.indexOf('_looksLikePartnerEcho(t)');
      final int mine = body.indexOf('_latestTtsEnd()');
      expect(partner, greaterThan(-1));
      expect(partner, lessThan(mine),
          reason: '내가 아무 소리도 안 낸 동안 들어온 상대 소리는 그 아래까지 가지도 못한다');
    });

    test('내 TTS 에코 필터는 그대로다', () {
      expect(duo, contains('final DateTime? spokeAt = _latestTtsEnd();'));
      expect(duo, contains('for (final g in _recentGenerated) {'));
      expect(duo, contains('final bool strict = sinceTtsMs < 1200;'));
    });

    test('통역 필터가 이 판정을 쓴다', () {
      expect(duo, contains('final bool isEcho = _looksLikeEcho(trimmed);'));
      expect(duo, contains('isShortGhost || isEcho) {'));
    });
  });

  group('마이크와 문턱은 안 건드렸다', () {
    test('알림이 마이크를 닫지 않는다', () {
      final String body = _region(duo, 'void _notePartnerSpoke(String text) {',
          'void _announceSpokenToPartner(String spoken) {');
      for (final String forbidden in <String>[
        'closeAudioGate',
        '_stopInterpreterCapture',
        'InterpMicPhase',
      ]) {
        expect(body, isNot(contains(forbidden)),
            reason: '$forbidden — 게이트로 막으면 그동안의 진짜 발화가 잘린다');
      }
    });

    test('세기 문턱은 그대로 −42.0이다', () {
      expect(duo, contains('kDuoMinUtteranceRmsDbfs'));
      final String gate = _read('lib/custom_code/services/duo_transcript_gate.dart');
      expect(gate, contains('kDuoMinUtteranceRmsDbfs = -42.0'));
    });

    test('통화가 끝나면 목록을 비운다', () {
      final String body = _region(duo,
          'Future<void> _stopInterpreterCapture(String reason) async {',
          '/// 🔵 [INTERP-LIVE] 상대가 사라졌다.');
      expect(body, contains('_partnerEcho.clear();'));
    });
  });
}
