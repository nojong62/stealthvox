// 🌬️ [BREATH-ECHO] AI 한 호흡 → 유저가 혼자 따라 말하기, 를 한 계단 동안
//   굴리는 상태 머신.
//
//   **동시 낭독이 아니다.** AI가 완전히 끝난 뒤에 마이크를 열고, 유저가
//   멈춘 뒤에 다음 호흡을 연다. 둘이 절대 겹치지 않는다.
//
//   UI를 그리지 않는다. 화면은 콜백만 받는다 — P3도 같은 엔진을 쓴다.
//
//   ⚠️ **recorder는 빌려 쓴다.** `appAudioRecorder`는 P1·P2·P3가 공유하는
//   물건이라 엔진이 만들지도 없애지도 않는다. 쓰는 동안만 붙잡았다가
//   [stop]에서 반드시 놓는다.

import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'audio_silence_analyzer.dart';
import 'breath_segment.dart';

enum BreathEchoPhase {
  idle,
  aiPlaying,
  waitingForUser,
  userSpeaking,
  advancing,
  completed,
  cancelled,
}

/// 🚧 P2 Breath 전용 상수. **다른 기능의 VAD 값과 무관하다** —
/// `_startAutoVADRecording`(P1·튜터)·Circle·Scenario·Duo는 건드리지 않는다.
/// 실기기에서 조정할 값이라 여기 한 곳에 모아 둔다.
class BreathEchoTiming {
  const BreathEchoTiming({
    this.userSilenceMs = 1500,
    this.noSpeechGiveUpMs = 8000,
    this.betweenBreathsMs = 250,
    this.repeatGapMs = 400,
  });

  /// 유저가 말을 멈춘 뒤 다음 호흡으로 넘어가기까지. 기존 앱 값(1,500ms)에서
  /// 시작하되 **P2 Breath에서는 길 가능성이 높다.** 실기기에서 줄여본다.
  final int userSilenceMs;

  /// 한 마디도 안 했을 때 이 호흡을 포기하기까지.
  final int noSpeechGiveUpMs;

  /// 유저가 끝나고 다음 AI 호흡까지의 숨.
  final int betweenBreathsMs;

  /// 두 번 말하기에서 듣기 재생과 다시 재생 사이.
  final int repeatGapMs;

  BreathEchoTiming copyWith({int? userSilenceMs}) => BreathEchoTiming(
        userSilenceMs: userSilenceMs ?? this.userSilenceMs,
        noSpeechGiveUpMs: noSpeechGiveUpMs,
        betweenBreathsMs: betweenBreathsMs,
        repeatGapMs: repeatGapMs,
      );
}

/// 마이크 스트림이 흐르는 동안 발성을 세는 자.
///
/// 청크 경계에서 프레임이 잘리지 않게 남는 바이트를 이월한다. 판정은
/// [isVoicedPcmFrame] 하나만 쓴다 — AI 쪽 분석과 같은 자다.
class _StreamVoiceMeter {
  _StreamVoiceMeter(this.cfg)
      : samplesPerFrame =
            (cfg.sampleRate * cfg.frameMs ~/ 1000).clamp(1, 1 << 20);

  final BreathAnalysisConfig cfg;
  final int samplesPerFrame;

  Uint8List _carry = Uint8List(0);
  int voicedFrameCount = 0;
  int trailingSilentFrames = 0;
  int totalFrameCount = 0;
  bool hasSpoken = false;

  int get bytesPerFrame => samplesPerFrame * 2;
  int get voicedMs => voicedFrameCount * cfg.frameMs;
  int get trailingSilenceMs => trailingSilentFrames * cfg.frameMs;
  int get elapsedMs => totalFrameCount * cfg.frameMs;

  void add(Uint8List chunk) {
    final Uint8List buffer;
    if (_carry.isEmpty) {
      buffer = chunk;
    } else {
      buffer = Uint8List(_carry.length + chunk.length)
        ..setRange(0, _carry.length, _carry)
        ..setRange(_carry.length, _carry.length + chunk.length, chunk);
    }
    final data = ByteData.sublistView(buffer);
    int offset = 0;
    while (offset + bytesPerFrame <= buffer.length) {
      final voiced = isVoicedPcmFrame(data, offset, samplesPerFrame, cfg);
      totalFrameCount++;
      if (voiced) {
        voicedFrameCount++;
        trailingSilentFrames = 0;
        hasSpoken = true;
      } else {
        trailingSilentFrames++;
      }
      offset += bytesPerFrame;
    }
    _carry = Uint8List.fromList(
        Uint8List.sublistView(buffer, offset)); // 뷰를 들고 있으면 원본이 안 풀린다
  }
}

