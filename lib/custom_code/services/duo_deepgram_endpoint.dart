// ====================================================================
// 📡 [DUO-ENDPOINT] Deepgram을 **발화 경계 센서로만** 쓰는 자리
// --------------------------------------------------------------------
// 여기서 Deepgram에게 묻는 것은 하나뿐이다.
//
//   "지금 한 사람이 한 말이 언제 시작해서 언제 끝났나?"
//
// **글자는 받아 오되 쓰지 않는다.** 최종 전사문의 책임자는 `gpt-transcribe`
// 하나다. Deepgram의 transcript는 Deepgram이 스스로 경계를 재기 위해 쓰는
// 내부 재료일 뿐이고, 이 클래스 밖으로 나가지 않는다.
//
// 🚫 **PCM을 자르지 않는다.** 이 클래스는 소리를 흘려보내기만 하고 무엇도
//   버리지 않는다. 소리를 담는 일은 `DuoUtteranceCapture`가 한다. 둘을 한
//   곳에 합치면 "판정으로 프레임을 버리는 gate"가 되고, 그러면 작은 음절과
//   짧은 대답이 조용히 사라진다.
//
// ── 종료 신호를 UtteranceEnd 하나로 통일한 이유 ──────────────────────
//
// Deepgram은 끝을 두 가지로 알린다.
//
//   speech_final   `endpointing` — 실제 오디오 VAD가 무음을 재서 낸다.
//                  배경 잡음이 있으면 늦거나 아예 안 온다.
//   UtteranceEnd   `utterance_end_ms` — **마지막으로 확정된 단어가 끝난 뒤
//                  새 단어가 없는 시간**을 잰다. 잡음이 있어도 단어가 안
//                  잡히면 끝을 알아챈다.
//
// Duo는 [kDuoUtteranceEndMs]의 UtteranceEnd **하나만** 커밋 신호로 쓴다.
// `speech_final`로도 닫으면 한 발화가 두 번 커밋되고, 앱이 별도의 침묵
// 타이머를 하나 더 두면 판단기가 둘이 된다.
//
// 🕰️ **UtteranceEnd 뒤에 더 기다리지 않는다.** 이 이벤트는 이미 마지막 단어
//   뒤로 1.8초의 공백을 확인하고 온다. 거기서 400ms를 더 기다리면 지연만
//   2.2초가 되고, 그 사이에 시작된 다음 발화의 앞부분이 이전 발화에 붙는다.
//   도착 시점까지 담긴 소리가 곧 뒤 여유다.
// ====================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:web_socket_channel/io.dart';

import 'pcm_audio_utils.dart';

/// 발화 종료를 재는 침묵. **Deepgram 지원 범위는 1000~5000ms다.**
///
/// 1800ms인 이유는 실기기 로그다. 2026-09-04 실측에서 한 문장 안의 숨 고르기가
/// 617 · 629 · 760 · 834 · **1164**ms였고, 진짜 턴 전환은 **4957**ms 이상이었다
/// (같은 표가 `routine_mode_duo.dart`의 `kDuoVadSilenceDurationMs` 옆에 있다).
///
/// 1500이면 가장 긴 쉼 위로 336ms밖에 안 남아 사람마다의 변동을 못 흡수한다.
/// 1800이면 여유가 636ms로 늘고, 진짜 턴 전환과는 여전히 3초 이상 뜬다.
/// 대가는 턴마다 전사가 300ms 늦어지는 것뿐이다 — 목소리는 통화 경로로 이미
/// 실시간으로 가 있고, 여기서 정하는 것은 **글자가 언제 확정되는가**다.
///
/// **빨리 띄우는 것보다 한 문장을 통째로 gpt-transcribe에 넣는 것이 앞선다.**
const int kDuoUtteranceEndMs = 1800;

