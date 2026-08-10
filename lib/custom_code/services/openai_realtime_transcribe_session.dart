// ====================================================================
// 🎙️ [REALTIME-STT] OpenAI Realtime transcription 세션
// --------------------------------------------------------------------
// 이 파일이 하는 일은 셋뿐이다.
//   1. 유저 마이크 PCM을 OpenAI로 흘려보낸다
//   2. OpenAI Server VAD가 발화 시작/종료를 잡는다
//   3. 최종 전사문을 돌려준다
//
// 하지 않는 일:
//   · AI 답변 생성 (Realtime conversation 아님 — 전사 전용 세션이다)
//   · 마이크 제어 (앱이 녹음하고, 이 클래스는 받은 바이트를 보낼 뿐이다)
//   · TTS
//
// 기존 Deepgram 경로를 대체하되, 콜백 모양을 최대한 비슷하게 맞춰
// 호출부(routine_mode_anyone.dart)의 변경을 앞단으로만 한정한다.
//
// 공식 스펙 근거 (2026-08 확인):
//   · 연결      wss://api.openai.com/v1/realtime?intent=transcription
//   · 세션 설정 session.update { session.type = "transcription" }
//   · 입력 PCM  audio/pcm 24000Hz mono 16bit
//   · VAD       audio.input.turn_detection = server_vad
//   · 이벤트    input_audio_buffer.speech_started / .speech_stopped
//               conversation.item.input_audio_transcription.delta / .completed
// ====================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'pcm_audio_utils.dart';

// ====================================================================
// 🎚️ [PHASE-1 FLAG] Circle Talk 유저 음성 전사 엔진 전환 스위치
// --------------------------------------------------------------------
//   ON  → OpenAI Realtime transcription (Server VAD + 스트리밍 전사)
//   OFF → 기존 Deepgram Nova-3 경계 + gpt-4o-transcribe 파일 전사
//
// **둘은 절대 동시에 돌지 않는다.** 한 턴에 STT 경로는 하나뿐이고,
// 소켓 예열도 켜진 쪽만 한다. 실기기 A/B 측정은 이 값을 뒤집어서 한다:
//   flutter run --dart-define=FREETALK_REALTIME_STT=false
//
// 바뀌는 것은 전사 공급자뿐이다. 노이즈 게이트·AI 응답·TTS·History·
// billing·30분 롤오버는 `userOriginal` 합류 지점부터 기존 코드를 탄다.
// ====================================================================
const bool kFreeTalkUseRealtimeStt =
    bool.fromEnvironment('FREETALK_REALTIME_STT', defaultValue: true);

/// 전사 전용 세션 엔드포인트. `intent=transcription`이 붙어야 음성 응답용
/// conversation 세션이 아니라 전사 세션으로 열린다.
const String kRealtimeSttEndpoint =
    'wss://api.openai.com/v1/realtime?intent=transcription';

/// 전사 모델. **여기 한 줄만 바꾸면 모델이 바뀐다** — 다른 곳에 박지 않는다.
///
/// Phase 1은 기존 파일 전사와 같은 `gpt-4o-transcribe`를 유지한다. 전송 방식
/// (Deepgram VAD + WAV 업로드 → Server VAD + 스트리밍)만 바꿔야 속도·정확도·
/// 비용 변화의 원인을 분리할 수 있기 때문이다.
/// 공식 가이드가 권장하는 저지연 스트리밍 모델은 `gpt-live-transcribe`다.
const String kRealtimeSttModel = 'gpt-4o-transcribe';

// ── Server VAD 초기값 ────────────────────────────────────────────────
// 고정 정책이 아니라 실기기 측정 시작점이다. 500 / 600 / 700을 비교한다.
//   · 문장 중간 잘림 발생률
//   · speech_stopped → transcription.completed
//   · speech_stopped → AI 첫 소리
const double kRealtimeVadThreshold = 0.5;
const int kRealtimeVadPrefixPaddingMs = 300;
const int kRealtimeVadSilenceDurationMs = 600;

const Duration kRealtimeSttConnectTimeout = Duration(seconds: 6);

