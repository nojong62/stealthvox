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
  bool _isConversationActive = false;
  double _fontScale = 1.0;
  bool _showOriginal = true;
  int _turnCounter = 0;
  String? _sessionDocId; // 🔧 [v3 추가] 첫 대화 후 세션 ID (클론 변경 시 null 리셋)
  DocumentReference? _myHistoryRef; // 🔧 [히스토리] chat_history 문서 참조 (Duo 패턴)

  // 🔧 [v3.4 발화 합치기] 유저 더듬거림 대응
  // speech_final 받아도 바로 파이프라인 시작 안 하고 조건부 대기
  // 대기 중 새 발화 오면 합쳐서 처리 (최종 한 덩어리로)
  String _pendingTranscript = ''; // 대기 중인 유저 발화 누적
  Timer? _commitTimer; // "진짜 끝났는지" 확정 타이머
  static const int COMMIT_WAIT_SPEECH_FINAL_MS = 600; // speechFinal=true 시 빠른 응답
  static const int COMMIT_WAIT_UNCERTAIN_MS = 1100; // UtteranceEnd/speechFinal=false 시 여유 대기
  bool _lastTurnWasSpeechFinal = false; // 마지막 onTurnEnded 이벤트 타입 기록

  // 🔬 [v3.1 진단] 화면 로그 뷰어 (팝업에 쌓음)
  final List<String> _debugLogs = [];
  void _log(String tag, String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    final line = '[$ts] $tag $msg';
    print(line);
    _debugLogs.add(line);
    if (_debugLogs.length > 500) {
      _debugLogs.removeRange(0, 50);
    }
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

  // 🎭 롤플레이 시나리오 (AI가 자동 생성, 4필드)
  String _scenarioKeyword = "";
  String _scenarioSituation = "";
  String _scenarioAiRole = "";
  String _scenarioUserRole = "";
  bool _isGeneratingScenario = false;
  bool _isAiOpenerPlaying = false; // AI 첫 발화 재생 중 여부

  // 🚨 긴급 상황 200개 데이터
  List<Map<String, dynamic>> _emergencySituations = [];
  String _selectedEmergencyKeyword = ""; // 유저가 선택한 긴급 상황 키워드
  String _lastRawTranscript = ''; // 정정 감지용 직전 유저 발화 원문

  // 오디오 및 UI
  final List<Map<String, dynamic>> _localMessages = [];
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
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
    BillingTicker.instance.setRate(BillingRate.full);
    BillingTicker.instance.resume();
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
    await [Permission.microphone, Permission.storage].request();
  }

  Future<void> _fetchKeysAndInit() async {
    await _loadEmergencySituations();
    try {
      await FirebaseRemoteConfig.instance.fetchAndActivate();
      if (mounted) {
        setState(() {
          _deepgramKey =
              FirebaseRemoteConfig.instance.getString('DeepgramAPIKey');
          _openAiKey = FirebaseRemoteConfig.instance.getString('OpenAIAPIKey');
        });
        // 🚨 최초 입장 시 랜덤 긴급 상황으로 시나리오 자동 생성
        if (_emergencySituations.isNotEmpty) {
          final rand = _emergencySituations[Random().nextInt(_emergencySituations.length)];
          _selectedEmergencyKeyword = rand['situation'] as String;
        }
        _generateScenario();
      }
    } catch (e) {
      print('❌ Key Load Error: $e');
    }
  }

  Future<void> _loadEmergencySituations() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/jsons/emergency_situations_200.json');
      final decoded = jsonDecode(jsonStr);
      final data = decoded as Map<String, dynamic>;
      final rawList = data['emergency_situations'];
      if (rawList == null) {
        debugPrint('❌ Emergency JSON: "emergency_situations" key not found');
        return;
      }
      final list = (rawList as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      debugPrint('✅ Emergency situations loaded: ${list.length}');
      if (mounted) setState(() => _emergencySituations = list);
    } catch (e, st) {
      debugPrint('❌ Emergency JSON Load Error: $e\n$st');
    }
  }

  // ====================================================================
  // 📦 [Box 4: 시나리오 관리 (긴급상황 JSON 기반 AI 생성)]
  // ====================================================================
  Future<void> _generateScenario() async {
    if (_openAiKey.isEmpty || _isGeneratingScenario) return;
    setState(() => _isGeneratingScenario = true);

    try {
      final keyword = _selectedEmergencyKeyword.isNotEmpty
          ? _selectedEmergencyKeyword
          : "공항 여권 분실";
      final result = await RoleplayBrain.generateEmergencyScenario(_openAiKey, keyword);
      if (mounted && result != null) {
        setState(() {
          _scenarioKeyword = result['keyword'] ?? keyword;
          _scenarioSituation = result['situation'] ?? keyword;
          _scenarioAiRole = result['ai_role'] ?? "담당 직원";
          _scenarioUserRole = result['user_role'] ?? "당황한 여행자";
          // 시나리오 변경 시 세션 리셋
          _sessionDocId = null;
          _myHistoryRef = null;
          _localMessages.clear();
          _isConversationActive = false;
        });
      }
    } catch (e) {
      print("❌ 시나리오 생성 에러: $e");
    } finally {
      if (mounted) setState(() => _isGeneratingScenario = false);
    }
  }

  // 상황 선택 바텀시트
  void _showSituationPicker() {
    final categories = [
      {'key': '공항_비행기_교통', 'label': '✈️ 교통', 'color': const Color(0xFF0EA5E9)},
      {'key': '호텔_숙소_주거', 'label': '🏨 숙소', 'color': const Color(0xFF10B981)},
      {'key': '식당_쇼핑_유흥', 'label': '🛍️ 쇼핑', 'color': const Color(0xFFF59E0B)},
      {'key': '공공장소_병원_비즈니스', 'label': '🏥 공공', 'color': const Color(0xFFEF4444)},
      {'key': '레저_관광_자연_기타', 'label': '🏞️ 레저', 'color': const Color(0xFF8B5CF6)},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _SituationPickerSheet(
          emergencySituations: _emergencySituations,
          categories: categories,
          onSelected: (situationKeyword) {
            Navigator.pop(ctx);
            if (!_isConversationActive) {
              setState(() => _selectedEmergencyKeyword = situationKeyword);
              _generateScenario();
            }
          },
        );
      },
    );
  }

