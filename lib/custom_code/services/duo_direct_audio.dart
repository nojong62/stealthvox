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

// ====================================================================
// 🎙️ [DUO-FANOUT] 마이크 한 줄기를 두 갈래로 나누는 자리
// --------------------------------------------------------------------
//   LocalMicPcm (PreparedAudioCapture, AEC 적용 후 · 릴레이 이전)
//        ├─→ DuoCallSender          (DuoPcmRelayClient.sendPcm)
//        └─→ DuoTranscriptionInput  (OpenAiStreamingTranscribeSession)
//
//   RemoteRelayPcm ─→ DuoPlayback (DuoPcmJitterPlayer) — **여기서 끝난다.**
//
// 이 클래스가 지키는 것은 두 가지다.
//   1. 통화 갈래가 먼저 간다. 전사 갈래가 던지든 늦든 위 한 줄에 영향이 없다.
//   2. 전사 갈래로 들어간 PCM은 **항상 이 단말 마이크의 것**이다. 상대에게서
//      받은 PCM은 이 클래스를 통과할 수 없다(입력이 하나뿐이다).
//
// 위젯 안 클로저에 두면 이 두 가지를 시험으로 지킬 수가 없어 밖으로 뺐다.
// ====================================================================

/// 전사에 들어간 PCM의 출처. 저장 문서(`source`)와 진단 로그가 같은 값을 쓴다.
/// 이 문자열이 아닌 값이 나오면 어딘가에서 마이크가 아닌 소리를 전사한 것이다.
const String kDuoSttPcmSourceLocalMic = 'local_mic';

/// 마이크 PCM 팬아웃 한 개 = 통화 한 번.
class DuoMicPcmFanout {
  DuoMicPcmFanout({
    required this.speakerRole,
    required this.toCall,
    required this.toStt,
    this.toLevel,
    this.toProbe,
    this.sampleRate = kStealthVoxSttSampleRate,
    this.isMuted,
    this.isSttOpen,
    this.onLog,
    this.logEveryFrames = 100,
  });

  /// 'HOST' 또는 'GUEST'. 진단 로그의 `speaker=`가 이 값이다.
  final String speakerRole;

  /// 갈래 1 — 상대 폰에서 실제 목소리로 나갈 조각.
  final void Function(Uint8List pcm) toCall;

  /// 갈래 2 — 내 발화를 글자로 만들 조각.
  final void Function(Uint8List pcm) toStt;

  /// 갈래 3 — **세기 계측.** `DuoUtteranceRmsMeter`가 이 조각으로 발화
  /// 구간의 평균 세기를 쌓고, 그 값이 low_level 게이트의 근거가 된다.
  ///
  /// ⚠️ **진단이 아니다.** release에서도 반드시 돌아야 한다 — A/B 비교나
  /// WAV 저장이 꺼져 있어도 이 갈래는 살아 있어야 게이트가 동작한다.
  /// 전사 게이트와도 무관하게 받는다(소켓이 잠깐 닫혀도 세기는 이어 잰다).
  final void Function(Uint8List pcm)? toLevel;

  /// 갈래 4 — **진단 전용.** 개발 빌드에서 같은 조각을 A/B 비교기에 넘긴다.
  /// null이면 아무 일도 없다(release가 그렇다).
  ///
  /// ⚠️ **전사 게이트와 무관하게 받는다.** 비교기는 발화 시작 전 소리를
  /// 고리에 담아 두었다가 앞에 붙이는데(pre-roll), 게이트를 따라 끊으면
  /// 파일 쪽만 첫 음절이 빠진 채 견주게 된다.
  final void Function(Uint8List pcm)? toProbe;

  final int sampleRate;

  /// 음소거는 **내 소리를 안 보내는 것**이다. 참이면 두 갈래 다 버린다 —
  /// 음소거 중에 한 말이 History에 남으면 안 되기 때문이다.
  final bool Function()? isMuted;

  /// 전사 세션이 오디오를 받을 수 있는 상태인가(게이트/연결). 없으면 항상 참.
  final bool Function()? isSttOpen;

  final void Function(String tag, String msg)? onLog;

  /// 진단 로그 주기(전사로 보낸 프레임 수 기준). 0이면 로그를 남기지 않는다.
  final int logEveryFrames;

  int _callFrames = 0;
  int _callBytes = 0;
  int _sttFrames = 0;
  int _sttBytes = 0;
  int _mutedFrames = 0;
  int _callErrors = 0;
  int _sttErrors = 0;
  int _levelFrames = 0;
  int _levelErrors = 0;
  int _probeFrames = 0;
  int _probeErrors = 0;

