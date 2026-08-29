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

// 📦 [Box 1: Imports 및 패키지]
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/rendering.dart'; // RenderAbstractViewport (읽기 스크롤)
import 'package:flutter/services.dart';
import 'routine_mode_scenario_talk.dart' show TtsCache;
import '/custom_code/actions/billing_ticker.dart';
import '/custom_code/actions/billing_idle_mixin.dart';
import '/custom_code/services/ai_style.dart';
import '/custom_code/services/origin_language_session.dart'
    show detectOriginScript, textContradictsLanguage;
import '/custom_code/services/transcript_repair_guard.dart';
import 'alt_style_popup.dart';
import '/custom_code/services/audio_silence_analyzer.dart';
import '/custom_code/services/breath_echoing_engine.dart';
import '/custom_code/services/breath_segment.dart';
import '/custom_code/services/p2_voice_styles.dart';
import '/custom_code/services/speech_reconstruction.dart';
import '/custom_code/services/duo_study_state.dart';
import '/custom_code/services/history_text_model.dart';
import '/custom_code/services/duo_canonical.dart';
import '/custom_code/services/study_access.dart';
import '/custom_code/services/pcm_audio_utils.dart'
    show kStealthVoxSttSampleRate, pcm16DurationMs, pcm16ToWav;

// ════════════════════════════════════════════════════════════════════
// 🌬️ [P3-BREATH] Breath Echoing이 쓰는 값. **한곳에만 둔다.**
// ════════════════════════════════════════════════════════════════════

/// P3가 처음 열릴 때의 보이스. 에코잉이 기본 모드라 그 목록의 첫 칸을 든다 —
/// 목록에 없는 값을 들고 열면 어느 칸도 켜지지 않은 채 소리만 난다.
const String _kBreathVoice = 'coral';

/// 🎵 낭독 패턴. Voice Lab의 Smooth Jazz 한 벌과 달리 **훈련 모드마다**
/// 갈린다.
///   · 에코잉  — Sing-Song Flow (호흡마다 끊어 따라 읽기)
///   · 쉐도잉  — Story Melody  (이야기하듯 이어 읽어 얹어 말하기)
/// id가 다르므로 캐시 칸도 따로 선다. 모드를 오가도 이미 받은 소리는 남는다.
P2VoiceStyle _p3StyleFor(P3PracticeMode mode) =>
    mode == P3PracticeMode.echoing ? kP3SpeakingStyle : kP3ShadowingStyle;

/// 훈련 전용 캐시 칸. 스타일 id가 달라 Lab이 만들어 둔 소리와도, 두 모드끼리도
/// 섞이지 않는다.
String _p3CacheNamespaceFor(P3PracticeMode mode, String voice) =>
    'p2_wav_${_historyPracticeTtsModel}_${_p3StyleFor(mode).id}'
    '_${kP2StyleInstructionVersion}_$voice';

const String _historyListenTtsModel = 'tts-1';
const String _historyListenTtsVoice = 'nova';
const String _historyPracticeTtsModel = 'gpt-4o-mini-tts';
const String _historyPracticeAiVoice = 'nova';
const String _historyPracticeUserVoice = 'verse';
const Color _p3ShadowingAccentColor = Color(0xFF818CF8);
const Color _p3PracticeSurfaceColor = Color(0xFF1C1C1C);
const Color _p3PracticeBorderColor = Color(0x22FFFFFF);
const Color _p3BreathAccentColor = Color(0xFF7DD3FC);

/// 🗣️ [P3-VOICE] 모드마다 고를 수 있는 목소리가 다르다.
///   · 에코잉 — 호흡을 끊어 따라 읽는 연습이라 둘만 둔다.
///   · 쉐도잉 — 겹쳐 말하는 연습이라 결이 다른 셋을 준다.
/// 어느 쪽도 성별은 적지 않는다. 캐시 키에 목소리가 들어가므로 목록을 바꿔도
/// 이미 받아 둔 소리는 그대로 남는다.
const List<String> _kP3EchoingVoices = <String>['coral', 'alloy'];
const List<String> _kP3ShadowingVoices = <String>['echo', 'ash', 'coral'];

/// 의미단위 낭독의 공통 뼈대. 무엇을 한 덩어리로 볼지, 덩어리 안을 어떻게
/// 붙일지까지만 정한다. **덩어리 사이를 어떻게 다룰지는 아래 두 낭독 방식이
/// 갈라서 정한다.**
///
/// 속도는 목표가 아니라 결과라서 배속 숫자를 지시하지 않는다. 숫자를 앞에 두면
/// 모델이 느리게 읽기부터 집행해 밋밋하게 늘어지고 리듬이 뒤로 밀린다.

/// 학습용 — 구간을 **의도적으로 벌려** 따라 하기 쉽게 만든다.

/// 원어민식 — 중요하지 않은 곳은 **흘려 붙이고** 핵심만 세운다.

/// 📦 [Box 2: 위젯 클래스 선언부]
class ChatHistoryMaster extends StatefulWidget {
  const ChatHistoryMaster({
    Key? key,
    this.width,
    this.height,
    required this.historyDoc,
  }) : super(key: key);

  final double? width;
  final double? height;
  final DocumentReference historyDoc;

  @override
  _ChatHistoryMasterState createState() => _ChatHistoryMasterState();
}

