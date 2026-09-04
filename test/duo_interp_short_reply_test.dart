// 🗣️ [INTERP-LEN] 통역도 짧은 대답을 버리지 않는다
//
// `trimmed.length <= 2`가 통역 필터에만 있었다. "네"·"응"·"왜"(1자)와
// "맞아"·"그래"(2자)를 통째로 버렸다 — 통역에서 가장 흔한 대답들이다.
//
// 같은 규칙이 직접 대화에는 없다. 한 앱의 두 모드가 다른 정책을 쓰고 있었고,
// 통역 쪽이 2026-08-28에 못 박은 원칙을 어기고 있었다
// ([[duo-history-cleanup-principle]] — "글자 수·단어 목록 기반 규칙 금지").
//
// 짧은 대답과 환청을 가르는 것은 글자 수가 아니라 **소리 난 시간과 세기**다.
// 그 판정은 두 모드가 같은 함수·같은 상수로 이미 한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _duo = 'lib/custom_code/widgets/routine_mode_duo.dart';
const String _gate = 'lib/custom_code/services/duo_transcript_gate.dart';

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
  final String gate = _read(_gate);

  /// 통역이 전사문을 버릴지 정하는 구역.
  String interpFilter() => _region(
      duo, 'final bool isEcho = _looksLikeEcho(trimmed);', 'await _processRelayPipeline(');

  group('글자 수로 버리지 않는다', () {
    test('길이 조건이 사라졌다', () {
      // 주석은 세지 않는다 — 왜 지웠는지 설명하려면 그 문자열을 적어야 한다.
      final String code = duo
          .split('\n')
          .where((l) {
            final t = l.trimLeft();
            return !t.startsWith('//') && !t.startsWith('///');
          })
          .join('\n');
      expect(code, isNot(contains('trimmed.length <= 2')),
          reason: '"네"·"맞아"가 이 한 줄에 걸려 버려졌다');
    });

    test('버리는 조건이 넷뿐이다 — 빈 글자·고정 환청·짧은 환청·에코', () {
      final String body = interpFilter();
      expect(
          body,
          contains('if (lowerClean.isEmpty || isHardGhost || '
              'isShortGhost || isEcho) {'));
    });

    test('실행되는 줄 어디에도 길이 비교가 없다', () {
      final String code = interpFilter()
          .split('\n')
          .where((l) {
            final t = l.trimLeft();
            return !t.startsWith('//') && !t.startsWith('///');
          })
          .join('\n');
      for (final String len in <String>[
        'trimmed.length <',
        'trimmed.length >',
        'trimmed.length ==',
      ]) {
        expect(code, isNot(contains(len)), reason: '$len 이 남아 있다');
      }
    });

    test('왜 지웠는지 코드 옆에 적어 뒀다', () {
      // 다음 사람이 "짧은 게 자꾸 들어온다"며 다시 넣는 것을 막는다.
      expect(duo, contains('🚫 [LEN] **글자 수로 버리지 않는다.**'));
      expect(duo, contains('소리 난 시간과'));
    });
  });

  group('두 모드가 같은 정책을 쓴다', () {
    test('직접 대화에도 길이 규칙이 없다', () {
      final String body = _region(
          gate, 'String? noiseTranscriptReason(', '/// 🔉 발화 구간 평균 세기의 문턱(dBFS)');
      expect(body, isNot(contains('length <')));
    });

    test('가르는 것은 두 모드 다 소리다', () {
      // 같은 함수·같은 상수를 두 곳에서 부른다.
      expect(RegExp(r'belowVoicedGate\(voicedMs, minMs: kDuoMinVoicedMs\)')
          .allMatches(duo)
          .length,
          greaterThanOrEqualTo(2));
      expect(RegExp(r'belowLevelGate\(rmsDbfs, minDbfs: kDuoMinUtteranceRmsDbfs\)')
          .allMatches(duo)
          .length,
          greaterThanOrEqualTo(2));
    });
  });

  group('나머지 방어선은 그대로다', () {
    test('고정 환청 목록이 살아 있다', () {
      expect(duo, contains("'시청해 주셔서'"));
      expect(duo, contains("'thank you for watching'"));
    });

    test('에코 필터가 살아 있다', () {
      expect(interpFilter(), contains('isEcho'));
      expect(duo, contains('bool _looksLikeEcho(String transcript)'));
    });

    test('잘린 발화는 여전히 버린다', () {
      // 통역은 재생 시작이 말하던 중의 버퍼를 강제 확정시킨다. 그때
      // voicedMs를 못 재면 "모른다"가 아니라 "잘렸다"는 뜻이다.
      expect(duo, contains('unmeasured_truncation'));
    });

    test('버린 이유를 로그에서 가릴 수 있다', () {
      final String body = interpFilter();
      expect(body, contains('empty='));
      expect(body, contains('ghost='));
      expect(body, contains('echo='));
    });
  });
}
