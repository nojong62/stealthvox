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
class RoutineModeClone extends StatefulWidget {
  const RoutineModeClone({super.key, this.width, this.height});
  final double? width;
  final double? height;

  @override
  State<RoutineModeClone> createState() => _RoutineModeCloneState();
}

class _RoutineModeCloneState extends State<RoutineModeClone> {
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
  bool _isAiOpenerPlaying = false; // AI 첫 발화 재생 중 여부

  // 🔧 [v3.4 발화 합치기] 유저 더듬거림 대응
  // speech_final 받아도 바로 파이프라인 시작 안 하고 1.2초 대기
  // 대기 중 새 발화 오면 합쳐서 처리 (최종 한 덩어리로)
  String _pendingTranscript = ''; // 대기 중인 유저 발화 누적
  Timer? _commitTimer; // "진짜 끝났는지" 확정 타이머
  static const int COMMIT_WAIT_MS = 1200; // 발화 합치기 대기 시간
  String _lastRawTranscript = ''; // 정정 감지용 직전 유저 발화 원문

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

  // 클론 데이터 관리
  String _selectedCloneId = "";
  String _selectedCloneContext = "";
  List<Map<String, dynamic>> _clones = [];

  // 🧠 [장기 기억] 클론별 메모리 (SharedPreferences 동기화)
  String _cloneSummary = '';
  List<Map<String, String>> _recentHistory = [];
  int _memoryTurnCount = 0;

  final TextEditingController _cloneNameController = TextEditingController();
  final TextEditingController _kakaoTextController = TextEditingController();
  final TextEditingController _editPersonaController = TextEditingController();
  bool _isCreatingClone = false;
  bool _isEditingClone = false;

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

