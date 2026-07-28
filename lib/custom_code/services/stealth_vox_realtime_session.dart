import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

import 'realtime_client_secret_service.dart';
import 'realtime_feature_flags.dart';

enum RealtimeConnectionState {
  disconnected,
  requestingToken,
  connecting,
  configuring,
  ready,
  reconnecting,
  closing,
  closed,
  failed,
}

enum RealtimeTurnState {
  idle,
  listening,
  userSpeaking,
  turnEnding,
  responseRequested,
  responseStreaming,
  audioPlaying,
  interrupted,
  finalizing,
  completed,
  cancelled,
  failed,
}

enum RealtimeEventType {
  stateChanged,
  turnStateChanged,
  serverEvent,
  iceStateChanged,
  remoteAudioTrack,
  dataChannelOpened,
  staleEventDropped,
  error,
}

class RealtimeSessionEvent {
  const RealtimeSessionEvent({
    required this.type,
    this.connectionState,
    this.turnState,
    this.payload,
    this.remoteStream,
  });

  final RealtimeEventType type;
  final RealtimeConnectionState? connectionState;
  final RealtimeTurnState? turnState;
  final Map<String, dynamic>? payload;
  final MediaStream? remoteStream;
}

/// Terminal outcome of a single text-driven translation turn.
enum RealtimeTurnOutcome { completed, failed, cancelled, timedOut }

/// Handle for one text-driven translation turn multiplexed over the shared
/// [StealthVoxRealtimeSession]. The session drives its state; callers only read
/// the text stream and the completion futures.
class RealtimeTranslationTurn {
  RealtimeTranslationTurn._(this.turnId, {required bool expectAudio})
      : _expectAudio = expectAudio {
    if (!expectAudio) {
      // Text-only turns have no audio to wait for.
      _audioDone = true;
      if (!_audioComplete.isCompleted) _audioComplete.complete();
    }
  }

  final String turnId;
  final bool _expectAudio;

  /// Server-assigned response id, bound on `response.created`.
  String? responseId;

  final StringBuffer _textBuffer = StringBuffer();
  final StreamController<String> _textCtl =
      StreamController<String>.broadcast();
  final Completer<String> _finalText = Completer<String>();
  final Completer<void> _audioComplete = Completer<void>();
  final Completer<RealtimeTurnOutcome> _done = Completer<RealtimeTurnOutcome>();

  bool _settled = false;
  bool _responseDoneSeen = false;
  bool _audioDone = false;

  /// 원격 오디오가 실제로 흐르기 시작한 시각. `output_audio_buffer.started`
  /// 또는 첫 `response.output_audio.delta`로 잡는다.
  DateTime? _audioStartedAt;

  /// Incremental translation text (transcript deltas for audio turns,
  /// text deltas for text-only turns).
  Stream<String> get textStream => _textCtl.stream;

  /// The full translation text, resolved when the response finishes.
  Future<String> get finalText => _finalText.future;

  /// Resolves when the model audio has finished playing out. Completes
  /// immediately for text-only turns, and via a fallback timer if no explicit
  /// stop signal arrives.
  Future<void> get audioComplete => _audioComplete.future;

  /// Terminal outcome of the turn.
  Future<RealtimeTurnOutcome> get done => _done.future;

  bool get isSettled => _settled;
  String get accumulatedText => _textBuffer.toString();

  void _emitText(String delta) {
    if (_settled || delta.isEmpty) return;
    _textBuffer.write(delta);
    if (!_textCtl.isClosed) _textCtl.add(delta);
  }

  void _overrideText(String text) {
    if (_settled) return;
    _textBuffer
      ..clear()
      ..write(text);
  }

  void _completeText() {
    if (!_finalText.isCompleted) _finalText.complete(_textBuffer.toString());
  }

  void _completeAudio() {
    _audioDone = true;
    if (!_audioComplete.isCompleted) _audioComplete.complete();
  }

  void _markAudioStarted() {
    _audioStartedAt ??= DateTime.now();
  }

  /// 🕐 [RT-AUDIO] `output_audio_buffer.stopped`가 오지 않는 응답이 실제로
  /// 존재한다(실기기 확인). 그때마다 고정 5초를 통째로 기다리면 턴 사이가
  /// 그만큼 비므로, 낭독에 남은 시간을 낭독문 길이로 추정해 대기 상한을 좁힌다.
  ///
  /// 낭독 속도는 실제(약 165wpm)보다 느리게 잡아 과소추정으로 AI 음성이 유저
  /// 음성 꼬리를 덮는 일이 없게 한다. 시작 신호조차 못 받은 경우에는 추정을
  /// 포기하고 기존 상한을 그대로 쓴다.
  Duration? _estimateRemainingAudio() {
    final startedAt = _audioStartedAt;
    if (startedAt == null) return null;
    final words = _textBuffer
        .toString()
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    if (words == 0) return null;
    final estimatedTotal = Duration(milliseconds: words * 380 + 700);
    final remaining = estimatedTotal - DateTime.now().difference(startedAt);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void _settle(RealtimeTurnOutcome outcome) {
    if (_settled) return;
    _settled = true;
    _completeText();
    if (!_audioComplete.isCompleted) _audioComplete.complete();
    if (!_done.isCompleted) _done.complete(outcome);
    if (!_textCtl.isClosed) _textCtl.close();
  }
}

/// Transport-only WebRTC layer. It owns no UI, Firestore, billing, or TTS.
class StealthVoxRealtimeSession {
  StealthVoxRealtimeSession({
    RealtimeClientSecretService? secretService,
    RealtimeLogger? logger,
  })  : _secretService = secretService ?? RealtimeClientSecretService(),
        _logger = logger;

  final RealtimeClientSecretService _secretService;
  final RealtimeLogger? _logger;
  final StreamController<RealtimeSessionEvent> _events =
      StreamController<RealtimeSessionEvent>.broadcast();

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  MediaStream? _localStream;
  String? _modeSessionId;
  String? _turnId;
  String? _responseId;
  int _connectionGeneration = 0;
  bool _disposed = false;
  RealtimeConnectionState _connectionState =
      RealtimeConnectionState.disconnected;
  RealtimeTurnState _turnState = RealtimeTurnState.idle;