  int get callFrames => _callFrames;
  int get callBytes => _callBytes;
  int get sttFrames => _sttFrames;
  int get sttBytes => _sttBytes;
  int get mutedFrames => _mutedFrames;
  int get callErrors => _callErrors;
  int get sttErrors => _sttErrors;
  int get levelFrames => _levelFrames;
  int get levelErrors => _levelErrors;
  int get probeFrames => _probeFrames;
  int get probeErrors => _probeErrors;

  /// 마이크 조각 하나. **await하지 않는다** — 통화 경로가 전사 쪽 future나
  /// 네트워크 응답을 기다리게 만들지 않는 것이 이 자리의 규칙이다.
  void add(Uint8List pcm) {
    if (pcm.isEmpty) return;
    if (isMuted?.call() ?? false) {
      _mutedFrames++;
      return;
    }

    // 갈래 1 — 통화. 문턱을 두지 않는다. 사람이 말한 소리는 무조건 나간다.
    try {
      toCall(pcm);
      _callFrames++;
      _callBytes += pcm.length;
    } catch (e) {
      _callErrors++;
      onLog?.call('⚠️ [DuoAudio]', 'call_branch_error=${e.runtimeType}');
    }

    // 갈래 2 — 전사. 여기서 무슨 일이 나도 위 한 줄은 이미 끝났다.
    if (isSttOpen?.call() ?? true) {
      try {
        toStt(pcm);
        _sttFrames++;
        _sttBytes += pcm.length;
        if (logEveryFrames > 0 && _sttFrames % logEveryFrames == 0) {
          onLog?.call(
              '[DuoSTT]',
              'speaker=$speakerRole source=$kDuoSttPcmSourceLocalMic '
                  'sampleRate=$sampleRate bytes=$_sttBytes seq=$_sttFrames');
        }
      } catch (e) {
        _sttErrors++;
        onLog?.call(
            '⚠️ [DuoSTT]', 'stt_branch_error=${e.runtimeType} (통화는 계속된다)');
      }
    }

    // 갈래 3 — 세기 계측. 통화·전사가 지나간 뒤에 선다. 여기서 무슨 일이
    // 나도 앞의 두 갈래는 이미 끝났다.
    final level = toLevel;
    if (level != null) {
      try {
        level(pcm);
        _levelFrames++;
      } catch (e) {
        _levelErrors++;
        onLog?.call('⚠️ [DuoSTT]',
            'level_branch_error=${e.runtimeType} (통화·전사는 계속된다)');
      }
    }

    // 갈래 4 — 진단. 맨 뒤에 서고, 실패해도 아무것도 되돌리지 않는다.
    final probe = toProbe;
    if (probe == null) return;
    try {
      probe(pcm);
      _probeFrames++;
    } catch (e) {
      _probeErrors++;
      onLog?.call('⚠️ [DuoSTT-AB]',
          'probe_branch_error=${e.runtimeType} (통화·전사는 계속된다)');
    }
  }

  /// 통화 종료 로그 한 줄. 오디오 내용은 남기지 않는다 — 세는 값만 남긴다.
  String summary() => 'speaker=$speakerRole source=$kDuoSttPcmSourceLocalMic '
      'sampleRate=$sampleRate callFrames=$_callFrames callBytes=$_callBytes '
      'sttFrames=$_sttFrames sttBytes=$_sttBytes mutedFrames=$_mutedFrames '
      'callErrors=$_callErrors sttErrors=$_sttErrors '
      'levelFrames=$_levelFrames levelErrors=$_levelErrors '
      'probeFrames=$_probeFrames probeErrors=$_probeErrors';
}

/// 상대에게서 받아 **재생만 하는** PCM의 계측기.
///
/// 이 클래스에는 전사로 나가는 출구가 없다. 상대 목소리를 내 단말에서 다시
/// 전사하지 않는다는 규칙이 코드 모양으로 드러나 있어야 해서 따로 둔다.
class DuoRemotePcmMeter {
  DuoRemotePcmMeter({this.onLog, this.logEveryFrames = 100});

  final void Function(String tag, String msg)? onLog;
  final int logEveryFrames;

  int _frames = 0;
  int _bytes = 0;

  int get frames => _frames;
  int get bytes => _bytes;

  void note(Uint8List pcm) {
    if (pcm.isEmpty) return;
    _frames++;
    _bytes += pcm.length;
    if (logEveryFrames > 0 && _frames % logEveryFrames == 0) {
      onLog?.call(
          '[DuoAudio]', 'direction=remote_playback bytes=$_bytes seq=$_frames');
    }
  }
}