/// `session.update`를 서버가 받아들였다는 확인을 기다리는 시간.
/// 확인 없이 오디오를 흘리면 설정이 반영 안 된 세션에 말이 들어간다.
const Duration kRealtimeSttConfigTimeout = Duration(seconds: 4);

const int kRealtimeSttMaxRetries = 5;

/// 전사 세션 하나. 대화방 세션 동안 살아 있고, 턴마다 새로 만들지 않는다.
///
/// **연결과 마이크 입력은 분리되어 있다.** 소켓은 유지한 채
/// [openAudioGate] / [closeAudioGate]로 오디오 전송만 여닫는다.
class OpenAiRealtimeTranscribeSession {
  OpenAiRealtimeTranscribeSession({
    required this.apiKey,
    required this.languageCode,
    this.onLog,
  });

  final String apiKey;
  final String languageCode;
  final void Function(String tag, String msg)? onLog;

  // ── 늦게 묶는 핸들러 ───────────────────────────────────────────────
  // 예열 단계에서는 소켓만 열어 두고, 방에 들어온 뒤 콜백을 붙인다.
  // 붙기 전에는 오디오를 한 바이트도 보내지 않으므로 전사 이벤트도 없다.
  void Function()? onSpeechStarted;
  void Function()? onSpeechStopped;
  void Function(String itemId, String delta)? onTranscriptDelta;
  void Function(String itemId, String text)? onTranscriptCompleted;
  void Function(String reason)? onFatalError;
  void Function(int attempt)? onReconnecting;
  void Function()? onGaveUp;
  void Function(DateTime at)? onFirstAudioSent;

  /// 재연결을 시도해도 되는 상황인지 호출부가 판단한다.
  /// (백그라운드에서는 소켓이 붙지 않으므로 재시도를 태우면 안 된다)
  bool Function()? shouldReconnect;

  WebSocket? _socket;
  StreamSubscription? _sub;
  Completer<bool>? _configured;
  bool _disposed = false;
  bool _audioGateOpen = false;
  bool _firstAudioSent = false;
  bool _reconnectInProgress = false;
  int _retryCount = 0;
  int _sentAudioBytes = 0;
  DateTime? _connectedAt;

  bool get isConnected =>
      !_disposed && _socket != null && _socket!.readyState == WebSocket.open;

  bool get audioGateOpen => _audioGateOpen;

  /// 마이크에서 보낸 총 오디오 시간(ms). 과금 로그용.
  int get sentAudioMs => kStealthVoxSttBytesPerMs <= 0
      ? 0
      : _sentAudioBytes ~/ kStealthVoxSttBytesPerMs;

  /// 소켓이 열린 지 얼마나 됐는지. 예열 소켓 채택 판단에 쓴다.
  Duration get age => _connectedAt == null
      ? Duration.zero
      : DateTime.now().difference(_connectedAt!);

  void _lg(String tag, String msg) => onLog?.call(tag, msg);

  /// 소켓을 열고 세션 설정까지 끝낸다. false면 호출부는 기존 경로로 폴백한다.
  Future<bool> connect() async {
    if (_disposed) return false;
    if (isConnected) return true;
    final sw = Stopwatch()..start();
    try {
      final socket = await WebSocket.connect(
        kRealtimeSttEndpoint,
        headers: {'Authorization': 'Bearer $apiKey'},
      ).timeout(kRealtimeSttConnectTimeout);
      if (_disposed) {
        unawaited(socket.close());
        return false;
      }
      socket.pingInterval = const Duration(seconds: 10);
      _socket = socket;
      await _sub?.cancel();
      _sub = socket.listen(
        _handleEvent,
        onError: (Object e) => _onSocketLost('ws_error(${e.runtimeType})'),
        onDone: () => _onSocketLost('ws_closed'),
        cancelOnError: true,
      );

      final configured = Completer<bool>();
      _configured = configured;
      _sendSessionUpdate();

      final ok = await configured.future.timeout(
        kRealtimeSttConfigTimeout,
        onTimeout: () => false,
      );
      if (!ok) {
        _lg('❌ [RT-STT]',
            'session_update_unconfirmed elapsedMs=${sw.elapsedMilliseconds}');
        await _teardownSocket();
        return false;
      }
      _connectedAt = DateTime.now();
      _retryCount = 0;
      _lg(
        '✅ [RT-STT]',
        'connected model=$kRealtimeSttModel lang=$languageCode '
            'rate=$kStealthVoxSttSampleRate vad=server_vad '
            'threshold=$kRealtimeVadThreshold '
            'prefixMs=$kRealtimeVadPrefixPaddingMs '
            'silenceMs=$kRealtimeVadSilenceDurationMs '
            'connectMs=${sw.elapsedMilliseconds}',
      );
      return true;
    } catch (e) {
      _lg('❌ [RT-STT]',
          'connect_failed(${e.runtimeType}) elapsedMs=${sw.elapsedMilliseconds}');
      await _teardownSocket();
      return false;
    } finally {
      sw.stop();
    }
  }