    _initPermissions();
    _loadClones();
    _fetchKeys();
    BillingTicker.instance.setRate(BillingRate.full);
    BillingTicker.instance.resume();
  }

  @override
  void dispose() {
    BillingTicker.instance.pause();
    _stopEverything();
    _voiceManager?.dispose();
    _audioRecorder.dispose();
    _ttsQueueManager.stop();
    _scrollController.dispose();
    _cloneNameController.dispose();
    _kakaoTextController.dispose();
    _editPersonaController.dispose();
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
      }
    } catch (e) {
      print('❌ Key Load Error: $e');
    }
  }

  // ====================================================================
  // 📦 [Box 4: Clone 관리] — Firestore 기반
  // ====================================================================

  CollectionReference<Map<String, dynamic>>? _clonesRef() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('clones');
  }

  Future<void> _loadClones() async {
    final ref = _clonesRef();
    if (ref == null) {
      _log('⚠️ [CLONE-LOAD]', '로그인되지 않음 → SharedPreferences fallback');
      await _loadClonesFromPrefs();
      return;
    }
    try {
      final snapshot = await ref.orderBy('created_at').get();
      if (mounted) {
        setState(() {
          _clones = snapshot.docs.map((doc) {
            final d = doc.data();
            return <String, dynamic>{
              'id': doc.id,
              'name': d['name'] ?? '',
              'characteristics': d['personality'] ?? '',
              'original_text': d['original_text'] ?? '',
            };
          }).toList();
        });
      }
      _log('✅ [CLONE-LOAD]', '${_clones.length}개 로드 완료');
    } catch (e) {
      _log('❌ [CLONE-LOAD]', 'Firestore 실패 → SharedPreferences fallback: $e');
      await _loadClonesFromPrefs();
    }
  }

  Future<void> _loadClonesFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('my_ai_clones');
    if (json != null && mounted) {
      setState(() {
        _clones = (jsonDecode(json) as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    }
  }

  // 클론 생성 시 Firestore에 저장 → doc.id 반환
  Future<String> _createCloneInFirestore({
    required String name,
    required String personality,
    required String originalText,
  }) async {
    final ref = _clonesRef();
    if (ref == null) {
      // 비로그인 fallback
      return 'clone_${DateTime.now().millisecondsSinceEpoch}';
    }
    final doc = await ref.add({
      'name': name,
      'personality': personality,
      'original_text': originalText,
      'summary': '',
      'recent_history': [],
      'turn_count': 0,
      'created_at': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  // 클론 편집 시 Firestore 업데이트
  Future<void> _updateCloneInFirestore(
      String cloneId, String personality, String originalText) async {
    final ref = _clonesRef();
    if (ref == null || cloneId.isEmpty) return;
    try {
      await ref.doc(cloneId).update({
        'personality': personality,
        'original_text': originalText,
      });
    } catch (e) {
      _log('❌ [CLONE-UPDATE]', 'personality 업데이트 실패: $e');
    }
  }

  // 🧠 [장기 기억] 클론 진입 시 Firestore에서 메모리 로드
  Future<void> _loadCloneContext(String cloneId) async {
    if (cloneId.isEmpty) return;
    final ref = _clonesRef();

    String personality = '';
    String summary = '';
    List<Map<String, String>> history = [];
    int turnCount = 0;

    if (ref != null) {
      try {
        final doc = await ref.doc(cloneId).get();
        if (doc.exists) {
          final d = doc.data()!;
          personality = (d['personality'] as String?) ?? '';
          summary = (d['summary'] as String?) ?? '';
          turnCount = (d['turn_count'] as int?) ?? 0;
          final raw = d['recent_history'] as List<dynamic>? ?? [];
          history = raw.map((e) => Map<String, String>.from(e as Map)).toList();
        }
      } catch (e) {
        _log('❌ [CLONE-CTX]', 'Firestore 실패 → SharedPreferences fallback: $e');
        // SharedPreferences fallback
        final prefs = await SharedPreferences.getInstance();
        personality = prefs.getString('clone_personality_$cloneId') ?? '';
        summary = prefs.getString('clone_summary_$cloneId') ?? '';
        turnCount = prefs.getInt('clone_turn_count_$cloneId') ?? 0;
        final hJson = prefs.getString('clone_recent_history_$cloneId');
        if (hJson != null) {
          try {
            history = (jsonDecode(hJson) as List)
                .map((e) => Map<String, String>.from(e))
                .toList();
          } catch (_) {}
        }
      }
    }

    if (mounted) {
      setState(() {
        if (personality.isNotEmpty) _selectedCloneContext = personality;
        _cloneSummary = summary;
        _recentHistory = history;
        _memoryTurnCount = turnCount;
      });
    }
    final preview = summary.length > 50 ? summary.substring(0, 50) : summary;
    _log('🧠 [MEMORY-LOAD]',
        'cloneId=$cloneId personality=${personality.length}자 summary="$preview" history=${history.length}개 turns=$turnCount');
  }

  // 🧠 [장기 기억] 대화 완료 후 Firestore recent_history / turn_count 업데이트
  Future<void> _saveRecentHistory(String userText, String aiText) async {
    if (_selectedCloneId.isEmpty) return;

    _recentHistory.add({'role': 'user', 'content': userText});
    _recentHistory.add({'role': 'assistant', 'content': aiText});
    while (_recentHistory.length > 4) _recentHistory.removeAt(0);
    _memoryTurnCount++;

    final ref = _clonesRef();
    if (ref != null) {
      ref.doc(_selectedCloneId).update({
        'recent_history': _recentHistory,
        'turn_count': _memoryTurnCount,
      }).catchError((e) => _log('❌ [HIST-SAVE]', 'recent_history 저장 실패: $e'));
    }

    if (_memoryTurnCount % 5 == 0) _updateCloneSummary();
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

  // 🧠 [장기 기억] 5턴마다 GPT-4o-mini로 요약 갱신 → Firestore summary 업데이트
  Future<void> _updateCloneSummary() async {
    if (_selectedCloneId.isEmpty ||
        _openAiKey.isEmpty ||
        _recentHistory.isEmpty) return;
    _log('🧠 [SUMMARY-START]', '요약 업데이트 시작 (turn=$_memoryTurnCount)');

    final historyText = _recentHistory
        .map((m) => '${m['role'] == 'user' ? 'User' : 'AI'}: ${m['content']}')
        .join('\n');
    final prevSummary = _cloneSummary;

    final client = http.Client();
    try {
      final res = await client
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $_openAiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'model': 'gpt-4o-mini',
              'temperature': 0.3,
              'max_tokens': 100,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      '당신은 대화 요약 전문가입니다. 두 사람의 관계와 주요 사건을 1~2문장으로 업데이트 요약하세요.',
                },
                {
                  'role': 'user',
                  'content':
                      '${prevSummary.isNotEmpty ? "이전 요약:\n$prevSummary\n\n" : ""}'
                          '최근 대화:\n$historyText\n\n'
                          '두 사람의 관계와 주요 사건을 1~2문장으로 업데이트해줘.',
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final newSummary =
            data['choices'][0]['message']['content'].toString().trim();
        // Firestore에 요약 저장
        final ref = _clonesRef();
        if (ref != null) {
          ref.doc(_selectedCloneId).update({'summary': newSummary}).catchError(
              (e) => _log('❌ [SUMMARY-SAVE]', 'summary Firestore 저장 실패: $e'));
        }
        if (mounted) setState(() => _cloneSummary = newSummary);
        _log('🧠 [SUMMARY-DONE]', '새 요약: $newSummary');
      }
    } catch (e) {
      _log('❌ [SUMMARY-ERR]', '요약 업데이트 실패: $e');
    } finally {
      client.close();
    }
  }

  // 🔬 [v3.1 진단] 로그 뷰어 다이얼로그 (복사 가능)
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
                    // 로그 본문 (선택 가능 텍스트)
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
                    // 하단 버튼들
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

  void _showCloneDashboard() {
    _cloneNameController.clear();
    _kakaoTextController.clear();
    _isCreatingClone = false;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          return DefaultTabController(
            length: 2,
            child: Dialog(
              backgroundColor: const Color(0xFF1C1C1E),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── 헤더 ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 8, 0),
                    child: Row(children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF9333EA).withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person_pin_rounded,
                            color: Color(0xFFD8B4FE), size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Text("Manage Clones",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white38, size: 20),
                        onPressed: () => Navigator.pop(dialogContext),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  // ── 탭 바 ──
                  const TabBar(
                    tabs: [
                      Tab(text: "Select"),
                      Tab(text: "Create"),
                    ],
                    labelColor: Color(0xFFD8B4FE),
                    unselectedLabelColor: Colors.white38,
                    indicatorColor: Color(0xFF9333EA),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.white12,
                    labelStyle:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  // ── 탭 내용 ──
                  SizedBox(
                    height: 460,
                    child: TabBarView(
                      children: [
                        // ── Tab 0: 대화 상대 선택 ──
                        _clones.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.person_off_outlined,
                                        color: Colors.white24, size: 48),
                                    const SizedBox(height: 12),
                                    const Text("아직 클론이 없어요",
                                        style: TextStyle(
                                            color: Colors.white38,
                                            fontSize: 14)),
                                    const SizedBox(height: 6),
                                    const Text("'클론 만들기' 탭에서 새 클론을 추가하세요",
                                        style: TextStyle(
                                            color: Colors.white24,
                                            fontSize: 12)),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                itemCount: _clones.length,
                                separatorBuilder: (_, __) => const Divider(
                                    color: Colors.white12,
                                    height: 1,
                                    indent: 56),
                                itemBuilder: (_, i) {
                                  final clone = _clones[i];
                                  final isSelected =
                                      clone['id'] == _selectedCloneId;
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 4),
                                    leading: GestureDetector(
                                      onTap: () {
                                        _stopEverything();
                                        setState(() {
                                          _selectedCloneId = clone['id'];
                                          _selectedCloneContext =
                                              clone['characteristics'];
                                          _sessionDocId = null;
                                          _myHistoryRef = null;
                                          _localMessages.clear();
                                          _isConversationActive = true;
                                          _cloneSummary = '';
                                          _recentHistory = [];
                                          _memoryTurnCount = 0;
                                        });
                                        _loadCloneContext(clone['id']);
                                        Navigator.pop(dialogContext);
                                        Future.delayed(
                                            const Duration(seconds: 2), () {
                                          if (mounted)
                                            _generateAndPlayAiOpener();
                                        });
                                      },
                                      child: Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isSelected
                                              ? const Color(0xFF9333EA)
                                                  .withOpacity(0.25)
                                              : Colors.white10,
                                          border: Border.all(
                                            color: isSelected
                                                ? const Color(0xFF9333EA)
                                                : Colors.transparent,
                                            width: 2,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.person_rounded,
                                          color: isSelected
                                              ? const Color(0xFFD8B4FE)
                                              : Colors.white38,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      clone['name'],
                                      style: TextStyle(
                                        color: isSelected
                                            ? const Color(0xFFD8B4FE)
                                            : Colors.white,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        fontSize: 15,
                                      ),
                                    ),
                                    subtitle: isSelected
                                        ? const Text("대화 중",
                                            style: TextStyle(
                                                color: Color(0xFF9333EA),
                                                fontSize: 11))
                                        : null,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (!isSelected)
                                          GestureDetector(
                                            onTap: () {
                                              _stopEverything();
                                              setState(() {
                                                _selectedCloneId = clone['id'];
                                                _selectedCloneContext =
                                                    clone['characteristics'];
                                                _sessionDocId = null;
                                                _myHistoryRef = null;
                                                _localMessages.clear();
                                                _isConversationActive = true;
                                                _cloneSummary = '';
                                                _recentHistory = [];
                                                _memoryTurnCount = 0;
                                              });
                                              _loadCloneContext(clone['id']);
                                              Navigator.pop(dialogContext);
                                              Future.delayed(
                                                  const Duration(seconds: 2),
                                                  () {
                                                if (mounted)
                                                  _generateAndPlayAiOpener();
                                              });
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF9333EA)
                                                    .withOpacity(0.15),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                    color:
                                                        const Color(0xFF9333EA)
                                                            .withOpacity(0.4)),
                                              ),
                                              child: const Text("선택",
                                                  style: TextStyle(
                                                      color: Color(0xFFD8B4FE),
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                            ),
                                          ),
                                        const SizedBox(width: 6),
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined,
                                              color: Colors.white38, size: 18),
                                          onPressed: () {
                                            Navigator.pop(dialogContext);
                                            _showEditCloneDialog(
                                                cloneId: clone['id']);
                                          },
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                              minWidth: 32, minHeight: 32),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),

                        // ── Tab 1: 클론 만들기 ──
                        SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("클론 이름",
                                  style: TextStyle(
                                      color: Colors.white54, fontSize: 12)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _cloneNameController,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: "예: 민준이",
                                  hintStyle:
                                      const TextStyle(color: Colors.white24),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.06),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text("클론 특징",
                                  style: TextStyle(
                                      color: Colors.white54, fontSize: 12)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _kakaoTextController,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13),
                                maxLines: 5,
                                decoration: InputDecoration(
                                  hintText: "나와의 관계, 성격이나 특별한 말투 등",
                                  hintStyle: const TextStyle(
                                      color: Colors.white24, fontSize: 12),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.06),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.all(14),
                                ),
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                child: _isCreatingClone
                                    ? const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(8),
                                          child: CircularProgressIndicator(
                                              color: Color(0xFF9333EA),
                                              strokeWidth: 2),
                                        ),
                                      )
                                    : ElevatedButton.icon(
                                        icon: const Icon(
                                            Icons.add_circle_outline,
                                            size: 18),
                                        label: const Text("Create Clone"),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF9333EA),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 13),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10)),
                                        ),
                                        onPressed: () async {
                                          final newName =
                                              _cloneNameController.text.trim();
                                          if (newName.isEmpty ||
                                              _kakaoTextController.text.isEmpty)
                                            return;
                                          // 중복 이름 검사
                                          final isDuplicate = _clones.any(
                                            (c) =>
                                                (c['name'] as String).trim() ==
                                                newName,
                                          );
                                          if (isDuplicate) {
                                            ScaffoldMessenger.of(ctx)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                    '⚠️ "$newName" 이름의 클론이 이미 존재합니다.'),
                                                backgroundColor:
                                                    const Color(0xFFEF4444),
                                                duration:
                                                    const Duration(seconds: 2),
                                              ),
                                            );
                                            return;
                                          }
                                          setStateDialog(
                                              () => _isCreatingClone = true);
                                          String persona = await CloneBrain
                                              .generatePersonaFromChat(
                                            apiKey: _openAiKey,
                                            chatLog: _kakaoTextController.text,
                                            cloneName: newName,
                                          );
                                          // 온도 0.2로 정체성 확정
                                          persona = await CloneBrain
                                              .confirmCloneIdentity(
                                            apiKey: _openAiKey,
                                            cloneName: newName,
                                            persona: persona,
                                          );
                                          final String newId =
                                              await _createCloneInFirestore(
                                            name: newName,
                                            personality: persona,
                                            originalText:
                                                _kakaoTextController.text,
                                          );
                                          setState(() {
                                            _clones.add({
                                              'id': newId,
                                              'name': newName,
                                              'characteristics': persona,
                                              'original_text':
                                                  _kakaoTextController.text,
                                            });
                                            _selectedCloneId = newId;
                                            _selectedCloneContext = persona;
                                            _cloneSummary = '';
                                            _recentHistory = [];
                                            _memoryTurnCount = 0;
                                            _localMessages.clear();
                                          });
                                          Navigator.pop(dialogContext);
                                          Future.delayed(
                                              const Duration(seconds: 2), () {
                                            if (mounted)
                                              _generateAndPlayAiOpener();
                                          });
                                        },
                                      ),
                              ),
                            ],
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
      ),
    );
  }

  void _showEditCloneDialog({String? cloneId}) {
    final targetId = cloneId ?? _selectedCloneId;
    if (targetId.isEmpty) return;
    final targetIdx = _clones.indexWhere((c) => c['id'] == targetId);
    if (targetIdx == -1) return;
    final currentClone = _clones[targetIdx];
    final cloneName = currentClone['name'] as String? ?? '';
    _editPersonaController.text = currentClone['original_text'] ?? "";
    _isEditingClone = false;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          return Dialog(
            backgroundColor: const Color(0xFF1C1C1E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.edit_rounded,
                          color: Color(0xFFD8B4FE), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        "$cloneName 수정",
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white38, size: 20),
                        onPressed: () => Navigator.pop(dialogContext),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    const Text(
                      "대화 로그를 수정하고 저장하면 AI가 페르소나를 재생성합니다.",
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _editPersonaController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      maxLines: 6,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_isEditingClone)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(
                              color: Color(0xFF10B981), strokeWidth: 2),
                        ),
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text("취소",
                                style: TextStyle(color: Colors.white38)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.autorenew_rounded, size: 16),
                            label: const Text("저장 & 재생성"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () async {
                              if (_editPersonaController.text.isEmpty) return;
                              final editedText = _editPersonaController.text;
                              setStateDialog(() => _isEditingClone = true);
                              String updatedPersona =
                                  await CloneBrain.generatePersonaFromChat(
                                apiKey: _openAiKey,
                                chatLog: editedText,
                                cloneName: cloneName,
                              );
                              if (!mounted) return;
                              setState(() {
                                if (_selectedCloneId == targetId) {
                                  _selectedCloneContext = updatedPersona;
                                }
                                final updateIdx = _clones
                                    .indexWhere((c) => c['id'] == targetId);
                                if (updateIdx != -1) {
                                  _clones[updateIdx]['characteristics'] =
                                      updatedPersona;
                                  _clones[updateIdx]['original_text'] =
                                      editedText;
                                }
                              });
                              _updateCloneInFirestore(
                                targetId,
                                updatedPersona,
                                editedText,
                              );
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
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
        alignment: 0.02,
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
  // 클론 대화 시작 원칙:
  //   1. AI가 항상 먼저 말한다 — 화면 진입 시 클론이 자동으로 먼저 발화.
  //   2. 타겟 언어로만 말한다 — 한국어 절대 혼용 금지.
  //   3. 클론 페르소나에 충실한 자연스러운 첫 마디 (AI 티 내지 않음).
  // ====================================================================
  Future<void> _generateAndPlayAiOpener() async {
    if (_isAiOpenerPlaying || _selectedCloneContext.isEmpty) return;
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
      // String openerBuffer = ''; // [하이브리드 전환] HybridTtsPlayer.onChunk로 대체 (롤백 가능)
      // final RegExp splitPattern = RegExp(r'[,\.?!;:。、！？…，；：\n]'); // [하이브리드 전환]

      final ChunkedTtsFetcher aiTtsFetcher = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        "nova",
        isUser: false,
        onLog: _log,
      );
      final openerHybrid = HybridTtsPlayer(
        _openAiKey,
        _ttsQueueManager,
        aiTtsFetcher,
        "nova",
        onLog: _log,
      );
      _ttsQueueManager.setUserTurn(false);
      _ttsQueueManager.setAiPaused(false);

      await for (final chunk in CloneBrain.generateCloneOpener(
        apiKey: _openAiKey,
        cloneContext: _selectedCloneContext,
        targetLang: targetLangName,
        cloneSummary: _cloneSummary,
      )) {
        if (!_isConversationActive) break;
        openerText += chunk;
        // openerBuffer += chunk; // [하이브리드 전환]
        if (mounted)
          setState(() => _localMessages[aiIndex]['target'] = openerText);

        openerHybrid
            .onChunk(chunk); // [하이브리드 전환] HybridTtsPlayer.onChunk로 대체 (롤백 가능)

        /* [하이브리드 전환] HybridTtsPlayer.onChunk로 대체 (롤백 가능)
        final matches = splitPattern.allMatches(openerBuffer).toList();
        if (matches.isNotEmpty) {
          final int lastIdx = matches.last.end;
          final String toSpeak = openerBuffer.substring(0, lastIdx).trim();
          openerBuffer = openerBuffer.substring(lastIdx);
          if (toSpeak.isNotEmpty) aiTtsFetcher.addText(_cleanText(toSpeak));
        }
        */
      }
      // [하이브리드 전환] HybridTtsPlayer.onStreamEnd로 대체 (롤백 가능)
      await openerHybrid.onStreamEnd(
          fullSentence: _cleanText(openerText.trim()));
      /* [하이브리드 전환] HybridTtsPlayer.onChunk로 대체 (롤백 가능)
      if (openerBuffer.trim().isNotEmpty)
        aiTtsFetcher.addText(_cleanText(openerBuffer.trim()));
      */

      // 역번역 (한국어 자막)
      CloneBrain.generateCleanOriginal(
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
        final String aiOriginal = await CloneBrain.generateCleanOriginal(
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
      _log('❌ [OPENER-ERR]', 'Clone Opener Error: $e');
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
  //   예: AI가 잘못 들었을 때 유저가 같은 말을 다시 말하는 경우
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
    if (_deepgramKey.isEmpty || !(await _audioRecorder.hasPermission())) return;

    _isConversationActive = true;
    if (mounted) {
      setState(() {
        _debugResult = "⏱️ 듣는 중...";
        _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
      });
      // HOST_TEMP 버블은 스크롤 트리거 없음 — 실제 HOST 버블 등장 시 스크롤
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
  }

  // 🔧 [v3.4] Deepgram speech_final 수신 시 호출됨
  // 1.2초 대기창 안에서 추가 발화 합치기 → 완전히 끝나면 파이프라인 시작
  void _stopMicAndProcess(String transcript) async {
    final clean = transcript.trim();
    _log('🔀 [STOP-01]', 'speech_final 수신: "$clean" (len=${clean.length})');

    if (clean.length < 2) {
      _log('🔀 [STOP-02]', '너무 짧음 → 무시');
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
        // 너무 짧아서 인식 실패 → 다시 말해 달라 요청
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
        _scrollToBottom();
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

      final userStream = CloneBrain.streamUserTranslation(
        apiKey: _openAiKey,
        textOriginal: finalTranscript,
        targetLang: targetLangName,
        contextStr: contextStr,
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
            userTtsFetcher.addText(toSpeak);
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
            userTtsFetcher.addText(_cleanText(userBuffer.trim()));
            userBuffer = "";
            firstChunkSent = true;
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

      if (userBuffer.trim().isNotEmpty)
        userTtsFetcher.addText(userBuffer.trim());

      // 🔧 [v3.7] 유저 통문장 TtsCache 백그라운드 저장 (히스토리 HIT 유도)
      //   - 청크별 캐시만으로는 히스토리에서 통문장 GET이 MISS됨
      //   - fire-and-forget: 유저 재생 흐름과 무관하게 백그라운드 처리
      //   - voice/speed는 히스토리 _playRhythmAudio와 동일하게 "nova", 1.0 고정
      _saveUserFullSentenceToCache(userTargetText.trim());

      // 유저 역번역 (백그라운드)
      CloneBrain.generateCleanOriginal(
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

      final aiStream = CloneBrain.streamCloneResponse(
        apiKey: _openAiKey,
        userTargetText: userTargetText,
        contextStr: latestContextStr,
        cloneContext: _selectedCloneContext,
        myTarget: targetLangName,
        cloneSummary: _cloneSummary,
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
          if (mounted && !_ttsQueueManager.aiPaused) {
            setState(() => _localMessages[aiIndex]['target'] = aiTargetText);
            // throttled ensureVisible — 스트리밍 중 현재 AI 버블 중앙 고정
            final _scrollNow = DateTime.now();
            if (_lastScrollThrottle == null ||
                _scrollNow.difference(_lastScrollThrottle!) >=
                    const Duration(milliseconds: 250)) {
              _lastScrollThrottle = _scrollNow;
              _scrollToCurrent(aiIndex);
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
      // [v3.6] PIPE-07 시점: 버퍼된 AI 텍스트 일괄 표시 — 중앙 고정으로 안정적 표시
      if (mounted && aiTargetText.isNotEmpty) {
        setState(() => _localMessages[aiIndex]['target'] = aiTargetText);
        _scrollToCurrent(aiIndex);
      }

      // AI 역번역을 AI TTS 재생 전에 미리 시작 (백그라운드)
      CloneBrain.generateCleanOriginal(
              apiKey: _openAiKey, englishText: aiTargetText)
          .then((cleanKorean) {
        if (mounted && _localMessages.length > aiIndex) {
          setState(() => _localMessages[aiIndex]['original'] = cleanKorean);
          _log('🔤 [BACK-TRANS]', 'AI 역번역 완료 → UI 반영');
        }
      });

      await aiGenerationTask;
      _log('🧠 [PIPE-08]',
          'aiGenerationTask 완료. AI pending=${aiTtsFetcher.pendingRequests}');
      // [하이브리드] remainder 발사 + 통문장 TtsCache 저장
      await _hybridTtsPlayer!
          .onStreamEnd(fullSentence: _cleanText(aiTargetText.trim()));

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
      final hostLine = {
        'role': 'HOST',
        'original_text':
            (_localMessages[hostIndex]['original'] ?? '').toString(),
        'translated_text': userTargetText,
      };
      final systemLine = {
        'role': 'SYSTEM',
        'original_text': '',
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
          'mode': 'clone',
          'clone_id': _selectedCloneId,
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
        'room_name': "Clone Mode",
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
          });
          _log('💾 [HIST-UPD]', 'last_message 업데이트 완료');
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
          _buildTopControls(),
          const SizedBox(height: 10),
          Expanded(child: _buildChatList()),
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: _showCloneDashboard,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
              color: const Color(0xFF2C2C2E),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: const Color(0xFF9333EA).withOpacity(0.4))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.manage_accounts, color: Color(0xFFD8B4FE)),
            const SizedBox(width: 8),
            Text(
                _selectedCloneId.isEmpty
                    ? "Manage Clones"
                    : "Clone: ${_clones.firstWhere((c) => c['id'] == _selectedCloneId)['name']}",
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
  }

  Widget _buildChatList() {
    if (_selectedCloneId.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [],
        ),
      );
    }
    final double bottomPad = MediaQuery.of(context).size.height * 0.55;
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
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
                : const Color(0xFF9333EA).withOpacity(0.15),
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
              const Text("Clone AI",
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              GestureDetector(
                onTap: () {
                  if (_deepgramKey.isEmpty) return;
                  setState(
                      () => _isConversationActive = !_isConversationActive);
                  if (_isConversationActive) {
                    if (_localMessages.isEmpty) {
                      _generateAndPlayAiOpener();
                    } else {
                      _startDeepgramListening();
                    }
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
  final Function(String) onTurnEnded;
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

    // TtsCache 통문장 백그라운드 저장 (재생 없음)
    final sentence = fullSentence.trim();
    if (sentence.isEmpty) return;
    try {
      final cached = await TtsCache.get(sentence, _voice);
      if (cached != null && cached.isNotEmpty) {
        onLog?.call('[HYB-03-HIT]', 'TtsCache HIT — 저장 생략');
        return;
      }
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
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await TtsCache.put(sentence, _voice, res.bodyBytes);
        onLog?.call('[HYB-04-SAVED]', '${res.bodyBytes.length}B');
      } else {
        onLog?.call('[HYB-ERR]', 'API status=${res.statusCode}');
      }
    } catch (e) {
      onLog?.call('[HYB-ERR]', 'TtsCache 저장 실패: $e');
    }
  }
}

// ============================================================================

// ====================================================================
// 🧠 [Box 7-1] CloneBrain v3 — 클론 모드 전용 AI 뇌
// ====================================================================
// 📂 서브박스 구성:
//   [Box 7-1-A] _truncatePersona        — 페르소나 1500자 트림 (컨텍스트 점령 방지)
//   [Box 7-1-B] streamUserTranslation   — 유저 한→영 번역 (CoT 2단계 주어 복원)
//   [Box 7-1-C] generateCleanOriginal   — AI 영→한 역번역 (UI 자막)
//   [Box 7-1-D] streamCloneResponse     — 클론 AI 응답 (2문장 강제, 8단어 제약)
//   [Box 7-1-E] generatePersonaFromChat — 카톡 로그 → 8차원 페르소나 추출
// ====================================================================
class CloneBrain {
  // ==================================================================
  // 📦 [Box 7-1-A] _truncatePersona — 페르소나 토큰 과부하 방지
  // ==================================================================
  static String _truncatePersona(String persona, {int maxChars = 1500}) {
    if (persona.length <= maxChars) return persona;
    final sentences = persona.split(RegExp(r'(?<=[.!?\n])'));
    final buffer = StringBuffer();
    for (final s in sentences) {
      if (buffer.length + s.length > maxChars) break;
      buffer.write(s);
    }
    return buffer.toString().trim();
  }

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
  }) async* {
    final client = http.Client();
    try {
      final sysPrompt =
          '''You are an expert real-time Korean-to-$targetLang translator specialized in live conversation.

Korean is a heavy pro-drop language — subjects, objects, and pronouns are constantly omitted when clear from context. Your job is to resolve these omissions perfectly.

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
  // 📦 [Box 7-1-C] generateCleanOriginal — 영→한 역번역 (UI 자막)
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
    return englishText; // 실패 시 영어 원문 (빈칸 방지)
  }

  // ==================================================================
  // 📦 [Box 7-1-D] streamCloneResponse — 클론 AI 응답 스트림
  // ------------------------------------------------------------------
  // 🔧 장황함 방지 핵심:
  //   - max_tokens 80 (모델 레벨에서 2문장 강제)
  //   - "Under 8 words per sentence" 구체 제약
  //   - "Often 1 sentence is enough" 간결 유도
  //   - "Match emotional tone" 제거 (부사 남발 주범)
  // ==================================================================
  static Stream<String> streamCloneResponse({
    required String apiKey,
    required String userTargetText,
    required String contextStr,
    required String cloneContext,
    required String myTarget,
    String cloneSummary = '',
  }) async* {
    final client = http.Client();
    try {
      final safePersona = _truncatePersona(cloneContext);
      final summaryBlock = cloneSummary.isNotEmpty
          ? '\n\n[MEMORY] 당신은 다음 요약된 과거 내용을 기억하고 있습니다: $cloneSummary'
          : '';

      final sysPrompt =
          '''⚠️ ABSOLUTE OUTPUT RULES — these override the persona ⚠️
1. OUTPUT LANGUAGE: $myTarget ONLY. Zero Korean characters (한글) allowed in output.
2. If the persona contains Korean signature phrases, translate them to natural $myTarget equivalents. Never quote the Korean text.

$safePersona$summaryBlock

[CONVERSATION RULES]
- Respond in $myTarget only.
- MAXIMUM 2 short sentences. Often 1 sentence is enough.
- Keep each sentence under 8 words when possible.
- Sound like a real person, not an AI. Stay in character.
- No greetings, no "I understand", no meta-comments, no prefixes. Just reply.
- Respond in natural, concise everyday conversational style.
- If the user's input is completely unclear or impossible to understand in context (likely a speech recognition error), ask them politely to repeat in $myTarget.''';

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
        'max_tokens': 80, // 🔧 핵심: 2문장 모델 레벨 강제
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

  // ==================================================================
  // 📦 [Box 7-1-E2] generateCloneOpener — 클론 AI 첫 발화 생성 (스트리밍)
  // ------------------------------------------------------------------
  // 클론 페르소나를 읽고, 해당 인물이 가장 먼저 꺼낼 법한 말 한 마디 생성.
  // ==================================================================
  static Stream<String> generateCloneOpener({
    required String apiKey,
    required String cloneContext,
    required String targetLang,
    String cloneSummary = '',
  }) async* {
    final client = http.Client();
    try {
      final safePersona = _truncatePersona(cloneContext, maxChars: 800);
      final memoryLine = cloneSummary.isNotEmpty
          ? '\n\n[MEMORY] 당신은 이 사람과의 과거 대화를 기억합니다: $cloneSummary'
          : '';

      final sysPrompt = """$safePersona$memoryLine

[YOUR TASK]
Based on the persona above, identify WHO you are to the user (parent, sibling, close friend, partner, coworker, etc.) and open the conversation with something real that reflects that relationship — NOT a generic greeting.

[RULES]
- Speak ONLY in $targetLang. Do NOT use Korean or any other language.
- ONE sentence only. Under 10 words.
- Match the persona's exact tone, energy, and vocabulary.
- NEVER say bare "Hello", "Hi", "Hey!", or "How have you been?" — these are too generic.
- Say something situational and relationship-specific:
  · Parent/elder: "Did you eat yet?", "What time are you coming home?", "Got any plans today?"
  · Sibling/close friend: "Dude, you won't believe what just happened.", "I was literally just about to text you."
  · Partner: "You okay? You seemed off earlier.", "Miss me?"
  · Colleague: "Rough day?", "Did you see the email they sent?"
- If memory exists, reference it naturally instead of starting fresh.

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
        'temperature': 0.8,
        'max_tokens': 40,
        'messages': [
          {'role': 'system', 'content': sysPrompt},
          {
            'role': 'user',
            'content':
                'Start the conversation — say your opening line in $targetLang.',
          },
        ],
      });

      final response =
          await client.send(request).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;

      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.startsWith('data: ') && line != 'data: [DONE]') {
          try {
            final delta =
                jsonDecode(line.substring(6))['choices'][0]['delta']['content'];
            if (delta != null) yield delta.toString();
          } catch (_) {}
        }
      }
    } catch (_) {
    } finally {
      client.close();
    }
  }

  // ==================================================================
  // 📦 [Box 7-1-E1] confirmCloneIdentity — 이름 확정 (temperature 0.2)
  // ------------------------------------------------------------------
  // 페르소나 생성 후 "You are [name]." 정체성을 온도 0.2로 고정
  // ==================================================================
  static Future<String> confirmCloneIdentity({
    required String apiKey,
    required String cloneName,
    required String persona,
  }) async {
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
              'max_tokens': 700,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'You are an AI persona editor. Finalize the identity of a clone character.',
                },
                {
                  'role': 'user',
                  'content': 'The clone\'s confirmed name is "$cloneName".\n\n'
                      'Here is the extracted persona:\n$persona\n\n'
                      'Rewrite this as a final, clean system prompt. '
                      'It MUST begin with "You are $cloneName." — this is the confirmed identity. '
                      'Preserve all personality traits. Be concise.',
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        return data['choices'][0]['message']['content'].toString().trim();
      }
    } catch (e) {
      print('confirmCloneIdentity error: $e');
    } finally {
      client.close();
    }
    return persona;
  }

  // ==================================================================
  // 📦 [Box 7-1-E] generatePersonaFromChat — 8차원 페르소나 추출
  // ------------------------------------------------------------------
  // 카톡 로그 → 말투/감정/습관어/관심사/관계/금지어까지 8차원 분석
  // ==================================================================
  static Future<String> generatePersonaFromChat({
    required String apiKey,
    required String chatLog,
    String cloneName = '',
  }) async {
    final client = http.Client();
    try {
      final nameSection = cloneName.isNotEmpty
          ? '''
CRITICAL: The clone character is named "$cloneName". Even if the input is written FROM another person's perspective ABOUT "$cloneName" (e.g. a parent describing their child), you must generate the persona FOR "$cloneName" — not for the writer.
- Start with: "You are $cloneName."
- Identify who the writer/other party is relative to $cloneName (e.g. father, mother, friend) and include ONE line: "The user you are talking to is your [relationship]." — this tells the AI who it is speaking TO.'''
          : '';
      final sysPrompt = '''You are a persona extraction expert.
Analyze the input and write a detailed persona profile for the clone character.
This profile will become the system prompt for an AI role-playing as that person.

$nameSection

Write the persona using these 8 dimensions. Quote actual expressions where possible.

1. IDENTITY & TONE - formal or casual? warm or blunt? energetic or laid-back?
2. SPEAKING STYLE - sentence length? use of ellipses (...), dashes, ALL CAPS?
3. EMOTIONAL PATTERNS - how do they react to joy, stress, surprise, bad news?
4. SIGNATURE PHRASES - list 3-5 real phrases or words they use often
5. INTERESTS - what do they talk about most?
6. RELATIONSHIP DYNAMIC - how do they treat the user (teasing, caring, respectful, casual)?
7. ANTI-PATTERNS - phrases that would sound completely wrong for them (e.g. corporate speak, overly polite AI-like phrases)
8. SELF-INTRODUCTION - a 2-sentence "You are..." opener at the very top, followed by "The user you are talking to is your [relationship]."

Format: Start with "You are [name]..." then cover each dimension briefly (1-3 sentences each).
Output ONLY the persona profile. No preamble, no meta-commentary.''';

      final res = await client
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'model': 'gpt-4o-mini',
              'temperature': 0.3,
              'max_tokens': 1000,
              'messages': [
                {'role': 'system', 'content': sysPrompt},
                {
                  'role': 'user',
                  'content': 'Chat log to analyze:\n\n$chatLog',
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        return data['choices'][0]['message']['content'].toString().trim();
      }
    } catch (e) {
      print('generatePersonaFromChat error: $e');
    } finally {
      client.close();
    }

    // 실패 시 구체적 폴백 페르소나
    return '''You are a close friend who chats in a relaxed, casual tone.
You keep responses short - usually 1 sentence, max 2.
You\'re warm but not over-the-top. You tease a little, but always with care.
You use casual language and contractions, never corporate or formal.
You never sound like an AI - no "I understand", no "Of course!", no "I\'m happy to help".''';
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
