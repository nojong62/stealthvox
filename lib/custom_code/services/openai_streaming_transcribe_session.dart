// ====================================================================
// 🎙️ [STREAMING-STT] 유저 음성 스트리밍 전사 세션
// --------------------------------------------------------------------
// ⚠️ 이름 주의 — 이 앱에서 "리얼타임"은 쓰지 않는다.
//   전사 모델은 파일 전사와 같은 **gpt-transcribe**다. 갈리는 것은 그 모델에
//   음성을 건네는 방법뿐이다: 녹음이 끝난 뒤 WAV 파일을 올리던 것을,
//   말하는 동안 소켓으로 흘려보내는 방식으로 바꿨다.
//
//   그 소켓의 주소가 OpenAI 쪽 이름으로 `/v1/realtime`일 뿐이고,
//   2026-08-08에 걷어낸 **Realtime 음성 대화(WebRTC, gpt-realtime)와는
//   다른 물건이다.** AI 응답은 `gpt-6-luna`가 만들고 `tts-1`이 읽는다.
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
// 호출부(routine_mode_circle_talk.dart)의 변경을 앞단으로만 한정한다.
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
import 'secure_ai_gateway.dart';

// ====================================================================
// 🎚️ [PHASE-1 FLAG] Circle Talk 유저 음성 전사 엔진 전환 스위치
// --------------------------------------------------------------------
//   ON  → 스트리밍 전사 (Server VAD + gpt-transcribe)
//   OFF → 기존 Deepgram Nova-3 경계 + gpt-transcribe 파일 전사
//
// 양쪽 다 글자를 만드는 모델은 gpt-transcribe로 같다. 갈리는 것은
// 발화 종료를 누가 잡느냐(OpenAI Server VAD vs Deepgram)와
// 음성을 어떻게 보내느냐(스트리밍 vs 파일 업로드) 둘뿐이다.
//
// **둘은 절대 동시에 돌지 않는다.** 한 턴에 STT 경로는 하나뿐이고,
// 소켓 예열도 켜진 쪽만 한다. 실기기 A/B 측정은 이 값을 뒤집어서 한다:
//   flutter run --dart-define=FREETALK_STREAMING_STT=false
//
// 바뀌는 것은 전사 공급자뿐이다. 노이즈 게이트·AI 응답·TTS·History·
// billing·10분 롤오버는 `userOriginal` 합류 지점부터 기존 코드를 탄다.
// ====================================================================
const bool kFreeTalkUseStreamingStt =
    bool.fromEnvironment('FREETALK_STREAMING_STT', defaultValue: true);

/// 전사 전용 세션 엔드포인트. `intent=transcription`이 붙어야 음성 응답용
/// conversation 세션이 아니라 전사 세션으로 열린다.
const String kStreamingSttEndpoint =
    'wss://api.openai.com/v1/realtime?intent=transcription';

/// 전사 모델. **여기 한 줄만 바꾸면 모델이 바뀐다** — 다른 곳에 박지 않는다.
///
/// 파일 전사(`OpenAiTranscribeService.model`)와 **같은 값으로 맞춰 둔다.**
/// 서클톡·시나리오톡은 이 소켓과 파일 전사 중 한 길로만 다니는데
/// ([kFreeTalkUseStreamingStt]), 길마다 다른 모델을 쓰면 같은 말을 해도
/// 어느 길로 갔느냐에 따라 글자가 달라진다. 2026-09-07에 Duo가 옮겨 간
/// `gpt-transcribe`로 통일했다.
///
/// ⚠️ **주소가 달라 받는 모델 목록도 다르다.** 여기는 실시간 소켓
/// (`wss://…/v1/realtime?intent=transcription`)이고 파일 전사는 HTTP다.
/// 소켓이 이 모델을 안 받으면 **에러가 아니라 조용히 연결 실패**로 나타나고
/// (`❌ [STREAM-STT] connect_failed`), 앱은 Deepgram 경계 + 파일 전사 쪽으로
/// 떨어진다 — 글자는 계속 나오지만 말하는 중 미리보기가 사라지고 느려진다.
/// 실기기에서 `connected … model=` 줄로 확인할 것.
const String kStreamingSttModel = 'gpt-transcribe';

// ── Server VAD 초기값 ────────────────────────────────────────────────
// 고정 정책이 아니라 실기기 측정 시작점이다. 500 / 600 / 700을 비교한다.
//   · 문장 중간 잘림 발생률
//   · speech_stopped → transcription.completed
//   · speech_stopped → AI 첫 소리
const double kStreamingSttVadThreshold = 0.5;
const int kStreamingSttVadPrefixPaddingMs = 300;
const int kStreamingSttVadSilenceDurationMs = 600;