  void _sendSessionUpdate() {
    _send({
      'type': 'session.update',
      'session': {
        'type': 'transcription',
        'audio': {
          'input': {
            'format': {
              'type': 'audio/pcm',
              'rate': kStealthVoxSttSampleRate,
            },
            'transcription': {
              'model': kRealtimeSttModel,
              'language': languageCode,
            },
            // 발화 경계는 전적으로 서버가 잡는다. 앱에서 commit하지 않는다.
            'turn_detection': {
              'type': 'server_vad',
              'threshold': kRealtimeVadThreshold,
              'prefix_padding_ms': kRealtimeVadPrefixPaddingMs,
              'silence_duration_ms': kRealtimeVadSilenceDurationMs,
            },
          },
        },
      },
    });
  }

  /// 오디오 전송을 연다. 소켓은 건드리지 않는다.
  void openAudioGate({required String reason}) {
    if (_disposed || _audioGateOpen) return;
    _audioGateOpen = true;
    _lg('🎙️ [RT-GATE]', 'open reason=$reason');
  }

  /// 오디오 전송을 닫는다. **소켓은 살려 둔다** — 다음 턴에 다시 열기 위해서다.
  /// AI TTS가 나가는 동안 유저 마이크가 전사로 들어가지 않게 하는 것도 이것이다.
  void closeAudioGate({required String reason}) {
    if (!_audioGateOpen) return;
    _audioGateOpen = false;
    _lg('🎙️ [RT-GATE]', 'close reason=$reason');
  }

  /// 마이크 PCM 한 조각. 게이트가 닫혀 있으면 조용히 버린다(버퍼링하지 않는다 —
  /// 묵혀 뒀다 보내면 AI 목소리나 지난 턴 꼬리가 다음 발화에 섞인다).
  void appendAudio(Uint8List pcm) {
    if (_disposed || !_audioGateOpen || pcm.isEmpty) return;
    if (!isConnected) return;
    _send({
      'type': 'input_audio_buffer.append',
      'audio': base64Encode(pcm),
    });
    _sentAudioBytes += pcm.length;
    if (!_firstAudioSent) {
      _firstAudioSent = true;
      final at = DateTime.now();
      _lg('📡 [RT-FIRST-SEND]',
          'at=${at.toIso8601String()} bytes=${pcm.length}');
      onFirstAudioSent?.call(at);
    }
  }

  void _send(Map<String, dynamic> payload) {
    final socket = _socket;
    if (socket == null || _disposed) return;
    try {
      socket.add(jsonEncode(payload));
    } catch (e) {
      _onSocketLost('send_failed(${e.runtimeType})');
    }
  }

  void _handleEvent(dynamic raw) {
    if (_disposed || raw is! String) return;
    Map<String, dynamic> event;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      event = decoded;
    } catch (_) {
      return;
    }
    final String type = event['type']?.toString() ?? '';

