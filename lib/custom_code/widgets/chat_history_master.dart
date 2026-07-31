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

// 📦 [Box 1: Imports 및 패키지]
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;
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
import 'routine_mode_roleplay.dart' show TtsCache;
import '/custom_code/actions/billing_ticker.dart';

const String _historyListenTtsModel = 'tts-1';
const String _historyListenTtsVoice = 'nova';
const String _historyPracticeTtsModel = 'gpt-4o-mini-tts';
const String _historyPracticeAiVoice = 'nova';
const String _historyPracticeUserVoice = 'verse';
const List<String> _meaningUnitVoiceOptions = <String>[
  'marin',
  'cedar',
  'verse',
  'coral',
];
const List<String> _nativeMeaningUnitVoiceOptions = <String>[
  'verse',
  'cedar',
  'coral',
];
const List<String> _p3LearningVoiceOptions = <String>[
  'marin',
  'cedar',
  'verse',
];
const Color _p3ShadowingAccentColor = Color(0xFF818CF8);
const String _meaningUnitTtsInstructions = '''
Read the English sentence for language learners using clear thought groups.

Follow these rules:

1. Divide the sentence into meaningful phrases based on grammar and meaning, not word by word.
2. Keep words inside each phrase naturally connected.
3. Add a short, subtle pause between thought groups.
4. Make each thought group easy to recognize, but do not exaggerate the pauses.
5. Slightly emphasize the key word in each phrase.
6. Reduce less important function words naturally, but do not make them unclear.
7. Preserve natural English rhythm, linking, stress, and intonation.
8. Do not sound like a newsreader, audiobook narrator, or pronunciation drill.
9. Do not speak unnaturally slowly.
10. Use a clear, conversational pace suitable for intermediate English learners.
11. For long or complex sentences, slow down slightly at clause boundaries.
12. Make questions, contrasts, conditions, and important corrections clear through intonation.
13. Do not insert spoken explanations, labels, or the words pause or slash.
14. Read only the supplied sentence.

The result should sound like a native speaker speaking clearly to an English learner: natural within each phrase, with brief and recognizable pauses between meaning units.
''';
const String _nativeMeaningUnitTtsInstructions = '''
Speak in natural, everyday English using native-like thought groups.

Follow these rules:

1. Group words naturally according to meaning and sentence flow.
2. Keep each thought group smoothly connected without sounding segmented.
3. Use brief, subtle pauses only where a native speaker would naturally pause.
4. Do not pause at every comma or punctuation mark.
5. Let important words carry the stress, while function words remain lighter and naturally reduced.
6. Use natural linking, contractions, rhythm, and intonation.
7. Vary the pace slightly: move faster through predictable information and slow down briefly for important, contrasting, or new information.
8. Do not over-enunciate every word.
9. Do not sound like a teacher, newsreader, audiobook narrator, or pronunciation exercise.
10. Maintain a relaxed, conversational pace used in real-life native speech.
11. Preserve clarity, but prioritize natural flow over textbook-style pronunciation.
12. Read only the supplied text without adding explanations or commentary.

The result should sound like a native speaker talking naturally to another person, with meaning carried through rhythm, stress, linking, and subtle pauses.
''';

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
    with SingleTickerProviderStateMixin {
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
  bool _isActionLocked = false;
  bool _isEnteringPractice = false;
  bool _isOpeningAdjacentHistory = false;
  int _openingHistoryOffset = 0;
  Map<String, dynamic>? _cachedRoomData;

  // 📦 [Box 4: 상태 변수 - Shadowing 상태 머신]
  ShadowingPhase _phase = ShadowingPhase.idle;
  SentenceVariant _selectedVariant = SentenceVariant.expanded;
  String? _entryMessageDocId;
  String _expandedSentence = "";
  String _polishedSentence = "";
  bool _polishedLoadDone = false;
  String _formattedFullSentence = "";
  // 🔧 [STAMPEDE-FIX] 같은 청크에 대한 동시 API 호출 방지
  // key: chunk index, value: 진행 중인 audio fetch Future
  final Map<int, Future<Uint8List?>> _inFlightChunkFetch = {};
  final Map<String, Future<Uint8List?>> _meaningUnitTtsInFlight = {};
  final Map<String, Future<Uint8List?>> _p3MeaningUnitTtsInFlight = {};
  List<PracticeChunk> _chunks = [];
  int _currentChunkIdx = 0;
  bool _isRerecordingSingle = false;
  bool _isPlayingFullUser = false;
  int _fullUserPlayIdx = 0;
  final Map<String, Uint8List> _fullAIAudioCache = {};
  String? _tempRecordDir;
  bool _isListening = false;
  Timer? _utteranceSafetyTimer;

  // 🆕 [TUTOR] 양측 대화 자동 재생 모드 상태 변수
  bool _isTutorPlaying = false;
  int _tutorCurrentIdx = -1;
  bool _tutorIsAiTurn = false;
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
  bool _showEchoingOverlay = false;
  Timer? _echoingOverlayTimer;

  // P2 샤도잉 시작 팝업 오버레이
  bool _showShadowingOverlay = false;
  Timer? _shadowingOverlayTimer;

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
  List<String> _shadowWords = [];
  int _shadowWordIdx = -1;
  Timer? _shadowHighlightTimer;
  Timer? _shadowAdvanceTimer;
  double _shadowSpeed = 1.0; // 오디오 실패 시 하이라이트 fallback용 고정 속도.
  String? _selectedMeaningUnitVoice;
  // P2 학습 Voice를 직접 선택해야 의미단위 쉐도잉을 시작한다.
  bool _shadowStarted = false;
  bool _p2CountdownStarting = false;
  Future<Uint8List?>? _p2CountdownAudioFuture;
  AudioPlayer? _p2CountdownPlayer;
  Completer<void>? _p2CountdownCancel;
  int _p2CountdownGeneration = 0;
  // [P2-PROXY] Local amplitude proxy for spoken-ratio checks. No Whisper cost.
  Timer? _shadowAmpTimer;
  int _shadowVoicedTicks = 0;
  int _shadowTotalTicks = 0;
  int _shadowRereadCount = 0;
  // [P2-SHADOW-REC] User-line audio captured for Play all. No scoring/STT.
  bool _shadowRecording = false;
  int _shadowRecordLineIdx = -1;
  // [P2-SHADOW-AI] AI voice read-along: highlight follows audio playback position.
  AudioPlayer? _shadowAiPlayer;
  StreamSubscription<Duration>? _shadowPosSub;
  StreamSubscription<Duration>? _shadowDurSub;
  StreamSubscription<void>? _shadowCompleteSub;
  Duration _shadowAudioDuration = Duration.zero;
  // [P-PULSE] Softer indigo pulse for the P3 polished button.
  static const Color _pPulseColor = Color(0xFF818CF8);

  // 🆕 [P2-INDICATOR] AI 청크 발화 중 여부 (인디케이터 빛남용)
  bool _aiChunkPlaying = false;
  // AI TTS 로딩 중 (재생 전 Thinking... 표시용)
  bool _aiChunkLoading = false;
  // 🆕 [P2-INDICATOR] AI 다시 듣기 모드 (true이면 끝나도 마이크 자동 ON 안 함)
  bool _isReplayMode = false;

  // P3 한 문장 의미단위 쉐도잉 상태.
  String? _selectedP3LearningVoice;
  String? _selectedP3NativeVoice;
  bool? _p3UsesNativeStyle;
  bool _p3ShadowLoading = false;
  bool _p3ShadowPlaying = false;
  bool _p3ShadowRecording = false;
  bool _p3ShadowComplete = false;
  int _p3ShadowGeneration = 0;
  AudioPlayer? _p3ShadowPlayer;
  String? _p3ShadowRecordPath;

  // 🆕 [CHUNK-PRACTICE] 의미단위 연습 모드 상태
  bool _practicingPolished = false; // false = expanded, true = polished
  bool _isBuildingExpand = false; // 🆕 [EXPAND-FROM-CHAT] 확장문장 생성 중 플래그
  String _cachedRoomMode = ''; // 🔧 [FREE-TALK-BTN] 버튼 표시 조건용 mode 캐시
  bool _isPlayingFullAI = false; // 전체 AI 듣기 진행 중
  int _polishedRevealCount = 0;
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
  String _apiKey = "";
  String _deepgramKey = "";
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
  bool _appIsShadowRecording = false;
  bool _isPlayingAppAudio = false;
  String? _shadowRecordPath;
  String _appTranscript = "";
  // 🆕 Another Sentence 중복 회피: 최근 생성한 한국어 문장(최대 6개) 기억
  final List<String> _appRecentKoSentences = [];

  // ── Idle Timeout (무반응 과금 정지, History: 자동 이동 없음) ──────────────
  // 🔧 틱 방식: 1초마다 활동 여부 확인. 튜터링/녹음/오디오 재생 중엔 카운터 0 유지.
  Timer? _idlePauseTimer;
  bool _isIdlePaused = false;
  int _idleElapsedSec = 0;

  // 유저나 AI가 작동 중인지 판단 (활동 중이면 idle 누적 안 함)
  bool get _isSystemBusy {
    return _isTutorPlaying ||
        isPlaying ||
        _appIsRecording ||
        _appIsShadowRecording ||
        _isPlayingAppAudio ||
        _isAutoRecording ||
        _tutorUserRecording ||
        _tutorAiSpeaking ||
        _aiChunkPlaying ||
        _aiChunkLoading ||
        _isPlayingFullAI ||
        _isPlayingFullUser ||
        _polishedUnitAIPlaying;
  }

  void _resetIdleTimer() {
    _idleElapsedSec = 0;
    if (_isIdlePaused) {
      _isIdlePaused = false;
      if (mounted) setState(() {});
      BillingTicker.instance.resume();
      BillingTicker.instance.logMode('history');
    }
    _idlePauseTimer?.cancel();
    _idlePauseTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _idleTick());
  }

  void _idleTick() {
    if (!mounted) return;
    // 🔒 [오토포즈 가드] 최상단 active route가 아니면(다른 페이지가 위에) idle 누적 금지
    if (ModalRoute.of(context)?.isCurrent == false) {
      _idleElapsedSec = 0;
      return;
    }
    if (_isIdlePaused) return;
    if (_isSystemBusy) {
      _idleElapsedSec = 0;
      return;
    }
    _idleElapsedSec++;
    if (_idleElapsedSec >= 60) {
      _handleIdlePause();
    }
  }

  void _handleIdlePause() {
    if (!mounted || _isIdlePaused) return;
    _isIdlePaused = true;
    _idleElapsedSec = 0;
    BillingTicker.instance.pause();
    if (mounted) setState(() {});
  }

  void _clearIdleTimers() {
    _idlePauseTimer?.cancel();
    _idlePauseTimer = null;
    _idleElapsedSec = 0;
  }

  // 사용자 실제 활동 시작 시 오토포즈 즉시 해제 (중복 방지 포함)
  void _resumeHistoryFromUserAction() {
    _resetIdleTimer();
    BillingTicker.instance.resumeFromActivity('history_user_action');
  }

  Widget _buildIdleBanner() => const SizedBox.shrink();

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
    _fetchRemoteConfig();
    _fetchRoomData();
    _initPermissions();
    BillingTicker.instance.setRate(BillingRate.quarter);
    BillingTicker.instance.resume();
    BillingTicker.instance.logMode('history');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resetIdleTimer();
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
    _clearIdleTimers();
    _utteranceSafetyTimer?.cancel();
    _silenceTimer?.cancel();
    _roleBubbleTimer?.cancel();
    _blinkController.dispose();
    _echoingOverlayTimer?.cancel();
    _shadowingOverlayTimer?.cancel();
    _polishedRevealTimer?.cancel();
    _shadowHighlightTimer?.cancel(); // [P2-SHADOW]
    _shadowAdvanceTimer?.cancel(); // [P2-SHADOW]
    _stopShadowAiPlayback(); // [P2-SHADOW-AI]
    _stopP2Countdown();
    _chunkScrollController.dispose();
    _practiceScrollController.dispose();
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
    _p2CountdownPlayer?.dispose();
    _tutorAudioPlayer?.dispose();
    _appCorrectedAudio = null;
    if (_appIsRecording || _appIsShadowRecording || _shadowRecording) {
      appAudioRecorder.stop().catchError((_) {});
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

  Future<void> _deleteMessage(DocumentReference msgRef) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('메시지 삭제', style: TextStyle(color: Colors.white)),
        content: const Text('이 메시지를 삭제할까요?',
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
      await msgRef.delete();
    } catch (e) {
      debugPrint('[deleteMessage] $e');
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
      }
    } catch (e) {
      debugPrint("[fetchRoomData] $e");
    }
    if (mounted) setState(() => isLoadingRoom = false);
  }

  Future<void> _fetchRemoteConfig() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.fetchAndActivate();
      if (mounted) {
        setState(() {
          _apiKey = remoteConfig.getString('OpenAIAPIKey');
          _deepgramKey = remoteConfig.getString('DeepgramAPIKey');
        });
      }
    } catch (e) {
      debugPrint("[fetchRemoteConfig] $e");
    }
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
        _entryMessageDocId = null;
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
      var messageDocs = _cachedDocs;
      if (messageDocs.isEmpty) {
        final messagesSnap = await widget.historyDoc
            .collection('messages')
            .orderBy('created_at', descending: false)
            .get();
        messageDocs = messagesSnap.docs;
        _cachedDocs = messageDocs;
      }
      if (!mounted) return;

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
        _showRoomEntryToast("아직 연습할 대화가 없습니다");
        return;
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

  Future<void> _prepareStepP3(String sentence, int generation) async {
    try {
      if (!mounted || generation != _stepP3PreparationGeneration) return;
      setState(() {
        _isPreparingStepP3 = false;
        _stepP3PreparationError =
            sentence.trim().isEmpty ? 'P3에서 사용할 문장이 없습니다.' : null;
      });
    } catch (e) {
      debugPrint('[prepareStepP3] $e');
      if (!mounted || generation != _stepP3PreparationGeneration) return;
      setState(() {
        _isPreparingStepP3 = false;
        _stepP3PreparationError = 'P3 준비에 실패했습니다. 눌러서 다시 시도하세요.';
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
          _tutorIsAiTurn = lineRepresentsAi;
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
        _tutorIsAiTurn = false;
      });
    }
  }

  // 🆕 [TUTOR] OpenAI TTS API 직접 호출 → 로컬 AudioPlayer 재생 (끝까지 대기)
  // 🔧 [v3.7] TtsCache 우선 조회 → MISS 시 API 호출 후 캐시 저장
  Future<void> _playTutorLineTTS(String text, bool isAi) async {
    if (_apiKey.isEmpty || text.trim().isEmpty) return;
    final voice = isAi ? _historyPracticeAiVoice : _historyPracticeUserVoice;
    final cacheVoice = _practiceCacheVoice(voice);
    try {
      Uint8List? audio = await TtsCache.get(text, cacheVoice);
      if (audio != null) {
      } else {
        audio = await _fetchPracticeTTS(text, voice);
        if (audio != null) {
          TtsCache.put(text, cacheVoice, audio);
        }
      }
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
    _resetIdleTimer();
    _tutorAudioPlayer?.stop();
    if (mounted) {
      setState(() {
        _isTutorPlaying = false;
        _tutorCurrentIdx = -1;
        _tutorIsAiTurn = false;
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

  void _forceNextTurn() {
    _stopAutoVADRecording();
    audioPlayer.stop();
    _stopShadowAiPlayback(); // [P2-SHADOW-AI] Stop read-along voice on skip.
    _nextTurn();
  }

  void _checkAndStartTurn() {
    if (!mounted || !isPracticeMode || isPaused) return;
    if (currentIndex >= _tutorLines.length) return;
    // [P2-START] Do not start either AI playback or user highlight until speed is chosen.
    if (_phase == ShadowingPhase.part2Practice && !_shadowStarted) return;
    final line = _tutorLines[currentIndex];
    final bool isAiTurn = _isAiTurn(line); // 🆕 [BOX-32]
    if (isAiTurn) {
      _checkAndPlayAILine();
    } else if (_phase == ShadowingPhase.part2Practice) {
      _startShadowHighlight(); // [P2-SHADOW]
    } else {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && isPracticeMode && !isPaused && !_isAutoRecording) {
          _startAutoVADRecording();
        }
      });
    }
  }

  // ============================================================================
  // [P2-SHADOW] Highlight read-along. P2 only, no recording.
  // ============================================================================
  void _startShadowHighlight() {
    _shadowHighlightTimer?.cancel();
    _shadowAdvanceTimer?.cancel();
    if (!mounted || !isPracticeMode || currentIndex >= _tutorLines.length) {
      return;
    }
    final text = (_tutorLines[currentIndex]['text'] as String).trim();
    final words =
        text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) {
      _nextTurn();
      return;
    }
    if (mounted) {
      setState(() {
        _shadowWords = words;
        _shadowWordIdx = -1;
      });
    }
    final int lineIdx = currentIndex;
    _pinShadowLineToTop(lineIdx);
    _shadowHighlightTimer = Timer(const Duration(seconds: 1), () async {
      if (!mounted ||
          _phase != ShadowingPhase.part2Practice ||
          isPaused ||
          currentIndex != lineIdx) {
        return;
      }
      await _startShadowRecording(lineIdx);
      if (!mounted ||
          _phase != ShadowingPhase.part2Practice ||
          isPaused ||
          currentIndex != lineIdx) {
        return;
      }
      _startShadowLineGlide(lineIdx, words);
      // [P2-SHADOW-AI] Play the AI voice and drive the highlight from the audio
      // playback position. Falls back to the timer stepping if audio is
      // unavailable (offline / no API key).
      await _startShadowAiVoice(lineIdx, words);
    });
  }

  // [P2-SHADOW-AI] Fetch + play the AI voice for the current read-along line and
  // sync the word highlight to the audio position. The generated audio itself
  // carries natural thought-group pauses; playback speed is never manipulated.
  Future<void> _startShadowAiVoice(int lineIdx, List<String> words) async {
    final text = (_tutorLines[lineIdx]['text'] as String).trim();
    final voice = _selectedMeaningUnitVoice;
    if (voice == null) {
      _stepShadowHighlight(0);
      return;
    }
    Uint8List? audio;
    try {
      audio = await _getMeaningUnitTTS(text, voice);
    } catch (e) {
      debugPrint('[startShadowAiVoice] fetch $e');
    }
    if (!mounted ||
        _phase != ShadowingPhase.part2Practice ||
        isPaused ||
        currentIndex != lineIdx) {
      return;
    }
    // No audio available → keep the original timer-based read-along.
    if (audio == null) {
      _stepShadowHighlight(0);
      return;
    }
    await _stopShadowAiPlayback();
    final player = AudioPlayer();
    _shadowAiPlayer = player;
    _shadowAudioDuration = Duration.zero;
    _shadowDurSub = player.onDurationChanged.listen((d) {
      if (d > Duration.zero) _shadowAudioDuration = d;
    });
    _shadowPosSub = player.onPositionChanged.listen((pos) {
      if (!mounted ||
          _phase != ShadowingPhase.part2Practice ||
          isPaused ||
          currentIndex != lineIdx) {
        return;
      }
      final total = _shadowAudioDuration.inMilliseconds;
      if (total <= 0 || words.isEmpty) return;
      final ratio = (pos.inMilliseconds / total).clamp(0.0, 1.0);
      final idx = (ratio * words.length).floor().clamp(0, words.length - 1);
      if (idx != _shadowWordIdx) {
        setState(() => _shadowWordIdx = idx);
      }
    });
    _shadowCompleteSub =
        player.onPlayerComplete.listen((_) => _onShadowAiComplete(lineIdx));
    try {
      await player.play(BytesSource(audio));
    } catch (e) {
      debugPrint('[startShadowAiVoice] play $e');
      await _stopShadowAiPlayback();
      if (mounted &&
          _phase == ShadowingPhase.part2Practice &&
          !isPaused &&
          currentIndex == lineIdx) {
        _stepShadowHighlight(0); // fallback
      }
    }
  }

  // [P2-SHADOW-AI] AI voice finished → mark all words read, then reuse the
  // existing recording-stop + evaluate/advance flow.
  void _onShadowAiComplete(int lineIdx) {
    if (!mounted ||
        _phase != ShadowingPhase.part2Practice ||
        isPaused ||
        currentIndex != lineIdx) {
      return;
    }
    if (mounted) setState(() => _shadowWordIdx = _shadowWords.length);
    _shadowAdvanceTimer?.cancel();
    _shadowAdvanceTimer = Timer(const Duration(milliseconds: 700), () async {
      if (!mounted || _phase != ShadowingPhase.part2Practice || isPaused) {
        return;
      }
      await _stopShadowRecordingAndEvaluate();
    });
  }

  // [P2-SHADOW-AI] Stop + dispose the read-along AI player and its listeners.
  Future<void> _stopShadowAiPlayback() async {
    _shadowPosSub?.cancel();
    _shadowPosSub = null;
    _shadowDurSub?.cancel();
    _shadowDurSub = null;
    _shadowCompleteSub?.cancel();
    _shadowCompleteSub = null;
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
    _shadowAudioDuration = Duration.zero;
  }

  void _stepShadowHighlight(int idx) {
    if (!mounted || _phase != ShadowingPhase.part2Practice || isPaused) return;
    if (idx >= _shadowWords.length) {
      if (mounted) setState(() => _shadowWordIdx = _shadowWords.length);
      // [P2-PROXY] Stop recording after 700ms, then advance or show retry popup.
      _shadowAdvanceTimer?.cancel();
      _shadowAdvanceTimer = Timer(const Duration(milliseconds: 700), () async {
        if (!mounted || _phase != ShadowingPhase.part2Practice || isPaused) {
          return;
        }
        await _stopShadowRecordingAndEvaluate();
      });
      return;
    }
    if (mounted) setState(() => _shadowWordIdx = idx);
    _shadowHighlightTimer?.cancel();
    _shadowHighlightTimer = Timer(
      Duration(milliseconds: _shadowWordDuration(_shadowWords[idx])),
      () => _stepShadowHighlight(idx + 1),
    );
  }

  int _shadowWordDuration(String w) {
    final clean = w.replaceAll(RegExp(r'[^A-Za-z]'), '');
    int d = 220 + clean.length * 55;
    if (RegExp(r'[,;:]$').hasMatch(w)) d += 160;
    if (RegExp(r'[.!?]$').hasMatch(w)) d += 320;
    d = (d / _shadowSpeed).round();
    return d.clamp(140, 1100);
  }

  // [P2-SHADOW-REC] Capture the user's read-along audio for Play all.
  Future<void> _startShadowRecording(int lineIdx) async {
    try {
      if (!await appAudioRecorder.hasPermission()) return;
      if (_shadowRecording) {
        try {
          await appAudioRecorder.stop();
        } catch (_) {}
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/p2shadow_${lineIdx}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await appAudioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      _shadowRecording = true;
      _shadowRecordLineIdx = lineIdx;
      // [P2-PROXY] Sample amplitude every 100ms to estimate spoken ratio.
      _shadowVoicedTicks = 0;
      _shadowTotalTicks = 0;
      _shadowAmpTimer?.cancel();
      _shadowAmpTimer =
          Timer.periodic(const Duration(milliseconds: 100), (t) async {
        if (!mounted || !_shadowRecording) {
          t.cancel();
          return;
        }
        try {
          if (await appAudioRecorder.isRecording()) {
            final amp = await appAudioRecorder.getAmplitude();
            _shadowTotalTicks++;
            if (amp.current > -25.0) _shadowVoicedTicks++;
          }
        } catch (_) {
          t.cancel();
        }
      });
    } catch (e) {
      debugPrint('[startShadowRecording] $e');
      _shadowRecording = false;
    }
  }

  Future<void> _stopShadowRecording() async {
    if (!_shadowRecording) return;
    _shadowRecording = false;
    try {
      final path = await appAudioRecorder.stop();
      if (path != null &&
          path.isNotEmpty &&
          _shadowRecordLineIdx >= 0 &&
          _shadowRecordLineIdx < _tutorLines.length) {
        _tutorLines[_shadowRecordLineIdx]['user_record_path'] = path;
      }
    } catch (_) {}
    _shadowRecordLineIdx = -1;
  }

  // [P2-PROXY] Evaluate spoken ratio after the read-along recording ends.
  Future<void> _stopShadowRecordingAndEvaluate() async {
    _shadowAmpTimer?.cancel();
    final double ratio =
        _shadowTotalTicks == 0 ? 0.0 : _shadowVoicedTicks / _shadowTotalTicks;
    await _stopShadowRecording();
    if (!mounted || _phase != ShadowingPhase.part2Practice || isPaused) return;
    if (ratio < 0.5 && _shadowRereadCount < 3) {
      _showShadowRetryDialog();
    } else {
      _shadowRereadCount = 0;
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && _phase == ShadowingPhase.part2Practice && !isPaused) {
          _nextTurn();
        }
      });
    }
  }

  // [P2-PROXY] Retry popup when the local spoken-ratio proxy is too low.
  void _showShadowRetryDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2E1C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.amber.withValues(alpha: 0.5)),
        ),
        contentPadding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "조금 더 크게 읽어볼까요?",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: '다시 말하기',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _shadowRereadCount++;
                          if (mounted &&
                              _phase == ShadowingPhase.part2Practice &&
                              !isPaused) {
                            _startShadowHighlight();
                          }
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.replay_rounded,
                                  color: Colors.amber, size: 34),
                              SizedBox(height: 6),
                              Text("다시 말하기",
                                  style: TextStyle(
                                      color: Colors.amber, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    button: true,
                    label: '다음 진행',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _shadowRereadCount = 0;
                          if (mounted &&
                              _phase == ShadowingPhase.part2Practice &&
                              !isPaused) {
                            _nextTurn();
                          }
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.arrow_forward_rounded,
                                  color: Colors.greenAccent, size: 34),
                              SizedBox(height: 6),
                              Text("다음 진행",
                                  style: TextStyle(
                                      color: Colors.greenAccent, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
      final cacheVoice = _practiceCacheVoice(voice);
      Uint8List? audio = await TtsCache.get(text, cacheVoice);
      if (audio != null) {
      } else {
        if (_apiKey.isEmpty) {
          if (mounted && isPracticeMode) {
            setState(() => _tutorAiSpeaking = false);
            _nextTurn();
          }
          return;
        }
        audio = await _fetchPracticeTTS(text, voice);
        if (audio != null) {
          TtsCache.put(text, cacheVoice, audio);
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
      final cacheVoice = _practiceCacheVoice(_historyPracticeAiVoice);
      Uint8List? audio = await TtsCache.get(prompt, cacheVoice);
      if (audio != null) {
      } else if (_apiKey.isNotEmpty) {
        audio = await _fetchPracticeTTS(prompt, _historyPracticeAiVoice);
        if (audio != null) TtsCache.put(prompt, cacheVoice, audio);
      } else {}
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

  // 📦 [Box 11: Shadowing 진입점]
  Future<void> _enterShadowing(DocumentSnapshot doc, String docId) async {
    final data = doc.data() as Map<String, dynamic>;
    final rawText = (data['translated_text'] ?? '').toString();
    final String directExpanded =
        (data['expanded_sentence'] ?? '').toString().trim();

    // 디버그 로그 초기화 및 기록

    if (directExpanded.isNotEmpty) {
      _expandedSentence = directExpanded;
    } else {
      final parts = rawText.split(RegExp(r'\n\s*\n'));
      _expandedSentence = parts.length >= 2
          ? parts.sublist(1).join('\n\n').trim()
          : rawText.trim();
    }

    _polishedSentence = "";
    _entryMessageDocId = docId;
    _practicingPolished = false;

    if (mounted) {
      BillingTicker.instance.setRate(BillingRate.full);
      setState(() => isPracticeMode = true);
      _goToChunkPractice();
    }
    _loadPolishedSentence();
  }

  Future<void> _loadPolishedSentence() async {
    try {
      final roomDoc = await widget.historyDoc.get();
      if (!mounted) return;
      final roomData = roomDoc.data() as Map<String, dynamic>?;
      if (roomData == null) {
        if (mounted) setState(() => _polishedLoadDone = true);
        return;
      }

      // ── 1순위: polished_sentence 직접 읽기 ──────────────────────
      final directPolished = roomData['polished_sentence'] as String?;

      if (directPolished != null && directPolished.isNotEmpty) {
        debugPrint("[loadPolishedSentence] 1순위: polished_sentence 직접 읽기 성공");
        if (mounted)
          setState(() {
            _polishedSentence = directPolished;
            _polishedLoadDone = true;
          });
        return;
      }

      // ── 2순위: expanded_sentence 직접 읽기 ──────────────────────
      final directExpanded = roomData['expanded_sentence'] as String?;
      if (directExpanded != null && directExpanded.isNotEmpty) {
        debugPrint(
            "[loadPolishedSentence] 2순위: expanded_sentence → _expandedSentence 보정");
        if (mounted) setState(() => _expandedSentence = directExpanded);
      } else {}

      // ── 3순위: session_ref로 refined_sentence fallback 조회 ──────
      final sessionRef = roomData['session_ref'] as String?;
      if (sessionRef == null || sessionRef.isEmpty) {
        debugPrint("[loadPolishedSentence] 3순위: session_ref 없음 → 종료");
        if (mounted) setState(() => _polishedLoadDone = true);
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _polishedLoadDone = true);
        return;
      }

      debugPrint("[loadPolishedSentence] 3순위: session_ref=$sessionRef 조회 시도");
      final sessionDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('sessions')
          .doc(sessionRef)
          .get();
      if (!mounted) return;

      final fallbackPolished =
          sessionDoc.data()?['refined_sentence'] as String?;
      if (fallbackPolished != null && fallbackPolished.isNotEmpty) {
        debugPrint("[loadPolishedSentence] 3순위: refined_sentence fallback 성공");
        setState(() {
          _polishedSentence = fallbackPolished;
          _polishedLoadDone = true;
        });
      } else {
        debugPrint("[loadPolishedSentence] 3순위: refined_sentence 없음");
        setState(() => _polishedLoadDone = true);
      }
    } catch (e) {
      debugPrint("[loadPolishedSentence] 예외: $e");
      if (mounted) setState(() => _polishedLoadDone = true);
    }
  }

  Future<void> _startPracticeWithVariant(SentenceVariant variant) async {
    _selectedVariant = variant;
    final sentence =
        (variant == SentenceVariant.polished && _polishedSentence.isNotEmpty)
            ? _polishedSentence
            : _expandedSentence;
    _formattedFullSentence = sentence;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/tts_cache/${widget.historyDoc.id}');
      if (await folder.exists()) {
        final files = await folder.list().toList();
        for (final f in files) {}
      } else {}
    } catch (e) {
      debugPrint("[cacheSnapshot] $e");
    }
    if (!mounted) return;

    await _buildChunks(sentence);

    if (_chunks.isEmpty) {
    } else {
      for (int i = 0; i < _chunks.length; i++) {}
    }

    if (mounted) setState(() => _phase = ShadowingPhase.practicing);
    _prefetchAllChunkAI();
  }

  void _exitShadowing() {
    _stepP3PreparationGeneration++;
    _deleteUserRecordings(); // 🆕 Practice 임시 녹음 파일 정리
    BillingTicker.instance.setRate(BillingRate.quarter);
    _stopTutorPlayback();
    _stopAutoVADRecording();
    _utteranceSafetyTimer?.cancel();
    _polishedRevealTimer?.cancel();
    _shadowHighlightTimer?.cancel(); // [P2-SHADOW]
    _shadowAdvanceTimer?.cancel(); // [P2-SHADOW]
    _stopShadowAiPlayback(); // [P2-SHADOW-AI]
    _stopShadowRecording(); // [P2-SHADOW-REC]
    _stopP2Countdown();
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
        _isRerecordingSingle = false;
        _isPlayingFullUser = false;
        _fullUserPlayIdx = 0;
        _fullAIAudioCache.clear();
        _expandedSentence = "";
        _polishedSentence = "";
        _polishedLoadDone = false;
        _formattedFullSentence = "";
        _entryMessageDocId = null;
        currentIndex = 0;
        _isAutoRecording = false;
        _aiChunkPlaying = false; // 🆕 [P2-INDICATOR]
        _aiChunkLoading = false;
        _isReplayMode = false; // 🆕 [P2-INDICATOR]
        _practicingPolished = false; // 🆕 [CHUNK-PRACTICE]
        _isPlayingFullAI = false; // 🆕 [CHUNK-PRACTICE]
        _polishedRevealCount = 0;
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

  // [chunkSplit] HOST 메시지 갯수 조회 → N (1~10 클램프)
  Future<int> _fetchUserTurnCount() async {
    try {
      final snap = await widget.historyDoc.collection('messages').get();
      final hostCount = snap.docs.where((doc) {
        return ((doc.data()['role'] ?? '') as String) == 'HOST';
      }).length;
      final n = hostCount.clamp(1, 10);
      return n;
    } catch (e) {
      debugPrint("[fetchUserTurnCount] $e");
      return 0;
    }
  }

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

  void _triggerEchoingOverlay({VoidCallback? onDismiss}) {
    if (!mounted) return;
    setState(() => _showEchoingOverlay = true);
    _echoingOverlayTimer?.cancel();
    _echoingOverlayTimer = Timer(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      setState(() => _showEchoingOverlay = false);
      onDismiss?.call();
    });
  }

  void _triggerShadowingOverlay({VoidCallback? onDismiss}) {
    if (!mounted) return;
    setState(() => _showShadowingOverlay = true);
    _shadowingOverlayTimer?.cancel();
    _shadowingOverlayTimer = Timer(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      setState(() => _showShadowingOverlay = false);
      onDismiss?.call();
    });
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
        _isRerecordingSingle = false;
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
    if (_phase != ShadowingPhase.turnPractice) {
      final diskHit = await _AudioDiskCache.read(historyId, cacheKey);
      if (diskHit != null && mounted && idx < _chunks.length) {
        setState(() => _chunks[idx].aiAudio = diskHit);
        return diskHit;
      }
    }
    // 🔧 [정상속도] formatForSlowRhythm 제거 → 텍스트 그대로 TTS
    final audio = await _fetchPracticeTTS(chunk.text, _historyPracticeAiVoice);
    if (!mounted) return null;
    if (audio != null && idx < _chunks.length) {
      setState(() => _chunks[idx].aiAudio = audio);
      if (_phase != ShadowingPhase.turnPractice) {
        await _AudioDiskCache.write(historyId, cacheKey, audio);
      }
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
        _isRerecordingSingle = false;
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
        _isRerecordingSingle = false;
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

  String _hashText(String text) {
    final h = text.hashCode.abs().toRadixString(16);
    return '${h}_${text.length}';
  }

  // 메인 뷰의 리듬 듣기 (일반 모드)
  void _playRhythmAudio(String text) async {
    _resumeHistoryFromUserAction();
    if (text.isEmpty) return;
    final historyId = widget.historyDoc.id;
    final variant =
        _selectedVariant == SentenceVariant.polished ? 'pol' : 'exp';
    final cacheKey = 'gpt4omini_nova_full_${variant}_${_hashText(text)}.mp3';
    // TODO: LRU 정리 — 30개 초과 시 가장 오래된 것부터 제거
    if (_fullAIAudioCache.containsKey(cacheKey)) {
      await audioPlayer.play(BytesSource(_fullAIAudioCache[cacheKey]!));
      return;
    }
    // 대화방 공유 캐시(TtsCache) 확인 — 같은 문장을 대화방에서 들었으면 API 0회
    final cacheVoice = _practiceCacheVoice(_historyPracticeAiVoice);
    final ttsHit = await TtsCache.get(text, cacheVoice);
    if (ttsHit != null && mounted) {
      _fullAIAudioCache[cacheKey] = ttsHit;
      await audioPlayer.play(BytesSource(ttsHit));
      return;
    }
    if (_phase != ShadowingPhase.turnPractice) {
      final diskHit = await _AudioDiskCache.read(historyId, cacheKey);
      if (diskHit != null && mounted) {
        _fullAIAudioCache[cacheKey] = diskHit;
        await audioPlayer.play(BytesSource(diskHit));
        return;
      }
    }
    // 🔧 [정상속도] formatForSlowRhythm 제거 → 텍스트 그대로 TTS
    Uint8List? audio = await _fetchPracticeTTS(text, _historyPracticeAiVoice);
    if (!mounted) return;
    if (audio != null) {
      _fullAIAudioCache[cacheKey] = audio;
      await TtsCache.put(text, cacheVoice, audio);
      if (_phase != ShadowingPhase.turnPractice) {
        await _AudioDiskCache.write(historyId, cacheKey, audio);
      }
      await audioPlayer.play(BytesSource(audio));
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

  String _meaningUnitCacheVoice(String voice) =>
      '${_historyPracticeTtsModel}_meaning_groups_v1_$voice';

  Future<Uint8List?> _fetchMeaningUnitTTS(String text, String voice) =>
      _fetchOpenAITTS(
        text,
        1.0,
        voice,
        model: _historyPracticeTtsModel,
        instructions: _meaningUnitTtsInstructions,
        instructionTag: 'p2_learning',
      );

  Future<Uint8List?> _getMeaningUnitTTS(String text, String voice) {
    final requestKey = '$voice|${text.trim()}';
    final existing = _meaningUnitTtsInFlight[requestKey];
    if (existing != null) return existing;
    final future = () async {
      final cacheVoice = _meaningUnitCacheVoice(voice);
      var audio = await TtsCache.get(text, cacheVoice);
      if (audio != null) return audio;
      audio = await _fetchMeaningUnitTTS(text, voice);
      if (audio != null) await TtsCache.put(text, cacheVoice, audio);
      return audio;
    }();
    _meaningUnitTtsInFlight[requestKey] = future;
    future.whenComplete(() => _meaningUnitTtsInFlight.remove(requestKey));
    return future;
  }

  String _p3MeaningUnitCacheVoice(String voice, {required bool nativeStyle}) =>
      '${_historyPracticeTtsModel}_p3_${nativeStyle ? 'native' : 'learning'}_thought_groups_v1_$voice';

  Future<Uint8List?> _getP3MeaningUnitTTS(
    String text,
    String voice, {
    required bool nativeStyle,
  }) {
    final requestKey =
        '${nativeStyle ? 'native' : 'learning'}|$voice|${text.trim()}';
    final existing = _p3MeaningUnitTtsInFlight[requestKey];
    if (existing != null) return existing;
    final future = () async {
      final cacheVoice =
          _p3MeaningUnitCacheVoice(voice, nativeStyle: nativeStyle);
      var audio = await TtsCache.get(text, cacheVoice);
      if (audio != null) return audio;
      audio = await _fetchOpenAITTS(
        text,
        1.0,
        voice,
        model: _historyPracticeTtsModel,
        instructions: nativeStyle
            ? _nativeMeaningUnitTtsInstructions
            : _meaningUnitTtsInstructions,
        instructionTag: nativeStyle ? 'p3_native' : 'p3_learning',
      );
      if (audio != null) await TtsCache.put(text, cacheVoice, audio);
      return audio;
    }();
    _p3MeaningUnitTtsInFlight[requestKey] = future;
    future.whenComplete(() => _p3MeaningUnitTtsInFlight.remove(requestKey));
    return future;
  }

  Future<Uint8List?> _fetchOpenAITTS(String text, double speed, String voice,
      {String model = _historyListenTtsModel,
      String? instructions,
      String? instructionTag}) async {
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
              if (instructions != null && instructions.trim().isNotEmpty)
                'instructions': instructions,
            }),
          )
          .timeout(const Duration(seconds: 10));
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

  // 📦 [Box 17-A-2: 실전 튜터링 - 팝업 바텀시트]
  void _showTutoringPopup(String docId, String baseText) {
    _resumeHistoryFromUserAction();
    if (_appIsRecording || _appIsShadowRecording) {
      appAudioRecorder.stop().catchError((_) {});
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
      _appIsShadowRecording = false;
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
          .setRate(BillingRate.quarter); // 튜터링 종료 → quarter 복귀
      _dialogSetState = null;
      if (_appIsRecording || _appIsShadowRecording) {
        appAudioRecorder.stop().catchError((_) {});
      }
      if (mounted) {
        setState(() {
          activeAppDocId = null;
          _appIsRecording = false;
          _appIsShadowRecording = false;
        });
      }
    });
  }

  // 📦 [Box 17-B: 실전 튜터링 - 아코디언 UI (4단계)]
  Widget _buildAccordion(String docId, String baseText,
      {VoidCallback? onClose}) {
    void closeAccordion() {
      if (_appIsRecording || _appIsShadowRecording) {
        appAudioRecorder.stop().catchError((_) {});
      }
      setState(() {
        activeAppDocId = null;
        _appIsRecording = false;
        _appIsShadowRecording = false;
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
              await _fetchPracticeTTS(correctedEn, _historyPracticeAiVoice);
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

  // 📦 [Box 18-E: 실전 튜터링 - 쉐도잉 녹음 시작 (교정 TTS 1회 재생 후 녹음)]
  Future<void> _startShadowRecord() async {
    _resumeHistoryFromUserAction();
    // Step 4-1: 교정 TTS 먼저 1회 재생 후 완료 대기
    if (_appCorrectedAudio != null && mounted) {
      final completer = Completer<void>();
      StreamSubscription? sub;
      sub = audioPlayer.onPlayerComplete.listen((_) {
        if (!completer.isCompleted) completer.complete();
        sub?.cancel();
      });
      if (mounted) setState(() => _isPlayingAppAudio = true);
      try {
        BillingTicker.instance.resumeFromActivity('history_tutoring_tts_start');
        await audioPlayer.play(BytesSource(_appCorrectedAudio!));
        await completer.future
            .timeout(const Duration(seconds: 20), onTimeout: () {});
        BillingTicker.instance.resumeFromActivity('history_tutoring_tts_end');
      } catch (e) {
        debugPrint("[startShadowRecord TTS] $e");
      } finally {
        sub?.cancel();
        if (mounted) setState(() => _isPlayingAppAudio = false);
      }
    }
    if (!mounted) return;

    // Step 4-2: 녹음 시작
    final hasPermission = await appAudioRecorder.hasPermission();
    if (!hasPermission) return;
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/shadow_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await appAudioRecorder.start(
        const RecordConfig(
            encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1),
        path: path,
      );
      if (mounted) setState(() => _appIsShadowRecording = true);
    } catch (e) {
      debugPrint("[startShadowRecord] $e");
    }
  }

  // 📦 [Box 18-F: 실전 튜터링 - 쉐도잉 녹음 중지]
  Future<void> _stopShadowRecord() async {
    _resumeHistoryFromUserAction();
    final path = await appAudioRecorder.stop();
    BillingTicker.instance
        .resumeFromActivity('history_tutoring_shadow_recorded');
    if (mounted) {
      setState(() {
        _appIsShadowRecording = false;
        _shadowRecordPath = path;
      });
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
          SafeArea(child: _buildChunkPracticeScreen()),
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
                      if (mounted) _cachedDocs = docs;
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

  // 로비 ENTER 버튼과 동일한 로직: 잔여 시간 확인 후 StealthRoom 입장
  void _handleEnterRoom() async {
    _resetIdleTimer();
    if (_isActionLocked) return;
    _isActionLocked = true;
    try {
      FocusScope.of(context).unfocus();
      final appState = FFAppState();
      if (appState.hasConfirmedZeroTime) {
        context.pushNamed('Store');
        return;
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final newHistoryRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('chat_history')
          .doc();
      await newHistoryRef.set(
          {'created_at': FieldValue.serverTimestamp(), 'is_pinned': false});
      if (mounted) {
        context.pushNamed('StealthRoom',
            queryParameters: {
              'historyRef':
                  serializeParam(newHistoryRef, ParamType.DocumentReference)
            }.withoutNulls);
      }
    } finally {
      _isActionLocked = false;
    }
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
                  : roomName
                      .replaceAll(' Mode', '')
                      .replaceAll('Step Expand', 'Step.Ex'),
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
              onTap: s == 0 ? _resetIdleTimer : null,
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
                  // 말풍선 본체 (탭 → Keepers 저장)
                  Flexible(
                    child: GestureDetector(
                      onTap: () => _saveToKeepers(
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
                          children: collapseSame
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
                                  if (_langDisplayMode != 2) ...[
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
                                  if (_langDisplayMode != 1 &&
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
              audio = await _fetchPracticeTTS(text, voice);
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
    return Text(
      line['text'] as String,
      textAlign: lineIsAi ? TextAlign.right : TextAlign.left,
      style: TextStyle(
        color: isCurrent ? Colors.white : Colors.white60,
        fontSize: 14 * _fontScale,
        height: 1.5,
        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
      ),
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
                    onPressed: _exitShadowing,
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
                        Text(
                          isComplete
                              ? "Practice 완료!"
                              : (_phase == ShadowingPhase.part1Practice
                                  ? "Practice 1"
                                  : _phase == ShadowingPhase.part2Practice
                                      ? "Practice 2"
                                      : "Practice"),
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0),
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
                      onTap: s == 0 ? _resetIdleTimer : null,
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
                                  File(rp).delete().catchError((_) {});
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

  // 세련문장 5~7단어 호흡 단위 연습으로 전환 (Expanded와 동일 기준)
  Future<void> _switchToPolishedPractice() async {
    if (_polishedSentence.isEmpty) return;
    if (_isListening) _stopDeepgramListening();
    audioPlayer.stop();
    _polishedRevealTimer?.cancel();
    // 로딩 스피너 먼저 표시 (GPT 분할 대기 중)
    if (mounted) setState(() => _practicingPolished = true);
    final units = await _splitSentenceIntoChunks(_polishedSentence, 'polished');
    if (mounted) {
      setState(() {
        _polishedUnits = units.isNotEmpty ? units : [_polishedSentence];
        _polishedUnitIdx = 0;
        _polishedUnitAIPlaying = false;
        _isPlayingFullUser = false;
        _isPlayingFullAI = false;
        _aiChunkPlaying = false;
      });
    }
    await _playPolishedUnit(0);
  }

  // 직독직해 친화적 의미단위 분할
  List<String> _splitPolishedIntoUnits(String sentence) {
    final s = sentence.trim();
    if (s.isEmpty) return [s];

    // 단일 트리거 단어 (이 단어 앞에서 분할)
    const splitTriggers = {
      'and',
      'but',
      'or',
      'so',
      'yet',
      'because',
      'since',
      'although',
      'though',
      'while',
      'when',
      'before',
      'after',
      'if',
      'unless',
      'until',
      'as',
      'who',
      'whom',
      'whose',
      'which',
      'where',
      'that',
    };

    // 쉼표 뒤 절 시작 대명사 (주절 시작 신호)
    const clauseStartPronouns = {
      'i',
      'you',
      'he',
      'she',
      'we',
      'they',
      'it',
      'there',
    };

    // 부정사 to 뒤에 오면 분할하지 않는 단어 (전치사구 to)
    const infToNonVerbs = {
      'the',
      'a',
      'an',
      'my',
      'your',
      'his',
      'her',
      'our',
      'their',
      'its',
      'this',
      'that',
      'these',
      'those',
      'some',
      'any',
      'all',
      'no',
      'each',
      'every',
      'both',
      'few',
      'many',
      'much',
      'more',
      'most',
      'another',
      'me',
      'you',
      'him',
      'us',
      'them',
      'it',
    };

    // 복합 전치사/접속사 — 첫 단어 앞에서 분할, 내부는 묶음 유지
    const multiWordPrepList = [
      'as soon as',
      'as long as',
      'as well as',
      'as if',
      'as though',
      'even though',
      'even if',
      'in front of',
      'because of',
      'instead of',
      'on top of',
      'due to',
      'according to',
      'in spite of',
      'in order to',
      'out of',
      'apart from',
      'on behalf of',
      'as a result of',
      'in addition to',
      'with regard to',
      'in terms of',
    ];

    // 분사로 오해할 수 있는 일반 단어 제외
    const participleExclusions = {
      'need',
      'said',
      'would',
      'could',
      'should',
      'indeed',
      'agreed',
      'old',
      'good',
      'new',
      'bad',
      'loved',
      'named',
    };

    String cleanWord(String w) => w
        .replaceAll(RegExp(r'^[,;:]+'), '')
        .replaceAll(RegExp(r'[.,;:!?]+$'), '')
        .toLowerCase();

    bool isParticipleWord(String clean) {
      if (clean.length <= 3 || participleExclusions.contains(clean))
        return false;
      return clean.endsWith('ing') ||
          clean.endsWith('ed') ||
          clean.endsWith('en');
    }

    final words = s.split(RegExp(r'\s+'));
    if (words.isEmpty) return [s];

    // 복합 전치사 위치 사전 계산 (시작 위치 및 내부 위치 마킹)
    final Set<int> multiPrepStarts = {};
    final Set<int> insideMultiPrep = {};
    for (final prep in multiWordPrepList) {
      final pWords = prep.split(' ');
      for (int j = 0; j <= words.length - pWords.length; j++) {
        final slice =
            words.sublist(j, j + pWords.length).map(cleanWord).join(' ');
        if (slice == prep) {
          multiPrepStarts.add(j);
          for (int k = j + 1; k < j + pWords.length; k++) {
            insideMultiPrep.add(k);
          }
        }
      }
    }

    final List<List<String>> units = [[]];

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final clean = cleanWord(word);
      final currentUnit = units.last;
      final wordCount = currentUnit.length;

      // 복합 전치사 내부 단어 — 분할 없이 그냥 추가
      if (insideMultiPrep.contains(i)) {
        currentUnit.add(word);
        continue;
      }

      // 1. 복합 전치사 시작 앞에서 분할 (현재 단위 ≥2 단어일 때)
      if (multiPrepStarts.contains(i) && wordCount >= 2) {
        units.add([word]);
        continue;
      }

      // 2. 쉼표 뒤 분할 (현재 단위 ≥2 단어)
      if (wordCount >= 2) {
        final lastWord = currentUnit.last;
        if (lastWord.endsWith(',') || lastWord == ',') {
          // 2a. 주절 시작 대명사
          if (clauseStartPronouns.contains(clean)) {
            units.add([word]);
            continue;
          }
          // 2b. 분사구문 (-ing / -ed / -en)
          if (isParticipleWord(clean)) {
            units.add([word]);
            continue;
          }
        }
      }

      // 3. 접속사 / 관계사 앞에서 분할
      if (wordCount >= 2 && splitTriggers.contains(clean)) {
        units.add([word]);
        continue;
      }

      // 4. 목적·결과 부정사 to 앞에서 분할
      if (clean == 'to' && wordCount >= 2 && i + 1 < words.length) {
        final nextClean = cleanWord(words[i + 1]);
        if (!infToNonVerbs.contains(nextClean)) {
          units.add([word]);
          continue;
        }
      }

      currentUnit.add(word);
    }

    // 2단어 미만 조각은 앞 단위에 합치기
    final List<List<String>> merged = [];
    for (final unit in units) {
      if (unit.isEmpty) continue;
      if (merged.isNotEmpty && unit.length < 2) {
        merged.last.addAll(unit);
      } else {
        merged.add(unit);
      }
    }

    final result =
        merged.where((u) => u.isNotEmpty).map((u) => u.join(' ')).toList();

    return result.isEmpty ? [s] : result;
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
      audio = await _fetchPracticeTTS(text, _historyPracticeAiVoice);
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

  // 전체 AI 순차 재생
  Future<void> _playAllAI() async {
    _resumeHistoryFromUserAction();
    if (_chunks.isEmpty) return;
    if (_isListening) _stopDeepgramListening();
    if (mounted)
      setState(() {
        _isPlayingFullAI = true;
        _currentChunkIdx = -1;
        _aiChunkPlaying = false;
      });
    for (int i = 0; i < _chunks.length; i++) {
      if (!mounted || !_isPlayingFullAI) break;
      if (mounted) setState(() => _currentChunkIdx = i);
      await _playChunkAI(i);
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 100));
        return isPlaying && mounted && _isPlayingFullAI;
      });
      if (!mounted) break;
      await Future.delayed(const Duration(milliseconds: 350));
    }
    if (mounted)
      setState(() {
        _isPlayingFullAI = false;
        _currentChunkIdx = -1;
      });
  }

  // 청크 리스트 마지막 아이템으로 인라인 삽입되는 버튼 영역
  Widget _buildPracticeButtonsInline() {
    // 버튼 2개 + 충분한 하단 여백 (마지막 청크가 자동 스크롤로 화면 상단에 올라올 수 있도록)
    // viewPadding.bottom: 폰 도구 높이 보상, size.height * 0.55: 스크롤 여백
    final double bottomPad = MediaQuery.of(context).size.height * 0.55 +
        MediaQuery.of(context).viewPadding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(0, 6, 0, bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(
                    _isPlayingFullAI ? Icons.stop_rounded : Icons.volume_up,
                    size: 16,
                    color: Colors.amber,
                  ),
                  label: Text(
                    _isPlayingFullAI ? '중지' : 'AI Voice',
                    style: const TextStyle(color: Colors.amber, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.withValues(alpha: 0.1),
                    side:
                        BorderSide(color: Colors.amber.withValues(alpha: 0.6)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  onPressed: _isPlayingFullAI
                      ? () {
                          audioPlayer.stop();
                          if (mounted)
                            setState(() {
                              _isPlayingFullAI = false;
                              _currentChunkIdx = -1;
                            });
                        }
                      : _playAllAI,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(
                    _isPlayingFullUser ? Icons.stop_rounded : Icons.person,
                    size: 16,
                    color: Colors.greenAccent,
                  ),
                  label: Text(
                    _isPlayingFullUser ? '중지' : 'My Voice',
                    style: const TextStyle(
                        color: Colors.greenAccent, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent.withValues(alpha: 0.08),
                    side: BorderSide(
                        color: Colors.greenAccent.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  onPressed: _isPlayingFullUser
                      ? () {
                          audioPlayer.stop();
                          if (mounted)
                            setState(() => _isPlayingFullUser = false);
                        }
                      : _playFullUser,
                ),
              ),
            ],
          ),
        ],
      ),
    );
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

  String _p3Sentence({required bool nativeStyle}) {
    if (nativeStyle && _polishedSentence.trim().isNotEmpty) {
      return _polishedSentence.trim();
    }
    return _expandedSentence.trim();
  }

  Future<void> _stopP3Shadowing({bool resetSelection = false}) async {
    _p3ShadowGeneration++;
    final player = _p3ShadowPlayer;
    _p3ShadowPlayer = null;
    if (player != null) {
      try {
        await player.stop();
      } catch (_) {}
      try {
        await player.dispose();
      } catch (_) {}
    }
    if (_p3ShadowRecording) {
      _p3ShadowRecording = false;
      try {
        final path = await appAudioRecorder.stop();
        if (path != null && path.isNotEmpty) _p3ShadowRecordPath = path;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _p3ShadowLoading = false;
      _p3ShadowPlaying = false;
      if (resetSelection) {
        _selectedP3LearningVoice = null;
        _selectedP3NativeVoice = null;
        _p3UsesNativeStyle = null;
        _p3ShadowComplete = false;
        _p3ShadowRecordPath = null;
      }
    });
  }

  Future<void> _startP3ShadowRecording(int generation) async {
    if (!await appAudioRecorder.hasPermission()) return;
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/p3_shadow_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await appAudioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted || generation != _p3ShadowGeneration) {
        await appAudioRecorder.stop();
        return;
      }
      setState(() {
        _p3ShadowRecording = true;
        _p3ShadowRecordPath = path;
      });
    } catch (e) {
      debugPrint('[P3-SHADOW-REC] start failed: $e');
    }
  }

  Future<void> _startP3MeaningUnitShadowing({
    required bool nativeStyle,
    required String voice,
  }) async {
    await _stopP3Shadowing();
    if (!mounted || _phase != ShadowingPhase.chunkPractice) return;
    final text = _p3Sentence(nativeStyle: nativeStyle);
    if (text.isEmpty) {
      _showRoomEntryToast('P3에서 사용할 문장이 없습니다');
      return;
    }
    final generation = ++_p3ShadowGeneration;
    setState(() {
      _p3UsesNativeStyle = nativeStyle;
      _p3ShadowLoading = true;
      _p3ShadowPlaying = false;
      _p3ShadowComplete = false;
      _p3ShadowRecordPath = null;
    });

    final audio = await _getP3MeaningUnitTTS(
      text,
      voice,
      nativeStyle: nativeStyle,
    );
    if (!mounted ||
        generation != _p3ShadowGeneration ||
        _phase != ShadowingPhase.chunkPractice) {
      return;
    }
    if (audio == null) {
      setState(() => _p3ShadowLoading = false);
      _showRoomEntryToast('P3 학습 음성을 만들지 못했습니다');
      return;
    }

    final player = AudioPlayer();
    _p3ShadowPlayer = player;

    final playbackComplete = player.onPlayerComplete.first;
    await _startP3ShadowRecording(generation);
    if (!mounted || generation != _p3ShadowGeneration) return;
    setState(() {
      _p3ShadowLoading = false;
      _p3ShadowPlaying = true;
    });
    try {
      await player.play(BytesSource(audio));
      await playbackComplete.timeout(const Duration(seconds: 90));
      await Future.delayed(const Duration(milliseconds: 700));
    } catch (e) {
      debugPrint('[P3-SHADOW] play failed: $e');
    }
    if (!mounted || generation != _p3ShadowGeneration) return;
    if (_p3ShadowRecording) {
      _p3ShadowRecording = false;
      try {
        final path = await appAudioRecorder.stop();
        if (path != null && path.isNotEmpty) _p3ShadowRecordPath = path;
      } catch (_) {}
    }
    if (identical(_p3ShadowPlayer, player)) _p3ShadowPlayer = null;
    await player.dispose();
    if (mounted && generation == _p3ShadowGeneration) {
      setState(() {
        _p3ShadowPlaying = false;
        _p3ShadowComplete = true;
      });
    }
  }

  void _replaySelectedP3Shadowing() {
    final nativeStyle = _p3UsesNativeStyle;
    if (nativeStyle == null) return;
    final voice =
        nativeStyle ? _selectedP3NativeVoice : _selectedP3LearningVoice;
    if (voice == null) return;
    unawaited(_startP3MeaningUnitShadowing(
      nativeStyle: nativeStyle,
      voice: voice,
    ));
  }

  Future<void> _playP3ShadowRecording() async {
    final path = _p3ShadowRecordPath;
    if (path == null || path.isEmpty || !await File(path).exists()) return;
    final player = AudioPlayer();
    try {
      final complete = player.onPlayerComplete.first;
      await player.play(DeviceFileSource(path));
      await complete.timeout(const Duration(seconds: 90));
    } catch (e) {
      debugPrint('[P3-SHADOW-REC] playback failed: $e');
    } finally {
      await player.dispose();
    }
  }

  Widget _buildChunkPracticeScreen() => _buildP3MeaningUnitShadowingScreen();

  Widget _buildP3VoiceSelector({
    required String label,
    required List<String> options,
    required String? value,
    required Color color,
    required ValueChanged<String> onSelected,
  }) {
    final needsSelection = value == null;
    final content = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: needsSelection ? 0.11 : 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: needsSelection ? color : color.withValues(alpha: 0.45),
          width: needsSelection ? 1.7 : 1.2,
        ),
        boxShadow: needsSelection
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: needsSelection ? color : Colors.white60,
              fontSize: 10.5,
              height: 1.25,
              fontWeight: needsSelection ? FontWeight.bold : FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 36,
            padding: const EdgeInsets.only(left: 12, right: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.65)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                hint: Text(
                  '선택',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                isExpanded: true,
                dropdownColor: const Color(0xFF232323),
                icon: Icon(Icons.keyboard_arrow_down_rounded,
                    color: color, size: 18),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                items: options
                    .map(
                      (voice) => DropdownMenuItem<String>(
                        value: voice,
                        child: Text(
                            '${voice[0].toUpperCase()}${voice.substring(1)}'),
                      ),
                    )
                    .toList(),
                onChanged: (voice) {
                  if (voice != null) onSelected(voice);
                },
              ),
            ),
          ),
        ],
      ),
    );
    if (!needsSelection) return content;
    return AnimatedBuilder(
      animation: _blinkController,
      builder: (_, child) => Opacity(
        opacity: 0.35 + (_blinkOpacity.value * 0.65),
        child: child,
      ),
      child: content,
    );
  }

  Widget _buildP3SentenceText(String sentence) {
    return Text(
      sentence,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white70,
        fontSize: 20 * _fontScale,
        height: 1.65,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildP3MeaningUnitShadowingScreen() {
    final activeNative = _p3UsesNativeStyle == true;
    final activeLearning = _p3UsesNativeStyle == false;
    final sentence = _p3UsesNativeStyle == null
        ? _expandedSentence.trim()
        : _p3Sentence(nativeStyle: activeNative);
    final busy = _p3ShadowLoading || _p3ShadowPlaying;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 2),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: _exitShadowing,
              ),
              const Expanded(
                child: Text(
                  'P3  Meaning-unit Shadowing',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              ValueListenableBuilder<int>(
                valueListenable: BillingTicker.instance.billingState,
                builder: (_, state, __) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: CustomPaint(
                    size: const Size(16, 16),
                    painter: BillingDotPainter(state),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(() {
                  _fontScale = _fontScale == 1.0
                      ? 1.3
                      : _fontScale == 1.3
                          ? 0.8
                          : 1.0;
                }),
                icon: const Icon(Icons.format_size, color: Colors.white54),
              ),
            ],
          ),
        ),
        if (_isStepExpandRoom) _buildPracticeTabBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildP3VoiceSelector(
                  label: '원어민식 쉐도잉',
                  options: _nativeMeaningUnitVoiceOptions,
                  value: _selectedP3NativeVoice,
                  color: _p3ShadowingAccentColor,
                  onSelected: (voice) {
                    setState(() => _selectedP3NativeVoice = voice);
                    unawaited(_startP3MeaningUnitShadowing(
                      nativeStyle: true,
                      voice: voice,
                    ));
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildP3VoiceSelector(
                  label: '학습용 쉐도잉',
                  options: _p3LearningVoiceOptions,
                  value: _selectedP3LearningVoice,
                  color: _p3ShadowingAccentColor,
                  onSelected: (voice) {
                    setState(() => _selectedP3LearningVoice = voice);
                    unawaited(_startP3MeaningUnitShadowing(
                      nativeStyle: false,
                      voice: voice,
                    ));
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: activeNative || activeLearning
                          ? _p3ShadowingAccentColor
                          : Colors.white12,
                      width: _p3UsesNativeStyle == null ? 1 : 1.6,
                    ),
                  ),
                  child: sentence.isEmpty
                      ? const Text(
                          'P3에서 사용할 문장이 없습니다.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38),
                        )
                      : _buildP3SentenceText(sentence),
                ),
                const SizedBox(height: 18),
                if (_p3UsesNativeStyle == null)
                  const Text(
                    '왼쪽 또는 오른쪽에서 Voice를 선택하면 시작합니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  )
                else if (_p3ShadowLoading)
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _p3ShadowingAccentColor),
                      ),
                      SizedBox(width: 9),
                      Text('의미단위 음성 준비 중...',
                          style: TextStyle(color: Colors.white60)),
                    ],
                  )
                else if (_p3ShadowPlaying)
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.graphic_eq,
                          color: Colors.greenAccent, size: 20),
                      SizedBox(width: 8),
                      Text('음성을 들으며 동시에 따라 읽으세요',
                          style: TextStyle(color: Colors.greenAccent)),
                    ],
                  )
                else if (_p3ShadowComplete)
                  const Text('쉐도잉 완료',
                      style: TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold)),
                const SizedBox(height: 18),
                if (_p3UsesNativeStyle != null)
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: busy ? null : _replaySelectedP3Shadowing,
                            icon: Icon(busy
                                ? Icons.hourglass_top_rounded
                                : Icons.replay_rounded),
                            label: Text(busy ? '진행 중' : '다시 쉐도잉'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ),
                      if (_p3ShadowComplete && _p3ShadowRecordPath != null) ...[
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: _playP3ShadowRecording,
                            icon: const Icon(Icons.hearing_rounded),
                            label: const Text('내 음성'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegacyChunkPracticeScreen() {
    const Color colorA = Color(0xFF0F2233);
    const Color colorB = Color(0xFF1A0F2E);
    const Color colorAActive = Color(0xFF1C3D55);
    const Color colorBActive = Color(0xFF2E1650);

    return Stack(
      children: [
        Column(
          children: [
            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: _exitShadowing,
                  ),
                  Expanded(
                    child: Center(
                      child: GestureDetector(
                        onTap: _practicingPolished
                            ? () async {
                                _polishedRevealTimer?.cancel();
                                audioPlayer.stop();
                                await _buildChunks(_expandedSentence);
                                if (!mounted) return;
                                setState(() {
                                  _practicingPolished = false;
                                  _currentChunkIdx = -1;
                                  _isPlayingFullUser = false;
                                  _isPlayingFullAI = false;
                                  _aiChunkPlaying = false;
                                  _polishedRevealCount = 0;
                                });
                              }
                            : null,
                        child: Text(
                          _practicingPolished ? 'Polished' : 'Expanded',
                          style: TextStyle(
                            color: _practicingPolished
                                ? Colors.amber
                                : Colors.greenAccent,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 빌링 상태 인디케이터
                  ValueListenableBuilder<int>(
                    valueListenable: BillingTicker.instance.billingState,
                    builder: (_, s, __) => GestureDetector(
                      onTap: s == 0 ? _resetIdleTimer : null,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, right: 6),
                        child: CustomPaint(
                          size: const Size(16, 16),
                          painter: BillingDotPainter(s),
                        ),
                      ),
                    ),
                  ),
                  // P/E 버튼 — Expanded ↔ Polished 전환
                  GestureDetector(
                    onTap: _practicingPolished
                        ? () async {
                            _polishedRevealTimer?.cancel();
                            audioPlayer.stop();
                            await _buildChunks(_expandedSentence);
                            if (!mounted) return;
                            setState(() {
                              _practicingPolished = false;
                              _currentChunkIdx = -1;
                              _isPlayingFullUser = false;
                              _isPlayingFullAI = false;
                              _aiChunkPlaying = false;
                              _polishedRevealCount = 0;
                            });
                          }
                        : (_polishedSentence.isNotEmpty
                            ? _switchToPolishedPractice
                            : null),
                    // [P-PULSE] Glow the available P button in Expanded mode.
                    child: AnimatedBuilder(
                      animation: _blinkController,
                      child: Center(
                        child: Text(
                          _practicingPolished ? 'E' : 'P',
                          style: TextStyle(
                            color: _practicingPolished
                                ? Colors.greenAccent
                                : (_polishedSentence.isNotEmpty
                                    ? _pPulseColor
                                    : Colors.white24),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      builder: (context, child) {
                        // [P-PULSE] Pulse only when polished practice is available.
                        final bool pPulse = !_practicingPolished &&
                            _polishedSentence.isNotEmpty;
                        final double t = _blinkOpacity.value;
                        return Container(
                          width: 40,
                          height: 40,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _practicingPolished
                                  ? Colors.greenAccent
                                  : (_polishedSentence.isNotEmpty
                                      ? _pPulseColor
                                      : Colors.white24),
                              width: 1.5,
                            ),
                            boxShadow: pPulse
                                ? [
                                    BoxShadow(
                                      color: _pPulseColor.withValues(
                                          alpha: 0.10 + 0.35 * t),
                                      blurRadius: 5 + 8 * t,
                                      spreadRadius: 1 + 1.5 * t,
                                    ),
                                  ]
                                : null,
                          ),
                          child: child,
                        );
                      },
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() {
                      _fontScale = _fontScale == 1.0
                          ? 1.3
                          : _fontScale == 1.3
                              ? 0.8
                              : 1.0;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      child: Icon(
                        Icons.format_size,
                        color: _fontScale > 1.0
                            ? const Color(0xFFFBBF24)
                            : _fontScale < 1.0
                                ? Colors.white38
                                : Colors.white54,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Step Expand 방: Practice 탭 바
            if (_isStepExpandRoom) _buildPracticeTabBar(),

            // 청크 리스트 + 버튼 영역
            Expanded(
              // [P3-INTRO] Hide and block only the body/chunk area during intro. Header/tabs stay visible.
              child: IgnorePointer(
                ignoring: _showEchoingOverlay,
                child: AnimatedOpacity(
                  opacity: _showEchoingOverlay ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 500),
                  child: _practicingPolished
                      // ── Polished 의미단위 카드 ──────────────────────────────
                      ? (_polishedUnits.isEmpty
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.amber))
                          : ListView.builder(
                              controller: _chunkScrollController,
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                              itemCount: _polishedUnits.length + 1,
                              itemBuilder: (context, i) {
                                if (i == _polishedUnits.length) {
                                  return _buildPracticeButtonsInline();
                                }
                                final unit = _polishedUnits[i];
                                final bool isCurrent = i == _polishedUnitIdx;
                                final bool isEven = i % 2 == 0;
                                final Color bgColor = isCurrent
                                    ? (isEven ? colorAActive : colorBActive)
                                    : (isEven ? colorA : colorB);
                                final Color borderColor = isCurrent
                                    ? (_polishedUnitAIPlaying
                                        ? const Color(0xFF5BB8F5)
                                        : _isListening
                                            ? Colors.greenAccent
                                            : Colors.amber)
                                    : Colors.amber.withValues(alpha: 0.35);
                                final Color textColor =
                                    isCurrent ? Colors.white : Colors.white70;
                                return GestureDetector(
                                  key: _polishedItemKeys.putIfAbsent(
                                      i, () => GlobalKey()),
                                  onTap: () => _onPolishedUnitTapped(i),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 13),
                                    decoration: BoxDecoration(
                                      color: bgColor,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: borderColor,
                                          width: isCurrent ? 2 : 1.5),
                                      boxShadow: isCurrent
                                          ? [
                                              BoxShadow(
                                                  color: borderColor.withValues(
                                                      alpha: 0.3),
                                                  blurRadius: 10,
                                                  spreadRadius: 1)
                                            ]
                                          : [],
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 20,
                                          child: Text('${i + 1}',
                                              style: TextStyle(
                                                  color: textColor.withValues(
                                                      alpha: 0.45),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            unit,
                                            style: TextStyle(
                                              color: textColor,
                                              fontSize: 16 * _fontScale,
                                              fontWeight: isCurrent
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              height: 1.45,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        if (isCurrent && _polishedUnitAIPlaying)
                                          const Icon(Icons.volume_up,
                                              color: Color(0xFF5BB8F5),
                                              size: 22)
                                        else if (isCurrent && _isListening)
                                          const Icon(Icons.mic,
                                              color: Colors.greenAccent,
                                              size: 22)
                                        else if (isCurrent)
                                          const Icon(Icons.play_arrow_rounded,
                                              color: Colors.amber, size: 22)
                                        else
                                          const Icon(Icons.play_arrow_rounded,
                                              color: Colors.white24, size: 22),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ))
                      // ── Expanded 청크 카드 (기존 그대로) ────────────────────
                      : (_chunks.isEmpty
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.amber))
                          : Builder(builder: (context) {
                              final int visibleCount = _chunks.length;
                              final bool showButtons = true;
                              return ListView.builder(
                                controller: _chunkScrollController,
                                cacheExtent: 1500,
                                padding:
                                    const EdgeInsets.fromLTRB(14, 4, 14, 8),
                                itemCount: visibleCount + (showButtons ? 1 : 0),
                                itemBuilder: (context, i) {
                                  if (showButtons && i == visibleCount) {
                                    return _buildPracticeButtonsInline();
                                  }
                                  final chunk = _chunks[i];
                                  final bool isCurrent = i == _currentChunkIdx;
                                  final bool isDone = chunk.isDone;
                                  final bool isEven = i % 2 == 0;

                                  final Color bgColor = isCurrent
                                      ? (isEven ? colorAActive : colorBActive)
                                      : isDone
                                          ? (isEven ? colorA : colorB)
                                              .withValues(alpha: 0.55)
                                          : (isEven ? colorA : colorB);

                                  final Color borderColor = isCurrent
                                      ? (_isListening
                                          ? Colors.greenAccent
                                          : _aiChunkPlaying
                                              ? const Color(0xFF5BB8F5)
                                              : Colors.amber)
                                      : isDone
                                          ? Colors.white12
                                          : Colors.white10;

                                  final Color textColor = isCurrent
                                      ? Colors.white
                                      : isDone
                                          ? Colors.white38
                                          : Colors.white70;

                                  return GestureDetector(
                                    key: _itemKeys.putIfAbsent(
                                        i, () => GlobalKey()),
                                    onTap: () => _onChunkTapped(i),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 220),
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 13),
                                      decoration: BoxDecoration(
                                        color: bgColor,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: borderColor,
                                            width: isCurrent ? 2 : 1),
                                        boxShadow: isCurrent
                                            ? [
                                                BoxShadow(
                                                    color: borderColor
                                                        .withValues(alpha: 0.3),
                                                    blurRadius: 10,
                                                    spreadRadius: 1)
                                              ]
                                            : [],
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 20,
                                            child: Text('${i + 1}',
                                                style: TextStyle(
                                                    color: textColor.withValues(
                                                        alpha: 0.45),
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  chunk.text,
                                                  style: TextStyle(
                                                    color: textColor,
                                                    fontSize: 16 * _fontScale,
                                                    fontWeight: isCurrent
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                    height: 1.45,
                                                  ),
                                                ),
                                                _buildChunkKoLine(
                                                    chunk), // 🆕 [KO-FRAG]
                                                if (isCurrent &&
                                                    _aiChunkLoading) ...[
                                                  const SizedBox(height: 4),
                                                  const Text(
                                                    'Thinking...',
                                                    style: TextStyle(
                                                        color:
                                                            Color(0xFF5BB8F5),
                                                        fontSize: 11),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          if (isCurrent && _isListening)
                                            const Icon(Icons.mic,
                                                color: Colors.greenAccent,
                                                size: 22)
                                          else if (isCurrent && _aiChunkPlaying)
                                            const Icon(Icons.volume_up,
                                                color: Color(0xFF5BB8F5),
                                                size: 22)
                                          else if (isDone)
                                            const Icon(Icons.check_circle,
                                                color: Colors.greenAccent,
                                                size: 20)
                                          else
                                            const Icon(Icons.play_arrow_rounded,
                                                color: Colors.white24,
                                                size: 22),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            })),
                ), // [P3-INTRO] AnimatedOpacity close
              ), // [P3-INTRO] IgnorePointer close
            ),
          ],
        ),
        // Do Echoing 팝업 오버레이
        AnimatedOpacity(
          opacity: _showEchoingOverlay ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 600),
          child: IgnorePointer(
            ignoring: !_showEchoingOverlay,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 22),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.80),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.amber.withValues(alpha: 0.18),
                        blurRadius: 24,
                        spreadRadius: 2)
                  ],
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Echo it!',
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // 📦 [Box 11-D: Step Expand Practice 1 & 2 엔진]
  // ============================================================================

  /// messages 서브컬렉션 docs → _stepExpandTurns 파싱
  List<Map<String, dynamic>> _parseStepExpandTurns(
      List<DocumentSnapshot> docs) {
    final turns = <Map<String, dynamic>>[];
    String? pendingAiText;
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final role = (data['role'] as String?) ?? '';
      final translatedText = (data['translated_text'] as String?) ?? '';
      final originalText = (data['original_text'] as String?) ?? '';
      final text = translatedText.isNotEmpty ? translatedText : originalText;
      if (role == 'SYSTEM') {
        pendingAiText = text.trim();
      } else if (role == 'HOST' && pendingAiText != null) {
        final expandedField = (data['expanded_sentence'] as String?) ?? '';
        final parts = text.split('\n\n');
        final part1 = parts[0].trim();
        String part2;
        if (expandedField.isNotEmpty) {
          part2 = expandedField.trim();
        } else {
          part2 = parts.length >= 2 ? parts.sublist(1).join('\n\n').trim() : '';
        }
        turns.add({'aiText': pendingAiText, 'part1': part1, 'part2': part2});
        pendingAiText = null;
      }
    }
    return turns;
  }

  Future<void> _startPart1Practice() async {
    if (_stepExpandTurns.isEmpty) return;
    final lines = <Map<String, dynamic>>[];
    for (final turn in _stepExpandTurns) {
      lines.add({'role': 'HOST', 'text': turn['aiText'] as String});
      lines.add({'role': 'USER', 'text': turn['part1'] as String});
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
    for (int i = 0; i < totalTurns; i++) {
      final turn = _stepExpandTurns[i];
      lines.add({'role': 'HOST', 'text': turn['aiText'] as String});
      if (i < totalTurns - 1) {
        final part2 = (turn['part2'] as String).isNotEmpty
            ? turn['part2'] as String
            : turn['part1'] as String;
        lines.add({'role': 'USER', 'text': part2});
      }
    }
    if (mounted) {
      setState(() {
        _phase = ShadowingPhase.part2Practice;
        _tutorLines = lines;
        currentIndex = 0;
        _tutorCurrentIdx = 0;
        _isAutoRecording = false;
        _tutorAwaitingStart = false; // [P2-SHADOW]
        _swapRoles = false;
        _tutorAiSpeaking = false;
        _tutorUserRecording = false;
        _tutorPlayingFullback = false;
        _showRetryHint = false;
        _shadowWords = []; // [P2-SHADOW]
        _shadowWordIdx = -1; // [P2-SHADOW]
        _shadowSpeed = 1.0;
        _selectedMeaningUnitVoice = null;
        _shadowStarted = false;
        _shadowRereadCount = 0; // [P2-PROXY]
        _showEchoingOverlay = false;
        _showShadowingOverlay = false;
      });
      _echoingOverlayTimer?.cancel();
      _shadowingOverlayTimer?.cancel();
      _shadowHighlightTimer?.cancel(); // [P2-SHADOW]
      _shadowAdvanceTimer?.cancel(); // [P2-SHADOW]
      _stopShadowAiPlayback(); // [P2-SHADOW-AI]
      _stopP2Countdown();
      // 진입 안내 뒤 학습 Voice를 선택해야만 P2가 시작된다.
      _triggerShadowingOverlay();
      _prepareP2StartAudio();
    }
  }

  static const String _p2CountdownText = 'Three, two, one, start.';

  Future<Uint8List?> _loadP2CountdownAudio() async {
    Uint8List? audio = await TtsCache.get(_p2CountdownText, 'echo');
    if (audio != null) return audio;
    audio = await _fetchOpenAITTS(_p2CountdownText, 1.0, 'echo');
    if (audio != null) TtsCache.put(_p2CountdownText, 'echo', audio);
    return audio;
  }

  void _prepareP2StartAudio() {
    // Voice 선택을 기다리는 동안 카운트다운과 첫 AI 문장을 준비한다.
    _p2CountdownGeneration++;
    _p2CountdownAudioFuture = _loadP2CountdownAudio();
    if (_tutorLines.isEmpty) return;
    final firstText = (_tutorLines.first['text'] ?? '').toString().trim();
    if (firstText.isEmpty) return;
    unawaited(() async {
      final cacheVoice = _practiceCacheVoice(_historyPracticeAiVoice);
      var audio = await TtsCache.get(firstText, cacheVoice);
      if (audio == null) {
        audio = await _fetchPracticeTTS(firstText, _historyPracticeAiVoice);
        if (audio != null) TtsCache.put(firstText, cacheVoice, audio);
      }
    }());
  }

  Future<void> _prefetchNextMeaningUnitAudio() async {
    if (_phase != ShadowingPhase.part2Practice) return;
    Map<String, dynamic>? nextLine;
    for (int i = currentIndex; i < _tutorLines.length; i++) {
      final line = _tutorLines[i];
      if ((line['role'] as String?) == 'USER') {
        nextLine = line;
        break;
      }
    }
    if (nextLine == null) return;
    final text = (nextLine['text'] ?? '').toString().trim();
    if (text.isEmpty) return;
    final voice = _selectedMeaningUnitVoice;
    if (voice == null) return;
    await _getMeaningUnitTTS(text, voice);
  }

  Future<void> _startP2AfterCountdown() async {
    if (_p2CountdownStarting || !mounted) return;
    _p2CountdownStarting = true;
    final generation = _p2CountdownGeneration;
    try {
      final future = _p2CountdownAudioFuture ?? _loadP2CountdownAudio();
      final audio = await future.timeout(
        const Duration(seconds: 4),
        onTimeout: () => null,
      );
      if (!mounted ||
          generation != _p2CountdownGeneration ||
          _phase != ShadowingPhase.part2Practice ||
          !_shadowStarted ||
          isPaused) {
        return;
      }
      if (audio != null) {
        final player = AudioPlayer();
        _p2CountdownPlayer = player;
        final completed = player.onPlayerComplete.first;
        final cancelled = Completer<void>();
        _p2CountdownCancel = cancelled;
        try {
          await player.play(BytesSource(audio));
          await Future.any([completed, cancelled.future])
              .timeout(const Duration(seconds: 8));
        } catch (e) {
          debugPrint('[P2 countdown] $e');
        } finally {
          if (identical(_p2CountdownCancel, cancelled)) {
            _p2CountdownCancel = null;
          }
          if (identical(_p2CountdownPlayer, player)) {
            _p2CountdownPlayer = null;
          }
          await player.dispose();
        }
      }
      if (mounted &&
          generation == _p2CountdownGeneration &&
          _phase == ShadowingPhase.part2Practice &&
          _shadowStarted &&
          !isPaused) {
        _startTurnPractice();
      }
    } finally {
      if (generation == _p2CountdownGeneration) {
        _p2CountdownStarting = false;
      }
    }
  }

  Future<void> _stopP2Countdown() async {
    _p2CountdownGeneration++;
    _p2CountdownStarting = false;
    _p2CountdownAudioFuture = null;
    final cancelled = _p2CountdownCancel;
    _p2CountdownCancel = null;
    if (cancelled != null && !cancelled.isCompleted) cancelled.complete();
    final player = _p2CountdownPlayer;
    _p2CountdownPlayer = null;
    if (player != null) {
      await player.stop();
    }
  }

  // 🆕 [EXPAND-FROM-CHAT v2] 대화 전체(AI+유저) → 종합 확장 문장 1개 (의미단위 ~5개, 문법 연결)
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

  String _inferHistoryMode(Map<String, dynamic>? data) {
    final mode = _normalizeHistoryMode(_historyString(data, 'mode'));
    if (mode.isNotEmpty) return mode;
    final room = _historyString(data, 'room_name');
    if (room == 'Clone Mode') return 'clone';
    if (room == 'Roleplay Mode') return 'roleplay';
    if (room == 'FreeTalk Mode' || room == 'Free Talk Mode') return 'free_talk';
    if (room == 'Anyone') return 'free_talk';
    if (room == 'Duo Mode' || room == 'Duo Connect Mode') return 'duo';
    if (room == 'Step.Ex Mode' || room == 'Step Expand Mode') {
      return 'step_expand';
    }
    return '';
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
    _shadowingOverlayTimer?.cancel();
    _echoingOverlayTimer?.cancel();
    unawaited(_stopP3Shadowing(resetSelection: true));
    if (mounted) {
      setState(() {
        _isAutoRecording = false;
        _showRetryHint = false;
        _currentChunkIdx = -1;
        _phase = ShadowingPhase.chunkPractice;
        _showShadowingOverlay = false;
        _showEchoingOverlay = false;
        _selectedP3LearningVoice = null;
        _selectedP3NativeVoice = null;
        _p3UsesNativeStyle = null;
        _p3ShadowComplete = false;
      });
    }
  }

  void _switchToPractice(int practiceNum) {
    if (!mounted) return;
    _stopAutoVADRecording();
    audioPlayer.stop();
    _shadowHighlightTimer?.cancel(); // [P2-SHADOW]
    _shadowAdvanceTimer?.cancel(); // [P2-SHADOW]
    _stopShadowAiPlayback(); // [P2-SHADOW-AI]
    _stopShadowRecording(); // [P2-SHADOW-REC]
    _stopP2Countdown();
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
    return Stack(
      children: [
        Column(
          children: [
            _buildPracticeTabBar(),
            Expanded(
              child: IgnorePointer(
                ignoring: _showShadowingOverlay,
                child: AnimatedOpacity(
                  opacity: _showShadowingOverlay ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 500),
                  child: Column(
                    children: [
                      if (_phase == ShadowingPhase.part2Practice)
                        _buildMeaningUnitVoiceSelector(),
                      Expanded(child: _buildTurnPracticeScreen()),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        AnimatedOpacity(
          opacity: _showShadowingOverlay ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 600),
          child: IgnorePointer(
            ignoring: !_showShadowingOverlay,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 22),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.80),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withValues(alpha: 0.18),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Text(
                  'Thought-group\nShadowing',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ),
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

  // P2 상단 오른쪽: 의미단위 쉐도잉 전용 학습 Voice.
  Widget _buildMeaningUnitVoiceSelector() {
    final busy = _shadowAiPlayer != null || _shadowRecording;
    final needsSelection = _selectedMeaningUnitVoice == null;
    final selector = Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Text(
              '학습용 의미단위 쉐도잉 보이스 선택',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: needsSelection ? Colors.amber : Colors.white54,
                fontSize: 11,
                fontWeight: needsSelection ? FontWeight.bold : FontWeight.w500,
                shadows: needsSelection
                    ? const [
                        Shadow(color: Colors.amber, blurRadius: 10),
                      ]
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            height: 36,
            padding: const EdgeInsets.only(left: 12, right: 8),
            decoration: BoxDecoration(
              color: needsSelection
                  ? Colors.amber.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: needsSelection ? Colors.amber : Colors.white24,
                width: needsSelection ? 1.5 : 1,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedMeaningUnitVoice,
                hint: const Text(
                  '선택',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                dropdownColor: const Color(0xFF232323),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: busy ? Colors.white24 : Colors.amber,
                  size: 18,
                ),
                style: TextStyle(
                  color: busy ? Colors.white38 : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                items: _meaningUnitVoiceOptions
                    .map(
                      (voice) => DropdownMenuItem<String>(
                        value: voice,
                        child: Text(
                          '${voice[0].toUpperCase()}${voice.substring(1)}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (voice) {
                        if (voice == null ||
                            voice == _selectedMeaningUnitVoice) {
                          return;
                        }
                        final firstSelection = !_shadowStarted;
                        setState(() {
                          _selectedMeaningUnitVoice = voice;
                          if (firstSelection) _shadowStarted = true;
                        });
                        unawaited(_prefetchNextMeaningUnitAudio());
                        if (firstSelection &&
                            _phase == ShadowingPhase.part2Practice &&
                            !isPaused) {
                          unawaited(_startP2AfterCountdown());
                        }
                      },
              ),
            ),
          ),
        ],
      ),
    );
    if (!needsSelection) return selector;
    return AnimatedBuilder(
      animation: _blinkController,
      builder: (_, child) =>
          Opacity(opacity: _blinkOpacity.value, child: child),
      child: selector,
    );
  }

  Widget _buildStepExpandSelectScreen() {
    final bool hasData = _stepExpandTurns.isNotEmpty;
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
                  "어떤 연습부터 시작할까요?",
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
          _buildPracticeSelectionCard(
            title: "Practice 1",
            subtitle: "AI 질문 + 단답 역할교환 (5턴)",
            color: Colors.greenAccent,
            icon: Icons.swap_horiz_rounded,
            onTap: hasData ? _startPart1Practice : null,
          ),
          const SizedBox(height: 12),
          _buildPracticeSelectionCard(
            title: "Practice 2",
            subtitle: "AI 질문 + 확장문장 역할교환 (4턴+AI)",
            color: Colors.lightBlueAccent,
            icon: Icons.expand_more_rounded,
            onTap: hasData ? _startPart2Practice : null,
          ),
          const SizedBox(height: 12),
          _buildPracticeSelectionCard(
            title: "Practice 3",
            subtitle: _isPreparingStepP3
                ? "P3 준비 중... P1/P2는 바로 시작할 수 있어요"
                : (_stepP3PreparationError ?? "전체 문장 의미단위 쉐도잉"),
            color: Colors.amber,
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
            child: const Text("취소",
                style: TextStyle(color: Colors.white38, fontSize: 14)),
          ),
        ],
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
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.15),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: color,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12, height: 1.3)),
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
                    color: color.withValues(alpha: 0.6), size: 22),
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

  static Future<void> clearRoom(String historyId) async {
    if (historyId.isEmpty) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/tts_cache/$historyId');
      if (await folder.exists()) await folder.delete(recursive: true);
    } catch (_) {}
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

// 말풍선 위쪽 삼각형 화살표 페인터
class _UpTrianglePainter extends CustomPainter {
  final Color color;
  const _UpTrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_UpTrianglePainter old) => old.color != color;
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
