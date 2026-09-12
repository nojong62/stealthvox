// ====================================================================
// 🎧 [DUO-STT] 마이크 소리 한 갈래가 글자가 되기까지
// --------------------------------------------------------------------
// 직접 대화와 만능 통역이 **이 파이프라인 하나를 함께 쓴다.** 둘은 같은
// 마이크 PCM을 쓰고, 풀어야 할 문제도 같다 — 덜 훼손된 소리를 얼마나 정확히
// 글자로 옮기는가.
//
//   마이크 PCM (software APM 앞, HW AEC만 걸린 소리)
//        ├─→ DuoUtteranceCapture      소리를 담는다 (앞 여유 600ms 포함)
//        └─→ DuoDeepgramEndpointSensor 경계만 판단한다 (글자는 버린다)
//                    │
//        SpeechStarted│ → capture.begin()  발화 id 발급
//        UtteranceEnd │ → capture.commit() → gpt-transcribe → 글자
//
// 여기서 끝난다. 그 뒤 무엇을 할지는 모드마다 다르다 —
// 직접 대화는 History로, 만능 통역은 번역·TTS로 간다. **후단은 섞지 않는다.**
//
// ⚠️ 이 파이프라인이 지키는 것 셋
//   1. PCM을 판정으로 버리지 않는다 (`DuoUtteranceCapture`)
//   2. 경계는 Deepgram 하나가, 글자는 gpt-transcribe 하나가 책임진다
//   3. 발화 id는 **이 앱이 만든다** — 외부 서비스 id를 빌려 쓰지 않는다
// ====================================================================

import 'dart:async';
import 'dart:typed_data';

import 'dart:math' as math;

import 'duo_deepgram_endpoint.dart';
import 'duo_direct_audio.dart' show kDuoMicVoicedFrameDbfs;
import 'duo_transcript_context.dart';
import 'duo_utterance_capture.dart';
import 'openai_transcribe_service.dart';
import 'pcm_audio_utils.dart';

/// 🔎 [계측 전용] STT 입력 PCM 한 창의 통계. **판정에 쓰이지 않는다.**
class _SttWindow {
  const _SttWindow(this.frames, this.bytes, this.avgDbfs, this.peakDbfs,
      this.voiced, this.allZero);
  final int frames;
  final int bytes;
  final double avgDbfs;
  final double peakDbfs;
  final int voiced;
  final int allZero;
}

/// 🔎 [계측 전용] 목소리 판정은 [kDuoMicVoicedFrameDbfs] 하나를 그대로 쓴다.
///   여기서 새 임계값을 만들면 직접 대화와 다른 잣대가 된다.
class _SttInputProbe {
  static const int _framesPerLog = 100;

  int _frames = 0;
  int _bytes = 0;
  int _samples = 0;
  double _sumSquares = 0;
  double _peak = 0;
  int _voiced = 0;
  int _allZero = 0;

  int lifeFrames = 0;
  int lifeVoiced = 0;
  int lifeAllZero = 0;

  bool get due => _frames >= _framesPerLog;

  void note(Uint8List pcm) {
    final int samples = pcm.lengthInBytes ~/ 2;
    if (samples == 0) return;
    final ByteData view = ByteData.sublistView(pcm, 0, samples * 2);
    double frameSum = 0;
    bool allZero = true;
    for (var i = 0; i < samples; i++) {
      final int raw = view.getInt16(i * 2, Endian.little);
      if (raw != 0) allZero = false;
      final double v = raw / 32768.0;
      frameSum += v * v;
      final double a = v.abs();
      if (a > _peak) _peak = a;
    }
    _frames++;
    lifeFrames++;
    _bytes += pcm.lengthInBytes;
    _samples += samples;
    _sumSquares += frameSum;
    if (allZero) {
      _allZero++;
      lifeAllZero++;
    }
    final double frameDbfs = pcm16LinearToDbfs(math.sqrt(frameSum / samples));
    if (frameDbfs >= kDuoMicVoicedFrameDbfs) {
      _voiced++;
      lifeVoiced++;
    }
  }

