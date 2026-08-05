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

// ====================================================================
// 🏷️ [용어 대응표] 이 파일은 이름이 3개다. 헷갈리지 말 것.
//   · 파일/클래스 이름 : roleplay        (코드에서 쓰는 이름)
//   · Firestore 저장 id : roleplay       (mode / partnerType 필드 값)
//   · 화면 표시명       : Scenario Talk  (유저가 보는 이름)
//
//   표시명만 Roleplay → Scenario Talk으로 바뀌었다. 저장 id와
//   room_name("Roleplay Mode")은 그대로 둔다. 이 둘은 과거 대화
//   기록의 분류 키라서 바꾸면 기록이 미분류로 떨어진다.
//   별칭 해석 테이블: chat_history_master.dart _inferHistoryMode()
// ====================================================================

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
import '/custom_code/services/korean_turn_validator.dart';
import '/custom_code/services/openai_transcribe_service.dart';
import 'first_utterance_context_judge.dart'; // 3모드 공통 응답 길이 규칙

// ====================================================================
// 🛡️ [v4] 시나리오 재진입 보존용 static 홀더 (App State 대체)
//   방을 나갔다 다시 들어와도 유저가 세팅/수정한 시나리오를 유지.
// ====================================================================
class RoleplayScenarioStore {
  static String situation = '';
  static String aiRole = '';
  static String userRole = '';
}

/// ==================================================================== [Box
/// 2: 클래스 선언부]
/// ====================================================================
class RoutineModeRoleplay extends StatefulWidget {
  const RoutineModeRoleplay({super.key, this.width, this.height});
  final double? width;
  final double? height;

  @override
  State<RoutineModeRoleplay> createState() => _RoutineModeRoleplayState();
}

class _RoutineModeRoleplayState extends State<RoutineModeRoleplay> {
  // ====================================================================
  // 📦 [Box 3: 상태 변수 및 초기화]
  // ====================================================================
  String _deepgramKey = "";
  String _openAiKey = "";
  static const String _aiVoice = 'nova';
  static const Duration _accurateTranscribeTimeout = Duration(seconds: 12);
  bool _isConversationActive = false;
  double _fontScale = 1.0;
  bool _showOriginal = true;
  int _turnCounter = 0;

  // 👂 [HEARD-CONFIRM] 전사가 깨졌을 때 "글로 적기 전에" 말로 되묻는다.
  //   전사문을 화면에 쓰지 않고 여기에 보류해 두었다가, 유저가 "네"라고
  //   확인해 주면 그대로 재개하고, 아니면 버린다. 잘못 들은 문장이
  //   화면에 남아 유저가 컴플레인할 일을 없애는 것이 목적이다.
  String? _pendingHeardConfirmation;
  int _heardConfirmationAttempts = 0;

  String? _sessionDocId; // 🔧 [v3 추가] 첫 대화 후 세션 ID (클론 변경 시 null 리셋)
  DocumentReference? _myHistoryRef; // 🔧 [히스토리] chat_history 문서 참조 (Duo 패턴)

  // 🔧 [v3.4 발화 합치기] 유저 더듬거림 대응
  // speech_final 받아도 바로 파이프라인 시작 안 하고 조건부 대기
  // 대기 중 새 발화 오면 합쳐서 처리 (최종 한 덩어리로)
  String _pendingTranscript = ''; // 대기 중인 유저 발화 누적
  Timer? _commitTimer; // "진짜 끝났는지" 확정 타이머
  static const int COMMIT_WAIT_SPEECH_FINAL_MS =
      600; // speechFinal=true 시 빠른 응답
  static const int COMMIT_WAIT_UNCERTAIN_MS =
      1100; // UtteranceEnd/speechFinal=false 시 여유 대기
  bool _lastTurnWasSpeechFinal = false; // 마지막 onTurnEnded 이벤트 타입 기록
  final List<Uint8List> _turnPcmChunks = <Uint8List>[];
  int _turnPcmBytes = 0;
  static const int _turnPcmBufferMaxBytes = 32000 * 60;
  int _pipelineGeneration = 0;
  bool _aiTurnActive = false;

  void _log(String tag, String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    final line = '[$ts] $tag $msg';
    print(line);
    AppLogLedger.instance.add('ROLEPLAY', '$tag $msg');
  }

