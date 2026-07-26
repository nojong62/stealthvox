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
  bool _playbackStarted = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  @override
  void dispose() {
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
    setState(() {
      _running = true;
      _playbackStarted = false;
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
      if (mounted) setState(() => _status = 'negotiated — waiting for audio');
    } catch (e) {
      // 자동 폴백 없음: 실패 로그만 남기고 세션을 정리한다.
      if (mounted) setState(() => _status = 'failed — 종료(폴백 없음)');
      await _sub?.cancel();
      _sub = null;
      await session.dispose();
      _session = null;
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _onEvent(RealtimeSessionEvent event) async {
    switch (event.type) {
      case RealtimeEventType.stateChanged:
        final name = event.connectionState?.name;
        if (name != null && mounted) setState(() => _status = name);
        break;
      case RealtimeEventType.remoteAudioTrack:
        if (!_playbackStarted) {
          _playbackStarted = true;
          try {
            await Helper.setSpeakerphoneOn(true);
          } catch (_) {}
          _log('[RT-AUDIO]', 'playback_started');
          if (mounted) setState(() => _status = 'audio playing');
        }
        break;
      case RealtimeEventType.error:
        _log('[RT-ERROR]', 'stage=session reason=server_event');
        break;
      default:
        break;
    }
  }

  Future<void> _restart() async {
    await _sub?.cancel();
    _sub = null;
    await _session?.dispose();
    _session = null;
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
