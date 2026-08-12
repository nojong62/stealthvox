// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom widgets
import '/custom_code/actions/index.dart'; // Imports custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom widget code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'index.dart'; // Imports other custom widgets

import 'dart:ui';
import 'dart:ui' as ui;
import '/auth/firebase_auth/auth_util.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '/custom_code/actions/billing_ticker.dart';
import '/custom_code/services/duo_direct_audio.dart';
import '/custom_code/services/duo_pcm_relay_client.dart';
import '/custom_code/services/openai_streaming_transcribe_session.dart';
import 'first_turn_realtime_voice.dart';
// 마이크 캡처는 Circle Talk과 **같은 구현 한 벌**을 쓴다. 복제하면 sample rate ·
// 권한 · 종료 처리가 두 군데로 갈라진다.
import 'routine_mode_anyone.dart' show AnyonePreparedAudioCapture;

// ============================================================================
// 🗣️ [DUO-MODE] Duo는 두 가지 방식으로 갈린다.
//   direct      — 사람 목소리 그대로 오가는 통화. AI가 끼지 않는다.
//                 마이크 PCM을 릴레이로 보내고, 같은 PCM을 전사에도 흘려
//                 History용 텍스트만 뒤에서 만든다.
//   interpreter — 기존 Duo. PTT로 말하면 STT→번역→TTS로 상대에게 들려준다.
//
// 저장 id는 이 두 문자열이다. 표시명이 바뀌어도 여기는 바꾸지 않는다.
// ============================================================================
const String kDuoModeDirect = 'direct';
const String kDuoModeInterpreter = 'interpreter';

class RoutineModeDuo extends StatefulWidget {
  const RoutineModeDuo({
    Key? key,
    this.width,
    this.height,
    this.roomId,
  }) : super(key: key);
  final double? width;
  final double? height;
  final String? roomId;

  @override
  _RoutineModeDuoState createState() => _RoutineModeDuoState();
}