  _SttWindow takeWindow() {
    final double avg = _samples == 0
        ? -160.0
        : pcm16LinearToDbfs(math.sqrt(_sumSquares / _samples));
    final double peak = _peak <= 0 ? -160.0 : pcm16LinearToDbfs(_peak);
    final w = _SttWindow(_frames, _bytes, avg, peak, _voiced, _allZero);
    _frames = 0;
    _bytes = 0;
    _samples = 0;
    _sumSquares = 0;
    _peak = 0;
    _voiced = 0;
    _allZero = 0;
    return w;
  }
}

/// 최종 전사에 주는 시간 상한. 발화가 길면 그만큼 오래 걸린다.
const Duration kDuoTranscribeTimeout = Duration(seconds: 20);

/// 통화를 닫으며 마지막 전사문을 기다리는 상한. 이보다 오래 걸리면 그 발화는
/// 어느 History에도 남지 않고, 호출부가 그 사실을 로그로 남긴다.
const int kDuoFlushWaitMs = 8000;

/// 🧭 직전 발화를 낱말 힌트로 함께 보낼 것인가. **기본은 꺼짐이다.**
///
/// 켜면 이름·지명의 철자가 통화 내내 같아지지만, 그 대가로 **모델이 애매한
/// 소리를 앞서 나온 낱말 쪽으로 읽는다.** 그건 "들은 대로"가 아니다.
/// 지금 이 앱이 원하는 것은 소리에 충실한 글자이고, 통화가 끝난 뒤의 정돈은
/// canonical이 따로 한다.
///
///   flutter run --dart-define=DUO_STT_CONTEXT_HINT=true
///
/// 링 자체는 살려 둔다 — 껐다 켜며 견주는 것이 이 값의 쓸모다.
const bool kDuoSttContextHint =
    bool.fromEnvironment('DUO_STT_CONTEXT_HINT', defaultValue: false);

/// 전사 결과 한 벌. 로그와 후단이 같은 값을 본다.
class DuoSttResult {
  const DuoSttResult({
    required this.utteranceId,
    required this.text,
    required this.utterance,
    required this.languageCode,
    required this.elapsedMs,
    required this.usedContext,
  });

  final String utteranceId;
  final String text;
  final DuoCapturedUtterance utterance;
  final String languageCode;
  final int elapsedMs;
  final bool usedContext;
}

/// 통화 한 통 × 모드 하나 = 이 객체 한 개.
class DuoSttPipeline {
  DuoSttPipeline({
    required this.openAiKey,
    required this.deepgramKey,
    required this.idPrefix,
    required this.mode,
    required this.originLanguageCode,
    this.sampleRate = kStealthVoxSttSampleRate,
    this.onLog,
  })  : _capture = DuoUtteranceCapture(
          idPrefix: idPrefix,
          sampleRate: sampleRate,
        ),
        context = DuoTranscriptContext();

  /// 🔎 [계측 전용] 이 통로가 호스트 것인가 게스트 것인가. 같은 빌드라도
  ///   두 역할의 오디오 상태가 다르므로 로그에서 갈라 읽어야 한다.
  String roleLabel = '?';

  /// 🔎 [계측 전용] **STT로 실제 들어가는 그 PCM**을 잰다. WebRTC stats나
  ///   다른 미터가 아니라, 아래 [addPcm]이 캡처·Deepgram에 넘기는 바로 그
  ///   바이트다. 판정 기준은 [kDuoMicVoicedFrameDbfs] 하나를 그대로 쓴다 —
  ///   여기서 새 임계값을 만들면 직접 대화와 다른 잣대가 된다.
  final _SttInputProbe _inProbe = _SttInputProbe();

  /// 🔎 [계측 전용] 게이트가 버린 몫. 들어왔는데 STT까지 못 간 소리다.
  int _gateDroppedFrames = 0;
  int _gateDroppedBytes = 0;

  final String openAiKey;
  final String deepgramKey;

  /// 발화 id의 머리말. 로그에서 모드가 바로 읽힌다.
  final String idPrefix;

  /// 로그에 적는 모드 이름(`direct` / `interpreter`).
  final String mode;

  /// **발화를 확정하는 순간** 부른다. 만능 통역은 첫 발화로 Origin을
  /// 판정하므로(`OriginLanguageSession`) 통화 시작 시점 값으로 굳히면 안 된다.
  final String Function() originLanguageCode;

