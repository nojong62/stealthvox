// ====================================================================
// 🎙️ [STREAMING-STT] 유저 음성 스트리밍 전사 세션
// --------------------------------------------------------------------
// ⚠️ 이름 주의 — 이 앱에서 "리얼타임"은 쓰지 않는다.
//   전사 모델은 예전과 같은 **gpt-4o-transcribe**다. 바뀐 것은 그 모델에
//   음성을 건네는 방법뿐이다: 녹음이 끝난 뒤 WAV 파일을 올리던 것을,
//   말하는 동안 소켓으로 흘려보내는 방식으로 바꿨다.
//
//   그 소켓의 주소가 OpenAI 쪽 이름으로 `/v1/realtime`일 뿐이고,
//   2026-08-08에 걷어낸 **Realtime 음성 대화(WebRTC, gpt-realtime)와는
//   다른 물건이다.** AI 응답은 지금도 gpt-4o-mini + tts-1이 만든다.
//
// 이 파일이 하는 일은 셋뿐이다.
//   1. 유저 마이크 PCM을 OpenAI로 흘려보낸다
//   2. OpenAI Server VAD가 발화 시작/종료를 잡는다
//   3. 최종 전사문을 돌려준다
//
// 하지 않는 일:
//   · AI 답변 생성 — 전사 전용 세션이다
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

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'pcm_audio_utils.dart';

// ====================================================================
// 🎚️ [PHASE-1 FLAG] Circle Talk 유저 음성 전사 엔진 전환 스위치
// --------------------------------------------------------------------
//   ON  → 스트리밍 전사 (Server VAD + gpt-4o-transcribe)
//   OFF → 기존 Deepgram Nova-3 경계 + gpt-4o-transcribe 파일 전사
//
// 양쪽 다 글자를 만드는 모델은 gpt-4o-transcribe로 같다. 갈리는 것은
// 발화 종료를 누가 잡느냐(OpenAI Server VAD vs Deepgram)와
// 음성을 어떻게 보내느냐(스트리밍 vs 파일 업로드) 둘뿐이다.
//
// **둘은 절대 동시에 돌지 않는다.** 한 턴에 STT 경로는 하나뿐이고,
// 소켓 예열도 켜진 쪽만 한다. 실기기 A/B 측정은 이 값을 뒤집어서 한다:
//   flutter run --dart-define=FREETALK_STREAMING_STT=false
//
// 바뀌는 것은 전사 공급자뿐이다. 노이즈 게이트·AI 응답·TTS·History·
// billing·30분 롤오버는 `userOriginal` 합류 지점부터 기존 코드를 탄다.
// ====================================================================
const bool kFreeTalkUseStreamingStt =
    bool.fromEnvironment('FREETALK_STREAMING_STT', defaultValue: true);

/// 전사 전용 세션 엔드포인트. `intent=transcription`이 붙어야 음성 응답용
/// conversation 세션이 아니라 전사 세션으로 열린다.
const String kStreamingSttEndpoint =
    'wss://api.openai.com/v1/realtime?intent=transcription';

/// 전사 모델. **여기 한 줄만 바꾸면 모델이 바뀐다** — 다른 곳에 박지 않는다.
///
/// Phase 1은 기존 파일 전사와 같은 `gpt-4o-transcribe`를 유지한다. 전송 방식
/// (Deepgram VAD + WAV 업로드 → Server VAD + 스트리밍)만 바꿔야 속도·정확도·
/// 비용 변화의 원인을 분리할 수 있기 때문이다.
/// 공식 가이드가 권장하는 저지연 스트리밍 모델은 `gpt-live-transcribe`다.
const String kStreamingSttModel = 'gpt-4o-transcribe';

// ── Server VAD 초기값 ────────────────────────────────────────────────
// 고정 정책이 아니라 실기기 측정 시작점이다. 500 / 600 / 700을 비교한다.
//   · 문장 중간 잘림 발생률
//   · speech_stopped → transcription.completed
//   · speech_stopped → AI 첫 소리
const double kStreamingSttVadThreshold = 0.5;
const int kStreamingSttVadPrefixPaddingMs = 300;
const int kStreamingSttVadSilenceDurationMs = 600;

const Duration kStreamingSttConnectTimeout = Duration(seconds: 6);