/// 🕰️ [STALE-SPEECH] 발화가 열린 뒤 **단어가 하나도 안 잡히면** 얼마 만에
/// "말하는 중"을 내릴 것인가.
///
/// SpeechStarted는 VAD가 내는 신호라 잡음에도 열린다. 그런데 UtteranceEnd는
/// **마지막으로 확정된 단어** 뒤의 공백을 재므로, 단어가 하나도 안 잡히면
/// 종료 신호가 영영 오지 않는다. 그 발화는 열린 채로 굳는다.
///
/// 2026-09-07 실기기 통역에서 그 일이 났다. 마이크가 무음(outLevel=0.000)인데
/// 발화가 열린 채 굳었고(`started=3 ended=2`), "말하는 중"을 보고 상대 목소리를
/// 미루는 INTERP-YIELD가 **세 마디를 끝까지 안 틀었다.**
///
/// ⚠️ **소리는 버리지 않는다.** 여기서 내리는 것은 "말하는 중" 표시뿐이고,
///   담기는 그대로 이어진다. 조용히 말한 진짜 발화였다면 단어가 늦게라도
///   잡히고, 그때 UtteranceEnd가 평소대로 확정한다.
/// 🕰️ **[kDuoUtteranceEndMs]보다 길어야 한다.** 정상 발화에서는 마지막 단어가
///   두 시계를 나란히 세운다 — UtteranceEnd는 1800ms 뒤, 이 값은 3000ms 뒤다.
///   순서가 뒤집히면 멀쩡한 발화가 확정되기 전에 굳었다고 판정되고, 상대
///   목소리가 내 말 위로 끼어든다.
const int kDuoSpeechStaleMs = 3000;

/// 🔇 [SILENCE-GATE] Deepgram에는 **말이 있는 구간만** 보낸다(직접 대화).
///
/// 과금이 보낸 소리 길이를 따르므로, 무음까지 통화 내내 흘리면 말하는 시간의
/// 3~4배를 낸다(2026-11-21 실측: 30분 통화에 폰마다 30.3분 전송).
/// Deepgram은 경계 센서일 뿐이고 소리는 앱이 따로 담으므로, 보내지 않은
/// 구간이 전사·저장에 미치는 영향은 없다.
///
/// 끄려면 `--dart-define=DUO_DG_SILENCE_GATE=false`.
const bool kDuoDeepgramSilenceGate =
    bool.fromEnvironment('DUO_DG_SILENCE_GATE', defaultValue: true);

/// 이 세기(dBFS) 이상인 조각이 오면 문을 연다. 기존 "목소리 프레임" 기준과
/// 같은 값이다 — 근거리 말소리 −30~−37, 방 잡음 −60대(2026-11 실측).
const double kDuoDeepgramGateOpenDbfs = -50.0;

/// 문이 닫혀 있는 동안 들고 있다가, 열릴 때 **앞서** 보내는 소리의 길이.
/// 첫 음절이 문 여는 순간보다 앞에서 시작하기 때문이다.
const int kDuoDeepgramGatePrerollMs = 1000;

/// 마지막 목소리 뒤로도 이만큼은 계속 보낸다. **[kDuoUtteranceEndMs]보다 길어야
/// 한다** — Deepgram이 1.8초 무음을 "들어야" UtteranceEnd를 낸다.
const int kDuoDeepgramGateHangoverMs = kDuoUtteranceEndMs + 600;

/// 소리를 안 보내는 동안 연결을 살려 두는 주기(Deepgram은 10초 침묵에 끊는다).
const Duration kDuoDeepgramKeepAliveEvery = Duration(seconds: 4);

/// 언어를 아직 모를 때 쓰는 값. **비워 두면 안 된다** — Deepgram의 기본은
/// `en`이라, 한국어를 말하는데 영어 모델로 듣게 된다. 그러면 단어가 확정되지
/// 않고, 마지막 단어 시각에 기대는 UtteranceEnd가 제때 오지 않는다.
///
/// 만능 통역이 첫 발화로 Origin을 판정하기 전까지 여기에 머문다. 판정이
/// 끝나면 `switchLanguage`가 실제 언어로 소켓을 다시 연다.
const String kDuoDeepgramAutoLanguage = 'multi';