// ── 듀오도 공용 Server VAD를 쓴다 ────────────────────────────────────
// 한때 듀오만 문턱 0.35 / 앞소리 500ms / 침묵 800ms로 내려 잡았다. 폰이
// 책상 위에 있어 입과 마이크가 멀다는 이유였다.
//
// **그 완화가 뒤에 세 겹의 수습을 낳았다.** 예민해진 VAD가 잡음까지 발화로
// 잡고 → 잡음이 전사기로 가서 없는 말을 지어내고 → 그 환청을 거르려고
// 세기 게이트를 달았고 → 그 게이트가 진짜 사람 말을 버렸다.
// (2026-09-03 실기기: 4.9초짜리 실제 발화가 -42.7dBFS라는 이유로 버려졌다.)
//
// 문턱 하나를 손으로 맞추면 그 대가를 다른 문턱으로 갚게 된다. 특별한 값을
// 쓸 근거가 실측으로 확인되기 전까지는 공용값을 쓴다.

const Duration kStreamingSttConnectTimeout = Duration(seconds: 6);

/// 종료 직전, 아직 안 돌아온 마지막 전사문을 기다리는 상한.
/// 실측에서 speech_stopped → completed가 350~800ms였다. 2초면 충분하고,
/// 넘으면 통화 종료가 눈에 띄게 늦어지므로 여기서 끊는다.
const Duration kStreamingSttFlushTimeout = Duration(seconds: 2);

/// `session.update`를 서버가 받아들였다는 확인을 기다리는 시간.
/// 확인 없이 오디오를 흘리면 설정이 반영 안 된 세션에 말이 들어간다.
const Duration kStreamingSttConfigTimeout = Duration(seconds: 4);

/// 🔁 [RECONNECT] 재연결 간격의 **상한**. 지수 증가가 여기서 멈춘다.
///
/// 예전에는 5회(0.5·1·2·4·8초 = 15.5초)를 쓰고 포기했다. 그러면 **이동 중
/// 15초 끊김 한 번에 전사가 영구히 끝난다** — 셀룰러에서는 반드시 걸린다.
/// (2026-09-04 실기기: 5G 호스트에서 소켓과 WebRTC가 같은 순간 끊겼고,
///  재시도 5회가 다 실패하자 마이크까지 닫혔다.)
///
/// 이제 **통화가 살아 있는 동안은 계속 붙어 본다.** 끝내는 것은 횟수가 아니라
/// `shouldReconnect` 게이트다 — 방을 나가면 그 게이트가 닫히고 재연결도 멈춘다.
const Duration kStreamingSttBackoffCeiling = Duration(seconds: 10);

/// 이 횟수를 넘으면 실패 로그를 줄인다. **포기하는 횟수가 아니다.**
/// 10초 간격으로 계속 붙어 보므로, 긴 끊김에서 로그가 폭주하지 않게 한다.
const int kStreamingSttQuietLogAfter = 5;

/// 🔁 [RECONNECT] [attempt]번째 재시도 전에 기다릴 시간.
///
/// `0.5 → 1 → 2 → 4 → 8 → 10 → 10초…` 로 늘다가 상한에서 멈춘다.
/// **사다리에 끝은 없다.** 끝내는 것은 횟수가 아니라 `shouldReconnect`
/// 게이트이고, 그 게이트는 방을 나갈 때만 닫힌다.
Duration streamingSttBackoff(int attempt) {
  if (attempt <= 1) return const Duration(milliseconds: 500);
  // 1 << 31 부터는 int가 넘칠 자리다. 그 훨씬 앞에서 이미 상한이다.
  if (attempt >= 32) return kStreamingSttBackoffCeiling;
  final int ms = 500 * (1 << (attempt - 1));
  return ms >= kStreamingSttBackoffCeiling.inMilliseconds
      ? kStreamingSttBackoffCeiling
      : Duration(milliseconds: ms);
}

/// 🚫 재시도로 **풀리지 않는** 실패면 그 이유, 아니면 null.
///
/// 끊김(`SocketException`)·서버 흔들림(5xx)·한도(429)는 다시 붙으면 풀린다.
/// 열쇠가 틀린 것(401)과 권한이 없는 것(403)은 10초마다 영원히 두드려도
/// 그대로다 — 이런 것만 갈라서 기존 fatal 정책으로 보낸다.
///
/// `dart:io`의 핸드셰이크 실패는 `WebSocketException(message, httpStatusCode)`
/// 로 **상태 코드를 실어서** 온다(dart-sdk `_http/websocket_impl.dart`).
/// 문자열을 뒤질 필요가 없다.
String? streamingSttPermanentReason(Object error) {
  if (error is WebSocketException) {
    final int? code = error.httpStatusCode;
    if (code == 401 || code == 403) return 'auth_$code';
  }
  return null;
}

