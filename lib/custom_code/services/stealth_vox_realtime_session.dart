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
  RealtimeTranslationTurn? _activeTurn;
  Timer? _turnTimeoutTimer;
  Timer? _audioTailTimer;
  Duration _audioStabilization = const Duration(milliseconds: 250);
  Duration _audioTailTimeout = const Duration(seconds: 5);

  Stream<RealtimeSessionEvent> get events => _events.stream;
  RealtimeTranslationTurn? get activeTurn => _activeTurn;
  RealtimeConnectionState get connectionState => _connectionState;
  RealtimeTurnState get turnState => _turnState;
  bool get isReady => _connectionState == RealtimeConnectionState.ready;
  String? get modeSessionId => _modeSessionId;
  String? get responseId => _responseId;

  Future<void> connect({
    required String mode,
    required String modeSessionId,
    String voice = 'marin',
    String instructions = '',
    bool allowWhenDisabled = false,
    bool captureMicrophone = true,
    bool disableServerVad = false,
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
    _modeSessionId = modeSessionId;
    final generation = ++_connectionGeneration;
    String stage = 'secret';
    try {
      _setConnectionState(RealtimeConnectionState.requestingToken);
      final secret = await _secretService.create(mode: mode, logger: _logger);
      _assertCurrent(generation);
      _setConnectionState(RealtimeConnectionState.connecting);

      stage = 'peer_connection';
      final peer = await createPeerConnection(<String, dynamic>{});
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
        _logger?.call('[RT-ICE]', _iceStateLabel(state));
      };
      peer.onConnectionState = (state) {
        if (!_isCurrent(generation)) {
          _emit(RealtimeEventType.staleEventDropped);
          return;
        }
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _setConnectionState(RealtimeConnectionState.ready);
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _setConnectionState(RealtimeConnectionState.failed);
        }
      };

      stage = 'microphone';
      if (_captureMicrophone) {
        _localStream = await navigator.mediaDevices.getUserMedia(
          <String, dynamic>{'audio': true, 'video': false},
        );
        final audioTracks = _localStream!.getAudioTracks();
        if (audioTracks.isEmpty) {
          throw StateError('No local microphone track.');
        }
        await peer.addTrack(audioTracks.first, _localStream!);
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
      _dataChannel = await peer.createDataChannel(
        'oai-events',
        RTCDataChannelInit(),
      );
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
      final offer = await peer.createOffer(<String, dynamic>{});
      await peer.setLocalDescription(offer);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final localDescription = await peer.getLocalDescription();
      final sdp = localDescription?.sdp;
      if (sdp == null || sdp.isEmpty) throw StateError('Local SDP is empty.');
      _logger?.call('[RT-SDP]', 'offer_created');

      stage = 'sdp_answer';
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/realtime/calls'),
        headers: <String, String>{
          'Authorization': 'Bearer ${secret.value}',
          'Content-Type': 'application/sdp',
        },
        body: sdp,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Realtime SDP negotiation failed.');
      }
      await peer.setRemoteDescription(
        RTCSessionDescription(response.body, 'answer'),
      );
      _logger?.call('[RT-SDP]', 'answer_applied');
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
        'output': <String, dynamic>{'voice': voice},
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
        break;
      case 'output_audio_buffer.stopped':
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
    // stop (WebRTC) with a stabilization delay, then a hard fallback timeout.
    if (turn._expectAudio && !turn._audioDone) {
      _audioTailTimer?.cancel();
      _audioTailTimer = Timer(_audioTailTimeout, () {
        if (!identical(_activeTurn, turn) || turn.isSettled) return;
        turn._completeAudio();
        _logger?.call('[RT-AUDIO]', 'completion_timeout turnId=${turn.turnId}');
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
    await _localStream?.dispose();
    await _dataChannel?.close();
    await _peerConnection?.close();
    _dataChannel = null;
    _peerConnection = null;
    _setConnectionState(RealtimeConnectionState.closed);
    await _events.close();
  }

  void _sendSessionUpdate(
      {required String voice, required String instructions}) {
    final audio = <String, dynamic>{
      'output': <String, dynamic>{'voice': voice},
    };
    if (_disableServerVad) {
      // Text-driven turns must never auto-respond to inbound audio.
      audio['input'] = <String, dynamic>{'turn_detection': null};
    }
    sendEvent(<String, dynamic>{
      'type': 'session.update',
      'session': <String, dynamic>{
        'type': 'realtime',
        'model': 'gpt-realtime-2.1-mini',
        'output_modalities': <String>['audio'],
        'instructions': instructions,
        'audio': audio,
      },
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
      if (type == 'response.created') {
        _responseId = (payload['response'] as Map?)?['id']?.toString();
        _setTurnState(RealtimeTurnState.responseStreaming);
      } else if (type == 'response.done') {
        _setTurnState(RealtimeTurnState.completed);
      } else if (type == 'error' || type == 'response.failed') {
        _setTurnState(RealtimeTurnState.failed);
        _emit(RealtimeEventType.error, payload: payload);
      }
      _routeTurnEvent(type, payload);
      _emit(RealtimeEventType.serverEvent, payload: payload);
    } catch (_) {
      _emit(RealtimeEventType.error);
    }
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _connectionGeneration;

  void _assertCurrent(int generation) {
    if (!_isCurrent(generation)) throw StateError('Stale Realtime session.');
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
