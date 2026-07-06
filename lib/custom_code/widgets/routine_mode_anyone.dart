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
import 'trial/trial_flow_state.dart';
import 'trial/trial_anyone_timer_mixin.dart';
import 'trial/learning_prep_overlay.dart';
import 'trial/trial_study_page.dart';

const int kFreeTalkCommitWaitMs = 900;
const int kFreeTalkDeepgramEndpointingMs = 700;
const int kFreeTalkDeepgramUtteranceEndMs =
    1000; // Deepgram minimum allowed value; 900 returns HTTP 400.
const int kFreeTalkUserTtsFetchTimeoutMs = 15000;
const int kFreeTalkUserTtsPlaybackTimeoutMs = 15000;
const int kFreeTalkAiTtsWaitTimeoutMs = 20000;
const int kFreeTalkOpenAiTtsHttpTimeoutSeconds =
    18; // Long-form cache save path.
const List<int> kFreeTalkChunkTtsTimeoutLadderSec = [
  3,
  5,
  8
]; // Chunk TTS per-attempt timeout ladder.
const int kFreeTalkAiResponseMaxTokens = 70;

/// ==================================================================== [Box
/// 2: 클래스 선언부]
/// ====================================================================
class RoutineModeAnyone extends StatefulWidget {
  const RoutineModeAnyone({super.key, this.width, this.height});
  final double? width;
  final double? height;

  @override
  State<RoutineModeAnyone> createState() => _RoutineModeAnyoneState();
}

class _RoutineModeAnyoneState extends State<RoutineModeAnyone>
    with TrialAnyoneTimerMixin<RoutineModeAnyone> {
  // ====================================================================
  // 📦 [Box 3: 상태 변수 및 초기화]
  // ====================================================================
  String _deepgramKey = "";
  String _openAiKey = "";
  bool _isConversationActive = false;
  bool _isStartingListening = false;
  bool _isPipelineRunning = false;
  int _listenGeneration = 0;
  DateTime? _lastListenStartAt;
  double _fontScale = 1.0;
  bool _showOriginal = true;
  bool _showUsageGuide = false; // 🆕 [Anyone] 이용방법 말풍선 토글
  int _turnCounter = 0;
  String? _sessionDocId; // 🔧 [v3 추가] 첫 대화 후 세션 ID (클론 변경 시 null 리셋)
  DocumentReference? _myHistoryRef; // 🔧 [히스토리] chat_history 문서 참조 (Duo 패턴)
  bool _hasShownNudgeBubble = false; // 🆕 [즉시 안내 말풍선] 세션당 1회 노출 가드
  bool _showNudgeBubble = false; // 🆕 [즉시 안내 말풍선] 현재 표시 여부(페이드 애니메이션 트리거)

  // ── Idle Timeout v2 ───────────────────────────────────────────────
  // 기준: "유저도 AI도 아무 작동이 없는 상태"가 연속 60초 지속되면 pause.
  //  - AI 작동 = _ttsQueueManager.isBusy (TTS 재생/대기)
  //  - 유저 작동 = _voiceManager != null (마이크 연결/녹음)
  // 1초 주기 감시 타이머가 작동 여부를 보고 idle 누적초를 증감한다.
  Timer? _idlePauseTimer;
  bool _isIdlePaused = false;
  int _idleElapsedSec = 0;

  bool get _isSystemBusy {
    return _ttsQueueManager.isBusy;
  }

  void _resetIdleTimer() {
    _idleElapsedSec = 0;
    if (_isIdlePaused) {
      _isIdlePaused = false;
      if (mounted) setState(() {});
      if (!TrialFlowState.instance.isTrial) {
        BillingTicker.instance.resume();
        BillingTicker.instance.logMode('free_talk');
      }
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
    // 유저나 AI가 작동 중이면 idle 누적을 멈추고 리셋
    if (_isSystemBusy) {
      _idleElapsedSec = 0;
      return;
    }
    if (trialMode && isTrialTimeUp) {
      unawaited(_handleTrialEnd());
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
  // ──────────────────────────────────────────────────────────────────

  Widget _buildIdleBanner() => const SizedBox.shrink();

  Widget _buildIdleOverlay() => const SizedBox.shrink();
  // ─────────────────────────────────────────────────────────────────────────

  // 🔧 [v3.4 발화 합치기] 유저 더듬거림 대응
  // speech_final 받아도 바로 파이프라인 시작 안 하고 900ms 대기
  // 대기 중 새 발화 오면 합쳐서 처리 (최종 한 덩어리로)
  String _pendingTranscript = ''; // 대기 중인 유저 발화 누적
  Timer? _commitTimer; // "진짜 끝났는지" 확정 타이머
  static const int COMMIT_WAIT_MS = kFreeTalkCommitWaitMs; // 발화 합치기 대기 시간
  void _log(String tag, String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    final line = '[$ts] $tag $msg';
    print(line);
    AppLogLedger.instance.add('FREETALK', '$tag $msg');
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
      case 'dutch':
        return 'nl';
      default:
        return 'en'; // English 포함
    }
  }

  // 언어 수준 고정값 (초/중/고급 선택 UI 제거 — 내부 프롬프트 파이프라인용 Intermediate 고정)
  final String _freeTalkLevel = "Intermediate";

  // 대화 컨텍스트용 슬라이딩 히스토리 (파이프라인에서 사용 — 유지)
  List<Map<String, String>> _recentHistory = [];

  // 오디오 및 UI
  final List<Map<String, dynamic>> _localMessages = [];
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  DeepgramV2VoiceManager? _voiceManager;
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final TtsQueueManager _ttsQueueManager;
  HybridTtsPlayer? _hybridTtsPlayer; // [하이브리드] 메인 턴 TTS 플레이어

  // ⏱️ 성능 측정용 초시계
  final Stopwatch _swDeepgram = Stopwatch();
  final Stopwatch _swOpenAI = Stopwatch();
  final Stopwatch _swTTS = Stopwatch();
  String _debugResult = "⏱️ 대기 중";
  DateTime? _lastScrollThrottle;

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

    TrialFlowState.instance.restoreFromAppState();
    if (TrialFlowState.instance.isTrialAnyone) {
      trialMode = true;
      trialSeconds = 60;
      _myHistoryRef = TrialFlowState.instance.myHistoryRef;
      startTrialTimer();
    }

    _initPermissions();
    _fetchKeys();
    BillingTicker.instance.setRate(BillingRate.full);
    if (!TrialFlowState.instance.isTrial) {
      BillingTicker.instance.resume();
      BillingTicker.instance.logMode('free_talk');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resetIdleTimer();
    });
  }

  @override
  void dispose() {
    disposeTrialTimer();
    _clearIdleTimers();
    BillingTicker.instance.pause();
    _stopEverything();
    _voiceManager?.dispose();
    _audioRecorder.dispose();
    _ttsQueueManager.stop();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initPermissions() async {
    await [Permission.microphone].request();
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
        // 🆕 첫 로드 완료 후 세션 자동 시작 (StepExpand 패턴). race 제거.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startFreeTalkSession();
        });
      }
    } catch (e) {
      print('❌ Key Load Error: $e');
    }
  }

  /// 🆕 세션 자동 시작: 표시등 ON + 마이크 먼저(유저 먼저 말하게).
  /// 마이크 첫 청취가 시작되면 _isConversationActive=true 로 자동 점등.
  /// 마이크 연결 직후 안내 말풍선 1.5초 노출.
  Future<void> _startFreeTalkSession() async {
    if (_deepgramKey.isEmpty || !mounted) return;
    if (_isConversationActive) return; // 중복 시작 방지
    _hasShownNudgeBubble = false;
    _startDeepgramListening();
  }

  // ====================================================================

  void _saveRecentHistory(String userText, String aiText) {
    _recentHistory.add({'role': 'user', 'content': userText});
    _recentHistory.add({'role': 'assistant', 'content': aiText});
    while (_recentHistory.length > 4) _recentHistory.removeAt(0);
  }

  void _saveUserFullSentenceToCache(String text) {
    if (text.isEmpty) return;
    TtsCache.get(text, 'nova').then((existing) {
      if (existing != null) return;
      http
          .post(
        Uri.parse('https://api.openai.com/v1/audio/speech'),
        headers: {
          'Authorization': 'Bearer $_openAiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'tts-1',
          'input': text,
          'voice': 'nova',
          'speed': 1.0,
        }),
      )
          .then((res) {
        if (res.statusCode == 200) {
          TtsCache.put(text, 'nova', res.bodyBytes);
        }
      }).catchError((e) {
        debugPrint('[_saveUserFullSentenceToCache] $e');
      });
    });
  }

