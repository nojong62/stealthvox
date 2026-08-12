// ====================================================================
// 🔀 [DUO-RELAY] Duo 직접 대화 전용 PCM 릴레이 클라이언트
// --------------------------------------------------------------------
// 하는 일은 셋뿐이다.
//   1. 방(roomId) 기준으로 릴레이 서버에 붙는다
//   2. 마이크 PCM 조각을 **binary WebSocket frame 그대로** 올려보낸다
//   3. 상대가 올린 PCM 조각을 그대로 받아 [inbound] 스트림으로 넘긴다
//
// 하지 않는 일:
//   · 인코딩(WAV/AAC/MP3/Opus) — PCM16 24kHz mono LE를 손대지 않고 보낸다
//   · 전사·번역·TTS — 릴레이는 소리의 내용을 모른다
//   · 저장 — 보낸 조각도 받은 조각도 남기지 않는다
//
// ⚠️ 이름 주의: 여기서 쓰는 WebSocket은 **우리 릴레이 서버**로 가는 소켓이다.
//   OpenAI 스트리밍 전사 소켓(openai_streaming_transcribe_session.dart)과는
//   완전히 다른 물건이고, 둘은 같은 마이크 스트림을 나란히 먹는다.
// ====================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'pcm_audio_utils.dart';

/// 릴레이가 주고받는 오디오 규격. 앱 전체 STT 샘플레이트와 **같은 값이어야**
/// 마이크 스트림을 그대로 두 갈래로 흘릴 수 있다.
const int kDuoRelaySampleRate = kStealthVoxSttSampleRate;
const String kDuoRelayAudioFormat = 'pcm_s16le_mono';

const Duration kDuoRelayConnectTimeout = Duration(seconds: 6);
const Duration kDuoRelayHelloTimeout = Duration(seconds: 4);

/// 재접속 간격. 통화 중 끊김은 짧게 여러 번 시도하고, 그래도 안 붙으면 포기한다.
const List<int> kDuoRelayRetryDelaysMs = <int>[300, 700, 1500, 3000, 5000];

/// 소켓이 죽은 걸 빨리 알아채기 위한 핑 주기.
const Duration kDuoRelayPingInterval = Duration(seconds: 5);

/// 릴레이 왕복 지연 측정 주기(계측 로그용).
const Duration kDuoRelayRttProbeInterval = Duration(seconds: 10);

/// 릴레이 서버 주소. Remote Config `DuoRelayUrl`이 1순위이고, 그게 비어 있으면
/// 빌드 타임 정의를 쓴다. 둘 다 없으면 직접 대화는 켜지지 않는다.
const String kDuoRelayUrlFromEnv =
    String.fromEnvironment('DUO_RELAY_URL', defaultValue: '');

/// 릴레이 접속 토큰. Remote Config `DuoRelayToken`이 1순위다. 서버가
/// `RELAY_TOKEN` 없이 떠 있으면 빈 값이어도 붙는다(로컬 개발용).
const String kDuoRelayTokenFromEnv =
    String.fromEnvironment('DUO_RELAY_TOKEN', defaultValue: '');

/// 릴레이 클라이언트 한 개 = 통화 한 번. 방을 나가면 버리고 새로 만든다.
class DuoPcmRelayClient {
  DuoPcmRelayClient({
    required this.url,
    required this.roomId,
    required this.uid,
    required this.role,
    required this.sessionId,
    this.token = '',
    this.idToken = '',
    this.onLog,
    this.onPartnerPresence,
  });

  /// `wss://…` 릴레이 주소.
  final String url;

  /// 기존 duo_sessions 문서 ID를 그대로 쓴다 — 릴레이에 별도 방 체계를 만들지 않는다.
  final String roomId;
  final String uid;

  /// 'HOST' 또는 'GUEST'.
  final String role;

  /// 이 통화의 세대값. 방을 다시 열면 값이 바뀌고, 옛 세션의 늦은 프레임을 버린다.
  final String sessionId;

  /// 릴레이 서버가 `RELAY_TOKEN`을 요구할 때 함께 보내는 값.
  final String token;

  /// Firebase ID 토큰. 서버가 uid 소유를 검증하는 데 쓴다. 비회원 게스트는
  /// 토큰이 없으므로 빈 값이고, 그때는 서버가 방 문서의 partnerUid 일치만 본다.
  final String idToken;