class _ChatHistoryMasterState extends State<ChatHistoryMaster>
    with SingleTickerProviderStateMixin, BillingIdleMixin<ChatHistoryMaster> {
  // 📦 [Box 3: 상태 변수 - 기본 UI 및 로딩]
  bool isPracticeMode = false;
  bool isPaused = false;
  double _fontScale = 1.0;

  /// 언어 표시 모드: 0=영어+한글, 1=영어만, 2=한글만
  int _langDisplayMode = 0;

  /// 이 History 세션 생성 당시 저장된 언어 식별값.
  /// 레거시(구버전) 문서엔 없으므로 null → 텍스트 동일성 fallback으로 판정한다.
  /// 전역 FFAppState 값을 쓰지 않으므로, 이후 언어 설정을 바꿔도 과거 기록은 안전하다.
  String? _sessionNativeLang;
  String? _sessionTargetLang;

  /// 언어 식별값 정규화: 대소문자·앞뒤 공백 차이를 흡수한다.
  String _normLangCode(String v) => v.trim().toLowerCase();

  /// 텍스트 정규화(레거시 fallback 비교용): 대소문자·연속 공백 차이를 흡수한다.
  String _normLangText(String v) =>
      v.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// 이 세션이 동일 언어(Origin=Target)인지 — 기록별 언어값 기준.
  /// 기록에 Origin/Target 언어값이 모두 있으면 그것으로 판정하고,
  /// 없으면 null을 반환해 호출부가 텍스트 동일성 fallback으로 위임하게 한다.
  bool? get _recordSameLang {
    final n = _sessionNativeLang;
    final t = _sessionTargetLang;
    if (n != null && n.trim().isNotEmpty && t != null && t.trim().isNotEmpty) {
      return _normLangCode(n) == _normLangCode(t);
    }
    return null;
  }

  bool isLoadingRoom = true;
  String roomName = "";

  /// 상단 제목에 쓸 표시명. **저장값은 절대 건드리지 않는다** — `room_name`은
  /// 과거 문서의 분류 키라, 히스토리 필터와 모드 추론(`_inferHistoryMode`)이
  /// 이 문자열을 그대로 읽는다. 바꾸면 옛 대화가 미분류로 떨어진다.
  ///
  /// 표시명은 Free Talk → Anyone → Circle Talk, Roleplay → Scenario Talk으로
  /// 바뀌어 왔는데 저장된 이름은 그대로라, 옛 방을 열면 옛 이름이 떴다.
  /// "Anyone · 회사 동료"처럼 뒤에 붙은 설명은 살린다.
  String _displayRoomTitle(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return name;

    var head = name;
    var suffix = '';
    final sep = name.indexOf('·');
    if (sep >= 0) {
      head = name.substring(0, sep).trim();
      suffix = name.substring(sep + 1).trim();
    }

    final String display;
    if (head.contains('Anyone') ||
        head.contains('Free Talk') ||
        head.contains('Circle Talk')) {
      display = 'Circle Talk';
    } else if (head.contains('Roleplay') || head.contains('Scenario')) {
      display = 'Scenario Talk';
    } else {
      display = head.replaceAll(' Mode', '');
    }
    return suffix.isEmpty ? display : '$display · $suffix';
  }

  bool _isEnteringPractice = false;
  bool _isOpeningAdjacentHistory = false;
  int _openingHistoryOffset = 0;
  Map<String, dynamic>? _cachedRoomData;

  // 📦 [Box 4: 상태 변수 - Shadowing 상태 머신]
  ShadowingPhase _phase = ShadowingPhase.idle;
  SentenceVariant _selectedVariant = SentenceVariant.mySpeech;

  /// 🗣️ [MY-SPEECH] 대화에서 유저가 실제로 표현한 것만 모은 한 벌.
  String _mySpeech = "";

  /// 🇺🇸 [NATIVE-ENGLISH] 같은 의미를 미국식 사고 배열로 다시 세운 한 벌.
  String _nativeEnglish = "";

  /// Native English 자리에 한글이 남아 있으면 만들다 만 값이다.
  static final RegExp _hangul = RegExp(r'[가-힣ᄀ-ᇿ㄰-㆏]');
  // 🔧 [STAMPEDE-FIX] 같은 청크에 대한 동시 API 호출 방지
  // key: chunk index, value: 진행 중인 audio fetch Future
  final Map<int, Future<Uint8List?>> _inFlightChunkFetch = {};
  final Map<String, Future<Uint8List?>> _breathPcmInFlight = {};
  // 모든 연속 TTS 요청은 동일한 요청 키로 하나의 네트워크 Future를 공유한다.
  final Map<String, Future<Uint8List?>> _openAiTtsInFlight = {};
  List<PracticeChunk> _chunks = [];
  int _currentChunkIdx = 0;
  bool _isPlayingFullUser = false;
  int _fullUserPlayIdx = 0;
  final Map<String, Uint8List> _fullAIAudioCache = {};
  bool _isListening = false;
  Timer? _utteranceSafetyTimer;

  // 🆕 [TUTOR] 양측 대화 자동 재생 모드 상태 변수
  bool _isTutorPlaying = false;
  List<Map<String, dynamic>> _tutorLines = [];
  AudioPlayer? _tutorAudioPlayer;

  // 🆕 [BOX-30] 시작 화면 표시 여부 (true이면 You/AI 선택 화면, false이면 진행 중)
  bool _tutorAwaitingStart = true;
  // 🆕 [BOX-32] 역할 스왑 플래그 (true이면 HOST↔USER 동적 반전)
  bool _swapRoles = false;
  // 🆕 [BOX-31] AI 청크 발화 중 (헤더 인디케이터용)
  bool _tutorAiSpeaking = false;
  // 🆕 [BOX-31] 유저 녹음 중 (헤더 인디케이터용)
  bool _tutorUserRecording = false;
  // 🆕 [BOX-34] 완료 후 전체 통합 재생 중 여부
  bool _tutorPlayingFullback = false;
  // 역할 선택 말풍선
  bool _showRoleBubble = false;
  Timer? _roleBubbleTimer;
  // 아이콘 선택 유도 깜박 애니메이션
  late AnimationController _blinkController;
  late Animation<double> _blinkOpacity;

  // 에코링 팝업 오버레이
  Timer? _echoingOverlayTimer;

  // 📦 [Box 4-B: 양방향 턴제 연습 엔진 상태]
  int currentIndex = 0;

  bool _isAutoRecording = false;
  Timer? _silenceTimer;
  int _silenceCounter = 0;
  bool _hasSpoken = false;

  /// 못 만든 이유. null이면 실패한 적이 없다. 카드에 그대로 뜬다.
  String? _mySpeechError;
  String? _nativeEnglishError;
  // 다시 읽어 달라는 힌트
  bool _showRetryHint = false;
  int _turnPracticeRetryCount = 0;

  // 🆕 [P2-INDICATOR] AI 청크 발화 중 여부 (인디케이터 빛남용)
  bool _aiChunkPlaying = false;
  // AI TTS 로딩 중 (재생 전 Thinking... 표시용)
  bool _aiChunkLoading = false;
  // 🆕 [P2-INDICATOR] AI 다시 듣기 모드 (true이면 끝나도 마이크 자동 ON 안 함)
  bool _isReplayMode = false;

  // P3 한 문장 의미단위 쉐도잉 상태.
  /// 📜 [P3-READ-SCROLL] 본문 패널의 자리를 재는 데 쓴다.
  final GlobalKey _p3SentenceKey = GlobalKey();

  /// 📜 [P3-READ-SCROLL] 본문 **아래** 컨트롤 묶음([AI]·[ECHO]·[SHADOW]
  /// 듣기와 Stop). 다 읽었을 때 여기까지 화면에 들어와야 한다.
  final GlobalKey _p3ControlsKey = GlobalKey();

  /// 손으로 스크롤한 뒤에는 자동으로 밀지 않는다. 읽는 자리를 직접 잡은
  /// 사람과 싸우면 안 된다. 다음 Start에서 다시 열린다.
  bool _p3AutoScrollBlocked = false;
  StreamSubscription<Duration>? _p3ShadowPositionSub;
  StreamSubscription<Duration>? _p3ShadowDurationSub;

  // 🆕 [CHUNK-PRACTICE] 의미단위 연습 모드 상태
  bool _practicingNativeEnglish =
      false; // false = My Speech, true = Native English
  bool _isBuildingMySpeech = false; // 🗣️ [MY-SPEECH] 만드는 중
  bool _isBuildingNativeEnglish = false; // 🇺🇸 [NATIVE-ENGLISH] 만드는 중
  /// 이 방의 저장 모드. 학습 경로 카드를 무엇까지 띄울지 여기서 가른다.
  String _cachedRoomMode = '';
  bool _isPlayingFullAI = false; // 전체 AI 듣기 진행 중
  Timer? _nativeEnglishRevealTimer;
  final ScrollController _chunkScrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  // 🆕 [BOX-34-SCROLL] Practice 화면 스크롤 컨트롤러 & 아이템 키
  final ScrollController _practiceScrollController = ScrollController();
  final Map<int, GlobalKey> _practiceItemKeys = {};
  final Map<int, GlobalKey> _nativeEnglishItemKeys = {};

  // 🆕 [NATIVE-UNITS] Native English 문장의 의미단위 콜앤리스폰 연습
  List<String> _nativeEnglishUnits = [];
  int _nativeEnglishUnitIdx = -1;
  bool _nativeEnglishUnitAIPlaying = false;

  // 📦 [Box 5: 상태 변수 - 오디오 플레이어 및 마이크]
  late AudioPlayer audioPlayer;
  bool isPlaying = false;
  late AudioRecorder appAudioRecorder;
  BytesBuilder _pcmBuffer = BytesBuilder();

  // 📦 [Box 5-3: Deepgram 웹소켓 (utterance_end 감지 전용)]
  WebSocket? _dgSocket;
  StreamSubscription? _dgSubscription;
  StreamSubscription? _micStreamSub;

  // 🔧 Subscription 누수 방지용 변수
  StreamSubscription? _playerStateSub;
  StreamSubscription? _playerCompleteSub;

  // 📦 [Box 6: 상태 변수 - DB 캐시 및 튜터링 팝업]
  List<DocumentSnapshot> _cachedDocs = [];

  /// 📚 [SOURCE / CANONICAL] 공부방이 그리는 줄만 남긴다.
  ///
  /// 듀오 정리가 추려낸 줄은 **지워지지 않고** `study_state`만 바뀐 채
  /// 컬렉션에 남아 있다(2026-08-28부터). 화면·연습·배울글·교정 문맥이 모두
  /// 이 목록 하나를 보므로, 들어오는 입구에서 한 번만 거른다.
  ///
  /// 값이 없는 옛 문서는 그대로 보인다 — 마이그레이션이 필요 없다.
  List<DocumentSnapshot> _visibleMessages(List<DocumentSnapshot> docs) {
    return docs.where((doc) {
      final data = doc.data();
      if (data is! Map<String, dynamic>) return true;
      return isStudyVisible(data[kStudyStateField]);
    }).toList();
  }
  final Map<String, Future<bool>> _targetTranslationInFlight =
      <String, Future<bool>>{};

  /// 타겟 문장을 끝내 못 만든 줄. docId → 실패 종류(`_targetFailureLabel` 참고).
  ///
  /// 예전에는 실패가 아무 데도 남지 않았다. 화면에서는 원문만 있는 줄이 정상인
  /// 줄과 똑같이 보였고, 연습에 들어가면 그 줄은 말없이 빠졌다(`_enterShadowingFromRoom`).
  /// 어느 쪽도 사용자에게 이유를 알려주지 않았다. 여기 남겨서 말풍선에 배지를
  /// 띄우고 다시 시도할 수 있게 한다.
  final Map<String, String> _targetFailures = <String, String>{};
  String _apiKey = "";
  String _deepgramKey = "";
  Future<void>? _remoteConfigFuture;
  String? activeAppDocId;
  bool isGeneratingApp = false;
  String appOriginalText = "";
  String appCorrectedText = "";
  StateSetter? _dialogSetState;
  bool _appIsRecording = false;
  String _appAnswerEn = "";
  String _appCorrection = "";
  String _appUsageTip = ""; // 🆕 활용가치 있는 구문/관용구 팁 (있을 때만)
  Uint8List? _appCorrectedAudio;
  bool _isPlayingAppAudio = false;
  String _appTranscript = "";
  // 🆕 Another Sentence 중복 회피: 최근 생성한 한국어 문장(최대 6개) 기억
  final List<String> _appRecentKoSentences = [];

  // ── Idle Timeout (무반응 과금 정지, History: 자동 이동 없음) ──────────────
  // 🔧 틱 방식: 1초마다 활동 여부 확인. 튜터링/녹음/오디오 재생 중엔 카운터 0 유지.
  @override
  String get billingModeName => 'history';

  @override
  bool get isBillingBusy {
    return _isTutorPlaying ||
        isPlaying ||
        _appIsRecording ||
        _isPlayingAppAudio ||
        _isAutoRecording ||
        _tutorUserRecording ||
        _tutorAiSpeaking ||
        _aiChunkPlaying ||
        _aiChunkLoading ||
        _isPlayingFullAI ||
        _isPlayingFullUser ||
        _nativeEnglishUnitAIPlaying ||
        // 🎤 [P3-SPEAK] PCM 준비·Breath Echo·Full Echo·Shadow·재생 중에
        //   유휴로 잘못 판정해 과금이 멈추지 않게 한다.
        _p3Busy;
  }

  bool _handlingExhaustion = false;

  /// 공부방에서 잔여시간이 0이 됐을 때. 차감만 멈추면 STT·LLM·TTS가 그대로
  /// 돌아 무료 이용이 되므로 화면 자체를 닫는다.
  ///
  /// 정산과 usage_logs 저장은 [BillingTicker.pause]가 소유한다 — 여기서 따로
  /// 저장하지 않는다. 나머지 정리는 [dispose]가 한다.
  void _onBalanceExhausted() {
    if (!BillingTicker.instance.balanceExhausted.value) return;
    if (!mounted || _handlingExhaustion) return;
    _handlingExhaustion = true;
    BillingTicker.instance.pause();
    dismissRoutesAbove(context);
    showBillingBlockedNotice(
      context,
      message: '잔여 시간이 모두 소진되어 공부방을 닫았습니다.',
      offerStore: false,
    );
    context.pushReplacementNamed('Store');
  }

  // 사용자 실제 활동 시작 시 오토포즈 즉시 해제 (중복 방지 포함)
  void _resumeHistoryFromUserAction() {
    resetBillingIdle();
    BillingTicker.instance.resumeFromActivity('history_user_action');
  }

  // ─────────────────────────────────────────────────────────────────────────

  // 📦 [Box 7: 라이프사이클 - initState]
  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _blinkOpacity = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );
    audioPlayer = AudioPlayer();
    appAudioRecorder = AudioRecorder();
    _remoteConfigFuture = _fetchRemoteConfig();
    _fetchRoomData();
    _initPermissions();
    BillingTicker.instance.balanceExhausted.addListener(_onBalanceExhausted);
    // 💰 [BILLING-IDLE] 입장 즉시 과금 + 60초 유휴 감시. 규칙은 공용이다.
    //   첫 프레임 뒤로 미룬다 — initState에서 바로 부르면 resume()이
    //   billingState(ValueNotifier)를 빌드 도중에 고쳐서, 그걸 듣는
    //   ValueListenableBuilder가 "setState during build"로 터졌다
    //   (실기기 로그, 2026-08-27). 한 프레임(≈16ms) 늦어질 뿐이다.
    //   startBillingRoom()이 안에서 resetBillingIdle()을 부르므로,
    //   여기서 따로 부르던 것도 같이 정리한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) startBillingRoom();
    });

    _playerStateSub = audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => isPlaying = state == PlayerState.playing);
    });
    _playerCompleteSub = audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      _onAudioComplete();
    });
  }

  // 📦 [Box 8: 라이프사이클 - dispose]
  @override
  void dispose() {
    BillingTicker.instance.balanceExhausted.removeListener(_onBalanceExhausted);
    clearBillingIdle();
    _utteranceSafetyTimer?.cancel();
    _silenceTimer?.cancel();
    _roleBubbleTimer?.cancel();
    _blinkController.dispose();
    _echoingOverlayTimer?.cancel();
    _nativeEnglishRevealTimer?.cancel();
    // 🎤 [P3-SPEAK] dispose에서 async setState가 나오지 않게 회차를 먼저
    //   무효화하고, 소유한 재생·타이머·임시 녹음을 직접 접는다.
    _p3Generation++;
    _p3SilenceTimer?.cancel();
    _p3ReturnTimer?.cancel();
    _p3PageScrollController.dispose();
    _p3PlayerSub?.cancel();
    _p3Player?.stop();
    _p3Player?.dispose();
    _p3Engine?.stop();
    _deleteP3Recordings();
    _chunkScrollController.dispose();
    _practiceScrollController.dispose();
    _p3ShadowPositionSub?.cancel();
    _p3ShadowDurationSub?.cancel();
    _playerStateSub?.cancel();
    _playerCompleteSub?.cancel();
    _dgSubscription?.cancel();
    _micStreamSub?.cancel();
    try {
      _dgSocket?.close();
    } catch (_) {}
    _dialogSetState = null;
    BillingTicker.instance.pause();
    audioPlayer.dispose();
    _tutorAudioPlayer?.dispose();
    _appCorrectedAudio = null;
    if (_appIsRecording || _p3Recording) {
      _p3Recording = false;
      appAudioRecorder.stop().ignore();
    }
    appAudioRecorder.dispose();
    super.dispose();
  }

  // 📦 [Box 8-B: 대화방 전체 삭제]
  Future<void> _deleteHistoryRoom() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('대화 삭제', style: TextStyle(color: Colors.white)),
        content: const Text('이 대화 전체를 삭제할까요?\n복구할 수 없습니다.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final msgSnap = await widget.historyDoc.collection('messages').get();
      for (final doc in msgSnap.docs) {
        await doc.reference.delete();
      }
      await widget.historyDoc.delete();
      await _AudioDiskCache.clearRoom(widget.historyDoc.id);
    } catch (e) {
      debugPrint('[deleteHistoryRoom] $e');
    }
    if (!mounted) return;
    context.pushReplacementNamed('ChatHistory');
  }

  Future<void> _openAdjacentHistoryInSameMode(int offset) async {
    if (_isOpeningAdjacentHistory || (offset != -1 && offset != 1)) return;
    _resumeHistoryFromUserAction();
    setState(() {
      _isOpeningAdjacentHistory = true;
      _openingHistoryOffset = offset;
    });
    try {
      var currentData = _cachedRoomData;
      if (currentData == null) {
        final currentSnapshot = await widget.historyDoc.get();
        currentData = currentSnapshot.data() as Map<String, dynamic>?;
      }
      final currentModeKey = _historyModeKey(currentData);
      final snapshot = await widget.historyDoc.parent
          .orderBy('is_pinned', descending: true)
          .orderBy('created_at', descending: true)
          .get();

      final sameModeDocs = snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        return data?['last_message'] != null &&
            _historyModeKey(data) == currentModeKey;
      }).toList();
      final currentIndex =
          sameModeDocs.indexWhere((doc) => doc.id == widget.historyDoc.id);
      final adjacentIndex = currentIndex + offset;
      final DocumentSnapshot? adjacentDoc = currentIndex >= 0 &&
              adjacentIndex >= 0 &&
              adjacentIndex < sameModeDocs.length
          ? sameModeDocs[adjacentIndex]
          : null;

      if (!mounted) return;
      if (adjacentDoc == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              offset < 0 ? '같은 모드의 이전 대화가 없습니다.' : '같은 모드의 다음 대화가 없습니다.',
            ),
            duration: Duration(seconds: 1),
          ),
        );
        return;
      }
      context.pushReplacementNamed(
        'ChatDetail',
        queryParameters: {
          'historyRef': serializeParam(
              adjacentDoc.reference, ParamType.DocumentReference),
        }.withoutNulls,
      );
    } catch (e) {
      debugPrint('[openAdjacentHistoryInSameMode] $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              offset < 0 ? '이전 대화를 불러오지 못했습니다.' : '다음 대화를 불러오지 못했습니다.',
            ),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningAdjacentHistory = false;
          _openingHistoryOffset = 0;
        });
      }
    }
  }

  // 📦 [Box 9: 헬퍼 - 룸 데이터 및 원격 키 호출]
  Future<void> _fetchRoomData() async {
    try {
      var doc = await widget.historyDoc.get();
      if (doc.exists && doc.data() != null) {
        var data = doc.data() as Map<String, dynamic>;
        _cachedRoomData = data;
        roomName = data['room_name'] ?? "History Master";
        // 세션 생성 당시 보존된 언어 식별값(있으면 동일 언어 판정에 사용)
        _sessionNativeLang = data['native_lang'] as String?;
        _sessionTargetLang = data['target_lang'] as String?;
        // 🧩 [CANONICAL] 이 방이 듀오 통화였다면 공유 결과를 한 번 맞춰 본다.
        //   통화가 끝나는 순간 못 옮겼어도(앱을 먼저 껐거나 결과가 늦게
        //   완성됐거나) 방을 열 때 여기서 따라잡는다. 같은 판이면 아무것도
        //   하지 않는다.
        unawaited(_syncDuoCanonical(data));
        _scheduleMissingTargetGeneration(_cachedDocs);
      }
    } catch (e) {
      debugPrint("[fetchRoomData] $e");
    }
    if (mounted) setState(() => isLoadingRoom = false);
  }

  /// 공유 결과를 내 방에 맞춘다. 옛 방(`duo_room_id` 없음)은 그냥 지나간다.
  Future<void> _syncDuoCanonical(Map<String, dynamic> room) async {
    final String roomId = (room[kDuoRoomIdField] ?? '').toString().trim();
    if (roomId.isEmpty) return;
    final int? applied = (room[kDuoCanonicalVersionField] as num?)?.toInt();
    final bool changed = await applyDuoCanonicalToHistory(
      historyRef: widget.historyDoc.withConverter<Map<String, dynamic>>(
        fromFirestore: (snap, _) => snap.data() ?? <String, dynamic>{},
        toFirestore: (value, _) => value,
      ),
      roomId: roomId,
      appliedVersion: applied,
    );
    if (changed && mounted) {
      // 줄이 바뀌었으니 배울글을 다시 살펴야 한다. 스트림이 새 문서를
      // 실어 오면 그때 빠진 타겟을 만든다.
      debugPrint('[HISTORY] canonical_applied room=$roomId');
    }
  }

  Future<void> _fetchRemoteConfig({bool force = false}) async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      if (force) {
        // 사용자가 직접 누른 재시도다. 앱 시작 때 잡아 둔 1시간 캐시 간격에
        // 걸리면 같은 빈 키를 또 받아와서, 재시도 버튼이 아무 일도 안 한다.
        await remoteConfig.setConfigSettings(RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 20),
          minimumFetchInterval: Duration.zero,
        ));
      }
      await remoteConfig.fetchAndActivate();
      if (mounted) {
        setState(() {
          _apiKey = remoteConfig.getString('OpenAIAPIKey');
          _deepgramKey = remoteConfig.getString('DeepgramAPIKey');
        });
        _scheduleMissingTargetGeneration(_cachedDocs);
      }
    } catch (e) {
      debugPrint("[fetchRemoteConfig] $e");
    }
  }

  /// 이미 다시 쓰인 원문을 되돌린 줄. 한 세션에 한 줄당 한 번이다.
  final Set<String> _originRepairReverted = <String>{};

  /// 📝 [ORIGIN-REPAIR-REVERT] 예전에 모델이 통째로 다시 써 버린 원문을
  /// 전사 원문으로 되돌린다.
  ///
  /// 되돌릴 근거는 `original_text_raw`에 그대로 남아 있다. 교정이라 부를 만한
  /// 작은 손질이면 그대로 두고, 문장이 바뀐 줄만 되돌린다.
  ///
  /// **배울글도 함께 비운다.** 그 번역은 다시 쓰인 문장에서 나온 것이라,
  /// 원문만 되돌리면 두 줄이 서로 다른 이야기를 하게 된다. 비워 두면 아래
  /// 생성기가 되돌린 원문으로 곧바로 다시 만든다.
  void _revertOverreachingOriginRepairs(List<DocumentSnapshot> docs) {
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final raw = (data['original_text_raw'] ?? '').toString().trim();
      if (raw.isEmpty) continue;
      final current = (data['original_text'] ?? '').toString().trim();
      if (current.isEmpty || current == raw) continue;
      if (isMinimalTranscriptRepair(raw, current)) continue;
      if (!_originRepairReverted.add(doc.id)) continue;
      debugPrint('[ORIGIN-REPAIR] reverted msg=${doc.id} '
          '"$current" → "$raw"');
      unawaited(doc.reference.update(<String, dynamic>{
        'original_text': raw,
        'translated_text': '',
        'origin_repair_reverted_at': FieldValue.serverTimestamp(),
      }).catchError((Object e) {
        debugPrint('[ORIGIN-REPAIR] revert_failed msg=${doc.id} $e');
      }));
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // 🔎 [HISTORY-DIAG] 배울글이 **어디서** 잘못 실렸는지 남긴다.
  //
  //   화면만 보고는 세 가지를 가릴 수 없다.
  //     ① 대화방이 저장할 때 이미 원문이 배울글 자리에 실려 있었다
  //        → `by=none` (공부방이 만든 적이 없다)
  //     ② 공부방이 "번역할 게 없다"고 보고 원문을 복사했다
  //        → `by=copy`
  //     ③ 공부방이 번역을 불렀는데 원문 언어가 돌아왔다
  //        → `by=gpt-4o-mini`
  //
  //   본문은 앞 24자까지만 찍는다 — 로그가 대화록이 되면 안 된다.
  // ══════════════════════════════════════════════════════════════════
  final Set<String> _diagLoggedDocs = <String>{};
  bool _diagLoggedRoom = false;

  static String _diagCut(Object? value) {
    final text = (value ?? '').toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return '';
    return text.length <= 24 ? text : '${text.substring(0, 24)}…';
  }

  void _logHistoryDiagnostics(List<DocumentSnapshot> docs) {
    // 방 문서가 아직 안 왔으면 언어 값이 비어 찍힌다. 다음 스냅샷에 다시 본다.
    if (!_diagLoggedRoom && _cachedRoomData != null) {
      _diagLoggedRoom = true;
      debugPrint('[HISTORY-DIAG] room=${widget.historyDoc.id} '
          'mode=${_inferHistoryMode(_cachedRoomData)} '
          'native=${_sessionNativeLang ?? '-'} '
          'target=${_sessionTargetLang ?? '-'} '
          'roomSameLang=$_recordSameLang '
          'deferred=$_usesDeferredHistoryTargets '
          'key=${_apiKey.isEmpty ? 'missing' : 'ok'}');
    }
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      if (!_diagLoggedDocs.add(doc.id)) continue;
      debugPrint('[HISTORY-DIAG] msg=${doc.id} '
          'role=${data['role'] ?? '-'} '
          'duo=${data['duo_mode'] ?? '-'} '
          'src=${data['source_lang'] ?? '-'} '
          'by=${data['target_generated_by'] ?? 'none'} '
          'tgt="${_diagCut(data['translated_text'])}" '
          'org="${_diagCut(data['original_text'])}" '
          'raw="${_diagCut(data['original_text_raw'])}"');
    }
  }

  void _scheduleMissingTargetGeneration(List<DocumentSnapshot> docs) {
    if (!_usesDeferredHistoryTargets || docs.isEmpty) return;
    // 🎫 배울글은 GPT가 만든다 = 새 비용이다. 못 만드는 사람에게는 원문이
    //   그대로 남고 배지만 붙는다 — 자기가 한 말은 그대로 보인다.
    if (!_paidStudySilentlyAllowed('target_generation')) return;
    _revertOverreachingOriginRepairs(docs);
    // 키를 아직 못 받았다. 원격 설정이 안 내려온 것뿐이라 곧 풀릴 수도 있지만,
    // 그 사이 화면은 "번역이 없는 줄"을 정상인 것처럼 보여준다. 실패로 표시해
    // 두면 배지가 뜨고, `_fetchRemoteConfig`가 성공하면 다시 이 함수가 불려
    // 저절로 지워진다.
    if (_apiKey.isEmpty) {
      _markMissingTargetsFailed(docs, 'no_key');
      return;
    }
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      if (!_historyTargetNeedsWork(doc.id, data)) continue;
      unawaited(_generateAndCacheHistoryTarget(
        doc.reference,
        (data['original_text'] ?? '').toString().trim(),
        _sourceLangForMessage(data),
      ));
    }
  }

  /// 타겟이 비어 있는 줄을 한꺼번에 실패로 찍는다(요청조차 못 보낸 경우).
  void _markMissingTargetsFailed(List<DocumentSnapshot> docs, String kind) {
    bool changed = false;
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final original = (data['original_text'] ?? '').toString().trim();
      final translated = (data['translated_text'] ?? '').toString().trim();
      if (original.isEmpty || translated.isNotEmpty) continue;
      if (_targetFailures[doc.id] == kind) continue;
      _targetFailures[doc.id] = kind;
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  void _recordTargetFailure(String docId, String kind) {
    if (_targetFailures[docId] == kind) return;
    _targetFailures[docId] = kind;
    if (mounted) setState(() {});
  }

  void _clearTargetFailure(String docId) {
    if (_targetFailures.remove(docId) != null && mounted) setState(() {});
  }

  /// HTTP 응답 코드를 사용자에게 설명할 수 있는 실패 종류로 바꾼다.
  /// 401/403과 429는 원인이 다르다 — 하나는 키가 막힌 것, 하나는 한도다.
  String _targetFailureKindForStatus(int status) {
    if (status == 401 || status == 403) return 'auth';
    if (status == 429) return 'quota';
    if (status >= 500) return 'server';
    return 'http';
  }

  String _targetFailureLabel(String kind) {
    switch (kind) {
      case 'no_key':
        return '설정을 못 받았어요';
      case 'auth':
        return '번역 사용이 막혔어요';
      case 'quota':
        return '번역 한도를 넘었어요';
      case 'server':
        return '번역 서버가 응답하지 않아요';
      case 'network':
        return '연결이 끊겼어요';
      case 'empty':
        return '번역 결과가 비었어요';
      default:
        return '번역을 만들지 못했어요';
    }
  }

  /// 이 줄의 원문이 무슨 언어인지.
  ///
  /// Duo 직접 대화는 두 사람이 서로 다른 언어로 말하므로 줄마다 `source_lang`이
  /// 실려 온다. 그 값이 없으면 방 단위 Origin, 그것도 없으면 한국어로 본다
  /// (Origin을 저장하지 않던 시절 기록과의 호환).
  ///
  /// ⚠️ **선언보다 글자가 우선이다.** `source_lang`은 말한 사람이 로비에 적어
  /// 둔 값일 뿐이라, 상대가 그 설정과 다른 언어로 말하면 그대로 어긋난다.
  /// 한국어로 말한 줄이 English로 실려 오면 배울언어(English)와 같아져
  /// "번역할 게 없다"로 판정되고, 한국어가 배울글 자리에 복사된다.
  /// 2026-08-28 실기기에서 게스트 줄 하나가 정확히 그렇게 찍혔다
  /// (`model=copy src=English tgt=English`, 본문은 "책 얘기도 하고").
  /// 한글·가나·한자·키릴처럼 글자만으로 확정되는 경우에는 글자를 따르고,
  /// 라틴 문자끼리는 가릴 수 없으므로 선언을 그대로 쓴다.
  String _sourceLangForMessage(Map<String, dynamic>? data) {
    final text = (data?['original_text'] ?? '').toString();
    final verdict = detectOriginScript(text);
    if (verdict.decisive && verdict.language != null) return verdict.language!;
    final perMessage = (data?['source_lang'] ?? '').toString().trim();
    if (perMessage.isNotEmpty) return perMessage;
    final session = (_sessionNativeLang ?? '').trim();
    return session.isNotEmpty ? session : 'Korean';
  }

  /// 잘못 실린 배울글을 고쳐 쓴 줄. **한 세션에 한 줄당 한 번뿐이다.**
  ///
  /// 고쳐 쓰면 문서가 바뀌고, 바뀐 문서는 StreamBuilder를 다시 돌린다. 그
  /// 자리에서 또 "어긋난다"고 판정하면 무한히 다시 만들게 된다 — 돈이 도는
  /// 자리라 반드시 한 번으로 끊는다.
  final Set<String> _targetRepairAttempted = <String>{};

  /// 이 줄의 배울글을 (다시) 만들어야 하는가.
  ///
  /// 비어 있으면 만든다. **채워져 있어도 그 글자가 배울 언어가 아니면 잘못
  /// 실린 것이다** — 위 선언 문제로 원문이 그대로 복사된 줄이 이미 저장되어
  /// 있다. 고쳐 쓰는 대상은 듀오 줄로 좁힌다(`duo_mode`). 다른 모드의 배울글은
  /// 대화 중에 이미 배울 언어로 만들어졌다.
  bool _historyTargetNeedsWork(String docId, Map<String, dynamic> data) {
    final original = (data['original_text'] ?? '').toString().trim();
    if (original.isEmpty) return false;
    final translated = (data['translated_text'] ?? '').toString().trim();
    if (translated.isEmpty) return true;
    if ((data['duo_mode'] ?? '').toString().trim().isEmpty) return false;
    if (_recordSameLang == true) return false;
    final target = (_sessionTargetLang ?? '').trim();
    if (!textContradictsLanguage(translated, target)) return false;
    return _targetRepairAttempted.add(docId);
  }

  Future<bool> _generateAndCacheHistoryTarget(
    DocumentReference messageRef,
    String originalText,
    String sourceLanguage,
  ) {
    final existing = _targetTranslationInFlight[messageRef.id];
    if (existing != null) return existing;
    final future = _performHistoryTargetGeneration(
        messageRef, originalText, sourceLanguage);
    _targetTranslationInFlight[messageRef.id] = future;
    // 진행 중 표시("번역 중")를 띄우고 지우기 위한 rebuild. 이 맵은 원래
    // 중복 요청 방지용이었고 화면에는 전혀 드러나지 않았다.
    if (mounted) setState(() {});
    return future.whenComplete(() {
      if (identical(_targetTranslationInFlight[messageRef.id], future)) {
        _targetTranslationInFlight.remove(messageRef.id);
      }
      if (mounted) setState(() {});
    });
  }

  /// 배지의 "다시 시도". 실패 원인에 따라 되짚는 자리가 다르다.
  ///
  /// 키를 못 받아 실패했으면 번역 요청을 다시 보내봐야 소용없다. 원격 설정부터
  /// 강제로 다시 받아야 한다.
  Future<void> _retryHistoryTarget(DocumentSnapshot doc) async {
    // 🎫 배지 자체는 잠긴 사람에게도 보인다(그 줄에 배울글이 없는 것은 사실
    //   이므로). 다만 "다시 시도"는 GPT를 부르는 자리라, 여기서 이유를
    //   말한다 — 눌러 봐야 "만들지 못했습니다"만 나오면 왜인지 알 수 없다.
    if (!_guardPaidStudy()) return;
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return;
    final original = (data['original_text'] ?? '').toString().trim();
    if (original.isEmpty) return;
    _resumeHistoryFromUserAction();
    if (_apiKey.isEmpty) {
      await _fetchRemoteConfig(force: true);
      if (!mounted) return;
      if (_apiKey.isEmpty) {
        _showRoomEntryToast('설정을 아직 받지 못했습니다. 잠시 후 다시 시도해 주세요');
        return;
      }
    }
    _clearTargetFailure(doc.id); // 배지 → "번역 중"으로 바뀐다
    final ok = await _generateAndCacheHistoryTarget(
      doc.reference,
      original,
      _sourceLangForMessage(data),
    );
    if (!mounted || ok) return;
    _showRoomEntryToast(
        '번역을 다시 만들지 못했습니다 · ${_targetFailureLabel(_targetFailures[doc.id] ?? '')}');
  }

  /// 원문 교정에 쓸 앞뒤 대화.
  ///
  /// 한 줄만 보고는 "우리 병 중에서"가 잘못 적힌 것인지 알 수 없다. 앞뒤에
  /// 총무·작가 이야기가 있어야 "병"이 "반"이었음을 복원할 수 있다.
  /// 지금 줄 자체는 뺀다 — 고쳐야 할 대상이지 근거가 아니다.
  String _historyRepairContext(DocumentReference messageRef) {
    final docs = _cachedDocs;
    final idx = docs.indexWhere((d) => d.reference.id == messageRef.id);
    if (idx < 0) return '';
    const int window = 4;
    // 🧭 [CAST] 등장인물은 대화 첫머리에서 정해진다("둘째가 집에 들어와 있어").
    //   창이 뒤로 밀려 그 줄이 빠지면, 주어를 생략한 뒷줄이 전부 말한 사람
    //   얘기로 번역된다("지금 취업 준비 중이야" → "I'm preparing..."). 그래서
    //   앞머리는 창 밖이어도 항상 싣는다.
    const int openingLines = 2;
    final int start = idx - window < 0 ? 0 : idx - window;
    final int end =
        idx + window + 1 > docs.length ? docs.length : idx + window + 1;
    final picked = <int>{};
    for (int i = 0; i < openingLines && i < docs.length; i++) {
      picked.add(i);
    }
    for (int i = start; i < end; i++) {
      picked.add(i);
    }
    final ordered = picked.toList()..sort();
    final buffer = StringBuffer();
    int? previous;
    for (final i in ordered) {
      // 번역할 줄 자체는 빼되, 자리는 이어진 것으로 친다(생략 표시 방지).
      if (i == idx) {
        previous = i;
        continue;
      }
      final data = docs[i].data() as Map<String, dynamic>?;
      if (data == null) continue;
      final text = (data['original_text'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      // 앞머리와 창 사이가 떨어져 있으면 끊긴 자리를 알려 준다.
      if (previous != null && i > previous + 1) buffer.writeln('...');
      final role = (data['role'] ?? '').toString().toUpperCase();
      buffer.writeln('${role == 'HOST' ? 'USER' : 'AI'}: $text');
      previous = i;
    }
    return buffer.toString().trim();
  }

  Future<bool> _performHistoryTargetGeneration(
    DocumentReference messageRef,
    String originalText,
    String sourceLanguage,
  ) async {
    if (!_paidStudySilentlyAllowed('target_generation')) return false;
    final source = originalText.trim();
    if (source.isEmpty) return false;
    if (_apiKey.isEmpty) {
      _recordTargetFailure(messageRef.id, 'no_key');
      return false;
    }
    try {
      final targetLanguage = (_sessionTargetLang ?? 'English').trim();
      final sourceName =
          sourceLanguage.trim().isEmpty ? 'Korean' : sourceLanguage.trim();
      // 원문과 타겟이 같은 언어면 번역할 게 없다. 방 단위 판정(_recordSameLang)에
      // 더해 줄 단위 출발 언어도 본다 — Duo 직접 대화는 줄마다 언어가 다르다.
      final sameLanguage = _recordSameLang == true ||
          _normLangCode(sourceName) == _normLangCode(targetLanguage);
      String targetText = source;
      // 문맥으로 되살린 원문. 교정할 게 없으면 source와 같게 돌아온다.
      String repairedOriginal = '';
      // 🎨 [AI-STYLE] 로비에서 고른 스타일. 영어 타겟이 아니면 빈 문자열이라
      //   프롬프트가 예전과 한 글자도 달라지지 않는다. 교정된 원어 줄에는
      //   절대 걸리면 안 되므로 scope로 번역문만 지목한다.
      final String styleBlock = aiStylePromptBlock(
        targetLang: targetLanguage,
        scope: 'the "target" translation, '
            'never the corrected $sourceName line',
      );
      final String context = _historyRepairContext(messageRef);
      final String lineBlock = 'LINE: $source';
      final String userContent = context.isEmpty
          ? lineBlock
          : 'SURROUNDING CONVERSATION:\n$context\n\n$lineBlock';
      if (!sameLanguage) {
        final response = await http
            .post(
              Uri.parse('https://api.openai.com/v1/chat/completions'),
              headers: <String, String>{
                'Authorization': 'Bearer $_apiKey',
                'Content-Type': 'application/json; charset=utf-8',
              },
              body: jsonEncode(<String, dynamic>{
                'model': kHistoryRepairModel,
                'temperature': 0.0,
                'max_tokens': 220,
                'response_format': <String, String>{'type': 'json_object'},
                'messages': <Map<String, String>>[
                  <String, String>{
                    'role': 'system',
                    'content':
                        '''You are preparing ONE line of a saved voice conversation for a language-learning review screen.

The line came from speech recognition, so a word may have been misheard. Use the surrounding lines to restore what the speaker actually said, then translate that.

CORRECTED $sourceName LINE — rules:
- Fix ONLY words speech recognition clearly got wrong. The signal is a word that makes no sense in this conversation.
- Never rephrase, polish, shorten, expand, or change the speaker's wording, style, tone, or politeness level.
- Never add or remove information, and never invent a name, number, or fact.
- Keep the word count identical. Replace at most one or two clearly misheard words, each with a similar-sounding word. If more than that looks off, the line was NOT misheard — return it EXACTLY as given.
- Changing a particle, an ending, the word order, the subject, or who does what to whom is NOT a correction. It is a rewrite, and a rewrite is forbidden here.
- If nothing is clearly wrong, return the line EXACTLY as given.

TRANSLATION — natural spoken $targetLanguage of the corrected line. Preserve the speaker viewpoint, meaning, tone, and relationship.

WHO THE LINE IS ABOUT — read this before you translate:
- $sourceName leaves out the subject and the object whenever they are already understood. $targetLanguage cannot. You must supply them, and SURROUNDING CONVERSATION is where they are.
- Whoever the conversation is currently about stays the subject until the speaker moves to someone else. A line with no subject continues to be about that person — NOT about the speaker.
- Never fall back on "I" just because the subject is missing. Use "I" only when the line is genuinely about the speaker.
- The people in this conversation are introduced in its opening lines. Settle who they are there first, then keep them straight through every line.
- Keep each person's relationship to the speaker exactly as stated. Do not promote, demote, or merge them, and do not invent one who was never mentioned.
- These subject rules serve the TRANSLATION only. Never reach back and change the corrected $sourceName line to match them.
Reply as JSON: {"original": "<corrected $sourceName line>", "target": "<$targetLanguage translation>"}$styleBlock''',
                  },
                  <String, String>{
                    'role': 'user',
                    'content': userContent,
                  },
                ],
              }),
            )
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) {
          debugPrint(
              '[HISTORY-TARGET] status=${response.statusCode} msg=${messageRef.id}');
          _recordTargetFailure(
              messageRef.id, _targetFailureKindForStatus(response.statusCode));
          return false;
        }
        final body =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final choices = body['choices'] as List? ?? const <dynamic>[];
        final firstChoice =
            choices.isEmpty ? null : choices.first as Map<String, dynamic>?;
        final message = firstChoice?['message'] as Map<String, dynamic>?;
        final content = (message?['content'] ?? '').toString().trim();
        // JSON이 깨져 오면 교정은 포기하고 번역만 살린다. 원문을 못 고치는
        // 것보다 줄이 통째로 비는 쪽이 훨씬 나쁘다.
        try {
          final parsed = jsonDecode(content) as Map<String, dynamic>;
          targetText = (parsed['target'] ?? '').toString().trim();
          repairedOriginal = (parsed['original'] ?? '').toString().trim();
        } catch (_) {
          debugPrint('[HISTORY-TARGET] json_parse_failed msg=${messageRef.id}');
          targetText = content;
        }
      }
      if (targetText.isEmpty) {
        _recordTargetFailure(messageRef.id, 'empty');
        return false;
      }
      // 📝 [ORIGIN-REPAIR] 전사가 잘못 들은 낱말을 문맥으로 되살린다.
      //   대화방에서는 손대지 않는다 — 실장님 지시(2026-08-18). 히스토리는
      //   학습 자료라, 원문이 깨진 채로 남으면 그걸 보고 외우게 된다.
      //
      //   **원본 전사는 지우지 않는다.** `original_text_raw`에 남겨 두어야
      //   교정이 잘못됐을 때 되짚을 수 있고, 무엇이 어떻게 들렸는지도 남는다.
      // 🛡️ 받은 교정문이 **교정인지 다시 쓴 문장인지**를 본다. 프롬프트로
      //   못 박아도 모델은 종종 문장을 통째로 바꾼다. 그때는 전사 원문을
      //   지킨다 — 못 고친 낱말이 남는 편이, 하지 않은 말이 남는 것보다 낫다.
      final bool overreach = repairedOriginal.isNotEmpty &&
          repairedOriginal != source &&
          !isMinimalTranscriptRepair(source, repairedOriginal);
      if (overreach) {
        debugPrint('[ORIGIN-REPAIR] rejected msg=${messageRef.id} '
            '"$source" ↛ "$repairedOriginal"');
      }
      final bool repaired = repairedOriginal.isNotEmpty &&
          repairedOriginal != source &&
          !overreach;
      await messageRef.update(<String, dynamic>{
        'translated_text': targetText,
        if (repaired) 'original_text': repairedOriginal,
        if (repaired) 'original_text_raw': source,
        if (repaired) 'original_repaired_at': FieldValue.serverTimestamp(),
        'target_generated_by': sameLanguage ? 'copy' : kHistoryRepairModel,
        'target_generated_at': FieldValue.serverTimestamp(),
      });
      if (repaired) {
        debugPrint('[ORIGIN-REPAIR] msg=${messageRef.id} '
            '"$source" → "$repairedOriginal"');
      }
      debugPrint('[HISTORY-TARGET] generated msg=${messageRef.id} '
          'model=${sameLanguage ? 'copy' : 'gpt-4o-mini'} '
          'src=$sourceName tgt=$targetLanguage '
          'roomSameLang=$_recordSameLang repaired=$repaired');
      _clearTargetFailure(messageRef.id);
      return true;
    } catch (error) {
      debugPrint(
          '[HISTORY-TARGET] failed msg=${messageRef.id} reason=${error.runtimeType}');
      _recordTargetFailure(messageRef.id, 'network');
      return false;
    }
  }

  Future<void> _ensureHistoryTargets(List<DocumentSnapshot> docs) async {
    if (!_usesDeferredHistoryTargets || _apiKey.isEmpty) return;
    final tasks = <Future<bool>>[];
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      if (_historyTargetNeedsWork(doc.id, data)) {
        tasks.add(_generateAndCacheHistoryTarget(
          doc.reference,
          (data['original_text'] ?? '').toString().trim(),
          _sourceLangForMessage(data),
        ));
      }
    }
    if (tasks.isNotEmpty) await Future.wait(tasks);
  }

  // 📦 [Box 10: 헬퍼 - 권한 요청]
  Future<void> _initPermissions() async {
    await [Permission.microphone].request();
  }

  // 📦 [Box 11-Room: 방 단위 진입]
  //   저장된 대화를 역할 교환 Practice로 연다. 그 다음 단계인
  //   MY SPEECH / NATIVE ENGLISH는 Practice 화면의 버튼에서 시작한다.
  Future<void> _enterShadowingFromRoom() async {
    if (_isEnteringPractice) return;
    if (!_guardPaidStudy()) return;
    _resumeHistoryFromUserAction();
    if (mounted) setState(() => _isEnteringPractice = true);
    try {
      // 🔄 [FRESH-ROOM] 캐시를 믿지 않는다.
      //
      //   방 문서에는 대화가 끝난 뒤 백그라운드에서 쓰이는 값이 있다. 반면
      //   `_cachedRoomData`는 히스토리 화면이 열릴 때 한 번 읽은 값이라 그
      //   사이에 쓰인 것이 빠져 있다. 문서 하나 더 읽는 값을 치른다.
      var data = _cachedRoomData;
      try {
        final fresh = await widget.historyDoc.get();
        if (!mounted) return;
        final freshData = fresh.data() as Map<String, dynamic>?;
        if (freshData != null) {
          data = freshData;
          _cachedRoomData = freshData;
        }
      } catch (e) {
        debugPrint('[enterShadowing] room refetch $e');
      }
      if (data == null) {
        final snap = await widget.historyDoc.get();
        if (!mounted) return;
        data = snap.data() as Map<String, dynamic>?;
        _cachedRoomData = data;
      }

      if (data == null) {
        _showRoomEntryToast("연습할 대화가 없습니다");
        return;
      }

      _cachedRoomMode = _inferHistoryMode(data);

      // 대화 재생 연습(Practice)으로 들어간다. MY SPEECH / NATIVE ENGLISH는
      // Practice가 끝난 뒤 [_buildMySpeechFromConversation]이 만든다.
      await _remoteConfigFuture;
      var messageDocs = _cachedDocs;
      if (messageDocs.isEmpty) {
        final messagesSnap = await widget.historyDoc
            .collection('messages')
            .orderBy('created_at', descending: false)
            .get();
        messageDocs = _visibleMessages(messagesSnap.docs);
        _cachedDocs = messageDocs;
      }
      await _ensureHistoryTargets(messageDocs);
      final refreshedMessages = await widget.historyDoc
          .collection('messages')
          .orderBy('created_at', descending: false)
          .get();
      messageDocs = _visibleMessages(refreshedMessages.docs);
      _cachedDocs = messageDocs;
      if (!mounted) return;

      // 타겟을 끝내 못 만든 줄이 몇 개인지 먼저 센다.
      //
      // ⚠️ 아래 `?? original_text` 폴백은 **필드가 null일 때만** 돈다. Duo 직접
      //    대화는 `translated_text`를 빈 문자열로 저장하므로 폴백이 돌지 않고,
      //    그 줄은 아래 `where`에서 조용히 빠진다. 모국어를 따라 읽히지 않는
      //    결과 자체는 옳으니 동작은 그대로 두고, **몇 줄이 빠졌는지 알린다.**
      final int untranslatedCount = _usesDeferredHistoryTargets
          ? messageDocs.where((doc) {
              final d = doc.data() as Map<String, dynamic>;
              return (d['translated_text'] ?? '').toString().trim().isEmpty &&
                  (d['original_text'] ?? '').toString().trim().isNotEmpty;
            }).length
          : 0;

      final tutorLines = messageDocs
          .map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            return <String, dynamic>{
              'role': d['role'] ?? 'HOST',
              'text':
                  (d['translated_text'] ?? d['original_text'] ?? '').toString(),
            };
          })
          .where((m) => (m['text'] as String).isNotEmpty)
          .toList();

      if (tutorLines.isEmpty) {
        // 대화는 멀쩡히 쌓여 있는데 번역만 실패한 경우를 "대화가 없다"고
        // 말하면 안 된다. 사용자는 기록이 날아간 줄 안다.
        _showRoomEntryToast(untranslatedCount > 0
            ? "번역이 안 돼 연습할 수 없습니다. 대화 화면에서 '다시 시도'를 눌러 주세요"
            : "아직 연습할 대화가 없습니다");
        return;
      }

      if (untranslatedCount > 0) {
        _showRoomEntryToast("$untranslatedCount개 줄은 번역이 안 돼 연습에서 빠졌습니다");
      }

      // 🧹 듀오만 맞장구를 걷어낸다. 저장된 대화는 그대로 두고 연습 재료만
      //   추린다. 전부 맞장구인 방이면 거르지 않는다 — 연습할 것이 없어진다.
      var practiceLines = tutorLines;
      int droppedBackchannels = 0;
      if (_inferHistoryMode(_cachedRoomData) == 'duo') {
        final kept = tutorLines
            .where((m) => !_isBackchannelOnly(m['text'] as String))
            .toList();
        if (kept.isNotEmpty) {
          droppedBackchannels = tutorLines.length - kept.length;
          practiceLines = kept;
        }
      }
      if (droppedBackchannels > 0 && untranslatedCount == 0) {
        _showRoomEntryToast('맞장구 $droppedBackchannels줄은 연습에서 뺐습니다');
      }

      _tutorLines = practiceLines;

      // 🗂️ 저장돼 있으면 카드에 미리 보인다. 판이 다른 옛 값은 안 읽는다 —
      //   이름 있는 상대까지 보는 정밀 검사는 카드를 누를 때 한 번 더 한다.
      final bool storedSchemaOk =
          _historyString(data, 'speech_schema_version') ==
              _kSpeechSchemaVersion;
      final String storedMySpeech =
          storedSchemaOk ? _historyString(data, 'my_speech') : '';
      final String storedNativeEnglish =
          storedSchemaOk ? _historyString(data, 'native_english') : '';

      if (mounted) {
        setState(() {
          isPracticeMode = true;
          _phase = ShadowingPhase.studySelect;
          _mySpeech = storedMySpeech;
          _nativeEnglish =
              _canReuseStoredNativeEnglish(storedNativeEnglish, storedMySpeech)
                  ? storedNativeEnglish
                  : '';
          _mySpeechError = null;
          _nativeEnglishError = null;
          currentIndex = 0;
          _isAutoRecording = false;
          _tutorAwaitingStart = true;
          _swapRoles = false;
          _tutorAiSpeaking = false;
          _tutorUserRecording = false;
          _tutorPlayingFullback = false;
        });
      }
    } catch (e) {
      _showRoomEntryToast("연습 진입 실패: $e");
    } finally {
      if (mounted) setState(() => _isEnteringPractice = false);
    }
  }

  // 🆕 [TUTOR] 진입/차단 토스트 헬퍼
  void _showRoomEntryToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF2C2C2E),
      ),
    );
  }

  // ── 🎫 [STUDY-GATE] 보기는 열고, 새 비용만 막는다 ──────────────────────
  //
  //   대화 내용·타임라인·이미 만들어 둔 소리는 누구에게나 보인다. 막는 것은
  //   **지금 새로 돈이 나가는 동작**뿐이다 — TTS 생성, GPT 재가공, 녹음 전사,
  //   에코잉·쉐도잉·연습.
  //
  //   두 겹으로 막는다.
  //     ① 눈에 보이는 겹 — 버튼을 흐리게 두고 누르면 이유를 말한다.
  //        눌러도 아무 일이 없는 버튼은 만들지 않는다.
  //     ② 손에 잡히는 겹 — 실제로 API를 부르는 함수 앞에서 한 번 더 막는다.
  //        자동으로 도는 것(빠진 배울글 생성 등)은 버튼을 거치지 않는다.
  //
  //   판정은 `services/study_access.dart` 한 곳에서 온다. 과금 티커도 같은
  //   자리를 보므로 "버튼은 열렸는데 차감만 막힌" 구간이 생기지 않는다.

  StudyAccess get _studyAccess => currentStudyAccess();

  bool get _paidStudyAllowed => _studyAccess.canUsePaidStudy;

  /// 눌린 버튼에서 부른다. 막혔으면 이유를 알리고 false.
  bool _guardPaidStudy() {
    final access = _studyAccess;
    if (access.canUsePaidStudy) return true;
    _showRoomEntryToast(access.gateLabel);
    debugPrint('[STUDY-GATE] blocked reason=${access.reason.name}');
    return false;
  }

  /// 자동 경로·네트워크 함수 앞에서 부른다. 조용히 막는다 — 화면이 스스로
  /// 부른 일이라 알릴 사람이 없다.
  bool _paidStudySilentlyAllowed(String what) {
    if (_paidStudyAllowed) return true;
    debugPrint('[STUDY-GATE] skipped $what '
        'reason=${_studyAccess.reason.name}');
    return false;
  }

  // 🆕 [TUTOR] 사용자가 종료/중단할 때 호출
  void _stopTutorPlayback() {
    resetBillingIdle();
    _tutorAudioPlayer?.stop();
    if (mounted) {
      setState(() {
        _isTutorPlaying = false;
      });
    }
  }

  // 역할 선택 안내 말풍선 (2.8초 후 자동 사라짐)
  void _showRoleSelectBubble() {
    if (!mounted) return;
    setState(() => _showRoleBubble = true);
    HapticFeedback.mediumImpact();
    _roleBubbleTimer?.cancel();
    _roleBubbleTimer = Timer(const Duration(milliseconds: 2800), () {
      if (mounted) setState(() => _showRoleBubble = false);
    });
  }

  // 📦 [BOX-30: 시작 화면 - 선택값 반영하여 진행]
  void _confirmStart({required bool swap}) {
    _resumeHistoryFromUserAction();
    if (mounted) {
      setState(() {
        _swapRoles = swap;
        _tutorAwaitingStart = false;
      });
    }
    _startTurnPractice();
  }

  // ============================================================================
  // 📦 [Box 11-C: 양방향 턴제 연습 엔진 (Turn-Based Practice)]
  // ============================================================================

  void _startTurnPractice() {
    _resumeHistoryFromUserAction();
    if (!mounted || _tutorLines.isEmpty) return;
    currentIndex = 0;
    // currentIndex는 화면이 읽는 값이라 여기서 한 번 다시 그린다.
    if (mounted) setState(() {});
    // 목록을 controller로 먼저 맨 위에 되돌린다. 끝까지 내려간 상태에서는
    // ListView.builder가 아이템 0을 버려 `_practiceItemKeys[0]`의 context가
    // null이고, 그러면 아래 `_scrollPracticeToIndex(0)`이 조용히 아무것도
    // 하지 않는다 — 소리는 첫 대사인데 화면만 끝에 남는다.
    if (_practiceScrollController.hasClients) {
      _practiceScrollController.jumpTo(0);
    }
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollPracticeToIndex(0));
    _checkAndStartTurn();
  }

  void _nextTurn() {
    BillingTicker.instance.resumeFromActivity('history_practice_next');
    if (!mounted || !isPracticeMode || isPaused) return;
    final next = currentIndex + 1;
    if (next >= _tutorLines.length) {
      if (mounted) {
        setState(() {
          currentIndex = next;
          _turnPracticeRetryCount = 0;
          _showRetryHint = false;
        });
        // 🆕 [BOX-34] 완료: 자동 종료 대신 완료 화면 표시
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scrollPracticeToIndex(_tutorLines.length - 1));
      }
      return;
    }
    if (mounted)
      setState(() {
        currentIndex = next;
        _turnPracticeRetryCount = 0;
        _showRetryHint = false;
      });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollPracticeToIndex(next));
    _checkAndStartTurn();
  }

  void _checkAndStartTurn() {
    if (!mounted || !isPracticeMode || isPaused) return;
    if (currentIndex >= _tutorLines.length) return;
    final line = _tutorLines[currentIndex];
    final bool isAiTurn = _isAiTurn(line); // 🆕 [BOX-32]
    if (isAiTurn) {
      _checkAndPlayAILine();
    } else {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && isPracticeMode && !isPaused && !_isAutoRecording) {
          _startAutoVADRecording();
        }
      });
    }
  }

  Future<void> _checkAndPlayAILine() async {
    if (!mounted || !isPracticeMode || currentIndex >= _tutorLines.length)
      return;
    final text = (_tutorLines[currentIndex]['text'] as String).trim();
    if (text.isEmpty) {
      _nextTurn();
      return;
    }
    final voice = _practiceVoiceForLine(_tutorLines[currentIndex]);
    if (mounted) setState(() => _tutorAiSpeaking = true); // 🆕 [BOX-31]
    await _playSmartAudio(text, voice: voice);
  }

  // 🔧 [v3.7] TtsCache 우선 조회 → MISS 시 API 호출 후 캐시 저장
  Future<void> _playSmartAudio(
    String text, {
    String voice = _historyPracticeAiVoice,
  }) async {
    _resumeHistoryFromUserAction();
    text = text.trim();
    if (text.isEmpty) {
      if (mounted && isPracticeMode) {
        setState(() => _tutorAiSpeaking = false);
        _nextTurn();
      }
      return;
    }
    try {
      Uint8List? audio = await _getOrFetchPracticeTTS(text, voice);
      if (audio == null) {
        if (_apiKey.isEmpty) {
          if (mounted && isPracticeMode) {
            setState(() => _tutorAiSpeaking = false);
            _nextTurn();
          }
          return;
        }
      }
      if (!mounted || !isPracticeMode) return;
      if (audio != null) {
        // 🆕 [BOX-34] AI 오디오 캐시 (turnPractice용)
        if (_phase == ShadowingPhase.turnPractice &&
            currentIndex < _tutorLines.length) {
          _tutorLines[currentIndex]['ai_audio_bytes'] = audio;
        }
        await audioPlayer.play(BytesSource(audio));
      } else {
        if (mounted) setState(() => _tutorAiSpeaking = false);
        _nextTurn();
      }
    } catch (e) {
      debugPrint("[playSmartAudio] $e");
      if (mounted && isPracticeMode) {
        setState(() => _tutorAiSpeaking = false);
        _nextTurn();
      }
    }
  }

  Future<void> _startAutoVADRecording() async {
    if (!mounted || !isPracticeMode || isPaused || _isAutoRecording) return;
    // 🎫 녹음은 곧 전사(STT) 요청이다.
    if (!_paidStudySilentlyAllowed('practice_recording')) return;
    final hasPermission = await appAudioRecorder.hasPermission();
    if (!hasPermission) return;
    if (mounted)
      setState(() {
        _isAutoRecording = true;
        if (_phase == ShadowingPhase.turnPractice)
          _tutorUserRecording = true; // 🆕 [BOX-31]
      });
    _hasSpoken = false;
    _silenceCounter = 0;
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/turn_${currentIndex}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await appAudioRecorder.start(
        const RecordConfig(
            encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1),
        path: path,
      );
      _silenceTimer?.cancel();
      _silenceTimer =
          Timer.periodic(const Duration(milliseconds: 100), (timer) async {
        if (!mounted || !isPracticeMode || !_isAutoRecording) {
          timer.cancel();
          return;
        }
        try {
          if (await appAudioRecorder.isRecording()) {
            final amp = await appAudioRecorder.getAmplitude();
            if (amp.current > -25.0) {
              _hasSpoken = true;
              _silenceCounter = 0;
            } else {
              _silenceCounter++;
              if (_hasSpoken && _silenceCounter >= 15) {
                timer.cancel();
                await _stopAutoVADRecordingAndProcess();
              } else if (!_hasSpoken && _silenceCounter >= 50) {
                timer.cancel();
                await appAudioRecorder.stop();
                if (mounted) setState(() => _isAutoRecording = false);
                if (mounted && isPracticeMode && !isPaused)
                  _startAutoVADRecording();
              }
            }
          } else {
            timer.cancel();
          }
        } catch (_) {
          timer.cancel();
        }
      });
    } catch (e) {
      debugPrint("[startAutoVADRecording] $e");
      if (mounted) setState(() => _isAutoRecording = false);
    }
  }

  Future<void> _stopAutoVADRecordingAndProcess() async {
    _silenceTimer?.cancel();
    final path = await appAudioRecorder.stop();
    BillingTicker.instance.resumeFromActivity('history_practice_stt_result');
    if (mounted)
      setState(() {
        _isAutoRecording = false;
        _tutorUserRecording = false; // 🆕 [BOX-31]
      });
    if (path != null && mounted && isPracticeMode && !isPaused) {
      await _processAutoVADRecording(path);
    } else {
      if (mounted && isPracticeMode && !isPaused) _startAutoVADRecording();
    }
  }

  void _stopAutoVADRecording() {
    _silenceTimer?.cancel();
    try {
      appAudioRecorder.stop();
    } catch (_) {}
    if (mounted)
      setState(() {
        _isAutoRecording = false;
        _tutorUserRecording = false; // 🆕 [BOX-31]
      });
  }

  String _normalizePracticeMatchText(String text) {
    var normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r"[’`´]"), "'")
        .replaceAll(RegExp(r"\bi'm\b"), "i am")
        .replaceAll(RegExp(r"\byou're\b"), "you are")
        .replaceAll(RegExp(r"\bwe're\b"), "we are")
        .replaceAll(RegExp(r"\bthey're\b"), "they are")
        .replaceAll(RegExp(r"\bhe's\b"), "he is")
        .replaceAll(RegExp(r"\bshe's\b"), "she is")
        .replaceAll(RegExp(r"\bit's\b"), "it is")
        .replaceAll(RegExp(r"\bdon't\b"), "do not")
        .replaceAll(RegExp(r"\bdoesn't\b"), "does not")
        .replaceAll(RegExp(r"\bdidn't\b"), "did not")
        .replaceAll(RegExp(r"\bcan't\b"), "cannot")
        .replaceAll(RegExp(r"\bcannot\b"), "can not")
        .replaceAll(RegExp(r"\bwon't\b"), "will not")
        .replaceAll(RegExp(r"\bwouldn't\b"), "would not")
        .replaceAll(RegExp(r"\bcouldn't\b"), "could not")
        .replaceAll(RegExp(r"\bshouldn't\b"), "should not")
        .replaceAll(RegExp(r"\bisn't\b"), "is not")
        .replaceAll(RegExp(r"\baren't\b"), "are not")
        .replaceAll(RegExp(r"\bwasn't\b"), "was not")
        .replaceAll(RegExp(r"\bweren't\b"), "were not")
        .replaceAll(RegExp(r"\bi've\b"), "i have")
        .replaceAll(RegExp(r"\byou've\b"), "you have")
        .replaceAll(RegExp(r"\bi'll\b"), "i will")
        .replaceAll(RegExp(r"\byou'll\b"), "you will")
        .replaceAll(RegExp(r"\bi'd\b"), "i would")
        .replaceAll(RegExp(r"\byou'd\b"), "you would");
    normalized = normalized.replaceAll(RegExp(r"[^a-z0-9\s]"), " ");
    return normalized.replaceAll(RegExp(r"\s+"), " ").trim();
  }

  Set<String> _practiceMatchWords(String text) {
    const weakWords = {'a', 'the', 'to', 'of', 'in', 'on'};
    return _normalizePracticeMatchText(text)
        .split(' ')
        .where((word) => word.length > 1 && !weakWords.contains(word))
        .toSet();
  }

  String _practicePhoneticKey(String word) {
    return word
        .replaceAll('th', 't')
        .replaceAll(RegExp(r'[rl]'), 'l')
        .replaceAll(RegExp(r'[bv]'), 'b')
        .replaceAll(RegExp(r'[pf]'), 'p')
        .replaceAll(RegExp(r'[tds]'), 't')
        .replaceAll(RegExp(r'[zj]'), 'j');
  }

  bool _practiceWordsMatch(String target, String spoken) {
    if (target == spoken) return true;
    if ((target.length - spoken.length).abs() > 2) return false;
    return _practicePhoneticKey(target) == _practicePhoneticKey(spoken);
  }

  double _practiceSimilarity(Set<String> targetWords, Set<String> spokenWords) {
    if (targetWords.isEmpty || spokenWords.isEmpty) return 0.0;
    var matched = 0;
    for (final target in targetWords) {
      if (spokenWords.any((spoken) => _practiceWordsMatch(target, spoken))) {
        matched++;
      }
    }
    return matched / targetWords.length;
  }

  Future<void> _playRetryPrompt() async {
    const prompt = '끝까지 다시 읽어 주세요';
    try {
      Uint8List? audio = _apiKey.isNotEmpty
          ? await _getOrFetchPracticeTTS(prompt, _historyPracticeAiVoice)
          : null;
      if (audio == null || !mounted || !isPracticeMode) return;
      final player = AudioPlayer();
      final completer = Completer<void>();
      late StreamSubscription sub;
      sub = player.onPlayerComplete.listen((_) {
        if (!completer.isCompleted) completer.complete();
        sub.cancel();
      });
      try {
        await player.play(BytesSource(audio));
        await completer.future
            .timeout(const Duration(milliseconds: 1800), onTimeout: () {});
      } finally {
        sub.cancel();
        await player.dispose();
      }
    } catch (e) {
      debugPrint("[playRetryPrompt] $e");
    }
  }

  Future<void> _processAutoVADRecording(String path) async {
    if (!mounted || !isPracticeMode || currentIndex >= _tutorLines.length)
      return;
    if (!_paidStudySilentlyAllowed('practice_stt')) return;
    final targetText = (_tutorLines[currentIndex]['text'] as String).trim();
    try {
      final uri = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $_apiKey';
      request.fields['model'] = 'whisper-1';
      request.fields['language'] = 'en';
      request.fields['prompt'] = targetText;
      request.files.add(await http.MultipartFile.fromPath('file', path));
      final streamed =
          await request.send().timeout(const Duration(seconds: 10));
      final body = await streamed.stream.bytesToString();
      if (!mounted || !isPracticeMode) return;
      if (streamed.statusCode == 200) {
        final transcript = (jsonDecode(body)['text'] as String? ?? '').trim();
        BillingTicker.instance
            .resumeFromActivity('history_practice_stt_result');
        final tWords = _practiceMatchWords(targetText);
        final sWords = _practiceMatchWords(transcript);
        final similarity = _practiceSimilarity(tWords, sWords);
        // [READ-THROUGH] 전체를 끝까지 읽었는지 판정
        // 8단어 미만: 음성 인식되면 통과
        // 8단어 이상: 60% 이상 매칭 필요
        final bool pass;
        if (tWords.length < 8) {
          pass = transcript.isNotEmpty && sWords.isNotEmpty;
        } else {
          pass =
              transcript.isNotEmpty && sWords.isNotEmpty && similarity >= 0.6;
        }
        if (pass) {
          _turnPracticeRetryCount = 0;
          // 🆕 [BOX-34] 유저 녹음 경로 캐시
          if (currentIndex < _tutorLines.length) {
            _tutorLines[currentIndex]['user_record_path'] = path;
          }
          _nextTurn();
        } else {
          _turnPracticeRetryCount++;
          final exceeded = _turnPracticeRetryCount >= 3;
          if (_phase == ShadowingPhase.turnPractice && mounted) {
            setState(() => _showRetryHint = true);
            await _playRetryPrompt();
            await Future.delayed(const Duration(milliseconds: 1200));
            if (mounted) setState(() => _showRetryHint = false);
          }
          if (!mounted || !isPracticeMode || isPaused) return;
          if (exceeded) {
            _turnPracticeRetryCount = 0;
            _nextTurn();
          } else {
            _startAutoVADRecording();
          }
        }
      } else {
        if (isPracticeMode && !isPaused) _startAutoVADRecording();
      }
    } catch (e) {
      debugPrint("[processAutoVADRecording] $e");
      if (mounted && isPracticeMode && !isPaused) _startAutoVADRecording();
    }
  }

  void _exitShadowing() {
    _deleteUserRecordings(); // 🆕 Practice 임시 녹음 파일 정리
    BillingTicker.instance.setRate(BillingRate.full);
    _stopTutorPlayback();
    _stopAutoVADRecording();
    _utteranceSafetyTimer?.cancel();
    _nativeEnglishRevealTimer?.cancel();
    unawaited(_stopP3Shadowing(resetSelection: true));
    _stopDeepgramListening();
    audioPlayer.stop();
    if (mounted) {
      setState(() {
        isPracticeMode = false;
        isPaused = false;
        _phase = ShadowingPhase.idle;
        _chunks = [];
        _inFlightChunkFetch.clear(); // 🔧 [STAMPEDE-FIX] 진행 중 fetch 정리
        _currentChunkIdx = 0;
        _isListening = false;
        _isPlayingFullUser = false;
        _fullUserPlayIdx = 0;
        _fullAIAudioCache.clear();
        _mySpeech = "";
        _nativeEnglish = "";
        _mySpeechError = null;
        currentIndex = 0;
        _isAutoRecording = false;
        _aiChunkPlaying = false; // 🆕 [P2-INDICATOR]
        _aiChunkLoading = false;
        _isReplayMode = false; // 🆕 [P2-INDICATOR]
        _practicingNativeEnglish = false; // 🆕 [CHUNK-PRACTICE]
        _isPlayingFullAI = false; // 🆕 [CHUNK-PRACTICE]
        _tutorAwaitingStart = true; // 🆕 [BOX-30]
        _swapRoles = false; // 🆕 [BOX-32]
        _tutorAiSpeaking = false; // 🆕 [BOX-31]
        _tutorUserRecording = false; // 🆕 [BOX-31]
        _tutorPlayingFullback = false; // 🆕 [BOX-34]
        _nativeEnglishError = null;
        _showRetryHint = false;
      });
    }
  }

  // 📦 [Box 12: 상태 머신 본체]

  void _onAudioComplete() {
    if (!mounted) return;
    if (_phase == ShadowingPhase.turnPractice && isPracticeMode && !isPaused) {
      if (mounted) setState(() => _tutorAiSpeaking = false); // 🆕 [BOX-31]
      _nextTurn();
    } else if (_practicingNativeEnglish && _nativeEnglishUnitAIPlaying) {
      // Native English 의미단위 AI 재생 완료 → 사용자 녹음 시작
      if (mounted) setState(() => _nativeEnglishUnitAIPlaying = false);
      _startDualCapture();
    } else if (_phase == ShadowingPhase.chunkPractice) {
      if (_isPlayingFullUser) {
        _advanceFullUserPlay();
      } else if (!_isPlayingFullAI &&
          _currentChunkIdx >= 0 &&
          _currentChunkIdx < _chunks.length) {
        // AI 청크 재생 완료 → 자동 녹음 시작
        if (mounted) setState(() => _aiChunkPlaying = false);
        _startDualCapture();
      } else {
        if (mounted) setState(() => _aiChunkPlaying = false);
      }
    } else {
      setState(() {});
    }
  }

  // 📦 [Box 13: 듀얼 캡처 - Deepgram + WAV 파일]
  Future<void> _startDualCapture() async {
    // 🎫 소켓이 열리는 순간부터 전사 비용이 나간다. 이 자리는 버튼이 아니라
    //   재생 완료 콜백(`_onAudioComplete`)이 부르므로 자체 빗장이 필요하다.
    if (!_paidStudySilentlyAllowed('shadow_stt')) return;
    if (_deepgramKey.isEmpty) {
      return;
    }
    if (_isListening) {
      return;
    }
    _pcmBuffer = BytesBuilder();
    try {
      if (mounted) setState(() => _isListening = true);

      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {}

      final stream = await appAudioRecorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ));

      _dgSocket = await WebSocket.connect(
        'wss://api.deepgram.com/v1/listen'
        '?model=nova-3'
        '&language=en-US'
        '&encoding=linear16'
        '&sample_rate=16000'
        '&utterance_end_ms=1200'
        '&vad_events=true'
        '&interim_results=true',
        headers: {'Authorization': 'Token $_deepgramKey'},
      );

      _micStreamSub = stream.listen((data) {
        if (_dgSocket?.readyState == WebSocket.open) {
          _dgSocket?.add(data);
        }
        _pcmBuffer.add(data);
      });

      _dgSubscription = _dgSocket?.listen(
        (event) {
          if (!mounted || event is! String) return;
          try {
            final json = jsonDecode(event) as Map<String, dynamic>;
            if (json['type'] == 'UtteranceEnd') {
              _onUserUtteranceEnd();
            }
          } catch (_) {}
        },
        onError: (e) {
          debugPrint("[Deepgram] error: $e");
        },
        onDone: () {
          debugPrint("[Deepgram] socket closed");
        },
      );

      _utteranceSafetyTimer?.cancel();
      _utteranceSafetyTimer = Timer(const Duration(seconds: 10), () {
        if (mounted && _isListening) {
          _onUserUtteranceEnd();
        }
      });
    } catch (e) {
      debugPrint("[startDualCapture] $e");
      if (mounted) setState(() => _isListening = false);
    }
  }

  Future<String?> _stopDualCaptureAndSave() async {
    _utteranceSafetyTimer?.cancel();
    _utteranceSafetyTimer = null;
    _micStreamSub?.cancel();
    _micStreamSub = null;
    _dgSubscription?.cancel();
    _dgSubscription = null;
    try {
      _dgSocket?.close();
    } catch (_) {}
    _dgSocket = null;
    try {
      await appAudioRecorder.stop();
    } catch (_) {}
    if (mounted) setState(() => _isListening = false);

    final pcmData = _pcmBuffer.takeBytes();
    if (pcmData.isEmpty) return null;
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/shadow_c${_currentChunkIdx}_${DateTime.now().millisecondsSinceEpoch}.wav';
      await File(path).writeAsBytes(_buildWavFromPcm(pcmData));
      return path;
    } catch (e) {
      debugPrint("[stopDualCaptureAndSave] $e");
      return null;
    }
  }

  void _stopDeepgramListening() {
    _utteranceSafetyTimer?.cancel();
    _utteranceSafetyTimer = null;
    _micStreamSub?.cancel();
    _micStreamSub = null;
    _dgSubscription?.cancel();
    _dgSubscription = null;
    try {
      _dgSocket?.close();
    } catch (_) {}
    _dgSocket = null;
    try {
      appAudioRecorder.stop();
    } catch (_) {}
    if (mounted) setState(() => _isListening = false);
  }

  void _onUserUtteranceEnd() async {
    if (!mounted) return;
    if (!_isListening) return;

    // Native English 의미단위 모드: 녹음 완료 → 다음 유닛으로 자동 이동
    if (_practicingNativeEnglish) {
      await _stopDualCaptureAndSave();
      if (!mounted) return;
      final nextIdx = _nativeEnglishUnitIdx + 1;
      if (nextIdx < _nativeEnglishUnits.length) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted && _practicingNativeEnglish) {
            _onNativeEnglishUnitTapped(nextIdx);
          }
        });
      }
      return;
    }

    if (_phase != ShadowingPhase.chunkPractice) return;
    final path = await _stopDualCaptureAndSave();
    if (!mounted) return;
    if (path != null && _currentChunkIdx < _chunks.length) {
      final int doneIdx = _currentChunkIdx;
      setState(() {
        _chunks[doneIdx].userRecordPath = path;
        _chunks[doneIdx].isDone = true;
      });
      // chunkPractice 모드: 자동으로 다음 청크로 이동
      if (_phase == ShadowingPhase.chunkPractice && !_isReplayMode) {
        final nextIdx = doneIdx + 1;
        if (nextIdx < _chunks.length) {
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted &&
                _phase == ShadowingPhase.chunkPractice &&
                !_isReplayMode) {
              _onChunkTapped(nextIdx);
            }
          });
        }
      }
    }
  }

  Uint8List _buildWavFromPcm(Uint8List pcm) {
    const sampleRate = 16000;
    const channels = 1;
    const bitsPerSample = 16;
    const byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    const blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = pcm.length;
    final header = ByteData(44);
    void setStr(int offset, String s) {
      for (int i = 0; i < s.length; i++) {
        header.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    setStr(0, 'RIFF');
    header.setUint32(4, 36 + dataSize, Endian.little);
    setStr(8, 'WAVE');
    setStr(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    setStr(36, 'data');
    header.setUint32(40, dataSize, Endian.little);
    final result = Uint8List(44 + dataSize);
    result.setRange(0, 44, header.buffer.asUint8List());
    result.setRange(44, 44 + dataSize, pcm);
    return result;
  }

  // 🔧 [STAMPEDE-FIX] in-flight 잠금: 같은 청크 동시 API 호출을 1회로 합침
  Future<Uint8List?> _getOrFetchChunkAudio(int idx) {
    if (_inFlightChunkFetch.containsKey(idx)) {
      return _inFlightChunkFetch[idx]!;
    }
    final future = _fetchChunkAudioInternal(idx);
    _inFlightChunkFetch[idx] = future;
    future.whenComplete(() => _inFlightChunkFetch.remove(idx));
    return future;
  }

  Future<Uint8List?> _fetchChunkAudioInternal(int idx) async {
    if (idx >= _chunks.length) return null;
    final chunk = _chunks[idx];
    final historyId = widget.historyDoc.id;
    final variant =
        _selectedVariant == SentenceVariant.nativeEnglish ? 'nat' : 'exp';
    final cacheKey = 'gpt4omini_nova_chunk_${variant}_$idx.mp3';
    if (chunk.aiAudio != null) {
      return chunk.aiAudio;
    }
    final diskHit = await _AudioDiskCache.read(historyId, cacheKey);
    if (diskHit != null && mounted && idx < _chunks.length) {
      setState(() => _chunks[idx].aiAudio = diskHit);
      return diskHit;
    }
    // 🔧 [정상속도] formatForSlowRhythm 제거 → 텍스트 그대로 TTS
    final audio = await _getOrFetchPracticeTTS(
      chunk.text,
      _historyPracticeAiVoice,
    );
    if (!mounted) return null;
    if (audio != null && idx < _chunks.length) {
      setState(() => _chunks[idx].aiAudio = audio);
      await _AudioDiskCache.write(historyId, cacheKey, audio);
    } else {}
    return audio;
  }

  Future<void> _playChunkAI(int idx) async {
    _resumeHistoryFromUserAction();
    if (idx >= _chunks.length) return;
    if (mounted)
      setState(() {
        _aiChunkPlaying = true;
        _aiChunkLoading = true;
      });
    try {
      final audio = await _getOrFetchChunkAudio(idx);
      if (!mounted) return;
      if (mounted) setState(() => _aiChunkLoading = false);
      if (audio != null) {
        await audioPlayer.play(BytesSource(audio));
        BillingTicker.instance.resumeFromActivity('history_practice_tts_end');
      } else {
        // [NULL-FALLBACK] Continue to the next chunk when TTS returns no audio.
        if (_phase == ShadowingPhase.chunkPractice && !_isReplayMode) {
          final nextIdx = idx + 1;
          if (nextIdx < _chunks.length) {
            Future.delayed(const Duration(milliseconds: 400), () {
              if (mounted && _phase == ShadowingPhase.chunkPractice) {
                _onChunkTapped(nextIdx);
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint("[playChunkAI] $e");
    } finally {
      if (mounted)
        setState(() {
          _aiChunkPlaying = false;
          _aiChunkLoading = false;
        });
    }
  }

  void _advanceFullUserPlay() {
    final nextIdx = _fullUserPlayIdx + 1;
    if (nextIdx < _chunks.length) {
      if (mounted) setState(() => _fullUserPlayIdx = nextIdx);
      _playUserChunk(nextIdx);
    } else {
      if (mounted)
        setState(() {
          _isPlayingFullUser = false;
          _fullUserPlayIdx = 0;
        });
    }
  }

  Future<void> _playUserChunk(int idx) async {
    if (idx >= _chunks.length) return;
    final path = _chunks[idx].userRecordPath;
    if (path == null || path.isEmpty) {
      if (_isPlayingFullUser) _advanceFullUserPlay();
      return;
    }
    _resumeHistoryFromUserAction();
    try {
      await audioPlayer.play(DeviceFileSource(path));
    } catch (e) {
      debugPrint("[playUserChunk] $e");
      if (_isPlayingFullUser) _advanceFullUserPlay();
    }
  }

  // 히스토리 말풍선 소리듣기 — msgId 기반 디스크 캐시 우선
  Future<void> _playMsgAudio(String msgId, String text) async {
    _resumeHistoryFromUserAction();
    if (text.isEmpty || _apiKey.isEmpty) return;
    // 🎫 이미 받아 둔 소리는 그대로 들려준다. 아래 캐시가 비었을 때만
    //   새로 만들게 되고, 그 자리는 [_fetchOpenAITTSInternal]이 막는다.
    if (!_paidStudyAllowed) {
      final cached = await _AudioDiskCache.read(
          widget.historyDoc.id, 'tts1_nova_native_$msgId.mp3');
      if (cached == null) {
        _guardPaidStudy();
        return;
      }
    }
    final historyId = widget.historyDoc.id;
    final cacheKey = 'tts1_nova_native_$msgId.mp3';
    final diskHit = await _AudioDiskCache.read(historyId, cacheKey);
    if (diskHit != null) {
      await audioPlayer.play(BytesSource(diskHit));
      return;
    }
    final audio = await _fetchOpenAITTS(text, 1.0, _historyListenTtsVoice);
    if (audio == null || !mounted) return;
    await _AudioDiskCache.write(historyId, cacheKey, audio);
    await audioPlayer.play(BytesSource(audio));
  }

  // OpenAI TTS 헬퍼
  String _practiceCacheVoice(String voice) =>
      '${_historyPracticeTtsModel}_$voice';

  Future<Uint8List?> _fetchPracticeTTS(String text, String voice) =>
      _fetchOpenAITTS(
        text,
        1.0,
        voice,
        model: _historyPracticeTtsModel,
      );

  Future<Uint8List?> _getOrFetchPracticeTTS(String text, String voice) {
    final cacheVoice = _practiceCacheVoice(voice);
    final requestKey = '$cacheVoice|${text.trim()}';
    final existing = _openAiTtsInFlight[requestKey];
    if (existing != null) return existing;
    final future = () async {
      var audio = await TtsCache.get(text, cacheVoice);
      if (audio != null) return audio;
      audio = await _fetchPracticeTTS(text, voice);
      if (audio != null) await TtsCache.put(text, cacheVoice, audio);
      return audio;
    }();
    _openAiTtsInFlight[requestKey] = future;
    future.whenComplete(() => _openAiTtsInFlight.remove(requestKey));
    return future;
  }

  Future<Uint8List?> _fetchOpenAITTS(String text, double speed, String voice,
      {String model = _historyListenTtsModel,
      String? instructions,
      String? instructionTag}) {
    final requestKey = jsonEncode([
      model,
      text.trim(),
      voice,
      speed,
      instructions ?? '',
    ]);
    final existing = _openAiTtsInFlight[requestKey];
    if (existing != null) return existing;
    final future = _fetchOpenAITTSInternal(
      text,
      speed,
      voice,
      model: model,
      instructions: instructions,
      instructionTag: instructionTag,
    );
    _openAiTtsInFlight[requestKey] = future;
    future.whenComplete(() => _openAiTtsInFlight.remove(requestKey));
    return future;
  }

  Future<Uint8List?> _fetchOpenAITTSInternal(
    String text,
    double speed,
    String voice, {
    String model = _historyListenTtsModel,
    String? instructions,
    String? instructionTag,
    String? responseFormat,
  }) async {
    // 🎫 소리를 **새로 만드는** 유일한 자리다. 여기만 막으면 이미 받아 둔
    //   소리는 그대로 들리고, 새 비용만 나가지 않는다.
    if (!_paidStudySilentlyAllowed('tts_generate')) return null;
    if (_apiKey.isEmpty || text.trim().isEmpty) return null;
    try {
      var response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/audio/speech'),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({
              'model': model,
              'input': text,
              'voice': voice,
              if (model == _historyListenTtsModel) 'speed': speed,
              if (responseFormat != null) 'response_format': responseFormat,
              if (instructions != null && instructions.trim().isNotEmpty)
                'instructions': instructions,
            }),
          )
          // PCM은 mp3보다 응답이 커서 10초로는 모자랄 수 있다.
          .timeout(Duration(seconds: responseFormat == 'pcm' ? 30 : 10));
      debugPrint(
          '[HISTORY-TTS] model=$model voice=$voice instruction=${instructionTag ?? 'none'} status=${response.statusCode} chars=${text.trim().length}');
      return response.statusCode == 200 ? response.bodyBytes : null;
    } catch (e) {
      debugPrint("[fetchOpenAITTS] $e");
      return null;
    }
  }

  // 📦 [Box 17-A: 실전 튜터링 - 말풍선 옆 버튼]
  Widget _buildAppBtn(String docId, String baseText) {
    return IconButton(
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      icon: const Icon(
        Icons.school_rounded,
        color: Colors.deepPurpleAccent,
        size: 24,
      ),
      onPressed: () => _showTutoringPopup(docId, baseText),
      tooltip: "실전 튜터링",
    );
  }

  // 📦 [Box 17-B: 다른 표현 보기]
  //   버튼도 팝업도 Keepers와 함께 쓴다 — `widgets/alt_style_popup.dart`.
  //   화면마다 사본을 두면 같은 이름의 Native가 서로 다른 문장이 된다.
  Widget _buildAltStyleBtn(String baseText) =>
      buildAltStyleButton(onPressed: () => _showAltStylePopup(baseText));

  /// 이 세션의 TARGET 언어 이름. 비어 있으면 영어로 본다(기존 동작).
  String _sessionTargetLangName() {
    final name = (_sessionTargetLang ?? '').trim();
    return name.isEmpty ? 'English' : name;
  }

  /// 같은 뜻을 스타일만 바꿔 늘어놓는다. 목록도 생성 규칙도 공용이다.
  void _showAltStylePopup(String baseText) {
    if (!_guardPaidStudy()) return;
    _resumeHistoryFromUserAction();
    showAltStylePopup(
      context: context,
      apiKey: _apiKey,
      baseText: baseText,
      targetLang: _sessionTargetLangName(),
    );
  }

  // 📦 [Box 17-A-2: 실전 튜터링 - 팝업 바텀시트]
  void _showTutoringPopup(String docId, String baseText) {
    if (!_guardPaidStudy()) return;
    _resumeHistoryFromUserAction();
    if (_appIsRecording) {
      appAudioRecorder.stop().ignore();
    }
    setState(() {
      activeAppDocId = docId;
      appOriginalText = "";
      appCorrectedText = "";
      _appAnswerEn = "";
      _appCorrection = "";
      _appTranscript = "";
      _appIsRecording = false;
      _appCorrectedAudio = null;
      _isPlayingAppAudio = false;
    });
    _generateAppText(baseText);
    BillingTicker.instance.setRate(BillingRate.full); // 튜터링 구간 full rate

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (_, ss) {
          _dialogSetState = ss;
          return DraggableScrollableSheet(
            initialChildSize: 0.72,
            minChildSize: 0.45,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollController) => SingleChildScrollView(
              controller: scrollController,
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).padding.bottom + 24),
              child: _buildAccordion(
                docId,
                baseText,
                onClose: () => Navigator.of(ctx).pop(),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      BillingTicker.instance
          .setRate(BillingRate.full); // 튜터링 종료 (배율은 하나뿐이라 그대로)
      _dialogSetState = null;
      if (_appIsRecording) {
        appAudioRecorder.stop().ignore();
      }
      if (mounted) {
        setState(() {
          activeAppDocId = null;
          _appIsRecording = false;
        });
      }
    });
  }

  // 📦 [Box 17-B: 실전 튜터링 - 아코디언 UI (4단계)]
  Widget _buildAccordion(String docId, String baseText,
      {VoidCallback? onClose}) {
    void closeAccordion() {
      if (_appIsRecording) {
        appAudioRecorder.stop().ignore();
      }
      setState(() {
        activeAppDocId = null;
        _appIsRecording = false;
      });
      onClose?.call();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 헤더
          Row(
            children: [
              const Icon(Icons.school_rounded, color: Colors.amber, size: 18),
              const SizedBox(width: 8),
              const Text(
                "실전 튜터링",
                style: TextStyle(
                    color: Colors.amber,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                onPressed: closeAccordion,
                icon: const Icon(Icons.close, color: Colors.white70, size: 22),
                padding: const EdgeInsets.all(12),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Step 1: 로딩 or 한국어 응용 문장
          if (isGeneratingApp)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(
                    color: Colors.amber, strokeWidth: 2),
              ),
            )
          else if (appOriginalText.isNotEmpty) ...[
            // 한국어 문장 박스
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
              ),
              child: Text(
                appOriginalText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    height: 1.4),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "위 문장을 영어로 말해보세요",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 16),

            // Step 2: 녹음 버튼 (교정 전)
            if (_appCorrection.isEmpty)
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (_appIsRecording) {
                          _stopAppRecordAndProcess(
                              appOriginalText, _appAnswerEn);
                        } else {
                          _startAppRecording();
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _appIsRecording
                              ? Colors.redAccent.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.05),
                          border: Border.all(
                            color: _appIsRecording
                                ? Colors.redAccent
                                : Colors.white38,
                            width: _appIsRecording ? 2.5 : 1.5,
                          ),
                          boxShadow: _appIsRecording
                              ? [
                                  BoxShadow(
                                      color: Colors.redAccent
                                          .withValues(alpha: 0.3),
                                      blurRadius: 14,
                                      spreadRadius: 2)
                                ]
                              : [],
                        ),
                        child: Icon(
                          _appIsRecording
                              ? Icons.stop_rounded
                              : Icons.mic_rounded,
                          color: _appIsRecording
                              ? Colors.redAccent
                              : Colors.white70,
                          size: 32,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _appIsRecording
                          ? "Recording... tap to stop"
                          : "Tap to start recording",
                      style: TextStyle(
                          color: _appIsRecording
                              ? Colors.redAccent
                              : Colors.white38,
                          fontSize: 12),
                    ),
                  ],
                ),
              ),

            // Step 3/4: 교정 결과 + TTS + 쉐도잉
            if (_appCorrection.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(Icons.check_circle_outline,
                                color: Colors.greenAccent, size: 14),
                          ),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text("Correction Result",
                                style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ]),
                    const SizedBox(height: 8),
                    Text(_appCorrection,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13, height: 1.5)),
                  ],
                ),
              ),

              // 🆕 활용 구문 팁 (있을 때만)
              if (_appUsageTip.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: EdgeInsets.only(top: 1),
                              child: Icon(Icons.lightbulb_outline,
                                  color: Colors.amber, size: 14),
                            ),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text("더 자연스러운 표현",
                                  style: TextStyle(
                                      color: Colors.amber,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ]),
                      const SizedBox(height: 8),
                      Text(_appUsageTip,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.5)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),

              // Step 3: TTS 재생 버튼
              OutlinedButton.icon(
                onPressed: (_isPlayingAppAudio || _appCorrectedAudio == null)
                    ? null
                    : _playAppCorrectedAudio,
                icon: Icon(
                  _isPlayingAppAudio
                      ? Icons.volume_up_rounded
                      : Icons.play_circle_outline_rounded,
                  color:
                      _isPlayingAppAudio ? Colors.greenAccent : Colors.white70,
                  size: 18,
                ),
                label: Text(
                  _isPlayingAppAudio ? "Playing..." : "Shadow This!",
                  style: TextStyle(
                      color: _isPlayingAppAudio
                          ? Colors.greenAccent
                          : Colors.white70,
                      fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: _isPlayingAppAudio
                          ? Colors.greenAccent.withValues(alpha: 0.6)
                          : Colors.white24),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 14),
            ],

            const SizedBox(height: 18),

            // Show transcript above the bottom action buttons.
            if (_appTranscript.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
                child: Text(
                  _appTranscript,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      height: 1.4,
                      fontStyle: FontStyle.italic),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 하단 버튼
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: _appIsRecording ? null : closeAccordion,
                  child: const Text("Close",
                      style: TextStyle(color: Colors.white54, fontSize: 14)),
                ),
                Flexible(
                  child: ElevatedButton.icon(
                    onPressed: (isGeneratingApp || _appIsRecording)
                        ? null
                        : () {
                            setState(() {
                              _appCorrection = "";
                              _appUsageTip = "";
                              _appCorrectedAudio = null;
                              _appTranscript = "";
                            });
                            _generateAppText(baseText);
                          },
                    icon: const Icon(Icons.refresh, size: 15),
                    label: const Text("Another Sentence",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: const Color(0xFF121212),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // 📦 [Box 18: AI 튜터링 - 응용 문장 생성 API 호출]
  Future<void> _generateAppText(String baseText) async {
    if (!_paidStudySilentlyAllowed('tutoring_text')) return;
    _resumeHistoryFromUserAction();
    if (!mounted) return;
    setState(() => isGeneratingApp = true);
    _dialogSetState?.call(() {});

    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'temperature': 1.0,
          'response_format': {'type': 'json_object'},
          'messages': [
            {
              'role': 'system',
              'content':
                  r"""You are a grammar application tutor. Keep ONLY the core grammar pattern (tense / structure / word order) of the input English sentence. Then create ONE completely NEW Korean sentence that uses the SAME structure but an ENTIRELY DIFFERENT topic, vocabulary, and situation from the input — it must not be a paraphrase of the input. Also provide one natural English answer for that new Korean sentence. reply ONLY in JSON: {"ko": "새 한국어 문장", "en": "영어 정답"}""",
            },
            {
              'role': 'user',
              'content': _appRecentKoSentences.isEmpty
                  ? 'Input English sentence: "$baseText"'
                  : 'Input English sentence: "$baseText"\n\nDo NOT repeat the topic or wording of these recently used Korean sentences — pick a clearly different subject:\n- ${_appRecentKoSentences.join("\n- ")}',
            },
          ],
        }),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final jsonResult = jsonDecode(data['choices'][0]['message']['content']);
        final newKo = (jsonResult['ko'] as String? ?? '').trim();
        setState(() {
          appOriginalText = newKo;
          _appAnswerEn = (jsonResult['en'] as String? ?? '').trim();
          appCorrectedText = "";
          _appCorrection = "";
          _appUsageTip = "";
        });
        // 🆕 최근 문장 기록(중복 회피용, 최대 6개 유지)
        if (newKo.isNotEmpty) {
          _appRecentKoSentences.add(newKo);
          if (_appRecentKoSentences.length > 6) {
            _appRecentKoSentences.removeAt(0);
          }
        }
        _dialogSetState?.call(() {});
      }
    } catch (e) {
      debugPrint("[generateAppText] $e");
    } finally {
      if (mounted) setState(() => isGeneratingApp = false);
      _dialogSetState?.call(() {});
    }
  }

  // 📦 [Box 18-B: 실전 튜터링 - 녹음 시작]
  Future<void> _startAppRecording() async {
    if (!_guardPaidStudy()) return;
    _resumeHistoryFromUserAction();
    final hasPermission = await appAudioRecorder.hasPermission();
    if (!hasPermission) return;
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/tutoring_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await appAudioRecorder.start(
        const RecordConfig(
            encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1),
        path: path,
      );
      if (mounted) setState(() => _appIsRecording = true);
      _dialogSetState?.call(() {});
    } catch (e) {
      debugPrint("[startAppRecording] $e");
    }
  }

  // 📦 [Box 18-C: 실전 튜터링 - 녹음 중지 → STT → GPT 교정]
  Future<void> _stopAppRecordAndProcess(
      String targetKo, String targetEn) async {
    if (!_paidStudySilentlyAllowed('tutoring_stt')) return;
    _resumeHistoryFromUserAction();
    final path = await appAudioRecorder.stop();
    if (mounted) setState(() => _appIsRecording = false);
    _dialogSetState?.call(() {});
    if (path == null || !mounted) return;
    if (mounted) setState(() => isGeneratingApp = true);
    _dialogSetState?.call(() {});
    try {
      // 1. Whisper STT
      final uri = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $_apiKey';
      request.fields['model'] = 'gpt-4o-mini-transcribe';
      request.fields['language'] = 'en';
      request.files.add(await http.MultipartFile.fromPath('file', path));
      final streamed =
          await request.send().timeout(const Duration(seconds: 15));
      final body = await streamed.stream.bytesToString();
      if (!mounted) return;
      final transcript = (jsonDecode(body)['text'] as String? ?? '').trim();
      BillingTicker.instance.resumeFromActivity('history_tutoring_stt_result');

      if (mounted) {
        setState(() => _appTranscript = transcript);
        _dialogSetState?.call(() {});
      }

      // 2. GPT correction + reason — 한국어 원문을 "의미 기준"으로 삼아 객관적으로 채점
      final corrPrompt =
          '''You are a strict but fair English tutor for a Korean learner.

[KOREAN_PROMPT] (the meaning the user MUST express): "$targetKo"
[EXAMPLE_EN] (ONE natural example answer — NOT the only correct answer): "$targetEn"
[USER_SPEECH]: "$transcript"

Judge OBJECTIVELY. The [KOREAN_PROMPT] is the source of truth for MEANING.

RULES — follow exactly:
1. MEANING CHECK (most important): Does [USER_SPEECH] express the SAME meaning as [KOREAN_PROMPT]?
   - Different wording, synonyms, or a different valid structure are FINE as long as the meaning matches [KOREAN_PROMPT]. Do not mark a real paraphrase wrong.
   - BUT if a content word changes the intended meaning (e.g. said "order" when the prompt means "arrive", wrong verb/noun, or a tense that changes the intent), it is WRONG. Do NOT praise it.
   - Ignore minor STT noise (punctuation, capitalization).
2. If the meaning matches [KOREAN_PROMPT] AND the grammar is correct:
   - "corrected_en" = the user's OWN sentence, cleaned of STT noise only. Do NOT replace it with [EXAMPLE_EN].
   - "reason_ko" = one short Korean praise line. You MAY append "다른 표현: [EXAMPLE_EN]".
3. If there is a real error (meaning mismatch vs [KOREAN_PROMPT], grammar, tense, word order, word choice, or a real pronunciation/spelling error):
   - "corrected_en" = a corrected English sentence that is BOTH grammatical AND matches [KOREAN_PROMPT]'s meaning. Fix the actual error; keep the parts that are already correct.
   - "reason_ko" = ENCOURAGING, constructive Korean feedback in 2-3 sentences. Do NOT merely say it is wrong. FIRST acknowledge what [USER_SPEECH] actually means as it stands, so the learner sees their attempt made sense. THEN point to the specific small fix and the meaning it unlocks — e.g. "지금 말한 문장은 '...'라는 뜻이에요. 여기서 'X'를 'Y'로 바꾸면 '...'라는 원하던 의미가 됩니다." Be specific, warm, and positive; never scold. Never invent an error that is not present.
4. "usage_tip_ko": Suggest 1-2 MORE NATURAL, more native-like or idiomatic ways to say the SAME meaning as "corrected_en" (a native-speaker upgrade). For each, put the English expression first, then a short Korean note on the nuance or feel it adds and why a native might prefer it. Aim at real spoken-English naturalness — idioms, natural phrasings, or common conversational add-ons (e.g. "though", "actually", "you know") — NOT a plain synonym swap and NOT just making the sentence longer. Write the notes in Korean. If "corrected_en" is already the most natural way and there is genuinely nothing valuable to add, use "".
5. Output ONLY valid JSON with exactly these three keys: {"corrected_en": "...", "reason_ko": "...", "usage_tip_ko": "..."}''';

      final resp = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json'
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'response_format': {'type': 'json_object'},
          'temperature': 0.1,
          'max_tokens': 250,
          'messages': [
            {'role': 'user', 'content': corrPrompt}
          ]
        }),
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final rd = jsonDecode(utf8.decode(resp.bodyBytes));
        final jr = jsonDecode(rd['choices'][0]['message']['content']);
        final correctedEn = (jr['corrected_en'] as String? ?? '').trim();
        final reasonKo = (jr['reason_ko'] as String? ?? '').trim();
        final usageTip = (jr['usage_tip_ko'] as String? ?? '').trim();
        if (mounted)
          setState(() {
            _appCorrection = "$correctedEn\n\n$reasonKo";
            _appUsageTip = usageTip;
          });
        _dialogSetState?.call(() {});

        // Step 3: TTS 생성 → 자동 재생
        if (correctedEn.isNotEmpty) {
          final corrCacheKey =
              'gpt4omini_nova_correction_${correctedEn.hashCode.abs()}.mp3';
          Uint8List? cachedAudio;
          if (_phase != ShadowingPhase.turnPractice) {
            cachedAudio =
                await _AudioDiskCache.read(widget.historyDoc.id, corrCacheKey);
          }
          final ttsAudio = cachedAudio ??
              await _getOrFetchPracticeTTS(
                correctedEn,
                _historyPracticeAiVoice,
              );
          if (cachedAudio == null && ttsAudio != null) {
            if (_phase != ShadowingPhase.turnPractice) {
              await _AudioDiskCache.write(
                  widget.historyDoc.id, corrCacheKey, ttsAudio);
            }
          }
          if (mounted && ttsAudio != null) {
            setState(() {
              _appCorrectedAudio = ttsAudio;
              _isPlayingAppAudio = true;
            });
            _dialogSetState?.call(() {});
            BillingTicker.instance
                .resumeFromActivity('history_tutoring_tts_start');
            await audioPlayer.play(BytesSource(ttsAudio));
            BillingTicker.instance
                .resumeFromActivity('history_tutoring_tts_end');
            if (mounted) setState(() => _isPlayingAppAudio = false);
            _dialogSetState?.call(() {});
          }
        }
      }
    } catch (e) {
      debugPrint("[stopAppRecordAndProcess] $e");
    } finally {
      if (mounted) setState(() => isGeneratingApp = false);
      _dialogSetState?.call(() {});
    }
  }

  // 📦 [Box 18-D: 실전 튜터링 - 교정 TTS 재생]
  Future<void> _playAppCorrectedAudio() async {
    _resumeHistoryFromUserAction();
    if (_appCorrectedAudio == null || !mounted) return;
    setState(() => _isPlayingAppAudio = true);
    _dialogSetState?.call(() {});
    try {
      BillingTicker.instance.resumeFromActivity('history_tutoring_tts_start');
      await audioPlayer.play(BytesSource(_appCorrectedAudio!));
      BillingTicker.instance.resumeFromActivity('history_tutoring_tts_end');
    } catch (e) {
      debugPrint("[playAppCorrectedAudio] $e");
    } finally {
      if (mounted) setState(() => _isPlayingAppAudio = false);
      _dialogSetState?.call(() {});
    }
  }

  // 📦 [Box 19: UI 메인 - Scaffold 및 분기]
  @override
  Widget build(BuildContext context) {
    if (isLoadingRoom) {
      return const Scaffold(
          backgroundColor: Color(0xFF121212),
          body: Center(child: CircularProgressIndicator()));
    }

    if (_phase == ShadowingPhase.studySelect) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Stack(children: [
          SafeArea(child: _buildStudySelectScreen()),
          Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                  child: GestureDetector(
                child: const SizedBox(width: 40, height: 40),
              ))),
        ]),
      );
    }

    if (_phase == ShadowingPhase.chunkPractice) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Stack(children: [
          SafeArea(
            child: Column(
              children: [
                // 🔙 왼쪽 X는 두 문장 고르는 자리로 돌아가고, 오른쪽 SR은
                //   공부방으로 나간다.
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 16, 2),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        tooltip: '다시 고르기',
                        onPressed: _backToStudySelect,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 40, minHeight: 40),
                      ),
                      const Spacer(),
                      _buildStudyRoomPill(),
                    ],
                  ),
                ),
                Expanded(child: _buildChunkPracticeScreen()),
              ],
            ),
          ),
          Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                  child: GestureDetector(
                child: const SizedBox(width: 40, height: 40),
              ))),
        ]),
      );
    }

    if (_phase == ShadowingPhase.turnPractice) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Stack(children: [
          SafeArea(child: _buildTurnPracticeScreen()),
          Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                  child: GestureDetector(
                child: const SizedBox(width: 40, height: 40),
              ))),
        ]),
      );
    }

    // idle: 일반 채팅 뷰
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                  stream: widget.historyDoc
                      .collection('messages')
                      .orderBy('created_at', descending: false)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = _visibleMessages(snapshot.data!.docs);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _cachedDocs = docs;
                        _logHistoryDiagnostics(docs);
                        _scheduleMissingTargetGeneration(docs);
                      }
                    });
                    if (docs.isEmpty) {
                      return const Center(
                        child: Text("데이터가 없습니다.",
                            style: TextStyle(color: Colors.white54)),
                      );
                    }
                    return _buildChatBubbles(docs);
                  },
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 📦 [Box 20: UI - 상단 네비게이션 바]
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                  onTap: () => context.pop(),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 64,
                    height: 56,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 8),
                    child: const Icon(Icons.keyboard_arrow_left,
                        color: Colors.amber, size: 28),
                  )),
            ],
          ),
          Expanded(
            child: Text(
              _displayRoomTitle(roomName),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: BillingTicker.instance.billingState,
            builder: (_, s, __) => GestureDetector(
              onTap: s == 0 ? resetBillingIdle : null,
              child: Padding(
                padding: const EdgeInsets.only(left: 4, right: 6),
                child: CustomPaint(
                  size: const Size(16, 16),
                  painter: BillingDotPainter(s),
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.format_size,
              color: _fontScale > 1.0
                  ? const Color(0xFFFBBF24)
                  : _fontScale < 1.0
                      ? Colors.white38
                      : Colors.white70,
              size: 24,
            ),
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: () => setState(() {
              _fontScale = _fontScale == 1.0
                  ? 1.3
                  : _fontScale == 1.3
                      ? 0.8
                      : 1.0;
            }),
          ),
          IconButton(
            icon: CustomPaint(
              size: const Size(26, 26),
              painter: _LangIconPainter(mode: _langDisplayMode),
            ),
            tooltip: _langDisplayMode == 0
                ? '영어만 보기'
                : _langDisplayMode == 1
                    ? '한글만 보기'
                    : '영어+한글 보기',
            onPressed: () => setState(() {
              _langDisplayMode = (_langDisplayMode + 1) % 3;
            }),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          GestureDetector(
            onLongPress: () {},
            child: IconButton(
              icon: _isEnteringPractice
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.amber,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Icon(
                      isPracticeMode ? Icons.close : Icons.record_voice_over,
                      // 🎫 잠긴 상태를 색으로 먼저 알린다. 누르면 이유가 나온다.
                      color: _paidStudyAllowed
                          ? Colors.amber
                          : Colors.amber.withValues(alpha: 0.35),
                      size: 28,
                    ),
              tooltip: isPracticeMode
                  ? "연습 종료"
                  : (_paidStudyAllowed ? "쉐도잉 연습 시작" : _studyAccess.gateLabel),
              onPressed: _isEnteringPractice
                  ? null
                  : () {
                      if (isPracticeMode) {
                        _exitShadowing();
                      } else {
                        _enterShadowingFromRoom();
                      }
                    },
            ),
          ),
        ],
      ),
    );
  }

  // 📦 [Box 22: UI - 대화 말풍선 리스트 (Shadow 진입 버튼 추가)]
  /// 타겟 문장이 아직/끝내 없는 줄에 붙는 배지.
  ///
  /// 이 줄은 원문(모국어)이 배울글 자리를 대신 채우고 있다. 배지가 없으면
  /// 정상인 줄과 구별되지 않아, 영어를 배우는 줄 알고 한국어를 따라 읽게 된다.
  /// 실패면 원인과 "다시 시도"를, 진행 중이면 "번역 중"을 보여준다.
  Widget _buildTargetStatusBadge(DocumentSnapshot doc, bool isHost) {
    final String? failure = _targetFailures[doc.id];
    final bool pending =
        failure == null || _targetTranslationInFlight.containsKey(doc.id);
    final MainAxisAlignment align =
        isHost ? MainAxisAlignment.end : MainAxisAlignment.start;

    if (pending) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: align,
          children: [
            const SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                  strokeWidth: 1.6, color: Colors.white38),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text('번역 중',
                  style: TextStyle(
                      color: Colors.white38, fontSize: 11 * _fontScale)),
            ),
          ],
        ),
      );
    }

    const Color warn = Color(0xFFF59E0B);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: align,
        children: [
          const Icon(Icons.error_outline, color: warn, size: 13),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '원문 그대로 · ${_targetFailureLabel(failure)}',
              style: TextStyle(color: warn, fontSize: 11 * _fontScale),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _retryHistoryTarget(doc),
            child: Padding(
              // 배지 글씨가 작아서 그냥 두면 손가락으로 못 누른다.
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Text('다시 시도',
                  style: TextStyle(
                      color: warn,
                      fontSize: 11 * _fontScale,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                      decorationColor: warn)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubbles(List<DocumentSnapshot> docs) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        var data = docs[index].data() as Map<String, dynamic>;
        bool isHost = data['role'] == 'HOST';
        // 모든 말풍선: \n\n 앞의 첫 대답만 표시
        String translated = (data['translated_text'] ?? '').toString();
        String original = (data['original_text'] ?? '').toString();
        final tParts = translated.split(RegExp(r'\n\s*\n'));
        if (tParts.length > 1) translated = tParts.first.trim();
        final oParts = original.split(RegExp(r'\n\s*\n'));
        if (oParts.length > 1) original = oParts.first.trim();

        // 동일 언어(Origin=Target) → 같은 문장 중복 방지: Target 한 줄만 표시.
        //  1) 기록별 언어값이 있으면 그것으로 판정한다.
        //  2) 언어값이 없는 레거시 기록은 전역 설정이 아니라
        //     original/translated 텍스트가 정규화 후 완전히 동일할 때만 중복 처리한다.
        final bool? recSame = _recordSameLang;
        final bool collapseSame = recSame ??
            (translated.isNotEmpty &&
                original.isNotEmpty &&
                _normLangText(original) == _normLangText(translated));

        // 타겟을 히스토리에서 만드는 방(Duo 직접 대화 등)인데 그 자리가 비었다.
        // 동일 언어 방은 원문이 곧 타겟이라 알릴 게 없다.
        final bool showTargetBadge = _usesDeferredHistoryTargets &&
            !collapseSame &&
            translated.isEmpty &&
            original.isNotEmpty;

        // 🎫 비용이 드는 세 가지(소리 듣기·실전 튜터링·다른 표현)는 잠기면
        //   흐려진다. **대화 글자는 그대로 보인다** — 못 쓰는 것은 새로 만드는
        //   동작뿐이다. 탭은 살려 둔다: 눌러야 이유를 알 수 있다.
        Widget controlButtons = Opacity(
          opacity: _paidStudyAllowed ? 1.0 : 0.4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: const Icon(Icons.play_circle,
                    color: Colors.amberAccent, size: 28),
                onPressed: () => _playMsgAudio(docs[index].id, translated),
                tooltip: _paidStudyAllowed ? "소리 듣기" : _studyAccess.gateLabel,
              ),
              const SizedBox(height: 4),
              _buildAppBtn(docs[index].id, translated),
              const SizedBox(height: 4),
              _buildAltStyleBtn(translated),
            ],
          ),
        );

        final String docId = docs[index].id;
        final bool isLast = index == docs.length - 1;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                // 유저: 좌측 정렬, AI(HOST): 우측 정렬
                mainAxisAlignment:
                    isHost ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // AI(HOST): 아이콘이 말풍선 왼쪽 바깥에
                  if (isHost) ...[
                    controlButtons,
                    const SizedBox(width: 6),
                  ],
                  // 말풍선 본체 (길게 누르기 → Keepers 저장)
                  //   가볍게 스치기만 해도 저장돼서, 스크롤하다 손이 닿거나
                  //   대사를 눈으로 짚는 것만으로 Keepers가 쌓였다. 저장은
                  //   의도가 있어야 하는 동작이므로 길게 누르기로 옮긴다.
                  Flexible(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: () => _saveToKeepers(
                        messageDocId: docId,
                        translatedText: translated,
                        originalText: original,
                        speakerRole: isHost ? 'HOST' : 'USER',
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: isHost
                              ? const Color(0xFF2C2C2E)
                              : const Color(0xFF2563EB).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: isHost
                              ? null
                              : Border.all(
                                  color: const Color(0xFF2563EB)
                                      .withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: isHost
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ...(collapseSame
                                // Origin=Target 동일 언어(또는 레거시 동일 텍스트):
                                // 같은 문장이 두 번 나오지 않도록 Target 한 줄만 표시한다.
                                // Target이 비어 있으면 Origin을 fallback으로 쓴다.
                                ? [
                                    Text(
                                        translated.isNotEmpty
                                            ? translated
                                            : original,
                                        textAlign: isHost
                                            ? TextAlign.right
                                            : TextAlign.left,
                                        style: TextStyle(
                                            color: isHost
                                                ? Colors.white
                                                : const Color(0xFF93C5FD),
                                            fontSize: 16 * _fontScale,
                                            fontWeight: FontWeight.bold,
                                            height: 1.4)),
                                  ]
                                : [
                                    // 영어(타겟) 표시: mode 0,1 에서 보임
                                    // 배지가 붙는 줄은 타겟이 아예 없다 — 빈 줄만
                                    // 남기지 말고 자리를 배지에 넘긴다.
                                    if (_langDisplayMode != 2 &&
                                        !showTargetBadge) ...[
                                      Text(translated,
                                          textAlign: isHost
                                              ? TextAlign.right
                                              : TextAlign.left,
                                          style: TextStyle(
                                              color: isHost
                                                  ? Colors.white
                                                  : const Color(0xFF93C5FD),
                                              fontSize: 16 * _fontScale,
                                              fontWeight: FontWeight.bold,
                                              height: 1.4)),
                                    ],
                                    // 한글(원어) 표시: mode 0,2 에서 보임
                                    // 타겟만 보는 mode 1이라도, 배지가 붙는 줄은
                                    // 원문을 감추면 말풍선이 통째로 빈다.
                                    if ((_langDisplayMode != 1 ||
                                            showTargetBadge) &&
                                        original.isNotEmpty) ...[
                                      if (_langDisplayMode == 0)
                                        const SizedBox(height: 8),
                                      Text(original,
                                          textAlign: isHost
                                              ? TextAlign.right
                                              : TextAlign.left,
                                          style: TextStyle(
                                              color: _langDisplayMode == 2
                                                  ? (isHost
                                                      ? Colors.white
                                                      : const Color(0xFF93C5FD))
                                                  : Colors.grey,
                                              fontSize: _langDisplayMode == 2
                                                  ? 16 * _fontScale
                                                  : 12 * _fontScale,
                                              fontWeight: _langDisplayMode == 2
                                                  ? FontWeight.bold
                                                  : FontWeight.normal)),
                                    ],
                                  ]),
                            if (showTargetBadge)
                              _buildTargetStatusBadge(docs[index], isHost),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 유저(USER): 아이콘이 말풍선 오른쪽 바깥에
                  if (!isHost) ...[
                    const SizedBox(width: 6),
                    controlButtons,
                  ],
                ],
              ),
            ),
            if (isLast) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 0, 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _isOpeningAdjacentHistory
                          ? null
                          : () => _openAdjacentHistoryInSameMode(-1),
                      tooltip: '같은 모드의 이전 대화',
                      icon: _isOpeningAdjacentHistory &&
                              _openingHistoryOffset == -1
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.amber,
                              ),
                            )
                          : const Icon(
                              Icons.arrow_back_rounded,
                              color: Colors.amber,
                              size: 24,
                            ),
                    ),
                    IconButton(
                      onPressed: _isOpeningAdjacentHistory
                          ? null
                          : () => _openAdjacentHistoryInSameMode(1),
                      tooltip: '같은 모드의 다음 대화',
                      icon: _isOpeningAdjacentHistory &&
                              _openingHistoryOffset == 1
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.amber,
                              ),
                            )
                          : const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.amber,
                              size: 24,
                            ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _deleteHistoryRoom,
                      tooltip: '대화 삭제',
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.white54,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: double.infinity, height: 64),
            ],
          ],
        );
      },
    );
  }

  // 📦 [Keepers: 대사 → Keepers 복사 저장 + 중복 방지]
  Future<void> _saveToKeepers({
    required String messageDocId,
    required String translatedText,
    required String originalText,
    required String speakerRole,
  }) async {
    if (translatedText.trim().isEmpty) return;
    final userRef = FirebaseAuth.instance.currentUser;
    if (userRef == null) return;
    final keepersRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userRef.uid)
        .collection('keepers');

    try {
      // ── 중복 체크: source_message_id 기준 ──
      final existing = await keepersRef
          .where('source_message_id', isEqualTo: messageDocId)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("이미 Keepers에 저장된 표현입니다.",
                style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Color(0xFF6B7280),
            duration: Duration(seconds: 1),
          ));
        }
        return;
      }

      // ── 새 Keeper 문서 생성 ──
      await keepersRef.add({
        'translated_text': translatedText,
        'original_text': originalText,
        'speaker_role': speakerRole,
        'source_message_id': messageDocId,
        'source_room_id': widget.historyDoc.id,
        'source_room_name': roomName,
        'created_at': FieldValue.serverTimestamp(),
        'pinned_at': null,
        'is_deleted': false,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Keepers에 저장되었습니다. ⭐",
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Color(0xFFD97706),
          duration: Duration(seconds: 1),
        ));
      }
    } catch (e) {
      debugPrint('[saveToKeepers] $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("저장에 실패했습니다.",
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 1),
        ));
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // 📦 [Box 22-B: 학습 경로 고르는 자리 — History Study의 첫 화면]
  //
  //   PRACTICE | MY SPEECH | NATIVE ENGLISH 셋을 나란히 둔다.
  //   **어느 하나가 다른 하나의 관문이 아니다.** Practice는 몇 번이고 다시
  //   들어오는 자리고, 나머지 둘은 대화 전체를 한 벌의 발화로 다루는 자리다.
  //
  //   ⚠️ 두 발화 카드는 **절대 같은 글자를 보이지 않는다.** Native English를
  //      못 만들었으면 그 카드는 비어 있고 "다시 시도"만 있다.
  // ══════════════════════════════════════════════════════════════════
  Widget _buildStudySelectScreen() {
    final bool busy = _isBuildingMySpeech || _isBuildingNativeEnglish;
    // 🎫 잠겨 있어도 카드를 감추지 않는다. 무엇이 있는지 보이고, 왜 지금은
    //   못 쓰는지 적힌다. 탭은 살려 둔다 — 눌러야 이유가 나온다.
    final StudyAccess access = _studyAccess;
    final bool locked = !access.canUsePaidStudy;
    // 대화가 남지 않는 방이면 전체 발화 학습 자체가 성립하지 않는다. 눌러 보고
    // 실패를 읽게 하지 말고 아예 띄우지 않는다.
    final bool speechReady = _supportsSpeechPractice(_cachedRoomMode);
    // 📐 시스템 글자 크기를 크게 써 둔 기기에서 짧은 라벨이 어절 중간에서
    //    끊기지 않게, 이 선택 화면에서만 배율에 천장을 씌운다.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: _exitShadowing,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
                const Spacer(),
                _buildStudyRoomPill(),
              ],
            ),
            const Text(
              "무엇으로 공부할까요?",
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStudyPathCard(
                      title: "PRACTICE",
                      subtitle: "역할을 바꿔 가며 대화 연습",
                      icon: Icons.swap_horiz_rounded,
                      color: const Color(0xFF4ADE80),
                      locked: locked,
                      emptyHint: locked ? access.gateLabel : '',
                      onTap: busy ? null : _openPracticeStudy,
                    ),
                    if (speechReady) ...[
                      const SizedBox(height: 12),
                      _buildStudyPathCard(
                        title: "MY SPEECH",
                        subtitle: "내가 대화에서 실제로 한 말",
                        icon: Icons.record_voice_over_rounded,
                        color: const Color(0xFF38BDF8),
                        preview: _mySpeech,
                        emptyHint: locked ? access.gateLabel : "눌러서 만들기",
                        error: _mySpeechError,
                        locked: locked,
                        isLoading: _isBuildingMySpeech,
                        onTap:
                            busy ? null : () => unawaited(_openMySpeechStudy()),
                      ),
                      const SizedBox(height: 12),
                      _buildStudyPathCard(
                        title: "NATIVE ENGLISH",
                        subtitle: "같은 생각을 미국인이 처음부터 영어로",
                        icon: Icons.auto_awesome,
                        color: const Color(0xFFFBBF24),
                        preview: _nativeEnglish,
                        emptyHint: locked ? access.gateLabel : "눌러서 만들기",
                        error: _nativeEnglishError,
                        locked: locked,
                        isLoading: _isBuildingNativeEnglish,
                        onTap: busy
                            ? null
                            : () => unawaited(_openNativeEnglishStudy()),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            TextButton(
              onPressed: _exitShadowing,
              child: const Text("나가기",
                  style: TextStyle(color: Colors.white38, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  /// 학습 경로 카드 한 장.
  ///
  /// [preview]가 있으면 그 글을 세 줄까지 보여 준다 — 무엇을 연습하게 되는지
  /// 누르기 전에 보이는 편이 낫다. 없으면 [emptyHint], 실패했으면 [error]다.
  /// 셋은 서로 배타적이라 카드가 거짓말을 하지 않는다.
  Widget _buildStudyPathCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    String preview = '',
    String emptyHint = '',
    String? error,
    bool isLoading = false,
    bool locked = false,
  }) {
    // 잠긴 카드는 미리보기를 지운다 — 만들어 둔 문장이 있으면 쓸 수 있는
    // 것처럼 보인다. 자리에는 [emptyHint]로 들어온 이유가 대신 앉는다.
    final String body = locked ? '' : preview.trim();
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: (onTap == null && !isLoading) || locked ? 0.45 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: color.withValues(alpha: 0.65), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 19),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(title,
                        style: TextStyle(
                            color: color,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6)),
                  ),
                  if (isLoading)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: color, strokeWidth: 2.2),
                    )
                  else
                    Icon(Icons.chevron_right_rounded,
                        color: color.withValues(alpha: 0.6), size: 20),
                ],
              ),
              const SizedBox(height: 5),
              Text(subtitle,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
              if (isLoading) ...[
                const SizedBox(height: 10),
                const Text("만드는 중...",
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
              ] else if (body.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14 * _fontScale,
                      height: 1.5),
                ),
              ] else if (error != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.refresh_rounded, color: color, size: 15),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text("$error — 눌러서 다시 시도",
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              height: 1.4)),
                    ),
                  ],
                ),
              ] else if (emptyHint.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(emptyHint,
                    style: TextStyle(
                        color: color.withValues(alpha: 0.85), fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 📦 [BOX-32: 역할 스왑 - 동적 판정 헬퍼]
  // History Practice는 HOST=사용자, SYSTEM=AI 기준으로 판정한다.
  bool _lineRepresentsAi(Map<String, dynamic> line) =>
      (line['role'] as String) == 'SYSTEM';

  String _practiceVoiceForLine(Map<String, dynamic> line) =>
      _lineRepresentsAi(line)
          ? _historyPracticeAiVoice
          : _historyPracticeUserVoice;

  bool _isAiTurn(Map<String, dynamic> line) {
    final role = line['role'] as String;
    return _swapRoles ? role == 'HOST' : role == 'SYSTEM';
  }

  // 📦 [BOX-33: 유저 재녹음 핸들러]
  void _onTutorUserIconTap() {
    if (_tutorAwaitingStart || currentIndex >= _tutorLines.length) return;
    final line = _tutorLines[currentIndex];
    if (_isAiTurn(line)) {
      return;
    }
    try {
      _stopAutoVADRecording();
    } catch (_) {}
    if (mounted) setState(() => _tutorUserRecording = false);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      if (currentIndex >= _tutorLines.length) return;
      _startAutoVADRecording();
    });
  }

  // 📦 [BOX-34: 완료 후 전체 통합 재생]
  Future<void> _startTurnPracticeFullback() async {
    if (_tutorPlayingFullback) {
      audioPlayer.stop();
      _tutorAudioPlayer?.stop();
      if (mounted) setState(() => _tutorPlayingFullback = false);
      return;
    }
    if (mounted) setState(() => _tutorPlayingFullback = true);
    try {
      for (int i = 0; i < _tutorLines.length; i++) {
        if (!mounted || !_tutorPlayingFullback) break;
        final line = _tutorLines[i];
        final bool isAutomatedTurn = _isAiTurn(line);
        final text = (line['text'] as String).trim();
        if (text.isEmpty) continue;
        if (isAutomatedTurn) {
          final voice = _practiceVoiceForLine(line);
          final cacheVoice = _practiceCacheVoice(voice);
          Uint8List? audio = line['ai_audio_bytes'] as Uint8List?;
          if (audio != null) {
          } else {
            // 🔧 [v3.7] TtsCache 우선 조회 → MISS 시 API 호출 후 캐시+메모리 저장
            audio = await TtsCache.get(text, cacheVoice);
            if (audio != null) {
              line['ai_audio_bytes'] = audio;
            } else {
              audio = await _getOrFetchPracticeTTS(text, voice);
              if (audio != null) {
                line['ai_audio_bytes'] = audio;
                TtsCache.put(text, cacheVoice, audio);
              }
            }
          }
          if (!mounted || !_tutorPlayingFullback) break;
          if (audio != null) {
            final completer = Completer<void>();
            final player = AudioPlayer();
            _tutorAudioPlayer = player;
            StreamSubscription? sub;
            sub = player.onPlayerComplete.listen((_) {
              if (!completer.isCompleted) completer.complete();
              sub?.cancel();
            });
            try {
              await player.play(BytesSource(audio));
              await completer.future
                  .timeout(const Duration(seconds: 30), onTimeout: () {});
            } finally {
              sub?.cancel();
              await player.dispose();
              _tutorAudioPlayer = null;
            }
          }
        } else {
          // 🆕 [BOX-34-FIX] 공유 audioPlayer 대신 별도 플레이어 사용
          // (공유 플레이어는 onPlayerComplete에 영구 리스너가 있어 _onAudioComplete 호출 충돌)
          final recordPath = line['user_record_path'] as String?;
          if (recordPath != null && recordPath.isNotEmpty) {
            if (!mounted || !_tutorPlayingFullback) break;
            final completer = Completer<void>();
            final userPlayer = AudioPlayer();
            StreamSubscription? sub;
            sub = userPlayer.onPlayerComplete.listen((_) {
              if (!completer.isCompleted) completer.complete();
              sub?.cancel();
            });
            try {
              await userPlayer.play(DeviceFileSource(recordPath));
              await completer.future
                  .timeout(const Duration(seconds: 30), onTimeout: () {});
            } finally {
              sub?.cancel();
              await userPlayer.dispose();
            }
          }
        }
        if (!mounted || !_tutorPlayingFullback) break;
        await Future.delayed(const Duration(milliseconds: 400));
      }
    } catch (e) {
      debugPrint("[startTurnPracticeFullback] $e");
    } finally {
      if (mounted) setState(() => _tutorPlayingFullback = false);
    }
  }

  // 📦 [Box 22-E: 양방향 턴제 연습 화면]
  Widget _buildPracticeLineText(
      Map<String, dynamic> line, bool isCurrent, bool lineIsAi) {
    final text = line['text'] as String;
    final base = TextStyle(
      color: isCurrent ? Colors.white : Colors.white60,
      fontSize: 14 * _fontScale,
      height: 1.5,
      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
    );
    // 📖 배울글 아래에 대화 언어 원문을 함께 둔다. 위는 따라 말할 글,
    //   아래는 그때 실제로 오간 말 — 둘이 붙어 있어야 "내 생각이 저 문장이
    //   됐다"가 보인다. 배울글이 없는 줄은 `native`가 비어 있어 예전과 같다.
    final native = (line['native'] ?? '').toString().trim();
    if (native.isEmpty || native == text) {
      return Text(text,
          textAlign: lineIsAi ? TextAlign.right : TextAlign.left, style: base);
    }
    return Column(
      crossAxisAlignment:
          lineIsAi ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text,
            textAlign: lineIsAi ? TextAlign.right : TextAlign.left,
            style: base),
        const SizedBox(height: 4),
        Text(
          native,
          textAlign: lineIsAi ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            color: isCurrent ? Colors.white54 : Colors.white38,
            fontSize: 12 * _fontScale,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildTurnPracticeScreen() {
    final bool isAwaiting = _tutorAwaitingStart;
    final bool isComplete = currentIndex >= _tutorLines.length;

    return Stack(
      children: [
        Column(
          children: [
            // 📦 [BOX-31] 헤더 인디케이터
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    tooltip: '학습 경로 다시 고르기',
                    onPressed: _backToStudySelect,
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 좌측: 유저 아이콘 — 역할 선택(대기) 또는 재녹음
                        AnimatedBuilder(
                          animation: _blinkController,
                          builder: (context, child) => Opacity(
                            opacity: isAwaiting ? _blinkOpacity.value : 1.0,
                            child: child,
                          ),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: isAwaiting
                                ? () => _confirmStart(swap: false)
                                : _onTutorUserIconTap,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _tutorUserRecording
                                    ? Colors.greenAccent.withValues(alpha: 0.15)
                                    : isAwaiting
                                        ? Colors.greenAccent
                                            .withValues(alpha: 0.08)
                                        : Colors.white.withValues(alpha: 0.04),
                                border: Border.all(
                                  color: _tutorUserRecording
                                      ? Colors.greenAccent
                                      : isAwaiting
                                          ? Colors.greenAccent
                                              .withValues(alpha: 0.65)
                                          : Colors.white24,
                                  width: _tutorUserRecording ? 2 : 1.5,
                                ),
                              ),
                              child: Icon(
                                Icons.person_rounded,
                                size: 18,
                                color: _tutorUserRecording
                                    ? Colors.greenAccent
                                    : isAwaiting
                                        ? Colors.greenAccent
                                            .withValues(alpha: 0.85)
                                        : Colors.white38,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 📏 글꼴을 크게 써 둔 기기에서도 한 줄로 보이게
                        //   자리에 맞춰 줄인다. 양옆은 인물 아이콘이 잡고 있어
                        //   남는 폭이 좁다.
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                isComplete ? "Practice 완료!" : "Practice",
                                maxLines: 1,
                                style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 우측: AI 아이콘 — 역할 선택(대기)
                        AnimatedBuilder(
                          animation: _blinkController,
                          builder: (context, child) => Opacity(
                            opacity: isAwaiting ? _blinkOpacity.value : 1.0,
                            child: child,
                          ),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: isAwaiting
                                ? () => _confirmStart(swap: true)
                                : null,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _tutorAiSpeaking
                                    ? Colors.blue.withValues(alpha: 0.15)
                                    : isAwaiting
                                        ? Colors.blue.withValues(alpha: 0.08)
                                        : Colors.white.withValues(alpha: 0.04),
                                border: Border.all(
                                  color: _tutorAiSpeaking
                                      ? Colors.blue
                                      : isAwaiting
                                          ? Colors.blue.withValues(alpha: 0.65)
                                          : Colors.white24,
                                  width: _tutorAiSpeaking ? 2 : 1.5,
                                ),
                              ),
                              child: Icon(
                                Icons.smart_toy_rounded,
                                size: 18,
                                color: _tutorAiSpeaking
                                    ? Colors.blue
                                    : isAwaiting
                                        ? Colors.blue.withValues(alpha: 0.85)
                                        : Colors.white38,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 빌링 상태 인디케이터
                  ValueListenableBuilder<int>(
                    valueListenable: BillingTicker.instance.billingState,
                    builder: (_, s, __) => GestureDetector(
                      onTap: s == 0 ? resetBillingIdle : null,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, right: 6),
                        child: CustomPaint(
                          size: const Size(16, 16),
                          painter: BillingDotPainter(s),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 진행 바
            LinearProgressIndicator(
              value: _tutorLines.isEmpty
                  ? 0
                  : (currentIndex / _tutorLines.length).clamp(0.0, 1.0),
              backgroundColor: Colors.white12,
              color: Colors.amber,
              minHeight: 3,
            ),

            // 대화 목록
            Expanded(
              child: ListView.builder(
                controller: _practiceScrollController,
                padding: const EdgeInsets.all(14),
                itemCount: _tutorLines.length + 1,
                itemBuilder: (context, i) {
                  if (i == _tutorLines.length) {
                    return Container(
                      height: 120,
                      decoration:
                          const BoxDecoration(color: Colors.transparent),
                    );
                  }
                  final key =
                      _practiceItemKeys.putIfAbsent(i, () => GlobalKey());
                  final line = _tutorLines[i];
                  final bool lineIsAi = _isAiTurn(line); // 🆕 [BOX-32] 스왑 반영
                  final bool isCurrent = i == currentIndex;
                  final bool isPast = i < currentIndex;
                  final Color roleColor =
                      lineIsAi ? Colors.amber : Colors.greenAccent;

                  return Align(
                    alignment:
                        lineIsAi ? Alignment.centerRight : Alignment.centerLeft,
                    child: AnimatedOpacity(
                      key: key,
                      duration: const Duration(milliseconds: 300),
                      opacity: isPast ? 0.45 : 1.0,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.80,
                        ),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? roleColor.withValues(alpha: 0.1)
                              : const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrent ? roleColor : Colors.white12,
                            width: isCurrent ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isCurrent
                                    ? roleColor.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.05),
                                border: Border.all(
                                  color: isCurrent ? roleColor : Colors.white24,
                                  width: isCurrent ? 2 : 1,
                                ),
                              ),
                              child: Icon(
                                lineIsAi
                                    ? Icons.smart_toy_rounded
                                    : Icons.person_rounded,
                                color: isCurrent ? roleColor : Colors.white38,
                                size: 17,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: lineIsAi
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  _buildPracticeLineText(
                                      line, isCurrent, lineIsAi),
                                  // 📐 아래 세 줄 안내(녹음 중 / 다시 읽어
                                  //   주세요 / AI 재생 중)는 Icon + Text를
                                  //   Row에 나란히 둔다. Text를 그냥 두면
                                  //   기기 글자 크기를 키웠을 때 말풍선 폭을
                                  //   넘어 가로로 터졌다(실기기 1.7배에서
                                  //   37px 초과, 2026-08-27). Flexible로
                                  //   감싸 남는 폭에 맞춰 줄바꿈하게 한다.
                                  if (isCurrent &&
                                      !lineIsAi &&
                                      _isAutoRecording) ...[
                                    const SizedBox(height: 6),
                                    Row(children: const [
                                      Icon(Icons.graphic_eq,
                                          color: Colors.greenAccent, size: 15),
                                      SizedBox(width: 5),
                                      Flexible(
                                        child: Text("녹음 중...",
                                            style: TextStyle(
                                                color: Colors.greenAccent,
                                                fontSize: 11)),
                                      ),
                                    ]),
                                  ],
                                  if (isCurrent &&
                                      !lineIsAi &&
                                      _showRetryHint) ...[
                                    const SizedBox(height: 6),
                                    Row(children: const [
                                      Icon(Icons.mic_off,
                                          color: Colors.orange, size: 15),
                                      SizedBox(width: 5),
                                      Flexible(
                                        child: Text("끝까지 다시 읽어 주세요 🎙",
                                            style: TextStyle(
                                                color: Colors.orange,
                                                fontSize: 11)),
                                      ),
                                    ]),
                                  ],
                                  if (isCurrent && lineIsAi && isPlaying) ...[
                                    const SizedBox(height: 6),
                                    Row(children: const [
                                      Icon(Icons.volume_up,
                                          color: Colors.amber, size: 15),
                                      SizedBox(width: 5),
                                      Flexible(
                                        child: Text("AI 재생 중...",
                                            style: TextStyle(
                                                color: Colors.amber,
                                                fontSize: 11)),
                                      ),
                                    ]),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // 완료 후 액션
            if (isComplete)
              Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 12, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(
                              _tutorPlayingFullback
                                  ? Icons.stop_rounded
                                  : Icons.volume_up_rounded,
                              size: 18,
                            ),
                            label: Text(
                              _tutorPlayingFullback ? "정지" : "Play all",
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Colors.blue.withValues(alpha: 0.15),
                              foregroundColor: Colors.blue,
                              side: const BorderSide(color: Colors.blue),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: _startTurnPracticeFullback,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.replay_rounded, size: 18),
                            label: const Text("Start over",
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Colors.greenAccent.withValues(alpha: 0.1),
                              foregroundColor: Colors.greenAccent,
                              side: const BorderSide(color: Colors.greenAccent),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: () {
                              audioPlayer.stop();
                              _tutorAudioPlayer?.stop();
                              for (final l in _tutorLines) {
                                // 🆕 [BOX-34-CLEANUP] 실제 파일도 삭제
                                final rp = l['user_record_path'] as String?;
                                if (rp != null && rp.isNotEmpty) {
                                  File(rp).delete().ignore();
                                }
                                l.remove('user_record_path');
                                l.remove('ai_audio_bytes');
                              }
                              if (mounted) {
                                setState(() {
                                  currentIndex = 0;
                                  _tutorPlayingFullback = false;
                                  _tutorAwaitingStart = true;
                                  _swapRoles = false;
                                  _tutorAiSpeaking = false;
                                  _tutorUserRecording = false;
                                });
                                // 역할을 고르기 전부터 첫 대사가 보여야
                                // 한다. 여기서 안 돌리면 끝 화면을 본 채
                                // 역할을 고르게 된다.
                                if (_practiceScrollController.hasClients) {
                                  _practiceScrollController.jumpTo(0);
                                }
                                WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => _showRoleSelectBubble());
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _exitShadowing,
                      child: const Text("종료",
                          style:
                              TextStyle(color: Colors.white38, fontSize: 14)),
                    ),
                  ],
                ),
              ),
          ],
        ),
        // 역할 선택 말풍선 오버레이
        if (_showRoleBubble && isAwaiting)
          Positioned(
            top: 68,
            left: 0,
            right: 0,
            child: Center(child: _buildRoleSpeechBubble()),
          ),
      ],
    );
  }

  // 역할 선택 말풍선 위젯
  Widget _buildRoleSpeechBubble() {
    return const SizedBox.shrink();
  }

  // 📦 [Box 23: UI - 하단 Practice 컨트롤 (enum 비교)]
  // ====================================================================
  // 📦 [Box 22-F: 의미단위 청크 연습 화면 - 새로운 Practice 메인 UI]
  // ====================================================================

  // 청크 탭 핸들러: 진행 중 다른 청크 탭 → 즉시 거기서 재시작
  void _onChunkTapped(int idx) {
    if (_isListening) _stopDeepgramListening();
    audioPlayer.stop();
    if (mounted) {
      setState(() {
        _currentChunkIdx = idx;
        _isPlayingFullUser = false;
        _isPlayingFullAI = false;
        _aiChunkPlaying = false;
        _aiChunkLoading = false;
      });
    }
    _playChunkAI(idx);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollCurrentChunkToCenter();
    });
  }

  void _onNativeEnglishUnitTapped(int idx) {
    if (_isListening) _stopDeepgramListening();
    audioPlayer.stop();
    if (mounted) {
      setState(() {
        _nativeEnglishUnitIdx = idx;
        _nativeEnglishUnitAIPlaying = false;
      });
    }
    _playNativeEnglishUnit(idx);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollCurrentNativeEnglishUnitToCenter();
    });
  }

  // 🆕 [BOX-34-SCROLL] Practice 화면에서 현재 인덱스 아이템을 스크롤
  void _scrollPracticeToIndex(int idx) {
    final key = _practiceItemKeys[idx];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.4,
      );
    }
  }

  // 🆕 [BOX-34-CLEANUP] Practice 세션 임시 녹음 파일 삭제
  Future<void> _deleteUserRecordings() async {
    for (final l in _tutorLines) {
      final path = l['user_record_path'] as String?;
      if (path != null && path.isNotEmpty) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }
  }

  // 현재 청크가 화면 중앙에 오도록 스크롤 (GlobalKey 기반 → 실제 높이 반영)
  void _scrollCurrentChunkToCenter() {
    if (_currentChunkIdx < 0) return;
    final key = _itemKeys[_currentChunkIdx];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.35,
      );
      return;
    }
    if (!_chunkScrollController.hasClients) return;
    const double estimatedItemHeight = 120.0;
    final double viewportHeight =
        _chunkScrollController.position.viewportDimension;
    final double targetOffset = (_currentChunkIdx * estimatedItemHeight) -
        (viewportHeight / 2 - estimatedItemHeight / 2);
    final double clamped = targetOffset.clamp(
      0.0,
      _chunkScrollController.position.maxScrollExtent,
    );
    _chunkScrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  // Native English 현재 단위가 화면 중앙에 오도록 스크롤
  void _scrollCurrentNativeEnglishUnitToCenter() {
    if (_nativeEnglishUnitIdx < 0) return;
    final key = _nativeEnglishItemKeys[_nativeEnglishUnitIdx];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.35,
      );
      return;
    }
    if (!_chunkScrollController.hasClients) return;
    const double estimatedItemHeight = 90.0;
    final double viewportHeight =
        _chunkScrollController.position.viewportDimension;
    final double targetOffset = (_nativeEnglishUnitIdx * estimatedItemHeight) -
        (viewportHeight / 2 - estimatedItemHeight / 2);
    final double clamped = targetOffset.clamp(
      0.0,
      _chunkScrollController.position.maxScrollExtent,
    );
    _chunkScrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  // 의미단위 AI TTS 재생
  // 🔧 [v3.7] TtsCache 우선 조회 → MISS 시 API 호출 후 캐시 저장
  Future<void> _playNativeEnglishUnit(int idx) async {
    _resumeHistoryFromUserAction();
    if (!mounted || idx >= _nativeEnglishUnits.length) return;
    if (mounted) setState(() => _nativeEnglishUnitAIPlaying = true);
    final text = _nativeEnglishUnits[idx];
    final cacheVoice = _practiceCacheVoice(_historyPracticeAiVoice);
    Uint8List? audio = await TtsCache.get(text, cacheVoice);
    if (audio != null) {
    } else {
      audio = await _getOrFetchPracticeTTS(text, _historyPracticeAiVoice);
      if (audio != null) {
        TtsCache.put(text, cacheVoice, audio);
      }
    }
    if (!mounted) return;
    if (audio != null) {
      await audioPlayer.play(BytesSource(audio));
    } else {
      if (mounted) setState(() => _nativeEnglishUnitAIPlaying = false);
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // 🎤 [P3-SPEAK] Speaking Practice
  //
  //   고른 한 벌(MY SPEECH 또는 NATIVE ENGLISH)을 **실제로 입에 붙이는**
  //   자리다. 두 벌 모두 같은 흐름을 그대로 쓴다.
  //
  //     Stage 1 Breath Echoing — 호흡 하나씩 듣고 혼자 따라 말하기
  //     Stage 2 Full Echo      — 전체를 듣고, 끝난 뒤 혼자 전체 말하기
  //     Stage 3 Full Shadow    — 호흡 사이만 벌린 AI와 **동시에** 말하기
  //     Stage 4 Compare        — AI / ECHO / SHADOW 각각 다시 듣기
  //
  //   ⚠️ **TTS는 문장당 딱 한 번이다.** 네 단계가 전부 그 PCM 하나에서 나온다.
  //   Shadow를 열 번 반복해도 API 호출은 늘지 않는다.
  // ══════════════════════════════════════════════════════════════════

  /// 훈련이 대상으로 삼는 문장. MY SPEECH와 NATIVE ENGLISH 두 벌을 각각
  /// 같은 Speaking Practice 흐름으로 연다.
  ///
  /// ⚠️ **없으면 빈 문자열이다.** 고른 쪽이 비었다고 다른 쪽을 대신 걸지
  ///    않는다 — 두 카드가 같은 문장이 되면 견줄 것이 사라진다. 카드 자체가
  ///    [_p3VariantAvailable]로 잠기므로 빈 채로 들어올 일도 없다.
  String get _p3TargetSentence => _speechFor(_selectedVariant).trim();

  String _speechFor(SentenceVariant variant) =>
      variant == SentenceVariant.nativeEnglish ? _nativeEnglish : _mySpeech;

  bool _p3VariantAvailable(SentenceVariant variant) =>
      _speechFor(variant).trim().isNotEmpty;

  String _p3VariantLabel(SentenceVariant variant) =>
      variant == SentenceVariant.nativeEnglish ? 'NATIVE ENGLISH' : 'MY SPEECH';

  /// 🚧 Shadow 여유. **말하는 속도를 바꾸는 게 아니다** — AI의 발음·억양·속도는
  /// 그대로 두고 **호흡 사이 빈 자리만** 늘린다. 실기기에서 조정한다.
  static const Map<P3ShadowGap, int> _kP3ShadowGapMs = <P3ShadowGap, int>{
    P3ShadowGap.tight: 300,
    P3ShadowGap.normal: 500,
    P3ShadowGap.relaxed: 800,
  };

  static const Map<P3ShadowGap, String> _kP3ShadowGapLabel =
      <P3ShadowGap, String>{
    P3ShadowGap.tight: 'Tight',
    P3ShadowGap.normal: 'Normal',
    P3ShadowGap.relaxed: 'Relaxed',
  };

  /// 🚧 P3 전용 timing. **다른 모드의 VAD 값과 무관하다.** 최종값 아님.
  static const int _kP3EchoSilenceMs = 1800;
  static const int _kP3EchoNoSpeechMs = 10000;
  static const int _kP3ShadowTailMs = 700;
  static const Duration _kP3StageGap = Duration(milliseconds: 600);

  /// Start를 누른 뒤 첫 소리까지의 숨. 누르자마자 AI가 튀어나오면 화면을
  /// 볼 새도 준비할 새도 없다. Echoing·Shadowing 둘 다 같은 값을 쓴다.
  static const Duration _kP3StartDelay = Duration(seconds: 1);

  // ── P3 상태 ───────────────────────────────────────────────────────
  P3Stage _p3Stage = P3Stage.idle;
  P3PracticeMode _p3PracticeMode = P3PracticeMode.echoing;
  String _p3Voice = _kBreathVoice;
  int _p3Generation = 0;
  Uint8List? _p3FullPcm;
  List<BreathSegment> _p3Segments = const <BreathSegment>[];
  int _p3BreathIndex = 0;
  int _p3BreathTotal = 0;
  P3ShadowGap _p3Gap = P3ShadowGap.normal;
  String? _p3EchoPath;
  String? _p3ShadowPath;
  String? _p3Error;
  BreathEchoingEngine? _p3Engine;
  AudioPlayer? _p3Player;
  StreamSubscription<void>? _p3PlayerSub;
  Timer? _p3SilenceTimer;
  bool _p3Recording = false;
  bool _p3UserSpeaking = false;

  /// 🎤 [P3-ONEPAGE] 메뉴는 늘 맨 위에 있고 연습칸이 그 아래로 이어진다.
  ///   화면을 갈아 끼우지 않고 **한 페이지를 오르내린다.**
  final ScrollController _p3PageScrollController = ScrollController();

  /// 연습칸의 시작점. 스크롤이 여기를 화면 위로 올린다.
  final GlobalKey _p3PracticeKey = GlobalKey();

  /// 한 바퀴가 끝나고 메뉴로 되돌아가기까지의 유예. 이 동안 녹음을 눌러
  /// 들어볼 수 있고, 그냥 두면 알아서 위로 올라간다.
  Timer? _p3ReturnTimer;
  static const Duration _kP3ReturnDelay = Duration(seconds: 3);

  /// 문장을 갈아 끼우는 동안만 참. 없는 문장은 여기서 만들어 오느라 몇 초가
  /// 걸리는데, 그 사이 두 번째 탭이 들어오면 두 벌이 겹쳐 돈다.
  bool _p3VariantSwitching = false;

  bool get _p3Busy =>
      // 문장을 갈아 끼우는 동안은 Start·모드·보이스를 함께 잠근다. 문장 카드는
      // 제 잠금(`_p3VariantSwitching`)을 따로 본다 — 그래야 갈아탈 수 있다.
      _p3VariantSwitching ||
      _p3Stage == P3Stage.preparing ||
      _p3Stage == P3Stage.breathListen ||
      _p3Stage == P3Stage.breathEcho ||
      _p3Stage == P3Stage.fullEchoListen ||
      _p3Stage == P3Stage.fullEchoRecord ||
      _p3Stage == P3Stage.fullShadowRecord ||
      _p3Recording ||
      _p3Player != null;

  int get _p3GapMs => _kP3ShadowGapMs[_p3Gap] ?? 500;

  bool _p3Alive(int generation) =>
      mounted &&
      _phase == ShadowingPhase.chunkPractice &&
      generation == _p3Generation;

  void _setP3Stage(P3Stage stage) {
    if (!mounted) return;
    setState(() {
      _p3Stage = stage;
      if (stage != P3Stage.breathEcho) _p3UserSpeaking = false;
    });
  }

  /// 재생·녹음·타이머를 전부 접는다. 화면을 나가는 모든 길이 여기로 온다.
  /// 연습칸을 화면 위로 끌어올린다. 메뉴는 위로 밀려나지만 사라지지 않는다.
  void _scrollP3ToPractice() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _p3PracticeKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// 맨 위 메뉴로 되돌아간다. 연습칸은 아래에 그대로 남는다 — 방금 한 것을
  /// 지우지 않으므로 녹음도 계속 들어볼 수 있다.
  void _scrollP3ToMenu() {
    if (!_p3PageScrollController.hasClients) return;
    _p3PageScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  /// 📜 [P3-READ-SCROLL] 읽는 진행만큼 **페이지를** 민다. 0이면 문장 첫 줄이
  /// 화면 위, 1이면 **문장 끝과 그 아래 버튼까지** 화면 안에 들어온다.
  ///
  /// 끝점을 문장 패널 하단으로 잡으면 패널 바로 밑의 [AI]·[ECHO]·[SHADOW]
  /// 듣기 줄과 Stop이 화면 밖에 남는다. 한 문장짜리 시절에는 패널이 작아
  /// 애초에 다 보였지만, My Speech는 여러 문장이라 패널이 화면을 채운다.
  /// 그래서 끝점을 **컨트롤 묶음 하단**까지 넓힌다.
  ///
  /// 스크롤 면은 페이지 하나뿐이다. 문장 칸에 자기 스크롤을 주면 그 위에
  /// 얹힌 손가락이 갇혀 아래 버튼까지 못 내려간다.
  ///
  /// 글자와 소리를 잇는 지도는 없다 — 호흡 경계는 PCM에서 나온 값이라 몇 번째
  /// 글자인지 모른다. 그래서 진행률로만 민다. 문장이 한 화면에 다 들어오면
  /// 밀 거리가 없어 아무 일도 하지 않는다.
  void _p3ScrollReadingTo(double progress) {
    if (_p3AutoScrollBlocked) return;
    final c = _p3PageScrollController;
    if (!c.hasClients) return;
    final ctx = _p3SentenceKey.currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    // alignment 0 = 패널 위가 화면 위, 1 = 패널 아래가 화면 아래.
    final double top = viewport.getOffsetToReveal(box, 0.0).offset;
    double bottom = viewport.getOffsetToReveal(box, 1.0).offset;
    // 아래 버튼까지가 끝이다. 둘 중 더 아래를 끝점으로 삼는다.
    final controlsBox =
        _p3ControlsKey.currentContext?.findRenderObject() as RenderBox?;
    if (controlsBox != null && controlsBox.hasSize) {
      final double controlsBottom =
          viewport.getOffsetToReveal(controlsBox, 1.0).offset;
      if (controlsBottom > bottom) bottom = controlsBottom;
    }
    // 본문과 버튼이 통째로 한 화면에 들어오면 `bottom <= top`이라 여기서
    // 멈춘다 — 짧은 문장은 예전처럼 한 번도 움직이지 않는다.
    if (bottom <= top) return;
    final double max = c.position.maxScrollExtent;
    final double target =
        (top + (bottom - top) * progress.clamp(0.0, 1.0)).clamp(0.0, max);
    if ((target - c.offset).abs() < 8) return;
    c.animateTo(
      target,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
    );
  }

  /// 한 바퀴가 끝났다. 바로 튕겨 올리지 않고 [_kP3ReturnDelay]만큼 둔다.
  void _scheduleP3ReturnToMenu() {
    _p3ReturnTimer?.cancel();
    _p3ReturnTimer = Timer(_kP3ReturnDelay, () {
      if (!mounted || _phase != ShadowingPhase.chunkPractice) return;
      _scrollP3ToMenu();
    });
  }

  Future<void> _stopP3Shadowing({bool resetSelection = false}) async {
    _p3ReturnTimer?.cancel();
    _p3Generation++;
    _p3SilenceTimer?.cancel();
    _p3SilenceTimer = null;
    await _p3PlayerSub?.cancel();
    _p3PlayerSub = null;
    final player = _p3Player;
    _p3Player = null;
    if (player != null) {
      try {
        await player.stop();
      } catch (_) {}
      try {
        await player.dispose();
      } catch (_) {}
    }
    await _p3Engine?.stop();
    if (_p3Recording) {
      _p3Recording = false;
      try {
        await appAudioRecorder.stop();
      } catch (_) {}
    }
    if (resetSelection) {
      _deleteP3Recordings();
      _p3FullPcm = null;
      _p3Segments = const <BreathSegment>[];
    }
    if (mounted && resetSelection) {
      setState(() {
        _p3Stage = P3Stage.idle;
        _p3Error = null;
        _p3UserSpeaking = false;
      });
    }
  }

  void _deleteP3Recordings() {
    _deleteP3File(_p3EchoPath);
    _deleteP3File(_p3ShadowPath);
    _p3EchoPath = null;
    _p3ShadowPath = null;
  }

  /// 완성/세련 문장은 TTS·호흡·사용자 녹음이 서로 다른 한 벌이다.
  /// 문장을 바꾸면 현재 회차를 완전히 접고 새 선택을 준비한다. 원본 TTS는
  /// text가 캐시 identity에 들어가므로 각 문장별로 재사용된다.
  ///
  /// **첫 화면에서는 고르기만 한다** — 시작은 ▶ Start가 연다. 한 번 시작한
  /// 뒤에는 Start가 화면에 없으므로, 메뉴에서 고르는 것이 곧 다시 시작이다.
  /// `_stopP3Shadowing`이 stage를 idle로 되돌리므로 **멈추기 전에** 진행
  /// 중이었는지를 기억해 둬야 한다.
  ///
  /// 🔁 **듣는 중에도 갈아탈 수 있다.** 돌고 있다고 잠가 두면 X로 나갔다
  /// 학습 경로에서 다시 들어오는 수밖에 없었다 — 두 문장을 번갈아 보는 것이
  /// 이 화면의 전부인데 그 길이 막혀 있었다. 누르면 돌던 회차를 접고 그
  /// 자리에서 새 문장으로 다시 돈다.
  ///
  /// 아직 만들지 않은 문장도 여기서 만든다. 순서는 [_ensureSpeechVariant]가
  /// 지킨다 — NATIVE ENGLISH의 재료는 언제나 My Speech다.
  ///
  /// 모드·보이스와 같은 규칙으로 **화면부터 칠한다.** `_stopP3Shadowing`이
  /// 실기기에서 1초 가까이 걸려서, 그걸 기다렸다 칠하니 눌러도 안 바뀌는
  /// 것처럼 보였다. 다만 **아직 없는 문장은 미리 칠하지 않는다** — 빈 문장을
  /// 고른 상태가 한 순간도 생기면 안 된다. 그쪽은 카드의 스피너가 알린다.
  Future<void> _selectP3Variant(SentenceVariant variant) async {
    if (_p3VariantSwitching) return;
    final bool wasStarted = _p3Stage != P3Stage.idle;
    final bool hasSentence = _p3VariantAvailable(variant);
    if (_selectedVariant == variant && !wasStarted && hasSentence) return;
    setState(() {
      _p3VariantSwitching = true;
      if (hasSentence) {
        _selectedVariant = variant;
        _p3Stage = P3Stage.idle;
        _p3Error = null;
        _p3UserSpeaking = false;
      }
    });
    bool ready = hasSentence;
    try {
      await _stopP3Shadowing(resetSelection: true);
      if (!mounted || _phase != ShadowingPhase.chunkPractice) return;
      if (!ready) {
        final bool built = await _ensureSpeechVariant(variant);
        if (!mounted || _phase != ShadowingPhase.chunkPractice) return;
        if (!built) {
          setState(() => _p3Error = _variantBuildError(variant));
          return;
        }
        setState(() {
          _selectedVariant = variant;
          _p3Stage = P3Stage.idle;
          _p3Error = null;
          _p3UserSpeaking = false;
        });
        ready = true;
      }
    } finally {
      // 다시 도는 동안까지 잠가 두면 그 회차 내내 갈아탈 수 없다. 잠금은
      // 여기서 풀고, 시작은 밖에서 한다.
      if (mounted) {
        setState(() => _p3VariantSwitching = false);
      } else {
        _p3VariantSwitching = false;
      }
    }
    if (ready && wasStarted) await _startP3Speaking();
  }

  /// 고른 쪽이 비어 있으면 만들어 온다. 생성 순서는 하나뿐이다 —
  /// Conversation → My Speech → Native English. 실패하면 false이고 그 자리는
  /// 빈 채로 둔다 — 다른 쪽 문장을 대신 걸지 않는다.
  Future<bool> _ensureSpeechVariant(SentenceVariant variant) async {
    if (_mySpeech.trim().isEmpty && !await _ensureMySpeech()) return false;
    if (!mounted) return false;
    if (variant == SentenceVariant.mySpeech) return _mySpeech.trim().isNotEmpty;
    if (_nativeEnglish.trim().isNotEmpty) return true;
    return _ensureNativeEnglish();
  }

  String _variantBuildError(SentenceVariant variant) =>
      (variant == SentenceVariant.nativeEnglish
          ? _nativeEnglishError ?? _mySpeechError
          : _mySpeechError) ??
      '만들지 못했습니다 — 다시 시도해 주세요';

  /// 고르는 것은 **고르기까지만** 한다. 시작은 Start 버튼이다 — 누르지도
  /// 않았는데 소리가 나면 놀란다.
  ///
  /// 화면부터 칠하고 정지는 그 뒤에 기다린다. `_stopP3Shadowing`은 플레이어·
  /// 엔진·recorder를 모두 await해서 실기기에서 1초 가까이 걸리는데, 그걸
  /// 기다렸다 칠하니 눌러도 안 바뀌는 것처럼 보였다. 정지가 끝나기 전에는
  /// `_p3Busy`가 참이라 Start도 눌리지 않는다 — 중간에 끼어들 틈이 없다.
  Future<void> _selectP3PracticeMode(P3PracticeMode mode) async {
    if (_p3PracticeMode == mode && _p3Stage == P3Stage.idle) return;
    setState(() {
      _p3PracticeMode = mode;
      _coerceP3VoiceForMode();
      _p3Stage = P3Stage.idle;
      _p3Error = null;
      _p3UserSpeaking = false;
    });
    await _stopP3Shadowing(resetSelection: true);
  }

  /// ■ Stop — 연습을 접고 맨 위 메뉴로 되돌아간다.
  Future<void> _stopP3AndReturnToMenu() async {
    await _stopP3Shadowing(resetSelection: true);
    if (!mounted) return;
    _scrollP3ToMenu();
  }

  /// 최종 문장의 Sing-Song Flow PCM을 얻어 호흡으로 가른 뒤 Stage 1을 연다.
  ///
  /// ⚠️ **특정 단어만 세워 읽는 강조 지시문을 넣지 않는다.** 문장을 특정 단어만
  /// 도드라진 상태로 익히면 안 된다.
  Future<void> _startP3Speaking() async {
    if (!_guardPaidStudy()) return;
    final text = _p3TargetSentence;
    if (text.isEmpty) {
      _showRoomEntryToast('No sentence is available for P3');
      return;
    }
    await _stopP3Shadowing();
    final generation = ++_p3Generation;
    if (mounted) {
      setState(() {
        _p3Stage = P3Stage.preparing;
        _p3Error = null;
        _p3UserSpeaking = false;
        _p3AutoScrollBlocked = false;
      });
      // 메뉴는 위에 남고 연습칸이 화면 정면으로 올라온다.
      _scrollP3ToPractice();
    }

    Uint8List? pcm = _p3FullPcm;
    if (pcm == null || pcm.isEmpty) {
      try {
        pcm = await _getP3OriginalPcm(text);
      } catch (e) {
        debugPrint('[P3-SPEAK] tts $e');
      }
    }
    if (!_p3Alive(generation)) return;
    if (pcm == null || pcm.isEmpty) {
      setState(() {
        _p3Stage = P3Stage.idle;
        _p3Error = 'Could not create the practice voice';
      });
      return;
    }
    final analysis = analyzeBreaths(pcm, const BreathAnalysisConfig());
    if (analysis.segments.isEmpty) {
      setState(() {
        _p3Stage = P3Stage.idle;
        _p3Error = 'Could not detect breath groups';
      });
      return;
    }
    _p3FullPcm = pcm;
    _p3Segments = analysis.segments;
    if (mounted) {
      setState(() {
        _p3BreathIndex = 0;
        _p3BreathTotal = analysis.segments.length;
        _p3Stage = _p3PracticeMode == P3PracticeMode.echoing
            ? P3Stage.breathListen
            : P3Stage.fullShadowRecord;
      });
    }
    debugPrint('[P3-SPEAK] breaths=${analysis.segments.length} '
        'total=${analysis.totalMs}ms voice=$_p3Voice');
    // 화면이 먼저 자리를 잡고 나서 소리가 난다. 두 모드가 갈리기 전에 한 번만
    // 기다린다 — 각자 넣으면 값이 갈라진다.
    await Future<void>.delayed(_kP3StartDelay);
    if (!_p3Alive(generation)) return;
    if (_p3PracticeMode == P3PracticeMode.echoing) {
      await _ensureP3Engine().start(
        aiPcm: pcm,
        segments: analysis.segments,
        repeatCount: 1,
      );
    } else {
      await _runP3FullShadow();
    }
  }

  /// 원본 PCM. **강조 지시가 없는 순수 낭독**이라 Lab 캐시와 키가 다르다.
  Future<Uint8List?> _getP3OriginalPcm(String text) {
    final voice = _p3Voice;
    final style = _p3StyleFor(_p3PracticeMode);
    final ns = '${_p3CacheNamespaceFor(_p3PracticeMode, voice)}_p3';
    final requestKey = '$ns|$text';
    final existing = _breathPcmInFlight[requestKey];
    if (existing != null) return existing;
    final future = () async {
      final cached = await TtsCache.get(text, ns);
      if (cached != null && cached.length > 44) return pcmFromWav(cached);
      final raw = await _fetchOpenAITTSInternal(
        text,
        1.0,
        voice,
        model: _historyPracticeTtsModel,
        instructions: style.instruction,
        instructionTag: '${style.id}_p3',
        responseFormat: 'pcm',
      );
      if (raw == null || raw.isEmpty) return null;
      await TtsCache.put(
          text, ns, pcm16ToWav(raw, sampleRate: kStealthVoxSttSampleRate));
      return raw;
    }();
    _breathPcmInFlight[requestKey] = future;
    future.whenComplete(() => _breathPcmInFlight.remove(requestKey));
    return future;
  }

  BreathEchoingEngine _ensureP3Engine() {
    final existing = _p3Engine;
    if (existing != null) return existing;
    final engine = BreathEchoingEngine(
      recorder: appAudioRecorder,
      onPhase: (phase, index, total) {
        if (!mounted) return;
        setState(() {
          _p3BreathIndex = index;
          _p3BreathTotal = total;
          _p3UserSpeaking = phase == BreathEchoPhase.userSpeaking;
          if (phase == BreathEchoPhase.aiPlaying) {
            _p3Stage = P3Stage.breathListen;
          } else if (phase == BreathEchoPhase.waitingForUser ||
              phase == BreathEchoPhase.userSpeaking) {
            _p3Stage = P3Stage.breathEcho;
          }
        });
        // 📜 호흡이 넘어갈 때마다 그만큼 본문을 올린다. 첫 호흡은 0이라
        //   시작하자마자 움직이지는 않는다.
        if (phase == BreathEchoPhase.aiPlaying) {
          _p3ScrollReadingTo(total <= 1 ? 0 : index / (total - 1));
        }
        if (phase == BreathEchoPhase.userSpeaking) {
          BillingTicker.instance.resumeFromActivity('p3_breath_user');
        }
      },
      // 🎤 P3는 호흡별 녹음을 쓰지 않는다. 유저 PCM은 턴을 넘기는 판정에만
      //   쓰이고 여기서 버려진다 — 조립하지도 저장하지도 않는다.
      onLineComplete: (_, __) => unawaited(_onP3BreathDone()),
      onError: (message) => debugPrint('[P3-SPEAK] $message'),
    );
    _p3Engine = engine;
    return engine;
  }

  Future<void> _onP3BreathDone() async {
    final generation = _p3Generation;
    await Future<void>.delayed(_kP3StageGap);
    if (!_p3Alive(generation)) return;
    await _runP3FullEcho();
  }

  /// AI 전체를 듣고 **끝난 뒤** 혼자 전체 문장을 말한다. 겹치지 않는다.
  Future<void> _runP3FullEcho() async {
    final pcm = _p3FullPcm;
    if (pcm == null) return;
    final generation = ++_p3Generation;
    _setP3Stage(P3Stage.fullEchoListen);
    await _playP3Pcm(pcm, generation);
    if (!_p3Alive(generation)) return;

    // AI가 완전히 끝났다. 고정 대기를 두지 않는다 — mic start는 30ms 안쪽이다.
    final path = await _startP3Recording('echo');
    if (!_p3Alive(generation) || path == null) {
      await _stopP3Recording();
      return;
    }
    _setP3Stage(P3Stage.fullEchoRecord);
    // 📜 방금 낭독이 끝난 자리는 문장 **끝**이다. 이제 유저가 처음부터 통째로
    //    말할 차례라 첫 줄로 되돌린다. 이 구간에는 진행을 알려 줄 소리가 없어
    //    자동으로 밀지 않는다 — 그 뒤로는 손으로 끄는 대로 둔다.
    _p3ScrollReadingTo(0);
    _watchP3Silence(
      generation,
      silenceMs: _kP3EchoSilenceMs,
      noSpeechMs: _kP3EchoNoSpeechMs,
      // 한 바퀴가 끝나도 화면을 갈아 끼우지 않는다. compare를 그대로 두어
      //   녹음을 들어볼 수 있게 하고, 3초 뒤 **스크롤만** 메뉴로 올린다.
      onDone: (recorded, spoke) {
        if (!spoke) {
          // 말하지 않았다. 빈 파일을 성공한 녹음으로 취급하지 않는다.
          _deleteP3File(recorded ?? path);
          setState(() {
            _p3Error = 'No speech was detected';
            _p3Stage = P3Stage.compare;
            _p3UserSpeaking = false;
          });
          _scheduleP3ReturnToMenu();
          return;
        }
        _deleteP3File(_p3EchoPath);
        setState(() {
          _p3EchoPath = recorded ?? path;
          _p3Error = null;
          _p3Stage = P3Stage.compare;
          _p3UserSpeaking = false;
        });
        _scheduleP3ReturnToMenu();
      },
    );
  }

  /// 호흡 사이만 [_p3GapMs]만큼 벌린 AI와 **동시에** 말한다.
  ///
  /// **recorder를 먼저 연 뒤 재생을 시작한다** — 반대로 하면 첫 음절이 잘린다.
  /// 발화 감지로 폐기하지 않는다: 스피커 소리가 마이크에 들어와 유저 목소리와
  /// 구분되지 않기 때문이다(재생 시간 기준으로 정상 종료).
  Future<void> _runP3FullShadow() async {
    final pcm = _p3FullPcm;
    if (pcm == null || _p3Segments.isEmpty) return;
    final generation = ++_p3Generation;
    await _stopP3Playback();
    if (mounted) setState(() => _p3Error = null);

    final gapped = buildGappedPcm(
      pcm,
      _p3Segments,
      extraGapMs: _p3GapMs,
      sampleRate: kStealthVoxSttSampleRate,
    );
    final path = await _startP3Recording('shadow');
    if (!_p3Alive(generation) || path == null) {
      await _stopP3Recording();
      return;
    }
    _setP3Stage(P3Stage.fullShadowRecord);
    await _playP3Pcm(gapped, generation);
    if (!_p3Alive(generation)) {
      await _stopP3Recording();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: _kP3ShadowTailMs));
    if (!_p3Alive(generation)) {
      await _stopP3Recording();
      return;
    }
    final recorded = await _stopP3Recording();
    if (!_p3Alive(generation)) return;
    final old = _p3ShadowPath;
    if (old != null && old != (recorded ?? path)) _deleteP3File(old);
    setState(() {
      _p3ShadowPath = recorded ?? path;
      _p3Stage = P3Stage.compare;
      _p3UserSpeaking = false;
    });
    _scheduleP3ReturnToMenu();
  }

  Future<void> _stopP3Playback() async {
    await _p3PlayerSub?.cancel();
    _p3PlayerSub = null;
    final player = _p3Player;
    _p3Player = null;
    if (player != null) {
      try {
        await player.stop();
      } catch (_) {}
      try {
        await player.dispose();
      } catch (_) {}
    }
  }

  /// PCM을 WAV로 감싸 재생하고 **끝날 때까지 기다린다.**
  /// `onPlayerComplete.first`는 쓰지 않는다 — dispose 때 예외가 새어 나간다.
  Future<void> _playP3Pcm(Uint8List pcm, int generation) async {
    await _stopP3Playback();
    if (!_p3Alive(generation)) return;
    final wav = pcm16ToWav(pcm, sampleRate: kStealthVoxSttSampleRate);
    final player = AudioPlayer();
    _p3Player = player;
    final completer = Completer<void>();
    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    final sub = player.onPlayerComplete.listen(
      (_) => finish(),
      onDone: finish,
      onError: (Object _) => finish(),
      cancelOnError: false,
    );
    _p3PlayerSub = sub;
    final int expectedMs =
        pcm16DurationMs(pcm.length, sampleRate: kStealthVoxSttSampleRate);
    // 📜 통으로 읽는 구간(풀 에코 듣기·쉐도잉)은 재생 위치가 곧 읽는 자리다.
    unawaited(_p3ShadowPositionSub?.cancel());
    _p3ShadowPositionSub = expectedMs <= 0
        ? null
        : player.onPositionChanged.listen((pos) {
            if (!mounted) return;
            _p3ScrollReadingTo(pos.inMilliseconds / expectedMs);
          });
    try {
      await player.play(BytesSource(wav));
      await completer.future.timeout(
        Duration(milliseconds: expectedMs + 8000),
        onTimeout: finish,
      );
    } catch (e) {
      debugPrint('[P3-SPEAK] play $e');
    } finally {
      await sub.cancel();
      await _p3ShadowPositionSub?.cancel();
      _p3ShadowPositionSub = null;
      if (identical(_p3PlayerSub, sub)) _p3PlayerSub = null;
      if (identical(_p3Player, player)) _p3Player = null;
      try {
        await player.stop();
      } catch (_) {}
      try {
        await player.dispose();
      } catch (_) {}
    }
  }

  Future<String?> _startP3Recording(String tag) async {
    if (_p3Recording) return null;
    try {
      if (!await appAudioRecorder.hasPermission()) {
        if (mounted) {
          setState(() => _p3Error = 'Microphone permission required');
        }
        return null;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/p3${tag}_'
          '${DateTime.now().millisecondsSinceEpoch}.m4a';
      await appAudioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      _p3Recording = true;
      return path;
    } catch (e) {
      if (mounted) setState(() => _p3Error = 'Could not start recording: $e');
      return null;
    }
  }

  Future<String?> _stopP3Recording() async {
    _p3SilenceTimer?.cancel();
    _p3SilenceTimer = null;
    if (!_p3Recording) return null;
    _p3Recording = false;
    try {
      return await appAudioRecorder.stop();
    } catch (_) {
      return null;
    }
  }

  /// 진폭 폴링으로 발화 종료를 본다. **Full Echo에만 쓴다** — Shadow는 AI
  /// 소리가 섞여 이 판정이 성립하지 않는다.
  void _watchP3Silence(
    int generation, {
    required int silenceMs,
    required int noSpeechMs,
    required void Function(String? path, bool spoke) onDone,
  }) {
    bool spoke = false;
    int silentTicks = 0;
    int elapsedTicks = 0;
    final int silentLimit = silenceMs ~/ 100;
    final int giveUpLimit = noSpeechMs ~/ 100;
    _p3SilenceTimer?.cancel();
    _p3SilenceTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!_p3Alive(generation) || !_p3Recording) {
        timer.cancel();
        return;
      }
      try {
        if (!await appAudioRecorder.isRecording()) {
          timer.cancel();
          return;
        }
        elapsedTicks++;
        final amp = await appAudioRecorder.getAmplitude();
        if (amp.current > -25.0) {
          spoke = true;
          silentTicks = 0;
        } else {
          silentTicks++;
        }
        final bool done =
            spoke ? silentTicks >= silentLimit : elapsedTicks >= giveUpLimit;
        if (done) {
          timer.cancel();
          final path = await _stopP3Recording();
          if (!_p3Alive(generation)) return;
          onDone(path, spoke);
        }
      } catch (_) {
        timer.cancel();
      }
    });
  }

  void _deleteP3File(String? path) {
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  Future<void> _playP3File(String? path) async {
    if (path == null || path.isEmpty) return;
    if (!await File(path).exists()) return;
    await _stopP3Playback();
    final player = AudioPlayer();
    _p3Player = player;
    final completer = Completer<void>();
    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    final sub = player.onPlayerComplete.listen(
      (_) => finish(),
      onDone: finish,
      onError: (Object _) => finish(),
      cancelOnError: false,
    );
    _p3PlayerSub = sub;
    if (mounted) setState(() {});
    try {
      await player.play(DeviceFileSource(path));
      await completer.future
          .timeout(const Duration(seconds: 90), onTimeout: finish);
    } catch (e) {
      debugPrint('[P3-SPEAK] file play $e');
    } finally {
      await sub.cancel();
      if (identical(_p3PlayerSub, sub)) _p3PlayerSub = null;
      if (identical(_p3Player, player)) _p3Player = null;
      try {
        await player.stop();
      } catch (_) {}
      try {
        await player.dispose();
      } catch (_) {}
      if (mounted) setState(() {});
    }
  }

  /// AI 원본 다시 듣기. TTS를 다시 부르지 않는다.
  Future<void> _playP3Original() async {
    final pcm = _p3FullPcm;
    if (pcm == null) return;
    await _playP3Pcm(pcm, _p3Generation);
  }

  // ── P3 화면 ───────────────────────────────────────────────────────

  Widget _buildChunkPracticeScreen() => _buildP3SpeakingScreen();

  String get _p3StageLabel {
    switch (_p3Stage) {
      case P3Stage.idle:
        return '';
      case P3Stage.preparing:
        return 'Preparing voice…';
      case P3Stage.breathListen:
        return 'Breath ${(_p3BreathIndex + 1).clamp(1, _p3BreathTotal)}/$_p3BreathTotal · Listen';
      case P3Stage.breathEcho:
        return 'Breath ${(_p3BreathIndex + 1).clamp(1, _p3BreathTotal)}/$_p3BreathTotal · Your turn';
      case P3Stage.fullEchoListen:
        return 'Listen to the full sentence';
      case P3Stage.fullEchoRecord:
        return 'Now say it on your own';
      case P3Stage.fullShadowRecord:
        return 'Speak along with the AI';
      case P3Stage.compare:
        return 'Compare the recordings';
    }
  }

  /// 🎤 [P3-ONEPAGE] 첫 화면은 **메뉴 + ▶ Start**만 있는 그대로다.
  ///
  /// 시작한 뒤부터 한 페이지가 된다 — 메뉴는 맨 위에 남고 연습칸이 그 아래로
  /// 이어진다. 그때부터는 Start를 다시 누르지 않는다: 메뉴에서 모드나 문장을
  /// 고르면 아래 내용이 곧바로 그것으로 바뀌며 진행된다.
  Widget _buildP3SpeakingScreen() {
    final text = _p3TargetSentence;
    final bool started = _p3Stage != P3Stage.idle;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: NotificationListener<ScrollStartNotification>(
        // 📜 손으로 끌기 시작하면 자동 스크롤은 물러난다. 우리가 animateTo로
        //    미는 것은 dragDetails가 없어 여기 걸리지 않는다.
        onNotification: (notification) {
          if (notification.dragDetails != null) _p3AutoScrollBlocked = true;
          return false;
        },
        child: SingleChildScrollView(
          controller: _p3PageScrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 메뉴 ── 첫 화면에서도, 연습 중에도 같은 자리에 있다.
              _buildP3VoiceSelector(),
              const SizedBox(height: 10),
              _buildP3PracticeModePicker(),
              const SizedBox(height: 14),
              // 라벨만 있으면 갈아타도 점 하나 옮겨진 것 말고는 달라진 게
              // 없어 보인다. 어느 문장으로 가는지 글자로 보여 준다.
              _buildP3VariantPicker(showPreview: true),
              if (_p3PracticeMode == P3PracticeMode.shadowing) ...[
                const SizedBox(height: 12),
                _buildP3GapPicker(),
              ],

              // 오류는 연습이 시작되지 못했을 때도 보여야 하므로 밖에 둔다.
              if (_p3Error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _p3Error!,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Color(0xFFFF6B6B), fontSize: 12),
                ),
              ],

              // ── Start ── 메뉴 밑에 늘 있다. 첫 화면이면 여기서 한 바퀴가
              //   열리고, 한 바퀴 돌린 뒤에는 고른 그대로 다시 돌린다.
              //   도는 중에는 잠근다 — 모드·보이스와 같은 규칙이다.
              const SizedBox(height: 14),
              _p3PrimaryButton(
                started ? '▶ Start again' : '▶ Start',
                _p3Busy ? null : () => unawaited(_startP3Speaking()),
              ),
              const SizedBox(height: 14),

              // ── 연습칸 ── 시작한 뒤에만. 메뉴 아래로 이어 붙는다.
              if (started)
                Column(
                  key: _p3PracticeKey,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    // 에코잉에서는 진도(Breath n/n · …)를 여기 두지 않는다.
                    //   귀로 따라오게 하는 연습이라 위쪽에 숫자가 있으면 눈이
                    //   먼저 간다. 호흡 위치는 문장 패널 안 카운터가 알린다.
                    if (_p3PracticeMode == P3PracticeMode.echoing)
                      const Text(
                        'Read it in one breath',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      )
                    else
                      Text(
                        _p3StageLabel,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _p3Stage == P3Stage.fullShadowRecord
                              ? Colors.amber
                              : Colors.white54,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 14),
                    _buildP3SentencePanel(text),

                    // ── 2) 한 바퀴가 끝난 뒤: 에코잉만 다시 돌린다.
                    //   모드는 그대로라 쉐도잉으로 넘어가지 않는다. 아래
                    //   [AI]·[ECHO] 듣기 버튼은 건드리지 않는다.
                    if (_p3Stage == P3Stage.compare &&
                        _p3PracticeMode == P3PracticeMode.echoing) ...[
                      const SizedBox(height: 14),
                      _p3PrimaryButton(
                        '↻ Echo Again',
                        _p3Busy ? null : () => unawaited(_startP3Speaking()),
                      ),
                    ],
                    const SizedBox(height: 18),
                    // 📜 [P3-READ-SCROLL] 다 읽었을 때 화면에 들어와야 하는
                    //    끝자락이다. 자동 스크롤이 이 묶음을 기준으로 멈춘다.
                    Column(
                      key: _p3ControlsKey,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildP3CompareRow(),
                        const SizedBox(height: 12),
                        // 맨 밑 정지 — 연습을 접고 첫 화면으로 돌아간다.
                        _p3SecondaryButton(
                          '■ Stop',
                          () => unawaited(_stopP3AndReturnToMenu()),
                        ),
                      ],
                    ),
                    // 연습칸이 화면 맨 위까지 올라갈 수 있으려면 아래에 여백이
                    // 있어야 한다. 없으면 스크롤이 끝에 걸려 메뉴가 안 밀린다.
                    SizedBox(height: MediaQuery.of(context).size.height * 0.55),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Voice Lab의 차분한 surface와 호흡 포인트 컬러를 P3용으로 정리한다.
  /// 사용자 차례가 오면 본문 색만 살짝 바꾸고, VAD가 실제 목소리를 잡은
  /// 동안에만 바탕·테두리·마이크 표시를 한 단계 더 밝힌다.
  /// 어느 경우에도 자리와 크기는 그대로다 — 읽는 중에 글자가 움직이면 안 된다.
  Widget _buildP3SentencePanel(String text) {
    final bool inBreathEcho =
        _p3Stage == P3Stage.breathListen || _p3Stage == P3Stage.breathEcho;
    final bool userTurn = _p3Stage == P3Stage.breathEcho ||
        _p3Stage == P3Stage.fullEchoRecord ||
        _p3Stage == P3Stage.fullShadowRecord;
    final bool speaking = (inBreathEcho && _p3UserSpeaking) ||
        _p3Stage == P3Stage.fullEchoRecord ||
        _p3Stage == P3Stage.fullShadowRecord;
    final Color userTurnAccent = _p3PracticeMode == P3PracticeMode.echoing
        ? _p3BreathAccentColor
        : _p3ShadowingAccentColor;
    final int safeTotal = _p3BreathTotal.clamp(0, 24);
    final int safeIndex =
        safeTotal == 0 ? 0 : _p3BreathIndex.clamp(0, safeTotal - 1);

    return AnimatedContainer(
      key: _p3SentenceKey,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 17),
      decoration: BoxDecoration(
        color: speaking
            ? _p3BreathAccentColor.withValues(alpha: 0.10)
            : _p3PracticeSurfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: speaking
              ? _p3BreathAccentColor.withValues(alpha: 0.72)
              : inBreathEcho
                  ? _p3BreathAccentColor.withValues(alpha: 0.30)
                  : _p3PracticeBorderColor,
          // 굵기는 고정이다. 1 → 1.4로 바뀌면 테두리가 안쪽을 그만큼 먹어
          // 본문이 미세하게 밀린다 — 읽는 중에 글자가 흔들려 보였다.
          width: 1.4,
        ),
        boxShadow: speaking
            ? <BoxShadow>[
                BoxShadow(
                  color: _p3BreathAccentColor.withValues(alpha: 0.10),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 높이를 잡아 둔다. READING 배지가 떴다 사라질 때마다 이 줄이
          // 커졌다 작아지면서 아래 본문이 통째로 오르내렸다.
          SizedBox(
            height: 24,
            child: Row(
              children: <Widget>[
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: Icon(
                    speaking ? Icons.mic_rounded : Icons.air_rounded,
                    key: ValueKey<bool>(speaking),
                    color: inBreathEcho ? _p3BreathAccentColor : Colors.white30,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  _p3PracticeMode == P3PracticeMode.echoing
                      ? 'ECHOING'
                      : 'SHADOWING',
                  style: TextStyle(
                    color: inBreathEcho ? _p3BreathAccentColor : Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                  ),
                ),
                const Spacer(),
                // 카운터와 READING을 한 자리에서 교대시키면 정작 말하는 동안
                // 몇 번째 호흡인지가 사라진다. 둘을 나란히 두고 카운터는 늘
                // 남긴다.
                if (inBreathEcho && safeTotal > 0)
                  Text(
                    '${safeIndex + 1} / $safeTotal',
                    style: TextStyle(
                      color: userTurn ? userTurnAccent : Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: speaking
                      ? Container(
                          key: const ValueKey<String>('p3-speaking'),
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _p3BreathAccentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Text(
                            'READING',
                            style: TextStyle(
                              color: _p3BreathAccentColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(
                          key: ValueKey<String>('p3-no-status')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 🚫 본문은 크기도 굵기도 그대로다 — 읽는 중에 글자가 조금이라도
          //    움직이면 눈이 줄을 놓친다. 내 차례라는 신호는 색만 얹는다.
          //
          // 📜 [P3-READ-SCROLL] 문장 칸을 따로 스크롤시키지 않는다. 스크롤
          //    면이 둘이면 손가락이 안쪽에 갇혀 페이지가 안 밀리고, 아래 버튼에
          //    닿지 못한다. 읽는 진행은 페이지째 민다 — _p3ScrollReadingTo.
          Text(
            text.isEmpty ? 'Sentence unavailable' : text,
            style: TextStyle(
              color: userTurn
                  ? Color.lerp(Colors.white, userTurnAccent, 0.34)!
                      .withValues(alpha: 0.96)
                  : Colors.white.withValues(alpha: 0.90),
              fontSize: 16 * _fontScale,
              fontWeight: FontWeight.w400,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  /// 목소리는 모드와 같은 규칙으로 연다 — 한 바퀴가 끝난 뒤에도 바꿀 수 있고,
  /// 바꾸면 그 자리에서 다시 시작한다. 도는 중에만 잠근다.
  Widget _buildP3VoiceSelector() {
    final enabled = !_p3Busy;
    final List<String> voices = _p3VoiceChoices;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _p3ShadowingAccentColor.withValues(alpha: 0.34),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'VOICE',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(width: 12),
          // 남는 폭을 똑같이 나눠 갖는다. 모드에 따라 둘이 되었다 셋이 되는데,
          // 글자 폭에 맡기면 글꼴을 키운 기기에서 줄이 넘친다.
          for (int i = 0; i < voices.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _buildP3VoiceChip(
                id: voices[i],
                label: voices[i],
                enabled: enabled,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 지금 모드에서 고를 수 있는 목소리.
  List<String> get _p3VoiceChoices => _p3PracticeMode == P3PracticeMode.echoing
      ? _kP3EchoingVoices
      : _kP3ShadowingVoices;

  /// 모드를 바꾸면 목소리도 그 모드의 것으로 맞춘다. 남의 모드 목소리가 그대로
  /// 남으면 어느 칸도 켜지지 않은 채 그 목소리로 소리가 난다.
  void _coerceP3VoiceForMode() {
    final choices = _p3VoiceChoices;
    if (choices.contains(_p3Voice)) return;
    _p3Voice = choices.first;
    _p3FullPcm = null;
    _p3Segments = const <BreathSegment>[];
  }

  /// 🗣️ [P3-VOICE] 고를 목소리를 한 줄에 나란히 펼쳐 둔다.
  ///
  /// 풀다운은 열어 봐야 무엇이 있는지 알 수 있었는데 고를 것은 둘 또는 셋뿐이다.
  /// 아래 모드/문장 고르는 줄과 같은 생김새로 맞춰, 한 번 눌러 바꾼다.
  Widget _buildP3VoiceChip({
    required String id,
    required String label,
    required bool enabled,
  }) {
    final bool selected = _p3Voice == id;
    return InkWell(
      onTap: enabled ? () => unawaited(_selectP3Voice(id)) : null,
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? _p3ShadowingAccentColor.withValues(alpha: enabled ? 0.18 : 0.10)
              : Colors.white.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected
                ? _p3ShadowingAccentColor.withValues(
                    alpha: enabled ? 1.0 : 0.40)
                : Colors.white12,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: selected
                  ? (enabled ? Colors.white : Colors.white54)
                  : (enabled ? Colors.white70 : Colors.white24),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  /// 목소리를 바꾸면 만들어 둔 소리와 호흡 경계는 버린다 — 그 목소리로 뜬
  /// 파형이라 다음 재생이 어긋난다. 캐시는 목소리별로 나뉘어 있어 되돌아오면
  /// 다시 받지 않는다.
  ///
  /// 모드 고르기와 같은 규칙이다 — 화면부터 칠하고, 정지는 뒤에서 기다리고,
  /// 시작은 Start 버튼이 한다.
  Future<void> _selectP3Voice(String voice) async {
    if (voice == _p3Voice) return;
    setState(() {
      _p3Voice = voice;
      _p3FullPcm = null;
      _p3Segments = const <BreathSegment>[];
      _p3Stage = P3Stage.idle;
      _p3Error = null;
      _p3UserSpeaking = false;
    });
    await _stopP3Shadowing(resetSelection: true);
  }

  Widget _buildP3PracticeModePicker() {
    return Row(
      children: [
        for (final mode in P3PracticeMode.values) ...[
          Expanded(
            child: InkWell(
              onTap:
                  _p3Busy ? null : () => unawaited(_selectP3PracticeMode(mode)),
              borderRadius: BorderRadius.circular(11),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _p3PracticeMode == mode
                      ? _p3ShadowingAccentColor.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.035),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: _p3PracticeMode == mode
                        ? _p3ShadowingAccentColor
                        : Colors.white12,
                    width: _p3PracticeMode == mode ? 1.4 : 1,
                  ),
                ),
                child: Text(
                  mode == P3PracticeMode.echoing ? 'Echoing' : 'Shadowing',
                  style: TextStyle(
                    color:
                        _p3PracticeMode == mode ? Colors.white : Colors.white54,
                    fontSize: 13,
                    fontWeight: _p3PracticeMode == mode
                        ? FontWeight.bold
                        : FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          if (mode != P3PracticeMode.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }

  /// P3의 두 학습 문장. 단순 label만 보여 주면 문장을 바꾸고도
  /// 무엇을 골랐는지 알기 어려워 짧은 preview를 함께 보여 준다.
  Widget _buildP3VariantPicker({required bool showPreview}) {
    return Column(
      children: [
        for (final variant in SentenceVariant.values) ...[
          _buildP3VariantCard(variant, showPreview: showPreview),
          if (variant != SentenceVariant.values.last) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildP3VariantCard(
    SentenceVariant variant, {
    required bool showPreview,
  }) {
    final available = _p3VariantAvailable(variant);
    final building = variant == SentenceVariant.nativeEnglish
        ? _isBuildingNativeEnglish
        : _isBuildingMySpeech;
    final selected = _selectedVariant == variant;
    final sentence = _speechFor(variant).trim();
    // 아직 없는 문장이라고 잠그지 않는다 — 누르면 그 자리에서 만든다.
    final String? note = building
        ? '만드는 중…'
        : !available
            ? '눌러서 만들기'
            : (showPreview ? sentence : null);
    return InkWell(
      onTap: building || _p3VariantSwitching
          ? null
          : () => unawaited(_selectP3Variant(variant)),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
        decoration: BoxDecoration(
          color: selected
              ? _p3ShadowingAccentColor.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _p3ShadowingAccentColor : Colors.white12,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: building
                      ? Colors.white24
                      : (selected ? _p3ShadowingAccentColor : Colors.white38),
                  size: 17,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    _p3VariantLabel(variant),
                    style: TextStyle(
                      color: building
                          ? Colors.white38
                          : (selected ? Colors.white : Colors.white60),
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                ),
                if (building) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ],
            ),
            if (note != null) ...[
              const SizedBox(height: 6),
              Text(
                note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: available && !building
                      ? Colors.white54
                      : Colors.white38,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// gap 3단계. **API를 다시 부르지 않는다** — 같은 PCM을 다시 조립할 뿐이다.
  Widget _buildP3GapPicker() {
    return Row(
      children: [
        for (final gap in P3ShadowGap.values) ...[
          Expanded(
            child: InkWell(
              onTap: _p3Busy ? null : () => setState(() => _p3Gap = gap),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _p3Gap == gap
                      ? _p3ShadowingAccentColor.withValues(alpha: 0.20)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _p3Gap == gap
                        ? _p3ShadowingAccentColor
                        : Colors.white24,
                    width: _p3Gap == gap ? 1.4 : 1,
                  ),
                ),
                child: Text(
                  _kP3ShadowGapLabel[gap] ?? '',
                  style: TextStyle(
                    color: _p3Gap == gap
                        ? _p3ShadowingAccentColor
                        : Colors.white60,
                    fontSize: 12,
                    fontWeight:
                        _p3Gap == gap ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          if (gap != P3ShadowGap.values.last) const SizedBox(width: 6),
        ],
      ],
    );
  }

  /// AI / ECHO / SHADOW 각각 독립 재생. 자동 연속 재생은 하지 않는다.
  Widget _buildP3CompareRow() {
    return Row(
      children: [
        Expanded(
          child: _p3CompareButton(
              'AI', _p3FullPcm != null, () => unawaited(_playP3Original())),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _p3PracticeMode == P3PracticeMode.echoing
              ? _p3CompareButton('ECHO', _p3EchoPath != null,
                  () => unawaited(_playP3File(_p3EchoPath)))
              : _p3CompareButton('SHADOW', _p3ShadowPath != null,
                  () => unawaited(_playP3File(_p3ShadowPath))),
        ),
      ],
    );
  }

  Widget _p3CompareButton(String label, bool enabled, VoidCallback onTap) {
    final bool active = enabled && !_p3Busy;
    return InkWell(
      onTap: active ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        // 📐 최소 높이로 바꿔 라벨이 커져도 잘리지 않게 한다.
        constraints: const BoxConstraints(minHeight: 40),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: active ? 0.06 : 0.02),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? Colors.white24 : Colors.white10),
        ),
        child: Text(
          '▶ $label',
          style: TextStyle(
            color: active ? Colors.white70 : Colors.white24,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _p3PrimaryButton(String label, VoidCallback? onTap) => ConstrainedBox(
        // 📐 높이 고정 해제 — 배율이 크면 라벨이 버튼 밖으로 잘렸다.
        constraints: const BoxConstraints(minHeight: 48),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _p3ShadowingAccentColor,
            disabledBackgroundColor: Colors.white12,
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white38,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: onTap,
          child: Text(label,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ),
      );

  Widget _p3SecondaryButton(String label, VoidCallback? onTap) =>
      ConstrainedBox(
        // 📐 위와 같은 이유로 최소 높이만 둔다.
        constraints: const BoxConstraints(minHeight: 40),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            side: const BorderSide(color: Colors.white24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: onTap,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      );

  String _historyString(Map<String, dynamic>? data, String key) {
    return (data?[key] ?? '').toString().trim();
  }

  String _normalizeHistoryMode(String mode) {
    return mode.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
  }

  // 🏷️ [모드 별칭 해석표 — 표시명이 바뀔 때 여기만 한 줄씩 추가한다]
  //   저장 id는 절대 바꾸지 않는다. 이미 저장된 문서가 미분류로 떨어진다.
  //     free_talk   ← 표시명 Free Talk → Anyone → Circle Talk 로 변천
  //     roleplay    ← 표시명 Scenario Talk (room_name은 "Roleplay Mode" 유지)
  //   기존 조건은 지우지 말고 OR로 덧붙일 것. 지우면 그 시기 기록이 죽는다.
  String _inferHistoryMode(Map<String, dynamic>? data) {
    final mode = _normalizeHistoryMode(_historyString(data, 'mode'));
    if (mode.isNotEmpty) return mode;
    final room = _historyString(data, 'room_name');
    if (room == 'Clone Mode') return 'clone';
    if (room == 'Roleplay Mode') return 'roleplay';
    if (room == 'FreeTalk Mode' ||
        room == 'Free Talk Mode' ||
        room.startsWith('Circle Talk')) return 'free_talk';
    if (room == 'Anyone') return 'free_talk';
    if (room == 'Duo Mode' || room == 'Duo Connect Mode') return 'duo';
    return '';
  }

  /// 원문만 저장해 두고 타겟 문장은 **히스토리에서 처음 열 때 만드는** 모드들.
  ///
  /// Duo는 두 방식이 한 컬렉션에 섞인다. 만능 통역 줄은 대화 중에 이미
  /// `translated_text`가 채워져 있어 생성 대상에서 자동으로 빠지고(호출부가
  /// 비어 있는 줄만 고른다), 직접 대화 줄만 여기서 타겟을 얻는다.
  bool get _usesDeferredHistoryTargets {
    final mode = _inferHistoryMode(_cachedRoomData);
    return mode == 'free_talk' || mode == 'roleplay' || mode == 'duo';
  }

  /// 🧹 [DUO-PRACTICE-FILTER] 연습 재료에서 맞장구만 뺀다.
  ///
  /// **저장은 손대지 않는다.** 듀오는 말한 것을 그대로 다 남긴다(짧다고 버리면
  /// "네"·"왜?" 같은 진짜 대답까지 사라진다 — 2026-08-14에 31건 중 5건을 그렇게
  /// 잃었다). 다만 두 사람이 실제로 주고받은 말이라 맞장구가 그대로 줄이 되고,
  /// 그것을 따라 말하는 연습은 배울 것이 없다. 그래서 **고를 때만** 뺀다.
  ///
  /// 기준은 "줄 전체가 맞장구뿐인가"다. 다른 낱말이 하나라도 섞이면 남긴다 —
  /// "네, 그건 내일 할게요"는 맥락이 있는 말이다.
  static final RegExp _kBackchannelStrip = RegExp(r'[^\w\s가-힣]');
  static final RegExp _kBackchannelSplit = RegExp(r'\s+');
  static const Set<String> _kBackchannelTokens = <String>{
    '네',
    '넹',
    '넵',
    '예',
    '응',
    '어',
    '엉',
    '음',
    '아',
    '오',
    '와',
    '그래',
    '그래요',
    '그렇지',
    '맞아',
    '맞아요',
    '알겠어',
    '알겠어요',
    '알았어',
    'ok',
    'okay',
    'yeah',
    'yep',
    'yup',
    'yes',
    'no',
    'uh',
    'um',
    'hmm',
    'mhm',
    'right',
    'sure',
    'wow',
    'oh',
    'ah',
  };

  bool _isBackchannelOnly(String text) {
    final cleaned =
        text.toLowerCase().replaceAll(_kBackchannelStrip, ' ').trim();
    if (cleaned.isEmpty) return true;
    final tokens = cleaned.split(_kBackchannelSplit);
    // 세 낱말을 넘으면 맞장구만으로 보지 않는다. 볼 것도 없이 남긴다.
    if (tokens.length > 3) return false;
    return tokens.every(_kBackchannelTokens.contains);
  }

  String _historyModeKey(Map<String, dynamic>? data) {
    final inferred = _inferHistoryMode(data);
    if (inferred.isNotEmpty) return 'mode:$inferred';
    return 'room:${_normalizeHistoryMode(_historyString(data, 'room_name'))}';
  }

  Future<String> _fetchCloneNameForHistory(String cloneId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || cloneId.isEmpty) return '';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('clones')
          .doc(cloneId)
          .get();
      return (snap.data()?['name'] ?? '').toString().trim();
    } catch (e) {
      debugPrint('[historyLabels] clone fetch $e');
      return '';
    }
  }

  Future<Map<String, String>> _resolveHistoryExpandLabels(
      Map<String, dynamic>? data) async {
    final mode = _inferHistoryMode(data);
    if (mode == 'clone') {
      String partner = _historyString(data, 'partner_label');
      if (partner.isEmpty) partner = _historyString(data, 'clone_name');
      if (partner.isEmpty)
        partner = _historyString(data, 'expand_partner_name');
      if (partner.isEmpty) {
        partner =
            await _fetchCloneNameForHistory(_historyString(data, 'clone_id'));
      }
      if (partner.isEmpty) partner = 'the clone';
      String user = _historyString(data, 'user_label');
      if (user.isEmpty) user = _historyString(data, 'expand_user_label');
      if (user.isEmpty) user = 'the user';
      return {
        'mode': 'clone',
        'userLabel': user,
        'partnerLabel': partner,
        'partnerType': 'clone',
        'situation': '',
      };
    }
    if (mode == 'roleplay') {
      String partner = _historyString(data, 'partner_label');
      if (partner.isEmpty) partner = _historyString(data, 'ai_role');
      if (partner.isEmpty)
        partner = _historyString(data, 'expand_partner_name');
      if (partner.isEmpty) partner = 'the roleplay partner';
      String user = _historyString(data, 'user_label');
      if (user.isEmpty) user = _historyString(data, 'user_role');
      if (user.isEmpty) user = _historyString(data, 'expand_user_label');
      if (user.isEmpty) user = 'the user';
      final situation = _historyString(data, 'scenario_situation').isNotEmpty
          ? _historyString(data, 'scenario_situation')
          : _historyString(data, 'scenario_keyword');
      return {
        'mode': 'roleplay',
        'userLabel': user,
        'partnerLabel': partner,
        'partnerType': 'roleplay',
        'situation': situation,
      };
    }
    return {
      'mode': mode,
      'userLabel': 'User',
      'partnerLabel': 'AI',
      'partnerType': mode,
      'situation': '',
    };
  }

  /// 🗣️ [MY-SPEECH] 이 방이 MY SPEECH / NATIVE ENGLISH를 만들 수 있는 방인가.
  ///
  /// **세 대화 모드가 전부 만든다.** 사람이 실제로 나눈 대화가 있는 방이면
  /// 그 대화가 곧 재료다. 옛 Clone 방도 같은 모양이라 함께 연다.
  static const Set<String> _kSpeechPracticeModes = <String>{
    'duo',
    'free_talk',
    'roleplay',
    'clone',
  };

  bool _supportsSpeechPractice(String mode) =>
      _kSpeechPracticeModes.contains(_normalizeHistoryMode(mode));

  /// 저장 모양의 판. 규칙이 바뀌면 이 값을 올려 옛 결과를 다시 만들게 한다.
  static const String _kSpeechSchemaVersion = 'my_speech_v1';

  /// 저장된 MY SPEECH를 그대로 써도 되는가.
  ///
  /// 판이 다르면 옛 규칙(대화 전체 요약 한 문장)으로 만든 글이라 쓰지 않는다.
  /// 이름 있는 상대가 바뀐 방도 마찬가지다 — 그 이름으로 다시 만들어야 한다.
  bool _canReuseStoredMySpeech(
    Map<String, dynamic>? data,
    String mySpeech,
    Map<String, String> labels,
  ) {
    if (mySpeech.trim().isEmpty) return false;
    if (_historyString(data, 'speech_schema_version') !=
        _kSpeechSchemaVersion) {
      return false;
    }
    final mode = labels['mode'] ?? '';
    if (mode == 'clone' || mode == 'roleplay') {
      if (_historyString(data, 'speech_partner_type') != mode) return false;
      final savedPartner = _historyString(data, 'speech_partner_name');
      if (savedPartner.isNotEmpty && savedPartner != labels['partnerLabel']) {
        return false;
      }
    }
    return true;
  }

  /// 저장된 NATIVE ENGLISH를 그대로 써도 되는가.
  ///
  /// 이 카드는 언제나 영어다. 한글이 섞여 있으면 만들다 만 값이라 버린다.
  /// 두 카드가 같은 글자여도 버린다 — 견줄 것이 없으면 배울 것도 없다.
  bool _canReuseStoredNativeEnglish(String nativeEnglish, String mySpeech) {
    final text = nativeEnglish.trim();
    if (text.isEmpty) return false;
    if (_hangul.hasMatch(text)) return false;
    if (text == mySpeech.trim()) return false;
    return true;
  }

  /// messages 서브컬렉션 → My Speech가 읽을 대화록.
  ///
  /// **교정된 원어(`original_text`)를 쓴다.** 배울글은 번역을 한 번 거친 글이라
  /// 유저가 실제로 무슨 뜻으로 말했는지가 옅어진다. 뜻의 근거는 유저가 자기
  /// 말로 한 그 문장이어야 한다. 원어가 비어 있는 줄만 배울글로 받는다.
  ///
  /// HOST가 유저, SYSTEM이 상대다 — 세 모드가 같은 규칙으로 저장한다.
  List<SpeechTranscriptTurn> _speechTranscriptTurns() {
    final turns = <SpeechTranscriptTurn>[];
    for (final doc in _cachedDocs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      var text = _historyString(data, 'original_text');
      if (text.isEmpty) text = _historyString(data, 'translated_text');
      if (text.isEmpty) continue;
      final role = (data['role'] as String?) ?? 'HOST';
      turns.add(SpeechTranscriptTurn(isUser: role == 'HOST', text: text));
    }
    return turns;
  }

  /// 실패 종류를 유저 말로 옮긴다. 무엇을 다시 해야 하는지가 보여야 한다.
  String _speechFailureMessage(SpeechBuildFailure failure) {
    switch (failure) {
      case SpeechBuildFailure.apiKeyMissing:
        return 'API 키가 없어 만들 수 없습니다';
      case SpeechBuildFailure.emptyTranscript:
        return '내가 말한 내용이 없어 만들 수 없습니다';
      case SpeechBuildFailure.timeout:
        return '시간이 오래 걸려 멈췄습니다 — 다시 시도해 주세요';
      case SpeechBuildFailure.httpError:
      case SpeechBuildFailure.emptyReply:
      case SpeechBuildFailure.transportError:
      case SpeechBuildFailure.none:
        return '만들지 못했습니다 — 다시 시도해 주세요';
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // 🎓 [STUDY] 나란한 세 학습 경로
  //
  //   PRACTICE  — 역할을 바꿔 가며 대화를 다시 해 보는 자리. **끝이 없다.**
  //               몇 번이고 다시 들어온다.
  //   MY SPEECH — 대화 전체에서 유저가 실제로 표현한 것만 모은 한 벌.
  //   NATIVE ENGLISH — 그 My Speech를 미국식 사고 배열로 다시 세운 한 벌.
  //
  //   셋은 **서로의 전제가 아니다.** Practice를 끝내야 My Speech가 열리는
  //   식이면 "계속 반복하는 연습"과 "전체 발화 학습"이 한 줄에 꿰여, 둘 다
  //   제 성격을 잃는다. 어느 카드든 언제나 누를 수 있다.
  //
  //   다만 **생성 순서는 하나뿐이다** — Conversation → My Speech →
  //   Native English. NATIVE ENGLISH를 먼저 눌러도 My Speech가 먼저 선다.
  // ══════════════════════════════════════════════════════════════════

  /// 🔄 PRACTICE — 역할 교환 대화 연습. 재료는 진입할 때 이미 실려 있다.
  void _openPracticeStudy() {
    if (!_guardPaidStudy()) return;
    if (_tutorLines.isEmpty) {
      _showRoomEntryToast('연습할 대화가 없습니다');
      return;
    }
    _resumeHistoryFromUserAction();
    // 다시 들어올 때마다 새 회차다. 지난 회차의 녹음을 들고 시작하면 방금
    // 말한 것처럼 보인다. 재료(`_tutorLines`)는 그대로 두고 흔적만 지운다.
    for (final line in _tutorLines) {
      final path = line['user_record_path'] as String?;
      if (path != null && path.isNotEmpty) File(path).delete().ignore();
      line.remove('user_record_path');
      line.remove('ai_audio_bytes');
    }
    if (!mounted) return;
    setState(() {
      _phase = ShadowingPhase.turnPractice;
      currentIndex = 0;
      _isAutoRecording = false;
      _tutorAwaitingStart = true;
      _swapRoles = false;
      _tutorAiSpeaking = false;
      _tutorUserRecording = false;
      _tutorPlayingFullback = false;
      _showRetryHint = false;
    });
    // 역할 선택 말풍선 (2.8초 후 자동 사라짐)
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _showRoleSelectBubble());
  }

  /// 🗣️ MY SPEECH — 없으면 만들고, 그대로 훈련으로 들어간다.
  Future<void> _openMySpeechStudy() async {
    if (!_guardPaidStudy()) return;
    if (_isBuildingMySpeech || _isBuildingNativeEnglish) return;
    if (_mySpeech.trim().isEmpty && !await _ensureMySpeech()) return;
    if (!mounted) return;
    _openSpeechStage(SentenceVariant.mySpeech);
  }

  /// 🇺🇸 NATIVE ENGLISH — My Speech가 없으면 그것부터 만든 뒤 이어서 만든다.
  Future<void> _openNativeEnglishStudy() async {
    if (!_guardPaidStudy()) return;
    if (_isBuildingMySpeech || _isBuildingNativeEnglish) return;
    if (_nativeEnglish.trim().isEmpty) {
      if (_mySpeech.trim().isEmpty && !await _ensureMySpeech()) return;
      if (!mounted) return;
      if (!await _ensureNativeEnglish()) return;
    }
    if (!mounted) return;
    _openSpeechStage(SentenceVariant.nativeEnglish);
  }

  /// 대화 전체에서 MY SPEECH 한 벌을 확보한다. 이미 있으면 그대로 쓴다.
  ///
  /// 실패하면 **false다.** 상대방 말을 섞거나 아무 문장이나 만들어 채우지
  /// 않는다. 이유는 카드에 그대로 적힌다.
  Future<bool> _ensureMySpeech() async {
    if (!_paidStudySilentlyAllowed('my_speech')) return false;
    if (_isBuildingMySpeech) return false;
    if (mounted) {
      setState(() {
        _isBuildingMySpeech = true;
        _mySpeechError = null;
      });
    }
    try {
      audioPlayer.stop();
      _stopAutoVADRecording();

      Map<String, dynamic>? roomData = _cachedRoomData;
      try {
        final snap = await widget.historyDoc.get();
        final fresh = snap.data() as Map<String, dynamic>?;
        if (fresh != null) {
          roomData = fresh;
          _cachedRoomData = fresh;
        }
      } catch (e) {
        debugPrint('[MY-SPEECH] room fetch $e');
      }
      if (!mounted) return false;

      final mode = _inferHistoryMode(roomData);
      _cachedRoomMode = mode;
      if (!_supportsSpeechPractice(mode)) {
        setState(() => _mySpeechError = '이 방에서는 만들 수 없습니다');
        return false;
      }

      final labels = await _resolveHistoryExpandLabels(roomData);
      if (!mounted) return false;

      var mySpeech = _historyString(roomData, 'my_speech');
      if (_canReuseStoredMySpeech(roomData, mySpeech, labels)) {
        final stored = _historyString(roomData, 'native_english');
        setState(() {
          _mySpeech = mySpeech;
          _nativeEnglish =
              _canReuseStoredNativeEnglish(stored, mySpeech) ? stored : '';
        });
        return true;
      }

      final result = await MySpeechBuilder.build(
        apiKey: _apiKey,
        turns: _speechTranscriptTurns(),
        targetLang: _sessionTargetLangName(),
        userLabel: labels['userLabel'] ?? '',
        partnerLabel: labels['partnerLabel'] ?? '',
        situation: labels['situation'] ?? '',
        onLog: (tag, message) => debugPrint('$tag $message'),
      );
      if (!mounted) return false;
      if (!result.isUsable) {
        setState(() => _mySpeechError = _speechFailureMessage(result.failure));
        return false;
      }
      mySpeech = result.text;
      setState(() {
        _mySpeech = mySpeech;
        // 새로 만든 My Speech에는 짝이 없다. 옛 Native English를 그대로
        // 걸어 두면 서로 다른 두 생각이 한 쌍인 척한다.
        _nativeEnglish = '';
        _nativeEnglishError = null;
        _practicingNativeEnglish = false;
        _nativeEnglishUnits = <String>[];
        _nativeEnglishUnitIdx = -1;
      });
      try {
        await widget.historyDoc.update(<String, dynamic>{
          'my_speech': mySpeech,
          'native_english': FieldValue.delete(),
          'speech_schema_version': _kSpeechSchemaVersion,
          'speech_generated_at': FieldValue.serverTimestamp(),
          'speech_user_label': labels['userLabel'],
          'speech_partner_name': labels['partnerLabel'],
          'speech_partner_type': labels['partnerType'],
          'has_practice': true,
        });
      } catch (e) {
        debugPrint('[MY-SPEECH] cache write $e');
      }
      return true;
    } catch (e) {
      debugPrint('[MY-SPEECH] $e');
      if (mounted) setState(() => _mySpeechError = '오류: $e');
      return false;
    } finally {
      if (mounted) setState(() => _isBuildingMySpeech = false);
    }
  }

  /// 🇺🇸 [NATIVE-ENGLISH] **입력은 언제나 My Speech다.**
  ///
  /// 대화 원문을 직접 읽지 않는다 — 그러면 상대방이 한 말이 섞여 들어올 길이
  /// 열린다. 실패하면 false이고, 그 자리는 **빈 채로 둔다.** My Speech를
  /// 복사해 채우면 두 카드가 같은 글자가 되어 견줄 것이 사라진다.
  Future<bool> _ensureNativeEnglish() async {
    if (!_paidStudySilentlyAllowed('native_english')) return false;
    final source = _mySpeech.trim();
    if (source.isEmpty || _isBuildingNativeEnglish) return false;
    if (mounted) {
      setState(() {
        _isBuildingNativeEnglish = true;
        _nativeEnglishError = null;
      });
    }
    try {
      final result = await NativeEnglishSpeechBuilder.build(
        apiKey: _apiKey,
        mySpeech: source,
        onLog: (tag, message) => debugPrint('$tag $message'),
      );
      if (!mounted) return false;
      if (!result.isUsable) {
        setState(
            () => _nativeEnglishError = _speechFailureMessage(result.failure));
        return false;
      }
      final text = result.text;
      setState(() {
        _nativeEnglish = text;
        _nativeEnglishError = null;
        _nativeEnglishUnits = <String>[];
        _nativeEnglishUnitIdx = -1;
      });
      try {
        await widget.historyDoc.update(<String, dynamic>{
          'native_english': text,
          'speech_schema_version': _kSpeechSchemaVersion,
          'has_practice': true,
        });
      } catch (e) {
        debugPrint('[NATIVE-ENGLISH] cache write $e');
      }
      return true;
    } catch (e) {
      debugPrint('[NATIVE-ENGLISH] $e');
      if (mounted) setState(() => _nativeEnglishError = '오류: $e');
      return false;
    } finally {
      if (mounted) setState(() => _isBuildingNativeEnglish = false);
    }
  }

  /// 훈련 중 X는 방을 닫지 않고 **학습 경로 고르는 자리로** 돌아간다.
  /// 어느 경로에서 나가든 같은 자리로 돌아와야 셋이 나란해 보인다.
  void _backToStudySelect() {
    _stopTutorPlayback();
    _stopAutoVADRecording();
    _utteranceSafetyTimer?.cancel();
    _stopDeepgramListening();
    unawaited(_stopP3Shadowing(resetSelection: true));
    _echoingOverlayTimer?.cancel();
    audioPlayer.stop();
    if (!mounted) return;
    setState(() {
      _phase = ShadowingPhase.studySelect;
      _isListening = false;
      _isPlayingFullUser = false;
      _isPlayingFullAI = false;
      _isReplayMode = false;
      _aiChunkPlaying = false;
      _aiChunkLoading = false;
      _currentChunkIdx = 0;
    });
  }

  /// MY SPEECH / NATIVE ENGLISH 카드 하나를 골라 훈련으로 들어간다.
  void _openSpeechStage(SentenceVariant variant) {
    _selectedVariant = variant;
    _goToChunkPractice();
  }

  /// 고른 문장으로 Speaking Practice(에코잉·쉐도잉)를 연다.
  ///
  /// ⚠️ 여기서 `_selectedVariant`를 손대지 않는다. 어느 카드를 눌렀는지는
  ///    [_openSpeechStage]가 이미 정해 두었고, 여기서 다시 덮으면 NATIVE
  ///    ENGLISH를 눌러도 MY SPEECH가 열린다.
  void _goToChunkPractice() {
    if (!mounted) return;
    _silenceTimer?.cancel();
    try {
      appAudioRecorder.stop();
    } catch (_) {}
    audioPlayer.stop();
    _echoingOverlayTimer?.cancel();
    unawaited(_stopP3Shadowing(resetSelection: true));
    if (mounted) {
      setState(() {
        _isAutoRecording = false;
        _showRetryHint = false;
        _currentChunkIdx = -1;
        _phase = ShadowingPhase.chunkPractice;
        // 🎤 [P3-SPEAK] 새 세션으로 연다. 이전 녹음은 남기지 않는다 —
        //   AI 원본 TTS 캐시는 그대로 재사용된다.
        _p3Stage = P3Stage.idle;
        _p3Error = null;
        _p3UserSpeaking = false;
      });
      unawaited(_stopP3Shadowing(resetSelection: true));
    }
  }

  /// 🏫 [SR] 공부방 목록으로 가는 알약. 설정 페이지·대화방에 단 것과 같다.
  ///
  /// 자리를 내주고 간다(`pushReplacement`) — 이 방은 열려 있는 동안 과금이
  /// 돌아서, 방이 정리되어야 차감이 멈춘다.
  Widget _buildStudyRoomPill() {
    return Tooltip(
      message: '공부방 (Study Room)',
      child: GestureDetector(
        onTap: () => context.pushReplacementNamed('ChatHistory'),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: const Text(
            "SR",
            maxLines: 1,
            style: TextStyle(
              color: Color(0xFFE7E9EE),
              fontWeight: FontWeight.w600,
              fontSize: 13,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

// 📦 [Box 24: API Brain - 쉐도잉 포맷팅용 HTTP 통신 정적 클래스]
class ShadowingBrain {
  static final http.Client client = http.Client();

  static Future<String> formatForSlowRhythm(
      String apiKey, String rawText) async {
    try {
      Uri uri = Uri.parse('https://api.openai.com/v1/chat/completions');
      String systemPrompt = '''Role: 너는 영어 학습 앱의 '쉐도잉 텍스트 에디터'이다.
사용자가 입력한 영문을 OpenAI tts-1 모델이 읽기에 가장 적합한 '아주 느리고 리듬감 있는 텍스트'로 재구성한다.
Core Objective:
인위적인 속도 조절(speed) 없이, 오직 텍스트 포맷팅만으로 발화 속도를 늦추고 또박또박 끊어 읽게 만든다.
Formatting Rules (Strict):
1. Micro-Chunking: 문장을 2~3단어 단위의 아주 짧은 의미 군으로 잘게 쪼개고, 그 사이에 무조건 쉼표(,)를 삽입하라. 의미 경계가 강한 곳(전치사구, 접속사, 부사절 시작 등)에는 쉼표를 중첩(,, )하여 더 깊은 휴지를 만들어라.
2. Expanding Contractions: 모든 축약어(I'm, don't, can't 등)는 완전한 형태(I am, do not, cannot 등)로 풀어서 써라.
숫자도 스펠링으로 풀어 써라.
3. Deep Pause Markers: 쉼표(,) 뒤에는 반드시 두 번의 줄바꿈(\\n\\n)을 넣어 TTS가 물리적으로 길게 쉬도록 만들어라. 특히 강조할 경계에는 쉼표 뒤에 마침표를 추가(,. )하거나 쉼표를 중첩(,, )한 뒤 줄바꿈(\\n\\n)을 삽입하여 TTS가 가장 깊게 쉬어가도록 유도하라.
예시 패턴: "I went,. \\n\\nto the store,, \\n\\nbecause I needed,. \\n\\nsome time, \\n\\nto think."
4. Neutral Tone: 대문자 강조나 느낌표(!)를 쓰지 말고, 오직 쉼표(,)와 마침표(.)만 사용하여 감정 없이 평탄하고 또박또박하게(deliberate and slow) 읽히도록 유도하라.
5. Output ONLY the formatted text. Do not add any extra explanations.''';

      var res = await client
          .post(uri,
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json; charset=utf-8'
              },
              body: jsonEncode({
                'model': 'gpt-4o-mini',
                'temperature': 0.1,
                'messages': [
                  {'role': 'system', 'content': systemPrompt},
                  {'role': 'user', 'content': rawText}
                ]
              }))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        var data = jsonDecode(utf8.decode(res.bodyBytes));
        return data['choices'][0]['message']['content'].toString().trim();
      }
    } catch (e) {
      debugPrint("[ShadowingBrain] $e");
    }
    return rawText;
  }
}

// 📦 [Box 24-B: 디스크 TTS 캐시 헬퍼]
class _AudioDiskCache {
  static Future<File> _fileFor(String historyId, String key) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/tts_cache/$historyId');
    await folder.create(recursive: true);
    return File('${folder.path}/$key');
  }

  static Future<Uint8List?> read(String historyId, String key) async {
    if (historyId.isEmpty) return null;
    try {
      final file = await _fileFor(historyId, key);
      if (await file.exists()) return await file.readAsBytes();
    } catch (e) {
      debugPrint('[_AudioDiskCache.read] $e');
    }
    return null;
  }

  static Future<void> write(
      String historyId, String key, Uint8List bytes) async {
    if (historyId.isEmpty) return;
    try {
      final file = await _fileFor(historyId, key);
      await file.writeAsBytes(bytes);
    } catch (e) {
      debugPrint('[_AudioDiskCache.write] $e');
    }
  }

  /// 방을 지울 때 그 방의 오디오 폴더도 같이 지운다. 방이 사라지면 이
  /// historyId는 다시 매칭될 일이 없어, 남겨두면 회수 불가능한 고아가 된다.
  static Future<void> clearRoom(String historyId) async {
    if (historyId.isEmpty) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/tts_cache/$historyId');
      if (await folder.exists()) await folder.delete(recursive: true);
    } catch (e) {
      debugPrint('[_AudioDiskCache.clearRoom] $e');
    }
  }
}

// 📦 [Box 25: enum + PracticeChunk 모델 클래스]
enum ShadowingPhase {
  idle,

  /// 학습 경로 셋을 나란히 고르는 자리. History Study의 첫 화면이다.
  studySelect,

  /// PRACTICE — 역할 교환 대화 연습.
  turnPractice,

  /// MY SPEECH · NATIVE ENGLISH 훈련(Echoing / Shadowing).
  /// 이름은 옛것이다 — 지금 이 자리는 청크를 쓰지 않는다.
  chunkPractice,
}

/// 두 학습 문장. 화면 이름은 MY SPEECH / NATIVE ENGLISH다.
enum SentenceVariant { mySpeech, nativeEnglish }

enum P3PracticeMode { echoing, shadowing }

/// 🎤 [P3-SPEAK] 말하기 연습의 단계. bool 조합으로 단계를 짐작하지 않는다.
enum P3Stage {
  idle,
  preparing,
  breathListen,
  breathEcho,
  fullEchoListen,
  fullEchoRecord,
  fullShadowRecord,
  compare,
}

/// 🎤 [P3-SPEAK] 쉐도잉 여유. **속도가 아니라 호흡 사이 공간이다.**
enum P3ShadowGap { tight, normal, relaxed }

class PracticeChunk {
  final String text;
  final String? korean; // 🆕 [KO-FRAG] 영어어순 직독 한국어 조각 (없으면 null)
  Uint8List? aiAudio;
  String? userRecordPath;
  bool isDone;

  PracticeChunk({
    required this.text,
    this.korean,
    this.aiAudio,
    this.userRecordPath,
    this.isDone = false,
  });
}

class _LangIconPainter extends CustomPainter {
  /// 0=영어+한글, 1=영어만, 2=한글만
  final int mode;
  const _LangIconPainter({required this.mode});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);

    canvas
        .clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: r)));

    // ── 배경 ──
    // mode 0: 파란 투톤, mode 1: 하단 파란+상단 어둡게, mode 2: 상단 파란+하단 어둡게
    if (mode == 0) {
      // 밝은 파란 전체
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()..color = const Color(0xFF1E7DB5));
      // 짙은 파란 삼각형 (하단 우측)
      canvas.drawPath(
        Path()
          ..moveTo(size.width * 0.05, size.height)
          ..lineTo(size.width, size.height * 0.05)
          ..lineTo(size.width, size.height)
          ..close(),
        Paint()..color = const Color(0xFF0B4870),
      );
    } else if (mode == 1) {
      // 영어만: 상단(원어) 어둡게, 하단(타겟) 파란
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()..color = const Color(0xFF2A2A2A));
      canvas.drawPath(
        Path()
          ..moveTo(size.width * 0.05, size.height)
          ..lineTo(size.width, size.height * 0.05)
          ..lineTo(size.width, size.height)
          ..close(),
        Paint()..color = const Color(0xFF0B4870),
      );
    } else {
      // 한글만: 상단(원어) 파란, 하단(타겟) 어둡게
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()..color = const Color(0xFF1E7DB5));
      canvas.drawPath(
        Path()
          ..moveTo(size.width * 0.05, size.height)
          ..lineTo(size.width, size.height * 0.05)
          ..lineTo(size.width, size.height)
          ..close(),
        Paint()..color = const Color(0xFF2A2A2A),
      );
    }

    // ── 대각선 ──
    canvas.drawLine(
      Offset(size.width * 0.04, size.height * 0.96),
      Offset(size.width * 0.96, size.height * 0.04),
      Paint()
        ..color = const Color(0xFFD4AF37)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // ── 원형 테두리 ──
    canvas.drawCircle(
      center,
      r - 1.5,
      Paint()
        ..color = const Color(0xFFD4AF37)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // ── 상단 좌측 "T" (원어/한글) ──
    final bool origActive = (mode == 0 || mode == 2);
    _drawText(canvas, 'T', Offset(size.width * 0.09, size.height * 0.06),
        size.width * 0.34, origActive ? Colors.white : const Color(0x44FFFFFF));

    // ── 상단 우측: 빨간 점(활성) 또는 X(비활성) ──
    if (origActive) {
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
      // 원어 숨김 X
      final xPaint = Paint()
        ..color = Colors.redAccent.withValues(alpha: 0.65)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(size.width * 0.53, size.height * 0.11),
          Offset(size.width * 0.74, size.height * 0.32), xPaint);
      canvas.drawLine(Offset(size.width * 0.74, size.height * 0.11),
          Offset(size.width * 0.53, size.height * 0.32), xPaint);
    }

    // ── 하단 우측 "T" (타겟/영어) ──
    final bool targetActive = (mode == 0 || mode == 1);
    _drawText(
        canvas,
        'T',
        Offset(size.width * 0.55, size.height * 0.58),
        size.width * 0.34,
        targetActive ? Colors.white : const Color(0x44FFFFFF));

    // ── 하단 좌측: 타겟 비활성일 때 X 표시 ──
    if (!targetActive) {
      final xPaint = Paint()
        ..color = Colors.redAccent.withValues(alpha: 0.65)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(size.width * 0.27, size.height * 0.65),
          Offset(size.width * 0.48, size.height * 0.86), xPaint);
      canvas.drawLine(Offset(size.width * 0.48, size.height * 0.65),
          Offset(size.width * 0.27, size.height * 0.86), xPaint);
    }
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
  bool shouldRepaint(_LangIconPainter old) => old.mode != mode;
}
