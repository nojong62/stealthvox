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

import '/custom_code/widgets/index.dart';
import '/custom_code/actions/index.dart';
import '/flutter_flow/custom_functions.dart';
import 'package:flutter/services.dart'; // 🔬 [v3.1] Clipboard용

// ====================================================================
// 📦 [Box 1: 필수 임포트]
// ====================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
// 🔧 [v3 추가] TTS 로컬 캐싱 + Firestore 저장용
import 'dart:io';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '/custom_code/actions/billing_ticker.dart';

/// ==================================================================== [Box
/// 2: 클래스 선언부]
/// ====================================================================
class RoutineModeStepExpand extends StatefulWidget {
  const RoutineModeStepExpand({super.key, this.width, this.height});
  final double? width;
  final double? height;

  @override
  State<RoutineModeStepExpand> createState() => _RoutineModeStepExpandState();
}

class _RoutineModeStepExpandState extends State<RoutineModeStepExpand> {
  // ====================================================================
  // 📦 [Box 3: 상태 변수 및 초기화]
  // ====================================================================
  String _deepgramKey = "";
  String _openAiKey = "";
  bool _isConversationActive = false;
  double _fontScale = 1.0;
  bool _showOriginal = true;
  int _turnCounter = 0;
  String? _sessionDocId; // 🔧 [v3 추가] 첫 대화 후 세션 ID (클론 변경 시 null 리셋)
  DocumentReference? _myHistoryRef; // 🔧 [히스토리] chat_history 문서 참조 (Duo 패턴)

  // ── Idle Timeout v2 ───────────────────────────────────────────────
  // 기준: "유저도 AI도 아무 작동이 없는 상태"가 연속 30초 지속되면 pause.
  //  - AI 작동 = _ttsQueueManager.isBusy (TTS 재생/대기)
  //  - 유저 작동 = _voiceManager != null (마이크 연결/녹음)
  // 1초 주기 감시 타이머가 작동 여부를 보고 idle 누적초를 증감한다.
  Timer? _idlePauseTimer;
  bool _isIdlePaused = false;
  int _idleElapsedSec = 0;

  bool get _isSystemBusy {
    final ttsBusy = _ttsQueueManager.isBusy;
    final micBusy = _voiceManager != null;
    return ttsBusy || micBusy;
  }

  void _resetIdleTimer() {
    _idleElapsedSec = 0;
    if (_isIdlePaused) {
      _isIdlePaused = false;
      if (mounted) setState(() {});
      BillingTicker.instance.resume();
      BillingTicker.instance.logMode('study_room');
    }
    _idlePauseTimer?.cancel();
    _idlePauseTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _idleTick());
  }

  void _idleTick() {
    if (!mounted) return;
    if (_isIdlePaused) return;
    // 유저나 AI가 작동 중이면 idle 누적을 멈추고 리셋
    if (_isSystemBusy) {
      _idleElapsedSec = 0;
      return;
    }
    _idleElapsedSec++;
    if (_idleElapsedSec >= 30) {
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
  // ──────────────────────────────────────────────────────────────────

  Widget _buildIdleBanner() => const SizedBox.shrink();

  Widget _buildIdleOverlay() => const SizedBox.shrink();
  // ─────────────────────────────────────────────────────────────────────────

  // 🔧 [v3.4 발화 합치기] 유저 더듬거림 대응
  // speech_final 받아도 바로 파이프라인 시작 안 하고 1.2초 대기
  // 대기 중 새 발화 오면 합쳐서 처리 (최종 한 덩어리로)
  String _pendingTranscript = ''; // 대기 중인 유저 발화 누적
  Timer? _commitTimer; // "진짜 끝났는지" 확정 타이머
  static const int COMMIT_WAIT_MS = 1200; // 발화 합치기 대기 시간
  Timer? _silenceTimer; // 첫 질문 침묵/망설임 감지 타이머
  static const int OPENING_SILENCE_SEC = 7; // 침묵 판정 대기 시간(초) — 유저 망설임 7초 대기
  bool _silenceFallbackFired = false; // 폴백 발화 후 재타이머 방지 플래그

  // 🔬 [v3.1 진단] 화면 로그 뷰어 (팝업에 쌓음)
  final List<String> _debugLogs = [];
  void _log(String tag, String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    final line = '[$ts] $tag $msg';
    print(line);
    _debugLogs.add(line);
    // 메모리 폭발 방지: 500줄 초과 시 앞에서 50줄 자르기
    if (_debugLogs.length > 500) {
      _debugLogs.removeRange(0, 50);
    }
  }

  // 🌐 [v3.1] 로비에서 선택한 언어 이름 → Deepgram/OpenAI 언어 코드 매핑
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
      default:
        return 'en'; // English 포함
    }
  }

  // 🌱 스텝익스팬드 전용 상태
  static const int MAX_TURNS = 5; // 5턴 자동 마무리 룰
  bool _isSessionComplete = false; // 5턴 완료 플래그 (마이크 잠금)
  bool _isPolishing = false; // 세련된 변형 문장 생성 중
  String _polishedSentence = ""; // 생성된 세련된 변형
  bool _showPolishButton = false; // 5턴 완료 후 "Polished Version" 버튼 표시
  final GlobalKey _polishedCardKey = GlobalKey();
  final List<String> _history = []; // polish 완성 문장 누적 (세션 간 유지)

  // 🌱 [AUTO-FLOW] 5턴 완료 후 자동 표시 상태
  String _expandedFinalSentence = ""; // 완성된 확장 문장 (별도 표시)
  bool _showExpandedFinalCard = false; // 확장 문장 카드 표시 여부
  bool _showStudyRoomPrompt = false; // "Study Room에서 연습 하세요" 표시 여부

  // 🎯 [PRACTICE] 의미단위 반복 연습 모드
  bool _isPracticeMode = false;
  List<String> _practiceUnits = [];
  int _currentUnitIdx = 0;
  bool _practiceComplete = false;
  bool _isPracticeAiSpeaking = false;
  bool _isPracticeUserListening = false;
  bool _isAiFullPlaying = false;
  bool _isUserFullPlaying = false;
  bool _isSplittingUnits = false;
  final AudioPlayer _practicePlayer = AudioPlayer();
  List<int> _userPcmAccumulator = [];
  String? _userWavPath;

  // 오디오 및 UI
  final List<Map<String, dynamic>> _localMessages = [];
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  DeepgramV2VoiceManager? _voiceManager;
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final TtsQueueManager _ttsQueueManager;

  // ⏱️ 성능 측정용 초시계
  final Stopwatch _swDeepgram = Stopwatch();
  final Stopwatch _swOpenAI = Stopwatch();
  final Stopwatch _swTTS = Stopwatch();
  String _debugResult = "⏱️ 대기 중";

  @override
  void initState() {
    super.initState();
    _ttsQueueManager = TtsQueueManager(onPlayStart: () {
      if (_swTTS.isRunning) {
        _swTTS.stop();
        if (mounted) {
          setState(() {
            _debugResult =
                "⏱️ 확정: ${_swDeepgram.elapsedMilliseconds}ms | 뇌: ${_swOpenAI.elapsedMilliseconds}ms | 입: ${_swTTS.elapsedMilliseconds}ms";
          });
        }
      }
    });

    _initPermissions();
    _fetchKeys();
    BillingTicker.instance.setRate(BillingRate.full);
    BillingTicker.instance.resume();
    BillingTicker.instance.logMode('study_room');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resetIdleTimer();
    });
  }

  @override
  void dispose() {
    _clearIdleTimers();
    BillingTicker.instance.pause();
    _stopEverything();
    _voiceManager?.dispose();
    _audioRecorder.dispose();
    _ttsQueueManager.stop();
    _practicePlayer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initPermissions() async {
    await [Permission.microphone, Permission.storage].request();
  }

  Future<void> _fetchKeys() async {
    try {
      await FirebaseRemoteConfig.instance.fetchAndActivate();
      if (mounted) {
        setState(() {
          _deepgramKey =
              FirebaseRemoteConfig.instance.getString('DeepgramAPIKey');
          _openAiKey = FirebaseRemoteConfig.instance.getString('OpenAIAPIKey');
        });
        // 키 로드 완료 → AI가 먼저 개방형 질문 발화
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startSessionWithAiQuestion();
        });
      }
    } catch (e) {
      print('❌ Key Load Error: $e');
    }
  }

  // ====================================================================
  // 🎯 [스텝익스팬드 대화 설계 원칙]
  // ====================================================================
  // 1. AI가 먼저 말한다 (AI-First)
  //    - 세션 시작 시 AI가 개방형 질문을 먼저 생성·발화
  //    - 유저는 조용히 듣다가 자연스럽게 대답
  //
  // 2. 개방형 질문 원칙 (Open-Ended Questions)
  //    - "예/아니오"로 답할 수 없는 질문만 사용
  //    - 반드시 "어떻게(How)", "왜(Why)", "어떤 면에서(What/In what way)"로 시작
  //    - 유저가 자기 생각·이야기를 자유롭게 꺼낼 수 있는 질문
  //    - 첫 질문 이후 유저의 대답에서부터 문장 확장(expand)이 시작됨
  //
  // 3. 마이크 버튼 없음 (No Mic Button)
  //    - AI 발화 완료 후 STT 자동 시작 (유저가 버튼 누를 필요 없음)
  //    - 화면 하단은 노란 불빛 인디케이터만 표시 → 채팅 공간 최대화
  // ====================================================================

  /// 세션 시작 시 AI가 먼저 개방형 질문을 발화하고, 완료 후 STT 자동 시작
  Future<void> _startSessionWithAiQuestion() async {
    if (_openAiKey.isEmpty || !mounted) return;
    if (_isSessionComplete) return;
    _resetIdleTimer();
    _isConversationActive = true;
    if (mounted) setState(() {});

    // AI 질문 버블 생성
    if (mounted) {
      setState(() {
        _localMessages.add({'role': 'SYSTEM', 'target': '', 'original': ''});
      });
      _scrollToBottom();
    }
    final int aiIdx = _localMessages.length - 1;

    final String targetLangName = FFAppState().targetLang.isNotEmpty
        ? FFAppState().targetLang
        : 'English';
    final String nativeLangName =
        FFAppState().nativeLang.isNotEmpty ? FFAppState().nativeLang : 'Korean';

    final aiStream = StepExpandBrain.streamGrammarQuestion(
      apiKey: _openAiKey,
      contextStr: '',
      turnNumber: 0,
      maxTurns: MAX_TURNS,
      myTarget: targetLangName,
      myNative: nativeLangName,
      isOpening: true,
    );

    final ChunkedTtsFetcher tts = ChunkedTtsFetcher(
      _openAiKey,
      _ttsQueueManager,
      'alloy',
      isUser: false,
      onLog: _log,
    );
    _ttsQueueManager.setUserTurn(false);
    _ttsQueueManager.setAiPaused(false);

    String aiText = '';
    String buffer = '';
    final RegExp sp = RegExp(r'[,\.?!;:。、！？…，；：\n]');

    await for (final chunk in aiStream) {
      if (!mounted || !_isConversationActive) break;
      aiText += chunk;
      buffer += chunk;
      if (mounted && aiIdx < _localMessages.length) {
        setState(() => _localMessages[aiIdx]['target'] = aiText);
      }
      _scrollToBottom();
      final matches = sp.allMatches(buffer).toList();
      if (matches.isNotEmpty) {
        final lastIdx = matches.last.end;
        final toSpeak = buffer.substring(0, lastIdx).trim();
        buffer = buffer.substring(lastIdx);
        if (toSpeak.isNotEmpty) tts.addText(toSpeak);
      }
    }
    if (buffer.trim().isNotEmpty) tts.addText(buffer.trim());

    // 🌱 스트리밍 완료 즉시 번역 시작 — TTS 재생과 병렬로 실행
    StepExpandBrain.generateCleanOriginal(
            apiKey: _openAiKey, englishText: aiText)
        .then((kor) {
      if (mounted && _localMessages.length > aiIdx) {
        setState(() => _localMessages[aiIdx]['original'] = kor);
      }
    });

    // TTS 재생 완료 대기 (최대 10초)
    int ticks = 0;
    while ((tts.pendingRequests > 0 || _ttsQueueManager.isBusy) && mounted) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (++ticks > 200) break;
    }

    // AI 발화 완료 → STT 자동 시작 (유저 버튼 불필요)
    if (mounted && _isConversationActive && !_isSessionComplete) {
      _startDeepgramListening();
    }
  }

