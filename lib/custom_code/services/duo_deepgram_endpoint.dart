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
//   뒤로 1.5초의 공백을 확인하고 온다. 거기서 400ms를 더 기다리면 지연만
//   1.9초가 되고, 그 사이에 시작된 다음 발화의 앞부분이 이전 발화에 붙는다.
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
/// 1500ms인 이유는 실기기 로그다 — 같은 문장 안에서도 600~1100ms의 쉼이
/// 관측됐다. 500~700ms로 잡으면 한 문장이 두세 개의 말풍선으로 갈린다.
/// **빨리 띄우는 것보다 한 문장을 지키는 것이 앞선다.**
const int kDuoUtteranceEndMs = 1500;

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
  });

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

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  bool _closed = false;

  /// 지금 발화가 열려 있는가. 열려 있지 않으면 UtteranceEnd를 흘려보낸다 —
  /// 시작 없이 끝만 오는 이벤트로 빈 발화를 만들지 않기 위해서다.
  bool _speechOpen = false;

  int _speechStartedCount = 0;
  int _utteranceEndCount = 0;
  int _ignoredEndCount = 0;

  bool get isOpen => _channel != null && !_closed;
  bool get isSpeechOpen => _speechOpen;
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
        headers: <String, dynamic>{'Authorization': 'Token $apiKey'},
      );
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
    if (_closed || pcm.isEmpty) return;
    try {
      _channel?.sink.add(pcm);
    } catch (_) {
      // 소켓이 잠깐 닫힌 것뿐이다. 소리는 이미 캡처가 들고 있다.
    }
  }

  /// 소켓 없이 이벤트 판정만 시험한다. **동작은 실제 경로와 같은 함수다** —
  /// 시험용으로 규칙을 다시 적으면 그 사본만 맞고 본선은 틀릴 수 있다.
  @visibleForTesting
  void handleMessageForTest(String raw) => _onMessage(raw);

  /// 소켓이 죽었을 때 열린 발화를 닫는다. **고착을 막는 자리다.**
  void _failOpenSpeech(String reason) {
    if (_closed) return;
    _speechOpen = false;
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
      _speechStartedCount++;
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
      _utteranceEndCount++;
      onUtteranceEnd?.call();
      return;
    }

    // 🗑️ Results(글자)는 여기서 끝난다. **밖으로 내보내지 않는다.**
    //   Deepgram이 경계를 재려면 글자가 필요할 뿐이고, 최종 전사문의
    //   책임자는 gpt-transcribe 하나다.
  }

  /// 통화가 끝났다.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _speechOpen = false;
    _lg('closing started=$_speechStartedCount ended=$_utteranceEndCount '
        'ignored=$_ignoredEndCount');
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
