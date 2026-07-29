import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/realtime_feature_flags.dart';
import '../services/stealth_vox_realtime_session.dart';

// ====================================================================
// 🛰️ [PHASE 2 PROBE] 신규 보안 WebRTC 경로 실기기 연결 검증 전용 위젯
// --------------------------------------------------------------------
// 이 위젯은 오직 신규 공용 계층(StealthVoxRealtimeSession)만 사용한다.
//   - FirstTurnRealtimeVoice / 기존 WebSocket Realtime → 호출하지 않음
//   - 같은 턴의 Deepgram / GPT / TTS → 호출하지 않음
//   - 연결 실패 시 자동 폴백 없음. [RT-ERROR] 로그만 남기고 종료한다.
//
// 진입 조건:
//   feature flag ON  → 신규 WebRTC 테스트 경로 실행
//   feature flag OFF → 실행하지 않음(서버 flag가 아직 꺼져 있어도 실기기
//                      검증을 돌릴 수 있게 forceEnable로 우회 가능)
// ====================================================================
class RealtimeWebrtcProbe extends StatefulWidget {
  const RealtimeWebrtcProbe({
    super.key,
    this.width,
    this.height,
    this.mode = 'anyone',
    this.forceEnable = true,
    this.autoStart = true,
  });

  final double? width;
  final double? height;

  /// 검증할 모드 flag 키('anyone' 등).
  final String mode;

  /// 서버 flag가 아직 꺼져 있어도 실기기 검증을 돌릴 수 있게 한다.
  /// 켜지면 connect(allowWhenDisabled: true)로 진입한다.
  final bool forceEnable;

  final bool autoStart;

  @override
  State<RealtimeWebrtcProbe> createState() => _RealtimeWebrtcProbeState();
}

class _RealtimeWebrtcProbeState extends State<RealtimeWebrtcProbe> {
  StealthVoxRealtimeSession? _session;
  StreamSubscription<RealtimeSessionEvent>? _sub;
  final List<String> _logs = <String>[];
  String _status = 'idle';
  bool _running = false;
  bool _speakerReady = false;
  bool _micEnabled = true;
  bool _translationRunning = false;
  bool _awaitingPostEnableTranscript = false;
  String _translationText = '';
  DateTime? _micDisabledAt;
  final Set<String> _activeInputItemIds = <String>{};
  final Set<String> _mutedCarryoverItemIds = <String>{};
  int _probeGeneration = 0;
  bool _disposing = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  @override
  void dispose() {
    _disposing = true;
    ++_probeGeneration;
    _session?.cancelActiveTurn();
    _sub?.cancel();
    _session?.dispose();
    super.dispose();
  }

  void _log(String tag, String detail) {
    final line = '$tag $detail';
    debugPrint('🛰️ $line');
    if (!mounted) return;
    setState(() {
      _logs.insert(0, line);
      if (_logs.length > 80) _logs.removeLast();
    });
  }

  Future<void> _start() async {
    if (_running) return;
    final generation = ++_probeGeneration;
    setState(() {
      _running = true;
      _speakerReady = false;
      _micEnabled = true;
      _translationRunning = false;
      _awaitingPostEnableTranscript = false;
      _translationText = '';
      _micDisabledAt = null;
      _activeInputItemIds.clear();
      _mutedCarryoverItemIds.clear();
      _status = 'connecting';
    });

    final bool enabled = RealtimeFeatureFlags.enabledFor(widget.mode);
    _log('[RT-FLAG]', 'enabled=$enabled');
    if (!enabled && !widget.forceEnable) {
      _log('[RT-PROBE]', 'skipped reason=flag_off (기존 운영 경로)');
      setState(() {
        _status = 'flag off — 기존 운영 경로';
        _running = false;
      });
      return;
    }

    final session = StealthVoxRealtimeSession(logger: _log);
    _session = session;
    _sub = session.events.listen(_onEvent);

    try {
      await session.connect(
        mode: widget.mode,
        modeSessionId: 'probe-${DateTime.now().microsecondsSinceEpoch}',
        allowWhenDisabled: widget.forceEnable,
      );
      if (_isCurrentSession(session, generation)) {
        setState(() => _status = 'negotiated — speak once');
      }
    } catch (e) {
      // 자동 폴백 없음: 실패 로그만 남기고 세션을 정리한다.
      if (_isCurrentSession(session, generation)) {
        setState(() => _status = 'failed — 종료(폴백 없음)');
      }
      await _sub?.cancel();
      _sub = null;
      await session.dispose();
      if (identical(_session, session)) _session = null;
    } finally {
      if (mounted && generation == _probeGeneration) {
        setState(() => _running = false);
      }
    }
  }

