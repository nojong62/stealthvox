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
import 'package:flutter/services.dart'; // ?”¬ [v3.1] Clipboard??

// ====================================================================
// ?“¦ [Box 1: ?„ìˆ˜ ?„í¬??
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
// ?”§ [v3 ì¶”ê?] TTS ë¡œì»¬ ìºì‹± + Firestore ?€?¥ìš©
import 'dart:io';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '/custom_code/actions/billing_ticker.dart';

// ====================================================================
// ?›¡ï¸?[v4] ?œë‚˜ë¦¬ì˜¤ ?¬ì§„??ë³´ì¡´??static ?€??(App State ?€ì²?
//   ë°©ì„ ?˜ê°”???¤ì‹œ ?¤ì–´?€??? ì?ê°€ ?¸íŒ…/?˜ì •???œë‚˜ë¦¬ì˜¤ë¥?? ì?.
// ====================================================================
class _RoleplayScenarioStore {
  static String situation = '';
  static String aiRole = '';
  static String userRole = '';
}

/// ==================================================================== [Box
/// 2: ?´ë˜??? ì–¸ë¶€]
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
  // ?“¦ [Box 3: ?íƒœ ë³€??ë°?ì´ˆê¸°??
  // ====================================================================
  String _deepgramKey = "";
  String _openAiKey = "";
  bool _isConversationActive = false;
  double _fontScale = 1.0;
  bool _showOriginal = true;
  int _turnCounter = 0;
  String? _sessionDocId; // ?”§ [v3 ì¶”ê?] ì²??€?????¸ì…˜ ID (?´ë¡  ë³€ê²???null ë¦¬ì…‹)
  DocumentReference? _myHistoryRef; // ?”§ [?ˆìŠ¤? ë¦¬] chat_history ë¬¸ì„œ ì°¸ì¡° (Duo ?¨í„´)

  // ?”§ [v3.4 ë°œí™” ?©ì¹˜ê¸? ? ì? ?”ë“¬ê±°ë¦¼ ?€??
  // speech_final ë°›ì•„??ë°”ë¡œ ?Œì´?„ë¼???œì‘ ???˜ê³  ì¡°ê±´ë¶€ ?€ê¸?
  // ?€ê¸?ì¤???ë°œí™” ?¤ë©´ ?©ì³??ì²˜ë¦¬ (ìµœì¢… ???©ì–´ë¦¬ë¡œ)
  String _pendingTranscript = ''; // ?€ê¸?ì¤‘ì¸ ? ì? ë°œí™” ?„ì 
  Timer? _commitTimer; // "ì§„ì§œ ?ë‚¬?”ì?" ?•ì • ?€?´ë¨¸
  static const int COMMIT_WAIT_SPEECH_FINAL_MS =
      600; // speechFinal=true ??ë¹ ë¥¸ ?‘ë‹µ
  static const int COMMIT_WAIT_UNCERTAIN_MS =
      1100; // UtteranceEnd/speechFinal=false ???¬ìœ  ?€ê¸?
  bool _lastTurnWasSpeechFinal = false; // ë§ˆì?ë§?onTurnEnded ?´ë²¤???€??ê¸°ë¡

  void _log(String tag, String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    final line = '[$ts] $tag $msg';
    print(line);
    AppLogLedger.instance.add('ROLEPLAY', '$tag $msg');
  }

  // API ?‘ë‹µ?ì„œ [Action], (Laughs) ê°™ì? ?¤ì—¼ ?¨í„´ ?œê±°
  String _cleanText(String text) {
    return text
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // punctuation/ê³µë°±ë§??ˆëŠ” ë¬¸ì?´ì? TTS ?ì— ?£ì? ?Šê¸° ?„í•œ ?„í„°
  bool isMeaninglessTtsText(String text) {
    final t = text.trim();
    if (t.isEmpty) return true;
    return RegExp('^[\\s.,!?;:\'"\\[\\]{}()\\-]+\$').hasMatch(t);
  }

  // ?Œ [v3.1] ë¡œë¹„?ì„œ ? íƒ???¸ì–´ ?´ë¦„ ??Deepgram/OpenAI ?¸ì–´ ì½”ë“œ ë§¤í•‘
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
        return 'en'; // English ?¬í•¨
    }
  }

  // ?­ ë¡¤í”Œ?ˆì´ ?œë‚˜ë¦¬ì˜¤
  String _scenarioKeyword = "";
  String _scenarioSituation = "";
  String _scenarioAiRole = "";
  String _scenarioUserRole = "";
  bool _isGeneratingScenario = false;
  bool _isAiOpenerPlaying = false; // AI ì²?ë°œí™” ?¬ìƒ ì¤??¬ë?

  String get _roleplayPartnerLabel {
    final local = _scenarioAiRole.trim();
    if (local.isNotEmpty) return local;
    final stored = _RoleplayScenarioStore.aiRole.trim();
    return stored.isNotEmpty ? stored : 'the roleplay partner';
  }

  String get _roleplayUserLabel {
    final local = _scenarioUserRole.trim();
    if (local.isNotEmpty) return local;
    final stored = _RoleplayScenarioStore.userRole.trim();
    return stored.isNotEmpty ? stored : 'the user';
  }

  // ?€?€ Idle Timeout v2 ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
  // ê¸°ì?: "? ì???AI???„ë¬´ ?‘ë™???†ëŠ” ?íƒœ"ê°€ ?°ì† 60ì´?ì§€?ë˜ë©?pause.
  //  - AI ?‘ë™ = _ttsQueueManager.isBusy (TTS ?¬ìƒ/?€ê¸?
  //  - ? ì? ?‘ë™ = _voiceManager != null (ë§ˆì´???°ê²°/?¹ìŒ)
  // 1ì´?ì£¼ê¸° ê°ì‹œ ?€?´ë¨¸ê°€ ?‘ë™ ?¬ë?ë¥?ë³´ê³  idle ?„ì ì´ˆë? ì¦ê°?œë‹¤.
  Timer? _idlePauseTimer;
  List<String> _lastExchangeMsgIds = []; // [?•ì •] ì§ì „ êµí™˜ messages docId
  bool _showCorrectionPopup = false; // [?•ì •] ?ì—… ?œì‹œ ?íƒœ
  Timer? _correctionPopupTimer; // [?•ì •] ?ì—… ?ë™ ì¢…ë£Œ ?€?´ë¨¸
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
      BillingTicker.instance.resume();
      BillingTicker.instance.logMode('roleplay');
    }
    _idlePauseTimer?.cancel();
    _idlePauseTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _idleTick());
  }

  void _idleTick() {
    if (!mounted) return;
    // ?”’ [?¤í† ?¬ì¦ˆ ê°€?? ìµœìƒ??active routeê°€ ?„ë‹ˆë©??¤ë¥¸ ?˜ì´ì§€ê°€ ?„ì—) idle ?„ì  ê¸ˆì?
    if (ModalRoute.of(context)?.isCurrent == false) {
      _idleElapsedSec = 0;
      return;
    }
    if (_isIdlePaused) return;
    // ? ì???AIê°€ ?‘ë™ ì¤‘ì´ë©?idle ?„ì ??ë©ˆì¶”ê³?ë¦¬ì…‹
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
    _correctionPopupTimer?.cancel();
    _idlePauseTimer = null;
    _correctionPopupTimer = null;
    _idleElapsedSec = 0;
  }
  // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€

  Widget _buildIdleBanner() => const SizedBox.shrink();

  Widget _buildIdleOverlay() => const SizedBox.shrink();

  // [?•ì • ?ì—…] 2ì´??œì‹œ ???ë™ ì¢…ë£Œ
  void _triggerCorrectionPopup() {
    _correctionPopupTimer?.cancel();
    if (mounted) setState(() => _showCorrectionPopup = true);
    _correctionPopupTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showCorrectionPopup = false);
    });
  }

  Widget _buildCorrectionPopup() {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _showCorrectionPopup ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 250),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                '?¬ë°”ë¥´ê²Œ ë§í•˜ì§€ ëª»í–ˆ?´ìš”.\n?¤ì‹œ ë§í•´ì£¼ì„¸??,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€

  // ?¤ë””??ë°?UI
  final List<Map<String, dynamic>> _localMessages = [];
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  DateTime? _lastScrollThrottle;
  DeepgramV2VoiceManager? _voiceManager;
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final TtsQueueManager _ttsQueueManager;
  late HybridTtsPlayer hybridTtsPlayer;

  // ?±ï¸ ?±ëŠ¥ ì¸¡ì •??ì´ˆì‹œê³?
  final Stopwatch _swDeepgram = Stopwatch();
  final Stopwatch _swOpenAI = Stopwatch();
  final Stopwatch _swTTS = Stopwatch();
  // ?±ï¸ latency ?¸ë? ì¸¡ì •
  final Stopwatch _swSpeechEnd = Stopwatch(); // ë°œí™” ?•ì • ?œì  ê¸°ì?
  int _msGptFirstToken = 0;
  int _msGptStreamEnd = 0;
  String _debugResult = "?±ï¸ ?€ê¸?ì¤?;

  @override
  void initState() {
    super.initState();
    _ttsQueueManager = TtsQueueManager(onPlayStart: () {
      if (_swTTS.isRunning) {
        _swTTS.stop();
        if (mounted) {
          setState(() {
            _debugResult =
                "?±ï¸ ?•ì •: ${_swDeepgram.elapsedMilliseconds}ms | ?? ${_swOpenAI.elapsedMilliseconds}ms | ?? ${_swTTS.elapsedMilliseconds}ms";
          });
        }
      }
    });

    _initPermissions();
    _fetchKeysAndInit();
    BillingTicker.instance.setRate(BillingRate.full);
    BillingTicker.instance.resume();
    BillingTicker.instance.logMode('roleplay');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resetIdleTimer();
    });
  }

  /// ?˜ê???ëª¨ë“  ê²½ë¡œ?ì„œ ?¸ì¶œ: chat_json + last_message ?€??(?ìƒ‰ ?†ì´ ?œìˆ˜ ?€?¥ë§Œ)
  Future<void> _forceSaveToFirestore() async {
    if (_myHistoryRef == null) return;
    String lastMsg = "?€???´ì—­???†ìŠµ?ˆë‹¤.";
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
      debugPrint("???ˆìŠ¤? ë¦¬ ?ë™ ?€???±ê³µ");
    } catch (e) {
      debugPrint("???ˆìŠ¤? ë¦¬ ?€??ì¤??¤ë¥˜: $e");
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
        // ?›¡ï¸?[v4 ê°€?? ?¸íŒ…???œë‚˜ë¦¬ì˜¤ê°€ ?ˆìœ¼ë©??¬ì§„????ë³´ì¡´, ?†ìœ¼ë©????œì•ˆ
        if (_RoleplayScenarioStore.situation.isNotEmpty &&
            _RoleplayScenarioStore.aiRole.isNotEmpty &&
            _RoleplayScenarioStore.userRole.isNotEmpty) {
          setState(() {
            _scenarioSituation = _RoleplayScenarioStore.situation;
            _scenarioAiRole = _RoleplayScenarioStore.aiRole;
            _scenarioUserRole = _RoleplayScenarioStore.userRole;
            _scenarioKeyword = _RoleplayScenarioStore.situation;
          });
        } else {
          _generateScenario();
        }
      }
    } catch (e) {
      print('??Key Load Error: $e');
    }
  }

  // ====================================================================
  // ?“¦ [Box 4-A: ?œë¼ë§??í™” ?¥ë©´ ê¸°ë°˜ ?œë‚˜ë¦¬ì˜¤ ?ë™ ?ì„±]
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
        // ?›¡ï¸?[v4] ?¬ì§„??ë³´ì¡´???€???™ê¸°??
        _RoleplayScenarioStore.situation = _scenarioSituation;
        _RoleplayScenarioStore.aiRole = _scenarioAiRole;
        _RoleplayScenarioStore.userRole = _scenarioUserRole;
      }
    } catch (e) {
      print('???œë‚˜ë¦¬ì˜¤ ?ì„± ?ëŸ¬: $e');
    } finally {
      if (mounted) setState(() => _isGeneratingScenario = false);
    }
  }

  // ====================================================================
  // ?“¦ [Box 4: ?œë‚˜ë¦¬ì˜¤ ?¤ì • ??? ì? ì§ì ‘ ?…ë ¥]
  // ====================================================================
  void _showSituationInputSheet() {
    if (_isConversationActive) return;
    final situationCtrl = TextEditingController(text: _scenarioSituation);
    final aiRoleCtrl = TextEditingController(text: _scenarioAiRole);
    final userRoleCtrl = TextEditingController(text: _scenarioUserRole);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, _) => Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF0A1A0D),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('?í™© ?¤ì •',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text('?í™©ê³???• ???…ë ¥?˜ë©´ ë°”ë¡œ ë¡¤í”Œ?ˆì´ê°€ ?œì‘?©ë‹ˆ??',
                        style: TextStyle(color: Colors.white38, fontSize: 12)),
                    const SizedBox(height: 20),
                    _inputField(situationCtrl, '?í™© (10-15??', '?? ?¨ê²¨???ˆë‹¤ë°??¤í‚´'),
                    const SizedBox(height: 12),
                    _inputField(aiRoleCtrl, '?ë? ??• ', '?? ?”ë‚œ ë°°ìš°??),
                    const SizedBox(height: 12),
                    _inputField(userRoleCtrl, '????• ', '?? ?¹í™©???¨í¸'),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: () {
                          final sit = situationCtrl.text.trim();
                          final ai = aiRoleCtrl.text.trim();
                          final user = userRoleCtrl.text.trim();
                          if (sit.isEmpty || ai.isEmpty || user.isEmpty) return;
                          Navigator.pop(ctx);
                          setState(() {
                            _scenarioSituation = sit;
                            _scenarioAiRole = ai;
                            _scenarioUserRole = user;
                            _scenarioKeyword = sit;
                            _sessionDocId = null;
                            _myHistoryRef = null;
                            _localMessages.clear();
                            _isConversationActive = false;
                          });
                          // ?›¡ï¸?[v4] ? ì? ?˜ì •ê°?ë³´ì¡´???€???™ê¸°??
                          _RoleplayScenarioStore.situation = sit;
                          _RoleplayScenarioStore.aiRole = ai;
                          _RoleplayScenarioStore.userRole = user;
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF16A34A), Color(0xFF22C55E)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Center(
                            child: Text('?•ì¸',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _inputField(TextEditingController ctrl, String label, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF86EFAC),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
            filled: true,
            fillColor: const Color(0xFF0D200F),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF16A34A)),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

// ====================================================================
// ?“¦ [Box 5: Deepgram + Relay Pipeline] ???µì‹ ë¡œì§ ë°•ìŠ¤ì½”ë“œ?€ ?„ì „ ?¼ì¹˜
// ====================================================================
  // [?”ë ˆ?„ë¡¬?„í„° v1] ?„ì¬ ë²„ë¸”???”ë©´ ì¤‘ì•™(0.45)?¼ë¡œ ë¶€?œëŸ½ê²??´ë™.
  //   ?ìŠ¤??ê¸¸ì´ ê¸°ë°˜ ?™ì  duration: ì§§ìœ¼ë©??ê¸‹(700ms), ê¸¸ë©´ ë¹ ë¥´ê²?150ms).
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

  // ?„ì¬ AI ë²„ë¸”???”ë©´ ì¤‘ì•™??ê³ ì • (?¤íŠ¸ë¦¬ë° ì¤?ë°€ë¦?ë°©ì?)
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

  // ?„ì¬ ?€?¬ë? ?”ë©´ ë§??„ì— ê³ ì • ??Scrollable.ensureVisible ê¸°ë°˜
  void _scrollToCurrentTop(int index) {
    final role = (index >= 0 && index < _localMessages.length)
        ? (_localMessages[index]['role'] ?? '')
        : '';
    _log('?§­ [SCROLL-TOP]', 'index=$index role=$role');
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
    _isConversationActive = false;
    _isAiOpenerPlaying = false;
    _commitTimer?.cancel(); // ?”§ [v3.4] ?€ê¸?ì¤??€?´ë¨¸ ?•ë¦¬
    _commitTimer = null;
    _pendingTranscript = ''; // ?€ê¸?ì¤?ë°œí™”??ë²„ë¦¼
    _voiceManager?.dispose();
    _voiceManager = null;
    _ttsQueueManager.stop();
    if (mounted) setState(() {});
  }

  // ====================================================================
  // ?“¦ [AI ì²?ë°œí™” ??AIê°€ ë¨¼ì? ?€???œì‘]
  // ====================================================================
  // ?¯ [ë¡¤í”Œ?ˆì´ ?€???œì‘ 3?ì¹™] (ì½”ë“œ ?•ì±… ?”ì•½)
  //
  // ?ì¹™ 1. AIê°€ ??ƒ ë¨¼ì? ë§ì„ ?œì‘?œë‹¤.
  //         ? ì?ê°€ ë§ˆì´??ë²„íŠ¼???„ë¥´ë©?AIê°€ ?¤í”„??ë©˜íŠ¸ë¥?ë¨¼ì? ë°œí™”.
  //         AI ë°œí™” ?„ë£Œ ??ë§ˆì´??ì²?·¨ê°€ ?œì‘??
  //
  // ?ì¹™ 2. ?€ê²??¸ì–´(targetLang)ë¡œë§Œ ë§í•œ??
  //         ai_role / user_role ?´ë¦„???œê?ë¡?ì£¼ì–´?¸ë„
  //         ?¤ì œ AI ?€?¬ëŠ” ë°˜ë“œ??targetLang?¼ë¡œë§?ì¶œë ¥.
  //         ?œêµ­????ëª¨êµ­?´ë? ?ˆë? ?ì? ?ŠëŠ”??
  //
  // ?ì¹™ 3. ?´ë‹¹ ??• ???¤ì œ ?„ì‹¤?ì„œ ê°€??ë¨¼ì? ??ë²•í•œ ?ì—°?¤ëŸ¬??ë§ë¡œ ?œì‘.
  //         ?´ìƒ‰???™ìŠµ???¸ì‚¬ X, ê·???• Â·?í™©????ë§ëŠ” ?„ì‹¤??êµ¬ì–´ì²?O.
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
        _scrollToBottom();
      }
      final int aiIndex = _localMessages.length - 1;

      String openerText = '';
      String openerBuffer = '';
      final RegExp splitPattern = RegExp(r'[,\.?!;:?‚ã€ï¼ï¼Ÿâ€?¼Œï¼›ï¼š\n]');

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
              _log('?”Š [TTS-SKIP] [AI]', '?˜ë? ?†ëŠ” TTS ì¡°ê° skip: "$cleaned"');
            } else {
              aiTtsFetcher.addText(cleaned);
            }
          }
        }
      }
      if (openerBuffer.trim().isNotEmpty) {
        final cleanedOpener = _cleanText(openerBuffer.trim());
        if (isMeaninglessTtsText(cleanedOpener)) {
          _log('?”Š [TTS-SKIP] [AI]', '?˜ë? ?†ëŠ” TTS ì¡°ê° skip: "$cleanedOpener"');
        } else {
          aiTtsFetcher.addText(cleanedOpener);
        }
      }

      // ??²ˆ??(?œêµ­???ë§‰)
      RoleplayBrain.generateCleanOriginal(
              apiKey: _openAiKey, englishText: openerText)
          .then((cleanKorean) {
        if (mounted && _localMessages.length > aiIndex) {
          setState(() => _localMessages[aiIndex]['original'] = cleanKorean);
        }
      });

      // TTS ?¬ìƒ ?„ë£Œ ?€ê¸?
      int waitTicks = 0;
      while ((aiTtsFetcher.pendingRequests > 0 || _ttsQueueManager.isBusy) &&
          _isConversationActive) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (++waitTicks > 200) break;
      }

      // chat_history ?€??
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
      _log('??[OPENER-ERR]', 'AI Opener Error: $e');
    } finally {
      _isAiOpenerPlaying = false;
      if (mounted && _isConversationActive) {
        _startDeepgramListening();
      }
    }
  }

  // [?•ì •] ì§ì „ ?˜ëª»??êµí™˜(HOST+SYSTEM)??chat_history?ì„œ ?œê±°
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
      _log('[HIST-DEL]', '?˜ëª»??êµí™˜ ${ids.length}ê±??ˆìŠ¤? ë¦¬ ?œê±°');
    } catch (e) {
      _log('[HIST-DEL-ERR]', '?ˆìŠ¤? ë¦¬ ?œê±° ?¤íŒ¨: $e');
    }
  }

  void _removeLastExchange() {
    // ê°€??ìµœê·¼ SYSTEM(AI) ë²„ë¸” ?¸ë±???ìƒ‰
    int lastSystemIdx = -1;
    for (int i = _localMessages.length - 1; i >= 0; i--) {
      if (_localMessages[i]['role'] == 'SYSTEM') {
        lastSystemIdx = i;
        break;
      }
    }

    // SYSTEM ???†ìœ¼ë©??„ì²´ ???ì„œ ê°€??ìµœê·¼ HOST ë²„ë¸” ?ìƒ‰
    int lastHostIdx = -1;
    int searchFrom =
        lastSystemIdx >= 0 ? lastSystemIdx - 1 : _localMessages.length - 1;
    for (int i = searchFrom; i >= 0; i--) {
      if (_localMessages[i]['role'] == 'HOST') {
        lastHostIdx = i;
        break;
      }
    }

    // ?¸ë±?¤ê? ??ê²ƒë????œê±° (?¸ë±??ë°€ë¦?ë°©ì?)
    if (lastSystemIdx >= 0) _localMessages.removeAt(lastSystemIdx);
    if (lastHostIdx >= 0) _localMessages.removeAt(lastHostIdx);
  }

  // AIê°€ ?‘ë‹µ?˜ê¸° ?„ì— ì¤‘ë‹¨??"ê³ ì•„ HOST ë²„ë¸”" ?œê±°
  // ?????œì‘ ???¸ì¶œ?˜ì—¬ ì§ì „ ?¤ì¸??ì¤‘ë‹¨ ë©”ì‹œì§€ë¥??•ë¦¬
  void _removeOrphanedHostBubbles() {
    int lastSystemIdx = -1;
    for (int i = _localMessages.length - 1; i >= 0; i--) {
      if (_localMessages[i]['role'] == 'SYSTEM') {
        lastSystemIdx = i;
        break;
      }
    }
    // ë§ˆì?ë§?SYSTEM ?´í›„(?ëŠ” SYSTEM ?†ìœ¼ë©??„ì²´)??HOST ë²„ë¸” ??ˆœ ?œê±°
    for (int i = _localMessages.length - 1; i > lastSystemIdx; i--) {
      if (_localMessages[i]['role'] == 'HOST') {
        _localMessages.removeAt(i);
      }
    }
  }

  Future<void> _startDeepgramListening() async {
    if (_deepgramKey.isEmpty || !(await _audioRecorder.hasPermission())) return;
    _resetIdleTimer();
    _isConversationActive = true;
    if (mounted) {
      setState(() {
        _debugResult = "?±ï¸ ?£ëŠ” ì¤?..";
        _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
        _localMessages
            .add({'role': 'HOST_TEMP', 'target': '...', 'type': 'user_input'});
      });
      // HOST_TEMP("...")???¤í¬ë¡??¸ë¦¬ê±??†ìŒ ???¤ì œ HOST ë²„ë¸” ?±ì¥ ???¤í¬ë¡?
    }

    _log('?¤ [LISTEN-01]', '_startDeepgramListening ì§„ì…, VoiceManager ?ì„±');

    // ?Œ [v3.1] ë¡œë¹„?ì„œ ? ì?ê°€ ? íƒ??ëª¨êµ­??nativeLang)ë¡?Deepgram ?¸ì‹
    // ? ì?ê°€ ?œêµ­?´ë¡œ ë§í•˜ë©?Deepgram???œêµ­?´ë¡œ ?¸ì‹ ??Brain???ì–´ë¡?ë²ˆì—­
    final String nativeLang =
        FFAppState().nativeLang.isNotEmpty ? FFAppState().nativeLang : 'Korean';
    final String dgLangCode = _mapLanguageToCode(nativeLang);
    _log('?Œ [LANG]', 'nativeLang="$nativeLang" ??Deepgram code="$dgLangCode"');

    _voiceManager = DeepgramV2VoiceManager(
      apiKey: _deepgramKey,
      audioRecorder: _audioRecorder,
      langCode: dgLangCode,
      onLog: _log, // ?”¬ ë¡œê·¸ ??ì£¼ì…
      onConnected: () {
        _log('??[LISTEN-02]', 'onConnected ì½œë°± ?¤í–‰');
      },
      onTranscriptUpdate: (transcript) {
        BillingTicker.instance.resumeFromActivity('roleplay_stt_partial');
        _swDeepgram.reset();
        _swDeepgram.start();
      },
      onTurnEnded: (transcript, {bool speechFinal = false}) {
        BillingTicker.instance.resumeFromActivity('roleplay_stt_result');
        _lastTurnWasSpeechFinal = speechFinal;
        _log('?? [LISTEN-03]',
            'onTurnEnded ì½œë°± ?˜ì‹ : "$transcript" speechFinal=$speechFinal');
        _swDeepgram.stop();
        _stopMicAndProcess(transcript);
      },
      onError: (err) {
        _log('??[LISTEN-ERR]', 'Deepgram Error: $err');
        _stopEverything();
      },
    );
    _log('?¤ [LISTEN-04]', 'connectAndStart ?¸ì¶œ ì§ì „');
    await _voiceManager!.connectAndStart();
    BillingTicker.instance.resumeFromActivity('roleplay_mic_start');
    _log('?¤ [LISTEN-05]', 'connectAndStart ?„ë£Œ');
  }

  // speechFinal ?¬ë????°ë¥¸ ì¡°ê±´ë¶€ commit ?€ê¸??œê°„ ê³„ì‚°
  int _getCommitWaitMs() {
    if (_lastTurnWasSpeechFinal) {
      return COMMIT_WAIT_SPEECH_FINAL_MS;
    }
    return COMMIT_WAIT_UNCERTAIN_MS;
  }

  // ?”§ [v3.4] Deepgram speech_final/UtteranceEnd ?˜ì‹  ???¸ì¶œ??
  // ì¡°ê±´ë¶€ ?€ê¸°ì°½ ?ˆì—??ì¶”ê? ë°œí™” ?©ì¹˜ê¸????„ì „???ë‚˜ë©??Œì´?„ë¼???œì‘
  void _stopMicAndProcess(String transcript) async {
    _resetIdleTimer();
    final clean = transcript.trim();
    _log('?? [STOP-01]', 'speech_final ?˜ì‹ : "$clean" (len=${clean.length})');

    if (clean.length < 2) {
      _log('?? [STOP-02]', '?ˆë¬´ ì§§ìŒ ??ë¬´ì‹œ');
      return;
    }

    final waitMs = _getCommitWaitMs();

    // ?”§ ê¸°ì¡´ ?€ê¸?ì¤‘ì¸ ë°œí™”ê°€ ?ˆìœ¼ë©?ê³µë°±?¼ë¡œ ?°ê²° (?”ë“¬ê±°ë¦¼ ?©ì¹˜ê¸?
    if (_pendingTranscript.isEmpty) {
      _pendingTranscript = clean;
      _log('?? [STOP-03]',
          '? ê·œ ë°œí™” ?‘ìˆ˜. ${waitMs}ms ì¡°ê±´ë¶€ ?€ê¸°ì°½ ?œì‘ speechFinal=$_lastTurnWasSpeechFinal');
    } else {
      _pendingTranscript = '$_pendingTranscript $clean';
      _log('?? [STOP-04]',
          '?©ì¹˜ê¸? "$_pendingTranscript" (${waitMs}ms ì¡°ê±´ë¶€ ?€ê¸°ì°½ ë¦¬ì…‹)');
    }

    // UI: ?‘ìˆ˜??ë°œí™”ë¥?HOST_TEMP ?ì„ ???¤ì‹œê°?ë°˜ì˜
    if (mounted) {
      setState(() {
        _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
        _localMessages.add({
          'role': 'HOST_TEMP',
          'target': '...',
          'original': '...', // Deepgram ?ë¬¸ ?¨ê¸°ê¸?
          'type': 'user_input',
        });
      });
    }

    // ê¸°ì¡´ ?€?´ë¨¸ ì·¨ì†Œ (??ë°œí™”ê°€ ?”ìœ¼ë¯€ë¡??€ê¸°ì°½ ë¦¬ì…‹)
    _commitTimer?.cancel();

    // ì¡°ê±´ë¶€ ?€ê¸????Œì´?„ë¼???œì‘ ?ˆì•½
    _commitTimer = Timer(
      Duration(milliseconds: waitMs),
      () => _commitAndProcess(),
    );
  }

  // ?”§ [v3.4] 1.2ì´??€ê¸??????´ìƒ ë°œí™” ?†ìœ¼ë©??•ì • ???Œì´?„ë¼???œì‘
  void _commitAndProcess() async {
    final committed = _pendingTranscript.trim();
    _pendingTranscript = '';
    _commitTimer = null;

    if (committed.isEmpty) {
      _log('?? [COMMIT-00]', 'ë¹?ë°œí™” ??ë§ˆì´???¬ì‹œ??);
      if (_isConversationActive) _startDeepgramListening();
      return;
    }

    _log('?? [COMMIT-01]', '?•ì •: "$committed" ???Œì´?„ë¼???œì‘');
    _swSpeechEnd.reset();
    _swSpeechEnd.start();

    // ë§ˆì´??VoiceManager ?•ë¦¬
    await _voiceManager?.dispose();
    _voiceManager = null;
    _log('?? [COMMIT-02]', 'VoiceManager dispose ?„ë£Œ');

    _log('?? [COMMIT-03]', '_processRelayPipeline ?¸ì¶œ');
    _processRelayPipeline(committed);
  }

// ====================================================================
// ?“¦ [Box 5-A: ì¤‘ì•™ ?µì œ??- ë£¨í‹´ ?•ì„ "?œê°„ë²Œê¸° ë§ˆìˆ " ?¨í„´]
// ====================================================================
// ?¯ ?µì‹¬ ?„ëµ:
//   STEP 1: ì¦ë°œ ê²€??(ê³ ìŠ¤?¸ì›Œ???ˆë¬´ ì§§ìŒ ??ì¡°ìš©???ê¸°)
//   STEP 2: HOST ?ì„  + ? ì? ë²ˆì—­ ?¤íŠ¸ë¦¬ë° (CoT ì£¼ì–´ ë³µì›)
//   STEP 3: ? ì? ?€ê²?TTS ?¬ìƒ ?œì‘ (_aiPaused=true)
//   STEP 4: (ë³‘ë ¬) AI ?‘ë‹µ ?¤íŠ¸ë¦¬ë° + ì²?‚¹ ?????ì¬ (?¬ìƒ ?€ê¸?
//   STEP 5: ? ì? ??… ?„ë£Œ ??_aiPaused=false ??AI ì²?¬ ??°œ
//   STEP 6: AI ??²ˆ??+ Firestore ?€??(ë°±ê·¸?¼ìš´??
//   STEP 7: ë§ˆì´???¬ê°œë°?
// ====================================================================
  String _retryPhrase(String lang) {
    switch (lang.toLowerCase()) {
      case 'korean':
        return '?¤ì‹œ ë§ì???ì£¼ì„¸??';
      case 'japanese':
        return '?‚ã†ä¸€åº¦ãŠé¡˜ã„?—ã¾?™ã€?;
      case 'chinese':
        return 'è¯·å†è¯´ä??ã€?;
      case 'french':
        return 'Pardon?';
      case 'spanish':
        return 'Â¿PerdÃ³n?';
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
    _log('?§  [PIPE-01]',
        'Pipeline ?œì‘ turn=$_turnCounter input="$finalTranscript"');

    // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
    // STEP 1: ì¦ë°œ ê²€??(UI ?ì„  ì°ê¸° ??
    // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
    String lowerClean =
        finalTranscript.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    List<String> ghostWords = [
      'thank you',
      'thanks',
      'yeah',
      'okay',
      'ê°ì‚¬?©ë‹ˆ??,
      '??,
      '??
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
      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      // STEP 2: HOST ?ì„  ?ì„± + ? ì? ë²ˆì—­ ?¤íŠ¸ë¦¬ë°
      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      if (mounted) {
        setState(() {
          _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
          _removeOrphanedHostBubbles(); // AI ?‘ë‹µ ?†ì´ ì¤‘ë‹¨???´ì „ HOST ë²„ë¸” ?œê±°
          _localMessages.add({'role': 'HOST', 'target': '', 'original': ''});
        });
        _scrollToBottom();
      }

      int hostIndex = _localMessages.length - 1;

      // ?„ì„±???´ë§Œ ì»¨í…?¤íŠ¸???¬í•¨ (ë¯¸ì™„??'...' ?œì™¸)
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
      _ttsQueueManager.setAiPaused(false); // ? ì? ì²?¬??ì¦‰ì‹œ ?¬ìƒ

      // ?Œ [v3.1] ë¡œë¹„?ì„œ ? ì?ê°€ ? íƒ???€ê²??¸ì–´ë¡?ë²ˆì—­
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
      );

      bool evaporated = false;
      bool clarified = false; // ì£¼ì–´/ëª©ì ??ëª¨í˜¸ ??AI ?˜ë¬»ê¸?
      bool corrected = false; // ? ì?ê°€ AI???¤í•´ë¥??•ì • ??ì§ì „ êµí™˜ ?? œ ???¬ì²˜ë¦?
      bool misheard = false; // ?˜ëª» ?¤ì—ˆ?¤ëŠ” ë¶ˆë§Œë§??ˆìŒ ??ì§ì „ êµí™˜ ?? œ ???¬ì²­ì·?
      bool dissatisfiedReply = false; // AI ì§ì „ ?‘ë‹µ ë¶ˆë§Œ ???‘ë‹µë§??¬ìƒ??
      // [USER-FULL-TTS] firstChunkSent removed; user TTS fires once after stream end.
      await for (String chunk in userStream) {
        userTargetText += chunk;

        // ?”§ [v3.3] ?„ì ???„ì²´ ?ìŠ¤?¸ì—??EVAPORATE ê°ì? (?¤íŠ¸ë¦?ì¡°ê° ë¶„í•  ?€??
        if (userTargetText.contains("[EVAPORATE]")) {
          evaporated = true;
          _log('? ï¸ [EVAPORATE]', 'ì¦ë°œ ê°ì? ????ì·¨ì†Œ');
          break;
        }
        // ?”„ [CORRECTION] ?•ì • ê°ì? (?¬ì§„????ë¬´ì‹œ)
        if (!isCorrectionRetry && userTargetText.contains("[CORRECTION]")) {
          corrected = true;
          _log('?”„ [CORRECTION]', '?•ì • ê°ì? ??ì§ì „ êµí™˜ ?? œ ???¬ì‹œ??);
          break;
        }
        // ?‘‚ [MISHEARD] ?˜ëª» ?¤ì—ˆ?¤ëŠ” ë¶ˆë§Œë§??ˆìŒ
        if (!isCorrectionRetry && userTargetText.contains("[MISHEARD]")) {
          misheard = true;
          _log('?‘‚ [MISHEARD]', '?¤ì²­ì·?ë¶ˆë§Œ ê°ì? ??ì§ì „ êµí™˜ ?? œ ???¬ì²­ì·?);
          break;
        }
        // ?Ÿ£ [DISSATISFIED] AI ì§ì „ ?‘ë‹µ???€??ë¶ˆë§Œ ???¤ë¥¸ ?‘ë‹µ ?¬ìƒ??
        if (userTargetText.contains("[DISSATISFIED]")) {
          dissatisfiedReply = true;
          _log('?Ÿ£ [DISSATISFIED]', '?‘ë‹µ ë¶ˆë§Œ ê°ì? ??ì§ì „ ?‘ë‹µ ?? œ ???¬ìƒ??);
          break;
        }

        // ?˜ë¬»ê¸?ê°ì?: ì£¼ì–´/ëª©ì ??ëª¨í˜¸ ??AI In-Character ?˜ë¬»ê¸?
        if (userTargetText.contains("[CLARIFY]")) {
          clarified = true;
          _log('??[CLARIFY]', '?˜ë¬»ê¸?ê°ì? ??clarification ì²˜ë¦¬');
          break;
        }
        if (mounted)
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

      // ?”„ [CORRECTION] ? ì?ê°€ AI???¤í•´/?¤ì²­ì·¨ë? ?•ì • ??ì§ì „ êµí™˜ ?? œ ???¬ì²˜ë¦?
      if (corrected) {
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length &&
                _localMessages[hostIndex]['role'] == 'HOST') {
              _localMessages.removeAt(hostIndex); // ë°©ê¸ˆ ë§Œë“  ?„ì¬ HOST ë²„ë¸” ?œê±°
            }
            _removeLastExchange(); // ì§ì „ HOST(?¤í•´ ë°œí™”)+SYSTEM(?€ë¦??‘ë‹µ) ?œê±°
          });
          if (_localMessages.isNotEmpty) _scrollToBottom();
        }
        _ttsQueueManager.stop();
        _ttsQueueManager.setUserTurn(false);
        // ?•ì •??ë°œí™”ë¡??¬ì²˜ë¦?(?¬ì§„?…ì´ë¯€ë¡?[CORRECTION] ?¬ê°ì§€ ????
        await _deleteLastExchangeFromHistory();
        _processRelayPipeline(finalTranscript, isCorrectionRetry: true);
        return;
      }

      // ?‘‚ [MISHEARD] ?˜ëª» ?¤ì—ˆ?¤ëŠ” ë¶ˆë§Œë§??ˆìŒ ??ì§ì „ êµí™˜ ?? œ ???¬ì²­ì·?
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
        _triggerCorrectionPopup();
        await Future.delayed(const Duration(seconds: 2));
        if (mounted && _isConversationActive) _startDeepgramListening();
        return;
      }

      // ?Ÿ£ [DISSATISFIED] AI ì§ì „ ?‘ë‹µ ë¶ˆë§Œ ??ì§ì „ SYSTEMë§??œê±°?˜ê³  ê°™ì? ë°œí™”ë¡??¬ìƒ??
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
        regenPhraseTts.addText("ê·¸ëŸ¼ ?¤ì‹œ ?µí•´ ë³¼ê²Œ??");
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

      // ??[CLARIFY] ? ì? ë°œí™” ì£¼ì–´/ëª©ì ??ëª¨í˜¸ ??In-Character ?˜ë¬»ê¸?+ STT ?¬ì‹œ??
      if (clarified) {
        _turnCounter--;
        final clarifyText =
            userTargetText.replaceFirst(RegExp(r'^\[CLARIFY\]\s*'), '');
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length)
              _localMessages.removeAt(hostIndex);
            _localMessages
                .add({'role': 'SYSTEM', 'target': clarifyText, 'original': ''});
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

      // [USER-FULL-TTS] fire the complete translated user sentence once.
      final String fullUserTts = _cleanText(userTargetText.trim());
      if (fullUserTts.isNotEmpty) {
        if (isMeaninglessTtsText(fullUserTts)) {
          _log('?”Š [TTS-SKIP] [USER]', '?˜ë? ?†ëŠ” TTS ì¡°ê° skip: "$fullUserTts"');
        } else {
          userTtsFetcher.addText(fullUserTts);
        }
      }

      // ?”§ [v3.7] ? ì? ?µë¬¸??TtsCache ë°±ê·¸?¼ìš´???€??(?ˆìŠ¤? ë¦¬ HIT ? ë„)
      //   - ì²?¬ë³?ìºì‹œë§Œìœ¼ë¡œëŠ” ?ˆìŠ¤? ë¦¬?ì„œ ?µë¬¸??GET??MISS??
      //   - fire-and-forget: ? ì? ?¬ìƒ ?ë¦„ê³?ë¬´ê??˜ê²Œ ë°±ê·¸?¼ìš´??ì²˜ë¦¬
      //   - voice/speed???ˆìŠ¤? ë¦¬ _playRhythmAudio?€ ?™ì¼?˜ê²Œ "nova", 1.0 ê³ ì •
      //   - _cleanText ?ìš©: translated_text?€ ?™ì¼???¤ë¡œ ?€??
      _saveUserFullSentenceToCache(_cleanText(userTargetText.trim()));

      // ? ì? ??²ˆ??(ë°±ê·¸?¼ìš´?? Future ë³´ê? ???€????await)
      final userOriginalFuture = RoleplayBrain.generateCleanOriginal(
          apiKey: _openAiKey, englishText: userTargetText);
      userOriginalFuture.then((cleanKorean) {
        if (mounted && _localMessages.length > hostIndex) {
          setState(() => _localMessages[hostIndex]['original'] = cleanKorean);
        }
      });

      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      // STEP 3 & 4 (ë³‘ë ¬): AI ?‘ë‹µ ë°±ê·¸?¼ìš´???ì„±
      //   ??AI ì²?¬???ì— ?“ì´ì§€ë§?_aiPaused=true???¬ìƒ ?€ê¸?
      //   ??? ì? TTS??ê³„ì† ?¬ìƒ ì¤?
      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      if (mounted) {
        setState(() => _localMessages
            .add({'role': 'SYSTEM', 'target': '', 'original': ''}));
        // ë¹?AI ë²„ë¸”?€ ?¤í¬ë¡??†ìŒ ??ì²?? íš¨ ì²?¬ ??_scrollToCurrentTop ?¸ì¶œ
      }
      int aiIndex = _localMessages.length - 1;

      // ?”§ [v3.2 ë²„ê·¸ ?˜ì •] setUserTurn(false)??? ì? ?¬ìƒ ?„ë£Œ ?„ë¡œ ?´ë™
      // ?„ì¬ ?œì ?ì„œ ? ì? TTSê°€ ?„ì§ ?¬ìƒ ì¤‘ì¸??_isUserTurn=falseë¡?ë°”ê¾¸ë©?
      // TtsQueueManager._processQueueê°€ 'AI ?´ì´ê³?paused' ?ë‹¨?˜ì—¬ ? ì? ë§ˆì?ë§?ì²?¬ê¹Œì? ë©ˆì¶°ë²„ë¦¼
      _ttsQueueManager.setAiPaused(true); // AI ?¬ìƒ ?€ê¸?ëª¨ë“œ (? ì? TTS??ê³„ì† ?¬ìƒ)
      // ?”§ [v3.5] AI ?„ìš© ?ë¡œ ë³´ë‚´ê¸??„í•´ isUser: false ëª…ì‹œ
      ChunkedTtsFetcher aiTtsFetcher = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        "nova",
        isUser: false, // AI ?ë¡œ ë¶„ë¦¬
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

      _log('?§  [PIPE-02]', 'AI ?¤íŠ¸ë¦??”ì²­: userText="$userTargetText"');

      final aiStream = RoleplayBrain.streamRoleplayResponse(
        apiKey: _openAiKey,
        userTargetText: userTargetText,
        contextStr: latestContextStr,
        situation: _scenarioSituation,
        aiRole: _scenarioAiRole,
        userRole: _scenarioUserRole,
        myTarget: targetLangName, // ?Œ [v3.1] ? ì?ê°€ ? íƒ???€ê²??¸ì–´
      );

      // AI ?ì„±+ì²?‚¹??Futureë¡?(? ì? ?¬ìƒê³?ë³‘ë ¬)
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
            _log('?§  [PIPE-03]', 'GPT ì²?? íš¨ ì²?¬ ?˜ì‹ : "$cleanedChunk"');
            _firstAiChunkLogged = true;
            _scrollToBottom();
          }
          if (_swOpenAI.isRunning) _swOpenAI.stop();
          aiTargetText += cleanedChunk;
          aiBuffer += cleanedChunk;

          // [RETRY] ? í˜¸ ê°ì? ??ë°œìŒ ë¶ˆëª… ?ëŠ” ë¬¸ë§¥ ?´ìƒ
          if (aiTargetText.contains('[RETRY]')) {
            aiRetry = true;
            _log('?” [RETRY-DET]', '[RETRY] ê°ì? ???¬ì²­ì·?ëª¨ë“œ');
            break;
          }

          if (mounted && !_ttsQueueManager.aiPaused) {
            setState(() => _localMessages[aiIndex]['target'] = aiTargetText);
            _scrollToBottomThrottled();
          }

          // ?˜ì´ë¸Œë¦¬?? ì²?êµ¬ë‘??OR 5?¨ì–´ ?„ë‹¬ ??1?Œë§Œ firstChunk ì¦‰ì‹œ ë°œì‚¬
          // Rollback: hybridTtsPlayer ?œê±° ??aiTtsFetcher.addText(toSpeak) ë³µì›
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
          // ?´í›„ ì²?¬??aiBuffer???„ì ë§???onStreamEnd?ì„œ remainder ì²˜ë¦¬
        }
        _msGptStreamEnd = _swSpeechEnd.elapsedMilliseconds;
        // AI remainder TTS ???ì¬ ??? ì? TTS ?¬ìƒê³?ë³‘ë ¬ë¡?ì¤€ë¹?(?¤ì œ ?¬ìƒ?€ setAiPaused(false) ??
        if (!aiRetry && aiTargetText.trim().isNotEmpty) {
          await hybridTtsPlayer.onStreamEnd(
            fullSentence: _cleanText(aiTargetText.trim()),
            remainderBuffer: aiBuffer,
            fetcher: aiTtsFetcher,
            swSpeechEnd: _swSpeechEnd,
          );
          _log('?§  [PIPE-08A]',
              'AI stream end + remainder queued. pending=${aiTtsFetcher.pendingRequests}');
        }
      }();

      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      // STEP 5: ? ì? TTS ëª¨ë‘ ?¬ìƒ???Œê¹Œì§€ ?€ê¸?
      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      _log('?§  [PIPE-04]',
          '? ì? TTS ?€ê¸??œì‘. pending=${userTtsFetcher.pendingRequests}');

      int waitTicks = 0;
      while (userTtsFetcher.pendingRequests > 0) {
        await Future.delayed(const Duration(milliseconds: 50));
        waitTicks++;
        if (waitTicks > 200) {
          // 10ì´??€?„ì•„??
          _log('? ï¸ [PIPE-TIMEOUT]', '? ì? TTS fetch 10ì´?ì´ˆê³¼, ê°•ì œ ì§„í–‰');
          break;
        }
      }
      _log(
          '?§  [PIPE-05]', '? ì? TTS fetch ?„ë£Œ. isBusy=${_ttsQueueManager.isBusy}');

      // ?”’ [Box 7 USER-DRAIN-SIGNAL] ?¤ì œ ê¸°ë°˜ drain ê²Œì´??
      //   ë§ˆì?ë§?? ì? ì²?¬??ë§ˆì?ë§??˜í”Œ ?¬ìƒ ?„ë£Œ ì¦‰ì‹œ ?´ì œ?œë‹¤.
      //   isBusy ?´ë§ê³?ì²?¬ ?¬ì´ false ?„í—˜???œê±°?œë‹¤.
      _ttsQueueManager.sealUserStream();
      await _ttsQueueManager.waitUserDrained();
      _log('?§  [PIPE-06]', '? ì? TTS ?¬ìƒ ?„ë£Œ ??AI ??ê°œë°©');

// ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      // STEP 6: AI ??ê°œë°©
      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      // ?”§ [v3.3 ?ˆì „ ê°„ê²©] ? ì? TTS ?¬ìƒ ?„ë£Œ ì§í›„ 250ms ?€ê¸?
      // ?´ìœ : isBusy=falseê°€ ?˜ì—ˆ?´ë„ AudioPlayer ?´ë??ì„œ
      //       ë§ˆì?ë§??˜í”Œ???”ì½”???¬ìƒ ê¼¬ë¦¬ê°€ ?¨ì„ ???ˆì–´ ?Œë¦¬ ê²¹ì¹¨ ë°œìƒ
      //       250ms = ì²´ê°???ì—°?¤ëŸ¬??"??ê³ ë¥´ê¸? + ê²¹ì¹¨ ë°©ì?
      await Future.delayed(const Duration(milliseconds: 250));
      _log('?§  [PIPE-GAP]', '? ì?-AI ?„í™˜ ?ˆì „ ê°„ê²© 250ms ?„ë£Œ');

      // ???„í™˜
      _ttsQueueManager.setUserTurn(false);
      _ttsQueueManager.setAiPaused(false);
      _log('?§  [PIPE-07]', 'setUserTurn(false) + setAiPaused(false). AI ?¬ìƒ ?œì‘');
      // [v3.6] PIPE-07 ?œì : ë²„í¼??AI ?ìŠ¤???¼ê´„ ?œì‹œ
      if (mounted && aiTargetText.isNotEmpty) {
        setState(() => _localMessages[aiIndex]['target'] = aiTargetText);
        _scrollToBottom();
      }

      // AI ??²ˆ??(ë°±ê·¸?¼ìš´?? Future ë³´ê? ???€????await)
      final aiOriginalFuture = RoleplayBrain.generateCleanOriginal(
          apiKey: _openAiKey, englishText: aiTargetText);
      aiOriginalFuture.then((cleanKorean) {
        if (mounted && _localMessages.length > aiIndex) {
          setState(() => _localMessages[aiIndex]['original'] = cleanKorean);
          _log('?”¤ [BACK-TRANS]', 'AI ??²ˆ???„ë£Œ ??UI ë°˜ì˜');
        }
      });

      await aiGenerationTask;
      _log('?§  [PIPE-08]',
          'aiGenerationTask ?„ë£Œ. AI pending=${aiTtsFetcher.pendingRequests}');
      // [PIPE-08A] onStreamEnd??aiGenerationTask ?´ë??ì„œ ?„ë£Œ??(ì¤‘ë³µ ?¸ì¶œ ?†ìŒ)
      if (!aiRetry && aiTargetText.trim().isNotEmpty) {
        if (mounted) {
          setState(() {
            _debugResult += '\nGPT ì²?? í°: ${_msGptFirstToken}ms'
                '\nGPT ?¤íŠ¸ë¦?ì¢…ë£Œ: ${_msGptStreamEnd}ms'
                '\nì²?ì²?¬ ë°œì‚¬: ${hybridTtsPlayer.lastFirstChunkMs}ms'
                '\n?µë¬¸???€?? ${hybridTtsPlayer.lastCacheSaveMs}ms'
                ' | Cache: ${hybridTtsPlayer.lastCacheHit ? "HIT" : "MISS"}';
          });
        }
      }

      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      // [RETRY] ì²˜ë¦¬ ??AI ë²„ë¸” ?œê±° ???Œì„±?¼ë¡œë§??¬ì²­ì·??”ì²­
      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      if (aiRetry) {
        _ttsQueueManager.stop();
        if (mounted) {
          setState(() {
            if (aiIndex < _localMessages.length)
              _localMessages.removeAt(aiIndex);
          });
        }
        _log('?” [RETRY-ACT]', 'AI ë²„ë¸” ?œê±° + ?¬ì²­ì·?TTS ë°œí™”');
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
          // 15ì´??€?„ì•„??
          _log('? ï¸ [PIPE-TIMEOUT]', 'AI TTS 15ì´?ì´ˆê³¼, ê°•ì œ ì§„í–‰');
          break;
        }
      }
      _log('?§  [PIPE-09]', 'AI TTS ?¬ìƒ ?„ë£Œ');

      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      // STEP 7: ??²ˆ???„ë£Œ ?€ê¸???Firestore ?€??
      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
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
      _log('?§  [PIPE-10]', 'Firestore ?€???¸ì¶œ ?„ë£Œ');
    } catch (e) {
      _log('??[PIPE-ERR]', 'Relay Error: $e');
    } finally {
      _log('?§  [PIPE-END]',
          'finally ì§„ì…. active=$_isConversationActive turn=$_turnCounter/current=$currentTurnId mounted=$mounted');
      if (mounted && _isConversationActive && _turnCounter == currentTurnId) {
        _log('?§  [PIPE-RESTART]', 'ë§ˆì´???¬ì‹œ???œë„');
        _startDeepgramListening();
      } else {
        _log('? ï¸ [PIPE-NORESTART]', 'ë§ˆì´???¬ì‹œ??ì¡°ê±´ ë¶ˆì¶©ì¡?);
      }
    }
  }

  // ?”§ [v3.7] ? ì? ?µë¬¸??TtsCache ë°±ê·¸?¼ìš´???€???¬í¼
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

  /// ????? ì?+AI)??ChatLine 2ê°œë? Firestore???€??
  /// - _sessionDocIdê°€ null?´ë©´ ???¸ì…˜ ?ì„±
  /// - ?ˆìœ¼ë©?ê¸°ì¡´ ?¸ì…˜??transcript??arrayUnion?¼ë¡œ append
  Future<void> _saveTurnToFirestore(
      List<Map<String, dynamic>> chatLines) async {
    _log('?’¾ [SAVE-01]', '?€???œì‘. chatLines=${chatLines.length}ê°?);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _log('??[SAVE-ERR-A]', 'FirebaseAuth.currentUser == null (ë¡œê·¸???ˆë¨)');
        return;
      }
      final uid = user.uid;
      final firestore = FirebaseFirestore.instance;
      _log('?’¾ [SAVE-02]', 'uid=$uid, sessionDocId=$_sessionDocId');

      if (_sessionDocId == null) {
        // ì²??€???????¸ì…˜ ë¬¸ì„œ ?ì„±
        _log('?’¾ [SAVE-03]', 'ì²??€???????¸ì…˜ ?ì„± ?œë„');
        final userDocRef = firestore.collection('users').doc(uid);
        final userDoc = await userDocRef.get();
        final currentTotal = (userDoc.data()?['total_sessions'] as int?) ?? 0;
        final nextSessionNo = currentTotal + 1;
        _log('?’¾ [SAVE-04]',
            'total_sessions=$currentTotal ??next=$nextSessionNo');

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
        _log('?’¾ [SAVE-05]', '???¸ì…˜ ?ì„± ?„ë£Œ. docId=$_sessionDocId');

        await userDocRef.update({'total_sessions': nextSessionNo});
        _log('?’¾ [SAVE-06]', 'users ë¬¸ì„œ total_sessions ?…ë°?´íŠ¸ ?„ë£Œ');
      } else {
        // ê¸°ì¡´ ?¸ì…˜??append
        _log('?’¾ [SAVE-07]', 'ê¸°ì¡´ ?¸ì…˜??append ?œë„. docId=$_sessionDocId');
        await firestore
            .collection('users')
            .doc(uid)
            .collection('sessions')
            .doc(_sessionDocId)
            .update({
          'transcript': FieldValue.arrayUnion(chatLines),
        });
        _log('?’¾ [SAVE-08]', 'arrayUnion ?„ë£Œ');
      }
    } catch (e, stack) {
      _log('??[SAVE-ERR-B]', 'Firestore ?€???¤íŒ¨: $e');
      _log(
          '??[SAVE-STACK]',
          stack.toString().substring(0,
              stack.toString().length > 200 ? 200 : stack.toString().length));
    }
  }

  // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
  // ?”§ [?ˆìŠ¤? ë¦¬] chat_history ?€???¨ìˆ˜ 3ì¢?(Duo ?¨í„´ ë³µì œ)
  //   - sessions ?€??_saveTurnToFirestore)ê³?ë³‘í–‰
  //   - sessions???ˆë ¨ ë¶„ì„?? chat_history???ˆìŠ¤? ë¦¬ ë¦¬ìŠ¤?¸ìš©
  // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€

  /// chat_history ë°?ë¬¸ì„œ ë³´ì¥ (?†ìœ¼ë©??ì„±)
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
        'mode': 'roleplay', // ?†• [ROUTER-FIX] ?¼ìš°?°ê? Step Expandë¡??¤ì¸ ë°©ì?
        'scenario_situation': _scenarioSituation,
        'scenario_keyword': _scenarioKeyword,
        'user_role': _scenarioUserRole,
        'ai_role': _scenarioAiRole,
        'user_label': _roleplayUserLabel,
        'partner_label': _roleplayPartnerLabel,
        'is_pinned': false,
        'msg_count': 0
      });
      _myHistoryRef = newRef;
      _log('?“š [HIST-NEW]', 'chat_history ë°??ì„±: ${_myHistoryRef!.id}');
    }
  }

  /// ?´ë§ˆ??chat_history/messages ?œë¸Œì»¬ë ‰?˜ì— ê¸°ë¡ ë³‘í–‰ ?€??
  Future<void> _saveHistoryMessages(
      List<Map<String, dynamic>> chatLines) async {
    try {
      await _ensureHistoryRef();
      if (_myHistoryRef == null) return;

      // messages ?œë¸Œì»¬ë ‰?˜ì— ê°?ë°œí™” ?€??
      final List<String> savedIds = [];
      for (final line in chatLines) {
        final translated = (line['translated_text'] ?? '').toString().trim();
        if (translated.isEmpty) continue;
        final addedRef = await _myHistoryRef!.collection('messages').add({
          'role': line['role'] ?? '',
          'translated_text': translated,
          'original_text': (FFAppState().nativeLang.isNotEmpty &&
                  FFAppState().nativeLang == FFAppState().targetLang)
              ? ''
              : (line['original_text'] ?? '').toString(),
          'created_at': FieldValue.serverTimestamp(),
        });
        savedIds.add(addedRef.id);
      }
      if (savedIds.isNotEmpty) {
        _lastExchangeMsgIds = List<String>.from(savedIds);
      }

      // ?”§ [?µì‹¬] ?´ë§ˆ??msg_count/last_message ?…ë°?´íŠ¸
      final lastTranslated = chatLines
          .map((l) => (l['translated_text'] ?? '').toString().trim())
          .lastWhere((t) => t.isNotEmpty, orElse: () => '');
      if (lastTranslated.isNotEmpty) {
        await _myHistoryRef!.update({
          'msg_count': FieldValue.increment(chatLines.length),
          'last_message': lastTranslated,
          'last_active': FieldValue.serverTimestamp(),
        });
        _log('?’¾ [HIST-UPD]',
            'msg_count+${chatLines.length}, last="$lastTranslated"');
      }
    } catch (e) {
      _log('??[HIST-ERR]', 'chat_history ?€???¤íŒ¨: $e');
    }
  }

  /// ?¤ë¡œê°€ê¸??? ë¹?ë°???ŒŒ or last_message ?…ë°?´íŠ¸ ???˜ê?ê¸?
  Future<void> _handleAutoSaveAndExit() async {
    BillingTicker.instance.pause();
    try {
      if (_myHistoryRef != null) {
        final hasUserTurn = _localMessages.any((m) => m['role'] == 'HOST');
        if (!hasUserTurn) {
          await _myHistoryRef!.delete();
          _log('?—‘ï¸?[HIST-DEL]', 'ë¹?ë°??? œ ?„ë£Œ');
        } else {
          String lastText = "?€??ê¸°ë¡ ?€??;
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
          _log('?’¾ [HIST-UPD]', 'last_message ?€??);
        }
      }
    } catch (e) {
      _log('??[HIST-EXIT-ERR]', '$e');
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
  // ?“¦ [Box 6: UI]
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
                  _buildIdleOverlay(),
                  _buildCorrectionPopup(),
                ],
              ),
            ),
            _buildControlArea(bottomPad),
          ]),
        ),
      ),
    );
  }

  // ... (_buildTopBar, _buildTopControls, _buildChatList, _buildTextBlock, _buildControlArea??ê¸°ì¡´ê³??™ì¼?˜ê²Œ ? ì?) ...
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: _handleAutoSaveAndExit, // ?”§ [?ˆìŠ¤? ë¦¬] AutoSave ?°ê²°
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 56,
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
            const SizedBox(width: 4),
            // [v3.6] ?”ì—¬?œê°„ ?œì‹œ + ê¸¸ê²Œ ?„ë¥´ë©?ë¡œê·¸ (ê°œë°œ?ìš©)
            GestureDetector(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
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
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      () {
                        final int s = (FFAppState().remainingTime)
                            .toInt()
                            .clamp(0, 999999);
                        final int h = s ~/ 3600;
                        final int m = (s % 3600) ~/ 60;
                        return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
                      }(),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
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
    final hasScenario =
        _scenarioSituation.isNotEmpty && _scenarioAiRole.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: (_isConversationActive || _isGeneratingScenario)
                ? null
                : _showSituationInputSheet,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0D2417), Color(0xFF071A0F)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: _isGeneratingScenario
                  ? const SizedBox(
                      height: 60,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF22C55E),
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : hasScenario
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(children: const [
                              Icon(Icons.theater_comedy_rounded,
                                  color: Color(0xFF86EFAC), size: 13),
                              SizedBox(width: 5),
                              Text(
                                'SITUATION',
                                style: TextStyle(
                                  color: Color(0xFF86EFAC),
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
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF16A34A)
                                    .withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFF16A34A)
                                      .withValues(alpha: 0.40),
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
                                          color: Color(0xFFBBF7D0), size: 13),
                                      SizedBox(width: 4),
                                      Text('AI',
                                          style: TextStyle(
                                            color: Color(0xFF86EFAC),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.4,
                                          )),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(_scenarioAiRole,
                                      style: const TextStyle(
                                        color: Color(0xFFDCFCE7),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      )),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0EA5E9)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFF0EA5E9)
                                      .withValues(alpha: 0.32),
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
                            if (!_isConversationActive) ...[
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: const [
                                  Icon(Icons.edit_outlined,
                                      color: Colors.white24, size: 13),
                                  SizedBox(width: 4),
                                  Text('??•˜???˜ì •',
                                      style: TextStyle(
                                          color: Colors.white24, fontSize: 11)),
                                ],
                              ),
                            ],
                          ],
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.movie_outlined,
                                  color: Color(0xFF86EFAC), size: 20),
                              SizedBox(width: 8),
                              Text('?œë‚˜ë¦¬ì˜¤ ë¶ˆëŸ¬?¤ëŠ” ì¤?..',
                                  style: TextStyle(
                                      color: Color(0xFF86EFAC),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
            ),
          ),
          if (!_isGeneratingScenario && !_isConversationActive) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: _generateScenario,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
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
                        Text('?¤ì‹œ ?ì„±',
                            style:
                                TextStyle(color: Colors.white30, fontSize: 12)),
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

    // ?„ì´ì½??„ë°”?€
    final Widget avatar = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isHost
            ? const Color(0xFF1D4ED8).withValues(alpha: 0.22)
            : const Color(0xFF16A34A).withValues(alpha: 0.22),
        shape: BoxShape.circle,
        border: Border.all(
          color: isHost
              ? const Color(0xFF60A5FA).withValues(alpha: 0.45)
              : const Color(0xFF4ADE80).withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: Icon(
        isHost ? Icons.person_rounded : Icons.smart_toy_rounded,
        color: isHost ? const Color(0xFF93C5FD) : const Color(0xFFBBF7D0),
        size: 17,
      ),
    );

    // ë§í’??
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
              const Text("Roleplay",
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              // Start ë²„íŠ¼: AI ??•  ?¤ì • ?„ë£Œ & ?€??ë¯¸ì‹œ???íƒœ
              if (_scenarioAiRole.isNotEmpty &&
                  _localMessages.isEmpty &&
                  !_isAiOpenerPlaying &&
                  !_isConversationActive)
                GestureDetector(
                  onTap: () {
                    if (_openAiKey.isEmpty) return;
                    _resetIdleTimer();
                    setState(() => _isConversationActive = true);
                    _generateAndPlayAiOpener();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF16A34A), Color(0xFF15803D)],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF16A34A).withValues(alpha: 0.35),
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
                // AI ì²?ë°œí™” ?¬ìƒ ì¤?
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
                // ?€??ì¤?on/off ? ê?
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
// ?™ï¸?[Box 7] ê³µí†µ ?µì‹  ?”ì§„ v3 ??ëª¨ë“  ëª¨ë“œ ê³µìœ 
// ====================================================================
// ?“‚ ?œë¸Œë°•ìŠ¤ êµ¬ì„±:
//   [Box 7-A] ConversationHistory  ???¬ë¼?´ë”© ?ˆë„???€??ê¸°ì–µ
//   [Box 7-B] DeepgramV2VoiceManager ??? ì? ?Œì„± ???ìŠ¤??(STT)
//   [Box 7-C] UnifiedBrain          ??ë²”ìš© GPT ?¤íŠ¸ë¦¬ë° (Duo ??
//   [Box 7-D] TtsCache              ??TTS ë¡œì»¬ ìºì‹± (Firebase Storage ë¹„ìš© 0)
//   [Box 7-E] TtsQueueManager       ??TTS ?¤ë””????+ AI ?€ê¸??Œë˜ê·?
//   [Box 7-F] ChunkedTtsFetcher     ??TTS ?˜ë??¨ìœ„ ì²?‚¹ + ìºì‹±
//   [Box 7-G] RelayPipeline         ??ë²”ìš© ?Œì´?„ë¼??(ì°¸ê³ ??
// ====================================================================