/// 직접 대화와 만능 통역이 같은 값으로 시작한다. 두 모드의 성질이 실제로
/// 다르다는 것이 로그로 확인되면 그때 갈라 잡는다.
///
/// 🎯 **모델을 생략하지 않는다.** 빼면 최신 모델이 아니라 `base-general`이
///   붙는다. Deepgram의 글자를 최종 결과로 쓰지는 않지만, UtteranceEnd가
///   **그 글자의 마지막 단어 시각**에 기대므로 단어를 안정적으로 잡는
///   모델일수록 경계도 안정적이다. Nova-3는 한국어(ko)를 정식 지원한다.
Uri buildDuoDeepgramEndpointUri(String languageCode) {
  final String language = languageCode.trim().isEmpty
      ? kDuoDeepgramAutoLanguage
      : languageCode.trim();
  return Uri.parse(
    'wss://api.deepgram.com/v1/listen'
    '?model=nova-3'
    '&language=$language'
    // 🔇 글자를 쓰지 않으므로 꾸밈은 필요 없다. 다만 끄면 안 되는 것이 둘이다.
    //   · interim_results — UtteranceEnd가 단어 시각을 이걸로 잡는다
    //   · vad_events      — SpeechStarted가 여기서 온다
    '&interim_results=true'
    '&vad_events=true'
    '&utterance_end_ms=$kDuoUtteranceEndMs'
    '&encoding=linear16'
    // 🎚️ 마이크와 반드시 같은 값이어야 한다. 한쪽만 바꾸면 Deepgram이
    //   조용히 엉뚱한 속도로 듣는다.
    '&sample_rate=$kStealthVoxSttSampleRate'
    '&channels=1'
    '&filler_words=false',
  );
}

/// 통화 한 통 = 이 객체 한 개.
class DuoDeepgramEndpointSensor {
  DuoDeepgramEndpointSensor({
    required this.apiKey,
    required this.languageCode,
    this.onLog,
    this.silenceGate = false,
  });

  /// 무음 구간을 Deepgram에 보내지 않는다. 직접 대화만 켠다.
  final bool silenceGate;

  final String apiKey;

  /// Deepgram이 들을 언어. 최종 전사에 넘기는 Origin Language와 같은 값에서
  /// 나와야 한다 — 다르면 경계와 글자가 서로 다른 말을 듣고 있게 된다.
  final String languageCode;

  final void Function(String tag, String msg)? onLog;

  /// 말이 시작됐다. 여기서 발화 하나가 열린다.
  void Function()? onSpeechStarted;

  /// 말이 끝났다. **커밋은 여기 한 곳에서만 일어난다.**
  void Function()? onUtteranceEnd;

  /// 소켓이 죽었다. **여기서 열린 발화를 닫는다** — 안 닫으면 "말하는 중"이
  /// 고착되어 통역의 TTS·양보가 영영 안 열린다.
  void Function(String reason)? onClosed;

  /// 🕰️ 열린 발화에서 [kDuoSpeechStaleMs] 동안 단어가 하나도 안 잡혔다.
  /// **발화를 닫는 것이 아니라 "말하는 중"만 내린다** — 소리는 계속 담긴다.
  void Function()? onSpeechStale;

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  bool _closed = false;

  /// 지금 발화가 열려 있는가. 열려 있지 않으면 UtteranceEnd를 흘려보낸다 —
  /// 시작 없이 끝만 오는 이벤트로 빈 발화를 만들지 않기 위해서다.
  bool _speechOpen = false;

  /// 🕰️ 열려는 있으나 단어가 안 잡혀 "말하는 중"을 내린 상태.
  /// 단어가 하나라도 잡히면 곧바로 풀린다.
  bool _speechStale = false;
  Timer? _staleTimer;

  /// 🔎 [계측 전용] 받은 것과 실제로 소켓에 보낸 것.
  int _micFrames = 0;
  int _micBytes = 0;
  int _sentFrames = 0;
  int _sentBytes = 0;
  int _droppedFrames = 0;
  int _lastSendLogAt = 0;

  // [SILENCE-GATE] 상태. 문이 닫힌 동안은 최근 [kDuoDeepgramGatePrerollMs]만 들고 있다.
  bool _gateOpen = false;
  int _gateSilentMs = 0;
  int _gateSkippedBytes = 0;
  int _gateOpenCount = 0;
  int _gateCloseCount = 0;
  int _keepAliveCount = 0;
  final List<Uint8List> _gateRing = <Uint8List>[];
  int _gateRingBytes = 0;
  Timer? _keepAliveTimer;

  @visibleForTesting
  bool get gateOpenForTest => _gateOpen;
  @visibleForTesting
  int get gateSkippedBytesForTest => _gateSkippedBytes;
  @visibleForTesting
  int get gateOpenCountForTest => _gateOpenCount;
  @visibleForTesting
  int get gateCloseCountForTest => _gateCloseCount;

  int _speechStartedCount = 0;
  int _staleCount = 0;
  int _utteranceEndCount = 0;
  int _ignoredEndCount = 0;

