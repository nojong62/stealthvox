// ====================================================================
// 🔊 [INTERP-PLAY] 만능 통역 전용 PCM 재생기 — 통화 경로로 소리를 낸다
// --------------------------------------------------------------------
// 통역 중에는 기기가 **통신 세션**이다. 그 상태에서 물리 볼륨 키는
// `STREAM_VOICE_CALL`을 잡는데, 통역 TTS는 `USAGE_MEDIA`로 나가고 있었다.
// 두 축이 달라서 사용자가 통역 음량을 올리지도 내리지도 못했다.
//
//   2026-09-11 실기기(SM-S931N) 실측
//     dumpsys  STREAM_MUSIC speaker=0 / STREAM_VOICE_CALL speaker=5
//     재생기   usage=USAGE_MEDIA content=CONTENT_TYPE_MUSIC
//     볼륨키 10회 → VOICE_CALL 5→15, MUSIC 0 그대로 (안 닿는다)
//   미디어를 0으로 둔 채 통역에 들어가면 상대 목소리가 영원히 안 들리는데,
//   로그에는 `underruns=0`으로 정상 재생이라 찍힌다.
//
// 그래서 통역만 네이티브 `AudioTrack`을 `USAGE_VOICE_COMMUNICATION`으로 연다.
// 서클톡·시나리오톡·로봇은 [PcmStreamPlayer](flutter_sound) 그대로다.
//
// 🚫 **오디오 세션은 건드리지 않는다.** 통역 중에는 WebRTC가 이미
//   `MODE_IN_COMMUNICATION`, 오디오 포커스, 라우팅(스피커/유선/블루투스)을
//   쥐고 있다. 발화마다 이쪽에서 다시 잡았다 놓으면 통화가 흔들린다.
//   네이티브의 `voiceCommTrackOnly` 모드가 정확히 그 약속이다 —
//   트랙 usage만 통화용이고 mode·focus·speakerphone은 손대지 않는다.
//   (Duo 직접 대화는 `voiceCallManaged`로 그대로 간다. 그쪽은 자기가 AEC를
//    쓰려고 통화 모드를 직접 잡아야 한다.)
//
// 🚰 **백프레셔가 이 파일의 핵심이다.** flutter_sound의
//   `feedUint8FromStream`은 await가 재생 속도를 따라가서, 어댑터가 버퍼를
//   무한히 앞질러 채우지 않게 막아 준다. 네이티브 `append`는 executor에
//   던지고 즉시 반환하므로 그 성질이 없다 — 그래서 `appendBlocking`을 따로
//   두고 실제 write가 끝난 뒤에만 돌아오게 했다. 기존 `append`는 Direct가
//   쓰고 있어 한 글자도 바꾸지 않았다.
// ====================================================================

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'pcm_audio_utils.dart';
import 'tts_adapter.dart';

/// 네이티브 재생기 채널. Direct·첫턴과 **같은 채널**을 쓴다 — 새 오디오
/// 라이브러리를 들이지 않으려고 검증된 통로를 재사용한다.
const String kDuoInterpPcmChannel = 'stealthvox/realtime_pcm';

/// 네이티브가 아는 재생 모드 이름. `MainActivity.kt`의 상수와 짝이다.
const String kPlaybackVoiceCommTrackOnly = 'voiceCommTrackOnly';

/// 🔊 통역 TTS를 통화 경로로 내보내는 [TtsPcmSink].
///
/// 계약은 [PcmStreamPlayer]와 **같은 의미**여야 한다. 어댑터의 큐·세그먼트·
/// 프리롤 계산이 그 의미 위에 서 있기 때문이다.
class DuoInterpPcmPlayer implements TtsPcmSink {
  DuoInterpPcmPlayer({
    MethodChannel? channel,
    this.onLog,
  }) : _channel = channel ?? const MethodChannel(kDuoInterpPcmChannel);

  final MethodChannel _channel;
  final void Function(String tag, String msg)? onLog;

  bool _sessionActive = false;
  int _fedBytes = 0;
  DateTime? _feedStartAt;
  int _sampleRate = TtsAdapterConfig.sampleRate;