// ====================================================================
// ?“¦ [Box 7 ê³µìš© ?ìˆ˜] ?¤êµ­??TTS êµ¬ë‘???¨í„´
// ====================================================================
// ?œêµ­???¼ë³¸??ì¤‘êµ­???¼í‹´ êµ¬ë‘???µí•© (?¼í‘œ/ë§ˆì¹¨??ë¬¼ìŒ???ë‚Œ????
// ê°?Brain/?Œì´?„ë¼?¸ì—??TTS ì²?‚¹ ê¸°ì??¼ë¡œ ?¬ìš©
final RegExp kTtsDelimiterPattern = RegExp(r'[,\.?!;:?‚ã€ï¼ï¼Ÿâ€?¼Œï¼›ï¼š\n]');

// ====================================================================
// ?“¦ [Box 7-A: ConversationHistory] ???¬ë¼?´ë”© ?ˆë„???ˆìŠ¤? ë¦¬ ê´€ë¦¬ì
// ê¸°ì¡´ ë²„ì „ ë¬¸ì œ: ?ˆìŠ¤? ë¦¬ê°€ ì£¼ì„?ë§Œ ì¡´ì¬, ?¤ì œ êµ¬í˜„ ?†ìŒ
// ê°œì„ : 2000? í° ?¬ë¼?´ë”© ?ˆë„?? ??•  êµ¬ë¶„, ì§ë ¬??ì§€??
// ====================================================================
class ConversationHistory {
  final int maxTokens;
  final List<Map<String, String>> _turns = [];