  final void Function(String tag, String msg)? onLog;

  /// 상대가 같은 방 릴레이에 붙어 있는지 여부가 바뀔 때 호출된다.
  final void Function(bool present)? onPartnerPresence;

  final StreamController<Uint8List> _inbound =
      StreamController<Uint8List>.broadcast(sync: true);

  WebSocket? _socket;
  StreamSubscription? _sub;
  Completer<bool>? _hello;
  Timer? _rttTimer;
  Timer? _retryTimer;

  bool _disposed = false;
  bool _partnerPresent = false;
  int _retryIndex = 0;
  int _sentBytes = 0;
  int _receivedBytes = 0;
  int _droppedNoPartnerBytes = 0;
  DateTime? _lastRttSentAt;
  int? _lastRttMs;

  /// 상대 PCM. 지터버퍼(DuoPcmJitterPlayer)가 이걸 받아 재생한다.
  Stream<Uint8List> get inbound => _inbound.stream;

  bool get isConnected =>
      !_disposed && _socket != null && _socket!.readyState == WebSocket.open;

  bool get partnerPresent => _partnerPresent;
  int get sentBytes => _sentBytes;
  int get receivedBytes => _receivedBytes;
  int get droppedNoPartnerBytes => _droppedNoPartnerBytes;

  /// 마지막으로 측정된 릴레이 왕복 시간(ms). 편도 추정치는 이 값의 절반이다.
  int? get lastRoundTripMs => _lastRttMs;

  void _lg(String tag, String msg) => onLog?.call(tag, msg);

  /// 소켓을 열고 hello 확인까지 끝낸다. false면 호출부는 직접 대화를 켜지 않는다.
  Future<bool> connect() async {
    if (_disposed) return false;
    if (isConnected) return true;
    if (url.trim().isEmpty) {
      _lg('❌ [DUO-RELAY]', 'no_relay_url');
      return false;
    }
    final sw = Stopwatch()..start();
    try {
      final socket = await WebSocket.connect(url).timeout(
        kDuoRelayConnectTimeout,
      );
      if (_disposed) {
        unawaited(socket.close());
        return false;
      }
      socket.pingInterval = kDuoRelayPingInterval;
      _socket = socket;
      await _sub?.cancel();
      _sub = socket.listen(
        _handleFrame,
        onError: (Object e) => _onSocketLost('ws_error(${e.runtimeType})'),
        onDone: () => _onSocketLost('ws_closed'),
        cancelOnError: true,
      );

      final hello = Completer<bool>();
      _hello = hello;
      _sendJson(<String, dynamic>{
        'type': 'hello',
        'roomId': roomId,
        'uid': uid,
        'role': role,
        'sessionId': sessionId,
        if (token.isNotEmpty) 'token': token,
        if (idToken.isNotEmpty) 'idToken': idToken,
        'audio': <String, dynamic>{
          'format': kDuoRelayAudioFormat,
          'rate': kDuoRelaySampleRate,
          'channels': 1,
        },
      });

      final ok = await hello.future.timeout(
        kDuoRelayHelloTimeout,
        onTimeout: () => false,
      );
      if (!ok) {
        _lg('❌ [DUO-RELAY]', 'hello_unconfirmed elapsedMs=${sw.elapsedMilliseconds}');
        await _teardownSocket();
        return false;
      }
      _retryIndex = 0;
      _startRttProbe();
      _lg(
        '✅ [DUO-RELAY]',
        'connected room=$roomId role=$role rate=$kDuoRelaySampleRate '
            'connectMs=${sw.elapsedMilliseconds}',
      );
      return true;
    } catch (e) {
      _lg('❌ [DUO-RELAY]',
          'connect_failed(${e.runtimeType}) elapsedMs=${sw.elapsedMilliseconds}');
      await _teardownSocket();
      return false;
    } finally {
      sw.stop();
    }
  }

