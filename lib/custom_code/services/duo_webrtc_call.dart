// ====================================================================
// 📞 [DUO-RTC] 직접 대화 통화 — WebRTC P2P (실패 시 TURN)
// --------------------------------------------------------------------
// `DuoPcmRelayClient`가 하던 일을 대신한다. 다른 점은 하나뿐이다.
//
//   옛 경로:  마이크 PCM → 우리 WebSocket → Cloud Run → 상대 → AudioTrack
//   새 경로:  마이크 → WebRTC → (P2P | TURN) → 상대 WebRTC → 상대 스피커
//
// 그래서 이 클래스에는 **`sendPcm`이 없다.** 오디오는 우리 Dart 코드를
// 지나가지 않는다. 조각을 세거나 지터버퍼를 돌릴 일도 없다 — WebRTC가
// 안에서 다 한다.
//
// ⚠️ 그 대가로 **마이크를 이 클래스가 따로 연다.** 기존 STT용
//   `PreparedAudioCapture`(record 패키지)와 별개의 AudioRecord다.
//   이 구조의 위험은 `kDuoWebrtcMicNote`에 적어 두었다 — 읽고 시작할 것.
//
// 🚫 **만능 통역은 이 파일을 쓰지 않는다.** 거기는 원음을 보내지 않고
//   STT → 번역 → TTS로 상대 단말이 소리를 만든다. 이 클래스를 만능 통역
//   경로에서 만들면 원음이 새어 나간다.
// ====================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'duo_ice_config.dart';
import 'duo_webrtc_signaling.dart';

/// 🎙️ **마이크가 두 개 열린다는 사실을 여기 적어 둔다.**
///
/// - STT 갈래: `record` 패키지 → `AudioRecord(AudioSource.DEFAULT, 24kHz)`
/// - 통화 갈래: flutter_webrtc → `JavaAudioDeviceModule` →
///   `AudioRecord(VOICE_COMMUNICATION, 보통 48kHz)`
///
/// 같은 앱 안에서 두 개의 AudioRecord가 동시에 열리는 구조다. 대부분의
/// 기기에서 열리지만, **하드웨어 AEC는 한쪽 세션에만 붙는다.** 삼성 일부
/// 기기에서 두 번째 open이 실패한다는 보고도 있다.
///
/// 마이크를 하나만 열고 그 조각을 두 갈래로 나누려면 flutter_webrtc의
/// `SamplesReadyCallback`을 Dart로 끌어올리는 네이티브 작업(+48k→24k
/// 리샘플링)이 필요하다. 그건 이번 범위가 아니고, 착수 전에 따로 보고한다.
///
/// **그래서 이 경로는 Remote Config 스위치 뒤에 있다.** 실기기 검증 전까지
/// 기본값은 옛 릴레이다.
const String kDuoWebrtcMicNote =
    'webrtc_opens_its_own_audiorecord_alongside_record_package';

/// 연결 수립 상한. 이 안에 못 붙으면 통화를 열지 않는다(호출부가 폴백한다).
const Duration kDuoWebrtcConnectTimeout = Duration(seconds: 20);

/// 📨 만능 통역이 글자를 실어 나르는 DataChannel 이름.
///
/// 직접 대화는 이 채널을 열지 않는다 — 거기는 소리가 곧 대화다.
const String kDuoInterpDataChannelLabel = 'duo-interp-text';

/// 통화 중 연결이 흔들릴 때 ICE restart를 걸기까지 기다리는 시간.
/// `disconnected`는 잠깐의 망 끊김에도 나므로 즉시 재협상하면 멀쩡한 통화를
/// 흔든다. 이 시간을 넘겨도 안 돌아오면 그때 다시 붙인다.
const Duration kDuoWebrtcIceRestartDelay = Duration(seconds: 4);

/// ICE restart 최대 횟수. 계속 실패하면 통화를 포기하고 호출부에 알린다.
const int kDuoWebrtcMaxIceRestarts = 3;

// ============================================================================
// 💰 [BILLING-IDLE] 상대가 말하고 있는지를 WebRTC에서 알아내는 자리
// ----------------------------------------------------------------------------
// 릴레이 경로에서는 상대 PCM이 Dart를 지나가므로 진폭을 직접 쟀다
// (`_noteInboundAudio`). WebRTC에서는 그 PCM이 앱에 오지 않는다. 그대로 두면
// **상대만 말하는 동안 호스트가 유휴로 떨어져 과금이 멈춘다** — 대화는
// 이어지는데 요금만 안 붙는다.
//
// 그래서 통계에서 상대 오디오 레벨을 주기적으로 읽어 같은 신호를 만든다.
// 바이트 수로는 못 가른다 — Opus는 침묵 구간에도 comfort noise를 보낸다.
// ============================================================================

/// 상대 오디오 레벨을 읽는 주기. 유휴 판정 창(3초)보다 촘촘해야 한다.
const Duration kDuoWebrtcStatsInterval = Duration(seconds: 1);

/// 상대가 "말하고 있다"고 볼 오디오 레벨(0.0~1.0).
///
/// 릴레이 경로의 문턱과 같은 크기다: PCM16 진폭 1200 / 32768 ≈ 0.037.
/// 두 통로의 과금 유휴 판정이 어긋나면 안 되므로 값을 맞춰 둔다.
const double kDuoWebrtcRemoteVoiceLevel = 0.037;