/// 한 계단의 호흡 에코를 굴린다.
class BreathEchoingEngine {
  BreathEchoingEngine({
    required this.recorder,
    required this.onPhase,
    required this.onLineComplete,
    required this.onError,
    this.timing = const BreathEchoTiming(),
    this.analysisConfig = const BreathAnalysisConfig(),
  });

  /// 화면이 소유한 공용 recorder. 엔진은 빌려 쓸 뿐이다.
  final AudioRecorder recorder;

  /// (phase, breathIndex, totalBreaths)
  final void Function(BreathEchoPhase phase, int index, int total) onPhase;

  /// 계단의 모든 호흡이 끝났다. 유저 PCM과 발성 길이를 함께 넘긴다 —
  /// Practice Replay 조립은 화면이 한다.
  final void Function(List<Uint8List?> userPcm, List<int> userVoicedMs)
      onLineComplete;

  final void Function(String message) onError;

  final BreathEchoTiming timing;
  final BreathAnalysisConfig analysisConfig;

  int _generation = 0;
  bool _running = false;
  int _index = 0;
  int _repeatCount = 1;

  List<BreathSegment> _segments = const <BreathSegment>[];
  Uint8List _aiPcm = Uint8List(0);
  late List<Uint8List?> _userPcm;
  late List<int> _userVoicedMs;

  AudioPlayer? _player;
  StreamSubscription<Uint8List>? _micSub;
  Timer? _pollTimer;
  Completer<void>? _captureDone;

  bool get isRunning => _running;
  bool get isAiPlaying => _player != null;
  bool get isCapturing => _micSub != null;
  int get currentIndex => _index;
  int get totalBreaths => _segments.length;

  /// 계단 하나를 시작한다. [repeatCount]가 2면 AI를 두 번 들려준 뒤 유저가
  /// 따라 한다(기존 "두 번 말하기"의 듣기 회차 의미를 살린 것).
  Future<void> start({
    required Uint8List aiPcm,
    required List<BreathSegment> segments,
    int repeatCount = 1,
  }) async {
    await stop();
    if (segments.isEmpty || aiPcm.isEmpty) {
      onError('호흡 구간이 없다');
      return;
    }
    final generation = ++_generation;
    _running = true;
    _aiPcm = aiPcm;
    _segments = segments;
    _repeatCount = repeatCount.clamp(1, 3);
    _index = 0;
    _userPcm = List<Uint8List?>.filled(segments.length, null);
    _userVoicedMs = List<int>.filled(segments.length, 0);
    await _runBreath(generation);
  }

  Future<void> _runBreath(int generation) async {
    while (_running && generation == _generation && _index < _segments.length) {
      final segment = _segments[_index];

      // ── AI 호흡 ─────────────────────────────────────────────
      for (int pass = 0; pass < _repeatCount; pass++) {
        if (!_alive(generation)) return;
        onPhase(BreathEchoPhase.aiPlaying, _index, _segments.length);
        await _playSegment(segment, generation);
        if (!_alive(generation)) return;
        if (pass < _repeatCount - 1) {
          await _sleep(timing.repeatGapMs, generation);
        }
      }
      if (!_alive(generation)) return;

      // ── 유저 에코 ───────────────────────────────────────────
      //   AI가 완전히 끝난 뒤에만 마이크를 연다. 고정 대기는 두지 않는다 —
      //   실측 mic start latency가 15~32ms라 지연시킬 이유가 없다.
      onPhase(BreathEchoPhase.waitingForUser, _index, _segments.length);
      await _captureUserEcho(segment, generation);
      if (!_alive(generation)) return;

      onPhase(BreathEchoPhase.advancing, _index, _segments.length);
      await _sleep(timing.betweenBreathsMs, generation);
      if (!_alive(generation)) return;
      _index++;
    }

    if (!_alive(generation)) return;
    _running = false;
    onPhase(BreathEchoPhase.completed, _segments.length, _segments.length);
    onLineComplete(List<Uint8List?>.from(_userPcm), List<int>.from(_userVoicedMs));
  }

  bool _alive(int generation) => _running && generation == _generation;