  Future<void> _onEvent(RealtimeSessionEvent event) async {
    switch (event.type) {
      case RealtimeEventType.stateChanged:
        final name = event.connectionState?.name;
        if (name != null && mounted) setState(() => _status = name);
        break;
      case RealtimeEventType.remoteAudioTrack:
        if (!_speakerReady) {
          _speakerReady = true;
          try {
            await Helper.setSpeakerphoneOn(true);
          } catch (_) {}
          _log('[RT-AUDIO]', 'speaker_ready');
        }
        break;
      case RealtimeEventType.serverEvent:
        _handleServerEvent(event.payload);
        break;
      case RealtimeEventType.error:
        _log('[RT-ERROR]', 'stage=session reason=server_event');
        break;
      default:
        break;
    }
  }

  void _handleServerEvent(Map<String, dynamic>? payload) {
    if (payload == null) return;
    final type = payload['type']?.toString() ?? '';
    final itemId = payload['item_id']?.toString() ?? '';

    if (type == 'output_audio_buffer.started') {
      _log('[RT-AUDIO]', 'playback_started');
      if (mounted) setState(() => _status = 'translation audio playing');
      return;
    }

    const inputEventTypes = <String>{
      'input_audio_buffer.speech_started',
      'conversation.item.input_audio_transcription.delta',
      'conversation.item.input_audio_transcription.completed',
    };
    if (!inputEventTypes.contains(type)) return;

    final wasAlreadyActive = _activeInputItemIds.contains(itemId);
    if (type == 'input_audio_buffer.speech_started' && itemId.isNotEmpty) {
      _activeInputItemIds.add(itemId);
    }

    if (!_micEnabled) {
      final isCarryover =
          itemId.isNotEmpty && _mutedCarryoverItemIds.contains(itemId);
      if (!isCarryover) {
        _log(
          '[RT-MIC-TEST]',
          'transcript_while_muted event=$type itemId=$itemId '
              'disabledAt=${_micDisabledAt?.toIso8601String() ?? "unknown"} '
              'wasActiveBeforeMute=$wasAlreadyActive',
        );
      } else {
        _log('[RT-MIC-TEST]',
            'delayed_pre_mute_event event=$type itemId=$itemId');
      }
    } else if (type ==
        'conversation.item.input_audio_transcription.completed') {
      final transcriptLength =
          payload['transcript']?.toString().trim().length ?? 0;
      if (transcriptLength > 0) {
        if (_awaitingPostEnableTranscript) {
          _awaitingPostEnableTranscript = false;
          _log('[RT-MIC-TEST]',
              'post_enable_transcript_received itemId=$itemId len=$transcriptLength');
          if (mounted) {
            setState(() => _status = 'post-enable transcript received');
          }
        } else {
          _log('[RT-MIC-TEST]',
              'active_transcript_received itemId=$itemId len=$transcriptLength');
        }
      }
    }

    if (type == 'conversation.item.input_audio_transcription.completed') {
      _activeInputItemIds.remove(itemId);
      _mutedCarryoverItemIds.remove(itemId);
    }
  }

  bool _isCurrentSession(
          StealthVoxRealtimeSession session, int generation) =>
      mounted &&
      !_disposing &&
      generation == _probeGeneration &&
      identical(_session, session);

  bool get _sessionUsable {
    final state = _session?.connectionState;
    return state == RealtimeConnectionState.ready ||
        state == RealtimeConnectionState.configuring;
  }

  bool _disableMicrophone({
    required StealthVoxRealtimeSession session,
    required int generation,
  }) {
    if (!_isCurrentSession(session, generation) || !_sessionUsable) return false;
    _micDisabledAt = DateTime.now();
    _mutedCarryoverItemIds
      ..clear()
      ..addAll(_activeInputItemIds);
    _log(
      '[RT-MIC-TEST]',
      'disable_requested disabledAt=${_micDisabledAt!.toIso8601String()} '
          'carryoverItemIds=${_mutedCarryoverItemIds.join(",")}',
    );
    try {
      session.setMicrophoneEnabled(false);
      if (mounted) {
        setState(() {
          _micEnabled = false;
          _status = 'microphone disabled';
        });
      }
      return true;
    } catch (e) {
      _log('[RT-ERROR]', 'stage=mic_disable reason=${e.runtimeType}');
      return false;
    }
  }