/// 몇 번의 통계 주기마다 건강 로그를 한 줄 남길지. 1초 주기이므로 5면 5초다.
/// 통화 내내 찍히지만 한 줄이 짧고 오디오 내용이 없다.
const int kDuoWebrtcHealthLogEveryTicks = 5;

/// 통화 한 번 = 이 객체 한 개.
class DuoWebrtcCall {
  DuoWebrtcCall({
    required this.roomId,
    required this.uid,
    required this.role,
    required this.sessionId,
    required this.isOfferer,
    this.onLog,
    this.onPartnerPresence,
    this.onFatal,
    this.onRemoteVoice,
    this.sendAudio = true,
    this.withDataChannel = false,
    this.onData,
    this.onDataChannelState,
  });

  final String roomId;
  final String uid;

  /// 'HOST' 또는 'GUEST'. 신호 컬렉션에서 내 후보와 상대 후보를 가르는 값이다.
  final String role;

  /// `'$roomId#$generation'`. stale 신호를 거르는 유일한 기준.
  final String sessionId;

  /// 호스트가 offer를 만든다.
  final bool isOfferer;

  final void Function(String tag, String msg)? onLog;

  /// **오디오가 실제로 오갈 수 있는 상태인가.** 옛 릴레이의
  /// `onPartnerPresence`와 같은 자리에 꽂히지만 뜻이 다르다 —
  /// 여기서는 PeerConnection이 connected인지를 말한다.
  ///
  /// ⚠️ 이 값은 **화면 표시와 오디오 상태 전용**이다. 통화 종료·과금·참가자
  ///   판정은 여전히 Firestore lifecycle이 한다.
  final void Function(bool present)? onPartnerPresence;

  /// 되살릴 수 없는 실패. 호출부가 통화를 접거나 폴백을 결정한다.
  final void Function(String reason)? onFatal;

  /// 💰 상대가 지금 말하고 있다. 릴레이 경로의 `_noteInboundAudio`와 **같은
  /// 뜻**이고, 같은 자리(과금 유휴 판정)에 꽂힌다.
  ///
  /// ⚠️ 이 값으로 전사를 하지 않는다. 여기 오는 것은 소리가 아니라
  ///    "소리가 났다"는 사실 하나뿐이다 — 상대 오디오는 앱에 닿지 않는다.
  final void Function()? onRemoteVoice;

  /// 🎙️ 내 목소리를 상대에게 **보낼 것인가.**
  ///
  /// 직접 대화는 true다 — 그게 통화의 전부다.
  ///
  /// 만능 통역은 false다. 통역은 원어를 들려주지 않으므로 오디오를 보낼
  /// 이유가 없고, 보내면 상대 스피커에서 원어가 그대로 난다. 마이크는 그래도
  /// 연다 — WebRTC의 AEC/NS/AGC를 태운 PCM을 [DuoWebrtcMicTap]으로 받아
  /// 전사에 쓰기 때문이다. **트랙을 만들되 PeerConnection에는 안 붙인다.**
  ///
  /// ⚠️ 붙이지 않아도 APM(AEC/NS/AGC)이 도는지는 **실기기에서 확인할 일**이다.
  ///   안 돈다면 붙이고 상대 렌더링만 끄는 쪽으로 바꿔야 한다.
  final bool sendAudio;

  /// 📨 글자를 실어 나를 DataChannel을 열 것인가.
  ///
  /// 만능 통역이 Firestore 대신 쓰는 통로다. 직접 대화는 false — 지금 동작을
  /// 한 글자도 바꾸지 않는다.
  final bool withDataChannel;

  /// DataChannel로 들어온 한 건. JSON 객체 하나가 발화 하나다.
  final void Function(Map<String, dynamic> payload)? onData;

  /// 채널이 열렸는가/닫혔는가. 호출부가 "글자를 보낼 수 있는 상태"를 안다.
  final void Function(bool open)? onDataChannelState;

  RTCPeerConnection? _pc;
  RTCDataChannel? _dataChannel;
  bool _dataChannelOpen = false;
  MediaStream? _localStream;
  MediaStreamTrack? _localAudioTrack;
  DuoWebrtcSignaling? _signaling;
  DuoIceConfig? _ice;

  Completer<bool>? _connected;
  Timer? _iceRestartTimer;
  Timer? _statsTimer;

  /// 연결 마감 시계. 호스트는 offer를 올린 뒤, 게스트는 offer를 받은 뒤 건다.
  Timer? _connectDeadline;

  /// 마지막으로 적용한 원격 서술의 열쇠(`세션|종류|SDP`).
  /// 같은 값이 또 오면 건너뛴다 — 무한 재협상 고리를 끊는 자리다.
  String? _lastAppliedRemoteKey;

  /// `audioLevel`을 안 주는 기기를 위한 폴백 근거. `totalAudioEnergy`는
  /// 단조 증가하므로 **늘어났는가**로 소리를 판단할 수 있다.
  double? _lastAudioEnergy;
  bool _statsHaveAudioSignal = false;
  int _healthTicks = 0;

  bool _disposed = false;
  bool _partnerPresent = false;
  bool _remoteDescriptionSet = false;
  bool _muted = false;
  int _iceRestarts = 0;
  DateTime? _startedAt;
  int? _connectMs;

  /// 원격 서술이 오기 전에 도착한 후보를 담아 둔다. setRemoteDescription
  /// 전에 addCandidate를 부르면 버려지기 때문이다.
  final List<RTCIceCandidate> _pendingRemoteCandidates = <RTCIceCandidate>[];