  // 🚰 검증용 계측. 실기기 확인이 끝나면 이 중 feedMaxMs/bufferedPeakMs만
  //   남기고 나머지 자세한 로그는 걷어낸다.
  int _feedMaxMs = 0;
  int _bufferedPeakMs = 0;

  /// 이번 세션에서 **한 번의 feed가 가장 오래 걸린 시간**(ms).
  /// 공급이 재생에 밀리고 있으면 여기가 커진다.
  int get feedMaxMs => _feedMaxMs;

  /// 이번 세션에서 **아직 안 난 소리가 가장 많이 쌓였던 양**(ms).
  /// 백프레셔가 깨지면 이 값이 계속 늘어난다.
  int get bufferedPeakMs => _bufferedPeakMs;

  @override
  bool get isSessionActive => _sessionActive;

  @override
  Future<void> begin({
    required int sampleRate,
    required double volume,
  }) async {
    if (_sessionActive) await abort();
    _feedMaxMs = 0;
    _bufferedPeakMs = 0;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'start',
        <String, dynamic>{
          'sampleRate': sampleRate,
          'playbackMode': kPlaybackVoiceCommTrackOnly,
          'volume': volume,
        },
      );
      if (ok != true) {
        onLog?.call('❌ [INTERP-PLAY]', 'start_rejected rate=$sampleRate');
        return;
      }
    } catch (e) {
      onLog?.call('❌ [INTERP-PLAY]', 'start_failed(${e.runtimeType})');
      return;
    }
    _sessionActive = true;
    _fedBytes = 0;
    _feedStartAt = null;
    _sampleRate = sampleRate;
  }

  @override
  Future<void> feed(Uint8List data) async {
    if (!_sessionActive || data.isEmpty) return;
    _feedStartAt ??= DateTime.now();
    final sw = Stopwatch()..start();
    try {
      // 🚰 실제 write가 끝나야 돌아온다. 이 await가 곧 백프레셔다.
      await _channel.invokeMethod<void>('appendBlocking', data);
    } catch (e) {
      onLog?.call('⚠️ [INTERP-PLAY]', 'feed_failed(${e.runtimeType})');
      return;
    } finally {
      sw.stop();
    }
    _fedBytes += data.length;
    if (sw.elapsedMilliseconds > _feedMaxMs) {
      _feedMaxMs = sw.elapsedMilliseconds;
    }
    final int buffered = remainingPlaybackMs();
    if (buffered > _bufferedPeakMs) _bufferedPeakMs = buffered;
  }

  /// 아직 안 난 소리(ms). [PcmStreamPlayer]와 **같은 산수**다 — 기기에
  /// 재생 위치를 묻지 않는다. 물어봐야 채널 왕복만 늘고 답은 같다.
  @override
  int remainingPlaybackMs() {
    final start = _feedStartAt;
    if (!_sessionActive || start == null) return 0;
    final totalMs = pcm16DurationMs(_fedBytes, sampleRate: _sampleRate);
    final elapsed = DateTime.now().difference(start).inMilliseconds;
    final remain = totalMs - elapsed;
    return remain > 0 ? remain : 0;
  }

  @override
  Future<void> setVolume(double volume) async {
    if (!_sessionActive) return;
    try {
      await _channel.invokeMethod<void>(
        'setVolume',
        <String, dynamic>{'volume': volume},
      );
    } catch (_) {}
  }

  @override
  Future<void> finish() async {
    if (!_sessionActive) return;
    // 팝 소리를 막는 꼬리 무음. flutter_sound 쪽과 같은 규격을 쓴다.
    await feed(Uint8List(TtsAdapterConfig.tailSilenceBytes));
    _sessionActive = false;
    try {
      // 네이티브가 마지막 샘플이 다 날 때까지 기다린 뒤 트랙을 놓는다.
      await _channel.invokeMethod<void>('finish');
    } catch (e) {
      onLog?.call('⚠️ [INTERP-PLAY]', 'finish_failed(${e.runtimeType})');
    }
  }

  @override
  Future<void> abort() async {
    if (!_sessionActive) return;
    _sessionActive = false;
    try {
      // 네이티브가 generation을 올려 진행 중인 write까지 즉시 빠져나온다.
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  @override
  Future<void> dispose() => abort();
}