  ConversationHistory({this.maxTokens = 2000});

  /// ?€??????ì¶”ê? (role: 'user' | 'assistant')
  void add(String role, String content) {
    _turns.add({'role': role, 'content': content});
    _trim();
  }

  /// ?¤ë˜???´ì„ ?œê±°?˜ì—¬ ? í° ?ˆì‚° ? ì?
  /// ?’¡ ? í° ì¶”ì‚°: ?œêµ­?´ëŠ” ê¸€?ë‹¹ ~1.8? í°, ?ì–´??~0.75? í°
  void _trim() {
    while (_estimatedTokens() > maxTokens && _turns.length > 2) {
      _turns.removeAt(0); // ê°€???¤ë˜???´ë????œê±°
    }
  }

  int _estimatedTokens() {
    return _turns.fold(0, (sum, turn) {
      final content = turn['content'] ?? '';
      // ?œê? ë¹„ìœ¨???°ë¼ ? í° ì¶”ì‚° ì¡°ì •
      final koreanChars = RegExp(r'[ê°€-??').allMatches(content).length;
      final ratio = koreanChars / (content.length > 0 ? content.length : 1);
      final tokenRate = 0.75 + (ratio * 1.05); // ?ì–´ 0.75 ~ ?œêµ­??1.8
      return sum + (content.length * tokenRate).round();
    });
  }

  /// GPT API messages ë°°ì—´ë¡?ì§ë ¬??
  List<Map<String, String>> toMessages() => List.unmodifiable(_turns);

  /// ?ˆìŠ¤? ë¦¬ë¥??¨ìˆœ ?ìŠ¤?¸ë¡œ ì§ë ¬??(legacy ?œìŠ¤???¸í™˜)
  String toPlainText() => _turns
      .map((t) => '[${t['role']?.toUpperCase()}]: ${t['content']}')
      .join('\n');

