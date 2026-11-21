import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_deepgram_endpoint.dart';

/// 24kHz PCM16 mono, [ms] long. [amplitude] 0~1 (사인파).
Uint8List _tone(int ms, double amplitude) {
  final int samples = 24 * ms;
  final out = Uint8List(samples * 2);
  final view = ByteData.sublistView(out);
  for (var i = 0; i < samples; i++) {
    final v = (math.sin(2 * math.pi * 300 * i / 24000) * amplitude * 32767)
        .round();
    view.setInt16(i * 2, v, Endian.little);
  }
  return out;
}

Uint8List _silence(int ms) => Uint8List(24 * ms * 2);

DuoDeepgramEndpointSensor _sensor({bool gate = true}) =>
    DuoDeepgramEndpointSensor(
      apiKey: 'test',
      languageCode: 'en',
      silenceGate: gate,
    );

void _feed(DuoDeepgramEndpointSensor s, Uint8List chunk, int times) {
  for (var i = 0; i < times; i++) {
    s.addPcm(chunk);
  }
}

void main() {
  test('silence only: the gate stays closed and holds the audio back', () {
    final s = _sensor();
    _feed(s, _silence(40), 250); // 10초
    expect(s.gateOpenForTest, isFalse);
    expect(s.gateOpenCountForTest, 0);
    expect(s.gateSkippedBytesForTest, 250 * 40 * 48);
  });

  test('speech opens the gate; the held preroll is released first', () {
    final s = _sensor();
    _feed(s, _silence(40), 100); // 4초 무음
    _feed(s, _tone(40, 0.1), 5); // -20 dBFS 근처
    expect(s.gateOpenForTest, isTrue);
    expect(s.gateOpenCountForTest, 1);
  });

  test('the gate does not close before the utterance-end hangover', () {
    final s = _sensor();
    _feed(s, _tone(40, 0.1), 10);
    // 1.8초 무음 — Deepgram이 UtteranceEnd를 내려면 이 구간을 들어야 한다.
    _feed(s, _silence(40), kDuoUtteranceEndMs ~/ 40);
    expect(s.gateOpenForTest, isTrue);
    expect(s.gateCloseCountForTest, 0);
  });

  test('the gate closes after the hangover and reopens on the next speech', () {
    final s = _sensor();
    _feed(s, _tone(40, 0.1), 10);
    _feed(s, _silence(40), kDuoDeepgramGateHangoverMs ~/ 40 + 5);
    expect(s.gateOpenForTest, isFalse);
    expect(s.gateCloseCountForTest, 1);
    final skippedAfterClose = s.gateSkippedBytesForTest;
    _feed(s, _silence(40), 50);
    expect(s.gateSkippedBytesForTest, greaterThan(skippedAfterClose));
    _feed(s, _tone(40, 0.1), 3);
    expect(s.gateOpenForTest, isTrue);
    expect(s.gateOpenCountForTest, 2);
  });

  test('quiet room noise below the threshold never opens the gate', () {
    final s = _sensor();
    // 진폭 0.0005 ≈ -66 dBFS
    _feed(s, _tone(40, 0.0005), 500);
    expect(s.gateOpenForTest, isFalse);
  });

  test('gate off: every chunk is passed through (interpreter unchanged)', () {
    final s = _sensor(gate: false);
    _feed(s, _silence(40), 100);
    expect(s.gateSkippedBytesForTest, 0);
    expect(s.gateOpenCountForTest, 0);
  });
}