  bool _enableMicrophone({
    required StealthVoxRealtimeSession session,
    required int generation,
    bool expectNextTranscript = false,
  }) {
    if (!_isCurrentSession(session, generation) || !_sessionUsable) return false;
    _log('[RT-MIC-TEST]', 'enable_requested');
    try {
      session.setMicrophoneEnabled(true);
      if (mounted) {
        setState(() {
          _micEnabled = true;
          _micDisabledAt = null;
          _mutedCarryoverItemIds.clear();
          _awaitingPostEnableTranscript = expectNextTranscript;
          _status = expectNextTranscript
              ? 'microphone enabled — speak again'
              : 'microphone enabled';
        });
      }
      return true;
    } catch (e) {
      _log('[RT-ERROR]', 'stage=mic_enable reason=${e.runtimeType}');
      return false;
    }
  }

  void _disableMicButton() {
    final session = _session;
    if (session == null) return;
    _disableMicrophone(session: session, generation: _probeGeneration);
  }

  void _enableMicButton() {
    final session = _session;
    if (session == null) return;
    _enableMicrophone(session: session, generation: _probeGeneration);
  }

  Future<void> _runTranslationTest() async {
    final session = _session;
    if (session == null || _translationRunning || !_sessionUsable) return;
    final generation = _probeGeneration;
    if (!_disableMicrophone(session: session, generation: generation)) return;

    setState(() {
      _translationRunning = true;
      _translationText = '';
    });
    StreamSubscription<String>? textSub;
    try {
      _log('[RT-MIC-TEST]', 'translation_requested');
      final turn = session.requestTranslatedTurn(
        turnId: 'probe-mic-${DateTime.now().microsecondsSinceEpoch}',
        sourceText: '마이크 음소거 재전사 검증입니다.',
        instructions:
            'Translate the user sentence into natural English. Return only '
            'the translation, without labels, notes, or alternatives.',
        voice: 'marin',
      );
      textSub = turn.textStream.listen((delta) {
        if (!_isCurrentSession(session, generation)) return;
        setState(() => _translationText += delta);
      });
      final outcome = await turn.done;
      final finalText = (await turn.finalText).trim();
      if (!_isCurrentSession(session, generation)) return;
      if (outcome != RealtimeTurnOutcome.completed || finalText.isEmpty) {
        throw StateError('Translation probe did not complete.');
      }
      setState(() {
        _translationText = finalText;
        _status = 'translation playback complete';
      });
      _log('[RT-MIC-TEST]',
          'translation_completed textLen=${finalText.length}');
    } catch (e) {
      _log('[RT-ERROR]',
          'stage=translation_test reason=${e.runtimeType}');
    } finally {
      await textSub?.cancel();
      if (_isCurrentSession(session, generation) && !_micEnabled) {
        _enableMicrophone(
          session: session,
          generation: generation,
          expectNextTranscript: true,
        );
      }
      if (mounted && generation == _probeGeneration) {
        setState(() => _translationRunning = false);
      }
    }
  }

  Future<void> _restart() async {
    ++_probeGeneration;
    _session?.cancelActiveTurn();
    await _sub?.cancel();
    _sub = null;
    await _session?.dispose();
    _session = null;
    if (!mounted) return;
    setState(() {
      _logs.clear();
      _status = 'idle';
    });
    await _start();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: const Color(0xFF0E1116),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '🛰️ WebRTC Probe',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton(
                onPressed: _running ? null : _restart,
                child: Text(_running ? '...' : 'Restart'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'status: $_status',
            style: const TextStyle(color: Color(0xFF7EE787), fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _sessionUsable && _micEnabled && !_translationRunning
                    ? _disableMicButton
                    : null,
                child: const Text('Mic Disable'),
              ),
              OutlinedButton(
                onPressed:
                    _sessionUsable && !_micEnabled && !_translationRunning
                        ? _enableMicButton
                        : null,
                child: const Text('Mic Enable'),
              ),
              ElevatedButton(
                onPressed: _sessionUsable && !_translationRunning
                    ? _runTranslationTest
                    : null,
                child: Text(
                    _translationRunning ? 'Translation...' : 'Translation Test'),
              ),
            ],
          ),
          if (_translationText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _translationText,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
          const Divider(color: Colors.white24, height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  _logs[i],
                  style: const TextStyle(
                    color: Color(0xFFD1D5DB),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
