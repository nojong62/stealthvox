import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'pcm_audio_utils.dart';

// ====================================================================
// 🧪 [DUO-INJECT] 시험 전용: 직접통화 마이크 대신 소리 파일을 흘려 넣는다
// --------------------------------------------------------------------
// 사람 둘 없이 긴 직접통화(10분 분할 등)를 실기기로 돌리기 위한 장치다.
// `--dart-define=DUO_PCM_INJECT=true` 빌드에서만 켜진다. 기본은 꺼짐이고,
// 이 파일은 시험 브랜치(test/duo-pcm-inject)에만 있다 — main에 넣지 않는다.
//
// 자리: `DuoMicPcmFanout.add` 하나. 그 뒤(전사·Deepgram 게이트·원본 소리
// 보관·통화 후 재전사)는 실제 마이크와 완전히 같은 길을 탄다.
// 파일은 24kHz·16bit·mono raw PCM 자산. 파일이 끝나면 실제 마이크로 돌아간다.
// ====================================================================

const bool kDuoPcmInject =
    bool.fromEnvironment('DUO_PCM_INJECT', defaultValue: false);

String duoPcmInjectAssetFor(String role) => role.toUpperCase() == 'HOST'
    ? 'assets/test_inject/duo_host.pcm'
    : 'assets/test_inject/duo_guest.pcm';

class DuoPcmInjector {
  DuoPcmInjector({
    required this.asset,
    required this.onPcm,
    this.onLog,
    this.sampleRate = kStealthVoxSttSampleRate,
    this.frameMs = 20,
  });

  final String asset;
  final void Function(Uint8List pcm) onPcm;
  final void Function(String tag, String msg)? onLog;
  final int sampleRate;
  final int frameMs;

  Uint8List? _data;
  Timer? _timer;
  final Stopwatch _clock = Stopwatch();
  int _pos = 0;
  bool _done = false;

  /// 참이면 실제 마이크 조각을 버린다(파일이 대신 들어가는 중).
  bool get replacingMic => _timer != null && !_done;

  Future<bool> start() async {
    try {
      final bd = await rootBundle.load(asset);
      _data = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
    } catch (e) {
      onLog?.call('⚠️ [DUO-INJECT]', 'asset_missing $asset (${e.runtimeType})');
      return false;
    }
    _clock
      ..reset()
      ..start();
    _timer = Timer.periodic(Duration(milliseconds: frameMs), (_) => _tick());
    onLog?.call('🧪 [DUO-INJECT]',
        'started asset=$asset bytes=${_data!.length} '
            'sec=${_data!.length ~/ (sampleRate * 2)}');
    return true;
  }

  void _tick() {
    final data = _data;
    if (data == null || _done) return;
    final int frameBytes = sampleRate * 2 * frameMs ~/ 1000;
    // 벽시계 기준으로 따라잡는다 — 타이머가 밀려도 실시간 속도를 지킨다.
    final int target =
        (_clock.elapsedMilliseconds * sampleRate * 2 ~/ 1000) & ~1;
    while (_pos < target && _pos < data.length) {
      final int end = math.min(_pos + frameBytes, data.length);
      onPcm(Uint8List.fromList(Uint8List.sublistView(data, _pos, end)));
      _pos = end;
    }
    if (_pos >= data.length) {
      _done = true;
      _timer?.cancel();
      onLog?.call('🧪 [DUO-INJECT]', 'finished — 실제 마이크로 돌아간다');
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _clock.stop();
  }
}