  bool get isConnected => !_disposed && _partnerPresent;
  bool get partnerPresent => _partnerPresent;

  /// TURN이 설정에 들어갔는가. 없으면 대칭 NAT에서 무음 실패한다.
  bool get hasTurn => _ice?.hasTurn ?? false;

  /// 연결까지 걸린 시간(ms). 옛 릴레이의 RTT 로그 자리를 대신한다.
  int? get connectMs => _connectMs;

  /// 🎙️ 이 통화가 연 **유일한 마이크**의 트랙 id.
  ///
  /// 전사 갈래(`DuoWebrtcMicTap`)가 이 id로 같은 트랙에 귀를 붙인다 —
  /// 마이크를 한 번만 열기 위한 고리다. 아직 안 열렸으면 null.
  String? get localAudioTrackId => _localAudioTrack?.id;

  /// 📨 글자를 지금 보낼 수 있는가.
  bool get isDataChannelOpen => !_disposed && _dataChannelOpen;

  /// 📨 발화 한 건을 상대에게 보낸다. 보냈으면 true.
  ///
  /// **실패를 삼키지 않는다.** 채널이 안 열렸으면 false를 돌려주고, 호출부가
  /// 그 사실을 로그로 남긴다 — 조용히 Firestore로 되돌아가면 어느 통로가
  /// 실제로 돌았는지 실기기에서 못 가린다.
  bool sendData(Map<String, dynamic> payload) {
    final ch = _dataChannel;
    if (_disposed || ch == null || !_dataChannelOpen) return false;
    try {
      ch.send(RTCDataChannelMessage(jsonEncode(payload)));
      return true;
    } catch (e) {
      _lg('❌ [INTERP-DATA]', 'send_failed(${e.runtimeType})');
      return false;
    }
  }

  void _lg(String tag, String msg) => onLog?.call(tag, msg);

  /// 📨 채널 하나에 콜백을 건다. 호스트가 만든 것도, 게스트가 받은 것도
  /// 여기를 지난다 — 양쪽 동작이 갈라지지 않게 한 자리로 모은다.
  void _wireDataChannel(RTCDataChannel ch, String origin) {
    _dataChannel = ch;
    ch.onDataChannelState = (RTCDataChannelState state) {
      if (_disposed) return;
      final bool open = state == RTCDataChannelState.RTCDataChannelOpen;
      if (open == _dataChannelOpen) return;
      _dataChannelOpen = open;
      _lg('[INTERP-DATA]',
          'channel_state=${open ? 'open' : 'closed'} origin=$origin');
      onDataChannelState?.call(open);
    };
    ch.onMessage = (RTCDataChannelMessage msg) {
      if (_disposed || msg.isBinary) return;
      try {
        final decoded = jsonDecode(msg.text);
        if (decoded is! Map) return;
        onData?.call(Map<String, dynamic>.from(decoded));
      } catch (e) {
        // 한 건이 깨져도 통화를 흔들지 않는다.
        _lg('❌ [INTERP-DATA]', 'decode_failed(${e.runtimeType})');
      }
    };
  }