  // API 응답에서 [Action], (Laughs) 같은 오염 패턴 제거
  String _cleanText(String text) {
    return text
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // punctuation/공백만 있는 문자열은 TTS 큐에 넣지 않기 위한 필터
  bool isMeaninglessTtsText(String text) {
    final t = text.trim();
    if (t.isEmpty) return true;
    return RegExp('^[\\s.,!?;:\'"\\[\\]{}()\\-]+\$').hasMatch(t);
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

  void _resetTurnPcmBuffer() {
    _turnPcmChunks.clear();
    _turnPcmBytes = 0;
  }

  void _appendTurnPcm(Uint8List bytes) {
    if (bytes.isEmpty) return;
    _turnPcmChunks.add(bytes);
    _turnPcmBytes += bytes.length;
    while (
        _turnPcmBytes > _turnPcmBufferMaxBytes && _turnPcmChunks.isNotEmpty) {
      _turnPcmBytes -= _turnPcmChunks.removeAt(0).length;
    }
  }

  Uint8List? _snapshotTurnPcm() {
    if (_turnPcmBytes <= 0) return null;
    final pcm = Uint8List(_turnPcmBytes);
    var offset = 0;
    for (final chunk in _turnPcmChunks) {
      pcm.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return pcm;
  }

  Future<String?> _transcribeTurn(Uint8List pcm) {
    if (pcm.isEmpty || _openAiKey.isEmpty) return Future.value(null);
    return OpenAiTranscribeService.transcribePcm16(
      apiKey: _openAiKey,
      pcm: pcm,
      language: 'ko',
      model: OpenAiTranscribeService.firstTurnModel,
      timeout: _accurateTranscribeTimeout,
      onLog: _log,
    );
  }

  String _buildScenarioMemberInstructions() => '''
You are the assigned character inside a live Korean scenario conversation.
Situation: ${_scenarioSituation.trim()}
Your role: ${_roleplayPartnerLabel.trim()}
User role: ${_roleplayUserLabel.trim()}

${buildNativeOutputLanguagePolicy(FFAppState().nativeLang)}
- You are NOT a host, moderator, narrator, facilitator, guide, or coach.
- Never introduce the scenario, welcome the user to an activity, explain what will happen, or invite the user to begin.
- Speak only as "${_roleplayPartnerLabel.trim()}" would actually speak to "${_roleplayUserLabel.trim()}" inside this exact situation.
- Stay fully in character and react directly to the user's latest line.
- Preserve the established situation, roles, relationship, and conversation memory.
- Do not translate, teach, coach, narrate, or mention being an AI.
- Do not output stage directions, labels, brackets, or explanations.

$kKoreanPoliteSpeechPolicy

$kSpokenReplyLengthPolicy
- In character, this means answering like a real person in that situation would: briefly.
''';

  String _recentKoreanConversation() {
    final turns = _localMessages.where((message) {
      final role = message['role']?.toString() ?? '';
      final text = message['target']?.toString().trim() ?? '';
      return (role == 'HOST' || role == 'SYSTEM') && text.isNotEmpty;
    }).toList();
    final recent = turns.length > 12 ? turns.sublist(turns.length - 12) : turns;
    return recent.map((message) {
      final speaker = message['role'] == 'HOST' ? 'USER' : 'AI';
      return '$speaker: ${message['target']}';
    }).join('\n');
  }

  Future<void> _speakKoreanLine(String text) async {
    final spoken = text.trim();
    if (spoken.isEmpty || _openAiKey.isEmpty) return;
    _ttsQueueManager.setUserTurn(false);
    _ttsQueueManager.setAiPaused(false);
    final fetcher = ChunkedTtsFetcher(
      _openAiKey,
      _ttsQueueManager,
      _aiVoice,
      language: 'ko',
      isUser: false,
      onLog: _log,
    );
    fetcher.addText(spoken);
    int ticks = 0;
    while ((fetcher.pendingRequests > 0 || _ttsQueueManager.isBusy) &&
        mounted &&
        _isConversationActive) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (++ticks > 400) {
        _log('[KOREAN-TTS-TIMEOUT]', 'Scenario Talk TTS exceeded 20s');
        break;
      }
    }
  }

  // 🎭 롤플레이 시나리오
  String _scenarioKeyword = "";
  String _scenarioSituation = "";
  String _scenarioAiRole = "";
  String _scenarioUserRole = "";
  bool _isGeneratingScenario = false;
  bool _isAiOpenerPlaying = false; // AI 첫 발화 재생 중 여부

  String get _roleplayPartnerLabel {
    final local = _scenarioAiRole.trim();
    if (local.isNotEmpty) return local;
    final stored = RoleplayScenarioStore.aiRole.trim();
    return stored.isNotEmpty ? stored : 'the roleplay partner';
  }

  String get _roleplayUserLabel {
    final local = _scenarioUserRole.trim();
    if (local.isNotEmpty) return local;
    final stored = RoleplayScenarioStore.userRole.trim();
    return stored.isNotEmpty ? stored : 'the user';
  }

  // ── Idle Timeout v2 ───────────────────────────────────────────────
  // 기준: "유저도 AI도 아무 작동이 없는 상태"가 연속 60초 지속되면 pause.
  //  - AI 작동 = _ttsQueueManager.isBusy (TTS 재생/대기)
  //  - 유저 작동 = _voiceManager != null (마이크 연결/녹음)
  // 1초 주기 감시 타이머가 작동 여부를 보고 idle 누적초를 증감한다.
  Timer? _idlePauseTimer;
  List<String> _lastExchangeMsgIds = []; // [정정] 직전 교환 messages docId
  bool _isIdlePaused = false;
  int _idleElapsedSec = 0;

  bool get _isSystemBusy {
    return _ttsQueueManager.isBusy || _aiTurnActive;
  }

  void _resetIdleTimer() {
    _idleElapsedSec = 0;
    if (_isIdlePaused) {
      _isIdlePaused = false;
      if (mounted) setState(() {});
      BillingTicker.instance.resume();
      BillingTicker.instance.logMode('roleplay');
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

  // 오디오 및 UI
  final List<Map<String, dynamic>> _localMessages = [];
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  DateTime? _lastScrollThrottle;
  DeepgramV2VoiceManager? _voiceManager;
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final TtsQueueManager _ttsQueueManager;
  late HybridTtsPlayer hybridTtsPlayer;

  // ⏱️ 성능 측정용 초시계
  final Stopwatch _swDeepgram = Stopwatch();
  final Stopwatch _swOpenAI = Stopwatch();
  final Stopwatch _swTTS = Stopwatch();
  // ⏱️ latency 세부 측정
  final Stopwatch _swSpeechEnd = Stopwatch(); // 발화 확정 시점 기준
  int _msGptFirstToken = 0;
  int _msGptStreamEnd = 0;
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
    _fetchKeysAndInit();
    BillingTicker.instance.setSessionIdentifiers();
    BillingTicker.instance.setRate(BillingRate.full);
    BillingTicker.instance.resume();
    BillingTicker.instance.logMode('roleplay');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resetIdleTimer();
    });
  }

  /// 나가는 모든 경로에서 호출: chat_json + last_message 저장 (탐색 없이 순수 저장만)
  Future<void> _forceSaveToFirestore() async {
    if (_myHistoryRef == null) return;
    String lastMsg = "대화 내역이 없습니다.";
    for (int i = _localMessages.length - 1; i >= 0; i--) {
      final t = (_localMessages[i]['target'] ?? '').toString().trim();
      if (t.isNotEmpty && t != '...') {
        lastMsg = t;
        break;
      }
    }
    try {
      await _myHistoryRef!.update({
        'last_message': lastMsg,
        'last_active': FieldValue.serverTimestamp(),
        'chat_json': jsonEncode(_localMessages),
        'is_completed': false,
      });
      debugPrint("✅ 히스토리 자동 저장 성공");
    } catch (e) {
      debugPrint("❌ 히스토리 저장 중 오류: $e");
    }
  }

  @override
  void dispose() {
    _clearIdleTimers();
    BillingTicker.instance.pause();
    _forceSaveToFirestore();
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

  Future<void> _fetchKeysAndInit() async {
    try {
      await FirebaseRemoteConfig.instance.fetchAndActivate();
      if (mounted) {
        setState(() {
          _deepgramKey =
              FirebaseRemoteConfig.instance.getString('DeepgramAPIKey');
          _openAiKey = FirebaseRemoteConfig.instance.getString('OpenAIAPIKey');
        });
        // 🛡️ [v4 가드] 세팅된 시나리오가 있으면 재진입 시 보존, 없으면 새 제안
        if (RoleplayScenarioStore.situation.isNotEmpty &&
            RoleplayScenarioStore.aiRole.isNotEmpty &&
            RoleplayScenarioStore.userRole.isNotEmpty) {
          setState(() {
            _scenarioSituation = RoleplayScenarioStore.situation;
            _scenarioAiRole = RoleplayScenarioStore.aiRole;
            _scenarioUserRole = RoleplayScenarioStore.userRole;
            _scenarioKeyword = RoleplayScenarioStore.situation;
          });
          _maybeAutoStartScenario();
        } else {
          _generateScenario();
        }
      }
    } catch (e) {
      print('❌ Key Load Error: $e');
    }
  }

  /// 시나리오가 정해지면 AI가 알아서 첫 대사를 건다. 예전에는 Start 버튼을
  /// 눌러야 시작됐다. 조건은 지웠던 그 버튼의 표시 조건과 같다 — 역할이 정해졌고,
  /// 아직 아무 말도 오가지 않았고, 첫 대사가 재생 중이 아닐 때 딱 한 번.
  void _maybeAutoStartScenario() {
    if (!mounted) return;
    if (_openAiKey.isEmpty || _scenarioAiRole.isEmpty) return;
    if (_localMessages.isNotEmpty ||
        _isAiOpenerPlaying ||
        _isConversationActive) {
      return;
    }
    _resetIdleTimer();
    setState(() => _isConversationActive = true);
    _generateAndPlayAiOpener();
  }

  // ====================================================================
  // 📦 [Box 4-A: 드라마/영화 장면 기반 시나리오 자동 생성]
  // ====================================================================
  Future<void> _generateScenario() async {
    if (_openAiKey.isEmpty || _isGeneratingScenario) return;
    setState(() => _isGeneratingScenario = true);
    try {
      final result = await RoleplayBrain.generateDramaticScenario(_openAiKey);
      if (mounted && result != null) {
        setState(() {
          _scenarioKeyword = result['situation'] ?? '';
          _scenarioSituation = result['situation'] ?? '';
          _scenarioAiRole = result['ai_role'] ?? '';
          _scenarioUserRole = result['user_role'] ?? '';
          _sessionDocId = null;
          _myHistoryRef = null;
          _localMessages.clear();
          _isConversationActive = false;
        });
        // 🛡️ [v4] 재진입 보존용 홀더 동기화
        RoleplayScenarioStore.situation = _scenarioSituation;
        RoleplayScenarioStore.aiRole = _scenarioAiRole;
        RoleplayScenarioStore.userRole = _scenarioUserRole;
        _maybeAutoStartScenario();
      }
    } catch (e) {
      print('❌ 시나리오 생성 에러: $e');
    } finally {
      if (mounted) setState(() => _isGeneratingScenario = false);
    }
  }

// ====================================================================
// 📦 [Box 5: Deepgram + Relay Pipeline] ← 통신로직 박스코드와 완전 일치
// ====================================================================
  // [텔레프롬프터 v1] 현재 버블을 화면 중앙(0.45)으로 부드럽게 이동.
  //   텍스트 길이 기반 동적 duration: 짧으면 느긋(700ms), 길면 빠르게(150ms).
  //   reverse list uses position 0 as the latest-message anchor.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
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

  // 현재 대사를 화면 맨 위에 고정 — Scrollable.ensureVisible 기반
  void _scrollToCurrentTop(int index) {
    final role = (index >= 0 && index < _localMessages.length)
        ? (_localMessages[index]['role'] ?? '')
        : '';
    _log('🧭 [SCROLL-TOP]', 'index=$index role=$role');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[index];
      if (key == null) return;
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.98, // reverse: true top anchoring
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _stopEverything() {
    _pipelineGeneration++;
    _isConversationActive = false;
    _isAiOpenerPlaying = false;
    _aiTurnActive = false;
    _commitTimer?.cancel(); // 🔧 [v3.4] 대기 중 타이머 정리
    _commitTimer = null;
    _pendingHeardConfirmation = null; // 보류된 확인 대기 발화도 버림
    _heardConfirmationAttempts = 0;
    _pendingTranscript = ''; // 대기 중 발화도 버림
    _resetTurnPcmBuffer();
    _voiceManager?.dispose();
    _voiceManager = null;
    _ttsQueueManager.stop();
    if (mounted) setState(() {});
  }

  // ====================================================================
  // 📦 [AI 첫 발화 — AI가 먼저 대화 시작]
  // ====================================================================
  // 🎯 [롤플레이 대화 시작 3원칙] (코드 정책 요약)
  //
  // 원칙 1. AI가 항상 먼저 말을 시작한다.
  //         유저가 마이크 버튼을 누르면 AI가 오프닝 멘트를 먼저 발화.
  //         AI 발화 완료 후 마이크 청취가 시작됨.
  //
  // 원칙 2. 타겟 언어(targetLang)로만 말한다.
  //         ai_role / user_role 이름이 한글로 주어져도
  //         실제 AI 대사는 반드시 targetLang으로만 출력.
  //         한국어 등 모국어를 절대 섞지 않는다.
  //
  // 원칙 3. 해당 역할이 실제 현실에서 가장 먼저 할 법한 자연스러운 말로 시작.
  //         어색한 학습용 인사 X, 그 역할·상황에 딱 맞는 현실적 구어체 O.
  // ====================================================================
  Future<void> _generateAndPlayAiOpener() async {
    if (_isAiOpenerPlaying || _scenarioAiRole.isEmpty) return;
    _isAiOpenerPlaying = true;
    var aiIndex = -1;
    if (mounted) setState(() {});
    try {
      var aiKorean = await RoleplayBrain.generateKoreanOpener(
        apiKey: _openAiKey,
        situation: _scenarioSituation,
        aiRole: _roleplayPartnerLabel.trim(),
        userRole: _roleplayUserLabel.trim(),
      );
      if (aiKorean.isEmpty) {
        aiKorean = '그래서 지금 어떻게 하실 생각이세요?';
        _log('[OPENER-FALLBACK]', 'gpt-4o-mini 첫 대사 비어 있음');
      }
      if (!mounted || !_isConversationActive) return;
      setState(() {
        _localMessages.add(<String, dynamic>{
          'role': 'SYSTEM',
          'target': aiKorean,
          'original': '',
        });
        aiIndex = _localMessages.length - 1;
      });
      _scrollToBottom();

      _ttsQueueManager.setUserTurn(false);
      _ttsQueueManager.setAiPaused(false);
      final fetcher = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        _aiVoice,
        language: 'ko',
        isUser: false,
        onLog: _log,
      );
      fetcher.addText(aiKorean);

      // 🎤 마이크는 첫 대사가 끝난 뒤 아래 finally에서 연다. 동시에 열어 봤더니
      //   스피커로 나가는 AI 목소리를 echoCancel이 지우면서 유저 입력까지 통째로
      //   눌려, Deepgram이 빈 전사만 돌려줬다. 바지인보다 입력이 먼저다.
      int ticks = 0;
      while ((fetcher.pendingRequests > 0 || _ttsQueueManager.isBusy) &&
          mounted &&
          _isConversationActive &&
          !fetcher.isCancelled) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (++ticks > 400) {
          _log('⚠️ [OPENER-TTS-TIMEOUT]', '첫 대사 음성 20초 초과');
          break;
        }
      }
      await _saveHistoryMessages(<Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'SYSTEM',
          'original_text': aiKorean,
        },
      ]);
      _log('[OPENER]', 'model=gpt-4o-mini voice=$_aiVoice lang=ko');
    } catch (error) {
      _log('[OPENER-ERR]', 'reason=${error.runtimeType}');
      if (mounted && aiIndex >= 0 && aiIndex < _localMessages.length) {
        setState(() => _localMessages.removeAt(aiIndex));
      }
    } finally {
      _isAiOpenerPlaying = false;
      // 첫 대사가 실패해도 마이크는 반드시 열어 대화가 죽지 않게 한다.
      if (mounted && _isConversationActive) _startDeepgramListening();
    }
  }

  // ignore: unused_element
  Future<void> _generateAndPlayAiOpenerLegacy() async {
    if (_isAiOpenerPlaying || _scenarioAiRole.isEmpty) return;
    _isAiOpenerPlaying = true;
    if (mounted) setState(() {});

    try {
      final String targetLangName = FFAppState().targetLang.isNotEmpty
          ? FFAppState().targetLang
          : 'English';

      if (mounted) {
        setState(() {
          _localMessages.add({'role': 'SYSTEM', 'target': '', 'original': ''});
        });
        _scrollToBottom();
      }
      final int aiIndex = _localMessages.length - 1;

      String openerText = '';
      String openerBuffer = '';
      final RegExp splitPattern = RegExp(r'[,\.?!;:。、！？…，；：\n]');

      final ChunkedTtsFetcher aiTtsFetcher = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        "nova",
        isUser: false,
        onLog: _log,
      );
      _ttsQueueManager.setUserTurn(false);
      _ttsQueueManager.setAiPaused(false);

      await for (final chunk in RoleplayBrain.generateAiOpener(
        apiKey: _openAiKey,
        situation: _scenarioSituation,
        aiRole: _scenarioAiRole,
        userRole: _scenarioUserRole,
        targetLang: targetLangName,
      )) {
        if (!_isConversationActive) break;
        openerText += chunk;
        openerBuffer += chunk;
        if (mounted)
          setState(() => _localMessages[aiIndex]['target'] = openerText);

        final matches = splitPattern.allMatches(openerBuffer).toList();
        if (matches.isNotEmpty) {
          final int lastIdx = matches.last.end;
          final String toSpeak = openerBuffer.substring(0, lastIdx).trim();
          openerBuffer = openerBuffer.substring(lastIdx);
          if (toSpeak.isNotEmpty) {
            final cleaned = _cleanText(toSpeak);
            if (isMeaninglessTtsText(cleaned)) {
              _log('🔊 [TTS-SKIP] [AI]', '의미 없는 TTS 조각 skip: "$cleaned"');
            } else {
              aiTtsFetcher.addText(cleaned);
            }
          }
        }
      }
      if (openerBuffer.trim().isNotEmpty) {
        final cleanedOpener = _cleanText(openerBuffer.trim());
        if (isMeaninglessTtsText(cleanedOpener)) {
          _log('🔊 [TTS-SKIP] [AI]', '의미 없는 TTS 조각 skip: "$cleanedOpener"');
        } else {
          aiTtsFetcher.addText(cleanedOpener);
        }
      }

      // 역번역 (한국어 자막)
      RoleplayBrain.generateCleanOriginal(
              apiKey: _openAiKey, englishText: openerText)
          .then((cleanKorean) {
        if (mounted && _localMessages.length > aiIndex) {
          setState(() => _localMessages[aiIndex]['original'] = cleanKorean);
        }
      });

      // TTS 재생 완료 대기
      int waitTicks = 0;
      while ((aiTtsFetcher.pendingRequests > 0 || _ttsQueueManager.isBusy) &&
          _isConversationActive) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (++waitTicks > 200) break;
      }

      // chat_history 저장
      if (openerText.isNotEmpty) {
        final String aiOriginal = await RoleplayBrain.generateCleanOriginal(
            apiKey: _openAiKey, englishText: openerText);
        if (mounted && _localMessages.length > aiIndex) {
          setState(() => _localMessages[aiIndex]['original'] = aiOriginal);
        }
        await _saveHistoryMessages([
          {
            'role': 'SYSTEM',
            'original_text': aiOriginal,
            'translated_text': _cleanText(openerText),
          }
        ]);
      }
    } catch (e) {
      _log('❌ [OPENER-ERR]', 'AI Opener Error: $e');
    } finally {
      _isAiOpenerPlaying = false;
      if (mounted && _isConversationActive) {
        _startDeepgramListening();
      }
    }
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

    // SYSTEM 앞(없으면 전체 끝)에서 가장 최근 HOST 버블 탐색
    int lastHostIdx = -1;
    int searchFrom =
        lastSystemIdx >= 0 ? lastSystemIdx - 1 : _localMessages.length - 1;
    for (int i = searchFrom; i >= 0; i--) {
      if (_localMessages[i]['role'] == 'HOST') {
        lastHostIdx = i;
        break;
      }
    }

    // 인덱스가 큰 것부터 제거 (인덱스 밀림 방지)
    if (lastSystemIdx >= 0) _localMessages.removeAt(lastSystemIdx);
    if (lastHostIdx >= 0) _localMessages.removeAt(lastHostIdx);
  }

  // AI가 응답하기 전에 중단된 "고아 HOST 버블" 제거
  // 새 턴 시작 전 호출하여 직전 오인식/중단 메시지를 정리
  void _removeOrphanedHostBubbles() {
    int lastSystemIdx = -1;
    for (int i = _localMessages.length - 1; i >= 0; i--) {
      if (_localMessages[i]['role'] == 'SYSTEM') {
        lastSystemIdx = i;
        break;
      }
    }
    // 마지막 SYSTEM 이후(또는 SYSTEM 없으면 전체)의 HOST 버블 역순 제거
    for (int i = _localMessages.length - 1; i > lastSystemIdx; i--) {
      if (_localMessages[i]['role'] == 'HOST') {
        _localMessages.removeAt(i);
      }
    }
  }

  Future<void> _startDeepgramListening() async {
    // 이미 듣고 있으면 새로 열지 않는다. 첫 대사 재생과 마이크 열기가 겹치면서
    // 여기가 두 번 불릴 수 있는데, 그대로 두면 VoiceManager가 하나 더 생겨
    // 녹음 스트림이 이중으로 돈다. 턴이 끝나면 _voiceManager가 null이 되므로
    // 다음 턴 재개는 막히지 않는다.
    if (_voiceManager != null) {
      _log('🎤 [LISTEN-SKIP]', '이미 듣는 중 → 중복 오픈 무시');
      return;
    }
    if (_deepgramKey.isEmpty || !(await _audioRecorder.hasPermission())) return;
    _resetIdleTimer();
    _isConversationActive = true;
    _resetTurnPcmBuffer();
    if (mounted) {
      setState(() {
        _debugResult = "⏱️ 듣는 중...";
        _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
        _localMessages
            .add({'role': 'HOST_TEMP', 'target': '...', 'type': 'user_input'});
      });
      // HOST_TEMP("...")는 스크롤 트리거 없음 — 실제 HOST 버블 등장 시 스크롤
    }

    _log('🎤 [LISTEN-01]', '_startDeepgramListening 진입, VoiceManager 생성');

    // 🌐 [v3.1] 로비에서 유저가 선택한 모국어(nativeLang)로 Deepgram 인식
    // 유저가 한국어로 말하면 Deepgram이 한국어로 인식 → Brain이 영어로 번역
    const String dgLangCode = 'ko';
    _log('🌐 [LANG]', 'Deepgram boundary language=ko');

    _voiceManager = DeepgramV2VoiceManager(
      apiKey: _deepgramKey,
      audioRecorder: _audioRecorder,
      langCode: dgLangCode,
      onLog: _log, // 🔬 로그 훅 주입
      onConnected: () {
        _log('✅ [LISTEN-02]', 'onConnected 콜백 실행');
      },
      onTranscriptUpdate: (transcript) {
        BillingTicker.instance.resumeFromActivity('roleplay_stt_partial');
        _swDeepgram.reset();
        _swDeepgram.start();
      },
      onAudioData: _appendTurnPcm,
      onTurnEnded: (transcript, {bool speechFinal = false}) {
        BillingTicker.instance.resumeFromActivity('roleplay_stt_result');
        _lastTurnWasSpeechFinal = speechFinal;
        _log('🔀 [LISTEN-03]',
            'onTurnEnded 콜백 수신: "$transcript" speechFinal=$speechFinal');
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
    BillingTicker.instance.resumeFromActivity('roleplay_mic_start');
    _log('🎤 [LISTEN-05]', 'connectAndStart 완료');
  }

  // speechFinal 여부에 따른 조건부 commit 대기 시간 계산
  int _getCommitWaitMs() {
    if (_lastTurnWasSpeechFinal) {
      return COMMIT_WAIT_SPEECH_FINAL_MS;
    }
    return COMMIT_WAIT_UNCERTAIN_MS;
  }

  // 🔧 [v3.4] Deepgram speech_final/UtteranceEnd 수신 시 호출됨
  // 조건부 대기창 안에서 추가 발화 합치기 → 완전히 끝나면 파이프라인 시작
  void _stopMicAndProcess(String transcript) async {
    _resetIdleTimer();
    final clean = transcript.trim();
    _log('🔀 [STOP-01]', 'speech_final 수신: "$clean" (len=${clean.length})');

    if (clean.length < 2) {
      _log('🔀 [STOP-02]', '너무 짧음 → 무시');
      _resetTurnPcmBuffer();
      return;
    }

    final waitMs = _getCommitWaitMs();

    // 🔧 기존 대기 중인 발화가 있으면 공백으로 연결 (더듬거림 합치기)
    if (_pendingTranscript.isEmpty) {
      _pendingTranscript = clean;
      _log('🔀 [STOP-03]',
          '신규 발화 접수. ${waitMs}ms 조건부 대기창 시작 speechFinal=$_lastTurnWasSpeechFinal');
    } else {
      _pendingTranscript = '$_pendingTranscript $clean';
      _log('🔀 [STOP-04]',
          '합치기: "$_pendingTranscript" (${waitMs}ms 조건부 대기창 리셋)');
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

    // 조건부 대기 후 파이프라인 시작 예약
    _commitTimer = Timer(
      Duration(milliseconds: waitMs),
      () => _commitAndProcess(),
    );
  }

  // Deepgram 텍스트는 발화 종료 경계에만 사용한다. 실제 한국어 문장은
  // 녹음 PCM 전체를 gpt-4o-transcribe에 전달해 매 턴 새로 확정한다.
  void _commitAndProcess() async {
    final generation = _pipelineGeneration;
    final boundaryTranscript = _pendingTranscript.trim();
    _pendingTranscript = '';
    _commitTimer = null;
    if (boundaryTranscript.isEmpty) {
      if (_isConversationActive) _startDeepgramListening();
      return;
    }

    final pcm = _snapshotTurnPcm();
    final closingManager = _voiceManager;
    _voiceManager = null;
    if (closingManager != null) unawaited(closingManager.dispose());
    if (pcm == null || pcm.isEmpty) {
      _log('[STT-ROUTE]', 'gpt-4o-transcribe skipped reason=empty_pcm');
      if (_isConversationActive) _startDeepgramListening();
      return;
    }

    final userKorean = (await _transcribeTurn(pcm))?.trim() ?? '';
    if (!mounted || generation != _pipelineGeneration) return;
    if (userKorean.isEmpty) {
      _log('[STT-ROUTE]', 'gpt-4o-transcribe failed; Deepgram text discarded');
      if (_isConversationActive) _startDeepgramListening();
      return;
    }
    _log('[STT-ROUTE]',
        'selected=gpt-4o-transcribe every_turn=true len=${userKorean.length}');

    final validation = await KoreanTurnValidator.validate(
      apiKey: _openAiKey,
      transcribedText: userKorean,
      mode: 'scenario_talk',
      modeContext: '''Situation: $_scenarioSituation
AI role: ${_roleplayPartnerLabel.trim()}
User role: ${_roleplayUserLabel.trim()}''',
      recentConversation: _recentKoreanConversation(),
    );
    if (!mounted || generation != _pipelineGeneration) return;
    _log('[TURN-VALIDATE]',
        'accepted=${validation.accepted} reason=${validation.reason}');
    if (!validation.accepted) {
      setState(() {
        _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
        _localMessages.add(<String, dynamic>{
          'role': 'SYSTEM',
          'target': KoreanTurnValidator.retryLine,
          'original': '',
          'clarify': true,
        });
      });
      _scrollToBottom();
      await _speakKoreanLine(KoreanTurnValidator.retryLine);
      if (mounted && _isConversationActive) _startDeepgramListening();
      return;
    }
    await _processScenarioTalkTurn(validation.text, generation: generation);
  }

  // ignore: unused_element
  void _commitAndProcessLegacy() async {
    final committed = _pendingTranscript.trim();
    _pendingTranscript = '';
    _commitTimer = null;

    if (committed.isEmpty) {
      _log('🔀 [COMMIT-00]', '빈 발화 → 마이크 재시작');
      if (_isConversationActive) _startDeepgramListening();
      return;
    }

    _log('🔀 [COMMIT-01]', '확정: "$committed" → 파이프라인 시작');
    _swSpeechEnd.reset();
    _swSpeechEnd.start();

    // 마이크/VoiceManager 정리
    await _voiceManager?.dispose();
    _voiceManager = null;
    _log('🔀 [COMMIT-02]', 'VoiceManager dispose 완료');

    _log('🔀 [COMMIT-03]', '_processRelayPipeline 호출');
    _processRelayPipeline(committed);
  }

  Future<void> _processScenarioTalkTurn(
    String userKorean, {
    required int generation,
  }) async {
    if (!mounted ||
        !_isConversationActive ||
        generation != _pipelineGeneration) {
      return;
    }
    _turnCounter++;
    final turnNumber = _turnCounter;
    var aiIndex = -1;
    final recentConversation = _recentKoreanConversation();
    try {
      setState(() {
        _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
        _removeOrphanedHostBubbles();
        _localMessages.add(<String, dynamic>{
          'role': 'HOST',
          'target': userKorean,
          'original': '',
        });
      });
      _scrollToBottom();

      final aiKorean = await RoleplayBrain.generateKoreanTurn(
        apiKey: _openAiKey,
        instructions: _buildScenarioMemberInstructions(),
        userText: userKorean,
        recentConversation: recentConversation,
      );
      if (aiKorean.isEmpty) {
        throw StateError('Scenario Talk response did not complete.');
      }
      if (!mounted ||
          !_isConversationActive ||
          generation != _pipelineGeneration ||
          turnNumber != _turnCounter) {
        return;
      }
      setState(() {
        _localMessages.add(<String, dynamic>{
          'role': 'SYSTEM',
          'target': aiKorean,
          'original': '',
        });
        aiIndex = _localMessages.length - 1;
      });
      _scrollToBottom();
      await _speakKoreanLine(aiKorean);

      final hostLine = <String, dynamic>{
        'role': 'HOST',
        'original_text': userKorean,
      };
      final systemLine = <String, dynamic>{
        'role': 'SYSTEM',
        'original_text': aiKorean,
      };
      _saveTurnToFirestore(<Map<String, dynamic>>[hostLine, systemLine]);
      await _saveHistoryMessages(<Map<String, dynamic>>[hostLine, systemLine]);
      _log('[GPT-HISTORY]',
          'turn=$turnNumber model=gpt-4o-mini voice=$_aiVoice tts=true');
    } catch (error) {
      _log('[RT-PIPE-ERR]', 'turn=$turnNumber reason=${error.runtimeType}');
      if (mounted && aiIndex >= 0 && aiIndex < _localMessages.length) {
        setState(() {
          if ((_localMessages[aiIndex]['target'] ?? '').toString().isEmpty) {
            _localMessages.removeAt(aiIndex);
          }
        });
      }
    } finally {
      if (mounted &&
          _isConversationActive &&
          generation == _pipelineGeneration &&
          turnNumber == _turnCounter) {
        _startDeepgramListening();
      }
    }
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
      case 'korean':
        return '다시 말씀해 주세요.';
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

  // [정정] 직전 잘못된 교환(HOST+SYSTEM)을 chat_history에서 제거
  Future<void> _deleteLastExchangeFromHistory() async {
    if (_myHistoryRef == null || _lastExchangeMsgIds.isEmpty) return;
    final ids = List<String>.from(_lastExchangeMsgIds);
    _lastExchangeMsgIds = [];
    try {
      for (final id in ids) {
        await _myHistoryRef!.collection('messages').doc(id).delete();
      }
      await _myHistoryRef!
          .update({'msg_count': FieldValue.increment(-ids.length)});
      _log('[HIST-DEL]', '잘못된 교환 ${ids.length}건 히스토리 제거');
    } catch (e) {
      _log('[HIST-DEL-ERR]', '히스토리 제거 실패: $e');
    }
  }

  Future<void> _processRelayPipeline(String finalTranscript,
      {bool isCorrectionRetry = false,
      bool understandingConfirmed = false}) async {
    // 👂 [HEARD-CONFIRM] 되묻기를 걸어둔 상태면, 이번 발화는 새 대화가 아니라
    //   그 되물음에 대한 답이다. 확인/부정/정정 셋으로 갈라 처리한다.
    final pendingHeard = _pendingHeardConfirmation;
    if (pendingHeard != null) {
      final reply = finalTranscript
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[\s.!?~]'), '');
      const affirmatives = {
        '네',
        '예',
        '응',
        '맞아',
        '맞아요',
        '맞습니다',
        'yes',
        'yeah',
        'right',
        'correct'
      };
      const bareNegatives = {
        '아니',
        '아니요',
        '아닙니다',
        'no',
        'nope',
      };
      _pendingHeardConfirmation = null;
      if (affirmatives.contains(reply)) {
        // 제대로 들은 게 맞았다 → 보류해 둔 원래 발화를 그때부터 이어서 처리
        _heardConfirmationAttempts = 0;
        _log('[HEARD-CONFIRM]', 'affirmed → 보류 발화 재개');
        return _processRelayPipeline(
          pendingHeard,
          isCorrectionRetry: isCorrectionRetry,
          understandingConfirmed: true,
        );
      }
      if (bareNegatives.contains(reply)) {
        // 아니라고만 했다 → 보류 발화는 버리고 다시 듣는다
        _heardConfirmationAttempts = 0;
        _log('[HEARD-CONFIRM]', 'denied_without_correction → 재청취');
        await _speakRetryAndListen();
        return;
      }
      // 내용이 담긴 답 → 유저가 다시 설명한 것이므로 이번 발화를 새 발화로 본다
      _log('[HEARD-CONFIRM]', 'corrected_with_content → 새 발화 판정');
    }
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
        if (finalTranscript.length <= 2) {
          _speakRetryAndListen();
        } else {
          _startDeepgramListening();
        }
      }
      return;
    }

    try {
      // ─────────────────────────────────────────────────────
      // STEP 2: HOST 풍선 생성 + 유저 번역 스트리밍
      // ─────────────────────────────────────────────────────
      if (mounted) {
        setState(() {
          _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
          _removeOrphanedHostBubbles(); // AI 응답 없이 중단된 이전 HOST 버블 제거
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
      // User voice follows the lobby My Voice setting; AI remains fixed to nova.
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

      // 🌐 [v3.1] 로비에서 유저가 선택한 타겟 언어로 번역
      final String targetLangName = FFAppState().targetLang.isNotEmpty
          ? FFAppState().targetLang
          : 'English';

      final userStream = RoleplayBrain.streamUserTranslation(
        apiKey: _openAiKey,
        textOriginal: finalTranscript,
        targetLang: targetLangName,
        contextStr: contextStr,
        userRole: _scenarioUserRole,
        situation: _scenarioSituation,
        isCorrectionRetry: isCorrectionRetry,
        disableHeardConfirmation: understandingConfirmed,
      );

      bool evaporated = false;
      bool clarified = false; // 주어/목적어 모호 → AI 되묻기
      bool corrected = false; // 유저가 AI의 오해를 정정 → 직전 교환 삭제 후 재처리
      bool misheard = false; // 잘못 들었다는 불만만 있음 → 직전 교환 삭제 후 재청취
      bool dissatisfiedReply = false; // AI 직전 응답 불만 → 응답만 재생성
      bool heardConfirmation = false; // 전사가 깨짐 → 글로 적기 전에 말로 확인
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

        // 되묻기 감지: 주어/목적어 모호 → AI In-Character 되묻기
        //   되묻는 문장 전체를 받아야 하므로 break 하지 않는다. 여기서 끊으면
        //   질문이 잘린 채로 TTS를 타서 "Who are you"에서 끝나 버린다.
        if (!clarified && userTargetText.contains("[CLARIFY]")) {
          clarified = true;
          _log('❓ [CLARIFY]', '되묻기 감지 → 스트림 완료 후 처리 예정');
        }
        // 👂 [HEARD-CONFIRM] 전사가 깨져 뜻을 복원할 수 없음
        //   → 추측 번역 금지. 화면에 적기 전에 말로 먼저 확인한다.
        if (!heardConfirmation &&
            (userTargetText.contains("[HEARD_CONFIRM]") ||
                userTargetText.trimLeft().startsWith('제가 잘못 들었나요?'))) {
          heardConfirmation = true;
          _log('[HEARD-CONFIRM]', '단어 확인 필요 → 스트림 완료 후 처리 예정');
        }
        // 되묻기/확인 중에는 유저 버블에 아무것도 쓰지 않는다. 이 텍스트는
        // 유저가 한 말이 아니라 AI의 되물음이라 그대로 적으면 오해를 만든다.
        if (mounted && !clarified && !heardConfirmation)
          setState(() =>
              _localMessages[hostIndex]['target'] = _cleanText(userTargetText));
        _scrollToCurrentTop(hostIndex);

        // [USER-FULL-TTS] no chunk TTS during user translation streaming.
        // Text still streams to the screen through setState above.
      }

      if (evaporated) {
        if (mounted)
          setState(
              () => _localMessages.removeWhere((m) => m['role'] == 'HOST'));
        if (_isConversationActive && _turnCounter == currentTurnId)
          _speakRetryAndListen();
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
          if (_localMessages.isNotEmpty) _scrollToBottom();
        }
        _ttsQueueManager.stop();
        _ttsQueueManager.setUserTurn(false);
        // 정정된 발화로 재처리 (재진입이므로 [CORRECTION] 재감지 안 함)
        await _deleteLastExchangeFromHistory();
        _processRelayPipeline(finalTranscript, isCorrectionRetry: true);
        return;
      }

      // 👂 [MISHEARD] 잘못 들었다는 불만만 있음 → 직전 교환 삭제 후 재청취
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
        _ttsQueueManager.stop();
        _ttsQueueManager.setUserTurn(false);
        _ttsQueueManager.setAiPaused(false);
        await _deleteLastExchangeFromHistory();
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
        if (mounted && _isConversationActive) _startDeepgramListening();
        return;
      }

      // 🟣 [DISSATISFIED] AI 직전 응답 불만 → 직전 SYSTEM만 제거하고 같은 발화로 재생성
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
          _speakRetryAndListen();
          return;
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
        final regenStream = RoleplayBrain.streamRoleplayResponse(
          apiKey: _openAiKey,
          userTargetText: lastUserTarget,
          contextStr: regenContextStr,
          situation: _scenarioSituation,
          aiRole: _scenarioAiRole,
          userRole: _scenarioUserRole,
          myTarget: targetLangName,
          rejectedReply: rejectedReply,
        );
        await for (final chunk in regenStream) {
          regenText += chunk;
          if (regenText.contains('[RETRY]')) break;
          if (mounted && regenAiIndex < _localMessages.length) {
            setState(() => _localMessages[regenAiIndex]['target'] = regenText);
          }
        }
        if (regenText.contains('[RETRY]') || regenText.trim().isEmpty) {
          if (mounted && regenAiIndex < _localMessages.length) {
            setState(() => _localMessages.removeAt(regenAiIndex));
          }
          _speakRetryAndListen();
          return;
        }
        final String regenClean = _cleanText(regenText.trim());
        if (regenClean.isNotEmpty) regenTts.addText(regenClean);
        RoleplayBrain.generateCleanOriginal(
                apiKey: _openAiKey, englishText: regenText)
            .then((cleanKorean) {
          if (mounted && _localMessages.length > regenAiIndex) {
            setState(
                () => _localMessages[regenAiIndex]['original'] = cleanKorean);
          }
        });
        int regenTicks = 0;
        while ((regenPhraseTts.pendingRequests > 0 ||
                regenTts.pendingRequests > 0 ||
                _ttsQueueManager.isBusy) &&
            mounted) {
          await Future.delayed(const Duration(milliseconds: 50));
          if (++regenTicks > 400) break;
        }
        if (mounted && _isConversationActive) _startDeepgramListening();
        return;
      }

      // ❓ [CLARIFY] 유저 발화 주어/목적어 모호 → In-Character 되묻기 + STT 재시작
      if (clarified) {
        _turnCounter--;
        final clarifyText =
            userTargetText.replaceFirst(RegExp(r'^\[CLARIFY\]\s*'), '').trim();
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length &&
                _localMessages[hostIndex]['role'] == 'HOST')
              _localMessages.removeAt(hostIndex);
            _localMessages.add({
              'role': 'SYSTEM',
              'target': clarifyText,
              'original': '',
              'clarify': true, // 임시 되묻기 버블 — 다음 발화 시 증발 처리
            });
          });
          _scrollToBottom();
        }
        _ttsQueueManager.stop();
        _ttsQueueManager.setUserTurn(false);
        _ttsQueueManager.setAiPaused(false);
        final clarifyTts = ChunkedTtsFetcher(
          _openAiKey,
          _ttsQueueManager,
          'nova',
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

      // 👂 [HEARD-CONFIRM] 전사가 깨져 뜻을 복원할 수 없음
      //   유저 발화를 화면에 적지 않고 보류한 채, 한국어로 먼저 확인만 한다.
      //   추측해서 적어 놓으면 유저는 자기가 하지도 않은 말을 보게 된다.
      if (heardConfirmation) {
        _turnCounter--;
        // 프롬프트가 확인 문장을 통째로 낸 경우와 [HEARD_CONFIRM] 태그 뒤에
        // 의심 단어만 낸 경우 둘 다 받는다.
        final spokenPrompt = userTargetText.trimLeft().startsWith('제가 잘못 들었나요?')
            ? userTargetText.trim().replaceAll(RegExp(r'[\r\n]+'), ' ')
            : '';
        final candidate = spokenPrompt.isNotEmpty
            ? ''
            : userTargetText
                .replaceFirst(RegExp(r'^.*?\[HEARD_CONFIRM\]\s*'), '')
                .trim()
                .replaceAll(RegExp(r'[\r\n]+'), ' ');
        _pendingHeardConfirmation = finalTranscript.trim();
        _heardConfirmationAttempts++;
        // 두 번 되물어도 안 풀리면 단어 확인을 접고 통째로 다시 말해 달라고 한다.
        // 세 번째부터는 되묻기가 대화를 막는 쪽으로 작동하기 때문이다.
        final tooManyAttempts = _heardConfirmationAttempts > 2 ||
            _pendingHeardConfirmation!.isEmpty ||
            (candidate.isEmpty && spokenPrompt.isEmpty);
        final prompt = tooManyAttempts
            ? '죄송해요. 문장을 조금 천천히 다시 말씀해 주세요.'
            : spokenPrompt.isNotEmpty
                ? spokenPrompt
                : "제가 잘못 들었나요? '$candidate'라고 말씀하신 게 맞나요?";
        final promptTarget = tooManyAttempts
            ? 'Sorry. Please say the sentence again a little more slowly.'
            : "Did I hear you correctly? Did you say '$candidate'?";
        if (tooManyAttempts) {
          _pendingHeardConfirmation = null;
          _heardConfirmationAttempts = 0;
        }
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length &&
                _localMessages[hostIndex]['role'] == 'HOST')
              _localMessages.removeAt(hostIndex);
            _localMessages.add({
              'role': 'SYSTEM',
              'target': promptTarget,
              'original': prompt,
              'clarify': true,
            });
          });
          _scrollToBottom();
        }
        _ttsQueueManager.stop();
        _ttsQueueManager.setUserTurn(false);
        _ttsQueueManager.setAiPaused(false);
        // 확인 질문은 한국어로 말한다. 못 알아들었다는 말까지 외국어로 하면
        // 유저가 두 번 헤맨다.
        final confirmTts = ChunkedTtsFetcher(
          _openAiKey,
          _ttsQueueManager,
          _aiVoice,
          language: 'ko',
          isUser: false,
          onLog: _log,
        );
        confirmTts.addText(prompt);
        int confirmTicks = 0;
        while ((confirmTts.pendingRequests > 0 || _ttsQueueManager.isBusy) &&
            mounted) {
          await Future.delayed(const Duration(milliseconds: 50));
          if (++confirmTicks > 200) break;
        }
        if (mounted && _isConversationActive) _startDeepgramListening();
        return;
      }

      // [USER-FULL-TTS] fire the complete translated user sentence once.
      final String fullUserTts = _cleanText(userTargetText.trim());
      if (fullUserTts.isNotEmpty) {
        if (isMeaninglessTtsText(fullUserTts)) {
          _log('🔊 [TTS-SKIP] [USER]', '의미 없는 TTS 조각 skip: "$fullUserTts"');
        } else {
          userTtsFetcher.addText(fullUserTts);
        }
      }

      // 🔧 [v3.7] 유저 통문장 TtsCache 백그라운드 저장 (히스토리 HIT 유도)
      //   - 청크별 캐시만으로는 히스토리에서 통문장 GET이 MISS됨
      //   - fire-and-forget: 유저 재생 흐름과 무관하게 백그라운드 처리
      //   - voice/speed는 히스토리 _playRhythmAudio와 동일하게 "nova", 1.0 고정
      //   - _cleanText 적용: translated_text와 동일한 키로 저장
      _saveUserFullSentenceToCache(_cleanText(userTargetText.trim()));

      // 유저 역번역 (백그라운드, Future 보관 → 저장 시 await)
      final userOriginalFuture = RoleplayBrain.generateCleanOriginal(
          apiKey: _openAiKey, englishText: userTargetText);
      userOriginalFuture.then((cleanKorean) {
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
        // 빈 AI 버블은 스크롤 없음 — 첫 유효 청크 시 _scrollToCurrentTop 호출
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
      hybridTtsPlayer = HybridTtsPlayer(
        apiKey: _openAiKey,
        onLog: _log,
      );
      hybridTtsPlayer.reset();

      String latestContextStr = contextStr.isEmpty
          ? "User: $userTargetText"
          : "$contextStr\nUser: $userTargetText";
      String aiTargetText = "";
      String aiBuffer = "";
      bool firstChunkSentToTTS = false;

      _swOpenAI.reset();
      _swOpenAI.start();
      _swTTS.reset();

      _log('🧠 [PIPE-02]', 'AI 스트림 요청: userText="$userTargetText"');

      final aiStream = RoleplayBrain.streamRoleplayResponse(
        apiKey: _openAiKey,
        userTargetText: userTargetText,
        contextStr: latestContextStr,
        situation: _scenarioSituation,
        aiRole: _scenarioAiRole,
        userRole: _scenarioUserRole,
        myTarget: targetLangName, // 🌐 [v3.1] 유저가 선택한 타겟 언어
      );

      // AI 생성+청킹을 Future로 (유저 재생과 병렬)
      bool aiRetry = false;
      bool _firstAiChunkLogged = false;
      final Future<void> aiGenerationTask = () async {
        await for (String chunk in aiStream) {
          final cleanedChunk = chunk;
          if (cleanedChunk.trim().isEmpty) {
            continue;
          }
          if (!_firstAiChunkLogged) {
            _msGptFirstToken = _swSpeechEnd.elapsedMilliseconds;
            _log('🧠 [PIPE-03]', 'GPT 첫 유효 청크 수신: "$cleanedChunk"');
            _firstAiChunkLogged = true;
            _scrollToBottom();
          }
          if (_swOpenAI.isRunning) _swOpenAI.stop();
          aiTargetText += cleanedChunk;
          aiBuffer += cleanedChunk;

          // [RETRY] 신호 감지 — 발음 불명 또는 문맥 이상
          if (aiTargetText.contains('[RETRY]')) {
            aiRetry = true;
            _log('🔁 [RETRY-DET]', '[RETRY] 감지 → 재청취 모드');
            break;
          }

          if (mounted && !_ttsQueueManager.aiPaused) {
            setState(() => _localMessages[aiIndex]['target'] = aiTargetText);
            _scrollToBottomThrottled();
          }

          // 하이브리드: 첫 구두점 OR 5단어 도달 시 1회만 firstChunk 즉시 발사
          // Rollback: hybridTtsPlayer 제거 후 aiTtsFetcher.addText(toSpeak) 복원
          if (!hybridTtsPlayer.firstChunkFired) {
            final cutIdx =
                hybridTtsPlayer.onChunk(aiBuffer, aiTtsFetcher, _swSpeechEnd);
            if (cutIdx >= 0) {
              aiBuffer = aiBuffer.substring(cutIdx);
              if (!firstChunkSentToTTS) {
                _swTTS.start();
                firstChunkSentToTTS = true;
              }
            }
          }
          // 이후 청크는 aiBuffer에 누적만 — onStreamEnd에서 remainder 처리
        }
        _msGptStreamEnd = _swSpeechEnd.elapsedMilliseconds;
        // AI remainder TTS 큐 적재 — 유저 TTS 재생과 병렬로 준비 (실제 재생은 setAiPaused(false) 후)
        if (!aiRetry && aiTargetText.trim().isNotEmpty) {
          await hybridTtsPlayer.onStreamEnd(
            fullSentence: _cleanText(aiTargetText.trim()),
            remainderBuffer: aiBuffer,
            fetcher: aiTtsFetcher,
            swSpeechEnd: _swSpeechEnd,
          );
          _log('🧠 [PIPE-08A]',
              'AI stream end + remainder queued. pending=${aiTtsFetcher.pendingRequests}');
        }
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
      // [v3.6] PIPE-07 시점: 버퍼된 AI 텍스트 일괄 표시
      if (mounted && aiTargetText.isNotEmpty) {
        setState(() => _localMessages[aiIndex]['target'] = aiTargetText);
        _scrollToBottom();
      }

      // AI 역번역 (백그라운드, Future 보관 → 저장 시 await)
      final aiOriginalFuture = RoleplayBrain.generateCleanOriginal(
          apiKey: _openAiKey, englishText: aiTargetText);
      aiOriginalFuture.then((cleanKorean) {
        if (mounted && _localMessages.length > aiIndex) {
          setState(() => _localMessages[aiIndex]['original'] = cleanKorean);
          _log('🔤 [BACK-TRANS]', 'AI 역번역 완료 → UI 반영');
        }
      });

      await aiGenerationTask;
      _log('🧠 [PIPE-08]',
          'aiGenerationTask 완료. AI pending=${aiTtsFetcher.pendingRequests}');
      // [PIPE-08A] onStreamEnd는 aiGenerationTask 내부에서 완료됨 (중복 호출 없음)
      if (!aiRetry && aiTargetText.trim().isNotEmpty) {
        if (mounted) {
          setState(() {
            _debugResult += '\nGPT 첫 토큰: ${_msGptFirstToken}ms'
                '\nGPT 스트림 종료: ${_msGptStreamEnd}ms'
                '\n첫 청크 발사: ${hybridTtsPlayer.lastFirstChunkMs}ms'
                '\n통문장 저장: ${hybridTtsPlayer.lastCacheSaveMs}ms'
                ' | Cache: ${hybridTtsPlayer.lastCacheHit ? "HIT" : "MISS"}';
          });
        }
      }

      // ─────────────────────────────────────────────────────
      // [RETRY] 처리 — AI 버블 제거 후 음성으로만 재청취 요청
      // ─────────────────────────────────────────────────────
      if (aiRetry) {
        _ttsQueueManager.stop();
        if (mounted) {
          setState(() {
            if (aiIndex < _localMessages.length)
              _localMessages.removeAt(aiIndex);
          });
        }
        _log('🔁 [RETRY-ACT]', 'AI 버블 제거 + 재청취 TTS 발화');
        if (_isConversationActive && _turnCounter == currentTurnId) {
          _speakRetryAndListen();
        }
        return;
      }

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
      // STEP 7: 역번역 완료 대기 후 Firestore 저장
      // ─────────────────────────────────────────────────────
      final userOriginal = await userOriginalFuture;
      final aiOriginal = await aiOriginalFuture;
      final hostLine = {
        'role': 'HOST',
        'original_text': userOriginal,
        'translated_text': _cleanText(userTargetText),
      };
      final systemLine = {
        'role': 'SYSTEM',
        'original_text': aiOriginal,
        'translated_text': _cleanText(aiTargetText),
      };
      _saveTurnToFirestore([hostLine, systemLine]);
      await _saveHistoryMessages([hostLine, systemLine]);
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

  // 🔧 [v3.7] 유저 통문장 TtsCache 백그라운드 저장 헬퍼
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
          'model': 'gpt-4o-mini-tts',
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
          'mode': 'roleplay',
          'scenario_info': {
            'keyword': _scenarioKeyword,
            'situation': _scenarioSituation,
            'ai_role': _scenarioAiRole,
            'user_role': _scenarioUserRole,
          },
          'scenario_situation': _scenarioSituation,
          'scenario_keyword': _scenarioKeyword,
          'user_role': _scenarioUserRole,
          'ai_role': _scenarioAiRole,
          'user_label': _roleplayUserLabel,
          'partner_label': _roleplayPartnerLabel,
          'created_at': FieldValue.serverTimestamp(),
          'transcript': chatLines,
        });
        _sessionDocId = newSession.id;
        BillingTicker.instance.setSessionIdentifiers(
          sessionDocId: _sessionDocId,
          roomId: _myHistoryRef?.id,
        );
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
      final newRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('chat_history')
          .doc();
      await newRef.set({
        'created_at': FieldValue.serverTimestamp(),
        'room_name': "Roleplay Mode",
        'mode': 'roleplay', // 🆕 [ROUTER-FIX] 라우터가 Step Expand로 오인 방지
        'scenario_situation': _scenarioSituation,
        'scenario_keyword': _scenarioKeyword,
        'user_role': _scenarioUserRole,
        'ai_role': _scenarioAiRole,
        'user_label': _roleplayUserLabel,
        'partner_label': _roleplayPartnerLabel,
        'is_pinned': false,
        'msg_count': 0,
        // 세션 생성 당시 언어 식별값 보존(History 동일 언어 판정용)
        'native_lang': 'Korean',
        'target_lang': FFAppState().targetLang,
      });
      _myHistoryRef = newRef;
      BillingTicker.instance.setSessionIdentifiers(
        sessionDocId: _sessionDocId,
        roomId: _myHistoryRef?.id,
      );
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
      final List<String> savedIds = [];
      for (final line in chatLines) {
        final original = (line['original_text'] ?? '').toString().trim();
        if (original.isEmpty) continue;
        final addedRef = await _myHistoryRef!.collection('messages').add({
          'role': line['role'] ?? '',
          // Target은 History 진입 시 gpt-4o-mini로 최초 1회 생성한다.
          'original_text': original,
          'created_at': FieldValue.serverTimestamp(),
        });
        savedIds.add(addedRef.id);
      }
      if (savedIds.isNotEmpty) {
        _lastExchangeMsgIds = List<String>.from(savedIds);
      }

      // 🔧 [핵심] 턴마다 msg_count/last_message 업데이트
      final lastOriginal = chatLines
          .map((l) => (l['original_text'] ?? '').toString().trim())
          .lastWhere((t) => t.isNotEmpty, orElse: () => '');
      if (lastOriginal.isNotEmpty) {
        await _myHistoryRef!.update({
          'msg_count': FieldValue.increment(chatLines.length),
          'last_message': lastOriginal,
          'last_active': FieldValue.serverTimestamp(),
        });
        _log('💾 [HIST-UPD]',
            'msg_count+${chatLines.length}, korean_text_only=true');
      }
    } catch (e) {
      _log('❌ [HIST-ERR]', 'chat_history 저장 실패: $e');
    }
  }

  /// 뒤로가기 시: 빈 방 폭파 or last_message 업데이트 후 나가기
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

          final userLabel = _roleplayUserLabel;
          final partnerLabel = _roleplayPartnerLabel;

          await _myHistoryRef!.update({
            'last_message': lastText,
            'last_message_time': FieldValue.serverTimestamp(),
            'msg_count': _localMessages.length,
            'last_active': FieldValue.serverTimestamp(),
            'chat_json': jsonEncode(_localMessages),
            'is_completed': false,
            'mode': 'roleplay',
            'scenario_situation': _scenarioSituation,
            'scenario_keyword': _scenarioKeyword,
            'user_role': _scenarioUserRole,
            'ai_role': _scenarioAiRole,
            'user_label': userLabel,
            'partner_label': partnerLabel,
          });
          _log('💾 [HIST-UPD]', 'last_message 저장');
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
  void _showScenarioTalkGuide() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.menu_book_rounded, color: Color(0xFF4ADE80)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Scenario Talk 사용설명서',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            '실제 상황처럼 역할을 나누어 AI와 대화하는 모드입니다.\n\n'
            '시작 전 시나리오와 AI·사용자 역할을 확인하거나 직접 수정할 수 있습니다.\n\n'
            'Start 버튼을 누른 뒤, 화면에 표시된 역할의 인물처럼 자연스럽게 말해 보세요. AI도 지정된 역할을 유지하며 대화합니다.',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.55),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('확인', style: TextStyle(color: Color(0xFF4ADE80))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewPadding.bottom == 0
        ? 24.0
        : MediaQuery.of(context).viewPadding.bottom + 8.0;
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _handleAutoSaveAndExit();
      },
      child: Container(
        color: const Color(0xFF121212),
        child: SafeArea(
          child: Column(children: [
            _buildTopBar(),
            // 🗑️ 상황 박스 제거. 상황은 입장 전 설정 페이지에서 확인하고
            //   들어오므로 방 안에서 다시 띄울 필요가 없다.
            Expanded(
              child: Stack(
                children: [
                  _buildChatList(),
                  _buildIdleOverlay(),
                ],
              ),
            ),
            _buildControlArea(bottomPad),
          ]),
        ),
      ),
    );
  }

  // 🗑️ 방 안 시나리오 UI는 모두 제거했다. 초록 상황 박스(_buildScenarioTitle),
  //    빈 방에 떠 있던 시작 카드(_buildTopControls), 그 카드로만 들어가던
  //    수정 시트(_showSituationInputSheet/_inputField)까지 함께 없앴다.
  //    상황과 두 역할은 입장 전 Scenario Talk Settings 페이지에서 정한다.
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: _handleAutoSaveAndExit, // 🔧 [히스토리] AutoSave 연결
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 72,
              height: 56,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 8),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white70),
            ),
          ),
          // 📏 아이콘 셋은 고정 크기로 두고, 폭이 모자랄 때는 잔여시간 칩만
          //   줄어들게 한다. 예전에는 아이콘까지 한 FittedBox로 묶어서
          //   시간 글자가 길어지면 아이콘이 통째로 작아졌다. (Circle Talk과 동일)
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.menu_book_rounded,
                      color: Color(0xFF4ADE80), size: 23),
                  tooltip: 'Scenario Talk 사용설명서',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                  onPressed: _showScenarioTalkGuide,
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
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
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
                  tooltip: _showOriginal ? '원문 숨기기' : '원문 함께 보기',
                  onPressed: () =>
                      setState(() => _showOriginal = !_showOriginal),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                const SizedBox(width: 4),
                // [v3.6] 잔여시간 표시 + 길게 누르면 로그 (개발자용)
                Flexible(
                  child: GestureDetector(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                          color: const Color(0xFF2563EB),
                          borderRadius: BorderRadius.circular(20)),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          ValueListenableBuilder<int>(
                            valueListenable:
                                BillingTicker.instance.billingState,
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
                              final int s = (FFAppState().remainingTime)
                                  .toInt()
                                  .clamp(0, 999999);
                              final int h = s ~/ 3600;
                              final int m = (s % 3600) ~/ 60;
                              return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
                            }(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatList() {
    final double bottomPad = MediaQuery.of(context).size.height * 0.55;
    return ListView.builder(
      reverse: true,
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(16, bottomPad, 16, 12),
      itemCount: _localMessages.length,
      itemBuilder: (context, idx) {
        final realIdx = _localMessages.length - 1 - idx;
        _itemKeys[realIdx] ??= GlobalKey();
        return Container(
            key: _itemKeys[realIdx],
            child: _buildTextBlock(_localMessages[realIdx]));
      },
    );
  }

  Widget _buildTextBlock(Map<String, dynamic> msg) {
    final role = (msg['role'] ?? '').toString();
    final bool isHost = role == 'HOST' || role == 'HOST_TEMP';
    final rawTarget = (msg['target'] ?? '').toString();
    final bool isThinking = (role == 'SYSTEM' && rawTarget.isEmpty) ||
        (role == 'HOST_TEMP' && rawTarget == '...') ||
        (role == 'HOST' && rawTarget.isEmpty);
    final String displayTarget = isThinking ? '...' : rawTarget;
    if (displayTarget.isEmpty) return const SizedBox.shrink();

    // 말풍선
    final Widget bubble = ConstrainedBox(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.73),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isHost
              ? const Color(0xFF1E293B)
              : const Color(0xFF22C55E).withValues(alpha: 0.13),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isHost ? 16 : 4),
            bottomRight: Radius.circular(isHost ? 4 : 16),
          ),
          border: Border.all(
            color: isHost
                ? const Color(0xFF3B82F6).withValues(alpha: 0.18)
                : const Color(0xFF22C55E).withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isHost ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(displayTarget,
                textAlign: isHost ? TextAlign.right : TextAlign.left,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16 * _fontScale,
                    fontWeight: FontWeight.bold,
                    height: 1.4)),
            if (_showOriginal &&
                !(FFAppState().nativeLang.isNotEmpty &&
                    FFAppState().nativeLang == FFAppState().targetLang) &&
                !isThinking &&
                msg['original'] != null &&
                msg['original'].toString().isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(msg['original'],
                  textAlign: isHost ? TextAlign.right : TextAlign.left,
                  style:
                      TextStyle(color: Colors.grey, fontSize: 12 * _fontScale))
            ],
          ],
        ),
      ),
    );

    final String speakerLabel =
        isHost ? _roleplayUserLabel : _roleplayPartnerLabel;
    final Widget messageBlock = ConstrainedBox(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.73),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            isHost ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              speakerLabel,
              textAlign: isHost ? TextAlign.right : TextAlign.left,
              softWrap: true,
              style: TextStyle(
                color:
                    isHost ? const Color(0xFF93C5FD) : const Color(0xFF86EFAC),
                fontSize: 12 * _fontScale,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(height: 5),
          bubble,
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment:
            isHost ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [messageBlock],
      ),
    );
  }

  Widget _buildControlArea(double bp) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 4, 24, bp),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 📏 폰 글꼴을 키워 둔 기기에서 이 제목이 커지면서 Start 버튼을
              //   밀어내 줄 오른쪽이 잘렸다. 버튼 자리를 먼저 주고 제목은
              //   남는 폭에 맞춰 줄어들게 한다.
              const Flexible(
                child: Text("Scenario Talk",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ),
              // Start 버튼은 없앴다. 시나리오가 정해지면 AI가 알아서 먼저
              // 말을 건다(_maybeAutoStartScenario). 버튼을 한 번 더 누르게
              // 하는 것은 "첫 소리는 AI부터"라는 대화 설계와 어긋난다.
              if (_isAiOpenerPlaying)
                // AI 첫 발화 재생 중
                const SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Color(0xFF4ADE80),
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                )
              else
                // 대화 중 on/off 토글
                GestureDetector(
                  onTap: () {
                    if (_deepgramKey.isEmpty) return;
                    _resetIdleTimer();
                    setState(
                        () => _isConversationActive = !_isConversationActive);
                    if (_isConversationActive) {
                      _startDeepgramListening();
                    } else {
                      _stopEverything();
                    }
                  },
                  child: Container(
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
  final void Function(String, {bool speechFinal}) onTurnEnded;
  final Function(String) onError;
  final Function(int)? onReconnecting; // 재연결 시도 알림 (선택적)
  final VoidCallback? onGaveUp; // 재연결 포기 알림 (선택적)
  final void Function(String tag, String msg)? onLog; // 🔬 [v3.1] 로그 훅
  final void Function(Uint8List bytes)? onAudioData;

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
        '&utterance_end_ms=1200' // 🔧 [v3.4] 1000→1200ms: UtteranceEnd도 여유있게
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
              onAudioData?.call(Uint8List.fromList(data));
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
          onTurnEnded(finalText, speechFinal: false);
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
          onTurnEnded(finalText, speechFinal: true);
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
        BillingTicker.instance.resumeFromActivity(_currentChunkIsUser
            ? 'roleplay_user_tts_start'
            : 'roleplay_ai_tts_start');
        await _player.play(BytesSource(bytes));
        await _completer!.future.timeout(estimatedDuration);
        BillingTicker.instance.resumeFromActivity(_currentChunkIsUser
            ? 'roleplay_user_tts_end'
            : 'roleplay_ai_tts_end');
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
  int get pendingRequests => _pendingCount;
  VoidCallback? onAllComplete;

  // 🎤 [BARGE-IN] 취소되면 이미 날아간 요청의 응답이 돌아와도 큐에 넣지 않는다.
  //   audioQueue.stop()만으로는 부족하다. stop()은 그 시점의 큐만 비우고,
  //   뒤늦게 도착한 청크는 addAudio로 재생을 다시 깨워 유저 위에 겹쳐 울린다.
  bool _cancelled = false;
  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _buffer.clear();
  }

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

    // [2단계] API 호출 (타임아웃 사다리 5/8/12초, 최대 3회 시도) — TTS 지연 스파이크 대응
    Uint8List result = Uint8List(0);
    const List<int> timeoutLadderSec = [5, 8, 12];
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
                'model': 'gpt-4o-mini-tts',
                'input': text,
                'voice': voice,
                'speed': 1.0,
                'response_format': 'mp3',
              }),
            )
            .timeout(Duration(seconds: timeoutLadderSec[attempt]));

        if (res.statusCode == 200) {
          result = res.bodyBytes;
          final turnTag = isUser ? 'USER' : 'AI';
          onLog?.call('🔊 [TTS-02]',
              '[$turnTag] API OK (${result.length}B) for "$text"');
          // [3단계] 캐시 저장 (백그라운드)
          TtsCache.put(text, voice, result);
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

    _buffer[id] = result;
    _pendingCount--;
    _pushReady();
    if (_pendingCount == 0) onAllComplete?.call();
  }

  void _pushReady() {
    if (_cancelled) {
      _buffer.clear();
      return;
    }
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

  Future<void> _onUserTurnEnded(String userText,
      {bool speechFinal = false}) async {
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
// 📦 [Box 7-H: HybridTtsPlayer] — 하이브리드 TTS (Roleplay 전용)
// ====================================================================
// 설계 원칙: 첫 구두점 즉시 발사(체감 빠름) + 통문장 캐시 저장(히스토리 통합)
//   → tryFireFirstChunk: 첫 구두점 도달 시 ChunkedTtsFetcher에 1회 발사
//   → onStreamEnd: remainder 순차 발사 + fullSentence TtsCache 저장 (재생 없음)
//   → Rollback: tryFireFirstChunk 제거 후 aiTtsFetcher.addText(toSpeak) 복원
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

  // 첫 구두점 도달 시 1회 호출. firstChunk를 fetcher에 즉시 발사.
  // 반환값: buffer에서 자를 인덱스 (>=0이면 발사됨, -1이면 미발사)
  int tryFireFirstChunk(
      String buffer, ChunkedTtsFetcher fetcher, Stopwatch swSpeechEnd) {
    if (_firstChunkFired) return -1;
    final match = kTtsDelimiterPattern.firstMatch(buffer);
    if (match == null) return -1;

    final text = buffer.substring(0, match.end).trim();
    if (text.isEmpty) return match.end;

    _firstChunkFired = true;
    lastFirstChunkMs = swSpeechEnd.elapsedMilliseconds;
    fetcher.addText(text);
    onLog?.call(
        '[HYB-01]', 'firstChunk fired (${text.length}c) ${lastFirstChunkMs}ms');
    return match.end;
  }

  // [Box 7-H] 조기 발사 보충: 구두점 OR firstChunkMinWords 단어 중 먼저 오는 쪽 발사
  // buffer: 현재까지 누적된 AI 텍스트 버퍼 (외부에서 관리)
  // 반환값: buffer에서 자를 인덱스 (>=0이면 발사됨, -1이면 미발사)
  static const int firstChunkMinWords = 5;

  int onChunk(String buffer, ChunkedTtsFetcher fetcher, Stopwatch swSpeechEnd) {
    if (_firstChunkFired) return -1;

    final punctMatch = kTtsDelimiterPattern.firstMatch(buffer);
    final wordCount =
        buffer.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    if (punctMatch == null && wordCount < firstChunkMinWords) return -1;

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
        '발사(${punctMatch != null ? "구두점" : "5단어"}): "$text" ${lastFirstChunkMs}ms');
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
      // 구두점 없이 스트림 종료 — 전체 텍스트를 지금 발사
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

    // 2. TtsCache 저장은 백그라운드 fire-and-forget으로 분리한다.
    final sentence = fullSentence.trim();
    if (sentence.isEmpty) return;
    unawaited(_cacheFullSentenceInBackground(sentence));
  }

  // _cacheFullSentenceInBackground: 통문장 캐시 저장을 await하지 않는 백그라운드 작업.
  Future<void> _cacheFullSentenceInBackground(String fullSentence) async {
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
      // Longer timeout + one retry for long full-sentence cache writes.
      Uint8List? bytes;
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
                  'model': 'gpt-4o-mini-tts',
                  'input': fullSentence,
                  'voice': voice,
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
        await TtsCache.put(fullSentence, voice, bytes);
        lastCacheSaveMs = sw.elapsedMilliseconds;
        onLog?.call(
            '[HYB-04-SAVED]', '${lastCacheSaveMs}ms (${bytes.length}B)');
      } else {
        onLog?.call('[HYB-ERR]', 'TtsCache 저장 2회 실패 후 스킵');
      }
      sw.stop();
    } catch (e) {
      onLog?.call('[HYB-ERR]', 'TtsCache 저장 실패: $e');
    }
  }
}