// ====================================================================
// 📦 [Box 5: Deepgram + Relay Pipeline] ← 통신로직 박스코드와 완전 일치
// ====================================================================
  // 최신 메시지(position 0 = 하단)로 스크롤
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  // 현재 AI 버블을 화면 중앙에 고정 (스트리밍 중 밀림 방지)
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

  void _scrollToBottomThrottled() {
    final now = DateTime.now();
    if (_lastScrollThrottle == null ||
        now.difference(_lastScrollThrottle!) >=
            const Duration(milliseconds: 250)) {
      _lastScrollThrottle = now;
      _scrollToBottom();
    }
  }

  // 현재 대사를 화면 맨 위에 고정 — Scrollable.ensureVisible 기반
  void _scrollToCurrentTop(int index) {
    _log('🧭 [SCROLL-TOP]', 'index=$index');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[index];
      if (key == null) return;
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.98, // reversed list에서 화면 상단
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  String _cleanText(String text) {
    return text
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _stopEverything() {
    _isConversationActive = false;
    _hasShownNudgeBubble = false;
    _showNudgeBubble = false;
    _isStartingListening = false;
    _isPipelineRunning = false;
    _listenGeneration++;
    _commitTimer?.cancel(); // 🔧 [v3.4] 대기 중 타이머 정리
    _commitTimer = null;
    _pendingTranscript = ''; // 대기 중 발화도 버림
    _voiceManager?.dispose();
    _voiceManager = null;
    _ttsQueueManager.stop();
    if (mounted) setState(() {});
  }

  // ====================================================================
  // 📦 [즉시 안내 말풍선] — 소리 대신 화면 텍스트로 2초간 표시 후 자동 소멸
  // ====================================================================
  void _showNudgeBubbleOnce() {
    if (_hasShownNudgeBubble || !mounted) return;
    _hasShownNudgeBubble = true;
    setState(() => _showNudgeBubble = true);
    Timer(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => _showNudgeBubble = false);
    });
  }

  void _removeLastExchange() {
    // 가장 최근 SYSTEM(AI) 버블 인덱스 탐색
    int lastSystemIdx = -1;
    for (int i = _localMessages.length - 1; i >= 0; i--) {
      if (_localMessages[i]['role'] == 'SYSTEM') {
        lastSystemIdx = i;
        break;
      }
    }
    if (lastSystemIdx < 0) return;

    // SYSTEM 바로 앞의 HOST(유저) 버블 인덱스 탐색
    int lastHostIdx = -1;
    for (int i = lastSystemIdx - 1; i >= 0; i--) {
      if (_localMessages[i]['role'] == 'HOST') {
        lastHostIdx = i;
        break;
      }
    }

    // 인덱스가 큰 것부터 제거 (인덱스 밀림 방지)
    _localMessages.removeAt(lastSystemIdx);
    if (lastHostIdx >= 0) _localMessages.removeAt(lastHostIdx);
  }

  Future<void> _startDeepgramListening() async {
    if (_isStartingListening) {
      _log('🎤 [LISTEN-SKIP]', 'already starting');
      return;
    }
    if (_isPipelineRunning) {
      _log('🎤 [LISTEN-SKIP]', 'pipeline running');
      return;
    }
    if (_ttsQueueManager.isBusy) {
      _log('🎤 [LISTEN-SKIP]', 'tts busy');
      return;
    }
    final now = DateTime.now();
    if (_lastListenStartAt != null &&
        now.difference(_lastListenStartAt!) < const Duration(seconds: 1)) {
      _log('🎤 [LISTEN-SKIP]', 'called again within 1s');
      return;
    }

    _isStartingListening = true;
    _lastListenStartAt = now;
    final int listenGeneration = ++_listenGeneration;
    _log('🎤 [LISTEN-GEN]', 'start generation=$listenGeneration');

    try {
      if (_deepgramKey.isEmpty || !(await _audioRecorder.hasPermission())) {
        return;
      }
      if (!mounted || listenGeneration != _listenGeneration) return;
      _resetIdleTimer();
      _isConversationActive = true;
      if (mounted) {
        setState(() {
          _debugResult = "⏱️ 듣는 중...";
          _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
        });
        // HOST_TEMP 버블은 스크롤 트리거 없음 — 실제 HOST 버블 등장 시 스크롤
      }

      _log('🎤 [LISTEN-01]', '_startDeepgramListening 진입, VoiceManager 생성');
      if (_voiceManager != null) {
        await _voiceManager?.dispose();
        _voiceManager = null;
      }

      // 🌐 [v3.1] 로비에서 유저가 선택한 모국어(nativeLang)로 Deepgram 인식
      // 유저가 한국어로 말하면 Deepgram이 한국어로 인식 → Brain이 영어로 번역
      final String nativeLang = FFAppState().nativeLang.isNotEmpty
          ? FFAppState().nativeLang
          : 'Korean';
      final String dgLangCode = _mapLanguageToCode(nativeLang);
      _log('🌐 [LANG]',
          'nativeLang="$nativeLang" → Deepgram code="$dgLangCode"');

      bool isCurrentGeneration() =>
          mounted && listenGeneration == _listenGeneration;

      _voiceManager = DeepgramV2VoiceManager(
        apiKey: _deepgramKey,
        audioRecorder: _audioRecorder,
        langCode: dgLangCode,
        onLog: _log, // 🔬 로그 훅 주입
        shouldReconnect: () =>
            isCurrentGeneration() &&
            _isConversationActive &&
            !_isPipelineRunning &&
            !_ttsQueueManager.isBusy,
        onConnected: () {
          if (!isCurrentGeneration()) {
            _log('🎤 [LISTEN-STALE]', 'onConnected ignored');
            return;
          }
          _log('✅ [LISTEN-02]', 'onConnected 콜백 실행');
        },
        onTranscriptUpdate: (transcript) {
          if (!TrialFlowState.instance.isTrial) {
            BillingTicker.instance.resumeFromActivity('free_talk_stt_partial');
          }
          if (!isCurrentGeneration()) {
            _log('🎤 [LISTEN-STALE]', 'onTranscriptUpdate ignored');
            return;
          }
          _swDeepgram.reset();
          _swDeepgram.start();
        },
        onTurnEnded: (transcript) {
          if (!TrialFlowState.instance.isTrial) {
            BillingTicker.instance.resumeFromActivity('free_talk_stt_result');
          }
          if (!isCurrentGeneration()) {
            _log('🎤 [LISTEN-STALE]', 'onTurnEnded ignored');
            return;
          }
          _log('🔀 [LISTEN-03]', 'onTurnEnded 콜백 수신: "$transcript"');
          _swDeepgram.stop();
          _stopMicAndProcess(transcript);
        },
        onError: (err) {
          if (!isCurrentGeneration()) {
            _log('🎤 [LISTEN-STALE]', 'onError ignored');
            return;
          }
          _log('❌ [LISTEN-ERR]', 'Deepgram Error: $err');
          _stopEverything();
        },
        onReconnecting: (attempt) {
          if (!isCurrentGeneration()) {
            _log('🎤 [LISTEN-STALE]', 'onReconnecting ignored');
            return;
          }
          _log('🎤 [LISTEN-RETRY]', 'Deepgram 재연결 시도 $attempt');
        },
        onGaveUp: () {
          if (!isCurrentGeneration()) {
            _log('🎤 [LISTEN-STALE]', 'onGaveUp ignored');
            return;
          }
          _log('❌ [LISTEN-GIVEUP]', 'Deepgram 재연결 포기');
        },
      );
      _log('🎤 [LISTEN-04]', 'connectAndStart 호출 직전');
      await _voiceManager!.connectAndStart();
      if (!TrialFlowState.instance.isTrial) {
        BillingTicker.instance.resumeFromActivity('free_talk_mic_start');
      }
      _log('🎤 [LISTEN-05]', 'connectAndStart 완료');

      // 🆕 [즉시 안내 말풍선] 첫 턴이면 마이크 연결 직후 바로 표시 (텍스트라 겹침 걱정 없음)
      if (_localMessages.isEmpty && !_hasShownNudgeBubble) {
        _showNudgeBubbleOnce();
      }
    } finally {
      if (listenGeneration == _listenGeneration) {
        _isStartingListening = false;
      }
    }
  }

  // 🔧 [v3.4] Deepgram speech_final 수신 시 호출됨
  // 1.2초 대기창 안에서 추가 발화 합치기 → 완전히 끝나면 파이프라인 시작
  void _stopMicAndProcess(String transcript) async {
    _resetIdleTimer();
    final clean = transcript.trim();
    _log('🔀 [STOP-01]', 'speech_final 수신: "$clean" (len=${clean.length})');

    if (clean.length < 2) {
      _log('🔀 [STOP-02]', '너무 짧음 → 무시');
      return;
    }

    // 🔧 기존 대기 중인 발화가 있으면 공백으로 연결 (더듬거림 합치기)
    if (_pendingTranscript.isEmpty) {
      _pendingTranscript = clean;
      _log('🔀 [STOP-03]', '신규 발화 접수. 900ms 대기창 시작');
    } else {
      _pendingTranscript = '$_pendingTranscript $clean';
      _log('🔀 [STOP-04]', '합치기: "$_pendingTranscript" (900ms 대기창 리셋)');
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

    // 900ms 후 파이프라인 시작 예약
    _commitTimer = Timer(
      const Duration(milliseconds: COMMIT_WAIT_MS),
      () => _commitAndProcess(),
    );
  }

  // 🔧 [v3.4] 900ms 대기 후 더 이상 발화 없으면 확정 → 파이프라인 시작
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
  String _retryPhrase(String lang) {
    switch (lang.toLowerCase()) {
      case 'japanese':
        return 'もう一度お願いします。';
      case 'chinese':
        return '请再说一遍。';
      case 'french':
        return 'Pardon?';
      case 'spanish':
        return '¿Perdón?';
      case 'german':
        return 'Wie bitte?';
      default:
        return 'Pardon?';
    }
  }

  Future<void> _speakRetryAndListen() async {
    if (!mounted || !_isConversationActive) return;
    final lang = FFAppState().targetLang.isNotEmpty
        ? FFAppState().targetLang
        : 'English';
    _ttsQueueManager.stop();
    _ttsQueueManager.setUserTurn(false);
    _ttsQueueManager.setAiPaused(false);
    final fetcher = ChunkedTtsFetcher(
      _openAiKey,
      _ttsQueueManager,
      "nova",
      isUser: false,
      onLog: _log,
    );
    fetcher.addText(_retryPhrase(lang));
    while (
        (fetcher.pendingRequests > 0 || _ttsQueueManager.isBusy) && mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (mounted && _isConversationActive) _startDeepgramListening();
  }

  Future<void> _processRelayPipeline(String finalTranscript,
      {bool isCorrectionRetry = false}) async {
    _resetIdleTimer();
    _turnCounter++;
    final int currentTurnId = _turnCounter;
    bool skipFinallyRestart = false;
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
    // [GHOST-EXACT] Change ghost-word detection from substring contains to exact match.
    //   Before: short ghost words could evaporate normal phrases that merely included them.
    //   Now: evaporate only when the entire cleaned transcript is itself a ghost word.
    //   Mixed phrases pass through and are handled later by the [EVAPORATE] rules if needed.
    bool isGhost =
        finalTranscript.length <= 2 || ghostWords.contains(lowerClean.trim());

    if (isGhost) {
      if (mounted)
        setState(
            () => _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP'));
      if (_isConversationActive) {
        // 너무 짧아서 인식 실패 → 다시 말해 달라 요청
        if (finalTranscript.length <= 2) {
          _speakRetryAndListen();
        } else {
          _startDeepgramListening();
        }
      }
      return;
    }

    _isPipelineRunning = true;
    try {
      // ─────────────────────────────────────────────────────
      // STEP 2: HOST 풍선 생성 + 유저 번역 스트리밍
      // ─────────────────────────────────────────────────────
      if (mounted) {
        setState(() {
          _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
          _localMessages.add({'role': 'HOST', 'target': '', 'original': ''});
        });
      }

      int hostIndex = _localMessages.length - 1;
      // HOST 말풍선은 상단 고정 — 사용자 발화가 화면 안에 안정적으로 보이도록
      _scrollToCurrentTop(hostIndex);

      // 컨텍스트 구성: 장기 기억(recent_history) 우선, 없으면 localMessages fallback
      String contextStr;
      if (_recentHistory.isNotEmpty) {
        contextStr = _recentHistory
            .map((m) =>
                '${m['role'] == 'user' ? 'User' : 'AI'}: ${m['content']}')
            .join('\n');
      } else {
        var validMsgs = _localMessages.where((m) {
          if (m['role'] != 'HOST' && m['role'] != 'SYSTEM') return false;
          final target = (m['target'] ?? '').toString().trim();
          return target.isNotEmpty && target != '...';
        }).toList();
        if (validMsgs.length > 10)
          validMsgs = validMsgs.sublist(validMsgs.length - 10);
        contextStr = validMsgs
            .map(
                (m) => "${m['role'] == 'HOST' ? 'User' : 'AI'}: ${m['target']}")
            .join("\n");
      }

      // 🧩 [A] 클론 응답용 구조화 히스토리(오프너 포함, 역할별 교대 턴).
      //   소스는 화면 메시지(_localMessages): HOST→user, SYSTEM(클론 발화)→assistant.
      //   빈 target / '...' / HOST_TEMP 는 제외. 현재 입력(빈 HOST 버블)은 자동 제외되고,
      List<Map<String, dynamic>> cloneHistory = _localMessages
          .where((m) {
            final role = (m['role'] ?? '').toString();
            if (role != 'HOST' && role != 'SYSTEM') return false;
            final t = (m['target'] ?? '').toString().trim();
            return t.isNotEmpty && t != '...';
          })
          .map<Map<String, dynamic>>((m) => <String, dynamic>{
                'role': (m['role'] == 'HOST') ? 'user' : 'assistant',
                'content': (m['target'] ?? '').toString().trim(),
              })
          .toList();
      // 화면 메시지가 비어 있으면(예: 세션 복원 직후) 장기기억으로 폴백
      if (cloneHistory.isEmpty && _recentHistory.isNotEmpty) {
        cloneHistory = _recentHistory
            .map<Map<String, dynamic>>((m) => <String, dynamic>{
                  'role': (m['role'] == 'assistant') ? 'assistant' : 'user',
                  'content': (m['content'] ?? '').toString().trim(),
                })
            .where((m) => (m['content'] as String).isNotEmpty)
            .toList();
      }

      String userTargetText = "";
      // 🆕 유저 목소리 = 로비에서 고른 값(FFAppState().aiVoice). AI는 nova 고정.
      final String userVoice =
          FFAppState().aiVoice.isNotEmpty ? FFAppState().aiVoice : 'echo';
      ChunkedTtsFetcher userTtsFetcher = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        userVoice,
        onLog: _log,
      );
      _ttsQueueManager.setUserTurn(true);
      _ttsQueueManager.setAiPaused(false); // 유저 청크는 즉시 재생

      // 다국어 구두점 단위 쪼개기
      final RegExp splitPattern = RegExp(r'[,\.?!;:。、！？…，；：\n]');

      // 🌐 [v3.1] 로비에서 유저가 선택한 타겟 언어로 번역
      final String targetLangName = FFAppState().targetLang.isNotEmpty
          ? FFAppState().targetLang
          : 'English';

      final userStream = FreeTalkBrain.streamUserTranslation(
        apiKey: _openAiKey,
        textOriginal: finalTranscript,
        targetLang: targetLangName,
        contextStr: contextStr,
        disableCorrection: isCorrectionRetry,
      );

      bool evaporated = false;
      bool corrected = false; // 유저가 AI의 오해를 정정 → 직전 교환 삭제 후 재처리
      bool misheard = false; // 잘못 들었다는 불만만 있음 → 직전 교환 삭제 후 재청취
      bool dissatisfiedReply = false; // AI 직전 응답 불만 → 응답만 재생성
      // [USER-FULL-TTS] firstChunkSent removed; user TTS fires once after stream end.
      await for (String chunk in userStream) {
        userTargetText += chunk;

        // 🔧 [v3.3] 누적된 전체 텍스트에서 EVAPORATE 감지 (스트림 조각 분할 대응)
        if (userTargetText.contains("[EVAPORATE]")) {
          evaporated = true;
          _log('⚠️ [EVAPORATE]', '증발 감지 → 턴 취소');
          break;
        }
        // 🔄 [CORRECTION] 정정 감지 (재진입 시 무시)
        if (!isCorrectionRetry && userTargetText.contains("[CORRECTION]")) {
          corrected = true;
          _log('🔄 [CORRECTION]', '정정 감지 → 직전 교환 삭제 후 재시작');
          break;
        }
        // 👂 [MISHEARD] 잘못 들었다는 불만만 있음
        if (!isCorrectionRetry && userTargetText.contains("[MISHEARD]")) {
          misheard = true;
          _log('👂 [MISHEARD]', '오청취 불만 감지 → 직전 교환 삭제 후 재청취');
          break;
        }
        // 🟣 [DISSATISFIED] AI 직전 응답에 대한 불만 → 다른 응답 재생성
        if (userTargetText.contains("[DISSATISFIED]")) {
          dissatisfiedReply = true;
          _log('🟣 [DISSATISFIED]', '응답 불만 감지 → 직전 응답 삭제 후 재생성');
          break;
        }
        if (mounted)
          setState(() => _localMessages[hostIndex]['target'] = userTargetText);

        // [USER-FULL-TTS] no chunk TTS during user translation streaming.
        // Text still streams to the screen through setState above.
      }

      if (evaporated) {
        if (mounted)
          setState(
              () => _localMessages.removeWhere((m) => m['role'] == 'HOST'));
        if (_isConversationActive && _turnCounter == currentTurnId) {
          skipFinallyRestart = true;
          _isPipelineRunning = false;
          await _speakRetryAndListen();
        }
        return;
      }

      // 🔄 [CORRECTION] 유저가 AI의 오해/오청취를 정정 → 직전 교환 삭제 후 재처리
      if (corrected) {
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length &&
                _localMessages[hostIndex]['role'] == 'HOST') {
              _localMessages.removeAt(hostIndex); // 방금 만든 현재 HOST 버블 제거
            }
            _removeLastExchange(); // 직전 HOST(오해 발화)+SYSTEM(틀린 응답) 제거
          });
          _scrollToBottom();
        }
        // 🔑 장기기억에서도 직전 교환 제거 — 안 하면 재처리 시 오해가 contextStr로 재주입됨
        if (_recentHistory.length >= 2) {
          _recentHistory.removeRange(
              _recentHistory.length - 2, _recentHistory.length);
        }
        _ttsQueueManager.stop();
        _ttsQueueManager.setUserTurn(false);
        // 정정된 발화로 재처리 (재진입이므로 [CORRECTION] 재감지 안 함)
        skipFinallyRestart = true;
        _isPipelineRunning = false;
        unawaited(
            _processRelayPipeline(finalTranscript, isCorrectionRetry: true));
        return;
      }

      // 👂 [MISHEARD] 잘못 들었다는 불만만 말한 경우 → 직전 교환 삭제 후 재청취
      if (misheard) {
        _turnCounter--;
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length &&
                _localMessages[hostIndex]['role'] == 'HOST') {
              _localMessages.removeAt(hostIndex);
            }
            _removeLastExchange();
          });
          if (_localMessages.isNotEmpty) _scrollToBottom();
        }
        if (_recentHistory.length >= 2) {
          _recentHistory.removeRange(
              _recentHistory.length - 2, _recentHistory.length);
        }
        _ttsQueueManager.stop();
        _ttsQueueManager.setUserTurn(false);
        _ttsQueueManager.setAiPaused(false);
        final misheardTts = ChunkedTtsFetcher(
          _openAiKey,
          _ttsQueueManager,
          'nova',
          isUser: false,
          onLog: _log,
        );
        misheardTts.addText("아 제가 잘못 들었어요. 다시 한 번 말해주세요.");
        int misheardTicks = 0;
        while ((misheardTts.pendingRequests > 0 || _ttsQueueManager.isBusy) &&
            mounted) {
          await Future.delayed(const Duration(milliseconds: 50));
          if (++misheardTicks > 200) break;
        }
        skipFinallyRestart = true;
        _isPipelineRunning = false;
        if (mounted && _isConversationActive) _startDeepgramListening();
        return;
      }

      // 🟣 [DISSATISFIED] AI 직전 응답 불만 → 직전 SYSTEM만 제거하고 같은 유저 발화로 재생성
      if (dissatisfiedReply) {
        _turnCounter--;
        String rejectedReply = '';
        String lastUserTarget = '';
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length &&
                _localMessages[hostIndex]['role'] == 'HOST') {
              _localMessages.removeAt(hostIndex);
            }
            final lastSysIdx =
                _localMessages.lastIndexWhere((m) => m['role'] == 'SYSTEM');
            if (lastSysIdx != -1) {
              rejectedReply =
                  (_localMessages[lastSysIdx]['target'] ?? '').toString();
              _localMessages.removeAt(lastSysIdx);
            }
            final lastHostIdx =
                _localMessages.lastIndexWhere((m) => m['role'] == 'HOST');
            if (lastHostIdx != -1) {
              lastUserTarget =
                  (_localMessages[lastHostIdx]['target'] ?? '').toString();
            }
          });
          if (_localMessages.isNotEmpty) _scrollToBottom();
        }
        if (lastUserTarget.trim().isEmpty) {
          _ttsQueueManager.stop();
          skipFinallyRestart = true;
          _isPipelineRunning = false;
          await _speakRetryAndListen();
          return;
        }
        if (_recentHistory.isNotEmpty &&
            _recentHistory.last['role'] == 'assistant') {
          _recentHistory.removeLast();
        }
        _ttsQueueManager.stop();
        _ttsQueueManager.setUserTurn(false);
        _ttsQueueManager.setAiPaused(false);
        final regenPhraseTts = ChunkedTtsFetcher(
          _openAiKey,
          _ttsQueueManager,
          'nova',
          isUser: false,
          onLog: _log,
        );
        regenPhraseTts.addText("그럼 다시 답해 볼게요.");
        var regenMsgs = _localMessages.where((m) {
          if (m['role'] != 'HOST' && m['role'] != 'SYSTEM') return false;
          final target = (m['target'] ?? '').toString().trim();
          return target.isNotEmpty && target != '...';
        }).toList();
        if (regenMsgs.length > 10)
          regenMsgs = regenMsgs.sublist(regenMsgs.length - 10);
        final String regenContextStr = regenMsgs
            .map(
                (m) => "${m['role'] == 'HOST' ? 'User' : 'AI'}: ${m['target']}")
            .join("\n");
        if (mounted) {
          setState(() => _localMessages
              .add({'role': 'SYSTEM', 'target': '', 'original': ''}));
          _scrollToBottom();
        }
        final int regenAiIndex = _localMessages.length - 1;
        final regenTts = ChunkedTtsFetcher(
          _openAiKey,
          _ttsQueueManager,
          'nova',
          isUser: false,
          onLog: _log,
        );
        String regenText = "";
        final regenStream = FreeTalkBrain.streamFreeTalkResponse(
          apiKey: _openAiKey,
          userTargetText: lastUserTarget,
          contextStr: regenContextStr,
          myTarget: targetLangName,
          level: _freeTalkLevel,
          rejectedReply: rejectedReply,
        );
        await for (final chunk in regenStream) {
          regenText += chunk;
          if (mounted && regenAiIndex < _localMessages.length) {
            setState(() => _localMessages[regenAiIndex]['target'] = regenText);
          }
        }
        final String regenClean = _cleanText(regenText.trim());
        if (regenClean.isEmpty) {
          if (mounted && regenAiIndex < _localMessages.length) {
            setState(() => _localMessages.removeAt(regenAiIndex));
          }
          skipFinallyRestart = true;
          _isPipelineRunning = false;
          await _speakRetryAndListen();
          return;
        }
        regenTts.addText(regenClean);
        FreeTalkBrain.generateCleanOriginal(
                apiKey: _openAiKey, englishText: regenText)
            .then((cleanKorean) {
          if (mounted && _localMessages.length > regenAiIndex) {
            setState(
                () => _localMessages[regenAiIndex]['original'] = cleanKorean);
          }
        });
        _recentHistory.add({'role': 'assistant', 'content': regenText});
        while (_recentHistory.length > 4) _recentHistory.removeAt(0);
        int regenTicks = 0;
        while ((regenPhraseTts.pendingRequests > 0 ||
                regenTts.pendingRequests > 0 ||
                _ttsQueueManager.isBusy) &&
            mounted) {
          await Future.delayed(const Duration(milliseconds: 50));
          if (++regenTicks > 400) break;
        }
        skipFinallyRestart = true;
        _isPipelineRunning = false;
        if (mounted && _isConversationActive) _startDeepgramListening();
        return;
      }

      // 🛡️ [CORRECTION-GUARD] 태그가 번역 결과로 화면/TTS에 남는 것 차단
      //   - 재진입 경로에서 모델이 태그를 내면 제거하고,
      //   - 남는 내용이 없으면 EVAPORATE와 동일하게 처리 (버블 제거 + 재청취)
      if (userTargetText.contains('[CORRECTION]')) {
        userTargetText = userTargetText.replaceAll('[CORRECTION]', '').trim();
        if (mounted && hostIndex < _localMessages.length) {
          setState(() => _localMessages[hostIndex]['target'] = userTargetText);
        }
        if (userTargetText.isEmpty) {
          if (mounted) {
            setState(() {
              _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
              if (hostIndex < _localMessages.length &&
                  _localMessages[hostIndex]['role'] == 'HOST') {
                _localMessages.removeAt(hostIndex);
              }
            });
          }
          if (_isConversationActive && _turnCounter == currentTurnId) {
            skipFinallyRestart = true;
            _isPipelineRunning = false;
            await _speakRetryAndListen();
          }
          return;
        }
      }

      // [USER-FULL-TTS] fire the complete translated user sentence once.
      final String fullUserTts = _cleanText(userTargetText.trim());
      if (fullUserTts.isNotEmpty) {
        userTtsFetcher.addText(fullUserTts);
      }

      // 🔧 [v3.7] 유저 통문장 TtsCache 백그라운드 저장 (히스토리 HIT 유도)
      //   - 청크별 캐시만으로는 히스토리에서 통문장 GET이 MISS됨
      //   - fire-and-forget: 유저 재생 흐름과 무관하게 백그라운드 처리
      //   - voice/speed는 히스토리 _playRhythmAudio와 동일하게 "nova", 1.0 고정
      _saveUserFullSentenceToCache(userTargetText.trim());

      // 유저 original 생성 (백그라운드)
      FreeTalkBrain.generateCleanOriginal(
              apiKey: _openAiKey, englishText: userTargetText)
          .then((cleanKorean) {
        if (mounted && _localMessages.length > hostIndex) {
          setState(() => _localMessages[hostIndex]['original'] = cleanKorean);
        }
      });

      // ─────────────────────────────────────────────────────
      // STEP 3 & 4 (병렬): AI 응답 백그라운드 생성
      //   → AI 청크는 큐에 쌓이지만 _aiPaused=true라 재생 대기
      //   → 유저 TTS는 계속 재생 중
      // ─────────────────────────────────────────────────────
      if (mounted) {
        setState(() => _localMessages
            .add({'role': 'SYSTEM', 'target': '', 'original': ''}));
        _scrollToCurrent(_localMessages.length - 1);
      }
      int aiIndex = _localMessages.length - 1;

      // 🔧 [v3.2 버그 수정] setUserTurn(false)는 유저 재생 완료 후로 이동
      // 현재 시점에서 유저 TTS가 아직 재생 중인데 _isUserTurn=false로 바꾸면
      // TtsQueueManager._processQueue가 'AI 턴이고 paused' 판단하여 유저 마지막 청크까지 멈춰버림
      _ttsQueueManager.setAiPaused(true); // AI 재생 대기 모드 (유저 TTS는 계속 재생)
      // 🔧 [v3.5] AI 전용 큐로 보내기 위해 isUser: false 명시
      ChunkedTtsFetcher aiTtsFetcher = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        "nova",
        isUser: false, // AI 큐로 분리
        onLog: _log,
      );
      // [하이브리드 전환] 턴 시작 시 리셋 + 새 인스턴스 생성
      _hybridTtsPlayer?.reset();
      _hybridTtsPlayer = HybridTtsPlayer(
        _openAiKey,
        _ttsQueueManager,
        aiTtsFetcher,
        "nova",
        onLog: _log,
      );

      String latestContextStr = contextStr.isEmpty
          ? "User: $userTargetText"
          : "$contextStr\nUser: $userTargetText";
      String aiTargetText = "";
      // String aiBuffer = ""; // [하이브리드 전환] HybridTtsPlayer 내부에서 처리 (삭제 금지)
      bool firstChunkSentToTTS = false;

      _swOpenAI.reset();
      _swOpenAI.start();
      _swTTS.reset();

      _log('🧠 [PIPE-02]', 'AI 스트림 요청: userText="$userTargetText"');

      final aiStream = FreeTalkBrain.streamFreeTalkResponse(
        apiKey: _openAiKey,
        userTargetText: userTargetText,
        contextStr: latestContextStr,
        myTarget: targetLangName,
        level: _freeTalkLevel,
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
          aiTargetText += chunk;
          // aiBuffer += chunk; // [하이브리드 전환] HybridTtsPlayer 내부에서 처리 (롤백 가능)
          // 🔧 [요청1] AI 영어 텍스트는 유저 TTS 재생 완료 후에만 표시.
          // 유저가 말하는 중에는 AI 글자가 먼저 노출되지 않게 막는다.
          if (mounted && !_ttsQueueManager.aiPaused) {
            setState(() => _localMessages[aiIndex]['target'] = aiTargetText);
            // 스크롤은 AI 차례(!aiPaused)에만 수행해 유저가 자기 버블을 보는 중
            // AI 버블로 화면이 이동하는 것을 방지.
            if (!_ttsQueueManager.aiPaused) {
              final _scrollNow = DateTime.now();
              if (_lastScrollThrottle == null ||
                  _scrollNow.difference(_lastScrollThrottle!) >=
                      const Duration(milliseconds: 250)) {
                _lastScrollThrottle = _scrollNow;
                _scrollToCurrent(aiIndex);
              }
            }
          }

          // [하이브리드 전환] HybridTtsPlayer.onChunk로 대체 (롤백 가능)
          _hybridTtsPlayer!.onChunk(chunk);
          if (!firstChunkSentToTTS && _hybridTtsPlayer!.firstChunkFired) {
            _swTTS.start();
            firstChunkSentToTTS = true;
          }

          /* [하이브리드 전환] HybridTtsPlayer.onChunk로 대체 (롤백 가능)
          final matches = splitPattern.allMatches(aiBuffer).toList();
          if (matches.isNotEmpty) {
            int lastIdx = matches.last.end;
            String toSpeak = aiBuffer.substring(0, lastIdx).trim();
            aiBuffer = aiBuffer.substring(lastIdx);
            if (toSpeak.isNotEmpty) {
              if (!firstChunkSentToTTS) {
                _swTTS.start();
                firstChunkSentToTTS = true;
              }
              aiTtsFetcher.addText(toSpeak);
            }
          }
          */
        }
        /* [하이브리드 전환] HybridTtsPlayer.onStreamEnd로 대체 (롤백 가능)
        if (aiBuffer.trim().isNotEmpty) {
          if (!firstChunkSentToTTS) {
            _swTTS.start();
            firstChunkSentToTTS = true;
          }
          aiTtsFetcher.addText(aiBuffer.trim());
        }
        */
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
        if (waitTicks * 50 >= kFreeTalkUserTtsFetchTimeoutMs) {
          userTtsFetcher.cancel(dropBuffered: false);
          _log('⚠️ [PIPE-TIMEOUT]', '유저 TTS fetch 15초 초과, 강제 진행');
          break;
        }
      }
      _log(
          '🧠 [PIPE-05]', '유저 TTS fetch 완료. isBusy=${_ttsQueueManager.isBusy}');

      // 🔒 [Box 7 USER-DRAIN-SIGNAL] 실제 기반 drain 게이트.
      //   마지막 유저 청크의 마지막 샘플 재생 완료 즉시 해제한다.
      //   isBusy 폴링과 청크 사이 false 위험을 제거한다.
      _ttsQueueManager.sealUserStream();
      await _ttsQueueManager.waitUserDrained();
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
      // [v3.6] PIPE-07 시점: 버퍼된 AI 텍스트 일괄 표시 — 중앙 고정으로 안정적 표시
      if (mounted && aiTargetText.isNotEmpty) {
        setState(() => _localMessages[aiIndex]['target'] = aiTargetText);
        _scrollToCurrent(aiIndex);
      }

      await aiGenerationTask;
      _log('🧠 [PIPE-08]',
          'aiGenerationTask 완료. AI pending=${aiTtsFetcher.pendingRequests}');
      Future<String>? aiOriginalFuture;
      if (aiTargetText.trim().isNotEmpty) {
        aiOriginalFuture = FreeTalkBrain.generateCleanOriginal(
            apiKey: _openAiKey, englishText: aiTargetText);
      }
      // [하이브리드] remainder 발사 + 통문장 TtsCache 저장
      await _hybridTtsPlayer!
          .onStreamEnd(fullSentence: _cleanText(aiTargetText.trim()));

      waitTicks = 0;
      while (aiTtsFetcher.pendingRequests > 0 || _ttsQueueManager.isBusy) {
        await Future.delayed(const Duration(milliseconds: 50));
        waitTicks++;
        if (waitTicks * 50 >= kFreeTalkAiTtsWaitTimeoutMs) {
          _log('⚠️ [PIPE-TIMEOUT]', 'AI TTS 20초 초과, 강제 진행');
          break;
        }
      }
      _log('🧠 [PIPE-09]', 'AI TTS 재생 완료');

      // ─────────────────────────────────────────────────────
      // STEP 7: Firestore 저장
      // ─────────────────────────────────────────────────────
      // AI original 생성 — aiTargetText 확정 후, 저장 전에 생성 (bilingual 저장 보장)
      String aiOriginalText = '';
      if (aiTargetText.trim().isNotEmpty) {
        try {
          aiOriginalText = await (aiOriginalFuture ??
              FreeTalkBrain.generateCleanOriginal(
                  apiKey: _openAiKey, englishText: aiTargetText));
          _log('🔤 [AI-ORIG]', 'AI original 생성 완료 → UI 반영 및 저장');
          if (mounted && _localMessages.length > aiIndex) {
            setState(
                () => _localMessages[aiIndex]['original'] = aiOriginalText);
          }
        } catch (e) {
          _log('❌ [AI-ORIG-ERR]', 'AI original 생성 실패: $e');
        }
      }

      // 유저 original — 백그라운드 생성이 완료된 값 사용, 비어 있으면 Deepgram 원문 fallback
      final String hostOriginal = (_localMessages[hostIndex]['original'] ?? '')
              .toString()
              .trim()
              .isNotEmpty
          ? (_localMessages[hostIndex]['original'] ?? '').toString()
          : finalTranscript;

      final hostLine = {
        'role': 'HOST',
        'original_text': hostOriginal,
        'translated_text': userTargetText,
      };
      final systemLine = {
        'role': 'SYSTEM',
        'original_text': aiOriginalText,
        'translated_text': aiTargetText,
      };
      _saveTurnToFirestore([hostLine, systemLine]);
      _saveHistoryMessages([hostLine, systemLine]); // 🔧 [히스토리] 병행 저장
      _saveRecentHistory(
          userTargetText, aiTargetText); // 🧠 [장기 기억] 백그라운드 메모리 업데이트
      _log('🧠 [PIPE-10]', 'Firestore 저장 호출 완료');
    } catch (e) {
      _log('❌ [PIPE-ERR]', 'Relay Error: $e');
    } finally {
      if (!skipFinallyRestart) {
        _isPipelineRunning = false;
      }
      _log('🧠 [PIPE-END]',
          'finally 진입. active=$_isConversationActive turn=$_turnCounter/current=$currentTurnId mounted=$mounted skipRestart=$skipFinallyRestart');
      if (skipFinallyRestart) {
        _log('⚠️ [PIPE-NORESTART]', 'handoff flow already restarted mic');
      } else if (mounted &&
          _isConversationActive &&
          _turnCounter == currentTurnId) {
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
          'mode': 'free_talk',
          'user_label': 'the user',
          'partner_label': 'AI partner',
          'created_at': FieldValue.serverTimestamp(),
          'transcript': chatLines,
        });
        _sessionDocId = newSession.id;
        _log('💾 [SAVE-05]', '새 세션 생성 완료. docId=$_sessionDocId');

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
        'room_name': "Anyone",
        'mode': 'free_talk',
        'user_label': 'the user',
        'partner_label': 'AI partner',
        'expand_partner_type': 'free_talk',
        'is_pinned': false,
        'msg_count': 0
      });
      _log('📚 [HIST-NEW]', 'chat_history 방 생성: ${_myHistoryRef!.id}');
    }
  }

  /// 턴마다 chat_history/messages 서브컬렉션에 기록 병행 저장
  Future<void> _saveHistoryMessages(
      List<Map<String, dynamic>> chatLines) async {
    try {
      await _ensureHistoryRef();
      if (_myHistoryRef == null) return;

      // messages 서브컬렉션에 각 발화 저장
      for (final line in chatLines) {
        final translated = (line['translated_text'] ?? '').toString().trim();
        if (translated.isEmpty) continue;
        await _myHistoryRef!.collection('messages').add({
          'role': line['role'] ?? '',
          'translated_text': translated,
          'original_text': (FFAppState().nativeLang.isNotEmpty &&
                  FFAppState().nativeLang == FFAppState().targetLang)
              ? ''
              : (line['original_text'] ?? '').toString(),
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      // 🔧 [핵심] 턴마다 msg_count/last_message 업데이트
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
  Future<void> _handleTrialEnd() async {
    if (!trialMode) return;
    trialMode = false;
    disposeTrialTimer();
    BillingTicker.instance.pause();

    final historyRef = _myHistoryRef ?? TrialFlowState.instance.myHistoryRef;
    if (historyRef == null) {
      TrialFlowState.instance.reset();
      if (mounted) context.pushReplacementNamed('Store');
      return;
    }

    TrialFlowState.instance.myHistoryRef = historyRef;
    TrialFlowState.instance.advanceTo(2);

    try {
      await historyRef.update({
        'status': 'completed',
        'last_active': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    if (!mounted) return;
    await LearningPrepOverlay.show(
      context,
      historyRef: historyRef,
      onReady: (ref) {
        TrialFlowState.instance.myHistoryRef = ref;
        TrialFlowState.instance.advanceTo(3);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => TrialStudyPage(historyRef: ref)),
        );
      },
    );
  }

  Future<void> _handleAutoSaveAndExit() async {
    BillingTicker.instance.pause();
    try {
      if (_myHistoryRef != null) {
        final hasUserTurn = _localMessages.any((m) => m['role'] == 'HOST');
        if (!hasUserTurn) {
          await _myHistoryRef!.delete();
          _log('🗑️ [HIST-DEL]', '빈 방 삭제 완료');
        } else {
          String lastText = "대화 기록 저장";
          for (int i = _localMessages.length - 1; i >= 0; i--) {
            final t = (_localMessages[i]['target'] ?? '').toString().trim();
            if (t.isNotEmpty && t != '...') {
              lastText = t;
              break;
            }
          }

          // 🆕 프리톡은 확장 문장 생성 안 함 → 대화 기록만 저장
          await _myHistoryRef!.update({
            'last_message': lastText,
            'last_message_time': FieldValue.serverTimestamp(),
            'msg_count': _localMessages.length,
            'last_active': FieldValue.serverTimestamp(),
            'mode': 'free_talk',
            'user_label': 'the user',
            'partner_label': 'AI partner',
          });
          _log('💾 [HIST-UPD]', 'last_message 저장 (free_talk, no expand)');
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
          const SizedBox(height: 10),
          Expanded(
            child: Stack(children: [
              _buildChatList(),
              _buildIdleOverlay(),
              if (trialMode) buildTrialCountdown(),
              if (_showUsageGuide) _buildUsageGuide(), // 🆕 [Anyone] 이용방법 말풍선
              _buildNudgeBubble(), // 🆕 [즉시 안내 말풍선] 마이크 켜지면 2초 노출 후 소멸
            ]),
          ),
          _buildControlArea(bottomPad),
        ]),
      ),
    );
  }

  // 🆕 [즉시 안내 말풍선] 마이크 켜지는 즉시 표시, 2초 후 자동 페이드아웃
  // 텍스트라서 마이크/재생과 충돌 없음 → 타이밍 로직(대기/취소) 불필요.
  Widget _buildNudgeBubble() {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.center,
        child: AnimatedOpacity(
          opacity: _showNudgeBubble ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 36),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E22).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF7F77DD).withValues(alpha: 0.55),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2DD4BF).withValues(alpha: 0.25),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Text(
              '여기, 그 사람이 있어요. 편하게 말 걸어보세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 🆕 [Anyone] 이용방법 말풍선 (배경/말풍선 어디든 톡 누르면 닫힘)
  Widget _buildUsageGuide() {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showUsageGuide = false),
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 22),
                    child: CustomPaint(
                      size: const Size(22, 11),
                      painter: _BubbleTailPainter(),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2E),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: Colors.amberAccent.withValues(alpha: 0.6),
                        width: 1.2),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: const [
                        Icon(Icons.lightbulb_outline,
                            color: Colors.amberAccent, size: 20),
                        SizedBox(width: 8),
                        Text("이용 방법",
                            style: TextStyle(
                                color: Colors.amberAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                      ]),
                      const SizedBox(height: 12),
                      const Text(
                        '대화하고 싶은 사람을 한 명 마음속에 떠올려 보세요. 그리고 그 사람이 바로 지금 눈앞에 있다고 생각하고, 하고 싶었던 말을 편하게 꺼내보세요. AI가 그 사람과 다르게 반응한다면, 그냥 넘기지 말고 "왜 그렇게 느껴?"하고 되물어 보세요. 묻고 답하다 보면, AI는 점점 더 그 사람에 가까워집니다. 진짜 그 사람과 마주 앉은 것처럼요.',
                        style: TextStyle(
                            color: Colors.white, fontSize: 14, height: 1.6),
                      ),
                      const SizedBox(height: 10),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text("(말풍선을 톡 누르면 닫혀요)",
                            style:
                                TextStyle(color: Colors.white38, fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ... (_buildTopBar, _buildChatList, _buildTextBlock, _buildControlArea는 기존과 동일하게 유지) ...
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
            // 🆕 [Anyone] 이용방법 말풍선 토글
            IconButton(
              icon: const Icon(Icons.help_outline,
                  color: Colors.amberAccent, size: 22),
              onPressed: () =>
                  setState(() => _showUsageGuide = !_showUsageGuide),
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
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  ValueListenableBuilder<int>(
                    valueListenable: BillingTicker.instance.billingState,
                    builder: (_, s, __) => GestureDetector(
                      onTap: s == 0 ? _resetIdleTimer : null,
                      child: CustomPaint(
                        size: const Size(14, 14),
                        painter: BillingDotPainter(s),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    () {
                      final int s =
                          (FFAppState().remainingTime).toInt().clamp(0, 999999);
                      final int h = s ~/ 3600;
                      final int m = (s % 3600) ~/ 60;
                      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
                    }(),
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

  Widget _buildChatList() {
    final double bottomPad = MediaQuery.of(context).size.height * 0.55;
    return Stack(
      children: [
        // 🆕 바탕 연한 안내 (대화 시작 전에만 표시)
        if (_localMessages.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.language_rounded,
                    size: 28,
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '타겟 언어로만 프리톡하려면',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.22),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.6,
                    ),
                  ),
                  Text(
                    '타겟과 오리지널 언어를 같게 하세요',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.14),
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ListView.builder(
          reverse: true,
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(16, bottomPad, 16, 16),
          itemCount: _localMessages.length,
          itemBuilder: (context, idx) {
            final realIdx = _localMessages.length - 1 - idx;
            _itemKeys[realIdx] ??= GlobalKey();
            return Container(
                key: _itemKeys[realIdx],
                child: _buildTextBlock(_localMessages[realIdx]));
          },
        ),
      ],
    );
  }

  Widget _buildTextBlock(Map<String, dynamic> msg) {
    final role = (msg['role'] ?? '').toString();
    bool isHost = role == 'HOST' || role == 'HOST_TEMP';
    final rawTarget = (msg['target'] ?? '').toString();
    final bool isThinking = (role == 'SYSTEM' && rawTarget.isEmpty) ||
        (role == 'HOST_TEMP' && rawTarget == '...') ||
        (role == 'HOST' && rawTarget.isEmpty);
    final String displayTarget = isThinking ? '...' : rawTarget;
    if (displayTarget.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: isHost ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: isHost
                ? const Color(0xFF2C2C2E)
                : const Color(0xFF9333EA).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16)),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        child: Column(
            crossAxisAlignment:
                isHost ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(displayTarget,
                  textAlign: isHost ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16 * _fontScale,
                      fontWeight: FontWeight.bold)),
              if (_showOriginal &&
                  !(FFAppState().nativeLang.isNotEmpty &&
                      FFAppState().nativeLang == FFAppState().targetLang) &&
                  !isThinking &&
                  msg['original'] != null &&
                  msg['original'].toString().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(msg['original'],
                    textAlign: isHost ? TextAlign.right : TextAlign.left,
                    style: TextStyle(
                        color: Colors.grey, fontSize: 12 * _fontScale))
              ]
            ]),
      ),
    );
  }

  Widget _buildControlArea(double bp) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 8, 24, bp),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Free Talk",
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              // 🆕 작동 표시등(패시브). 버튼 아님 - 세션 시작 시 자동 점등.
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                child: Container(
                  width: 12,
                  height: 12,
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
              ),
            ],
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
  final bool Function()? shouldReconnect;
  final void Function(String tag, String msg)? onLog; // 🔬 [v3.1] 로그 훅

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
    this.shouldReconnect,
    this.onLog,
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
        '&endpointing=$kFreeTalkDeepgramEndpointingMs' // 🔧 Free Talk: 더듬거림에 덜 민감하게
        '&utterance_end_ms=$kFreeTalkDeepgramUtteranceEndMs' // 🔧 Free Talk: 900ms로 반응속도 개선
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
              _channel?.sink.add(Uint8List.fromList(data));
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
    if (shouldReconnect != null && !shouldReconnect!()) {
      _lg('🎤 [DG-RETRY-SKIP]', '재연결 조건 불충족');
      return;
    }
    _isConnected = false;
    if (_retryCount < _maxRetries) {
      _retryCount++;
      _lg('🎤 [DG-RETRY]', '재연결 시도 $_retryCount/$_maxRetries');
      onReconnecting?.call(_retryCount); // 🔧 선택적 콜백 호출
      final delay = Duration(milliseconds: 500 * (1 << (_retryCount - 1)));
      await Future.delayed(delay);
      if (!_isDisposed && (shouldReconnect == null || shouldReconnect!())) {
        await _connect();
      } else {
        _lg('🎤 [DG-RETRY-SKIP]', '재연결 지연 중 상태 변경');
      }
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

  // 🔧 [B 수정] 디스크 I/O 경합으로 hang되는 것을 막기 위해 2초 타임아웃.
  // 타임아웃/예외 시 캐시 미스로 처리(null)해 호출 측은 API 경로로 진행.
  static Future<Uint8List?> get(String text, String voice) async {
    try {
      return await _getInternal(text, voice)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _getInternal(String text, String voice) async {
    final path = '${await _getDir()}/${_key(text, voice)}.mp3';
    final file = File(path);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }

  // 🔧 [B 수정] 저장도 2초 타임아웃. 실패해도 캐시는 best-effort로 조용히 무시.
  static Future<void> put(String text, String voice, Uint8List data) async {
    try {
      await _putInternal(text, voice, data).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  static Future<void> _putInternal(
      String text, String voice, Uint8List data) async {
    final path = '${await _getDir()}/${_key(text, voice)}.mp3';
    await File(path).writeAsBytes(data);
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

  // 🔒 [Box 7 USER-DRAIN-SIGNAL] 유저 큐 완전 drain 감지용
  bool _userStreamSealed = false;
  Completer<void>? _userDrainedCompleter;
  bool _currentChunkIsUser = false;

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

  // 🔒 [Box 7 USER-DRAIN-SIGNAL] 유저 청크 스트림 봉인.
  // 호출 시점 = "더 이상 유저 청크가 들어오지 않음" 선언.
  void sealUserStream() {
    _userStreamSealed = true;
    if (_userQueue.isEmpty && !_currentChunkIsUser) {
      if (_userDrainedCompleter != null &&
          !_userDrainedCompleter!.isCompleted) {
        _userDrainedCompleter!.complete();
      }
    }
  }

  // 🔒 [Box 7 USER-DRAIN-SIGNAL] 유저 큐가 완전히 비고 마지막 청크 재생이 끝날 때까지 대기.
  Future<void> waitUserDrained({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (_userQueue.isEmpty && !_currentChunkIsUser) {
      _userStreamSealed = false;
      return;
    }
    _userDrainedCompleter ??= Completer<void>();
    try {
      await _userDrainedCompleter!.future.timeout(timeout);
    } catch (_) {
      // Timeout은 강제 진행해 호출부가 막히지 않도록 한다.
    } finally {
      _userDrainedCompleter = null;
      _userStreamSealed = false;
    }
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
        _currentChunkIsUser = true; // 🔒 [Box 7 USER-DRAIN-SIGNAL]
      } else if (!_aiPaused && _aiQueue.isNotEmpty) {
        bytes = _aiQueue.removeAt(0);
        _currentChunkIsUser = false; // 🔒 [Box 7 USER-DRAIN-SIGNAL]
      } else {
        break;
      }

      if (bytes.isEmpty) continue;

      _completer = Completer<void>();
      final estimatedDuration = Duration(
        seconds: ((bytes.length / 16000) + 3).ceil(),
      );

      try {
        if (!TrialFlowState.instance.isTrial) {
          BillingTicker.instance.resumeFromActivity(_currentChunkIsUser
              ? 'free_talk_user_tts_start'
              : 'free_talk_ai_tts_start');
        }
        await _player.play(BytesSource(bytes));
        await _completer!.future.timeout(estimatedDuration);
        if (!TrialFlowState.instance.isTrial) {
          BillingTicker.instance.resumeFromActivity(_currentChunkIsUser
              ? 'free_talk_user_tts_end'
              : 'free_talk_ai_tts_end');
        }
      } catch (_) {
      } finally {
        if (_completer != null && !_completer!.isCompleted) {
          _completer!.complete();
        }
      }

      // 🔒 [Box 7 USER-DRAIN-SIGNAL] 유저 청크 재생 완료 직후 sealed 상태면 drain 신호.
      if (_currentChunkIsUser && _userStreamSealed && _userQueue.isEmpty) {
        if (_userDrainedCompleter != null &&
            !_userDrainedCompleter!.isCompleted) {
          _userDrainedCompleter!.complete();
        }
      }
      _currentChunkIsUser = false;
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
    // 🔒 [Box 7 USER-DRAIN-SIGNAL] drain 대기자 깨우기(deadlock 방지)
    if (_userDrainedCompleter != null && !_userDrainedCompleter!.isCompleted) {
      _userDrainedCompleter!.complete();
    }
    _userDrainedCompleter = null;
    _userStreamSealed = false;
    _currentChunkIsUser = false;
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
  int _generation = 0;
  bool _cancelled = false;
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
    // TTS API is unreliable for punctuation-only chunks like "!" or ",".
    if (!RegExp(r'[a-zA-Z0-9가-힣]').hasMatch(text)) {
      onLog?.call('🔊 [TTS-SKIP]', 'punctuation-only skipped: "$text"');
      return;
    }
    if (_cancelled) {
      final turnTag = isUser ? 'USER' : 'AI';
      onLog?.call('🔊 [TTS-DROP-LATE]',
          '[$turnTag] addText ignored after cancel: "$text"');
      return;
    }
    _pendingCount++;
    final turnTag = isUser ? 'USER' : 'AI';
    onLog?.call(
        '🔊 [TTS-01]', '[$turnTag] addText: "$text" (pending=$_pendingCount)');
    _fetch(_requestCounter++, text, _generation);
  }

  Future<void> _fetch(int id, String text, int generation) async {
    // 🔧 [B 수정] 모든 경로(캐시 히트/API 성공/실패/예외)에서
    // _pendingCount가 정확히 1회 감소하도록 try/finally로 보장.
    Uint8List result = Uint8List(0);
    try {
      // [1단계] 로컬 캐시 확인 (히트 시 result에 담고 finally에서 큐 적재)
      final cached = await TtsCache.get(text, voice);
      if (cached != null && cached.isNotEmpty) {
        result = cached;
        return;
      }

      // [2단계] API 호출 (5초 타임아웃, 최대 3회 시도) — TTS 지연 스파이크 대응
      for (int attempt = 0; attempt < 3; attempt++) {
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
              .timeout(Duration(
                  seconds: kFreeTalkChunkTtsTimeoutLadderSec[attempt]));

          if (res.statusCode == 200) {
            result = res.bodyBytes;
            final turnTag = isUser ? 'USER' : 'AI';
            onLog?.call('🔊 [TTS-02]',
                '[$turnTag] API OK (${result.length}B) for "$text"');
            // [3단계] 캐시 저장 (백그라운드, await 없음)
            unawaited(TtsCache.put(text, voice, result));
            break;
          } else {
            onLog?.call('❌ [TTS-API-ERR]',
                'statusCode=${res.statusCode} (attempt=${attempt + 1}/3)');
          }
        } catch (e) {
          onLog?.call('⚠️ [TTS-RETRY]',
              'attempt=${attempt + 1}/3 실패 (${e.runtimeType}) for "$text"');
          if (attempt < 2 && e is! TimeoutException) {
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }
      }
      if (result.isEmpty) {
        onLog?.call('❌ [TTS-FAIL]', '3회 모두 실패 — 청크 스킵: "$text"');
      }
    } catch (_) {
      // 예외가 나도 finally에서 pending 정리 후 게이트 영구 대기를 방지.
    } finally {
      if (_cancelled || generation != _generation) {
        final turnTag = isUser ? 'USER' : 'AI';
        onLog?.call('🔊 [TTS-DROP-LATE]', '[$turnTag] stale user TTS ignored');
      } else {
        _buffer[id] = result;
        _pendingCount--;
        _pushReady();
        if (_pendingCount == 0) onAllComplete?.call();
      }
    }
  }

  void _pushReady() {
    while (_buffer.containsKey(_readyCounter)) {
      final data = _buffer.remove(_readyCounter)!;
      // 🔧 [v3.5] isUser 플래그로 큐 선택
      if (!_cancelled && data.isNotEmpty) {
        audioQueue.addAudio(data, isUser: isUser);
      }
      _readyCounter++;
    }
  }

  void cancel({bool dropBuffered = true}) {
    _generation++;
    _cancelled = true;
    _pendingCount = 0;
    if (dropBuffered) _buffer.clear();
  }

  void reset() {
    _generation++;
    _cancelled = false;
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
// 📦 [Box 7-H: HybridTtsPlayer] — 하이브리드 TTS (Clone 전용)
// ====================================================================
// 설계 원칙: 구두점 OR 4단어 먼저 오는 쪽 즉시 발사(체감 빠름) + 통문장 TtsCache 저장
//   → onChunk: 청크 수신마다 호출. 구두점 OR 4단어 달성 시 fetcher에 1회 발사.
//   → onStreamEnd: remainder 순차 발사 + fullSentence TtsCache 저장 (재생 없음)
//   → reset: 턴 시작 시 상태 초기화 (새 인스턴스 생성 전 호출)
//   → Rollback: onChunk/onStreamEnd 제거 후 aiTtsFetcher.addText(toSpeak) 복원
class HybridTtsPlayer {
  final String _apiKey;
  final TtsQueueManager _ttsQueueManager;
  final ChunkedTtsFetcher _fetcher;
  final String _voice;
  final void Function(String, String)? onLog;

  bool _firstChunkFired = false;
  final StringBuffer _chunkBuffer = StringBuffer();

  HybridTtsPlayer(
    this._apiKey,
    this._ttsQueueManager,
    this._fetcher,
    this._voice, {
    this.onLog,
  });

  bool get firstChunkFired => _firstChunkFired;

  void reset() {
    _firstChunkFired = false;
    _chunkBuffer.clear();
  }

  // 구두점 OR 4단어 중 먼저 오는 쪽 1회 발사.
  // 발사 후에도 이후 청크를 _chunkBuffer에 누적 — onStreamEnd에서 remainder 처리.
  void onChunk(String chunk) {
    _chunkBuffer.write(chunk);
    if (_firstChunkFired) return;

    final buf = _chunkBuffer.toString();
    final punctMatch = kTtsDelimiterPattern.firstMatch(buf);
    final wordCount =
        buf.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    if (punctMatch == null && wordCount < 4) return;

    final String text;
    final String unfired;
    if (punctMatch != null) {
      text = buf.substring(0, punctMatch.end).trim();
      unfired = buf.substring(punctMatch.end);
    } else {
      text = buf.trim();
      unfired = '';
    }

    if (text.isEmpty) return;

    _firstChunkFired = true;
    _fetcher.addText(text);
    onLog?.call(
        '[HYB-01]', '발사(${punctMatch != null ? "구두점" : "4단어"}): "$text"');

    // 발사된 부분 제거 — 이후 onChunk는 unfired부터 누적
    _chunkBuffer.clear();
    if (unfired.isNotEmpty) _chunkBuffer.write(unfired);
  }

  // GPT 스트림 종료 시 호출:
  //   1) remainder 청킹 발사 (firstChunk 이후 남은 텍스트)
  //   2) fullSentence TtsCache 저장 (재생 없음 — 히스토리 뷰 HIT 유도)
  Future<void> onStreamEnd({String fullSentence = ''}) async {
    final remainder = _chunkBuffer.toString().trim();
    if (!_firstChunkFired && remainder.isNotEmpty) {
      // 구두점/4단어 없이 스트림 종료 — 전체 발사
      _fetcher.addText(remainder);
      _firstChunkFired = true;
      onLog?.call(
          '[HYB-01-LATE]', 'no punct/4words — full text fired at stream end');
    } else if (_firstChunkFired && remainder.isNotEmpty) {
      int lastIdx = 0;
      for (final match in kTtsDelimiterPattern.allMatches(remainder)) {
        final seg = remainder.substring(lastIdx, match.end).trim();
        if (seg.isNotEmpty) _fetcher.addText(seg);
        lastIdx = match.end;
      }
      final tail = remainder.substring(lastIdx).trim();
      if (tail.isNotEmpty) _fetcher.addText(tail);
      onLog?.call('[HYB-02]', 'remainder fired (${remainder.length}c)');
    }

    // 🔧 [C 수정] 통문장 TtsCache 저장을 백그라운드로 분리해 파이프라인을 막지 않음.
    final sentence = fullSentence.trim();
    if (sentence.isNotEmpty) {
      unawaited(_cacheFullSentenceInBackground(sentence));
    }
  }

  // 🔧 [C 수정] 통문장 캐시 저장은 onStreamEnd에서 await하지 않는 fire-and-forget 작업.
  Future<void> _cacheFullSentenceInBackground(String sentence) async {
    try {
      final cached = await TtsCache.get(sentence, _voice);
      if (cached != null && cached.isNotEmpty) {
        onLog?.call('[HYB-03-HIT]', 'TtsCache HIT — 저장 생략');
        return;
      }
      // Longer timeout + one retry for long full-sentence cache writes.
      Uint8List? bytes;
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          final res = await http
              .post(
                Uri.parse('https://api.openai.com/v1/audio/speech'),
                headers: {
                  'Authorization': 'Bearer $_apiKey',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({
                  'model': 'tts-1',
                  'input': sentence,
                  'voice': _voice,
                  'speed': 1.0,
                  'response_format': 'mp3',
                }),
              )
              .timeout(const Duration(seconds: 25));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            bytes = res.bodyBytes;
            break;
          }
        } catch (e) {
          if (attempt == 0) {
            onLog?.call('[HYB-CACHE-RETRY]', '캐시 저장 재시도(${e.runtimeType})');
          }
        }
      }
      if (bytes != null) {
        await TtsCache.put(sentence, _voice, bytes);
        onLog?.call('[HYB-04-SAVED]', '${bytes.length}B');
      } else {
        onLog?.call('[HYB-ERR]', 'TtsCache 저장 2회 실패 후 스킵');
      }
    } catch (e) {
      onLog?.call('[HYB-ERR]', 'TtsCache 저장 실패: $e');
    }
  }
}

// ============================================================================

// ====================================================================
// 🧠 [Box 7-1] FreeTalkBrain v3 — 클론 모드 전용 AI 뇌
// ====================================================================
// 📂 서브박스 구성:
//   [Box 7-1-B] streamUserTranslation   — 유저 한→영 번역 (CoT 2단계 주어 복원)
//   [Box 7-1-C] generateCleanOriginal   — AI original 생성 (오리지널 언어 자막)
// ====================================================================
class FreeTalkBrain {
  // 🆕 [EXPAND-EXIT] 대화 전체(AI+유저) → 종합 확장 문장 1개 (의미단위 ~5개, 문법 연결)
  static Future<String?> generateExpandedFromConversation(
    String apiKey,
    String transcript, {
    String userLabel = 'the user',
    String partnerLabel = 'AI partner',
  }) async {
    if (apiKey.isEmpty || transcript.trim().isEmpty) return null;
    try {
      final safeUserLabel =
          userLabel.trim().isNotEmpty ? userLabel.trim() : 'the user';
      final safePartnerLabel =
          partnerLabel.trim().isNotEmpty ? partnerLabel.trim() : 'AI partner';
      final sysPrompt = """You are an English speaking coach.
You are given a short conversation transcript.
This conversation is between $safeUserLabel and $safePartnerLabel.
Your job: compose ONE long, natural English sentence that synthesizes the overall
content and gist of the WHOLE conversation.

[RULES]
- If the partner must be mentioned, use $safePartnerLabel.
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
              'Authorization': 'Bearer $apiKey',
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
      if (s.startsWith('"') && s.endsWith('"'))
        s = s.substring(1, s.length - 1);
      return s.isEmpty ? null : s;
    } catch (e) {
      debugPrint("[FreeTalkBrain.generateExpandedFromConversation] $e");
      return null;
    }
  }

  // 🆕 [EXPAND-EXIT] 확장 문장 → 쉽고 세련된 한 문장 (Polished)
  static Future<String?> polishSentence(
    String apiKey,
    String originalSentence, {
    String partnerLabel = 'AI partner',
  }) async {
    if (apiKey.isEmpty || originalSentence.trim().isEmpty) return null;
    try {
      final safePartnerLabel =
          partnerLabel.trim().isNotEmpty ? partnerLabel.trim() : 'AI partner';
      final sysPrompt = """You are an English speaking coach.
Rewrite the given long English sentence as ONE "easy but elegant" spoken sentence.

[GOALS]
- Natural spoken rhythm (not written/academic)
- Common vocabulary (no SAT words, no bookish phrases)
- Smooth flow (pause-friendly, commas for breath)
- Same meaning as the original (do not add new facts)
- Easier to pronounce and say out loud
- Render every participant name, role label, and situation in English (translate role or description phrases; romanize real personal names). Never keep Korean text.
- The final sentence must be 100% English and must NOT contain any Korean (Hangul) characters.

[OUTPUT]
- Exactly ONE sentence. No explanation, no quotes, no prefixes.""";
      final response = await http
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
      if (response.statusCode != 200) return originalSentence;
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      String p =
          ((body['choices'] as List).first['message']['content'] as String)
              .trim();
      if (p.startsWith('"') && p.endsWith('"'))
        p = p.substring(1, p.length - 1);
      return p.isEmpty ? originalSentence : p;
    } catch (e) {
      debugPrint("[FreeTalkBrain.polishSentence] $e");
      return originalSentence;
    }
  }

  // ==================================================================
  // ==================================================================
  // 📦 [Box 7-1-B] streamUserTranslation — CoT 2단계 번역 스트림
  // ------------------------------------------------------------------
  // 핵심: 한국어 주어 생략 → 영어 주어 복원
  // Step 1: CONTEXT CHECK (이전 대화로 화자 파악)
  // Step 2: SUBJECT RESTORATION (생략된 주어/목적어 복원)
  // Step 3: TRANSLATE (구어체 톤 유지 + TTS 쉼표)
  // ==================================================================
  static Stream<String> streamUserTranslation({
    required String apiKey,
    required String textOriginal,
    required String targetLang,
    required String contextStr,
    bool disableCorrection = false,
  }) async* {
    final client = http.Client();
    try {
      final String correctionBlock = disableCorrection
          ? "Never output [CORRECTION] or [MISHEARD]. Treat the input as normal content to translate."
          : '''[CASE CORRECTION] — Check this FIRST, only when the conversation history contains at least one "User:" line.
The user is correcting the AI's misunderstanding or mishearing of their PREVIOUS utterance.
Signs:
- Starts with a correction signal: "아니" / "아니요" / "아 그게 아니라" / "다시" / "내 말은" / "그러니까" / "I mean" / "actually" / "no," / "wait,"
- AND the content is clearly a re-statement or clarification of the LAST "User:" line in the history, NOT new information.
- The user is essentially saying "that's not what I said — what I said was X."
If this is a correction, output EXACTLY: [CORRECTION]  (and nothing else)
Do NOT output [CORRECTION] when the user simply adds new details that happen to start with "아니" etc.

[CASE MISHEARD] — Check this SECOND, only when the history contains at least one "User:" line.
The user is COMPLAINING that their previous words were misheard or misunderstood, WITHOUT restating what they actually said.
Signs: "내 말이 그런 뜻이 아니야" / "그런 거 아니야" / "내 말은 그게 아니야" / "잘못 들었어" / "잘못 적었어" / "잘못 알아들었어" / "that's not what I meant" / "you misheard me" / "you got my words wrong"
- AND the utterance contains NO restated content (no actual new statement).
If so, output EXACTLY: [MISHEARD]  (and nothing else)
If the complaint INCLUDES the corrected content, use [CORRECTION] instead.

[CASE DISSATISFIED] — Check this THIRD, only when the history contains at least one "AI:" line.
The user is complaining about the AI's LAST reply itself and wants a different one,
OR the user did not catch / did not like the AI's last QUESTION and asks for it to be repeated, rephrased, or replaced.
Signs: "무슨 대답이 그래" / "무슨 질문이 그래" / "대답이 이상해" / "다른 말 해줘" / "다시 대답해 봐" / "그 대답 별로야" / "say something else" / "that's a weird reply" / "answer again"
More signs (question complaints): "뭐라고 물었어" / "뭐라고 물은 거야" / "다시 물어봐" / "제대로 다시 물어봐" / "질문 다시 해줘" / "다른 질문 해줘" / "what did you ask" / "ask me again" / "ask a different question"
More signs (MILD dissatisfaction — these ALSO count): "별로" / "별론데" / "아 그건 좀" / "에이" / "그런 거 말고" / "그건 없어" / "재미없어" / "이상하네" / "뭐야 그게" / "meh" / "not really" / "hmm, not that one"
Even slight or indirect displeasure aimed at the AI's last reply or question counts as [DISSATISFIED].
Do NOT confuse this with a negative ANSWER to the question (e.g., "아니, 안 갔어" = a valid answer, NOT dissatisfaction).
If so, output EXACTLY: [DISSATISFIED]  (and nothing else)''';

      final sysPrompt =
          '''You are an expert real-time Korean-to-$targetLang translator specialized in live conversation.

Korean is a heavy pro-drop language — subjects, objects, and pronouns are constantly omitted when clear from context. Your job is to resolve these omissions perfectly.

$correctionBlock

[INTERNAL THINKING - do not output]
Step 1. CONTEXT CHECK: Review the conversation history to identify who is speaking, who is being addressed, and who/what is the current topic.
Step 2. SUBJECT RESTORATION: Identify any omitted subject, object, or pronoun in the current Korean input and restore them based on context.
  Use these Korean grammar markers to determine roles:
  - ~이/가 = SUBJECT marker (doer of action): "엄마가 사줬어" → Mom bought it (Mom is subject)
  - ~은/는 = TOPIC marker (often the subject): "나는 갔어" → I went
  - ~한테/에게 = RECIPIENT marker (indirect object): "나한테 줬어" → gave it TO ME
  - ~을/를 = OBJECT marker (thing acted upon): "그걸 봤어" → saw THAT
  - Honorific ~(으)시 attaches to the SUBJECT's verb: "선생님이 오셨어" → The teacher came (teacher is subject, not me)
  - ~해줬어/해주셨어 = someone did something FOR someone else: the person before 가/이 is the doer
Step 3. TRANSLATE: Produce natural, fluent $targetLang with explicit subjects (I, you, he, she, they, we).

[COMMON MISTAKES - avoid these]
Korean: "걔가 나한테 전화했어" → CORRECT: He called me. WRONG: I called him.
Korean: "엄마가 용돈 줬어" → CORRECT: Mom gave me allowance. WRONG: I gave mom allowance.
Korean: "선생님이 칭찬해주셨어" → CORRECT: The teacher praised me. WRONG: I praised the teacher.
Korean: "친구가 요즘 바빠서 못 만나" → CORRECT: My friend is busy lately, so I can't meet him. WRONG: I'm busy lately...
Korean: "호진이 시험 몇 점 받을 것 같아?" → CORRECT: What score do you think Hojin will get on the exam? WRONG: What score do you think you/I will get?
NAMED PEOPLE (proper nouns like 호진, 민수, 엄마, 선생님) must stay as that exact person. NEVER collapse a named subject into "I" or "you".
The particle before the verb's doer (이/가) is ALWAYS the subject. Never swap subject and object.

[OUTPUT RULES]
- Preserve speech register: formal Korean → polite English, casual (반말) → casual English with contractions.
- Keep emotional nuance (excitement, sarcasm, hesitation) in tone.
- Insert commas (,) after each natural phrase to create rhythm for TTS shadowing.
- Output ONLY the $targetLang translation. No explanation, no Korean text, no prefixes.
- If the input is meaningless noise or filler (under 2 meaningful chars), output EXACTLY: [EVAPORATE]''';

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
        'temperature': 0.0, // 주어 추론 일관성 극대화
        'max_tokens': 120,
        'messages': [
          {'role': 'system', 'content': sysPrompt},
          {
            'role': 'user',
            'content':
                'Conversation so far:\n$contextStr\n\nTranslate this Korean utterance: "$textOriginal"',
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
  // 📦 [Box 7-1-C] generateCleanOriginal — AI original 생성 (오리지널 언어 자막)
  // ==================================================================
  static Future<String> generateCleanOriginal({
    required String apiKey,
    required String englishText,
  }) async {
    // 빈 입력 가드: GPT에 빈 문장을 보내 메타 응답을 받는 것을 방지.
    if (englishText.trim().isEmpty) return englishText;

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
                'temperature': 0.0,
                'max_tokens': 150,
                'messages': [
                  {
                    'role': 'system',
                    'content':
                        '''당신은 한영 통역 전문가입니다. 다음 영어 문장을 **자연스러운 한국어 구어체**로 번역하세요.

[중요 규칙 - 주어 생략 처리]
- 한국어는 주어를 자주 생략합니다. 영어의 I/You/He/She/We/They를 무조건 그대로 살리지 마세요.
- 문맥상 당연한 주어는 과감히 생략하여 자연스럽게 만드세요.
  예: "I need to go" → "가야겠어요" (✅) / "나는 가야 한다" (❌ 어색)
  예: "Are you coming?" → "올 거예요?" (✅) / "당신은 오고 있습니까?" (❌)
- 대화 상대가 명확하면 "너/당신"도 생략 가능합니다.
- 하지만 의미 혼동 가능성이 있을 때는 주어를 살립니다.

[구어체 톤]
- 문어체 X, 일상 대화체 O
- "~하였다" X → "~했어요" O
- "~이다" X → "~이에요/~예요" O

[출력]
- 번역문만 한 줄로 출력. 설명/주석/따옴표 없음.
''',
                  },
                  {'role': 'user', 'content': englishText},
                ],
              }),
            )
            .timeout(const Duration(seconds: 15));

        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          final result =
              data['choices'][0]['message']['content'].toString().trim();
          // 응답 검증: 번역 대신 안내/메타 응답이 오면 재시도 후 fallback.
          final lower = result.toLowerCase();
          if (lower.contains('번역할 문장') ||
              lower.contains('문장이 필요') ||
              lower.contains('문장을 제공') ||
              lower.contains('please provide') ||
              lower.contains('i need a sentence') ||
              lower.contains('no text') ||
              result.isEmpty) {
            continue;
          }
          return result;
        }
      } catch (_) {
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      } finally {
        client.close();
      }
    }
    return englishText; // 실패 시 영어 원문 (빈칸 방지)
  }

  // ==================================================================
  // 📦 Free Talk 언어 수준별 어휘 지침
  static String _freeTalkLevelInstruction(String level) {
    switch (level) {
      case "Beginner":
        return "BEGINNER (CEFR A1-A2). Use only the most common everyday words. "
            "Keep every sentence to 8 words or fewer. "
            "Use only simple present and simple past tense. "
            "No idioms, no phrasal verbs, no slang. "
            "Speak as if talking to a young child learning the language.";
      case "Advanced":
        return "ADVANCED (CEFR C1-C2). Speak like a refined, well-educated native adult. "
            "Use sophisticated, precise vocabulary and elegant, polished expressions. "
            "Refined idioms and nuanced word choice are welcome; NO slang, NO vulgar or overly casual wording. "
            "Use varied grammar such as conditionals, relative clauses, and perfect tenses. "
            "CRITICAL: Elevate WORD CHOICE only. NEVER make replies longer — keep the exact same brevity as the other levels (usually ONE short sentence).";
      case "Intermediate":
      default:
        return "INTERMEDIATE (CEFR B1-B2). Use everyday vocabulary with some variety. "
            "Keep sentences to about 14 words or fewer. "
            "Common phrasal verbs and natural expressions are fine, "
            "but avoid rare idioms and slang.";
    }
  }

  // 📦 [Box 7-1-D] streamFreeTalkResponse — Free Talk AI 응답 스트림
  static Stream<String> streamFreeTalkResponse({
    required String apiKey,
    required String userTargetText,
    required String contextStr,
    required String myTarget,
    String level = "Intermediate",
    String rejectedReply = '',
  }) async* {
    final client = http.Client();
    try {
      final String rejectedBlock = rejectedReply.trim().isEmpty
          ? ""
          : "\n- IMPORTANT: The user disliked your previous reply: \"${rejectedReply.trim()}\". Give a COMPLETELY DIFFERENT reply this time — different angle, different wording. Do NOT repeat or rephrase it.";
      final sysPrompt =
          """You are role-playing as the specific person the user has in mind and is speaking to.
You do NOT know who that person is — a partner, a parent, a boss, an old friend, someone they drifted apart from. Work it out silently from how they speak.
From their tone, what they call you, the topic, the emotion, the history they assume — quietly infer who you are to them, and become that person.

OUTPUT LANGUAGE: $myTarget ONLY. Zero Korean characters in output.

[ABSOLUTE RULES]
- NEVER reveal you are guessing or analyzing. Never name the relationship, never ask "who am I to you?", never say things like "we go way back" or "as your ___". No meta-comments about who they might be talking to.
- Just respond AS that person would — their likely tone, attitude, and feelings. Stay fully in character.
- As the conversation continues, become more consistent and more precisely that person.
- If the user pushes back because your reaction feels off (e.g. "why would you say that?"), answer in character and naturally shift toward the person they seem to be speaking to.
- Never say you are an AI or a language model.

[STYLE]
- Respond in $myTarget only. Usually ONE short sentence; use two only when truly needed.
- Ask at most ONE question. Leave room for the user to speak next.
- No greetings, no "I understand", no prefixes. Just speak as that person.
- If the audio is garbled or impossible to make out (a speech recognition error), ask them to repeat, in character, in $myTarget.$rejectedBlock

Learner level: ${_freeTalkLevelInstruction(level)}""";

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
        'temperature': 0.5,
        'max_tokens': kFreeTalkAiResponseMaxTokens,
        'messages': [
          {'role': 'system', 'content': sysPrompt},
          {
            'role': 'user',
            'content':
                'Conversation history:\n$contextStr\n\nUser just said: "$userTargetText"\n\nYour brief reply:',
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

// 🆕 [Anyone] 이용방법 말풍선 꼬리 페인터
class _BubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2A2A2E)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