  final int sampleRate;
  final void Function(String tag, String msg)? onLog;

  final DuoUtteranceCapture _capture;

  /// 애매하게 들린 낱말을 가려내는 힌트. 수용된 전사문만 들어간다.
  final DuoTranscriptContext context;

  DuoDeepgramEndpointSensor? _sensor;

  /// 발화가 열린 시각. 로그가 경계를 되짚는 기준이다.
  DateTime? _speechStartedAt;

  bool _stopped = false;
  int _inFlight = 0;

  /// 발화가 열렸다. 후단이 발화 id를 미리 잡아 둘 수 있다.
  void Function(String utteranceId)? onSpeechStarted;

  /// **소리가 닫혔다.** 전사가 돌아오기 전, 확정된 PCM이 나온 그 순간이다.
  ///
  /// 세기 계측을 멈추고 진단이 소리를 건네받는 자리다. 전사문이 온 뒤에
  /// 하면 그 사이 소리가 다음 발화 몫으로 섞인다.
  void Function(
          String utteranceId, DuoCapturedUtterance utterance, int? voicedMs)?
      onUtteranceClosed;

  /// 글자가 나왔다. **후단은 여기서부터 모드마다 갈린다.**
  void Function(DuoSttResult result)? onTranscript;

  /// 글자를 못 만들었다. 소리는 있었는데 전사가 실패한 경우다.
  void Function(String utteranceId, String reason)? onFailed;

  /// 🚪 소리를 들여보낼 것인가. **연결이 붙은 뒤에 연다.**
  ///
  /// 열기 전 조각은 흘려보낸다 — 통화 준비 중의 소리를 발화로 세면 방에
  /// 들어서는 잡음이 첫 말풍선이 된다. 옛 스트리밍 세션의 같은 이름 규칙을
  /// 그대로 옮긴 것이라 호출부가 바뀌지 않는다.
  bool _gateOpen = false;
  bool get audioGateOpen => _gateOpen;

  void openAudioGate({String reason = ''}) {
    if (_gateOpen) return;
    _gateOpen = true;
    _lg('mode=$mode audio_gate=open reason=$reason');
  }

  /// 소리를 더 들이지 않는다. 담던 발화는 **버린다** — 문이 닫힌 뒤의 반쪽
  /// 발화를 나중에 확정하면 그 자리에 없던 말이 남는다.
  void closeAudioGate({String reason = ''}) {
    if (!_gateOpen) return;
    _gateOpen = false;
    _capture.abort();
    // 🚪 [GATE-SYNC] **앱만 버리면 안 된다.** 문이 닫히면 소리가 Deepgram으로도
    //   안 가므로, 저쪽에 열린 채 남은 발화는 단어를 못 받아 영영 안 닫힌다.
    //   그 껍데기가 다음 구간으로 넘어가 실제 말과 경계가 어긋났다.
    _sensor?.abortOpenSpeech(reason.isEmpty ? 'gate_close' : reason);
    _speechStartedAt = null;
    _lg('mode=$mode audio_gate=close reason=$reason');
  }

  /// 소켓이 죽었다. 통화는 계속되지만 전사는 멈춘다.
  void Function(String reason)? onFatalError;

  /// 끊긴 소켓을 다시 이을 것인가. 통화가 살아 있는 동안만 참이어야 한다.
  bool Function()? shouldReconnect;

  /// 다시 잇는 중이다. 화면이 그 사실을 적는다.
  void Function(int attempt)? onReconnecting;

  /// 이어졌다.
  void Function()? onConnected;

  /// 말이 끝났다(소리가 닫힌 것과 같은 순간이다).
  void Function()? onSpeechStopped;

  /// 🕰️ 열린 발화에서 단어가 한동안 하나도 안 잡혔다. **발화를 닫는 것이
  /// 아니라 "말하는 중"만 내린 것이다** — 소리는 계속 담기고, 단어가 늦게라도
  /// 잡히면 평소대로 확정된다.
  ///
  /// 통역이 미뤄 둔 상대 목소리를 여기서 풀어야 한다. 안 풀면 굳은 발화 하나가
  /// 상대의 남은 말을 통째로 막는다(2026-09-07 실기기).
  void Function()? onSpeechStale;

