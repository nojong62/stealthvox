// ====================================================================
// 🎙️ [DUO-MIC-TAP] WebRTC가 잡은 마이크 PCM을 전사 갈래로 받는 통로
// --------------------------------------------------------------------
// 직접 대화의 마이크는 이제 **하나뿐이다.**
//
//   flutter_webrtc AudioRecord (1개)
//        ├─→ WebRTC 통화        (네이티브 파이프라인 그대로)
//        └─→ 이 클래스 → DuoMicPcmFanout → STT / RMS / 진단
//
// 예전에는 `record` 패키지가 두 번째 AudioRecord를 열었다. 같은 앱에서 둘이
// 경합하면 안드로이드는 오류 없이 한쪽에 무음만 내보내고 하드웨어 AEC도 한쪽
// 세션에만 붙는다(제조사마다 다르다). 그 구조를 없애는 것이 이 파일의 목적이다.
//
// 🚫 **만능 통역은 이 통로를 쓰지 않는다.** 거기는 원음을 보내지 않으므로
//   WebRTC 자체가 돌지 않고, 마이크는 기존 `PreparedAudioCapture` 그대로다.
//
// 규격: 네이티브에서 이미 48k→24k 변환과 모노 합치기를 마친
//   **PCM16 / 24000Hz / mono little-endian**이 온다. Dart 쪽에서 다시 만지지
//   않는다 — 팬아웃 이후 경로가 지금과 똑같아야 하기 때문이다.
// ====================================================================

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'pcm_audio_utils.dart';

/// 네이티브 `DuoWebrtcMicTap`과 짝이 되는 채널 이름.
const String kDuoMicTapMethodChannel = 'stealthvox/duo_mic_tap';
const String kDuoMicTapEventChannel = 'stealthvox/duo_mic_tap/pcm';

/// 이 통로로 오는 PCM의 규격. 앱 전체 STT 샘플레이트와 **같아야** 한다.
const int kDuoMicTapSampleRate = kStealthVoxSttSampleRate;

/// 전사에 들어간 PCM의 출처. 저장 문서(`source`)와 진단 로그가 같은 값을 쓴다.
///
/// ⚠️ `local_mic`과 **구분해서 남긴다.** 둘 다 이 단말의 마이크지만 잡은
/// 주체가 다르다(record vs WebRTC). 실기기 로그에서 어느 경로로 만든 글자인지
/// 가릴 수 있어야 한다.
const String kDuoSttPcmSourceWebrtcMic = 'webrtc_mic';

/// 통화 한 번 = 이 객체 한 개.
class DuoWebrtcMicTap {
  DuoWebrtcMicTap({this.onLog});

  static const MethodChannel _method = MethodChannel(kDuoMicTapMethodChannel);
  static const EventChannel _events = EventChannel(kDuoMicTapEventChannel);

  final void Function(String tag, String msg)? onLog;

  StreamSubscription<dynamic>? _sub;
  bool _started = false;
  int _frames = 0;
  int _bytes = 0;

  bool get isStarted => _started;
  int get frames => _frames;
  int get bytes => _bytes;

  void _lg(String tag, String msg) => onLog?.call(tag, msg);

  /// 🔇 하드웨어 잡음 억제를 끈다.
  ///
  /// flutter_webrtc는 기본으로 이걸 켜는데, **NS는 마찰음(ㅅ·ㅊ·ㅎ)과 문장
  /// 끝을 같이 깎아 전사를 망친다** — 이 프로젝트가 `record` 쪽에서
  /// `noiseSuppress: false`를 쓰는 것과 같은 이유다.
  ///
  /// 통화 쪽 잡음 억제는 잃지 않는다. WebRTC 소프트웨어 APM이 **우리 탭보다
  /// 뒤에서** 계속 하기 때문이다. 즉 STT는 덜 깎인 소리를, 통화는 다듬어진
  /// 소리를 받는다.
  ///
  /// 하드웨어 AEC는 **끄지 않는다.** 탭 위치가 하드웨어 AEC 뒤라서, 기존
  /// `echoCancel: true`와 성질이 같아지려면 그대로 켜 두어야 한다.
  Future<bool> disableHardwareNoiseSuppressor() async {
    try {
      final ok = await _method.invokeMethod<bool>(
        'setHardwareNoiseSuppressor',
        <String, dynamic>{'enabled': false},
      );
      _lg('🔇 [DUO-MIC-TAP]', 'hardwareNs=off ok=$ok');
      return ok ?? false;
    } catch (e) {
      _lg('⚠️ [DUO-MIC-TAP]', 'hardware_ns_failed(${e.runtimeType})');
      return false;
    }
  }

  /// WebRTC 로컬 오디오 트랙에 귀를 붙이고 PCM을 받기 시작한다.
  ///
  /// [trackId]는 `getUserMedia`가 돌려준 오디오 트랙의 id다.
  /// false면 호출부는 전사 갈래를 열지 않는다 — **통화는 계속한다.**
  Future<bool> start({
    required String trackId,
    required void Function(Uint8List pcm) onPcm,
  }) async {
    if (_started) await stop();
    try {
      final ok = await _method.invokeMethod<bool>(
        'start',
        <String, dynamic>{'trackId': trackId},
      );
      if (ok != true) {
        _lg('❌ [DUO-MIC-TAP]', 'attach_failed trackId=$trackId');
        return false;
      }
    } catch (e) {
      _lg('❌ [DUO-MIC-TAP]', 'start_failed(${e.runtimeType})');
      return false;
    }

    _frames = 0;
    _bytes = 0;
    _sub = _events.receiveBroadcastStream().listen(
      (dynamic data) {
        if (data is! Uint8List || data.isEmpty) return;
        _frames++;
        _bytes += data.length;
        onPcm(data);
      },
      onError: (Object e) =>
          _lg('⚠️ [DUO-MIC-TAP]', 'stream_error(${e.runtimeType})'),
    );
    _started = true;
    _lg('🎙️ [DUO-MIC-TAP]',
        'started trackId=$trackId rate=$kDuoMicTapSampleRate mono');
    return true;
  }

  Future<void> stop() async {
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    if (_started) {
      try {
        await _method.invokeMethod<void>('stop');
      } catch (_) {}
      _lg('🧹 [DUO-MIC-TAP]', 'stopped frames=$_frames bytes=$_bytes');
    }
    _started = false;
  }

  /// 통화 종료 로그 한 줄. 오디오 내용은 남기지 않는다.
  String summary() =>
      'source=$kDuoSttPcmSourceWebrtcMic rate=$kDuoMicTapSampleRate '
      'frames=$_frames bytes=$_bytes';
}