  bool get isOpen => _channel != null && !_closed;
  bool get isSpeechOpen => _speechOpen;

  /// 🗣️ 사람이 **지금 말하고 있는가.** [isSpeechOpen]과 다르다 — 열려는
  /// 있으나 단어가 안 잡혀 굳은 발화는 여기서 거짓이다. 통역의 양보
  /// (INTERP-YIELD)가 이 값을 본다.
  bool get isUserSpeaking => _speechOpen && !_speechStale;
  int get staleCount => _staleCount;
  int get speechStartedCount => _speechStartedCount;
  int get utteranceEndCount => _utteranceEndCount;

  void _lg(String msg) => onLog?.call('📡 [DUO-ENDPOINT]', msg);

  Future<bool> connect() async {
    if (apiKey.isEmpty) {
      _lg('connect_skipped reason=no_key');
      return false;
    }
    try {
      final uri = buildDuoDeepgramEndpointUri(languageCode);
      _channel = IOWebSocketChannel.connect(
        uri,
        headers: <String, dynamic>{'Authorization': 'Bearer $apiKey'},
      );
      // 연결 실패는 아래 stream.onError로 이미 처리한다. `ready`를 아무도 안 받으면
      // 같은 오류가 "잡히지 않은 오류"로 Crashlytics에 치명으로 올라간다(DNS 실패 시).
      _channel!.ready.catchError((Object _) {});
      _sub = _channel!.stream.listen(
        _onMessage,
        onError: (Object e) {
          _lg('socket_error ${e.runtimeType}');
          _failOpenSpeech('socket_error');
        },
        onDone: () {
          _lg('socket_done');
          _failOpenSpeech('socket_done');
        },
        cancelOnError: false,
      );
      _closed = false;
      _startKeepAlive();
      _lg('connected model=nova-3 lang=${uri.queryParameters['language']} '
          'utteranceEndMs=$kDuoUtteranceEndMs');
      return true;
    } catch (e) {
      _lg('connect_failed ${e.runtimeType}');
      _channel = null;
      return false;
    }
  }

  /// 소리를 흘려보낸다. **되돌아오는 글자는 쓰지 않는다.**
  void addPcm(Uint8List pcm) {
    if (_closed || pcm.isEmpty) {
      // [계측] 닫힌 소켓으로 온 몫. 동작은 예전과 같다.
      if (pcm.isNotEmpty) _droppedFrames++;
      return;
    }
    _micFrames++;
    _micBytes += pcm.lengthInBytes;
    if (!silenceGate || _gateAllows(pcm)) {
      _sendPcm(pcm);
    }
    _maybeLogPcm();
  }

  void _sendPcm(Uint8List pcm) {
    try {
      _channel?.sink.add(pcm);
      if (_channel == null) {
        _droppedFrames++;
      } else {
        _sentFrames++;
        _sentBytes += pcm.lengthInBytes;
      }
    } catch (_) {
      // 소켓이 잠깐 닫힌 것뿐이다. 소리는 이미 캡처가 들고 있다.
      _droppedFrames++;
    }
  }

  /// 이 조각을 지금 Deepgram에 보내야 하는가.
  ///
  /// 열기: 목소리 세기가 문턱을 넘으면 열고, 들고 있던 앞소리를 먼저 보낸다.
  /// 닫기: 목소리가 끊긴 지 [kDuoDeepgramGateHangoverMs]가 지나고 Deepgram도
  /// "말하는 중"이 아닐 때만 닫는다 — 그 전에 닫으면 UtteranceEnd가 안 온다.
  bool _gateAllows(Uint8List pcm) {
    final double db = pcm16LinearToDbfs(pcm16Rms(pcm));
    // 24kHz 16bit mono = 48 bytes/ms
    final int ms = pcm.lengthInBytes ~/ 48;
    final bool voiced = db >= kDuoDeepgramGateOpenDbfs;
    if (voiced) {
      _gateSilentMs = 0;
    } else {
      _gateSilentMs += ms;
    }
    if (_gateOpen) {
      final bool deepgramBusy = _speechOpen && !_speechStale;
      if (!voiced &&
          !deepgramBusy &&
          _gateSilentMs >= kDuoDeepgramGateHangoverMs) {
        _gateOpen = false;
        _gateCloseCount++;
        _lg('silence_gate=closed silentMs=$_gateSilentMs');
        _holdInRing(pcm);
        return false;
      }
      return true;
    }
    if (voiced) {
      _gateOpen = true;
      _gateOpenCount++;
      _lg('silence_gate=open dbfs=${db.toStringAsFixed(1)} '
          'prerollBytes=$_gateRingBytes');
      for (final Uint8List held in _gateRing) {
        _sendPcm(held);
      }
      _gateRing.clear();
      _gateRingBytes = 0;
      return true;
    }
    _holdInRing(pcm);
    return false;
  }