  bool get isConnected => _sensor?.isOpen ?? false;

  int _reconnectAttempt = 0;
  bool _reconnecting = false;

  /// 발화 id → 그 발화의 `voicedMs`. 소리가 닫힐 때 적고, 전사문이 온 뒤
  /// 게이트가 읽는다. 옛 스트리밍 세션이 들고 있던 장부와 같은 자리다.
  final Map<String, int?> _voiced = <String, int?>{};
  final List<String> _voicedOrder = <String>[];

  int? utteranceVoicedMsOf(String utteranceId) => _voiced[utteranceId];

  /// 옛 경로는 `server`/`local` 두 갈래였다. 새 경로는 로컬 폴백과 같은 식
  /// 하나뿐이라 언제나 `local`이다([_voicedMsOf]).
  String? utteranceVoicedSourceOf(String utteranceId) =>
      _voiced.containsKey(utteranceId) ? 'local' : null;

  /// 🌐 Origin이 뒤늦게 판정됐다(`OriginLanguageSession`). 다음 전사부터는
  /// [originLanguageCode]가 새 값을 돌려주므로 그쪽은 저절로 따라온다.
  /// 경계 센서만 새 언어로 다시 연다.
  Future<bool> switchLanguage(String languageCode) async {
    if (_stopped) return false;
    _lg('mode=$mode switch_language to=$languageCode — 센서를 다시 연다');
    await _sensor?.close();
    return _openSensor();
  }

  /// 🗣️ 사람이 **지금 말하고 있는가.**
  ///
  /// 열려는 있으나 단어가 안 잡혀 굳은 발화는 여기서 거짓이다
  /// ([kDuoSpeechStaleMs]). 통역의 양보(INTERP-YIELD)가 이 값을 보므로,
  /// 굳은 발화를 참으로 두면 상대 목소리가 영영 안 나온다.
  bool get isUserSpeaking => _sensor?.isUserSpeaking ?? false;

  /// 아직 끝나지 않은 발화가 있는가.
  ///
  /// 담는 중이거나 전사가 도는 중이면 참이다. 종료 흐름이 이 값으로
  /// "마지막 말이 저장됐는가"를 판단한다.
  bool get hasPendingUtterance => _capture.isCapturing || _inFlight > 0;
  String? get currentUtteranceId => _capture.currentId;
  int get inFlightCount => _inFlight;

  void _lg(String msg) => onLog?.call('📡 [DUO-ENDPOINT]', msg);

  /// Deepgram 소켓을 연다. 실패해도 **소리 수집은 계속된다** — 경계를 못
  /// 받을 뿐이고, 담아 둔 PCM은 그대로 남는다.
  Future<bool> start() async {
    if (_stopped) return false;
    final ok = await _openSensor();
    if (ok) {
      _reconnectAttempt = 0;
      onConnected?.call();
    } else {
      _lg('mode=$mode sensor_unavailable — 소리는 계속 담는다');
    }
    return ok;
  }

  Future<bool> _openSensor() async {
    final sensor = DuoDeepgramEndpointSensor(
      apiKey: deepgramKey,
      languageCode: originLanguageCode(),
      onLog: (tag, msg) => onLog?.call(tag, 'mode=$mode $msg'),
    );
    sensor.onSpeechStarted = _handleSpeechStarted;
    sensor.onUtteranceEnd = _handleUtteranceEnd;
    // 🕰️ 굳은 발화를 알린다. **담기는 그대로 이어진다** — 여기서 소리를
    //   버리지 않는다.
    sensor.onSpeechStale = () {
      if (_stopped) return;
      _logSttInput('speech_stale');
      _lg('mode=$mode utt=${_capture.currentId ?? '-'} speech_stale '
          'capturedMs=${_capture.currentMs} — 말하는 중을 내린다');
      onSpeechStale?.call();
    };
    // 🚨 소켓이 끊기면 **말하는 중 표시가 고착되지 않게** 반드시 내린다.
    //   고착되면 통역이 TTS·INTERP-YIELD를 영영 못 연다.
    sensor.onClosed = _handleSensorClosed;
    _sensor = sensor;
    return sensor.connect();
  }