  void clear() => _turns.clear();
  int get length => _turns.length;
}

// ====================================================================
// ?“¦ [Box 7-B: DeepgramV2VoiceManager] ??STT ?”ì§„ (ì§€??ë°±ì˜¤???¬ì—°ê²?
// ê¸°ì¡´ ë²„ì „ ë¬¸ì œ:
//   1. ?¬ì—°ê²?ë¡œì§ ?†ìŒ ???¤íŠ¸?Œí¬ ?Šê? ???¸ì…˜ ?Œë©¸
//   2. dispose ??ì½œë°± ?¤í–‰ ê°€?????¬ë˜???„í—˜
//   3. onError ???„ë¬´ ë³µêµ¬ ?œë„ ?†ìŒ
// ê°œì„ :
//   - ìµœë? 5??ì§€??ë°±ì˜¤???¬ì—°ê²?(1s, 2s, 4s, 8s, 16s)
//   - _isDisposed ê°€?œë? ëª¨ë“  ë¹„ë™ê¸?ì½œë°±???ìš©
//   - onReconnecting / onGaveUp ì½œë°± ì¶”ê?ë¡?UI ?íƒœ ?™ê¸°??
// ====================================================================
class DeepgramV2VoiceManager {
  final String apiKey;
  final AudioRecorder audioRecorder;
  final String langCode;
  final VoidCallback onConnected;
  final Function(String) onTranscriptUpdate;
  final void Function(String, {bool speechFinal}) onTurnEnded;
  final Function(String) onError;
  final Function(int)? onReconnecting; // ?¬ì—°ê²??œë„ ?Œë¦¼ (? íƒ??
  final VoidCallback? onGaveUp; // ?¬ì—°ê²??¬ê¸° ?Œë¦¼ (? íƒ??
  final void Function(String tag, String msg)? onLog; // ?”¬ [v3.1] ë¡œê·¸ ??

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
    _lg('?¤ [DG-00]', 'connectAndStart ì§„ì…');
    await _connect();
  }

  Future<void> _connect() async {
    if (_isDisposed) return;
    _lg('?¤ [MIC-01]', '_connect ì§„ì…');
    try {
      final uri = Uri.parse(
        'wss://api.deepgram.com/v1/listen'
        '?model=nova-3'
        '&language=$langCode'
        '&smart_format=true'
        '&endpointing=700' // ?”§ [v3.4] 500??00ms: ?”ë“¬ê±°ë¦¼????ë¯¼ê°?˜ê²Œ
        '&utterance_end_ms=1200' // ?”§ [v3.4] 1000??200ms: UtteranceEnd???¬ìœ ?ˆê²Œ
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
      _lg('?¤ [DG-01]', 'WebSocket ?°ê²° ?”ì²­ ?„ì†¡');

      await _wsSub?.cancel();
      _wsSub = _channel!.stream.listen(
        _handleMessage,
        onError: (e) {
          _lg('??[DG-WS-ERR]', 'WebSocket ?ëŸ¬: $e');
          _handleDisconnect();
        },
        onDone: () {
          _lg('?¤ [DG-WS-DONE]', 'WebSocket onDone');
          _handleDisconnect();
        },
      );

      // ?”§ [v3.1 ?µì‹¬ ë²„ê·¸ ?˜ì •] ë§ˆì´???¤íŠ¸ë¦?ê°•ì œ ?¬ì‹œ??
      _lg('?¤ [MIC-02]', 'ë§ˆì´???œì‘ ?œí€€??ì§„ì…');
      await _audioSub?.cancel();
      _audioSub = null;
      _lg('?¤ [MIC-03]', 'ê¸°ì¡´ _audioSub êµ¬ë… ?´ì œ ?„ë£Œ');

      try {
        final isRec = await audioRecorder.isRecording();
        _lg('?¤ [MIC-04]', 'audioRecorder.isRecording()=$isRec');
        if (isRec) {
          await audioRecorder.stop();
          _lg('?¤ [MIC-05]', 'ê¸°ì¡´ ?¹ìŒ ê°•ì œ ì¤‘ë‹¨ ?„ë£Œ');
        }
      } catch (e) {
        _lg('??[MIC-ERR-A]', 'isRecording/stop ?ëŸ¬: $e');
      }

      try {
        final stream = await audioRecorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 16000,
            numChannels: 1,
          ),
        );
        _lg('?¤ [MIC-06]', 'startStream ?±ê³µ');

        int packetCount = 0;
        _audioSub = stream.listen(
          (data) {
            if (_isDisposed) return;
            if (data.isNotEmpty) {
              packetCount++;
              if (packetCount == 1) {
                _lg('?¤ [MIC-07]', 'ì²??¤ë””???¨í‚· ?˜ì‹  (${data.length}B)');
              }
              if (packetCount == 50) {
                _lg('?¤ [MIC-08]', '?¨í‚· 50ê°??¡ì‹  ì¤?(ë§ˆì´???•ìƒ ?™ì‘)');
              }
              _channel?.sink.add(Uint8List.fromList(data));
            }
          },
          onError: (e) {
            _lg('??[MIC-ERR-B]', '?¤ë””???¤íŠ¸ë¦??ëŸ¬: $e');
          },
          onDone: () {
            _lg('?¤ [MIC-09]', '?¤ë””???¤íŠ¸ë¦?ì¢…ë£Œ (ì´?$packetCount ?¨í‚·)');
          },
        );
        _lg('?¤ [MIC-10]', 'stream.listen êµ¬ë… ?„ë£Œ ??ë§ˆì´???„ì „ ?œì„±??);
      } catch (e) {
        _lg('??[MIC-ERR-C]', 'startStream ?¤íŒ¨: $e');
      }

      _retryCount = 0;
    } catch (e) {
      _lg('??[DG-CONN-ERR]', '_connect ?„ì²´ ?¤íŒ¨: $e');
      if (!_isDisposed) _handleDisconnect();
    }
  }

  void _handleMessage(dynamic msg) {
    if (_isDisposed) return;
    try {
      final data = jsonDecode(msg as String);

      if (data['type'] == 'Metadata') {
        _isConnected = true;
        _lg('?“¡ [DG-02]', 'Metadata ?˜ì‹  ??onConnected ?¸ì¶œ');
        onConnected();
        return;
      }

      // ?”§ [v3.1] UtteranceEnd ?´ë²¤??(utterance_end_ms ?¸ë¦¬ê±?
      // ?´ê²ƒ??speech_finalê³??™ì¼?˜ê²Œ ??ì¢…ë£Œë¡?ì·¨ê¸‰
      if (data['type'] == 'UtteranceEnd') {
        final finalText = _currentTranscript.trim();
        _currentTranscript = '';
        _lg('?“¡ [DG-UE]',
            'UtteranceEnd ?´ë²¤????onTurnEnded. finalText="$finalText"');
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
        _lg('?“¡ [DG-03]',
            'isFinal=$isFinal speechFinal=$speechFinal chunk="$chunk"');
      }

      if (isFinal && chunk.isNotEmpty) {
        _currentTranscript += '$chunk ';
        if (!_isDisposed) onTranscriptUpdate(_currentTranscript);
      }

      if (speechFinal) {
        final finalText = _currentTranscript.trim();
        _currentTranscript = '';
        _lg('?“¡ [DG-04]',
            'speech_final ??onTurnEnded ?¸ì¶œ ?œë„. finalText="$finalText"');
        if (!_isDisposed && finalText.isNotEmpty) {
          _lg('?“¡ [DG-05]', 'onTurnEnded ?¤ì œ ?¸ì¶œ');
          onTurnEnded(finalText, speechFinal: true);
        } else {
          _lg('?“¡ [DG-06]', 'finalText ë¹ˆê°’ ??onTurnEnded ?¤í‚µ');
        }
      }
    } catch (e) {
      _lg('??[DG-PARSE-ERR]', '_handleMessage ?Œì‹± ?ëŸ¬: $e');
    }
  }

  Future<void> _handleDisconnect() async {
    if (_isDisposed) return;
    _isConnected = false;
    if (_retryCount < _maxRetries) {
      _retryCount++;
      _lg('?¤ [DG-RETRY]', '?¬ì—°ê²??œë„ $_retryCount/$_maxRetries');
      onReconnecting?.call(_retryCount); // ?”§ ? íƒ??ì½œë°± ?¸ì¶œ
      final delay = Duration(milliseconds: 500 * (1 << (_retryCount - 1)));
      await Future.delayed(delay);
      if (!_isDisposed) await _connect();
    } else {
      _lg('??[DG-GIVEUP]', '?¬ì—°ê²?ìµœë?ì¹??„ë‹¬');
      onGaveUp?.call(); // ?”§ ? íƒ??ì½œë°± ?¸ì¶œ
      onError('Connection lost');
    }
  }

  Future<void> dispose() async {
    _lg('?¤ [DG-DISPOSE]', 'dispose ì§„ì…');
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
// ?“¦ [Box 7-C: UnifiedBrain] ??ë²”ìš© GPT ?¤íŠ¸ë¦¬ë° (Duo ?±ì—???¬ìš©)
// ê¸°ì¡´ ë²„ì „ ë¬¸ì œ:
//   1. static Client ê³µìœ  ???™ì‹œ ?”ì²­ ??ê²½ìŸ ?íƒœ
//   2. ?ˆìŠ¤? ë¦¬ ?†ìŒ
//   3. ?¤íŠ¸ë¦¬ë° ?ëŸ¬ ì²˜ë¦¬ ?†ìŒ, ?€?„ì•„???†ìŒ
// ê°œì„ :
//   - ?”ì²­ë§ˆë‹¤ ??Client ?ì„± (stateless)
//   - ConversationHistoryë¥?messages ë°°ì—´ë¡?ì§ì ‘ ?„ë‹¬
//   - 30ì´??€?„ì•„??+ ?¤íŠ¸ë¦??ëŸ¬ ?„íŒŒ
// ====================================================================
class UnifiedBrain {
  /// ?’¡ ë³€ê²? static Client ?œê±°, ?”ì²­ë³???Client ?¬ìš©
  static Stream<String> streamChat({
    required String apiKey,
    required String systemPrompt,
    required String userMessage,
    ConversationHistory? history, // ?’¡ ? ê·œ: ?ˆìŠ¤? ë¦¬ ì§ì ‘ ì£¼ì…
    double temp = 0.2,
    Duration timeout = const Duration(seconds: 30), // ?’¡ ? ê·œ: ?€?„ì•„??
  }) async* {
    final client = http.Client();

    try {
      // ë©”ì‹œì§€ ë°°ì—´ êµ¬ì„±: system ??history ???„ì¬ ? ì? ë©”ì‹œì§€
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
        'max_tokens': 500, // ?’¡ ? ê·œ: ?Œì„± ?€?”ëŠ” ì§§ê²Œ (TTS ì§€??ìµœì†Œ??
      });

      // ?’¡ ? ê·œ: ?€?„ì•„???ìš©
      final response = await client.send(request).timeout(timeout);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw Exception('GPT API ?¤ë¥˜ ${response.statusCode}: $body');
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
            // ë¶ˆì™„?„í•œ JSON ì²?¬ ?¤í‚µ
          }
        }
      }
    } finally {
      client.close(); // ?’¡ ??ƒ ?´ë¼?´ì–¸???´ì œ
    }
  }
}

// ====================================================================
// ?“¦ 4 TtsQueueManager v2 ???„ë£Œ ê°ì? ?ˆì •??ê°œì„ 
// ê¸°ì¡´ ë²„ì „ ë¬¸ì œ:
//   1. onPlayerComplete ë¦¬ìŠ¤?ˆê? ?„ìˆ˜ ê°€??
//   2. timeout 10ì´ˆê? ì§§ì? ë¬¸ì¥??ê³¼í•¨, ê¸?ë¬¸ì¥??ë¶€ì¡?
// ê°œì„ :
//   - StreamSubscription?¼ë¡œ ë¦¬ìŠ¤??ëª…ì‹œ??ê´€ë¦?
//   - ?¤ë””??ê¸¸ì´ ì¶”ì‚° ê¸°ë°˜ ?™ì  ?€?„ì•„??
//   - stop() ??Completer ?ˆì „ ?„ë£Œ ì²˜ë¦¬
// ====================================================================
// ====================================================================
// ?“¦ [Box 7-D: TtsCache] ??TTS ?¤ë””??ë¡œì»¬ ìºì‹± (MD5 ?¤í????´ì‹œ)
// ====================================================================
// ?”§ [v3 ? ê·œ] ê°™ì? ?ìŠ¤??voice+speed???Œì¼ ?¬ì‚¬??
//   ??OpenAI API ?¸ì¶œ 0, ì¦‰ì‹œ ?¬ìƒ, Firebase Storage ë¹„ìš© 0
//   ??ê²½ë¡œ: {?±ë¡œì»?/tts_cache/{?´ì‹œ??.mp3
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

  /// ìºì‹œ ?©ëŸ‰ ê´€ë¦?(100MB ì´ˆê³¼ ???¤ë˜???Œì¼ë¶€???œê±°)
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
// ?“¦ [Box 7-E: TtsQueueManager] ??AI ?€ê¸??Œë˜ê·?ì¶”ê?
// ====================================================================
// ?”§ [v3] _aiPaused ?Œë˜ê·¸ë¡œ "? ì? ??… ?„ë£Œ ?„ê¹Œì§€ AI ?¬ìƒ ?€ê¸? êµ¬í˜„
class TtsQueueManager {
  final AudioPlayer _player = AudioPlayer();
  // ?”§ [v3.5] ë¶„ë¦¬??????
  final List<Uint8List> _userQueue = []; // ? ì? TTS ?„ìš©
  final List<Uint8List> _aiQueue = []; // AI TTS ?„ìš©

  bool _isPlaying = false;
  Completer<void>? _completer;
  StreamSubscription? _completeSub;
  final VoidCallback? onPlayStart;
  final VoidCallback? onQueueEmpty;

  // AI ?¬ìƒ ?€ê¸??Œë˜ê·?(? ì? ?¬ìƒ ì¤??ëŠ” ? ì? ?¬ìƒ ì§í›„ ?ˆì „ ê°„ê²©)
  bool _aiPaused = false;

  // ?”§ [v3.6] ?¸ë??ì„œ _aiPaused ?íƒœ ì¡°íšŒ (UI ?…ë°?´íŠ¸ ë³´ë¥˜ ?ë‹¨??
  bool get aiPaused => _aiPaused;
  // UI ?íƒœ ?œì‹œ??(?ˆê±°???¸í™˜)
  bool _isUserTurn = true;

  // ?”’ [Box 7 USER-DRAIN-SIGNAL] ? ì? ???„ì „ drain ê°ì???
  bool _userStreamSealed = false;
  Completer<void>? _userDrainedCompleter;
  bool _currentChunkIsUser = false;

  /// ? ì? ?¬ìƒ ì¤‘ì´ê±°ë‚˜ ? ì? ?ì— ?¨ì? ê²??ˆìœ¼ë©?busy
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

  /// AI ì²?¬ ?¬ìƒ ?¼ì‹œ?•ì?/?¬ê°œ
  void setAiPaused(bool paused) {
    _aiPaused = paused;
    if (!paused &&
        !_isPlaying &&
        (_userQueue.isNotEmpty || _aiQueue.isNotEmpty)) {
      _processQueue();
    }
  }

  /// ?ˆê±°???¸í™˜??(UI ?íƒœ ?œì‹œë§?
  void setUserTurn(bool isUser) {
    _isUserTurn = isUser;
  }

  /// ?”§ [v3.5] isUser=trueë©?? ì? ?? falseë©?AI ?ì— ?ì¬
  Future<void> addAudio(Uint8List bytes, {required bool isUser}) async {
    if (isUser) {
      _userQueue.add(bytes);
    } else {
      _aiQueue.add(bytes);
    }
    if (!_isPlaying) _processQueue();
  }

  // ?”’ [Box 7 USER-DRAIN-SIGNAL] ? ì? ì²?¬ ?¤íŠ¸ë¦?ë´‰ì¸.
  // ?¸ì¶œ ?œì  = "???´ìƒ ? ì? ì²?¬ê°€ ?¤ì–´?¤ì? ?ŠìŒ" ? ì–¸.
  void sealUserStream() {
    _userStreamSealed = true;
    if (_userQueue.isEmpty && !_currentChunkIsUser) {
      if (_userDrainedCompleter != null &&
          !_userDrainedCompleter!.isCompleted) {
        _userDrainedCompleter!.complete();
      }
    }
  }

