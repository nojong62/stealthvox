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
  bool _showOriginal = true;
  bool isLoadingRoom = true;
  String roomName = "";
  String _debugLogs = "";
  bool _isActionLocked = false;

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

  // 📦 [Box 4-B: 양방향 턴제 연습 엔진 상태]
  int currentIndex = 0;

  bool _isAutoRecording = false;
  Timer? _silenceTimer;
  int _silenceCounter = 0;
  bool _hasSpoken = false;

  // 📦 [Box 4-C: Step Expand Practice 1 & 2 상태]
  bool _isStepExpandRoom = false;
  List<Map<String, dynamic>> _stepExpandTurns = [];
  // P1/P2 "Please try again" 힌트 표시 여부
  bool _showRetryHint = false;

  // 🆕 [P2-INDICATOR] AI 청크 발화 중 여부 (인디케이터 빛남용)
  bool _aiChunkPlaying = false;
  // AI TTS 로딩 중 (재생 전 Thinking... 표시용)
  bool _aiChunkLoading = false;
  // 🆕 [P2-INDICATOR] AI 다시 듣기 모드 (true이면 끝나도 마이크 자동 ON 안 함)
  bool _isReplayMode = false;

  // 🆕 [CHUNK-PRACTICE] 의미단위 연습 모드 상태
  bool _practicingPolished = false; // false = expanded, true = polished
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
  String _selectedPracticeVoice = 'nova';
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
  Uint8List? _appCorrectedAudio;
  bool _appIsShadowRecording = false;
  bool _isPlayingAppAudio = false;
  String? _shadowRecordPath;
  String _appTranscript = "";

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
    BillingTicker.instance.setRate(BillingRate.discounted);
    BillingTicker.instance.resume();

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
    _utteranceSafetyTimer?.cancel();
    _silenceTimer?.cancel();
    _roleBubbleTimer?.cancel();
    _blinkController.dispose();
    _echoingOverlayTimer?.cancel();
    _polishedRevealTimer?.cancel();
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
    _tutorAudioPlayer?.dispose();
    _appCorrectedAudio = null;
    if (_appIsRecording || _appIsShadowRecording) {
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
        roomName = data['room_name'] ?? "History Master";
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
    await [Permission.microphone, Permission.storage].request();
  }

  // 📦 [Box 11-Room: 방 단위 진입 라우터]
  // 🔧 [TUTOR-FIX] 방 종류에 따라 분기:
  //   - polished/expanded 있음 (Step Expand 방) → 기존 Shadowing variantSelect
  //   - polished/expanded 없음 (Clone/Roleplay/Duo 방) → Tutor 모드
  Future<void> _enterShadowingFromRoom() async {
    _debugLogs = "=== ROOM PRACTICE ENTRY ===\n";
    _debugLogs += "시각: ${DateTime.now()}\n";
    _debugLogs += "방 ID: ${widget.historyDoc.id}\n\n";
    try {
      final snap = await widget.historyDoc.get();
      if (!mounted) return;
      final data = snap.data() as Map<String, dynamic>?;

      if (data == null) {
        _debugLogs += "❌ 방 데이터 없음 → 진입 차단\n";
        _showRoomEntryToast("연습할 대화가 없습니다");
        return;
      }

      final polished = (data['polished_sentence'] as String?) ?? '';
      final expanded = (data['expanded_sentence'] as String?) ?? '';

      _debugLogs +=
          "polished_sentence: ${polished.isEmpty ? '(없음)' : polished}\n";
      _debugLogs +=
          "expanded_sentence: ${expanded.isEmpty ? '(없음)' : expanded}\n\n";

      // Step Expand 방: messages 로드 + _stepExpandTurns 파싱 → variantSelect(3버튼)
      if (polished.isNotEmpty || expanded.isNotEmpty) {
        _debugLogs += "✅ Step Expand 방 분기 → messages 로드 + variantSelect\n";
        _polishedSentence = polished;
        _expandedSentence = expanded.isNotEmpty ? expanded : polished;
        _polishedLoadDone = true;
        _entryMessageDocId = null;
        _practicingPolished = false;

        // messages 서브컬렉션 로드 및 _stepExpandTurns 파싱
        try {
          final msgSnap = await widget.historyDoc
              .collection('messages')
              .orderBy('created_at', descending: false)
              .get();
          if (mounted) {
            _stepExpandTurns = _parseStepExpandTurns(msgSnap.docs);
            _debugLogs += "Step Expand 턴 수: ${_stepExpandTurns.length}\n";
          }
        } catch (e) {
          _debugLogs += "⚠️ messages 로드 실패: $e\n";
        }
        if (!mounted) return;

        // P3 즉시 진입을 위해 chunks 미리 빌드
        await _buildChunks(_expandedSentence);
        if (!mounted) return;

        if (mounted) {
          setState(() {
            _isStepExpandRoom = true;
            isPracticeMode = true;
            _phase = ShadowingPhase.variantSelect;
          });
        }
        _prefetchAllChunkAI();
        return;
      }

      // Clone / Roleplay / Duo 방: messages 서브컬렉션 → Tutor 모드
      _debugLogs += "✅ Tutor 모드 분기 → messages 서브컬렉션 조회\n";
      final messagesSnap = await widget.historyDoc
          .collection('messages')
          .orderBy('created_at', descending: false)
          .get();
      if (!mounted) return;

      final tutorLines = messagesSnap.docs
          .map((doc) {
            final d = doc.data();
            return <String, dynamic>{
              'role': d['role'] ?? 'HOST',
              'text':
                  (d['translated_text'] ?? d['original_text'] ?? '').toString(),
            };
          })
          .where((m) => (m['text'] as String).isNotEmpty)
          .toList();

      if (tutorLines.isEmpty) {
        _debugLogs += "❌ chat_lines 없음 → 진입 차단\n";
        _showRoomEntryToast("아직 연습할 대화가 없습니다");
        return;
      }

      _debugLogs += "✅ 턴제 연습 진입: ${tutorLines.length}줄 로드\n";
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
      _debugLogs += "💥 예외: $e\n";
      _showRoomEntryToast("연습 진입 실패: $e");
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

  // 🆕 [TUTOR] chat_lines 처음부터 끝까지 TTS 자동 재생
  Future<void> _startTutorPlayback() async {
    if (!mounted) return;
    if (mounted) setState(() => _isTutorPlaying = true);

    for (int i = 0; i < _tutorLines.length; i++) {
      if (!mounted || !_isTutorPlaying) break;
      final line = _tutorLines[i];
      final text = line['text'] as String;
      final bool isAi = (line['role'] as String) == 'HOST';

      if (mounted) {
        setState(() {
          _tutorCurrentIdx = i;
          _tutorIsAiTurn = isAi;
        });
      }

      await _playTutorLineTTS(text, isAi);

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
    final voice = isAi ? 'nova' : FFAppState().aiVoice;
    try {
      Uint8List? audio = await TtsCache.get(text, voice);
      if (audio != null) {
        _debugLogs += "💾 [캐시 HIT-TTS공유] _playTutorLineTTS\n";
      } else {
        _debugLogs += "🌐 [캐시 MISS→API] _playTutorLineTTS\n";
        audio = await _fetchOpenAITTS(text, 1.0, voice);
        if (audio != null) {
          TtsCache.put(text, voice, audio);
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
        await player.play(BytesSource(audio));
        await completer.future
            .timeout(const Duration(seconds: 30), onTimeout: () {});
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
    _debugLogs += "⏹️ [TUTOR] 사용자 종료 요청\n";
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
    _roleBubbleTimer?.cancel();
    _roleBubbleTimer = Timer(const Duration(milliseconds: 2800), () {
      if (mounted) setState(() => _showRoleBubble = false);
    });
  }

  // 📦 [BOX-30: 시작 화면 - 선택값 반영하여 진행]
  void _confirmStart({required bool swap}) {
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
    if (!mounted || _tutorLines.isEmpty) return;
    currentIndex = 0;
    if (mounted) setState(() => _tutorCurrentIdx = 0);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollPracticeToIndex(0));
    _checkAndStartTurn();
  }

  void _nextTurn() {
    if (!mounted || !isPracticeMode || isPaused) return;
    final next = currentIndex + 1;
    if (next >= _tutorLines.length) {
      if (mounted) {
        setState(() {
          currentIndex = next;
          _tutorCurrentIdx = next;
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
      });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollPracticeToIndex(next));
    _checkAndStartTurn();
  }

  void _forceNextTurn() {
    _stopAutoVADRecording();
    audioPlayer.stop();
    _nextTurn();
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
    if (mounted) setState(() => _tutorAiSpeaking = true); // 🆕 [BOX-31]
    await _playSmartAudio(text);
  }

  // 🔧 [v3.7] TtsCache 우선 조회 → MISS 시 API 호출 후 캐시 저장
  Future<void> _playSmartAudio(String text) async {
    if (_apiKey.isEmpty || text.trim().isEmpty) return;
    try {
      Uint8List? audio = await TtsCache.get(text, 'nova');
      if (audio != null) {
        _debugLogs += "💾 [캐시 HIT-TTS공유] _playSmartAudio\n";
      } else {
        _debugLogs += "🌐 [캐시 MISS→API] _playSmartAudio\n";
        audio = await _fetchOpenAITTS(text, 1.0, 'nova');
        if (audio != null) {
          TtsCache.put(text, 'nova', audio);
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
        _nextTurn();
      }
    } catch (e) {
      debugPrint("[playSmartAudio] $e");
      if (mounted && isPracticeMode) _nextTurn();
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

  Future<void> _processAutoVADRecording(String path) async {
    if (!mounted || !isPracticeMode || currentIndex >= _tutorLines.length)
      return;
    final targetText = (_tutorLines[currentIndex]['text'] as String).trim();
    try {
      final uri = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $_apiKey';
      request.fields['model'] = 'whisper-1';
      request.files.add(await http.MultipartFile.fromPath('file', path));
      final streamed =
          await request.send().timeout(const Duration(seconds: 10));
      final body = await streamed.stream.bytesToString();
      if (!mounted || !isPracticeMode) return;
      if (streamed.statusCode == 200) {
        final transcript = (jsonDecode(body)['text'] as String? ?? '').trim();
        final tWords = targetText
            .toLowerCase()
            .split(RegExp(r'\W+'))
            .where((w) => w.length > 1)
            .toSet();
        final sWords = transcript
            .toLowerCase()
            .split(RegExp(r'\W+'))
            .where((w) => w.length > 1)
            .toSet();
        final similarity = tWords.isEmpty
            ? 1.0
            : tWords.intersection(sWords).length / tWords.length;
        if (similarity >= 0.5) {
          // 🆕 [BOX-34] 유저 녹음 경로 캐시
          if (currentIndex < _tutorLines.length) {
            _tutorLines[currentIndex]['user_record_path'] = path;
          }
          _nextTurn();
        } else {
          if ((_phase == ShadowingPhase.part1Practice ||
                  _phase == ShadowingPhase.part2Practice) &&
              mounted) {
            setState(() => _showRetryHint = true);
            await Future.delayed(const Duration(milliseconds: 1800));
            if (mounted) setState(() => _showRetryHint = false);
          }
          if (isPracticeMode && !isPaused) _startAutoVADRecording();
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
    _debugLogs = "=== PRACTICE ENTRY DEBUG ===\n";
    _debugLogs += "시각: ${DateTime.now()}\n";
    _debugLogs += "DocId: $docId\n\n";
    _debugLogs += "[메시지 문서 필드]\n";
    _debugLogs +=
        "translated_text: ${rawText.length > 100 ? rawText.substring(0, 100) + '...' : rawText}\n";
    _debugLogs +=
        "expanded_sentence (직접): ${directExpanded.isEmpty ? '(없음/비어있음)' : directExpanded}\n\n";

    if (directExpanded.isNotEmpty) {
      _expandedSentence = directExpanded;
      _debugLogs += "✅ [진입조건] 1순위: expanded_sentence 직접 사용\n";
      _debugLogs += "_expandedSentence 확정값: $_expandedSentence\n";
    } else {
      final parts = rawText.split(RegExp(r'\n\s*\n'));
      _expandedSentence = parts.length >= 2
          ? parts.sublist(1).join('\n\n').trim()
          : rawText.trim();
      _debugLogs += "⚠️ [진입조건] expanded_sentence 없음 → fallback\n";
      _debugLogs += "split 결과 파트 수: ${parts.length}\n";
      _debugLogs += "_expandedSentence fallback 값: $_expandedSentence\n";
    }

    _debugLogs += "\n[Practice 진입 가능 여부]\n";
    _debugLogs += "_expandedSentence 비어있음: ${_expandedSentence.isEmpty}\n";
    _debugLogs +=
        "→ ${_expandedSentence.isNotEmpty ? '✅ 진입 허용' : '❌ 차단: expanded 없음'}\n";
    _debugLogs += "\n[polished_sentence 로딩 시작 전]\n";

    _polishedSentence = "";
    _entryMessageDocId = docId;
    _practicingPolished = false;
    await _buildChunks(_expandedSentence);

    if (mounted) {
      setState(() {
        isPracticeMode = true;
        _phase = ShadowingPhase.chunkPractice;
        _currentChunkIdx = -1;
      });
      _triggerEchoingOverlay();
    }
    _loadPolishedSentence();
    _prefetchAllChunkAI();
    Future.delayed(Duration.zero, () {
      if (mounted &&
          _phase == ShadowingPhase.chunkPractice &&
          _chunks.isNotEmpty &&
          _currentChunkIdx == -1) {
        _onChunkTapped(0);
      }
    });
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
      _debugLogs += "[historyDoc 필드 목록]\n";
      _debugLogs +=
          "polished_sentence: ${directPolished == null ? '(null)' : directPolished.isEmpty ? '(빈 문자열)' : directPolished}\n";
      _debugLogs +=
          "expanded_sentence: ${roomData['expanded_sentence'] ?? '(null)'}\n";
      _debugLogs += "session_ref: ${roomData['session_ref'] ?? '(null)'}\n\n";

      if (directPolished != null && directPolished.isNotEmpty) {
        debugPrint("[loadPolishedSentence] 1순위: polished_sentence 직접 읽기 성공");
        _debugLogs += "✅ [polished 로딩] 1순위: polished_sentence 직접 읽기 성공\n";
        _debugLogs += "polished 확정값: $directPolished\n";
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
        _debugLogs += "⚠️ [polished 로딩] 1순위 실패 → 2순위: expanded_sentence 보정\n";
        _debugLogs += "expanded 보정값: $directExpanded\n";
        if (mounted) setState(() => _expandedSentence = directExpanded);
      } else {
        _debugLogs += "⚠️ [polished 로딩] 1순위 실패, 2순위 expanded도 없음\n";
      }

      // ── 3순위: session_ref로 refined_sentence fallback 조회 ──────
      final sessionRef = roomData['session_ref'] as String?;
      if (sessionRef == null || sessionRef.isEmpty) {
        debugPrint("[loadPolishedSentence] 3순위: session_ref 없음 → 종료");
        _debugLogs +=
            "❌ [polished 로딩] 3순위: session_ref 없음 → polished 없음으로 종료\n";
        if (mounted) setState(() => _polishedLoadDone = true);
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _debugLogs += "❌ [polished 로딩] 3순위: currentUser null → 종료\n";
        if (mounted) setState(() => _polishedLoadDone = true);
        return;
      }

      debugPrint("[loadPolishedSentence] 3순위: session_ref=$sessionRef 조회 시도");
      _debugLogs += "[polished 로딩] 3순위: session_ref=$sessionRef 조회 시도\n";
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
        _debugLogs += "✅ [polished 로딩] 3순위: refined_sentence fallback 성공\n";
        _debugLogs += "polished fallback값: $fallbackPolished\n";
        setState(() {
          _polishedSentence = fallbackPolished;
          _polishedLoadDone = true;
        });
      } else {
        debugPrint("[loadPolishedSentence] 3순위: refined_sentence 없음");
        _debugLogs +=
            "❌ [polished 로딩] 3순위: refined_sentence도 없음 → polished 최종 없음\n";
        setState(() => _polishedLoadDone = true);
      }
    } catch (e) {
      debugPrint("[loadPolishedSentence] 예외: $e");
      _debugLogs += "💥 [polished 로딩] 예외 발생: $e\n";
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

    _debugLogs += "\n=== VARIANT 선택 ===\n";
    _debugLogs +=
        "선택: ${variant == SentenceVariant.polished ? 'Polished' : 'Expanded'}\n";
    _debugLogs += "사용 문장(${sentence.length}자): $sentence\n";
    _debugLogs +=
        "_apiKey: ${_apiKey.isEmpty ? '❌ 비어있음 → TTS 전체 실패' : '✅ 로드됨 (${_apiKey.length}자)'}\n";
    _debugLogs +=
        "_deepgramKey: ${_deepgramKey.isEmpty ? '❌ 비어있음 → 마이크 녹음 차단' : '✅ 로드됨 (${_deepgramKey.length}자)'}\n";

    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/tts_cache/${widget.historyDoc.id}');
      _debugLogs += "\n=== 캐시 디렉토리 스냅샷 ===\n";
      _debugLogs += "경로: ${folder.path}\n";
      if (await folder.exists()) {
        final files = await folder.list().toList();
        _debugLogs += "파일 ${files.length}개:\n";
        for (final f in files) {
          _debugLogs += "  ${f.path.split('/').last}\n";
        }
      } else {
        _debugLogs += "디렉토리 없음 (첫 진입)\n";
      }
    } catch (e) {
      debugPrint("[cacheSnapshot] $e");
    }
    if (!mounted) return;

    await _buildChunks(sentence);

    _debugLogs += "\n=== CHUNKS 생성 결과 ===\n";
    _debugLogs += "청크 수: ${_chunks.length}개\n";
    if (_chunks.isEmpty) {
      _debugLogs += "❌ 청크 0개 → Practice 화면 스피너만 표시됨\n";
      _debugLogs += "원인: 문장에 [,.!?] 구분자 없거나 문장 자체가 비어있음\n";
    } else {
      for (int i = 0; i < _chunks.length; i++) {
        _debugLogs += "  [${i + 1}] ${_chunks[i].text}\n";
      }
    }

    if (mounted) setState(() => _phase = ShadowingPhase.practicing);
    _prefetchAllChunkAI();
  }

  void _exitShadowing() {
    _deleteUserRecordings(); // 🆕 Practice 임시 녹음 파일 정리
    _stopTutorPlayback();
    _stopAutoVADRecording();
    _utteranceSafetyTimer?.cancel();
    _polishedRevealTimer?.cancel();
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
      _debugLogs += "📊 [chunkSplit] 답변 갯수 N=$n (HOST 메시지 ${hostCount}개)\n";
      return n;
    } catch (e) {
      debugPrint("[fetchUserTurnCount] $e");
      _debugLogs += "⚠️ [chunkSplit] 답변 갯수 조회 실패 → fallback\n";
      return 0;
    }
  }

  // [chunkSplit] GPT-4o-mini로 문장을 n조각으로 분할
  Future<List<String>?> _splitSentenceByTurns(String sentence, int n) async {
    if (_apiKey.isEmpty || sentence.isEmpty || n <= 0) return null;
    try {
      final prompt =
          'Split the following English sentence into exactly $n meaningful, '
          'natural-sounding chunks for speaking practice. '
          'Return ONLY a JSON array of strings with no extra text or explanation. '
          'Example for n=3: ["chunk one", "chunk two", "chunk three"]\n\n'
          'Sentence: "$sentence"';
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
                {'role': 'user', 'content': prompt}
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
      return list
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint("[splitSentenceByTurns] $e");
      return null;
    }
  }

  // [chunkSplit] 기존 정규식 분할 (fallback용)
  List<String> _buildChunksLegacyList(String sentence) {
    const abbrevs = ['Mr', 'Mrs', 'Ms', 'Dr', 'Prof', 'Sr', 'Jr', 'St'];
    String temp = sentence;
    for (final abbr in abbrevs) {
      temp = temp.replaceAll('$abbr.', '$abbr․');
    }
    final splitRe = RegExp(
      r'(?<=[,.!?])\s+|'
      r'\s+(?=(?:who|whom|whose|which|that|where|when|while|because|since|although|though|if|unless|but|and|so)\b)',
      caseSensitive: false,
    );
    final rawParts = temp
        .split(splitRe)
        .map((s) => s.trim().replaceAll('․', '.'))
        .where((s) => s.isNotEmpty)
        .toList();
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
    return merged;
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

  // [chunkCache] 디스크에서 분할 결과 읽기
  Future<List<String>?> _readChunkCache(String variant, String sentence) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final roomId = widget.historyDoc.id;
      final hash = _chunkTextHash(sentence);
      final file = File(
          '${dir.path}/chunk_cache/chunk_split_${roomId}_${variant}_$hash.json');
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final list = jsonDecode(content) as List;
      final result =
          list.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      _debugLogs += "✅ [chunkCache] HIT chunks=${result.length}\n";
      return result;
    } catch (e) {
      debugPrint("[readChunkCache] $e");
      return null;
    }
  }

  // [chunkCache] 디스크에 분할 결과 저장
  Future<void> _writeChunkCache(
      String variant, String sentence, List<String> chunks) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final roomId = widget.historyDoc.id;
      final hash = _chunkTextHash(sentence);
      final folder = Directory('${dir.path}/chunk_cache');
      if (!await folder.exists()) await folder.create(recursive: true);
      final file =
          File('${folder.path}/chunk_split_${roomId}_${variant}_$hash.json');
      await file.writeAsString(jsonEncode(chunks));
      _debugLogs += "💿 [chunkCache] 저장 완료 chunks=${chunks.length}\n";
    } catch (e) {
      debugPrint("[writeChunkCache] $e");
    }
  }

  Future<void> _buildChunks(String sentence) async {
    if (sentence.isEmpty) {
      _chunks = [];
      _currentChunkIdx = 0;
      return;
    }
    final isPolished =
        _polishedSentence.isNotEmpty && sentence == _polishedSentence;
    final variant = isPolished ? 'polished' : 'expanded';

    // 1. 디스크 캐시 확인
    final cached = await _readChunkCache(variant, sentence);
    if (cached != null && cached.isNotEmpty) {
      _chunks = cached.map((t) => PracticeChunk(text: t)).toList();
      _currentChunkIdx = 0;
      return;
    }
    _debugLogs += "🌐 [chunkCache] MISS → GPT 호출 시도\n";

    // 2. HOST 답변 갯수 조회 후 GPT 분할
    final n = await _fetchUserTurnCount();
    if (n > 0) {
      _debugLogs += "📊 [chunkSplit] 답변 갯수 N=$n → GPT 분할 시도\n";
      final gptChunks = await _splitSentenceByTurns(sentence, n);
      if (gptChunks != null && gptChunks.isNotEmpty) {
        final result = gptChunks.take(10).toList();
        _debugLogs += "✅ [chunkSplit] 완료 chunks=${result.length}\n";
        _chunks = result.map((t) => PracticeChunk(text: t)).toList();
        _currentChunkIdx = 0;
        await _writeChunkCache(variant, sentence, result);
        return;
      }
    }

    // 3. Fallback: 정규식 분할
    _debugLogs += "⚠️ [chunkSplit] GPT 실패 → 정규식 fallback\n";
    final legacy = _buildChunksLegacyList(sentence);
    _chunks = legacy.map((t) => PracticeChunk(text: t)).toList();
    _currentChunkIdx = 0;
  }

  void _triggerEchoingOverlay() {
    if (!mounted) return;
    setState(() => _showEchoingOverlay = true);
    _echoingOverlayTimer?.cancel();
    _echoingOverlayTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _showEchoingOverlay = false);
    });
  }

  Future<void> _prefetchAllChunkAI() async {
    _debugLogs += "\n=== TTS PREFETCH 시작 ===\n";
    if (_apiKey.isEmpty) {
      _debugLogs += "❌ _apiKey 없음 → prefetch 전체 스킵됨\n";
    }
    for (int i = 0; i < _chunks.length; i++) {
      if (!mounted ||
          (_phase != ShadowingPhase.practicing &&
              _phase != ShadowingPhase.chunkPractice)) {
        _debugLogs += "⚠️ prefetch 중단 (phase 변경 또는 unmount) at i=$i\n";
        break;
      }
      if (_chunks[i].aiAudio != null) {
        _debugLogs += "💾 [캐시 HIT-메모리] prefetch idx=$i\n";
        continue;
      }
      try {
        await _getOrFetchChunkAudio(i);
      } catch (e) {
        debugPrint("[prefetchAllChunkAI] $e");
        _debugLogs += "💥 청크[$i] TTS 예외: $e\n";
      }
    }
    _debugLogs += "=== TTS PREFETCH 완료 ===\n";
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
    _debugLogs += "\n=== 마이크 녹음 시도 ===\n";
    if (_deepgramKey.isEmpty) {
      _debugLogs += "❌ _deepgramKey 없음 → 녹음 차단\n";
      return;
    }
    if (_isListening) {
      _debugLogs += "⚠️ 이미 녹음 중 → 중복 호출 무시\n";
      return;
    }
    _pcmBuffer = BytesBuilder();
    try {
      if (mounted) setState(() => _isListening = true);

      final micStatus = await Permission.microphone.status;
      _debugLogs += "마이크 권한: $micStatus\n";
      if (!micStatus.isGranted) {
        _debugLogs += "❌ 마이크 권한 없음 → 녹음 실패 원인\n";
      }

      final stream = await appAudioRecorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ));
      _debugLogs += "✅ AudioRecorder startStream 성공\n";

      _dgSocket = await WebSocket.connect(
        'wss://api.deepgram.com/v1/listen'
        '?model=nova-2'
        '&language=en-US'
        '&encoding=linear16'
        '&sample_rate=16000'
        '&utterance_end_ms=1200'
        '&vad_events=true'
        '&interim_results=true',
        headers: {'Authorization': 'Token $_deepgramKey'},
      );
      _debugLogs += "✅ Deepgram WebSocket 연결 성공\n";

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
              _debugLogs += "🎙 UtteranceEnd 감지 → 녹음 종료 처리\n";
              _onUserUtteranceEnd();
            }
          } catch (_) {}
        },
        onError: (e) {
          debugPrint("[Deepgram] error: $e");
          _debugLogs += "💥 Deepgram 소켓 오류: $e\n";
        },
        onDone: () {
          debugPrint("[Deepgram] socket closed");
          _debugLogs += "⚠️ Deepgram 소켓 closed\n";
        },
      );

      _utteranceSafetyTimer?.cancel();
      _utteranceSafetyTimer = Timer(const Duration(seconds: 10), () {
        if (mounted && _isListening) {
          _debugLogs += "⏱ 10초 safety timer 발동 → 강제 종료\n";
          _onUserUtteranceEnd();
        }
      });
    } catch (e) {
      debugPrint("[startDualCapture] $e");
      _debugLogs += "💥 startDualCapture 예외: $e\n";
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
      _debugLogs += "[chunkFetch] in-flight 재사용 idx=$idx\n";
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
    final cacheKey = 'chunk_${variant}_$idx.mp3';
    if (chunk.aiAudio != null) {
      _debugLogs += "💾 [캐시 HIT-메모리] fetchInternal idx=$idx\n";
      return chunk.aiAudio;
    }
    if (_phase != ShadowingPhase.turnPractice) {
      final diskHit = await _AudioDiskCache.read(historyId, cacheKey);
      if (diskHit != null && mounted && idx < _chunks.length) {
        setState(() => _chunks[idx].aiAudio = diskHit);
        _debugLogs += "💾 [캐시 HIT-디스크] fetchInternal key=$cacheKey\n";
        return diskHit;
      }
    }
    _debugLogs += "🌐 [캐시 MISS→API] fetchInternal key=$cacheKey\n";
    // 🔧 [정상속도] formatForSlowRhythm 제거 → 텍스트 그대로 TTS
    final audio = await _fetchOpenAITTS(chunk.text, 1.0, 'nova');
    if (!mounted) return null;
    if (audio != null && idx < _chunks.length) {
      setState(() => _chunks[idx].aiAudio = audio);
      if (_phase != ShadowingPhase.turnPractice) {
        await _AudioDiskCache.write(historyId, cacheKey, audio);
        _debugLogs +=
            "💿 [디스크 저장] fetchInternal key=$cacheKey (${audio.length}b)\n";
      }
      _debugLogs += "✅ 청크[$idx] TTS 성공 (${audio.length} bytes)\n";
    } else {
      _debugLogs += "❌ 청크[$idx] TTS 실패: audio=null\n";
    }
    return audio;
  }

  // 📦 [Box 14: AI 청크 재생]
  Future<void> _playCurrentChunkAI() async {
    if (_currentChunkIdx >= _chunks.length) return;
    await _playChunkAI(_currentChunkIdx);
  }

  Future<void> _playChunkAI(int idx) async {
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
      if (audio != null) await audioPlayer.play(BytesSource(audio));
    } catch (e) {
      debugPrint("[playChunkAI] $e");
      _debugLogs += "💥 [AI재생] 예외: $e\n";
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
    _debugLogs += "🔁 [P2-REPLAY] 청크[$idx] 다시 듣기 요청\n";
    if (idx >= _chunks.length) return;
    // 1. 진행 중인 녹음 즉시 취소
    if (_isListening) {
      _stopDeepgramListening();
      _debugLogs += "🔁 [P2-REPLAY] 녹음 중단됨\n";
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
    _debugLogs += "🔁 [P2-REPLAY] AI 재생 완료 — 마이크 대기 (사용자 누를 때까지)\n";
  }

  // 🆕 [P2-REPLAY] 사용자가 마이크 버튼을 명시적으로 눌렀을 때 호출
  //   - Replay 모드 해제 후 일반 녹음 시작
  void _userTriggeredRecord() {
    _debugLogs += "🎤 [P2-USER-REC] 사용자 녹음 버튼 클릭\n";
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
    if (text.isEmpty) return;
    final historyId = widget.historyDoc.id;
    final variant =
        _selectedVariant == SentenceVariant.polished ? 'pol' : 'exp';
    final cacheKey = 'full_${variant}_${_hashText(text)}.mp3';
    // TODO: LRU 정리 — 30개 초과 시 가장 오래된 것부터 제거
    if (_fullAIAudioCache.containsKey(cacheKey)) {
      _debugLogs += "💾 [캐시 HIT-메모리] _playRhythmAudio key=$cacheKey\n";
      await audioPlayer.play(BytesSource(_fullAIAudioCache[cacheKey]!));
      return;
    }
    // 대화방 공유 캐시(TtsCache) 확인 — 같은 문장을 대화방에서 들었으면 API 0회
    final ttsHit = await TtsCache.get(text, _selectedPracticeVoice);
    if (ttsHit != null && mounted) {
      _debugLogs += "💾 [캐시 HIT-TTS공유] _playRhythmAudio key=$cacheKey\n";
      _fullAIAudioCache[cacheKey] = ttsHit;
      await audioPlayer.play(BytesSource(ttsHit));
      return;
    }
    if (_phase != ShadowingPhase.turnPractice) {
      final diskHit = await _AudioDiskCache.read(historyId, cacheKey);
      if (diskHit != null && mounted) {
        _debugLogs += "💾 [캐시 HIT-디스크] _playRhythmAudio key=$cacheKey\n";
        _fullAIAudioCache[cacheKey] = diskHit;
        await audioPlayer.play(BytesSource(diskHit));
        return;
      }
    }
    _debugLogs += "🌐 [캐시 MISS→API] _playRhythmAudio key=$cacheKey\n";
    // 🔧 [정상속도] formatForSlowRhythm 제거 → 텍스트 그대로 TTS
    Uint8List? audio = await _fetchOpenAITTS(text, 1.0, _selectedPracticeVoice);
    if (!mounted) return;
    if (audio != null) {
      _fullAIAudioCache[cacheKey] = audio;
      await TtsCache.put(text, _selectedPracticeVoice, audio);
      if (_phase != ShadowingPhase.turnPractice) {
        await _AudioDiskCache.write(historyId, cacheKey, audio);
        _debugLogs +=
            "💿 [디스크 저장] _playRhythmAudio key=$cacheKey (${audio.length}b)\n";
      }
      await audioPlayer.play(BytesSource(audio));
    }
  }

  // 히스토리 말풍선 소리듣기 — msgId 기반 디스크 캐시 우선
  Future<void> _playMsgAudio(String msgId, String text) async {
    if (text.isEmpty || _apiKey.isEmpty) return;
    final historyId = widget.historyDoc.id;
    final cacheKey = 'native_$msgId.mp3';
    final diskHit = await _AudioDiskCache.read(historyId, cacheKey);
    if (diskHit != null) {
      await audioPlayer.play(BytesSource(diskHit));
      return;
    }
    final audio = await _fetchOpenAITTS(text, 1.0, 'nova');
    if (audio == null || !mounted) return;
    await _AudioDiskCache.write(historyId, cacheKey, audio);
    await audioPlayer.play(BytesSource(audio));
  }

  // OpenAI TTS 헬퍼
  Future<Uint8List?> _fetchOpenAITTS(
      String text, double speed, String voice) async {
    if (_apiKey.isEmpty || text.trim().isEmpty) return null;
    try {
      var response = await http.post(
        Uri.parse('https://api.openai.com/v1/audio/speech'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json'
        },
        body: jsonEncode(
            {'model': 'tts-1', 'input': text, 'voice': voice, 'speed': speed}),
      );
      return response.statusCode == 200 ? response.bodyBytes : null;
    } catch (e) {
      debugPrint("[fetchOpenAITTS] $e");
      return null;
    }
  }

  // 📦 [Box 16-C: 통합 디버그 팝업 — 🐛 버튼 탭 또는 롱프레스로 호출]
  Future<void> _showDebugPopup() async {
    // ── 1. Firestore 상태 조회 ──────────────────────────────
    String firestoreSection = "=== [1] Firestore 데이터 상태 ===\n";
    firestoreSection += "시각: ${DateTime.now()}\n";
    firestoreSection += "문서 ID: ${widget.historyDoc.id}\n\n";

    try {
      final snap = await widget.historyDoc.get();
      final data = snap.data() as Map<String, dynamic>?;

      final expandedSentence = (data?['expanded_sentence'] as String?) ?? '';
      final polishedSentence = (data?['polished_sentence'] as String?) ?? '';
      final hasPractice = data?['has_practice']?.toString() ?? 'false';
      final canEnterPractice = polishedSentence.isNotEmpty;

      firestoreSection += "expanded_sentence:\n"
          "${expandedSentence.isEmpty ? '없음' : expandedSentence}\n\n";
      firestoreSection += "polished_sentence:\n"
          "${polishedSentence.isEmpty ? '없음' : polishedSentence}\n\n";
      firestoreSection += "has_practice: $hasPractice\n\n";
      firestoreSection += "연습 모드 진입 가능 여부:\n"
          "${canEnterPractice ? '✅ 가능 (polished_sentence 존재)' : '❌ 불가 (polished_sentence 없음)'}\n";
    } catch (e) {
      firestoreSection += "❌ 데이터 로딩 실패: $e\n";
    }

    // ── 2. 메모리 상태 (현재 위젯 상태 변수) ───────────────
    final memorySection = """
=== [2] 메모리 상태 ===
isPracticeMode: $isPracticeMode
_phase: $_phase
_expandedSentence(${_expandedSentence.length}자): ${_expandedSentence.isEmpty ? '없음' : _expandedSentence}
_polishedSentence(${_polishedSentence.length}자): ${_polishedSentence.isEmpty ? '없음' : _polishedSentence}
_polishedLoadDone: $_polishedLoadDone
_chunks: ${_chunks.length}개
_currentChunkIdx: $_currentChunkIdx
_apiKey: ${_apiKey.isEmpty ? '❌ 없음' : '✅ (${_apiKey.length}자)'}
_deepgramKey: ${_deepgramKey.isEmpty ? '❌ 없음' : '✅ (${_deepgramKey.length}자)'}
""";

    // ── 3. 누적 흐름 로그 ──────────────────────────────────
    final flowSection = "=== [3] 누적 흐름 로그 ===\n"
        "${_debugLogs.isEmpty ? '(아직 Practice 진입 기록 없음)' : _debugLogs}";

    final fullLog = "$firestoreSection\n$memorySection\n$flowSection";

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.bug_report, color: Colors.amber, size: 20),
              SizedBox(width: 8),
              Text("Debug 상태 확인",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 420,
            child: SingleChildScrollView(
              child: SelectableText(
                fullLog,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    height: 1.6),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("닫기", style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text("로그 전체 복사",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: const Color(0xFF121212),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: fullLog));
                Navigator.pop(dialogContext);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("로그가 복사되었습니다"),
                    duration: Duration(seconds: 2),
                    backgroundColor: Color(0xFF2C2C2E),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
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
            initialChildSize: 0.65,
            minChildSize: 0.45,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollController) => SingleChildScrollView(
              controller: scrollController,
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
          .setRate(BillingRate.discounted); // 튜터링 종료 → discounted 복귀
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
        border: Border.all(color: Colors.amber.withOpacity(0.25)),
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
              GestureDetector(
                onTap: closeAccordion,
                child: const Icon(Icons.close, color: Colors.white38, size: 18),
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
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withOpacity(0.35)),
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
                              ? Colors.redAccent.withOpacity(0.15)
                              : Colors.white.withOpacity(0.05),
                          border: Border.all(
                            color: _appIsRecording
                                ? Colors.redAccent
                                : Colors.white38,
                            width: _appIsRecording ? 2.5 : 1.5,
                          ),
                          boxShadow: _appIsRecording
                              ? [
                                  BoxShadow(
                                      color: Colors.redAccent.withOpacity(0.3),
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
                          ? Colors.greenAccent.withOpacity(0.6)
                          : Colors.white24),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 14),
            ],

            const SizedBox(height: 18),

            // 하단 버튼
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: _appIsRecording ? null : closeAccordion,
                  child: const Text("Close",
                      style: TextStyle(color: Colors.white54, fontSize: 14)),
                ),
                ElevatedButton.icon(
                  onPressed: (isGeneratingApp || _appIsRecording)
                      ? null
                      : () {
                          setState(() {
                            _appCorrection = "";
                            _appCorrectedAudio = null;
                            _appTranscript = "";
                          });
                          _generateAppText(baseText);
                        },
                  icon: const Icon(Icons.refresh, size: 15),
                  label: const Text("Another Sentence",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: const Color(0xFF121212),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),

            // 투명 말풍선 (STT 결과) - 화면 최하단
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
          ],
        ],
      ),
    );
  }

  // 📦 [Box 18: AI 튜터링 - 응용 문장 생성 API 호출]
  Future<void> _generateAppText(String baseText) async {
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
          'temperature': 0.9,
          'response_format': {'type': 'json_object'},
          'messages': [
            {
              'role': 'system',
              'content':
                  r"""You are a grammar application tutor. Keep only the core grammar pattern (tense/structure/word order) of the input English sentence, and create one completely NEW Korean sentence with entirely different words and context, plus one natural English answer for that Korean sentence. reply ONLY in JSON: {"ko": "새 한국어 문장", "en": "영어 정답"}""",
            },
            {
              'role': 'user',
              'content': 'Input English sentence: "$baseText"',
            },
          ],
        }),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final jsonResult = jsonDecode(data['choices'][0]['message']['content']);
        setState(() {
          appOriginalText = (jsonResult['ko'] as String? ?? '').trim();
          _appAnswerEn = (jsonResult['en'] as String? ?? '').trim();
          appCorrectedText = "";
          _appCorrection = "";
        });
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
      request.fields['model'] = 'whisper-1';
      request.fields['language'] = 'en';
      request.files.add(await http.MultipartFile.fromPath('file', path));
      final streamed =
          await request.send().timeout(const Duration(seconds: 15));
      final body = await streamed.stream.bytesToString();
      if (!mounted) return;
      final transcript = (jsonDecode(body)['text'] as String? ?? '').trim();

      if (mounted) {
        setState(() => _appTranscript = transcript);
        _dialogSetState?.call(() {});
      }

      // 2. GPT correction + reason (English only, pure pronunciation/grammar evaluation)
      final corrPrompt = '''You are an English pronunciation and grammar coach.

[TARGET_EN_FIXED]: "$targetEn"
[USER_SPEECH]: "$transcript"

RULES — follow exactly:
1. [TARGET_EN_FIXED] is the absolute correct answer. You must NEVER rephrase, reword, or replace it with any other sentence.
2. Compare [USER_SPEECH] against [TARGET_EN_FIXED] only. No other reference exists.
3. If [USER_SPEECH] matches [TARGET_EN_FIXED] closely (minor STT noise allowed):
   - Set "corrected_en" to the exact text of [TARGET_EN_FIXED].
   - Set "reason_ko" to a single short praise sentence in Korean.
4. If [USER_SPEECH] differs from [TARGET_EN_FIXED]:
   - Set "corrected_en" to the minimally corrected version that moves [USER_SPEECH] toward [TARGET_EN_FIXED] (fix only what is wrong: pronunciation spelling, grammar, word order, or tense).
   - Set "reason_ko" to 1-3 Korean sentences explaining what was wrong (specify which of: 발음, 문법, 어순, 시제). Do NOT write sentences that redefine [TARGET_EN_FIXED] as a different sentence.
5. Output ONLY valid JSON with exactly these two keys: {"corrected_en": "...", "reason_ko": "..."}''';

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
        _debugLogs += "[튜터링-교정] TARGET_EN_FIXED = \"$targetEn\"\n";
        _debugLogs += "[튜터링-교정] USER_SPEECH     = \"$transcript\"\n";
        if (mounted)
          setState(() => _appCorrection = "$correctedEn\n\n$reasonKo");
        _dialogSetState?.call(() {});

        // Step 3: TTS 생성 → 자동 재생
        if (correctedEn.isNotEmpty) {
          final corrCacheKey = 'correction_${correctedEn.hashCode.abs()}.mp3';
          Uint8List? cachedAudio;
          if (_phase != ShadowingPhase.turnPractice) {
            cachedAudio =
                await _AudioDiskCache.read(widget.historyDoc.id, corrCacheKey);
            if (cachedAudio != null)
              _debugLogs += "💾 [캐시 HIT-디스크] correction key=$corrCacheKey\n";
          }
          final ttsAudio =
              cachedAudio ?? await _fetchOpenAITTS(correctedEn, 1.0, 'nova');
          if (cachedAudio == null && ttsAudio != null) {
            _debugLogs += "🌐 [캐시 MISS→API] correction key=$corrCacheKey\n";
            if (_phase != ShadowingPhase.turnPractice) {
              await _AudioDiskCache.write(
                  widget.historyDoc.id, corrCacheKey, ttsAudio);
              _debugLogs +=
                  "💿 [디스크 저장] correction key=$corrCacheKey (${ttsAudio.length}b)\n";
            }
          }
          if (mounted && ttsAudio != null) {
            setState(() {
              _appCorrectedAudio = ttsAudio;
              _isPlayingAppAudio = true;
            });
            _dialogSetState?.call(() {});
            await audioPlayer.play(BytesSource(ttsAudio));
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
    if (_appCorrectedAudio == null || !mounted) return;
    setState(() => _isPlayingAppAudio = true);
    _dialogSetState?.call(() {});
    try {
      await audioPlayer.play(BytesSource(_appCorrectedAudio!));
    } catch (e) {
      debugPrint("[playAppCorrectedAudio] $e");
    } finally {
      if (mounted) setState(() => _isPlayingAppAudio = false);
      _dialogSetState?.call(() {});
    }
  }

  // 📦 [Box 18-E: 실전 튜터링 - 쉐도잉 녹음 시작 (교정 TTS 1회 재생 후 녹음)]
  Future<void> _startShadowRecord() async {
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
        await audioPlayer.play(BytesSource(_appCorrectedAudio!));
        await completer.future
            .timeout(const Duration(seconds: 20), onTimeout: () {});
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
    final path = await appAudioRecorder.stop();
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
                onLongPress: _showDebugPopup,
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
                onLongPress: _showDebugPopup,
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
            Expanded(child: _buildShadowingPracticeBody()),
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
                onLongPress: _showDebugPopup,
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
                onLongPress: _showDebugPopup,
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
                onLongPress: _showDebugPopup,
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
                onLongPress: _showDebugPopup,
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
                onLongPress: _showDebugPopup,
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
    if (_isActionLocked) return;
    _isActionLocked = true;
    try {
      FocusScope.of(context).unfocus();
      final appState = FFAppState();
      if (appState.remainingTime <= 0) {
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
                    padding: const EdgeInsets.all(12),
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
          IconButton(
            icon: Icon(
              Icons.format_size,
              color: _fontScale > 1.0
                  ? const Color(0xFFFBBF24)
                  : _fontScale < 1.0
                      ? Colors.white38
                      : Colors.white70,
              size: 22,
            ),
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
              painter: _LangIconPainter(active: _showOriginal),
            ),
            tooltip: _showOriginal ? '원어 숨기기' : '원어 보기',
            onPressed: () => setState(() => _showOriginal = !_showOriginal),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          GestureDetector(
            onLongPress: () {
              _showDebugPopup();
            },
            child: IconButton(
              icon: Icon(
                isPracticeMode ? Icons.close : Icons.record_voice_over,
                color: Colors.amber,
                size: 28,
              ),
              tooltip: isPracticeMode ? "연습 종료" : "쉐도잉 연습 시작",
              onPressed: () {
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
                        ? Colors.greenAccent.withOpacity(0.15)
                        : Colors.white.withOpacity(0.05),
                    border: Border.all(
                      color: isUserActive ? Colors.greenAccent : Colors.white24,
                      width: isUserActive ? 2.5 : 1.0,
                    ),
                    boxShadow: isUserActive
                        ? [
                            BoxShadow(
                                color: Colors.greenAccent.withOpacity(0.35),
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
                        ? Colors.amber.withOpacity(0.15)
                        : Colors.white.withOpacity(0.05),
                    border: Border.all(
                      color: isAIActive ? Colors.amber : Colors.white24,
                      width: isAIActive ? 2.5 : 1.0,
                    ),
                    boxShadow: isAIActive
                        ? [
                            BoxShadow(
                                color: Colors.amber.withOpacity(0.35),
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
                  // 말풍선 본체
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75),
                      decoration: BoxDecoration(
                        color: isHost
                            ? const Color(0xFF2C2C2E)
                            : const Color(0xFF2563EB).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: isHost
                            ? null
                            : Border.all(
                                color:
                                    const Color(0xFF2563EB).withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: isHost
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(translated,
                              textAlign:
                                  isHost ? TextAlign.right : TextAlign.left,
                              style: TextStyle(
                                  color: isHost
                                      ? Colors.white
                                      : const Color(0xFF93C5FD),
                                  fontSize: 16 * _fontScale,
                                  fontWeight: FontWeight.bold,
                                  height: 1.4)),
                          if (_showOriginal && original.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(original,
                                textAlign:
                                    isHost ? TextAlign.right : TextAlign.left,
                                style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12 * _fontScale)),
                          ],
                        ],
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
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: _deleteHistoryRoom,
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(8, 0, 4, 4),
                    child: Icon(Icons.delete_outline_rounded,
                        color: Colors.white54, size: 22),
                  ),
                ),
              ),
              const SizedBox(width: double.infinity, height: 64),
            ],
          ],
        );
      },
    );
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
                    color: Colors.greenAccent.withOpacity(0.5), width: 1.5),
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
                      color: Colors.amber.withOpacity(0.5), width: 1.5),
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
                  ? Colors.greenAccent.withOpacity(0.15)
                  : Colors.white.withOpacity(0.05),
              border: Border.all(
                color: userActive ? Colors.greenAccent : Colors.white24,
                width: userActive ? 2 : 1,
              ),
              boxShadow: userActive
                  ? [
                      BoxShadow(
                          color: Colors.greenAccent.withOpacity(0.4),
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
                  ? Colors.blue.withOpacity(0.15)
                  : Colors.white.withOpacity(0.05),
              border: Border.all(
                color: aiActive ? Colors.blue : Colors.white24,
                width: aiActive ? 2 : 1,
              ),
              boxShadow: aiActive
                  ? [
                      BoxShadow(
                          color: Colors.blue.withOpacity(0.4),
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
                    backgroundColor: Colors.amber.withOpacity(0.15),
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
                    backgroundColor: Colors.greenAccent.withOpacity(0.1),
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
                      ? Colors.greenAccent.withOpacity(0.1)
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
                      child: Text(
                        chunk.text,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14 * _fontScale,
                            height: 1.4),
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
                        ? highlightColor.withOpacity(0.15)
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
                              ? highlightColor.withOpacity(0.2)
                              : Colors.white.withOpacity(0.05),
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
                      backgroundColor: Colors.red.withOpacity(0.8),
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
  // 원래 line.role을 _swapRoles 값에 따라 동적으로 뒤집어 반환.
  bool _isAiTurn(Map<String, dynamic> line) {
    final original = (line['role'] as String) == 'HOST';
    return _swapRoles ? !original : original;
  }

  // 📦 [BOX-33: 유저 재녹음 핸들러]
  void _onTutorUserIconTap() {
    if (_tutorAwaitingStart || currentIndex >= _tutorLines.length) return;
    final line = _tutorLines[currentIndex];
    if (_isAiTurn(line)) {
      _debugLogs += "🚫 [BOX-33] 유저 아이콘 탭 — AI 차례라 무시\n";
      return;
    }
    _debugLogs += "🔁 [BOX-33] 유저 재녹음 트리거\n";
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
        final bool isAi = _isAiTurn(line);
        final text = (line['text'] as String).trim();
        if (text.isEmpty) continue;
        if (isAi) {
          Uint8List? audio = line['ai_audio_bytes'] as Uint8List?;
          if (audio != null) {
            _debugLogs += "💾 [캐시 HIT-메모리] tutor key=tutor_$i.mp3\n";
          } else {
            // 🔧 [v3.7] TtsCache 우선 조회 → MISS 시 API 호출 후 캐시+메모리 저장
            audio = await TtsCache.get(text, 'nova');
            if (audio != null) {
              _debugLogs += "💾 [캐시 HIT-TTS공유] tutor line=$i\n";
              line['ai_audio_bytes'] = audio;
            } else {
              _debugLogs += "🌐 [캐시 MISS→API] tutor line=$i\n";
              audio = await _fetchOpenAITTS(text, 1.0, 'nova');
              if (audio != null) {
                line['ai_audio_bytes'] = audio;
                TtsCache.put(text, 'nova', audio);
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
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _tutorUserRecording
                                    ? Colors.greenAccent.withOpacity(0.15)
                                    : isAwaiting
                                        ? Colors.greenAccent.withOpacity(0.08)
                                        : Colors.white.withOpacity(0.04),
                                border: Border.all(
                                  color: _tutorUserRecording
                                      ? Colors.greenAccent
                                      : isAwaiting
                                          ? Colors.greenAccent.withOpacity(0.65)
                                          : Colors.white24,
                                  width: _tutorUserRecording ? 2 : 1.5,
                                ),
                              ),
                              child: Icon(
                                Icons.person_rounded,
                                size: 24,
                                color: _tutorUserRecording
                                    ? Colors.greenAccent
                                    : isAwaiting
                                        ? Colors.greenAccent.withOpacity(0.85)
                                        : Colors.white38,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
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
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _tutorAiSpeaking
                                    ? Colors.blue.withOpacity(0.15)
                                    : isAwaiting
                                        ? Colors.blue.withOpacity(0.08)
                                        : Colors.white.withOpacity(0.04),
                                border: Border.all(
                                  color: _tutorAiSpeaking
                                      ? Colors.blue
                                      : isAwaiting
                                          ? Colors.blue.withOpacity(0.65)
                                          : Colors.white24,
                                  width: _tutorAiSpeaking ? 2 : 1.5,
                                ),
                              ),
                              child: Icon(
                                Icons.smart_toy_rounded,
                                size: 24,
                                color: _tutorAiSpeaking
                                    ? Colors.blue
                                    : isAwaiting
                                        ? Colors.blue.withOpacity(0.85)
                                        : Colors.white38,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded,
                        color: Colors.white54),
                    tooltip: "이번 차례 건너뛰기",
                    onPressed:
                        (isComplete || isAwaiting) ? null : _forceNextTurn,
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
                              ? roleColor.withOpacity(0.1)
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
                                    ? roleColor.withOpacity(0.2)
                                    : Colors.white.withOpacity(0.05),
                                border: Border.all(
                                  color: isCurrent ? roleColor : Colors.white24,
                                  width: isCurrent ? 2 : 1,
                                ),
                              ),
                              child: Icon(
                                lineIsAi
                                    ? Icons.volume_up_rounded
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
                                  Text(
                                    lineIsAi ? "AI" : "You",
                                    style: TextStyle(
                                      color: isCurrent
                                          ? roleColor
                                          : Colors.white38,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    line['text'] as String,
                                    textAlign: lineIsAi
                                        ? TextAlign.right
                                        : TextAlign.left,
                                    style: TextStyle(
                                      color: isCurrent
                                          ? Colors.white
                                          : Colors.white60,
                                      fontSize: 14 * _fontScale,
                                      height: 1.5,
                                      fontWeight: isCurrent
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
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
                                      Text("Please try again 🎙",
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
                              backgroundColor: Colors.blue.withOpacity(0.15),
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
                                  Colors.greenAccent.withOpacity(0.1),
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
    return const Text(
      "Tap your role icon",
      style: TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.bold,
        decoration: TextDecoration.none,
        shadows: [Shadow(color: Colors.black87, blurRadius: 10)],
      ),
    );
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

  // 🆕 [BOX-34-SCROLL] Practice 화면에서 현재 인덱스 아이템을 중앙으로 스크롤
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

  // 세련문장 2-3 의미단위 콜앤리스폰 연습으로 전환
  Future<void> _switchToPolishedPractice() async {
    if (_polishedSentence.isEmpty) return;
    if (_isListening) _stopDeepgramListening();
    audioPlayer.stop();
    _polishedRevealTimer?.cancel();
    final units = _splitPolishedIntoUnits(_polishedSentence);
    if (mounted) {
      setState(() {
        _practicingPolished = true;
        _polishedUnits = units;
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
    if (!mounted || idx >= _polishedUnits.length) return;
    if (mounted) setState(() => _polishedUnitAIPlaying = true);
    final text = _polishedUnits[idx];
    Uint8List? audio = await TtsCache.get(text, _selectedPracticeVoice);
    if (audio != null) {
      _debugLogs += "💾 [캐시 HIT-TTS공유] _playPolishedUnit idx=$idx\n";
    } else {
      _debugLogs += "🌐 [캐시 MISS→API] _playPolishedUnit idx=$idx\n";
      audio = await _fetchOpenAITTS(text, 1.0, _selectedPracticeVoice);
      if (audio != null) {
        TtsCache.put(text, _selectedPracticeVoice, audio);
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
                    backgroundColor: Colors.amber.withOpacity(0.1),
                    side: BorderSide(color: Colors.amber.withOpacity(0.6)),
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
                    backgroundColor: Colors.greenAccent.withOpacity(0.08),
                    side:
                        BorderSide(color: Colors.greenAccent.withOpacity(0.5)),
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

  Widget _buildChunkPracticeScreen() {
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
                    child: Container(
                      width: 26,
                      height: 26,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _practicingPolished
                              ? Colors.greenAccent
                              : (_polishedSentence.isNotEmpty
                                  ? Colors.amber
                                  : Colors.white24),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _practicingPolished ? 'E' : 'P',
                          style: TextStyle(
                            color: _practicingPolished
                                ? Colors.greenAccent
                                : (_polishedSentence.isNotEmpty
                                    ? Colors.amber
                                    : Colors.white24),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() {
                      _fontScale = _fontScale == 1.0
                          ? 1.3
                          : _fontScale == 1.3
                              ? 0.8
                              : 1.0;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.format_size,
                        color: _fontScale > 1.0
                            ? const Color(0xFFFBBF24)
                            : _fontScale < 1.0
                                ? Colors.white38
                                : Colors.white54,
                        size: 20,
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
              child: _practicingPolished
                  // ── Polished 의미단위 카드 ──────────────────────────────
                  ? (_polishedUnits.isEmpty
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.amber))
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
                                : Colors.amber.withOpacity(0.35);
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
                                              color:
                                                  borderColor.withOpacity(0.3),
                                              blurRadius: 10,
                                              spreadRadius: 1)
                                        ]
                                      : [],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      child: Text('${i + 1}',
                                          style: TextStyle(
                                              color:
                                                  textColor.withOpacity(0.45),
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
                                          color: Color(0xFF5BB8F5), size: 22)
                                    else if (isCurrent && _isListening)
                                      const Icon(Icons.mic,
                                          color: Colors.greenAccent, size: 22)
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
                          child: CircularProgressIndicator(color: Colors.amber))
                      : Builder(builder: (context) {
                          final int visibleCount = _chunks.length;
                          final bool showButtons = true;
                          return ListView.builder(
                            controller: _chunkScrollController,
                            cacheExtent: 1500,
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
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
                                          .withOpacity(0.55)
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
                                key:
                                    _itemKeys.putIfAbsent(i, () => GlobalKey()),
                                onTap: () => _onChunkTapped(i),
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
                                        width: isCurrent ? 2 : 1),
                                    boxShadow: isCurrent
                                        ? [
                                            BoxShadow(
                                                color: borderColor
                                                    .withOpacity(0.3),
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
                                                color:
                                                    textColor.withOpacity(0.45),
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold)),
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
                                            if (isCurrent &&
                                                _aiChunkLoading) ...[
                                              const SizedBox(height: 4),
                                              const Text(
                                                'Thinking...',
                                                style: TextStyle(
                                                    color: Color(0xFF5BB8F5),
                                                    fontSize: 11),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      if (isCurrent && _isListening)
                                        const Icon(Icons.mic,
                                            color: Colors.greenAccent, size: 22)
                                      else if (isCurrent && _aiChunkPlaying)
                                        const Icon(Icons.volume_up,
                                            color: Color(0xFF5BB8F5), size: 22)
                                      else if (isDone)
                                        const Icon(Icons.check_circle,
                                            color: Colors.greenAccent, size: 20)
                                      else
                                        const Icon(Icons.play_arrow_rounded,
                                            color: Colors.white24, size: 22),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        })),
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
                  color: Colors.black.withOpacity(0.80),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.amber.withOpacity(0.18),
                        blurRadius: 24,
                        spreadRadius: 2)
                  ],
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Do Echoing!',
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

  void _goToChunkPractice() {
    if (!mounted) return;
    _silenceTimer?.cancel();
    try {
      appAudioRecorder.stop();
    } catch (_) {}
    audioPlayer.stop();
    if (mounted) {
      setState(() {
        _isAutoRecording = false;
        _showRetryHint = false;
        _currentChunkIdx = -1;
        _phase = ShadowingPhase.chunkPractice;
      });
    }
    _triggerEchoingOverlay();
    Future.delayed(Duration.zero, () {
      if (mounted &&
          _phase == ShadowingPhase.chunkPractice &&
          _chunks.isNotEmpty &&
          _currentChunkIdx == -1) {
        _onChunkTapped(0);
      }
    });
  }

  void _switchToPractice(int practiceNum) {
    if (!mounted) return;
    _stopAutoVADRecording();
    audioPlayer.stop();
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
          color: isActive ? Colors.amber.withOpacity(0.18) : Colors.transparent,
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
            subtitle: "확장문장 의미단위 따라읽기",
            color: Colors.amber,
            icon: Icons.music_note_rounded,
            onTap: _goToChunkPractice,
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
    VoidCallback? onTap,
  }) {
    final bool enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.5), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.15),
                  border: Border.all(color: color.withOpacity(0.5)),
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
              Icon(Icons.chevron_right_rounded,
                  color: color.withOpacity(0.6), size: 22),
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
                    ? Colors.greenAccent.withOpacity(0.2)
                    : Colors.white.withOpacity(0.08),
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
  Uint8List? aiAudio;
  String? userRecordPath;
  bool isDone;

  PracticeChunk({
    required this.text,
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
  final bool active;
  const _LangIconPainter({required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);

    canvas
        .clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: r)));

    // 배경: 활성=파란, 비활성=어두운 회색
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()
          ..color = active ? const Color(0xFF1E7DB5) : const Color(0xFF2A2A2A));

    if (active) {
      // 짙은 파란 삼각형 (하단 우측)
      canvas.drawPath(
        Path()
          ..moveTo(size.width * 0.05, size.height)
          ..lineTo(size.width, size.height * 0.05)
          ..lineTo(size.width, size.height)
          ..close(),
        Paint()..color = const Color(0xFF0B4870),
      );
    }

    // 대각선: 활성=골드, 비활성=희미
    canvas.drawLine(
      Offset(size.width * 0.04, size.height * 0.96),
      Offset(size.width * 0.96, size.height * 0.04),
      Paint()
        ..color = active ? const Color(0xFFD4AF37) : Colors.white12
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // 원형 테두리: 활성=골드, 비활성=희미
    canvas.drawCircle(
      center,
      r - 1.5,
      Paint()
        ..color = active ? const Color(0xFFD4AF37) : Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // 상단 좌측 "T" (원어): 활성=흰색, 비활성=거의 투명
    _drawText(canvas, 'T', Offset(size.width * 0.09, size.height * 0.06),
        size.width * 0.34, active ? Colors.white : const Color(0x22FFFFFF));

    if (active) {
      // 빨간 원형 포인트 (두 언어 구분점)
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
        ..color = Colors.redAccent.withOpacity(0.65)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(size.width * 0.53, size.height * 0.11),
          Offset(size.width * 0.74, size.height * 0.32), xPaint);
      canvas.drawLine(Offset(size.width * 0.74, size.height * 0.11),
          Offset(size.width * 0.53, size.height * 0.32), xPaint);
    }

    // 하단 우측 "T" (타겟): 항상 흰색
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