  /// 소켓이 죽었다. 담던 발화를 버리고, 통화가 살아 있으면 다시 잇는다.
  void _handleSensorClosed(String reason) {
    if (_stopped || _reconnecting) return;
    // 담던 소리는 어느 발화의 것도 아니게 됐다. 다음 발화에 붙이지 않는다.
    _capture.abort();
    _speechStartedAt = null;
    _lg('mode=$mode sensor_closed reason=$reason — speaking=false');
    if (shouldReconnect?.call() != true) {
      onFatalError?.call(reason);
      return;
    }
    unawaited(_reconnect());
  }

  /// 통화가 살아 있는 동안만 돈다. **마이크는 닫지 않는다** — 끊긴 동안 한
  /// 말은 경계를 못 받지만, 붙는 순간 다음 말을 바로 받아야 한다.
  Future<void> _reconnect() async {
    _reconnecting = true;
    try {
      while (!_stopped && (shouldReconnect?.call() ?? false)) {
        _reconnectAttempt++;
        onReconnecting?.call(_reconnectAttempt);
        _lg('mode=$mode reconnecting attempt=$_reconnectAttempt');
        await Future<void>.delayed(
            Duration(milliseconds: 400 * _reconnectAttempt.clamp(1, 5)));
        if (_stopped) return;
        await _sensor?.close();
        if (await _openSensor()) {
          _reconnectAttempt = 0;
          _lg('mode=$mode reconnected');
          onConnected?.call();
          return;
        }
      }
    } finally {
      _reconnecting = false;
    }
  }

  /// 마이크 조각 하나. **두 갈래로 똑같이 보낸다.**
  void addPcm(Uint8List pcm) {
    if (_stopped || !_gateOpen || pcm.isEmpty) {
      // 🔎 [계측] 게이트가 닫혀 버려진 몫. 동작은 예전과 같다.
      if (!_stopped && !_gateOpen && pcm.isNotEmpty) {
        _gateDroppedFrames++;
        _gateDroppedBytes += pcm.lengthInBytes;
      }
      return;
    }
    // 🔎 [계측] **STT가 실제로 먹는 그 바이트**를 여기서 잰다.
    _inProbe.note(pcm);
    if (_inProbe.due) _logSttInput('periodic');
    _capture.addPcm(pcm);
    _sensor?.addPcm(pcm);
  }

  /// 🔎 [계측 전용] STT 입력 PCM 한 판을 찍는다. 발화가 안 열려도 보인다.
  void _logSttInput(String at) {
    final w = _inProbe.takeWindow();
    _lg('mode=$mode [DUO-STT-PCM] at=$at role=$roleLabel '
        'frames=${w.frames} bytes=${w.bytes} '
        'avgDbfs=${w.avgDbfs.toStringAsFixed(1)} '
        'peakDbfs=${w.peakDbfs.toStringAsFixed(1)} '
        'voiced=${w.voiced} allZero=${w.allZero} '
        'lifeFrames=${_inProbe.lifeFrames} lifeVoiced=${_inProbe.lifeVoiced} '
        'lifeAllZero=${_inProbe.lifeAllZero} '
        'gate=${_gateOpen ? 'open' : 'closed'} '
        'gateDroppedFrames=$_gateDroppedFrames '
        'speechOpen=${_sensor?.isSpeechOpen ?? false} '
        'capturing=${_capture.isCapturing}');
  }

  /// 옛 스트리밍 세션과 같은 이름. 호출부(`DuoMicPcmFanout`)가 그대로 쓴다.
  void appendAudio(Uint8List pcm) => addPcm(pcm);

  /// 소켓을 연다. 이름도 옛 세션과 같게 둔다.
  Future<bool> connect() => start();