  /// 통화를 연다. false면 호출부는 이 경로를 포기한다.
  Future<bool> connect() async {
    if (_disposed) return false;
    _startedAt = DateTime.now();

    try {
      _ice = await loadDuoIceConfig(onLog: onLog);
      if (_disposed) return false;
      if (!_ice!.hasTurn) {
        // 숨기지 않는다. P2P가 안 되는 망에서 이 한 줄이 유일한 단서다.
        _lg('⚠️ [DUO-RTC]',
            'no_turn — P2P만 가능하다. 대칭 NAT(일부 LTE·기업망)에서는 '
                '연결이 무음으로 실패한다');
      }

      // 🎧 오디오 세션의 주인을 여기서 정한다. WebRTC 경로에서는
      //    네이티브 AudioTrack(`stealthvox/realtime_pcm`)을 열지 않으므로
      //    MainActivity의 AudioManager 조작도 돌지 않는다. 즉 이 구간의
      //    주인은 flutter_webrtc 하나뿐이다.
      await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.communication);

      final pc = await createPeerConnection(_ice!.toPeerConnectionConfig());
      if (_disposed) {
        await pc.dispose();
        return false;
      }
      _pc = pc;

      // 🎙️ 마이크를 연다. **이것이 두 번째 AudioRecord다**
      //    (`kDuoWebrtcMicNote` 참고).
      //
      //    AEC/NS는 WebRTC 쪽에 맡긴다 — 여기서 끄면 스피커로 나간 상대
      //    목소리가 그대로 되돌아간다. STT 갈래의 record 설정
      //    (echoCancel:true / noiseSuppress:false)은 건드리지 않는다.
      //
      // 🩺 이 호출의 성패가 **두 번째 AudioRecord가 열렸는가**다. 실기기에서
      //    가장 먼저 봐야 하는 한 줄이라 성공·실패를 모두 남긴다.
      MediaStream stream;
      try {
        stream = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
          'audio': <String, dynamic>{
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
          },
          'video': false,
        });
      } catch (e) {
        // record 패키지가 이미 마이크를 잡고 있어 실패하는 경우가 여기다.
        _lg(
            '❌ [DUO-RTC-MIC]',
            'getUserMedia_failed(${e.runtimeType}) — WebRTC AudioRecord를 '
                '열지 못했다. STT용 record.startStream과 경합했을 수 있다');
        return false;
      }
      if (_disposed) {
        await stream.dispose();
        await pc.dispose();
        return false;
      }
      _localStream = stream;
      final tracks = stream.getAudioTracks();
      if (tracks.isEmpty) {
        _lg('❌ [DUO-RTC-MIC]',
            'no_audio_track — 스트림은 열렸는데 오디오 트랙이 없다');
        return false;
      }
      _lg(
          '🎙️ [DUO-RTC-MIC]',
          'opened tracks=${tracks.length} '
              'aec=requested ns=requested agc=requested '
              '(※ 실제 적용 여부는 플랫폼이 정하며 보고하지 않는다)');
      _localAudioTrack = tracks.first;
      // 음소거 상태로 시작하지 않는다. 호출부가 통화 중에 토글한다.
      _localAudioTrack!.enabled = !_muted;
      if (sendAudio) {
        await pc.addTrack(_localAudioTrack!, stream);
      } else {
        // 🎙️ 통역: 마이크는 열되 상대에게 보내지 않는다. 트랙은 살아 있으므로
        //   [DuoWebrtcMicTap]은 그대로 붙고, 상대 스피커에서는 원어가 안 난다.
        _lg('[INTERP-WEBRTC]',
            'mic_ready sendAudio=false — 트랙은 열고 상대에겐 보내지 않는다');
      }

      // 📨 글자 통로. 호스트가 만들고 게스트가 받는다 — offer/answer와 같은
      //   주인 규칙이라 양쪽이 서로 만들어 둘이 생기는 일이 없다.
      if (withDataChannel) {
        if (isOfferer) {
          final ch = await pc.createDataChannel(
            kDuoInterpDataChannelLabel,
            RTCDataChannelInit()
              ..ordered = true
              ..negotiated = false,
          );
          _wireDataChannel(ch, 'created');
          _lg('[INTERP-DATA]', 'channel_created label=$kDuoInterpDataChannelLabel');
        } else {
          pc.onDataChannel = (RTCDataChannel ch) {
            if (_disposed) return;
            _wireDataChannel(ch, 'received');
            _lg('[INTERP-DATA]', 'channel_received label=${ch.label ?? '-'}');
          };
        }
      }

      _wireConnectionState(pc);

      // 🆔 세션 id의 주인은 호스트다. 게스트는 `offerSessionId`를 주지 않고,
      //   문서에 적힌 값을 채택한다(`_adoptSession`).
      final signaling = DuoWebrtcSignaling(
        roomId: roomId,
        isOfferer: isOfferer,
        offerSessionId: isOfferer ? sessionId : null,
        onLog: onLog,
      );
      _signaling = signaling;

      pc.onIceCandidate = (RTCIceCandidate candidate) {
        if (_disposed) return;
        unawaited(signaling.sendCandidate(
          role: role,
          candidate: candidate.candidate,
          sdpMid: candidate.sdpMid,
          sdpMLineIndex: candidate.sdpMLineIndex,
        ));
      };

      final connected = Completer<bool>();
      _connected = connected;

      signaling.listenForDescription((sdp, type, docSession) async {
        if (_disposed) return;
        await _applyRemoteDescription(sdp, type, docSession);
      });
      // 호스트는 자기 id를 이미 알고 있으므로 후보 리스너를 곧바로 연다.
      // 게스트는 세션을 채택한 뒤에야 열 수 있다(질의 조건에 그 값이 든다).
      if (isOfferer) {
        signaling.listenForCandidates(
          myRole: role,
          onRemoteCandidate: _onRemoteCandidate,
        );
      }

      // 호스트만 신호 자리를 비우고 offer를 만든다. 게스트가 같이 지우면
      // 방금 올라온 offer를 지워 버린다.
      if (isOfferer) {
        await signaling.reset();
        if (_disposed) return false;
        final offer = await pc.createOffer(<String, dynamic>{
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': false,
        });
        await pc.setLocalDescription(offer);
        await signaling.sendOffer(offer.sdp ?? '', offer.type ?? 'offer', uid);
        _lg('📞 [DUO-RTC]', 'offer_sent room=$roomId session=$sessionId');
        // 호스트는 offer를 올린 순간부터 시계를 잰다.
        _startConnectDeadline('offer_sent');
      } else {
        // ⏳ **게스트는 여기서 시계를 재지 않는다.**
        //
        //   offer가 언제 올지는 호스트 사정이다. 게스트가 먼저 들어와 있는
        //   것은 정상이고(입장하자마자 시작하니 오히려 흔하다), 그때 20초를
        //   세면 호스트가 시작하기도 전에 포기한다 — 2026-09-02 실측에서
        //   게스트가 호스트보다 24초 먼저 시작해 4초 차이로 offer를 놓쳤다.
        //
        //   기다림을 끝내는 것은 시계가 아니라 방이다. 방이 끝나거나 상대가
        //   나가면 호출부가 `dispose()`를 부르고, 그때 이 대기가 풀린다.
        _lg('📞 [DUO-RTC]',
            'awaiting_offer room=$roomId (시계 없음 — offer 도착부터 잰다)');
      }

      final ok = await connected.future;
      if (!ok) {
        // 못 붙었을 때야말로 후보 상태가 필요하다. 성공 경로에만 로그를 두면
        // 정작 원인을 찾아야 할 때 아무것도 안 남는다.
        await _dumpIceFailure();
        return false;
      }

      _connectMs = _startedAt == null
          ? null
          : DateTime.now().difference(_startedAt!).inMilliseconds;
      _lg(
          '✅ [DUO-RTC]',
          'connected room=$roomId role=$role connectMs=$_connectMs '
              '${_ice?.describe() ?? ''}');
      return true;
    } catch (e) {
      _lg('❌ [DUO-RTC]', 'connect_failed(${e.runtimeType})');
      return false;
    }
  }

  void _wireConnectionState(RTCPeerConnection pc) {
    pc.onConnectionState = (RTCPeerConnectionState state) {
      if (_disposed) return;
      _lg('🔌 [DUO-RTC]', 'connectionState=${state.name}');
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _cancelIceRestart();
          _iceRestarts = 0;
          // 붙었으니 마감 시계는 더 필요 없다.
          _connectDeadline?.cancel();
          _connectDeadline = null;
          _startRemoteVoiceProbe();
          _setPartnerPresent(true);
          final c = _connected;
          _connected = null;
          if (c != null && !c.isCompleted) c.complete(true);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          // 잠깐의 망 끊김일 수 있다. 바로 흔들지 않고 기다린다.
          _setPartnerPresent(false);
          _scheduleIceRestart('disconnected');
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _setPartnerPresent(false);
          _scheduleIceRestart('failed');
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _setPartnerPresent(false);
          break;
        default:
          break;
      }
    };

    pc.onIceConnectionState = (RTCIceConnectionState state) {
      if (_disposed) return;
      _lg('🧊 [DUO-RTC]', 'iceState=${state.name}');
    };
  }

  /// ⏱️ 연결 마감 시계를 건다. **한 번만 건다.**
  ///
  /// 호스트는 offer를 올린 순간부터, 게스트는 offer를 받은 순간부터 잰다.
  /// 게스트가 `connect()` 호출 시점부터 재면 호스트가 시작하기도 전에
  /// 포기한다(2026-09-02 실측: 24초 차이로 놓쳤다).
  void _startConnectDeadline(String reason) {
    if (_connectDeadline != null || _disposed) return;
    _connectDeadline = Timer(kDuoWebrtcConnectTimeout, () {
      if (_disposed || _partnerPresent) return;
      _lg(
          '❌ [DUO-RTC]',
          'connect_timeout after=${kDuoWebrtcConnectTimeout.inSeconds}s '
              'from=$reason turn=${_ice?.hasTurn}');
      final c = _connected;
      _connected = null;
      if (c != null && !c.isCompleted) c.complete(false);
    });
  }

  void _onRemoteCandidate(String candidate, String? sdpMid, int? sdpMLineIndex) {
    if (_disposed) return;
    _addRemoteCandidate(RTCIceCandidate(candidate, sdpMid, sdpMLineIndex));
  }

  /// 원격 서술 하나를 적용한다.
  ///
  /// 🔁 **같은 신호를 두 번 적용하지 않는다.** Firestore 문서 리스너는 같은
  ///   내용을 여러 번 준다 — 내가 answer를 같은 문서에 쓰면 스냅샷이 다시
  ///   떨어지고 거기에 offer가 그대로 들어 있기 때문이다. 막지 않으면
  ///   offer 재적용 → answer 재생성 → 쓰기 → 스냅샷 → … 무한 고리가 된다
  ///   (2026-09-02 실측: 23초 통화에 answer 1,247회).
  ///
  ///   판단 기준은 **세션·종류·SDP 셋 다**이다(`duoRemoteSdpKey`). 역할별
  ///   예외(`type == 'answer'`일 때만 막기)는 쓰지 않는다 — 그건 offerer만
  ///   지켜 주고 answerer는 그대로 두는 반쪽짜리였다. 셋을 함께 보므로
  ///   ICE restart처럼 **정말 달라진** SDP는 그대로 통과한다.
  Future<void> _applyRemoteDescription(
      String sdp, String type, String docSession) async {
    final pc = _pc;
    if (pc == null || _disposed) return;

    final key = duoRemoteSdpKey(sessionId: docSession, type: type, sdp: sdp);
    if (_lastAppliedRemoteKey == key) return; // 같은 신호 — 조용히 넘어간다

    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
      _lastAppliedRemoteKey = key;
      _remoteDescriptionSet = true;
      _lg('📮 [DUO-RTC]', 'remote_description_set type=$type');
      // 게스트는 offer를 받은 이 순간부터 시계를 잰다.
      if (!isOfferer && type == 'offer') {
        _startConnectDeadline('offer_received');
        // 세션을 채택했으니 이제 상대 후보를 받을 수 있다.
        _signaling?.listenForCandidates(
          myRole: role,
          onRemoteCandidate: _onRemoteCandidate,
        );
      }

      // 기다리던 후보를 이제 붓는다.
      final pending = List<RTCIceCandidate>.of(_pendingRemoteCandidates);
      _pendingRemoteCandidates.clear();
      for (final candidate in pending) {
        try {
          await pc.addCandidate(candidate);
        } catch (_) {}
      }

      // offer를 받았으면 answer를 만들어 돌려준다.
      if (!isOfferer && type == 'offer') {
        final answer = await pc.createAnswer(<String, dynamic>{
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': false,
        });
        await pc.setLocalDescription(answer);
        await _signaling?.sendAnswer(
            answer.sdp ?? '', answer.type ?? 'answer', uid);
        _lg('📞 [DUO-RTC]', 'answer_sent');
      }
    } catch (e) {
      _lg('❌ [DUO-RTC]', 'set_remote_failed(${e.runtimeType}) type=$type');
    }
  }

  void _addRemoteCandidate(RTCIceCandidate candidate) {
    final pc = _pc;
    if (pc == null) return;
    if (!_remoteDescriptionSet) {
      _pendingRemoteCandidates.add(candidate);
      return;
    }
    unawaited(pc.addCandidate(candidate).catchError((Object e) {
      _lg('⚠️ [DUO-RTC]', 'add_candidate_failed(${e.runtimeType})');
    }));
  }

  void _scheduleIceRestart(String reason) {
    if (_disposed || !isOfferer) {
      // 재협상은 offerer(호스트)만 건다. 둘이 동시에 걸면 신호가 엉킨다.
      return;
    }
    if (_iceRestarts >= kDuoWebrtcMaxIceRestarts) {
      _lg('❌ [DUO-RTC]', 'ice_restart_exhausted attempts=$_iceRestarts');
      onFatal?.call('ice_restart_exhausted');
      return;
    }
    _iceRestartTimer?.cancel();
    _iceRestartTimer = Timer(kDuoWebrtcIceRestartDelay, () async {
      if (_disposed || _partnerPresent) return;
      final pc = _pc;
      if (pc == null) return;
      _iceRestarts++;
      _lg('🔁 [DUO-RTC]',
          'ice_restart attempt=$_iceRestarts reason=$reason');
      try {
        final offer = await pc.createOffer(<String, dynamic>{
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': false,
          'iceRestart': true,
        });
        await pc.setLocalDescription(offer);
        _remoteDescriptionSet = false;
        // 재협상이므로 상대의 새 answer를 받아야 한다. 이전 열쇠를 놓지 않으면
        // 새 answer가 "같은 신호"로 보여 적용되지 않는다.
        _lastAppliedRemoteKey = null;
        await _signaling?.sendOffer(
            offer.sdp ?? '', offer.type ?? 'offer', uid);
      } catch (e) {
        _lg('❌ [DUO-RTC]', 'ice_restart_failed(${e.runtimeType})');
      }
    });
  }

  void _cancelIceRestart() {
    _iceRestartTimer?.cancel();
    _iceRestartTimer = null;
  }

  /// 💰 [BILLING-IDLE] 상대 오디오 레벨을 주기적으로 읽는다.
  ///
  /// 릴레이 경로가 상대 PCM 진폭으로 하던 일을 통계로 대신한다. 이게 없으면
  /// **상대만 말하는 동안 호스트가 유휴로 떨어져 과금이 멈춘다.**
  void _startRemoteVoiceProbe() {
    if (_statsTimer != null) return;
    _statsTimer = Timer.periodic(kDuoWebrtcStatsInterval, (_) async {
      if (_disposed) return;
      final pc = _pc;
      if (pc == null) return;
      try {
        final reports = await pc.getStats();
        if (_disposed) return;
        if (_readRemoteVoice(reports)) onRemoteVoice?.call();
        _logAudioHealth(reports);
      } catch (_) {
        // 통계 한 번 실패로 통화를 흔들지 않는다.
      }
    });
  }

  /// 🩺 [DUO-RTC-HEALTH] 통화 쪽 마이크와 스피커가 살아 있는가.
  ///
  /// STT 쪽 계측(`DuoMicLiveMeter`)과 **나란히 놓고 읽으라고** 만든 줄이다.
  /// 두 AudioRecord가 경합하면 보통 한쪽만 죽는데, 두 줄을 견주면 어느 쪽이
  /// 죽었는지 바로 갈린다.
  ///
  ///   outLevel 살아 있고 micHealth 무음 → **STT 마이크가 졌다**
  ///   outLevel 0이고  micHealth 정상   → **통화 마이크가 졌다**
  ///   둘 다 정상                        → 공존 성공
  ///
  /// `path`는 P2P로 붙었는지 TURN을 거치는지다(host/srflx/prflx = P2P,
  /// relay = TURN). TURN 요금과 지연의 근거가 이 값이다.
  void _logAudioHealth(List<StatsReport> reports) {
    _healthTicks++;
    // 첫 주기는 곧바로 남긴다. 붙자마자 P2P인지 TURN인지 알아야 하고,
    // 5초를 기다리면 짧은 통화에서는 한 줄도 안 남는다.
    if (_healthTicks != 1 &&
        _healthTicks % kDuoWebrtcHealthLogEveryTicks != 0) {
      return;
    }

    double? outLevel;
    double? inLevel;
    num? packetsSent;
    num? packetsReceived;

    for (final report in reports) {
      final values = report.values;
      final kind = values['kind'] ?? values['mediaType'];

      if (report.type == 'media-source' && kind == 'audio') {
        final v = values['audioLevel'];
        if (v is num) outLevel = v.toDouble();
      }
      if (report.type == 'outbound-rtp' && kind != 'video') {
        final v = values['packetsSent'];
        if (v is num) packetsSent = v;
      }
      if (report.type == 'inbound-rtp' && kind != 'video') {
        final v = values['audioLevel'];
        if (v is num) inLevel = v.toDouble();
        final p = values['packetsReceived'];
        if (p is num) packetsReceived = p;
      }
    }

    _lg(
        '🩺 [DUO-RTC-HEALTH]',
        'role=$role path=${_resolveIcePath(reports)} '
            'outLevel=${outLevel?.toStringAsFixed(3) ?? 'n/a'} '
            'inLevel=${inLevel?.toStringAsFixed(3) ?? 'n/a'} '
            'pktSent=${packetsSent ?? 'n/a'} pktRecv=${packetsReceived ?? 'n/a'}'
            '${outLevel != null && outLevel == 0 ? ' ⚠️ 통화 마이크 무음' : ''}');
  }

  /// ❌ 연결 실패의 근거를 남긴다. 후보를 몇 개나 모았고 어떤 종류였는지가
  /// "STUN이 안 먹었나 / 상대가 신호를 못 받았나 / TURN이 필요한가"를 가른다.
  ///
  /// 후보 문자열 자체(IP가 들어 있다)는 남기지 않는다 — 종류와 개수만 센다.
  Future<void> _dumpIceFailure() async {
    final pc = _pc;
    if (pc == null) return;
    try {
      final reports = await pc.getStats();
      final localTypes = <String, int>{};
      final remoteTypes = <String, int>{};
      int pairs = 0;
      for (final report in reports) {
        final t = report.values['candidateType'];
        if (report.type == 'local-candidate' && t is String) {
          localTypes[t] = (localTypes[t] ?? 0) + 1;
        }
        if (report.type == 'remote-candidate' && t is String) {
          remoteTypes[t] = (remoteTypes[t] ?? 0) + 1;
        }
        if (report.type == 'candidate-pair') pairs++;
      }
      _lg(
          '❌ [DUO-RTC-ICE]',
          'failed role=$role localCandidates=$localTypes '
              'remoteCandidates=$remoteTypes pairs=$pairs '
              'turn=${_ice?.hasTurn} '
              '${remoteTypes.isEmpty ? '→ 상대 후보가 0개다. signaling을 의심하라' : ''}'
              '${localTypes.isNotEmpty && localTypes['srflx'] == null ? ' → srflx 없음: STUN이 막혔다' : ''}');
    } catch (_) {
      _lg('❌ [DUO-RTC-ICE]', 'failed role=$role (통계도 못 읽었다)');
    }
  }

  String _resolveIcePath(List<StatsReport> reports) =>
      resolveDuoIcePath(reports);

  /// 통계 묶음에서 "상대가 지금 말하고 있다"를 읽어 낸다.
  ///
  /// 표준이 기기마다 조금씩 다르므로 두 근거를 차례로 본다.
  ///   ① `audioLevel` (0.0~1.0) — 있으면 이것이 가장 곧다
  ///   ② `totalAudioEnergy` — 단조 증가값. 늘었으면 소리가 났다
  ///
  /// **보낸 쪽(outbound/media-source) 통계는 보지 않는다.** 내 목소리로
  /// 상대가 말하는 중이라고 판정하면 유휴가 영영 서지 않는다.
  bool _readRemoteVoice(List<StatsReport> reports) {
    double? level;
    double? energy;
    for (final report in reports) {
      // 받는 쪽만 본다. 'inbound-rtp'가 표준이고, 옛 구현은 'track'에
      // `remoteSource: true`로 실어 보낸다.
      final bool inbound = report.type == 'inbound-rtp' ||
          (report.type == 'track' && report.values['remoteSource'] == true);
      if (!inbound) continue;
      final kind = report.values['kind'] ?? report.values['mediaType'];
      if (kind != null && kind != 'audio') continue;

      final rawLevel = report.values['audioLevel'];
      if (rawLevel is num) {
        level = level == null
            ? rawLevel.toDouble()
            : (rawLevel > level ? rawLevel.toDouble() : level);
      }
      final rawEnergy = report.values['totalAudioEnergy'];
      if (rawEnergy is num) {
        energy = (energy ?? 0) + rawEnergy.toDouble();
      }
    }

    if (level != null) {
      _statsHaveAudioSignal = true;
      return level >= kDuoWebrtcRemoteVoiceLevel;
    }
    if (energy != null) {
      _statsHaveAudioSignal = true;
      final previous = _lastAudioEnergy;
      _lastAudioEnergy = energy;
      // 에너지는 침묵이면 거의 그대로다. 의미 있게 늘었을 때만 소리로 본다.
      if (previous != null && energy - previous > 0.0005) return true;
      return false;
    }

    // 어느 근거도 없는 기기. 한 번만 알리고, 이후로는 조용히 넘어간다.
    if (!_statsHaveAudioSignal) {
      _statsHaveAudioSignal = true;
      _lg('⚠️ [DUO-RTC]',
          'no_remote_audio_level_stat — 상대 발화만으로는 과금 유휴가 '
              '풀리지 않는다(내 발화·통역 단계는 그대로 잡는다)');
    }
    return false;
  }

  void _setPartnerPresent(bool present) {
    if (_partnerPresent == present) return;
    _partnerPresent = present;
    _lg('👥 [DUO-RTC]', 'audioConnected=$present');
    onPartnerPresence?.call(present);
  }

  /// 🔇 음소거 = **내 소리를 안 보내는 것.** 옛 경로에서는 팬아웃이 조각을
  /// 버려서 이뤘지만, WebRTC는 오디오가 Dart를 지나지 않으므로 트랙을 끈다.
  ///
  /// ⚠️ 전사 갈래는 여기서 막지 않는다 — 그건 위젯의 팬아웃이 계속 맡는다.
  ///   (음소거 중에 한 말이 History에 남으면 안 된다는 규칙은 그대로다)
  void setMuted(bool muted) {
    _muted = muted;
    final track = _localAudioTrack;
    if (track == null) return;
    track.enabled = !muted;
    _lg('🔇 [DUO-RTC]', 'micTrackEnabled=${!muted}');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final ch = _dataChannel;
    _dataChannel = null;
    _dataChannelOpen = false;
    if (ch != null) {
      try {
        await ch.close();
      } catch (_) {
        // 닫다 실패해도 통화 정리는 계속한다.
      }
    }
    _cancelIceRestart();
    _statsTimer?.cancel();
    _statsTimer = null;
    // ⏳ 마감 시계도 여기서 끈다. 게스트가 offer를 기다리는 중에 방이 끝나면
    //   이 dispose가 유일한 탈출구다(아래에서 `_connected`를 false로 닫는다).
    _connectDeadline?.cancel();
    _connectDeadline = null;
    _setPartnerPresent(false);

    final c = _connected;
    _connected = null;
    if (c != null && !c.isCompleted) c.complete(false);

    await _signaling?.dispose();
    _signaling = null;

    final track = _localAudioTrack;
    _localAudioTrack = null;
    if (track != null) {
      try {
        await track.stop();
      } catch (_) {}
    }

    final stream = _localStream;
    _localStream = null;
    if (stream != null) {
      try {
        await stream.dispose();
      } catch (_) {}
    }

    final pc = _pc;
    _pc = null;
    if (pc != null) {
      try {
        await pc.close();
      } catch (_) {}
      try {
        await pc.dispose();
      } catch (_) {}
    }

    // 🎧 오디오 세션을 되돌린다. 이걸 빠뜨리면 통화가 끝나도 기기가
    //   통화 모드에 남아 다른 소리가 수화부로 나간다.
    try {
      await Helper.clearAndroidCommunicationDevice();
    } catch (_) {}
    try {
      await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.media);
    } catch (_) {}

    _lg('🧹 [DUO-RTC]',
        'disposed connectMs=$_connectMs iceRestarts=$_iceRestarts');
  }
}