  void _holdInRing(Uint8List pcm) {
    _gateSkippedBytes += pcm.lengthInBytes;
    _gateRing.add(pcm);
    _gateRingBytes += pcm.lengthInBytes;
    final int maxBytes = kDuoDeepgramGatePrerollMs * 48;
    while (_gateRingBytes > maxBytes && _gateRing.length > 1) {
      _gateRingBytes -= _gateRing.removeAt(0).lengthInBytes;
    }
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    if (!silenceGate) return;
    _keepAliveTimer = Timer.periodic(kDuoDeepgramKeepAliveEvery, (_) {
      if (_closed || _channel == null || _gateOpen) return;
      try {
        _channel?.sink.add(jsonEncode(<String, String>{'type': 'KeepAlive'}));
        _keepAliveCount++;
      } catch (_) {}
    });
  }

  void _maybeLogPcm() {
    // [계측] 받은 것과 실제로 보낸 것을 갈라 놓는다. 둘이 벌어지면
    // 배선이 끊긴 것이고, 나란히 가면 소켓까지는 갔다는 뜻이다.
    // (무음 게이트가 켜져 있으면 sentBytes가 micBytes보다 작은 것이 정상이다)
    if (_micFrames - _lastSendLogAt >= 100) {
      _lastSendLogAt = _micFrames;
      _lg('[DUO-DG-PCM] micFrames=$_micFrames sentFrames=$_sentFrames '
          'droppedFrames=$_droppedFrames micBytes=$_micBytes '
          'sentBytes=$_sentBytes socket=${_channel == null ? 'null' : 'open'} '
          'closed=$_closed speechOpen=$_speechOpen stale=$_speechStale '
          'gate=${silenceGate ? (_gateOpen ? 'open' : 'closed') : 'off'} '
          'gateSkippedBytes=$_gateSkippedBytes gateOpens=$_gateOpenCount '
          'keepAlives=$_keepAliveCount');
    }
  }

  /// 소켓 없이 이벤트 판정만 시험한다. **동작은 실제 경로와 같은 함수다** —
  /// 시험용으로 규칙을 다시 적으면 그 사본만 맞고 본선은 틀릴 수 있다.
  @visibleForTesting
  void handleMessageForTest(String raw) => _onMessage(raw);

  /// 🚪 [GATE-SYNC] **문이 닫혔다. 열린 발화를 버린다.**
  ///
  /// 통역은 상대 목소리를 트는 동안 마이크 문을 닫는다. 그때 앱은
  /// `_capture.abort()`로 담던 소리를 버리는데, 여기(Deepgram)의 `_speechOpen`은
  /// 그대로 남아 다음 문이 열린 구간까지 끌려갔다. 그러면 소리를 못 받는
  /// 동안에는 단어가 없어 UtteranceEnd가 안 오고, 다시 열렸을 때는 이미
  /// 끝난 발화가 아직 열려 있다고 믿는다 — 실기기에서 `utt=- capturedMs=0`,
  /// `started=2 ended=2`인데 실제 발화는 더 많았던 것이 그 모습이다(2026-09-10).
  ///
  /// **버리기만 하고 커밋하지 않는다.** 앱이 이미 소리를 버렸으므로
  /// `onUtteranceEnd`를 부르면 빈 종료만 남는다. 소켓은 그대로 둔다 —
  /// 다시 여는 값보다 잃는 시간이 크다.
  void abortOpenSpeech(String reason) {
    if (_closed || !_speechOpen) return;
    _speechOpen = false;
    _speechStale = false;
    _cancelStaleTimer();
    _lg('[GATE-SYNC] speech_aborted reason=$reason '
        'started=$_speechStartedCount ended=$_utteranceEndCount');
  }

  /// 소켓이 죽었을 때 열린 발화를 닫는다. **고착을 막는 자리다.**
  void _failOpenSpeech(String reason) {
    if (_closed) return;
    _speechOpen = false;
    _speechStale = false;
    _cancelStaleTimer();
    onClosed?.call(reason);
  }