  /// 말하던 중에 통화가 끝났다. **담긴 소리를 버리지 않고 지금 확정한다.**
  ///
  /// 이게 없으면 마지막 한마디가 통째로 사라진다 — 종료를 알리는
  /// UtteranceEnd가 영영 오지 않기 때문이다.
  ///
  /// 확정한 뒤 전사가 돌아올 때까지 [kDuoFlushWaitMs]까지 기다린다. 돌려주는
  /// 값은 **기다릴 것이 있었는가**다(호출부가 그 뒤 저장을 기다릴지 가른다).
  Future<bool> flushPendingUtterance({String reason = 'close'}) async {
    if (_stopped) return false;
    final bool had = _capture.isCapturing || _inFlight > 0;
    if (!had) return false;
    if (_capture.isCapturing) {
      _lg('mode=$mode flush_pending reason=$reason');
      _handleUtteranceEnd();
    }
    final sw = Stopwatch()..start();
    while (_inFlight > 0 && sw.elapsedMilliseconds < kDuoFlushWaitMs) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _lg('mode=$mode flush_done reason=$reason waitedMs=${sw.elapsedMilliseconds} '
        'inFlight=$_inFlight');
    return true;
  }

  void _handleSpeechStarted() {
    if (_stopped) return;
    final String id = _capture.begin();
    _speechStartedAt = DateTime.now();
    _logSttInput('speech_started');
    _lg('mode=$mode utt=$id speech_started '
        'preRollMs=${_capture.preRollBufferedMs}');
    onSpeechStarted?.call(id);
  }

  void _handleUtteranceEnd() {
    if (_stopped) return;
    final DateTime endedAt = DateTime.now();
    _logSttInput('utterance_end');
    final DuoCapturedUtterance? utterance = _capture.commit();
    if (utterance == null) {
      _lg('mode=$mode utterance_end_dropped reason=no_audio');
      return;
    }
    final DateTime? startedAt = _speechStartedAt;
    _speechStartedAt = null;
    final int wallMs =
        startedAt == null ? -1 : endedAt.difference(startedAt).inMilliseconds;
    // 🕰️ UtteranceEnd는 마지막 단어 뒤로 [kDuoUtteranceEndMs]의 공백을 이미
    //   확인하고 온다. 그 공백이 곧 뒤 여유이므로 **여기서 더 기다리지 않는다.**
    final int? voicedMs = _voicedMsOf(utterance);
    _lg('mode=$mode utt=${utterance.utteranceId} utterance_end '
        'preRollMs=${utterance.preRollMs} bodyMs=${utterance.bodyMs} '
        'totalMs=${utterance.durationMs} wallMs=$wallMs '
        'trailingGapMs=$kDuoUtteranceEndMs voicedMs=${voicedMs ?? -1} '
        'frames=${utterance.frames} maxGapMs=${utterance.maxFrameGapMs}');
    _voiced[utterance.utteranceId] = voicedMs;
    _voicedOrder.add(utterance.utteranceId);
    while (_voicedOrder.length > 32) {
      _voiced.remove(_voicedOrder.removeAt(0));
    }
    onUtteranceClosed?.call(utterance.utteranceId, utterance, voicedMs);
    onSpeechStopped?.call();
    unawaited(_transcribe(utterance));
  }

  /// 🔇 소리가 난 시간. **`bodyMs`가 아니다.**
  ///
  /// 옛 Server VAD 경로가 쓰던 **로컬 폴백과 같은 식**을 그대로 옮긴 것이다:
  ///
  ///     voicedMs = (발화 시작 ~ 종료 구간) − (종료를 재는 침묵)
  ///
  /// `bodyMs`는 시작부터 종료까지의 시간이라 **문장 중간의 쉼과 끝의 침묵을
  /// 모두 품는다.** 그 값을 그대로 `voicedMs` 자리에 넣으면 환청 방어선
  /// (`belowVoicedGate`, 150ms)이 아무것도 못 거른다 — 어떤 껍데기도
  /// 1500ms를 넘고 만다.
  ///
  /// ⚠️ **`null`은 "짧았다"가 아니라 "모른다"다.** 음수가 나오면 잰 값이
  /// 틀린 것이지 발화가 짧았던 게 아니므로, 게이트는 통과시킨다
  /// (`belowVoicedGate`가 null을 통과시키는 이유와 같다).
  int? _voicedMsOf(DuoCapturedUtterance utterance) {
    final int local = utterance.bodyMs - kDuoUtteranceEndMs;
    return local >= 0 ? local : null;
  }