// ====================================================================
// 🧠 [Box 7-1] RoleplayBrain v3 — 롤플레이 모드 전용 AI 뇌
// ====================================================================
class RoleplayBrain {
  // ==================================================================
  // 📦 [OPENING] 장면 첫 대사 — gpt-4o-mini가 한국어 한 문장으로 만든다.
  // ------------------------------------------------------------------
  // Realtime이 만들던 자리다. Realtime은 시크릿 발급이 막히면 첫 마디가
  // 통째로 사라져 대화가 시작조차 안 됐다. 짧은 한 줄이라 스트리밍도 필요 없다.
  // ==================================================================
  static Future<String> generateKoreanOpener({
    required String apiKey,
    required String situation,
    required String aiRole,
    required String userRole,
  }) async {
    if (apiKey.isEmpty) return '';
    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'model': 'gpt-4o-mini',
              'temperature': 0.8,
              'max_tokens': 80,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      '''You are "$aiRole" inside this scene, speaking to "$userRole".
Situation: $situation

Speak exactly ONE short opening line in Korean — the line this character would really say first, right now, inside this situation.
Never act as a host, guide, or narrator. Do not greet the user to a roleplay, explain the setup, or invite them to start.
Do not use English, do not describe the scene, do not use quotation marks or emoji.
Natural spoken Korean 해요체 존댓말, one sentence. Never use 반말.
Return only the line itself.'''
                },
                {
                  'role': 'user',
                  'content': 'Speak your opening line now.',
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return '';
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final text =
          (body['choices']?[0]?['message']?['content'] as String?)?.trim() ??
              '';
      return text.replaceAll(RegExp(r'^["“”\s]+|["“”\s]+$'), '');
    } catch (_) {
      return '';
    } finally {
      client.close();
    }
  }

  static Future<String> generateKoreanTurn({
    required String apiKey,
    required String instructions,
    required String userText,
    required String recentConversation,
  }) async {
    if (apiKey.isEmpty || userText.trim().isEmpty) return '';
    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: <String, String>{
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(<String, dynamic>{
              'model': 'gpt-4o-mini',
              'temperature': 0.75,
              'max_tokens': 120,
              'messages': <Map<String, String>>[
                <String, String>{'role': 'system', 'content': instructions},
                if (recentConversation.trim().isNotEmpty)
                  <String, String>{
                    'role': 'system',
                    'content':
                        'Recent scene dialogue (continue it consistently):\n$recentConversation',
                  },
                <String, String>{
                  'role': 'user',
                  'content': userText.trim(),
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return '';
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final text =
          (body['choices']?[0]?['message']?['content'] as String?)?.trim() ??
              '';
      return text.replaceAll(RegExp(r'^["“”\s]+|["“”\s]+$'), '');
    } catch (_) {
      return '';
    } finally {
      client.close();
    }
  }

  // 🆕 [EXPAND-EXIT] 대화 전체(AI+유저) → 종합 확장 문장 1개 (의미단위 ~5개, 문법 연결)
  static Future<String?> generateExpandedFromConversation(
    String apiKey,
    String transcript, {
    String userLabel = 'the user',
    String partnerLabel = 'the roleplay partner',
    String situation = '',
  }) async {
    if (apiKey.isEmpty || transcript.trim().isEmpty) return null;
    try {
      final safeUserLabel =
          userLabel.trim().isNotEmpty ? userLabel.trim() : 'the user';
      final safePartnerLabel = partnerLabel.trim().isNotEmpty
          ? partnerLabel.trim()
          : 'the roleplay partner';
      final situationLine = situation.trim().isNotEmpty
          ? 'Roleplay situation: ${situation.trim()}. Use it only if supported by the transcript.'
          : 'Use only the situation supported by the transcript.';
      final sysPrompt = """You are an English speaking coach.
You are given a short roleplay conversation transcript.
This is a roleplay conversation between $safeUserLabel and $safePartnerLabel.
$safePartnerLabel is the role being played, not AI.
$situationLine
Your job: compose ONE long, natural English sentence that synthesizes the overall
content and gist of the WHOLE conversation.

[RULES]
- Never call $safePartnerLabel AI, assistant, chatbot, or bot.
- If the partner must be mentioned, use $safePartnerLabel or a natural role phrase.
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
      debugPrint("[RoleplayBrain.generateExpandedFromConversation] $e");
      return null;
    }
  }

  // 🆕 [EXPAND-EXIT] 확장 문장 → 쉽고 세련된 한 문장 (Polished)
  static Future<String?> polishSentence(
    String apiKey,
    String originalSentence, {
    String partnerLabel = 'the roleplay partner',
  }) async {
    if (apiKey.isEmpty || originalSentence.trim().isEmpty) return null;
    try {
      final safePartnerLabel = partnerLabel.trim().isNotEmpty
          ? partnerLabel.trim()
          : 'the roleplay partner';
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
- Do not replace $safePartnerLabel with AI, assistant, chatbot, or bot.

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
      debugPrint("[RoleplayBrain.polishSentence] $e");
      return originalSentence;
    }
  }

  // 📋 [200개 기초 상황 — 카테고리 5종 × 40개] (v4 추가)
  /// 회원별 시나리오 순회 커서 키. 뒤에 uid를 붙여 저장한다.
  /// 기기 로컬(SharedPreferences)이라 앱을 지우거나 기기를 바꾸면 0부터
  /// 다시 시작한다. 기기 간 이어보기가 필요해지면 Firestore로 옮긴다.
  static const String _scenarioCursorPrefix = 'roleplay_scenario_cursor_';

  // 🗣️ 일상 100개 — 평범한 하루에 실제로 일어나는 두 사람의 대화.
  //   예전 목록은 200개가 전부 사고·응급 상황이라 "평범한 장면" 지시와
  //   정면으로 부딪혔다. 그래서 절반을 일상으로 갈아 끼웠다.
  static const List<String> _everydaySituations100 = [
    // ── 카페_식당 (12개) ──
    '카페에서 음료 고르기', '커피 쿠폰 사용 문의', '테이크아웃 포장 요청', '식당 메뉴 추천받기',
    '알레르기 재료 확인', '자리 옮겨도 되는지', '식당 예약 변경 문의', '단체석 있는지 문의',
    '남은 음식 포장 요청', '영업시간 확인하기', '주차 가능한지 묻기', '아이 의자 요청하기',
    // ── 쇼핑 (12개) ──
    '옷 사이즈 교환 문의', '탈의실 위치 묻기', '다른 색상 있는지', '세탁 방법 물어보기',
    '선물 포장 요청', '영수증 재발행 요청', '할인 기간 문의', '재고 확인 요청',
    '온라인 주문 매장 수령', '신발 발볼 상담', '화장품 색상 추천', '멤버십 적립 문의',
    // ── 은행_관공서 (10개) ──
    '은행 계좌 개설 문의', '체크카드 재발급 신청', '공과금 납부 방법', '주민등록등본 발급',
    '환전 수수료 문의', '적금 상품 상담', '인터넷뱅킹 등록', '전입신고 절차 문의',
    '여권 갱신 접수', '민원 서류 작성 도움',
    // ── 병원_약국 (8개) ──
    '감기 증상 진료 접수', '처방약 복용법 문의', '건강검진 예약하기', '진료 시간 변경 요청',
    '치과 스케일링 예약', '약 부작용 문의', '진단서 발급 요청', '예방접종 상담',
    // ── 회사_업무 (14개) ──
    '회의 시간 조율하기', '점심 메뉴 정하기', '휴가 일정 상의', '자료 공유 요청',
    '프린터 사용법 묻기', '신입에게 업무 안내', '외근 일정 보고', '회식 장소 정하기',
    '택배 수령 부탁', '자리 비운 사이 메모', '커피 사다 달라 부탁', '퇴근 시간 확인',
    '업무 인수인계 설명', '재택근무 신청 문의',
    // ── 동호회_운동 (10개) ──
    '헬스장 등록 상담', '운동 기구 사용법', 'PT 일정 조정', '축구 동호회 가입 문의',
    '배드민턴 라켓 추천', '수영 강습 등록', '요가 수업 시간 문의', '러닝 코스 추천받기',
    '동호회 회비 문의', '경기 일정 확인',
    // ── 동네_생활 (12개) ──
    '택배 반송 문의', '세탁소 얼룩 제거 문의', '미용실 머리 상담', '이사 견적 문의',
    '인터넷 설치 예약', '에어컨 청소 예약', '반려동물 미용 예약', '자전거 수리 맡기기',
    '열쇠 복사 요청', '옆집에 인사하기', '분리수거 방법 묻기', '아파트 주차 등록',
    // ── 교통_여행 (10개) ──
    '기차표 시간 변경', '버스 노선 물어보기', '택시에서 목적지 안내', '호텔 체크인 시간 문의',
    '렌터카 반납 장소 확인', '지하철 환승 묻기', '항공권 좌석 지정', '수하물 규정 문의',
    '관광지 가는 길 묻기', '숙소 조식 시간 문의',
    // ── 교육_기타 (12개) ──
    '학원 상담 받기', '수강 신청 문의', '도서관 대출 연장', '서점에서 책 찾기',
    '아이 학교 상담', '온라인 강의 등록', '자격증 시험 접수', '악기 레슨 문의',
    '사진관 증명사진 촬영', '안경 도수 상담', '휴대폰 요금제 변경', '중고 물건 거래하기',
  ];

  // 🚨 사고·문제 100개 — 기존 200개에서 현실적이고 말이 되는 것만 추렸다.
  //   '실제 유령 공포', '맹수 탈출 비상', '사막 식수 고갈', '샹들리에 추락'처럼
  //   회화 연습으로 쓰기 어려운 항목은 뺐다.
  static const List<String> _troubleSituations100 = [
    // ── 공항_교통 (20개) ──
    '여권 분실 발견함', '캐리어 파손 확인', '입국 거부 위기', '결제 오류 지연',
    '비행기 놓치기 직전', '탑승권 분실함', '탑승 거부 당함', '버스 고장 멈춤',
    '잘못된 티켓 발권', '소매치기 발생', '짐 오인 교환됨', '지갑 두고 내림',
    '막차 취소 고립됨', '부당 요금 요구', '혼유 사고 발생', '차량 타이어 펑크',
    '차량 배터리 방전', '예약 누락 발견', '가방 문 열려있음', '접촉 사고 후 도주',
    // ── 호텔_주거 (20개) ──
    '예약 취소 당함', '온수 안 나옴', '엘리베이터 갇힘', '알레르기 발생',
    '화재 경보 대피', '소지품 도난당함', '숙소 사진과 다름', '미끄러짐 부상',
    '도어락 고장 갇힘', '동파로 누수 발생', '층간소음 시비', '계단 실족 부상',
    '상한 음식 서빙', '차량 파손 발견', '가스 누출 의심', '옷 세탁 중 분실',
    '지하 침수 발생', '택배 분실 항의', '유리창 깨짐', '금고 안 열림',
    // ── 식당_쇼핑 (20개) ──
    '머리카락 나옴', '식중독 증상 발현', '주문 오인 대기', '결제 중복 처리',
    '커피 쏟아 화상', '음식 도중 소진', '바가지 요금 청구', '지갑 소매치기',
    '거스름돈 사기', '물건 파손 변상', '지갑 분실 확인', '유통기한 지남',
    '도난 경보 작동', '낙상 사고 발생', '배달 사고 누락', '주차 시비',
    '신발 도난당함', '변질된 음식 판매', '카트 충돌 부상', '에스컬레이터 낌',
    // ── 병원_공공_업무 (20개) ──
    '의료진 공백 지연', '오진 가능성 확인', '수술 지연 항의', '잇몸 과다 출혈',
    '보이스피싱 의심', '카드 먹통 됨', '중요 택배 분실', '억울한 누명 씀',
    '서류 조작 의심', '비자 발급 거부', '랜섬웨어 감염됨', '면접 서류 분실',
    '세금 폭탄 오류', '노트북 도난당함', '등교 미아 발생', '셔틀버스 사고',
    '암표 사기 당함', '부당해고 구제 신청', '전시 작품 훼손', '집단 감염 의심',
    // ── 레저_운동 (20개) ──
    '산소통 잔량 고갈', '보드 충돌 실신', '실족 고립 조난', '저체온증 발생',
    '충돌 골절 부상', '리프트 공중 멈춤', '타구 사고 부상', '심장마비 환자 발생',
    '바벨 낙하 깔림', '관절 탈구 부상', '스케이트 날 부상', '롤러코스터 멈춤',
    '카트 전복 사고', '낙석 낙하 갇힘', '막배 끊겨 고립', '낙뢰 사고 발생',
    '캠핑카 일산화탄소', '고온 화상 입음', '말에서 추락 부상', '음향 장비 감전',
  ];

  // ==================================================================
  // 📦 [Box 7-1-0] generateDramaticScenario — 드라마/영화 장면 자동 생성
  // ==================================================================
  static Future<Map<String, String>?> generateDramaticScenario(
      String apiKey) async {
    final client = http.Client();
    try {
      // 🎲 [풀 구성] 일상 100 + 사고 100 = 200.
      //   앞 100개는 평범한 하루, 뒤 100개는 사고·문제 대응이다.
      //   인덱스로 갈리므로 프롬프트에서 어느 쪽인지 알 수 있다.
      //   예전 20개 장르 씨앗은 절반이 극적인 사건(불륜 발각, 형사 심문 등)이라
      //   "평범한 장면" 방침과 충돌해서 없앴다.
      final pool = [..._everydaySituations100, ..._troubleSituations100];

      // 🔁 [순차 배분] 예전에는 pool[Random().nextInt(...)]로 매번 새로 뽑았다.
      //   복원추출이라 220개를 다 보기 훨씬 전에 같은 상황이 겹쳤다
      //   (생일 문제: 20번 안에 중복이 날 확률이 이미 절반을 넘는다).
      //   이제 회원마다 고정된 순서를 만들어 커서를 하나씩 밀어, 한 바퀴
      //   220개를 다 돌기 전에는 같은 상황이 두 번 나오지 않는다.
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
      final prefs = await SharedPreferences.getInstance();
      final cursorKey = '$_scenarioCursorPrefix$uid';
      final cursor = prefs.getInt(cursorKey) ?? 0;
      final round = cursor ~/ pool.length; // 몇 바퀴째인지
      // 회원 uid와 바퀴 수로 순서를 섞는다. 회원마다 순서가 다르고,
      // 두 바퀴째부터는 순서까지 새로 섞여 같은 흐름이 반복되지 않는다.
      final order = List<int>.generate(pool.length, (i) => i)
        ..shuffle(Random(uid.hashCode ^ (round * 0x9E3779B9)));
      final pickIndex = order[cursor % pool.length];
      final pick = pool[pickIndex];
      await prefs.setInt(cursorKey, cursor + 1);
      // 앞 100개가 일상, 뒤 100개가 사고. 어느 쪽이냐에 따라 지켜야 할
      // 선이 달라서 프롬프트를 갈라 준다.
      final bool isEveryday = pickIndex < _everydaySituations100.length;

      final systemPrompt = "You are setting up ONE ordinary, everyday scene between TWO people for a spoken roleplay app.\n"
              "\n"
              "OUTPUT: Return ONLY valid JSON, no extra text.\n"
              "{\n"
              '  "situation": "핵심 상황 요약 (10-15 Korean chars, e.g. 카페에서 신메뉴 추천)",\n'
              '  "ai_role": "AI가 맡을 사람 (10자 이내, e.g. 바리스타)",\n'
              '  "user_role": "유저가 맡을 사람 (8자 이내, e.g. 단골 손님)"\n'
              "}\n"
              "\n"
              "RULES:\n"
              // 🙅 인물의 심리·성격은 넣지 않는다. 역할 이름만 준다.
              //   성격을 미리 박아두면 대화가 그 성격을 연기하는 쪽으로
              //   끌려가고, 유저는 평범하게 말하고 싶은데 상대가 과장된다.
              "- ai_role and user_role: the ROLE ONLY — a plain job, position, or relationship noun.\n"
              "  NO personality, NO emotion, NO attitude, NO adjectives.\n"
              "  Good: 바리스타 / 은행 창구 직원 / 옆자리 동료 / 헬스장 트레이너 / 단골 손님\n"
              "  Bad: 친절한 바리스타 / 화난 손님 / 의심 많은 형사 / 지친 동료\n"
              "- The two roles must be people who would plausibly talk to each other in that scene.\n"
              "- situation: concrete and ordinary. Something that happens to normal people on a normal day.\n"
              "  Do NOT make it dramatic, high-stakes, or cinematic. Do NOT name any show or character.\n" +
          // 🔀 [매번 약간 변형] 예전에는 "USE THIS EXACT SITUATION as-is"라
          //   같은 상황이 글자 그대로 반복됐다. 이제 뼈대만 유지하고
          //   이웃한 일상 장면으로 조금씩 옮겨 매번 다르게 만든다.
          '- BASE SITUATION: "$pick"\n'
              '  Keep its core activity, but shift it slightly into a NEARBY variant so it is not identical to the base.\n'
              '  Move one or two of these: the place, the time of day, the errand at hand, or which of the two people needs something.\n' +
          // 🔀 일상 절반과 사고 절반은 지켜야 할 선이 다르다. 한쪽 기준을
          //   양쪽에 다 적용하면 "평범하게 하라"와 "여권을 잃어버렸다"가
          //   서로 부딪혀 모델이 갈피를 못 잡는다.
          (isEveryday
              ? '  The result must still read as an ordinary day. Do NOT escalate it into an accident, a dispute, or an emergency.\n'
                  '  Example — base "카페에서 음료 고르기": 테이크아웃 줄에서 고르기 / 마감 직전 남은 메뉴 묻기 / 쿠폰 쓰며 주문하기.\n'
              : '  This one IS a problem the user has to handle. Keep the problem real, but play it as it would actually happen:\n'
                  '  two ordinary people sorting it out at a counter or on the spot. No melodrama, no shouting, no life-or-death stakes.\n'
                  '  Example — base "여권 분실 발견함": 체크인 줄에서 없는 걸 알아챔 / 분실물 창구에 문의 / 호텔 프런트에 확인 요청.\n') +
          // 🔁 한 바퀴(200개)를 다 돈 회원에게는 변형 폭을 더 넓힌다.
          (round == 0
              ? ''
              : '- REPEAT VISIT: this user has already been through every base situation $round time(s).'
                  ' Push the variation further than usual — change the place and the reason, not just the wording.\n');

      final res = await client
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'model': 'gpt-4o-mini',
              'temperature': 1.1,
              'response_format': {'type': 'json_object'},
              'max_tokens': 150,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {
                  'role': 'user',
                  'content': '지금 바로 JSON 생성해줘.',
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final raw = jsonDecode(utf8.decode(res.bodyBytes))['choices'][0]
                ['message']['content']
            .toString()
            .trim();
        final parsed = jsonDecode(raw);
        return {
          'situation': parsed['situation']?.toString() ?? '',
          'ai_role': parsed['ai_role']?.toString() ?? '',
          'user_role': parsed['user_role']?.toString() ?? '',
        };
      }
    } catch (e) {
      print('generateDramaticScenario Error: $e');
    } finally {
      client.close();
    }
    return null;
  }

  // ==================================================================
  // 📦 [Box 7-1-A] streamUserTranslation — CoT 2단계 번역
  // ==================================================================
  static Stream<String> streamUserTranslation({
    required String apiKey,
    required String textOriginal,
    required String targetLang,
    required String contextStr,
    String userRole = '',
    String situation = '',
    bool isCorrectionRetry = false,
    bool disableHeardConfirmation = false,
  }) async* {
    final client = http.Client();
    try {
      final roleContext = userRole.isNotEmpty
          ? '\nThe user is playing the role of "$userRole"${situation.isNotEmpty ? ' in a "$situation" scenario' : ''}.'
          : '';
      final sysPrompt =
          """You are an expert real-time Korean-to-$targetLang translator for a live roleplay conversation.$roleContext
${isCorrectionRetry ? '''
[CORRECTION RESTATEMENT - ABSOLUTE TOP PRIORITY, applies to THIS input]
This input is the user RE-STATING what they actually meant. The wrong exchange is already deleted.
RULE 1: NEVER output [CORRECTION], [MISHEARD], [DISSATISFIED], or ANY bracket token. Completely IGNORE the [CASE CORRECTION], [CASE MISHEARD], [CASE DISSATISFIED] sections below; they DO NOT apply now.
RULE 2: STRIP all correction framing and output ONLY the actual intended content:
  - lead-ins: 아니 / 아니지 / 내 말은 / 내 말은요 / 그게 아니라 / 내가 말한 건
  - quote-report frames (CRITICAL): "~라고 했어요" / "~라고 했어" / "~라고 말했어요" / "~라고 말했고" / "~라고 한 거예요" / "I said" / "I also said" / "what I said was"
  - When the user reports MULTIPLE quoted statements, merge them into natural connected $targetLang (use "and", commas).
RULE 3: Output natural $targetLang only. No quotation marks around the content unless truly needed.
Examples:
  "아니 내 말은요 당신 잘못이라고요" -> "It's clearly your fault."
  "나는 빨리 구해 주세요라고 했어요 휴지가 없어요라고 말했고" -> "Please rescue me quickly, and there's no toilet paper."
  "아니지 나는 학교에 간다고 했어" -> "I'm going to school."
''' : ''}

Korean is a heavy pro-drop language - subjects, objects, and pronouns are constantly omitted when clear from context.

[CASE CORRECTION] — Check this FIRST, only when the conversation history contains at least one "User:" line.
The user is correcting the AI's misunderstanding or mishearing of their PREVIOUS utterance.
Signs:
- Starts with a correction signal: "아니" / "아니요" / "아 그게 아니라" / "다시" / "내 말은" / "그러니까" / "내가 말한 건" / "라고 했잖아" / "라고 말했어" / "I mean" / "I said" / "what I said was" / "that's not what I said" / "actually" / "no," / "wait,"
- AND the content is clearly a re-statement or clarification of the LAST "User:" line in the history, NOT new information.
- The user is essentially saying "that's not what I said — what I said was X."
${isCorrectionRetry ? 'NOTE: This is a correction RE-PROCESS. Do NOT output [CORRECTION] here; follow the [CORRECTION RESTATEMENT] rule at the top and translate only the core content.' : 'If this is a correction, output EXACTLY: [CORRECTION]  (and nothing else)'}
Do NOT output [CORRECTION] for genuinely NEW information that merely starts with "아니" etc. BUT if the AI's previous turn clearly captured the user's earlier utterance as DIFFERENT content (a wrong word or a wrong topic) and the user is now restating what they actually meant, output [CORRECTION] even when the restatement also reads like a fresh answer. Test: would the user naturally say "that's not what I said"? If yes -> output [CORRECTION].

[CASE MISHEARD] — Check this SECOND, only when the history contains at least one "User:" line.
The user is COMPLAINING that their previous words were misheard or misunderstood, WITHOUT restating what they actually said.
Signs: "내 말이 그런 뜻이 아니야" / "그런 거 아니야" / "내 말은 그게 아니야" / "잘못 들었어" / "잘못 적었어" / "잘못 알아들었어" / "that's not what I meant" / "you misheard me" / "you got my words wrong"
- AND the utterance contains NO restated content (no actual new statement).
If so, output EXACTLY: [MISHEARD]  (and nothing else)
If the complaint INCLUDES the corrected content, use [CORRECTION] instead.

[CASE DISSATISFIED] — Check this THIRD, only when the history contains at least one "AI:" line.
The user is stepping OUT of the roleplay to complain about the AI's LAST reply itself and wants a different one.
Signs: "무슨 대답이 그래" / "무슨 질문이 그래" / "대답이 이상해" / "다른 말 해줘" / "다시 대답해 봐" / "그 대답 별로야" / "say something else" / "that's a weird reply" / "answer again"
More signs (MILD dissatisfaction — these ALSO count when clearly aimed at the AI reply itself, OUT of character): "별로" / "별론데" / "아 그건 좀" / "에이" / "그런 거 말고" / "재미없어" / "이상하네" / "뭐야 그게" / "meh" / "not really" / "hmm, not that one"
Even slight or indirect displeasure aimed at the AI's last reply counts.
Do NOT output this when the user is answering negatively IN CHARACTER (e.g., refusing an offer inside the roleplay is a valid in-character answer).
If so, output EXACTLY: [DISSATISFIED]  (and nothing else)

[TRANSCRIPT CONFIDENCE GUARD — CHECK BEFORE TRANSLATING]
${disableHeardConfirmation ? "The user has explicitly confirmed the previously heard wording. Do NOT ask another hearing-confirmation question for this turn." : """What you receive is NOT typed text. It is speech-recognition output and it can contain misrecognized words. You never hear the audio, so judge the text itself.

Do NOT translate, and do NOT repair it by guessing, when any of these holds:
- The utterance does not hold together as Korean — grammar no speaker would produce, a word that is not a word, or a phrase that breaks off mid-thought.
- A word sits so oddly that the intended meaning cannot be recovered from the scenario and the conversation so far.
- Making it make sense would require you to invent a subject, object, or verb that the context does not supply.

In that case output EXACTLY in Korean: 제가 잘못 들었나요? '<the exact word or short phrase you doubt>'라고 말씀하신 게 맞나요?

This one line is spoken OUT of character on purpose. Checking what you heard is not a scene break — translating something the user never said is.

Being short is NOT by itself a reason to ask — "먼저 시켜놔." is complete and clear. Ask only when the text itself does not hold together. Accents, fillers, and casual grammar are fine; translate those normally.

Never smooth a broken transcript into a plausible sentence. Guessing puts words in the user's mouth and the scene then builds on something they never said."""}

[INTERNAL THINKING - do not output]
Step 1. CONTEXT CHECK: Review conversation history.
Step 2. SUBJECT RESTORATION: The speaker is${userRole.isNotEmpty ? ' a "$userRole"' : ' the user'}. Identify and restore any omitted subject/pronoun from THEIR perspective.
  Use these Korean grammar markers to determine roles:
  - ~이/가 = SUBJECT marker (doer of action): "엄마가 사줬어" → Mom bought it (Mom is subject)
  - ~은/는 = TOPIC marker (often the subject): "나는 갔어" → I went
  - ~한테/에게 = RECIPIENT marker (indirect object): "나한테 줬어" → gave it TO ME
  - ~을/를 = OBJECT marker (thing acted upon): "그걸 봤어" → saw THAT
  - Honorific ~(으)시 attaches to the SUBJECT's verb: "선생님이 오셨어" → The teacher came (teacher is subject, not me)
  - ~해줬어/해주셨어 = someone did something FOR someone else: the person before 가/이 is the doer
Step 3. TRANSLATE: Produce natural $targetLang speech that fits${userRole.isNotEmpty ? ' the "$userRole" role' : ' the user'}.

[COMMON MISTAKES - avoid these]
Korean: "걔가 나한테 전화했어" → CORRECT: He called me. WRONG: I called him.
Korean: "엄마가 용돈 줬어" → CORRECT: Mom gave me allowance. WRONG: I gave mom allowance.
Korean: "선생님이 칭찬해주셨어" → CORRECT: The teacher praised me. WRONG: I praised the teacher.
Korean: "친구가 요즘 바빠서 못 만나" → CORRECT: My friend is busy lately, so I can't meet him. WRONG: I'm busy lately...
The particle before the verb's doer (이/가) is ALWAYS the subject. Never swap subject and object.

[CLARIFICATION GUARD — In-Character]
Before translating, check: is the subject/object clear from the utterance OR resolvable from History?
If clear → proceed with normal translation.
If genuinely ambiguous AND History cannot resolve it → output EXACTLY:
[CLARIFY] <short, in-character clarification question in $targetLang>

The question must sound like the AI's assigned character is asking, not a system message.
Style pool — pick ONE that fits the character's personality and VARY each time:
- Terse: "Who are you talking about?"
- Skeptical: "Who? Be specific."
- Curious: "Oh — who exactly do you mean?"
- Playful: "I'm gonna need a name to work with here!"
- Confirming: "Do you mean [person from history]?"

NEVER output [CLARIFY] if the subject can be inferred from context.
NEVER break character when asking.

[OUTPUT RULES]
- The user IS${userRole.isNotEmpty ? ' a "$userRole"' : ' the user'} — translate their words from THAT perspective only.
- Preserve speech register appropriate for${userRole.isNotEmpty ? ' a "$userRole"' : ' the user'}.
- Insert commas (,) for TTS rhythm.
- Output ONLY the $targetLang translation.
- If input is noise (under 2 meaningful chars) OR is completely unrecognizable gibberish that cannot be interpreted as a human utterance in any language, output EXACTLY: [EVAPORATE]""";

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
        'max_tokens': 120,
        'messages': [
          {'role': 'system', 'content': sysPrompt},
          {
            'role': 'user',
            'content':
                'Conversation so far:\n$contextStr\n\nTranslate: "$textOriginal"',
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
  // 📦 [Box 7-1-B] generateCleanOriginal — 영→한 역번역
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

[절대 규칙 - 문장 누락 금지]
- 원문의 모든 문장을 빠짐없이 번역하세요. 요약/축약/생략 절대 금지.
- 원문이 2문장이면 번역도 반드시 2문장, 3문장이면 3문장.
- 마침표(.) 또는 물음표(?) 단위로 끊어서 각각 번역하세요.

[주어 생략 처리]
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
- 번역문만 출력. 설명/주석/따옴표 없음.
- 원문의 문장 수와 동일하게 출력.
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
    return englishText;
  }

  // ==================================================================
  // 📦 [Box 7-1-C] streamRoleplayResponse — AI 빙의 응답
  // ==================================================================
  static Stream<String> streamRoleplayResponse({
    required String apiKey,
    required String userTargetText,
    required String contextStr,
    required String situation,
    required String aiRole,
    required String userRole,
    required String myTarget,
    String rejectedReply = '',
  }) async* {
    final client = http.Client();
    try {
      final sysPrompt =
          'You are a master actor playing "$aiRole" in a high-immersion dramatic roleplay.\n'
                  '\n'
                  '[SCENARIO]\n'
                  'Situation: $situation\n'
                  'Your role: $aiRole\n'
                  "User's role: $userRole\n"
                  '\n'
                  '[LANGUAGE RULE]\n'
                  '- Respond in $myTarget ONLY. Role names may be Korean but your dialogue is 100% $myTarget.\n'
                  '\n'
                  '[CHARACTER RULES]\n'
                  '- Stay FULLY in character as "$aiRole" at all times. Never break character.\n'
                  '- Respond with the raw emotion, personality, and subtext that "$aiRole" would have in this situation.\n'
                  '- NO greetings, NO meta-comments. Pure in-character dialogue.\n'
                  '- MAXIMUM 2 short sentences. 1 sentence preferred. Under 15 words per sentence.\n'
                  '- Drive the scene forward — pressure, question, or react to force the user to respond.\n'
                  '- If the user\'s input is completely unintelligible (speech recognition error), output EXACTLY: [RETRY]' +
              (rejectedReply.trim().isEmpty
                  ? ''
                  : '\n- IMPORTANT: The user disliked your previous reply: "${rejectedReply.trim()}". Give a COMPLETELY DIFFERENT in-character reply this time — different angle, different wording. Do NOT repeat or rephrase it.');

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
        'max_tokens': 80,
        'messages': [
          {'role': 'system', 'content': sysPrompt},
          {
            'role': 'user',
            'content':
                'Conversation history:\n$contextStr\n\nUser just said: "$userTargetText"\n\nYour brief reply (in character as $aiRole):',
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
  // 📦 [Box 7-1-D] generateAiOpener — AI 첫 발화 생성 (스트리밍)
  // ==================================================================
  // 🎯 [롤플레이 대화 시작 3원칙]
  //
  // 원칙 1. AI가 먼저 말을 시작한다.
  //         유저가 마이크를 누르면 AI가 오프닝 멘트를 먼저 발화하고,
  //         TTS 재생 완료 후 마이크 청취가 시작된다.
  //
  // 원칙 2. 타겟 언어(targetLang)로만 말한다.
  //         ai_role / user_role 이름이 한글로 주어져도
  //         실제 AI 대사는 반드시 targetLang으로만 출력.
  //         한국어 등 모국어를 절대 섞지 않는다.
  //
  // 원칙 3. 해당 역할이 실제 현실에서 가장 먼저 할 법한 자연스러운 말로 시작.
  //         어색한 학습용 인사 X, 그 역할·상황에 딱 맞는 현실적 구어체 O.
  //         (예: 바리스타 → "What can I get for you?",
  //              의사 → "So, what brings you in today?",
  //              트레이너 → "Is this your first session here?")
  static Stream<String> generateAiOpener({
    required String apiKey,
    required String situation,
    required String aiRole,
    required String userRole,
    required String targetLang,
  }) async* {
    final client = http.Client();
    try {
      final sysPrompt =
          'You are a master actor and an English conversation coach playing "$aiRole".\n'
          '\n'
          '[SCENARIO]\n'
          'Situation: $situation\n'
          'Your role: $aiRole\n'
          "The other person's role: $userRole\n"
          '\n'
          '[CORE RULES]\n'
          '1. Start the scene IMMEDIATELY with your first line — no greetings, no meta-commentary.\n'
          '2. Read the emotional tone of the situation: if dramatic, be intense; if everyday, be natural and warm.\n'
          '3. Do NOT mention any drama, movie, or show titles. Keep it real and seamless.\n'
          '4. Your first line must be a natural, in-character statement or question that draws the user into the scene.\n'
          '5. Adopt the exact personality of "$aiRole". Use natural spoken $targetLang — NOT textbook dialogue.\n'
          '6. ONE sentence only. Under 20 words. Maximum immersion, zero filler.\n'
          '\n'
          'Output: ONE natural first line in $targetLang only.';

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
        'temperature': 0.9,
        'max_tokens': 60,
        'messages': [
          {'role': 'system', 'content': sysPrompt},
          {
            'role': 'user',
            'content': 'Speak your opening line as "$aiRole" in $targetLang.',
          },
        ],
      });

      final response =
          await client.send(request).timeout(const Duration(seconds: 15));
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
