// 🔉 [DUO-LEVEL] 발화 세기로 환청을 거르는 게이트를 지키는 시험.
//
// 이 게이트가 생긴 근거는 2026-08-30 실기기 두 통(SM-S931N)이다.
//   확실한 실제 발화  −23.3 ~ −25.9 dBFS   10건, 전사 전부 정확
//   중간(판단 보류)    −29.1 dBFS          1건
//   확실한 환청       −44.7 ~ −50.4 dBFS   10건, 전사 전부 엉터리
// 길이로는 하나도 못 갈랐다 — 환청이 전부 1.3~2.0초였다.
//
// 여기서 지키는 것은 두 가지다.
//   ① 문턱 −35 dBFS의 경계 동작이 흔들리지 않는다
//   ② 세기 계측이 **통화 PCM과 완전히 독립**이다 (게이트가 목소리를 막지 않는다)

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_direct_audio.dart';
import 'package:stealth_vox/custom_code/services/duo_transcript_gate.dart';
import 'package:stealth_vox/custom_code/services/pcm_audio_utils.dart';

/// 원하는 세기(dBFS)의 사인파 한 조각. RMS가 정확히 그 값이 되게 만든다.
///
/// 사인파의 RMS는 진폭÷√2이므로, 목표 선형세기에 √2를 곱한 진폭을 쓴다.
Uint8List toneAt(double dbfs, {int ms = 100}) {
  final int samples = ms * kStealthVoxSttSampleRate ~/ 1000;
  final double linear = math.pow(10, dbfs / 20).toDouble();
  final double amp = linear * math.sqrt2;
  final data = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    final double t = i / kStealthVoxSttSampleRate;
    final double v = math.sin(2 * math.pi * 220 * t) * amp;
    data.setInt16(
        i * 2, (v * 32767).round().clamp(-32768, 32767), Endian.little);
  }
  return data.buffer.asUint8List();
}

/// 한 발화를 통째로 흘려 넣고 확정된 세기를 돌려준다.
double? measureUtterance(DuoUtteranceRmsMeter meter, double dbfs,
    {String itemId = 'item_a', int frames = 5}) {
  meter.beginUtterance();
  for (var i = 0; i < frames; i++) {
    meter.addPcm(toneAt(dbfs));
  }
  return meter.commitUtterance(itemId);
}