/// 종료 직전, 아직 안 돌아온 마지막 전사문을 기다리는 상한.
/// 실측에서 speech_stopped → completed가 350~800ms였다. 2초면 충분하고,
/// 넘으면 통화 종료가 눈에 띄게 늦어지므로 여기서 끊는다.
const Duration kStreamingSttFlushTimeout = Duration(seconds: 2);

/// `session.update`를 서버가 받아들였다는 확인을 기다리는 시간.
/// 확인 없이 오디오를 흘리면 설정이 반영 안 된 세션에 말이 들어간다.
const Duration kStreamingSttConfigTimeout = Duration(seconds: 4);

const int kStreamingSttMaxRetries = 5;

/// 전사 세션 하나. 대화방 세션 동안 살아 있고, 턴마다 새로 만들지 않는다.
///
/// **연결과 마이크 입력은 분리되어 있다.** 소켓은 유지한 채
/// [openAudioGate] / [closeAudioGate]로 오디오 전송만 여닫는다.
class OpenAiStreamingTranscribeSession {
  OpenAiStreamingTranscribeSession({
    required this.apiKey,
    required String languageCode,
    this.onLog,
  }) : _languageCode = languageCode;

  final String apiKey;

  /// 전사기에 박을 언어 코드. **final이 아니다** — 첫 발화의 실제 언어가
  /// 로비 ORIGIN과 다르면 [switchLanguage]로 갈아 끼운다.
  ///
  /// **빈 문자열은 "언어를 박지 않는다" = 자동 감지**를 뜻한다. 첫 발화는
  /// 이 상태로 받아야 유저가 실제로 쓴 언어가 전사문에 남는다. 언어를 박아
  /// 두면 다른 언어 발화도 그 언어 문자로 음차되어 나와, 어긋났다는 사실
  /// 자체가 사라진다.
  String _languageCode;
  String get languageCode => _languageCode;

  /// 로그 훅. **final이 아니다** — 예열 소켓을 방이 물려받을 때 방의 로거로
  /// 갈아 끼워야 한다. 예열 쪽 로거는 시각도 안 붙이고 앱 내부 로그 원장에도
  /// 안 들어가서, 채택된 뒤의 이벤트가 실기기 로그에서 통째로 익명이 된다.
  void Function(String tag, String msg)? onLog;

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

  // ── 진행 중 발화 추적 ──────────────────────────────────────────────
  // 통화를 끊을 때 "지금 말하던 문장"이 아직 서버에 있는지 알아야 한다.
  // 모르면 기다릴 이유도 없는데 매번 2초를 버리거나, 기다려야 할 때
  // 그냥 끊어 마지막 문장을 잃는다.
  //
  //   speech_started            → 말하는 중 (_speechInFlight)
  //   input_audio_buffer.committed → 구간 확정, 전사 대기 (_pendingItemIds)
  //   transcription.completed   → 그 item 처리 끝
  bool _speechInFlight = false;
  final Set<String> _pendingItemIds = <String>{};
  Completer<void>? _drained;

  // ── 발화 순번 ──────────────────────────────────────────────────────
  // ⚠️ **transcription.completed의 도착 순서는 발화 순서가 아니다.** 전사는
  //   발화마다 따로 도는 비동기 작업이라, 짧은 뒷말이 긴 앞말보다 먼저 끝나
  //   먼저 도착할 수 있다. 도착 순서로 문장을 이으면 앞뒤가 뒤집힌다.
  //
  //   발화 순서를 아는 곳은 `input_audio_buffer.committed`다 — 서버 VAD가
  //   구간을 확정하는 이벤트라 말한 순서대로 온다. 여기서 item_id에 순번을
  //   박아 두고, 호출부는 [utteranceOrderOf]로 그 순번을 읽어 정렬한다.
  int _utteranceSeq = 0;
  final Map<String, int> _utteranceOrder = <String, int>{};