// ====================================================================
  // 📦 [Box 3-B: 로그 뷰어 다이얼로그]
  // ====================================================================
  // 🔬 [v3.1 진단] 실시간 로그를 팝업으로 보기 (복사/새로고침/지우기)
  void _showDebugLogDialog() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xFF1A1A1A),
              insetPadding: const EdgeInsets.all(12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: SizedBox(
                width: double.maxFinite,
                height: MediaQuery.of(ctx).size.height * 0.85,
                child: Column(
                  children: [
                    // 헤더
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.bug_report,
                              color: Color(0xFFFBBF24)),
                          const SizedBox(width: 8),
                          Text('진단 로그 (${_debugLogs.length})',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                          const Spacer(),
                          IconButton(
                            icon:
                                const Icon(Icons.close, color: Colors.white70),
                            onPressed: () => Navigator.pop(dialogContext),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white24, height: 1),
                    // 로그 본문 (선택 가능)
                    Expanded(
                      child: Container(
                        color: const Color(0xFF0A0A0A),
                        padding: const EdgeInsets.all(8),
                        child: SingleChildScrollView(
                          reverse: true,
                          child: SelectableText(
                            _debugLogs.isEmpty
                                ? '(로그 없음)'
                                : _debugLogs.join('\n'),
                            style: const TextStyle(
                              color: Color(0xFFB3E5FC),
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Divider(color: Colors.white24, height: 1),
                    // 하단 3버튼
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.copy, size: 16),
                              label: const Text('전체 복사'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981)),
                              onPressed: () async {
                                final text = _debugLogs.join('\n');
                                await Clipboard.setData(
                                    ClipboardData(text: text));
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text('✅ 로그 클립보드에 복사됨'),
                                      duration: Duration(seconds: 1),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('새로고침'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3B82F6)),
                              onPressed: () => setDialogState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.delete_outline, size: 16),
                              label: const Text('지우기'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFEF4444)),
                              onPressed: () {
                                setState(() => _debugLogs.clear());
                                setDialogState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ====================================================================
  // 📦 [Box 4: 주제 관리 (5턴 사이클 + 새 주제 버튼)]
  // ====================================================================
  // 💡 매 턴마다 Firestore에 저장되므로(_saveTurnToFirestore arrayUnion)
  //    별도의 "저장 후 리셋" 로직 불필요 — 새 주제 버튼은 UI 리셋만 수행
  //    단, 완성된 문장이 없으면 유저에게 안내 다이얼로그 표시

  /// 새 주제 시작 버튼 핸들러
  /// - 이미 5턴 완료 → 즉시 리셋
  /// - 진행 중 대화 있음 → 매 턴 저장됐음을 알리고 계속/리셋 선택
  /// - 대화 전혀 없음 → "저장할 내용 없음" 안내 후 리셋
  void _showNewTopicDialog() {
    final hasUserTurn = _localMessages.any((m) => m['role'] == 'HOST');

    // 🔧 5턴 완료 상태면 이미 모두 저장된 상태 → 즉시 리셋 후 AI 먼저 질문
    if (_isSessionComplete) {
      _resetSession();
      _startSessionWithAiQuestion();
      return;
    }

    // 🔧 대화 전혀 없음 → 안내 다이얼로그
    if (!hasUserTurn) {
      showDialog(
        context: context,
        builder: (BuildContext dialogContext) => Dialog(
          backgroundColor: const Color(0xFF2C2C2E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline,
                    color: Color(0xFFFBBF24), size: 36),
                const SizedBox(height: 12),
                const Text(
                  "완성된 문장이 없으므로 저장하지 않습니다.",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  "어떻게 할까요?",
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6)),
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text("계속 진행",
                            style: TextStyle(color: Colors.white)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444)),
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _resetSession();
                          _startSessionWithAiQuestion();
                        },
                        child: const Text("리셋",
                            style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    // 🔧 진행 중 대화 있음 → 매 턴 저장됐음을 알리고 리셋 확인
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => Dialog(
        backgroundColor: const Color(0xFF2C2C2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "현재까지의 진행은 자동 저장되었습니다.",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "새 주제로 시작할까요?",
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6B7280)),
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text("취소",
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981)),
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _resetSession();
                        _startSessionWithAiQuestion();
                      },
                      child: const Text("새 주제",
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 세션 UI 리셋 (Firestore 저장은 이미 매 턴 완료됨)
  void _resetSession() {
    _stopEverything();
    if (mounted) {
      setState(() {
        _localMessages.clear();
        _turnCounter = 0;
        _sessionDocId = null;
        _myHistoryRef = null; // 🔧 [히스토리] 새 방 생성 준비
        _isSessionComplete = false;
        _isPolishing = false;
        _polishedSentence = "";
        _showPolishButton = false;
        _debugResult = "⏱️ 대기 중";
        _isPracticeMode = false;
        _practiceUnits = [];
        _currentUnitIdx = 0;
        _practiceComplete = false;
        _isPracticeAiSpeaking = false;
        _isPracticeUserListening = false;
        _isAiFullPlaying = false;
        _isUserFullPlaying = false;
        _isSplittingUnits = false;
        _expandedFinalSentence = "";
        _showExpandedFinalCard = false;
        _showStudyRoomPrompt = false;
        _silenceFallbackFired = false;
      });
    }
  }

  /// "Suggest New Sentence" 버튼 → polish 결과를 히스토리에 저장 후 루프 재시작
  void _suggestNewSentence() {
    if (_polishedSentence.isNotEmpty) {
      _history.add(_polishedSentence);
    }
    _stopEverything();
    if (mounted) {
      setState(() {
        _localMessages.clear();
        _turnCounter = 0;
        _sessionDocId = null;
        _myHistoryRef = null; // 🔧 [히스토리] 새 방 생성 준비
        _isSessionComplete = false;
        _isPolishing = false;
        _polishedSentence = "";
        _showPolishButton = false;
        _debugResult = "⏱️ 대기 중";
        _isPracticeMode = false;
        _practiceUnits = [];
        _currentUnitIdx = 0;
        _practiceComplete = false;
        _isPracticeAiSpeaking = false;
        _isPracticeUserListening = false;
        _isAiFullPlaying = false;
        _isUserFullPlaying = false;
        _isSplittingUnits = false;
        _expandedFinalSentence = "";
        _showExpandedFinalCard = false;
        _showStudyRoomPrompt = false;
        _silenceFallbackFired = false;
      });
    }
    _startSessionWithAiQuestion(); // AI가 먼저 새 개방형 질문으로 다음 세션 시작
  }

  // ====================================================================
  // 📦 [Box 4-B: 세련된 변형 문장 생성 (Polish My Sentence)]
  // ====================================================================
  // 🌱 5턴 완료 후 최종 성장 문장을 "스피킹용 쉬운 고급" 문장으로 변환
  //    → 다이얼로그로 결과 표시
  Future<void> _polishSentence() async {
    if (_isPolishing || _openAiKey.isEmpty) return;

    // 마지막 HOST 메시지의 Part2(확장 문장) 추출
    String? finalExpanded;
    for (int i = _localMessages.length - 1; i >= 0; i--) {
      if (_localMessages[i]['role'] == 'HOST') {
        final target = (_localMessages[i]['target'] ?? '').toString();
        if (target.contains('\n\n')) {
          // [v3.6] Part2 전체 추출 (sublist(1) 합치기)
          final parts = target.split(RegExp(r'\n\s*\n'));
          if (parts.length >= 2) {
            finalExpanded = parts.sublist(1).join('\n\n').trim();
            break;
          }
        } else if (target.trim().isNotEmpty) {
          finalExpanded = target.trim();
          break;
        }
      }
    }

    if (finalExpanded == null || finalExpanded.isEmpty) return;

    setState(() {
      _isPolishing = true;
      _polishedSentence = "";
    });

    try {
      final polished = await StepExpandBrain.polishSentence(
        apiKey: _openAiKey,
        originalSentence: finalExpanded,
      );
      if (mounted) {
        setState(() {
          _polishedSentence = polished;
          _isPolishing = false;
        });
        _showPolishDialog(finalExpanded!, polished);

        // Firestore 세션 문서에 refined_sentence 필드 추가
        _savePolishedToFirestore(polished);
      }
    } catch (e) {
      print("❌ polish error: $e");
      if (mounted) setState(() => _isPolishing = false);
    }
  }

  /// 세련된 변형 다이얼로그
  void _showPolishDialog(String original, String polished) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => Dialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome, color: Color(0xFFFBBF24)),
                  SizedBox(width: 8),
                  Text("Polish My Sentence",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              const Text("🌱 Your sentence:",
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 4),
              SelectableText(original,
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 16),
              const Text("✨ Polished:",
                  style: TextStyle(color: Color(0xFFFBBF24), fontSize: 12)),
              const SizedBox(height: 4),
              SelectableText(polished,
                  style: const TextStyle(
                      color: Color(0xFFA7F3D0),
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child:
                      const Text("닫기", style: TextStyle(color: Colors.white70)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Polished 문장을 Firestore에 저장
  /// 🔧 [PRACTICE-FIX] _sessionDocId가 null이어도 _myHistoryRef는 살아있을 수 있음.
  ///                  가드를 분리하여 chat_history 저장만이라도 진행되도록 보장.
  ///                  + has_practice: true 플래그를 동시에 박아 Practice 진입 트리거로 사용.
  Future<void> _savePolishedToFirestore(String polished) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      // 1. sessions 문서에 refined_sentence 저장 (sessionDocId가 있을 때만)
      if (_sessionDocId != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('sessions')
            .doc(_sessionDocId)
            .update({'refined_sentence': polished});
        _log('💾 [POLISH]', 'refined_sentence 저장 완료');
      }
      // 2. chat_history 방 문서에 polished_sentence + has_practice 저장
      //    (_sessionDocId 여부와 무관하게 _myHistoryRef가 있으면 항상 저장)
      if (_myHistoryRef != null) {
        await _myHistoryRef!.update({
          'polished_sentence': polished,
          'has_practice': true,
        });
        _log('💾 [POLISH-HIST]',
            'chat_history polished_sentence + has_practice 저장 완료');
      }
    } catch (e) {
      _log('❌ [POLISH-ERR]', '저장 실패: $e');
    }
  }

  // ====================================================================
  // 📦 [Box 4-C: inline Polish — 5턴 완료 시 자동 호출, 채팅목록에 인라인 표시]
  // ====================================================================
  Future<void> _polishSentenceInline() async {
    if (_isPolishing || _openAiKey.isEmpty) return;

    String? finalExpanded;
    for (int i = _localMessages.length - 1; i >= 0; i--) {
      if (_localMessages[i]['role'] == 'HOST') {
        final target = (_localMessages[i]['target'] ?? '').toString();
        if (target.contains('\n\n')) {
          final parts = target.split(RegExp(r'\n\s*\n'));
          if (parts.length >= 2) {
            finalExpanded = parts.sublist(1).join('\n\n').trim();
            break;
          }
        } else if (target.trim().isNotEmpty) {
          finalExpanded = target.trim();
          break;
        }
      }
    }

    if (finalExpanded == null || finalExpanded.isEmpty) return;

    if (mounted) {
      setState(() {
        _isPolishing = true;
        _polishedSentence = "";
      });
      _scrollToBottom();
    }

    try {
      final polished = await StepExpandBrain.polishSentence(
        apiKey: _openAiKey,
        originalSentence: finalExpanded,
      );
      if (mounted) {
        setState(() {
          _polishedSentence = polished;
          _isPolishing = false;
        });
        _savePolishedToFirestore(polished);
        _scrollToBottom();
      }
    } catch (e) {
      _log('❌ [POLISH-INLINE]', 'error: $e');
      if (mounted) setState(() => _isPolishing = false);
    }
  }

  // ====================================================================
  // 📦 [Box 4-C2: 5턴 완료 자동 플로우 — 확장문장 낭독 → 폴리시 생성 → 낭독 → 안내]
  // ====================================================================
  Future<void> _autoPolishAndSpeak(String expandedSentence) async {
    if (expandedSentence.isEmpty || _openAiKey.isEmpty) {
      if (mounted) setState(() => _showPolishButton = true);
      return;
    }
    if (mounted) {
      setState(() {
        _isPolishing = true;
        _polishedSentence = "";
        _showPolishButton = true;
      });
      _scrollToBottom();
    }
    try {
      final polished = await StepExpandBrain.polishSentence(
        apiKey: _openAiKey,
        originalSentence: expandedSentence,
      );
      if (!mounted) return;
      setState(() {
        _polishedSentence = polished;
        _isPolishing = false;
      });
      _savePolishedToFirestore(polished);
      // Polished 카드 상단(헤더)을 먼저 보여주고 TTS 따라 자연스럽게 내려감
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_polishedCardKey.currentContext != null) {
          Scrollable.ensureVisible(
            _polishedCardKey.currentContext!,
            alignment: 0.0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
          );
        }
      });
      // Polished 문장 한 번 낭독
      if (polished.isNotEmpty) await _practiceSpeakText(polished, 'nova');
    } catch (e) {
      _log('❌ [AUTO-POLISH]', 'error: $e');
      if (mounted) setState(() => _isPolishing = false);
    }
  }

// ====================================================================
// 📦 [Box 4-D: Practice Mode — 의미단위 반복 연습]
// ====================================================================
// 🎯 polished 문장 → 의미단위 분해 → AI 낭독 → 유저 따라 말하기 → 자동 진행
//    완료 후: AI/유저 전체 듣기(상호 배타적) + 다음 세련된 문장 버튼

  /// Practice 모드 진입 — polishedSentence를 쉼표(,) 단위로 분해 후 시작
  Future<void> _enterPracticeMode() async {
    if (_polishedSentence.isEmpty) return;
    _stopEverything();

    // 쉼표(,)로 의미단위 분리, 마지막 단위 제외 쉼표 복원
    final rawParts = _polishedSentence.split(',');
    final units = <String>[];
    for (int i = 0; i < rawParts.length; i++) {
      final t = rawParts[i].trim();
      if (t.isEmpty) continue;
      units.add(i < rawParts.length - 1 ? '$t,' : t);
    }
    if (units.isEmpty) units.add(_polishedSentence.trim());

    _userPcmAccumulator = [];
    _userWavPath = null;

    if (!mounted) return;
    setState(() {
      _practiceUnits = units;
      _isPracticeMode = true;
      _currentUnitIdx = 0;
      _practiceComplete = false;
      _isPracticeAiSpeaking = false;
      _isPracticeUserListening = false;
      _isAiFullPlaying = false;
      _isUserFullPlaying = false;
      _isSplittingUnits = false;
    });
    _scrollToBottom();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please Echo Ring'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
    await _practicePlayCurrentUnit();
  }

  /// 현재 의미단위 AI 낭독 → 유저 따라 말하기 감지
  Future<void> _practicePlayCurrentUnit() async {
    if (!mounted || _currentUnitIdx >= _practiceUnits.length) {
      if (mounted) {
        setState(() {
          _practiceComplete = true;
          _isPracticeAiSpeaking = false;
          _isPracticeUserListening = false;
        });
      }
      return;
    }
    final unit = _practiceUnits[_currentUnitIdx];
    if (mounted) {
      setState(() {
        _isPracticeAiSpeaking = true;
        _isPracticeUserListening = false;
      });
    }
    await _practiceSpeakText(unit, 'nova');
    if (!mounted) return;
    setState(() {
      _isPracticeAiSpeaking = false;
      _isPracticeUserListening = true;
    });
    _startPracticeListening();
  }

  /// 유저 따라 말하기 STT 시작 (target 언어로 인식)
  void _startPracticeListening() {
    if (_deepgramKey.isEmpty) {
      Future.delayed(const Duration(seconds: 4), _practiceAdvanceUnit);
      return;
    }
    final String targetLang = FFAppState().targetLang.isNotEmpty
        ? FFAppState().targetLang
        : 'English';
    final String dgCode = _mapLanguageToCode(targetLang);
    _voiceManager?.dispose();
    _voiceManager = DeepgramV2VoiceManager(
      apiKey: _deepgramKey,
      audioRecorder: _audioRecorder,
      langCode: dgCode,
      onLog: _log,
      onConnected: () {},
      onTranscriptUpdate: (_) {},
      onTurnEnded: (transcript) {
        if (transcript.trim().length >= 2) _practiceAdvanceUnit();
      },
      onError: (_) => _practiceAdvanceUnit(),
      onAudioData: (bytes) => _userPcmAccumulator.addAll(bytes),
    );
    _voiceManager!.connectAndStart();
  }

  /// 특정 의미단위로 점프 (의미단위 탭 시 호출)
  void _jumpToUnit(int idx) {
    _voiceManager?.dispose();
    _voiceManager = null;
    _practicePlayer.stop();
    if (!mounted) return;
    setState(() {
      _currentUnitIdx = idx;
      _practiceComplete = false;
      _isPracticeAiSpeaking = false;
      _isPracticeUserListening = false;
    });
    _practicePlayCurrentUnit();
  }

  /// 다음 의미단위로 자동 진행
  void _practiceAdvanceUnit() {
    _voiceManager?.dispose();
    _voiceManager = null;
    if (!mounted) return;
    final nextIdx = _currentUnitIdx + 1;
    setState(() {
      _currentUnitIdx = nextIdx;
      _isPracticeUserListening = false;
    });
    if (nextIdx >= _practiceUnits.length) {
      setState(() {
        _practiceComplete = true;
        _isPracticeAiSpeaking = false;
      });
      _savePracticeRecording();
    } else {
      _practicePlayCurrentUnit();
    }
  }

  Future<void> _savePracticeRecording() async {
    if (_userPcmAccumulator.isEmpty) return;
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/user_practice_record.wav';
      await File(path).writeAsBytes(_buildWav(_userPcmAccumulator));
      if (mounted) setState(() => _userWavPath = path);
    } catch (_) {}
  }

  List<int> _buildWav(List<int> pcmBytes) {
    const sampleRate = 16000;
    const numChannels = 1;
    const bitsPerSample = 16;
    const byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    const blockAlign = numChannels * bitsPerSample ~/ 8;
    final dataSize = pcmBytes.length;
    final chunkSize = 36 + dataSize;
    final header = ByteData(44);
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);
    header.setUint32(4, chunkSize, Endian.little);
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6D);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);
    header.setUint32(40, dataSize, Endian.little);
    return [...header.buffer.asUint8List(), ...pcmBytes];
  }

  /// TTS 낭독 (독립 AudioPlayer — 완료 대기 후 반환)
  Future<void> _practiceSpeakText(String text, String voice) async {
    if (text.trim().isEmpty) return;
    try {
      final cached = await TtsCache.get(text, voice);
      Uint8List bytes;
      if (cached != null && cached.isNotEmpty) {
        bytes = cached;
      } else {
        final res = await http
            .post(
              Uri.parse('https://api.openai.com/v1/audio/speech'),
              headers: {
                'Authorization': 'Bearer $_openAiKey',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'model': 'tts-1',
                'input': text,
                'voice': voice,
                'speed': 1.0,
                'response_format': 'mp3',
              }),
            )
            .timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) return;
        bytes = res.bodyBytes;
        TtsCache.put(text, voice, bytes);
      }
      final completer = Completer<void>();
      StreamSubscription? sub;
      sub = _practicePlayer.onPlayerComplete.listen((_) {
        if (!completer.isCompleted) completer.complete();
        sub?.cancel();
      });
      await _practicePlayer.play(BytesSource(bytes));
      final estSec = (bytes.length / 12000 + 5).ceil();
      await completer.future
          .timeout(Duration(seconds: estSec), onTimeout: () {});
      sub?.cancel();
    } catch (e) {
      _log('❌ [PRACTICE-SPEAK]', '$e');
    }
  }

  /// AI 전체 문장 듣기 (상호 배타적 — 유저 재생 중이면 비활성)
  Future<void> _playAiFullSentence() async {
    if (_polishedSentence.isEmpty) return;
    if (_isAiFullPlaying) {
      await _practicePlayer.stop();
      if (mounted) setState(() => _isAiFullPlaying = false);
      return;
    }
    if (_isUserFullPlaying) {
      await _practicePlayer.stop();
      if (mounted) setState(() => _isUserFullPlaying = false);
    }
    if (mounted) setState(() => _isAiFullPlaying = true);
    await _practiceSpeakText(_polishedSentence, 'nova');
    if (mounted) setState(() => _isAiFullPlaying = false);
  }

  /// 유저 전체 문장 듣기 (녹음 파일 재생, 상호 배타적)
  Future<void> _playUserFullSentence() async {
    if (_isUserFullPlaying) {
      await _practicePlayer.stop();
      if (mounted) setState(() => _isUserFullPlaying = false);
      return;
    }
    if (_userWavPath == null) return;
    if (_isAiFullPlaying) {
      await _practicePlayer.stop();
      if (mounted) setState(() => _isAiFullPlaying = false);
    }
    if (mounted) setState(() => _isUserFullPlaying = true);
    try {
      final completer = Completer<void>();
      StreamSubscription? sub;
      sub = _practicePlayer.onPlayerComplete.listen((_) {
        if (!completer.isCompleted) completer.complete();
        sub?.cancel();
      });
      await _practicePlayer.play(DeviceFileSource(_userWavPath!));
      final fileSize = await File(_userWavPath!).length();
      final estSec = (fileSize / 32000 + 5).ceil();
      await completer.future
          .timeout(Duration(seconds: estSec), onTimeout: () {});
      sub?.cancel();
    } catch (e) {
      _log('❌ [USER-PLAY]', '$e');
    }
    if (mounted) setState(() => _isUserFullPlaying = false);
  }

  /// 다음 세련된 문장 프랙티스로 이동
  void _nextSentencePractice() {
    _practicePlayer.stop();
    _suggestNewSentence();
  }

// ====================================================================
// 📦 [Box 5: Deepgram + Relay Pipeline] ← 통신로직 박스코드와 완전 일치
// ====================================================================
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (_localMessages.length <= 1) return;
        _scrollController.animateTo(_scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _stopEverything() {
    _isConversationActive = false;
    _commitTimer?.cancel();
    _commitTimer = null;
    _pendingTranscript = '';
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _voiceManager?.dispose();
    _voiceManager = null;
    _ttsQueueManager.setAiPaused(false); // 🔧 [v3.6] TTS 대기 플래그 초기화
    _ttsQueueManager.setUserTurn(false);
    _ttsQueueManager.stop();
    _practicePlayer.stop();
    if (mounted) setState(() {});
  }

  Future<void> _startDeepgramListening() async {
    if (_deepgramKey.isEmpty || !(await _audioRecorder.hasPermission())) return;
    // 🌱 5턴 완료 시 마이크 잠김 (유저가 "새 주제" 버튼 눌러야 리셋됨)
    if (_isSessionComplete) return;
    _resetIdleTimer();
    _isConversationActive = true;
    if (mounted) {
      setState(() {
        _debugResult = "⏱️ 듣는 중...";
      });
    }

    _log('🎤 [LISTEN-01]', '_startDeepgramListening 진입, VoiceManager 생성');

    // 🌐 [v3.1] 로비에서 유저가 선택한 모국어(nativeLang)로 Deepgram 인식
    // 유저가 한국어로 말하면 Deepgram이 한국어로 인식 → Brain이 영어로 번역
    final String nativeLang =
        FFAppState().nativeLang.isNotEmpty ? FFAppState().nativeLang : 'Korean';
    final String dgLangCode = _mapLanguageToCode(nativeLang);
    _log('🌐 [LANG]', 'nativeLang="$nativeLang" → Deepgram code="$dgLangCode"');

    _voiceManager = DeepgramV2VoiceManager(
      apiKey: _deepgramKey,
      audioRecorder: _audioRecorder,
      langCode: dgLangCode,
      onLog: _log, // 🔬 로그 훅 주입
      onConnected: () {
        _log('✅ [LISTEN-02]', 'onConnected 콜백 실행');
      },
      onTranscriptUpdate: (transcript) {
        _swDeepgram.reset();
        _swDeepgram.start();
        // 유저가 말을 시작하는 순간 침묵 타이머 취소 (7초 경계 발화 보호)
        if (_silenceTimer != null) {
          _silenceTimer!.cancel();
          _silenceTimer = null;
          _log('⏱️ [SILENCE-CANCEL]', '발화 감지 → 침묵 타이머 취소');
        }
      },
      onTurnEnded: (transcript) {
        _log('🔀 [LISTEN-03]', 'onTurnEnded 콜백 수신: "$transcript"');
        _swDeepgram.stop();
        _stopMicAndProcess(transcript);
      },
      onError: (err) {
        _log('❌ [LISTEN-ERR]', 'Deepgram Error: $err');
        _stopEverything();
      },
    );
    _log('🎤 [LISTEN-04]', 'connectAndStart 호출 직전');
    await _voiceManager!.connectAndStart();
    _log('🎤 [LISTEN-05]', 'connectAndStart 완료');

    // 🌱 첫 질문(턴 0)에서만 침묵/망설임 타이머 시작 — 폴백 발화 후 재설정 방지
    if (_turnCounter == 0 && _isConversationActive && !_silenceFallbackFired) {
      _silenceTimer?.cancel();
      _silenceTimer = Timer(
        const Duration(seconds: OPENING_SILENCE_SEC),
        _handleOpeningSilenceFallback,
      );
      _log('⏱️ [SILENCE-01]', '첫질문 침묵 타이머 시작 (${OPENING_SILENCE_SEC}초)');
    }
  }

  // 🔧 [v3.4] Deepgram speech_final 수신 시 호출됨
  // 1.2초 대기창 안에서 추가 발화 합치기 → 완전히 끝나면 파이프라인 시작
  void _stopMicAndProcess(String transcript) async {
    _resetIdleTimer();
    _silenceTimer?.cancel();
    _silenceTimer = null;
    final clean = transcript.trim();
    _log('🔀 [STOP-01]', 'speech_final 수신: "$clean" (len=${clean.length})');

    if (clean.length < 2) {
      _log('🔀 [STOP-02]', '너무 짧음 → "Please say that again." TTS 후 대기');
      await _voiceManager?.dispose();
      _voiceManager = null;
      _ttsQueueManager.setUserTurn(false);
      _ttsQueueManager.setAiPaused(false);
      final retryTts = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        'alloy',
        isUser: false,
        onLog: _log,
      );
      retryTts.addText('Please say that again.');
      int _retryTicks = 0;
      while ((retryTts.pendingRequests > 0 || _ttsQueueManager.isBusy) &&
          mounted) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (++_retryTicks > 200) break;
      }
      if (mounted && _isConversationActive && !_isSessionComplete) {
        _startDeepgramListening();
      }
      return;
    }

    // 🔧 기존 대기 중인 발화가 있으면 공백으로 연결 (더듬거림 합치기)
    if (_pendingTranscript.isEmpty) {
      _pendingTranscript = clean;
      _log('🔀 [STOP-03]', '신규 발화 접수. 1.2초 대기창 시작');
    } else {
      _pendingTranscript = '$_pendingTranscript $clean';
      _log('🔀 [STOP-04]', '합치기: "$_pendingTranscript" (1.2초 대기창 리셋)');
    }

    // UI: 접수된 발화를 HOST_TEMP 풍선에 실시간 반영
    if (mounted) {
      setState(() {
        _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
        _localMessages.add({
          'role': 'HOST_TEMP',
          'target': '...',
          'original': '...', // Deepgram 원문 숨기기
          'type': 'user_input',
        });
      });
    }

    // 기존 타이머 취소 (새 발화가 왔으므로 대기창 리셋)
    _commitTimer?.cancel();

    // 1.2초 후 파이프라인 시작 예약
    _commitTimer = Timer(
      const Duration(milliseconds: COMMIT_WAIT_MS),
      () => _commitAndProcess(),
    );
  }

  // 🔧 [v3.4] 1.2초 대기 후 더 이상 발화 없으면 확정 → 파이프라인 시작
  void _commitAndProcess() async {
    final committed = _pendingTranscript.trim();
    _pendingTranscript = '';
    _commitTimer = null;

    if (committed.isEmpty) {
      _log('🔀 [COMMIT-00]', '빈 발화 → 마이크 재시작');
      if (_isConversationActive) _startDeepgramListening();
      return;
    }

    _log('🔀 [COMMIT-01]', '확정: "$committed" → 파이프라인 시작');

    // 마이크/VoiceManager 정리
    await _voiceManager?.dispose();
    _voiceManager = null;
    _log('🔀 [COMMIT-02]', 'VoiceManager dispose 완료');

    _log('🔀 [COMMIT-03]', '_processRelayPipeline 호출');
    _processRelayPipeline(committed);
  }

// ====================================================================
// 📦 [Box 5-SILENCE: 첫 질문 침묵/망설임 폴백]
// ====================================================================
  /// 타겟 언어별 "편하게 마음에 떠오르는 생각을 말해 보세요" 문구
  String _getSilenceFallbackPhrase(String targetLang) {
    switch (targetLang.trim().toLowerCase()) {
      case 'english':
        return 'Feel free to share any thought that comes to mind.';
      case 'japanese':
        return '気軽に頭に浮かんだことを話してください。';
      case 'chinese':
        return '请随意说出脑海中浮现的任何想法。';
      case 'spanish':
        return 'Comparte con tranquilidad cualquier pensamiento que se te venga a la mente.';
      case 'french':
        return 'Partagez librement toute pensée qui vous vient à l\'esprit.';
      case 'german':
        return 'Teilen Sie ruhig jeden Gedanken mit, der Ihnen in den Sinn kommt.';
      case 'italian':
        return 'Condividi liberamente qualsiasi pensiero che ti viene in mente.';
      case 'portuguese':
        return 'Sinta-se à vontade para compartilhar qualquer pensamento que lhe vier à mente.';
      case 'russian':
        return 'Свободно поделитесь любой мыслью, которая приходит вам в голову.';
      case 'vietnamese':
        return 'Hãy thoải mái chia sẻ bất kỳ suy nghĩ nào xuất hiện trong tâm trí bạn.';
      case 'thai':
        return 'รู้สึกอิสระที่จะแบ่งปันความคิดใดๆ ที่ผุดขึ้นมาในใจได้เลย';
      case 'indonesian':
        return 'Silakan bagikan pikiran apa pun yang terlintas di benak Anda.';
      case 'hindi':
        return 'जो भी विचार मन में आए, बेझिझक शेयर करें।';
      case 'arabic':
        return 'لا تتردد في مشاركة أي فكرة تخطر على بالك.';
      default:
        return 'Feel free to share any thought that comes to mind.';
    }
  }

  /// 첫 질문(턴 0)에서 7초 침묵 감지 → 타겟 언어로 격려 문구 발화 후 계속 대기
  Future<void> _handleOpeningSilenceFallback() async {
    if (!mounted || !_isConversationActive || _turnCounter > 0) return;
    _log('⏱️ [SILENCE-FB]', '침묵/망설임 감지 → 격려 문구 발화 후 대기 유지');

    _silenceFallbackFired = true; // 재타이머 방지

    // 마이크 일시 정지 (TTS 피드백 방지)
    await _voiceManager?.dispose();
    _voiceManager = null;

    final String targetLangName = FFAppState().targetLang.isNotEmpty
        ? FFAppState().targetLang
        : 'English';

    _ttsQueueManager.setUserTurn(false);
    _ttsQueueManager.setAiPaused(false);

    // 타겟 언어로 "편하게 마음에 떠오르는 생각을 말해 보세요" 발화
    final fallbackTts = ChunkedTtsFetcher(
      _openAiKey,
      _ttsQueueManager,
      'alloy',
      isUser: false,
      onLog: _log,
    );
    fallbackTts.addText(_getSilenceFallbackPhrase(targetLangName));

    // TTS 재생 완료 대기
    int ticks = 0;
    while ((fallbackTts.pendingRequests > 0 || _ttsQueueManager.isBusy) &&
        mounted) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (++ticks > 200) break;
    }

    // STT 재시작 — 타이머 없이 무한 대기 (_silenceFallbackFired=true 이므로 타이머 미설정)
    if (mounted && _isConversationActive && !_isSessionComplete) {
      _startDeepgramListening();
    }
  }

