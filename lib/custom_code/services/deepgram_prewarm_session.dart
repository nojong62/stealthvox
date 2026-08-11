import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';

import 'pcm_audio_utils.dart';

String deepgramLanguageCode(String language) {
  switch (language.trim().toLowerCase()) {
    case 'korean':
      return 'ko';
    case 'japanese':
      return 'ja';
    case 'chinese':
      return 'zh';
    case 'spanish':
      return 'es';
    case 'french':
      return 'fr';
    case 'german':
      return 'de';
    case 'italian':
      return 'it';
    case 'portuguese':
      return 'pt';
    case 'russian':
      return 'ru';
    case 'vietnamese':
      return 'vi';
    case 'thai':
      return 'th';
    case 'indonesian':
      return 'id';
    case 'hindi':
      return 'hi';
    case 'arabic':
      return 'ar';
    case 'dutch':
      return 'nl';
    default:
      return 'en';
  }
}

Uri buildAnyoneDeepgramUri(String languageCode) {
  return Uri.parse(
    'wss://api.deepgram.com/v1/listen'
    '?model=nova-3'
    '&language=$languageCode'
    '&smart_format=true'
    '&endpointing=700'
    '&utterance_end_ms=1000'
    '&interim_results=true'
    '&encoding=linear16'
    // 🎚️ 마이크 녹음과 반드시 같은 값이어야 한다. 스트리밍 전사가 24kHz를
    //   요구해 녹음을 올렸으므로 여기도 같이 올린다 — 한쪽만 바꾸면
    //   Deepgram이 조용히 엉뚱한 속도로 듣는다.
    '&sample_rate=$kStealthVoxSttSampleRate'
    '&channels=1'
    '&filler_words=false',
  );
}

/// StealthRoom 메뉴에서 인증된 Deepgram WebSocket을 미리 열어 Anyone에 넘긴다.
class DeepgramPrewarmSession {
  DeepgramPrewarmSession._();

  static final DeepgramPrewarmSession instance = DeepgramPrewarmSession._();

  IOWebSocketChannel? _channel;
  String _apiKey = '';
  String _languageCode = '';
  Future<bool>? _preparing;
  Timer? _keepAliveTimer;
  DateTime? _readyAt;

  // Deepgram can close an audio WebSocket that has stayed idle even when the
  // client-side channel object still exists. A stale channel is worse than a
  // fresh connection because it fails immediately after microphone adoption
  // and forces the recorder to restart.
  static const Duration _maxAdoptableAge = Duration(seconds: 12);

  Future<bool> prepare({
    required String apiKey,
    required String languageCode,
    void Function(String message)? onLog,
  }) {
    if (apiKey.isEmpty) return Future<bool>.value(false);
    if (_channel != null &&
        _apiKey == apiKey &&
        _languageCode == languageCode) {
      return Future<bool>.value(true);
    }
    final inFlight = _preparing;
    if (inFlight != null &&
        _apiKey == apiKey &&
        _languageCode == languageCode) {
      return inFlight;
    }

    _apiKey = apiKey;
    _languageCode = languageCode;
    final future = _prepareInternal(
      apiKey: apiKey,
      languageCode: languageCode,
      onLog: onLog,
    );
    _preparing = future;
    return future.whenComplete(() {
      if (identical(_preparing, future)) _preparing = null;
    });
  }

  Future<bool> _prepareInternal({
    required String apiKey,
    required String languageCode,
    void Function(String message)? onLog,
  }) async {
    await discard(reason: 'replace');
    final sw = Stopwatch()..start();
    try {
      final channel = IOWebSocketChannel.connect(
        buildAnyoneDeepgramUri(languageCode),
        headers: {'Authorization': 'Token $apiKey'},
        pingInterval: const Duration(seconds: 10),
      );
      await channel.ready.timeout(const Duration(seconds: 6));
      _channel = channel;
      _apiKey = apiKey;
      _languageCode = languageCode;
      _readyAt = DateTime.now();
      _keepAliveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        try {
          _channel?.sink.add(jsonEncode({'type': 'KeepAlive'}));
        } catch (_) {}
      });
      onLog?.call(
          '[DG-PREWARM] authenticated lang=$languageCode elapsedMs=${sw.elapsedMilliseconds}');
      return true;
    } catch (error) {
      onLog?.call(
          '[DG-PREWARM] failed reason=${error.runtimeType} elapsedMs=${sw.elapsedMilliseconds}');
      await discard(reason: 'prepare_failed');
      return false;
    } finally {
      sw.stop();
    }
  }

  IOWebSocketChannel? take({
    required String apiKey,
    required String languageCode,
    void Function(String message)? onLog,
  }) {
    if (_apiKey != apiKey || _languageCode != languageCode) return null;
    final channel = _channel;
    if (channel == null) return null;
    final readyAt = _readyAt;
    final age =
        readyAt == null ? _maxAdoptableAge : DateTime.now().difference(readyAt);
    if (age >= _maxAdoptableAge) {
      onLog?.call(
          '[DG-PREWARM] stale ageMs=${age.inMilliseconds} → fresh connect');
      unawaited(discard(reason: 'stale'));
      return null;
    }
    _channel = null;
    _readyAt = null;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    onLog?.call('[DG-PREWARM] adopted lang=$languageCode');
    return channel;
  }

  Future<void> discard({String reason = 'discard'}) async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    final channel = _channel;
    _channel = null;
    _readyAt = null;
    if (channel != null) {
      try {
        await channel.sink.close();
      } catch (_) {}
    }
  }
}