  // ── 발화 길이 ──────────────────────────────────────────────────────
  // 이 값 하나가 **환청과 실제 발화를 가른다.**
  //
  // 2026-08-13 Duo 실측(SM S931N, 65초 통화 9건):
  //   실제 말   1,323 / 2,200 / 2,999ms  → 14~23자
  //   클릭 잡음    41 /    42 /    44ms  → 3~7자  ← 전부 지어낸 문장
  // "급습했다." 같은 문장이 42ms짜리 클릭 하나에서 나왔다. 글자 수·단어
  // 목록으로는 절대 못 거른다 — 지어낸 문장은 멀쩡한 한국어라서다.
  //
  // ⚠️ 재는 방법이 둘이고 **정확도가 다르다.**
  //
  //   server — `speech_started.audio_start_ms`와 `speech_stopped.audio_end_ms`.
  //            서버가 오디오 버퍼 기준으로 찍은 값이라 소켓 지연·앱 스케줄링이
  //            섞이지 않고, 침묵 판정 시간을 뺄 필요도 없다. **이쪽이 옳다.**
  //   local  — 이벤트가 앱에 도착한 시각의 차에서 침묵 판정 시간을 뺀 값.
  //            서버가 그 필드를 안 줄 때만 쓰는 폴백이라 오차가 섞인다.
  //
  // 어느 쪽으로 쟀는지 로그에 남긴다 — 150ms 근처의 짧은 정상 응답이 잘리는지
  // 판단하려면 그 숫자가 무엇으로 잰 값인지부터 알아야 한다.
  DateTime? _speechStartedAt;
  int? _speechStartedAudioMs;
  int? _serverVoicedMs;
  final Map<String, int> _utteranceVoicedMs = <String, int>{};
  final Map<String, String> _utteranceVoicedSource = <String, String>{};

  /// 이 item이 몇 번째 발화인지. 모르면 null.
  int? utteranceOrderOf(String itemId) => _utteranceOrder[itemId];

  /// 이 발화에서 **실제로 소리가 난 시간(ms)**. 모르면 null.
  ///
  /// 서버가 준 `audio_start_ms`/`audio_end_ms` 차가 우선이고, 그게 없으면
  /// 로컬 시계에서 무음 판정 시간을 뺀 값이다.
  int? utteranceVoicedMsOf(String itemId) => _utteranceVoicedMs[itemId];

  /// 위 값을 무엇으로 쟀는지 — `'server'` 또는 `'local'`.
  String? utteranceVoicedSourceOf(String itemId) =>
      _utteranceVoicedSource[itemId];

  int _assignUtteranceOrder(String itemId) {
    if (itemId.isEmpty) return ++_utteranceSeq;
    final existing = _utteranceOrder[itemId];
    if (existing != null) return existing;
    final order = ++_utteranceSeq;
    _utteranceOrder[itemId] = order;
    // 한 방에 수백 발화가 쌓이므로 오래된 것부터 놓는다. 진행 중인 턴은
    // 많아야 몇 조각이라 32개면 넉넉하다.
    if (_utteranceOrder.length > 32) {
      final oldest = _utteranceOrder.entries.reduce(
        (a, b) => a.value <= b.value ? a : b,
      );
      _utteranceOrder.remove(oldest.key);
      _utteranceVoicedMs.remove(oldest.key);
      _utteranceVoicedSource.remove(oldest.key);
    }
    return order;
  }

  /// 아직 결과가 안 돌아온 발화가 있는가.
  bool get hasPendingUtterance => _speechInFlight || _pendingItemIds.isNotEmpty;

  /// **지금 유저가 말하는 중인가.** `speech_started` 뒤 `committed` 전이다.
  ///
  /// [hasPendingUtterance]와 따로 낸다. 둘을 하나로 묶어 쓰면 "말하는 중"이
  /// "전사 대기 중"에 가려져, 나중에 이 getter의 정의가 바뀔 때 호출부가
  /// 조용히 깨진다 — 말하는 중인 유저를 잘라 버리는 쪽으로.
  bool get isUserSpeaking => _speechInFlight;