/// 전사 세션 하나. 대화방 세션 동안 살아 있고, 턴마다 새로 만들지 않는다.
///
/// **연결과 마이크 입력은 분리되어 있다.** 소켓은 유지한 채
/// [openAudioGate] / [closeAudioGate]로 오디오 전송만 여닫는다.
class OpenAiStreamingTranscribeSession {
  OpenAiStreamingTranscribeSession({
    required this.apiKey,
    required String languageCode,
    this.onLog,
    this.vadThreshold = kStreamingSttVadThreshold,
    this.vadPrefixPaddingMs = kStreamingSttVadPrefixPaddingMs,
    this.vadSilenceDurationMs = kStreamingSttVadSilenceDurationMs,
  }) : _languageCode = languageCode;

  final String apiKey;

  // ── Server VAD. 기본값은 공용이고, 부르는 쪽이 갈아 끼울 수 있다.
  //   모드별로 다르게 잡을 근거가 생기면 그때 한 벌을 넘긴다.
  final double vadThreshold;
  final int vadPrefixPaddingMs;
  final int vadSilenceDurationMs;

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

  /// 🔁 [RECONNECT] 소켓이 (다시) 붙었다. 화면의 "연결 중" 표시를 내리는 자리다.
  /// 첫 연결에도 불리므로, 호출부는 상태가 켜져 있을 때만 내리면 된다.
  void Function()? onConnected;
  void Function()? onGaveUp;
  void Function(DateTime at)? onFirstAudioSent;

  /// 🔬 서버 VAD가 발화 구간을 확정한 순간(`input_audio_buffer.committed`).
  ///
  /// **item_id가 정해지는 유일한 자리다.** 진단용 A/B 비교가 "방금 끝난 발화의
  /// 오디오"를 나중에 도착할 전사문과 이어 붙이려면 이 순간이 필요하다.
  /// 붙이지 않는 모드에서는 아무 일도 일어나지 않는다.
  void Function(String itemId, int? voicedMs, String voicedSource)?
      onUtteranceCommitted;

  /// 재연결을 시도해도 되는 상황인지 호출부가 판단한다.
  /// (백그라운드에서는 소켓이 붙지 않으므로 재시도를 태우면 안 된다)
  bool Function()? shouldReconnect;

  WebSocket? _socket;
  StreamSubscription? _sub;
  Completer<bool>? _configured;
  bool _disposed = false;
  bool _audioGateOpen = false;

  /// 끊길 때 듣고 있었는가. 재연결 **사슬 전체**에 걸쳐 들고 간다.
  /// 시도마다 `_audioGateOpen`을 다시 읽으면, 첫 시도가 이미 닫아 둔 값을
  /// 읽어 두 번째 시도부터는 "안 듣고 있었다"가 된다 — 그러면 다시 붙어도
  /// 게이트가 영영 안 열린다(실기기 2026-10-13: 1초 넘는 끊김마다 마이크 사망).
  bool _reopenGateAfterReconnect = false;
  bool _firstAudioSent = false;
  bool _reconnectInProgress = false;
  int _retryCount = 0;