  Future<void> _sleep(int ms, int generation) async {
    if (ms <= 0) return;
    await Future<void>.delayed(Duration(milliseconds: ms));
  }

  // ── AI 구간 재생 ──────────────────────────────────────────────
  Future<void> _playSegment(BreathSegment segment, int generation) async {
    final wav = sliceToWav(_aiPcm, segment,
        sampleRate: analysisConfig.sampleRate);
    final player = AudioPlayer();
    _player = player;
    final completer = Completer<void>();
    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    // ⚠️ onPlayerComplete.first를 쓰면 dispose 때 `Bad state: No element`가
    //   새어 대기가 무너진다(Lab에서 실기기로 확인). 구독을 직접 든다.
    final sub = player.onPlayerComplete.listen(
      (_) => finish(),
      onDone: finish,
      onError: (Object _) => finish(),
      cancelOnError: false,
    );
    try {
      await player.play(BytesSource(wav));
      await completer.future.timeout(
        Duration(milliseconds: segment.durationMs + 5000),
        onTimeout: finish,
      );
    } catch (e) {
      debugPrint('[BREATH-ECHO] ai play $e');
    } finally {
      await sub.cancel();
      if (identical(_player, player)) _player = null;
      try {
        await player.stop();
      } catch (_) {}
      try {
        await player.dispose();
      } catch (_) {}
    }
  }

  // ── 유저 에코 캡처 ────────────────────────────────────────────
  Future<void> _captureUserEcho(BreathSegment segment, int generation) async {
    if (!await _hasMic()) {
      onError('마이크 권한이 없다');
      return;
    }
    final capture = BytesBuilder();
    final meter = _StreamVoiceMeter(analysisConfig);
    final done = Completer<void>();
    _captureDone = done;

    try {
      final stream = await recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: analysisConfig.sampleRate,
          numChannels: 1,
        ),
      );
      if (!_alive(generation)) {
        await _stopCapture();
        return;
      }
      bool announcedSpeaking = false;
      _micSub = stream.listen(
        (data) {
          if (!_alive(generation)) return;
          capture.add(data);
          meter.add(data);
          if (meter.hasSpoken && !announcedSpeaking) {
            announcedSpeaking = true;
            onPhase(BreathEchoPhase.userSpeaking, _index, _segments.length);
          }
        },
        onError: (Object e) {
          debugPrint('[BREATH-ECHO] mic $e');
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: false,
      );

      // 마이크 스트림만으로는 "지금 몇 ms 조용한가"를 이벤트로 알 수 없어
      // 짧은 주기로 확인한다. 판정 자체는 스트림 데이터로만 한다.
      _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (!_alive(generation)) {
          timer.cancel();
          if (!done.isCompleted) done.complete();
          return;
        }
        final bool finished = meter.hasSpoken
            ? meter.trailingSilenceMs >= timing.userSilenceMs
            : meter.elapsedMs >= timing.noSpeechGiveUpMs;
        if (finished) {
          timer.cancel();
          if (!done.isCompleted) done.complete();
        }
      });

      await done.future;
    } catch (e) {
      onError('녹음 시작 실패: $e');
    } finally {
      await _stopCapture();
    }

    if (!_alive(generation)) return;
    final bytes = capture.takeBytes();
    if (meter.hasSpoken && bytes.isNotEmpty) {
      _userPcm[_index] = bytes;
      _userVoicedMs[_index] = meter.voicedMs;
    } else {
      // 한 마디도 안 했다. 이 칸은 조립에서 AI 호흡으로 대체된다.
      _userPcm[_index] = null;
      _userVoicedMs[_index] = 0;
    }
    debugPrint('[BREATH-ECHO] breath=$_index voiced=${meter.voicedMs}ms '
        'ai=${segment.durationMs}ms spoke=${meter.hasSpoken}');
  }

  Future<bool> _hasMic() async {
    try {
      return await recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  Future<void> _stopCapture() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    await _micSub?.cancel();
    _micSub = null;
    try {
      if (await recorder.isRecording()) await recorder.stop();
    } catch (_) {}
    final done = _captureDone;
    _captureDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  /// 재생·녹음·타이머를 전부 접고 진행 중인 회차를 무효화한다.
  Future<void> stop() async {
    _generation++;
    _running = false;
    final player = _player;
    _player = null;
    if (player != null) {
      try {
        await player.stop();
      } catch (_) {}
      try {
        await player.dispose();
      } catch (_) {}
    }
    await _stopCapture();
  }
}
