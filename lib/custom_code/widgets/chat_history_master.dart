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
import 'package:flutter/services.dart';
import 'routine_mode_roleplay.dart' show TtsCache;
import '/custom_code/actions/billing_ticker.dart';
import '/custom_code/actions/billing_idle_mixin.dart';
import '/custom_code/services/audio_silence_analyzer.dart';
import '/custom_code/services/breath_echoing_engine.dart';
import '/custom_code/services/breath_segment.dart';
import '/custom_code/services/p2_voice_styles.dart';
import '/custom_code/services/sentence_morph.dart';
import '/custom_code/services/p2_chunk_mapping.dart';
import '/custom_code/services/pcm_audio_utils.dart'
    show kStealthVoxSttSampleRate, pcm16DurationMs, pcm16ToWav;

// ════════════════════════════════════════════════════════════════════
// 🌬️ [P2-BREATH] Breath Echoing이 쓰는 값. **한곳에만 둔다.**
// ════════════════════════════════════════════════════════════════════

/// P3가 처음 열릴 때의 보이스. 에코잉이 기본 모드라 그 목록의 첫 칸을 든다 —
/// 목록에 없는 값을 들고 열면 어느 칸도 켜지지 않은 채 소리만 난다.
const String _kBreathVoice = 'coral';

/// Breath TTS는 Lab과 **같은 Smooth Jazz 정의**를 쓴다. 복사본을 만들지
/// 않는다 — 갈라지면 Lab에서 고른 소리와 실사용 소리가 달라진다.
P2VoiceStyle get _kBreathStyle => kP2VoiceStyles.firstWhere(
      (s) => s.id == kP2BreathTestStyleId,
    );

/// 🎵 P3가 쓰는 낭독 패턴. **P2 Breath와 다른 한 벌이다** — P2는 Smooth Jazz
/// 그대로 두고, P3는 모드마다 갈린다.
///   · 에코잉  — Sing-Song Flow (호흡마다 끊어 따라 읽기)
///   · 쉐도잉  — Story Melody  (이야기하듯 이어 읽어 얹어 말하기)
/// id가 다르므로 캐시 칸도 따로 선다. 모드를 오가도 이미 받은 소리는 남는다.
P2VoiceStyle _p3StyleFor(P3PracticeMode mode) =>
    mode == P3PracticeMode.echoing ? kP3SpeakingStyle : kP3ShadowingStyle;

/// P3 전용 캐시 칸. 스타일 id가 달라 P2가 만들어 둔 소리와도, 두 모드끼리도
/// 섞이지 않는다.
String _p3CacheNamespaceFor(P3PracticeMode mode, String voice) =>
    'p2_wav_${_historyPracticeTtsModel}_${_p3StyleFor(mode).id}'
    '_${kP2StyleInstructionVersion}_$voice';

/// 실사용 Breath PCM 캐시. Lab(`p2lab_wav_`)과 접두어가 달라 섞이지 않는다.
/// Pattern 시스템이 들어오면 `style_smooth_jazz` 자리에 pattern id가 들어가고,
/// 같은 instruction·voice면 **캐시가 그대로 재사용된다**(재생성 0회).
String _breathCacheNamespace(String voice) =>
    'p2_wav_${_historyPracticeTtsModel}_${_kBreathStyle.id}'
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