  /// 🚫 재시도로 안 풀리는 실패의 이유. 차면 재연결 루프를 끝낸다.
  /// 일시적 끊김은 절대 여기 오지 않는다 — 그건 계속 붙어 봐야 한다.
  String? _permanentFailure;
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
    if (apiKey.trim().isEmpty) {
      // 설정 문제다. 10초마다 빈 열쇠로 두드려 봐야 결과가 같다.
      _permanentFailure = 'no_api_key';
      _lg('❌ [STREAM-STT]', 'connect_failed reason=no_api_key');
      return false;
    }
    final sw = Stopwatch()..start();
    try {
      final realtimeToken = await SecureAiGateway.openAiRealtimeToken();
      final socket = await WebSocket.connect(
        kStreamingSttEndpoint,
        headers: {'Authorization': 'Bearer $realtimeToken'},
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
      _permanentFailure = null;
      onConnected?.call();
      _lg(
        '✅ [STREAM-STT]',
        'connected model=$kStreamingSttModel '
            'lang=${_languageCode.isEmpty ? 'auto' : _languageCode} '
            'rate=$kStealthVoxSttSampleRate vad=server_vad '
            'threshold=$vadThreshold '
            'prefixMs=$vadPrefixPaddingMs '
            'silenceMs=$vadSilenceDurationMs '
            'connectMs=${sw.elapsedMilliseconds}',
      );
      return true;
    } catch (e) {
      // 재시도로 풀릴 실패인지 여기서 가른다. 아니라면 재연결 루프가
      // 이 표식을 보고 멈춘다 — 그 판단을 루프에 흩어 두지 않는다.
      _permanentFailure = streamingSttPermanentReason(e);
      _lg(
          '❌ [STREAM-STT]',
          'connect_failed(${e.runtimeType}) '
              'elapsedMs=${sw.elapsedMilliseconds} '
              'permanent=${_permanentFailure ?? 'no'}');
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
              'threshold': vadThreshold,
              'prefix_padding_ms': vadPrefixPaddingMs,
              'silence_duration_ms': vadSilenceDurationMs,
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
    // 끊긴 동안 호출부가 일부러 닫았다면(TTS 재생 등) 다시 붙어도 열지 않는다.
    _reopenGateAfterReconnect = false;
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
        _lg(
            '📡 [STREAM-VAD]',
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
          final local = spanMs - vadSilenceDurationMs;
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
        onUtteranceCommitted?.call(committedId, voicedMs, source);
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
    if (_audioGateOpen) _reopenGateAfterReconnect = true;
    _audioGateOpen = false;
    try {
      await _teardownSocket();
      final gate = shouldReconnect;
      if (gate != null && !gate()) {
        _lg('🎙️ [STREAM-STT]', 'reconnect_skipped reason=gate_closed');
        return;
      }
      // 🔁 [RECONNECT] **횟수로 포기하지 않는다.** 위 `gate()`가 이미
      //   "이 세션을 아직 원하는가"를 판정했고, 그것이 유일한 종료 조건이다.
      //   방을 나가거나 세대가 바뀌면 게이트가 닫히고 여기 오지도 않는다.
      if (_permanentFailure != null) {
        _endReconnectLoop();
        return;
      }
      _retryCount++;
      onReconnecting?.call(_retryCount);
      // 지수로 늘리되 상한에서 멈춘다. 끊김이 길어도 10초마다 계속 두드린다.
      final delay = streamingSttBackoff(_retryCount);
      await Future<void>.delayed(delay);
      if (_disposed) return;
      if (gate != null && !gate()) {
        _lg('🎙️ [STREAM-STT]',
            'reconnect_skipped reason=gate_closed_after_delay');
        return;
      }
      final ok = await connect();
      if (ok && _reopenGateAfterReconnect) {
        _reopenGateAfterReconnect = false;
        // 끊기기 전에 듣고 있었다면 그대로 다시 듣는다. 끊긴 동안의 발화는
        // 서버에 도달하지 않았으므로 복구하지 않는다(있지도 않은 말을
        // 만들어 내는 것보다 한 턴을 잃는 쪽이 낫다).
        openAudioGate(reason: 'reconnected');
      }
      if (!ok) {
        if (_permanentFailure != null) {
          _endReconnectLoop();
          return;
        }
        // 한 번 실패했다고 사다리를 건너뛰지 않는다. 이 구역을 빠져나간 뒤
        // 다음 백오프를 예약한다.
        // 긴 끊김에서 로그가 폭주하지 않게, 초반 몇 번만 매번 남기고
        // 그 뒤로는 10번에 한 번만 남긴다. **재시도는 계속된다.**
        if (_retryCount <= kStreamingSttQuietLogAfter || _retryCount % 10 == 0) {
          _lg(
              '[STREAM-STT]',
              'reconnect_attempt_failed attempt=$_retryCount '
                  'nextInMs=${streamingSttBackoff(_retryCount + 1).inMilliseconds}');
        }
        _reconnectInProgress = false;
        unawaited(Future<void>(() => _reconnect(reason)));
      }
    } finally {
      _reconnectInProgress = false;
    }
  }

  /// 🚫 재시도로 안 풀리는 실패에서만 부른다. 여기서만 기존 fatal 정책으로
  /// 넘어간다 — 통화 중 끊김은 이 길로 오지 않는다.
  void _endReconnectLoop() {
    final String why = _permanentFailure ?? 'permanent';
    _lg('❌ [STREAM-STT]',
        'reconnect_stopped reason=$why attempts=$_retryCount — 재시도로는 안 풀린다');
    onGaveUp?.call();
    onFatalError?.call(why);
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
