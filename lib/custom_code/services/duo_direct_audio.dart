// ====================================================================
// 🔉 [DUO-DIRECT] 직접 대화 수신측 재생기
// --------------------------------------------------------------------
// 마이크 캡처는 **여기서 새로 만들지 않는다.** Circle Talk이 쓰는
// `PreparedAudioCapture`(routine_mode_circle_talk.dart)를 그대로 쓴다.
// 같은 설정(pcm16bits / 24kHz / mono)과 같은 lifecycle을 한 벌만 두기
// 위해서다 — 복제해 두면 나중에 sample rate·권한·종료 처리가 두 군데로
// 갈라진다.
//
// 직접 대화의 팬아웃 구조:
//
//   PreparedAudioCapture (broadcast, sync)
//        ├─→ OpenAI 스트리밍 전사  (History용 텍스트)
//        └─→ DuoPcmRelayClient     (상대 폰에서 실제 목소리로 재생)
//
// 이 파일이 맡는 건 그 반대쪽, **상대에게서 온 PCM을 재생하는 일**뿐이다.
// ====================================================================

import 'dart:async';

import 'package:flutter/services.dart';

import 'pcm_audio_utils.dart';

/// PCM16 mono 기준 1ms당 바이트 수(24kHz면 48).
const int kDuoDirectBytesPerMs = kStealthVoxSttBytesPerMs;

/// 재생 전에 모아 두는 양. 네트워크 지터를 흡수할 최소한만 잡는다.
/// 80~120ms 범위에서 실기기로 조정한다 — 여기서 더 키우면 그만큼 통화가 밀린다.
const int kDuoJitterPrebufferMs = 100;

/// 버퍼가 이보다 앞서 나가면 오래된 조각을 버려 지연이 누적되지 않게 한다.
/// (보내는 쪽과 받는 쪽 클럭이 미세하게 달라 통화가 길어지면 반드시 밀린다)
const int kDuoJitterMaxBufferMs = 300;

/// 상대 PCM을 Android AudioTrack으로 흘리는 재생기.
///
/// 기존 `stealthvox/realtime_pcm` 채널을 그대로 쓴다 — 새 오디오 라이브러리를
/// 붙이지 않는다. 채널은 네이티브에 트랙이 하나뿐이므로, 직접 대화가 도는 동안
/// Realtime 음성(첫 턴 통역)은 절대 같이 돌면 안 된다.
class DuoPcmJitterPlayer {
  DuoPcmJitterPlayer({
    this.sampleRate = kStealthVoxSttSampleRate,
    this.prebufferMs = kDuoJitterPrebufferMs,
    this.maxBufferMs = kDuoJitterMaxBufferMs,
    this.onLog,
  });

  static const MethodChannel _channel = MethodChannel('stealthvox/realtime_pcm');

  final int sampleRate;
  final int prebufferMs;
  final int maxBufferMs;
  final void Function(String tag, String msg)? onLog;

  final List<Uint8List> _pending = <Uint8List>[];
  int _pendingBytes = 0;

  bool _started = false;
  bool _priming = true;
  /// 드리프트 계산용 창(窓) 카운터. [resetBuffer]가 0으로 되돌린다 —
  /// `_playbackStartedAt`과 **반드시 같이** 리셋돼야 경과시간 대비가 맞는다.
  int _writtenBytes = 0;

  /// 통화 전체 누적. **리셋하지 않는다.** 종료 로그가 이 값을 읽는다.
  /// 예전에는 위 창 카운터를 그대로 내보내서, 상대가 나가며 buffer_reset이
  /// 돌면 49초를 재생하고도 `playedBytes=0`으로 찍혔다(2026-08-14 실측).
  int _lifetimeWrittenBytes = 0;
  int _droppedBytes = 0;
  DateTime? _playbackStartedAt;
  DateTime? _firstChunkAt;
  int _firstPlayLatencyMs = -1;

  bool get isStarted => _started;
  int get writtenBytes => _lifetimeWrittenBytes;
  int get droppedBytes => _droppedBytes;

  /// 첫 상대 PCM 도착 → 첫 재생 지시까지 걸린 시간(ms). -1이면 아직 없음.
  int get firstPlayLatencyMs => _firstPlayLatencyMs;

  void _lg(String tag, String msg) => onLog?.call(tag, msg);

