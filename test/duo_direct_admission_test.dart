// 🎚️ [DIRECT-ADMISSION] 폰 가까이서 한 말은 들어가고, 멀리 있는 소리는 안 들어간다
//
// 2026-09-04 실기기 실측(SM-F946N, 직접통화):
//   가까이 말한 4건   rmsDbfs  -31.6 / -34.0 / -36.5 / -37.3   → 전부 통과
//   약 1m 발화 1건    rmsDbfs  -49.2                            → 버려짐
//   현재 문턱         -42.0
//
// 두 무리가 12~18dB 벌어졌고 문턱이 정확히 그 사이에 있다. **그래서 지금은
// 문턱을 옮기지 않는다.** SNR·적응형 바닥·기기별 보정은 만들지 않는다 —
// 같은 실측에서 snrDb는 근거리 1.3~8.5, 1m 3.6으로 **완전히 겹쳤다.**
//
// 이 파일은 그 기본값과, 근거리 짧은 대답이 살아남는 조건을 지킨다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_transcript_gate.dart';

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

  // ==========================================================================
  group('기본값을 지킨다', () {
    test('문턱은 -42.0 그대로다', () {
      expect(kDuoMinUtteranceRmsDbfs, -42.0,
          reason: '실측에서 근거리(-31~-37)와 1m(-49) 사이에 정확히 있다');
    });

    test('최소 길이는 150ms 그대로다', () {
      expect(duo, contains('static const int kDuoMinVoicedMs = 150;'));
    });

    test('게이트는 절대 세기 하나만 본다', () {
      final String body =
          _region(gate, 'bool belowLevelGate(', 'class DuoUtteranceRmsMeter');
      for (final String notYet in <String>['noiseFloor', 'snr', 'adaptive']) {
        expect(body, isNot(contains(notYet)),
            reason: '$notYet 기반 판정은 이번에 만들지 않는다');
      }
    });

    test('기기별 보정이 없다', () {
      // 기종 문자열이 **실행되는 줄**에 나타나면 그 순간 휴리스틱이 된다.
      // 주석에 실측 기기를 적는 것은 근거를 남기는 것이라 다른 일이다.
      final String code = duo
          .split('\n')
          .where((l) {
            final t = l.trimLeft();
            return !t.startsWith('//') && !t.startsWith('///');
          })
          .join('\n');
      for (final String forbidden in <String>[
        'ro.product.model',
        'SM-F946',
        'SM-S931',
        'Build.MODEL',
      ]) {
        expect(code, isNot(contains(forbidden)),
            reason: '몇 대 폰에 맞춘 휴리스틱으로 빠지는 길이다');
      }
    });
  });

  // ==========================================================================
  group('근거리 짧은 대답이 살아남는다', () {
    test('직접통화 글자 필터에 길이 규칙이 없다', () {
      // "네" · "응" · "맞아"가 길이 때문에 잘리면 안 된다.
      final String body =
          _region(gate, 'String? noiseTranscriptReason(', '/// 🔉 발화 구간 평균 세기의 문턱(dBFS)');
      expect(body, isNot(contains('length <')));
      expect(body, isNot(contains('length <=')));
    });

    test('버리는 사유가 셋뿐이다 — 빈 글자·정리 후 빈 글자·고정 환청', () {
      final String body =
          _region(gate, 'String? noiseTranscriptReason(', '/// 🔉 발화 구간 평균 세기의 문턱(dBFS)');
      expect(body, contains('DuoDropReason.emptyText'));
      expect(body, contains('DuoDropReason.emptyAfterClean'));
      expect(body, contains('DuoDropReason.hardGhost'));
    });

    test('직접통화가 그 필터를 쓴다', () {
      expect(duo, contains('final String? noiseReason = noiseTranscriptReason(trimmed);'));
    });

    test('세기는 서버가 들은 앞소리까지 포함해 잰다', () {
      // 서버 VAD가 prefix_padding_ms만큼 앞을 이미 쓰므로, 우리도 같은
      // 구간을 봐야 "서버가 들은 소리"와 "우리가 잰 소리"가 같아진다.
      // 이게 없으면 앞이 잘려 RMS가 낮게 나오고 근거리 발화가 버려진다.
      final String body =
          _region(gate, 'void beginUtterance()', 'void addPcm(');
      expect(body, contains('for (final chunk in _preRoll)'));
      expect(kDuoRmsPreRollMs, greaterThanOrEqualTo(300),
          reason: '서버 prefix_padding_ms(300)보다 짧으면 앞소리를 놓친다');
    });

    test('너무 짧게 잰 구간으로는 버리지 않는다', () {
      // 잰 창이 짧으면 null을 돌려주고, null은 통과다 — 모르는 것으로
      // 사람 말을 버리지 않는다.
      final String body =
          _region(gate, 'double? commitUtterance(', 'double? rmsDbfsOf(');
      expect(body, contains('if (samples < _minWindowSamples) return null;'));
      final String lvl = _region(gate, 'bool belowLevelGate(', 'class DuoUtteranceRmsMeter');
      expect(lvl, contains('null'), reason: 'null을 버리는 쪽으로 읽으면 안 된다');
    });
  });

  // ==========================================================================
  group('소켓 문제와 세기 문제가 로그에서 갈린다', () {
    test('버린 이유가 사유별로 남는다', () {
      expect(duo, contains('reason=\${DuoDropReason.lowLevel}'));
      expect(duo, contains('reason=\${DuoDropReason.voicedMs}'));
    });

    test('세기는 받아들이든 버리든 남는다', () {
      expect(duo, contains("'[DIRECT-LEVEL]'"),
          reason: '버린 것만 남기면 근거리/원거리 분포를 못 본다');
    });

    test('소켓 사고는 다른 태그로 남는다', () {
      // `[STREAM-STT] socket_lost` / `reconnect_gave_up`은 전사 세션 쪽이다.
      // 이걸 세기 문제로 읽으면 엉뚱한 문턱을 만지게 된다.
      final String stt =
          _read('lib/custom_code/services/openai_streaming_transcribe_session.dart');
      expect(stt, contains('socket_lost'));
      expect(stt, contains('reconnect_gave_up'));
      expect(stt, isNot(contains('lowLevel')),
          reason: '두 사고가 같은 태그를 쓰면 실기기에서 못 가린다');
    });
  });
}
