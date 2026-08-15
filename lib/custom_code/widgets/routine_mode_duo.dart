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
import '/custom_code/actions/billing_idle_mixin.dart';
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

/// 종료 직전 마지막 전사문의 History·채널 저장을 기다리는 상한.
/// Firestore 쓰기가 걸려도 통화 종료가 무한정 늘어지면 안 된다.
const Duration kDuoDirectSaveTimeout = Duration(seconds: 3);
const String kDuoModeInterpreter = 'interpreter';
const String kInterpreterPartnerTtsVoice = 'alloy';

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
    with WidgetsBindingObserver, BillingIdleMixin<RoutineModeDuo> {
  // ============================================================================
  // 📦 [1. 상태 변수 (STATE VARIABLES)]
  // 앱의 전반적인 상태, UI 설정, 데이터 보관용 변수 모음
  // ============================================================================
  String _openAiKey = "";
  bool _isConversationActive = false;

  // ── 🆕 [직접 대화] 모드 상태 ─────────────────────────────────────────────
  // 기본값은 **직접 대화**다. 초대 팝업이 이 값으로 열리므로, 호스트가 아무것도
  // 안 고르고 "초대하기"를 누르면 직접 통화로 초대된다. 만능 통역은 팝업에서
  // 골라야 한다.
  //
  // ⚠️ 이건 **화면 기본값**일 뿐이다. 실제 방의 방식은 duo_sessions 문서의
  //   `mode`가 정하고, 그 해석은 `_normalizeDuoMode`가 전담한다 — `mode`가
  //   없는 옛 방은 지금도 만능 통역으로 읽힌다.
  String _duoMode = kDuoModeDirect;
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

  /// 🔇 [DUO-MUTE] 내 소리를 보내지 않는 상태. **연결은 살아 있다** —
  /// 릴레이도 붙어 있고 상대 목소리도 계속 들린다. 마이크 PCM만 버린다.
  bool _directMuted = false;

  /// 🔴 [DUO-LIVE] 자동 연결을 이미 시도한 방인지. 실패한 뒤 스냅샷이 또
  /// 떨어질 때마다 자동으로 재시도하면, 권한을 거부한 유저에게 권한 창이
  /// 반복해서 뜬다. 자동은 한 번만 하고 그 뒤는 버튼(수동)에 맡긴다.
  bool _autoStartAttempted = false;
  DateTime? _directCaptureFirstFrameAt;

  /// 화자별 발화 일련번호와 발화 시작 시각. History 순서 복원용이다.
  int _directSeq = 0;
  DateTime? _directSpeechStartedAt;

  /// 종료 처리가 도는 중. 연속 탭으로 두 번 들어오는 것을 막는다.
  bool _directStopping = false;

  /// 종료 직전 마지막 전사문을 기다리는 창. 이 동안 도착한 전사문은
  /// 세대가 아직 살아 있으므로 정상 경로로 저장된다.
  bool _directFlushing = false;

  /// 아직 안 끝난 History/채널 저장들. 종료 전에 이것들을 기다린다.
  final Set<Future<void>> _directSaves = <Future<void>>{};

  /// 이미 저장한 전사 item. 같은 발화가 두 번 들어와도 한 번만 남긴다.
  final Set<String> _savedDirectItemIds = <String>{};

  /// History에 실제로 쓴 메시지 수. 직접 대화는 말풍선을 만들지 않으므로
  /// `_localMessages`로 저장 여부를 판단하면 히스토리가 통째로 지워진다.
  int _historyMessageCount = 0;

  // 🆕 [게스트 언어 오버레이] 초대 게스트(회원·비회원)가 입장 전 언어쌍 선택
  bool _showLangOverlay = false;
  String? _pendingJoinRoomId;

  /// 게스트 언어 오버레이가 고를 수 있는 언어. 드롭다운 목록이자
  /// 저장값이 유효한지 판정하는 기준이다.
  static const List<String> _kGuestLangs = [
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

  /// 게스트 언어 오버레이를 띄우기 전에 값을 목록 안의 값으로 맞춘다.
  /// **이 폰에 저장된 값이 목록에 있으면 그대로 둔다.** 비어 있거나 목록 밖의
  /// 값일 때만 기본값 — ORIGIN=Korean, TARGET=English — 으로 채운다.
  ///
  /// 화면에만 기본값을 보여 주고 저장값은 옛 값으로 남는 어긋남을 여기서
  /// 없앤다. 게스트가 아무것도 안 건드리고 입장해도 보이는 값과 실제로
  /// 쓰는 값(전사 언어·통역 프롬프트)이 같다.
  void _normalizeGuestLangs() {
    if (!_kGuestLangs.contains(FFAppState().nativeLang)) {
      FFAppState().nativeLang = 'Korean';
    }
    if (!_kGuestLangs.contains(FFAppState().targetLang)) {
      FFAppState().targetLang = 'English';
    }
  }

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
    // 💰 [BILLING-IDLE] 통화가 1분간 조용하면 정지, 다시 말하면 재개.
    //   예전에는 Duo만 유휴 타이머가 없어 켜 둔 채 잊으면 계속 차감됐다.
    resetBillingIdle();
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
    clearBillingIdle();
    BillingTicker.instance.pause();
  }

  // ── 💰 [BILLING-IDLE] Duo의 "대화 중" 판정 ────────────────────────
  // 다른 방과 달리 재생기 상태로는 알 수 없다. 릴레이는 침묵도 계속 보내서
  // "수신 중"이 곧 "대화 중"이 아니기 때문이다. 그래서 **양쪽 목소리를
  // 따로 본다** — 내 말은 Server VAD가, 상대 말은 들어온 PCM의 진폭이 알려
  // 준다. 상대만 말하는 동안 호스트가 유휴로 빠지면, 대화가 이어지는데도
  // 과금이 멈춘다.
  DateTime? _lastPartnerVoiceAt;

  /// 상대 목소리로 볼 최소 진폭(PCM16). 생마이크 노이즈는 이보다 훨씬 작다.
  static const int _kPartnerVoiceThreshold = 1200;

  /// 마지막 목소리 이후 이 시간까지는 "대화 중"으로 본다. 말 사이의 자연스러운
  /// 끊김에서 유휴로 떨어지지 않게 하는 여유다.
  static const Duration _kVoiceActivityWindow = Duration(seconds: 3);

  void _noteInboundAudio(Uint8List pcm) {
    // 16bit little-endian. 두 바이트씩 훑되 전부 볼 필요는 없다 —
    // 매 프레임 수천 샘플이라 띄엄띄엄 봐도 큰 소리는 걸린다.
    for (int i = 0; i + 1 < pcm.length; i += 64) {
      final int v = (pcm[i + 1] << 8) | pcm[i];
      final int sample = v >= 0x8000 ? v - 0x10000 : v;
      if (sample.abs() >= _kPartnerVoiceThreshold) {
        _lastPartnerVoiceAt = DateTime.now();
        return;
      }
    }
  }

  @override
  String get billingModeName => 'duo';

  /// 게스트는 무료다. 초대한 호스트만 부담한다 — 유휴에서 돌아올 때도
  /// 게스트 쪽에서 과금이 켜지면 안 된다.
  @override
  bool get isBillingEnabled => _amIHost;

  @override
  bool get isBillingBusy {
    if (_directStt?.isUserSpeaking == true) return true;
    final at = _lastPartnerVoiceAt;
    if (at != null && DateTime.now().difference(at) < _kVoiceActivityWindow) {
      return true;
    }
    return false;
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
  /// ⚠️ 잠든 경로 전용. 내 발화를 내 목소리로 다시 읽어주던 시절의 값이다.
  /// 상대 발화는 `kInterpreterPartnerTtsVoice`로 읽는다.
  // ignore: unused_element
  String _myVoice() =>
      FFAppState().aiVoice.isNotEmpty ? FFAppState().aiVoice : 'echo';

  FirstTurnRealtimeVoice _createDuoRealtime(String voice) {
    late final FirstTurnRealtimeVoice session;
    session = FirstTurnRealtimeVoice(
      apiKey: _openAiKey,
      voice: voice,
      enableStreamingPlayback: true,
      onStreamingAudioStart: () {
        if (!mounted || _isExiting || !identical(_activeDuoRealtime, session)) {
          return;
        }
        _setDuoState('playing');
        BillingTicker.instance.resumeFromActivity('duo_realtime_audio_start');
      },
      onLog: (tag, message) => debugPrint('[Duo][Realtime] $tag $message'),
    );
    return session;
  }

  /// ⚠️ 잠든 경로. `_resolveDuoTurn` 주석 참고.
  // ignore: unused_element
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

  /// ⚠️ 잠든 경로. `_resolveDuoTurn` 주석 참고.
  // ignore: unused_element
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
        _normalizeGuestLangs();
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
    // 못 읽었을 때 게스트 팝업에 보여 줄 값. 방의 진짜 방식은 아래에서 문서를
    // 읽어 덮어쓰고, 통화를 여는 순간 한 번 더 문서로 확인한다.
    String mode = kDuoModeDirect;
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

  /// 두 사람이 같은 대화 언어를 쓰는가.
  ///
  /// ⚠️ **`_mapLanguageToCode`로 비교하면 안 된다.** 그 함수는 목록에 없는
  /// 언어를 전부 `'en'`으로 떨어뜨린다(위 `default`). 베트남어와 태국어를
  /// 넣으면 둘 다 `'en'`이 나와 "같은 언어"로 판정되고, 번역 없이 베트남어가
  /// 태국어 사용자 귀에 그대로 간다. 에러가 아니라 **조용히 틀리는** 종류라
  /// 실기기에서 원인을 못 찾는다. 여기서는 이름 문자열만 정규화해서 본다
  /// (히스토리의 `_normLangCode`와 같은 방식).
  bool _isSameChatLang(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

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

  /// 🔇 [DUO-GHOST] 이 시간보다 짧게 소리 난 발화는 전사문이 뭐라고 나오든
  /// 버린다. **글자로는 못 거른다** — 지어낸 문장이 멀쩡한 한국어라서다.
  ///
  /// 2026-08-13 실기기(SM S931N) 65초 통화 9건 실측:
  ///   실제 말   1,323 / 2,200 / 2,999ms  → 14~23자
  ///   클릭 잡음    41 /    42 /    44ms  → 3~7자 ("급습했다." 등 전부 환청)
  /// 같은 방에서 두 폰을 스피커로 켜 두면 음향 되먹임이 생기고, 그 클릭 하나를
  /// Server VAD가 발화로 잡아 전사 모델이 문장을 지어낸다.
  ///
  /// 150ms는 잡음(44ms)의 3.4배이면서 짧은 실제 응답("네" 약 200~300ms)은
  /// 살리는 값이다. 유효 발화가 잘려 나가면 올리지 말고 **먼저 로그의
  /// `voicedMs`를 확인할 것** — 진짜 짧은 말인지 클릭인지 그 숫자가 가른다.
  static const int kDuoMinVoicedMs = 150;

  /// 직접 대화 전사문 중 버릴 것. 만능 통역 쪽 필터는 건드리지 않는다.
  ///
  /// ⚠️ **글자 수로 버리지 않는다.** 예전에는 2자 이하를 무조건 잡음으로 봤는데,
  ///   "네"·"응"·"왜?" 같은 정상 대답이 1초 넘게 말해도 그대로 사라졌다
  ///   (2026-08-14 실측: 31건 중 5건 유실, order=3은 voicedMs=1164였다).
  ///   환청과 짧은 대답을 가르는 것은 글자 수가 아니라 **소리 난 시간**이고,
  ///   그건 호출부의 voicedMs 게이트가 이미 판단한다.
  bool _isNoiseTranscript(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return true;
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

  /// 전사문을 저장해도 되는 세대인가. 통화 중이거나, **종료 직전 flush 창**이면
  /// 저장한다. `mounted`는 보지 않는다 — 저장은 Firestore 쓰기뿐이라 위젯이
  /// 살아 있을 필요가 없고, 그 조건을 걸면 마지막 문장을 또 잃는다.
  bool _canSaveDirectTranscript(int generation) =>
      generation == _directGeneration && (_directCallActive || _directFlushing);

  /// 🔴 [DUO-LIVE] 마이크 버튼. 통화가 붙어 있으면 **음소거 토글**이고,
  /// 안 붙어 있으면 **연결 재시도**다.
  ///
  /// 통화 시작은 상대가 들어오는 순간 자동으로 이뤄진다
  /// ([_maybeAutoStartDirectCall]). 그래도 이 버튼의 재시도 경로를 남기는
  /// 이유는 하나다 — **자동 연결이 실패하거나 마이크 권한이 거부되면 통화를
  /// 시작할 방법이 아예 사라지기 때문이다.** 그때 유저에게 남는 손잡이가 이것뿐이다.
  ///
  /// 통화를 끝내는 것은 이 버튼이 아니라 방을 나가는 것이다(대칭 종료).
  void _onDirectMicToggle() {
    if (!_directCallActive) {
      if (_directStarting || _directStopping) {
        _lgDuo('[DUO-LIVE]', 'retry_ignored reason=busy');
        return;
      }
      _lgDuo('[DUO-LIVE]',
          'manual_retry partnerOnline=$_isPartnerOnline role=$_myRole');
      unawaited(_startDirectCall());
      return;
    }
    setState(() => _directMuted = !_directMuted);
    _lgDuo('[DUO-MUTE]', 'muted=$_directMuted');
  }

  /// 🔴 [DUO-LIVE] 상대가 방에 있으면 양쪽이 알아서 붙고 송신을 시작한다.
  ///
  /// 혼자 있는 동안에는 마이크를 열지 않는다 — 들을 사람이 없는데 녹음할
  /// 이유가 없다.
  ///
  /// **재진입 차단이 핵심이다.** 양쪽이 거의 동시에 들어오면 Firestore 스냅샷이
  /// 연달아 떨어져 이 함수가 여러 번 불린다. `_startDirectCall`에 자체 가드가
  /// 있지만 그 앞에서 한 번 더 좁히고, 자동 시도는 방마다 한 번으로 묶는다
  /// (실패 후 무한 재시도로 권한 창이 반복해 뜨는 것을 막는다).
  void _maybeAutoStartDirectCall(String reason) {
    if (!_isDirectMode) return;
    if (!_isPartnerOnline) return;
    if (!mounted || _isExiting) return;
    if (_directCallActive || _directStarting || _directStopping) return;
    if (_autoStartAttempted) return;
    _autoStartAttempted = true;
    _lgDuo('[DUO-LIVE]', 'auto_start reason=$reason role=$_myRole');
    unawaited(_startDirectCall());
  }

  Future<void> _startDirectCall() async {
    if (_directCallActive || _directStarting || _directStopping || _isExiting) {
      return;
    }
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
        idToken = await FirebaseAuth.instance.currentUser?.getIdToken() ?? '';
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
        _noteInboundAudio(pcm);
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
        // 🔇 [DUO-DIRECT] 통화라 상대가 말하는 동안에도 마이크를 닫을 수 없다.
        //   스피커로 나간 상대 목소리를 마이크가 도로 잡아 되먹임이 생기므로
        //   AEC로 지운다. 잡음 억제는 무음 구간에 실려 가던 생마이크
        //   노이즈("쉐" 소리)를 깎는다. 재생기를 먼저 통화 모드로 열어 둔
        //   뒤에 마이크를 여는 순서(①→④)를 지켜야 AEC가 참조를 잡는다.
        echoCancel: true,
        // 🎧 [STT-QUALITY] **잡음 억제는 끈다.** AEC와 NS는 별개 효과인데,
        //   글자를 망치는 쪽은 NS다 — 무엇이 잡음인지 추측해서 깎기 때문에
        //   ㅅ·ㅊ·ㅎ 같은 마찰음과 문장 끝을 같이 먹는다. 그 깎인 소리가
        //   그대로 gpt-4o-transcribe에 들어가 Circle Talk보다 전사가 나빴다
        //   (2026-08-14 실장님 확인). AEC는 "내가 방금 재생한 신호"라는 정답을
        //   알고 빼는 것이라 훨씬 덜 해치므로 되먹임 방지용으로 남긴다.
        //
        //   NS를 끄면 무음 구간 생마이크 노이즈가 늘 수 있으나, 그건
        //   voicedMs 150ms 게이트가 이미 막는다.
        noiseSuppress: false,
        onRecordingStarted: (at) => _lgDuo(
            '[PCM_CAPTURE]', 'recording_started at=${at.toIso8601String()}'),
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
          // 🔇 [DUO-MUTE] 음소거는 **내 소리를 안 보내는 것**이다. 릴레이 연결과
          //   상대 음성 수신은 그대로 살아 있다 — 여기서 내 조각만 버린다.
          //   전사도 같이 막는다. 안 그러면 음소거 중에 한 말이 History에 남는다.
          if (_directMuted) return;
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
      if (!_canSaveDirectTranscript(generation)) return;
      // 🔇 [DUO-GHOST] 소리가 난 시간을 여기서 읽는다. 전사문이 도착한 뒤에는
      //   이 값이 유일하게 남은 "진짜 말이었는가"의 근거다.
      final voicedMs = session.utteranceVoicedMsOf(itemId);
      final voicedSrc = session.utteranceVoicedSourceOf(itemId) ?? 'none';
      if (voicedMs != null && voicedMs < kDuoMinVoicedMs) {
        _lgDuo(
            '[DUO-GHOST]',
            'dropped item=$itemId voicedMs=$voicedMs src=$voicedSrc '
                'len=${text.trim().length}');
        return;
      }
      // 종료 대기가 이 future를 기다린다 — unawaited로 흘려보내면 안 된다.
      final save = _handleDirectTranscript(generation, text, itemId,
          voicedMs: voicedMs);
      _directSaves.add(save);
      unawaited(save.whenComplete(() => _directSaves.remove(save)));
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
      int generation, String text, String itemId,
      {int? voicedMs}) async {
    if (!_canSaveDirectTranscript(generation)) return;
    final String trimmed = text.trim();
    if (trimmed.isEmpty || _isNoiseTranscript(trimmed)) {
      // 예전에는 여기서 로그 없이 사라졌다. 무엇이 왜 버려졌는지 남지 않아
      // 실기기에서 "빠진 대사"를 추적할 수가 없었다.
      _lgDuo('[DUO-DROP]',
          'noise_gate item=$itemId len=${trimmed.length} voicedMs=${voicedMs ?? -1}');
      return;
    }
    // 중복 저장 가드. 같은 item이 두 번 오면(재전달·flush 겹침) 한 번만 남긴다.
    if (itemId.isNotEmpty && !_savedDirectItemIds.add(itemId)) {
      _lgDuo('[DIRECT-STT]', 'duplicate_skipped item=$itemId');
      return;
    }
    if (_savedDirectItemIds.length > 200) {
      _savedDirectItemIds.remove(_savedDirectItemIds.first);
    }
    final int seq = ++_directSeq;
    final DateTime spokenAt = _directSpeechStartedAt ?? DateTime.now();
    _directSpeechStartedAt = null;
    _lgDuo(
        '[DIRECT-STT]',
        'completed seq=$seq item=$itemId len=${trimmed.length} '
            'voicedMs=${voicedMs ?? -1}');
    // 상대 채널 업로드도 기다린다. 흘려보내면 종료 때 마지막 문장이
    // 내 History에만 남고 상대 History에는 안 간다.
    await _uploadMyMessage(
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

  /// 통화를 끊는다. **순서가 전부다.**
  ///
  /// 예전에는 맨 먼저 `++_directGeneration`을 올리고 곧바로 STT를 dispose했다.
  /// 그러면 말하는 도중에 끈 발화는 전사문이 도착해도 세대가 어긋나 버려지고,
  /// 애초에 기다리지도 않아서 **마지막 문장이 통째로 사라졌다.**
  ///
  /// 지금 순서:
  ///   ① 마이크 PCM 추가 전송 차단 (구독 취소 + 녹음 정지)
  ///   ② 진행 중 발화가 있으면 마지막 버퍼를 확정하고 전사문을 최대 2초 대기
  ///   ③ 그 전사문의 History·채널 저장이 끝날 때까지 대기
  ///   ④ 그다음에야 세대 증가 + 세션 dispose
  /// 진행 중 발화가 없으면 ②③은 즉시 통과한다(말없이 끄면 안 느려진다).
  Future<void> _stopDirectCall(String reason) async {
    if (_directStopping) return; // 중복 종료 가드 (연속 두 번 탭)
    if (!_directCallActive && _relayClient == null && _directCapture == null) {
      return;
    }
    _directStopping = true;
    _directCaptureFirstFrameAt = null;

    // ① 추가 PCM부터 끊는다. 확정 직후 들어온 소리가 새 발화를 열면 안 된다.
    final captureSub = _directCaptureSub;
    _directCaptureSub = null;
    await captureSub?.cancel();

    final capture = _directCapture;
    _directCapture = null;
    await capture?.stop();

    // ②③ 마지막 발화 확정 → 전사문 대기 → 저장 완료까지.
    //     `_directCallActive`와 세대는 아직 그대로다. 이 창 안에서 도착한
    //     전사문은 정상 경로로 저장된다.
    final stt = _directStt;
    _directStt = null;
    if (stt != null) {
      _directFlushing = true;
      try {
        final waited = await stt.flushPendingUtterance(reason: reason);
        if (waited) {
          await _awaitDirectSaves();
          // 상한을 넘겨 전사문이 끝내 안 왔으면 **그 문장은 어느 History에도
          // 없다.** 조용히 넘어가면 나중에 "왜 마지막 말이 없지"를 로그로
          // 못 찾는다. 여기서 분명히 남긴다.
          if (stt.hasPendingUtterance) {
            _lgDuo('⚠️ [DIRECT-STT]',
                'last_utterance_lost reason=$reason — flush 상한 내 전사문 미도착. '
                    '이 발화는 내 History와 상대 채널 어디에도 저장되지 않았다.');
          }
        }
      } catch (e) {
        _lgDuo('[DIRECT]', 'flush_failed(${e.runtimeType}) — 종료는 계속한다');
      } finally {
        _directFlushing = false;
      }
    }

    // ④ 이제부터 도착하는 늦은 콜백은 전부 남의 세대다.
    ++_directGeneration;
    _directCallActive = false;
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

    // 🔇 [DUO-MUTE] 다음 통화는 음소거 아닌 상태로 시작한다. 이전 통화의
    //   음소거를 물려받으면 유저가 모르는 채로 말하게 된다.
    if (mounted && !_isExiting) {
      setState(() {
        _micActive = false;
        _sttActive = false;
        _relayConnected = false;
        _partnerRelayConnected = false;
        _directMuted = false;
      });
      _setDuoState('idle');
    } else {
      _micActive = false;
      _sttActive = false;
      _relayConnected = false;
      _partnerRelayConnected = false;
      _directMuted = false;
      _duoState = 'idle';
    }
    _lgDuo(
        '[DIRECT]',
        'call_stopped reason=$reason relayRttMs=${relay?.lastRoundTripMs} '
            'playFirstLatencyMs=${player?.firstPlayLatencyMs} '
            'sentBytes=${relay?.sentBytes} recvBytes=${relay?.receivedBytes} '
            'playedBytes=${player?.writtenBytes} droppedBytes=${player?.droppedBytes}');
    _directStopping = false;
  }

  /// 진행 중인 History/채널 저장이 끝날 때까지 기다린다. 저장이 걸려도 통화
  /// 종료가 무한정 늦어지면 안 되므로 상한을 둔다.
  Future<void> _awaitDirectSaves() async {
    if (_directSaves.isEmpty) return;
    try {
      await Future.wait(List<Future<void>>.of(_directSaves))
          .timeout(kDuoDirectSaveTimeout);
    } catch (e) {
      _lgDuo('⚠️ [DIRECT-STT]',
          'save_wait_timeout(${e.runtimeType}) — 마지막 문장의 History/채널 '
              '저장이 상한 안에 안 끝났다. 저장 자체는 계속 진행되지만 '
              '실패했을 수 있다.');
    }
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

  /// ⚠️ **지금은 호출되지 않는다.** 만능 통역이 배울 언어를 통화 중에 만들던
  /// 시절의 경로다. 이제 대화 중에는 각자 자기 대화 언어로만 말하고 듣고,
  /// 배울 언어는 공부방이 만든다. 첫 턴 Realtime 음성(`FirstTurnRealtimeVoice`)도
  /// 내 발화를 다시 읽어줄 때만 쓰였으므로 같이 잠들었다.
  ///
  /// 지우지 않고 남긴 이유: 되살릴지 말지는 실기기에서 새 경로를 확인한 뒤에
  /// 정할 일이다.
  // ignore: unused_element
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
      final fallbackTarget = (fallback?['target'] ?? '').trim().isNotEmpty
          ? fallback!['target']!.trim()
          : raw;
      final fallbackOriginal = (fallback?['original'] ?? '').trim().isNotEmpty
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

    final fallbackTarget = (fallback?['target'] ?? '').trim().isNotEmpty
        ? fallback!['target']!.trim()
        : raw;
    final fallbackOriginal = (fallback?['original'] ?? '').trim().isNotEmpty
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

  /// ⚠️ 잠든 경로. `_resolveDuoTurn` 주석 참고.
  // ignore: unused_element
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
          BillingTicker.instance.resumeFromActivity('duo_realtime_audio_start');
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

  /// 🚀 [내 발화 처리] 내가 한 말을 상대에게 넘기고, 화면과 히스토리에 남긴다.
  ///
  /// **내 말을 나에게 다시 읽어주지 않는다.** 방금 내가 한 말이다. 예전에는
  /// 여기서 GPT로 내 배울 언어를 만들고 TTS로 읽어줬는데, 그 두 번의 왕복이
  /// 끝날 때까지 다음 말을 할 수 없었고 상대에게 가는 것도 늦어졌다.
  /// 배울 언어는 이제 공부방(히스토리)이 맡는다.
  ///
  /// 순서가 중요하다 — **업로드가 가장 먼저다.** 상대가 기다리는 건 그것뿐이고,
  /// 화면·히스토리는 내 폰 사정이라 상대를 붙잡을 이유가 없다.
  Future<void> _processRelayPipeline(String finalTranscript) async {
    _turnCounter++;
    final int currentTurnId = _turnCounter;
    ++_duoConversationTurnCounter;
    final String myNative = _myNative();
    final String spoken = finalTranscript.trim();
    if (spoken.isEmpty) return;

    // 1. 상대에게 넘긴다. 번역하지 않은 내 말 그대로 — 상대 폰이 자기 대화
    //    언어로 옮긴다(두 사람의 대화 언어가 다를 수 있으므로 내가 옮기면 안 된다).
    final DateTime uploadStartedAt = DateTime.now();
    await _uploadMyMessage(spoken, myNative);
    _lgDuo(
        '[INTERP-TURN]',
        'outgoing turn=$_duoConversationTurnCounter lang=$myNative '
            'len=${spoken.length} '
            'uploadMs=${DateTime.now().difference(uploadStartedAt).inMilliseconds}');

    if (!_isConversationActive || _turnCounter != currentTurnId) return;

    // 2. 내 말풍선 — 내가 한 말 그대로.
    if (mounted) {
      setState(() {
        _localMessages.add({'role': 'HOST', 'target': spoken, 'original': ''});
      });
      _scrollToCurrentTop(_localMessages.length - 1);
    }

    // 3. 히스토리 — 원문만. 배울글·배울소리는 공부방에서 만든다.
    await _saveHistoryMessage(
      '',
      spoken,
      'HOST',
      mode: kDuoModeInterpreter,
      sourceLang: myNative,
      deferTarget: true,
    );

    // 내 발화는 앱이 소리 내지 않으므로 에코 목록에 넣을 이유가 없다.
    // 그래도 남겨 둔다 — 상대 폰의 TTS가 스피커폰으로 내 마이크에 되돌아오는
    // 경우가 있고, 그 문장은 내가 한 말과 같은 언어다.
    _rememberGenerated(spoken);

    // 🆕 [PTT] 자동 재녹음 제거 — 쿨다운 후 대기 상태로 복귀
    _setDuoState('cooldown');
    await Future.delayed(const Duration(milliseconds: 300));
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

    // 상대 발화를 들려주는 동안 내 녹음 일시 정지.
    //
    // 🔇 [ECHO] 예전에는 앱이 **내 배울 언어**로 읽어서, 마이크에 새어 들어와도
    //   내가 말한 언어와 달라 티가 났다. 이제 앱도 나와 같은 대화 언어로
    //   말한다. 스피커폰이면 앱 목소리가 그대로 내 발화로 오인될 수 있으므로,
    //   **재생 중에는 마이크를 아예 열지 않는 것**이 1차 방어선이다.
    _silenceTimer?.cancel();
    try {
      await _audioRecorder.stop();
    } catch (_) {}
    _setDuoState('processing');

    final String myNative = _myNative();
    ++_duoConversationTurnCounter;

    // 대화 중에는 **내 대화 언어**로 듣는다. 배울 언어는 공부방이 맡는다.
    //
    // 상대가 이미 내 대화 언어로 말했으면 번역할 것이 없다 — GPT 왕복을
    // 통째로 건너뛴다(첫 토큰까지만 0.6~1.4초가 걸리던 자리다).
    final bool sameLang = _isSameChatLang(srcLang, myNative);
    String spoken = raw.trim();
    if (!sameLang) {
      final translated = await DuoBrain.translateForSpeech(
        key: _openAiKey,
        text: raw,
        srcLang: srcLang,
        toLang: myNative,
      );
      // 번역이 실패해도 상대 말을 통째로 잃지는 않는다. 못 알아들을지언정
      // 원문이라도 남기는 편이, 아무 일도 없었던 것처럼 조용히 사라지는
      // 것보다 낫다 — 사라지면 상대는 자기 말이 갔는지도 모른다.
      spoken = (translated ?? '').trim().isNotEmpty ? translated!.trim() : raw.trim();
      if (translated == null) {
        _lgDuo('⚠️ [INTERP-TRANSLATE]',
            'failed src=$srcLang to=$myNative — 원문 그대로 재생한다');
      }
    }
    _lgDuo('[INTERP-TURN]',
        'incoming src=$srcLang mine=$myNative same=$sameLang gptCalls=${sameLang ? 0 : 1}');

    if (!mounted || _isExiting) return;

    // 상대 말풍선: 좌측 (role='SYSTEM'). 큰 줄은 내가 알아들을 말,
    // 작은 줄은 상대가 실제로 한 말(같은 언어면 중복이라 생략).
    if (mounted) {
      setState(() {
        _localMessages.add({
          'role': 'SYSTEM',
          'target': spoken,
          'original': sameLang ? '' : raw.trim(),
        });
      });
      _scrollToCurrent(_localMessages.length - 1);
    }

    // 히스토리 — 원문 자리에는 내가 들은 말(내 대화 언어)을 넣는다.
    // 상대가 말한 언어가 마침 내 배울 언어면 그 원문이 곧 배울 문장이므로
    // 타겟까지 여기서 채운다. 번역의 번역이 아니라 상대가 실제로 한 말이
    // 배울글이 되고, 공부방이 API를 부를 일도 없다.
    final bool rawIsMyTargetLang = _isSameChatLang(srcLang, _myTarget());
    await _saveHistoryMessage(
      rawIsMyTargetLang ? raw.trim() : '',
      spoken,
      'SYSTEM',
      mode: kDuoModeInterpreter,
      sourceLang: myNative,
      deferTarget: !rawIsMyTargetLang,
    );

    // 🔇 [ECHO] 앱이 소리 낼 문장을 기억해 둔다. 스피커폰에서 이 소리가
    //   마이크로 되돌아오면 내 발화로 오인되는데, 이제 나와 같은 언어라
    //   언어만으로는 구분되지 않는다.
    _rememberGenerated(spoken);
    if (_isConversationActive && !_isExiting) {
      await _playSerialized(
          await _fetchTTSBytes(spoken, kInterpreterPartnerTtsVoice));
    }
    // 🆕 [PTT] 상대 발화 재생 후에도 자동 재녹음 금지 — 쿨다운 후 대기 복귀
    _setDuoState('cooldown');
    await Future.delayed(const Duration(milliseconds: 300));
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
      // 🔴 [DUO-LIVE] 연결은 자동이라 유저가 할 일이 없다. 그래서 화면은
      //   "지금 왜 소리가 안 가는지"를 말해 줘야 한다.
      if (!_directCallActive) {
        if (_directStarting) return 'Connecting…';
        // 상대가 없으면 기다리는 게 정상이다 — 실패가 아니다.
        if (!_isPartnerOnline) return 'Waiting…';
        // 상대는 있는데 안 붙었다 = 자동 연결이 실패했다.
        // 이 문구가 곧 재시도 안내다(탭하면 다시 붙는다).
        return 'Tap to reconnect';
      }
      if (_directMuted) return 'Muted — tap to unmute';
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
  /// **듀오 두 방식이 같은 규칙을 쓴다.** 대화 중에는 각자 자기 대화 언어로
  /// 말하고 들을 뿐이고, 배울 언어(타겟)는 히스토리를 열 때 그 방의
  /// `target_lang`으로 만든다 — 나머지 세 모드와 같다.
  /// (chat_history_master의 `_scheduleMissingTargetGeneration`이 받는다)
  ///
  /// 예외가 하나 있다: 상대가 말한 언어가 마침 **내 배울 언어와 같으면**,
  /// 그 원문이 곧 배울 문장이다. 그때는 `target`에 실어 보내 `deferTarget`을
  /// 끈다. 번역의 번역이 아니라 상대가 실제로 한 말이 배울글이 되고,
  /// 공부방에서 API를 부를 필요도 없다.
  Future<void> _saveHistoryMessage(
    String target,
    String original,
    String role, {
    String? mode,
    int? seq,
    DateTime? spokenAt,
    String? speakerUid,
    String? sourceLang,
    bool? deferTarget,
  }) async {
    // 호출부가 명시하지 않으면 예전 규칙(직접 대화만 미룸)을 그대로 따른다.
    final bool defer = deferTarget ?? (mode == kDuoModeDirect);
    // 타겟을 미루는 줄은 원문이 본문이다. 아니면 타겟이 본문이다.
    if (defer ? original.trim().isEmpty : target.trim().isEmpty) return;
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
        'translated_text': defer ? '' : target,
        'original_text': defer
            ? original
            : ((FFAppState().nativeLang.isNotEmpty &&
                    FFAppState().nativeLang == FFAppState().targetLang)
                ? ''
                : original),
        'created_at': FieldValue.serverTimestamp(),
        // ↓ 듀오에서만 붙는 필드. 다른 모드의 문서 모양은 그대로다.
        //   `duo_mode`는 지금 읽는 곳이 없지만, 두 방식이 한 컬렉션에 섞이므로
        //   나중에 "어느 방식에서 생긴 줄인지"를 데이터만 보고 가릴 수 있어야 한다.
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
        'last_message': defer ? original : target,
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
        'StealthVox Duo 초대 - 저와 함께 Duo 대화해요!\n$inviteLink',
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
      // 🔴 [DUO-LIVE] **게스트 쪽 자동 시작은 여기가 유일한 자리다.**
      //   게스트는 `_listenForPartnerJoined`를 걸지 않는다(호스트만 건다).
      //   입장에 성공한 이 시점이 곧 "상대(호스트)가 있다"는 확정이다.
      _maybeAutoStartDirectCall('guest_joined');
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
        // 🔴 [DUO-LIVE] 상대가 들어오면 양쪽이 자동으로 붙는다. 각자 마이크를
        //   눌러야 소리가 가던 구조는 라이브 통화가 아니라 "각자 통화 참가"였다.
        //   마이크 버튼은 이제 음소거 토글이다(연결 실패 시에는 재시도).
        if (partnerJoined) {
          _maybeAutoStartDirectCall('partner_joined');
        } else {
          // 상대가 없는 동안 자동 시도 기록을 놓는다. 다음에 상대가 들어오면
          // 그때 한 번 더 자동으로 붙는다.
          _autoStartAttempted = false;
        }
        // 게스트 퇴장 → 호스트 강제 종료 (1:1 대칭 종료 모델).
        // 재통화는 새 초대로 시작한다 — 과금도 그 기준에 맞춰져 있다.
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
        // 🆕 정식 회원이 초대를 받아 들어온 경우, 대화가 끝나면 게스트 딱지를
        //   뗀다. 안 떼면 Intro가 회원 계정이 살아 있어도 로그인 화면에 붙잡아
        //   둬서, 방금 나눈 대화를 자기 History에서 못 본다(기록은 이미 자기
        //   uid 아래 저장돼 있다).
        //   익명 계정으로 들어온 비회원 게스트는 그대로 둔다 — 볼 수 있는
        //   Lobby도 없고, Intro의 가입 유도가 의도된 흐름이다.
        final guestUser = FirebaseAuth.instance.currentUser;
        if (guestUser != null && !guestUser.isAnonymous) {
          FFAppState().isGuestSession = false;
          _lgDuo('[GUEST-EXIT]', 'member guest — isGuestSession 해제');
        } else {
          _lgDuo('[GUEST-EXIT]', 'anonymous guest — Intro에 남긴다');
        }
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
                                  !_isDirectMode
                                      ? "마이크를 탭하면 시작됩니다.\n말이 끝나면 자동으로 전송됩니다."
                                      // 🔴 [DUO-LIVE] 연결은 상대가 들어오면
                                      //   자동이다. "마이크를 탭하라"·"상대도
                                      //   마이크를 켜면"은 더 이상 사실이
                                      //   아니라서 지웠다. 지금 왜 소리가
                                      //   안 가는지는 버튼 옆 라벨이 말한다.
                                      : "서로의 실제 목소리로 대화하세요.",
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

  static String _modeDesc(String mode) =>
      mode == kDuoModeDirect ? '서로의 실제 목소리로 통화합니다.' : '상대의 말을 통역 음성으로 들려줍니다.';

  /// 🆕 [모드 선택 — 호스트 전용] 초대장을 만들기 직전에 뜬다.
  /// 여기서 고른 값만이 세션 문서의 `mode`가 된다.
  Future<String?> _showHostModePicker() {
    String picked = _duoMode;
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Widget tile(String mode) {
          final bool selected = picked == mode;
          final bool isDirect = mode == kDuoModeDirect;
          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setS(() => picked = mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF253B63)
                    : const Color(0xFF2A3445),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF5B9BFF)
                      : const Color(0xFF445066),
                  width: selected ? 1.8 : 1.0,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color:
                              const Color(0xFF2563EB).withValues(alpha: 0.22),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF3B82F6)
                          : const Color(0xFF39465B),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      isDirect ? Icons.call_rounded : Icons.graphic_eq_rounded,
                      size: 23,
                      color: selected ? Colors.white : const Color(0xFFB9C5D8),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _modeTitle(mode),
                          style: const TextStyle(
                            color: Color(0xFFF8FAFC),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _modeDesc(mode),
                          style: const TextStyle(
                            color: Color(0xFFBCC7D9),
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        key: ValueKey(selected),
                        size: 23,
                        color: selected
                            ? const Color(0xFF69A7FF)
                            : const Color(0xFF718096),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF202938),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: const Color(0xFF3C4A60)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.42),
                    blurRadius: 32,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '대화 방식 선택',
                      style: TextStyle(
                        color: Color(0xFFF8FAFC),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '초대할 대화 방식을 골라주세요.',
                      style: TextStyle(
                        color: Color(0xFFAEBACD),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    tile(kDuoModeDirect),
                    tile(kDuoModeInterpreter),
                    const SizedBox(height: 2),
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: Color(0xFF91A1B8),
                          ),
                        ),
                        SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            '상대방도 선택한 방식으로 초대됩니다.',
                            style: TextStyle(
                              color: Color(0xFFAEBACD),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFCBD5E1),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text(
                              '취소',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: const Color(0xFF3478F6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                            ),
                            onPressed: () => Navigator.pop(ctx, picked),
                            icon: const Icon(
                              Icons.person_add_alt_1_rounded,
                              size: 19,
                            ),
                            label: const Text(
                              '초대하기',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
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
        Icon(direct ? Icons.record_voice_over : Icons.graphic_eq_rounded,
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
    const List<String> langs = _kGuestLangs;
    // 열릴 때 이미 보정했지만, 다른 경로로 값이 바뀐 채 다시 그려질 수도 있다.
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
                  dropdown("Original", native, const Color(0xFF93C5FD), (val) {
                    if (val != null)
                      setState(() => FFAppState().nativeLang = val);
                  }, subtitle: "(Chat Lang)", subtitleBelow: false),
                  const SizedBox(height: 18),
                  dropdown("Target", target, const Color(0xFF4ADE80), (val) {
                    if (val != null)
                      setState(() => FFAppState().targetLang = val);
                  }, subtitle: "(Learn Lang)", subtitleBelow: true),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    onPressed: () {
                      final String? roomId = _pendingJoinRoomId;
                      // 손대지 않은 드롭다운의 표시값을 그대로 확정한다.
                      FFAppState().nativeLang = native;
                      FFAppState().targetLang = target;
                      _lgDuo('[GUEST-LANG]',
                          'entered origin=$native target=$target sttLang=${_mapLanguageToCode(native)}');
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
    // 🔴 [DUO-LIVE] 직접 대화: 소리가 실제로 나가는 동안만 초록이다.
    //   음소거 중에는 통화가 붙어 있어도 초록이 아니어야 한다 — 초록인데 내
    //   말이 안 가면 유저는 원인을 찾을 수 없다. 탭은 음소거 토글이다.
    final bool isRec = _isDirectMode
        ? (_directCallActive && !_directMuted)
        : _duoState == 'recording';
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

  /// 통화 중 **재생용** 번역. 한 언어만 만든다.
  ///
  /// `processTranslation`은 배울 언어와 대화 언어를 JSON 두 칸으로 한꺼번에
  /// 만든다. 통화 중에 필요한 건 **내 대화 언어 한 칸뿐**이다(배울 언어는
  /// 공부방이 히스토리를 열 때 만든다). 그래서 여기서는 JSON도 쓰지 않고
  /// 평문 한 줄만 받는다 — 나올 글자가 절반 이하로 줄고, 파싱 실패라는
  /// 실패 모드 자체가 없어진다.
  static Future<String?> translateForSpeech({
    required String key,
    required String text,
    required String srcLang,
    required String toLang,
  }) async {
    final String source = text.trim();
    if (key.isEmpty || source.isEmpty) return null;
    try {
      final Uri uri = Uri.parse('https://api.openai.com/v1/chat/completions');
      final String prompt =
          "You are a translation engine for a live interpreter app.\n"
          "You are NOT a chat assistant. NEVER reply, comment, answer, or ask "
          "questions. NEVER continue the conversation.\n\n"
          "Translate the utterance from $srcLang into natural spoken $toLang.\n"
          "Preserve tone, intent, names, and numbers exactly. Do not add or "
          "remove meaning.\n"
          "If the utterance is unclear or empty, output nothing.\n"
          "Return ONLY the translated sentence — no quotes, no label, no "
          "explanation.";
      final res = await client
          .post(uri,
              headers: {
                'Authorization': 'Bearer $key',
                'Content-Type': 'application/json; charset=utf-8'
              },
              body: jsonEncode({
                'model': 'gpt-4o-mini',
                'temperature': 0.2,
                // 한 문장이면 충분하다. 400은 JSON 두 칸 시절의 값이다.
                'max_tokens': 200,
                'messages': [
                  {'role': 'system', 'content': prompt},
                  {'role': 'user', 'content': source},
                ]
              }))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        debugPrint('[Duo][SpeechTranslate] status=${res.statusCode}');
        return null;
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final choices = body['choices'] as List? ?? const <dynamic>[];
      if (choices.isEmpty) return null;
      final message = (choices.first as Map<String, dynamic>)['message']
          as Map<String, dynamic>?;
      final out = (message?['content'] ?? '').toString().trim();
      return out.isEmpty ? null : out;
    } catch (e) {
      debugPrint('[Duo][SpeechTranslate] failed=${e.runtimeType}');
      return null;
    }
  }

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