  Future<bool> start() async {
    if (_started) return true;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'start',
        <String, dynamic>{
          'sampleRate': sampleRate,
          // 🎧 통화 경로로 연다. 네이티브가 AudioManager를 MODE_IN_COMMUNICATION
          //   으로 돌려야 마이크쪽 echoCancel이 지울 대상(재생 신호)을 받는다.
          //   이 재생기는 직접 대화 전용이라 항상 true다 — 같은 채널을 쓰는
          //   첫 턴 Realtime 음성은 인자를 안 보내므로 미디어 재생 그대로다.
          'voiceCall': true,
        },
      );
      _started = ok ?? false;
    } catch (e) {
      _lg('❌ [DUO-PLAY]', 'start_failed(${e.runtimeType})');
      _started = false;
    }
    if (_started) {
      _priming = true;
      _writtenBytes = 0;
      _lifetimeWrittenBytes = 0;
      _droppedBytes = 0;
      _playbackStartedAt = null;
      _firstChunkAt = null;
      _firstPlayLatencyMs = -1;
      _lg('▶️ [DUO-PLAY]', 'started rate=$sampleRate prebufferMs=$prebufferMs');
    }
    return _started;
  }

  /// 릴레이에서 온 조각 하나. 앞선 조각이 아직 재생 중이면 네이티브 쪽에서
  /// 순서대로 소화되므로 여기서는 **얼마나 앞서 있는지만** 감시한다.
  void add(Uint8List pcm) {
    if (!_started || pcm.isEmpty) return;
    _firstChunkAt ??= DateTime.now();

    if (_priming) {
      _pending.add(pcm);
      _pendingBytes += pcm.length;
      if (_pendingBytes < prebufferMs * kDuoDirectBytesPerMs) return;
      _priming = false;
      final primed = _pending;
      final primedBytes = _pendingBytes;
      _pending.clear();
      _pendingBytes = 0;
      _playbackStartedAt = DateTime.now();
      final firstAt = _firstChunkAt;
      if (firstAt != null && _firstPlayLatencyMs < 0) {
        _firstPlayLatencyMs =
            _playbackStartedAt!.difference(firstAt).inMilliseconds;
        _lg('⏱️ [PCM_PLAY]',
            'prebufferedBytes=$primedBytes firstPlayLatencyMs=$_firstPlayLatencyMs');
      }
      for (final chunk in primed) {
        _write(chunk);
      }
      return;
    }

    // 재생이 우리가 부은 양을 못 따라오면(=우리가 앞서 나가면) 지연이 쌓인다.
    // 그만큼은 버려서 통화가 뒤로 밀리지 않게 한다.
    if (_outstandingMs() > maxBufferMs) {
      _droppedBytes += pcm.length;
      _lg('⚠️ [DUO-PLAY]',
          'drift_drop outstandingMs=${_outstandingMs()} droppedBytes=$_droppedBytes');
      return;
    }
    _write(pcm);
  }

  /// 우리가 부은 소리 중 아직 안 나갔을 것으로 추정되는 양(ms).
  /// AudioTrack의 playbackHeadPosition을 Dart로 가져오지 않고, 부은 양과
  /// 흐른 시간의 차이로 추정한다 — 채널 왕복을 매 조각마다 태우지 않기 위해서다.
  int _outstandingMs() {
    final startedAt = _playbackStartedAt;
    if (startedAt == null) return 0;
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    final wroteMs = _writtenBytes ~/ kDuoDirectBytesPerMs;
    final outstanding = wroteMs - elapsedMs;
    return outstanding < 0 ? 0 : outstanding;
  }

  void _write(Uint8List pcm) {
    _writtenBytes += pcm.length;
    _lifetimeWrittenBytes += pcm.length;
    // ⚠️ 여기서 await하면 안 된다. 네이티브 `append`는 조각을 pcmExecutor
    // (단일 스레드)에 넘기고 즉시 반환하며, 실제 `AudioTrack.write`는
    // WRITE_BLOCKING이라 그 스레드에서 재생 속도만큼 막힌다. 기다리면
    // 그 블로킹이 릴레이 수신 콜백까지 끌어내려 소켓 처리가 밀린다.
    unawaited(_appendNative(pcm));
  }

  Future<void> _appendNative(Uint8List pcm) async {
    try {
      await _channel.invokeMethod<void>('append', pcm);
    } catch (_) {
      // 조각 하나 실패로 통화를 죽이지 않는다. stop()에서 자원은 확실히 회수한다.
    }
  }

  /// 상대가 끊겼다가 다시 붙는 등, 흐름이 끊긴 뒤 재개할 때 쓴다.
  /// **밀린 조각은 버린다** — 과거 음성을 몰아서 들려주면 안 된다.
  void resetBuffer(String reason) {
    _pending.clear();
    _pendingBytes = 0;
    _priming = true;
    _writtenBytes = 0;
    _playbackStartedAt = null;
    _lg('🧽 [DUO-PLAY]', 'buffer_reset reason=$reason');
  }

  Future<void> stop() async {
    _pending.clear();
    _pendingBytes = 0;
    _priming = true;
    if (!_started) return;
    _started = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
    _lg('⏹️ [DUO-PLAY]',
        'stopped writtenBytes=$_lifetimeWrittenBytes droppedBytes=$_droppedBytes');
  }
}