  /// 종료 직전에 부른다. 진행 중인 발화가 있으면 **마지막 버퍼를 명시적으로
  /// 확정**하고 전사문이 돌아올 때까지 [timeout]까지 기다린다.
  ///
  /// 반환값은 "기다렸는가"다. 진행 중 발화가 없으면 아무것도 안 하고 즉시
  /// false를 돌려주므로, 말하지 않고 끈 경우 종료가 느려지지 않는다.
  ///
  /// ⚠️ 게이트를 먼저 닫는다. 열어 둔 채 commit하면 확정 직후 들어온 PCM이
  /// 다음 버퍼를 열어 또 하나의 발화가 생긴다.
  Future<bool> flushPendingUtterance({
    required String reason,
    Duration timeout = kStreamingSttFlushTimeout,
  }) async {
    closeAudioGate(reason: reason);
    if (_disposed || !hasPendingUtterance) return false;

    // 서버 VAD가 아직 발화 종료를 못 잡은 상태면 우리가 끊어 준다. 이미
    // committed까지 간 발화는 서버가 확정했으므로 다시 commit하지 않는다
    // (빈 버퍼 commit은 error 이벤트만 만든다 — 로그만 더러워진다).
    if (_speechInFlight && isConnected) {
      _lg('🎙️ [STREAM-FLUSH]', 'commit reason=$reason');
      _send({'type': 'input_audio_buffer.commit'});
    }

    final drained = Completer<void>();
    _drained = drained;
    final sw = Stopwatch()..start();
    try {
      await drained.future.timeout(timeout, onTimeout: () {});
    } finally {
      sw.stop();
      if (identical(_drained, drained)) _drained = null;
    }
    final bool done = !hasPendingUtterance;
    _lg('🎙️ [STREAM-FLUSH]',
        'drained=$done waitedMs=${sw.elapsedMilliseconds} reason=$reason');
    return true;
  }