class _RoutineModeDuoState extends State<RoutineModeDuo>
    with WidgetsBindingObserver {
  // ============================================================================
  // 📦 [1. 상태 변수 (STATE VARIABLES)]
  // 앱의 전반적인 상태, UI 설정, 데이터 보관용 변수 모음
  // ============================================================================
  String _openAiKey = "";
  bool _isConversationActive = false;

  // ── 🆕 [직접 대화] 모드 상태 ─────────────────────────────────────────────
  // 기본값은 기존 동작(만능 통역)이다. 게스트가 입장 팝업에서 고른 값이
  // duo_sessions 문서에 실리고, 호스트는 세션 리스너로 같은 값을 받는다.
  String _duoMode = kDuoModeInterpreter;
  bool get _isDirectMode => _duoMode == kDuoModeDirect;

  /// 게스트가 입장 팝업에서 초대 방식을 읽어오는 중인지.
  bool _pendingModeLoading = false;

  /// 세션 문서의 `mode`를 표준화한다. 값이 없거나 모르는 값이면 기존 Duo 동작인
  /// 만능 통역으로 떨어진다 — mode 필드가 없던 시절 세션과의 호환이다.
  static String _normalizeDuoMode(Object? raw) =>
      raw?.toString().trim() == kDuoModeDirect
          ? kDuoModeDirect
          : kDuoModeInterpreter;

  // 릴레이 접속 정보 (Remote Config → 없으면 --dart-define)
  String _relayUrl = kDuoRelayUrlFromEnv;
  String _relayToken = kDuoRelayTokenFromEnv;

  // 직접 대화 한 통화의 부속들. 통화가 끝나면 전부 버리고 새로 만든다.
  DuoPcmRelayClient? _relayClient;
  StreamSubscription<Uint8List>? _relayInboundSub;
  DuoPcmJitterPlayer? _jitterPlayer;
  AnyonePreparedAudioCapture? _directCapture;
  StreamSubscription<Uint8List>? _directCaptureSub;
  OpenAiStreamingTranscribeSession? _directStt;

  /// 통화 세대값. 방을 나가거나 재입장하면 올라가고, 이전 세대의 늦은
  /// 콜백(전사 완료·릴레이 프레임)은 전부 무시된다.
  int _directGeneration = 0;
  bool _directCallActive = false;
  bool _relayConnected = false;
  bool _partnerRelayConnected = false;
  bool _micActive = false;
  bool _sttActive = false;
  bool _directStarting = false;
  DateTime? _directCaptureFirstFrameAt;

  /// 화자별 발화 일련번호와 발화 시작 시각. History 순서 복원용이다.
  int _directSeq = 0;
  DateTime? _directSpeechStartedAt;

  /// History에 실제로 쓴 메시지 수. 직접 대화는 말풍선을 만들지 않으므로
  /// `_localMessages`로 저장 여부를 판단하면 히스토리가 통째로 지워진다.
  int _historyMessageCount = 0;

  // 🆕 [게스트 언어 오버레이] 초대 게스트(회원·비회원)가 입장 전 언어쌍 선택
  bool _showLangOverlay = false;
  String? _pendingJoinRoomId;

  // 🆕 [PTT] Duo 무전기 상태기계
  // idle: 대기 / recording: 녹음 중 / finishing: 마이크 종료 표시 /
  // processing: STT·번역 중 / playing: TTS 재생 중 / cooldown: 재생 후 짧은 잠금
  String _duoState = 'idle';
  // 🆕 [과금정책] 게스트 입장 후에만 과금 시작 (호스트 대기 중 정지)
  bool _billingStarted = false;
  void _startDuoBilling() {
    // 🆕 [과금정책] 게스트(회원·비회원 무관)는 차감 안 함 — 초대한 호스트만 과금
    if (!_amIHost) return;
    BillingTicker.instance.setSessionIdentifiers(
      sessionDocId: _myHistoryRef?.id,
      roomId: _duoSessionRef?.id ?? widget.roomId,
    );
    BillingTicker.instance.setRate(BillingRate.full);
    BillingTicker.instance.start();
    if (!_billingStarted) {
      _billingStarted = true;
      BillingTicker.instance.logMode('duo');
    }
    if (BillingTicker.instance.isPaused) {
      BillingTicker.instance.resume();
    }
  }

  void _stopDuoBilling() {
    if (!_amIHost) return;
    _billingStarted = false;
    BillingTicker.instance.pause();
  }

  // 🆕 [PTT 에코 차단] 최근 앱이 생성/표시한 문장 보관 (target/original 혼합, 최대 10개)
  final List<String> _recentGenerated = [];
  DateTime? _lastTtsEndAt; // 🆕 마지막 TTS 종료 시각(엄격 필터 윈도우용)

  String _normForEcho(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\w가-힣]'), '');

  void _rememberGenerated(String s) {
    final t = s.trim();
    if (t.isEmpty) return;
    _recentGenerated.add(t);
    while (_recentGenerated.length > 10) _recentGenerated.removeAt(0);
  }

  // 토큰 자카드 유사도 (0~1)
  double _jaccard(String a, String b) {
    final sa = a
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toSet();
    final sb = b
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toSet();
    if (sa.isEmpty || sb.isEmpty) return 0.0;
    final inter = sa.intersection(sb).length;
    final uni = sa.union(sb).length;
    return uni == 0 ? 0.0 : inter / uni;
  }

  bool _looksLikeEcho(String transcript) {
    final t = transcript.trim();
    if (t.length < 4) return false;
    final tn = _normForEcho(t);

    // TTS 종료 직후 1.2초는 엄격 모드(임계값 완화 → 더 잘 버림)
    final bool strict = _lastTtsEndAt != null &&
        DateTime.now().difference(_lastTtsEndAt!).inMilliseconds < 1200;
    final double simThreshold = strict ? 0.6 : 0.8;

    for (final g in _recentGenerated) {
      if (g.isEmpty) continue;
      final gn = _normForEcho(g);
      if (gn.isEmpty) continue;
      // ① 정규화 포함 관계
      if (gn == tn || gn.contains(tn) || tn.contains(gn)) return true;
      // ② 토큰 자카드 유사도
      if (_jaccard(g, t) >= simThreshold) return true;
    }
    return false;
  }

  void _setDuoState(String s) {
    if (!mounted) return;
    setState(() => _duoState = s);
  }

  bool _isPartnerOnline = false;
  bool _isExiting = false;
  int _turnCounter = 0;
  int _duoConversationTurnCounter = 0;
  double _fontScale = 1.0;
  bool _showOriginal = true;

  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _localMessages = [];
  final Map<int, GlobalKey> _itemKeys = {}; // 상단 고정 렌더링을 위한 추적기
  DateTime? _lastScrollThrottle; // 스크롤 throttle 타임스탬프 (Roleplay 이식)

  DocumentReference? _myHistoryRef;
  DocumentReference? _duoSessionRef;
  StreamSubscription? _partnerJoinedSubscription;

  // ── 🆕 [양방향 통역] 역할/메시지 채널 상태 ────────────────────────────────
  // _amIHost: 이 방에서 내가 호스트인지.
  //
  // **세션 진입 경로 하나로만 정해진다.**
  //   · 초대 링크(roomId)를 타고 들어옴 → 게스트  (initState / _joinAsGuest)
  //   · 그 외(스텔스룸 메뉴로 직접 진입) → 호스트 (아래 기본값)
  // UI 액션으로는 절대 바뀌지 않는다. 이 값이 senderRole · 릴레이 hello의
  // role · 과금 대상 판정을 모두 좌우하므로, 여기가 흔들리면 세 곳이 같이 어긋난다.
  bool _amIHost = true;
  // _myUid: 메시지 발신자 식별용 (호스트=firebase uid, 게스트=합류 시 부여된 uid)
  String _myUid = '';
  // 내 역할 문자열 ('HOST' 또는 'GUEST') — 발신/필터 기준
  String get _myRole => _amIHost ? 'HOST' : 'GUEST';
  // 공유 메시지 채널(duo_sessions/{roomId}/messages) 구독
  StreamSubscription? _messageSubscription;
  // 이미 처리한 메시지 doc id (중복 렌더 방지)
  final Set<String> _processedMsgIds = {};
  // 리스너 첫 스냅샷 priming 여부 (기존 메시지 replay 방지)
  bool _messagesPrimed = false;
  // 상대 메시지 처리 큐 (순차 처리 — 음성 겹침 방지)
  final List<Map<String, dynamic>> _incomingQueue = [];
  bool _isDrainingIncoming = false;
  // 오디오 재생 직렬화 체인 (내 음성 ↔ 상대 음성 동시재생 방지)
  Future<void> _audioChain = Future.value();
  FirstTurnRealtimeVoice? _prewarmedDuoRealtime;
  FirstTurnRealtimeVoice? _activeDuoRealtime;
  int _duoRealtimeGeneration = 0;
  // ──────────────────────────────────────────────────────────────────────────

  // ============================================================================
  // 📦 [2. 오디오 컨트롤러 (AUDIO CONTROLLERS)]
  // 녹음, 재생, 타이머 관리를 위한 오디오 변수 모음
  // ============================================================================
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _ttsPlayer = AudioPlayer();

  Timer? _silenceTimer;
  int _silenceCounter = 0;
  bool _hasSpoken = false;
  bool _isTtsActive = false;
  Completer<void>? _ttsCompleter;

  // ── 🆕 [양방향 통역] 언어쌍/보이스 헬퍼 (로비 값 매번 참조) ────────────────
  String _myTarget() =>
      FFAppState().targetLang.isNotEmpty ? FFAppState().targetLang : 'English';
  String _myNative() =>
      FFAppState().nativeLang.isNotEmpty ? FFAppState().nativeLang : 'Korean';
  String _myVoice() =>
      FFAppState().aiVoice.isNotEmpty ? FFAppState().aiVoice : 'echo';

  FirstTurnRealtimeVoice _createDuoRealtime(String voice) {
    late final FirstTurnRealtimeVoice session;
    session = FirstTurnRealtimeVoice(
      apiKey: _openAiKey,
      voice: voice,
      enableStreamingPlayback: true,
      onStreamingAudioStart: () {
        if (!mounted ||
            _isExiting ||
            !identical(_activeDuoRealtime, session)) {
          return;
        }
        _setDuoState('playing');
        BillingTicker.instance.resumeFromActivity('duo_realtime_audio_start');
      },
      onLog: (tag, message) =>
          debugPrint('[Duo][Realtime] $tag $message'),
    );
    return session;
  }

  void _prewarmDuoRealtime(String voice) {
    if (_openAiKey.isEmpty || _isExiting) return;
    final existing = _prewarmedDuoRealtime;
    if (existing != null && existing.voice == voice) return;
    existing?.cancel();
    final session = _createDuoRealtime(voice);
    _prewarmedDuoRealtime = session;
    debugPrint('[Duo][Realtime] prewarm voice=$voice');
    unawaited(session.prewarm());
  }

  FirstTurnRealtimeVoice? _takePrewarmedDuoRealtime(String voice) {
    final session = _prewarmedDuoRealtime;
    _prewarmedDuoRealtime = null;
    if (session == null) return null;
    if (session.voice != voice) {
      session.cancel();
      return null;
    }
    return session;
  }

  void _cancelDuoRealtime() {
    ++_duoRealtimeGeneration;
    _prewarmedDuoRealtime?.cancel();
    _prewarmedDuoRealtime = null;
    _activeDuoRealtime?.cancel();
    _activeDuoRealtime = null;
  }
  // ──────────────────────────────────────────────────────────────────────────

  // ============================================================================
  // 📦 [3. 라이프사이클 (LIFECYCLE)]
  // 위젯의 시작(initState)과 끝(dispose) 및 초기 설정
  // ============================================================================
  @override
  void initState() {
    super.initState();
    // 잔여시간 소진 시 StealthRoom이 이 경로로 방을 닫는다(호스트만 해당 —
    // 게스트는 과금 대상이 아니라 소진 신호 자체가 뜨지 않는다).
    StealthRoomMaster.saveAndExitCurrentMode = _handleAutoSaveAndExit;
    WidgetsBinding.instance.addObserver(this);
    _fetchKeys();
    _audioPlayer.setVolume(1.0);
    _ttsPlayer.setVolume(1.0);

    // 🆕 발신자 식별용 uid 확보 (게스트는 _joinAsGuest에서 덮어씀)
    _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // 🆕 [과금정책] Duo는 게스트 입장 시점에 과금 시작 — 진입 시엔 rate만 설정하고 pause 유지
    BillingTicker.instance.setSessionIdentifiers();
    BillingTicker.instance.setRate(BillingRate.full);
    _stopDuoBilling();
    _billingStarted = false;

    // 🔒 [역할 확정] 진입 경로만으로 역할을 정한다. 초대 링크(roomId)를 들고
    //    들어왔으면 게스트다. 첫 프레임을 그리기 전에 정해야 호스트용 UI(초대
    //    버튼)가 한 프레임도 게스트에게 보이지 않는다.
    //    ※ 과금 초기화(_stopDuoBilling)는 이 줄 위에서 끝내 둔다 — 그 함수가
    //      _amIHost를 보고 갈라지기 때문이다.
    if (_resolveGuestRoomId() != null) {
      _amIHost = false;
      debugPrint('[Duo] role=GUEST (invite entry)');
    } else {
      debugPrint('[Duo] role=HOST (direct entry)');
    }

    _ttsPlayer.onPlayerComplete.listen((_) {
      _isTtsActive = false;
      if (_ttsCompleter != null && !_ttsCompleter!.isCompleted) {
        _ttsCompleter!.complete();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final String? pendingRoomId = _resolveGuestRoomId();
      if (pendingRoomId != null) {
        debugPrint(
            '[Duo] initState — guest entry, show lang overlay: $pendingRoomId');
        // 🆕 입장 전 언어 선택 오버레이 — 기본값 보정 후 표시
        if (FFAppState().nativeLang.isEmpty) FFAppState().nativeLang = 'Korean';
        if (FFAppState().targetLang.isEmpty)
          FFAppState().targetLang = 'English';
        if (mounted) {
          setState(() {
            _pendingJoinRoomId = pendingRoomId;
            _showLangOverlay = true;
            _pendingModeLoading = true;
          });
        }
        // 🆕 대화 방식은 딥링크가 아니라 **세션 문서**가 기준이다. 팝업을 띄운
        //    뒤 곧바로 방 문서를 읽어 호스트가 정한 방식을 표시한다.
        unawaited(_loadInvitedMode(pendingRoomId));
      }
    });
  }

  /// 초대받은 방의 대화 방식을 읽어 온다(게스트 입장 팝업용).
  Future<void> _loadInvitedMode(String roomId) async {
    String mode = kDuoModeInterpreter;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('duo_sessions')
          .doc(roomId)
          .get();
      mode = _normalizeDuoMode(snap.data()?['mode']);
      _lgDuo('[MODE]', 'invited mode=$mode room=$roomId');
    } catch (e) {
      _lgDuo('[MODE]', 'invited_mode_read_failed(${e.runtimeType}) → 기본값 사용');
    }
    if (!mounted) return;
    setState(() {
      _duoMode = mode;
      _pendingModeLoading = false;
    });
  }

  @override
  void dispose() {
    if (StealthRoomMaster.saveAndExitCurrentMode == _handleAutoSaveAndExit) {
      StealthRoomMaster.saveAndExitCurrentMode = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _partnerJoinedSubscription?.cancel();
    _messageSubscription?.cancel(); // 🆕 메시지 채널 구독 해제
    // 🆕 직접 대화 통화 경로(마이크·릴레이·전사·재생) 즉시 정리
    unawaited(_stopDirectCall('dispose'));
    _silenceTimer?.cancel();
    _cancelAudio();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _ttsPlayer.dispose();
    BillingTicker.instance.pause();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!FFAppState().isGuestSession) return;

    if (state == AppLifecycleState.paused) {
      // 초대 게스트가 앱을 떠나면 Duo 세션을 종료한다. 정리 작업은
      // 백그라운드에서도 마무리하고, 복귀 시에는 Intro만 보이게 한다.
      unawaited(_handleAutoSaveAndExit());
    } else if (state == AppLifecycleState.resumed && _isExiting && mounted) {
      context.goNamed('Intro');
    }
  }

  Future<void> _fetchKeys() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: const Duration(minutes: 1)));
      await remoteConfig.fetchAndActivate();
      final String relayUrl = remoteConfig.getString('DuoRelayUrl').trim();
      final String relayToken = remoteConfig.getString('DuoRelayToken').trim();
      if (mounted) {
        setState(() {
          _openAiKey = remoteConfig.getString('OpenAIAPIKey');
          // Remote Config가 1순위, 비어 있으면 빌드 타임 값을 유지한다.
          if (relayUrl.isNotEmpty) _relayUrl = relayUrl;
          if (relayToken.isNotEmpty) _relayToken = relayToken;
        });
      }
    } catch (e) {}
  }

  void _lgDuo(String tag, String msg) => debugPrint('[Duo]$tag $msg');

  /// 초대받아 들어온 방 id. null이면 이 화면을 직접 연 호스트다.
  /// widget.roomId 우선, 없으면 딥링크가 남긴 FFAppState 값을 본다.
  String? _resolveGuestRoomId() {
    final String? fromWidget = widget.roomId;
    if (fromWidget != null && fromWidget.isNotEmpty) return fromWidget;
    if (FFAppState().isGuestSession && FFAppState().duoRoomId.isNotEmpty) {
      return FFAppState().duoRoomId;
    }
    return null;
  }

  // 전사 세션이 요구하는 언어 코드. 직접 대화에서는 **내가 말하는 언어**,
  // 즉 내 ORIGIN(대화 언어)을 넘긴다.
  String _mapLanguageToCode(String lang) {
    switch (lang.trim().toLowerCase()) {
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
      case 'hindi':
        return 'hi';
      case 'dutch':
        return 'nl';
      default:
        return 'en';
    }
  }

  Future<void> _initPermissions() async {
    await [Permission.microphone].request();
  }

  // ============================================================================
  // 📦 [4. 오디오 관리 로직 (AUDIO MANAGEMENT)]
  // TTS 재생, 취소 및 마이크 입력 감지
  // ============================================================================
  void _cancelAudio() {
    _cancelDuoRealtime();
    _audioPlayer.stop();
    _ttsPlayer.stop();
    if (_ttsCompleter != null && !_ttsCompleter!.isCompleted) {
      _ttsCompleter!.complete();
    }
    _isTtsActive = false;
  }

  Future<void> _playAudioAndWait(Uint8List? bytes) async {
    if (bytes == null || !_isConversationActive) return;
    _isTtsActive = true;
    _ttsCompleter = Completer<void>();
    try {
      await _ttsPlayer.play(BytesSource(bytes));
      await _ttsCompleter!.future;
    } catch (e) {}
    _ttsCompleter = null;
    _isTtsActive = false;
    _lastTtsEndAt = DateTime.now();
  }

  // 🆕 오디오 재생 직렬화: 내 음성과 상대 음성이 동시에 겹쳐 재생되지 않도록 큐잉
  Future<void> _playSerialized(Uint8List? bytes) {
    final Future<void> prev = _audioChain;
    final Completer<void> done = Completer<void>();
    _audioChain = done.future;
    () async {
      try {
        await prev;
      } catch (_) {}
      try {
        await _playAudioAndWait(bytes);
      } finally {
        if (!done.isCompleted) done.complete();
      }
    }();
    return done.future;
  }

  // ============================================================================
  // 📦 [4-D. 직접 대화 (DIRECT CALL)]
  // 마이크 PCM 한 줄기를 두 갈래로 나눈다.
  //
  //   record.startStream(pcm16 24kHz mono)
  //        ├─→ DuoPcmRelayClient  → 릴레이 → 상대 폰 AudioTrack (실제 목소리)
  //        └─→ OpenAiStreaming…   → 전사문 → 공유 채널 + History (화면 표시 없음)
  //
  // 두 갈래는 서로를 기다리지 않는다. 전사가 늦거나 죽어도 목소리는 그대로 간다.
  // 이 경로에는 GPT 번역·TTS-1·Realtime·Nova가 **하나도** 들어오지 않는다.
  // ============================================================================

  /// 직접 대화 전사문 중 버릴 것. 만능 통역 쪽 필터는 건드리지 않는다.
  bool _isNoiseTranscript(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.length <= 2) return true;
    final String lower = trimmed.toLowerCase();
    final String clean = lower.replaceAll(RegExp(r'[^\w\s가-힣]'), '').trim();
    if (clean.isEmpty) return true;
    const List<String> hardGhosts = [
      'thank you for watching',
      'thanks for watching',
      'please subscribe',
      'subtitles by',
      '시청해 주셔서',
      '시청해주셔서',
      '구독과 좋아요',
    ];
    return hardGhosts.any((g) => lower.contains(g));
  }

  bool _isDirectGenerationCurrent(int generation) =>
      mounted &&
      !_isExiting &&
      _directCallActive &&
      generation == _directGeneration;

  void _onDirectMicToggle() {
    if (_directCallActive) {
      unawaited(_stopDirectCall('user_tap'));
    } else {
      unawaited(_startDirectCall());
    }
  }

  Future<void> _startDirectCall() async {
    if (_directCallActive || _directStarting || _isExiting) return;
    if (_relayUrl.trim().isEmpty) {
      _lgDuo('[DIRECT]', 'start_blocked reason=no_relay_url');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('직접 대화 서버 주소가 설정되지 않았습니다.'),
        ));
      }
      return;
    }
    final String? roomId = _duoSessionRef?.id ?? widget.roomId;
    if (roomId == null || roomId.isEmpty) {
      _lgDuo('[DIRECT]', 'start_blocked reason=no_room');
      return;
    }
    if (!await _audioRecorder.hasPermission()) {
      _lgDuo('[DIRECT]', 'start_blocked reason=no_mic_permission');
      return;
    }

    // 🔒 [모드 잠금] 오디오 경로를 여는 마지막 순간에 방 문서를 다시 읽는다.
    //    호스트와 게스트가 서로 다른 모드로 파이프라인을 여는 일을 여기서 막는다.
    //    (리스너를 놓쳤거나 화면 진입 후 모드가 바뀐 경우가 여기 걸린다)
    try {
      final snap = await FirebaseFirestore.instance
          .collection('duo_sessions')
          .doc(roomId)
          .get();
      final String authoritative = _normalizeDuoMode(snap.data()?['mode']);
      if (authoritative != kDuoModeDirect) {
        _lgDuo('[MODE]',
            'direct_start_blocked session_mode=$authoritative (문서가 기준)');
        if (mounted) setState(() => _duoMode = authoritative);
        return;
      }
    } catch (e) {
      // 문서를 못 읽으면 통화를 열지 않는다. 모드가 어긋난 채 여는 것보다 낫다.
      _lgDuo('[MODE]', 'direct_start_blocked reason=mode_read_failed');
      return;
    }

    _directStarting = true;
    final int generation = ++_directGeneration;
    _directCallActive = true;
    if (mounted) setState(() => _isConversationActive = true);
    _setDuoState('live');
    BillingTicker.instance.resumeFromActivity('duo_direct_start');

    try {
      // ① 재생기 먼저 — 상대 소리가 언제 와도 받을 수 있게 열어 둔다.
      final player = DuoPcmJitterPlayer(onLog: _lgDuo);
      final playerOk = await player.start();
      if (!_isDirectGenerationCurrent(generation)) {
        await player.stop();
        return;
      }
      _jitterPlayer = playerOk ? player : null;
      if (!playerOk) {
        // Android 외 플랫폼은 PCM 재생 채널이 없다. 상대 목소리를 낼 방법이
        // 없으므로 반쪽짜리 통화를 여는 대신 시작 자체를 막는다.
        _lgDuo('[DIRECT]', 'start_failed reason=pcm_player_unavailable');
        await _stopDirectCall('pcm_player_unavailable');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('이 기기에서는 아직 직접 대화를 지원하지 않습니다.'),
          ));
        }
        return;
      }

      // ② 릴레이 접속. 회원이면 ID 토큰을 같이 보내 서버가 uid 소유를 확인한다.
      String idToken = '';
      try {
        idToken =
            await FirebaseAuth.instance.currentUser?.getIdToken() ?? '';
      } catch (_) {}
      if (!_isDirectGenerationCurrent(generation)) return;
      final relay = DuoPcmRelayClient(
        url: _relayUrl,
        roomId: roomId,
        uid: _myUid,
        role: _myRole,
        sessionId: '$roomId#$generation',
        token: _relayToken,
        idToken: idToken,
        onLog: _lgDuo,
        onPartnerPresence: (present) {
          if (!_isDirectGenerationCurrent(generation)) return;
          if (mounted) setState(() => _partnerRelayConnected = present);
          // 상대가 끊겼다 붙으면 밀린 조각은 버리고 새 소리부터 재생한다.
          if (!present) _jitterPlayer?.resetBuffer('partner_left');
        },
      );
      _relayClient = relay;
      _relayInboundSub = relay.inbound.listen((pcm) {
        if (!_isDirectGenerationCurrent(generation)) return;
        _jitterPlayer?.add(pcm);
      });
      final relayOk = await relay.connect();
      if (!_isDirectGenerationCurrent(generation)) {
        await relay.dispose();
        return;
      }
      if (mounted) {
        setState(() {
          _relayConnected = relayOk;
          _partnerRelayConnected = relay.partnerPresent;
        });
      }
      if (!relayOk) {
        await _stopDirectCall('relay_connect_failed');
        return;
      }

      // ③ 전사 세션 — 실패해도 통화는 계속한다(History 텍스트만 포기).
      await _startDirectStt(generation);

      // ④ 마이크 한 개를 열어 두 갈래로 흘린다.
      final capture = await AnyonePreparedAudioCapture.start(
        recorder: _audioRecorder,
        onRecordingStarted: (at) =>
            _lgDuo('[PCM_CAPTURE]', 'recording_started at=${at.toIso8601String()}'),
        onFirstFrame: (at, byteCount) {
          _directCaptureFirstFrameAt = at;
          // 지터버퍼 크기를 정하려면 이 chunk 크기를 알아야 한다.
          _lgDuo(
              '[PCM_CAPTURE]',
              'first_frame_bytes=$byteCount (~${byteCount ~/ kDuoDirectBytesPerMs}ms) '
                  'at=${at.toIso8601String()}');
        },
      );
      if (!_isDirectGenerationCurrent(generation)) {
        await capture.stop();
        return;
      }
      _directCapture = capture;
      _directCaptureSub = capture.stream.listen(
        (bytes) {
          if (bytes.isEmpty) return;
          if (generation != _directGeneration) return;
          // 갈래 1 — 상대에게 보내는 실제 목소리. 전사를 기다리지 않는다.
          _relayClient?.sendPcm(bytes);
          // 갈래 2 — History용 전사. 실패해도 위 한 줄에 영향이 없다.
          final stt = _directStt;
          if (stt != null && stt.audioGateOpen) stt.appendAudio(bytes);
        },
        onError: (Object e) =>
            _lgDuo('[DIRECT]', 'capture_error=${e.runtimeType}'),
      );
      if (mounted) setState(() => _micActive = true);
      _lgDuo(
          '[DIRECT]',
          'call_started gen=$generation room=$roomId role=$_myRole '
              'micActive=true sttActive=$_sttActive '
              'relayConnected=$_relayConnected '
              'partnerRelayConnected=$_partnerRelayConnected '
              'captureFirstFrameAt=${_directCaptureFirstFrameAt?.toIso8601String()}');
    } catch (e) {
      _lgDuo('[DIRECT]', 'start_error=${e.runtimeType}');
      await _stopDirectCall('start_error');
    } finally {
      _directStarting = false;
    }
  }

  Future<void> _startDirectStt(int generation) async {
    if (_openAiKey.isEmpty) {
      _lgDuo('[DIRECT-STT]', 'skipped reason=no_api_key');
      return;
    }
    final session = OpenAiStreamingTranscribeSession(
      apiKey: _openAiKey,
      languageCode: _mapLanguageToCode(_myNative()),
      onLog: (tag, msg) => _lgDuo('[DIRECT-STT]$tag', msg),
    );
    session.shouldReconnect = () => _isDirectGenerationCurrent(generation);
    // 발화 순서는 전사 응답이 돌아온 순서가 아니라 **말을 시작한 시각** 기준이다.
    // 서버 VAD가 speech_started를 줄 때 찍어 두고, completed에 그대로 붙인다.
    session.onSpeechStarted = () {
      if (!_isDirectGenerationCurrent(generation)) return;
      _directSpeechStartedAt = DateTime.now();
    };
    session.onTranscriptCompleted = (itemId, text) {
      if (!_isDirectGenerationCurrent(generation)) return;
      unawaited(_handleDirectTranscript(generation, text, itemId));
    };
    session.onFatalError = (reason) {
      _lgDuo('[DIRECT-STT]', 'fatal=$reason (통화는 계속된다)');
      if (mounted && _isDirectGenerationCurrent(generation)) {
        setState(() => _sttActive = false);
      }
    };
    final ok = await session.connect();
    if (!_isDirectGenerationCurrent(generation)) {
      await session.dispose();
      return;
    }
    if (!ok) {
      await session.dispose();
      _lgDuo('[DIRECT-STT]', 'connect_failed (통화는 계속된다)');
      return;
    }
    session.openAudioGate(reason: 'direct_call');
    _directStt = session;
    if (mounted) setState(() => _sttActive = true);
  }

  /// 내 발화 전사문 하나. **화면에는 아무것도 그리지 않는다.**
  /// 상대 폰이 자기 History를 채울 수 있도록 기존 텍스트 채널로도 올린다.
  ///
  /// 순서 보장: 전사 응답 도착 순서가 아니라 발화 시작 시각(`spokenAt`)과
  /// 화자별 로컬 일련번호(`seq`)를 같이 남긴다. History는 나중에 이 둘로
  /// 두 사람의 발화를 하나의 대화 순서로 합칠 수 있다.
  Future<void> _handleDirectTranscript(
      int generation, String text, String itemId) async {
    if (!_isDirectGenerationCurrent(generation)) return;
    final String trimmed = text.trim();
    if (trimmed.isEmpty || _isNoiseTranscript(trimmed)) return;
    final int seq = ++_directSeq;
    final DateTime spokenAt = _directSpeechStartedAt ?? DateTime.now();
    _directSpeechStartedAt = null;
    _lgDuo('[DIRECT-STT]',
        'completed seq=$seq item=$itemId len=${trimmed.length}');
    _uploadMyMessage(
      trimmed,
      _myNative(),
      mode: kDuoModeDirect,
      seq: seq,
      spokenAt: spokenAt,
    );
    // 원문 자리에 전사문을 넣는다. 타겟 문장과 소리는 히스토리에서 만든다.
    await _saveHistoryMessage(
      '',
      trimmed,
      'HOST',
      mode: kDuoModeDirect,
      seq: seq,
      spokenAt: spokenAt,
      speakerUid: _myUid,
      sourceLang: _myNative(),
    );
  }

  Future<void> _stopDirectCall(String reason) async {
    if (!_directCallActive && _relayClient == null && _directCapture == null) {
      return;
    }
    ++_directGeneration; // 이 시점 이후의 늦은 콜백은 전부 남의 세대다.
    _directCallActive = false;
    _directCaptureFirstFrameAt = null;

    final captureSub = _directCaptureSub;
    _directCaptureSub = null;
    await captureSub?.cancel();

    final capture = _directCapture;
    _directCapture = null;
    await capture?.stop();

    final stt = _directStt;
    _directStt = null;
    stt?.closeAudioGate(reason: reason);
    await stt?.dispose();

    final relaySub = _relayInboundSub;
    _relayInboundSub = null;
    await relaySub?.cancel();

    final relay = _relayClient;
    _relayClient = null;
    await relay?.dispose();

    final player = _jitterPlayer;
    _jitterPlayer = null;
    await player?.stop();

    if (mounted && !_isExiting) {
      setState(() {
        _micActive = false;
        _sttActive = false;
        _relayConnected = false;
        _partnerRelayConnected = false;
      });
      _setDuoState('idle');
    } else {
      _micActive = false;
      _sttActive = false;
      _relayConnected = false;
      _partnerRelayConnected = false;
      _duoState = 'idle';
    }
    _lgDuo('[DIRECT]',
        'call_stopped reason=$reason relayRttMs=${relay?.lastRoundTripMs} '
        'playFirstLatencyMs=${player?.firstPlayLatencyMs} '
        'sentBytes=${relay?.sentBytes} recvBytes=${relay?.receivedBytes} '
        'playedBytes=${player?.writtenBytes} droppedBytes=${player?.droppedBytes}');
  }

  Future<void> _startWhisperRecording() async {
    if (_openAiKey.isEmpty) return;
    // 직접 대화는 m4a/whisper PTT 경로를 타지 않는다. 마이크는 통화가 쥔다.
    if (_isDirectMode) return;
    // 🆕 [PTT] idle 상태가 아니면 시작 금지 (TTS·처리·쿨다운·이미 녹음 중 차단)
    if (_duoState != 'idle') return;
    if (_isTtsActive || _isDrainingIncoming) return;
    if (await _audioRecorder.isRecording()) return;
    if (await _audioRecorder.hasPermission()) {
      BillingTicker.instance.resumeFromActivity('duo_mic_start');
      _hasSpoken = false;
      _silenceCounter = 0;
      try {
        final dir = await getTemporaryDirectory();
        final path =
            '${dir.path}/whisper_stt_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(
            const RecordConfig(
                encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1),
            path: path);
        _setDuoState('recording');
        if (_duoConversationTurnCounter == 0) {
          _prewarmDuoRealtime(_myVoice());
        }
        _silenceTimer?.cancel();
        // [토글] 발화 후 1.5초 침묵하면 자동 전송. 버튼 탭으로도 즉시 전송 가능.
        // 무발화로 오래 켜져 있으면 안전 종료하여 마이크 점유와 과금을 방지한다.
        _silenceTimer =
            Timer.periodic(const Duration(milliseconds: 100), (timer) async {
          if (await _audioRecorder.isRecording()) {
            final amp = await _audioRecorder.getAmplitude();
            if (amp.current > -25.0) {
              _hasSpoken = true;
              _silenceCounter = 0;
            } else {
              _silenceCounter++;
              if (_hasSpoken && _silenceCounter >= 15) {
                // 발화 후 1.5초 침묵 → 자동 종료·전송 (버튼 탭과 동일 경로)
                timer.cancel();
                await _stopAndSendToWhisper();
              } else if (!_hasSpoken && _silenceCounter >= 150) {
                // 말이 한 번도 없이 오래 켜져 있으면 안전 종료(전송 안 함)
                timer.cancel();
                await _audioRecorder.stop();
                _cancelDuoRealtime();
                _setDuoState('idle');
              }
            }
          } else {
            timer.cancel();
          }
        });
      } catch (e) {
        _cancelDuoRealtime();
        _setDuoState('idle');
      }
    }
  }