  // ?”’ [Box 7 USER-DRAIN-SIGNAL] ? ì? ?ê? ?„ì „??ë¹„ê³  ë§ˆì?ë§?ì²?¬ ?¬ìƒ???ë‚  ?Œê¹Œì§€ ?€ê¸?
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
      // Timeout?€ ê°•ì œ ì§„í–‰???¸ì¶œë¶€ê°€ ë§‰íˆì§€ ?Šë„ë¡??œë‹¤.
    } finally {
      _userDrainedCompleter = null;
      _userStreamSealed = false;
    }
  }

  Future<void> _processQueue() async {
    if (_isPlaying) return;
    _isPlaying = true;
    onPlayStart?.call();

    // ?”§ [v3.5] ?¬ìƒ ?°ì„ ?œìœ„:
    //   1?œìœ„: ? ì? ??(??ƒ ?°ì„ )
    //   2?œìœ„: AI ??(? ì? ??ë¹„ê³  _aiPaused=false???Œë§Œ)
    while (_userQueue.isNotEmpty || (!_aiPaused && _aiQueue.isNotEmpty)) {
      Uint8List bytes;
      if (_userQueue.isNotEmpty) {
        bytes = _userQueue.removeAt(0);
        _currentChunkIsUser = true; // ?”’ [Box 7 USER-DRAIN-SIGNAL]
      } else if (!_aiPaused && _aiQueue.isNotEmpty) {
        bytes = _aiQueue.removeAt(0);
        _currentChunkIsUser = false; // ?”’ [Box 7 USER-DRAIN-SIGNAL]
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

      // ?”’ [Box 7 USER-DRAIN-SIGNAL] ? ì? ì²?¬ ?¬ìƒ ?„ë£Œ ì§í›„ sealed ?íƒœë©?drain ? í˜¸.
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
    // ?”’ [Box 7 USER-DRAIN-SIGNAL] drain ?€ê¸°ì ê¹¨ìš°ê¸?deadlock ë°©ì?)
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
// ?“¦ [Box 7-F: ChunkedTtsFetcher] ??ìºì‹± + ?¬ì‹œ??
// ====================================================================
// ?”§ [v3] _fetch ?¨ê³„?ì„œ ë¡œì»¬ ìºì‹œ ë¨¼ì? ?•ì¸, ë¯¸ìŠ¤ ?œì—ë§?API ?¸ì¶œ + ?€??
class ChunkedTtsFetcher {
  final String apiKey;
  final TtsQueueManager audioQueue;
  final String voice;
  final String language;
  final bool isUser; // ?”§ [v3.5] true=? ì? ?? false=AI ??
  final void Function(String tag, String msg)? onLog; // ?”¬ [v3.1] ë¡œê·¸ ??

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
    this.isUser = true, // ?”§ [v3.5] ê¸°ë³¸ê°? ? ì? ??
    this.onAllComplete,
    this.onLog,
  });

  void addText(String text) {
    if (text.trim().isEmpty) return;
    // TTS API is unreliable for punctuation-only chunks like "!" or ",".
    if (!RegExp(r'[a-zA-Z0-9ê°€-??').hasMatch(text)) {
      onLog?.call('?”Š [TTS-SKIP]', 'punctuation-only skipped: "$text"');
      return;
    }
    _pendingCount++;
    final turnTag = isUser ? 'USER' : 'AI';
    onLog?.call(
        '?”Š [TTS-01]', '[$turnTag] addText: "$text" (pending=$_pendingCount)');
    _fetch(_requestCounter++, text);
  }

  Future<void> _fetch(int id, String text) async {
    // [1?¨ê³„] ë¡œì»¬ ìºì‹œ ?•ì¸ (?ˆíŠ¸ ??ì¦‰ì‹œ ë°˜í™˜)
    final cached = await TtsCache.get(text, voice);
    if (cached != null && cached.isNotEmpty) {
      _buffer[id] = cached;
      _pendingCount--;
      _pushReady();
      if (_pendingCount == 0) onAllComplete?.call();
      return;
    }

    // [2?¨ê³„] API ?¸ì¶œ (?€?„ì•„???¬ë‹¤ë¦?5/8/12ì´? ìµœë? 3???œë„) ??TTS ì§€???¤íŒŒ?´í¬ ?€??
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
                'model': 'tts-1',
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
          onLog?.call('?”Š [TTS-02]',
              '[$turnTag] API OK (${result.length}B) for "$text"');
          // [3?¨ê³„] ìºì‹œ ?€??(ë°±ê·¸?¼ìš´??
          TtsCache.put(text, voice, result);
          break;
        } else {
          onLog?.call('??[TTS-API-ERR]',
              'statusCode=${res.statusCode} (attempt=${attempt + 1}/3)');
        }
      } catch (e) {
        onLog?.call('? ï¸ [TTS-RETRY]',
            'attempt=${attempt + 1}/3 ?¤íŒ¨ (${e.runtimeType}) for "$text"');
        if (attempt < 2 && e is! TimeoutException) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    }
    if (result.isEmpty) {
      onLog?.call('??[TTS-FAIL]', '3??ëª¨ë‘ ?¤íŒ¨ ??ì²?¬ ?¤í‚µ: "$text"');
    }

    _buffer[id] = result;
    _pendingCount--;
    _pushReady();
    if (_pendingCount == 0) onAllComplete?.call();
  }

  void _pushReady() {
    while (_buffer.containsKey(_readyCounter)) {
      final data = _buffer.remove(_readyCounter)!;
      // ?”§ [v3.5] isUser ?Œë˜ê·¸ë¡œ ??? íƒ
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
// ?“¦ [Box 7-G: RelayPipeline] ??ë²”ìš© ?Œì´?„ë¼??(ì°¸ê³ ?? ?„ì ¯?ì„  Box 5-A ?¬ìš©)
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
      onConnected: () => print('[Deepgram] ?°ê²°??),
      onTranscriptUpdate: (_) {}, // UI?ì„œ ?¤ë²„?¼ì´??
      onTurnEnded: _onUserTurnEnded,
      onError: (e) => print('[Deepgram] ?¤ë¥˜: $e'),
      onReconnecting: (attempt) => print('[Deepgram] ?¬ì—°ê²??œë„ $attempt/5??),
      onGaveUp: () => print('[Deepgram] ?¬ì—°ê²??¬ê¸°'),
    );
  }

  Future<void> start() => _voiceManager.connectAndStart();

  /// ?’¡ ? ê·œ: ? ì?ê°€ AI ë§?ì¤‘ì— ë§ì„ ?œì‘?˜ë©´ ì¦‰ì‹œ ì¤‘ë‹¨ (ë°”ì??¸í„°?½íŠ¸)
  void interruptAi() {
    _ttsQueue.stop();
    _ttsFetcher.reset();
    _isSpeaking = false;
  }

  Future<void> _onUserTurnEnded(String userText,
      {bool speechFinal = false}) async {
    // ?’¡ AIê°€ ë§í•˜??ì¤‘ì— ? ì?ê°€ ë§í•˜ë©?ì¦‰ì‹œ ì¤‘ë‹¨
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

        // ?’¡ ê°œì„ ??ìª¼ê°œê¸? ?¤êµ­??êµ¬ë‘???¨í„´ ?¬ìš©
        final segments = _splitByDelimiter(ttsBuffer);
        if (segments.length > 1) {
          // ë§ˆì?ë§?ë¯¸ì™„???¸ê·¸ë¨¼íŠ¸??ë²„í¼???¨ê?
          for (int i = 0; i < segments.length - 1; i++) {
            final segment = segments[i].trim();
            if (segment.isNotEmpty) _ttsFetcher.addText(segment);
          }
          ttsBuffer = segments.last;
        }
      }

      // ?¤íŠ¸ë¦?ì¢…ë£Œ ???¨ì? ë²„í¼ ì²˜ë¦¬
      if (ttsBuffer.trim().isNotEmpty) {
        _ttsFetcher.addText(ttsBuffer.trim());
      }

      // ?’¡ ? ê·œ: AI ?‘ë‹µ ?„ë£Œ ???ˆìŠ¤? ë¦¬ ?€??
      if (aiResponseBuffer.isNotEmpty) {
        _history.add('assistant', aiResponseBuffer.trim());
      }
    } catch (e) {
      print('[RelayPipeline] AI ?¤ë¥˜: $e');
    }
  }

  /// ?’¡ ? ê·œ: ìª¼ê°œê¸?ë¡œì§ ë¶„ë¦¬ (?¤êµ­??êµ¬ë‘???•ê·œ???¬ìš©)
  List<String> _splitByDelimiter(String text) {
    final segments = <String>[];
    int lastSplit = 0;

    for (final match in kTtsDelimiterPattern.allMatches(text)) {
      segments.add(text.substring(lastSplit, match.end));
      lastSplit = match.end;
    }
    segments.add(text.substring(lastSplit)); // ?¨ì? ë¶€ë¶?(ë¯¸ì™„??

    return segments;
  }

  Future<void> dispose() async {
    await _voiceManager.dispose();
    await _ttsQueue.dispose();
  }
}

// ============================================================================

// ====================================================================
// ?“¦ [Box 7-H: HybridTtsPlayer] ???˜ì´ë¸Œë¦¬??TTS (Roleplay ?„ìš©)
// ====================================================================
// ?¤ê³„ ?ì¹™: ì²?êµ¬ë‘??ì¦‰ì‹œ ë°œì‚¬(ì²´ê° ë¹ ë¦„) + ?µë¬¸??ìºì‹œ ?€???ˆìŠ¤? ë¦¬ ?µí•©)
//   ??tryFireFirstChunk: ì²?êµ¬ë‘???„ë‹¬ ??ChunkedTtsFetcher??1??ë°œì‚¬
//   ??onStreamEnd: remainder ?œì°¨ ë°œì‚¬ + fullSentence TtsCache ?€??(?¬ìƒ ?†ìŒ)
//   ??Rollback: tryFireFirstChunk ?œê±° ??aiTtsFetcher.addText(toSpeak) ë³µì›
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

  // ì²?êµ¬ë‘???„ë‹¬ ??1???¸ì¶œ. firstChunkë¥?fetcher??ì¦‰ì‹œ ë°œì‚¬.
  // ë°˜í™˜ê°? buffer?ì„œ ?ë? ?¸ë±??(>=0?´ë©´ ë°œì‚¬?? -1?´ë©´ ë¯¸ë°œ??
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

  // [Box 7-H] ì¡°ê¸° ë°œì‚¬ ë³´ì¶©: êµ¬ë‘??OR firstChunkMinWords ?¨ì–´ ì¤?ë¨¼ì? ?¤ëŠ” ìª?ë°œì‚¬
  // buffer: ?„ì¬ê¹Œì? ?„ì ??AI ?ìŠ¤??ë²„í¼ (?¸ë??ì„œ ê´€ë¦?
  // ë°˜í™˜ê°? buffer?ì„œ ?ë? ?¸ë±??(>=0?´ë©´ ë°œì‚¬?? -1?´ë©´ ë¯¸ë°œ??
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
        'ë°œì‚¬(${punctMatch != null ? "êµ¬ë‘?? : "5?¨ì–´"}): "$text" ${lastFirstChunkMs}ms');
    return cutIdx;
  }

  // GPT ?¤íŠ¸ë¦?ì¢…ë£Œ ???¸ì¶œ:
  //   1) remainder ì²?¬ ?œì°¨ ë°œì‚¬ (ê¸°ì¡´ ?ì— ?´ì–´??
  //   2) fullSentence TtsCache ?€??(?¬ìƒ ?†ìŒ ???ˆìŠ¤? ë¦¬ ë·?HIT ? ë„)
  Future<void> onStreamEnd({
    required String fullSentence,
    required String remainderBuffer,
    required ChunkedTtsFetcher fetcher,
    required Stopwatch swSpeechEnd,
  }) async {
    // 1. Remainder ë°œì‚¬
    final remainder = remainderBuffer.trim();
    if (!_firstChunkFired && fullSentence.isNotEmpty) {
      // êµ¬ë‘???†ì´ ?¤íŠ¸ë¦?ì¢…ë£Œ ???„ì²´ ?ìŠ¤?¸ë? ì§€ê¸?ë°œì‚¬
      fetcher.addText(fullSentence);
      _firstChunkFired = true;
      lastFirstChunkMs = swSpeechEnd.elapsedMilliseconds;
      onLog?.call(
          '[HYB-01-LATE]', 'no punctuation ??full text fired at stream end');
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

    // 2. TtsCache ?€?¥ì? ë°±ê·¸?¼ìš´??fire-and-forget?¼ë¡œ ë¶„ë¦¬?œë‹¤.
    final sentence = fullSentence.trim();
    if (sentence.isEmpty) return;
    unawaited(_cacheFullSentenceInBackground(sentence));
  }

  // _cacheFullSentenceInBackground: ?µë¬¸??ìºì‹œ ?€?¥ì„ await?˜ì? ?ŠëŠ” ë°±ê·¸?¼ìš´???‘ì—….
  Future<void> _cacheFullSentenceInBackground(String fullSentence) async {
    try {
      final cached = await TtsCache.get(fullSentence, voice);
      if (cached != null && cached.isNotEmpty) {
        lastCacheHit = true;
        lastCacheSaveMs = 0;
        onLog?.call('[HYB-03-HIT]', 'TtsCache HIT ???€???ëµ');
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
                  'model': 'tts-1',
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
            onLog?.call('[HYB-CACHE-RETRY]', 'ìºì‹œ ?€???¬ì‹œ??${e.runtimeType})');
          }
        }
      }
      if (bytes != null) {
        await TtsCache.put(fullSentence, voice, bytes);
        lastCacheSaveMs = sw.elapsedMilliseconds;
        onLog?.call(
            '[HYB-04-SAVED]', '${lastCacheSaveMs}ms (${bytes.length}B)');
      } else {
        onLog?.call('[HYB-ERR]', 'TtsCache ?€??2???¤íŒ¨ ???¤í‚µ');
      }
      sw.stop();
    } catch (e) {
      onLog?.call('[HYB-ERR]', 'TtsCache ?€???¤íŒ¨: $e');
    }
  }
}

// ====================================================================
// ?§  [Box 7-1] RoleplayBrain v3 ??ë¡¤í”Œ?ˆì´ ëª¨ë“œ ?„ìš© AI ??
// ====================================================================
class RoleplayBrain {
  // ?†• [EXPAND-EXIT] ?€???„ì²´(AI+? ì?) ??ì¢…í•© ?•ì¥ ë¬¸ì¥ 1ê°?(?˜ë??¨ìœ„ ~5ê°? ë¬¸ë²• ?°ê²°)
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
- Keep it 25??0 words.
- Build it from about 5 meaning units joined with varied grammatical connectives
  (because, so, while, which, after, even though, and, etc.).
- Each meaning unit should be speakable in one breath, usually 5?? words.
- Use commas or natural connectors to make breath groups clear.
- Do not create a sentence with one very long clause.
- Natural, speakable rhythm ??common spoken English only.
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

  // ?†• [EXPAND-EXIT] ?•ì¥ ë¬¸ì¥ ???½ê³  ?¸ë ¨????ë¬¸ì¥ (Polished)
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

