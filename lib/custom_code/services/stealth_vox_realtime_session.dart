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

  Stream<RealtimeSessionEvent> get events => _events.stream;
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
  }) async {
    if (_disposed) throw StateError('Realtime session is disposed.');
    if (!allowWhenDisabled && !RealtimeFeatureFlags.enabledFor(mode)) {
      throw StateError('Realtime feature flag is disabled for $mode.');
    }
    if (isReady || _connectionState == RealtimeConnectionState.connecting) {
      return;
    }
    _logger?.call('[RT-PATH]', 'secure_webrtc mode=$mode');
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
      _localStream = await navigator.mediaDevices.getUserMedia(
        <String, dynamic>{'audio': true, 'video': false},
      );
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isEmpty) throw StateError('No local microphone track.');
      await peer.addTrack(audioTracks.first, _localStream!);

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
    if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel!.send(
        RTCDataChannelMessage(jsonEncode(<String, dynamic>{
          'type': 'response.cancel',
        })),
      );
      _dataChannel!.send(
        RTCDataChannelMessage(jsonEncode(<String, dynamic>{
          'type': 'output_audio_buffer.clear',
        })),
      );
    }
    _responseId = null;
    _setTurnState(RealtimeTurnState.cancelled);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
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
    sendEvent(<String, dynamic>{
      'type': 'session.update',
      'session': <String, dynamic>{
        'type': 'realtime',
        'model': 'gpt-realtime-2.1-mini',
        'output_modalities': <String>['audio'],
        'instructions': instructions,
        'audio': <String, dynamic>{
          'output': <String, dynamic>{'voice': voice},
        },
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