// ====================================================================
// 📦 [Box 5: Deepgram + Relay Pipeline] ← 통신로직 박스코드와 완전 일치
// ====================================================================
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // 첫 메시지(오프너)일 때는 상단 고정 → 시작 대사 전체가 보이게
        if (_localMessages.length <= 1) return;
        _scrollController.animateTo(_scrollController.position.maxScrollExtent,
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

  // 현재 대사를 화면 맨 위에 고정 — localToGlobal 기반 정확한 offset 계산
  void _scrollToCurrentTop(int index) {
    final role = (index >= 0 && index < _localMessages.length)
        ? (_localMessages[index]['role'] ?? '') : '';
    _log('🧭 [SCROLL-TOP]', 'index=$index role=$role');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final key = _itemKeys[index];
      if (key == null) return;
      final ctx = key.currentContext;
      if (ctx == null) return;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) return;
      final scrollableCtx = Scrollable.maybeOf(ctx)?.context;
      if (scrollableCtx == null) return;
      final scrollBox = scrollableCtx.findRenderObject() as RenderBox?;
      if (scrollBox == null) return;
      final itemOffset = box.localToGlobal(Offset.zero, ancestor: scrollBox);
      final target = (_scrollController.offset + itemOffset.dy - 12.0)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _log('🧭 [SCROLL-TOP-EXEC]', 'target=$target itemDy=${itemOffset.dy.toStringAsFixed(0)}');
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  void _stopEverything() {
    _isConversationActive = false;
    _isAiOpenerPlaying = false;
    _commitTimer?.cancel(); // 🔧 [v3.4] 대기 중 타이머 정리
    _commitTimer = null;
    _pendingTranscript = ''; // 대기 중 발화도 버림
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
    if (mounted) setState(() {});

    try {
      final String targetLangName = FFAppState().targetLang.isNotEmpty
          ? FFAppState().targetLang
          : 'English';

      if (mounted) {
        setState(() {
          _localMessages.add({'role': 'SYSTEM', 'target': '', 'original': ''});
        });
        _scrollToCurrentTop(_localMessages.length - 1);
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

  // ====================================================================
  // 📦 [정정 감지] AI 오해/오청취 시 직전 교환 삭제 후 재처리
  // ====================================================================
  // 감지 조건 1 — 명시적 정정 키워드로 시작하는 경우
  //   예: "아니야", "다시 해봐", "내 말은", "I meant", "No I said" 등
  // 감지 조건 2 — 직전 발화와 단어 겹침이 65% 이상 (재발음 재시도)
  //   예: AI가 "안녕하세요"를 잘못 들었을 때 유저가 "안녕하세요"를 다시 말하는 경우
  // 동작: 직전 HOST(유저) + SYSTEM(AI) 버블 쌍을 삭제하고 새로 처리
  // ====================================================================
  bool _hasLastExchange() {
    bool hasHost = false, hasSystem = false;
    for (final m in _localMessages) {
      if (m['role'] == 'HOST') hasHost = true;
      if (m['role'] == 'SYSTEM') hasSystem = true;
      if (hasHost && hasSystem) return true;
    }
    return false;
  }

  double _wordOverlap(String a, String b) {
    final wordsA = a
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .toSet();
    final wordsB = b
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .toSet();
    if (wordsA.isEmpty || wordsB.isEmpty) return 0.0;
    final common = wordsA.intersection(wordsB).length;
    return common / min(wordsA.length, wordsB.length);
  }

  bool _isCorrectionAttempt(String transcript) {
    if (!_hasLastExchange()) return false;

    final lower = transcript.toLowerCase().trim();

    // 명시적 정정 키워드 (한국어 + 영어)
    const correctionStarters = [
      // 한국어
      '아니야', '아니에요', '아니요', '아니 그게', '아니 그건', '아니 그거',
      '다시 해', '다시 말', '다시 한번', '다시 해봐',
      '내 말은', '제 말은', '내가 말한', '제가 말한',
      '이 뜻이야', '이 뜻은', '이런 뜻', '그 뜻이',
      '그게 아니라', '그게 아니야', '잘못 들',
      // English
      'i said ', 'i meant ', 'what i said', 'no i ', 'no, i ',
      'not that', 'wait, ', 'actually i said', "i didn't say",
    ];
    for (final starter in correctionStarters) {
      if (lower.startsWith(starter)) return true;
    }

    // 재발음 감지: 직전 발화와 단어 겹침 65% 이상
    if (_lastRawTranscript.isNotEmpty &&
        transcript.split(RegExp(r'\s+')).length >= 2) {
      if (_wordOverlap(transcript, _lastRawTranscript) >= 0.65) return true;
    }

    return false;
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
    if (_deepgramKey.isEmpty || !(await _audioRecorder.hasPermission())) return;

    _isConversationActive = true;
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
      },
      onTurnEnded: (transcript, {bool speechFinal = false}) {
        _lastTurnWasSpeechFinal = speechFinal;
        _log('🔀 [LISTEN-03]', 'onTurnEnded 콜백 수신: "$transcript" speechFinal=$speechFinal');
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
    final clean = transcript.trim();
    _log('🔀 [STOP-01]', 'speech_final 수신: "$clean" (len=${clean.length})');

    if (clean.length < 2) {
      _log('🔀 [STOP-02]', '너무 짧음 → 무시');
      return;
    }

    final waitMs = _getCommitWaitMs();

    // 🔧 기존 대기 중인 발화가 있으면 공백으로 연결 (더듬거림 합치기)
    if (_pendingTranscript.isEmpty) {
      _pendingTranscript = clean;
      _log('🔀 [STOP-03]', '신규 발화 접수. ${waitMs}ms 조건부 대기창 시작 speechFinal=$_lastTurnWasSpeechFinal');
    } else {
      _pendingTranscript = '$_pendingTranscript $clean';
      _log('🔀 [STOP-04]', '합치기: "$_pendingTranscript" (${waitMs}ms 조건부 대기창 리셋)');
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
    _swSpeechEnd.reset();
    _swSpeechEnd.start();

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

  Future<void> _processRelayPipeline(String finalTranscript) async {
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
      if (_isConversationActive) {
        if (finalTranscript.length <= 2) {
          _speakRetryAndListen();
        } else {
          _startDeepgramListening();
        }
      }
      return;
    }

    // ─────────────────────────────────────────────────────
    // STEP 1.5: 정정 감지 — AI 오해/오청취 시 직전 교환 삭제
    // ─────────────────────────────────────────────────────
    if (_isCorrectionAttempt(finalTranscript)) {
      _log('🔄 [CORRECT-01]', '정정 감지: "$finalTranscript" → 직전 교환 삭제');
      if (mounted) {
        setState(() {
          _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
          _removeLastExchange();
        });
        if (_localMessages.isNotEmpty)
          _scrollToCurrentTop(_localMessages.length - 1);
      }
      _log('🔄 [CORRECT-02]', '직전 교환 삭제 완료 → 재처리 진행');
    }

    try {
      // ─────────────────────────────────────────────────────
      // STEP 2: HOST 풍선 생성 + 유저 번역 스트리밍
      // ─────────────────────────────────────────────────────
      _lastRawTranscript = finalTranscript; // 다음 턴 정정 감지용 저장
      if (mounted) {
        setState(() {
          _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
          _removeOrphanedHostBubbles(); // AI 응답 없이 중단된 이전 HOST 버블 제거
          _localMessages.add({'role': 'HOST', 'target': '', 'original': ''});
        });
        _scrollToCurrentTop(_localMessages.length - 1);
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
      _ttsQueueManager.setUserTurn(true);
      _ttsQueueManager.setAiPaused(false); // 유저 청크는 즉시 재생

      // 다국어 구두점 단위 쪼개기
      final RegExp splitPattern = RegExp(r'[,\.?!;:。、！？…，；：\n]');

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
      );

      bool evaporated = false;
      bool firstChunkSent = false;
      await for (String chunk in userStream) {
        userTargetText += chunk;
        userBuffer += chunk;

        // 🔧 [v3.3] 누적된 전체 텍스트에서 EVAPORATE 감지 (스트림 조각 분할 대응)
        if (userTargetText.contains("[EVAPORATE]")) {
          evaporated = true;
          _log('⚠️ [EVAPORATE]', '증발 감지 → 턴 취소');
          break;
        }
        if (mounted)
          setState(() => _localMessages[hostIndex]['target'] = userTargetText);

        // 구두점 도달 즉시 TTS 청크 발사
        final matches = splitPattern.allMatches(userBuffer).toList();
        if (matches.isNotEmpty) {
          int lastIdx = matches.last.end;
          String toSpeak = userBuffer.substring(0, lastIdx).trim();
          userBuffer = userBuffer.substring(lastIdx);
          if (toSpeak.isNotEmpty) {
            final cleanedChunk = _cleanText(toSpeak);
            if (isMeaninglessTtsText(cleanedChunk)) {
              _log('🔊 [TTS-SKIP] [USER]', '의미 없는 TTS 조각 skip: "$cleanedChunk"');
            } else {
              userTtsFetcher.addText(cleanedChunk);
              firstChunkSent = true;
            }
          }
        }
        if (!firstChunkSent) {
          final wordCount = userBuffer
              .trim()
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .length;
          if (wordCount >= 4) {
            final cleanedBuf = _cleanText(userBuffer.trim());
            if (isMeaninglessTtsText(cleanedBuf)) {
              _log('🔊 [TTS-SKIP] [USER]', '의미 없는 TTS 조각 skip: "$cleanedBuf"');
            } else {
              userTtsFetcher.addText(cleanedBuf);
              firstChunkSent = true;
            }
            userBuffer = "";
          }
        }
      }

      if (evaporated) {
        if (mounted)
          setState(
              () => _localMessages.removeWhere((m) => m['role'] == 'HOST'));
        if (_isConversationActive && _turnCounter == currentTurnId)
          _speakRetryAndListen();
        return;
      }

      if (userBuffer.trim().isNotEmpty) {
        final cleanedRem = _cleanText(userBuffer.trim());
        if (isMeaninglessTtsText(cleanedRem)) {
          _log('🔊 [TTS-SKIP] [USER]', '의미 없는 TTS 조각 skip: "$cleanedRem"');
        } else {
          userTtsFetcher.addText(cleanedRem);
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
            _scrollToCurrentTop(aiIndex);
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

          if (mounted && !_ttsQueueManager.aiPaused)
            setState(() => _localMessages[aiIndex]['target'] = aiTargetText);

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
          _log('🧠 [PIPE-08A]', 'AI stream end + remainder queued. pending=${aiTtsFetcher.pendingRequests}');
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
      // [v3.6] PIPE-07 시점: 버퍼된 AI 텍스트 일괄 표시
      if (mounted && aiTargetText.isNotEmpty)
        setState(() => _localMessages[aiIndex]['target'] = aiTargetText);

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
      final newRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('chat_history')
          .doc();
      await newRef.set({
        'created_at': FieldValue.serverTimestamp(),
        'room_name': "Roleplay Mode",
        'is_pinned': false,
        'msg_count': 0
      });
      _myHistoryRef = newRef;
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
          'original_text': (line['original_text'] ?? '').toString(),
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
  Future<void> _handleAutoSaveAndExit() async {
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
          await _myHistoryRef!.update({
            'last_message': lastText,
            'last_message_time': FieldValue.serverTimestamp(),
            'msg_count': _localMessages.length,
            'last_active': FieldValue.serverTimestamp(),
            'chat_json': jsonEncode(_localMessages),
            'is_completed': false,
          });
          _log('💾 [HIST-UPD]', 'last_message + chat_json 업데이트 완료');
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
            Expanded(
              child: Stack(
                children: [
                  _buildChatList(),
                  if (_localMessages.isEmpty)
                    Positioned.fill(
                      child: Center(child: _buildTopControls()),
                    ),
                ],
              ),
            ),
            _buildControlArea(bottomPad),
          ]),
        ),
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
          GestureDetector(
            onTap: _handleAutoSaveAndExit, // 🔧 [히스토리] AutoSave 연결
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 72,
              height: 56,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 4),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white70),
            ),
          ),
          Row(children: [
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF251640), Color(0xFF141230)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF7C3AED).withOpacity(0.35),
                width: 1,
              ),
            ),
            child: _isGeneratingScenario
                ? const SizedBox(
                    height: 60,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF9333EA),
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 상황 헤더
                      Row(children: const [
                        Icon(Icons.theater_comedy_rounded,
                            color: Color(0xFFA78BFA), size: 13),
                        SizedBox(width: 5),
                        Text(
                          'SITUATION',
                          style: TextStyle(
                            color: Color(0xFFA78BFA),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        _scenarioSituation,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // AI 역할 박스
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED).withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF7C3AED).withOpacity(0.40),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.smart_toy_rounded,
                                    color: Color(0xFFD8B4FE), size: 13),
                                SizedBox(width: 4),
                                Text('AI',
                                    style: TextStyle(
                                      color: Color(0xFFA78BFA),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.4,
                                    )),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(_scenarioAiRole,
                                style: const TextStyle(
                                  color: Color(0xFFEDE9FE),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                )),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      // YOU 역할 박스
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0EA5E9).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF0EA5E9).withOpacity(0.32),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.person_rounded,
                                    color: Color(0xFF7DD3FC), size: 13),
                                SizedBox(width: 4),
                                Text('YOU',
                                    style: TextStyle(
                                      color: Color(0xFF7DD3FC),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.4,
                                    )),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(_scenarioUserRole,
                                style: const TextStyle(
                                  color: Color(0xFFE0F2FE),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                )),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          if (!_isGeneratingScenario) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {
                    if (!_isConversationActive) _showSituationPicker();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: const Color(0xFFEF4444).withOpacity(0.45), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.list_alt_rounded,
                            color: Color(0xFFFC8181), size: 14),
                        SizedBox(width: 6),
                        Text('상황 선택',
                            style: TextStyle(
                                color: Color(0xFFFC8181),
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () {
                    if (!_isConversationActive && _selectedEmergencyKeyword.isNotEmpty) {
                      _generateScenario();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.refresh_rounded,
                            color: Colors.white30, size: 14),
                        SizedBox(width: 6),
                        Text('다시 생성',
                            style: TextStyle(color: Colors.white30, fontSize: 12)),
                      ],
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

  Widget _buildChatList() {
    final double bottomPad = MediaQuery.of(context).size.height * 0.55;
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad),
      itemCount: _localMessages.length,
      itemBuilder: (context, idx) {
        _itemKeys[idx] ??= GlobalKey();
        return Container(
            key: _itemKeys[idx], child: _buildTextBlock(_localMessages[idx]));
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

    // 아이콘 아바타
    final Widget avatar = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isHost
            ? const Color(0xFF1D4ED8).withOpacity(0.22)
            : const Color(0xFF7C3AED).withOpacity(0.22),
        shape: BoxShape.circle,
        border: Border.all(
          color: isHost
              ? const Color(0xFF60A5FA).withOpacity(0.45)
              : const Color(0xFFA855F7).withOpacity(0.45),
          width: 1,
        ),
      ),
      child: Icon(
        isHost ? Icons.person_rounded : Icons.smart_toy_rounded,
        color: isHost ? const Color(0xFF93C5FD) : const Color(0xFFD8B4FE),
        size: 17,
      ),
    );

    // 말풍선
    final Widget bubble = ConstrainedBox(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.73),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isHost
              ? const Color(0xFF1E293B)
              : const Color(0xFF9333EA).withOpacity(0.13),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isHost ? 16 : 4),
            bottomRight: Radius.circular(isHost ? 4 : 16),
          ),
          border: Border.all(
            color: isHost
                ? const Color(0xFF3B82F6).withOpacity(0.18)
                : const Color(0xFF9333EA).withOpacity(0.25),
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment:
            isHost ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: isHost
            ? [bubble, const SizedBox(width: 8), avatar]
            : [avatar, const SizedBox(width: 8), bubble],
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
              const Text("AI Roleplay",
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              // Start 버튼: AI 역할 설정 완료 & 대화 미시작 상태
              if (_scenarioAiRole.isNotEmpty &&
                  _localMessages.isEmpty &&
                  !_isAiOpenerPlaying &&
                  !_isConversationActive)
                GestureDetector(
                  onTap: () {
                    if (_openAiKey.isEmpty) return;
                    setState(() => _isConversationActive = true);
                    _generateAndPlayAiOpener();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7C3AED).withOpacity(0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text('Start',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                )
              else if (_isAiOpenerPlaying)
                // AI 첫 발화 재생 중
                const SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Color(0xFFA855F7),
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

  Future<void> _onUserTurnEnded(String userText, {bool speechFinal = false}) async {
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
// 🧠 [Box 7-1] RoleplayBrain v3 — 롤플레이 모드 전용 AI 뇌
// ====================================================================
class RoleplayBrain {
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
  }) async* {
    final client = http.Client();
    try {
      final roleContext = userRole.isNotEmpty
          ? '\nThe user is playing the role of "$userRole"${situation.isNotEmpty ? ' in a "$situation" scenario' : ''}.'
          : '';
      final sysPrompt =
          """You are an expert real-time Korean-to-$targetLang translator for a live roleplay conversation.$roleContext

Korean is a heavy pro-drop language - subjects, objects, and pronouns are constantly omitted when clear from context.

[INTERNAL THINKING - do not output]
Step 1. CONTEXT CHECK: Review conversation history.
Step 2. SUBJECT RESTORATION: The speaker is${userRole.isNotEmpty ? ' a "$userRole"' : ' the user'}. Identify and restore any omitted subject/pronoun from THEIR perspective.
Step 3. TRANSLATE: Produce natural $targetLang speech that fits${userRole.isNotEmpty ? ' the "$userRole" role' : ' the user'}.

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
  }) async* {
    final client = http.Client();
    try {
      // 🎯 [롤플레이 AI 응답 언어 규칙] — 원칙 2
      // - AI는 타겟 언어($myTarget)로만 말한다.
      // - ai_role / user_role 이름이 한글이어도 실제 대사는 반드시 $myTarget.
      // - 한국어 등 모국어를 절대 섞지 않는다.
      final sysPrompt =
          """You are a roleplay partner in a language learning app.

[ROLEPLAY SCENARIO]
Situation: $situation
Your role: $aiRole
User's role: $userRole

[CRITICAL LANGUAGE RULE]
- Respond in $myTarget ONLY. NEVER use Korean or any other language.
- Even though role names "$aiRole" / "$userRole" are written in Korean, your actual dialogue must be 100% in $myTarget.
- Mixing Korean into your response = failure.

[CONVERSATION RULES]
- Stay fully in character as "$aiRole". Treat the user as "$userRole".
- MAXIMUM 2 short sentences. Often 1 sentence is enough.
- Keep each sentence under 8 words when possible.
- Stay in the scenario. Do not break character.
- No greetings, no "I understand", no meta-comments. Just respond naturally.
- Respond in natural, concise everyday conversational style.
- If the user's message is completely unclear, nonsensical, or impossible to understand in context (likely a speech recognition error), output EXACTLY: [RETRY] (nothing else). Do NOT attempt a confused or apologetic response.
- If the user's input is unclear (possible speech recognition error), ask them politely to repeat in $myTarget.""";

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
          """You are roleplaying as "$aiRole" in a language learning app.

[SCENARIO]
Situation: $situation
Your role: $aiRole
The other person: $userRole (has just arrived)

[CRITICAL LANGUAGE RULE]
- Speak ONLY in $targetLang. Do NOT use Korean or any other language.
- Even though role names are written in Korean, your dialogue must be 100% in $targetLang.

[OPENING RULES]
- You speak FIRST to start the conversation.
- Say ONE short, realistic sentence that a real person in your role would actually say.
- Avoid a generic "Hello!" alone — give a situational opener specific to your role.
- Under 10 words. Natural everyday speech only.

Examples:
- Barista at a café: "What can I get for you today?"
- Doctor at a clinic: "So, what brings you in today?"
- Store clerk: "Looking for anything specific today?"
- Gym trainer: "Is this your first time here?"
- Bank teller: "How can I help you today?"

Output: ONE sentence in $targetLang only.""";

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

  // ==================================================================
  // 📦 [Box 7-1-E] generateEmergencyScenario — 긴급상황 키워드 기반 동적 생성
  // ==================================================================
  static Future<Map<String, String>?> generateEmergencyScenario(
      String apiKey, String emergencyKeyword) async {
    // 매번 다른 구체적 시나리오를 만들기 위해 랜덤 seed 값 추가
    final seeds = [
      '오전 이른 시간대', '늦은 밤', '주말 오후', '출퇴근 혼잡 시간',
      '비가 오는 날', '눈이 오는 날', '더운 여름날', '크리스마스 연휴',
    ];
    final timeSeed = seeds[Random().nextInt(seeds.length)];

    final systemPrompt =
        """You are a Korean survival English roleplay scenario generator for a language learning app.

[TASK]
Given a short Korean emergency keyword and time context, create a vivid, specific roleplay scenario.
Each call should produce a DIFFERENT variation of the same keyword scenario.

[OUTPUT RULES]
Output EXACTLY this JSON (Korean only, label-style, short):
{
  "situation": "구체적인 상황 묘사 (15자 이내, 장소+디테일)",
  "ai_role": "AI의 역할 (10자 이내, 예: 당황한 승무원)",
  "user_role": "유저의 역할 (8자 이내, 예: 해외 여행자)"
}

[RULES]
- situation: must include specific detail beyond the keyword (NOT just repeat keyword)
- ai_role: give the AI a strong personality (예: 깐깐한 경찰관, 다급한 의사, 당황한 직원)
- user_role: clearly define user's position in the emergency
- VARY the specific detail each time (different victim, different severity, different location detail)""";

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
              'temperature': 1.2,
              'response_format': {'type': 'json_object'},
              'max_tokens': 200,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {
                  'role': 'user',
                  'content':
                      '긴급상황 키워드: "$emergencyKeyword"\n시간대: $timeSeed\n\n위 키워드를 기반으로 매번 다른 구체적 롤플레이 상황을 JSON으로 생성하세요.',
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final raw = jsonDecode(utf8.decode(res.bodyBytes))['choices'][0]
                ['message']['content']
            .toString();
        final cleanJson = _cleanJsonString(raw);
        final parsed = jsonDecode(cleanJson);
        return {
          'keyword': emergencyKeyword,
          'situation': parsed['situation']?.toString() ?? emergencyKeyword,
          'ai_role': parsed['ai_role']?.toString() ?? '담당 직원',
          'user_role': parsed['user_role']?.toString() ?? '당황한 여행자',
        };
      }
    } catch (e) {
      print('generateEmergencyScenario Error: $e');
    } finally {
      client.close();
    }
    return null;
  }

  // 기존 generateScenario 유지 (하위 호환)
  static Future<Map<String, String>?> generateScenario(String apiKey) async {
    const places = ['공항', '호텔', '응급실', '경찰서', '렌터카'];
    final place = places[Random().nextInt(places.length)];
    return generateEmergencyScenario(apiKey, '$place 긴급 상황');
  }

  // ==================================================================
  // 📦 [Box 7-1-F] _cleanJsonString
  // ==================================================================
  static String _cleanJsonString(String text) {
    String clean = text.trim();
    if (clean.startsWith('```json')) clean = clean.substring(7);
    if (clean.startsWith('```')) clean = clean.substring(3);
    if (clean.endsWith('```')) clean = clean.substring(0, clean.length - 3);
    return clean.trim();
  }
}

// ============================================================================
// 🚨 상황 선택 바텀시트 위젯
// ============================================================================
class _SituationPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> emergencySituations;
  final List<Map<String, dynamic>> categories;
  final void Function(String situationKeyword) onSelected;

  const _SituationPickerSheet({
    required this.emergencySituations,
    required this.categories,
    required this.onSelected,
  });

  @override
  State<_SituationPickerSheet> createState() => _SituationPickerSheetState();
}

class _SituationPickerSheetState extends State<_SituationPickerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget.categories.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _getSituationsForCategory(String categoryKey) {
    return widget.emergencySituations
        .where((s) => s['category'] == categoryKey)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F0E1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 핸들
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 헤더
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFEF4444), size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '긴급 상황 선택',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${widget.emergencySituations.length}개 상황',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // 카테고리 탭
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: const Color(0xFFEF4444),
                indicatorWeight: 2,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                labelStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
                unselectedLabelStyle:
                    const TextStyle(fontSize: 12),
                tabs: widget.categories
                    .map((c) => Tab(text: c['label'] as String))
                    .toList(),
              ),
              const Divider(color: Colors.white12, height: 1),
              // 탭 콘텐츠
              Expanded(
                child: widget.emergencySituations.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline,
                                color: Colors.white38, size: 36),
                            SizedBox(height: 12),
                            Text(
                              '상황 데이터를 불러오지 못했습니다',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 14),
                            ),
                            SizedBox(height: 6),
                            Text(
                              '앱을 재시작하거나 잠시 후 다시 시도해 주세요',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : TabBarView(
                  controller: _tabController,
                  children: widget.categories.map((cat) {
                    final situations =
                        _getSituationsForCategory(cat['key'] as String);
                    final color = cat['color'] as Color;
                    return GridView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2.6,
                      ),
                      itemCount: situations.length,
                      itemBuilder: (_, i) {
                        final item = situations[i];
                        final keyword = item['situation'] as String;
                        final id = item['id'] as int;
                        return GestureDetector(
                          onTap: () => widget.onSelected(keyword),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: color.withOpacity(0.35), width: 1),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.25),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '$id',
                                    style: TextStyle(
                                        color: color,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    keyword,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      height: 1.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
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