  void _clearPending(String? itemId) {
    if (itemId != null) _pendingItemIds.remove(itemId);
    if (!hasPendingUtterance) {
      final drained = _drained;
      _drained = null;
      if (drained != null && !drained.isCompleted) drained.complete();
    }
  }

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
        kStreamingSttEndpoint,
        headers: {'Authorization': 'Bearer $apiKey'},
      ).timeout(kStreamingSttConnectTimeout);
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
        kStreamingSttConfigTimeout,
        onTimeout: () => false,
      );
      if (!ok) {
        _lg('❌ [STREAM-STT]',
            'session_update_unconfirmed elapsedMs=${sw.elapsedMilliseconds}');
        await _teardownSocket();
        return false;
      }
      _connectedAt = DateTime.now();
      _retryCount = 0;
      _lg(
        '✅ [STREAM-STT]',
        'connected model=$kStreamingSttModel '
            'lang=${_languageCode.isEmpty ? 'auto' : _languageCode} '
            'rate=$kStealthVoxSttSampleRate vad=server_vad '
            'threshold=$kStreamingSttVadThreshold '
            'prefixMs=$kStreamingSttVadPrefixPaddingMs '
            'silenceMs=$kStreamingSttVadSilenceDurationMs '
            'connectMs=${sw.elapsedMilliseconds}',
      );
      return true;
    } catch (e) {
      _lg('❌ [STREAM-STT]',
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
              'model': kStreamingSttModel,
              // 빈 값이면 키를 통째로 뺀다. 서버는 그때만 언어를 스스로 잡는다.
              if (_languageCode.isNotEmpty) 'language': _languageCode,
            },
            // 발화 경계는 전적으로 서버가 잡는다. 앱에서 commit하지 않는다.
            'turn_detection': {
              'type': 'server_vad',
              'threshold': kStreamingSttVadThreshold,
              'prefix_padding_ms': kStreamingSttVadPrefixPaddingMs,
              'silence_duration_ms': kStreamingSttVadSilenceDurationMs,
            },
          },
        },
      },
    });
  }

  /// 전사 언어를 갈아 끼운다. **소켓은 그대로 둔다** — `session.update`만 다시
  /// 보내면 되므로 재연결 비용(핸드셰이크 + 설정 왕복)이 들지 않는다.
  ///
  /// 첫 발화를 자동 감지로 받아 실제 언어를 알아낸 직후에 부른다. 두 번째
  /// 턴부터는 언어가 박혀 있어야 짧은 발화의 전사 정확도가 돌아온다.
  Future<bool> switchLanguage(String code) async {
    if (_disposed || code.isEmpty || code == _languageCode) return false;
    if (!isConnected) {
      // 소켓이 없으면 값만 바꿔 둔다. 다음 connect()가 이 값으로 연다.
      _languageCode = code;
      return false;
    }
    final previous = _languageCode;
    _languageCode = code;
    final configured = Completer<bool>();
    _configured = configured;
    _sendSessionUpdate();
    final ok = await configured.future.timeout(
      kStreamingSttConfigTimeout,
      onTimeout: () => false,
    );
    if (!ok) {
      // 갈아 끼우기가 실패해도 전사 자체는 계속 돌아야 한다. 서버가 어떤
      // 언어로 돌고 있는지 모르게 되는 것이 가장 나쁘므로 값을 되돌린다.
      _languageCode = previous;
      _lg('⚠️ [STREAM-STT]', 'lang_switch_failed $previous←$code');
      return false;
    }
    _lg('🌐 [STREAM-STT]', 'lang_switched $previous→$code');
    return true;
  }

  /// 오디오 전송을 연다. 소켓은 건드리지 않는다.
  void openAudioGate({required String reason}) {
    if (_disposed || _audioGateOpen) return;
    _audioGateOpen = true;
    _lg('🎙️ [STREAM-GATE]', 'open reason=$reason');
  }

  /// 오디오 전송을 닫는다. **소켓은 살려 둔다** — 다음 턴에 다시 열기 위해서다.
  /// AI TTS가 나가는 동안 유저 마이크가 전사로 들어가지 않게 하는 것도 이것이다.
  void closeAudioGate({required String reason}) {
    if (!_audioGateOpen) return;
    _audioGateOpen = false;
    _lg('🎙️ [STREAM-GATE]', 'close reason=$reason');
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
      _lg('📡 [STREAM-FIRST-SEND]',
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
        _lg('❌ [STREAM-STT-ERR]',
            raw.length > 800 ? '${raw.substring(0, 800)}…' : raw);
        final pending = _configured;
        if (pending != null && !pending.isCompleted) {
          _completeConfigured(false);
        }
        // flush 중에 온 error는 대개 "빈 버퍼 commit"이다. 그 발화는 영영
        // 안 오므로 대기를 풀어 준다. 안 풀면 종료가 상한까지 늘어진다.
        if (_drained != null) {
          _speechInFlight = false;
          _clearPending(null);
        }
        return;

      case 'input_audio_buffer.speech_started':
        _speechInFlight = true;
        // 발화 길이를 재려면 시작점이 필요하다. 서버 값이 있으면 그것을 쓰고,
        // 없을 때를 대비해 로컬 시각도 같이 찍어 둔다. 한 발화의 committed는
        // 다음 speech_started보다 항상 먼저 오므로(실측 확인) 값 하나면 된다.
        _speechStartedAt = DateTime.now();
        _speechStartedAudioMs = (event['audio_start_ms'] as num?)?.toInt();
        _lg('📡 [STREAM-VAD]',
            'speech_started audioStartMs=${_speechStartedAudioMs ?? -1}');
        onSpeechStarted?.call();
        return;

      case 'input_audio_buffer.speech_stopped':
        // 아직 committed 전이다. 여기서 대기를 풀면 전사문을 놓친다.
        // 서버가 발화 끝을 오디오 기준으로 찍어 주면 여기서 길이가 확정된다 —
        // 침묵 판정 시간을 뺄 필요도, 로컬 지연을 걱정할 필요도 없다.
        final endAudioMs = (event['audio_end_ms'] as num?)?.toInt();
        final startAudioMs = _speechStartedAudioMs;
        if (endAudioMs != null && startAudioMs != null) {
          final span = endAudioMs - startAudioMs;
          // ⚠️ 음수는 **0으로 눌러선 안 된다.** 0은 "소리가 안 났다"는 뜻이라
          //   길이 게이트가 그 발화를 잡음으로 버린다. 값이 이상하면 그건
          //   "짧았다"가 아니라 "모른다"다 — 서버 값을 버리고 로컬 폴백으로
          //   넘겨, 근거 없는 차단이 일어나지 않게 한다.
          if (span >= 0) {
            _serverVoicedMs = span;
          } else {
            _lg('⚠️ [STREAM-VAD]',
                'audio_ms_out_of_order start=$startAudioMs end=$endAudioMs → local fallback');
          }
        }
        _lg('📡 [STREAM-VAD]',
            'speech_stopped audioEndMs=${endAudioMs ?? -1} '
                'serverVoicedMs=${_serverVoicedMs ?? -1}');
        onSpeechStopped?.call();
        return;

      case 'input_audio_buffer.committed':
        // 서버가 발화 구간을 확정했다는 신호일 뿐이다. 전사는 그 뒤에 온다.
        // **발화 순서가 확정되는 곳이 여기다** — 전사 도착 순서가 아니다.
        final committedId = event['item_id']?.toString() ?? '';
        _speechInFlight = false;
        if (committedId.isNotEmpty) _pendingItemIds.add(committedId);
        final committedOrder = _assignUtteranceOrder(committedId);
        final startedAt = _speechStartedAt;
        final serverVoiced = _serverVoicedMs;
        _speechStartedAt = null;
        _speechStartedAudioMs = null;
        _serverVoicedMs = null;
        int? voicedMs;
        String source = 'none';
        if (serverVoiced != null) {
          // 서버가 오디오 기준으로 잰 값. 로컬 지연이 섞이지 않는다.
          voicedMs = serverVoiced;
          source = 'server';
        } else if (startedAt != null) {
          // 폴백. 이벤트 도착 시각 차라 소켓·스케줄링 지연이 섞인다.
          final spanMs = DateTime.now().difference(startedAt).inMilliseconds;
          final local = spanMs - kStreamingSttVadSilenceDurationMs;
          // 여기도 음수를 0으로 누르지 않는다. VAD가 침묵을 확인하고 끊은
          // 이상 span은 침묵 시간보다 길어야 정상이다. 짧다면 잰 값이
          // 틀린 것이지 발화가 짧았던 게 아니다 → 모르는 것으로 둔다.
          if (local >= 0) {
            voicedMs = local;
            source = 'local';
          } else {
            _lg('⚠️ [STREAM-VAD]',
                'local_span_too_short spanMs=$spanMs → voicedMs unknown');
          }
        }
        if (voicedMs != null && committedId.isNotEmpty) {
          _utteranceVoicedMs[committedId] = voicedMs;
          _utteranceVoicedSource[committedId] = source;
        }
        _lg(
            '📡 [STREAM-VAD]',
            'committed item=$committedId order=$committedOrder '
                'voicedMs=${voicedMs ?? -1} src=$source');
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
        // committed를 못 본 item이면(이벤트 유실·순서 역전) 지금이라도 순번을
        // 준다. 순번 없는 조각이 생기면 정렬이 무너진다.
        final order = _assignUtteranceOrder(itemId);
        _lg('📡 [STREAM-STT]',
            'transcription_completed item=$itemId order=$order len=${text.length}');
        // ⚠️ **콜백보다 먼저 장부에서 지운다.** 순서가 반대면, 호출부가
        //   콜백 안에서 `hasPendingUtterance`를 읽을 때 **방금 도착한 그
        //   item이 아직 남아 있어** 항상 "서버가 더 물고 있다"로 보인다.
        //   이어 말하기가 그 값을 보고 계속 기다리다 안전 타임아웃(2.5초)에서야
        //   답변을 시작했다 — 실기기 로그에서 매 병합마다 2.5초를 버렸다
        //   (2026-08-14, [CONT-RESOLVE] decision=wait serverBusy=true).
        _clearPending(itemId);
        onTranscriptCompleted?.call(itemId, text);
        return;

      case 'conversation.item.input_audio_transcription.failed':
        _lg(
            '❌ [STREAM-STT]',
            'transcription_failed item=${event['item_id']} '
                'reason=${event['error']}');
        // 실패해도 대기는 풀어야 한다. 안 그러면 flush가 상한까지 논다.
        _clearPending(event['item_id']?.toString());
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
    _lg('⚠️ [STREAM-STT]', 'socket_lost reason=$reason');
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
        _lg('🎙️ [STREAM-STT]', 'reconnect_skipped reason=gate_closed');
        return;
      }
      if (_retryCount >= kStreamingSttMaxRetries) {
        _lg('❌ [STREAM-STT]', 'reconnect_gave_up after=$_retryCount');
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
        _lg('🎙️ [STREAM-STT]',
            'reconnect_skipped reason=gate_closed_after_delay');
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
    // 대기 중인 flush가 있으면 풀어 준다. 소켓을 닫아 놓고 재우면 상한까지 논다.
    _speechInFlight = false;
    _pendingItemIds.clear();
    _utteranceOrder.clear();
    _utteranceVoicedMs.clear();
    _utteranceVoicedSource.clear();
    _speechStartedAt = null;
    _speechStartedAudioMs = null;
    _serverVoicedMs = null;
    _clearPending(null);
    _lg('🎙️ [STREAM-STT]', 'dispose sentAudioMs=$sentAudioMs');
    await _teardownSocket();
  }

  /// 소켓 없이 이벤트 처리를 검증하기 위한 진입점. 테스트 전용이다.
  @visibleForTesting
  void debugHandleEvent(Map<String, dynamic> event) =>
      _handleEvent(jsonEncode(event));
}