// ============================================================================
  // 📦 [5. 핵심 양방향 통역 파이프라인 (CORE INTERPRETER LOGIC)]
  // 내 발화: STT → 내 폰 즉시 렌더 → 내 타겟 통역/TTS → 공유 채널 업로드
  // 상대 발화: 채널 리스너 수신 → 내 언어쌍으로 통역 → 좌측 렌더 + 내 타겟 TTS
  // ============================================================================
  Future<void> _stopAndSendToWhisper() async {
    _silenceTimer?.cancel();
    // 녹음은 즉시 멈추되, 화면에서는 마이크가 자연스럽게 꺼지는 짧은 전환을 보여준다.
    _setDuoState('finishing');
    final path = await _audioRecorder.stop();
    BillingTicker.instance.resumeFromActivity('duo_mic_stop');
    await Future.delayed(const Duration(milliseconds: 220));
    if (path == null) {
      _cancelDuoRealtime();
      _setDuoState('idle');
      if (_incomingQueue.isNotEmpty) _drainIncoming();
      return;
    }
    _setDuoState('processing');
    try {
      Uri uri = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
      var request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $_openAiKey';
      request.fields['model'] = 'whisper-1';
      request.files.add(await http.MultipartFile.fromPath('file', path));
      var response = await request.send().timeout(const Duration(seconds: 10));
      var responseData = await response.stream.bytesToString();
      if (response.statusCode == 200) {
        String transcript = jsonDecode(responseData)['text'] ?? "";
        BillingTicker.instance.resumeFromActivity('duo_stt_result');
        final String trimmed = transcript.trim();
        final String lowerRaw = trimmed.toLowerCase();
        final String lowerClean =
            lowerRaw.replaceAll(RegExp(r'[^\w\s가-힣]'), '').trim();
        final String collapsed = lowerClean.replaceAll(' ', '');
        const List<String> hardGhosts = [
          'thank you so much for watching',
          'thank you for watching',
          'thanks for watching',
          'please subscribe',
          'subtitles by',
          'share this video',
          '시청해 주셔서',
          '시청해주셔서',
          '구독과 좋아요',
          '감사합니다 시청',
        ];
        final bool isHardGhost = hardGhosts.any((g) => lowerRaw.contains(g));
        const List<String> shortGhosts = [
          'thank you',
          'yeah',
          'okay',
          'mbc',
          'you',
          'also',
          'i',
          '감사합니다',
        ];
        final bool isShortGhost = trimmed.length < 30 &&
            shortGhosts.any((g) => collapsed == g.replaceAll(' ', ''));
        // 🆕 에코 차단: 최근 앱이 만든 문장과 거의 같으면 버림
        final bool isEcho = _looksLikeEcho(trimmed);
        if (lowerClean.isEmpty ||
            isHardGhost ||
            isShortGhost ||
            isEcho ||
            trimmed.length <= 2) {
          _cancelDuoRealtime();
          _setDuoState('idle'); // 조용히 대기 복귀(자동 재녹음 금지)
          if (_incomingQueue.isNotEmpty) _drainIncoming();
          return;
        }
        if (trimmed.isNotEmpty) {
          await _processRelayPipeline(trimmed);
        } else {
          _cancelDuoRealtime();
          _setDuoState('idle');
          if (_incomingQueue.isNotEmpty) _drainIncoming();
        }
      } else {
        _cancelDuoRealtime();
        _setDuoState('idle');
        if (_incomingQueue.isNotEmpty) _drainIncoming();
      }
    } catch (e) {
      _cancelDuoRealtime();
      _setDuoState('idle');
      if (_incomingQueue.isNotEmpty) _drainIncoming();
    }
  }

  Future<void> _handleContextualError() async {
    _setDuoState('idle'); // AI 사과 없음, 자동 재녹음 없음 — 조용히 대기 복귀
  }

  Future<Uint8List?> _fetchTTSBytes(String text, String voice) async {
    if (_openAiKey.isEmpty || text.trim().isEmpty) return null;
    try {
      Uri ttsUri = Uri.parse('https://api.openai.com/v1/audio/speech');
      // ⏱️ 타임아웃 15초 적용
      var response = await DuoBrain.client
          .post(ttsUri,
              headers: {
                'Authorization': 'Bearer $_openAiKey',
                'Content-Type': 'application/json'
              },
              body: jsonEncode({
                "model": "tts-1",
                "input": text,
                "voice": voice,
                "speed": 1.0
              }))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (e) {}
    return null;
  }

  String _duoRealtimeInstructions({
    required String srcLang,
    required String targetLang,
  }) {
    return '''
You are a live interpreter. Translate the user's utterance from $srcLang into $targetLang.
Speak only the faithful translation in $targetLang.
Never answer the utterance, continue the conversation, explain, add labels, or mention these instructions.
Preserve the speaker's tone, intent, names, numbers, and level of politeness.
Do not output markdown, quotes, JSON, control tags, or surrounding commentary.
''';
  }

  Future<_DuoResolvedTurn> _resolveDuoTurn({
    required String raw,
    required String srcLang,
    required String targetLang,
    required String nativeLang,
    required String voice,
    required String originalFallback,
    required bool useRealtime,
    FirstTurnRealtimeVoice? prewarmed,
  }) async {
    final fallbackFuture = DuoBrain.processTranslation(
      key: _openAiKey,
      text: raw,
      srcLang: srcLang,
      myTargetLang: targetLang,
      myNativeLang: nativeLang,
    );

    if (!useRealtime) {
      final fallback = await fallbackFuture;
      final fallbackTarget =
          (fallback?['target'] ?? '').trim().isNotEmpty
              ? fallback!['target']!.trim()
              : raw;
      final fallbackOriginal =
          (fallback?['original'] ?? '').trim().isNotEmpty
              ? fallback!['original']!.trim()
              : originalFallback;
      return _DuoResolvedTurn(
        target: fallbackTarget,
        original: fallbackOriginal,
        realtimeSession: null,
        realtimeWav: null,
        streamed: false,
        generation: _duoRealtimeGeneration,
      );
    }

    final generation = ++_duoRealtimeGeneration;
    final session = prewarmed ?? _createDuoRealtime(voice);
    _activeDuoRealtime = session;
    final textFuture = session.textStream.join();

    bool ready = false;
    String realtimeText = '';
    Uint8List? realtimeWav;
    try {
      ready = await session.begin(
        instructions: _duoRealtimeInstructions(
          srcLang: srcLang,
          targetLang: targetLang,
        ),
        userContent: raw,
      );
      realtimeText = (await textFuture).trim();
      realtimeWav = await session.audioWav;
    } catch (error) {
      debugPrint('[Duo][Realtime] turn failed: $error');
      session.cancel();
    }

    final fallback = await fallbackFuture;
    final requestCurrent = mounted &&
        !_isExiting &&
        _isConversationActive &&
        generation == _duoRealtimeGeneration &&
        identical(_activeDuoRealtime, session);
    final streamed = requestCurrent && session.streamedAudio;
    final realtimeSucceeded = requestCurrent &&
        ready &&
        realtimeText.isNotEmpty &&
        (streamed || (realtimeWav?.isNotEmpty ?? false));

    if (!realtimeSucceeded) {
      if (identical(_activeDuoRealtime, session)) {
        _activeDuoRealtime = null;
      }
      session.cancel();
    }

    final fallbackTarget =
        (fallback?['target'] ?? '').trim().isNotEmpty
            ? fallback!['target']!.trim()
            : raw;
    final fallbackOriginal =
        (fallback?['original'] ?? '').trim().isNotEmpty
            ? fallback!['original']!.trim()
            : originalFallback;

    debugPrint(
      '[Duo][Realtime] resolved generation=$generation '
      'success=$realtimeSucceeded streamed=$streamed '
      'fallback=${!realtimeSucceeded}',
    );
    return _DuoResolvedTurn(
      target: realtimeSucceeded ? realtimeText : fallbackTarget,
      original: fallbackOriginal,
      realtimeSession: realtimeSucceeded ? session : null,
      realtimeWav: realtimeSucceeded ? realtimeWav : null,
      streamed: realtimeSucceeded && streamed,
      generation: generation,
    );
  }

  Future<void> _playDuoResolvedTurn(
    _DuoResolvedTurn turn, {
    required String fallbackVoice,
  }) async {
    final session = turn.realtimeSession;
    if (turn.generation != _duoRealtimeGeneration ||
        !_isConversationActive ||
        _isExiting) {
      session?.cancel();
      if (identical(_activeDuoRealtime, session)) {
        _activeDuoRealtime = null;
      }
      return;
    }
    if (session != null) {
      try {
        if (turn.streamed) {
          await session.playbackDone;
        } else if (turn.realtimeWav?.isNotEmpty ?? false) {
          _setDuoState('playing');
          BillingTicker.instance
              .resumeFromActivity('duo_realtime_audio_start');
          await _playSerialized(turn.realtimeWav);
        }
        BillingTicker.instance.resumeFromActivity('duo_realtime_audio_end');
        _lastTtsEndAt = DateTime.now();
      } finally {
        if (identical(_activeDuoRealtime, session)) {
          _activeDuoRealtime = null;
        }
      }
      return;
    }

    final bytes = await _fetchTTSBytes(turn.target, fallbackVoice);
    if (bytes == null || !_isConversationActive || _isExiting) return;
    _setDuoState('playing');
    BillingTicker.instance.resumeFromActivity('duo_tts_start');
    await _playSerialized(bytes);
    BillingTicker.instance.resumeFromActivity('duo_tts_end');
  }

  // 🚀 [내 발화 처리] 내가 말한 것을 내 폰에 즉시 띄우고, 내 타겟으로 통역/TTS, 채널 업로드
  Future<void> _processRelayPipeline(String finalTranscript) async {
    _turnCounter++;
    final int currentTurnId = _turnCounter;
    final bool useRealtime = ++_duoConversationTurnCounter == 1;
    final String myTarget = _myTarget();
    final String myNative = _myNative();

    // 1. 즉시 표시 제거 - 번역 완료 후 단계 4에서 새 말풍선으로 표시

    // 2. 공유 채널 업로드 — 상대 폰이 이 원문을 받아 자기 언어쌍으로 통역함 (백그라운드)
    _uploadMyMessage(finalTranscript, myNative);

    if (!_isConversationActive || _turnCounter != currentTurnId) return;

    // 3. 세션의 첫 PTT만 Realtime 우선. 이후 턴은 기존 GPT JSON + TTS-1.
    final resolved = await _resolveDuoTurn(
      raw: finalTranscript,
      srcLang: myNative,
      targetLang: myTarget,
      nativeLang: myNative,
      voice: _myVoice(),
      originalFallback: finalTranscript,
      useRealtime: useRealtime,
      prewarmed:
          useRealtime ? _takePrewarmedDuoRealtime(_myVoice()) : null,
    );

    if (!_isConversationActive || _turnCounter != currentTurnId) return;

    final String tgt = resolved.target;
    final String org = resolved.original;

    // 4. 번역 완료 후 내 말풍선을 [타겟 + 오리지널]로 새 말풍선에 표시
    if (mounted) {
      setState(() {
        _localMessages.add({'role': 'HOST', 'target': tgt, 'original': org});
      });
      _scrollToCurrentTop(_localMessages.length - 1);
    }
    await _saveHistoryMessage(tgt, org, 'HOST');

    // 5. 첫 PTT는 Realtime PCM/WAV 우선, 이후 턴은 기존 TTS-1로 재생한다.
    _rememberGenerated(tgt);
    _rememberGenerated(org);
    if (_isConversationActive && _turnCounter == currentTurnId) {
      await _playDuoResolvedTurn(
        resolved,
        fallbackVoice: _myVoice(),
      );
    }
    // 🆕 [PTT] 자동 재녹음 제거 — 쿨다운 후 대기 상태로 복귀
    _setDuoState('cooldown');
    await Future.delayed(const Duration(milliseconds: 800));
    _setDuoState('idle');
    // 🆕 내 발화 처리 끝 → 보류돼 있던 상대 메시지 처리 재개
    if (_incomingQueue.isNotEmpty) _drainIncoming();
  }

  // 🆕 [채널 업로드] 내 원문을 duo_sessions/{roomId}/messages 에 기록
  //
  // mode/seq/spokenAt은 직접 대화에서만 채워진다(기존 통역 경로는 호출부가
  // 그대로라 필드가 붙지 않는다 — 기존 문서 모양을 깨지 않는다).
  Future<void> _uploadMyMessage(
    String raw,
    String srcLang, {
    String? mode,
    int? seq,
    DateTime? spokenAt,
  }) async {
    if (_duoSessionRef == null || raw.trim().isEmpty) return;
    try {
      // 🆕 내 메시지 doc id를 업로드 전에 _processedMsgIds에 선등록한다.
      //    → 리스너(605행)가 내 발화를 항상 스킵하므로, 내 글이 절대
      //      상대(SYSTEM/좌측) 말풍선으로 되돌아오지 않는다. 역할/계정 무관.
      final docRef = _duoSessionRef!.collection('messages').doc();
      _processedMsgIds.add(docRef.id);
      await docRef.set({
        'senderUid': _myUid,
        'senderRole': _myRole,
        'text': raw,
        'srcLang': srcLang,
        'createdAt': FieldValue.serverTimestamp(),
        if (mode != null) 'duoMode': mode,
        if (seq != null) 'seq': seq,
        if (spokenAt != null) 'spokenAt': spokenAt.millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('[Duo] upload message error: $e');
    }
  }

  // 🆕 [상대 발화 리스너] 공유 채널 구독 → 상대(senderRole≠나) 메시지만 처리
  void _listenForMessages() {
    if (_duoSessionRef == null) return;
    _messageSubscription?.cancel();
    _messagesPrimed = false;
    _messageSubscription = _duoSessionRef!
        .collection('messages')
        .orderBy('createdAt')
        .snapshots()
        .listen((snap) {
      if (_isExiting || !mounted) return;

      // 첫 스냅샷: 기존 메시지는 '이미 본 것'으로 처리만 하고 렌더하지 않음 (replay 방지)
      if (!_messagesPrimed) {
        for (final d in snap.docs) {
          _processedMsgIds.add(d.id);
        }
        _messagesPrimed = true;
        return;
      }

      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final doc = change.doc;
        if (_processedMsgIds.contains(doc.id)) continue;
        _processedMsgIds.add(doc.id);

        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        final String msgRole = data['senderRole']?.toString() ?? '';
        if (msgRole == _myRole) continue; // 내가 올린 것 — 이미 로컬 렌더됨, 스킵

        BillingTicker.instance.resumeFromActivity('duo_message_received');
        _enqueueIncoming(data);
      }
    });
  }

  // 🆕 상대 메시지 순차 처리 큐 (음성 겹침/순서 꼬임 방지)
  void _enqueueIncoming(Map<String, dynamic> data) {
    _incomingQueue.add(data);
    _drainIncoming();
  }

  Future<void> _drainIncoming() async {
    if (_isDrainingIncoming) return;
    _isDrainingIncoming = true;
    while (_incomingQueue.isNotEmpty) {
      // 녹음뿐 아니라 내 발화의 Realtime/폴백 처리 중에도 상대 턴을 보류한다.
      // Android PCM 채널과 MP3 플레이어는 한 턴씩만 소유해야 음성이 겹치지 않는다.
      //
      // 직접 대화는 예외다. 상대 메시지가 소리를 재생하지 않고 History 텍스트만
      // 남기므로 통화 중(_duoState='live')에도 그대로 처리한다.
      if (!_isDirectMode && _duoState != 'idle') break;
      final data = _incomingQueue.removeAt(0);
      await _handleIncomingMessage(data);
    }
    _isDrainingIncoming = false;
  }

  // 🆕 [상대 발화 처리] 원문을 내 언어쌍으로 통역 → 좌측 말풍선 + 내 타겟 TTS
  Future<void> _handleIncomingMessage(Map<String, dynamic> data) async {
    if (!mounted || _isExiting) return;
    final String raw = data['text']?.toString() ?? '';
    final String srcLang = data['srcLang']?.toString() ?? 'English';
    if (raw.trim().isEmpty) return;

    // 🆕 [직접 대화] 상대 목소리는 이미 릴레이로 실시간 재생됐다. 여기 오는 건
    // 그 발화의 전사문뿐이므로 번역·TTS·말풍선 없이 History에만 남긴다.
    if (_isDirectMode) {
      final int? seq = (data['seq'] as num?)?.toInt();
      final int? spokenMs = (data['spokenAt'] as num?)?.toInt();
      await _saveHistoryMessage(
        '',
        raw.trim(),
        'SYSTEM',
        mode: kDuoModeDirect,
        seq: seq,
        spokenAt: spokenMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(spokenMs),
        speakerUid: data['senderUid']?.toString(),
        // 상대가 말한 언어는 상대의 ORIGIN이다. 채널에 실려 온 값을 그대로 쓴다.
        sourceLang: srcLang,
      );
      return;
    }

    // 상대 발화를 들려주는 동안 내 녹음 일시 정지 (스피커 음성이 마이크에 새는 것 방지)
    _silenceTimer?.cancel();
    try {
      await _audioRecorder.stop();
    } catch (_) {}
    _setDuoState('processing');

    final String myTarget = _myTarget();
    final String myNative = _myNative();
    final bool useRealtime = ++_duoConversationTurnCounter == 1;

    final resolved = await _resolveDuoTurn(
      raw: raw,
      srcLang: srcLang,
      targetLang: myTarget,
      nativeLang: myNative,
      voice: 'nova',
      originalFallback: '',
      useRealtime: useRealtime,
    );

    if (!mounted || _isExiting) return;

    final String tgt = resolved.target;
    final String org = resolved.original;

    // 상대 말풍선: 좌측 (role='SYSTEM')
    if (mounted) {
      setState(() {
        _localMessages.add({'role': 'SYSTEM', 'target': tgt, 'original': org});
      });
      _scrollToCurrent(_localMessages.length - 1);
    }
    await _saveHistoryMessage(tgt, org, 'SYSTEM');

    // 세션 첫 PTT면 Realtime, 이후 상대 발화는 기존 nova TTS-1로 재생한다.
    _rememberGenerated(tgt);
    _rememberGenerated(org);
    if (_isConversationActive && !_isExiting) {
      await _playDuoResolvedTurn(
        resolved,
        fallbackVoice: 'nova',
      );
    }
    // 🆕 [PTT] 상대 발화 재생 후에도 자동 재녹음 금지 — 쿨다운 후 대기 복귀
    _setDuoState('cooldown');
    await Future.delayed(const Duration(milliseconds: 800));
    _setDuoState('idle');
  }

// ============================================================================
  // 📦 [6. 데이터베이스 및 스크롤 관리 (DB & SCROLL)]
  // 히스토리 저장 및 화면 상단 고정 제어
  // ============================================================================
  // 최신 메시지(position 0 = 하단)로 스크롤
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  // 250ms throttle — 연속 setState 중 스크롤 남발 방지 (Roleplay 이식)
  void _scrollToBottomThrottled() {
    final now = DateTime.now();
    if (_lastScrollThrottle == null ||
        now.difference(_lastScrollThrottle!) >=
            const Duration(milliseconds: 250)) {
      _lastScrollThrottle = now;
      _scrollToBottom();
    }
  }

  // 현재 말풍선을 화면 중앙에 고정 — 상대 응답 추가 시 사용 (Roleplay 이식)
  void _scrollToCurrent(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final key = _itemKeys[index];
      if (key == null) return;
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  // 현재 말풍선을 화면 상단에 고정 — 내 발화 추가 시 사용 (Roleplay 이식)
  // reversed list에서 alignment 0.98 = 화면 상단 2%
  void _scrollToCurrentTop(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[index];
      if (key == null) return;
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.98,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  // 🆕 [토글] 마이크 버튼: idle이면 시작 / recording이면 종료·전송
  void _onMicToggle() {
    if (!_isConversationActive) {
      setState(() => _isConversationActive = true);
    }
    // 직접 대화의 마이크 버튼은 통화 시작/종료 토글이다. PTT가 아니다.
    if (_isDirectMode) {
      _onDirectMicToggle();
      return;
    }
    if (_duoState == 'idle') {
      _startWhisperRecording(); // 꺼짐 -> 켜기
    } else if (_duoState == 'recording') {
      _silenceTimer?.cancel();
      _stopAndSendToWhisper(); // 켜짐 -> 끄고 전송
    }
    // processing/playing/cooldown 중에는 무시
  }

  // 🆕 [토글] 버튼 상태별 표시 문구
  String _pttLabel() {
    if (_isDirectMode) {
      if (!_directCallActive) return 'Tap to call';
      if (!_relayConnected || !_micActive) return 'Connecting…';
      if (!_partnerRelayConnected) return 'Waiting…';
      // 전사가 끊겨도 통화는 계속된다. 그 사실을 화면에서 구분할 수 있게 둔다.
      return _sttActive ? 'Live' : 'Live (no record)';
    }
    switch (_duoState) {
      case 'recording':
        return '';
      case 'finishing':
        return '';
      case 'processing':
        return 'Processing…';
      case 'playing':
        return 'Playing…';
      case 'cooldown':
        return '…';
      default:
        return 'Tap to talk';
    }
  }

  void _showFontSizeDialog() {
    double tempScale = _fontScale;
    showDialog(
      context: context,
      barrierColor: Colors.black38,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('글자 크기',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Slider(
            value: tempScale,
            min: 0.8,
            max: 1.5,
            divisions: 7,
            label: '${(tempScale * 100).round()}%',
            activeColor: const Color(0xFF2563EB),
            onChanged: (v) {
              setS(() => tempScale = v);
              setState(() => _fontScale = v);
            },
          ),
          contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('확인', style: TextStyle(color: Color(0xFF2563EB))),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _ensureHistoryRef() async {
    final user = FirebaseAuth.instance.currentUser;
    if (_myHistoryRef == null && user != null) {
      _myHistoryRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('chat_history')
          .doc();
      await _myHistoryRef!.set({
        'created_at': FieldValue.serverTimestamp(),
        'last_active': FieldValue.serverTimestamp(),
        'last_message_time': FieldValue.serverTimestamp(),
        'room_name': "Duo Connect Mode",
        'is_pinned': false,
        'msg_count': 0,
        // 세션 생성 당시 언어 식별값 보존(History 동일 언어 판정용)
        'native_lang': FFAppState().nativeLang,
        'target_lang': FFAppState().targetLang,
      });
      BillingTicker.instance.setSessionIdentifiers(
        sessionDocId: _myHistoryRef?.id,
        roomId: _duoSessionRef?.id ?? widget.roomId ?? _pendingJoinRoomId,
      );
    }
  }

  /// 히스토리 메시지 한 줄.
  ///
  /// **만능 통역**은 대화 중에 이미 타겟 문장을 만들었으므로 그대로 저장한다.
  /// **직접 대화**는 번역을 하지 않는다. 전사한 원문만 `original_text`로 남기고
  /// `translated_text`는 비워 둔다 — 나머지 세 모드와 같은 방식으로, 히스토리를
  /// 열 때 그 방의 `target_lang`으로 타겟 문장과 소리가 1차 생성·캐싱된다.
  /// (chat_history_master의 `_scheduleMissingTargetGeneration`이 받는다)
  Future<void> _saveHistoryMessage(
    String target,
    String original,
    String role, {
    String? mode,
    int? seq,
    DateTime? spokenAt,
    String? speakerUid,
    String? sourceLang,
  }) async {
    final bool deferTarget = mode == kDuoModeDirect;
    // 직접 대화는 타겟이 비어 있는 게 정상이다. 통역은 타겟이 본문이라 없으면 버린다.
    if (deferTarget ? original.trim().isEmpty : target.trim().isEmpty) return;
    // 방을 나간 뒤 늦게 도착한 전사가 지워진 히스토리를 되살리지 않게 막는다.
    if (_isExiting) {
      _lgDuo('[HISTORY]', 'save_skipped reason=exiting role=$role');
      return;
    }
    await _ensureHistoryRef();
    if (_myHistoryRef == null) return;
    try {
      await _myHistoryRef!.collection('messages').add({
        'role': role,
        'translated_text': deferTarget ? '' : target,
        'original_text': deferTarget
            ? original
            : ((FFAppState().nativeLang.isNotEmpty &&
                    FFAppState().nativeLang == FFAppState().targetLang)
                ? ''
                : original),
        'created_at': FieldValue.serverTimestamp(),
        // ↓ 직접 대화에서만 붙는 필드. 기존 문서 모양은 그대로다.
        if (mode != null) 'duo_mode': mode,
        if (seq != null) 'speaker_seq': seq,
        if (spokenAt != null) 'spoken_at_ms': spokenAt.millisecondsSinceEpoch,
        if (speakerUid != null && speakerUid.isNotEmpty)
          'speaker_uid': speakerUid,
        // 발화자마다 말한 언어가 다르다(내 ORIGIN ≠ 상대 ORIGIN). 나중에
        // 타겟을 만들 때 출발 언어를 추측하지 않도록 줄마다 남긴다.
        if (sourceLang != null && sourceLang.isNotEmpty)
          'source_lang': sourceLang,
      });
      _historyMessageCount++;
      await _myHistoryRef!.update({
        'last_message': deferTarget ? original : target,
        'last_active': FieldValue.serverTimestamp(),
        'last_message_time': FieldValue.serverTimestamp(),
        'msg_count': FieldValue.increment(1),
      });
    } catch (e) {}
  }

  Future<void> _shareInviteCode() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // 🆕 [모드 결정권] 대화 방식은 **초대를 만드는 호스트가 세션당 한 번** 정한다.
    //    고른 값은 세션 문서의 `mode` 필드로 들어가고, 그 문서가 모드의 유일한
    //    기준이 된다(딥링크 파라미터는 기준이 아니다).
    //
    // ⚠️ 세션이 살아 있는 동안에는 방식을 바꾸지 않는다. 바꾸려면 방을 나가
    //    새 초대를 만들어야 한다 — 통화 도중 모드가 갈리면 두 사람의 오디오
    //    경로가 어긋나기 때문이다. 그래서 재초대(같은 방에 링크를 다시 공유)
    //    에서는 선택 창을 띄우지 않는다.
    final bool isNewSession = _duoSessionRef == null;
    String chosenMode = _duoMode;
    if (isNewSession) {
      final String? picked = await _showHostModePicker();
      if (picked == null) return; // 사용자가 취소
      chosenMode = picked;
      if (mounted) setState(() => _duoMode = picked);
    }
    try {
      // 1) 세션이 없으면 생성 — `mode`는 **이 순간에만** 쓰인다.
      if (isNewSession) {
        _duoSessionRef =
            FirebaseFirestore.instance.collection('duo_sessions').doc();
        await _duoSessionRef!.set({
          'hostUid': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
          'isDuoEnabled': false,
          'isPartnerJoined': false,
          'mode': chosenMode,
        });
      } else {
        // 같은 방에 다시 초대: 저장된 모드를 그대로 따른다(덮어쓰지 않는다).
        try {
          final snap = await _duoSessionRef!.get();
          chosenMode = _normalizeDuoMode(
              (snap.data() as Map<String, dynamic>?)?['mode']);
          if (mounted && chosenMode != _duoMode) {
            setState(() => _duoMode = chosenMode);
          }
        } catch (e) {
          _lgDuo('[MODE]', 'reinvite_mode_read_failed(${e.runtimeType})');
        }
      }
      // 역할은 여기서 바꾸지 않는다. 이 버튼은 호스트에게만 보이고, 호스트는
      // 방 진입 시점부터 이미 _amIHost=true다. UI 액션으로 역할이 승격되는
      // 경로를 남겨 두면 게스트가 호스트로 뒤집힐 수 있다.
      _myUid = user.uid;
      // 2) listener 항상 재등록 (cancel 후 재등록으로 중복 구독 방지)
      _listenForPartnerJoined();
      _listenForMessages(); // 🆕 공유 메시지 채널 리스너 시작
      // 3) 세션 활성화 — `mode`는 건드리지 않는다(생성 시 값이 끝까지 간다).
      await _duoSessionRef!.update({
        'isDuoEnabled': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // 4) OneLink URL 생성 (roomId 정상 주입)
      final String _roomId = _duoSessionRef!.id;
      BillingTicker.instance.setSessionIdentifiers(
        sessionDocId: _myHistoryRef?.id,
        roomId: _roomId,
      );
      final Map<String, String> _params = {
        'deep_link_value': 'duo_chat',
        'invite_type': 'duo',
        'entry_mode': 'guest',
        'room_id': _roomId,
        'duo_room_id': _roomId,
        'deep_link_sub1': user.uid,
        'deep_link_sub2': _roomId,
        'inviter_id': user.uid,
        'af_dp': 'stealthvox://duo',
        'af_force_deeplink': 'true',
        'pid': 'friend_invite',
        'c': 'in_app_share',
      };
      debugPrint('[Duo] inviteLink roomId: $_roomId');
      final String inviteLink =
          Uri.parse('https://stealthvox.onelink.me/31o1/fipsp75p')
              .replace(queryParameters: _params)
              .toString();
      debugPrint('[Duo] inviteLink: $inviteLink');
      // 5) 클립보드 복사 + 공유 시트
      await Clipboard.setData(ClipboardData(text: inviteLink));
      await Share.share(
        '저와 함께 Duo 대화 연습해요! 👉 $inviteLink',
        subject: 'StealthVox Duo 초대',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_modeTitle(chosenMode)}로 초대했습니다. 링크가 복사되었습니다.'),
          backgroundColor: const Color(0xFF2563EB),
          duration: const Duration(seconds: 3),
        ));
      }
    } catch (e) {
      debugPrint('[Duo] Share invite error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('초대 링크 발행에 실패했습니다. 다시 시도해주세요.')));
      }
    }
  }

  Future<void> _joinAsGuest(String roomId) async {
    // 초대 상태는 여기서 지우지 않음 — Firestore 업데이트 성공 후에만 삭제
    try {
      _duoSessionRef =
          FirebaseFirestore.instance.collection('duo_sessions').doc(roomId);
      final snap = await _duoSessionRef!.get();
      if (!snap.exists) {
        debugPrint('[Duo] _joinAsGuest: session not found ($roomId)');
        if (FFAppState().duoRoomId == roomId) {
          AppsFlyerManager.clearPendingDuoInvite();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('초대된 방을 찾을 수 없습니다.')),
          );
          StealthRoomMaster.exitCurrentMode?.call();
        }
        return;
      }
      final data = snap.data() as Map<String, dynamic>?;
      if (data == null || data['isDuoEnabled'] != true) {
        debugPrint('[Duo] _joinAsGuest: isDuoEnabled is not true ($roomId)');
        if (FFAppState().duoRoomId == roomId) {
          AppsFlyerManager.clearPendingDuoInvite();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이 방은 현재 사용할 수 없습니다.')),
          );
          StealthRoomMaster.exitCurrentMode?.call();
        }
        return;
      }

      final String? firebaseUid = FirebaseAuth.instance.currentUser?.uid;
      final String guestUid =
          firebaseUid ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';

      // 🆕 게스트 식별 확정
      _amIHost = false;
      _myUid = guestUid;
      BillingTicker.instance.setSessionIdentifiers(
        sessionDocId: _myHistoryRef?.id,
        roomId: roomId,
      );

      // 🆕 대화 방식의 최종값은 **방 문서**다. 게스트는 쓰지 않고 읽기만 한다.
      //    (딥링크 파라미터가 유실·변조돼도 여기서 바로잡힌다)
      final String sessionMode = _normalizeDuoMode(data['mode']);
      if (sessionMode != _duoMode) {
        _lgDuo('[MODE]', 'guest_sync $_duoMode → $sessionMode');
      }
      _duoMode = sessionMode;

      await _duoSessionRef!.update({
        'isPartnerJoined': true,
        'partnerUid': guestUid,
        'partnerJoinedAt': FieldValue.serverTimestamp(),
      });
      await AppsFlyerManager.markDuoInviteCompleted(roomId);

      // 입장 성공 후 방 초대 정보만 정리한다. isGuestSession은 대화 종료 뒤에도
      // Intro 복귀를 강제하는 세션 경계이므로 사용자가 Intro에서 새 흐름을
      // 시작할 때까지 유지한다.
      FFAppState().duoRoomId = '';
      FFAppState().pendingInviteType = '';
      debugPrint(
          '[AppState] duo invite room state cleared; guest session kept');

      debugPrint(
          '[Duo] _joinAsGuest success — guestUid: $guestUid, roomId: $roomId');

      // 🆕 공유 메시지 채널 리스너 시작 (게스트도 상대=호스트 발화 수신)
      _listenForMessages();

      if (mounted) {
        setState(() {
          _isConversationActive = true;
          _isPartnerOnline = true;
        });
      }
      // 🆕 [과금정책] 게스트 본인 입장 성공 — 과금은 호스트 리스너에서만 시작
      // 🆕 [PTT] 세션만 열고 녹음은 버튼으로 시작 — 자동 녹음 제거
    } catch (e) {
      debugPrint('[Duo] Guest join error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('연결 중 오류가 발생했습니다. 다시 시도해주세요.')),
        );
        StealthRoomMaster.exitCurrentMode?.call();
      }
    }
  }

  void _listenForPartnerJoined() {
    if (_duoSessionRef == null) return;
    _partnerJoinedSubscription?.cancel();
    _partnerJoinedSubscription = _duoSessionRef!.snapshots().listen((snap) {
      if (_isExiting || !mounted) return;

      // 세션 문서가 삭제된 경우 (호스트가 먼저 나가 세션 delete됨)
      if (!snap.exists) {
        _handleAutoSaveAndExit();
        return;
      }

      final data = snap.data() as Map<String, dynamic>?;
      if (data == null) return;
      final bool partnerJoined = data['isPartnerJoined'] == true;

      // 🛡️ [방어 전용] 정상 UX에서는 세션 도중 mode가 바뀌지 않는다 —
      //    방식은 초대를 만들 때 한 번 정해지고, 바꾸려면 방을 나가 새 초대를
      //    만들어야 한다. 그래도 문서가 밖에서(콘솔·다른 기기·이상 동작)
      //    바뀌면 문서 값을 따르고 직전 모드의 오디오 경로를 즉시 끊는다.
      final String sessionMode = _normalizeDuoMode(data['mode']);
      if (sessionMode != _duoMode) {
        _lgDuo('[MODE]',
            '⚠️ unexpected_session_mode_change $_duoMode → $sessionMode');
        unawaited(_stopDirectCall('mode_changed'));
        if (mounted) setState(() => _duoMode = sessionMode);
      }
      debugPrint(
          '[Duo][Billing] partnerJoined=$partnerJoined amIHost=$_amIHost '
          'paused=${BillingTicker.instance.isPaused} '
          'billingState=${BillingTicker.instance.billingState.value} '
          'billingStarted=$_billingStarted');

      // 게스트 퇴장 감지: _isPartnerOnline이 true → false로 떨어지는 순간
      final bool guestJustLeft = _isPartnerOnline && !partnerJoined;

      final bool shouldStartRecording = partnerJoined && !_isConversationActive;
      if (mounted) {
        setState(() {
          _isPartnerOnline = partnerJoined;
          if (shouldStartRecording) _isConversationActive = true;
        });
        // 🆕 [과금정책] 게스트 입장 확정 시 과금 시작 / 퇴장 시 정지
        if (partnerJoined) {
          _startDuoBilling();
        } else {
          _stopDuoBilling();
        }
        // 🆕 [PTT] 입장 시 자동 녹음 제거 — 버튼으로만 시작
        // 게스트 퇴장 → 호스트 강제 종료 (1:1 대칭 종료 모델)
        if (guestJustLeft) _handleAutoSaveAndExit();
      }
    });
  }

  Future<void> _handleAutoSaveAndExit() async {
    if (_isExiting) return;
    _isExiting = true;
    final bool isInviteGuest = FFAppState().isGuestSession;
    final String? guestRoomId = _duoSessionRef?.id ??
        widget.roomId ??
        _pendingJoinRoomId ??
        (FFAppState().duoRoomId.isNotEmpty ? FFAppState().duoRoomId : null);
    if (isInviteGuest) {
      await AppsFlyerManager.markDuoInviteCompleted(guestRoomId);
    }
    _stopDuoBilling();

    // listener 즉시 해제 — 본인의 Firestore 업데이트가 listener를 재트리거하지 않도록
    _partnerJoinedSubscription?.cancel();
    _partnerJoinedSubscription = null;
    _messageSubscription?.cancel(); // 🆕 메시지 채널 구독도 해제
    _messageSubscription = null;

    // 🆕 [직접 대화] 방을 나가는 순간 PCM 송수신을 먼저 끊는다. 이 뒤에 도착하는
    //    릴레이 프레임·전사 완료는 세대값이 달라 전부 무시된다.
    await _stopDirectCall('room_exit');

    _cancelAudio();
    _silenceTimer?.cancel();
    if (mounted) setState(() => _isConversationActive = false);

    // 호스트/게스트 분기: duo_sessions 처리
    if (_duoSessionRef != null) {
      try {
        final snap = await _duoSessionRef!.get();
        if (snap.exists) {
          final data = snap.data() as Map<String, dynamic>?;
          final String? hostUid = data?['hostUid']?.toString();
          final String? myUid = FirebaseAuth.instance.currentUser?.uid;
          if (hostUid != null && myUid != null && hostUid == myUid) {
            // 호스트: 세션 삭제 (1:1 대칭 종료)
            await _duoSessionRef!.delete();
          } else {
            // 게스트: isPartnerJoined=false 업데이트
            await _duoSessionRef!.update({
              'isPartnerJoined': false,
              'partnerLeftAt': FieldValue.serverTimestamp(),
            });
          }
        }
      } catch (e) {
        debugPrint('[Duo] session cleanup error: $e');
      }
    }

    if (_myHistoryRef != null) {
      // 직접 대화는 말풍선을 만들지 않으므로 _localMessages가 늘 비어 있다.
      // 실제로 저장한 메시지 수로 판단해야 히스토리가 통째로 지워지지 않는다.
      if (_localMessages.isEmpty && _historyMessageCount == 0) {
        await _myHistoryRef!.delete();
      } else {
        String lastText = _localMessages.isNotEmpty
            ? (_localMessages.last['target']?.toString() ?? "대화 기록 저장")
            : "대화 기록 저장";
        await _myHistoryRef!.update({
          'last_message': lastText.isNotEmpty ? lastText : "대화 기록 저장",
          'last_message_time': FieldValue.serverTimestamp(),
          'last_active': FieldValue.serverTimestamp()
        });
      }
    }
    if (mounted) {
      if (isInviteGuest) {
        // 게스트에게 StealthRoom 메뉴를 노출하지 않고 라우트 스택을 Intro로
        // 교체한다. 로그인 상태는 유지하되 자동 Lobby 진입만 차단한다.
        FFAppState().inviterUid = '';
        FFAppState().duoRoomId = '';
        FFAppState().pendingInviteType = '';
        FFAppState().update(() {});
        context.goNamed('Intro');
      } else if (StealthRoomMaster.exitCurrentMode != null) {
        StealthRoomMaster.exitCurrentMode!();
      } else if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        context.goNamed('Lobby');
      }
    }
  }

  // ============================================================================
  // 📦 [7. UI 빌더 (UI BUILDERS)]
  // 화면 레이아웃 (TopBar, ControlArea, TextBlock)
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    final effectiveBottomPadding =
        MediaQuery.of(context).viewPadding.bottom == 0
            ? 24.0
            : MediaQuery.of(context).viewPadding.bottom + 8.0;

    return PopScope(
        canPop: false,
        onPopInvoked: (didPop) async {
          if (didPop) return;
          await _handleAutoSaveAndExit();
        },
        child: Stack(children: [
          Container(
            width: widget.width,
            height: widget.height,
            color: const Color(0xFF121212),
            child: SafeArea(
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: Stack(children: [
                      // 직접 대화는 실시간 자막을 만들지 않는다. 화면은 통화
                      // 상태만 보여주고, 전사문은 뒤에서 History로만 간다.
                      _isDirectMode || _localMessages.isEmpty
                          ? Center(
                              child: Text(
                                  _isDirectMode
                                      ? "마이크를 탭하면 통화가 시작됩니다.\n서로의 실제 목소리로 대화하세요."
                                      : "마이크를 탭하면 시작됩니다.\n말이 끝나면 자동으로 전송됩니다.",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.white54, height: 1.5)))
                          : ListView.builder(
                              reverse: true,
                              controller: _scrollController,
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.only(
                                  left: 8,
                                  right: 8,
                                  top: MediaQuery.of(context).size.height * 0.4,
                                  bottom: 40),
                              itemCount: _localMessages.length,
                              itemBuilder: (context, index) {
                                final realIdx =
                                    _localMessages.length - 1 - index;
                                if (!_itemKeys.containsKey(realIdx))
                                  _itemKeys[realIdx] = GlobalKey();
                                return Container(
                                  key: _itemKeys[realIdx],
                                  child:
                                      _buildTextBlock(_localMessages[realIdx]),
                                );
                              }),
                    ]),
                  ),
                  _buildControlArea(effectiveBottomPadding),
                ],
              ),
            ),
          ),
          if (_showLangOverlay) _buildGuestLangOverlay(),
        ]));
  }

  static String _modeTitle(String mode) =>
      mode == kDuoModeDirect ? '직접 대화' : '만능 통역';

  static String _modeDesc(String mode) => mode == kDuoModeDirect
      ? '서로의 실제 목소리로 통화합니다.'
      : '상대의 말을 통역 음성으로 들려줍니다.';

  /// 🆕 [모드 선택 — 호스트 전용] 초대장을 만들기 직전에 뜬다.
  /// 여기서 고른 값만이 세션 문서의 `mode`가 된다.
  Future<String?> _showHostModePicker() {
    String picked = _duoMode;
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Widget tile(String mode) {
          final bool selected = picked == mode;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setS(() => picked = mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF2563EB).withValues(alpha: 0.18)
                    : Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: selected ? const Color(0xFF2563EB) : Colors.white24,
                    width: selected ? 1.6 : 1.0),
              ),
              child: Row(children: [
                Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 20,
                    color: selected
                        ? const Color(0xFF60A5FA)
                        : Colors.white38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_modeTitle(mode),
                          style: TextStyle(
                              color: selected ? Colors.white : Colors.white70,
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 3),
                      Text(_modeDesc(mode),
                          style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                              height: 1.3)),
                    ],
                  ),
                ),
              ]),
            ),
          );
        }

        return AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF2563EB), width: 1.2)),
          title: const Text('대화 방식 선택',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            tile(kDuoModeDirect),
            tile(kDuoModeInterpreter),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('상대는 이 방식으로 초대됩니다.',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('취소', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(ctx, picked),
              child: const Text('초대하기',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      }),
    );
  }

  /// 🆕 [모드 표시 — 게스트 전용] 호스트가 정한 방식을 **읽기 전용**으로 보여준다.
  /// 게스트는 이 값을 바꿀 수 없다. 언어만 고른다.
  Widget _buildInvitedModeBadge() {
    final bool loading = _pendingModeLoading;
    final bool direct = _duoMode == kDuoModeDirect;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2563EB), width: 1.2),
      ),
      child: Row(children: [
        Icon(direct ? Icons.record_voice_over : Icons.translate,
            size: 20, color: const Color(0xFF93C5FD)),
        const SizedBox(width: 12),
        Expanded(
          child: loading
              ? const Text('초대 방식 확인 중…',
                  style: TextStyle(color: Colors.white54, fontSize: 13))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_modeTitle(_duoMode)} 초대',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Text(_modeDesc(_duoMode),
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12, height: 1.3)),
                  ],
                ),
        ),
      ]),
    );
  }

  // 🆕 [게스트 언어 오버레이] 초대 게스트 입장 전 ORIGIN/TARGET 선택 게이트
  Widget _buildGuestLangOverlay() {
    const List<String> langs = [
      'English',
      'Japanese',
      'Chinese',
      'Spanish',
      'French',
      'German',
      'Korean',
      'Hindi',
      'Russian',
      'Portuguese',
      'Italian',
      'Dutch'
    ];
    String native = langs.contains(FFAppState().nativeLang)
        ? FFAppState().nativeLang
        : 'Korean';
    String target = langs.contains(FFAppState().targetLang)
        ? FFAppState().targetLang
        : 'English';

    Widget dropdown(String label, String value, Color labelColor,
        ValueChanged<String?> onChanged,
        {String? subtitle, bool subtitleBelow = false}) {
      Widget labelWidget;
      if (subtitle != null && !subtitleBelow) {
        labelWidget = Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(label,
                  style: TextStyle(
                      color: labelColor,
                      fontSize: 12,
                      letterSpacing: 1,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Text(subtitle,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
            ]);
      } else if (subtitle != null && subtitleBelow) {
        labelWidget =
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  color: labelColor,
                  fontSize: 12,
                  letterSpacing: 1,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 10, letterSpacing: 0.3)),
        ]);
      } else {
        labelWidget = Text(label,
            style: TextStyle(
                color: labelColor,
                fontSize: 12,
                letterSpacing: 1,
                fontWeight: FontWeight.bold));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          labelWidget,
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: value,
                dropdownColor: const Color(0xFF1E1E1E),
                icon: const Icon(Icons.unfold_more_rounded,
                    color: Colors.white54, size: 20),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
                items: langs
                    .map((l) =>
                        DropdownMenuItem<String>(value: l, child: Text(l)))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      );
    }

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.78),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: const Color(0xFF2563EB), width: 1.5)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("대화 언어 설정",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text("초대받은 대화 방식을 확인하고 언어를 선택하세요.",
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                  const SizedBox(height: 20),
                  _buildInvitedModeBadge(),
                  const SizedBox(height: 22),
                  dropdown("ORIGIN", native, const Color(0xFF93C5FD), (val) {
                    if (val != null)
                      setState(() => FFAppState().nativeLang = val);
                  }, subtitle: "(My Language)", subtitleBelow: false),
                  const SizedBox(height: 18),
                  dropdown("TARGET", target, const Color(0xFF4ADE80), (val) {
                    if (val != null)
                      setState(() => FFAppState().targetLang = val);
                  },
                      subtitle: "(Listening Language or Learning Language)",
                      subtitleBelow: true),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    onPressed: () {
                      final String? roomId = _pendingJoinRoomId;
                      setState(() {
                        _showLangOverlay = false;
                        _pendingJoinRoomId = null;
                      });
                      if (roomId != null && roomId.isNotEmpty) {
                        _joinAsGuest(roomId);
                      }
                    },
                    child: const Text("입장하기",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPartnerIndicator() {
    if (!_isPartnerOnline) return const SizedBox.shrink();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.person, color: Colors.white70, size: 20),
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF34D399),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white70),
                  tooltip: '이전 단계',
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  constraints:
                      const BoxConstraints(minWidth: 56, minHeight: 56),
                  onPressed: _handleAutoSaveAndExit),
              // 초대는 방을 만든 호스트만 낼 수 있다. 게스트에게는 버튼 자체를
              // 노출하지 않는다 — 눌러서 역할이 뒤집히는 경로를 없앤다.
              if (_amIHost)
                IconButton(
                  icon: const Icon(Icons.person_add_alt_1,
                      color: Colors.white70, size: 22),
                  tooltip: 'Duo 초대장 발행',
                  onPressed: _shareInviteCode,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              _buildPartnerIndicator(),
            ],
          ),
          const Spacer(),
          Row(children: [
            IconButton(
              icon: const Icon(Icons.format_size,
                  color: Colors.white70, size: 26),
              tooltip: '글자 크기 조절',
              onPressed: _showFontSizeDialog,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            IconButton(
              icon: CustomPaint(
                size: const Size(26, 26),
                painter: _LangIconPainter(active: _showOriginal),
              ),
              tooltip: _showOriginal ? '원어 숨기기' : '원어 보기',
              onPressed: () => setState(() => _showOriginal = !_showOriginal),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ]),
          const SizedBox(width: 4),
          ValueListenableBuilder<int>(
              valueListenable: BillingTicker.instance.remainingSecondsNotifier,
              builder: (context, remaining, child) {
                return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        borderRadius: BorderRadius.circular(20)),
                    child: Row(children: [
                      ValueListenableBuilder<int>(
                        valueListenable: BillingTicker.instance.billingState,
                        builder: (_, s, __) => CustomPaint(
                          size: const Size(14, 14),
                          painter: BillingDotPainter(s),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(() {
                        final int s = remaining.clamp(0, 999999);
                        final int h = s ~/ 3600;
                        final int m = (s % 3600) ~/ 60;
                        return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
                      }(),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold))
                    ]));
              }),
        ],
      ),
    );
  }

  Widget _buildControlArea(double bottomPadding) {
    // 직접 대화: 통화 중이면 마이크가 계속 켜져 있다(초록). 탭하면 끊는다.
    final bool isRec =
        _isDirectMode ? _directCallActive : _duoState == 'recording';
    final bool isFinishing = !_isDirectMode && _duoState == 'finishing';
    final bool isBusy = _isDirectMode
        ? _directStarting
        : (isFinishing ||
            _duoState == 'processing' ||
            _duoState == 'playing' ||
            _duoState == 'cooldown');
    final Color accent = isRec
        ? const Color(0xFF34D399)
        : (isBusy ? Colors.white38 : const Color(0xFF2563EB));
    return Container(
      padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPadding),
      decoration: const BoxDecoration(color: Color(0xFF121212)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (!isRec || _isDirectMode)
            Text(_pttLabel(),
                style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0))
          else
            const SizedBox.shrink(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            // [토글] 처리·재생·쿨다운 중에는 탭 무시
            onTap: isBusy ? null : _onMicToggle,
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: isRec ? 76 : 72,
                height: isRec ? 76 : 72,
                decoration: BoxDecoration(
                    // 녹음 중에는 초록 마이크와 은은한 활성 링으로 표시한다.
                    color: isRec
                        ? accent.withValues(alpha: 0.16)
                        : accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: accent, width: isRec ? 3.0 : 2.0),
                    boxShadow: isRec
                        ? [
                            BoxShadow(
                                color: accent.withValues(alpha: 0.28),
                                blurRadius: 20,
                                spreadRadius: 4)
                          ]
                        : null),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: Icon(
                    isRec
                        ? Icons.mic_rounded
                        : (isFinishing
                            ? Icons.mic_off_rounded
                            : Icons.mic_none_rounded),
                    key: ValueKey<String>(_duoState),
                    color: accent,
                    size: isRec ? 40 : 36,
                  ),
                )),
          ),
        ],
      ),
    );
  }

  Widget _buildTextBlock(Map<String, dynamic> msg) {
    String target = msg['target']?.toString() ?? '';
    String original = msg['original']?.toString() ?? '';
    bool isHost = msg['role'] == 'HOST'; // 'HOST'=내 말(우측) / 그 외=상대 말(좌측)

    if (target.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: isHost ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isHost
              ? const Color(0xFF2C2C2E)
              : const Color(0xFF2563EB).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        child: Column(
            crossAxisAlignment:
                isHost ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(target,
                  textAlign: isHost ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                      color: isHost ? Colors.white : const Color(0xFF93C5FD),
                      fontSize: 16 * _fontScale,
                      fontWeight: FontWeight.w600,
                      height: 1.3)),
              if (_showOriginal &&
                  !(FFAppState().nativeLang.isNotEmpty &&
                      FFAppState().nativeLang == FFAppState().targetLang) &&
                  original.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(original,
                    textAlign: isHost ? TextAlign.right : TextAlign.left,
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14 * _fontScale,
                        height: 1.3))
              ]
            ]),
      ),
    );
  }
}