/// 🛣️ 지금 소리가 **어느 길로** 가고 있는가.
///
/// TURN을 안 붙인 단계에서는 이 값이 반드시 `P2P(...)`여야 한다.
/// `TURN(relay ...)`가 나오면 설정이 어긋난 것이고, `not-selected-yet`이면
/// 아직 후보쌍을 안 골랐다는 뜻이다 — 셋을 구분해야 원인을 찾는다.
///
/// ⚠️ 표준 `RTCIceCandidatePairStats`에는 후보 **종류**가 없다.
///   `localCandidateId`/`remoteCandidateId`로 후보 보고서를 가리킬 뿐이다.
///   그래서 먼저 후보 보고서에서 id→종류 표를 만들고 그걸로 푼다. 일부
///   구현이 종류를 쌍에 직접 실어 보내므로 그 값도 폴백으로 본다.
///
/// 클래스 밖에 둔 이유는 하나다 — **실기기 없이 시험할 수 있어야 해서다.**
/// 이 함수가 틀리면 P2P인지 TURN인지 로그가 거짓말을 하고, 그 거짓말은
/// 실기기에서 눈으로 못 잡는다.
String resolveDuoIcePath(List<StatsReport> reports) {
  final types = <String, String>{};
    StatsReport? selectedPair;
    StatsReport? nominatedPair;
    StatsReport? anySucceeded;
    String? selectedPairId;

    for (final report in reports) {
      final values = report.values;
      switch (report.type) {
        case 'local-candidate':
        case 'remote-candidate':
        case 'localcandidate':
        case 'remotecandidate':
          final t = values['candidateType'];
          if (t is String) types[report.id] = t;
          break;
        case 'transport':
          final id = values['selectedCandidatePairId'];
          if (id is String && id.isNotEmpty) selectedPairId = id;
          break;
        case 'candidate-pair':
          if (values['selected'] == true) selectedPair ??= report;
          if (values['nominated'] == true && values['state'] == 'succeeded') {
            nominatedPair ??= report;
          }
          if (values['state'] == 'succeeded') anySucceeded ??= report;
          break;
      }
    }

    // transport가 가리키는 쌍이 가장 믿을 만하다. 없으면 nominated, 그다음
    // 아무 succeeded. 셋 다 없으면 아직 안 골랐다는 뜻이다.
    if (selectedPairId != null) {
      for (final report in reports) {
        if (report.type == 'candidate-pair' && report.id == selectedPairId) {
          selectedPair = report;
          break;
        }
      }
    }
    final pair = selectedPair ?? nominatedPair ?? anySucceeded;
    if (pair == null) return 'not-selected-yet';

    String typeOf(String idKey, String directKey) {
      final direct = pair.values[directKey];
      if (direct is String && direct.isNotEmpty) return direct;
      final id = pair.values[idKey];
      if (id is String) return types[id] ?? '?';
      return '?';
    }

    final local = typeOf('localCandidateId', 'localCandidateType');
    final remote = typeOf('remoteCandidateId', 'remoteCandidateType');
    // 어느 한쪽이라도 relay면 그 구간은 TURN을 지난다.
    final bool viaTurn = local == 'relay' || remote == 'relay';
  return viaTurn ? 'TURN(relay $local/$remote)' : 'P2P($local/$remote)';
}