  bool _captureMicrophone = true;
  bool _disableServerVad = false;
  // 🗣️ [RT-CONV] true면 server VAD가 발화 종료 시 곧바로 응답을 생성한다(음성
  //   대화 직결 모드). 이때 입력 전사(gpt-4o-mini-transcribe)는 사용하지 않고
  //   모델이 오디오를 직접 이해한다.
  bool _autoRespond = false;
  String _mode = '';
  // ⏱️ [RT-LATENCY] 음성 직결 모드 턴별 지연 측정용 타임스탬프.
  DateTime? _convSpeechStoppedAt;
  DateTime? _convResponseCreatedAt;
  DateTime? _convFirstTextAt;
  DateTime? _convFirstAudioAt;
  int _convTurnCount = 0;
  // AI 음성이 실제로 재생 중인지. 유저가 말을 시작하면 이걸 보고 즉시 끊는다.
  bool _outputAudioActive = false;
  // 🔇 [RT-HALF-DUPLEX] AI 음성이 스피커로 나가는 동안 마이크를 닫는다. 닫지
  //   않으면 자기 음성을 server VAD가 새 발화로 판정해 응답을 또 만들고, 그
  //   응답을 다시 듣는 무한 되먹임에 빠진다.
  bool _micMutedForPlayback = false;
  Timer? _micRestoreTimer;
  static const Duration _micRestoreTail = Duration(milliseconds: 350);

  void _muteMicForAiPlayback() {
    _micRestoreTimer?.cancel();
    _micRestoreTimer = null;
    if (_micMutedForPlayback || !_captureMicrophone) return;
    try {
      setMicrophoneEnabled(false);
      _micMutedForPlayback = true;
      _logger?.call('[RT-HALF-DUPLEX]', 'mic_muted_during_ai_audio');
    } catch (error) {
      _logger?.call('[RT-HALF-DUPLEX]', 'mute_failed ${error.runtimeType}');
    }
  }

  void _restoreMicAfterAiPlayback() {
    if (!_micMutedForPlayback) return;
    _micRestoreTimer?.cancel();
    // 스피커 잔향이 마이크로 새어 들어가 다시 트리거되지 않도록 짧은 꼬리를 둔다.
    _micRestoreTimer = Timer(_micRestoreTail, () {
      _micRestoreTimer = null;
      if (_disposed || !_micMutedForPlayback) return;
      try {
        setMicrophoneEnabled(true);
        _micMutedForPlayback = false;
        _logger?.call('[RT-HALF-DUPLEX]', 'mic_restored');
      } catch (error) {
        _logger?.call('[RT-HALF-DUPLEX]', 'restore_failed ${error.runtimeType}');
      }
    });
  }
  bool _peerConnected = false;
  bool _sessionUpdatedConfirmed = false;
  RealtimeTranslationTurn? _activeTurn;
  Timer? _turnTimeoutTimer;
  Timer? _audioTailTimer;
  Completer<void>? _sessionUpdatedCompleter;
  Duration _audioStabilization = const Duration(milliseconds: 250);
  Duration _audioTailTimeout = const Duration(seconds: 5);

  /// 🎧 [RT-TRANSCRIPTION] 입력 전사 언어. 비워 두면 서버가 언어부터 스스로
  /// 추측한다. 모국어를 못 박아 그 추측 단계를 없앤다.
  ///
  /// 어휘 힌트(prompt)는 의도적으로 쓰지 않는다. 특정 표현으로 인식을 끌어당겨
  /// 사용자가 다른 말을 해도 힌트 쪽으로 붙을 위험이 있고, 전사가 파이프라인의
  /// 임계 경로에 있어 프롬프트 길이가 그대로 지연이 된다.
  String? _transcriptionLanguage;

  /// 🎧 [RT-TRANSCRIPTION] 첫 발화만 정밀 모델로 받고 이후는 경량으로 내린다.
  /// 첫 발화는 상대·상황을 정하는 문장이라 한 번 잘못 들으면 대화 전체가
  /// 어긋난다. 2턴부터는 문맥이 쌓여 경량 모델로도 복구가 된다.
  static const String kAccurateTranscriptionModel = 'gpt-4o-transcribe';
  static const String kLightTranscriptionModel = 'gpt-4o-mini-transcribe';
  String _transcriptionModel = kLightTranscriptionModel;

  /// 전사 모델을 바꿔 session.update를 다시 보내려면 최초 설정값이 필요하다.
  String _sessionVoice = kDefaultRealtimeVoice;
  String _sessionInstructions = '';

  Stream<RealtimeSessionEvent> get events => _events.stream;
  RealtimeTranslationTurn? get activeTurn => _activeTurn;
  RealtimeConnectionState get connectionState => _connectionState;
  RealtimeTurnState get turnState => _turnState;
  bool get isReady => _connectionState == RealtimeConnectionState.ready;
  String? get modeSessionId => _modeSessionId;
  String? get responseId => _responseId;
  bool get capturesMicrophone => _captureMicrophone;
  bool get isMicrophoneEnabled =>
      _localStream?.getAudioTracks().any((track) => track.enabled) ?? false;