class _DuoResolvedTurn {
  const _DuoResolvedTurn({
    required this.target,
    required this.original,
    required this.realtimeSession,
    required this.realtimeWav,
    required this.streamed,
    required this.generation,
  });

  final String target;
  final String original;
  final FirstTurnRealtimeVoice? realtimeSession;
  final Uint8List? realtimeWav;
  final bool streamed;
  final int generation;
}

// ============================================================================
// 📦 [Box 7-1: 듀오 전용 AI 뇌 (DuoBrain)]
// 통역 전용 클래스 — 원문 1개를 받아 [내 타겟 + 내 오리지널] 동시 생성 (단일 GPT 호출)
// ⚠️ 절대 대화에 끼어들지 않음. 오직 번역만 수행 (양방향 통역폰 규칙).
// ============================================================================
class DuoBrain {
  static final http.Client client = http.Client();

  static Future<Map<String, String>?> processTranslation({
    required String key,
    required String text,
    required String srcLang,
    required String myTargetLang,
    required String myNativeLang,
  }) async {
    try {
      Uri uri = Uri.parse('https://api.openai.com/v1/chat/completions');

      String prompt =
          "You are a translation engine for a live interpreter app.\n"
          "You receive ONE utterance and render it into TWO languages.\n"
          "You are NOT a chat assistant. NEVER reply, comment, answer, or ask questions.\n"
          "NEVER continue the conversation. Translate the utterance only.\n\n"
          "Utterance language: $srcLang\n"
          "Output A (target): $myTargetLang\n"
          "Output B (native): $myNativeLang\n\n"
          "Rules:\n"
          "1. \"target\" = the utterance translated into $myTargetLang.\n"
          "2. \"original\" = the utterance translated into $myNativeLang.\n"
          "3. If the utterance is already in one of these languages, just clean it up (fix spacing/typos) for that field.\n"
          "4. Preserve tone, intent, names, and numbers exactly. Do not add or remove meaning.\n"
          "5. If the utterance is unclear or empty, output an empty string for both fields. Never invent content.\n"
          "6. Output strict JSON only, nothing else.\n\n"
          "Output format:\n"
          "{\n"
          "  \"target\": \"<utterance in $myTargetLang>\",\n"
          "  \"original\": \"<utterance in $myNativeLang>\"\n"
          "}\n\n"
          "Utterance: \"$text\"";

      var res = await client
          .post(uri,
              headers: {
                'Authorization': 'Bearer $key',
                'Content-Type': 'application/json; charset=utf-8'
              },
              body: jsonEncode({
                'model': 'gpt-4o-mini',
                'temperature': 0.2,
                'max_tokens': 400,
                'response_format': {'type': 'json_object'},
                'messages': [
                  {'role': 'user', 'content': prompt}
                ]
              }))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        String cleanJson = _cleanJsonString(
            jsonDecode(utf8.decode(res.bodyBytes))['choices'][0]['message']
                ['content']);
        var parsed = jsonDecode(cleanJson);
        return {
          'target': parsed['target']?.toString() ?? "",
          'original': parsed['original']?.toString() ?? "",
        };
      }
    } catch (e) {
      print("DuoBrain Error: $e");
    }
    return null;
  }

  static String _cleanJsonString(String text) {
    String clean = text.trim();
    if (clean.startsWith('```json')) {
      clean = clean.substring(7);
    } else if (clean.startsWith('```')) {
      clean = clean.substring(3);
    }
    if (clean.endsWith('```')) {
      clean = clean.substring(0, clean.length - 3);
    }
    return clean.trim();
  }
}