// ====================================================================
// 📦 [Box 5-RETRY: 재질문 처리]
// ====================================================================
  Future<void> _handleRetryQuestion(
      String contextStr, String targetLangName) async {
    _log('🔄 [RETRY]', '재질문 모드 진입');
    _ttsQueueManager.setUserTurn(false);
    _ttsQueueManager.setAiPaused(false);

    // "다시 질문할게요." 먼저 TTS
    final phraseTts = ChunkedTtsFetcher(
      _openAiKey,
      _ttsQueueManager,
      "alloy",
      isUser: false,
      onLog: _log,
    );
    phraseTts.addText("다시 질문할게요.");

    // 새 AI 질문 버블
    if (mounted) {
      setState(() {
        // 방금 전 질문 하나만 제거 → 이전 대화 흐름은 유지
        final lastSysIdx =
            _localMessages.lastIndexWhere((m) => m['role'] == 'SYSTEM');
        if (lastSysIdx != -1) _localMessages.removeAt(lastSysIdx);
        _localMessages.add({'role': 'SYSTEM', 'target': '', 'original': ''});
      });
      _scrollToBottom();
    }
    final int aiIdx = _localMessages.length - 1;

    final aiStream = StepExpandBrain.streamGrammarQuestion(
      apiKey: _openAiKey,
      contextStr: contextStr,
      turnNumber: _turnCounter,
      maxTurns: MAX_TURNS,
      myTarget: targetLangName,
      isRetry: true,
    );

    final questionTts = ChunkedTtsFetcher(
      _openAiKey,
      _ttsQueueManager,
      "alloy",
      isUser: false,
      onLog: _log,
    );
    final HybridTtsPlayer questionHybridTts = HybridTtsPlayer(
      apiKey: _openAiKey,
      voice: 'alloy',
      onLog: _log,
    );
    String aiText = "";
    String aiOriginalRetry = "";
    String aiBuffer = "";
    bool aiRetryHasDoubleNewline = false;

    await for (final chunk in aiStream) {
      if (!aiRetryHasDoubleNewline) {
        // Part1 (영어)
        aiText += chunk;
        aiBuffer += chunk;

        if (aiText.contains('\n\n')) {
          aiRetryHasDoubleNewline = true;
          final sepIdx = aiText.indexOf('\n\n');
          final afterSep = aiText.substring(sepIdx + 2);
          aiText = aiText.substring(0, sepIdx);
          final bufSepIdx = aiBuffer.indexOf('\n\n');
          if (bufSepIdx >= 0) aiBuffer = aiBuffer.substring(0, bufSepIdx);
          if (afterSep.isNotEmpty) aiOriginalRetry += afterSep;
        } else {
          // 하이브리드: 4단어/구두점 도달 시 첫 청크 발사
          if (!questionHybridTts.firstChunkFired) {
            final cutIdx =
                questionHybridTts.onChunk(aiBuffer, questionTts, _swTTS);
            if (cutIdx >= 0) aiBuffer = aiBuffer.substring(cutIdx);
          }
        }
      } else {
        // Part2 (한국어) — TTS 금지
        aiOriginalRetry += chunk;
      }
      if (mounted && aiIdx < _localMessages.length) {
        setState(() {
          _localMessages[aiIdx]['target'] = aiText;
          _localMessages[aiIdx]['original'] = aiOriginalRetry;
        });
      }
      _scrollToBottom();
    }
    await questionHybridTts.onStreamEnd(
      fullSentence: aiText.trim(),
      remainderBuffer: aiBuffer,
      fetcher: questionTts,
      swSpeechEnd: _swTTS,
    );

    // TTS 재생 완료 대기
    int ticks = 0;
    while (phraseTts.pendingRequests > 0 ||
        questionTts.pendingRequests > 0 ||
        _ttsQueueManager.isBusy) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (++ticks > 300) break;
    }

    if (_isConversationActive) _startDeepgramListening();
  }

// ====================================================================
// 📦 [Box 5-A: 중앙 통제실 - 루틴 정석 "시간벌기 마술" 패턴]
// ====================================================================
// 🎯 핵심 전략:
//   STEP 1: 증발 검열 (고스트워드/너무 짧음 → 조용히 폐기)
//   STEP 2: HOST 풍선 + 유저 번역 스트리밍 (CoT 주어 복원)
//   STEP 3: 유저 타겟 TTS 재생 시작 (_aiPaused=true)
//   STEP 4: (병렬) AI 응답 스트리밍 + 청킹 → 큐 적재 (재생 대기)
//   STEP 5: 유저 낭독 완료 → _aiPaused=false → AI 청크 폭발
//   STEP 6: AI 역번역 + Firestore 저장 (백그라운드)
//   STEP 7: 마이크 재개방
// ====================================================================
  Future<void> _processRelayPipeline(String finalTranscript) async {
    _resetIdleTimer();
    _turnCounter++;
    final int currentTurnId = _turnCounter;
    _log('🧠 [PIPE-01]',
        'Pipeline 시작 turn=$_turnCounter input="$finalTranscript"');

    // ─────────────────────────────────────────────────────
    // STEP 1: 증발 검열 (UI 풍선 찍기 전)
    // ─────────────────────────────────────────────────────
    String lowerClean =
        finalTranscript.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    List<String> ghostWords = [
      'thank you',
      'thanks',
      'yeah',
      'okay',
      '감사합니다',
      '네',
      '응'
    ];
    bool isGhost = finalTranscript.length <= 2 ||
        (ghostWords.any((gw) => lowerClean.contains(gw)) &&
            finalTranscript.length < 20);

    if (isGhost) {
      if (mounted)
        setState(
            () => _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP'));
      if (_isConversationActive) _startDeepgramListening();
      return;
    }

    try {
      // ─────────────────────────────────────────────────────
      // STEP 2: HOST 풍선 생성 + 유저 번역 스트리밍
      // ─────────────────────────────────────────────────────
      if (mounted) {
        setState(() {
          _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
          _localMessages.add({'role': 'HOST', 'target': '', 'original': ''});
        });
        _scrollToBottom();
      }

      int hostIndex = _localMessages.length - 1;

      // 완성된 턴만 컨텍스트에 포함 (미완성 '...' 제외)
      var validMsgs = _localMessages.where((m) {
        if (m['role'] != 'HOST' && m['role'] != 'SYSTEM') return false;
        final target = (m['target'] ?? '').toString().trim();
        return target.isNotEmpty && target != '...';
      }).toList();
      if (validMsgs.length > 10)
        validMsgs = validMsgs.sublist(validMsgs.length - 10);
      String contextStr = validMsgs
          .map((m) => "${m['role'] == 'HOST' ? 'User' : 'AI'}: ${m['target']}")
          .join("\n");

      String userTargetText = "";
      String userBuffer = "";
      ChunkedTtsFetcher userTtsFetcher = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        "nova",
        onLog: _log,
      );
      final HybridTtsPlayer userHybridTts = HybridTtsPlayer(
        apiKey: _openAiKey,
        voice: 'nova',
        onLog: _log,
      );
      _ttsQueueManager.setUserTurn(true);
      _ttsQueueManager.setAiPaused(false); // 유저 청크는 즉시 재생

      // 🌐 [v3.1] 로비에서 유저가 선택한 타겟 언어로 번역
      final String targetLangName = FFAppState().targetLang.isNotEmpty
          ? FFAppState().targetLang
          : 'English';

      final userStream = StepExpandBrain.streamUserTranslation(
        apiKey: _openAiKey,
        textOriginal: finalTranscript,
        targetLang: targetLangName,
        contextStr: contextStr,
      );

      // 🌱 [StepExpand Part2만 TTS] 첫 턴은 단순 번역 (Part 구분 없음)
      //    2턴+는 "Part1\n\nPart2" 구조 → Part2만 TTS로 재생
      //    \n\n 감지 전까지는 buffer에 쌓되 TTS는 안 보냄
      //    \n\n 감지 시 buffer 리셋 → 이후 chunk부터 TTS (=Part2)
      bool evaporated = false;
      bool retried = false;
      bool corrected = false; // 유저가 AI의 오해를 정정하는 경우 → 직전 HOST+SYSTEM 쌍 삭제 후 재시작
      bool clarified = false; // 주어/목적어 모호 → AI 되묻기
      bool _part2Started = false; // \n\n 이후 진입 여부
      bool hasDoubleNewline = false; // 2파트 구조 여부
      bool firstChunkSent = false;

      await for (String chunk in userStream) {
        userTargetText += chunk;
        userBuffer += chunk;

        // 🔧 [v3.3] EVAPORATE 감지
        if (userTargetText.contains("[EVAPORATE]")) {
          evaporated = true;
          _log('⚠️ [EVAPORATE]', '증발 감지 → 턴 취소');
          break;
        }

        // 재질문 감지 (발음 불명, 문맥 불일치 등)
        if (userTargetText.contains("[RETRY]")) {
          retried = true;
          _log('⚠️ [RETRY]', '재질문 감지 → 다른 질문 생성');
          break;
        }

        // 정정 감지: 유저가 AI의 오해를 바로잡는 경우
        // → 직전 HOST(오해된 유저 발화) + SYSTEM(잘못된 AI 응답) 삭제 후 정정 발화로 재시작
        if (userTargetText.contains("[CORRECTION]")) {
          corrected = true;
          _log('🔄 [CORRECTION]', '정정 감지 → 직전 HOST+SYSTEM 삭제 후 재시작');
          break;
        }

        // 되묻기 감지: 주어/목적어 모호 → AI 되묻기
        if (userTargetText.contains("[CLARIFY]")) {
          clarified = true;
          _log('❓ [CLARIFY]', '되묻기 감지 → clarification 처리');
          break;
        }

        if (mounted && hostIndex < _localMessages.length) {
          setState(() => _localMessages[hostIndex]['target'] = userTargetText);
        }
        _scrollToBottom();

        // 🌱 \n\n 최초 감지: Part1 버퍼 폐기, Part2만 TTS
        if (!hasDoubleNewline && userTargetText.contains('\n\n')) {
          // 첫 턴(turn 1)에선 확장 없음 → Part1만 onStreamEnd에 전달, Part2 무시
          if (currentTurnId == 1) {
            final idx = userTargetText.indexOf('\n\n');
            userTargetText = userTargetText.substring(0, idx).trim();
            if (mounted && hostIndex < _localMessages.length)
              setState(
                  () => _localMessages[hostIndex]['target'] = userTargetText);
            userBuffer = userTargetText; // Part1만 onStreamEnd에 전달
            break;
          }
          hasDoubleNewline = true;
          _part2Started = true;
          final idx = userTargetText.indexOf('\n\n');
          userBuffer = userTargetText.substring(idx + 2);
          _log('🌱 [PART2-START]', 'Part2 감지 → Part1 TTS 스킵, Part2만 낭독');
          continue;
        }

        // Part1 영역: TTS 절대 발사 안 함 (화면 자막만 흐름)
        if (!_part2Started) continue;

        // Part2 하이브리드: 4단어/구두점 도달 시 첫 청크만 발사
        if (!userHybridTts.firstChunkFired) {
          final cutIdx =
              userHybridTts.onChunk(userBuffer, userTtsFetcher, _swTTS);
          if (cutIdx >= 0) {
            userBuffer = userBuffer.substring(cutIdx);
            firstChunkSent = true;
          }
        }
        if (!firstChunkSent) {
          final wordCount = userBuffer
              .trim()
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .length;
          if (wordCount >= 4) {
            userTtsFetcher.addText(userBuffer.trim());
            userBuffer = "";
            firstChunkSent = true;
          }
        }
      }

      if (evaporated) {
        if (mounted) {
          setState(() {
            if (hostIndex < _localMessages.length) {
              _localMessages.removeAt(hostIndex);
            }
          });
        }
        if (_isConversationActive && _turnCounter == currentTurnId) {
          _startDeepgramListening();
        }
        return;
      }

      if (retried) {
        _turnCounter--; // 실패한 턴은 카운트 취소
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length) {
              _localMessages.removeAt(hostIndex);
            }
          });
        }
        await _handleRetryQuestion(contextStr, targetLangName);
        return;
      }

      // 🔄 [CORRECTION] 유저가 AI의 오해를 정정
      // 직전 HOST(잘못 인식된 유저 발화) + SYSTEM(잘못된 AI 응답)을 함께 삭제하고
      // 정정된 발화(_finalTranscript)로 해당 턴을 처음부터 다시 처리
      if (corrected) {
        // 이전 turn이 없으면 (1번째 턴에서 정정 불가능) RETRY로 폴백
        if (_turnCounter < 2) {
          _turnCounter--;
          if (mounted) {
            setState(() {
              _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
              if (hostIndex < _localMessages.length) {
                _localMessages.removeAt(hostIndex);
              }
            });
          }
          await _handleRetryQuestion(contextStr, targetLangName);
          return;
        }
        _turnCounter -= 2; // 현재 턴 + 이전 잘못된 턴 카운트 취소
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            // 방금 생성한 빈 HOST 버블 제거
            if (hostIndex < _localMessages.length) {
              _localMessages.removeAt(hostIndex);
            }
            // 이전 SYSTEM(AI의 잘못된 응답) 제거
            final lastSysIdx =
                _localMessages.lastIndexWhere((m) => m['role'] == 'SYSTEM');
            if (lastSysIdx != -1) _localMessages.removeAt(lastSysIdx);
            // 이전 HOST(오해된 유저 발화) 제거
            final lastHostIdx =
                _localMessages.lastIndexWhere((m) => m['role'] == 'HOST');
            if (lastHostIdx != -1) _localMessages.removeAt(lastHostIdx);
          });
          _scrollToBottom();
        }
        // 정정된 발화로 해당 턴 재처리
        _processRelayPipeline(finalTranscript);
        return;
      }

      // ❓ [CLARIFY] 유저 발화 주어/목적어 모호 → AI 되묻기 버블 + TTS + STT 재시작
      if (clarified) {
        _turnCounter--;
        final clarifyText =
            userTargetText.replaceFirst(RegExp(r'^\[CLARIFY\]\s*'), '');
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length)
              _localMessages.removeAt(hostIndex);
            _localMessages.add(
                {'role': 'SYSTEM', 'target': clarifyText, 'original': ''});
          });
          _scrollToBottom();
        }
        _ttsQueueManager.setUserTurn(false);
        _ttsQueueManager.setAiPaused(false);
        final clarifyTts = ChunkedTtsFetcher(
          _openAiKey,
          _ttsQueueManager,
          'alloy',
          isUser: false,
          onLog: _log,
        );
        clarifyTts.addText(clarifyText);
        int waitTicks = 0;
        while ((clarifyTts.pendingRequests > 0 || _ttsQueueManager.isBusy) &&
            mounted) {
          await Future.delayed(const Duration(milliseconds: 50));
          if (++waitTicks > 200) break;
        }
        if (mounted && _isConversationActive) _startDeepgramListening();
        return;
      }

      // 🌱 [E-2] 하이브리드: remainder 발사 + 통문장 TtsCache 저장
      final String _part2FullSentence = hasDoubleNewline
          ? userTargetText.substring(userTargetText.indexOf('\n\n') + 2).trim()
          : userTargetText.trim();
      await userHybridTts.onStreamEnd(
        fullSentence: _part2FullSentence,
        remainderBuffer: userBuffer,
        fetcher: userTtsFetcher,
        swSpeechEnd: _swTTS,
      );

      // 🌱 유저 original(한국어) 역번역
      // 1턴: 전체 문장 역번역 → 대화방 표시 + Firestore 저장
      // 2턴+: Part1\n\nPart2 전체를 역번역 → 대화방에서는 Part2 한국어만 표시, Firestore에는 전체 저장
      Future<String>? userOrigFuture;
      if (currentTurnId == 1) {
        userOrigFuture = StepExpandBrain.generateCleanOriginal(
            apiKey: _openAiKey, englishText: userTargetText);
        userOrigFuture.then((cleanKorean) {
          if (mounted && _localMessages.length > hostIndex) {
            setState(() => _localMessages[hostIndex]['original'] = cleanKorean);
          }
        });
      } else if (hasDoubleNewline) {
        // 2턴+: Part1(짧은 대답)만 역번역 → 확장문장(Part2)은 한국어 불필요
        final part1English = userTargetText.substring(0, userTargetText.indexOf('\n\n')).trim();
        if (part1English.isNotEmpty) {
          userOrigFuture = StepExpandBrain.generateCleanOriginal(
              apiKey: _openAiKey, englishText: part1English);
          userOrigFuture.then((cleanKorean) {
            if (mounted && _localMessages.length > hostIndex) {
              setState(() => _localMessages[hostIndex]['original'] = cleanKorean);
            }
          });
        }
      }

      // ─────────────────────────────────────────────────────
      // 🌱 [StepExpand] 5턴 완료 조기 종료
      // 5번째 유저 답변이 _localMessages에 추가된 직후 체크
      // → AI 응답을 생성하지 않고 결과 버튼 바로 표시
      // ─────────────────────────────────────────────────────
      if (_turnCounter >= MAX_TURNS) {
        // 🌱 [LAST-TURN] 마지막 5턴 — 긴 확장 문장(30~50단어)도 끝까지 들려준 뒤 완료 처리
        // 유저 TTS fetch 완료 대기 (10초 타임아웃)
        int waitTicks = 0;
        while (userTtsFetcher.pendingRequests > 0) {
          await Future.delayed(const Duration(milliseconds: 50));
          waitTicks++;
          if (waitTicks > 200) {
            _log('⚠️ [PIPE-TIMEOUT]', '유저 TTS fetch 10초 초과, 강제 진행');
            break;
          }
        }
        // 유저 TTS 재생 완료 대기 (최대 60초)
        waitTicks = 0;
        bool _lastTurnTimedOut = false;
        while (_ttsQueueManager.isBusy) {
          await Future.delayed(const Duration(milliseconds: 50));
          waitTicks++;
          if (waitTicks > 1200) {
            _log('⚠️ [PIPE-TIMEOUT]', '유저 TTS 재생 60초 초과, 강제 진행');
            _lastTurnTimedOut = true;
            break;
          }
        }
        // 자연 종료 시 800ms 마진 (끝부분 클리핑 방지)
        if (!_lastTurnTimedOut) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
        _ttsQueueManager.setUserTurn(false);

        // Firestore 저장 (유저 턴만, AI 응답 없음)
        // 🔧 [PRACTICE-FIX] _localMessages[hostIndex]['target']은 Part1\n\nPart2 형태로 누적됨
        //    → Part2(expanded)를 expanded_sentence 필드로 별도 추출 저장 (옵션 B, 후방호환)
        final bool _hostValid = hostIndex < _localMessages.length;
        final String hostFullTarget = _hostValid
            ? ((_localMessages[hostIndex]['target']) ?? userTargetText)
                .toString()
            : userTargetText;
        final List<String> hostParts = hostFullTarget.split(RegExp(r'\n\s*\n'));
        final String hostExpanded = hostParts.length >= 2
            ? hostParts.sublist(1).join('\n\n').trim()
            : '';
        final hostLineOnly = {
          'role': 'HOST',
          'original_text': _hostValid
              ? ((_localMessages[hostIndex]['original']) ?? '').toString()
              : '',
          'translated_text': userTargetText,
          // 🔧 [PRACTICE-FIX] expanded_sentence 별도 필드 저장 (옵션 B, 후방호환)
          if (hostExpanded.isNotEmpty) 'expanded_sentence': hostExpanded,
        };
        // 🔧 [PRACTICE-FIX] 순차 await로 race 차단
        //   1) sessions 저장 (이 안에서 session_ref 백링크가 _myHistoryRef에 박힘)
        //   2) chat_history 저장 (이 안에서 _ensureHistoryRef가 _myHistoryRef를 보장)
        await _saveTurnToFirestore([hostLineOnly]);
        await _saveHistoryMessages([hostLineOnly]); // 🔧 [히스토리] 병행 저장
        // 🌱 [PRACTICE-READY] 5턴 완료 즉시 방 루트에 Practice용 데이터 박아두기
        //   - 강제 종료/크래시/뒤로가기 우회 대비
        //   - has_practice: true 가 chat_history_master 측의 Practice 진입 트리거
        //   - polished_sentence는 이후 _polishSentenceInline → _savePolishedToFirestore에서 따로 채움
        if (_myHistoryRef != null && hostExpanded.isNotEmpty) {
          try {
            await _myHistoryRef!.update({
              'expanded_sentence': hostExpanded,
              'has_practice': true,
            });
            _log('🌱 [PRACTICE-READY]',
                '방 루트에 expanded_sentence + has_practice 저장');
          } catch (e) {
            _log('❌ [PRACTICE-READY-ERR]', '$e');
          }
        }

        _stopEverything();
        if (mounted) {
          setState(() {
            _isSessionComplete = true;
            _debugResult =
                _lastTurnTimedOut ? "🎉 5턴 완료! (긴 문장으로 일부 강제 종료)" : "🎉 5턴 완료!";
          });
        }
        _log('🌱 [DONE]', '5턴 완료 → 확장문장 표시 및 낭독 시작');

        // ── AUTO-FLOW 1: 완성된 확장 문장 별도 표시 후 낭독 ──
        if (hostExpanded.isNotEmpty && mounted) {
          setState(() {
            _expandedFinalSentence = hostExpanded;
            _showExpandedFinalCard = true;
          });
          _scrollToBottom();
          await _practiceSpeakText(hostExpanded, 'nova');
        }

        // ── AUTO-FLOW 2: Polished Sentence 자동 생성 → 낭독 → Study Room 안내 ──
        await _autoPolishAndSpeak(hostExpanded);
        return;
      }

      // ─────────────────────────────────────────────────────
      // STEP 3 & 4 (병렬): AI 응답 백그라운드 생성
      //   → AI 청크는 큐에 쌓이지만 _aiPaused=true라 재생 대기
      //   → 유저 TTS는 계속 재생 중
      // ─────────────────────────────────────────────────────
      if (mounted) {
        setState(() => _localMessages
            .add({'role': 'SYSTEM', 'target': '', 'original': ''}));
        _scrollToBottom();
      }
      int aiIndex = _localMessages.length - 1;

      // 🔧 [v3.2 버그 수정] setUserTurn(false)는 유저 재생 완료 후로 이동
      // 현재 시점에서 유저 TTS가 아직 재생 중인데 _isUserTurn=false로 바꾸면
      // TtsQueueManager._processQueue가 'AI 턴이고 paused' 판단하여 유저 마지막 청크까지 멈춰버림
      _ttsQueueManager.setAiPaused(true); // AI 재생 대기 모드 (유저 TTS는 계속 재생)
      // 🔧 [v3.5] AI 전용 큐로 보내기 위해 isUser: false 명시
      // 🌱 [v3.5 StepExpand] AI 목소리는 alloy 고정 (로비 선택에서 제외)
      ChunkedTtsFetcher aiTtsFetcher = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        "alloy", // 🌱 AI 목소리 alloy 고정
        isUser: false, // AI 큐로 분리
        onLog: _log,
      );

      String latestContextStr = contextStr.isEmpty
          ? "User: $userTargetText"
          : "$contextStr\nUser: $userTargetText";
      String aiTargetText = "";
      String aiOriginalText = "";
      String aiBuffer = "";
      bool firstChunkSentToTTS = false;
      bool aiHasDoubleNewline = false;
      final HybridTtsPlayer aiHybridTts = HybridTtsPlayer(
        apiKey: _openAiKey,
        voice: 'alloy',
        onLog: _log,
      );

      _swOpenAI.reset();
      _swOpenAI.start();
      _swTTS.reset();

      _log('🧠 [PIPE-02]', 'AI 스트림 요청: userText="$userTargetText"');

      final aiStream = StepExpandBrain.streamGrammarQuestion(
        apiKey: _openAiKey,
        contextStr: latestContextStr,
        turnNumber: _turnCounter,
        maxTurns: MAX_TURNS,
        myTarget: targetLangName, // 🌐 [v3.1] 유저가 선택한 타겟 언어
      );

      // AI 생성+청킹을 Future로 (유저 재생과 병렬)
      bool _firstAiChunkLogged = false;
      final Future<void> aiGenerationTask = () async {
        await for (String chunk in aiStream) {
          if (!_firstAiChunkLogged) {
            _log('🧠 [PIPE-03]', 'GPT 첫 청크 수신: "$chunk"');
            _firstAiChunkLogged = true;
          }
          if (_swOpenAI.isRunning) _swOpenAI.stop();

          if (!aiHasDoubleNewline) {
            // Part1 (영어): 누적 + 하이브리드 첫 청크 발사
            aiTargetText += chunk;
            aiBuffer += chunk;

            if (aiTargetText.contains('\n\n')) {
              // \n\n 감지: Part1 끝, Part2(한국어) 시작
              aiHasDoubleNewline = true;
              final sepIdx = aiTargetText.indexOf('\n\n');
              final afterSep = aiTargetText.substring(sepIdx + 2);
              aiTargetText = aiTargetText.substring(0, sepIdx);
              final bufSepIdx = aiBuffer.indexOf('\n\n');
              if (bufSepIdx >= 0) aiBuffer = aiBuffer.substring(0, bufSepIdx);
              if (afterSep.isNotEmpty) aiOriginalText += afterSep;
            } else {
              // Part1 하이브리드: 4단어/구두점 도달 시 첫 청크 발사
              if (!aiHybridTts.firstChunkFired) {
                if (!firstChunkSentToTTS) {
                  _swTTS.start();
                  firstChunkSentToTTS = true;
                }
                final cutIdx =
                    aiHybridTts.onChunk(aiBuffer, aiTtsFetcher, _swTTS);
                if (cutIdx >= 0) aiBuffer = aiBuffer.substring(cutIdx);
              }
            }
          } else {
            // Part2 (한국어): aiOriginalText에만 누적 — TTS 금지
            aiOriginalText += chunk;
          }

          // 텍스트는 AI 소리 시작 시점(setAiPaused=false)에 일괄 표시
        }
        // 스트림 종료: remainder 발사 + 통문장 TtsCache 저장
        if (!firstChunkSentToTTS) {
          _swTTS.start();
          firstChunkSentToTTS = true;
        }
        await aiHybridTts.onStreamEnd(
          fullSentence: aiTargetText.trim(),
          remainderBuffer: aiBuffer,
          fetcher: aiTtsFetcher,
          swSpeechEnd: _swTTS,
        );
      }();

      // ─────────────────────────────────────────────────────
      // STEP 5: 유저 TTS 모두 재생될 때까지 대기
      // ─────────────────────────────────────────────────────
      _log('🧠 [PIPE-04]',
          '유저 TTS 대기 시작. pending=${userTtsFetcher.pendingRequests}');

      int waitTicks = 0;
      while (userTtsFetcher.pendingRequests > 0) {
        await Future.delayed(const Duration(milliseconds: 50));
        waitTicks++;
        if (waitTicks > 200) {
          // 10초 타임아웃
          _log('⚠️ [PIPE-TIMEOUT]', '유저 TTS fetch 10초 초과, 강제 진행');
          break;
        }
      }
      _log(
          '🧠 [PIPE-05]', '유저 TTS fetch 완료. isBusy=${_ttsQueueManager.isBusy}');

      waitTicks = 0;
      while (_ttsQueueManager.isBusy) {
        await Future.delayed(const Duration(milliseconds: 50));
        waitTicks++;
        if (waitTicks > 200) {
          _log('⚠️ [PIPE-TIMEOUT]', '유저 TTS 재생 10초 초과, 강제 진행');
          break;
        }
      }
      _log('🧠 [PIPE-06]', '유저 TTS 재생 완료 → AI 큐 개방');