    switch (type) {
      case 'session.updated':
      case 'transcription_session.updated':
        _completeConfigured(true);
        return;

      case 'session.created':
      case 'transcription_session.created':
        // 서버가 소켓을 받자마자 보내는 인사. 설정 확인은 updated에서 한다.
        return;

      case 'error':
        // 세션 설정이 거부됐는지, 턴 하나가 실패했는지 갈라야 한다. 원문을
        // 그대로 남긴다 — 여기서 요약하면 스펙 불일치를 영영 못 찾는다.
        _lg('❌ [RT-STT-ERR]',
            raw.length > 800 ? '${raw.substring(0, 800)}…' : raw);
        final pending = _configured;
        if (pending != null && !pending.isCompleted) {
          _completeConfigured(false);
        }
        return;

      case 'input_audio_buffer.speech_started':
        _lg('📡 [RT-VAD]', 'speech_started');
        onSpeechStarted?.call();
        return;

      case 'input_audio_buffer.speech_stopped':
        _lg('📡 [RT-VAD]', 'speech_stopped');
        onSpeechStopped?.call();
        return;

      case 'input_audio_buffer.committed':
        // 서버가 발화 구간을 확정했다는 신호일 뿐이다. 전사는 그 뒤에 온다.
        _lg('📡 [RT-VAD]', 'committed item=${event['item_id']}');
        return;

      case 'conversation.item.input_audio_transcription.delta':
        final itemId = event['item_id']?.toString() ?? '';
        final delta = event['delta']?.toString() ?? '';
        if (delta.isEmpty) return;
        onTranscriptDelta?.call(itemId, delta);
        return;

      case 'conversation.item.input_audio_transcription.completed':
      case 'conversation.item.input_audio_transcription.done':
        final itemId = event['item_id']?.toString() ?? '';
        final text = event['transcript']?.toString() ?? '';
        _lg('📡 [RT-STT]',
            'transcription_completed item=$itemId len=${text.length}');
        onTranscriptCompleted?.call(itemId, text);
        return;

      case 'conversation.item.input_audio_transcription.failed':
        _lg(
            '❌ [RT-STT]',
            'transcription_failed item=${event['item_id']} '
                'reason=${event['error']}');
        return;

      default:
        return;
    }
  }

  void _completeConfigured(bool ok) {
    final pending = _configured;
    _configured = null;
    if (pending != null && !pending.isCompleted) pending.complete(ok);
  }

  void _onSocketLost(String reason) {
    if (_disposed) return;
    _lg('⚠️ [RT-STT]', 'socket_lost reason=$reason');
    _completeConfigured(false);
    unawaited(_reconnect(reason));
  }

  Future<void> _reconnect(String reason) async {
    if (_disposed || _reconnectInProgress) return;
    _reconnectInProgress = true;
    final wasGateOpen = _audioGateOpen;
    _audioGateOpen = false;
    try {
      await _teardownSocket();
      final gate = shouldReconnect;
      if (gate != null && !gate()) {
        _lg('🎙️ [RT-STT]', 'reconnect_skipped reason=gate_closed');
        return;
      }
      if (_retryCount >= kRealtimeSttMaxRetries) {
        _lg('❌ [RT-STT]', 'reconnect_gave_up after=$_retryCount');
        onGaveUp?.call();
        onFatalError?.call(reason);
        return;
      }
      _retryCount++;
      onReconnecting?.call(_retryCount);
      final delay = Duration(milliseconds: 500 * (1 << (_retryCount - 1)));
      await Future<void>.delayed(delay);
      if (_disposed) return;
      if (gate != null && !gate()) {
        _lg('🎙️ [RT-STT]', 'reconnect_skipped reason=gate_closed_after_delay');
        return;
      }
      _reconnectInProgress = false; // connect 실패 시 다음 이벤트를 다시 받는다
      final ok = await connect();
      if (ok && wasGateOpen) {
        // 끊기기 전에 듣고 있었다면 그대로 다시 듣는다. 끊긴 동안의 발화는
        // 서버에 도달하지 않았으므로 복구하지 않는다(있지도 않은 말을
        // 만들어 내는 것보다 한 턴을 잃는 쪽이 낫다).
        openAudioGate(reason: 'reconnected');
      }
      if (!ok) onFatalError?.call('reconnect_failed');
    } finally {
      _reconnectInProgress = false;
    }
  }

  Future<void> _teardownSocket() async {
    final socket = _socket;
    _socket = null;
    await _sub?.cancel();
    _sub = null;
    if (socket != null) {
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _audioGateOpen = false;
    _completeConfigured(false);
    _lg('🎙️ [RT-STT]', 'dispose sentAudioMs=$sentAudioMs');
    await _teardownSocket();
  }
}