/// 🪜 [P2-LADDER] P2 낭독 지시. 실장님 지정 문구다(2026-08-18).
///
/// 의미단위로 쪼개 읽던 예전 지시(`_meaningUnitCore` + `_learningUnitDelivery`)를
/// 걷어냈다 — P2가 대화 한 턴이 아니라 **한 문장이 계단마다 길어지는 것**을
/// 다루는 자리로 바뀌었고, 덩어리마다 끊어 읽으면 자란 자리가 아니라 끊긴
/// 자리만 들린다. 두 지시는 P3가 그대로 쓰므로 남겨 둔다.

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
      display =
          head.replaceAll(' Mode', '').replaceAll('Step Expand', 'Step.Ex');
    }
    return suffix.isEmpty ? display : '$display · $suffix';
  }

  bool _isEnteringPractice = false;
  bool _isOpeningAdjacentHistory = false;
  int _openingHistoryOffset = 0;
  Map<String, dynamic>? _cachedRoomData;

  // 📦 [Box 4: 상태 변수 - Shadowing 상태 머신]
  ShadowingPhase _phase = ShadowingPhase.idle;
  SentenceVariant _selectedVariant = SentenceVariant.expanded;
  String _expandedSentence = "";
  String _polishedSentence = "";
  // 완성문장에 한글이 남아 있으면 아직 영어가 안 만들어진 것이다.
  // 8019줄 [HANGUL-GUARD]가 Tutor 경로에서 쓰는 것과 같은 판정이다.
  static final RegExp _stepExpandHangul = RegExp(r'[가-힣ᄀ-ᇿ㄰-㆏]');
  bool _polishedLoadDone = false;
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
  int _tutorCurrentIdx = -1;
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

  // P2 샤도잉 시작 팝업 오버레이

  // 📦 [Box 4-B: 양방향 턴제 연습 엔진 상태]
  int currentIndex = 0;

  bool _isAutoRecording = false;
  Timer? _silenceTimer;
  int _silenceCounter = 0;
  bool _hasSpoken = false;

  // 📦 [Box 4-C: Step Expand Practice 1 & 2 상태]
  bool _isStepExpandRoom = false;
  List<Map<String, dynamic>> _stepExpandTurns = [];
  bool _isPreparingStepP3 = false;
  String? _stepP3PreparationError;
  int _stepP3PreparationGeneration = 0;
  // P1/P2 retry hint visibility
  bool _showRetryHint = false;
  int _turnPracticeRetryCount = 0;

  // [P2-MEANING-SHADOW] 의미단위 학습 음성을 동시에 따라 읽는 상태.
  Timer? _shadowHighlightTimer;
  Timer? _shadowAdvanceTimer;
  double _shadowSpeed = 1.0; // 오디오 실패 시 하이라이트 fallback용 고정 속도.
  /// P2 계단은 보이스를 번갈아 읽는다 — 첫 대사 cedar, 다음 marin, 그 다음
  /// cedar… 같은 목소리가 이어지면 계단이 자란 것인지 같은 문장을 다시 듣는
  /// 것인지 귀로 구분되지 않는다. 화면 선택은 없애고 순서만 남긴다.
  String _p2VoiceForLine(int lineIdx) => lineIdx.isEven ? 'cedar' : 'marin';
  // ── 🔤 [P2-MORPH] ───────────────────────────────────────────────
  /// 소리를 받아 오는 중. 이 동안에도 과금은 살아 있어야 한다.
  bool _morphPreparing = false;

  /// 전체 문장을 읽는 중.
  bool _morphPlaying = false;

  /// 전체 문장 PCM의 재생 위치를 단어 비율로 청크에 대응한 시각 인덱스.
  /// 실제 word timestamp가 아니므로 ±1~2단어 오차를 허용한다.
  int _p2ActiveChunkIndex = -1;
  int _p2MorphDurationMs = 0;

  // [P2-SHADOW-REC] User-line audio captured for Play all. No scoring/STT.
  bool _shadowRecording = false;
  // [P2-SHADOW-AI] AI voice read-along: highlight follows audio playback position.
  AudioPlayer? _shadowAiPlayer;
  StreamSubscription<Duration>? _shadowPosSub;
  StreamSubscription<Duration>? _shadowDurSub;
  StreamSubscription<void>? _shadowCompleteSub;

  // 🆕 [P2-INDICATOR] AI 청크 발화 중 여부 (인디케이터 빛남용)
  bool _aiChunkPlaying = false;
  // AI TTS 로딩 중 (재생 전 Thinking... 표시용)
  bool _aiChunkLoading = false;
  // 🆕 [P2-INDICATOR] AI 다시 듣기 모드 (true이면 끝나도 마이크 자동 ON 안 함)
  bool _isReplayMode = false;

  // P3 한 문장 의미단위 쉐도잉 상태.
  final ScrollController _p3SentenceScrollController = ScrollController();

  /// 📜 [P3-READ-SCROLL] 손으로 스크롤한 뒤에는 자동으로 밀지 않는다. 읽는
  /// 자리를 직접 잡은 사람과 싸우면 안 된다. 다음 Start에서 다시 열린다.
  bool _p3AutoScrollBlocked = false;
  StreamSubscription<Duration>? _p3ShadowPositionSub;
  StreamSubscription<Duration>? _p3ShadowDurationSub;

  // 🆕 [CHUNK-PRACTICE] 의미단위 연습 모드 상태
  bool _practicingPolished = false; // false = expanded, true = polished
  bool _isBuildingExpand = false; // 🆕 [EXPAND-FROM-CHAT] 확장문장 생성 중 플래그
  String _cachedRoomMode = ''; // 🔧 [FREE-TALK-BTN] 버튼 표시 조건용 mode 캐시
  bool _isPlayingFullAI = false; // 전체 AI 듣기 진행 중
  Timer? _polishedRevealTimer;
  final ScrollController _chunkScrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  // 🆕 [BOX-34-SCROLL] Practice 화면 스크롤 컨트롤러 & 아이템 키
  final ScrollController _practiceScrollController = ScrollController();
  final Map<int, GlobalKey> _practiceItemKeys = {};
  final Map<int, GlobalKey> _polishedItemKeys = {};

  // 🆕 [POLISHED-UNITS] 세련문장 2-3 의미단위 콜앤리스폰 연습
  List<String> _polishedUnits = [];
  int _polishedUnitIdx = -1;
  bool _polishedUnitAIPlaying = false;

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
        _polishedUnitAIPlaying ||
        // 🔤 [P2-MORPH] 소리를 받는 동안과 읽는 동안. 마이크가 없어 판정이
        //   단순해졌다 — 이 둘만 보면 된다.
        _morphPreparing ||
        _morphPlaying ||
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

  Widget _buildIdleOverlay() => const SizedBox.shrink();
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
    // 💰 [BILLING-IDLE] 입장 즉시 과금 + 60초 유휴 감시. 규칙은 공용이다.
    startBillingRoom();
    BillingTicker.instance.balanceExhausted.addListener(_onBalanceExhausted);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) resetBillingIdle();
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
    _polishedRevealTimer?.cancel();
    _shadowHighlightTimer?.cancel(); // [P2-SHADOW]
    _shadowAdvanceTimer?.cancel(); // [P2-SHADOW]
    _stopShadowAiPlayback(); // [P2-SHADOW-AI]
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
    _p3SentenceScrollController.dispose();
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
    if (_appIsRecording || _shadowRecording || _p3Recording) {
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
        _scheduleMissingTargetGeneration(_cachedDocs);
      }
    } catch (e) {
      debugPrint("[fetchRoomData] $e");
    }
    if (mounted) setState(() => isLoadingRoom = false);
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

  void _scheduleMissingTargetGeneration(List<DocumentSnapshot> docs) {
    if (!_usesDeferredHistoryTargets || docs.isEmpty) return;
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
      final original = (data['original_text'] ?? '').toString().trim();
      final translated = (data['translated_text'] ?? '').toString().trim();
      if (original.isEmpty || translated.isNotEmpty) continue;
      unawaited(_generateAndCacheHistoryTarget(
        doc.reference,
        original,
        _sourceLangForMessage(data),
        expandedText: (data['expanded_sentence'] ?? '').toString().trim(),
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
  String _sourceLangForMessage(Map<String, dynamic>? data) {
    final perMessage = (data?['source_lang'] ?? '').toString().trim();
    if (perMessage.isNotEmpty) return perMessage;
    final session = (_sessionNativeLang ?? '').trim();
    return session.isNotEmpty ? session : 'Korean';
  }

  Future<bool> _generateAndCacheHistoryTarget(
    DocumentReference messageRef,
    String originalText,
    String sourceLanguage, {
    // 🌱 [EXPAND-LADDER] Step Expand 유저 줄이 들고 있는 누적 문장(원어).
    //   같은 왕복에서 함께 번역한다 — 줄마다 API를 한 번 더 태우지 않는다.
    String expandedText = '',
  }) {
    final existing = _targetTranslationInFlight[messageRef.id];
    if (existing != null) return existing;
    final future = _performHistoryTargetGeneration(
        messageRef, originalText, sourceLanguage,
        expandedText: expandedText);
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
      expandedText: (data['expanded_sentence'] ?? '').toString().trim(),
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
    String sourceLanguage, {
    String expandedText = '',
  }) async {
    final source = originalText.trim();
    final expandedSource = expandedText.trim();
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
      // 🌱 [EXPAND-LADDER] 이 턴까지 자란 문장의 배울글. 같은 왕복에서 받는다.
      //   같은 언어면 번역할 게 없어 원어가 곧 배울글이고, 다른 언어인데 모델이
      //   안 돌려주면 **빈 채로 둔다** — 원어를 그 자리에 넣으면 P2 한복판에
      //   한국어 줄이 하나 섞인다.
      String expandedTargetText = sameLanguage ? expandedSource : '';
      List<P2Chunk> p2Chunks = fallbackP2Chunks(expandedTargetText);
      final String context = _historyRepairContext(messageRef);
      final String lineBlock = expandedSource.isEmpty
          ? 'LINE: $source'
          : 'LINE: $source\n\nGROWING SENTENCE: $expandedSource';
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
                'model': 'gpt-4o-mini',
                'temperature': 0.0,
                // 누적 문장이 실리면 마지막 턴은 한 줄이 아니라 다섯 턴이
                // 합쳐진 문장이다. 220으로는 번역이 중간에서 잘린다.
                'max_tokens': expandedSource.isEmpty ? 220 : 520,
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
- If nothing is clearly wrong, return the line EXACTLY as given.

TRANSLATION — natural spoken $targetLanguage of the corrected line. Preserve the speaker viewpoint, meaning, tone, and relationship.

WHO THE LINE IS ABOUT — read this before you translate:
- $sourceName leaves out the subject and the object whenever they are already understood. $targetLanguage cannot. You must supply them, and SURROUNDING CONVERSATION is where they are.
- Whoever the conversation is currently about stays the subject until the speaker moves to someone else. A line with no subject continues to be about that person — NOT about the speaker.
- Never fall back on "I" just because the subject is missing. Use "I" only when the line is genuinely about the speaker.
- The people in this conversation are introduced in its opening lines. Settle who they are there first, then keep them straight through every line.
- Keep each person's relationship to the speaker exactly as stated. Do not promote, demote, or merge them, and do not invent one who was never mentioned.
${expandedSource.isEmpty ? '' : '''
GROWING SENTENCE — the speaker is building ONE sentence across several turns, and GROWING SENTENCE is how far it has grown by this line. Translate it into natural spoken $targetLanguage as ONE sentence. Keep it a single flowing sentence — never a comma-separated list of facts. Add nothing that is not in it. The subject rules above apply to every clause in it.

P2 CHUNK MAPPING — return a "chunks" JSON array for the translated growing sentence. Split the translated "expanded" sentence into meaningful phrases or clauses, preserving every word exactly once and in order. Classify each chunk as:
- "kept": expression carried over from the translated "target" line with minimal change
- "evolved": the same meaning as the translated "target" line but restructured or rephrased
- "new": content not present in the translated "target" line
For both "kept" and "evolved", include "from" as an exact contiguous substring of the translated "target" line. For "new", omit "from". Never paraphrase text inside a chunk; concatenating all chunk text must reproduce the translated "expanded" sentence.
'''}
Reply as JSON: {"original": "<corrected $sourceName line>", "target": "<$targetLanguage translation>"${expandedSource.isEmpty ? '' : ', "expanded": "<$targetLanguage translation of GROWING SENTENCE>", "chunks": [{"text":"<exact chunk from expanded>","type":"kept|evolved|new","from":"<exact substring from target; kept/evolved only>"}]'}}''',
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
          final expandedReply = (parsed['expanded'] ?? '').toString().trim();
          if (expandedReply.isNotEmpty) {
            expandedTargetText = expandedReply;
            p2Chunks = parseP2Chunks(
              parsed['chunks'],
              expandedTargetText,
              part1Text: targetText,
            );
          }
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
      final bool repaired =
          repairedOriginal.isNotEmpty && repairedOriginal != source;
      await messageRef.update(<String, dynamic>{
        'translated_text': targetText,
        // 🌱 [EXPAND-LADDER] 누적 문장의 배울글. P2가 이 값으로 사다리를 읽는다.
        if (expandedTargetText.isNotEmpty)
          'expanded_translated': expandedTargetText,
        if (expandedTargetText.isNotEmpty)
          'p2_chunks': p2Chunks.map((chunk) => chunk.toJson()).toList(),
        if (repaired) 'original_text': repairedOriginal,
        if (repaired) 'original_text_raw': source,
        if (repaired) 'original_repaired_at': FieldValue.serverTimestamp(),
        'target_generated_by': sameLanguage ? 'copy' : 'gpt-4o-mini',
        'target_generated_at': FieldValue.serverTimestamp(),
      });
      if (repaired) {
        debugPrint('[ORIGIN-REPAIR] msg=${messageRef.id} '
            '"$source" → "$repairedOriginal"');
      }
      debugPrint(
          '[HISTORY-TARGET] generated msg=${messageRef.id} model=${sameLanguage ? 'copy' : 'gpt-4o-mini'}');
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
      final original = (data['original_text'] ?? '').toString().trim();
      final translated = (data['translated_text'] ?? '').toString().trim();
      if (original.isNotEmpty && translated.isEmpty) {
        tasks.add(_generateAndCacheHistoryTarget(
          doc.reference,
          original,
          _sourceLangForMessage(data),
          expandedText: (data['expanded_sentence'] ?? '').toString().trim(),
        ));
      }
    }
    if (tasks.isNotEmpty) await Future.wait(tasks);
  }

  // 📦 [Box 10: 헬퍼 - 권한 요청]
  Future<void> _initPermissions() async {
    await [Permission.microphone].request();
  }

  // 📦 [Box 11-Room: 방 단위 진입 라우터]
  // 🔧 [TUTOR-FIX] 방 종류에 따라 분기:
  //   - polished/expanded 있음 (Step Expand 방) → 기존 Shadowing variantSelect
  //   - polished/expanded 없음 (Clone/Roleplay/Duo 방) → Tutor 모드
  Future<void> _enterShadowingFromRoom() async {
    if (_isEnteringPractice) return;
    _resumeHistoryFromUserAction();
    if (mounted) setState(() => _isEnteringPractice = true);
    try {
      var data = _cachedRoomData;
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

      final polished = (data['polished_sentence'] as String?) ?? '';
      final expanded = (data['expanded_sentence'] as String?) ?? '';
      final roomMode =
          _inferHistoryMode(data); // 🆕 [ROUTER-FIX] 버튼 표시 조건용 mode 캐시
      _cachedRoomMode = roomMode;

      // 🆕 [ROUTER-FIX] step_expand(또는 mode 없는 구버전+expanded 존재)만 Step Expand 분기.
      // clone/roleplay는 expanded_sentence가 있어도 아래 Tutor 모드로 진행.
      if (roomMode == 'step_expand' ||
          (roomMode.isEmpty && (polished.isNotEmpty || expanded.isNotEmpty))) {
        _polishedSentence = polished;
        _expandedSentence = expanded.isNotEmpty ? expanded : polished;
        _polishedLoadDone = true;
        _practicingPolished = false;

        // 화면에 이미 로드된 메시지를 재사용하고, 캐시가 없을 때만 다시 조회한다.
        var messageDocs = _cachedDocs;
        if (messageDocs.isEmpty) {
          final msgSnap = await widget.historyDoc
              .collection('messages')
              .orderBy('created_at', descending: false)
              .get();
          messageDocs = msgSnap.docs;
          _cachedDocs = messageDocs;
        }
        _stepExpandTurns = _parseStepExpandTurns(messageDocs);
        if (!mounted) return;

        // P1/P2/P3 선택 화면부터 즉시 표시하고, 느린 P3 청크/번역 생성은
        // 화면 전환 뒤 백그라운드에서 진행한다.
        final generation = ++_stepP3PreparationGeneration;
        BillingTicker.instance.setRate(BillingRate.full);
        setState(() {
          _isStepExpandRoom = true;
          isPracticeMode = true;
          _phase = ShadowingPhase.variantSelect;
          _chunks = [];
          _isPreparingStepP3 = true;
          _stepP3PreparationError = null;
        });
        unawaited(_prepareStepP3(_expandedSentence, generation));
        return;
      }

      // Clone / Roleplay / Duo 방: messages 서브컬렉션 → Tutor 모드
      await _remoteConfigFuture;
      var messageDocs = _cachedDocs;
      if (messageDocs.isEmpty) {
        final messagesSnap = await widget.historyDoc
            .collection('messages')
            .orderBy('created_at', descending: false)
            .get();
        messageDocs = messagesSnap.docs;
        _cachedDocs = messageDocs;
      }
      await _ensureHistoryTargets(messageDocs);
      final refreshedMessages = await widget.historyDoc
          .collection('messages')
          .orderBy('created_at', descending: false)
          .get();
      messageDocs = refreshedMessages.docs;
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

      _tutorLines = tutorLines;
      if (mounted) {
        setState(() {
          isPracticeMode = true;
          _phase = ShadowingPhase.turnPractice;
          currentIndex = 0;
          _tutorCurrentIdx = 0;
          _isAutoRecording = false;
          // 🆕 [BOX-30] 자동 시작 대신 선택 화면 노출
          _tutorAwaitingStart = true;
          _swapRoles = false;
          _tutorAiSpeaking = false;
          _tutorUserRecording = false;
          _tutorPlayingFullback = false;
        });
        // 역할 선택 말풍선 (2.8초 후 자동 사라짐)
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _showRoleSelectBubble());
      }
    } catch (e) {
      _showRoomEntryToast("연습 진입 실패: $e");
    } finally {
      if (mounted) setState(() => _isEnteringPractice = false);
    }
  }

  /// 대화방이 넘긴 한국어 완성문장을 P3용 영어로 만든다.
  ///
  /// 대화방은 한국어 자료만 넘긴다. 영어는 히스토리가 자기 규칙으로 만드는데,
  /// 그 자리가 여기 P3 진입 시점이다 — 바로 아래 Polished 생성과 같은 자리다.
  /// `_fetchOpenAITTS`는 받은 글자를 그대로 읽을 뿐 번역하지 않으므로, 이걸
  /// 건너뛰면 "완성 문장" 탭이 한국어를 띄우고 한국어를 소리내어 읽는다.
  Future<String?> _translateExpandedToTarget(String source) async {
    final text = source.trim();
    if (text.isEmpty || _apiKey.isEmpty) return null;
    try {
      final targetLanguage = (_sessionTargetLang ?? 'English').trim();
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: <String, String>{
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(<String, dynamic>{
              'model': 'gpt-4o-mini',
              'temperature': 0.0,
              'max_tokens': 300,
              'messages': <Map<String, String>>[
                <String, String>{
                  'role': 'system',
                  'content': 'The user built this Korean sentence step by step in a speaking '
                      'practice. Translate it into ONE natural spoken $targetLanguage '
                      'sentence for shadowing practice.\n'
                      '- Keep the speaker viewpoint, meaning, tense, and tone.\n'
                      '- Do not add or drop information.\n'
                      '- Spoken rhythm, easy to say out loud. Not written prose.\n'
                      '- The result must be 100% $targetLanguage and must NOT contain '
                      'any Korean (Hangul) characters.\n'
                      'Return only the sentence, with no label or explanation.',
                },
                <String, String>{'role': 'user', 'content': text},
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        debugPrint('[P3-EXPAND-TARGET] status=${response.statusCode}');
        return null;
      }
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final choices = body['choices'] as List? ?? const <dynamic>[];
      final firstChoice =
          choices.isEmpty ? null : choices.first as Map<String, dynamic>?;
      final message = firstChoice?['message'] as Map<String, dynamic>?;
      final translated = (message?['content'] ?? '').toString().trim();
      return translated.isEmpty ? null : translated;
    } catch (error) {
      debugPrint('[P3-EXPAND-TARGET] failed reason=${error.runtimeType}');
      return null;
    }
  }

  Future<void> _prepareStepP3(String sentence, int generation) async {
    try {
      if (!mounted || generation != _stepP3PreparationGeneration) return;
      var expanded = sentence.trim();

      // 한글이 남아 있으면 아직 영어가 안 만들어진 방이다. 여기서 한 번 만들고
      // 방 문서에 캐시해, 다음 진입부터는 이 API를 다시 타지 않게 한다.
      if (expanded.isNotEmpty && _stepExpandHangul.hasMatch(expanded)) {
        final target = await _translateExpandedToTarget(expanded);
        if (!mounted || generation != _stepP3PreparationGeneration) return;
        if (target != null) {
          expanded = target;
          _expandedSentence = expanded;
          try {
            await widget.historyDoc.update({'expanded_sentence': expanded});
            debugPrint('[P3-EXPAND-TARGET] generated model=gpt-4o-mini');
          } catch (e) {
            debugPrint('[prepareStepP3] expanded cache save failed: $e');
          }
        } else {
          debugPrint('[P3-EXPAND-TARGET] failed → 한국어 완성문장 그대로 사용');
        }
      }

      if (expanded.isNotEmpty && _polishedSentence.trim().isEmpty) {
        final polished = await _polishExpandedSentence(
          expanded,
          partnerLabel: 'AI',
        );
        if (!mounted || generation != _stepP3PreparationGeneration) return;
        if (polished != null && polished.trim().isNotEmpty) {
          final readyPolished = polished.trim();
          _polishedSentence = readyPolished;
          try {
            await widget.historyDoc.update({
              'polished_sentence': readyPolished,
              'has_practice': true,
            });
          } catch (e) {
            debugPrint('[prepareStepP3] polished cache save failed: $e');
          }
        }
      }
      if (!mounted || generation != _stepP3PreparationGeneration) return;
      setState(() {
        _isPreparingStepP3 = false;
        _stepP3PreparationError =
            expanded.isEmpty ? 'No sentence is available for P3.' : null;
      });
    } catch (e) {
      debugPrint('[prepareStepP3] $e');
      if (!mounted || generation != _stepP3PreparationGeneration) return;
      setState(() {
        _isPreparingStepP3 = false;
        _stepP3PreparationError = 'P3 preparation failed. Tap to retry.';
      });
    }
  }

  void _retryStepP3Preparation() {
    if (_isPreparingStepP3 || _expandedSentence.isEmpty) return;
    final generation = ++_stepP3PreparationGeneration;
    setState(() {
      _isPreparingStepP3 = true;
      _stepP3PreparationError = null;
    });
    unawaited(_prepareStepP3(_expandedSentence, generation));
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

  // 🆕 [TUTOR] chat_lines 처음부터 끝까지 TTS 자동 재생
  Future<void> _startTutorPlayback() async {
    if (!mounted) return;
    _resumeHistoryFromUserAction();
    if (mounted) setState(() => _isTutorPlaying = true);

    for (int i = 0; i < _tutorLines.length; i++) {
      if (!mounted || !_isTutorPlaying) break;
      final line = _tutorLines[i];
      final text = line['text'] as String;
      final bool lineRepresentsAi = _lineRepresentsAi(line);

      if (mounted) {
        setState(() {
          _tutorCurrentIdx = i;
        });
      }

      await _playTutorLineTTS(text, lineRepresentsAi);

      if (!mounted || !_isTutorPlaying) break;
      await Future.delayed(const Duration(milliseconds: 600));
    }

    if (mounted) {
      setState(() {
        _isTutorPlaying = false;
        _tutorCurrentIdx = -1;
      });
    }
  }

  // 🆕 [TUTOR] OpenAI TTS API 직접 호출 → 로컬 AudioPlayer 재생 (끝까지 대기)
  // 🔧 [v3.7] TtsCache 우선 조회 → MISS 시 API 호출 후 캐시 저장
  Future<void> _playTutorLineTTS(String text, bool isAi) async {
    if (_apiKey.isEmpty || text.trim().isEmpty) return;
    final voice = isAi ? _historyPracticeAiVoice : _historyPracticeUserVoice;
    try {
      final audio = await _getOrFetchPracticeTTS(text, voice);
      if (!mounted || !_isTutorPlaying || audio == null) return;

      final completer = Completer<void>();
      final player = AudioPlayer();
      _tutorAudioPlayer = player;

      StreamSubscription? stateSub;
      StreamSubscription? completeSub;

      stateSub = player.onPlayerStateChanged.listen((state) {
        if (state == PlayerState.stopped) {
          if (!completer.isCompleted) completer.complete();
          stateSub?.cancel();
        }
      });
      completeSub = player.onPlayerComplete.listen((_) {
        if (!completer.isCompleted) completer.complete();
        completeSub?.cancel();
      });

      try {
        BillingTicker.instance.resumeFromActivity('history_tutor_tts_start');
        await player.play(BytesSource(audio));
        await completer.future
            .timeout(const Duration(seconds: 30), onTimeout: () {});
        BillingTicker.instance.resumeFromActivity('history_tutor_tts_end');
      } finally {
        stateSub.cancel();
        completeSub.cancel();
        await player.dispose();
        _tutorAudioPlayer = null;
      }
    } catch (e) {
      debugPrint("[playTutorLineTTS] $e");
    }
  }

  // 🆕 [TUTOR] 사용자가 종료/중단할 때 호출
  void _stopTutorPlayback() {
    resetBillingIdle();
    _tutorAudioPlayer?.stop();
    if (mounted) {
      setState(() {
        _isTutorPlaying = false;
        _tutorCurrentIdx = -1;
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

  void _startP2Reading() {
    if (!mounted ||
        _phase != ShadowingPhase.part2Practice ||
        !_tutorAwaitingStart) {
      return;
    }
    _resumeHistoryFromUserAction();
    setState(() => _tutorAwaitingStart = false);
    _startTurnPractice();
  }

  // ============================================================================
  // 📦 [Box 11-C: 양방향 턴제 연습 엔진 (Turn-Based Practice)]
  // ============================================================================

  void _startTurnPractice() {
    _resumeHistoryFromUserAction();
    if (!mounted || _tutorLines.isEmpty) return;
    currentIndex = 0;
    if (mounted) setState(() => _tutorCurrentIdx = 0);
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
          _tutorCurrentIdx = next;
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
        _tutorCurrentIdx = next;
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
    if (_phase == ShadowingPhase.part2Practice) {
      if (_tutorAwaitingStart) return;
      // 🔤 [P2-MORPH] See How It Grows를 누르면
      //   첫 문장부터 자라는 흐름을 시작한다.
      unawaited(_runMorphStep(currentIndex));
      return;
    }
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

  // ============================================================================
  // [P2-SHADOW] Highlight read-along.
  // ============================================================================

  // ══════════════════════════════════════════════════════════════════
  // 🔤 [P2-MORPH] Thought Expansion
  //
  //   P2는 **문장이 자라는 모습을 보고 듣는 자리**다. 마이크도 녹음도 없다.
  //   말하기는 P3가 맡는다.
  //
  //   화면: GPT의 kept/evolved/new 청크와 단계별로 짙어지는 문장 테두리
  //   음성: LCS 핵심 변화 하나만 살린 Smooth Jazz 전체 낭독 → 다음 계단
  // ══════════════════════════════════════════════════════════════════

  /// 문장이 먼저 눈에 들어온 뒤 전체 문장 재생을 시작하는 짧은 전환.
  static const Duration _kMorphHighlightDelay = Duration(milliseconds: 320);

  /// 한 계단을 연다.
  Future<void> _runMorphStep(int lineIdx) async {
    _shadowHighlightTimer?.cancel();
    _shadowAdvanceTimer?.cancel();
    if (!mounted || !isPracticeMode || lineIdx >= _tutorLines.length) return;

    final text = (_tutorLines[lineIdx]['text'] as String).trim();
    if (text.isEmpty) {
      _nextTurn();
      return;
    }
    // 바로 앞 계단이 비교 대상이다. 첫 계단은 견줄 것이 없어 강조가 없다.
    final previous =
        lineIdx > 0 ? (_tutorLines[lineIdx - 1]['text'] as String).trim() : '';
    final morph = computeMorph(previous, text);
    debugPrint('[P2-THOUGHT]\n'
        'Previous: ${previous.isEmpty ? '(none)' : previous}\n'
        'Current: $text\n'
        'All Changes: ${morph.phrases}\n'
        'Primary Morph: ${morph.primary?.phrase ?? '(none)'}');

    _pinShadowLineToTop(lineIdx);
    _startShadowLineGlide(lineIdx,
        text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList());
    if (mounted) {
      setState(() {
        _morphPreparing = true;
        _p2ActiveChunkIndex = -1;
        _p2MorphDurationMs = 0;
      });
    }

    // 소리는 미리 받아 둔다. 강조가 켜지는 동안 네트워크를 기다리지 않는다.
    final audioFuture = _getMorphPcm(text, morph, lineIdx);

    await Future<void>.delayed(_kMorphHighlightDelay);
    if (!_morphAlive(lineIdx)) return;

    Uint8List? pcm;
    try {
      pcm = await audioFuture;
    } catch (e) {
      debugPrint('[P2-MORPH] tts $e');
    }
    if (!_morphAlive(lineIdx)) return;
    if (mounted) setState(() => _morphPreparing = false);

    if (pcm == null || pcm.isEmpty) {
      // 소리를 못 만들었다. 계단을 붙잡아 두지 않고 넘어간다.
      _scheduleMorphAdvance(lineIdx);
      return;
    }
    await _playMorphAudio(_applyP2BreathGap(pcm, lineIdx), lineIdx);
  }

  /// P3 Shadowing과 같은 호흡 분석·gap 삽입을 재사용한다. 첫 문장은 Normal,
  /// 다음 문장부터는 Relaxed이며 원본 발성 속도는 바꾸지 않는다.
  Uint8List _applyP2BreathGap(Uint8List pcm, int lineIdx) {
    final gap = _p2GapForLine(lineIdx);
    final gapMs = _kP3ShadowGapMs[gap] ?? 500;
    final analysis = analyzeBreaths(pcm, const BreathAnalysisConfig());
    debugPrint('[P2-PACE] line=${lineIdx + 1} gap=${_kP3ShadowGapLabel[gap]} '
        'gapMs=$gapMs breaths=${analysis.segments.length}');
    return buildGappedPcm(
      pcm,
      analysis.segments,
      extraGapMs: gapMs,
      sampleRate: kStealthVoxSttSampleRate,
    );
  }

  P3ShadowGap _p2GapForLine(int lineIdx) =>
      lineIdx == 0 ? P3ShadowGap.normal : P3ShadowGap.relaxed;

  bool _morphAlive(int lineIdx) =>
      mounted &&
      _phase == ShadowingPhase.part2Practice &&
      !isPaused &&
      currentIndex == lineIdx;

  /// 전체 문장을 한 번 읽는다. 재생기는 기존 `_shadowAiPlayer`를 그대로 쓴다 —
  /// 화면 이탈·뒤로가기 정리 경로가 이미 [_stopShadowAiPlayback]을 부르고 있어
  /// 새 정리 지점을 만들지 않아도 된다.
  Future<void> _playMorphAudio(Uint8List pcm, int lineIdx) async {
    await _stopShadowAiPlayback();
    if (!_morphAlive(lineIdx)) return;
    final wav = pcm16ToWav(pcm, sampleRate: kStealthVoxSttSampleRate);
    final player = AudioPlayer();
    _shadowAiPlayer = player;
    final chunks = _p2ChunksForLine(_tutorLines[lineIdx]);
    _p2MorphDurationMs =
        ((pcm.length / 2) / kStealthVoxSttSampleRate * 1000).round();
    _shadowDurSub = player.onDurationChanged.listen((duration) {
      if (duration.inMilliseconds > 0) {
        _p2MorphDurationMs = duration.inMilliseconds;
      }
    });
    _shadowPosSub = player.onPositionChanged.listen((position) {
      if (!_morphAlive(lineIdx)) return;
      final next = p2ChunkIndexAtPosition(
        chunks,
        positionMs: position.inMilliseconds,
        totalMs: _p2MorphDurationMs,
      );
      if (next == _p2ActiveChunkIndex) return;
      setState(() => _p2ActiveChunkIndex = next);
    });
    if (mounted) {
      setState(() {
        _morphPlaying = true;
        _p2ActiveChunkIndex = chunks.isEmpty ? -1 : 0;
      });
    }
    // onPlayerComplete.first는 쓰지 않는다 - dispose 때 스트림이 빈 채로
    // 닫히며 Bad state: No element가 새어 대기가 무너진다.
    _shadowCompleteSub = player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _morphPlaying = false;
        _p2ActiveChunkIndex = -1;
      });
      _scheduleMorphAdvance(lineIdx);
    });
    try {
      await player.play(BytesSource(wav));
    } catch (e) {
      debugPrint('[P2-MORPH] play $e');
      await _stopShadowAiPlayback();
      if (mounted) {
        setState(() {
          _morphPlaying = false;
          _p2ActiveChunkIndex = -1;
        });
      }
      _scheduleMorphAdvance(lineIdx);
    }
  }

  void _scheduleMorphAdvance(int lineIdx) {
    _shadowAdvanceTimer?.cancel();
    final gapMs = _kP3ShadowGapMs[_p2GapForLine(lineIdx)] ?? 500;
    _shadowAdvanceTimer = Timer(Duration(milliseconds: gapMs), () {
      if (!_morphAlive(lineIdx)) return;
      _nextTurn();
    });
  }

  /// 이번 문장의 소리. **Primary Morph 하나가 캐시 키에 들어간다** - 같은
  /// 문장이라도 핵심 변화가 다르면 다른 소리이므로 같은 오디오를 쓰면 안 된다.
  Future<Uint8List?> _getMorphPcm(String text, MorphChange morph, int lineIdx) {
    const morphInstructionVersion = 'primary_v1';
    final voice = _p2VoiceForLine(lineIdx);
    final ns = '${_breathCacheNamespace(voice)}'
        '_$morphInstructionVersion'
        '_m${morph.identity}';
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
        instructions:
            _kBreathStyle.instruction + morphEmphasisInstruction(morph),
        instructionTag: '${_kBreathStyle.id}'
            '_$morphInstructionVersion'
            '_m${morph.identity}',
        responseFormat: 'pcm',
      );
      if (raw == null || raw.isEmpty) return null;
      await TtsCache.put(
        text,
        ns,
        pcm16ToWav(raw, sampleRate: kStealthVoxSttSampleRate),
      );
      return raw;
    }();
    _breathPcmInFlight[requestKey] = future;
    future.whenComplete(() => _breathPcmInFlight.remove(requestKey));
    return future;
  }

  /// 낭독 재생기를 닫는다. **P2 Morphing이 이 재생기를 그대로 쓴다** —
  /// 화면 이탈·뒤로가기 정리 경로가 이미 여기를 부르고 있어 새 정리 지점을
  /// 만들지 않아도 된다.
  Future<void> _stopShadowAiPlayback() async {
    _shadowPosSub?.cancel();
    _shadowPosSub = null;
    _shadowDurSub?.cancel();
    _shadowDurSub = null;
    _shadowCompleteSub?.cancel();
    _shadowCompleteSub = null;
    _p2ActiveChunkIndex = -1;
    _p2MorphDurationMs = 0;
    final p = _shadowAiPlayer;
    _shadowAiPlayer = null;
    if (p != null) {
      try {
        await p.stop();
      } catch (_) {}
      try {
        await p.dispose();
      } catch (_) {}
    }
  }

  /// 단어 하나를 읽는 데 걸리는 대략의 시간. 자동 스크롤
  /// ([_startShadowLineGlide])이 문장 길이를 가늠하는 데만 쓴다.
  int _shadowWordDuration(String w) {
    final clean = w.replaceAll(RegExp(r'[^A-Za-z]'), '');
    int d = 220 + clean.length * 55;
    if (RegExp(r'[,;:]$').hasMatch(w)) d += 160;
    if (RegExp(r'[.!?]$').hasMatch(w)) d += 320;
    d = (d / _shadowSpeed).round();
    return d.clamp(140, 1100);
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
          if ((_phase == ShadowingPhase.turnPractice ||
                  _phase == ShadowingPhase.part1Practice ||
                  _phase == ShadowingPhase.part2Practice) &&
              mounted) {
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

  Future<void> _startPracticeWithVariant(SentenceVariant variant) async {
    _selectedVariant = variant;
    final sentence =
        (variant == SentenceVariant.polished && _polishedSentence.isNotEmpty)
            ? _polishedSentence
            : _expandedSentence;
    if (!mounted) return;

    await _buildChunks(sentence);

    if (_chunks.isEmpty) {
    } else {
      for (int i = 0; i < _chunks.length; i++) {}
    }

    if (mounted) setState(() => _phase = ShadowingPhase.practicing);
    _prefetchAllChunkAI();
  }

  /// 🔙 [STEP-BACK] 진행 중인 Step Expand 연습을 접고 **P1/P2/P3 고르는 자리로**
  /// 돌아간다. 방을 나가지 않는다 — 실행 중 X는 "그만두겠다"가 아니라
  /// "다시 고르겠다"는 뜻이라, 방까지 닫으면 히스토리 목록부터 되짚어
  /// 들어와야 했다. 방을 나가는 X는 고르는 화면에 그대로 있다.
  ///
  /// 이 방의 재료(`_stepExpandTurns`·완성문장·P3 청크)는 손대지 않는다.
  /// 지운 것은 이번 회차의 흔적뿐이라 곧바로 다시 시작할 수 있다.
  void _backToStepExpandSelect() {
    unawaited(_deleteUserRecordings());
    _stopTutorPlayback();
    _stopAutoVADRecording();
    _utteranceSafetyTimer?.cancel();
    _shadowHighlightTimer?.cancel(); // [P2-SHADOW]
    _shadowAdvanceTimer?.cancel(); // [P2-SHADOW]
    unawaited(_stopShadowAiPlayback()); // [P2-SHADOW-AI]
    unawaited(_stopP3Shadowing(resetSelection: true));
    _stopDeepgramListening();
    audioPlayer.stop();
    if (!mounted) return;
    setState(() {
      _phase = ShadowingPhase.variantSelect;
      isPaused = false;
      _tutorLines = [];
      currentIndex = 0;
      _tutorCurrentIdx = 0;
      _isAutoRecording = false;
      _tutorAiSpeaking = false;
      _tutorUserRecording = false;
      _tutorPlayingFullback = false;
      _tutorAwaitingStart = true;
      _swapRoles = false;
      _showRetryHint = false;
      _isListening = false;
      _isPlayingFullUser = false;
      _isPlayingFullAI = false;
      _fullUserPlayIdx = 0;
      _isReplayMode = false;
      _aiChunkPlaying = false;
      _aiChunkLoading = false;
      _currentChunkIdx = 0;
    });
    _echoingOverlayTimer?.cancel();
  }

  void _exitShadowing() {
    _stepP3PreparationGeneration++;
    _deleteUserRecordings(); // 🆕 Practice 임시 녹음 파일 정리
    BillingTicker.instance.setRate(BillingRate.full);
    _stopTutorPlayback();
    _stopAutoVADRecording();
    _utteranceSafetyTimer?.cancel();
    _polishedRevealTimer?.cancel();
    _shadowHighlightTimer?.cancel(); // [P2-SHADOW]
    _shadowAdvanceTimer?.cancel(); // [P2-SHADOW]
    _stopShadowAiPlayback(); // [P2-SHADOW-AI]
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
        _expandedSentence = "";
        _polishedSentence = "";
        _polishedLoadDone = false;
        currentIndex = 0;
        _isAutoRecording = false;
        _aiChunkPlaying = false; // 🆕 [P2-INDICATOR]
        _aiChunkLoading = false;
        _isReplayMode = false; // 🆕 [P2-INDICATOR]
        _practicingPolished = false; // 🆕 [CHUNK-PRACTICE]
        _isPlayingFullAI = false; // 🆕 [CHUNK-PRACTICE]
        _tutorAwaitingStart = true; // 🆕 [BOX-30]
        _swapRoles = false; // 🆕 [BOX-32]
        _tutorAiSpeaking = false; // 🆕 [BOX-31]
        _tutorUserRecording = false; // 🆕 [BOX-31]
        _tutorPlayingFullback = false; // 🆕 [BOX-34]
        // Step Expand 리셋
        _isStepExpandRoom = false;
        _stepExpandTurns = [];
        _isPreparingStepP3 = false;
        _stepP3PreparationError = null;
        _showRetryHint = false;
      });
    }
  }

  // 📦 [Box 12: 상태 머신 본체]

  // [chunkSplit] GPT-4o-mini로 문장을 5~7단어 호흡 단위로 분할
  Future<List<String>?> _splitByBreathGroupsGpt(String sentence) async {
    if (_apiKey.isEmpty || sentence.isEmpty) return null;
    try {
      const sysPrompt =
          'You are a speaking practice assistant. Split the given English sentence '
          'into natural breath groups for speaking practice.\n'
          'Return ONLY a JSON array of strings with no extra text or explanation.\n'
          'Requirements:\n'
          '- Target 5–7 words per chunk.\n'
          '- Never exceed 8 words per chunk unless absolutely unavoidable.\n'
          '- Avoid chunks shorter than 3 words unless it is a very natural phrase.\n'
          '- Prefer splitting at: commas, conjunctions (and/but/so/because/when/while/'
          'although/if/since/after/before), relative clauses (who/which/that/where), '
          'prepositional phrases, infinitive phrases (to + verb).\n'
          '- Do not rewrite the sentence. Do not omit or add words. '
          'Preserve the original word order.\n'
          'Example: ["I wanted to practice English every day", '
          '"because I felt nervous", "when speaking with foreigners", '
          '"but I slowly became more confident", "after using the app"]';
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'gpt-4o-mini',
              'messages': [
                {'role': 'system', 'content': sysPrompt},
                {'role': 'user', 'content': 'Sentence: "$sentence"'},
              ],
              'temperature': 0.0,
              'max_tokens': 400,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final content =
          ((body['choices'] as List).first['message']['content'] as String)
              .trim();
      final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(content);
      if (jsonMatch == null) return null;
      final list = jsonDecode(jsonMatch.group(0)!) as List;
      final raw = list
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      return _postProcessChunks(raw);
    } catch (e) {
      debugPrint("[splitByBreathGroupsGpt] $e");
      return null;
    }
  }

  // [chunkSplit] 긴 청크(9단어↑)를 자연 분할 위치에서 재분할
  List<String> _splitLongChunkByWords(List<String> words) {
    if (words.length <= 8) return [words.join(' ')];
    const splitWords = {
      'because',
      'when',
      'while',
      'although',
      'if',
      'since',
      'after',
      'before',
      'who',
      'which',
      'that',
      'where',
      'and',
      'but',
      'so',
      'to'
    };
    // 4~7 위치에서 자연 분할 위치 탐색
    for (int i = 5; i >= 3; i--) {
      if (i < words.length) {
        final w = words[i].toLowerCase().replaceAll(RegExp(r'[.,;:!?]+$'), '');
        if (splitWords.contains(w)) {
          return [
            words.sublist(0, i).join(' '),
            words.sublist(i).join(' '),
          ];
        }
      }
    }
    // 자연 위치 없으면 중간 분할
    final mid = (words.length / 2).round().clamp(4, words.length - 1);
    return [words.sublist(0, mid).join(' '), words.sublist(mid).join(' ')];
  }

  // [chunkSplit] GPT 결과 후처리: 9단어↑ 재분할, 1~2단어 병합
  List<String> _postProcessChunks(List<String> chunks) {
    if (chunks.isEmpty) return chunks;
    // Step 1: 9단어 이상 청크 재분할
    final List<String> step1 = [];
    for (final chunk in chunks) {
      final words = chunk.trim().split(RegExp(r'\s+'));
      if (words.length >= 9) {
        step1.addAll(_splitLongChunkByWords(words));
      } else {
        step1.add(chunk);
      }
    }
    // Step 2: 1~2단어 청크를 앞 청크에 병합
    final List<String> step2 = [];
    for (final chunk in step1) {
      final wordCount = chunk.trim().split(RegExp(r'\s+')).length;
      if (wordCount <= 2 && step2.isNotEmpty) {
        step2[step2.length - 1] = '${step2.last} $chunk';
      } else {
        step2.add(chunk);
      }
    }
    return step2.isEmpty ? chunks : step2;
  }

  // [chunkSplit] 캐시 조회 → GPT → Fallback 통합 분할 (Expanded·Polished 공통)
  Future<List<String>> _splitSentenceIntoChunks(
      String sentence, String variant) async {
    if (sentence.isEmpty) return [];
    // 1. 디스크 캐시 확인 (v2)
    final cached = await _readChunkCache(variant, sentence);
    if (cached != null && cached.isNotEmpty) return cached;
    // 2. GPT 5~7단어 분할
    final gptChunks = await _splitByBreathGroupsGpt(sentence);
    if (gptChunks != null && gptChunks.isNotEmpty) {
      await _writeChunkCache(variant, sentence, gptChunks);
      return gptChunks;
    }
    // 3. Fallback: 정규식 분할
    return _buildChunksLegacyList(sentence);
  }

  // [chunkSplit] 정규식 분할 + 8단어 상한 후처리 (fallback용)
  List<String> _buildChunksLegacyList(String sentence) {
    const abbrevs = ['Mr', 'Mrs', 'Ms', 'Dr', 'Prof', 'Sr', 'Jr', 'St'];
    String temp = sentence;
    for (final abbr in abbrevs) {
      temp = temp.replaceAll('$abbr.', '$abbr․');
    }
    final splitRe = RegExp(
      r'(?<=[,.!?])\s+|'
      r'\s+(?=(?:who|whom|whose|which|that|where|when|while|because|since|although|though|if|unless|but|and|so|for|with|about|after|before|in|on|at|to)\b)',
      caseSensitive: false,
    );
    final rawParts = temp
        .split(splitRe)
        .map((s) => s.trim().replaceAll('․', '.'))
        .where((s) => s.isNotEmpty)
        .toList();
    // 1차 병합: 3단어 미만 조각을 앞 청크에 붙이기
    final merged = <String>[];
    for (final part in rawParts) {
      final wordCount = part.trim().split(RegExp(r'\s+')).length;
      if (wordCount < 3 && merged.isNotEmpty) {
        merged[merged.length - 1] = '${merged.last} $part';
      } else {
        merged.add(part);
      }
    }
    if (merged.length >= 2 &&
        merged[0].trim().split(RegExp(r'\s+')).length < 3) {
      merged[1] = '${merged[0]} ${merged[1]}';
      merged.removeAt(0);
    }
    // 2차: 8단어 초과 청크 재분할
    final List<String> step2 = [];
    for (final chunk in merged) {
      final words = chunk.trim().split(RegExp(r'\s+'));
      if (words.length >= 9) {
        step2.addAll(_splitLongChunkByWords(words));
      } else {
        step2.add(chunk);
      }
    }
    // 3차: 재분할 후 생긴 1~2단어 조각 재병합
    final List<String> result = [];
    for (final chunk in step2) {
      final wc = chunk.trim().split(RegExp(r'\s+')).length;
      if (wc <= 2 && result.isNotEmpty) {
        result[result.length - 1] = '${result.last} $chunk';
      } else {
        result.add(chunk);
      }
    }
    return result.isEmpty ? merged : result;
  }

  // [chunkCache] 문장 내용 기반 8자리 해시 (캐시 키용)
  String _chunkTextHash(String text) {
    int hash = 5381;
    for (final c in text.codeUnits) {
      hash = ((hash << 5) + hash) ^ c;
      hash &= 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0').substring(0, 8);
  }

  // [chunkCache] 디스크에서 분할 결과 읽기 (v2: 5~7단어 기준)
  Future<List<String>?> _readChunkCache(String variant, String sentence) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final roomId = widget.historyDoc.id;
      final hash = _chunkTextHash(sentence);
      final file = File(
          '${dir.path}/chunk_cache/chunk_split_v2_${roomId}_${variant}_$hash.json');
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final list = jsonDecode(content) as List;
      final result =
          list.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      return result;
    } catch (e) {
      debugPrint("[readChunkCache] $e");
      return null;
    }
  }

  // [chunkCache] 디스크에 분할 결과 저장 (v2: 5~7단어 기준)
  Future<void> _writeChunkCache(
      String variant, String sentence, List<String> chunks) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final roomId = widget.historyDoc.id;
      final hash = _chunkTextHash(sentence);
      final folder = Directory('${dir.path}/chunk_cache');
      if (!await folder.exists()) await folder.create(recursive: true);
      final file =
          File('${folder.path}/chunk_split_v2_${roomId}_${variant}_$hash.json');
      await file.writeAsString(jsonEncode(chunks));
    } catch (e) {
      debugPrint("[writeChunkCache] $e");
    }
  }

  // 🆕 [KO-FRAG] 영어 청크 리스트 → 영어어순 직독 한국어 조각 (개수·순서 1:1)
  Future<List<String>?> _generateKoFragmentsGpt(List<String> enChunks) async {
    if (_apiKey.isEmpty || enChunks.isEmpty) return null;
    try {
      const sysPrompt =
          """You are a Korean sight-translation (jikdokjikhae) helper.
You receive an English sentence already split into ordered chunks as a JSON array.
For EACH chunk, output ONE short Korean reading fragment that follows the English word order.
These are intentionally incomplete connecting fragments, NOT a polished full translation.

[RULES]
- Output ONLY a JSON array of Korean strings. No markdown, no extra text, no code fences.
- The array length MUST equal the number of input chunks, in the same order.
- Each fragment expresses ONLY that chunk, in English order. Do not reorder across chunks.
- Use natural Korean connective endings that fit each chunk role
  (reason: ~이니까/~여서, thinking: ~라고 생각해서, time: ~할 때, contrast: ~지만, purpose: ~하려고).
- Apply correct particles (이/가, 은/는, 을/를, 한테/에게). Use honorific ~시 only if present in English.
- Keep each fragment short, one breath. Do not add information not in the chunk.
- Korean only inside the strings.

Example input: ["I think","that the price","went up","because of the weather"]
Example output: ["나는 생각해","그 가격이","올랐다고","날씨 때문에"]""";
      final response = await http
          .post(
            Uri.parse("https://api.openai.com/v1/chat/completions"),
            headers: {
              "Authorization": "Bearer $_apiKey",
              "Content-Type": "application/json",
            },
            body: jsonEncode({
              "model": "gpt-4o-mini",
              "messages": [
                {"role": "system", "content": sysPrompt},
                {"role": "user", "content": jsonEncode(enChunks)},
              ],
              "temperature": 0.2,
              "max_tokens": 600,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final content =
          ((body["choices"] as List).first["message"]["content"] as String)
              .trim();
      final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(content);
      if (jsonMatch == null) return null;
      final list = jsonDecode(jsonMatch.group(0)!) as List;
      final ko = list.map((e) => e.toString().trim()).toList();
      if (ko.length != enChunks.length) {
        return null;
      }
      return ko;
    } catch (e) {
      debugPrint("[generateKoFragmentsGpt] $e");
      return null;
    }
  }

  // 🆕 [KO-FRAG] 디스크 캐시 읽기 (영어 청크 캐시와 파일명 분리: kofrag_v1)
  Future<List<String>?> _readKoFragCache(
      String variant, String sentence) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final roomId = widget.historyDoc.id;
      final hash = _chunkTextHash(sentence);
      final file = File(
          '${dir.path}/chunk_cache/kofrag_v1_${roomId}_${variant}_$hash.json');
      if (!await file.exists()) return null;
      final list = jsonDecode(await file.readAsString()) as List;
      return list.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint("[readKoFragCache] $e");
      return null;
    }
  }

  // 🆕 [KO-FRAG] 디스크 캐시 쓰기
  Future<void> _writeKoFragCache(
      String variant, String sentence, List<String> ko) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final roomId = widget.historyDoc.id;
      final hash = _chunkTextHash(sentence);
      final folder = Directory('${dir.path}/chunk_cache');
      if (!await folder.exists()) await folder.create(recursive: true);
      final file =
          File('${folder.path}/kofrag_v1_${roomId}_${variant}_$hash.json');
      await file.writeAsString(jsonEncode(ko));
    } catch (e) {
      debugPrint("[writeKoFragCache] $e");
    }
  }

  Future<void> _buildChunks(String sentence,
      {int? preparationGeneration}) async {
    bool isCurrentPreparation() =>
        preparationGeneration == null ||
        preparationGeneration == _stepP3PreparationGeneration;
    if (sentence.isEmpty) {
      if (!isCurrentPreparation()) return;
      _chunks = [];
      _currentChunkIdx = 0;
      return;
    }
    final isPolished =
        _polishedSentence.isNotEmpty && sentence == _polishedSentence;
    final variant = isPolished ? 'polished' : 'expanded';
    final result = await _splitSentenceIntoChunks(sentence, variant);

    // 🆕 [KO-FRAG] 영어 청크에 1:1 한국어 직독 조각 부착 (캐시 → GPT).
    //   실패/개수 불일치 시 ko=null → 영어 청크만 정상 표시 (영어 경로 영향 0).
    List<String>? ko = await _readKoFragCache(variant, sentence);
    if (ko == null || ko.length != result.length) {
      ko = await _generateKoFragmentsGpt(result);
      if (ko != null && ko.length == result.length) {
        await _writeKoFragCache(variant, sentence, ko);
      } else {
        ko = null;
      }
    }

    if (!isCurrentPreparation()) return;
    _chunks = List.generate(
      result.length,
      (i) => PracticeChunk(
        text: result[i],
        korean: (ko != null && i < ko.length) ? ko[i] : null,
      ),
    );
    _currentChunkIdx = 0;
  }

  Future<void> _prefetchAllChunkAI() async {
    if (_apiKey.isEmpty) {}
    for (int i = 0; i < _chunks.length; i++) {
      if (!mounted ||
          (_phase != ShadowingPhase.practicing &&
              _phase != ShadowingPhase.chunkPractice)) {
        break;
      }
      if (_chunks[i].aiAudio != null) {
        continue;
      }
      try {
        await _getOrFetchChunkAudio(i);
      } catch (e) {
        debugPrint("[prefetchAllChunkAI] $e");
      }
    }
  }

  void _onAudioComplete() {
    if (!mounted) return;
    if (_phase == ShadowingPhase.reviewing && _isPlayingFullUser) {
      _advanceFullUserPlay();
    } else if ((_phase == ShadowingPhase.turnPractice ||
            _phase == ShadowingPhase.part1Practice ||
            _phase == ShadowingPhase.part2Practice) &&
        isPracticeMode &&
        !isPaused) {
      if (mounted) setState(() => _tutorAiSpeaking = false); // 🆕 [BOX-31]
      _nextTurn();
    } else if (_practicingPolished && _polishedUnitAIPlaying) {
      // 세련문장 의미단위 AI 재생 완료 → 사용자 녹음 시작
      if (mounted) setState(() => _polishedUnitAIPlaying = false);
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

    // Polished 의미단위 모드: 녹음 완료 → 다음 유닛으로 자동 이동
    if (_practicingPolished) {
      await _stopDualCaptureAndSave();
      if (!mounted) return;
      final nextIdx = _polishedUnitIdx + 1;
      if (nextIdx < _polishedUnits.length) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted && _practicingPolished) {
            _onPolishedUnitTapped(nextIdx);
          }
        });
      }
      return;
    }

    if (_phase != ShadowingPhase.practicing &&
        _phase != ShadowingPhase.chunkPractice) return;
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
        _selectedVariant == SentenceVariant.polished ? 'pol' : 'exp';
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

  // 📦 [Box 14: AI 청크 재생]
  Future<void> _playCurrentChunkAI() async {
    if (_currentChunkIdx >= _chunks.length) return;
    await _playChunkAI(_currentChunkIdx);
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

  // 🆕 [P2-REPLAY] 사용자가 청크 ▶ 아이콘을 다시 탭했을 때 호출
  //   - 진행 중인 모든 동작(녹음/AI재생) 즉시 취소
  //   - 그 청크의 AI 음성만 재생, 끝나면 정지 (마이크 자동 활성 X)
  Future<void> _replayChunkAI(int idx) async {
    _resumeHistoryFromUserAction();
    if (idx >= _chunks.length) return;
    // 1. 진행 중인 녹음 즉시 취소
    if (_isListening) {
      _stopDeepgramListening();
    }
    // 2. 진행 중인 AI 재생 중지
    await audioPlayer.stop();
    // 3. Replay 모드 활성화 + 청크 이동 및 리셋
    if (mounted) {
      setState(() {
        _isReplayMode = true;
        _currentChunkIdx = idx;
        _chunks[idx].isDone = false;
        _chunks[idx].userRecordPath = null;
      });
    }
    // 4. AI 음성만 재생
    await _playChunkAI(idx);
  }

  // 🆕 [P2-REPLAY] 사용자가 마이크 버튼을 명시적으로 눌렀을 때 호출
  //   - Replay 모드 해제 후 일반 녹음 시작
  void _userTriggeredRecord() {
    if (mounted) {
      setState(() {
        _isReplayMode = false;
      });
    }
    _startDualCapture();
  }

  // 📦 [Box 15: 아이콘 탭 핸들러]
  void _onUserIconTap() {
    if (_phase != ShadowingPhase.practicing) return;
    if (_isListening) {
      _onUserUtteranceEnd();
    } else {
      audioPlayer.stop();
      _userTriggeredRecord(); // 🆕 [P2-REPLAY] Replay 모드 해제 후 녹음
    }
  }

  void _onAIIconTap() {
    if (_phase != ShadowingPhase.practicing) return;
    _replayChunkAI(_currentChunkIdx); // 🆕 [P2-REPLAY] 진행 중 취소 + AI만 재생
  }

  // 📦 [Box 16: 청크 전진/완료]
  void _advanceChunk() {
    if (_currentChunkIdx < _chunks.length - 1) {
      setState(() {
        _currentChunkIdx++;
      });
      _playCurrentChunkAI();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollCurrentChunkToCenter();
      });
    } else {
      _completeShadowing();
    }
  }

  void _completeShadowing() {
    _stopDeepgramListening();
    audioPlayer.stop();
    if (mounted) setState(() => _phase = ShadowingPhase.reviewing);
  }

  // 📦 [Box 16-A: Review 기능]
  Future<void> _playFullAI() async {
    _resumeHistoryFromUserAction();
    for (int i = 0; i < _chunks.length; i++) {
      if (!mounted || _phase != ShadowingPhase.reviewing) break;
      await _playChunkAI(i);
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 100));
        return isPlaying && mounted;
      });
      if (!mounted) break;
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<void> _playFullUser() async {
    _resumeHistoryFromUserAction();
    if (mounted)
      setState(() {
        _isPlayingFullUser = true;
        _fullUserPlayIdx = 0;
      });
    _playUserChunk(0);
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

  // 📦 [Box 17-B: 다른 표현 보기 - 말풍선 옆 버튼]
  Widget _buildAltStyleBtn(String baseText) {
    return IconButton(
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      // translate 아이콘은 글리프에 한자(文)가 들어 있어 쓰지 않는다.
      // 글자 없는 교체 화살표로 "같은 뜻 다른 표현"을 나타낸다.
      icon: const Icon(
        Icons.swap_horiz_rounded,
        color: Color(0xFF38BDF8),
        size: 26,
      ),
      onPressed: () => _showAltStylePopup(baseText),
      tooltip: "다른 표현 보기",
    );
  }

  /// 이 세션에서 실제로 적용되는 AI STYLE.
  ///
  /// AI STYLE은 **영어 대화 전용 설정**이다. 세션 타겟이 영어가 아니면
  /// 저장값(American 등)이 무엇이든 `Standard`로 취급한다. 전역
  /// `FFAppState().aiStyle` 자체는 건드리지 않는다 — 영어로 돌아왔을 때
  /// 마지막 선택을 그대로 복원해야 하기 때문이다.
  String _effectiveAiStyle() {
    final targetLanguage = (_sessionTargetLang ?? 'English').trim();
    if (targetLanguage != 'English') return 'Standard';
    final saved = FFAppState().aiStyle.trim();
    return saved.isEmpty ? 'Standard' : saved;
  }

  /// 지금 적용 중인 스타일([_effectiveAiStyle])을 뺀 나머지 스타일들.
  /// 영어가 타겟일 때만 American/British가 존재한다(로비와 같은 규칙).
  /// 순서는 Standard → American → British → Native로 고정한다.
  List<String> _otherAiStyles() {
    final targetLanguage = (_sessionTargetLang ?? 'English').trim();
    const canonical = ['Standard', 'American', 'British', 'Native'];
    final available =
        targetLanguage == 'English' ? canonical : const ['Standard', 'Native'];
    final current = _effectiveAiStyle();
    return available.where((style) => style != current).toList();
  }

  String _altStyleBrief(String style) {
    switch (style) {
      case 'Standard':
        return 'neutral, textbook-clear wording that any international speaker would understand';
      case 'American':
        return 'American vocabulary, idioms, and spelling as spoken in the US';
      case 'British':
        return 'British vocabulary, idioms, and spelling as spoken in the UK';
      case 'Native':
        return 'what a native speaker would actually say in relaxed everyday speech, with contractions and natural rhythm';
      default:
        return 'natural everyday wording';
    }
  }

  /// 같은 뜻을 스타일만 바꿔 다시 쓴다. 뜻·화자 시점·존댓말 정도는 유지한다.
  Future<Map<String, String>> _fetchAltStyleSentences(
    String baseText,
    List<String> styles,
  ) async {
    final source = baseText.trim();
    if (_apiKey.isEmpty || source.isEmpty || styles.isEmpty) {
      return <String, String>{};
    }
    final targetLanguage = (_sessionTargetLang ?? 'English').trim();
    final guide = styles.map((s) => '- "$s": ${_altStyleBrief(s)}').join('\n');
    try {
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: <String, String>{
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(<String, dynamic>{
              'model': 'gpt-4o-mini',
              'temperature': 0.4,
              'max_tokens': 400,
              'response_format': <String, String>{'type': 'json_object'},
              'messages': <Map<String, String>>[
                <String, String>{
                  'role': 'system',
                  'content': 'Rewrite ONE $targetLanguage sentence in different regional/register styles.\n'
                      'Keep the meaning, the speaker viewpoint, and the politeness level identical. '
                      'Only the wording and flavour change.\n'
                      'Styles requested:\n$guide\n'
                      'Return ONLY valid JSON whose keys are exactly the style names above '
                      'and whose values are the rewritten sentences. No labels, no explanation.',
                },
                <String, String>{'role': 'user', 'content': source},
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        debugPrint('[ALT-STYLE] status=${response.statusCode}');
        return <String, String>{};
      }
      final content = jsonDecode(utf8.decode(response.bodyBytes))['choices'][0]
              ['message']['content']
          .toString();
      final parsed = jsonDecode(content) as Map<String, dynamic>;
      final result = <String, String>{};
      for (final style in styles) {
        final line = parsed[style]?.toString().trim() ?? '';
        if (line.isNotEmpty) result[style] = line;
      }
      return result;
    } catch (e) {
      debugPrint('[ALT-STYLE] failed: $e');
      return <String, String>{};
    }
  }

  // 📦 [Box 17-B-2: 다른 표현 보기 - 팝업]
  //   팝업 아무 곳이나 누르면 닫힌다(유저 요청). 바깥을 눌러도 닫힌다.
  void _showAltStylePopup(String baseText) {
    _resumeHistoryFromUserAction();
    final styles = _otherAiStyles();
    if (styles.isEmpty) return;
    final future = _fetchAltStyleSentences(baseText, styles);
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(dialogContext).pop(),
        child: Dialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          // 문장이 길면 4개가 화면을 넘긴다. 높이를 화면의 75%로 묶고
          // 안쪽을 스크롤시켜 마지막 스타일까지 볼 수 있게 한다.
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.75,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: FutureBuilder<Map<String, String>>(
                future: future,
                builder: (ctx, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const SizedBox(
                      height: 90,
                      child: Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF38BDF8)),
                      ),
                    );
                  }
                  final data = snapshot.data ?? <String, String>{};
                  // 맨 위는 지금 설정된 스타일과 원래 문장, 그 아래로 나머지.
                  final entries = <MapEntry<String, String>>[
                    MapEntry(_effectiveAiStyle(), baseText.trim()),
                    ...styles
                        .where(data.containsKey)
                        .map((s) => MapEntry(s, data[s]!)),
                  ];
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '다른 표현 보기',
                        style: TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (data.isEmpty)
                        const Text(
                          '표현을 불러오지 못했습니다. 다시 시도해 주세요.',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        )
                      else
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              // 스타일 이름 한 줄, 다음 줄에 문장.
                              children: entries
                                  .map(
                                    (e) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            e.key,
                                            style: const TextStyle(
                                              color: Color(0xFFB46CFF),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            e.value,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              height: 1.35,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                      const SizedBox(height: 2),
                      const Center(
                        child: Text(
                          '탭하면 닫힙니다',
                          style: TextStyle(color: Colors.white24, fontSize: 11),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 📦 [Box 17-A-2: 실전 튜터링 - 팝업 바텀시트]
  void _showTutoringPopup(String docId, String baseText) {
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
                    const Row(children: [
                      Icon(Icons.check_circle_outline,
                          color: Colors.greenAccent, size: 14),
                      SizedBox(width: 6),
                      Text("Correction Result",
                          style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
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
                      const Row(children: [
                        Icon(Icons.lightbulb_outline,
                            color: Colors.amber, size: 14),
                        SizedBox(width: 6),
                        Text("더 자연스러운 표현",
                            style: TextStyle(
                                color: Colors.amber,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
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

    if (_phase == ShadowingPhase.variantSelect) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Stack(children: [
          SafeArea(child: _buildVariantSelectScreen()),
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
                _buildPracticeTabBar(),
                // 🔙 P3 화면 안에는 닫기가 없었다. 탭 바 바로 밑에 한 줄을 둔다
                //   — 왼쪽 X는 고르는 자리로 돌아가고, 오른쪽 SR은 공부방으로
                //   나간다. P1·P2는 각자 헤더에 이미 X를 들고 있다.
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 16, 2),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        tooltip: '다시 고르기',
                        onPressed: _isStepExpandRoom
                            ? _backToStepExpandSelect
                            : _exitShadowing,
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

    if (_phase == ShadowingPhase.practicing) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: SafeArea(
          child: Column(children: [
            _buildTopBar(),
            _buildPracticeHeaderIndicator(), // 🆕 [P2-INDICATOR]
            _buildPracticeIconBar(),
            Expanded(
              child: Stack(children: [
                _buildShadowingPracticeBody(),
                _buildIdleOverlay(),
              ]),
            ),
            _buildPracticeControl(),
          ]),
        ),
      );
    }

    if (_phase == ShadowingPhase.reviewing) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Stack(children: [
          SafeArea(child: _buildReviewScreen()),
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

    if (_phase == ShadowingPhase.tutorPlay) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Stack(children: [
          SafeArea(child: _buildTutorScreen()),
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

    if (_phase == ShadowingPhase.part1Practice) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Stack(children: [
          SafeArea(child: _buildStepPracticeWithTabBar()),
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

    if (_phase == ShadowingPhase.part2Practice) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Stack(children: [
          SafeArea(child: _buildStepPracticeWithTabBar()),
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
                    final docs = snapshot.data!.docs;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _cachedDocs = docs;
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
              _phase == ShadowingPhase.practicing
                  ? "Shadowing  ${_currentChunkIdx + 1} / ${_chunks.length}"
                  : _displayRoomTitle(roomName),
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
                      color: Colors.amber,
                      size: 28,
                    ),
              tooltip: isPracticeMode ? "연습 종료" : "쉐도잉 연습 시작",
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

  // 📦 [Box 21: UI - 진행 아이콘바 (enum 비교)]
  Widget _buildPracticeIconBar() {
    final bool isUserActive =
        _phase == ShadowingPhase.practicing && _isListening;
    final bool isAIActive =
        _phase == ShadowingPhase.practicing && isPlaying && !_isListening;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 유저 아이콘 (좌)
          GestureDetector(
            onTap: _onUserIconTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isUserActive
                        ? Colors.greenAccent.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.05),
                    border: Border.all(
                      color: isUserActive ? Colors.greenAccent : Colors.white24,
                      width: isUserActive ? 2.5 : 1.0,
                    ),
                    boxShadow: isUserActive
                        ? [
                            BoxShadow(
                                color:
                                    Colors.greenAccent.withValues(alpha: 0.35),
                                blurRadius: 16,
                                spreadRadius: 2)
                          ]
                        : [],
                  ),
                  child: Icon(Icons.mic_rounded,
                      color: isUserActive ? Colors.greenAccent : Colors.white38,
                      size: 30),
                ),
                const SizedBox(height: 6),
                Text('You',
                    style: TextStyle(
                        color:
                            isUserActive ? Colors.greenAccent : Colors.white38,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                SizedBox(
                  height: 18,
                  child: isUserActive
                      ? const Icon(Icons.graphic_eq,
                          color: Colors.greenAccent, size: 14)
                      : null,
                ),
              ],
            ),
          ),

          // 중앙 청크 진행 표시
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "${_currentChunkIdx + 1} / ${_chunks.length}",
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                _isListening
                    ? "🎙 Recording..."
                    : isPlaying
                        ? "🎧 AI Playing"
                        : _chunks.isNotEmpty &&
                                _currentChunkIdx < _chunks.length &&
                                _chunks[_currentChunkIdx].isDone
                            ? "✅ Done"
                            : "Tap mic to record",
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),

          // AI 아이콘 (우)
          GestureDetector(
            onTap: _onAIIconTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isAIActive
                        ? Colors.amber.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.05),
                    border: Border.all(
                      color: isAIActive ? Colors.amber : Colors.white24,
                      width: isAIActive ? 2.5 : 1.0,
                    ),
                    boxShadow: isAIActive
                        ? [
                            BoxShadow(
                                color: Colors.amber.withValues(alpha: 0.35),
                                blurRadius: 16,
                                spreadRadius: 2)
                          ]
                        : [],
                  ),
                  child: Icon(Icons.volume_up_rounded,
                      color: isAIActive ? Colors.amber : Colors.white38,
                      size: 30),
                ),
                const SizedBox(height: 6),
                Text('AI',
                    style: TextStyle(
                        color: isAIActive ? Colors.amber : Colors.white38,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                SizedBox(
                  height: 18,
                  child: isAIActive
                      ? const Icon(Icons.volume_up,
                          color: Colors.amber, size: 14)
                      : null,
                ),
              ],
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
            Text('번역 중',
                style: TextStyle(
                    color: Colors.white38, fontSize: 11 * _fontScale)),
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
        // 모든 말풍선: 확장문장 제거 - \n\n 앞의 첫 대답만 표시 (Step Expand HOST 메시지 포함)
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

        Widget controlButtons = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: const Icon(Icons.play_circle,
                  color: Colors.amberAccent, size: 28),
              onPressed: () => _playMsgAudio(docs[index].id, translated),
              tooltip: "소리 듣기",
            ),
            const SizedBox(height: 4),
            _buildAppBtn(docs[index].id, translated),
            const SizedBox(height: 4),
            _buildAltStyleBtn(translated),
          ],
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

  // 📦 [Box 22-B: Variant 선택 화면]
  Widget _buildVariantSelectScreen() {
    if (_isStepExpandRoom) return _buildStepExpandSelectScreen();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: _exitShadowing,
              ),
              const Expanded(
                child: Text(
                  "어떤 문장으로 연습할까요?",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 32),

          // Expanded variant card
          GestureDetector(
            onTap: () => _startPracticeWithVariant(SentenceVariant.expanded),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2E1C),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: Colors.greenAccent.withValues(alpha: 0.5),
                    width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.trending_up,
                          color: Colors.greenAccent, size: 18),
                      SizedBox(width: 8),
                      Text("🌱 Polished",
                          style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _expandedSentence.isNotEmpty
                        ? _expandedSentence
                        : "(문장 없음)",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15 * _fontScale,
                        height: 1.5),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Polished variant card
          GestureDetector(
            onTap: _polishedSentence.isNotEmpty
                ? () => _startPracticeWithVariant(SentenceVariant.polished)
                : null,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _polishedSentence.isNotEmpty ? 1.0 : 0.4,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.5), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.amber, size: 18),
                        SizedBox(width: 8),
                        Text("✨ Polished",
                            style: TextStyle(
                                color: Colors.amber,
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _polishedSentence.isNotEmpty
                        ? Text(
                            _polishedSentence,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15 * _fontScale,
                                height: 1.5),
                          )
                        : _polishedLoadDone
                            ? const Text(
                                "Polished 문장이 없습니다.\n(세션에서 Polish 버튼을 눌러주세요)",
                                style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 13,
                                    height: 1.5),
                              )
                            : const Row(
                                children: [
                                  SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          color: Colors.amber, strokeWidth: 2)),
                                  SizedBox(width: 12),
                                  Text("불러오는 중...",
                                      style: TextStyle(
                                          color: Colors.white54, fontSize: 14)),
                                ],
                              ),
                  ],
                ),
              ),
            ),
          ),

          const Spacer(),
          TextButton(
            onPressed: _exitShadowing,
            child: const Text("취소",
                style: TextStyle(color: Colors.white38, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  // 🆕 [P2-INDICATOR] 청크 텍스트 색상 분기: 완료=회색, 현재=노란, 대기=흰색
  Color _chunkTextColor(int i) {
    if (i < _currentChunkIdx) return Colors.white38;
    if (i == _currentChunkIdx) return const Color(0xFFFFC107);
    return Colors.white;
  }

  // 🆕 [P2-INDICATOR] 상단 "👤 Practice 🤖" 턴 인디케이터
  Widget _buildPracticeHeaderIndicator() {
    final bool userActive = _isListening;
    final bool aiActive = _aiChunkPlaying;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 좌측: User 아이콘
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: userActive
                  ? Colors.greenAccent.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: userActive ? Colors.greenAccent : Colors.white24,
                width: userActive ? 2 : 1,
              ),
              boxShadow: userActive
                  ? [
                      BoxShadow(
                          color: Colors.greenAccent.withValues(alpha: 0.4),
                          blurRadius: 12,
                          spreadRadius: 2)
                    ]
                  : [],
            ),
            child: Text(
              "👤",
              style: TextStyle(
                  fontSize: 18,
                  color: userActive ? Colors.greenAccent : Colors.white38),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            "Practice",
            style: TextStyle(
              color: Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 10),
          // 우측: AI 아이콘
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: aiActive
                  ? Colors.blue.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: aiActive ? Colors.blue : Colors.white24,
                width: aiActive ? 2 : 1,
              ),
              boxShadow: aiActive
                  ? [
                      BoxShadow(
                          color: Colors.blue.withValues(alpha: 0.4),
                          blurRadius: 12,
                          spreadRadius: 2)
                    ]
                  : [],
            ),
            child: Text(
              "🤖",
              style: TextStyle(
                  fontSize: 18, color: aiActive ? Colors.blue : Colors.white38),
            ),
          ),
        ],
      ),
    );
  }

  // 📦 [Box 22-C: Shadowing 진행 화면 — 전체 청크 리스트 표시]
  Widget _buildShadowingPracticeBody() {
    if (_chunks.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.amber));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _chunks.length + 1,
      itemBuilder: (context, i) {
        if (i == _chunks.length) {
          return Container(
            height: 120,
            decoration: const BoxDecoration(color: Colors.transparent),
          );
        }
        final chunk = _chunks[i];
        final bool isCurrent = i == _currentChunkIdx;
        final bool isDone = chunk.isDone;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isCurrent ? const Color(0xFF1C1C1E) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isCurrent
                  ? (_isListening
                      ? Colors.greenAccent
                      : _aiChunkPlaying
                          ? Colors.blue
                          : Colors.white24)
                  : Colors.white12,
              width: isCurrent ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chunk.text,
                      style: TextStyle(
                        color: _chunkTextColor(i), // 🆕 [P2-INDICATOR]
                        fontSize: 18 * _fontScale,
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal,
                        height: 1.5,
                      ),
                    ),
                    _buildChunkKoLine(chunk), // 🆕 [KO-FRAG]
                    if (isCurrent) ...[
                      const SizedBox(height: 4),
                      Text(
                        _isListening
                            ? "🎙 Recording..."
                            : _aiChunkPlaying
                                ? "🎧 Listen carefully..."
                                : isDone
                                    ? "✅ Recorded — tap ▶ to replay"
                                    : "Tap 🎤 or ▶ to start",
                        style: TextStyle(
                          color: _isListening
                              ? Colors.greenAccent
                              : _aiChunkPlaying
                                  ? Colors.blue
                                  : Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 청크별 ▶ 아이콘 — _replayChunkAI 연결 [P2-REPLAY]
              GestureDetector(
                onTap: () => _replayChunkAI(i),
                child: Icon(
                  isDone
                      ? Icons.replay_rounded
                      : Icons.play_circle_outline_rounded,
                  color: isCurrent
                      ? (isDone ? Colors.greenAccent : Colors.amber)
                      : Colors.white24,
                  size: 22,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 📦 [Box 22-D: Review 화면]
  Widget _buildReviewScreen() {
    return Column(
      children: [
        // 헤더
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: _exitShadowing,
              ),
              const Expanded(
                child: Text(
                  "🎉 Practice Complete!",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),

        // 전체 재생 버튼들
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.volume_up, size: 16),
                  label: const Text("AI Voice"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.withValues(alpha: 0.15),
                    foregroundColor: Colors.amber,
                    side: const BorderSide(color: Colors.amber),
                  ),
                  onPressed: _playFullAI,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.person, size: 16),
                  label: const Text("My Voice"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent.withValues(alpha: 0.1),
                    foregroundColor: Colors.greenAccent,
                    side: const BorderSide(color: Colors.greenAccent),
                  ),
                  onPressed: _playFullUser,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // 청크별 리스트
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _chunks.length,
            itemBuilder: (context, i) {
              final chunk = _chunks[i];
              final bool hasUser = chunk.userRecordPath != null &&
                  chunk.userRecordPath!.isNotEmpty;
              final bool isCurrentUser =
                  _isPlayingFullUser && _fullUserPlayIdx == i;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isCurrentUser
                      ? Colors.greenAccent.withValues(alpha: 0.1)
                      : const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color:
                          isCurrentUser ? Colors.greenAccent : Colors.white12),
                ),
                child: Row(
                  children: [
                    Text(
                      "${i + 1}",
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            chunk.text,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14 * _fontScale,
                                height: 1.4),
                          ),
                          _buildChunkKoLine(chunk), // 🆕 [KO-FRAG]
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.volume_up,
                          color: Colors.amber, size: 20),
                      tooltip: "AI 듣기",
                      onPressed: () => _playChunkAI(i),
                    ),
                    if (hasUser)
                      IconButton(
                        icon: const Icon(Icons.person,
                            color: Colors.greenAccent, size: 20),
                        tooltip: "내 녹음",
                        onPressed: () => _playUserChunk(i),
                      )
                    else
                      const SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(
                          child: Icon(Icons.mic_off,
                              color: Colors.white24, size: 18),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),

        // 완료 버튼
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: const Color(0xFF121212),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              onPressed: _exitShadowing,
              child: const Text("완료",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }

  // 🆕 [TUTOR] Tutor 모드 화면
  Widget _buildTutorScreen() {
    return Column(
      children: [
        // 헤더
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const SizedBox(width: 48),
              const Expanded(
                child: Text(
                  "🎧 Tutor 모드",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: _exitShadowing,
              ),
            ],
          ),
        ),

        // 대화 목록
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _tutorLines.length + 1,
            itemBuilder: (context, i) {
              if (i == _tutorLines.length) {
                return Container(
                  height: 100,
                  decoration: const BoxDecoration(color: Colors.transparent),
                );
              }
              final line = _tutorLines[i];
              final bool isAi = (line['role'] as String) == 'HOST';
              final bool isCurrent = _tutorCurrentIdx == i;
              final Color highlightColor =
                  isAi ? Colors.blue : Colors.greenAccent;
              final text = line['text'] as String;

              return Align(
                alignment: isAi ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.93,
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? highlightColor.withValues(alpha: 0.15)
                        : const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isCurrent ? highlightColor : Colors.white12,
                        width: isCurrent ? 2 : 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCurrent
                              ? highlightColor.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.05),
                          border: Border.all(
                              color:
                                  isCurrent ? highlightColor : Colors.white24,
                              width: isCurrent ? 2.5 : 1),
                        ),
                        child: Icon(
                          isAi ? Icons.volume_up_rounded : Icons.person_rounded,
                          color: isCurrent ? highlightColor : Colors.white38,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          text,
                          textAlign: isAi ? TextAlign.right : TextAlign.left,
                          style: TextStyle(
                              color: isCurrent ? Colors.white : Colors.white70,
                              fontSize: 15,
                              height: 1.5,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // 하단 제어 버튼
        Padding(
          padding: const EdgeInsets.all(16),
          child: _isTutorPlaying
              ? SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.stop_rounded, size: 20),
                    label: const Text("중지",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withValues(alpha: 0.8),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _stopTutorPlayback,
                  ),
                )
              : SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.replay_rounded, size: 20),
                    label: const Text("다시 재생",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: const Color(0xFF121212),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed:
                        _tutorLines.isNotEmpty ? _startTutorPlayback : null,
                  ),
                ),
        ),
      ],
    );
  }

  // 📦 [BOX-32: 역할 스왑 - 동적 판정 헬퍼]
  // 일반 History Practice는 HOST=사용자, SYSTEM=AI 기준으로 판정하고,
  // Step Expand P1/P2는 생성된 _tutorLines 구조(HOST=AI)를 유지한다.
  bool _lineRepresentsAi(Map<String, dynamic> line) {
    final role = line['role'] as String;
    if (_phase == ShadowingPhase.turnPractice) {
      return role == 'SYSTEM';
    }
    return role == 'HOST';
  }

  String _practiceVoiceForLine(Map<String, dynamic> line) =>
      _lineRepresentsAi(line)
          ? _historyPracticeAiVoice
          : _historyPracticeUserVoice;

  bool _isAiTurn(Map<String, dynamic> line) {
    final role = line['role'] as String;
    if (_phase == ShadowingPhase.turnPractice) {
      return _swapRoles ? role == 'HOST' : role == 'SYSTEM';
    }
    return role == 'HOST';
  }

  // 📦 [BOX-33: 유저 재녹음 핸들러]
  void _onTutorUserIconTap() {
    if (_tutorAwaitingStart || currentIndex >= _tutorLines.length) return;
    if (_phase == ShadowingPhase.part2Practice) return; // [P2-SHADOW]
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
  Future<void> _restartP2Practice() async {
    _shadowHighlightTimer?.cancel();
    _shadowAdvanceTimer?.cancel();
    await _stopShadowAiPlayback();
    if (!mounted || _phase != ShadowingPhase.part2Practice) return;
    setState(() {
      currentIndex = 0;
      _tutorCurrentIdx = 0;
      _tutorPlayingFullback = false;
      _tutorAwaitingStart = false;
      _morphPreparing = false;
      _morphPlaying = false;
      _p2ActiveChunkIndex = -1;
      _p2MorphDurationMs = 0;
    });
    // 목록을 맨 위로 되돌린다. ListView.builder는 화면 밖 아이템을 버리므로
    // 마지막 계단까지 내려간 상태에서는 `_practiceItemKeys[0]`의 context가
    // null이다. 그러면 `_scrollPracticeToIndex(0)`도 `_pinShadowLineToTop(0)`도
    // 조용히 아무것도 하지 않아, 소리만 처음으로 가고 화면은 끝에 남는다.
    // controller를 직접 0으로 보내면 아이템 0이 다시 만들어져 그 뒤 pin이 먹는다.
    if (_practiceScrollController.hasClients) {
      _practiceScrollController.jumpTo(0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _phase == ShadowingPhase.part2Practice) {
        _startTurnPractice();
      }
    });
  }

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
    if (_phase == ShadowingPhase.part2Practice) {
      return _buildP2ChunkLine(line, isCurrent, base);
    }
    return Text(text,
        textAlign: lineIsAi ? TextAlign.right : TextAlign.left, style: base);
  }

  List<P2Chunk> _p2ChunksForLine(Map<String, dynamic> line) {
    final mapped = line['p2Chunks'];
    if (mapped is List<P2Chunk> && mapped.isNotEmpty) return mapped;
    return fallbackP2Chunks((line['text'] ?? '').toString());
  }

  Color _p2ChunkAccent(P2Chunk chunk) {
    switch (chunk.type) {
      case 'evolved':
        return const Color(0xFF64B5F6);
      case 'new':
        return const Color(0xFF81C784);
      default:
        return Colors.white;
    }
  }

  Widget _buildP2ChunkLine(
      Map<String, dynamic> line, bool isCurrent, TextStyle base) {
    final chunks = _p2ChunksForLine(line);
    final active = isCurrent ? _p2ActiveChunkIndex : -1;
    final spans = <InlineSpan>[];
    for (var index = 0; index < chunks.length; index++) {
      final chunk = chunks[index];
      final accent = _p2ChunkAccent(chunk);
      final isActive = index == active;
      final isWaiting = active >= 0 && index > active;
      final backgroundAlpha = chunk.type == 'kept'
          ? (isActive ? 0.12 : 0.025)
          : isActive
              ? 0.30
              : isWaiting
                  ? 0.06
                  : 0.14;
      if (spans.isNotEmpty) spans.add(const TextSpan(text: ' '));
      spans.add(TextSpan(
        text: chunk.text,
        style: base.copyWith(
          color: isActive
              ? Colors.white
              : isWaiting
                  ? Colors.white54
                  : Colors.white.withValues(alpha: 0.88),
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
          backgroundColor: accent.withValues(alpha: backgroundAlpha),
        ),
      ));
    }
    return Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.left,
      style: base,
    );
  }

  Widget _buildTurnPracticeScreen() {
    final bool isAwaiting = _tutorAwaitingStart;
    final bool isComplete = currentIndex >= _tutorLines.length;
    final bool isP2Practice = _phase == ShadowingPhase.part2Practice;

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
                    // 🔙 [STEP-BACK] Step Expand 방에서는 방을 닫지 않고
                    //   P1/P2/P3 고르는 자리로 돌아간다.
                    onPressed: _isStepExpandRoom
                        ? _backToStepExpandSelect
                        : _exitShadowing,
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_phase != ShadowingPhase.part2Practice) ...[
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
                                      ? Colors.greenAccent
                                          .withValues(alpha: 0.15)
                                      : isAwaiting
                                          ? Colors.greenAccent
                                              .withValues(alpha: 0.08)
                                          : Colors.white
                                              .withValues(alpha: 0.04),
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
                        ],
                        // 📏 P1 라벨이 "Choose a Character"로 길어졌다. 양옆은
                        //   인물 아이콘이 잡고 있어 남는 폭이 좁고, 글꼴을
                        //   키워 둔 기기에서는 그대로 넘친다. 자리에 맞춰
                        //   줄여 언제나 한 줄로 보이게 한다.
                        Flexible(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _phase == ShadowingPhase.part2Practice &&
                                    isAwaiting &&
                                    !isComplete
                                ? _startP2Reading
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              child: AnimatedBuilder(
                                animation: _blinkController,
                                builder: (context, child) => Opacity(
                                  opacity:
                                      _phase == ShadowingPhase.part2Practice &&
                                              isAwaiting
                                          ? 0.35 + (_blinkOpacity.value * 0.65)
                                          : 1.0,
                                  child: child,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    isComplete
                                        ? "Practice 완료!"
                                        : (_phase ==
                                                ShadowingPhase.part1Practice
                                            ? "Choose a Character"
                                            : _phase ==
                                                    ShadowingPhase.part2Practice
                                                ? "See How It Grows"
                                                : "Practice"),
                                    maxLines: 1,
                                    style: TextStyle(
                                        color: _phase ==
                                                    ShadowingPhase
                                                        .part2Practice &&
                                                isAwaiting
                                            ? Colors.lightBlueAccent
                                            : Colors.white54,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.0),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_phase != ShadowingPhase.part2Practice) ...[
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
                                          : Colors.white
                                              .withValues(alpha: 0.04),
                                  border: Border.all(
                                    color: _tutorAiSpeaking
                                        ? Colors.blue
                                        : isAwaiting
                                            ? Colors.blue
                                                .withValues(alpha: 0.65)
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
                  final bool isP2 = _phase == ShadowingPhase.part2Practice;
                  final double growth = _tutorLines.length <= 1
                      ? 1.0
                      : i / (_tutorLines.length - 1);
                  final Color p2BorderColor = Color.lerp(
                    const Color(0xFFB9E3F8),
                    const Color(0xFF1565C0),
                    growth,
                  )!;

                  return Align(
                    alignment: _phase == ShadowingPhase.part2Practice
                        ? Alignment.center
                        : lineIsAi
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                    child: AnimatedOpacity(
                      key: key,
                      duration: const Duration(milliseconds: 300),
                      opacity: isPast ? 0.45 : 1.0,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width *
                              (_phase == ShadowingPhase.part2Practice
                                  ? 0.94
                                  : 0.80),
                        ),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isP2
                              ? p2BorderColor.withValues(
                                  alpha: isCurrent ? 0.10 : 0.035)
                              : isCurrent
                                  ? roleColor.withValues(alpha: 0.1)
                                  : const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isP2
                                ? p2BorderColor.withValues(
                                    alpha: isCurrent ? 0.95 : 0.58)
                                : isCurrent
                                    ? roleColor
                                    : Colors.white12,
                            width: isCurrent ? 2 : (isP2 ? 1.2 : 1),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_phase != ShadowingPhase.part2Practice) ...[
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
                                    color:
                                        isCurrent ? roleColor : Colors.white24,
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
                            ],
                            Flexible(
                              child: Column(
                                crossAxisAlignment: lineIsAi
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  _buildPracticeLineText(
                                      line, isCurrent, lineIsAi),
                                  if (isCurrent &&
                                      !lineIsAi &&
                                      _isAutoRecording) ...[
                                    const SizedBox(height: 6),
                                    Row(children: const [
                                      Icon(Icons.graphic_eq,
                                          color: Colors.greenAccent, size: 15),
                                      SizedBox(width: 5),
                                      Text("녹음 중...",
                                          style: TextStyle(
                                              color: Colors.greenAccent,
                                              fontSize: 11)),
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
                                      Text("끝까지 다시 읽어 주세요 🎙",
                                          style: TextStyle(
                                              color: Colors.orange,
                                              fontSize: 11)),
                                    ]),
                                  ],
                                  if (isCurrent && lineIsAi && isPlaying) ...[
                                    const SizedBox(height: 6),
                                    Row(children: const [
                                      Icon(Icons.volume_up,
                                          color: Colors.amber, size: 15),
                                      SizedBox(width: 5),
                                      Text("AI 재생 중...",
                                          style: TextStyle(
                                              color: Colors.amber,
                                              fontSize: 11)),
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
                        if (!isP2Practice) ...[
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
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.blue.withValues(alpha: 0.15),
                                foregroundColor: Colors.blue,
                                side: const BorderSide(color: Colors.blue),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: _startTurnPracticeFullback,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
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
                            onPressed: isP2Practice
                                ? () => unawaited(_restartP2Practice())
                                : () {
                                    audioPlayer.stop();
                                    _tutorAudioPlayer?.stop();
                                    for (final l in _tutorLines) {
                                      // 🆕 [BOX-34-CLEANUP] 실제 파일도 삭제
                                      final rp =
                                          l['user_record_path'] as String?;
                                      if (rp != null && rp.isNotEmpty) {
                                        File(rp).delete().ignore();
                                      }
                                      l.remove('user_record_path');
                                      l.remove('ai_audio_bytes');
                                    }
                                    if (mounted) {
                                      setState(() {
                                        currentIndex = 0;
                                        _tutorCurrentIdx = 0;
                                        _tutorPlayingFullback = false;
                                        _tutorAwaitingStart = true;
                                        _swapRoles = false;
                                        _tutorAiSpeaking = false;
                                        _tutorUserRecording = false;
                                      });
                                      WidgetsBinding.instance
                                          .addPostFrameCallback(
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

            // 🔒 Tutor history modes do not generate Expanded Sentence here.
            if (!_blocksHistoryExpandedSentence(_cachedRoomMode) &&
                _phase != ShadowingPhase.part1Practice &&
                _phase != ShadowingPhase.part2Practice)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  6,
                  20,
                  (isComplete ? 6 : 12) +
                      MediaQuery.of(context).viewPadding.bottom,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _isBuildingExpand
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.amber),
                          )
                        : const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: Text(
                      _isBuildingExpand ? "불러오는 중..." : "Expanded Sentence",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.withValues(alpha: 0.12),
                      foregroundColor: Colors.amber,
                      side: const BorderSide(color: Colors.amber),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed:
                        _isBuildingExpand ? null : _buildExpandFromConversation,
                  ),
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

  void _onPolishedUnitTapped(int idx) {
    if (_isListening) _stopDeepgramListening();
    audioPlayer.stop();
    if (mounted) {
      setState(() {
        _polishedUnitIdx = idx;
        _polishedUnitAIPlaying = false;
      });
    }
    _playPolishedUnit(idx);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollCurrentPolishedUnitToCenter();
    });
  }

  // [P2-TELEPROMPTER] 긴 대사는 시작할 때 반드시 첫 줄부터 보이게 한다.
  void _pinShadowLineToTop(int idx) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _phase != ShadowingPhase.part2Practice ||
          currentIndex != idx) {
        return;
      }
      final context = _practiceItemKeys[idx]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.0,
        duration: Duration.zero,
      );
    });
  }

  // [P2-TELEPROMPTER] 단어 하이라이트 총시간에 맞춰 마지막 줄까지 선형 이동한다.
  void _startShadowLineGlide(int idx, List<String> words) {
    final durationMs = words.fold<int>(
      0,
      (total, word) => total + _shadowWordDuration(word),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _phase != ShadowingPhase.part2Practice ||
          currentIndex != idx ||
          !_practiceScrollController.hasClients) {
        return;
      }
      final context = _practiceItemKeys[idx]?.currentContext;
      final renderObject = context?.findRenderObject();
      if (context == null || renderObject is! RenderBox) return;
      final viewportHeight =
          _practiceScrollController.position.viewportDimension;
      if (renderObject.size.height <= viewportHeight * 0.9) return;
      Scrollable.ensureVisible(
        context,
        alignment: 1.0,
        duration: Duration(milliseconds: durationMs.clamp(1200, 60000)),
        curve: Curves.linear,
      );
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
        alignment: _phase == ShadowingPhase.part2Practice ? 0.0 : 0.4,
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

  // Polished 현재 단위가 화면 중앙에 오도록 스크롤
  void _scrollCurrentPolishedUnitToCenter() {
    if (_polishedUnitIdx < 0) return;
    final key = _polishedItemKeys[_polishedUnitIdx];
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
    final double targetOffset = (_polishedUnitIdx * estimatedItemHeight) -
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
  Future<void> _playPolishedUnit(int idx) async {
    _resumeHistoryFromUserAction();
    if (!mounted || idx >= _polishedUnits.length) return;
    if (mounted) setState(() => _polishedUnitAIPlaying = true);
    final text = _polishedUnits[idx];
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
      if (mounted) setState(() => _polishedUnitAIPlaying = false);
    }
  }

  // 🆕 [KO-FRAG] 청크 한국어 직독 조각 한 줄 — _langDisplayMode 0(영+한)·2(한)에서만 표시
  Widget _buildChunkKoLine(PracticeChunk chunk) {
    if (_langDisplayMode == 1) return const SizedBox.shrink();
    final ko = chunk.korean;
    if (ko == null || ko.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(
        ko,
        style: TextStyle(
          color: Colors.white54,
          fontSize: 12 * _fontScale,
          height: 1.3,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // 🎤 [P3-SPEAK] Speaking Practice
  //
  //   P2가 "문장이 자라는 것을 보고 듣는" 자리라면, P3는 **최종 완성문장을
  //   실제로 입에 붙이는** 자리다.
  //
  //     Stage 1 Breath Echoing — 호흡 하나씩 듣고 혼자 따라 말하기
  //     Stage 2 Full Echo      — 전체를 듣고, 끝난 뒤 혼자 전체 말하기
  //     Stage 3 Full Shadow    — 호흡 사이만 벌린 AI와 **동시에** 말하기
  //     Stage 4 Compare        — AI / ECHO / SHADOW 각각 다시 듣기
  //
  //   ⚠️ **TTS는 문장당 딱 한 번이다.** 네 단계가 전부 그 PCM 하나에서 나온다.
  //   Shadow를 열 번 반복해도 API 호출은 늘지 않는다.
  // ══════════════════════════════════════════════════════════════════

  /// P3가 대상으로 삼는 최종 문장. 완성/세련 두 문장을 각각 같은
  /// Speaking Practice 흐름으로 열 수 있다.
  String get _p3TargetSentence {
    final preferred = _selectedVariant == SentenceVariant.polished
        ? _polishedSentence.trim()
        : _expandedSentence.trim();
    if (preferred.isNotEmpty) return preferred;
    return _selectedVariant == SentenceVariant.polished
        ? _expandedSentence.trim()
        : _polishedSentence.trim();
  }

  bool _p3VariantAvailable(SentenceVariant variant) =>
      (variant == SentenceVariant.polished
              ? _polishedSentence
              : _expandedSentence)
          .trim()
          .isNotEmpty;

  String _p3VariantLabel(SentenceVariant variant) =>
      variant == SentenceVariant.polished
          ? 'Polished Sentence'
          : 'Complete Sentence';

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

  bool get _p3Busy =>
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

  /// 📜 [P3-READ-SCROLL] 읽는 진행만큼 본문을 올린다. 0이면 첫 줄, 1이면
  /// 마지막 줄이다.
  ///
  /// 글자와 소리를 잇는 지도는 없다 — 호흡 경계는 PCM에서 나온 값이라 몇 번째
  /// 글자인지 모른다. 그래서 진행률로만 민다. 다 보이는 짧은 문장이면
  /// maxScrollExtent가 0이라 아무 일도 하지 않는다.
  void _p3ScrollSentenceTo(double progress) {
    if (_p3AutoScrollBlocked) return;
    final c = _p3SentenceScrollController;
    if (!c.hasClients) return;
    final double max = c.position.maxScrollExtent;
    if (max <= 0) return;
    final double target = max * progress.clamp(0.0, 1.0);
    if ((target - c.offset).abs() < 6) return;
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
  Future<void> _selectP3Variant(SentenceVariant variant) async {
    if (!_p3VariantAvailable(variant) || _p3Busy) return;
    final bool wasStarted = _p3Stage != P3Stage.idle;
    if (_selectedVariant == variant && !wasStarted) return;
    await _stopP3Shadowing(resetSelection: true);
    if (!mounted || _phase != ShadowingPhase.chunkPractice) return;
    setState(() {
      _selectedVariant = variant;
      _p3Stage = P3Stage.idle;
      _p3Error = null;
      _p3UserSpeaking = false;
    });
    if (wasStarted) await _startP3Speaking();
  }

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
  /// ⚠️ P2와 달리 **Morph 강조 지시문을 넣지 않는다.** 최종 문장을 특정 단어만
  /// 도드라진 상태로 익히면 안 된다.
  Future<void> _startP3Speaking() async {
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
      // 본문은 첫 줄부터 다시 읽는다.
      if (_p3SentenceScrollController.hasClients) {
        _p3SentenceScrollController.jumpTo(0);
      }
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

  /// P3 원본 PCM. **Morph 강조가 없는 순수 Smooth Jazz**라 P2 캐시와 키가
  /// 다르다(P2는 `_m{ranges}`가 붙는다).
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
          _p3ScrollSentenceTo(total <= 1 ? 0 : index / (total - 1));
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
            _p3ScrollSentenceTo(pos.inMilliseconds / expectedMs);
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
            _buildP3VariantPicker(showPreview: false),
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
                style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 12),
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
                  _buildP3CompareRow(),
                  const SizedBox(height: 12),
                  // 맨 밑 정지 — 연습을 접고 첫 화면으로 돌아간다.
                  _p3SecondaryButton(
                    '■ Stop',
                    () => unawaited(_stopP3AndReturnToMenu()),
                  ),
                  // 연습칸이 화면 맨 위까지 올라갈 수 있으려면 아래에 여백이
                  // 있어야 한다. 없으면 스크롤이 끝에 걸려 메뉴가 안 밀린다.
                  SizedBox(height: MediaQuery.of(context).size.height * 0.55),
                ],
              ),
          ],
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
          // 📜 [P3-READ-SCROLL] 긴 문장은 화면 아래로 넘어가 뒷부분을 못 봤다.
          //    칸 높이를 화면의 42%로 묶고, 그 안에서 읽는 진행만큼 올린다.
          //    손으로 스크롤하면 이번 회차는 자동으로 움직이지 않는다.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.42,
            ),
            child: NotificationListener<ScrollStartNotification>(
              onNotification: (notification) {
                if (notification.dragDetails != null) {
                  _p3AutoScrollBlocked = true;
                }
                return false;
              },
              child: SingleChildScrollView(
                controller: _p3SentenceScrollController,
                physics: const ClampingScrollPhysics(),
                // 🚫 본문은 크기도 굵기도 그대로다 — 읽는 중에 글자가 조금이라도
                //    움직이면 눈이 줄을 놓친다. 내 차례라는 신호는 색만 얹는다.
                child: Text(
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
              ),
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
    final selected = _selectedVariant == variant;
    final sentence = (variant == SentenceVariant.polished
            ? _polishedSentence
            : _expandedSentence)
        .trim();
    return InkWell(
      onTap: available && !_p3Busy
          ? () => unawaited(_selectP3Variant(variant))
          : null,
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
                  color: available
                      ? (selected ? _p3ShadowingAccentColor : Colors.white38)
                      : Colors.white12,
                  size: 17,
                ),
                const SizedBox(width: 7),
                Text(
                  _p3VariantLabel(variant),
                  style: TextStyle(
                    color: available
                        ? (selected ? Colors.white : Colors.white60)
                        : Colors.white24,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (showPreview) ...[
              const SizedBox(height: 6),
              Text(
                available ? sentence : 'Sentence unavailable',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: available ? Colors.white54 : Colors.white24,
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
        height: 40,
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

  Widget _p3PrimaryButton(String label, VoidCallback? onTap) => SizedBox(
        height: 48,
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

  Widget _p3SecondaryButton(String label, VoidCallback? onTap) => SizedBox(
        height: 40,
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

  // ============================================================================
  // 📦 [Box 11-D: Step Expand Practice 1 & 2 엔진]
  // ============================================================================

  /// messages 서브컬렉션 docs → _stepExpandTurns 파싱
  ///
  /// 한 턴은 **유저가 먼저 말하고 AI가 받는다**. 대화방이 저장하는 순서도
  /// `[HOST, SYSTEM]`이므로 HOST를 열고 뒤따르는 SYSTEM으로 닫는다.
  /// 예전에는 SYSTEM을 먼저 받아 두고 **뒤에 오는** HOST와 짝지었다. 그러면
  /// 짝지을 AI가 앞에 없는 **첫 유저 발화(씨앗)가 통째로 버려지고**, 연습이
  /// AI 질문부터 시작했다. 마지막 턴은 AI가 답하지 않으므로(`aiText` 빈 값)
  /// 짝이 없는 채로 닫는다.
  List<Map<String, dynamic>> _parseStepExpandTurns(
      List<DocumentSnapshot> docs) {
    final turns = <Map<String, dynamic>>[];
    Map<String, dynamic>? openTurn;
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final role = (data['role'] as String?) ?? '';
      final translatedText = (data['translated_text'] as String?) ?? '';
      final originalText = (data['original_text'] as String?) ?? '';
      final text = translatedText.isNotEmpty ? translatedText : originalText;
      if (role == 'HOST') {
        // AI 답 없이 유저 발화가 연달아 오면 앞 턴을 그대로 닫는다.
        if (openTurn != null) turns.add(openTurn);
        // 🌱 [EXPAND-LADDER] part2는 part1과 **같은 언어**여야 한다. part1이
        //   배울글(`translated_text`)이면 누적 문장도 배울글 쪽을 쓴다.
        //   배울글이 아직 안 만들어졌으면 빈 값으로 두고 아래에서 part1으로
        //   폴백시킨다 — 원어를 끼워 넣으면 P2에 한국어 줄이 섞인다.
        final expandedField = (translatedText.isNotEmpty
                ? (data['expanded_translated'] as String?)
                : (data['expanded_sentence'] as String?)) ??
            '';
        final parts = text.split('\n\n');
        final part1 = parts[0].trim();
        String part2;
        if (expandedField.isNotEmpty) {
          part2 = expandedField.trim();
        } else {
          part2 = parts.length >= 2 ? parts.sublist(1).join('\n\n').trim() : '';
        }
        openTurn = <String, dynamic>{
          'aiText': '',
          'part1': part1,
          'part2': part2,
          'p2Chunks': parseP2Chunks(
            data['p2_chunks'],
            part2,
            part1Text: part1,
          ),
        };
      } else if (role == 'SYSTEM' && openTurn != null) {
        openTurn['aiText'] = text.trim();
        turns.add(openTurn);
        openTurn = null;
      }
    }
    if (openTurn != null) turns.add(openTurn);
    return turns;
  }

  Future<void> _startPart1Practice() async {
    if (_stepExpandTurns.isEmpty) return;
    final lines = <Map<String, dynamic>>[];
    // 유저가 먼저 말하고 AI가 받는다 — 대화방에서 실제로 오간 순서다.
    for (final turn in _stepExpandTurns) {
      final userText = (turn['part1'] as String).trim();
      if (userText.isNotEmpty) {
        lines.add({'role': 'USER', 'text': userText});
      }
      // 마지막 턴은 AI가 답하지 않는다. 빈 말풍선을 만들지 않는다.
      final aiText = (turn['aiText'] as String).trim();
      if (aiText.isNotEmpty) {
        lines.add({'role': 'HOST', 'text': aiText});
      }
    }
    if (mounted) {
      setState(() {
        _phase = ShadowingPhase.part1Practice;
        _tutorLines = lines;
        currentIndex = 0;
        _tutorCurrentIdx = 0;
        _isAutoRecording = false;
        _tutorAwaitingStart = true;
        _swapRoles = false;
        _tutorAiSpeaking = false;
        _tutorUserRecording = false;
        _tutorPlayingFullback = false;
        _showRetryHint = false;
      });
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _showRoleSelectBubble());
    }
  }

  Future<void> _startPart2Practice() async {
    if (_stepExpandTurns.isEmpty) return;
    final lines = <Map<String, dynamic>>[];
    final totalTurns = _stepExpandTurns.length;
    // 🪜 [P2-LADDER] P2는 **유저 말이 자라는 것만** 본다. AI 질문은 넣지
    //   않는다 — 대화를 다시 듣는 자리가 아니라 한 문장이 1계단에서 4계단으로
    //   길어지는 것을 몸에 붙이는 자리다(P1이 대화를 맡는다).
    //   마지막 턴의 누적 문장은 완성문장 그 자체라 빼 둔다 — 그건 P3 몫이다.
    for (int i = 0; i < totalTurns - 1; i++) {
      final turn = _stepExpandTurns[i];
      final part2 = (turn['part2'] as String).isNotEmpty
          ? turn['part2'] as String
          : turn['part1'] as String;
      if (part2.trim().isNotEmpty) {
        final mapped = turn['p2Chunks'];
        lines.add(<String, dynamic>{
          'role': 'USER',
          'text': part2,
          'part1': (turn['part1'] ?? '').toString().trim(),
          'p2Chunks':
              mapped is List<P2Chunk> ? mapped : fallbackP2Chunks(part2),
        });
      }
    }
    if (mounted) {
      setState(() {
        _phase = ShadowingPhase.part2Practice;
        _tutorLines = lines;
        currentIndex = 0;
        _tutorCurrentIdx = 0;
        _isAutoRecording = false;
        _tutorAwaitingStart = true;
        _swapRoles = false;
        _tutorAiSpeaking = false;
        _tutorUserRecording = false;
        _tutorPlayingFullback = false;
        _showRetryHint = false;
        _shadowSpeed = 1.0;
      });
      _echoingOverlayTimer?.cancel();
      _shadowHighlightTimer?.cancel();
      _shadowAdvanceTimer?.cancel();
      _stopShadowAiPlayback();
      // 보이스 선택은 없앴다. See How It Grows를 누를 때 첫 문장을 연다.
    }
  }

  String _historyString(Map<String, dynamic>? data, String key) {
    return (data?[key] ?? '').toString().trim();
  }

  String _normalizeHistoryMode(String mode) {
    return mode.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
  }

  bool _blocksHistoryExpandedSentence(String mode) {
    final normalized = _normalizeHistoryMode(mode);
    return normalized != 'step_expand';
  }

  // 🏷️ [모드 별칭 해석표 — 표시명이 바뀔 때 여기만 한 줄씩 추가한다]
  //   저장 id는 절대 바꾸지 않는다. 이미 저장된 문서가 미분류로 떨어진다.
  //     free_talk   ← 표시명 Free Talk → Anyone → Circle Talk 로 변천
  //     roleplay    ← 표시명 Scenario Talk (room_name은 "Roleplay Mode" 유지)
  //     step_expand ← 표시명 Step Expand
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
    if (room == 'Step.Ex Mode' || room == 'Step Expand Mode') {
      return 'step_expand';
    }
    return '';
  }

  /// 원문만 저장해 두고 타겟 문장은 **히스토리에서 처음 열 때 만드는** 모드들.
  ///
  /// Duo는 두 방식이 한 컬렉션에 섞인다. 만능 통역 줄은 대화 중에 이미
  /// `translated_text`가 채워져 있어 생성 대상에서 자동으로 빠지고(호출부가
  /// 비어 있는 줄만 고른다), 직접 대화 줄만 여기서 타겟을 얻는다.
  bool get _usesDeferredHistoryTargets {
    final mode = _inferHistoryMode(_cachedRoomData);
    return mode == 'free_talk' ||
        mode == 'roleplay' ||
        mode == 'step_expand' ||
        mode == 'duo';
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

  bool _mentionsGenericAiPartner(String sentence) {
    return RegExp(r'\b(the\s+AI|AI|assistant|chatbot|bot)\b',
            caseSensitive: false)
        .hasMatch(sentence);
  }

  bool _canUseCachedNamedPartnerExpand(
    Map<String, dynamic>? data,
    String expanded,
    String polished,
    Map<String, String> labels,
  ) {
    // 🆕 [HANGUL-GUARD] 캐시된 확장/세련문장에 한글이 섞여 있으면 거부 → 재생성 유도
    final hangul = RegExp(r'[가-힣ᄀ-ᇿ㄰-㆏]');
    if (hangul.hasMatch('$expanded $polished')) return false;
    final mode = labels['mode'] ?? '';
    if (mode != 'clone' && mode != 'roleplay') return expanded.isNotEmpty;
    if (_historyString(data, 'expand_schema_version') != 'named_partner_v1') {
      return false;
    }
    if (_historyString(data, 'expand_partner_type') != mode) return false;
    final savedPartner = _historyString(data, 'expand_partner_name');
    if (savedPartner.isNotEmpty && savedPartner != labels['partnerLabel']) {
      return false;
    }
    if (_mentionsGenericAiPartner('$expanded $polished')) return false;
    return expanded.isNotEmpty;
  }

  Future<String?> _generateExpandedFromConversation(
    String transcript, {
    String userLabel = 'User',
    String partnerLabel = 'AI',
    String mode = '',
    String situation = '',
  }) async {
    if (_apiKey.isEmpty || transcript.trim().isEmpty) return null;
    try {
      final safeUserLabel =
          userLabel.trim().isNotEmpty ? userLabel.trim() : 'the user';
      final safePartnerLabel =
          partnerLabel.trim().isNotEmpty ? partnerLabel.trim() : 'the partner';
      final modeLine = mode == 'clone'
          ? 'For clone mode: conversation is between $safeUserLabel and $safePartnerLabel, a named clone/persona.'
          : mode == 'roleplay'
              ? 'For roleplay mode: conversation is between $safeUserLabel and $safePartnerLabel, a roleplay character.'
              : 'The transcript labels identify the participants.';
      final situationLine = situation.trim().isNotEmpty
          ? 'Situation: ${situation.trim()}. Use it only if supported by the transcript.'
          : '';
      final sysPrompt = """You are an English speaking coach.
You are given a short conversation transcript.
$modeLine
$safePartnerLabel is not AI.
$situationLine
Your job: compose ONE long, natural English sentence that synthesizes the overall
content and gist of the WHOLE conversation.

[RULES]
- Never call $safePartnerLabel AI, assistant, chatbot, or bot.
- Use $safePartnerLabel or a natural role phrase when referring to the partner.
- If any name, role label, or situation appears in Korean, render it in natural English (translate role or description phrases to their English equivalent; romanize real personal names). Never copy Korean text into the sentence.
- The final sentence must be 100% English and must NOT contain any Korean (Hangul) characters.
- It must be ONE single sentence (do not split it into multiple sentences).
- Keep it 25–40 words.
- Build it from about 5 meaning units joined with varied grammatical connectives
  (because, so, while, which, after, even though, and, etc.).
- Each meaning unit should be speakable in one breath, usually 5–7 words.
- Use commas or natural connectors to make breath groups clear.
- Do not create a sentence with one very long clause.
- Natural, speakable rhythm — common spoken English only.
- Capture the overall situation/idea of the conversation, not just one line.
- Common everyday vocabulary only. Do not add facts not in the transcript.
- Output exactly ONE sentence. No quotes, no prefixes, no explanation.""";
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'model': 'gpt-4o-mini',
              'temperature': 0.2,
              'max_tokens': 250,
              'messages': [
                {'role': 'system', 'content': sysPrompt},
                {
                  'role': 'user',
                  'content':
                      "Conversation:\n$transcript\n\nOne synthesized sentence:"
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      String s =
          ((body['choices'] as List).first['message']['content'] as String)
              .trim();
      if (s.startsWith('"') && s.endsWith('"')) {
        s = s.substring(1, s.length - 1);
      }
      return s.isEmpty ? null : s;
    } catch (e) {
      debugPrint("[generateExpandedFromConversation] $e");
      return null;
    }
  }

  // 🆕 [EXPAND-FROM-CHAT] 확장문장 → 쉽고 세련된 한 문장 (StepExpandBrain.polishSentence 동일 로직 복제)
  Future<String?> _polishExpandedSentence(
    String originalSentence, {
    String partnerLabel = 'the partner',
  }) async {
    if (_apiKey.isEmpty || originalSentence.trim().isEmpty) return null;
    try {
      final safePartnerLabel =
          partnerLabel.trim().isNotEmpty ? partnerLabel.trim() : 'the partner';
      final sysPrompt = """You are an English speaking coach.
The user has built a long English sentence through step-by-step expansion.
Your job: Rewrite it as ONE "easy but elegant" spoken English sentence.

[GOALS]
- Natural spoken rhythm (not written/academic)
- Common vocabulary (no SAT words, no bookish phrases)
- Smooth flow (pause-friendly, commas for breath)
- Same meaning as the original (do not add new facts)
- Slightly more elegant/polished than the original
- Easier to pronounce and say out loud
- Render every participant name, clone name, role label, and situation in English (translate role or description phrases; romanize real personal names). Never keep Korean text.
- The final sentence must be 100% English and must NOT contain any Korean (Hangul) characters.
- Do not replace $safePartnerLabel with AI, assistant, chatbot, or bot.

[AVOID]
- Big academic words
- Formal written phrases
- Complex nested clauses that are hard to speak
- Adding information not in the original

[OUTPUT]
- Exactly ONE sentence.
- No explanation, no quotes, no prefixes.
- Just the polished sentence.""";
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'model': 'gpt-4o-mini',
              'temperature': 0.2,
              'max_tokens': 150,
              'messages': [
                {'role': 'system', 'content': sysPrompt},
                {
                  'role': 'user',
                  'content':
                      'Original sentence:\n$originalSentence\n\nPolished version:'
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return originalSentence;
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      String polished =
          ((body['choices'] as List).first['message']['content'] as String)
              .trim();
      if (polished.startsWith('"') && polished.endsWith('"')) {
        polished = polished.substring(1, polished.length - 1);
      }
      return polished.isEmpty ? originalSentence : polished;
    } catch (e) {
      debugPrint("[polishExpandedSentence] $e");
      return originalSentence;
    }
  }

  // 🆕 [EXPAND-FROM-CHAT v2] 저장된 expanded/polished 우선 → 없으면 전체 대화로 생성+캐시 → P3 이동
  Future<void> _buildExpandFromConversation() async {
    if (_isBuildingExpand) return;
    if (mounted) setState(() => _isBuildingExpand = true);
    try {
      audioPlayer.stop();
      _stopAutoVADRecording();

      // 1순위: 방 문서에 이미 저장된 expanded/polished (+ mode/room_name 확보)
      String expanded = "";
      String polished = "";
      String existingMode = "";
      String roomName = "";
      Map<String, dynamic>? historyData;
      Map<String, String> labels = {
        'mode': '',
        'userLabel': 'User',
        'partnerLabel': 'AI',
        'partnerType': '',
        'situation': '',
      };
      try {
        final snap = await widget.historyDoc.get();
        final d = snap.data() as Map<String, dynamic>?;
        historyData = d;
        expanded = (d?['expanded_sentence'] as String?)?.trim() ?? "";
        polished = (d?['polished_sentence'] as String?)?.trim() ?? "";
        existingMode = _inferHistoryMode(d);
        roomName = (d?['room_name'] as String?)?.trim() ?? "";
        labels = await _resolveHistoryExpandLabels(d);
      } catch (e) {
        debugPrint("[buildExpand] doc fetch $e");
      }
      if (!mounted) return;

      if (_blocksHistoryExpandedSentence(existingMode)) {
        if (mounted) setState(() => _isBuildingExpand = false);
        return;
      }

      if (!_canUseCachedNamedPartnerExpand(
          historyData, expanded, polished, labels)) {
        expanded = "";
        polished = "";
      }

      // 2순위(fallback): 저장값 없으면 전체 대화로 즉석 생성 후 캐시
      if (expanded.isEmpty) {
        if (_apiKey.isEmpty) {
          setState(() => _isBuildingExpand = false);
          _showRoomEntryToast("API 키가 없어 생성할 수 없습니다");
          return;
        }
        final transcript = _tutorLines
            .map((l) {
              final t = (l['text'] as String? ?? '').trim();
              if (t.isEmpty) return null;
              final role = (l['role'] as String?) ?? '';
              final namedMode =
                  labels['mode'] == 'clone' || labels['mode'] == 'roleplay';
              final who = namedMode
                  ? (role == 'SYSTEM'
                      ? labels['partnerLabel']!
                      : labels['userLabel']!)
                  : (role == 'HOST' ? 'AI' : 'User');
              return "$who: $t";
            })
            .whereType<String>()
            .join("\n");
        if (transcript.isEmpty) {
          setState(() => _isBuildingExpand = false);
          _showRoomEntryToast("연습할 대화가 없습니다");
          return;
        }
        final gen = await _generateExpandedFromConversation(
          transcript,
          userLabel: labels['userLabel']!,
          partnerLabel: labels['partnerLabel']!,
          mode: labels['mode']!,
          situation: labels['situation']!,
        );
        if (!mounted) return;
        if (gen == null || gen.isEmpty) {
          setState(() => _isBuildingExpand = false);
          _showRoomEntryToast("확장문장 생성 실패");
          return;
        }
        expanded = gen;
        final pol = await _polishExpandedSentence(
          expanded,
          partnerLabel: labels['partnerLabel']!,
        );
        if (!mounted) return;
        polished = (pol != null && pol.trim().isNotEmpty) ? pol.trim() : "";

        // 캐시 저장 — has_practice + mode stamp(없으면 room_name으로 추론)로
        // 재입장 시 라우터가 expanded만 있는 모호한 방을 Step Expand로 오인하지 않게 보장
        String stampMode = existingMode;
        if (stampMode.isEmpty) {
          if (roomName == "Clone Mode") {
            stampMode = "clone";
          } else if (roomName == "Roleplay Mode") {
            stampMode = "roleplay";
          } else {
            stampMode = "clone"; // 안전 기본값: step_expand만 아니면 Tutor로 라우팅됨
          }
        }
        try {
          await widget.historyDoc.update({
            'expanded_sentence': expanded,
            if (polished.isNotEmpty) 'polished_sentence': polished,
            'has_practice': true,
            'expand_source': 'fallback',
            'expand_generated_at': FieldValue.serverTimestamp(),
            'expand_user_label': labels['userLabel'],
            'expand_partner_name': labels['partnerLabel'],
            'expand_partner_type': labels['partnerType'],
            'expand_schema_version': 'named_partner_v1',
            if (existingMode.isEmpty) 'mode': stampMode,
          });
        } catch (e) {
          debugPrint("[buildExpand] cache write $e");
        }
        if (!mounted) return;
      }

      // P3 진입 준비
      _isStepExpandRoom = false;
      _expandedSentence = expanded;
      _polishedSentence = polished;
      _practicingPolished = false;
      _polishedUnits = [];
      _polishedUnitIdx = -1;

      setState(() => _isBuildingExpand = false);
      _goToChunkPractice();
    } catch (e) {
      debugPrint("[buildExpandFromConversation] $e");
      if (mounted) {
        setState(() => _isBuildingExpand = false);
        _showRoomEntryToast("오류: $e");
      }
    }
  }

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
        _selectedVariant = SentenceVariant.expanded;
        // 🎤 [P3-SPEAK] 새 세션으로 연다. 이전 녹음은 남기지 않는다 —
        //   AI 원본 TTS 캐시는 그대로 재사용된다.
        _p3Stage = P3Stage.idle;
        _p3Error = null;
        _p3UserSpeaking = false;
      });
      unawaited(_stopP3Shadowing(resetSelection: true));
    }
  }

  void _switchToPractice(int practiceNum) {
    if (!mounted) return;
    _stopAutoVADRecording();
    audioPlayer.stop();
    _shadowHighlightTimer?.cancel(); // [P2-SHADOW]
    _shadowAdvanceTimer?.cancel(); // [P2-SHADOW]
    _stopShadowAiPlayback(); // [P2-SHADOW-AI]
    unawaited(_stopP3Shadowing(resetSelection: true));
    if (practiceNum == 1) {
      _startPart1Practice();
    } else if (practiceNum == 2) {
      _startPart2Practice();
    } else {
      _goToChunkPractice();
    }
  }

  // ============================================================================
  // 📦 [Box 22-E: Step Expand Practice 탭 바 & 화면]
  // ============================================================================

  Widget _buildPracticeTabBar() {
    final isP1 = _phase == ShadowingPhase.part1Practice;
    final isP2 = _phase == ShadowingPhase.part2Practice;
    final isP3 = _phase == ShadowingPhase.chunkPractice;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildPracticeTab('P1', isP1, () => _switchToPractice(1)),
          const SizedBox(width: 8),
          _buildPracticeTab('P2', isP2, () => _switchToPractice(2)),
          const SizedBox(width: 8),
          _buildPracticeTab('P3', isP3, () => _switchToPractice(3)),
        ],
      ),
    );
  }

  Widget _buildStepPracticeWithTabBar() {
    return Column(
      children: [
        _buildPracticeTabBar(),
        Expanded(child: _buildTurnPracticeScreen()),
      ],
    );
  }

  Widget _buildPracticeTab(String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.amber.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? Colors.amber : Colors.white24,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.amber : Colors.white38,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
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

  Widget _buildStepExpandSelectScreen() {
    final bool hasData = _stepExpandTurns.isNotEmpty;
    // 📐 시스템 글자 크기 1.7배 + 화면 확대(density 480→540)를 함께 쓰는 기기에서
    //    이 화면이 무너졌다(실기기 확인, 논리 폭 320dp). 제목이 두 줄로 쪼개져
    //    닫기 버튼과 부딪히고 카드 부제가 "역/할교환"처럼 어절 중간에서 끊겼다.
    //    여기는 문장이 아니라 짧은 라벨만 있는 선택 메뉴라, 이 화면에서만 배율을
    //    묶어 레이아웃을 지킨다. 본문 낭독 화면들은 배율을 그대로 따른다.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 닫기 버튼을 제목과 같은 줄에 두면 좁은 폭에서 제목이 96dp를 뺏겨
            // 두 줄이 된다. 버튼은 위, 제목은 아래 전체 폭으로 내린다.
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
              "Pick Your Practice",
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            _buildPracticeSelectionCard(
              title: "Practice 1",
              subtitle: "Short-answer role swap",
              color: const Color(0xFF4ADE80),
              icon: Icons.swap_horiz_rounded,
              onTap: hasData ? _startPart1Practice : null,
            ),
            const SizedBox(height: 12),
            _buildPracticeSelectionCard(
              title: "Practice 2",
              subtitle: "Watch and hear each sentence grow",
              color: const Color(0xFF38BDF8),
              icon: Icons.expand_more_rounded,
              onTap: hasData ? _startPart2Practice : null,
            ),
            const SizedBox(height: 12),
            _buildPracticeSelectionCard(
              title: "Practice 3",
              subtitle: _isPreparingStepP3
                  ? "Preparing P3... P1 and P2 are ready"
                  : (_stepP3PreparationError ?? "Echoing & Shadowing Practice"),
              color: const Color(0xFFA78BFA),
              icon: Icons.music_note_rounded,
              isLoading: _isPreparingStepP3,
              onTap: _isPreparingStepP3
                  ? null
                  : _stepP3PreparationError != null ||
                          _expandedSentence.trim().isEmpty
                      ? _retryStepP3Preparation
                      : _goToChunkPractice,
            ),
            const Spacer(),
            TextButton(
              onPressed: _exitShadowing,
              child: const Text("Cancel",
                  style: TextStyle(color: Colors.white38, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPracticeSelectionCard({
    required String title,
    required String subtitle,
    required Color color,
    required IconData icon,
    bool isLoading = false,
    VoidCallback? onTap,
  }) {
    final bool enabled = onTap != null || isLoading;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          // 좁은 폭(320dp)에서는 여백·아이콘이 가져가는 자리가 곧 글자가 깨지는
          // 원인이다. 라벨이 한 줄에 들어오도록 조금씩 줄여 글자 폭을 벌어 준다.
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: color.withValues(alpha: 0.72), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.20),
                  border: Border.all(color: color.withValues(alpha: 0.72)),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: color,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 13, height: 1.3)),
                  ],
                ),
              ),
              if (isLoading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: color,
                    strokeWidth: 2.2,
                  ),
                )
              else
                Icon(Icons.chevron_right_rounded,
                    color: color.withValues(alpha: 0.6), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPracticeControl() {
    if (_phase != ShadowingPhase.practicing) return const SizedBox.shrink();

    final bool hasRecording = _chunks.isNotEmpty &&
        _currentChunkIdx < _chunks.length &&
        _chunks[_currentChunkIdx].isDone;
    final bool isLastChunk = _currentChunkIdx == _chunks.length - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      decoration: const BoxDecoration(
          color: Color(0xFF1C1C1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // AI 재생 버튼
          IconButton(
            icon: const Icon(Icons.volume_up_rounded,
                color: Colors.amber, size: 32),
            onPressed: () => _replayChunkAI(_currentChunkIdx), // 🆕 [P2-REPLAY]
          ),

          // 녹음 버튼 (메인)
          GestureDetector(
            onTap: _onUserIconTap,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isListening
                    ? Colors.greenAccent.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.08),
                border: Border.all(
                    color: _isListening ? Colors.greenAccent : Colors.white38,
                    width: _isListening ? 2.5 : 1.5),
              ),
              child: Icon(
                _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                color: _isListening ? Colors.greenAccent : Colors.white70,
                size: 30,
              ),
            ),
          ),

          // 다음 버튼
          IconButton(
            icon: Icon(
              isLastChunk ? Icons.check_circle_outline : Icons.skip_next,
              color: hasRecording ? Colors.white : Colors.white24,
              size: 32,
            ),
            onPressed: hasRecording ? _advanceChunk : null,
          ),
        ],
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
  variantSelect,
  practicing,
  reviewing,
  tutorPlay,
  turnPractice,
  chunkPractice,
  part1Practice,
  part2Practice
}

enum SentenceVariant { expanded, polished }

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