  // ?“‹ [200ê°?ê¸°ì´ˆ ?í™© ??ì¹´í…Œê³ ë¦¬ 5ì¢?Ã— 40ê°? (v4 ì¶”ê?)
  static const List<String> _baseSituations200 = [
    // ?€?€ ê³µí•­_ë¹„í–‰ê¸?êµí†µ (40ê°? ?€?€
    'ê¸°ë‚´ ?˜í•™ ?˜ì ë°œìƒ', '?”ì¥??ê°‡í˜ ?¬ê³ ', '?°ì†Œë§ˆìŠ¤???‘ë™??, '?¬ê¶Œ ë¶„ì‹¤ ë°œê²¬??, 'ìºë¦¬???Œì† ?•ì¸',
    '?„ì¡°ì§€???˜ì‹¬??,
    '?…êµ­ ê±°ë? ?„ê¸°', '?Œì????¤ì¸ ?•ìˆ˜', 'ê²°ì œ ?¤ë¥˜ ì§€??, 'ë¹„í–‰ê¸??“ì¹˜ê¸?ì§ì „', '?‘ìŠ¹ê¶?ë¶„ì‹¤??, 'ë¯¸ì•„ ë°œìƒ ? ê³ ',
    '?¹ë¬´??ë¶€??ë°œìƒ', '?‘ìŠ¹ ê±°ë? ?¹í•¨', 'ë²„ìŠ¤ ê³ ì¥ ë©ˆì¶¤', '?˜ëª»???°ì¼“ ë°œê¶Œ', '?Œë§¤ì¹˜ê¸° ë°œìƒ', 'ì§??¤ì¸ êµí™˜??,
    '?¤í¬ë¦°ë„????,
    'ë¹„ìƒ ?•ì? ë°œìƒ', 'ì§€ê°??ê³  ?´ë¦¼', 'ë§‰ì°¨ ì·¨ì†Œ ê³ ë¦½??, 'ê¸‰ê²©??ë³µí†µ ë°œìƒ', 'ë¶€???”ê¸ˆ ?”êµ¬', '?œí­ ?´ì „ ê³µí¬',
    'ê³„ì•½ ?¬ê¸° ?˜ì‹¬',
    '?¼ìœ  ?¬ê³  ë°œìƒ', 'ì°¨ëŸ‰ ?€?´ì–´ ?‘í¬', 'ì°¨ëŸ‰ ë°°í„°ë¦?ë°©ì „', '?•ì‚°ê¸?ê³ ì¥ ë©ˆì¶¤', '?ˆì•½ ?„ë½ ë°œê²¬', '? ë‚´ ?”ì¬ ê²½ë³´',
    '?Œì???ë°”ë‹¤ ë¹ ì§', 'ë°??“ì¹˜ê³?ê³ ë¦½', 'ì§‘ë‹¨ ?ì¤‘??ì¦ìƒ', 'ê°€ë°?ë¬??´ë ¤?ˆìŒ', 'ë°˜ë‚© ì²˜ë¦¬ ?¤ë¥˜', 'ê³µì¤‘ ë©ˆì¶¤ ?¬ê³ ',
    '?‘ì´‰ ?¬ê³  ???„ì£¼', 'ì°¨ëŸ‰ ì¶œê³  ë¶ˆê?',
    // ?€?€ ?¸í…”_?™ì†Œ_ì£¼ê±° (40ê°? ?€?€
    '?ˆì•½ ì·¨ì†Œ ?¹í•¨', 'ë°??´ë? ëª°ì¹´ ?˜ì‹¬', '?¨ìˆ˜ ???˜ì˜´', '?˜ë¦¬ë² ì´??ê°‡í˜', '?µìˆ˜ ?¬ê³  ë°œìƒ', '?Œë ˆë¥´ê¸° ë°œìƒ',
    'ì·¨ê° ?œë¹„ ê±¸ë¦¼',
    '?´ë™ ê¸°êµ¬ ë¶€??, '?”ì¬ ê²½ë³´ ?€??, 'ê¸°ë? ë¬¸ì„œ ? ì¶œ', '?Œì????„ë‚œ?¹í•¨', '?™ì†Œ ?¬ì§„ê³??¤ë¦„', 'ë¯¸ë„?¬ì§ ë¶€??,
    '?íŠ¸ ë¬´ë„ˆì§?,
    'ë©§ë¼ì§€ ì¶œí˜„??, '?íŠ¸ ë¶ˆê¸¸ ë²ˆì§', '?„ì–´??ê³ ì¥ ê°‡í˜', '?™íŒŒë¡??„ìˆ˜ ë°œìƒ', 'ì¸µê°„?ŒìŒ ?œë¹„', 'ë§¹ê²¬ ì§„ì… ?„í—˜',
    'ê³„ë‹¨ ?¤ì¡± ë¶€??,
    '?€?ˆì•• ?¤ì‹ ??, 'ì£¼ì¸ë°?ë¬´ë‹¨ ì¹¨ì…', 'ë£¸ë©”?´íŠ¸ ?ˆë„', '?í•œ ?Œì‹ ?œë¹™', 'ì°¨ëŸ‰ ?Œì† ë°œê²¬', '?¥ìƒ ë¬?? ê? ê°‡í˜',
    '?…ì¶©??ë¬¼ë¦¼',
    'ë¬´ë‹¨ ì£¼ê±° ì¹¨ì…', '? ë¶„ì¦??„ìš© ?˜ì‹¬', '?œê°„ ?Œì† ?„í—˜', '?¼ë? ?”ìƒ ?…ìŒ', '?…ì‚¬ ì¶œí˜„ ë¹„ìƒ', 'ê°€???„ì¶œ ?˜ì‹¬',
    '???¸íƒ ì¤?ë¶„ì‹¤',
    'ê¸ˆê³  ???´ë¦¼', 'ì§€??ì¹¨ìˆ˜ ë°œìƒ', '?ë°° ë¶„ì‹¤ ??˜', '? ë¦¬ì°?ê¹¨ì§', '?¹ë“¤ë¦¬ì— ì¶”ë½',
    // ?€?€ ?ë‹¹_?¼í•‘_? í¥ (40ê°? ?€?€
    'ë¨¸ë¦¬ì¹´ë½ ?˜ì˜´', '?ì¤‘??ì¦ìƒ ë°œí˜„', 'ê¸°ë¦„ ë¶ˆíŒ ?”ì¬', 'ì£¼ë¬¸ ?¤ì¸ ?€ê¸?, 'ê²°ì œ ì¤‘ë³µ ì²˜ë¦¬', 'ì»¤í”¼ ?Ÿì•„ ?”ìƒ',
    '?íŒ ?ìŒ ?¬ê³ ',
    '?Œì‹ ?„ì¤‘ ?Œì§„', 'ë°”ê?ì§€ ?”ê¸ˆ ì²?µ¬', 'ì§€ê°??Œë§¤ì¹˜ê¸°', 'ëª…í’ˆ ?¼ì† ?œë¹„', '?¼ë? ë¶€?‘ìš© ë°œìƒ', 'ëª°ë˜ì¹´ë©”??ë°œê²¬',
    'ì¹´íŠ¸ ì¶©ëŒ ë¶€??,
    'ê±°ìŠ¤ë¦„ëˆ ?¬ê¸°', '?¬ê¶Œ ?•ë³´ ?¤ë¥˜', 'ë¬¼ê±´ ?Œì† ë³€??, 'ì§€ê°?ë¶„ì‹¤ ?•ì¸', '?´ì? ?†ì´ ê°‡í˜', '? í†µê¸°í•œ ì§€??,
    'ì·¨ê° ?¸ì? ë²ˆì§',
    '?„ë‚œ ê²½ë³´ ?‘ë™', '?Œë§¤ì¹˜ê¸° ì¶”ê²©', '?ìŠ¤ì»¬ë ˆ?´í„° ??, '?™ìƒ ?¬ê³  ë°œìƒ', '?´ë¬¼ì§?ì¹˜ì•„ ?Œì†', 'ë°°ë‹¬ ?¬ê³  ?„ë½',
    'ê°€?¤í†µ ??°œ ?„ê¸°',
    '?¸íŒŒ ?•ì‚¬ ?„í—˜', 'ì£¼ì°¨ ?œë¹„ ??–‰', '?¤ì´??ë¶„ì‹¤ ?¤í•´', '? ë°œ ?„ë‚œ?¹í•¨', 'ì±…ì¥ ?°ëŸ¬ì§??¬ê³ ', '?Œì¦ˆ ?Œì† ë¶€??,
    '?˜ëª»????ë³µìš©',
    'êµìƒ ?¬ê³  ë°œìƒ', 'ê°€ë°?ì¤?ê±¸ë ¤ ?Œì†', 'ì¹¼ë‚  ë¶€???¬ê³ ', 'ë³€ì§ˆëœ ?Œì‹ ?ë§¤', 'ì¹¨ë? ì£¼ì??‰ìŒ',
    // ?€?€ ê³µê³µ?¥ì†Œ_ë³‘ì›_ë¹„ì¦ˆ?ˆìŠ¤ (40ê°? ?€?€
    '?˜ë£Œì§?ê³µë°± ì§€??, '?¤ì§„ ê°€?¥ì„± ?•ì¸', '?¸í¡ ê³¤ë? ?˜ì', '?˜ìˆ  ì§€????˜', '?‡ëª¸ ê³¼ë‹¤ ì¶œí˜ˆ', 'ë³´ì´?¤í”¼???˜ì‹¬',
    'ì¹´ë“œ ë¨¹í†µ ??,
    'ì¤‘ìš” ?ë°° ë¶„ì‹¤', '?µìš¸???„ëª… ?€', 'ê¸´ê¸‰ ì¶œë™ ë°©í•´', '?œë¥˜ ì¡°ì‘ ?˜ì‹¬', 'ë¹„ì ë°œê¸‰ ê±°ë?', 'ë¹”í”„ë¡œì ????°œ',
    '?œì„¬?¨ì–´ ê°ì—¼??,
    '?•ìˆ˜ê¸??„ì „ ?”ì¬', 'ë©´ì ‘ ?œë¥˜ ë¶„ì‹¤', 'ë¬´ë‹¨ ì¹¨ì… ?œìœ„', '?¸ê° ?„ìš© ë°œê²¬', '?¸ê¸ˆ ??ƒ„ ?¤ë¥˜', '?Œì†¡ ?ë? ?‘ë°•',
    '?¸íŠ¸ë¶??„ë‚œ?¹í•¨',
    '?œí—˜ì§€ ? ì¶œ ë¹„ìƒ', '?”í•™ ?½í’ˆ ?„ì¶œ', '?±êµ ë¯¸ì•„ ë°œìƒ', '?”í?ë²„ìŠ¤ ?¬ê³ ', '?„ì‹œ ?‘í’ˆ ?¼ì†', '? ë¬¼ ?„ë‚œ ê²½ë³´',
    'ë¬´ë? ì¡°ëª… ì¶”ë½',
    '?ì‚¬ê¸??”ì¬ ë°œìƒ', '?”í‘œ ?¬ê¸° ?¹í•¨', 'ë§¹ìˆ˜ ?ˆì¶œ ë¹„ìƒ', '?…ì´ˆ ?¤ì ‘ì´?ë¶€??, '? ê¸°ê²??µê²©??, '?´ì‚¬ë³??˜ì ?¤ì‹ ',
    'ë²”ì£„ ?˜ì‹¬ ë¹„ëª…',
    'ë¶€?¹í•´ê³?êµ¬ì œ ? ì²­', 'ë¶€??ë¬´ë„ˆì§??¬ê³ ', '?ë°©??ë°©ì†¡ ?¬ê³ ', '?œì… ?Œìš” ?¬íƒœ', 'ì§‘ë‹¨ ê°ì—¼ ?˜ì‹¬',
    // ?€?€ ?ˆì?_ê´€ê´??ì—°_ê¸°í? (40ê°? ?€?€
    '?´ì‹ ì¡°ë¥˜ ?œë¥˜', '?°ì†Œ???”ëŸ‰ ê³ ê°ˆ', 'ë³´ë“œ ì¶©ëŒ ?¤ì‹ ', 'ì¥ê? ?˜ì„œ ?µìˆ˜', 'ê°‘ì‘?¤ëŸ¬??ë¶ˆì–´??, '?¬ë¼?´ë“œ ì¶©ëŒ',
    '?šì‹¯ë°”ëŠ˜ ??ì°”ë¦¼',
    '?¤ì¡± ê³ ë¦½ ì¡°ë‚œ', '?€ì²´ì˜¨ì¦?ë°œìƒ', 'ë¡œí”„ ?Šì–´ì§??„ê¸°', 'ì¶©ëŒ ê³¨ì ˆ ë¶€??, 'ë¦¬í”„??ê³µì¤‘ ë©ˆì¶¤', '?€êµ??¬ê³  ë¶€??,
    '?Œìš¸ë³??ˆë©´ ê°•í?',
    '?¬ì¥ë§ˆë¹„ ?˜ì ë°œìƒ', 'ë°”ë²¨ ?™í•˜ ê¹”ë¦¼', 'ê´€???ˆêµ¬ ë¶€??, '?ˆì¸ ì§„ì… ê¸°ê³„ ??, '?¤ì??´íŠ¸ ??ë¶€??, 'ë¡¤ëŸ¬ì½”ìŠ¤??ë©ˆì¶¤',
    '?¤ì œ ? ë ¹ ê³µí¬', '?¤ë°œ ?¬ê³  ë°œìƒ', 'ì¹´íŠ¸ ?„ë³µ ?¬ê³ ', '?˜ë¬´ ê±¸ë ¤ ì¡°ë‚œ', 'ì¤??€ë¦??¤ì¸ ë¹„ìƒ', '?¬ë§‰ ?ìˆ˜ ê³ ê°ˆ',
    '?•ê? ?…ì¶© ê³µê²©',
    '?™ì„ ?™í•˜ ê°‡í˜', 'ë§‰ë°° ?Šê²¨ ê³ ë¦½', '?µìœ ë¦?ê· ì—´ ë°œê²¬', '?™ë¢° ?¬ê³  ë°œìƒ', '?¸íŒŒ ë°€ì§??•ì‚¬', 'ìº í•‘ì¹??¼ì‚°?”íƒ„??,
    'ê³ ì˜¨ ?”ìƒ ?…ìŒ',
    '?Œí–¥ ?¥ë¹„ ê°ì „', '?¸í?ë¦??ŒíŒŒ ì¶©ëŒ', 'ë§ì—??ì¶”ë½ ë¶€??, '?êµ¬?€ ë¬´ë„ˆì§?, '?¹êµ¬?ë? ?œë¹„', 'ì½”ì¸ê¸°ê¸° ?”ì¬',
  ];