  Future<void> connect({
    required String mode,
    required String modeSessionId,
    String voice = 'marin',
    String instructions = '',
    bool allowWhenDisabled = false,
    bool captureMicrophone = true,
    bool disableServerVad = false,
    bool autoRespond = false,
    String? transcriptionLanguage,
    String transcriptionModel = kLightTranscriptionModel,
  }) async {
    if (_disposed) throw StateError('Realtime session is disposed.');
    if (!allowWhenDisabled && !RealtimeFeatureFlags.enabledFor(mode)) {
      throw StateError('Realtime feature flag is disabled for $mode.');
    }
    if (isReady || _connectionState == RealtimeConnectionState.connecting) {
      return;
    }
    _logger?.call('[RT-PATH]', 'secure_webrtc mode=$mode');
    _captureMicrophone = captureMicrophone;
    _disableServerVad = disableServerVad;
    _autoRespond = autoRespond;
    _transcriptionLanguage = transcriptionLanguage;
    _transcriptionModel = transcriptionModel;
    _sessionVoice = voice;
    _sessionInstructions = instructions;
    _mode = mode;
    _peerConnected = false;
    _sessionUpdatedConfirmed = false;
    _sessionUpdatedCompleter = Completer<void>();
    _modeSessionId = modeSessionId;
    final generation = ++_connectionGeneration;
    String stage = 'secret';
    try {
      _setConnectionState(RealtimeConnectionState.requestingToken);
      // 🔥 [RT-PREWARM] StealthRoom에서 미리 받아둔 secret이 살아 있으면 쓴다.
      //   없거나 만료가 임박하면 평소대로 새로 발급한다(동작 차이 없음).
      final secret =
          RealtimeClientSecretPrewarm.instance.take(mode, logger: _logger) ??
              await _secretService.create(mode: mode, logger: _logger);
      _assertCurrent(generation);
      _setConnectionState(RealtimeConnectionState.connecting);

      stage = 'peer_connection';
      final peer = await createPeerConnection(<String, dynamic>{})
          .timeout(const Duration(seconds: 5));
      _assertCurrent(generation);
      _peerConnection = peer;
      _logger?.call('[RT-PC]', 'created');
      peer.onTrack = (event) {
        if (!_isCurrent(generation) || event.streams.isEmpty) {
          _emit(RealtimeEventType.staleEventDropped);
          return;
        }
        _logger?.call('[RT-AUDIO]', 'remote_track_received');
        _emit(
          RealtimeEventType.remoteAudioTrack,
          remoteStream: event.streams.first,
        );
      };
      peer.onIceConnectionState = (state) {
        if (!_isCurrent(generation)) return;
        final label = _iceStateLabel(state);
        _logger?.call('[RT-ICE]', label);
        _emit(
          RealtimeEventType.iceStateChanged,
          payload: <String, dynamic>{'state': label},
        );
        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          _setConnectionState(RealtimeConnectionState.failed);
        } else if (state ==
            RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          _setConnectionState(RealtimeConnectionState.reconnecting);
        } else if (state ==
                RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _peerConnected = true;
          _setReadyWhenConfigured();
        }
      };
      peer.onConnectionState = (state) {
        if (!_isCurrent(generation)) {
          _emit(RealtimeEventType.staleEventDropped);
          return;
        }
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _peerConnected = true;
          _setReadyWhenConfigured();
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _setConnectionState(RealtimeConnectionState.failed);
        }
      };