// ─────────────────────────────────────────────────────
      // STEP 6: AI 큐 개방
      // ─────────────────────────────────────────────────────
      // 🔧 [v3.3 안전 간격] 유저 TTS 재생 완료 직후 250ms 대기
      // 이유: isBusy=false가 되었어도 AudioPlayer 내부에서
      //       마지막 샘플이 디코딩/재생 꼬리가 남을 수 있어 소리 겹침 발생
      //       250ms = 체감상 자연스러운 "숨 고르기" + 겹침 방지
      await Future.delayed(const Duration(milliseconds: 250));
      _log('🧠 [PIPE-GAP]', '유저-AI 전환 안전 간격 250ms 완료');

      // 턴 전환
      _ttsQueueManager.setUserTurn(false);
      _ttsQueueManager.setAiPaused(false);
      _log('🧠 [PIPE-07]', 'setUserTurn(false) + setAiPaused(false). AI 재생 시작');
      // AI 소리 시작과 동시에 지금까지 쌓인 텍스트 즉시 표시
      if (mounted && aiIndex < _localMessages.length) {
        setState(() {
          _localMessages[aiIndex]['target'] = aiTargetText;
          _localMessages[aiIndex]['original'] = aiOriginalText;
        });
        _scrollToBottom();
      }
      // [v3.8] AI 한국어 단일 호출 통합
      //   streamGrammarQuestion 프롬프트가 "영어 \n\n 한국어" 두 파트를 한 스트림으로 출력
      //   Part1 = target + TTS, Part2 = original (TTS 미전송)
      //   별도 generateCleanOriginal 호출 없음 — GPT 호출 1회로 둘 다 처리

      await aiGenerationTask;
      // 스트리밍이 아직 진행 중이었다면 최종 텍스트 반영
      if (mounted && aiIndex < _localMessages.length) {
        setState(() {
          _localMessages[aiIndex]['target'] = aiTargetText;
          _localMessages[aiIndex]['original'] = aiOriginalText;
        });
        _scrollToBottom();
      }
      _log('🧠 [PIPE-08]',
          'aiGenerationTask 완료. AI pending=${aiTtsFetcher.pendingRequests}');

      waitTicks = 0;
      while (aiTtsFetcher.pendingRequests > 0 || _ttsQueueManager.isBusy) {
        await Future.delayed(const Duration(milliseconds: 50));
        waitTicks++;
        if (waitTicks > 300) {
          // 15초 타임아웃
          _log('⚠️ [PIPE-TIMEOUT]', 'AI TTS 15초 초과, 강제 진행');
          break;
        }
      }
      _log('🧠 [PIPE-09]', 'AI TTS 재생 완료');

      // ─────────────────────────────────────────────────────
      // STEP 7: Firestore 저장
      // ─────────────────────────────────────────────────────
      // 히스토리 저장 전 Korean original 완료 보장 (1턴 및 2턴+)
      // effectiveOriginal(화면 표시용)과 달리, 저장 payload에는 실제 originalRaw 사용
      if (userOrigFuture != null) {
        try {
          final cleanKorean =
              await userOrigFuture.timeout(const Duration(seconds: 10));
          if (hostIndex < _localMessages.length &&
              (_localMessages[hostIndex]['original'] ?? '').toString().isEmpty) {
            _localMessages[hostIndex]['original'] = cleanKorean;
          }
        } catch (_) {}
      }
      final String _hostOriginal = hostIndex < _localMessages.length
          ? ((_localMessages[hostIndex]['original']) ?? '').toString()
          : '';
      final hostLine = {
        'role': 'HOST',
        'original_text': _hostOriginal,
        'translated_text': userTargetText,
      };
      final systemLine = {
        'role': 'SYSTEM',
        'original_text': aiOriginalText.trim(),
        'translated_text': aiTargetText,
      };
      _saveTurnToFirestore([hostLine, systemLine]);
      _saveHistoryMessages([hostLine, systemLine]); // 🔧 [히스토리] 병행 저장
      _log('🧠 [PIPE-10]', 'Firestore 저장 호출 완료');
    } catch (e) {
      _log('❌ [PIPE-ERR]', 'Relay Error: $e');
    } finally {
      _log('🧠 [PIPE-END]',
          'finally 진입. active=$_isConversationActive turn=$_turnCounter/current=$currentTurnId mounted=$mounted');
      if (mounted && _isConversationActive && _turnCounter == currentTurnId) {
        _log('🧠 [PIPE-RESTART]', '마이크 재시작 시도');
        _startDeepgramListening();
      } else {
        _log('⚠️ [PIPE-NORESTART]', '마이크 재시작 조건 불충족');
      }
    }
  }

  /// 한 턴(유저+AI)의 ChatLine 2개를 Firestore에 저장
  /// - _sessionDocId가 null이면 새 세션 생성
  /// - 있으면 기존 세션의 transcript에 arrayUnion으로 append
  Future<void> _saveTurnToFirestore(
      List<Map<String, dynamic>> chatLines) async {
    _log('💾 [SAVE-01]', '저장 시작. chatLines=${chatLines.length}개');
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _log('❌ [SAVE-ERR-A]', 'FirebaseAuth.currentUser == null (로그인 안됨)');
        return;
      }
      final uid = user.uid;
      final firestore = FirebaseFirestore.instance;
      _log('💾 [SAVE-02]', 'uid=$uid, sessionDocId=$_sessionDocId');

      if (_sessionDocId == null) {
        // 첫 대화 → 새 세션 문서 생성
        _log('💾 [SAVE-03]', '첫 대화 → 새 세션 생성 시도');
        final userDocRef = firestore.collection('users').doc(uid);
        final userDoc = await userDocRef.get();
        final currentTotal = (userDoc.data()?['total_sessions'] as int?) ?? 0;
        final nextSessionNo = currentTotal + 1;
        _log('💾 [SAVE-04]',
            'total_sessions=$currentTotal → next=$nextSessionNo');

        final newSession = await userDocRef.collection('sessions').add({
          'session_no': nextSessionNo,
          'mode': 'step_expand', // 🔧 [v3.1] 히스토리 모드별 필터링용
          'total_turns': _turnCounter, // 🌱 이 세션에서 몇 턴까지 성장했는지
          'created_at': FieldValue.serverTimestamp(),
          'transcript': chatLines,
        });
        _sessionDocId = newSession.id;
        _log('💾 [SAVE-05]', '새 세션 생성 완료. docId=$_sessionDocId');
        // 🔧 [v3.7] chat_history 방에 session_ref 백링크 (Practice 연동용)
        if (_myHistoryRef != null) {
          try {
            await _myHistoryRef!.update({'session_ref': _sessionDocId});
            _log('🔗 [HIST-LINK]', 'session_ref 링크 완료: $_sessionDocId');
          } catch (e) {
            _log('❌ [HIST-LINK-ERR]', 'session_ref 저장 실패: $e');
          }
        }

        await userDocRef.update({'total_sessions': nextSessionNo});
        _log('💾 [SAVE-06]', 'users 문서 total_sessions 업데이트 완료');
      } else {
        // 기존 세션에 append
        _log('💾 [SAVE-07]', '기존 세션에 append 시도. docId=$_sessionDocId');
        await firestore
            .collection('users')
            .doc(uid)
            .collection('sessions')
            .doc(_sessionDocId)
            .update({
          'transcript': FieldValue.arrayUnion(chatLines),
        });
        _log('💾 [SAVE-08]', 'arrayUnion 완료');
      }
    } catch (e, stack) {
      _log('❌ [SAVE-ERR-B]', 'Firestore 저장 실패: $e');
      _log(
          '❌ [SAVE-STACK]',
          stack.toString().substring(0,
              stack.toString().length > 200 ? 200 : stack.toString().length));
    }
  }

  // ────────────────────────────────────────────────────────────────────
  // 🔧 [히스토리] chat_history 저장 함수 3종 (Duo 패턴 복제)
  //   - sessions 저장(_saveTurnToFirestore)과 병행
  //   - sessions는 훈련 분석용, chat_history는 히스토리 리스트용
  // ────────────────────────────────────────────────────────────────────

  /// chat_history 방 문서 보장 (없으면 생성)
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
        'room_name': "Step.Ex Mode",
        'is_pinned': false,
        'msg_count': 0
      });
      _log('📚 [HIST-NEW]', 'chat_history 방 생성: ${_myHistoryRef!.id}');
    }
  }

  /// 턴마다 chat_history/messages 서브컬렉션에 기록 병행 저장
  /// - chatLines: _saveTurnToFirestore와 동일한 [{role, original_text, translated_text}, ...]
  Future<void> _saveHistoryMessages(
      List<Map<String, dynamic>> chatLines) async {
    try {
      await _ensureHistoryRef();
      if (_myHistoryRef == null) return;

      // messages 서브컬렉션에 각 발화 저장
      for (final line in chatLines) {
        final translated = (line['translated_text'] ?? '').toString().trim();
        if (translated.isEmpty) continue; // 빈 발화 스킵
        // 🔧 [PRACTICE-FIX] expanded_sentence 필드 있으면 함께 저장 (옵션 B 후방호환)
        final String expandedSent =
            (line['expanded_sentence'] ?? '').toString().trim();
        await _myHistoryRef!.collection('messages').add({
          'role': line['role'] ?? '',
          'translated_text': translated,
          'original_text': (line['original_text'] ?? '').toString(),
          if (expandedSent.isNotEmpty) 'expanded_sentence': expandedSent,
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      // 🔧 [핵심] 턴마다 msg_count/last_message 업데이트
      //   - 뒤로가기 경로와 무관하게 항상 갱신됨
      //   - last_message는 마지막 비어있지 않은 translated_text
      final lastTranslated = chatLines
          .map((l) => (l['translated_text'] ?? '').toString().trim())
          .lastWhere((t) => t.isNotEmpty, orElse: () => '');
      if (lastTranslated.isNotEmpty) {
        await _myHistoryRef!.update({
          'msg_count': FieldValue.increment(chatLines.length),
          'last_message': lastTranslated,
          'last_active': FieldValue.serverTimestamp(),
        });
        _log('💾 [HIST-UPD]',
            'msg_count+${chatLines.length}, last="$lastTranslated"');
      }
    } catch (e) {
      _log('❌ [HIST-ERR]', 'chat_history 저장 실패: $e');
    }
  }

  /// 뒤로가기 시: 빈 방 폭파 or last_message 업데이트 후 나가기
  Future<void> _handleAutoSaveAndExit() async {
    try {
      if (_myHistoryRef != null) {
        // 대화가 한 번도 없었으면 방 문서 삭제 (쓰레기 데이터 방지)
        final hasUserTurn = _localMessages.any((m) => m['role'] == 'HOST');
        if (!hasUserTurn) {
          await _myHistoryRef!.delete();
          _log('🗑️ [HIST-DEL]', '빈 방 삭제 완료');
        } else {
          // 마지막 유효 target 텍스트 찾기
          String lastText = "대화 기록 저장";
          for (int i = _localMessages.length - 1; i >= 0; i--) {
            final t = (_localMessages[i]['target'] ?? '').toString().trim();
            if (t.isNotEmpty && t != '...') {
              lastText = t;
              break;
            }
          }
          // expandedSentence 추출 (마지막 HOST 메시지 Part2)
          String expandedSentence = "";
          for (int j = _localMessages.length - 1; j >= 0; j--) {
            if (_localMessages[j]['role'] == 'HOST') {
              final tgt = (_localMessages[j]['target'] ?? '').toString();
              final parts = tgt.split(RegExp(r'\n\s*\n'));
              if (parts.length >= 2) {
                expandedSentence = parts.sublist(1).join('\n\n').trim();
                break;
              }
            }
          }

          final updateMap = <String, dynamic>{
            'last_message': lastText,
            'last_message_time': FieldValue.serverTimestamp(),
            'msg_count': _localMessages.length,
            'last_active': FieldValue.serverTimestamp(),
          };

          // expanded_sentence 있을 때만 추가 (1턴 단답형 방 제외)
          if (expandedSentence.isNotEmpty) {
            updateMap['expanded_sentence'] = expandedSentence;
          }

          // session_ref 있을 때만 추가 (신규 세션 생성된 경우)
          if (_sessionDocId != null) {
            updateMap['session_ref'] = _sessionDocId;
          }

          await _myHistoryRef!.update(updateMap);
          _log('💾 [HIST-UPD]',
              'chat_history 업데이트 완료 (expanded=${expandedSentence.isNotEmpty})');
        }
      }
    } catch (e) {
      _log('❌ [HIST-EXIT-ERR]', '$e');
    } finally {
      if (mounted) {
        if (StealthRoomMaster.exitCurrentMode != null) {
          StealthRoomMaster.exitCurrentMode!();
        } else if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          context.goNamed('Lobby');
        }
      }
    }
  }

  // ====================================================================
  // 📦 [Box 6: UI]
  // ====================================================================
  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewPadding.bottom == 0
        ? 24.0
        : MediaQuery.of(context).viewPadding.bottom + 8.0;
    return Container(
      color: const Color(0xFF121212),
      child: SafeArea(
        child: Column(children: [
          _buildTopBar(),
          const SizedBox(height: 4),
          Expanded(
            child: Stack(children: [
              _buildChatList(),
              _buildIdleOverlay(),
            ]),
          ),
          _buildControlArea(bottomPad),
        ]),
      ),
    );
  }

  // ... (_buildTopBar, _buildTopControls, _buildChatList, _buildTextBlock, _buildControlArea는 기존과 동일하게 유지) ...
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white70),
              onPressed: _handleAutoSaveAndExit), // 🔧 [히스토리] AutoSave 연결
          Row(children: [
            // ── Idle pause 아이콘 (T버튼 왼쪽, 클릭 시 pause 해제) ──
            if (_isIdlePaused)
              GestureDetector(
                onTap: _resetIdleTimer,
                child: const Padding(
                  padding: EdgeInsets.only(left: 4, right: 6),
                  child: Icon(
                    Icons.pause_circle_filled_rounded,
                    color: Color(0xFFFFD54F),
                    size: 20,
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
              onPressed: () => setState(() => _showOriginal = !_showOriginal),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            const SizedBox(width: 8),
            // [v3.6] 잔여시간 표시 + 길게 누르면 로그 (개발자용)
            GestureDetector(
              onLongPress: _showDebugLogDialog,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  const Icon(Icons.timer_outlined,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '${(FFAppState().remainingTime / 60).floor()}m',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ]),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildTopControls() {
    // [v3.6] 턴 진행 상태 인디케이터 (축소 — 공간 최소화)
    final progressText = _isSessionComplete
        ? "✨ Complete ($MAX_TURNS/$MAX_TURNS)"
        : _turnCounter == 0
            ? "Start with a new topic"
            : "Turn $_turnCounter / $MAX_TURNS";
    final progressColor =
        _isSessionComplete ? const Color(0xFF10B981) : const Color(0xFF9333EA);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isSessionComplete ? Icons.check_circle : Icons.trending_up,
            color: progressColor,
            size: 13,
          ),
          const SizedBox(width: 4),
          Text(
            progressText,
            style: TextStyle(color: progressColor, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildChatList() {
    if (_isPracticeMode) return _buildPracticeContent();

    // 추가 위젯 목록 (메시지 목록 아래에 순서대로 표시)
    final List<Widget Function()> extras = [];
    if (_isSessionComplete) {
      if (_showExpandedFinalCard && _expandedFinalSentence.isNotEmpty) {
        extras.add(_buildExpandedFinalCard);
      }
      if (_showPolishButton) {
        if (_polishedSentence.isNotEmpty) {
          extras.add(_buildPolishedCard);
          extras.add(_buildSuggestNewButton);
        } else {
          extras.add(_buildPolishActionButton);
        }
      }
    }

    final double bottomPad = _localMessages.length <= 1
        ? MediaQuery.of(context).size.height * 0.4
        : 16;
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
      itemCount: _localMessages.length + extras.length,
      itemBuilder: (context, idx) {
        if (idx < _localMessages.length) {
          return _buildTextBlock(_localMessages[idx]);
        }
        final extraIdx = idx - _localMessages.length;
        if (extraIdx < extras.length) return extras[extraIdx]();
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildPolishActionButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 16),
      child: Center(
        child: ElevatedButton.icon(
          icon: _isPolishing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome, color: Color(0xFFFBBF24)),
          label: Text(
            _isPolishing ? "Polishing..." : "✨ Polished Version",
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1F2937),
            side: const BorderSide(color: Color(0xFFFBBF24), width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          onPressed: _isPolishing ? null : _polishSentenceInline,
        ),
      ),
    );
  }

  Widget _buildSuggestNewButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          label: const Text(
            "Suggest New Sentence",
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF9333EA),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          onPressed: _suggestNewSentence,
        ),
      ),
    );
  }

  Widget _buildExpandedFinalCard() {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2040), Color(0xFF111827)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFF60A5FA).withOpacity(0.5), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle_outline,
                  color: Color(0xFF60A5FA), size: 15),
              SizedBox(width: 6),
              Text("✅ Completed Sentence",
                  style: TextStyle(
                      color: Color(0xFF60A5FA),
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(
            _expandedFinalSentence,
            style: TextStyle(
                color: Colors.white,
                fontSize: 16 * _fontScale,
                fontWeight: FontWeight.bold,
                height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildStudyRoomPrompt() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Center(
        child: Text(
          '📚 Study Room에서 연습 하세요',
          style: const TextStyle(
            color: Color(0xFFA7F3D0),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildPolishedCard() {
    return Container(
      key: _polishedCardKey,
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2F1A), Color(0xFF111827)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFF10B981).withOpacity(0.5), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: Color(0xFFFBBF24), size: 15),
              SizedBox(width: 6),
              Text("Polished Sentence",
                  style: TextStyle(
                      color: Color(0xFFFBBF24),
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          if (_isPolishing)
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Color(0xFF10B981), strokeWidth: 2.5),
              ),
            )
          else
            SelectableText(
              _polishedSentence,
              style: TextStyle(
                  color: const Color(0xFFA7F3D0),
                  fontSize: 16 * _fontScale,
                  fontWeight: FontWeight.bold,
                  height: 1.6),
            ),
        ],
      ),
    );
  }

  Widget _buildTextBlock(Map<String, dynamic> msg) {
    final role = (msg['role'] ?? '').toString();
    bool isHost = role == 'HOST' || role == 'HOST_TEMP';
    final targetRaw = (msg['target'] ?? '').toString();
    final originalRaw = (msg['original'] ?? '').toString();

    // Show '...' when AI is generating, user bubble is pending recognition,
    // or HOST bubble was just created with empty target (before streaming starts)
    final String displayTarget = ((role == 'SYSTEM' && targetRaw.isEmpty) ||
            (role == 'HOST_TEMP' && targetRaw == '...') ||
            (role == 'HOST' && targetRaw.isEmpty))
        ? '...'
        : targetRaw;

    final targetParts = targetRaw.split(RegExp(r'\n\s*\n'));
    // 🌱 유저 2턴+ (hasUserTwoParts): Part1 영어+한국어 → 한줄띄기 → Part2 영어(한국어 없음)
    final bool hasUserTwoParts = role == 'HOST' && targetParts.length >= 2;
    final String effectiveOriginal = (role == 'HOST_TEMP') ? '' : originalRaw;

    return Align(
      alignment: isHost ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: isHost
                ? const Color(0xFF2C2C2E)
                : const Color(0xFF9333EA).withOpacity(0.15),
            borderRadius: BorderRadius.circular(16)),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        child: Column(
          crossAxisAlignment:
              isHost ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (hasUserTwoParts) ...[
              // Part1 영어 (짧은 대답)
              Text(targetParts[0].trim(),
                  textAlign: isHost ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16 * _fontScale,
                      fontWeight: FontWeight.bold)),
              // Part1 한국어 (Part1 바로 아래)
              if (_showOriginal && effectiveOriginal.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(effectiveOriginal,
                    textAlign: isHost ? TextAlign.right : TextAlign.left,
                    style: TextStyle(
                        color: Colors.grey, fontSize: 10 * _fontScale)),
              ],
              // 한줄띄기 (Part1 영역과 Part2 영역 분리)
              const SizedBox(height: 16),
              // Part2 영어 (확장문장, 한국어 없음)
              Text(targetParts.sublist(1).join('\n\n').trim(),
                  textAlign: isHost ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16 * _fontScale,
                      fontWeight: FontWeight.bold)),
            ] else ...[
              Text(displayTarget,
                  textAlign: isHost ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16 * _fontScale,
                      fontWeight: FontWeight.bold)),
              if (_showOriginal && effectiveOriginal.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(effectiveOriginal,
                    textAlign: isHost ? TextAlign.right : TextAlign.left,
                    style: TextStyle(
                        color: Colors.grey, fontSize: 10 * _fontScale)),
              ],
            ],
          ],
        ),
      ),
    );
  }

  // ====================================================================
  // 🎯 [Practice UI] 의미단위 반복 연습 뷰
  // ====================================================================

  /// Practice 메인 뷰 (_buildChatList 대체)
  Widget _buildPracticeContent() {
    return Column(
      children: [
        // 헤더
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white54, size: 20),
                onPressed: () => setState(() {
                  _isPracticeMode = false;
                  _practicePlayer.stop();
                  _voiceManager?.dispose();
                  _voiceManager = null;
                }),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.play_circle_fill_rounded,
                  color: Color(0xFF9333EA), size: 16),
              const SizedBox(width: 6),
              const Text('Polished',
                  style: TextStyle(
                      color: Color(0xFF9333EA),
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              if (!_practiceComplete && _practiceUnits.isNotEmpty)
                Text(
                  '${_currentUnitIdx + 1} / ${_practiceUnits.length}',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
            ],
          ),
        ),
        // 스크롤 가능한 콘텐츠
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              children: [
                _buildPracticeFullSentence(),
                const SizedBox(height: 20),
                if (_practiceComplete) _buildPracticeCompleteArea(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 전체 문장 — 의미단위마다 두 색상 교차, 현재 단위 강조 + 탭으로 이동
  Widget _buildPracticeFullSentence() {
    const Color colorA = Color(0xFF60A5FA); // 파란색
    const Color colorB = Color(0xFFA7F3D0); // 녹색

    if (_practiceUnits.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
            child: CircularProgressIndicator(color: Color(0xFF9333EA))),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFF9333EA).withOpacity(0.3), width: 1),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: List.generate(_practiceUnits.length, (i) {
          final isActive = !_practiceComplete && i == _currentUnitIdx;
          final isDone = i < _currentUnitIdx || _practiceComplete;
          final base = i % 2 == 0 ? colorA : colorB;
          final textColor = isActive
              ? Colors.white
              : isDone
                  ? base.withOpacity(0.4)
                  : base.withOpacity(0.85);

          return GestureDetector(
            onTap: () => _jumpToUnit(i),
            child: Container(
              padding: isActive
                  ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
                  : const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              decoration: isActive
                  ? BoxDecoration(
                      color: base.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(6),
                    )
                  : null,
              child: Text(
                _practiceUnits[i],
                style: TextStyle(
                  color: textColor,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  fontSize: 18 * _fontScale,
                  height: 1.8,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// 진행 상태 행 (AI 낭독 / 유저 따라 말하기 / 스킵 버튼)
  Widget _buildPracticeStatusRow() {
    String label;
    Color color;
    IconData icon;

    if (_isPracticeAiSpeaking) {
      label = 'AI 낭독 중...';
      color = const Color(0xFF9333EA);
      icon = Icons.volume_up_rounded;
    } else if (_isPracticeUserListening) {
      label = '따라 말하세요 🎤';
      color = const Color(0xFF10B981);
      icon = Icons.mic_rounded;
    } else {
      label = '준비 중...';
      color = Colors.white38;
      icon = Icons.hourglass_empty_rounded;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: color, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        if (_isPracticeUserListening) ...[
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _practiceAdvanceUnit,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white24),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.skip_next_rounded,
                      color: Colors.white54, size: 16),
                  SizedBox(width: 4),
                  Text('Skip',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 완료 후: AI/유저 전체 듣기 + 확장문장 연습하기 이동 버튼
  Widget _buildPracticeCompleteArea() {
    return Column(
      children: [
        // AI Voice / My Voice (2버튼 한 줄)
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: Icon(
                  _isAiFullPlaying
                      ? Icons.stop_rounded
                      : Icons.volume_up_rounded,
                  color: Colors.white,
                  size: 16,
                ),
                label: Text(
                  _isAiFullPlaying ? '정지' : 'AI Voice',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isAiFullPlaying
                      ? const Color(0xFF6B7280)
                      : const Color(0xFF9333EA),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isUserFullPlaying ? null : _playAiFullSentence,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                icon: Icon(
                  _isUserFullPlaying
                      ? Icons.stop_rounded
                      : Icons.headphones_rounded,
                  color: Colors.white,
                  size: 16,
                ),
                label: Text(
                  _isUserFullPlaying ? '정지' : 'My Voice',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isUserFullPlaying
                      ? const Color(0xFF6B7280)
                      : _userWavPath == null
                          ? const Color(0xFF374151)
                          : const Color(0xFF0D9488),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: (_isAiFullPlaying || _userWavPath == null)
                    ? null
                    : _playUserFullSentence,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 마이크 버튼 없음 — AI 발화 후 STT 자동 시작
  // 하단은 노란 불빛 인디케이터만 표시하여 채팅 공간 최대화
  Widget _buildControlArea(double bp) {
    if (_isPracticeMode) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.fromLTRB(24, 8, 24, bp),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "Step Expand",
            style: TextStyle(
                color: Colors.white54,
                fontSize: 16,
                fontWeight: FontWeight.bold),
          ),
          // 작동 중 노란 불빛 인디케이터 (마이크 버튼 대신)
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isConversationActive
                  ? const Color(0xFFFBBF24)
                  : Colors.transparent,
              border: Border.all(
                color: _isConversationActive
                    ? const Color(0xFFFBBF24)
                    : Colors.white24,
                width: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// 🎙️ [Box 7] 공통 통신 엔진 v3 — 모든 모드 공유
// ====================================================================
// 📂 서브박스 구성:
//   [Box 7-A] ConversationHistory  — 슬라이딩 윈도우 대화 기억
//   [Box 7-B] DeepgramV2VoiceManager — 유저 음성 → 텍스트 (STT)
//   [Box 7-C] UnifiedBrain          — 범용 GPT 스트리밍 (Duo 등)
//   [Box 7-D] TtsCache              — TTS 로컬 캐싱 (Firebase Storage 비용 0)
//   [Box 7-E] TtsQueueManager       — TTS 오디오 큐 + AI 대기 플래그
//   [Box 7-F] ChunkedTtsFetcher     — TTS 의미단위 청킹 + 캐싱
//   [Box 7-G] RelayPipeline         — 범용 파이프라인 (참고용)
// ====================================================================

// ====================================================================
// 📦 [Box 7 공용 상수] 다국어 TTS 구두점 패턴
// ====================================================================
// 한국어/일본어/중국어/라틴 구두점 통합 (쉼표/마침표/물음표/느낌표 등)
// 각 Brain/파이프라인에서 TTS 청킹 기준으로 사용
final RegExp kTtsDelimiterPattern = RegExp(r'[,\.?!;:。、！？…，；：\n]');

// ====================================================================
// 📦 [Box 7-H: HybridTtsPlayer] — 하이브리드 TTS (Step Expand + Roleplay 공용)
// ====================================================================
// 설계 원칙: 첫 구두점 즉시 발사(체감 빠름) + 통문장 캐시 저장(히스토리 통합)
//   → onChunk: 첫 구두점/4단어 도달 시 ChunkedTtsFetcher에 1회 발사
//   → onStreamEnd: remainder 순차 발사 + fullSentence TtsCache 저장 (재생 없음)
class HybridTtsPlayer {
  final String apiKey;
  final String voice;
  final void Function(String, String)? onLog;

  bool _firstChunkFired = false;

  int lastFirstChunkMs = 0;
  int lastCacheSaveMs = 0;
  bool lastCacheHit = false;

  HybridTtsPlayer({
    required this.apiKey,
    this.voice = 'nova',
    this.onLog,
  });

  bool get firstChunkFired => _firstChunkFired;

  void reset() {
    _firstChunkFired = false;
    lastFirstChunkMs = 0;
    lastCacheSaveMs = 0;
    lastCacheHit = false;
  }

  // 4단어 조기 발사 보충: 구두점 OR 4단어 중 먼저 오는 쪽 발사
  // buffer: 현재까지 누적된 텍스트 버퍼 (외부에서 관리)
  // 반환값: buffer에서 자를 인덱스 (>=0이면 발사됨, -1이면 미발사)
  int onChunk(String buffer, ChunkedTtsFetcher fetcher, Stopwatch swSpeechEnd) {
    if (_firstChunkFired) return -1;

    final punctMatch = kTtsDelimiterPattern.firstMatch(buffer);
    final wordCount =
        buffer.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    if (punctMatch == null && wordCount < 4) return -1;

    final int cutIdx;
    final String text;
    if (punctMatch != null) {
      cutIdx = punctMatch.end;
      text = buffer.substring(0, cutIdx).trim();
    } else {
      cutIdx = buffer.length;
      text = buffer.trim();
    }

    if (text.isEmpty) return cutIdx;

    _firstChunkFired = true;
    lastFirstChunkMs = swSpeechEnd.elapsedMilliseconds;
    fetcher.addText(text);
    onLog?.call('[HYB-01]',
        '발사(${punctMatch != null ? "구두점" : "4단어"}): "$text" ${lastFirstChunkMs}ms');
    return cutIdx;
  }

  // GPT 스트림 종료 시 호출:
  //   1) remainder 청크 순차 발사 (기존 큐에 이어서)
  //   2) fullSentence TtsCache 저장 (재생 없음 — 히스토리 뷰 HIT 유도)
  Future<void> onStreamEnd({
    required String fullSentence,
    required String remainderBuffer,
    required ChunkedTtsFetcher fetcher,
    required Stopwatch swSpeechEnd,
  }) async {
    // 1. Remainder 발사
    final remainder = remainderBuffer.trim();
    if (!_firstChunkFired && fullSentence.isNotEmpty) {
      // 구두점/4단어 없이 스트림 종료 — 전체 텍스트를 지금 발사
      fetcher.addText(fullSentence);
      _firstChunkFired = true;
      lastFirstChunkMs = swSpeechEnd.elapsedMilliseconds;
      onLog?.call(
          '[HYB-01-LATE]', 'no punctuation — full text fired at stream end');
    } else if (remainder.isNotEmpty) {
      int lastIdx = 0;
      for (final match in kTtsDelimiterPattern.allMatches(remainder)) {
        final seg = remainder.substring(lastIdx, match.end).trim();
        if (seg.isNotEmpty) fetcher.addText(seg);
        lastIdx = match.end;
      }
      final tail = remainder.substring(lastIdx).trim();
      if (tail.isNotEmpty) fetcher.addText(tail);
      onLog?.call('[HYB-02]', 'remainder fired (${remainder.length}c)');
    }

    // 2. TtsCache 저장 (재생 없음)
    if (fullSentence.trim().isEmpty) return;
    try {
      final cached = await TtsCache.get(fullSentence, voice);
      if (cached != null && cached.isNotEmpty) {
        lastCacheHit = true;
        lastCacheSaveMs = 0;
        onLog?.call('[HYB-03-HIT]', 'TtsCache HIT — 저장 생략');
        return;
      }
      lastCacheHit = false;
      final sw = Stopwatch()..start();
      final res = await http
          .post(
            Uri.parse('https://api.openai.com/v1/audio/speech'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'tts-1',
              'input': fullSentence,
              'voice': voice,
              'speed': 1.0,
              'response_format': 'mp3',
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await TtsCache.put(fullSentence, voice, res.bodyBytes);
        lastCacheSaveMs = sw.elapsedMilliseconds;
        onLog?.call('[HYB-04-SAVED]',
            '${lastCacheSaveMs}ms (${res.bodyBytes.length}B)');
      } else {
        onLog?.call('[HYB-ERR]', 'API status=${res.statusCode}');
      }
      sw.stop();
    } catch (e) {
      onLog?.call('[HYB-ERR]', 'TtsCache 저장 실패: $e');
    }
  }
}

// ====================================================================
// 📦 [Box 7-A: ConversationHistory] — 슬라이딩 윈도우 히스토리 관리자
// 기존 버전 문제: 히스토리가 주석에만 존재, 실제 구현 없음
// 개선: 2000토큰 슬라이딩 윈도우, 역할 구분, 직렬화 지원
// ====================================================================
class ConversationHistory {
  final int maxTokens;
  final List<Map<String, String>> _turns = [];

  ConversationHistory({this.maxTokens = 2000});

  /// 대화 한 턴 추가 (role: 'user' | 'assistant')
  void add(String role, String content) {
    _turns.add({'role': role, 'content': content});
    _trim();
  }

  /// 오래된 턴을 제거하여 토큰 예산 유지
  /// 💡 토큰 추산: 한국어는 글자당 ~1.8토큰, 영어는 ~0.75토큰
  void _trim() {
    while (_estimatedTokens() > maxTokens && _turns.length > 2) {
      _turns.removeAt(0); // 가장 오래된 턴부터 제거
    }
  }

  int _estimatedTokens() {
    return _turns.fold(0, (sum, turn) {
      final content = turn['content'] ?? '';
      // 한글 비율에 따라 토큰 추산 조정
      final koreanChars = RegExp(r'[가-힣]').allMatches(content).length;
      final ratio = koreanChars / (content.length > 0 ? content.length : 1);
      final tokenRate = 0.75 + (ratio * 1.05); // 영어 0.75 ~ 한국어 1.8
      return sum + (content.length * tokenRate).round();
    });
  }

  /// GPT API messages 배열로 직렬화
  List<Map<String, String>> toMessages() => List.unmodifiable(_turns);

  /// 히스토리를 단순 텍스트로 직렬화 (legacy 시스템 호환)
  String toPlainText() => _turns
      .map((t) => '[${t['role']?.toUpperCase()}]: ${t['content']}')
      .join('\n');

  void clear() => _turns.clear();
  int get length => _turns.length;
}

// ====================================================================
// 📦 [Box 7-B: DeepgramV2VoiceManager] — STT 엔진 (지수 백오프 재연결)
// 기존 버전 문제:
//   1. 재연결 로직 없음 → 네트워크 끊김 시 세션 소멸
//   2. dispose 후 콜백 실행 가능 → 크래시 위험
//   3. onError 후 아무 복구 시도 없음
// 개선:
//   - 최대 5회 지수 백오프 재연결 (1s, 2s, 4s, 8s, 16s)
//   - _isDisposed 가드를 모든 비동기 콜백에 적용
//   - onReconnecting / onGaveUp 콜백 추가로 UI 상태 동기화
// ====================================================================
class DeepgramV2VoiceManager {
  final String apiKey;
  final AudioRecorder audioRecorder;
  final String langCode;
  final VoidCallback onConnected;
  final Function(String) onTranscriptUpdate;
  final Function(String) onTurnEnded;
  final Function(String) onError;
  final Function(int)? onReconnecting; // 재연결 시도 알림 (선택적)
  final VoidCallback? onGaveUp; // 재연결 포기 알림 (선택적)
  final void Function(String tag, String msg)? onLog; // 🔬 [v3.1] 로그 훅
  final void Function(Uint8List)? onAudioData;

  IOWebSocketChannel? _channel;
  StreamSubscription? _audioSub;
  StreamSubscription? _wsSub;
  String _currentTranscript = '';
  bool _isConnected = false;
  bool _isDisposed = false;
  int _retryCount = 0;
  static const int _maxRetries = 5;

  DeepgramV2VoiceManager({
    required this.apiKey,
    required this.audioRecorder,
    required this.langCode,
    required this.onConnected,
    required this.onTranscriptUpdate,
    required this.onTurnEnded,
    required this.onError,
    this.onReconnecting,
    this.onGaveUp,
    this.onLog,
    this.onAudioData,
  });

  void _lg(String tag, String msg) {
    onLog?.call(tag, msg);
  }

  Future<void> connectAndStart() async {
    _lg('🎤 [DG-00]', 'connectAndStart 진입');
    await _connect();
  }

  Future<void> _connect() async {
    if (_isDisposed) return;
    _lg('🎤 [MIC-01]', '_connect 진입');
    try {
      final uri = Uri.parse(
        'wss://api.deepgram.com/v1/listen'
        '?model=nova-3'
        '&language=$langCode'
        '&smart_format=true'
        '&endpointing=700' // 🔧 [v3.4] 500→700ms: 더듬거림에 덜 민감하게
        '&utterance_end_ms=1000' // 🔧 반응속도 단축: 1200→1000ms
        '&interim_results=true'
        '&encoding=linear16'
        '&sample_rate=16000'
        '&channels=1'
        '&filler_words=false',
      );

      _channel = IOWebSocketChannel.connect(
        uri,
        headers: {'Authorization': 'Token $apiKey'},
        pingInterval: const Duration(seconds: 10),
      );
      _lg('🎤 [DG-01]', 'WebSocket 연결 요청 전송');

      await _wsSub?.cancel();
      _wsSub = _channel!.stream.listen(
        _handleMessage,
        onError: (e) {
          _lg('❌ [DG-WS-ERR]', 'WebSocket 에러: $e');
          _handleDisconnect();
        },
        onDone: () {
          _lg('🎤 [DG-WS-DONE]', 'WebSocket onDone');
          _handleDisconnect();
        },
      );

      // 🔧 [v3.1 핵심 버그 수정] 마이크 스트림 강제 재시작
      _lg('🎤 [MIC-02]', '마이크 시작 시퀀스 진입');
      await _audioSub?.cancel();
      _audioSub = null;
      _lg('🎤 [MIC-03]', '기존 _audioSub 구독 해제 완료');

      try {
        final isRec = await audioRecorder.isRecording();
        _lg('🎤 [MIC-04]', 'audioRecorder.isRecording()=$isRec');
        if (isRec) {
          await audioRecorder.stop();
          _lg('🎤 [MIC-05]', '기존 녹음 강제 중단 완료');
        }
      } catch (e) {
        _lg('❌ [MIC-ERR-A]', 'isRecording/stop 에러: $e');
      }

      try {
        final stream = await audioRecorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 16000,
            numChannels: 1,
          ),
        );
        _lg('🎤 [MIC-06]', 'startStream 성공');

        int packetCount = 0;
        _audioSub = stream.listen(
          (data) {
            if (_isDisposed) return;
            if (data.isNotEmpty) {
              packetCount++;
              if (packetCount == 1) {
                _lg('🎤 [MIC-07]', '첫 오디오 패킷 수신 (${data.length}B)');
              }
              if (packetCount == 50) {
                _lg('🎤 [MIC-08]', '패킷 50개 송신 중 (마이크 정상 동작)');
              }
              final packet = Uint8List.fromList(data);
              _channel?.sink.add(packet);
              onAudioData?.call(packet);
            }
          },
          onError: (e) {
            _lg('❌ [MIC-ERR-B]', '오디오 스트림 에러: $e');
          },
          onDone: () {
            _lg('🎤 [MIC-09]', '오디오 스트림 종료 (총 $packetCount 패킷)');
          },
        );
        _lg('🎤 [MIC-10]', 'stream.listen 구독 완료 — 마이크 완전 활성화');
      } catch (e) {
        _lg('❌ [MIC-ERR-C]', 'startStream 실패: $e');
      }

      _retryCount = 0;
    } catch (e) {
      _lg('❌ [DG-CONN-ERR]', '_connect 전체 실패: $e');
      if (!_isDisposed) _handleDisconnect();
    }
  }

  void _handleMessage(dynamic msg) {
    if (_isDisposed) return;
    try {
      final data = jsonDecode(msg as String);

      if (data['type'] == 'Metadata') {
        _isConnected = true;
        _lg('📡 [DG-02]', 'Metadata 수신 → onConnected 호출');
        onConnected();
        return;
      }

      // 🔧 [v3.1] UtteranceEnd 이벤트 (utterance_end_ms 트리거)
      // 이것도 speech_final과 동일하게 턴 종료로 취급
      if (data['type'] == 'UtteranceEnd') {
        final finalText = _currentTranscript.trim();
        _currentTranscript = '';
        _lg('📡 [DG-UE]',
            'UtteranceEnd 이벤트 → onTurnEnded. finalText="$finalText"');
        if (!_isDisposed && finalText.isNotEmpty) {
          onTurnEnded(finalText);
        }
        return;
      }

      final channel = data['channel'];
      if (channel == null) return;

      final alt = channel['alternatives'] as List?;
      if (alt == null || alt.isEmpty) return;

      final chunk = (alt[0]['transcript'] as String?) ?? '';
      final isFinal = data['is_final'] == true;
      final speechFinal = data['speech_final'] == true;

      if (isFinal || speechFinal) {
        _lg('📡 [DG-03]',
            'isFinal=$isFinal speechFinal=$speechFinal chunk="$chunk"');
      }

      // 인터림 결과도 activity 신호로 사용 (침묵 타이머 취소용)
      if (!isFinal && chunk.isNotEmpty && !_isDisposed) {
        onTranscriptUpdate(_currentTranscript);
      }

      if (isFinal && chunk.isNotEmpty) {
        _currentTranscript += '$chunk ';
        if (!_isDisposed) onTranscriptUpdate(_currentTranscript);
      }

      if (speechFinal) {
        final finalText = _currentTranscript.trim();
        _currentTranscript = '';
        _lg('📡 [DG-04]',
            'speech_final → onTurnEnded 호출 시도. finalText="$finalText"');
        if (!_isDisposed && finalText.isNotEmpty) {
          _lg('📡 [DG-05]', 'onTurnEnded 실제 호출');
          onTurnEnded(finalText);
        } else {
          _lg('📡 [DG-06]', 'finalText 빈값 → onTurnEnded 스킵');
        }
      }
    } catch (e) {
      _lg('❌ [DG-PARSE-ERR]', '_handleMessage 파싱 에러: $e');
    }
  }

  Future<void> _handleDisconnect() async {
    if (_isDisposed) return;
    _isConnected = false;
    if (_retryCount < _maxRetries) {
      _retryCount++;
      _lg('🎤 [DG-RETRY]', '재연결 시도 $_retryCount/$_maxRetries');
      onReconnecting?.call(_retryCount); // 🔧 선택적 콜백 호출
      final delay = Duration(milliseconds: 500 * (1 << (_retryCount - 1)));
      await Future.delayed(delay);
      if (!_isDisposed) await _connect();
    } else {
      _lg('❌ [DG-GIVEUP]', '재연결 최대치 도달');
      onGaveUp?.call(); // 🔧 선택적 콜백 호출
      onError('Connection lost');
    }
  }

  Future<void> dispose() async {
    _lg('🎤 [DG-DISPOSE]', 'dispose 진입');
    _isDisposed = true;
    await _audioSub?.cancel();
    _audioSub = null;
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _isConnected = false;
  }
}

// ====================================================================
// 📦 [Box 7-C: UnifiedBrain] — 범용 GPT 스트리밍 (Duo 등에서 사용)
// 기존 버전 문제:
//   1. static Client 공유 → 동시 요청 시 경쟁 상태
//   2. 히스토리 없음
//   3. 스트리밍 에러 처리 없음, 타임아웃 없음
// 개선:
//   - 요청마다 새 Client 생성 (stateless)
//   - ConversationHistory를 messages 배열로 직접 전달
//   - 30초 타임아웃 + 스트림 에러 전파
// ====================================================================
class UnifiedBrain {
  /// 💡 변경: static Client 제거, 요청별 새 Client 사용
  static Stream<String> streamChat({
    required String apiKey,
    required String systemPrompt,
    required String userMessage,
    ConversationHistory? history, // 💡 신규: 히스토리 직접 주입
    double temp = 0.2,
    Duration timeout = const Duration(seconds: 30), // 💡 신규: 타임아웃
  }) async* {
    final client = http.Client();

    try {
      // 메시지 배열 구성: system → history → 현재 유저 메시지
      final messages = <Map<String, String>>[
        {'role': 'system', 'content': systemPrompt},
        if (history != null) ...history.toMessages(),
        {'role': 'user', 'content': userMessage},
      ];

      final request = http.Request(
        'POST',
        Uri.parse('https://api.openai.com/v1/chat/completions'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json; charset=utf-8',
      });
      request.body = jsonEncode({
        'model': 'gpt-4o-mini',
        'stream': true,
        'temperature': temp,
        'messages': messages,
        'max_tokens': 500, // 💡 신규: 음성 대화는 짧게 (TTS 지연 최소화)
      });

      // 💡 신규: 타임아웃 적용
      final response = await client.send(request).timeout(timeout);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw Exception('GPT API 오류 ${response.statusCode}: $body');
      }

      await for (final chunk in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (chunk.startsWith('data: ') && chunk != 'data: [DONE]') {
          try {
            final delta = jsonDecode(chunk.substring(6))['choices'][0]['delta']
                ['content'];
            if (delta != null) yield delta.toString();
          } catch (_) {
            // 불완전한 JSON 청크 스킵
          }
        }
      }
    } finally {
      client.close(); // 💡 항상 클라이언트 해제
    }
  }
}

// ====================================================================
// 📦 4 TtsQueueManager v2 — 완료 감지 안정성 개선
// 기존 버전 문제:
//   1. onPlayerComplete 리스너가 누수 가능
//   2. timeout 10초가 짧은 문장엔 과함, 긴 문장엔 부족
// 개선:
//   - StreamSubscription으로 리스너 명시적 관리
//   - 오디오 길이 추산 기반 동적 타임아웃
//   - stop() 시 Completer 안전 완료 처리
// ====================================================================
// ====================================================================
// 📦 [Box 7-D: TtsCache] — TTS 오디오 로컬 캐싱 (MD5 스타일 해시)
// ====================================================================
// 🔧 [v3 신규] 같은 텍스트+voice+speed는 파일 재사용
//   → OpenAI API 호출 0, 즉시 재생, Firebase Storage 비용 0
//   → 경로: {앱로컬}/tts_cache/{해시키}.mp3
class TtsCache {
  static String? _cacheDirPath;

  static String _key(String text, String voice) {
    final combined = '$text|$voice';
    final h = combined.hashCode.abs().toRadixString(16);
    return '${h}_${combined.length}';
  }

  static Future<String> _getDir() async {
    if (_cacheDirPath != null) return _cacheDirPath!;
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/tts_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    _cacheDirPath = cacheDir.path;
    return _cacheDirPath!;
  }

  static Future<Uint8List?> get(String text, String voice) async {
    try {
      final path = '${await _getDir()}/${_key(text, voice)}.mp3';
      final file = File(path);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (_) {}
    return null;
  }

  static Future<void> put(String text, String voice, Uint8List data) async {
    try {
      final path = '${await _getDir()}/${_key(text, voice)}.mp3';
      await File(path).writeAsBytes(data);
    } catch (_) {}
  }

  /// 캐시 용량 관리 (100MB 초과 시 오래된 파일부터 제거)
  static Future<void> cleanup({int maxBytes = 100 * 1024 * 1024}) async {
    try {
      final dir = Directory(await _getDir());
      final files =
          await dir.list().where((e) => e is File).cast<File>().toList();
      int total = 0;
      final infos = <MapEntry<File, int>>[];
      for (final f in files) {
        final stat = await f.stat();
        infos.add(MapEntry(f, stat.modified.millisecondsSinceEpoch));
        total += stat.size;
      }
      if (total > maxBytes) {
        infos.sort((a, b) => a.value.compareTo(b.value));
        for (final entry in infos) {
          final sz = (await entry.key.stat()).size;
          await entry.key.delete();
          total -= sz;
          if (total <= maxBytes * 0.8) break;
        }
      }
    } catch (_) {}
  }
}

// ====================================================================
// 📦 [Box 7-E: TtsQueueManager] — AI 대기 플래그 추가
// ====================================================================
// 🔧 [v3] _aiPaused 플래그로 "유저 낭독 완료 전까지 AI 재생 대기" 구현
class TtsQueueManager {
  final AudioPlayer _player = AudioPlayer();
  // 🔧 [v3.5] 분리된 두 큐
  final List<Uint8List> _userQueue = []; // 유저 TTS 전용
  final List<Uint8List> _aiQueue = []; // AI TTS 전용

  bool _isPlaying = false;
  Completer<void>? _completer;
  StreamSubscription? _completeSub;
  final VoidCallback? onPlayStart;
  final VoidCallback? onQueueEmpty;

  // AI 재생 대기 플래그 (유저 재생 중 또는 유저 재생 직후 안전 간격)
  bool _aiPaused = false;

  // 🔧 [v3.6] 외부에서 _aiPaused 상태 조회 (UI 업데이트 보류 판단용)
  bool get aiPaused => _aiPaused;
  // UI 상태 표시용 (레거시 호환)
  bool _isUserTurn = true;

  /// 유저 재생 중이거나 유저 큐에 남은 게 있으면 busy
  bool get isBusy =>
      _isPlaying ||
      _userQueue.isNotEmpty ||
      (!_aiPaused && _aiQueue.isNotEmpty);

  TtsQueueManager({this.onPlayStart, this.onQueueEmpty}) {
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (_completer != null && !_completer!.isCompleted) {
        _completer!.complete();
      }
    });
  }

  /// AI 청크 재생 일시정지/재개
  void setAiPaused(bool paused) {
    _aiPaused = paused;
    if (!paused &&
        !_isPlaying &&
        (_userQueue.isNotEmpty || _aiQueue.isNotEmpty)) {
      _processQueue();
    }
  }

  /// 레거시 호환용 (UI 상태 표시만)
  void setUserTurn(bool isUser) {
    _isUserTurn = isUser;
  }

  /// 🔧 [v3.5] isUser=true면 유저 큐, false면 AI 큐에 적재
  Future<void> addAudio(Uint8List bytes, {required bool isUser}) async {
    if (isUser) {
      _userQueue.add(bytes);
    } else {
      _aiQueue.add(bytes);
    }
    if (!_isPlaying) _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isPlaying) return;
    _isPlaying = true;
    onPlayStart?.call();

    // 🔧 [v3.5] 재생 우선순위:
    //   1순위: 유저 큐 (항상 우선)
    //   2순위: AI 큐 (유저 큐 비고 _aiPaused=false일 때만)
    while (_userQueue.isNotEmpty || (!_aiPaused && _aiQueue.isNotEmpty)) {
      Uint8List bytes;
      if (_userQueue.isNotEmpty) {
        bytes = _userQueue.removeAt(0);
      } else if (!_aiPaused && _aiQueue.isNotEmpty) {
        bytes = _aiQueue.removeAt(0);
      } else {
        break;
      }

      if (bytes.isEmpty) continue;

      _completer = Completer<void>();
      final estimatedDuration = Duration(
        seconds: ((bytes.length / 16000) + 3).ceil(),
      );

      try {
        await _player.play(BytesSource(bytes));
        await _completer!.future.timeout(estimatedDuration);
      } catch (_) {
      } finally {
        if (_completer != null && !_completer!.isCompleted) {
          _completer!.complete();
        }
      }
    }

    _isPlaying = false;
    if (_userQueue.isEmpty && _aiQueue.isEmpty) onQueueEmpty?.call();
  }

  void stop() {
    _userQueue.clear();
    _aiQueue.clear();
    _isPlaying = false;
    _aiPaused = false;
    _player.stop();
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
    }
  }

  Future<void> dispose() async {
    stop();
    await _completeSub?.cancel();
    await _player.dispose();
  }
}

// ====================================================================
// 📦 [Box 7-F: ChunkedTtsFetcher] — 캐싱 + 재시도
// ====================================================================
// 🔧 [v3] _fetch 단계에서 로컬 캐시 먼저 확인, 미스 시에만 API 호출 + 저장
class ChunkedTtsFetcher {
  final String apiKey;
  final TtsQueueManager audioQueue;
  final String voice;
  final String language;
  final bool isUser; // 🔧 [v3.5] true=유저 큐, false=AI 큐
  final void Function(String tag, String msg)? onLog; // 🔬 [v3.1] 로그 훅

  int _requestCounter = 0;
  int _readyCounter = 0;
  final Map<int, Uint8List> _buffer = {};
  int _pendingCount = 0;
  int get pendingRequests => _pendingCount;
  VoidCallback? onAllComplete;

  ChunkedTtsFetcher(
    this.apiKey,
    this.audioQueue,
    this.voice, {
    this.language = 'en',
    this.isUser = true, // 🔧 [v3.5] 기본값: 유저 큐
    this.onAllComplete,
    this.onLog,
  });

  void addText(String text) {
    if (text.trim().isEmpty) return;
    _pendingCount++;
    final turnTag = isUser ? 'USER' : 'AI';
    onLog?.call(
        '🔊 [TTS-01]', '[$turnTag] addText: "$text" (pending=$_pendingCount)');
    _fetch(_requestCounter++, text);
  }

  Future<void> _fetch(int id, String text) async {
    // [1단계] 로컬 캐시 확인 (히트 시 즉시 반환)
    final cached = await TtsCache.get(text, voice);
    if (cached != null && cached.isNotEmpty) {
      _buffer[id] = cached;
      _pendingCount--;
      _pushReady();
      if (_pendingCount == 0) onAllComplete?.call();
      return;
    }

    // [2단계] API 호출 (재시도 1회)
    Uint8List result = Uint8List(0);
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await http
            .post(
              Uri.parse('https://api.openai.com/v1/audio/speech'),
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'model': 'tts-1',
                'input': text,
                'voice': voice,
                'speed': 1.0,
                'response_format': 'mp3',
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          result = res.bodyBytes;
          final turnTag = isUser ? 'USER' : 'AI';
          onLog?.call('🔊 [TTS-02]',
              '[$turnTag] API OK (${result.length}B) for "$text"');
          // [3단계] 캐시 저장 (백그라운드)
          TtsCache.put(text, voice, result);
          break;
        } else {
          onLog?.call('❌ [TTS-API-ERR]', 'statusCode=${res.statusCode}');
        }
      } catch (_) {
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }

    _buffer[id] = result;
    _pendingCount--;
    _pushReady();
    if (_pendingCount == 0) onAllComplete?.call();
  }

  void _pushReady() {
    while (_buffer.containsKey(_readyCounter)) {
      final data = _buffer.remove(_readyCounter)!;
      // 🔧 [v3.5] isUser 플래그로 큐 선택
      if (data.isNotEmpty) audioQueue.addAudio(data, isUser: isUser);
      _readyCounter++;
    }
  }

  void reset() {
    _requestCounter = 0;
    _readyCounter = 0;
    _buffer.clear();
    _pendingCount = 0;
  }
}

// ====================================================================
// 📦 [Box 7-G: RelayPipeline] — 범용 파이프라인 (참고용, 위젯에선 Box 5-A 사용)
class RelayPipeline {
  final String openAiKey;
  final String deepgramKey;
  final String ttsVoice;
  final String targetLanguage;
  final String systemPrompt;
  final AudioRecorder audioRecorder;

  late final ConversationHistory _history;
  late final DeepgramV2VoiceManager _voiceManager;
  late final TtsQueueManager _ttsQueue;
  late ChunkedTtsFetcher _ttsFetcher;

  bool _isSpeaking = false;

  RelayPipeline({
    required this.openAiKey,
    required this.deepgramKey,
    required this.ttsVoice,
    required this.targetLanguage,
    required this.systemPrompt,
    required this.audioRecorder,
    int historyTokens = 2000,
  }) {
    _history = ConversationHistory(maxTokens: historyTokens);

    _ttsQueue = TtsQueueManager(
      onPlayStart: () => _isSpeaking = true,
      onQueueEmpty: () => _isSpeaking = false,
    );

    _ttsFetcher = ChunkedTtsFetcher(
      openAiKey,
      _ttsQueue,
      ttsVoice,
      language: targetLanguage,
    );

    _voiceManager = DeepgramV2VoiceManager(
      apiKey: deepgramKey,
      audioRecorder: audioRecorder,
      langCode: targetLanguage,
      onConnected: () => print('[Deepgram] 연결됨'),
      onTranscriptUpdate: (_) {}, // UI에서 오버라이드
      onTurnEnded: _onUserTurnEnded,
      onError: (e) => print('[Deepgram] 오류: $e'),
      onReconnecting: (attempt) => print('[Deepgram] 재연결 시도 $attempt/5회'),
      onGaveUp: () => print('[Deepgram] 재연결 포기'),
    );
  }

  Future<void> start() => _voiceManager.connectAndStart();

  /// 💡 신규: 유저가 AI 말 중에 말을 시작하면 즉시 중단 (바지인터럽트)
  void interruptAi() {
    _ttsQueue.stop();
    _ttsFetcher.reset();
    _isSpeaking = false;
  }

  Future<void> _onUserTurnEnded(String userText) async {
    // 💡 AI가 말하는 중에 유저가 말하면 즉시 중단
    if (_isSpeaking) interruptAi();

    _history.add('user', userText);

    String aiResponseBuffer = '';
    String ttsBuffer = '';

    try {
      await for (final chunk in UnifiedBrain.streamChat(
        apiKey: openAiKey,
        systemPrompt: systemPrompt,
        userMessage: userText,
        history: _history,
        temp: 0.2,
      )) {
        aiResponseBuffer += chunk;
        ttsBuffer += chunk;

        // 💡 개선된 쪼개기: 다국어 구두점 패턴 사용
        final segments = _splitByDelimiter(ttsBuffer);
        if (segments.length > 1) {
          // 마지막 미완성 세그먼트는 버퍼에 남김
          for (int i = 0; i < segments.length - 1; i++) {
            final segment = segments[i].trim();
            if (segment.isNotEmpty) _ttsFetcher.addText(segment);
          }
          ttsBuffer = segments.last;
        }
      }

      // 스트림 종료 후 남은 버퍼 처리
      if (ttsBuffer.trim().isNotEmpty) {
        _ttsFetcher.addText(ttsBuffer.trim());
      }

      // 💡 신규: AI 응답 완료 후 히스토리 저장
      if (aiResponseBuffer.isNotEmpty) {
        _history.add('assistant', aiResponseBuffer.trim());
      }
    } catch (e) {
      print('[RelayPipeline] AI 오류: $e');
    }
  }

  /// 💡 신규: 쪼개기 로직 분리 (다국어 구두점 정규식 사용)
  List<String> _splitByDelimiter(String text) {
    final segments = <String>[];
    int lastSplit = 0;

    for (final match in kTtsDelimiterPattern.allMatches(text)) {
      segments.add(text.substring(lastSplit, match.end));
      lastSplit = match.end;
    }
    segments.add(text.substring(lastSplit)); // 남은 부분 (미완성)

    return segments;
  }

  Future<void> dispose() async {
    await _voiceManager.dispose();
    await _ttsQueue.dispose();
  }
}

// ============================================================================

// ====================================================================
// 🧠 [Box 7-1] StepExpandBrain v3 — 스텝익스팬드 전용 AI 뇌
// ====================================================================
// 📂 서브박스 구성:
//   [Box 7-1-A] streamUserTranslation  — 첫턴=단순번역, 2턴+=Part1+\n\n+Part2
//   [Box 7-1-B] generateCleanOriginal  — 영→한 역번역 (\n\n 유지)
//   [Box 7-1-C] streamGrammarQuestion  — 턴 1~4: 문법 유도, 턴 5: 마무리
//   [Box 7-1-D] polishSentence          — 세련된 변형 생성 (스피킹용 고급)
// ====================================================================
class StepExpandBrain {
  // ==================================================================
  // 📦 [Box 7-1-0] splitIntoMeaningUnits — Practice용 의미단위 분해
  // ------------------------------------------------------------------
  // 문장을 6~12개의 의미단위(청크)로 분해. "|" 구분자로 반환.
  // ==================================================================
  static Future<List<String>> splitIntoMeaningUnits({
    required String apiKey,
    required String sentence,
  }) async {
    final client = http.Client();
    try {
      final res = await client
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'gpt-4o-mini',
              'temperature': 0.1,
              'max_tokens': 300,
              'messages': [
                {
                  'role': 'system',
                  'content': 'Split the following English sentence into 6 to 12 small, natural meaning units for speaking practice.\n'
                      'Each unit = one natural phrase or chunk (subject, verb phrase, prepositional phrase, clause, etc.).\n'
                      'Output ONLY the units separated by the "|" character. No numbering, no explanation.\n'
                      'Example output: I remembered | to call Alex | at the office | because he needed | the final report | by Monday morning.'
                },
                {'role': 'user', 'content': sentence},
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final text =
            (json['choices'][0]['message']['content'] as String).trim();
        final units = text
            .split('|')
            .map((u) => u.trim())
            .where((u) => u.isNotEmpty)
            .toList();
        if (units.length >= 2) return units;
      }
    } catch (_) {
    } finally {
      client.close();
    }
    // 폴백: 쉼표/전치사구 기준 단순 분리
    final raw = sentence
        .split(RegExp(
            r'(?<=[,;])\s+|(?=\s+(?:because|when|although|which|who|where|that|and|but|so|to)\s)'))
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();
    return raw.isNotEmpty ? raw : [sentence];
  }

  // ==================================================================
  // 📦 [Box 7-1-A] streamUserTranslation — CoT 2단계 + 성장 머징
  // ------------------------------------------------------------------
  // 🌱 두 가지 케이스:
  //   CASE 1 (첫 턴): 단순 번역 1개만
  //   CASE 2 (2턴+): Part1(짧은 번역) + \n\n + Part2(성장한 확장 문장)
  // ==================================================================
  static Stream<String> streamUserTranslation({
    required String apiKey,
    required String textOriginal,
    required String targetLang,
    required String contextStr,
  }) async* {
    final client = http.Client();
    try {
      final sysPrompt =
          """You are a [Step Expand Translator] translating Korean to $targetLang.
You help the user grow ONE English sentence across multiple turns, adding details each turn.

Read the 'History' carefully to determine the user's current turn.

[CASE CORRECTION] — Check this FIRST, but only when History contains at least one 'User:' line
The user is correcting the AI's misunderstanding of a previous answer.
Signs:
- Starts with correction signals: "아니" / "아니요" / "아 그게 아니라" / "다시" / "내 말은" / "그러니까" / "I mean" / "actually" / "no," / "wait,"
- AND the content is clearly a re-statement or clarification of the LAST 'User:' line in History (not new story info)
- The user is essentially saying "that's not what I said — what I said was X"
If this is a correction, output EXACTLY: [CORRECTION]
Do NOT output [CORRECTION] when the user simply adds new details that happen to start with "아니" etc.

[CASE 1] History is empty (USER'S FIRST TURN)
- Simply translate the user's Korean input into ONE natural English sentence.
- DO NOT expand. DO NOT add anything extra.
- Example Input: 알렉스에게 전화할 생각이 났어요.
- Example Output: I remembered to call Alex.

[CASE 2] History exists (USER'S SECOND+ TURN)
- Output EXACTLY two parts, separated by an empty line (\n\n).
- PART 1: A short, natural translation of ONLY the new Korean input.
- PART 2: A grown/expanded English sentence that naturally merges:
    (a) The most recent expanded sentence from History
    (b) The new information from Part 1
  Use varied grammatical structures to merge them smoothly:
    - Relative clauses (who/which/where/that)
    - Participial phrases (-ing / -ed)
    - To-infinitives (to V)
    - Prepositional phrases
    - Conjunctions (because/when/although)

[EXAMPLE FOR CASE 2]
History:
User: I remembered to call Alex.
AI: When and how did you remember it?
Input: 갑자기요.
Output:
Suddenly.

I suddenly remembered to call Alex.

[CLARIFICATION GUARD]
Before translating, check: is the subject or object of the utterance clear from the input OR resolvable from History?
If clear → proceed with normal translation.
If genuinely ambiguous AND History cannot resolve it → output EXACTLY:
[CLARIFY] <short, natural clarification question in $targetLang>

Style pool — pick ONE and VARY each time (never repeat the same phrasing twice in a row):
- Direct: "Who are you talking about?"
- Gentle: "Just to be sure — who do you mean?"
- Curious: "Oh — who's that about?"
- Confirming: "Do you mean [person/thing from history]?"
- Playful: "I'm gonna need a name to work with here!"

NEVER output [CLARIFY] if the subject can be reasonably inferred from context.

[RULES]
- CASE 2 output MUST have the empty line (\n\n) between parts.
- Output ONLY the translation. No labels, no "Part 1:", no meta-comments.
- Insert commas (,) after natural phrases for TTS rhythm.
- If the input is meaningless noise (random symbols, silence markers, or clearly non-speech artifacts), output EXACTLY: [EVAPORATE]
- Speech recognition may produce garbled or unusual text when the user's pronunciation is unclear. If the input looks garbled but a plausible meaning can be inferred from the conversation context, make your best interpretation and still produce the normal output — do NOT output [RETRY] in this case.
- Output [RETRY] ONLY when the input is on a completely unrelated topic AND no reasonable interpretation is possible even with context.""";

      final request = http.Request(
        'POST',
        Uri.parse('https://api.openai.com/v1/chat/completions'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json; charset=utf-8',
      });
      request.body = jsonEncode({
        'model': 'gpt-4o-mini',
        'stream': true,
        'temperature': 0.0,
        'max_tokens': 200,
        'messages': [
          {'role': 'system', 'content': sysPrompt},
          {
            'role': 'user',
            'content': 'History:\n$contextStr\n\nInput: $textOriginal'
          },
        ],
      });

      final response =
          await client.send(request).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        yield '[EVAPORATE]';
        return;
      }

      await for (final chunk in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (chunk.startsWith('data: ') && chunk != 'data: [DONE]') {
          try {
            final delta = jsonDecode(chunk.substring(6))['choices'][0]['delta']
                ['content'];
            if (delta != null) yield delta.toString();
          } catch (_) {}
        }
      }
    } catch (_) {
      yield '[EVAPORATE]';
    } finally {
      client.close();
    }
  }

  // ==================================================================
  // 📦 [Box 7-1-B] generateCleanOriginal — 영→한 역번역 (2파트 유지)
  // ------------------------------------------------------------------
  // 🌱 영어의 \n\n 줄바꿈을 한국어에도 동일하게 유지
  // ==================================================================
  static Future<String> generateCleanOriginal({
    required String apiKey,
    required String englishText,
  }) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      final client = http.Client();
      try {
        final res = await client
            .post(
              Uri.parse('https://api.openai.com/v1/chat/completions'),
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json; charset=utf-8',
              },
              body: jsonEncode({
                'model': 'gpt-4o-mini',
                'temperature': 0.2,
                'max_tokens': 120,
                'messages': [
                  {
                    'role': 'system',
                    'content':
                        '''당신은 영한 번역가입니다. 주어진 영어를 한국어 구어체로 번역하세요.

[규칙]
- 원문 내용만 번역. 설명·부연·의견 추가 절대 금지.
- 짧은 문장은 짧게, 긴 문장은 길게 — 원문 길이에 비례하게.
- 한국어 주어 생략: 문맥상 명확한 I/You/We/They는 생략.
- 구어체 (문어체 X).
- 원문에 빈 줄(\\n\\n)이 있으면 한국어에도 그대로 유지.
- 번역문만 출력. 설명/주석/따옴표 없음.
''',
                  },
                  {'role': 'user', 'content': englishText},
                ],
              }),
            )
            .timeout(const Duration(seconds: 15));

        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          return data['choices'][0]['message']['content'].toString().trim();
        }
      } catch (_) {
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      } finally {
        client.close();
      }
    }
    return englishText;
  }

  // ==================================================================
  // 📦 [Box 7-1-C] streamGrammarQuestion — 턴별 유도 질문
  // ------------------------------------------------------------------
  // 🎯 턴 1~(MAX_TURNS-1): 문법 다양성 유도 질문
  //   턴 MAX_TURNS: 최종 합성 (Expanded Sentence)
  //
  // 💡 실제 작동 예시 — 이런 식으로 대화가 흘러갑니다
  //
  // AI : Are there any specific tasks on your agenda for today?
  //      (혹시 오늘 꼭 해야할 일이 있나요?)
  // User: I remembered to call Alex.
  //       (알렉스에게 전화할 생각이 났어요.)
  //
  // AI : When and how did you remember it?
  //      (언제, 어떻게 기억이 났나요?)
  // User: Suddenly.
  //       (갑자기요.)
  //
  //       I suddenly remembered to call Alex.
  //       (문득 알렉스에게 전화할 생각이 났어요.)
  //
  // AI : What were you doing at that time?
  //      (그때 뭘 하고 있었나요?)
  // User: I was checking my emails this morning.
  //       (오늘 아침에 이메일을 확인하고 있었어요.)
  //
  //       Checking my emails this morning, I suddenly remembered to call Alex.
  //       (오늘 아침 이메일을 확인하다가, 문득 알렉스에게 전화할 생각이 났어요.)
  //
  // AI : Who is Alex?
  //      (알렉스가 누구죠?)
  // User: He is my old friend.
  //       (제 오랜 친구예요.)
  //
  //       Checking my emails this morning, I suddenly remembered to call my old friend, Alex.
  //       (오늘 아침 이메일을 확인하다가, 문득 내 오랜 친구인 알렉스에게 전화할 생각이 났어요.)
  //
  // AI : How is Alex doing these days?
  //      (알렉스는 요즘 어떻게 지내나요?)
  // User: He recently moved to London.
  //       (최근에 런던으로 이사 갔어요.)
  //
  //       Checking my emails this morning, I suddenly remembered to call my old friend, Alex,
  //       who recently moved to London.
  //       (오늘 아침 이메일을 확인하다가, 문득 최근 런던으로 이사 간 내 오랜 친구 알렉스에게 전화할 생각이 났어요.)
  //
  // AI : Why did you want to call him?
  //      (왜 전화하려고 했나요?)
  // User: To ask him about the restaurant.
  //       (그 식당에 대해 물어보려고요.)
  //
  //       Checking my emails this morning, I suddenly remembered to call my old friend, Alex,
  //       who recently moved to London, to ask him about the restaurant.
  //       (오늘 아침 이메일을 확인하다가, 최근 런던으로 이사 간 오랜 친구 알렉스에게 그 식당에 관해 물어보려고 전화할 생각이 났어요.)
  //
  // AI : What kind of restaurant is it?
  //      (그 식당이 어떤 곳인데요?)
  // User: It's where we had dinner last year.
  //       (작년에 우리가 저녁을 먹었던 곳이에요.)
  //
  //       Checking my emails this morning, I suddenly remembered to call my old friend, Alex,
  //       who recently moved to London, to ask him about the restaurant where we had dinner last year.
  //       (오늘 아침 이메일을 확인하다가, 작년에 우리가 저녁을 먹었던 식당에 대해 물어보려고
  //        최근 런던으로 이사 간 오랜 친구 알렉스에게 전화해야 한다는 사실이 문득 떠올랐어요.)
  //
  // Expanded Sentence:
  //   Checking my emails this morning, I suddenly remembered to call my old friend, Alex,
  //   who recently moved to London, to ask him about the restaurant where we had dinner last year.
  //
  // Polished Sentence:
  //   While checking my emails this morning, I suddenly thought of calling Alex—
  //   an old friend who just moved to London—to ask about the restaurant where we dined last year.
  // ==================================================================
  static Stream<String> streamGrammarQuestion({
    required String apiKey,
    required String contextStr,
    required int turnNumber,
    required int maxTurns,
    required String myTarget,
    String myNative = '',
    bool isRetry = false,
    bool isOpening = false, // 세션 첫 시작 — AI가 먼저 개방형 질문
  }) async* {
    final client = http.Client();
    try {
      final bool isFinalTurn = turnNumber >= maxTurns;

      // ── 개방형 오프닝 질문 프롬프트 ──────────────────────────────────
      // "예/아니오"로 답할 수 없는 질문만 허용
      // How / Why / What 으로 시작 → 유저가 자기 이야기를 자연스럽게 꺼냄
      // 첫 질문 이후 유저 대답부터 문장 확장(expand) 시작
      if (isOpening) {
        // ── [STEP 1] 오늘 뉴스 헤드라인 1건 선정 ────────────────────────
        // 가볍고 일상적인 뉴스 (생활/날씨/음식/문화/스포츠)만 선정
        // 정치·사회·AI윤리 등 무거운 주제 제외
        String newsHeadline = '';
        final newsClient = http.Client();
        try {
          final newsRes = await newsClient
              .post(
                Uri.parse('https://api.openai.com/v1/chat/completions'),
                headers: {
                  'Authorization': 'Bearer $apiKey',
                  'Content-Type': 'application/json; charset=utf-8',
                },
                body: jsonEncode({
                  'model': 'gpt-4o-mini',
                  'max_tokens': 20,
                  'temperature': 0.9,
                  'messages': [
                    {
                      'role': 'system',
                      'content':
                          'Pick ONE light, everyday small-talk topic for an English conversation warm-up.\n'
                          'STEP A — Silently choose ONE category at random from this WIDE pool (do not always pick the first ones):\n'
                          '  food & cooking, weather & seasons, travel & places, hobbies & free time, movies & TV, music, books & reading, sports & exercise, technology & gadgets, pets & animals, fashion & style, health & sleep, work & study life, childhood memories, dreams & future plans, local festivals & events, coffee & cafes, shopping & trends, nature & outdoors, holidays & celebrations.\n'
                          'STEP B — Inside that ONE category, invent a fresh, specific everyday topic.\n'
                          'Each time you are called, pick a DIFFERENT category than an obvious default — vary widely across the whole pool.\n'
                          'FORBIDDEN: politics, war, AI ethics, crime, economics, illness, anything heavy or controversial.\n'
                          'Output format: ONLY a 4-to-8-word English noun phrase. No verb. No question. No punctuation.\n'
                          'Examples (note how different the categories are):\n'
                          'a cozy rainy-day movie marathon\n'
                          'learning to bake sourdough bread\n'
                          'a weekend hiking trip in autumn\n'
                          'an old song stuck in your head\n'
                          'rearranging furniture in your room\n'
                          'a childhood snack you suddenly miss',
                    },
                    {
                      'role': 'user',
                      'content': 'Today\'s topic.',
                    },
                  ],
                }),
              )
              .timeout(const Duration(seconds: 10));
          if (newsRes.statusCode == 200) {
            final newsJson = jsonDecode(utf8.decode(newsRes.bodyBytes));
            final choices = newsJson['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              newsHeadline =
                  (choices[0]['message']?['content'] ?? '').toString().trim();
            }
          }
        } catch (_) {
          newsHeadline = '';
        } finally {
          newsClient.close();
        }

        // ── [STEP 2] 뉴스 소재 기반 짧은 오프닝 질문 생성 (streaming) ──
        final String openingSysPrompt = newsHeadline.isNotEmpty
            ? 'You are starting a casual English conversation.\n'
              'News topic: "$newsHeadline"\n\n'
              'Write ONE short open-ended question in $myTarget about this topic.\n'
              'Rules:\n'
              '- ONE sentence only. 8 words or fewer.\n'
              '- Sound like a friend, not a reporter.\n'
              '- Never yes/no.\n'
              'Output ONLY the question. Nothing else.'
            : 'You are starting a casual English conversation.\n'
              'Write ONE short open-ended question in $myTarget about something from everyday life.\n'
              'Rules:\n'
              '- ONE sentence only. 8 words or fewer.\n'
              '- Sound like a friend, not an interviewer.\n'
              '- Never yes/no.\n'
              'Output ONLY the question. Nothing else.';

        final openReq = http.Request(
          'POST',
          Uri.parse('https://api.openai.com/v1/chat/completions'),
        );
        openReq.headers.addAll({
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json; charset=utf-8',
        });
        openReq.body = jsonEncode({
          'model': 'gpt-4o-mini',
          'stream': true,
          'temperature': 0.7,
          'max_tokens': 30,
          'messages': [
            {'role': 'system', 'content': openingSysPrompt},
            {'role': 'user', 'content': 'Go.'},
          ],
        });
        final openResp =
            await openReq.send().timeout(const Duration(seconds: 15));
        if (openResp.statusCode != 200) {
          return;
        }
        await for (final chunk in openResp.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (chunk.startsWith('data: ') && chunk != 'data: [DONE]') {
            try {
              final delta = jsonDecode(chunk.substring(6))['choices'][0]
                  ['delta']['content'];
              if (delta != null) yield delta.toString();
            } catch (_) {}
          }
        }
        return;
      }
      // ─────────────────────────────────────────────────────────────────

      final String grammarHint = turnNumber == 1
          ? 'FOCUS: Follow the FEELING or MOTIVATION behind what the user just said.\n'
              'Silently guess WHY this matters to them or how they feel about it, then ask a light question that follows that thread — not a question that extracts a fixed answer.\n'
              'If the user clearly expressed loss of interest, motivation, enjoyment, or willingness to engage, follow that emotion instead (see [EMOTIONAL DEPTH RULE]).\n'
              'Their short answer (e.g. "because it was fun", "I was just curious") should attach smoothly to the growing sentence.'
          : turnNumber == 2
              ? 'FOCUS: Follow the PERSON, PLACE, or THING that seems to matter most in their story.\n'
                  'Guess what detail they would naturally want to share more about, and ask about that — gently and curiously, never like a checklist.\n'
                  'Their short answer (e.g. "my friend Jisu", "at the cafe") should attach naturally to the growing sentence.'
              : turnNumber == 3
                  ? 'FOCUS: Follow how they FELT or what stood out to them.\n'
                      'Guess the emotion or the surprising/memorable part behind their last answer, and ask about it lightly. Do not force a contrast — let it emerge from their feeling.\n'
                      'Their short answer (e.g. "it was a relief", "even though I was nervous") should attach naturally to the growing sentence.'
                  : 'FOCUS: Follow where their story is naturally heading — a moment, a situation, or what it means to them.\n'
                      'Guess what they would enjoy adding, and invite it gently and openly.\n'
                      'Their short answer (e.g. "when I have free time", "after work") should attach naturally to the growing sentence.';

      // ── 3단계 (최종 합성): 파편화된 답변 → Expanded Sentence ──────────────
      // ── 2단계 (문법 유도형 질문): 5-8단어 초단형, 구조를 이름 짓지 않고 유도 ──
      final String sysPrompt = isFinalTurn
          ? """You are a Step Expand grammar coach.
This is the FINAL turn ($turnNumber of $maxTurns). The user has answered your grammar-inducing questions step by step.

[YOUR JOB — Synthesis]
Read the History carefully. Collect the user's fragmented answers and synthesize them into ONE fluent sentence that naturally incorporates at least 2 of these structures:
- Causal clause (because / since)
- Relative clause (who / which)
- Concessive clause (although / despite / even though)
- Conditional clause (if / when)

[RULES]
- The user's lines in History may contain speech recognition errors due to unclear pronunciation. Infer the most likely intended meaning from context — do not quote garbled words literally.
- Reflect the user's intended meaning. Do not invent new facts beyond reasonable inference.
- Fluent, natural spoken English — not overly academic.
- Label the sentence with "Expanded Sentence:" prefix.

[OUTPUT FORMAT - STRICT]
Output EXACTLY two parts separated by ONE empty line.
PART 1: "Expanded Sentence: " + your synthesized sentence (25–40 words) + newline + "Grammar used: [list]"
PART 2: A natural Korean conversational translation of the synthesized sentence."""
          : """You are a Step Expand conversation guide. You are on turn $turnNumber of $maxTurns.

Read the conversation History carefully.

[YOUR ROLE]
You are a warm, skilled conversation coach — not a grammar teacher. Your job is to ask ONE short, natural question that makes the user want to share one more detail about their story. The detail they share will naturally grow the sentence, but you NEVER mention grammar.

[TWO-LAYER DESIGN — MANDATORY]

LAYER 1 — INTERNAL REASONING (never output, work silently):
Before writing your question, think through — in THIS order:
① FEELING FIRST: Read the user's LAST answer. What is the person likely thinking, feeling, or caring about underneath it? What motivated them to say it? Follow THAT thread.
② DO NOT just grab the first or most concrete noun in their answer and ask "what kind of X?" — that is shallow keyword-echoing and makes the user feel interrogated.
   Instead, go ONE level deeper than the surface words: their reason, motivation, mood, memory, hope, or the meaning behind what they said. Ask what a genuinely curious friend would actually wonder about.
③ Balance two moves — do not always use the same one:
   (a) GENUINE CURIOSITY: ask the real, specific thing you'd want to know about their situation.
   (b) EMOTIONAL CONTEXT: read the feeling under their words and gently follow it.
   Use whichever makes the user WANT to keep talking. The [TURN GOAL] below is only a soft lens, never a target you must extract.
④ What is the most natural, low-pressure 5–8-word question that picks up that one detail?
   - Can a quiet or hesitant person still answer in 1–3 words?
   - Does it avoid pressure words ("Why did you do that?", "Explain your reason")?
   - Does it avoid yes/no answers?
⑤ Does the question flow from the user's LAST statement and avoid already-covered ground?
   The user's short answer should still attach naturally to the growing sentence (this never changes).
NEVER reveal this reasoning in the output.

LAYER 2 — OUTPUT (the only thing you say):
ONE question. 5 to 8 words. Warm and direct. No preamble.
Output the question alone — nothing before it, nothing after it (except the PART 2 translation).

[TURN GOAL]
$grammarHint

[SPEECH RECOGNITION TOLERANCE — READ THIS FIRST]
The user speaks into a microphone. Speech recognition may produce imperfect text.
- If a user's line in History seems garbled or unusual, infer the most likely intended meaning from context and continue naturally.
- NEVER ask the user to repeat themselves or comment on unclear input.
- Always extract the most plausible meaning and build on it.

[CONTEXT-FIRST RULE — MANDATORY CHECK]
Scan the ENTIRE History before choosing your question:
- If "who" is already answered → NEVER ask "who" again. Shift to WHY, HOW, or WHAT HAPPENED.
- If "where" is already answered → NEVER ask "where" again. Zoom into FEELINGS or CONSEQUENCE.
- If "what" is already answered → NEVER ask "what" again. Dig into REASON or RESULT.
- If "when" is already answered → do NOT ask "when" again. Focus on IMPACT or REACTION.
- Always build on the MOST RECENT user statement. Never repeat ground already covered.

[EMOTIONAL DEPTH RULE — HIGHEST PRIORITY]
Before applying any TURN GOAL, check whether the user's LAST answer clearly expresses loss of interest, motivation, enjoyment, or willingness to engage.

Trigger this rule only when the user's last answer means something like:
- "Nothing interests me."
- "I don't find anything interesting."
- "I don't care about much these days."
- "Nothing feels fun."
- "I don't feel like talking."
- "흥미로운 게 없어."
- "관심 있는 게 없어."
- "요즘 재미있는 게 없어."
- "딱히 말하고 싶은 게 없어."

Do NOT trigger this rule for a vague "I don't know", "maybe", "그냥", or "모르겠어" unless the surrounding context clearly shows emotional withdrawal or loss of interest.

If this rule is triggered, OVERRIDE the normal TURN GOAL and instead:
1. Do NOT repeat or rephrase the same topic question. Asking "what else interests you?" after "nothing interests me" is robotic and tone-deaf.
2. Treat the user's disinterest as the story itself.
3. Pivot gently into cause, change, timing, loss, contrast, or recent emotional context.
4. Do not sound like a therapist. Keep the question casual, warm, and sentence-building friendly.
5. The question must still be 5–8 words, open-ended, and answerable in 1–3 words.
6. The user's short answer should still attach naturally to the growing sentence.

Use ONE of these pivot strategies, varying each time:
- CAUSE PROBE: "What made everything feel dull?" / "What drained your interest lately?"
- TIMING PROBE: "When did things start feeling flat?" / "When did this feeling begin?"
- LOSS PROBE: "What did you enjoy before?" / "What changed for you recently?"
- CONTRAST PROBE: "What last made you feel excited?" / "When did you last feel curious?"
- SOFT EVENT PROBE: "What took the spark away?" / "What happened before this feeling started?"

[EXAMPLE — EMOTIONAL PIVOT]
AI : What's been on your mind lately?
User: Nothing really. (별로 없어.)
  → Nothing has really been on my mind.
AI : When did things start feeling flat?  ← TIMING PROBE (NOT: "What kind of things interest you?")
User: Since I moved here alone. (여기 혼자 이사 온 뒤로.)
  → Nothing has really been on my mind since I moved here alone.
AI : What did you enjoy before? ← LOSS PROBE
User: Having someone to talk to. (얘기할 사람이 있었던 거.)
  → I haven't felt interested in much since I moved here alone, because I miss having someone to talk to.
AI : Who did you talk to most? ← natural follow-up
User: My college roommate. (대학 룸메이트.)
  → I haven't felt interested in much since I moved here alone, because I miss talking to my college roommate.


[QUESTION PRINCIPLES — MANDATORY]
1. Be a curious friend, not an interviewer or grammar teacher.
2. Do not echo the easiest surface word. Go one level deeper — into the reason, feeling, meaning, or memory behind it — and ask what genuinely makes you curious, so the user feels invited to open up.
3. Ask so that even a shy or hesitant user can answer with just 1–3 words.
4. Avoid pressure frames ("Why did you~?", "Explain why~", "Tell me the reason~").
   Use gentle frames instead: "What part~?", "What made it~?", "How did that~?", "What kind of~?"
5. Never give yes/no questions.
6. Design the question so the user's answer naturally attaches to the growing sentence.

[GO DEEPER, NOT WIDER]
"Wider" = staying on the same surface noun the user just said (shallow, robotic).
"Deeper" = moving to the feeling, reason, meaning, or story underneath it (what a real friend asks).
Examples of the SHIFT you must make:
- User: "I want good food for fall."
  WIDER (bad): "What kind of food do you like?"
  DEEPER (good): "What does fall food remind you of?" / "What makes fall feel special to you?"
- User: "I called my old friend."
  WIDER (bad): "What is your friend's name?"
  DEEPER (good): "What made you think of them today?"
- User: "I went hiking last weekend."
  WIDER (bad): "Which mountain did you hike?"
  DEEPER (good): "What did you need to get away from?" / "How did it clear your head?"
RULE: After drafting your question, check — am I just naming their noun again (WIDER)? If yes, rewrite it to go DEEPER.
BUT keep balance: a deeper question must still be light, answerable in 1–3 words, and its answer must still attach to the growing sentence. Never become abstract or therapy-like.

[SENTENCE GROWTH LENS]
Before finalizing your question, ask: "If the user answers this in 1–3 words, exactly where does it attach to the growing sentence?" If no clear attachment point exists, revise the question.

[OUTPUT RULES — STRICT]
Output ONLY the bare question. Nothing before it. Nothing after it (except PART 2 translation).
BANNED — never output any of the following:
  - General intro before question ("Many people find...", "It's common that...", "Studies show...")
  - Empathy / reaction before question ("I see", "That's interesting", "I understand why", "Makes sense")
  - Praise / acknowledgement ("Great answer!", "Nice!", "Good point!", "Exactly!")
  - AI opinion ("I think...", "I feel...", "Personally...", "In my view...")
  - Grammar term exposure ("Try using a relative clause", "Now add a because clause")
  - Options / forced choice ("A or B?", "Right or wrong?", "Is it X or Y?")
  - Summary / recap of user's answer ("So you mean...", "In other words...", "So what you're saying is...")
  - Two questions at once
  - Pressure-heavy interrogation ("Why did you do that?", "What was your reason?", "Explain why~")
${isRetry ? "- [RETRY] The previous question confused the user. Ask a simpler, more direct 5–8-word question." : ""}

[EXAMPLE FLOW]
(Notice: each question goes DEEPER — into feeling, reason, or meaning — not just naming the last noun.)
AI : What's something you're looking forward to lately?
User: A trip to Busan.
  → I'm looking forward to a trip to Busan.
AI : What made you pick Busan this time?
User: I needed the ocean.
  → I'm looking forward to a trip to Busan because I needed the ocean.
AI : What does the ocean do for you?
User: It calms me down after work stress.
  → I'm looking forward to a trip to Busan because I needed the ocean, which calms me down after work stress.
AI : What's been weighing on you most?
User: Too many deadlines piling up.
  → I'm looking forward to a trip to Busan because I needed the ocean to calm me down, since too many deadlines have been piling up.

[OUTPUT FORMAT - STRICT]
Output EXACTLY two parts separated by ONE empty line.
PART 1: Your English question (follow all rules above).
PART 2: A natural Korean conversational translation of PART 1.""";

      final request = http.Request(
        'POST',
        Uri.parse('https://api.openai.com/v1/chat/completions'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json; charset=utf-8',
      });
      request.body = jsonEncode({
        'model': 'gpt-4o-mini',
        'stream': true,
        'temperature': 0.2,
        'max_tokens': 300,
        'messages': [
          {'role': 'system', 'content': sysPrompt},
          {
            'role': 'user',
            'content': 'History:\n$contextStr\n\nYour response:'
          },
        ],
      });

      final response =
          await client.send(request).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        yield '...';
        return;
      }

      await for (final chunk in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (chunk.startsWith('data: ') && chunk != 'data: [DONE]') {
          try {
            final delta = jsonDecode(chunk.substring(6))['choices'][0]['delta']
                ['content'];
            if (delta != null) yield delta.toString();
          } catch (_) {}
        }
      }
    } catch (_) {
      yield '...';
    } finally {
      client.close();
    }
  }

  // ==================================================================
  // 📦 [Box 7-1-D] polishSentence — 스피킹용 쉬운 고급 변형
  // ------------------------------------------------------------------
  // 🌱 5턴 완료 후 최종 확장 문장을 "말하기 편한 세련된 문장"으로 변환
  //   - 어려운 단어 피함 (대학원 수준 X)
  //   - 자연스러운 구어체
  //   - 더 나은 리듬 / 문장 구조 다양화
  //   - 스피킹할 때 발음/리듬 편함
  // ==================================================================
  static Future<String> polishSentence({
    required String apiKey,
    required String originalSentence,
  }) async {
    final client = http.Client();
    try {
      const sysPrompt = """You are an English speaking coach.
The user has built a long English sentence through step-by-step expansion.
Your job: Rewrite it as ONE "easy but elegant" spoken English sentence.

[GOALS]
- Natural spoken rhythm (not written/academic)
- Common vocabulary (no SAT words, no bookish phrases)
- Smooth flow (pause-friendly, commas for breath)
- Same meaning as the original (do not add new facts)
- Slightly more elegant/polished than the original
- Easier to pronounce and say out loud

[AVOID]
- Big academic words ("nostalgically", "subsequently", "pertaining to")
- Formal written phrases ("in regards to", "pursuant to")
- Complex nested clauses that are hard to speak
- Adding information not in the original

[OUTPUT]
- Exactly ONE sentence.
- No explanation, no quotes, no prefixes.
- Just the polished sentence.""";

      final res = await client
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
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

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        String polished =
            data['choices'][0]['message']['content'].toString().trim();
        // 따옴표 제거 (혹시 AI가 감싸면)
        if (polished.startsWith('"') && polished.endsWith('"')) {
          polished = polished.substring(1, polished.length - 1);
        }
        return polished;
      }
    } catch (e) {
      print('polishSentence error: $e');
    } finally {
      client.close();
    }
    return originalSentence; // 실패 시 원문 반환
  }

  // ==================================================================
  // 📦 [Box 7-1-E-0] KBS 뉴스 RSS 일별 캐시 + 유저별 중복 방지
  // ------------------------------------------------------------------
  // 가벼운 주제만 필터링 (정치·사고·재난 제외)
  // 하루 1회 RSS fetch 후 SharedPreferences에 캐시
  // 유저 ID별로 출제 이력 관리 → 중복 질문 방지
  // ==================================================================
  static final RegExp _heavyTopicRe = RegExp(
    r'사고|범죄|화재|총격|전쟁|폭발|폭력|사망|붕괴|재난|지진|태풍|홍수|참사|대통령|국회|선거|탄핵|부패|비리',
    caseSensitive: false,
  );

  static Future<List<String>> _fetchKbsNewsTopics() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final cacheKey = 'kbs_news_$today';
    final cached = prefs.getStringList(cacheKey);
    if (cached != null && cached.isNotEmpty) return cached;

    final results = <String>[];
    for (final src in ['culture', 'economy', 'world', 'society']) {
      try {
        final res = await http
            .get(Uri.parse('https://news.kbs.co.kr/rss/rss.do?source=$src'))
            .timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) continue;
        final body = utf8.decode(res.bodyBytes);
        final re =
            RegExp(r'<title><!\[CDATA\[(.*?)\]\]></title>', dotAll: true);
        for (final m in re.allMatches(body).skip(1).take(8)) {
          final title = m.group(1)?.trim() ?? '';
          if (title.isNotEmpty && !_heavyTopicRe.hasMatch(title)) {
            results.add(title);
          }
        }
      } catch (_) {}
    }
    if (results.isNotEmpty) await prefs.setStringList(cacheKey, results);
    return results;
  }

  static Future<String?> _pickUnaskedTopic(String userId) async {
    if (userId.isEmpty) {
      final topics = await _fetchKbsNewsTopics();
      return topics.isNotEmpty ? topics.first : null;
    }
    final prefs = await SharedPreferences.getInstance();
    final askedKey = 'asked_fallback_$userId';
    final asked = Set<String>.from(prefs.getStringList(askedKey) ?? []);
    final topics = await _fetchKbsNewsTopics();
    if (topics.isEmpty) return null;

    final unasked = topics.where((t) => !asked.contains(t)).toList();
    if (unasked.isEmpty) {
      await prefs.remove(askedKey); // 전부 소진 → 이력 초기화
      await prefs.setStringList(askedKey, [topics.first]);
      return topics.first;
    }
    final pick = unasked.first;
    asked.add(pick);
    await prefs.setStringList(askedKey, asked.toList());
    return pick;
  }

  // ==================================================================
  // 📦 [Box 7-1-E] streamOpeningFallbackQuestion — 침묵 폴백용 KBS 뉴스 질문
  // ------------------------------------------------------------------
  // 첫 질문에 답 없거나 망설일 때: KBS 뉴스 가벼운 주제로 의견 질문
  // userId로 유저별 중복 방지 / 하루 1회 RSS 자동 갱신
  // ==================================================================
  static Stream<String> streamOpeningFallbackQuestion({
    required String apiKey,
    required String myTarget,
    String myNative = '',
    String userId = '',
  }) async* {
    String? newsTopic;
    try {
      newsTopic = await _pickUnaskedTopic(userId);
    } catch (_) {}

    final client = http.Client();
    try {
      final String nativeHint = myNative.isNotEmpty
          ? 'The user is from a $myNative-speaking background.\n'
          : '';
      final String topicHint = newsTopic != null
          ? 'KBS news headline (for reference only): "$newsTopic"\n'
              'From this headline, identify ONE concrete everyday WORD — a trend, technology, activity, habit, or concept.\n'
              'Do NOT use a proper noun, person\'s name, or political figure as the word.\n'
              'Ask ONLY about that single word — do NOT summarize or ask judgment on the full news event.\n'
          : 'Pick ONE simple everyday word related to a recent trend or daily life topic.\n';

      final String sysPrompt = 'You are a Step Expand grammar coach.\n'
          'The user hesitated on the opening question. You have already said "다시 질문 할께요" in Korean — '
          'do NOT repeat any intro phrase. Jump straight into the topic.\n'
          '\n'
          '${topicHint}'
          '${nativeHint}'
          '\n'
          '[NO PERSONAL OPINION — STRICT]\n'
          'NEVER express your own feelings, views, or preferences in the question.\n'
          'Your role is a neutral facilitator — you ask, the user speaks.\n'
          'Wrong: "I think [word] is really important these days — what about you?"\n'
          'Right: "These days, [word] keeps coming up for a lot of people. What do you think about it?"\n'
          '\n'
          '[OUTPUT STRUCTURE — follow exactly]\n'
          '1. Mention the ONE chosen word in ONE short neutral sentence that states a general trend, NOT your opinion.\n'
          '   (e.g. "These days, [word] keeps coming up." / "A lot of people have been talking about [word] lately.")\n'
          '2. End with a simple open question inviting the user\'s view on that word only:\n'
          '   "What do you think about [word]?" / "How do you feel about it?" / "Has [word] come up in your life?"\n'
          '   → Do NOT describe or summarize the full news story.\n'
          '   → Do NOT ask the user to judge or agree/disagree with a news event.\n'
          '\n'
          '[GRAMMAR SEED DESIGN — critical]\n'
          'The user\'s response to your question is the SEED for sentence expansion.\n'
          'Design the question angle so that the user\'s natural answer will contain:\n'
          '  • A REASON (because / since) — e.g. "What do you think about [word]?" invites "I think... because..."\n'
          '  • A PERSON or THING (who / which) — e.g. "Has [word] affected anyone you know?"\n'
          '  • A CONDITION (if / when) — e.g. "When does [word] matter most to you?"\n'
          'Pick the angle that best matches the chosen word so the answer seeds the richest expand chain.\n'
          '\n'
          '[RULES]\n'
          '- NO intro phrase (do NOT start with "Let me ask you" or "Here\'s something").\n'
          '- Middle-school level vocabulary — simple, natural, conversational.\n'
          '- Light topics only: NO politics, NO accidents, NO disasters, NO crime.\n'
          '- Output ONLY in $myTarget. No labels, no prefixes.\n'
          '- Total output: under 45 words.';

      final request = http.Request(
        'POST',
        Uri.parse('https://api.openai.com/v1/chat/completions'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json; charset=utf-8',
      });
      request.body = jsonEncode({
        'model': 'gpt-4o-mini',
        'stream': true,
        'temperature': 0.7,
        'max_tokens': 70,
        'messages': [
          {'role': 'system', 'content': sysPrompt},
          {
            'role': 'user',
            'content': 'Ask about the news topic now.',
          },
        ],
      });
      final response =
          await client.send(request).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        yield 'Let me ask you this. These days, more people enjoy cooking at home. What do you think?';
        return;
      }
      await for (final chunk in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (chunk.startsWith('data: ') && chunk != 'data: [DONE]') {
          try {
            final delta = jsonDecode(chunk.substring(6))['choices'][0]['delta']
                ['content'];
            if (delta != null) yield delta.toString();
          } catch (_) {}
        }
      }
    } catch (e) {
      yield 'Let me ask you this. These days, more people enjoy cooking at home. What do you think?';
    } finally {
      client.close();
    }
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

    // 밝은 파란 배경 (상단 좌측)
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

    // 골드 대각선
    canvas.drawLine(
      Offset(size.width * 0.04, size.height * 0.96),
      Offset(size.width * 0.96, size.height * 0.04),
      Paint()
        ..color = const Color(0xFFD4AF37)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // 골드 원형 테두리
    canvas.drawCircle(
      center,
      r - 1.5,
      Paint()
        ..color = const Color(0xFFD4AF37)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    final col = active ? Colors.white : const Color(0x61FFFFFF);

    // 상단 좌측 "T"
    _drawText(canvas, 'T', Offset(size.width * 0.09, size.height * 0.06),
        size.width * 0.34, col);

    // 빨간 원형 포인트 (○)
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

    // 하단 우측 "T"
    _drawText(canvas, 'T', Offset(size.width * 0.55, size.height * 0.58),
        size.width * 0.34, col);
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