  // ==================================================================
  // ?“¦ [Box 7-1-0] generateDramaticScenario ???œë¼ë§??í™” ?¥ë©´ ?ë™ ?ì„±
  // ==================================================================
  static Future<Map<String, String>?> generateDramaticScenario(
      String apiKey) async {
    final client = http.Client();
    try {
      // ?² [v4 ?©ë³¸ ?€] 200ê°?ê¸°ì´ˆ ?í™© + 20ê°??¥ë¥´ ?¨ì•— ??ë³€ì£????•ë?
      const genreSeeds = [
        // ?¼ìƒ/ê¸ì • (10ê°?
        'ì¹´í˜?ì„œ ??ë©”ë‰´ ì¶”ì²œë°›ê¸°', '?´ì™¸?¬í–‰ ì¤??„ì??¸ê³¼ ê¸?ë¬»ê¸°', '???´ì›ƒ?ê²Œ ?¸ì‚¬?˜ë©° ?™ë„¤ ?Œê°œ',
        '?·ê?ê²Œì—???¤í????ë‹´', '?Œì‚¬ ?ì‹¬?œê°„ ?™ë£Œ?€ ë§›ì§‘ ? í¬', '?¬ìŠ¤??ì²«ë‚  ?¸ë ˆ?´ë„ˆ?€ ?ë‹´',
        'ê³µí•­ ì²´í¬??ì¹´ìš´???€??, '?¸í…” ì²´í¬?¸í•˜ë©?ë°??…ê·¸?ˆì´???”ì²­', '?™ë„¤ ?œì ?ì„œ ì±?ì¶”ì²œ ?€??,
        'ë°˜ë ¤?™ë¬¼ ?°ì±… ì¤?ê²¬ì£¼?¼ë¦¬ ?€??,
        // ?œë¼ë§ˆí‹±/ê°ˆë“± (10ê°?
        'ë¶ˆë¥œ ë°œê°, ë¶€ë¶€ ê°ˆë“±', 'ì§ì¥ ??ê¶Œë ¥ ?¤íˆ¼, ?´ê³  ?„ê¸°', '?•ì‚¬ ?¬ë¬¸, ?©ì˜??ì·¨ì¡°',
        '?¬ë²Œê°€ ?ì† ë¶„ìŸ', 'ë¹„ë? ?°ì¸ ?¤í‚´', 'ê°€ì¡?ë¹„ë? ??¡œ', 'ì²«ì‚¬???¬íšŒ, ê°ì • ì¶©ëŒ',
        'ë£¸ë©”?´íŠ¸ ?í™œ ê·œì¹™ ê°ˆë“±', '?˜ë¶ˆ ?”ì²­?˜ëŠ”??ë§¤ì¥ ì§ì›??ê±°ë?', 'ì¹œêµ¬ê°€ ë¹Œë¦° ????ê°šìŒ',
      ];
      final pool = [..._baseSituations200, ...genreSeeds];
      final pick = pool[Random().nextInt(pool.length)];
      // 200ê°??©ë³¸???ˆìœ¼ë©?"ê·¸ë?ë¡???êµ¬ì²´ ?í™©", 20ê°??¨ì•—?´ë©´ "?•ì¥???¥ë¥´ ?ŒíŠ¸"
      final bool isConcrete = _baseSituations200.contains(pick);

      final systemPrompt =
          "You are a creative director for a high-immersion English roleplay app.\n"
                  "Your job is to create ONE vivid scene inspired by real-life situations, Netflix series, Korean/American dramas, or movies.\n"
                  "\n"
                  "OUTPUT: Return ONLY valid JSON, no extra text.\n"
                  "{\n"
                  '  "situation": "?µì‹¬ ?í™© ?”ì•½ (10-15 Korean chars, e.g. ì¹´í˜?ì„œ ? ë©”??ì¶”ì²œ)",\n'
                  '  "ai_role": "AI ìºë¦­??(10???´ë‚´, with clear personality, e.g. ì¹œì ˆ??ë°”ë¦¬?¤í?)",\n'
                  '  "user_role": "? ì? ìºë¦­??(8???´ë‚´, e.g. ?¨ê³¨ ?ë‹˜)"\n'
                  "}\n"
                  "\n"
                  "RULES:\n"
                  "- situation: vivid and specific. Do NOT name any show/character.\n"
                  "- ai_role: give a personality that fits the genre (friendly, enthusiastic, suspicious, furious, etc).\n"
                  "- user_role: the user naturally belongs in the scene.\n"
                  "- For everyday/positive genres: warm, helpful, curious personalities.\n"
                  "- For dramatic/conflict genres: intense, confrontational, emotional personalities.\n" +
              (isConcrete
                  ? '- USE THIS EXACT SITUATION as-is: "$pick". Do NOT invent a different one. Keep the situation field essentially equal to "$pick" (light wording polish within 10-15 Korean chars OK). Only assign a fitting ai_role and user_role.'
                  : "- Genre hint this round: $pick");

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
                  'content': 'ì§€ê¸?ë°”ë¡œ JSON ?ì„±?´ì¤˜.',
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
  // ?“¦ [Box 7-1-A] streamUserTranslation ??CoT 2?¨ê³„ ë²ˆì—­
  // ==================================================================
  static Stream<String> streamUserTranslation({
    required String apiKey,
    required String textOriginal,
    required String targetLang,
    required String contextStr,
    String userRole = '',
    String situation = '',
    bool isCorrectionRetry = false,
  }) async* {
    final client = http.Client();
    try {
      final roleContext = userRole.isNotEmpty
          ? '\nThe user is playing the role of "$userRole"${situation.isNotEmpty ? ' in a "$situation" scenario' : ''}.'
          : '';
      final sysPrompt =
          """You are an expert real-time Korean-to-$targetLang translator for a live roleplay conversation.$roleContext
${isCorrectionRetry ? '''
[CORRECTION RESTATEMENT - ABSOLUTE, applies to THIS input]
This input is the user RE-STATING what they actually meant after a misunderstanding.
- Do NOT output [CORRECTION], [MISHEARD], or [DISSATISFIED].
- STRIP the correction lead-in: "?„ë‹ˆ" / "?„ë‹ˆ ??ë§ì?" / "??ë§ì?" / "ê·¸ê²Œ ?„ë‹ˆ?? / "?´ê? ë§í•œ ê±? / "?¼ê³  ?ˆì–?? / "?¼ê³  ë§í–ˆ?? / "I mean" / "I said" / "what I said was".
- Translate ONLY the corrected core content into natural $targetLang.
Example: "?„ë‹ˆ ??ë§ì? ?¹ì‹  ?˜ëª»?´ë¼ê³ ìš”" -> "It's clearly your fault." (NOT "I mean, what I said was it's your fault.")
''' : ''}

Korean is a heavy pro-drop language - subjects, objects, and pronouns are constantly omitted when clear from context.

[CASE CORRECTION] ??Check this FIRST, only when the conversation history contains at least one "User:" line.
The user is correcting the AI's misunderstanding or mishearing of their PREVIOUS utterance.
Signs:
- Starts with a correction signal: "?„ë‹ˆ" / "?„ë‹ˆ?? / "??ê·¸ê²Œ ?„ë‹ˆ?? / "?¤ì‹œ" / "??ë§ì?" / "ê·¸ëŸ¬?ˆê¹Œ" / "?´ê? ë§í•œ ê±? / "?¼ê³  ?ˆì–?? / "?¼ê³  ë§í–ˆ?? / "I mean" / "I said" / "what I said was" / "that's not what I said" / "actually" / "no," / "wait,"
- AND the content is clearly a re-statement or clarification of the LAST "User:" line in the history, NOT new information.
- The user is essentially saying "that's not what I said ??what I said was X."
${isCorrectionRetry ? 'NOTE: This is a correction RE-PROCESS. Do NOT output [CORRECTION] here; follow the [CORRECTION RESTATEMENT] rule at the top and translate only the core content.' : 'If this is a correction, output EXACTLY: [CORRECTION]  (and nothing else)'}
Do NOT output [CORRECTION] for genuinely NEW information that merely starts with "?„ë‹ˆ" etc. BUT if the AI's previous turn clearly captured the user's earlier utterance as DIFFERENT content (a wrong word or a wrong topic) and the user is now restating what they actually meant, output [CORRECTION] even when the restatement also reads like a fresh answer. Test: would the user naturally say "that's not what I said"? If yes -> output [CORRECTION].

[CASE MISHEARD] ??Check this SECOND, only when the history contains at least one "User:" line.
The user is COMPLAINING that their previous words were misheard or misunderstood, WITHOUT restating what they actually said.
Signs: "??ë§ì´ ê·¸ëŸ° ?»ì´ ?„ë‹ˆ?? / "ê·¸ëŸ° ê±??„ë‹ˆ?? / "??ë§ì? ê·¸ê²Œ ?„ë‹ˆ?? / "?˜ëª» ?¤ì—ˆ?? / "?˜ëª» ?ì—ˆ?? / "?˜ëª» ?Œì•„?¤ì—ˆ?? / "that's not what I meant" / "you misheard me" / "you got my words wrong"
- AND the utterance contains NO restated content (no actual new statement).
If so, output EXACTLY: [MISHEARD]  (and nothing else)
If the complaint INCLUDES the corrected content, use [CORRECTION] instead.

[CASE DISSATISFIED] ??Check this THIRD, only when the history contains at least one "AI:" line.
The user is stepping OUT of the roleplay to complain about the AI's LAST reply itself and wants a different one.
Signs: "ë¬´ìŠ¨ ?€?µì´ ê·¸ë˜" / "ë¬´ìŠ¨ ì§ˆë¬¸??ê·¸ë˜" / "?€?µì´ ?´ìƒ?? / "?¤ë¥¸ ë§??´ì¤˜" / "?¤ì‹œ ?€?µí•´ ë´? / "ê·??€??ë³„ë¡œ?? / "say something else" / "that's a weird reply" / "answer again"
More signs (MILD dissatisfaction ??these ALSO count when clearly aimed at the AI reply itself, OUT of character): "ë³„ë¡œ" / "ë³„ë¡ ?? / "??ê·¸ê±´ ì¢€" / "?ì´" / "ê·¸ëŸ° ê±?ë§ê³ " / "?¬ë??†ì–´" / "?´ìƒ?˜ë„¤" / "ë­ì•¼ ê·¸ê²Œ" / "meh" / "not really" / "hmm, not that one"
Even slight or indirect displeasure aimed at the AI's last reply counts.
Do NOT output this when the user is answering negatively IN CHARACTER (e.g., refusing an offer inside the roleplay is a valid in-character answer).
If so, output EXACTLY: [DISSATISFIED]  (and nothing else)

[INTERNAL THINKING - do not output]
Step 1. CONTEXT CHECK: Review conversation history.
Step 2. SUBJECT RESTORATION: The speaker is${userRole.isNotEmpty ? ' a "$userRole"' : ' the user'}. Identify and restore any omitted subject/pronoun from THEIR perspective.
  Use these Korean grammar markers to determine roles:
  - ~??ê°€ = SUBJECT marker (doer of action): "?„ë§ˆê°€ ?¬ì¤¬?? ??Mom bought it (Mom is subject)
  - ~?€/??= TOPIC marker (often the subject): "?˜ëŠ” ê°”ì–´" ??I went
  - ~?œí…Œ/?ê²Œ = RECIPIENT marker (indirect object): "?˜í•œ??ì¤¬ì–´" ??gave it TO ME
  - ~??ë¥?= OBJECT marker (thing acted upon): "ê·¸ê±¸ ë´¤ì–´" ??saw THAT
  - Honorific ~(????attaches to the SUBJECT's verb: "? ìƒ?˜ì´ ?¤ì…¨?? ??The teacher came (teacher is subject, not me)
  - ~?´ì¤¬???´ì£¼?¨ì–´ = someone did something FOR someone else: the person before ê°€/??is the doer
Step 3. TRANSLATE: Produce natural $targetLang speech that fits${userRole.isNotEmpty ? ' the "$userRole" role' : ' the user'}.

[COMMON MISTAKES - avoid these]
Korean: "ê±”ê? ?˜í•œ???„í™”?ˆì–´" ??CORRECT: He called me. WRONG: I called him.
Korean: "?„ë§ˆê°€ ?©ëˆ ì¤¬ì–´" ??CORRECT: Mom gave me allowance. WRONG: I gave mom allowance.
Korean: "? ìƒ?˜ì´ ì¹?°¬?´ì£¼?¨ì–´" ??CORRECT: The teacher praised me. WRONG: I praised the teacher.
Korean: "ì¹œêµ¬ê°€ ?”ì¦˜ ë°”ë¹ ??ëª?ë§Œë‚˜" ??CORRECT: My friend is busy lately, so I can't meet him. WRONG: I'm busy lately...
The particle before the verb's doer (??ê°€) is ALWAYS the subject. Never swap subject and object.

[CLARIFICATION GUARD ??In-Character]
Before translating, check: is the subject/object clear from the utterance OR resolvable from History?
If clear ??proceed with normal translation.
If genuinely ambiguous AND History cannot resolve it ??output EXACTLY:
[CLARIFY] <short, in-character clarification question in $targetLang>

The question must sound like the AI's assigned character is asking, not a system message.
Style pool ??pick ONE that fits the character's personality and VARY each time:
- Terse: "Who are you talking about?"
- Skeptical: "Who? Be specific."
- Curious: "Oh ??who exactly do you mean?"
- Playful: "I'm gonna need a name to work with here!"
- Confirming: "Do you mean [person from history]?"

NEVER output [CLARIFY] if the subject can be inferred from context.
NEVER break character when asking.

[OUTPUT RULES]
- The user IS${userRole.isNotEmpty ? ' a "$userRole"' : ' the user'} ??translate their words from THAT perspective only.
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
  // ?“¦ [Box 7-1-B] generateCleanOriginal ???â†’????²ˆ??
  // ==================================================================
  static Future<String> generateCleanOriginal({
    required String apiKey,
    required String englishText,
  }) async {
    // ë¹??…ë ¥ ê°€?? GPT??ë¹?ë¬¸ì¥??ë³´ë‚´ ë©”í? ?‘ë‹µ??ë°›ëŠ” ê²ƒì„ ë°©ì?.
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
                        '''?¹ì‹ ?€ ?œì˜ ?µì—­ ?„ë¬¸ê°€?…ë‹ˆ?? ?¤ìŒ ?ì–´ ë¬¸ì¥??**?ì—°?¤ëŸ¬???œêµ­??êµ¬ì–´ì²?*ë¡?ë²ˆì—­?˜ì„¸??

[?ˆë? ê·œì¹™ - ë¬¸ì¥ ?„ë½ ê¸ˆì?]
- ?ë¬¸??ëª¨ë“  ë¬¸ì¥??ë¹ ì§?†ì´ ë²ˆì—­?˜ì„¸?? ?”ì•½/ì¶•ì•½/?ëµ ?ˆë? ê¸ˆì?.
- ?ë¬¸??2ë¬¸ì¥?´ë©´ ë²ˆì—­??ë°˜ë“œ??2ë¬¸ì¥, 3ë¬¸ì¥?´ë©´ 3ë¬¸ì¥.
- ë§ˆì¹¨??.) ?ëŠ” ë¬¼ìŒ???) ?¨ìœ„ë¡??Šì–´??ê°ê° ë²ˆì—­?˜ì„¸??

[ì£¼ì–´ ?ëµ ì²˜ë¦¬]
- ?œêµ­?´ëŠ” ì£¼ì–´ë¥??ì£¼ ?ëµ?©ë‹ˆ?? ?ì–´??I/You/He/She/We/Theyë¥?ë¬´ì¡°ê±?ê·¸ë?ë¡??´ë¦¬ì§€ ë§ˆì„¸??
- ë¬¸ë§¥???¹ì—°??ì£¼ì–´??ê³¼ê°???ëµ?˜ì—¬ ?ì—°?¤ëŸ½ê²?ë§Œë“œ?¸ìš”.
  ?? "I need to go" ??"ê°€?¼ê² ?´ìš”" (?? / "?˜ëŠ” ê°€???œë‹¤" (???´ìƒ‰)
  ?? "Are you coming?" ??"??ê±°ì˜ˆ??" (?? / "?¹ì‹ ?€ ?¤ê³  ?ˆìŠµ?ˆê¹Œ?" (??
- ?€???ë?ê°€ ëª…í™•?˜ë©´ "???¹ì‹ "???ëµ ê°€?¥í•©?ˆë‹¤.
- ?˜ì?ë§??˜ë? ?¼ë™ ê°€?¥ì„±???ˆì„ ?ŒëŠ” ì£¼ì–´ë¥??´ë¦½?ˆë‹¤.

[êµ¬ì–´ì²???
- ë¬¸ì–´ì²?X, ?¼ìƒ ?€?”ì²´ O
- "~?˜ì??? X ??"~?ˆì–´?? O
- "~?´ë‹¤" X ??"~?´ì—??~?ˆìš”" O

[ì¶œë ¥]
- ë²ˆì—­ë¬¸ë§Œ ì¶œë ¥. ?¤ëª…/ì£¼ì„/?°ì˜´???†ìŒ.
- ?ë¬¸??ë¬¸ì¥ ?˜ì? ?™ì¼?˜ê²Œ ì¶œë ¥.
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
          // ?‘ë‹µ ê²€ì¦? ë²ˆì—­ ?€???ˆë‚´/ë©”í? ?‘ë‹µ???¤ë©´ ?¬ì‹œ????fallback.
          final lower = result.toLowerCase();
          if (lower.contains('ë²ˆì—­??ë¬¸ì¥') ||
              lower.contains('ë¬¸ì¥???„ìš”') ||
              lower.contains('ë¬¸ì¥???œê³µ') ||
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
  // ?“¦ [Box 7-1-C] streamRoleplayResponse ??AI ë¹™ì˜ ?‘ë‹µ
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
                  '- Drive the scene forward ??pressure, question, or react to force the user to respond.\n'
                  '- If the user\'s input is completely unintelligible (speech recognition error), output EXACTLY: [RETRY]' +
              (rejectedReply.trim().isEmpty
                  ? ''
                  : '\n- IMPORTANT: The user disliked your previous reply: "${rejectedReply.trim()}". Give a COMPLETELY DIFFERENT in-character reply this time ??different angle, different wording. Do NOT repeat or rephrase it.');

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
  // ?“¦ [Box 7-1-D] generateAiOpener ??AI ì²?ë°œí™” ?ì„± (?¤íŠ¸ë¦¬ë°)
  // ==================================================================
  // ?¯ [ë¡¤í”Œ?ˆì´ ?€???œì‘ 3?ì¹™]
  //
  // ?ì¹™ 1. AIê°€ ë¨¼ì? ë§ì„ ?œì‘?œë‹¤.
  //         ? ì?ê°€ ë§ˆì´?¬ë? ?„ë¥´ë©?AIê°€ ?¤í”„??ë©˜íŠ¸ë¥?ë¨¼ì? ë°œí™”?˜ê³ ,
  //         TTS ?¬ìƒ ?„ë£Œ ??ë§ˆì´??ì²?·¨ê°€ ?œì‘?œë‹¤.
  //
  // ?ì¹™ 2. ?€ê²??¸ì–´(targetLang)ë¡œë§Œ ë§í•œ??
  //         ai_role / user_role ?´ë¦„???œê?ë¡?ì£¼ì–´?¸ë„
  //         ?¤ì œ AI ?€?¬ëŠ” ë°˜ë“œ??targetLang?¼ë¡œë§?ì¶œë ¥.
  //         ?œêµ­????ëª¨êµ­?´ë? ?ˆë? ?ì? ?ŠëŠ”??
  //
  // ?ì¹™ 3. ?´ë‹¹ ??• ???¤ì œ ?„ì‹¤?ì„œ ê°€??ë¨¼ì? ??ë²•í•œ ?ì—°?¤ëŸ¬??ë§ë¡œ ?œì‘.
  //         ?´ìƒ‰???™ìŠµ???¸ì‚¬ X, ê·???• Â·?í™©????ë§ëŠ” ?„ì‹¤??êµ¬ì–´ì²?O.
  //         (?? ë°”ë¦¬?¤í? ??"What can I get for you?",
  //              ?˜ì‚¬ ??"So, what brings you in today?",
  //              ?¸ë ˆ?´ë„ˆ ??"Is this your first session here?")
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
          '1. Start the scene IMMEDIATELY with your first line ??no greetings, no meta-commentary.\n'
          '2. Read the emotional tone of the situation: if dramatic, be intense; if everyday, be natural and warm.\n'
          '3. Do NOT mention any drama, movie, or show titles. Keep it real and seamless.\n'
          '4. Your first line must be a natural, in-character statement or question that draws the user into the scene.\n'
          '5. Adopt the exact personality of "$aiRole". Use natural spoken $targetLang ??NOT textbook dialogue.\n'
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

    // ë°ì? ?Œë? ë°°ê²½ (?ë‹¨ ì¢Œì¸¡)
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFF1E7DB5));

    // ì§™ì? ?Œë? ?¼ê°??(?˜ë‹¨ ?°ì¸¡)
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.05, size.height)
        ..lineTo(size.width, size.height * 0.05)
        ..lineTo(size.width, size.height)
        ..close(),
      Paint()..color = const Color(0xFF0B4870),
    );

    // ê³¨ë“œ ?€ê°ì„ 
    canvas.drawLine(
      Offset(size.width * 0.04, size.height * 0.96),
      Offset(size.width * 0.96, size.height * 0.04),
      Paint()
        ..color = const Color(0xFFD4AF37)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // ê³¨ë“œ ?í˜• ?Œë‘ë¦?
    canvas.drawCircle(
      center,
      r - 1.5,
      Paint()
        ..color = const Color(0xFFD4AF37)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    final col = active ? Colors.white : const Color(0x61FFFFFF);

    // ?ë‹¨ ì¢Œì¸¡ "T"
    _drawText(canvas, 'T', Offset(size.width * 0.09, size.height * 0.06),
        size.width * 0.34, col);

    // ë¹¨ê°„ ?í˜• ?¬ì¸??(??
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

    // ?˜ë‹¨ ?°ì¸¡ "T"
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