      stage = 'microphone';
      if (_captureMicrophone) {
        _localStream = await navigator.mediaDevices
            .getUserMedia(
              <String, dynamic>{'audio': true, 'video': false},
            )
            .timeout(const Duration(seconds: 8));
        _assertCurrent(generation);
        final audioTracks = _localStream!.getAudioTracks();
        if (audioTracks.isEmpty) {
          throw StateError('No local microphone track.');
        }
        await peer
            .addTrack(audioTracks.first, _localStream!)
            .timeout(const Duration(seconds: 5));
        _assertCurrent(generation);
        _logger?.call('[RT-MIC]', 'local_track_added enabled=true');
      } else {
        // Text-driven turns: receive remote audio without publishing a mic.
        await peer.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.RecvOnly,
          ),
        );
      }

      stage = 'data_channel';
      _dataChannel = await peer
          .createDataChannel(
            'oai-events',
            RTCDataChannelInit(),
          )
          .timeout(const Duration(seconds: 5));
      _assertCurrent(generation);
      _dataChannel!.onDataChannelState = (state) {
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          _emit(RealtimeEventType.dataChannelOpened);
          _setConnectionState(RealtimeConnectionState.configuring);
          _sendSessionUpdate(voice: voice, instructions: instructions);
        }
      };
      _dataChannel!.onMessage = (message) {
        _handleServerEvent(message.text, generation);
      };

      stage = 'sdp_offer';
      final offer = await peer
          .createOffer(<String, dynamic>{})
          .timeout(const Duration(seconds: 5));
      _assertCurrent(generation);
      await peer
          .setLocalDescription(offer)
          .timeout(const Duration(seconds: 5));
      _assertCurrent(generation);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final localDescription = await peer.getLocalDescription();
      final sdp = localDescription?.sdp;
      if (sdp == null || sdp.isEmpty) throw StateError('Local SDP is empty.');
      _logger?.call('[RT-SDP]', 'offer_created');

      stage = 'sdp_answer';
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/realtime/calls'),
            headers: <String, String>{
              'Authorization': 'Bearer ${secret.value}',
              'Content-Type': 'application/sdp',
            },
            body: sdp,
          )
          .timeout(const Duration(seconds: 10));
      _assertCurrent(generation);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Realtime SDP negotiation failed.');
      }
      await peer
          .setRemoteDescription(
            RTCSessionDescription(response.body, 'answer'),
          )
          .timeout(const Duration(seconds: 5));
      _assertCurrent(generation);
      _logger?.call('[RT-SDP]', 'answer_applied');

      stage = 'session_updated';
      await _sessionUpdatedCompleter!.future
          .timeout(const Duration(seconds: 3));
      _assertCurrent(generation);
    } catch (e) {
      if (_isCurrent(generation)) {
        _setConnectionState(RealtimeConnectionState.failed);
      }
      _logger?.call('[RT-ERROR]', 'stage=$stage reason=${e.runtimeType}');
      rethrow;
    }
  }

  String _iceStateLabel(RTCIceConnectionState state) {
    switch (state) {
      case RTCIceConnectionState.RTCIceConnectionStateChecking:
        return 'checking';
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
        return 'connected';
      case RTCIceConnectionState.RTCIceConnectionStateCompleted:
        return 'completed';
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        return 'failed';
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        return 'disconnected';
      case RTCIceConnectionState.RTCIceConnectionStateClosed:
        return 'closed';
      default:
        return 'new';
    }
  }

  void sendEvent(Map<String, dynamic> event) {
    if ((_connectionState != RealtimeConnectionState.ready &&
            _connectionState != RealtimeConnectionState.configuring) ||
        _dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw StateError('Realtime data channel is not open.');
    }
    _dataChannel!.send(RTCDataChannelMessage(jsonEncode(event)));
  }

  void requestResponse({String? turnId}) {
    _turnId = turnId ?? _turnId;
    _setTurnState(RealtimeTurnState.responseRequested);
    sendEvent(<String, dynamic>{'type': 'response.create'});
  }

  void cancelResponse() {
    _setTurnState(RealtimeTurnState.interrupted);
    _sendCancel();
    _setTurnState(RealtimeTurnState.cancelled);
  }

  /// Enables or mutes the published WebRTC microphone track without replacing
  /// the PeerConnection. Translation responses can therefore reuse the same
  /// connection without feeding speaker output back into the next user turn.
  void setMicrophoneEnabled(bool enabled) {
    if (!_captureMicrophone) {
      throw StateError('This Realtime session has no microphone track.');
    }
    final tracks = _localStream?.getAudioTracks() ?? <MediaStreamTrack>[];
    if (tracks.isEmpty) {
      throw StateError('Realtime microphone track is unavailable.');
    }
    for (final track in tracks) {
      track.enabled = enabled;
    }
    _logger?.call('[RT-MIC]', 'enabled=$enabled');
  }

  void _sendCancel() {
    if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel!.send(RTCDataChannelMessage(
          jsonEncode(<String, dynamic>{'type': 'response.cancel'})));
      _dataChannel!.send(RTCDataChannelMessage(
          jsonEncode(<String, dynamic>{'type': 'output_audio_buffer.clear'})));
    }
    _responseId = null;
  }

  /// Requests one text-driven translation turn on the live session and returns
  /// a handle exposing the text stream and completion futures. Rejects if a turn
  /// is already active — the caller serializes turns (one active response per
  /// session is a protocol constraint).
  ///
  /// [suppressAudio] true → text-only draft (first-turn review); false →
  /// text + WebRTC audio (turn 2+). The audio itself plays via the media track.
  RealtimeTranslationTurn requestTranslatedTurn({
    required String turnId,
    required String sourceText,
    required String instructions,
    String voice = 'marin',
    bool suppressAudio = false,
    Duration turnTimeout = const Duration(seconds: 20),
    Duration audioTailTimeout = const Duration(seconds: 5),
    Duration audioStabilization = const Duration(milliseconds: 250),
  }) {
    if (_disposed) throw StateError('Realtime session is disposed.');
    if (_activeTurn != null && !_activeTurn!.isSettled) {
      throw StateError('A realtime turn is already active.');
    }
    if (_connectionState != RealtimeConnectionState.ready &&
        _connectionState != RealtimeConnectionState.configuring) {
      throw StateError('Realtime session is not ready.');
    }

    final turn = RealtimeTranslationTurn._(turnId, expectAudio: !suppressAudio);
    _activeTurn = turn;
    _turnId = turnId;
    _audioTailTimeout = audioTailTimeout;
    _audioStabilization = audioStabilization;

    // 1) Inject the user text as a conversation item.
    sendEvent(<String, dynamic>{
      'type': 'conversation.item.create',
      'item': <String, dynamic>{
        'type': 'message',
        'role': 'user',
        'content': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'input_text', 'text': sourceText},
        ],
      },
    });

    // 2) Ask for exactly one response in the requested modality.
    final response = <String, dynamic>{
      'instructions': instructions,
      'output_modalities':
          suppressAudio ? <String>['text'] : <String>['audio'],
    };
    if (!suppressAudio) {
      response['audio'] = <String, dynamic>{
        'output': <String, dynamic>{'voice': _resolveRealtimeVoice(voice)},
      };
    }
    sendEvent(
        <String, dynamic>{'type': 'response.create', 'response': response});
    _setTurnState(RealtimeTurnState.responseRequested);
    _logger?.call(
        '[RT-TURN]', 'turnId=$turnId start suppress_audio=$suppressAudio');

    _turnTimeoutTimer?.cancel();
    _turnTimeoutTimer = Timer(turnTimeout, () {
      if (identical(_activeTurn, turn) && !turn.isSettled) {
        _logger?.call('[RT-TURN]', 'turnId=$turnId timeout');
        _endTurn(turn, RealtimeTurnOutcome.timedOut, cancelServer: true);
      }
    });

    return turn;
  }

  /// 🎙️ [SPEECH-FIRST] 서버 VAD가 방금 커밋한 유저 오디오를 그대로 조건으로 삼아
  /// 응답 1개를 요청한다. 전사 텍스트를 주입하지 않으므로 전사 완료를 기다릴
  /// 필요가 없고, 발화가 끝나는 즉시 발사할 수 있다(= 유저 목소리가 바로 나온다).
  /// 전사는 자막·AI 응답용으로 뒤따라 도착하며 이 턴을 막지 않는다.
  RealtimeTranslationTurn requestSpeechTranslationTurn({
    required String turnId,
    required String instructions,
    String voice = 'marin',
    Duration turnTimeout = const Duration(seconds: 20),
    Duration audioTailTimeout = const Duration(seconds: 5),
    Duration audioStabilization = const Duration(milliseconds: 250),
  }) {
    if (_disposed) throw StateError('Realtime session is disposed.');
    if (_activeTurn != null && !_activeTurn!.isSettled) {
      throw StateError('A realtime turn is already active.');
    }
    if (_connectionState != RealtimeConnectionState.ready &&
        _connectionState != RealtimeConnectionState.configuring) {
      throw StateError('Realtime session is not ready.');
    }

    final turn = RealtimeTranslationTurn._(turnId, expectAudio: true);
    _activeTurn = turn;
    _turnId = turnId;
    _audioTailTimeout = audioTailTimeout;
    _audioStabilization = audioStabilization;

    // 입력 아이템을 만들지 않는다 — 서버 VAD가 커밋한 오디오 아이템이 이미
    // 대화에 들어가 있으므로 response.create만 보내면 그 발화를 조건으로 답한다.
    sendEvent(<String, dynamic>{
      'type': 'response.create',
      'response': <String, dynamic>{
        'instructions': instructions,
        'output_modalities': <String>['audio'],
        'audio': <String, dynamic>{
          'output': <String, dynamic>{'voice': _resolveRealtimeVoice(voice)},
        },
      },
    });
    _setTurnState(RealtimeTurnState.responseRequested);
    _logger?.call('[RT-TURN]', 'turnId=$turnId start mode=speech_first');

    _turnTimeoutTimer?.cancel();
    _turnTimeoutTimer = Timer(turnTimeout, () {
      if (identical(_activeTurn, turn) && !turn.isSettled) {
        _logger?.call('[RT-TURN]', 'turnId=$turnId timeout');
        _endTurn(turn, RealtimeTurnOutcome.timedOut, cancelServer: true);
      }
    });

    return turn;
  }

  /// Cancels the in-flight translation turn, if any, and clears the server
  /// response so a late one cannot leak into the next turn.
  void cancelActiveTurn() {
    final turn = _activeTurn;
    if (turn == null || turn.isSettled) return;
    _endTurn(turn, RealtimeTurnOutcome.cancelled, cancelServer: true);
  }

  void _routeTurnEvent(String type, Map<String, dynamic> payload) {
    final turn = _activeTurn;
    if (turn == null || turn.isSettled) return;

    if (type == 'response.created') {
      turn.responseId ??= (payload['response'] as Map?)?['id']?.toString();
      return;
    }

    // Stale-response guard: once bound, ignore events from other responses.
    final eventResponseId = payload['response_id']?.toString() ??
        (payload['response'] as Map?)?['id']?.toString();
    if (turn.responseId != null &&
        eventResponseId != null &&
        eventResponseId != turn.responseId) {
      _emit(RealtimeEventType.staleEventDropped);
      return;
    }

    switch (type) {
      case 'response.output_text.delta':
      case 'response.output_audio_transcript.delta':
        turn._emitText(payload['delta']?.toString() ?? '');
        break;
      case 'response.output_text.done':
      case 'response.output_audio_transcript.done':
        final finalText =
            payload['text']?.toString() ?? payload['transcript']?.toString();
        if (finalText != null && finalText.isNotEmpty) {
          turn._overrideText(finalText);
        }
        turn._completeText();
        break;
      case 'output_audio_buffer.started':
      case 'response.output_audio.delta':
      case 'response.audio.delta':
        // 오디오가 실제로 흐르기 시작한 시각을 남긴다. 종료 신호가 오지 않는
        // 응답에서 남은 낭독 시간을 추정하는 기준점이다.
        if (turn._audioStartedAt == null) {
          turn._markAudioStarted();
          _logger?.call('[RT-AUDIO]', 'stream_started signal=$type '
              'turnId=${turn.turnId}');
        }
        break;
      case 'output_audio_buffer.stopped':
      case 'output_audio_buffer.cleared':
        _logger?.call(
            '[RT-AUDIO]', 'stop_signal=$type turnId=${turn.turnId}');
        _scheduleAudioComplete(turn);
        break;
      case 'response.done':
        _handleTurnResponseDone(
            turn, (payload['response'] as Map?)?['status']?.toString());
        break;
      case 'error':
      case 'response.failed':
        _endTurn(turn, RealtimeTurnOutcome.failed, cancelServer: true);
        break;
    }
  }

  void _scheduleAudioComplete(RealtimeTranslationTurn turn) {
    _audioTailTimer?.cancel();
    _audioTailTimer = Timer(_audioStabilization, () {
      if (!identical(_activeTurn, turn) || turn.isSettled) return;
      turn._completeAudio();
      _logger?.call('[RT-AUDIO]', 'turnId=${turn.turnId} playback_done');
      _maybeSettleTurn(turn);
    });
  }

  void _handleTurnResponseDone(RealtimeTranslationTurn turn, String? status) {
    turn._responseDoneSeen = true;
    turn._completeText();
    if (status != null && status != 'completed') {
      _logger?.call(
          '[RT-TURN]', 'turnId=${turn.turnId} response_status=$status');
      _endTurn(turn, RealtimeTurnOutcome.failed, cancelServer: true);
      return;
    }
    // response.done is not proof the speaker finished; wait for the audio buffer
    // stop (WebRTC) with a stabilization delay, then a fallback timeout.
    //
    // 🕐 [RT-AUDIO] 실기기에서 긴 발화 턴은 `output_audio_buffer.stopped`가
    //   끝내 오지 않는 경우가 있다. 그때 고정 상한(5초)을 통째로 기다리면 유저
    //   음성이 끝난 뒤에도 그만큼 정적이 생긴다. 낭독 길이로 남은 시간을 추정해
    //   기다림을 좁히되, 추정이 불가능하거나 추정치가 더 길면 기존 상한을 쓴다.
    if (turn._expectAudio && !turn._audioDone) {
      final estimated = turn._estimateRemainingAudio();
      final wait = (estimated != null && estimated < _audioTailTimeout)
          ? estimated
          : _audioTailTimeout;
      _audioTailTimer?.cancel();
      _audioTailTimer = Timer(wait, () {
        if (!identical(_activeTurn, turn) || turn.isSettled) return;
        turn._completeAudio();
        _logger?.call(
            '[RT-AUDIO]',
            'completion_timeout turnId=${turn.turnId} '
                'waited_ms=${wait.inMilliseconds} '
                'source=${estimated == null ? 'fixed_cap' : 'estimated'}');
        _maybeSettleTurn(turn);
      });
    }
    _maybeSettleTurn(turn);
  }

  void _maybeSettleTurn(RealtimeTranslationTurn turn) {
    if (turn.isSettled || !turn._responseDoneSeen) return;
    if (turn._expectAudio && !turn._audioDone) return;
    _endTurn(turn, RealtimeTurnOutcome.completed, cancelServer: false);
  }

  void _endTurn(
    RealtimeTranslationTurn turn,
    RealtimeTurnOutcome outcome, {
    required bool cancelServer,
  }) {
    if (turn.isSettled) return;
    if (cancelServer) _sendCancel();
    _turnTimeoutTimer?.cancel();
    _audioTailTimer?.cancel();
    turn._settle(outcome);
    if (identical(_activeTurn, turn)) _activeTurn = null;
    _setTurnState(outcome == RealtimeTurnOutcome.completed
        ? RealtimeTurnState.completed
        : RealtimeTurnState.failed);
    _logger?.call('[RT-TURN]', 'turnId=${turn.turnId} ${outcome.name}');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _turnTimeoutTimer?.cancel();
    _audioTailTimer?.cancel();
    final active = _activeTurn;
    _activeTurn = null;
    if (active != null && !active.isSettled) {
      active._settle(RealtimeTurnOutcome.cancelled);
    }
    ++_connectionGeneration;
    _setConnectionState(RealtimeConnectionState.closing);
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    _micRestoreTimer?.cancel();
    _micRestoreTimer = null;
    _micMutedForPlayback = false;
    _outputAudioActive = false;
    await _localStream?.dispose();
    await _dataChannel?.close();
    await _peerConnection?.close();
    _dataChannel = null;
    _peerConnection = null;
    _setConnectionState(RealtimeConnectionState.closed);
    await _events.close();
  }

  /// Realtime API가 허용하는 출력 voice 목록. legacy TTS(tts-1)에서 쓰는 이름
  /// (fable/onyx/nova)을 그대로 보내면 서버가 session.update 전체를
  /// invalid_value로 거부하고, 그 결과 세션이 통째로 Deepgram legacy로 폴백된다.
  static const Set<String> _supportedRealtimeVoices = <String>{
    'alloy',
    'ash',
    'ballad',
    'coral',
    'echo',
    'sage',
    'shimmer',
    'verse',
    'marin',
    'cedar',
  };

  /// legacy TTS voice → 가장 가까운 Realtime voice.
  static const Map<String, String> _legacyVoiceAliases = <String, String>{
    'fable': 'ballad',
    'onyx': 'ash',
    'nova': 'coral',
  };

  static const String kDefaultRealtimeVoice = 'marin';

  String _resolveRealtimeVoice(String requested) {
    final normalized = requested.trim().toLowerCase();
    if (_supportedRealtimeVoices.contains(normalized)) return normalized;
    final resolved = _legacyVoiceAliases[normalized] ?? kDefaultRealtimeVoice;
    _logger?.call(
      '[RT-VOICE]',
      'unsupported_voice_mapped requested=$requested resolved=$resolved',
    );
    return resolved;
  }

  /// 🎧 [RT-TRANSCRIPTION] 전사 모델을 바꾸고 세션 설정을 다시 보낸다.
  /// 다음 발화부터 적용된다. 진행 중인 전사에는 영향을 주지 않는다.
  void setTranscriptionModel(String model) {
    if (_disposed || _transcriptionModel == model) return;
    _transcriptionModel = model;
    if (!_captureMicrophone) return;
    if (_connectionState != RealtimeConnectionState.ready &&
        _connectionState != RealtimeConnectionState.configuring) {
      // 아직 연결 전이면 값만 바꿔 둔다. 최초 session.update가 이 값을 쓴다.
      return;
    }
    _logger?.call('[RT-TRANSCRIPTION]', 'model_switch → $model');
    _sendSessionUpdate(
        voice: _sessionVoice, instructions: _sessionInstructions);
  }

  void _sendSessionUpdate(
      {required String voice, required String instructions}) {
    final audio = <String, dynamic>{
      'output': <String, dynamic>{'voice': _resolveRealtimeVoice(voice)},
    };
    if (_disableServerVad) {
      // Text-driven turns must never auto-respond to inbound audio.
      audio['input'] = <String, dynamic>{'turn_detection': null};
    } else if (_captureMicrophone) {
      final turnDetection = <String, dynamic>{
        'type': 'server_vad',
        // 🗣️ [RT-CONV] 음성 직결 모드에서는 서버가 발화 종료 즉시 응답을
        //   만들고, 사용자가 끼어들면(barge-in) 진행 중 응답을 중단한다.
        'create_response': _autoRespond,
        'interrupt_response': _autoRespond,
      };
      if (_autoRespond) {
        // 기본값(threshold 0.5 / silence 500ms)은 문장 중간의 짧은 숨에도 발화를
        // 끊어 한 발화가 두 턴으로 쪼개지고, 그 결과 응답이 2개 생성돼 음성이
        // 겹친다. 임계값과 침묵 길이를 올려 한 발화를 한 턴으로 묶는다.
        turnDetection['threshold'] = 0.65;
        turnDetection['silence_duration_ms'] = 900;
        turnDetection['prefix_padding_ms'] = 300;
      }
      final input = <String, dynamic>{'turn_detection': turnDetection};
      // 입력 전사는 항상 병렬로 켠다.
      //  - autoRespond 모드: 모델은 오디오를 직접 이해해 즉시 응답하고, 전사는
      //    HOST 한국어 원문/History 저장 용도로만 비동기 도착한다. 전사 완료가
      //    응답 시작을 막지 않는다.
      //  - 텍스트 구동 경로: 전사 이벤트로 턴 경계를 잡는다.
      // 🎧 [RT-TRANSCRIPTION] language를 비워 두면 서버가 언어부터 추측한다.
      //   모국어를 못 박아 그 단계를 없앤다. 어휘 힌트(prompt)는 쓰지 않는다.
      final transcription = <String, dynamic>{
        'model': _transcriptionModel,
      };
      final language = _transcriptionLanguage?.trim();
      if (language != null && language.isNotEmpty) {
        transcription['language'] = language;
      }
      _logger?.call('[RT-TRANSCRIPTION]',
          'model=$_transcriptionModel language=${language ?? 'auto'}');
      input['transcription'] = transcription;
      if (_autoRespond) {
        _logger?.call('[RT-TRANSCRIPTION]',
            'parallel_for_subtitle_only mode=$_mode (응답 대기 없음)');
      }
      audio['input'] = input;
    }
    final session = <String, dynamic>{
      'type': 'realtime',
      'model': 'gpt-realtime-2.1-mini',
      'output_modalities': <String>['audio'],
      'instructions': instructions,
      'audio': audio,
    };
    // ⚠️ 여기에 temperature나 max_output_tokens를 넣지 말 것.
    //  - temperature: GA Realtime 세션이 거부한다.
    //    code=unknown_parameter param=session.temperature → 세션 설정 전체 실패.
    //  - max_output_tokens: 이 값은 "오디오" 출력 토큰까지 센다. 200으로 두었더니
    //    번역문이 예산을 다 써서 AI 응답이 "That" / "You" 한 단어에서 잘렸다.
    //    응답 길이는 오직 프롬프트로 제어한다(기본 "inf" 유지).
    sendEvent(<String, dynamic>{
      'type': 'session.update',
      'session': session,
    });
  }

  void _handleServerEvent(String raw, int generation) {
    if (!_isCurrent(generation)) {
      _emit(RealtimeEventType.staleEventDropped);
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final payload = Map<String, dynamic>.from(decoded);
      final type = payload['type']?.toString() ?? '';
      _logInputTranscriptionEvent(type, payload);
      if (_autoRespond) _trackConversationLatency(type);
      if (type == 'session.updated') {
        _confirmSessionUpdated(payload);
      } else if (type == 'response.created') {
        _responseId = (payload['response'] as Map?)?['id']?.toString();
        _setTurnState(RealtimeTurnState.responseStreaming);
        if (_captureMicrophone && _activeTurn == null) {
          _logger?.call(
              '[RT-TRANSCRIBE]', 'unexpected_auto_response response_created');
        }
      } else if (type == 'response.done') {
        _setTurnState(RealtimeTurnState.completed);
      } else if (type == 'error' || type == 'response.failed') {
        _logServerErrorDiagnostics(type, payload);
        _setTurnState(RealtimeTurnState.failed);
        final completer = _sessionUpdatedCompleter;
        if (!_sessionUpdatedConfirmed &&
            completer != null &&
            !completer.isCompleted) {
          completer.completeError(StateError('Realtime session update failed.'));
        }
        _emit(RealtimeEventType.error, payload: payload);
      }
      _routeTurnEvent(type, payload);
      _emit(RealtimeEventType.serverEvent, payload: payload);
    } catch (_) {
      final completer = _sessionUpdatedCompleter;
      if (!_sessionUpdatedConfirmed &&
          completer != null &&
          !completer.isCompleted) {
        completer.completeError(
            StateError('Realtime session event parsing failed.'));
      }
      _emit(RealtimeEventType.error);
    }
  }

  void _confirmSessionUpdated(Map<String, dynamic> payload) {
    // ⚠️ [DIAGNOSTIC] session.updated 스키마 확인용 임시 로그. 원인 확정 후 제거.
    _logSessionUpdatedRaw(payload);
    bool valid = true;
    if (_captureMicrophone && !_disableServerVad) {
      final session = payload['session'];
      final audio = session is Map ? session['audio'] : null;
      final input = audio is Map ? audio['input'] : null;
      final transcription = input is Map ? input['transcription'] : null;
      final turnDetection = input is Map ? input['turn_detection'] : null;
      // 성공 필수 조건은 "세션 객체 정상 + turn detection이 실제로 server VAD"
      // 까지다. 서버가 에코하지 않을 수 있는 선택 필드(create_response,
      // transcription)의 부재를 실패 사유로 삼지 않는다. 반대로 명백히 다른 값이
      // 확정돼 돌아오면 계속 실패 처리한다.
      final createResponse =
          turnDetection is Map ? turnDetection['create_response'] : null;
      valid = session is Map &&
          turnDetection is Map &&
          turnDetection['type']?.toString() == 'server_vad' &&
          (createResponse == null || createResponse == _autoRespond);
      _logSessionUpdatedCheck(
        session: session,
        audio: audio,
        input: input,
        transcription: transcription,
        turnDetection: turnDetection,
        valid: valid,
      );
    } else {
      _logger?.call(
        '[RT-SESSION-UPDATED-CHECK]',
        'validation_skipped captureMicrophone=$_captureMicrophone '
            'disableServerVad=$_disableServerVad valid=true',
      );
    }

    final completer = _sessionUpdatedCompleter;
    if (!valid) {
      if (completer != null && !completer.isCompleted) {
        completer.completeError(
            StateError('Realtime transcription session was not configured.'));
      }
      return;
    }
    _sessionUpdatedConfirmed = true;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _logger?.call('[RT-SESSION]', 'updated_confirmed');
    _setReadyWhenConfigured();
  }

  // ⚠️ [DIAGNOSTIC] 아래 3개 메서드는 session.updated 스키마 진단용 임시 코드다.
  //   원인이 확정되면 제거한다. 로그에는 client secret / instructions / SDP 등
  //   민감값을 절대 싣지 않는다.
  static const Set<String> _diagnosticRedactedKeys = <String>{
    'client_secret',
    'instructions',
    'sdp',
    'api_key',
    'token',
    'authorization',
  };

  Object? _redactForDiagnostics(Object? value) {
    if (value is Map) {
      final result = <String, dynamic>{};
      value.forEach((key, dynamic child) {
        final name = key.toString();
        if (_diagnosticRedactedKeys.contains(name.toLowerCase())) {
          result[name] = child is String
              ? '<redacted len=${child.length}>'
              : '<redacted>';
        } else {
          result[name] = _redactForDiagnostics(child);
        }
      });
      return result;
    }
    if (value is List) {
      return value.map<Object?>(_redactForDiagnostics).toList();
    }
    return value;
  }

  void _logSessionUpdatedRaw(Map<String, dynamic> payload) {
    try {
      final encoded = jsonEncode(_redactForDiagnostics(payload));
      // logcat 한 줄 길이 제한을 피하려고 조각내서 남긴다.
      const chunkSize = 700;
      final total = (encoded.length / chunkSize).ceil();
      for (var i = 0; i < total; i++) {
        final start = i * chunkSize;
        final end =
            start + chunkSize < encoded.length ? start + chunkSize : encoded.length;
        _logger?.call('[RT-SESSION-UPDATED-RAW]',
            'part=${i + 1}/$total ${encoded.substring(start, end)}');
      }
    } catch (error) {
      _logger?.call(
          '[RT-SESSION-UPDATED-RAW]', 'encode_failed reason=${error.runtimeType}');
    }
  }

  void _logSessionUpdatedCheck({
    required Object? session,
    required Object? audio,
    required Object? input,
    required Object? transcription,
    required Object? turnDetection,
    required bool valid,
  }) {
    try {
      final failures = <String>[];
      if (session is! Map) {
        failures.add('session expected=Map got=${session.runtimeType}');
      }
      if (audio is! Map) {
        failures.add('session.audio expected=Map got=${audio.runtimeType}');
      }
      if (input is! Map) {
        failures.add('session.audio.input expected=Map got=${input.runtimeType}');
      }
      if (turnDetection is! Map) {
        failures.add('session.audio.input.turn_detection expected=Map '
            'got=${turnDetection.runtimeType} value=$turnDetection');
      } else {
        final type = turnDetection['type'];
        if (type?.toString() != 'server_vad') {
          failures.add("turn_detection.type expected='server_vad' got='$type'");
        }
        final createResponse = turnDetection['create_response'];
        if (createResponse != null && createResponse != _autoRespond) {
          failures.add('turn_detection.create_response expected=$_autoRespond '
              'or omitted got=$createResponse type=${createResponse.runtimeType}');
        }
      }
      final td = turnDetection is Map ? turnDetection : null;
      _logger?.call(
        '[RT-SESSION-UPDATED-CHECK]',
        'expected_conditions="session is Map && turn_detection is Map && '
            "turn_detection['type']=='server_vad' && "
            '(create_response omitted || create_response==$_autoRespond)" '
            'autoRespond=$_autoRespond '
            'valid=$valid '
            'session_keys=${session is Map ? session.keys.toList() : null} '
            'audio_keys=${audio is Map ? audio.keys.toList() : null} '
            'input_keys=${input is Map ? input.keys.toList() : null} '
            'transcription=${transcription is Map ? transcription : transcription} '
            'turn_detection=$td '
            'turn_detection_type=${td?['type']} '
            'create_response=${td?['create_response']} '
            'create_response_present=${td?.containsKey('create_response')} '
            'interrupt_response=${td?['interrupt_response']} '
            'interrupt_response_present=${td?.containsKey('interrupt_response')} '
            'failed_fields=${failures.isEmpty ? 'none' : failures.join(' | ')}',
      );
    } catch (error) {
      _logger?.call(
          '[RT-SESSION-UPDATED-CHECK]', 'log_failed reason=${error.runtimeType}');
    }
  }

  void _logServerErrorDiagnostics(String type, Map<String, dynamic> payload) {
    try {
      final error = payload['error'];
      final detail = error is Map
          ? 'code=${error['code']} type=${error['type']} '
              'param=${error['param']} message=${error['message']}'
          : 'raw=${_redactForDiagnostics(payload)}';
      _logger?.call('[RT-SERVER-ERROR]', 'event=$type $detail');
    } catch (logError) {
      _logger?.call(
          '[RT-SERVER-ERROR]', 'log_failed reason=${logError.runtimeType}');
    }
  }

  /// 🗣️ [RT-CONV] 음성 직결 모드의 턴 경로와 지연을 측정한다. WebRTC에서는
  /// 오디오가 미디어 트랙으로 오므로 "첫 오디오"는 데이터채널의 오디오 신호
  /// 이벤트(output_audio_buffer.started / response.output_audio.delta)를 기준으로
  /// 잡는다. 실제 스피커 재생 시각과는 미세한 차이가 있을 수 있다.
  void _trackConversationLatency(String type) {
    final now = DateTime.now();
    switch (type) {
      case 'input_audio_buffer.speech_started':
        // 유저가 말을 시작하면 AI는 즉시 멈추고 유저 발화부터 처리한다.
        // interrupt_response는 서버의 생성만 중단시키므로, 이미 전송돼 클라이언트
        // 버퍼에 남은 오디오까지 비워야 두 목소리가 겹치지 않는다.
        if (_outputAudioActive) {
          sendEvent(<String, dynamic>{'type': 'output_audio_buffer.clear'});
          _outputAudioActive = false;
          _logger?.call('[RT-BARGE-IN]', 'user_speech_started → ai_audio_stopped');
        }
        _convSpeechStoppedAt = null;
        _convResponseCreatedAt = null;
        _convFirstTextAt = null;
        _convFirstAudioAt = null;
        return;
      case 'input_audio_buffer.speech_stopped':
        _convSpeechStoppedAt = now;
        return;
      case 'response.created':
        _convResponseCreatedAt = now;
        _convTurnCount++;
        _logger?.call('[RT-PATH]', '${_mode}_realtime_mini turnId=$_convTurnCount');
        return;
      case 'response.output_audio_transcript.delta':
      case 'response.audio_transcript.delta':
        _convFirstTextAt ??= now;
        return;
      case 'output_audio_buffer.started':
      case 'response.output_audio.delta':
      case 'response.audio.delta':
        _outputAudioActive = true;
        _muteMicForAiPlayback();
        if (_convFirstAudioAt == null) {
          _convFirstAudioAt = now;
          _logger?.call('[RT-PLAY]', 'secure WebRTC remote audio signal=$type');
        }
        return;
      case 'output_audio_buffer.cleared':
      case 'output_audio_buffer.stopped':
        _outputAudioActive = false;
        _restoreMicAfterAiPlayback();
        _emitConversationLatency(endedAt: now);
        return;
      case 'response.done':
        // 오디오 버퍼 이벤트가 없는 응답(텍스트만)에서도 마이크가 닫힌 채로
        // 남지 않도록 보정한다.
        _restoreMicAfterAiPlayback();
        _emitConversationLatency(endedAt: now);
        return;
    }
  }

  void _emitConversationLatency({required DateTime endedAt}) {
    final speechEnd = _convSpeechStoppedAt;
    if (speechEnd == null && _convResponseCreatedAt == null) return;
    String ms(DateTime? from, DateTime? to) {
      if (from == null || to == null) return 'n/a';
      return to.difference(from).inMilliseconds.toString();
    }

    final audioStart = _convFirstAudioAt ?? _convFirstTextAt;
    _logger?.call(
      '[RT-LATENCY]',
      'turnId=$_convTurnCount '
          'speechEndToResponseCreatedMs=${ms(speechEnd, _convResponseCreatedAt)} '
          'speechEndToFirstTextMs=${ms(speechEnd, _convFirstTextAt)} '
          'speechEndToFirstAudioMs=${ms(speechEnd, audioStart)} '
          'playbackDurationMs=${ms(audioStart, endedAt)} '
          'firstAudioSource=${_convFirstAudioAt != null ? 'audio_event' : 'text_proxy'} '
          'fallback=false',
    );
    _convSpeechStoppedAt = null;
    _convResponseCreatedAt = null;
    _convFirstTextAt = null;
    _convFirstAudioAt = null;
  }

  void _logInputTranscriptionEvent(
      String type, Map<String, dynamic> payload) {
    final itemId = payload['item_id']?.toString() ?? '';
    switch (type) {
      case 'input_audio_buffer.speech_started':
        _logger?.call('[RT-TRANSCRIBE]', 'speech_started itemId=$itemId');
        break;
      case 'input_audio_buffer.speech_stopped':
        _logger?.call('[RT-TRANSCRIBE]', 'speech_stopped itemId=$itemId');
        break;
      case 'conversation.item.input_audio_transcription.delta':
        final deltaLength = payload['delta']?.toString().length ?? 0;
        _logger?.call('[RT-TRANSCRIBE]',
            'transcription_delta itemId=$itemId len=$deltaLength');
        break;
      case 'conversation.item.input_audio_transcription.completed':
        final transcriptLength =
            payload['transcript']?.toString().trim().length ?? 0;
        _logger?.call('[RT-TRANSCRIBE]',
            'transcription_completed itemId=$itemId len=$transcriptLength');
        break;
    }
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _connectionGeneration;

  void _assertCurrent(int generation) {
    if (!_isCurrent(generation)) throw StateError('Stale Realtime session.');
  }

  void _setReadyWhenConfigured() {
    if (_peerConnected && _sessionUpdatedConfirmed) {
      _setConnectionState(RealtimeConnectionState.ready);
    }
  }

  void _setConnectionState(RealtimeConnectionState state) {
    _connectionState = state;
    _emit(RealtimeEventType.stateChanged, connectionState: state);
  }

  void _setTurnState(RealtimeTurnState state) {
    _turnState = state;
    _emit(RealtimeEventType.turnStateChanged, turnState: state);
  }

  void _emit(
    RealtimeEventType type, {
    RealtimeConnectionState? connectionState,
    RealtimeTurnState? turnState,
    Map<String, dynamic>? payload,
    MediaStream? remoteStream,
  }) {
    if (!_events.isClosed) {
      _events.add(RealtimeSessionEvent(
        type: type,
        connectionState: connectionState,
        turnState: turnState,
        payload: payload,
        remoteStream: remoteStream,
      ));
    }
  }
}