void main() {
  group('세기 계산이 실제 dBFS와 맞는가', () {
    test('넣은 세기가 그대로 나온다 (±0.5dB)', () {
      for (final double target in <double>[-23.3, -29.1, -35.0, -45.0]) {
        final meter = DuoUtteranceRmsMeter();
        final double? got = measureUtterance(meter, target);
        expect(got, isNotNull);
        expect((got! - target).abs(), lessThan(0.5),
            reason: '$target dBFS를 넣었는데 $got 이 나왔다');
      }
    });

    test('게이트와 진단기가 같은 식을 쓴다', () {
      // 두 벌이면 로그의 −34.9와 판정의 −35.1이 같은 소리를 가리키게 된다.
      expect(pcm16LinearToDbfs(1.0), closeTo(0.0, 0.001));
      expect(pcm16LinearToDbfs(0.1), closeTo(-20.0, 0.001));
      expect(pcm16LinearToDbfs(0.0), -160.0);
    });
  });

  group('문턱 −35 dBFS — 경계를 못 박는다', () {
    const double t = kDuoMinUtteranceRmsDbfs;

    test('문턱 상수가 −35.0이다', () {
      expect(t, -35.0);
    });

    test('−25 dBFS 실제 발화는 통과한다', () {
      expect(belowLevelGate(-25.0, minDbfs: t), isFalse);
    });

    test('−29 dBFS 애매한 발화도 통과한다 — 살리는 쪽이다', () {
      expect(belowLevelGate(-29.0, minDbfs: t), isFalse);
      expect(belowLevelGate(-29.1, minDbfs: t), isFalse);
    });

    test('−34.9 dBFS는 통과한다', () {
      expect(belowLevelGate(-34.9, minDbfs: t), isFalse);
    });

    test('−35.0 dBFS 정확히 문턱이면 **통과**한다 (미만일 때만 버린다)', () {
      expect(belowLevelGate(-35.0, minDbfs: t), isFalse,
          reason: '경계값 포함 여부가 흔들리면 같은 소리가 통마다 다르게 판정된다');
    });

    test('−35.1 dBFS는 버린다', () {
      expect(belowLevelGate(-35.1, minDbfs: t), isTrue);
    });

    test('−45 dBFS는 버린다', () {
      expect(belowLevelGate(-45.0, minDbfs: t), isTrue);
    });

    test('실기기 실측값이 의도대로 갈린다', () {
      // 실제 발화 10건 — 하나도 버리지 않는다.
      for (final double real in <double>[
        -23.2, -23.3, -23.3, -23.5, -23.8, -23.8, -24.0, -24.1, -25.6, -25.9,
      ]) {
        expect(belowLevelGate(real, minDbfs: t), isFalse, reason: '$real');
      }
      // 애매한 1건 — 살린다.
      expect(belowLevelGate(-29.1, minDbfs: t), isFalse);
      // 환청 10건 — 전부 버린다.
      for (final double ghost in <double>[
        -42.5, -44.7, -45.0, -45.8, -46.0, -46.8, -47.3, -47.7, -48.7, -50.4,
      ]) {
        expect(belowLevelGate(ghost, minDbfs: t), isTrue, reason: '$ghost');
      }
    });

    test('세기를 모르면(null) 통과시킨다 — 모르는 것으로 사람 말을 버리지 않는다', () {
      expect(belowLevelGate(null, minDbfs: t), isFalse);
    });
  });

  group('DuoUtteranceRmsMeter — 누적과 초기화', () {
    test('발화마다 새로 센다 — 앞 발화의 세기가 섞이지 않는다', () {
      final meter = DuoUtteranceRmsMeter();
      final double? loud = measureUtterance(meter, -23.0, itemId: 'a');
      final double? quiet = measureUtterance(meter, -46.0, itemId: 'b');
      expect((loud! + 23.0).abs(), lessThan(0.5));
      expect((quiet! + 46.0).abs(), lessThan(0.5),
          reason: '앞의 큰 발화가 섞였으면 이 값이 −46보다 훨씬 커진다');
    });

    test('speech_started 없이 온 committed는 앞 발화 값을 물려주지 않는다', () {
      final meter = DuoUtteranceRmsMeter();
      measureUtterance(meter, -23.0, itemId: 'a');
      // 시작을 못 본 채 조각만 들어오고 확정이 온 경우.
      meter.addPcm(toneAt(-23.0));
      expect(meter.commitUtterance('b'), isNull);
      expect(meter.rmsDbfsOf('b'), isNull,
          reason: '모르는 발화가 앞 발화의 세기로 통과하면 게이트가 있으나 마나다');
      // 그래도 앞 발화의 값은 그대로 남아 있어야 한다.
      expect(meter.rmsDbfsOf('a'), isNotNull);
    });

    test('reconnect 뒤 누적 상태가 다음 발화에 섞이지 않는다', () {
      final meter = DuoUtteranceRmsMeter();
      meter.beginUtterance();
      meter.addPcm(toneAt(-10.0)); // 끊기기 직전의 큰 소리
      meter.reset(); // ← 재접속
      expect(meter.isActive, isFalse);
      expect(meter.trackedItems, 0);

      final double? after = measureUtterance(meter, -46.0, itemId: 'c');
      expect((after! + 46.0).abs(), lessThan(0.5),
          reason: '끊기기 전 −10dB가 남아 있으면 이 발화가 통과해 버린다');
    });

    test('reset은 확정된 장부까지 비운다', () {
      final meter = DuoUtteranceRmsMeter();
      measureUtterance(meter, -23.0, itemId: 'a');
      expect(meter.rmsDbfsOf('a'), isNotNull);
      meter.reset();
      expect(meter.rmsDbfsOf('a'), isNull);
    });

    test('completed와 done이 두 번 와도 두 번 다 세기를 안다', () {
      // 읽으면서 지우면 두 번째가 세기를 모른 채 게이트를 통과한다.
      final meter = DuoUtteranceRmsMeter();
      measureUtterance(meter, -46.0, itemId: 'a');
      expect(meter.rmsDbfsOf('a'), isNotNull);
      expect(meter.rmsDbfsOf('a'), isNotNull);
    });

    test('소리가 한 조각도 없던 발화는 모르는 것으로 둔다', () {
      final meter = DuoUtteranceRmsMeter();
      meter.beginUtterance();
      expect(meter.commitUtterance('a'), isNull);
      expect(meter.rmsDbfsOf('a'), isNull);
    });

    test('빈 item_id는 담지 않는다', () {
      final meter = DuoUtteranceRmsMeter();
      meter.beginUtterance();
      meter.addPcm(toneAt(-23.0));
      expect(meter.commitUtterance(''), isNull);
      expect(meter.trackedItems, 0);
    });

    test('장부는 상한을 넘게 자라지 않는다', () {
      final meter = DuoUtteranceRmsMeter(maxTrackedItems: 4);
      for (var i = 0; i < 10; i++) {
        measureUtterance(meter, -23.0, itemId: 'item_$i');
      }
      expect(meter.trackedItems, 4);
      expect(meter.rmsDbfsOf('item_0'), isNull);
      expect(meter.rmsDbfsOf('item_9'), isNotNull);
    });

    test('누적하지 않는 동안 들어온 조각은 무시한다', () {
      final meter = DuoUtteranceRmsMeter();
      meter.addPcm(toneAt(-10.0));
      expect(meter.isActive, isFalse);
      final double? got = measureUtterance(meter, -46.0, itemId: 'a');
      expect((got! + 46.0).abs(), lessThan(0.5));
    });
  });

  group('통화 PCM과 완전히 독립이다', () {
    test('세기 계측이 통째로 없어도 통화·전사 PCM은 그대로 간다', () {
      final call = <Uint8List>[];
      final stt = <Uint8List>[];
      final fanout = DuoMicPcmFanout(
        speakerRole: 'HOST',
        toCall: call.add,
        toStt: stt.add,
        // toLevel 없음 = release에서 계측기가 없는 상황
      );
      fanout.add(toneAt(-46.0));
      expect(call.length, 1);
      expect(stt.length, 1);
      expect(fanout.levelFrames, 0);
    });

    test('아주 조용한 소리도 릴레이로는 그대로 나간다', () {
      // 🚫 게이트는 **저장 여부**에만 관여한다. 사람이 낸 소리는 세기와
      //    무관하게 상대에게 들려야 한다.
      final call = <Uint8List>[];
      final level = <Uint8List>[];
      final meter = DuoUtteranceRmsMeter();
      final fanout = DuoMicPcmFanout(
        speakerRole: 'HOST',
        toCall: call.add,
        toStt: (_) {},
        toLevel: (b) {
          level.add(b);
          meter.addPcm(b);
        },
      );
      meter.beginUtterance();
      for (var i = 0; i < 5; i++) {
        fanout.add(toneAt(-50.0));
      }
      final double? rms = meter.commitUtterance('a');

      // 전사는 버려질 세기다…
      expect(belowLevelGate(rms, minDbfs: kDuoMinUtteranceRmsDbfs), isTrue);
      // …그래도 통화 PCM은 다섯 조각 전부 나갔다.
      expect(call.length, 5);
      expect(fanout.callBytes, greaterThan(0));
      expect(level.length, 5);
    });

    test('계측기가 던져도 통화·전사는 이미 지나간 뒤다', () {
      final call = <Uint8List>[];
      final stt = <Uint8List>[];
      final fanout = DuoMicPcmFanout(
        speakerRole: 'HOST',
        toCall: call.add,
        toStt: stt.add,
        toLevel: (_) => throw StateError('meter blew up'),
      );
      fanout.add(toneAt(-23.0));
      fanout.add(toneAt(-23.0));
      expect(call.length, 2);
      expect(stt.length, 2);
      expect(fanout.levelErrors, 2);
      expect(fanout.levelFrames, 0);
    });

    test('A/B 진단기가 꺼져 있어도 세기 계측은 돈다', () {
      // release가 정확히 이 상태다 — toProbe는 아무것도 안 하고 toLevel만 산다.
      final level = <Uint8List>[];
      final fanout = DuoMicPcmFanout(
        speakerRole: 'HOST',
        toCall: (_) {},
        toStt: (_) {},
        toLevel: level.add,
        // toProbe 없음
      );
      fanout.add(toneAt(-23.0));
      expect(level.length, 1);
      expect(fanout.levelFrames, 1);
      expect(fanout.probeFrames, 0);
    });

    test('전사 게이트가 닫혀 있어도 세기는 이어 잰다', () {
      final level = <Uint8List>[];
      final stt = <Uint8List>[];
      final fanout = DuoMicPcmFanout(
        speakerRole: 'HOST',
        toCall: (_) {},
        toStt: stt.add,
        toLevel: level.add,
        isSttOpen: () => false,
      );
      fanout.add(toneAt(-23.0));
      expect(stt, isEmpty);
      expect(level.length, 1);
    });

    test('음소거 중에는 세기도 재지 않는다', () {
      // 음소거는 내 소리를 안 보내는 것이다. 잴 발화 자체가 없다.
      final level = <Uint8List>[];
      final fanout = DuoMicPcmFanout(
        speakerRole: 'HOST',
        toCall: (_) {},
        toStt: (_) {},
        toLevel: level.add,
        isMuted: () => true,
      );
      fanout.add(toneAt(-23.0));
      expect(level, isEmpty);
    });
  });

  group('두 게이트의 사유가 서로 구분된다', () {
    test('voiced_ms와 low_level은 다른 이름이다', () {
      expect(DuoDropReason.voicedMs, 'voiced_ms');
      expect(DuoDropReason.lowLevel, 'low_level');
      expect(DuoDropReason.voicedMs, isNot(DuoDropReason.lowLevel));
    });

    test('짧지만 큰 소리는 길이에서만 걸린다', () {
      expect(belowVoicedGate(44, minMs: 150), isTrue);
      expect(belowLevelGate(-23.0, minDbfs: kDuoMinUtteranceRmsDbfs), isFalse);
    });

    test('길지만 조용한 소리는 세기에서만 걸린다 — 실기기 환청이 전부 이 모양이다', () {
      // 2026-08-30 실측: 환청 10건이 1364~1972ms였다. 길이 게이트는 무력했다.
      for (final int ms in <int>[1364, 1428, 1520, 1680, 1972]) {
        expect(belowVoicedGate(ms, minMs: 150), isFalse,
            reason: '${ms}ms는 길이로 못 거른다');
      }
      expect(belowLevelGate(-46.0, minDbfs: kDuoMinUtteranceRmsDbfs), isTrue);
    });
  });
}
