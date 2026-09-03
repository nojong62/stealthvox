// 🔎 [LEVEL] 발화 세기와 환경 바닥을 **재기만** 한다
//
// 지금까지 직접통화는 **버린 발화의 세기만** 남겼다(`[DUO-DROP]`). 그래서
// "가까운 목소리는 몇 dBFS이고 먼 소리는 몇인가"를 알 방법이 없었고, 문턱을
// 고치려면 감으로 해야 했다. 몇 대 폰의 숫자에 맞춘 휴리스틱으로 빠지는
// 길이 거기서 열린다.
//
// 그래서 세 값을 받아들이든 버리든 남긴다:
//   rmsDbfs    발화 구간의 평균 세기
//   floorDbfs  그 발화가 시작될 때의 환경 바닥
//   snrDb      바닥 위로 얼마나 솟았나 (rms − floor)
//
// 🚫 **아무것도 가르지 않는다.** `kDuoMinUtteranceRmsDbfs = -42.0` 절대
//   문턱은 그대로 쓰이고, 이 숫자들은 게이트에 닿지 않는다. 상대 문턱으로
//   옮길지는 실기기 데이터가 쌓인 뒤에 정한다.

import 'dart:io';
import 'dart:typed_data';

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

/// 진폭 [amp]짜리 PCM16 조각. 24kHz 기준 [ms] 길이.
Uint8List _pcm(double amp, int ms) {
  final int samples = 24000 * ms ~/ 1000;
  final bytes = Uint8List(samples * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < samples; i++) {
    // 부호를 번갈아 주어 평균이 아니라 세기가 잡히게 한다.
    final int v = ((i.isEven ? amp : -amp) * 32767).round();
    view.setInt16(i * 2, v, Endian.little);
  }
  return bytes;
}

void main() {
  final String duo = _read(_duo);
  final String gate = _read(_gate);

  // ==========================================================================
  group('바닥을 실제로 잰다', () {
    test('조용한 구간만 모아 바닥을 낸다', () {
      final m = DuoUtteranceRmsMeter();
      m.addPcm(_pcm(0.001, 1000)); // 아주 조용한 1초
      final floor = m.idleFloorDbfs;
      expect(floor, isNotNull);
      expect(floor!, lessThan(-50), reason: '조용한 소리가 큰 값으로 나오면 안 된다');
    });

    test('아무것도 안 들어오면 0이 아니라 null이다', () {
      expect(DuoUtteranceRmsMeter().idleFloorDbfs, isNull,
          reason: '모르는 것을 0으로 적으면 다음 사람이 진짜 0으로 읽는다');
    });

    test('발화 중에는 바닥이 얼어붙는다', () {
      final m = DuoUtteranceRmsMeter();
      m.addPcm(_pcm(0.001, 1000)); // 조용
      final before = m.idleFloorDbfs!;
      m.beginUtterance();
      m.addPcm(_pcm(0.5, 500)); // 큰 소리로 말한다
      expect(m.idleFloorDbfs, closeTo(before, 0.01),
          reason: '말소리가 바닥에 섞이면 바닥이 아니다');
    });

    test('발화별로 바닥과 SNR이 묶인다', () {
      final m = DuoUtteranceRmsMeter();
      m.addPcm(_pcm(0.001, 1000));
      m.beginUtterance();
      m.addPcm(_pcm(0.2, 500));
      final rms = m.commitUtterance('item-a');
      expect(rms, isNotNull);
      final floor = m.noiseFloorDbfsOf('item-a');
      final snr = m.snrDbOf('item-a');
      expect(floor, isNotNull);
      expect(snr, isNotNull);
      expect(snr!, closeTo(rms! - floor!, 0.01));
      expect(snr, greaterThan(20), reason: '가까운 말은 바닥보다 한참 위여야 한다');
    });

    test('바닥을 모르면 SNR도 null이다', () {
      final m = DuoUtteranceRmsMeter();
      m.beginUtterance(); // 조용한 구간을 한 번도 못 봤다
      m.addPcm(_pcm(0.2, 500));
      m.commitUtterance('item-b');
      expect(m.noiseFloorDbfsOf('item-b'), isNull);
      expect(m.snrDbOf('item-b'), isNull);
    });

    test('reset이 바닥까지 비운다', () {
      final m = DuoUtteranceRmsMeter();
      m.addPcm(_pcm(0.001, 1000));
      m.beginUtterance();
      m.addPcm(_pcm(0.2, 500));
      m.commitUtterance('item-c');
      m.reset();
      expect(m.idleFloorDbfs, isNull);
      expect(m.noiseFloorDbfsOf('item-c'), isNull);
      expect(m.snrDbOf('item-c'), isNull);
    });
  });

  // ==========================================================================
  group('재기만 하고 아무것도 가르지 않는다', () {
    test('절대 문턱 값은 그대로다', () {
      expect(kDuoMinUtteranceRmsDbfs, -42.0,
          reason: '이번 작업은 계측이다. 문턱을 옮기는 것이 아니다');
    });

    test('게이트가 바닥이나 SNR을 보지 않는다', () {
      final String body =
          _region(gate, 'bool belowLevelGate(', 'class DuoUtteranceRmsMeter');
      expect(body, isNot(contains('noiseFloor')));
      expect(body, isNot(contains('snr')));
    });

    test('직접통화 게이트 조건이 안 바뀌었다', () {
      expect(duo, contains('belowVoicedGate(voicedMs, minMs: kDuoMinVoicedMs)'));
      expect(duo, contains('belowLevelGate(rmsDbfs, minDbfs: kDuoMinUtteranceRmsDbfs)'));
    });

    test('바닥은 판정에 쓰지 않는다고 코드에 적혀 있다', () {
      expect(gate, contains('**판정에 쓰지 않는다.**'));
    });
  });

  // ==========================================================================
  group('로그가 받아들인 발화도 남긴다', () {
    test('직접통화에 계측 줄이 생겼다', () {
      expect(duo, contains("'[DIRECT-LEVEL]'"));
    });

    test('게이트보다 먼저 찍는다 — 버려도 숫자가 남는다', () {
      final int level = duo.indexOf("'[DIRECT-LEVEL]'");
      final int gateAt =
          duo.indexOf('belowVoicedGate(voicedMs, minMs: kDuoMinVoicedMs)', level - 3000);
      expect(level, greaterThan(-1));
      expect(gateAt, greaterThan(level),
          reason: '게이트 뒤에 찍으면 버린 발화의 숫자가 또 안 남는다');
    });

    test('세 값이 모두 실린다', () {
      for (final String key in <String>['rmsDbfs=', 'floorDbfs=', 'snrDb=']) {
        expect(duo, contains(key), reason: '$key 이 로그에 없다');
      }
    });

    test('통역도 같은 세 값을 남긴다 — 두 경로를 나란히 읽는다', () {
      final String body =
          _region(duo, "'[INTERP-LEVEL]'", 'if (belowVoicedGate(');
      expect(body, contains('rmsDbfs='));
      expect(body, contains('floorDbfs='));
      expect(body, contains('snrDb='));
    });

    test('글자를 싣지 않는다 — 로그가 대화록이 되면 안 된다', () {
      final String body = _region(duo, "'[DIRECT-LEVEL]'", 'belowVoicedGate(');
      expect(body, isNot(contains('text=')));
      expect(body, contains('len='), reason: '길이만 남긴다');
    });

    test('못 잰 값은 n/a로 적는다', () {
      expect(duo, contains("v == null ? 'n/a' : v.toStringAsFixed(1)"),
          reason: '못 잰 것과 0dB이 로그에서 섞이면 안 된다');
    });
  });
}