  void _onMessage(dynamic raw) {
    if (_closed || raw is! String) return;
    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final String type = (data['type'] ?? '').toString();

    if (type == 'SpeechStarted') {
      // 이미 열려 있으면 무시한다 — 한 발화는 하나다.
      if (_speechOpen) return;
      _speechOpen = true;
      _speechStale = false;
      _speechStartedCount++;
      _armStaleTimer();
      onSpeechStarted?.call();
      return;
    }

    if (type == 'UtteranceEnd') {
      // 🚫 마지막 단어가 없다는 뜻이다. 늦게 온 껍데기이거나 같은 구간이
      //   두 번 온 것이라 커밋 대상이 아니다.
      final num? lastWordEnd = data['last_word_end'] as num?;
      if (lastWordEnd == null || lastWordEnd < 0) {
        _ignoredEndCount++;
        _lg('utterance_end_ignored reason=no_last_word');
        return;
      }
      // 시작 없이 끝만 왔다. 담긴 소리가 없으므로 흘려보낸다.
      if (!_speechOpen) {
        _ignoredEndCount++;
        _lg('utterance_end_ignored reason=no_open_speech');
        return;
      }
      _speechOpen = false;
      _speechStale = false;
      _cancelStaleTimer();
      _utteranceEndCount++;
      onUtteranceEnd?.call();
      return;
    }

    // 🗑️ Results(글자)는 여기서 끝난다. **밖으로 내보내지 않는다.**
    //   Deepgram이 경계를 재려면 글자가 필요할 뿐이고, 최종 전사문의
    //   책임자는 gpt-transcribe 하나다.
    //
    //   ⚠️ 다만 **단어가 잡혔다는 사실 하나**는 읽는다. UtteranceEnd가 기대는
    //   것이 바로 그 신호라, 단어가 안 잡히는 발화는 영영 안 닫힌다
    //   ([kDuoSpeechStaleMs]). 글자 자체는 여전히 이 함수 밖으로 안 나간다.
    if (type == 'Results' && _speechOpen && _hasWord(data)) _noteWord();
  }

  /// 이 응답에 실제 단어가 실려 있는가. **글자는 읽되 내보내지 않는다.**
  bool _hasWord(Map<String, dynamic> data) {
    final channel = data['channel'];
    if (channel is! Map) return false;
    final alternatives = channel['alternatives'];
    if (alternatives is! List || alternatives.isEmpty) return false;
    final first = alternatives.first;
    if (first is! Map) return false;
    return (first['transcript'] ?? '').toString().trim().isNotEmpty;
  }

  /// 단어가 잡혔다 = 사람이 실제로 말하고 있다. 굳었던 표시를 되돌린다.
  void _noteWord() {
    if (_speechStale) {
      _speechStale = false;
      _lg('speech_unstale — 단어가 잡혔다, 다시 말하는 중이다');
    }
    _armStaleTimer();
  }

  void _armStaleTimer() {
    _cancelStaleTimer();
    _staleTimer = Timer(const Duration(milliseconds: kDuoSpeechStaleMs), () {
      if (_closed || !_speechOpen || _speechStale) return;
      _speechStale = true;
      _staleCount++;
      _lg('speech_stale afterMs=$kDuoSpeechStaleMs — 단어가 안 잡힌다. '
          '말하는 중을 내린다(소리는 계속 담는다)');
      onSpeechStale?.call();
    });
  }

  void _cancelStaleTimer() {
    _staleTimer?.cancel();
    _staleTimer = null;
  }

  /// 통화가 끝났다.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _speechOpen = false;
    _speechStale = false;
    _cancelStaleTimer();
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _lg('closing started=$_speechStartedCount ended=$_utteranceEndCount '
        'ignored=$_ignoredEndCount stale=$_staleCount');
    _lg('[DUO-DG-PCM] call_summary micFrames=$_micFrames '
        'sentFrames=$_sentFrames droppedFrames=$_droppedFrames '
        'micBytes=$_micBytes sentBytes=$_sentBytes gateSkippedBytes=$_gateSkippedBytes '
        'gateOpens=$_gateOpenCount keepAlives=$_keepAliveCount');
    try {
      _channel?.sink.add(jsonEncode(<String, String>{'type': 'CloseStream'}));
    } catch (_) {}
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }
}