class _LangIconPainter extends CustomPainter {
  final bool active;
  const _LangIconPainter({required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);

    canvas
        .clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: r)));

    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()
          ..color = active ? const Color(0xFF1E7DB5) : const Color(0xFF2A2A2A));

    if (active) {
      canvas.drawPath(
        Path()
          ..moveTo(size.width * 0.05, size.height)
          ..lineTo(size.width, size.height * 0.05)
          ..lineTo(size.width, size.height)
          ..close(),
        Paint()..color = const Color(0xFF0B4870),
      );
    }

    canvas.drawLine(
      Offset(size.width * 0.04, size.height * 0.96),
      Offset(size.width * 0.96, size.height * 0.04),
      Paint()
        ..color = active ? const Color(0xFFD4AF37) : Colors.white12
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(
      center,
      r - 1.5,
      Paint()
        ..color = active ? const Color(0xFFD4AF37) : Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // 상단 좌측 "T" (원어) — 비활성 시 거의 투명
    _drawText(canvas, 'T', Offset(size.width * 0.09, size.height * 0.06),
        size.width * 0.34, active ? Colors.white : const Color(0x22FFFFFF));

    if (active) {
      final dotC = Offset(size.width * 0.63, size.height * 0.23);
      final dotR = size.width * 0.105;
      canvas.drawCircle(dotC, dotR, Paint()..color = const Color(0xFFE03030));
      canvas.drawCircle(
          dotC, dotR * 0.45, Paint()..color = const Color(0xFFFF6060));
      canvas.drawCircle(
          dotC,
          dotR,
          Paint()
            ..color = const Color(0xBBFFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8);
    } else {
      // 원어 숨김 표시 — 소형 X
      final xPaint = Paint()
        ..color = Colors.redAccent.withValues(alpha: 0.65)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(size.width * 0.53, size.height * 0.11),
          Offset(size.width * 0.74, size.height * 0.32), xPaint);
      canvas.drawLine(Offset(size.width * 0.74, size.height * 0.11),
          Offset(size.width * 0.53, size.height * 0.32), xPaint);
    }

    // 하단 우측 "T" (타겟) — 항상 흰색
    _drawText(canvas, 'T', Offset(size.width * 0.55, size.height * 0.58),
        size.width * 0.34, Colors.white);
  }

  void _drawText(
      Canvas canvas, String text, Offset offset, double fontSize, Color color) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              height: 1.0)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_LangIconPainter old) => old.active != active;
}