  /// 확정된 발화를 글자로 만든다. **여기가 gpt-transcribe 하나뿐인 자리다.**
  Future<void> _transcribe(DuoCapturedUtterance utterance) async {
    _inFlight++;
    final sw = Stopwatch()..start();
    final String language = originLanguageCode();
    // 🧭 기본은 힌트 없이 간다([kDuoSttContextHint]). 소리에 없는 낱말로
    //   끌려가지 않는 것이 먼저다.
    final String prompt = kDuoSttContextHint ? context.buildPrompt() : '';
    try {
      final String? text = await OpenAiTranscribeService.transcribePcm16(
        apiKey: openAiKey,
        pcm: utterance.pcm,
        sampleRate: utterance.sampleRate,
        // 🌐 자동 감지에 맡기지 않는다. 그 발화에 대해 확정된 Origin이다.
        language: language.isEmpty ? null : language,
        model: OpenAiTranscribeService.duoFinalModel,
        // 🧭 애매한 낱말·고유명사를 가려내는 힌트. 없으면 안 넘긴다.
        prompt: prompt.isEmpty ? null : prompt,
        timeout: kDuoTranscribeTimeout,
        // ✂️ **앞을 다시 깎지 않는다.** 600ms 앞 여유를 일부러 확보해 놓고
        //   전사 직전에 잘라내면 그 작업이 통째로 헛것이 된다.
        trimLeadingSilence: false,
        // 🔎 [계측] 서비스가 HTTP 상태·예외 종류를 이미 안다. 여태 null로
        //   막아 두어 `transcribe=failed` 한 줄만 남고 이유가 사라졌다.
        onLog: (tag, msg) => onLog?.call(tag, 'mode=$mode $msg'),
      );
      sw.stop();
      if (_stopped) return;
      if (text == null || text.trim().isEmpty) {
        // 🔎 [계측] **빈 글인가 호출 실패인가.** 이 둘이 갈려야 경계 문제인지
        //   전사 호출 문제인지 가른다. 여태 한 이름으로 뭉뚱그려 있었다.
        final String reason = text == null ? 'transcribe_error' : 'empty_text';
        _lg('mode=$mode utt=${utterance.utteranceId} transcribe=failed '
            'reason=$reason lang=$language '
            'audioMs=${utterance.durationMs} bytes=${utterance.pcm.lengthInBytes} '
            'elapsedMs=${sw.elapsedMilliseconds}');
        onFailed?.call(utterance.utteranceId, reason);
        return;
      }
      _lg('mode=$mode utt=${utterance.utteranceId} transcribe=ok '
          'lang=$language hint=${kDuoSttContextHint ? 'on' : 'off'} '
          'ctx=${prompt.isEmpty ? 0 : context.length} '
          'audioMs=${utterance.durationMs} len=${text.trim().length} '
          'elapsedMs=${sw.elapsedMilliseconds}');
      onTranscript?.call(DuoSttResult(
        utteranceId: utterance.utteranceId,
        text: text.trim(),
        utterance: utterance,
        languageCode: language,
        elapsedMs: sw.elapsedMilliseconds,
        usedContext: prompt.isNotEmpty,
      ));
    } catch (e) {
      sw.stop();
      _lg('mode=$mode utt=${utterance.utteranceId} transcribe=error '
          '${e.runtimeType} elapsedMs=${sw.elapsedMilliseconds}');
      onFailed?.call(utterance.utteranceId, 'transcribe_error');
    } finally {
      _inFlight--;
    }
  }

  /// 후단이 **받아들인** 전사문. 다음 발화의 낱말 힌트가 된다.
  ///
  /// 버려진 전사문은 넣지 않는다 — 잡음·환청으로 판정된 글자를 힌트로 주면
  /// 다음 발화가 그쪽으로 끌려간다.
  void noteAccepted(String text) => context.add(text);

  /// 소켓이 끊겼다 붙는 등, 어느 발화의 것도 아닌 소리를 버린다.
  void abortCurrent() {
    _capture.abort();
    _speechStartedAt = null;
  }

  /// 옛 세션과 같은 이름. 호출부가 그대로 쓴다.
  Future<void> dispose() => stop();

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _gateOpen = false;
    _capture.reset();
    context.clear();
    _voiced.clear();
    _voicedOrder.clear();
    await _sensor?.close();
    _sensor = null;
  }
}