  /// 마이크 PCM 한 조각. **binary frame 그대로** 나간다(base64 금지).
  ///
  /// 상대가 아직 안 붙었으면 쌓지 않고 버린다 — 나중에 몰아서 들려주면 안 된다.
  void sendPcm(Uint8List pcm) {
    if (_disposed || pcm.isEmpty) return;
    if (!isConnected) return;
    if (!_partnerPresent) {
      _droppedNoPartnerBytes += pcm.length;
      return;
    }
    try {
      _socket!.add(pcm);
      _sentBytes += pcm.length;
    } catch (e) {
      _onSocketLost('send_failed(${e.runtimeType})');
    }
  }

  void _handleFrame(dynamic frame) {
    if (_disposed) return;
    if (frame is List<int>) {
      if (frame.isEmpty) return;
      _receivedBytes += frame.length;
      final bytes = frame is Uint8List ? frame : Uint8List.fromList(frame);
      if (!_inbound.isClosed) _inbound.add(bytes);
      return;
    }
    if (frame is! String) return;
    Map<String, dynamic> event;
    try {
      final decoded = jsonDecode(frame);
      if (decoded is! Map<String, dynamic>) return;
      event = decoded;
    } catch (_) {
      return;
    }
    switch (event['type']) {
      case 'ready':
        _setPartnerPresent(event['partnerPresent'] == true);
        final hello = _hello;
        _hello = null;
        if (hello != null && !hello.isCompleted) hello.complete(true);
        break;
      case 'partner':
        _setPartnerPresent(event['present'] == true);
        break;
      case 'pong':
        final sentAt = _lastRttSentAt;
        if (sentAt != null) {
          _lastRttMs = DateTime.now().difference(sentAt).inMilliseconds;
          _lg('⏱️ [DUO-RELAY-RTT]', 'roundTripMs=$_lastRttMs');
        }
        break;
      case 'error':
        _lg('❌ [DUO-RELAY]', 'server_error=${event['reason']}');
        final hello = _hello;
        _hello = null;
        if (hello != null && !hello.isCompleted) hello.complete(false);
        break;
    }
  }

  void _setPartnerPresent(bool present) {
    if (_partnerPresent == present) return;
    _partnerPresent = present;
    _lg('👥 [DUO-RELAY]', 'partnerPresent=$present');
    onPartnerPresence?.call(present);
  }

  void _startRttProbe() {
    _rttTimer?.cancel();
    _rttTimer = Timer.periodic(kDuoRelayRttProbeInterval, (_) {
      if (!isConnected) return;
      _lastRttSentAt = DateTime.now();
      _sendJson(<String, dynamic>{'type': 'ping'});
    });
  }

  void _sendJson(Map<String, dynamic> payload) {
    final socket = _socket;
    if (socket == null || _disposed) return;
    try {
      socket.add(jsonEncode(payload));
    } catch (e) {
      _onSocketLost('send_json_failed(${e.runtimeType})');
    }
  }

  void _onSocketLost(String reason) {
    if (_disposed) return;
    _lg('⚠️ [DUO-RELAY]', 'socket_lost reason=$reason');
    _setPartnerPresent(false);
    unawaited(_teardownSocket());
    _scheduleReconnect();
  }

  /// 끊기면 통화를 죽이지 않고 짧게 다시 붙는다. **밀린 PCM은 재전송하지 않는다** —
  /// 이 클래스는 애초에 큐를 갖고 있지 않으므로 끊긴 동안의 소리는 그냥 사라진다.
  void _scheduleReconnect() {
    if (_disposed) return;
    if (_retryIndex >= kDuoRelayRetryDelaysMs.length) {
      _lg('❌ [DUO-RELAY]', 'gave_up retries=$_retryIndex');
      return;
    }
    final delayMs = kDuoRelayRetryDelaysMs[_retryIndex++];
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(milliseconds: delayMs), () async {
      if (_disposed) return;
      _lg('🔁 [DUO-RELAY]', 'reconnect attempt=$_retryIndex delayMs=$delayMs');
      final ok = await connect();
      if (!ok && !_disposed) _scheduleReconnect();
    });
  }

  Future<void> _teardownSocket() async {
    _rttTimer?.cancel();
    _rttTimer = null;
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _setPartnerPresent(false);
    await _teardownSocket();
    if (!_inbound.isClosed) await _inbound.close();
    _lg(
      '🧹 [DUO-RELAY]',
      'disposed sentBytes=$_sentBytes recvBytes=$_receivedBytes '
          'droppedNoPartner=$_droppedNoPartnerBytes',
    );
  }
}
