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

/// ==================================================================== [Box
/// 2: ?´ë˜??? ì–¸ë¶€]
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
  // ?“¦ [Box 3: ?íƒœ ë³€??ë°?ì´ˆê¸°??
  // ====================================================================
  String _deepgramKey = "";
  String _openAiKey = "";
  bool _isConversationActive = false;
  bool _isExiting = false; // ?”§ [EXIT-GUARD] PopScope+ë²„íŠ¼ ?´ì¤‘ ì¢…ë£Œ ë°©ì?
  double _fontScale = 1.0;
  bool _showOriginal = true;
  int _turnCounter = 0;
  String? _sessionDocId; // ?”§ [v3 ì¶”ê?] ì²??€?????¸ì…˜ ID (?´ë¡  ë³€ê²???null ë¦¬ì…‹)
  DocumentReference? _myHistoryRef; // ?”§ [?ˆìŠ¤? ë¦¬] chat_history ë¬¸ì„œ ì°¸ì¡° (Duo ?¨í„´)
  List<String> _lastExchangeMsgIds = []; // [?•ì •] ì§ì „ êµí™˜ messages docId
  bool _showSeedHint = false; // ?©ì„± ë¬¸ì¥ ?ˆë‚´ ë§í’???œì‹œ ?¬ë?
  Timer? _seedHintTimer; // ?©ì„± ë§í’??3ì´??ë™ ?¨ê? ?€?´ë¨¸

  // ?€?€ Idle Timeout v2 ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
  // ê¸°ì?: "? ì???AI???„ë¬´ ?‘ë™???†ëŠ” ?íƒœ"ê°€ ?°ì† 60ì´?ì§€?ë˜ë©?pause.
  //  - AI ?‘ë™ = _ttsQueueManager.isBusy (TTS ?¬ìƒ/?€ê¸?
  //  - ? ì? ?‘ë™ = _voiceManager != null (ë§ˆì´???°ê²°/?¹ìŒ)
  // 1ì´?ì£¼ê¸° ê°ì‹œ ?€?´ë¨¸ê°€ ?‘ë™ ?¬ë?ë¥?ë³´ê³  idle ?„ì ì´ˆë? ì¦ê°?œë‹¤.
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
      BillingTicker.instance.resume();
      BillingTicker.instance.logMode('study_room');
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
    _idlePauseTimer = null;
    _idleElapsedSec = 0;
  }
  // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€

  // ?€?€ [FAST-LANE] ë¡œì»¬ ì§ˆë¬¸ ë¶ˆë§Œ ?ì • ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
  // ëª¨ë¸ ?¸ì¶œ ??raw ?œêµ­??transcript?ì„œ ì§ˆë¬¸ ë¶ˆë§Œ ?œí˜„??ê°ì?.
  // ?•ìƒ ë¶€???µë?("?„ë‹ˆ, ??ê°”ì–´")?€ ?¡ì? ?Šë„ë¡?ì§ˆë¬¸ ?€???œí˜„ ?„ì£¼ë¡??ì •.
  bool _isQuestionDissatisfactionRaw(String text) {
    final t = text.trim().toLowerCase();
    const kws = [
      'ì§ˆë¬¸??ë­?,
      'ë¬´ìŠ¨ ì§ˆë¬¸??,
      'ê·?ì§ˆë¬¸',
      '??ì§ˆë¬¸',
      '?¤ë¥¸ ê±?ë¬¼ì–´ë´?,
      '?¤ë¥¸ ì§ˆë¬¸',
      '?¤ë¥¸ ê±?ë¬¼ì–´ë´?,
      'ë­ì•¼ ê·¸ê²Œ',
      'ë­ì•¼ ?´ê²Œ',
      'ê·¸ê²Œ ë­ì•¼',
      'ë³„ë¡ ??,
      '?¬ë??†ì–´',
      '?´ìƒ??ì§ˆë¬¸',
      '?´ìƒ?˜ë„¤',
      'ê·¸ê±´ ì¢€ ?„ë‹Œ',
      'ê·¸ê±´ ë³„ë¡œ',
      'ê·¸ê±´ ?«ì–´',
      'ê·¸ëŸ° ê±?ë§ê³ ',
      'ì§ˆë¬¸ ë°”ê¿”',
      'ë°”ê¿”ì¤?,
      '?¤ë¥¸ ê±¸ë¡œ',
      'ë§ˆìŒ?????¤ì–´',
      'ë§˜ì— ???¤ì–´',
      'ê°™ì? ì§ˆë¬¸',
      // ?´ë? ?µí•œ ?´ìš©???¤ì‹œ ë¬»ëŠ” ë°˜ë³µ ì§ˆë¬¸ ë¶ˆë§Œ
      '?„ê¹Œ ë§í–ˆ',
      '?´ë? ë§í–ˆ',
      'ë°©ê¸ˆ ë§í–ˆ',
      '?´ë? ?€??,
      '?„ê¹Œ ?€??,
      'ê·¸ê±° ë§í–ˆ',
      'ë§í–ˆ?–ì•„',
      '?€?µí–ˆ?–ì•„',
      'ë¬¼ì–´ë´¤ì–??,
      'ê°™ì? ê±?,
      '??ë¬¼ì–´',
      'ë°˜ë³µ',
      '?‘ê°™?€ ì§ˆë¬¸',
      '?„ê¹Œ ?˜ê¸°',
      '?´ë? ?˜ê¸°',
      'ask something else',
      'change the question',
      'different question',
      "don't like that question",
      'already said',
      'already answered',
      'already told you',
      'asked that already',
      'same question',
    ];
    for (final kw in kws) {
      if (t.contains(kw)) return true;
    }
    return false;
  }

  /// Seed snippet filter shared by FreeTalk and Roleplay history fetchers.
  static bool _isSeedFiller(String s) {
    final t = s.replaceAll(RegExp(r'[\s\.,!?~??'), '').toLowerCase();
    if (t.length < 6) return true;
    const fillerPatterns = [
      '??,
      '??,
      '??,
      'ê·¸ë˜',
      'ë§ì•„',
      'ë§ì•„??,
      'ì¢‹ì•„',
      'ì¢‹ì•„??,
      'ê¸€??,
      'ok',
      'okay',
      '??,
      '??,
      '??,
      'ê·¸ë˜??,
      'ê·¸ëŸ¬?ˆê¹Œ',
      'ê·¸ëŸ´ê¹?,
      'ê·¸ë ‡êµ¬ë‚˜',
      '?Œê² ??,
      '?Œê² ?µë‹ˆ??,
      'ê³ ë§ˆ??,
      'ê³ ë§™?µë‹ˆ??,
      'yes',
      'yeah',
      'sure',
      'right',
      'thank you',
      'thanks',
    ];
    if (fillerPatterns.contains(t)) return true;
    const complaintPatterns = [
      'ì§ˆë¬¸',
      'ë¬¼ì–´ë´?,
      'ë¬¼ì–´ë³?,
      '?¤ì‹œë§?,
      '?´ìƒ??,
      'ë³„ë¡œ',
      'ë­ì•¼',
      'ë°”ê¿”',
      'ê·¸ëŸ°ê±°ë§ê³?,
      'ê·¸ëŸ°ê²ƒë§ê³?,
      '?´ê±°',
      '?¤ë¥¸ê±?,
      '?¤ë¥¸ê±?,
      'ë§ˆìŒ?ì•ˆ',
      'ë§˜ì—??,
      'question',
      'askme',
      'weird',
    ];
    for (final p in complaintPatterns) {
      if (t.contains(p)) return true;
    }
    return false;
  }
  // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€

  Widget _buildIdleBanner() => const SizedBox.shrink();

  Widget _buildIdleOverlay() => const SizedBox.shrink();
  // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€

  // ?”§ [v3.4 ë°œí™” ?©ì¹˜ê¸? ? ì? ?”ë“¬ê±°ë¦¼ ?€??  // speech_final ë°›ì•„??ë°”ë¡œ ?Œì´?„ë¼???œì‘ ???˜ê³  1.2ì´??€ê¸?  // ?€ê¸?ì¤???ë°œí™” ?¤ë©´ ?©ì³??ì²˜ë¦¬ (ìµœì¢… ???©ì–´ë¦¬ë¡œ)
  String _pendingTranscript = ''; // ?€ê¸?ì¤‘ì¸ ? ì? ë°œí™” ?„ì 
  Timer? _commitTimer; // "ì§„ì§œ ?ë‚¬?”ì?" ?•ì • ?€?´ë¨¸
  static const int COMMIT_WAIT_MS = 1200; // ë°œí™” ?©ì¹˜ê¸??€ê¸??œê°„

  void _log(String tag, String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    final line = '[$ts] $tag $msg';
    print(line);
    AppLogLedger.instance.add('STEPEXPAND', '$tag $msg');
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

  // ?Œ± ?¤í…?µìŠ¤?¬ë“œ ?„ìš© ?íƒœ
  static const int MAX_TURNS = 5; // 5???ë™ ë§ˆë¬´ë¦?ë£?  bool _isSessionComplete = false; // 5???„ë£Œ ?Œë˜ê·?(ë§ˆì´??? ê¸ˆ)
  bool _isPolishing = false; // ?¸ë ¨??ë³€??ë¬¸ì¥ ?ì„± ì¤?  String _polishedSentence = ""; // ?ì„±???¸ë ¨??ë³€??  bool _showPolishButton = false; // 5???„ë£Œ ??"Polished Version" ë²„íŠ¼ ?œì‹œ
  final GlobalKey _polishedCardKey = GlobalKey();
  final List<String> _history = []; // polish ?„ì„± ë¬¸ì¥ ?„ì  (?¸ì…˜ ê°?? ì?)

  // ?Œ± [AUTO-FLOW] 5???„ë£Œ ???ë™ ?œì‹œ ?íƒœ
  String _expandedFinalSentence = ""; // ?„ì„±???•ì¥ ë¬¸ì¥ (ë³„ë„ ?œì‹œ)
  bool _showExpandedFinalCard = false; // ?•ì¥ ë¬¸ì¥ ì¹´ë“œ ?œì‹œ ?¬ë?
  bool _showStudyRoomPrompt = false; // "Study Room?ì„œ ?°ìŠµ ?˜ì„¸?? ?œì‹œ ?¬ë?
  int _consecutiveRestateCount = 0; // ê°™ì? ???°ì† GARBLED ?Ÿìˆ˜ (2 ?´ìƒ?´ë©´ ???¬ìš´ ë¬¸ì¥ ? ë„)
  // ?¯ [PRACTICE] ?˜ë??¨ìœ„ ë°˜ë³µ ?°ìŠµ ëª¨ë“œ
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
  Set<String> _practiceRecognizedWords = {};
  String? _userWavPath;

  // ?¤ë””??ë°?UI
  final List<Map<String, dynamic>> _localMessages = [];
  final ScrollController _scrollController = ScrollController();
  // [SCROLL-THROTTLE] State for suppressing excessive top-pin scroll calls.
  DateTime? _lastScrollTopAt;
  int _lastScrollTopIndex = -1;
  final Map<int, GlobalKey> _itemKeys = {};
  DeepgramV2VoiceManager? _voiceManager;
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final TtsQueueManager _ttsQueueManager;

  // ?±ï¸ ?±ëŠ¥ ì¸¡ì •??ì´ˆì‹œê³?  final Stopwatch _swDeepgram = Stopwatch();
  final Stopwatch _swOpenAI = Stopwatch();
  final Stopwatch _swTTS = Stopwatch();
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
    _seedHintTimer?.cancel();
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
        // ??ë¡œë“œ ?„ë£Œ ???œì‘ ?ˆë‚´ ??? ì? ê¸°ë³¸ ë¬¸ì¥ ?€ê¸?        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startSessionWaitingForUserSeed();
        });
      }
    } catch (e) {
      print('??Key Load Error: $e');
    }
  }

  // ====================================================================
  // ?¯ [?¤í…?µìŠ¤?¬ë“œ ?€???¤ê³„ ?ì¹™]
  // ====================================================================
  // 1. ? ì?ê°€ ë¨¼ì? ê¸°ë³¸ ë¬¸ì¥???œì•ˆ?œë‹¤ (User-First)
  //    - ?¸ì…˜ ?œì‘ ??AI???œì‘ ?ˆë‚´ë§??˜ê³  ?€ê¸?  //    - ? ì???ì²?ë¬¸ì¥???•ì¥ seedê°€ ??  //
  // 2. AI???œì‘ ?ˆë‚´ ???€ê¸?(Guided Waiting)
  //    - "?€?”í•˜ë©´ì„œ ë¬¸ì¥???˜ë ¤ê°€ê³??¶ì? ê¸°ë³¸ ë¬¸ì¥???˜ë‚˜ ?œì•ˆ??ì£¼ì„¸??"
  //    - OpenAI ì§ˆë¬¸ ?ì„± API ?¸ì¶œ ?†ìŒ
  //    - ?ˆë‚´ë¬?TTS ?„ë£Œ ??STT ?ë™ ?œì‘
  //
  // 3. ë§ˆì´??ë²„íŠ¼ ?†ìŒ (No Mic Button)
  //    - ?ˆë‚´ë¬?ë°œí™” ?„ë£Œ ??STT ?ë™ ?œì‘ (? ì?ê°€ ë²„íŠ¼ ?„ë? ?„ìš” ?†ìŒ)
  //    - ?”ë©´ ?˜ë‹¨?€ ?¸ë? ë¶ˆë¹› ?¸ë””ì¼€?´í„°ë§??œì‹œ ??ì±„íŒ… ê³µê°„ ìµœë???  //
  // 4. ?´í›„ AI??ê¸°ì¡´ 5???•ì¥ ?¨í„´?€ë¡?ì§§ì? ? ë„ ì§ˆë¬¸???œë‹¤
  //    - ?€???¨í„´ê³??•ì¥ ë¡œì§?€ ê¸°ì¡´ ? ì?
  // ====================================================================

  // ?†• ?„ë¦¬??ê¸°ë¡?ì„œ ? ì?(HOST) ë°œí™” ìµœë? 3ê°œë? ìµœê·¼ 3ê°?ë°©ì—???˜ì§‘.
  //   - mode alias ?•ì¥?¼ë¡œ ?¤ì–‘???€?¥ê°’ ì»¤ë²„
  //   - role/field fallback?¼ë¡œ ?€???¤í‚¤ë§?ì°¨ì´ ?€??  //   - ê¸°ë¡ ?†ìœ¼ë©?ë¹?ë¦¬ìŠ¤?????¸ì¶œë¶€?ì„œ roleplay ?ëŠ” ê³ ì • ?ˆë‚´ë¡??´ë°±
  Future<List<String>> _fetchFreeTalkUserSnippets() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    try {
      final roomsSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('chat_history')
          .orderBy('created_at', descending: true)
          .limit(30)
          .get();

      // mode alias: free_talk, freetalk, freeTalk, ai_free_talk, free_talk_mode
      bool isFtMode(String m) {
        final n = m.toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');
        return n == 'free_talk' ||
            n == 'freetalk' ||
            n == 'ai_free_talk' ||
            n == 'free_talk_mode';
      }

      final freeTalkRooms = roomsSnap.docs
          .where((d) => isFtMode((d.data()['mode'] ?? '').toString()))
          .take(5)
          .toList();
      if (freeTalkRooms.isEmpty) return [];

      // ì¤‘ë³µ ?Œí”¼: ìµœê·¼??????ë°??°ì„ 
      final prefs = await SharedPreferences.getInstance();
      final usedKey = 'freetalk_seed_used_${user.uid}';
      final used = Set<String>.from(prefs.getStringList(usedKey) ?? []);
      var pool = freeTalkRooms.where((d) => !used.contains(d.id)).toList();
      if (pool.isEmpty) {
        pool = List.of(freeTalkRooms);
        await prefs.remove(usedKey);
      }
      pool.shuffle();

      // ìµœê·¼ 3ê°?ë°©ì—???˜ì§‘
      final selectedRooms = pool.take(3).toList();
      final newUsed = Set<String>.from(prefs.getStringList(usedKey) ?? [])
        ..addAll(selectedRooms.map((r) => r.id));
      await prefs.setStringList(usedKey, newUsed.toList());

      // role ?ì • fallback: HOST, USER, host, user
      bool isHostRole(Map<String, dynamic> data) {
        final role =
            (data['role'] ?? data['speaker_role'] ?? data['sender'] ?? '')
                .toString()
                .toUpperCase();
        return role == 'HOST' || role == 'USER';
      }

      // ë©”ì‹œì§€ ?ìŠ¤??ì¶”ì¶œ fallback
      String extractText(Map<String, dynamic> data) {
        final orig = (data['original_text'] ??
                data['original'] ??
                data['text'] ??
                data['message'] ??
                data['content'] ??
                '')
            .toString()
            .trim();
        final tgt =
            (data['translated_text'] ?? data['target'] ?? '').toString().trim();
        return orig.isNotEmpty ? orig : tgt;
      }

      final List<String> allCandidates = [];
      for (final room in selectedRooms) {
        try {
          final msgSnap = await room.reference.collection('messages').get();
          final texts = msgSnap.docs
              .where((d) => isHostRole(d.data()))
              .map((d) => extractText(d.data()))
              .where((s) => s.isNotEmpty && !_isSeedFiller(s))
              .toList();
          allCandidates.addAll(texts);
        } catch (_) {}
      }

      if (allCandidates.isEmpty) return [];
      allCandidates.sort((a, b) => b.length.compareTo(a.length));
      final seedPool = allCandidates.take(8).toList()..shuffle();
      return seedPool.take(3).toList();
    } catch (e) {
      _log('? ï¸ [FT-SEED]', 'fetch ?¤íŒ¨: $e');
      return [];
    }
  }

  // ?†• roleplay ê¸°ë¡?ì„œ ? ì?(HOST) ë°œí™” 1~2ê°œë? ìµœê·¼ 3ê°?ë°©ì—???˜ì§‘.
  //   - mode alias ?•ì¥ (roleplay, role_play, routine_mode_roleplay)
  //   - ??• ê·?ë°œí™”?´ë?ë¡??¤ì œ ?¬ì‹¤ ?„ë‹˜ ??ì£¼ì œ/ë¶„ìœ„ê¸??¬ë£Œë¡œë§Œ ?¬ìš©
  Future<List<String>> _fetchRoleplayUserSnippets() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    try {
      final roomsSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('chat_history')
          .orderBy('created_at', descending: true)
          .limit(30)
          .get();

      // mode alias: roleplay, role_play, routine_mode_roleplay
      bool isRpMode(String m) {
        final n = m.toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');
        return n == 'roleplay' ||
            n == 'role_play' ||
            n == 'routine_mode_roleplay' ||
            n == 'roleplaying';
      }

      final rpRooms = roomsSnap.docs
          .where((d) => isRpMode((d.data()['mode'] ?? '').toString()))
          .take(5)
          .toList();
      if (rpRooms.isEmpty) return [];

      final prefs = await SharedPreferences.getInstance();
      final usedKey = 'roleplay_seed_used_${user.uid}';
      final used = Set<String>.from(prefs.getStringList(usedKey) ?? []);
      var pool = rpRooms.where((d) => !used.contains(d.id)).toList();
      if (pool.isEmpty) {
        pool = List.of(rpRooms);
        await prefs.remove(usedKey);
      }
      pool.shuffle();

      // ìµœê·¼ 3ê°?ë°©ì—???˜ì§‘
      final selectedRooms = pool.take(3).toList();
      final newUsed = Set<String>.from(prefs.getStringList(usedKey) ?? [])
        ..addAll(selectedRooms.map((r) => r.id));
      await prefs.setStringList(usedKey, newUsed.toList());

      // role ?ì • fallback
      bool isHostRole(Map<String, dynamic> data) {
        final role =
            (data['role'] ?? data['speaker_role'] ?? data['sender'] ?? '')
                .toString()
                .toUpperCase();
        return role == 'HOST' || role == 'USER';
      }

      // ë©”ì‹œì§€ ?ìŠ¤??ì¶”ì¶œ fallback
      String extractText(Map<String, dynamic> data) {
        final orig = (data['original_text'] ??
                data['original'] ??
                data['text'] ??
                data['message'] ??
                data['content'] ??
                '')
            .toString()
            .trim();
        final tgt =
            (data['translated_text'] ?? data['target'] ?? '').toString().trim();
        return orig.isNotEmpty ? orig : tgt;
      }

      final List<String> allCandidates = [];
      for (final room in selectedRooms) {
        try {
          final msgSnap = await room.reference.collection('messages').get();
          final texts = msgSnap.docs
              .where((d) => isHostRole(d.data()))
              .map((d) => extractText(d.data()))
              .where((s) => s.isNotEmpty && !_isSeedFiller(s))
              .toList();
          allCandidates.addAll(texts);
        } catch (_) {}
      }

      if (allCandidates.isEmpty) return [];
      allCandidates.sort((a, b) => b.length.compareTo(a.length));
      final seedPool = allCandidates.take(6).toList()..shuffle();
      return seedPool.take(2).toList();
    } catch (e) {
      _log('? ï¸ [RP-SEED]', 'fetch ?¤íŒ¨: $e');
      return [];
    }
  }

  // ?†• ?„ë¦¬??ê¸°ë°˜ ì²?ì§ˆë¬¸??AI ë²„ë¸”ë¡??Œë” + ?€ê²?TTS ?¬ìƒ (ê·¸ë˜ë¨?ì§ˆë¬¸ê³??™ì¼ ?¨í„´)
  Future<void> _generateAndPlayFreeTalkSeedQuestion(
      List<String> snippets, List<String> roleplaySnippets) async {
    final String targetLangName = FFAppState().targetLang.isNotEmpty
        ? FFAppState().targetLang
        : 'English';
    final String nativeLangName =
        FFAppState().nativeLang.isNotEmpty ? FFAppState().nativeLang : '';

    if (mounted) {
      setState(() {
        _localMessages.add({'role': 'SYSTEM', 'target': '', 'original': ''});
      });
      _scrollToBottom();
    }
    final int aiIdx = _localMessages.length - 1;

    final aiStream = StepExpandBrain.streamFreeTalkSeedQuestion(
      apiKey: _openAiKey,
      myTarget: targetLangName,
      myNative: nativeLangName,
      snippets: snippets,
      roleplaySnippets: roleplaySnippets,
    );

    final questionTts = ChunkedTtsFetcher(
      _openAiKey,
      _ttsQueueManager,
      'nova',
      isUser: false,
      onLog: _log,
    );
    final HybridTtsPlayer questionHybridTts = HybridTtsPlayer(
      apiKey: _openAiKey,
      voice: 'nova',
      onLog: _log,
    );
    _ttsQueueManager.setUserTurn(false);
    _ttsQueueManager.setAiPaused(false);

    String aiText = "";
    String aiOriginal = "";
    String aiBuffer = "";
    bool hasDoubleNewline = false;

    await for (final chunk in aiStream) {
      if (!hasDoubleNewline) {
        aiText += chunk;
        aiBuffer += chunk;
        if (aiText.contains('\n\n')) {
          hasDoubleNewline = true;
          final sepIdx = aiText.indexOf('\n\n');
          final afterSep = aiText.substring(sepIdx + 2);
          aiText = aiText.substring(0, sepIdx);
          final bufSepIdx = aiBuffer.indexOf('\n\n');
          if (bufSepIdx >= 0) aiBuffer = aiBuffer.substring(0, bufSepIdx);
          if (afterSep.isNotEmpty) aiOriginal += afterSep;
        } else {
          if (!questionHybridTts.firstChunkFired) {
            final cutIdx =
                questionHybridTts.onChunk(aiBuffer, questionTts, _swTTS);
            if (cutIdx >= 0) aiBuffer = aiBuffer.substring(cutIdx);
          }
        }
      } else {
        aiOriginal += chunk; // Part2 (ëª¨êµ­?? ??TTS ê¸ˆì?
      }
      if (mounted && aiIdx < _localMessages.length) {
        setState(() {
          _localMessages[aiIdx]['target'] = aiText;
          _localMessages[aiIdx]['original'] = aiOriginal;
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
    _revealForReading(aiIdx, aiText.trim()); // ?†• ê¸??€???”ë ˆ?„ë¡¬?„í„°

    int ticks = 0;
    while (questionTts.pendingRequests > 0 || _ttsQueueManager.isBusy) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (++ticks > 300) break;
    }

    if (mounted && aiIdx < _localMessages.length) {
      setState(() {
        _localMessages[aiIdx]['original'] = aiOriginal;
      });
    }
  }

  // ?©ì„± ë¬¸ì¥ ?ˆë‚´ ë§í’? ì„ ?œì‹œ ??3ì´????ë™ ?¨ê?
  void _showSeedHintBalloon() {
    if (!mounted) return;
    setState(() => _showSeedHint = true);
    _seedHintTimer?.cancel();
    _seedHintTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showSeedHint = false);
    });
  }

  /// ?¸ì…˜ ?œì‘: ?ˆë‚´ë¬?TTSë§??¬ìƒ?˜ê³  ? ì? ê¸°ë³¸ ë¬¸ì¥(seed) ?€ê¸?  Future<void> _startSessionWaitingForUserSeed() async {
    if (_openAiKey.isEmpty || !mounted) return;
    if (_isSessionComplete) return;
    _resetIdleTimer();
    _isConversationActive = true;
    if (mounted) setState(() {});

    _ttsQueueManager.setUserTurn(false);
    _ttsQueueManager.setAiPaused(false);

    // ?†• FreeTalk?€ Roleplayë¥??…ë¦½?ìœ¼ë¡?fetch (?í˜¸ ?˜ì¡´ ?œê±°)
    final List<String> ftSnippets = await _fetchFreeTalkUserSnippets();
    final List<String> rpSnippets = await _fetchRoleplayUserSnippets();

    // [SEED ë¡œê·¸]
    _log('[SEED-FT]',
        'count=${ftSnippets.length}, picked=${ftSnippets.join(" | ")}');
    _log('[SEED-RP]',
        'count=${rpSnippets.length}, picked=${rpSnippets.join(" | ")}');
    final String _seedSource = ftSnippets.isNotEmpty && rpSnippets.isNotEmpty
        ? 'freeTalk+roleplay'
        : ftSnippets.isNotEmpty
            ? 'freeTalkOnly'
            : rpSnippets.isNotEmpty
                ? 'roleplayOnly'
                : 'fallback';
    _log('[SEED-MIX]',
        'ft=${ftSnippets.length}, rp=${rpSnippets.length}, source=$_seedSource');

    if ((ftSnippets.isNotEmpty || rpSnippets.isNotEmpty) &&
        mounted &&
        _isConversationActive) {
      // ?ˆìŠ¤? ë¦¬ ê¸°ë°˜ ì²?ì§ˆë¬¸ ??"ê¸°ë³¸ ë¬¸ì¥ ë§í•˜?¸ìš”" ?ˆë‚´ ?ëµ
      await _generateAndPlayFreeTalkSeedQuestion(ftSnippets, rpSnippets);
    } else {
      // ê¸°ì¡´: ê³ ì • ?ˆë‚´ TTS
      final ChunkedTtsFetcher tts = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        'nova',
        isUser: false,
        onLog: _log,
      );
      tts.addText('?€?”í•˜ë©´ì„œ ë¬¸ì¥???˜ë ¤ê°€ê³??¶ì? ê¸°ë³¸ ë¬¸ì¥???˜ë‚˜ ?œì•ˆ??ì£¼ì„¸??');
      int ticks = 0;
      while ((tts.pendingRequests > 0 || _ttsQueueManager.isBusy) && mounted) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (++ticks > 200) break;
      }
    }

    // ?ˆë‚´/ì§ˆë¬¸ ?„ë£Œ  STT ì¦‰ì‹œ ?œì‘ (? ì? ê¸°ë³¸ ë¬¸ì¥ ?€ê¸?
    // ?”§ [MIC-INSTANT] 8ì´??œë ˆ???œê±°  AI ë§??ë‚˜?ë§ˆ??ë§ˆì´??ON.
    // ì¹¨ë¬µ ??ë³„ë„ ?ˆë‚´ ë©˜íŠ¸ ?†ì´ ê·¸ë?ë¡??€ê¸?ì¹¨ë¬µ ?´ë°± ?œê±°).
    _showSeedHintBalloon();
    if (mounted && _isConversationActive && !_isSessionComplete) {
      _startDeepgramListening();
    }
  }

  // ====================================================================
  // ?“¦ [Box 4: ì£¼ì œ ê´€ë¦?(5???¬ì´??+ ??ì£¼ì œ ë²„íŠ¼)]
  // ====================================================================
  // ?’¡ ë§??´ë§ˆ??Firestore???€?¥ë˜ë¯€ë¡?_saveTurnToFirestore arrayUnion)
  //    ë³„ë„??"?€????ë¦¬ì…‹" ë¡œì§ ë¶ˆí•„??????ì£¼ì œ ë²„íŠ¼?€ UI ë¦¬ì…‹ë§??˜í–‰
  //    ?? ?„ì„±??ë¬¸ì¥???†ìœ¼ë©?? ì??ê²Œ ?ˆë‚´ ?¤ì´?¼ë¡œê·??œì‹œ

  /// ??ì£¼ì œ ?œì‘ ë²„íŠ¼ ?¸ë“¤??  /// - ?´ë? 5???„ë£Œ ??ì¦‰ì‹œ ë¦¬ì…‹
  /// - ì§„í–‰ ì¤??€???ˆìŒ ??ë§????€?¥ë?Œì„ ?Œë¦¬ê³?ê³„ì†/ë¦¬ì…‹ ? íƒ
  /// - ?€???„í? ?†ìŒ ??"?€?¥í•  ?´ìš© ?†ìŒ" ?ˆë‚´ ??ë¦¬ì…‹
  void _showNewTopicDialog() {
    final hasUserTurn = _localMessages.any((m) => m['role'] == 'HOST');

    // ?”§ 5???„ë£Œ ?íƒœë©??´ë? ëª¨ë‘ ?€?¥ëœ ?íƒœ ??ì¦‰ì‹œ ë¦¬ì…‹ ??? ì? ê¸°ë³¸ ë¬¸ì¥ ?€ê¸?    if (_isSessionComplete) {
      _resetSession();
      _startSessionWaitingForUserSeed();
      return;
    }

    // ?”§ ?€???„í? ?†ìŒ ???ˆë‚´ ?¤ì´?¼ë¡œê·?    if (!hasUserTurn) {
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
                  "?„ì„±??ë¬¸ì¥???†ìœ¼ë¯€ë¡??€?¥í•˜ì§€ ?ŠìŠµ?ˆë‹¤.",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  "?´ë–»ê²?? ê¹Œ??",
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
                        child: const Text("ê³„ì† ì§„í–‰",
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
                          _startSessionWaitingForUserSeed();
                        },
                        child: const Text("ë¦¬ì…‹",
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

    // ?”§ ì§„í–‰ ì¤??€???ˆìŒ ??ë§????€?¥ë?Œì„ ?Œë¦¬ê³?ë¦¬ì…‹ ?•ì¸
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
                "?„ì¬ê¹Œì???ì§„í–‰?€ ?ë™ ?€?¥ë˜?ˆìŠµ?ˆë‹¤.",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "??ì£¼ì œë¡??œì‘? ê¹Œ??",
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
                      child: const Text("ì·¨ì†Œ",
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
                        _startSessionWaitingForUserSeed();
                      },
                      child: const Text("??ì£¼ì œ",
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

  /// ?¸ì…˜ UI ë¦¬ì…‹ (Firestore ?€?¥ì? ?´ë? ë§????„ë£Œ??
  void _resetSession() {
    _stopEverything();
    _seedHintTimer?.cancel();
    if (mounted) {
      setState(() {
        _showSeedHint = false;
        _localMessages.clear();
        _turnCounter = 0;
        _sessionDocId = null;
        _myHistoryRef = null; // ?”§ [?ˆìŠ¤? ë¦¬] ??ë°??ì„± ì¤€ë¹?        _isSessionComplete = false;
        _isPolishing = false;
        _polishedSentence = "";
        _showPolishButton = false;
        _debugResult = "?±ï¸ ?€ê¸?ì¤?;
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
      });
      _practiceRecognizedWords.clear();
    }
  }

  /// "Suggest New Sentence" ë²„íŠ¼ ??polish ê²°ê³¼ë¥??ˆìŠ¤? ë¦¬???€????ë£¨í”„ ?¬ì‹œ??  void _suggestNewSentence() {
    if (_polishedSentence.isNotEmpty) {
      _history.add(_polishedSentence);
    }
    _stopEverything();
    if (mounted) {
      setState(() {
        _localMessages.clear();
        _turnCounter = 0;
        _sessionDocId = null;
        _myHistoryRef = null; // ?”§ [?ˆìŠ¤? ë¦¬] ??ë°??ì„± ì¤€ë¹?        _isSessionComplete = false;
        _isPolishing = false;
        _polishedSentence = "";
        _showPolishButton = false;
        _debugResult = "?±ï¸ ?€ê¸?ì¤?;
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
      });
    }
    _practiceRecognizedWords.clear();
    _startSessionWaitingForUserSeed(); // ?œì‘ ?ˆë‚´ ??? ì? seed ë¬¸ì¥ ?€ê¸?  }

  // ====================================================================
  // ?“¦ [Box 4-B: ?¸ë ¨??ë³€??ë¬¸ì¥ ?ì„± (Polish My Sentence)]
  // ====================================================================
  // ?Œ± 5???„ë£Œ ??ìµœì¢… ?±ì¥ ë¬¸ì¥??"?¤í”¼?¹ìš© ?¬ìš´ ê³ ê¸‰" ë¬¸ì¥?¼ë¡œ ë³€??  //    ???¤ì´?¼ë¡œê·¸ë¡œ ê²°ê³¼ ?œì‹œ
  Future<void> _polishSentence() async {
    if (_isPolishing || _openAiKey.isEmpty) return;

    // ë§ˆì?ë§?HOST ë©”ì‹œì§€??Part2(?•ì¥ ë¬¸ì¥) ì¶”ì¶œ
    String? finalExpanded;
    for (int i = _localMessages.length - 1; i >= 0; i--) {
      if (_localMessages[i]['role'] == 'HOST') {
        final target = (_localMessages[i]['target'] ?? '').toString();
        if (target.contains('\n\n')) {
          // [v3.6] Part2 ?„ì²´ ì¶”ì¶œ (sublist(1) ?©ì¹˜ê¸?
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

        // Firestore ?¸ì…˜ ë¬¸ì„œ??refined_sentence ?„ë“œ ì¶”ê?
        _savePolishedToFirestore(polished);
      }
    } catch (e) {
      print("??polish error: $e");
      if (mounted) setState(() => _isPolishing = false);
    }
  }

  /// ?¸ë ¨??ë³€???¤ì´?¼ë¡œê·?  void _showPolishDialog(String original, String polished) {
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
              const Text("?Œ± Your sentence:",
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 4),
              SelectableText(original,
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 16),
              const Text("??Polished:",
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
                      const Text("?«ê¸°", style: TextStyle(color: Colors.white70)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Polished ë¬¸ì¥??Firestore???€??  /// ?”§ [PRACTICE-FIX] _sessionDocIdê°€ null?´ì–´??_myHistoryRef???´ì•„?ˆì„ ???ˆìŒ.
  ///                  ê°€?œë? ë¶„ë¦¬?˜ì—¬ chat_history ?€?¥ë§Œ?´ë¼??ì§„í–‰?˜ë„ë¡?ë³´ì¥.
  ///                  + has_practice: true ?Œë˜ê·¸ë? ?™ì‹œ??ë°•ì•„ Practice ì§„ì… ?¸ë¦¬ê±°ë¡œ ?¬ìš©.
  Future<void> _savePolishedToFirestore(String polished) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      // 1. sessions ë¬¸ì„œ??refined_sentence ?€??(sessionDocIdê°€ ?ˆì„ ?Œë§Œ)
      if (_sessionDocId != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('sessions')
            .doc(_sessionDocId)
            .update({'refined_sentence': polished});
        _log('?’¾ [POLISH]', 'refined_sentence ?€???„ë£Œ');
      }
      // 2. chat_history ë°?ë¬¸ì„œ??polished_sentence + has_practice ?€??      //    (_sessionDocId ?¬ë??€ ë¬´ê??˜ê²Œ _myHistoryRefê°€ ?ˆìœ¼ë©???ƒ ?€??
      if (_myHistoryRef != null) {
        await _myHistoryRef!.update({
          'polished_sentence': polished,
          'has_practice': true,
        });
        _log('?’¾ [POLISH-HIST]',
            'chat_history polished_sentence + has_practice ?€???„ë£Œ');
      }
    } catch (e) {
      _log('??[POLISH-ERR]', '?€???¤íŒ¨: $e');
    }
  }

  // ====================================================================
  // ?“¦ [Box 4-C: inline Polish ??5???„ë£Œ ???ë™ ?¸ì¶œ, ì±„íŒ…ëª©ë¡???¸ë¼???œì‹œ]
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
      _log('??[POLISH-INLINE]', 'error: $e');
      if (mounted) setState(() => _isPolishing = false);
    }
  }

  // ====================================================================
  // ?“¦ [Box 4-C2: 5???„ë£Œ ?ë™ ?Œë¡œ?????•ì¥ë¬¸ì¥ ??… ???´ë¦¬???ì„± ????… ???ˆë‚´]
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
      // Polished ì¹´ë“œ ?ë‹¨(?¤ë”)??ë¨¼ì? ë³´ì—¬ì£¼ê³  TTS ?°ë¼ ?ì—°?¤ëŸ½ê²??´ë ¤ê°?      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_polishedCardKey.currentContext != null) {
          Scrollable.ensureVisible(
            _polishedCardKey.currentContext!,
            alignment: 0.0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
          );
        }
      });
      // Polished ë¬¸ì¥ ??ë²???…
      if (polished.isNotEmpty) await _practiceSpeakText(polished, 'nova');
    } catch (e) {
      _log('??[AUTO-POLISH]', 'error: $e');
      if (mounted) setState(() => _isPolishing = false);
    }
  }

// ====================================================================
// ?“¦ [Box 4-D: Practice Mode ???˜ë??¨ìœ„ ë°˜ë³µ ?°ìŠµ]
// ====================================================================
// ?¯ polished ë¬¸ì¥ ???˜ë??¨ìœ„ ë¶„í•´ ??AI ??… ??? ì? ?°ë¼ ë§í•˜ê¸????ë™ ì§„í–‰
//    ?„ë£Œ ?? AI/? ì? ?„ì²´ ?£ê¸°(?í˜¸ ë°°í??? + ?¤ìŒ ?¸ë ¨??ë¬¸ì¥ ë²„íŠ¼

  /// Practice ëª¨ë“œ ì§„ì… ??polishedSentenceë¥??¼í‘œ(,) ?¨ìœ„ë¡?ë¶„í•´ ???œì‘
  Future<void> _enterPracticeMode() async {
    if (_polishedSentence.isEmpty) return;
    _stopEverything();

    // ?¼í‘œ(,)ë¡??˜ë??¨ìœ„ ë¶„ë¦¬, ë§ˆì?ë§??¨ìœ„ ?œì™¸ ?¼í‘œ ë³µì›
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

  /// ?„ì¬ ?˜ë??¨ìœ„ AI ??… ??? ì? ?°ë¼ ë§í•˜ê¸?ê°ì?
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
    _practiceRecognizedWords.clear();
    _startPracticeListening();
  }

  /// ? ì? ?°ë¼ ë§í•˜ê¸?STT ?œì‘ (target ?¸ì–´ë¡??¸ì‹)
  /// [PRACTICE-RATIO] Advance when recognized words cover 60% of the unit.
  void _checkPracticeWordRatio(String transcript) {
    if (!_isPracticeUserListening || _currentUnitIdx >= _practiceUnits.length) {
      return;
    }
    final incomingWords = transcript
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    _practiceRecognizedWords.addAll(incomingWords);

    final unitText = _practiceUnits[_currentUnitIdx];
    final unitWords = unitText
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toSet();
    if (unitWords.isEmpty) {
      _practiceAdvanceUnit();
      return;
    }
    final matchCount =
        unitWords.where((w) => _practiceRecognizedWords.contains(w)).length;
    if (matchCount / unitWords.length >= 0.6) {
      _practiceAdvanceUnit();
    }
  }

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
      onTranscriptUpdate: (transcript) {
        BillingTicker.instance.resumeFromActivity('step_expand_practice_stt');
        _checkPracticeWordRatio(transcript);
      },
      onTurnEnded: (transcript) {
        BillingTicker.instance.resumeFromActivity('step_expand_practice_stt');
        _checkPracticeWordRatio(transcript);
      },
      onError: (_) => _practiceAdvanceUnit(),
      onAudioData: (bytes) => _userPcmAccumulator.addAll(bytes),
    );
    _voiceManager!.connectAndStart();
    BillingTicker.instance.resumeFromActivity('step_expand_practice_start');
  }

  /// ?¹ì • ?˜ë??¨ìœ„ë¡??í”„ (?˜ë??¨ìœ„ ?????¸ì¶œ)
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

  /// ?¤ìŒ ?˜ë??¨ìœ„ë¡??ë™ ì§„í–‰
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

  /// TTS ??… (?…ë¦½ AudioPlayer ???„ë£Œ ?€ê¸???ë°˜í™˜)
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
      _log('??[PRACTICE-SPEAK]', '$e');
    }
  }

  /// AI ?„ì²´ ë¬¸ì¥ ?£ê¸° (?í˜¸ ë°°í?????? ì? ?¬ìƒ ì¤‘ì´ë©?ë¹„í™œ??
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

  /// ? ì? ?„ì²´ ë¬¸ì¥ ?£ê¸° (?¹ìŒ ?Œì¼ ?¬ìƒ, ?í˜¸ ë°°í???
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
      _log('??[USER-PLAY]', '$e');
    }
    if (mounted) setState(() => _isUserFullPlaying = false);
  }

  /// ?¤ìŒ ?¸ë ¨??ë¬¸ì¥ ?„ë™?°ìŠ¤ë¡??´ë™
  void _nextSentencePractice() {
    _practicePlayer.stop();
    _suggestNewSentence();
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

  // ?„ì¬ ? ì? ?•ì¥ ë¬¸ì¥???”ë©´ ?ë‹¨??ê³ ì •??ì²˜ìŒë¶€??ë³´ì´ê²?? ì?.
  void _scrollToCurrentTop(int index) {
    // [SCROLL-THROTTLE] Streaming GPT chunks can request the same 220ms scroll
    // animation repeatedly. Let new bubble indexes through immediately, but
    // suppress repeated calls for the same index inside 150ms.
    final now = DateTime.now();
    if (_lastScrollTopIndex == index &&
        _lastScrollTopAt != null &&
        now.difference(_lastScrollTopAt!).inMilliseconds < 150) {
      return;
    }
    _lastScrollTopAt = now;
    _lastScrollTopIndex = index;
    _log('?§­ [SCROLL-TOP]', 'index=$index');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final key = _itemKeys[index];
      if (key == null) return;
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.98,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  // ?†• ê¸??€???”ë ˆ?„ë¡¬?„í„°: ?”ë©´ë³´ë‹¤ ê¸¸ë©´ ì²?ì¤„ì„ ?ë‹¨??ê³ ì •????
  //    ?½ëŠ” ?œê°„(ì¶”ì •) ?™ì•ˆ ?œì„œ??ë§??„ë˜(?ì¤„)ë¡?? í˜• ê¸€?¼ì´??
  //    ?”ë©´?????¤ì–´?¤ë©´ ê¸°ì¡´ ì¹´í†¡??_scrollToBottom) ? ì?.
  void _revealForReading(int index, String spokenText) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final ctx = _itemKeys[index]?.currentContext;
      if (ctx == null) {
        _scrollToBottom();
        return;
      }
      final renderObj = ctx.findRenderObject();
      final double itemH = (renderObj is RenderBox) ? renderObj.size.height : 0;
      final double viewH = _scrollController.position.viewportDimension;
      // ?”ë©´?????¤ì–´?¤ë©´ ê¸°ì¡´ ?™ì‘
      if (itemH <= 0 || itemH <= viewH * 0.85) {
        _scrollToBottom();
        return;
      }
      // 1) ì²?ì¤„ì„ ?”ë©´ ?ë‹¨??ê³ ì • (ì¦‰ì‹œ)
      Scrollable.ensureVisible(ctx, alignment: 0.98, duration: Duration.zero);
      // 2) ?½ëŠ” ?œê°„ ?™ì•ˆ ?ì¤„ê¹Œì? ? í˜• ê¸€?¼ì´??      //    (reverse ë¦¬ìŠ¤?¸ì—??offset 0 = ë§??„ë˜)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          0,
          duration: Duration(milliseconds: _estimateReadMs(spokenText)),
          curve: Curves.linear,
        );
      });
    });
  }

  // ?½ëŠ” ?œê°„ ì¶”ì • (OpenAI TTS-1 ?ì–´ ??14??ì´?. ?´ì§ ì§§ê²Œ ?¡ì•„ ?ì¤„???½ê°„ ë¨¼ì? ?„ì°©.
  // ê¸€?¼ì´?œê? ?ˆë¬´ ë¹ ë¥´ë©?ê°’ì„ ??¶”ê³? ?ˆë¬´ ?ë¦¬ë©?ê°’ì„ ?¬ë¦°??
  static const double _kReadCharsPerSec = 14.0;
  int _estimateReadMs(String text) {
    final int n = text.trim().length;
    if (n <= 0) return 1500;
    final int ms = (n / _kReadCharsPerSec * 1000).round();
    return ms.clamp(1500, 25000);
  }

  void _stopEverything() {
    _isConversationActive = false;
    _commitTimer?.cancel();
    _commitTimer = null;
    _pendingTranscript = '';
    _voiceManager?.dispose();
    _voiceManager = null;
    _ttsQueueManager.setAiPaused(false); // ?”§ [v3.6] TTS ?€ê¸??Œë˜ê·?ì´ˆê¸°??    _ttsQueueManager.setUserTurn(false);
    _ttsQueueManager.stop();
    _practicePlayer.stop();
    if (mounted) setState(() {});
  }

  Future<void> _startDeepgramListening() async {
    if (_deepgramKey.isEmpty || !(await _audioRecorder.hasPermission())) return;
    // ?Œ± 5???„ë£Œ ??ë§ˆì´??? ê? (? ì?ê°€ "??ì£¼ì œ" ë²„íŠ¼ ?ŒëŸ¬??ë¦¬ì…‹??
    if (_isSessionComplete) return;
    _resetIdleTimer();
    _isConversationActive = true;
    if (mounted) {
      setState(() {
        _debugResult = "?±ï¸ ?£ëŠ” ì¤?..";
      });
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
        BillingTicker.instance.resumeFromActivity('step_expand_stt_partial');
        _swDeepgram.reset();
        _swDeepgram.start();
      },
      onTurnEnded: (transcript) {
        _log('?? [LISTEN-03]', 'onTurnEnded ì½œë°± ?˜ì‹ : "$transcript"');
        BillingTicker.instance.resumeFromActivity('step_expand_stt_result');
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
    BillingTicker.instance.resumeFromActivity('step_expand_mic_start');
    _log('?¤ [LISTEN-05]', 'connectAndStart ?„ë£Œ');
  }

  // ?”§ [v3.4] Deepgram speech_final ?˜ì‹  ???¸ì¶œ??  // 1.2ì´??€ê¸°ì°½ ?ˆì—??ì¶”ê? ë°œí™” ?©ì¹˜ê¸????„ì „???ë‚˜ë©??Œì´?„ë¼???œì‘
  void _stopMicAndProcess(String transcript) async {
    _resetIdleTimer();
    final clean = transcript.trim();
    _log('?? [STOP-01]', 'speech_final ?˜ì‹ : "$clean" (len=${clean.length})');

    if (clean.length < 2) {
      _log('?? [STOP-02]', '?ˆë¬´ ì§§ìŒ ??"Please say that again." TTS ???€ê¸?);
      await _voiceManager?.dispose();
      _voiceManager = null;
      _ttsQueueManager.setUserTurn(false);
      _ttsQueueManager.setAiPaused(false);
      final retryTts = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        'nova',
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

    // ?”§ ê¸°ì¡´ ?€ê¸?ì¤‘ì¸ ë°œí™”ê°€ ?ˆìœ¼ë©?ê³µë°±?¼ë¡œ ?°ê²° (?”ë“¬ê±°ë¦¼ ?©ì¹˜ê¸?
    if (_pendingTranscript.isEmpty) {
      _pendingTranscript = clean;
      _log('?? [STOP-03]', '? ê·œ ë°œí™” ?‘ìˆ˜. 1.2ì´??€ê¸°ì°½ ?œì‘');
    } else {
      _pendingTranscript = '$_pendingTranscript $clean';
      _log('?? [STOP-04]', '?©ì¹˜ê¸? "$_pendingTranscript" (1.2ì´??€ê¸°ì°½ ë¦¬ì…‹)');
    }

    // UI: ?‘ìˆ˜??ë°œí™”ë¥?HOST_TEMP ?ì„ ???¤ì‹œê°?ë°˜ì˜
    if (mounted) {
      setState(() {
        _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
        _localMessages.add({
          'role': 'HOST_TEMP',
          'target': '...',
          'original': '...', // Deepgram ?ë¬¸ ?¨ê¸°ê¸?          'type': 'user_input',
        });
      });
    }

    // ê¸°ì¡´ ?€?´ë¨¸ ì·¨ì†Œ (??ë°œí™”ê°€ ?”ìœ¼ë¯€ë¡??€ê¸°ì°½ ë¦¬ì…‹)
    _commitTimer?.cancel();

    // 1.2ì´????Œì´?„ë¼???œì‘ ?ˆì•½
    _commitTimer = Timer(
      const Duration(milliseconds: COMMIT_WAIT_MS),
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

    // ë§ˆì´??VoiceManager ?•ë¦¬
    await _voiceManager?.dispose();
    _voiceManager = null;
    _log('?? [COMMIT-02]', 'VoiceManager dispose ?„ë£Œ');

    _log('?? [COMMIT-03]', '_processRelayPipeline ?¸ì¶œ');
    _processRelayPipeline(committed);
  }

// ====================================================================
// ?“¦ [Box 5-RETRY: ?¬ì§ˆë¬?ì²˜ë¦¬]
// ====================================================================
  Future<void> _handleRetryQuestion(String contextStr, String targetLangName,
      {bool isDifferent = false,
      bool isMisheard = false,
      bool silentReplace = false,
      String rejectedQuestion = ''}) async {
    _log(
        '?”„ [RETRY]',
        isMisheard
            ? '?¤ì²­ì·??¬ì§ˆë¬?ëª¨ë“œ ì§„ì…'
            : (isDifferent
                ? (silentReplace ? 'ë¶ˆë§Œ ê°ì? ??ì¡°ìš©??ì§ˆë¬¸ êµì²´' : '?¤ë¥¸ ì§ˆë¬¸ ëª¨ë“œ ì§„ì…')
                : '?¬ì§ˆë¬?ëª¨ë“œ ì§„ì…'));
    _ttsQueueManager.setUserTurn(false);
    _ttsQueueManager.setAiPaused(false);

    // ?ˆë‚´ ë©˜íŠ¸ TTS ??silentReplace ëª¨ë“œ?´ë©´ ?„ì „??ê±´ë„ˆ?€
    ChunkedTtsFetcher? phraseTts;
    if (!silentReplace) {
      phraseTts = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        'nova',
        isUser: false,
        onLog: _log,
      );
      phraseTts.addText(isMisheard
          ? "???œê? ?˜ëª» ?¤ì—ˆ?´ìš”. ?¤ì‹œ ì§ˆë¬¸? ê²Œ??"
          : (isDifferent ? "ê·¸ëŸ¼ ?¤ë¥¸ ì§ˆë¬¸ ?œë¦´ê²Œìš”." : "?¤ì‹œ ì§ˆë¬¸? ê²Œ??"));
    }

    // ??AI ì§ˆë¬¸ ë²„ë¸”
    if (mounted) {
      setState(() {
        // ë°©ê¸ˆ ??ì§ˆë¬¸ ?˜ë‚˜ë§??œê±° ???´ì „ ?€???ë¦„?€ ? ì?
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
      userId: FirebaseAuth.instance.currentUser?.uid ?? '',
      isRetry: !isDifferent && !isMisheard,
      isDifferent: isDifferent,
      rejectedQuestion: rejectedQuestion,
    );

    final questionTts = ChunkedTtsFetcher(
      _openAiKey,
      _ttsQueueManager,
      'nova',
      isUser: false,
      onLog: _log,
    );
    final HybridTtsPlayer questionHybridTts = HybridTtsPlayer(
      apiKey: _openAiKey,
      voice: 'nova',
      onLog: _log,
    );
    String aiText = "";
    String aiOriginalRetry = "";
    String aiBuffer = "";
    bool aiRetryHasDoubleNewline = false;

    // _swTTS..reset()..start();
    _swTTS
      ..reset()
      ..start(); // ?¬ì§ˆë¬?ê²½ë¡œ??ë°œì‚¬ msë¥??ˆë¡œ ì¸¡ì •?œë‹¤.

    await for (final chunk in aiStream) {
      if (!aiRetryHasDoubleNewline) {
        // Part1 (?ì–´)
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
          // ?˜ì´ë¸Œë¦¬?? 4?¨ì–´/êµ¬ë‘???„ë‹¬ ??ì²?ì²?¬ ë°œì‚¬
          if (!questionHybridTts.firstChunkFired) {
            final cutIdx =
                questionHybridTts.onChunk(aiBuffer, questionTts, _swTTS);
            if (cutIdx >= 0) aiBuffer = aiBuffer.substring(cutIdx);
          }
        }
      } else {
        // Part2 (?œêµ­?? ??TTS ê¸ˆì?
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
    _revealForReading(aiIdx, aiText.trim()); // ?†• ê¸??€???”ë ˆ?„ë¡¬?„í„°

    // TTS ?¬ìƒ ?„ë£Œ ?€ê¸?    int ticks = 0;
    while ((phraseTts?.pendingRequests ?? 0) > 0 ||
        questionTts.pendingRequests > 0 ||
        _ttsQueueManager.isBusy) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (++ticks > 300) break;
    }

    if (_isConversationActive) _startDeepgramListening();
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
//   STEP 7: ë§ˆì´???¬ê°œë°?// ====================================================================
  /// Build clean HOST/SYSTEM context for normal, fast-lane, dissatisfied, and misheard paths.
  Map<String, String> _buildCleanContext({
    bool removeLastSystem = false,
    bool captureRejected = false,
    int maxMessages = 0,
  }) {
    var msgs = _localMessages.where((m) {
      if (m['role'] != 'HOST' && m['role'] != 'SYSTEM') return false;
      final target = (m['target'] ?? '').toString().trim();
      return target.isNotEmpty && target != '...';
    }).toList();

    if (maxMessages > 0 && msgs.length > maxMessages) {
      msgs = msgs.sublist(msgs.length - maxMessages);
    }

    String rejected = '';
    if (removeLastSystem) {
      final sysIdx = msgs.lastIndexWhere((m) => m['role'] == 'SYSTEM');
      if (sysIdx != -1) {
        if (captureRejected) {
          rejected = (msgs[sysIdx]['target'] ?? '').toString().trim();
        }
        msgs.removeAt(sysIdx);
      }
    }

    final List<String> lines = [];
    String latestExp = '';
    for (final m in msgs) {
      final t = (m['target'] ?? '').toString().trim();
      if (m['role'] == 'HOST') {
        final idx = t.indexOf('\n\n');
        final exp = idx < 0
            ? t
            : (t.substring(idx + 2).trim().isNotEmpty
                ? t.substring(idx + 2).trim()
                : t.substring(0, idx).trim());
        lines.add("User: $exp");
        latestExp = exp;
      } else {
        lines.add("AI: $t");
      }
    }

    String ctx = lines.join("\n");
    if (latestExp.isNotEmpty) {
      ctx += "\n\n[Most recent expanded sentence to grow from]: $latestExp";
    }

    return {
      'contextStr': ctx,
      'latestExpanded': latestExp,
      'rejectedQuestion': rejected,
    };
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
      if (_isConversationActive) _startDeepgramListening();
      return;
    }

    // [CLARIFY-EVAPORATE] If the latest SYSTEM bubble is a pronunciation clarify
    // prompt marked with 'clarify': true and this is a real user utterance, remove it
    // before building the next context.
    if (mounted) {
      final lastSysIdx =
          _localMessages.lastIndexWhere((m) => m['role'] == 'SYSTEM');
      if (lastSysIdx != -1 && _localMessages[lastSysIdx]['clarify'] == true) {
        setState(() => _localMessages.removeAt(lastSysIdx));
      }
    }

    // ?”§ [FAST-LANE] ë¡œì»¬ ì§ˆë¬¸ ë¶ˆë§Œ ?ì • ??streamUserTranslation ?¸ì¶œ ??ë¹ ë¥¸ ì²˜ë¦¬
    if (_isQuestionDissatisfactionRaw(finalTranscript)) {
      _log('?Ÿ  [FAST-DISSATISFIED]', 'ë¡œì»¬ fast-lane ê°ì?: "$finalTranscript"');
      _turnCounter--; // ë¶ˆë§Œ ë°œí™”???™ìŠµ ??ë¯¸ì ??      if (mounted) {
        setState(
            () => _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP'));
      }
      // Clean context: helper build
      final fclResult =
          _buildCleanContext(removeLastSystem: true, captureRejected: true);
      final String fclCtx = fclResult['contextStr']!;
      final String fclRejected = fclResult['rejectedQuestion']!;
      final String fclLang = FFAppState().targetLang.isNotEmpty
          ? FFAppState().targetLang
          : 'English';
      await _handleRetryQuestion(fclCtx, fclLang,
          isDifferent: true,
          silentReplace: true,
          rejectedQuestion: fclRejected);
      return;
    }

    try {
      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      // STEP 2: HOST ?ì„  ?ì„± + ? ì? ë²ˆì—­ ?¤íŠ¸ë¦¬ë°
      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      if (mounted) {
        setState(() {
          _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
          _localMessages.add({
            'role': 'HOST',
            'target': '',
            'original': '',
            'turnId': currentTurnId
          });
        });
        _scrollToBottom();
      }

      int hostIndex = _localMessages.length - 1;

      final pipeResult = _buildCleanContext(maxMessages: 10);
      String contextStr = pipeResult['contextStr']!;

      String userTargetText = "";
      String userBuffer = "";
      // User voice follows the lobby My Voice setting; AI remains fixed to nova.
      final String userVoice =
          FFAppState().aiVoice.isNotEmpty ? FFAppState().aiVoice : 'echo';
      ChunkedTtsFetcher userTtsFetcher = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        userVoice,
        onLog: _log,
      );
      final HybridTtsPlayer userHybridTts = HybridTtsPlayer(
        apiKey: _openAiKey,
        voice: userVoice,
        onLog: _log,
      );
      _ttsQueueManager.setUserTurn(true);
      _ttsQueueManager.setAiPaused(false); // ? ì? ì²?¬??ì¦‰ì‹œ ?¬ìƒ

      // ?Œ [v3.1] ë¡œë¹„?ì„œ ? ì?ê°€ ? íƒ???€ê²??¸ì–´ë¡?ë²ˆì—­
      final String targetLangName = FFAppState().targetLang.isNotEmpty
          ? FFAppState().targetLang
          : 'English';

      final userStream = StepExpandBrain.streamUserTranslation(
        apiKey: _openAiKey,
        textOriginal: finalTranscript,
        targetLang: targetLangName,
        contextStr: contextStr,
        disableCorrection: isCorrectionRetry,
      );

      // ?Œ± [StepExpand Part2ë§?TTS] ì²??´ì? ?¨ìˆœ ë²ˆì—­ (Part êµ¬ë¶„ ?†ìŒ)
      //    2????"Part1\n\nPart2" êµ¬ì¡° ??Part2ë§?TTSë¡??¬ìƒ
      //    \n\n ê°ì? ?„ê¹Œì§€??buffer???“ë˜ TTS????ë³´ëƒ„
      //    \n\n ê°ì? ??buffer ë¦¬ì…‹ ???´í›„ chunkë¶€??TTS (=Part2)
      bool evaporated = false;
      bool retried = false;
      bool corrected = false; // ? ì?ê°€ AI???¤í•´ë¥??•ì •?˜ëŠ” ê²½ìš° ??ì§ì „ HOST+SYSTEM ???? œ ???¬ì‹œ??      bool misheard = false; // ?˜ëª» ?¤ì—ˆ?¤ëŠ” ë¶ˆë§Œë§??ˆìŒ ??ì§ì „ êµí™˜ ?? œ ???¬ì§ˆë¬?      bool clarified = false; // ì£¼ì–´/ëª©ì ??ëª¨í˜¸ ??AI ?˜ë¬»ê¸?      bool restated = false; // ?¤í”„? í”½?´ì?ë§??¤í”¼???´ìš© ê·¸ë?ë¡??Œì„± ?•ì¸ ì§ˆë¬¸ ???¬ì²­ì·?      bool garbled = false; // ì§„ì§œ ë°œìŒ ë¶ˆí™•????"?¤ì‹œ ë§í•´ ì£¼ì„¸?? ?”ì²­
      bool dissatisfied = false; // [DISSATISFIED] ? ì?ê°€ AI ì§ˆë¬¸??ë¶ˆë§Œ ???•ì¸ ???¬ì§ˆë¬?      bool _part2Started = false; // \n\n ?´í›„ ì§„ì… ?¬ë?
      bool hasDoubleNewline = false; // 2?ŒíŠ¸ êµ¬ì¡° ?¬ë?
      bool firstChunkSent = false;

      await for (String chunk in userStream) {
        userTargetText += chunk;
        userBuffer += chunk;

        // ?”§ [v3.3] EVAPORATE ê°ì?
        if (userTargetText.contains("[EVAPORATE]")) {
          evaporated = true;
          _log('? ï¸ [EVAPORATE]', 'ì¦ë°œ ê°ì? ????ì·¨ì†Œ');
          break;
        }

        // ?¬ì§ˆë¬?ê°ì? (ë°œìŒ ë¶ˆëª…, ë¬¸ë§¥ ë¶ˆì¼ì¹???
        if (userTargetText.contains("[RETRY]")) {
          retried = true;
          _log('? ï¸ [RETRY]', '?¬ì§ˆë¬?ê°ì? ???¤ë¥¸ ì§ˆë¬¸ ?ì„±');
          break;
        }

        // [DISSATISFIED] ? ì?ê°€ AI ì§ˆë¬¸??ë¶ˆë§Œ ?œì‹œ
        if (userTargetText.contains("[DISSATISFIED]")) {
          dissatisfied = true;
          _log('?Ÿ  [DISSATISFIED]', 'ì§ˆë¬¸ ë¶ˆë§Œ ê°ì? ??ì¦‰ì‹œ ?¤ë¥¸ ì§ˆë¬¸ ?ì„±');
          break;
        }

        // ?•ì • ê°ì?: ? ì?ê°€ AI???¤í•´ë¥?ë°”ë¡œ?¡ëŠ” ê²½ìš°
        // ??ì§ì „ HOST(?¤í•´??? ì? ë°œí™”) + SYSTEM(?˜ëª»??AI ?‘ë‹µ) ?? œ ???•ì • ë°œí™”ë¡??¬ì‹œ??        if (!isCorrectionRetry && userTargetText.contains("[CORRECTION]")) {
          corrected = true;
          _log('?”„ [CORRECTION]', '?•ì • ê°ì? ??ì§ì „ HOST+SYSTEM ?? œ ???¬ì‹œ??);
          break;
        }

        // [MISHEARD] ?˜ëª» ?¤ì—ˆ?¤ëŠ” ë¶ˆë§Œë§??ˆìŒ ??ì§ì „ êµí™˜ ?? œ ???¬ì§ˆë¬?        if (!isCorrectionRetry && userTargetText.contains("[MISHEARD]")) {
          misheard = true;
          _log('?‘‚ [MISHEARD]', '?¤ì²­ì·?ë¶ˆë§Œ ê°ì? ??ì§ì „ êµí™˜ ?? œ ???¬ì§ˆë¬?);
          break;
        }

        // ?˜ë¬»ê¸?ê°ì?: ì£¼ì–´/ëª©ì ??ëª¨í˜¸ ??AI ?˜ë¬»ê¸?        if (!clarified && userTargetText.contains("[CLARIFY]")) {
          clarified = true;
          _log('??[CLARIFY]', '?˜ë¬»ê¸?ê°ì? ???¤íŠ¸ë¦??„ë£Œ ??ì²˜ë¦¬ ?ˆì •');
        }

        // ?¤ì‹œ ë§í•˜ê¸?ê°ì?: [RESTATE]=?¤í”„? í”½ / GARBLED=ì§„ì§œ ???¤ë¦¼
        // RESTATE??ê°„ë‹¨ ?ˆë‚´ ???¬ì²­ì·?ë¬¸ë§¥ ?•ì¸ ë£¨í”„ ?œê±°)
        if (userTargetText.contains("[RESTATE]")) {
          restated = true;
          _log('?” [RESTATE]', 'ë§¥ë½ ë¶ˆì¼ì¹???ê°„ë‹¨ ?ˆë‚´ ???¬ì²­ì·?);
          break;
        }
        if (userTargetText.contains("[GARBLED]")) {
          garbled = true;
          _log('?‘‚ [GARBLED]', 'ë°œìŒ ë¶ˆí™•?????¤ì‹œ ë§í•˜ê¸??”ì²­');
          break;
        }

        if (mounted && hostIndex < _localMessages.length) {
          setState(() => _localMessages[hostIndex]['target'] = userTargetText);
        }
        _scrollToCurrentTop(hostIndex);

        // ?Œ± \n\n ìµœì´ˆ ê°ì?: Part1 ë²„í¼ ?ê¸°, Part2ë§?TTS
        if (!hasDoubleNewline && userTargetText.contains('\n\n')) {
          // ì²???turn 1)?ì„  ?•ì¥ ?†ìŒ ??Part1ë§?onStreamEnd???„ë‹¬, Part2 ë¬´ì‹œ
          if (currentTurnId == 1) {
            final idx = userTargetText.indexOf('\n\n');
            userTargetText = userTargetText.substring(0, idx).trim();
            if (mounted && hostIndex < _localMessages.length)
              setState(
                  () => _localMessages[hostIndex]['target'] = userTargetText);
            userBuffer = userTargetText; // Part1ë§?onStreamEnd???„ë‹¬
            break;
          }
          hasDoubleNewline = true;
          _part2Started = true;
          final idx = userTargetText.indexOf('\n\n');
          userBuffer = userTargetText.substring(idx + 2);
          _log('?Œ± [PART2-START]', 'Part2 ê°ì? ??Part1 TTS ?¤í‚µ, Part2ë§???…');
          continue;
        }

        // Part1 ?ì—­: TTS ?ˆë? ë°œì‚¬ ????(?”ë©´ ?ë§‰ë§??ë¦„)
        if (!_part2Started) continue;

        // Part2 ?˜ì´ë¸Œë¦¬?? 4?¨ì–´/êµ¬ë‘???„ë‹¬ ??ì²?ì²?¬ë§?ë°œì‚¬
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
        _turnCounter--; // ?¤íŒ¨???´ì? ì¹´ìš´??ì·¨ì†Œ
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

      // [DISSATISFIED] ? ì?ê°€ ì§ˆë¬¸ ?´ìš©??ë¶ˆë§Œ ???ˆë‚´ ë©˜íŠ¸ ?†ì´ ì¦‰ì‹œ ?¤ë¥¸ ì§ˆë¬¸ ?ì„±
      if (dissatisfied) {
        _turnCounter--; // ë¶ˆë§Œ ë°œí™” ??ì¹´ìš´??ì·¨ì†Œ
        final dissResult =
            _buildCleanContext(removeLastSystem: true, captureRejected: true);
        final String dissCleanCtx = dissResult['contextStr']!;
        final String dissRejected = dissResult['rejectedQuestion']!;
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length) {
              _localMessages.removeAt(hostIndex);
            }
          });
        }
        await _handleRetryQuestion(dissCleanCtx, targetLangName,
            isDifferent: true,
            silentReplace: true,
            rejectedQuestion: dissRejected);
        return;
      }

      // ?”„ [CORRECTION] ? ì?ê°€ AI???¤í•´ë¥??•ì •
      // ì§ì „ HOST(?˜ëª» ?¸ì‹??? ì? ë°œí™”) + SYSTEM(?˜ëª»??AI ?‘ë‹µ)???¨ê»˜ ?? œ?˜ê³ 
      // ?•ì •??ë°œí™”(_finalTranscript)ë¡??´ë‹¹ ?´ì„ ì²˜ìŒë¶€???¤ì‹œ ì²˜ë¦¬
      if (corrected) {
        // ?´ì „ turn???†ìœ¼ë©?(1ë²ˆì§¸ ?´ì—???•ì • ë¶ˆê??? RETRYë¡??´ë°±
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
        _turnCounter -= 2; // ?„ì¬ ??+ ?´ì „ ?˜ëª»????ì¹´ìš´??ì·¨ì†Œ
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            // ë°©ê¸ˆ ?ì„±??ë¹?HOST ë²„ë¸” ?œê±°
            if (hostIndex < _localMessages.length) {
              _localMessages.removeAt(hostIndex);
            }
            // ?´ì „ SYSTEM(AI???˜ëª»???‘ë‹µ) ?œê±°
            final lastSysIdx =
                _localMessages.lastIndexWhere((m) => m['role'] == 'SYSTEM');
            if (lastSysIdx != -1) _localMessages.removeAt(lastSysIdx);
            // ?´ì „ HOST(?¤í•´??? ì? ë°œí™”) ?œê±°
            final lastHostIdx =
                _localMessages.lastIndexWhere((m) => m['role'] == 'HOST');
            if (lastHostIdx != -1) _localMessages.removeAt(lastHostIdx);
          });
          _scrollToBottom();
        }
        // ?•ì •??ë°œí™”ë¡??´ë‹¹ ???¬ì²˜ë¦?(?¬ì§„?…ì´ë¯€ë¡?[CORRECTION] ?¬ê°ì§€ ????
        await _deleteLastExchangeFromHistory();
        _processRelayPipeline(finalTranscript, isCorrectionRetry: true);
        return;
      }

      // ?‘‚ [MISHEARD] ? ì?ê°€ "?˜ëª» ?¤ì—ˆ????ë¶ˆë§Œë§?ë§í•¨ (?•ì • ?´ìš© ?†ìŒ)
      if (misheard) {
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
          await _handleRetryQuestion(contextStr, targetLangName,
              isMisheard: true);
          return;
        }
        _turnCounter -= 2; // ?„ì¬ ë¶ˆë§Œ ??+ ?´ì „ ?¤ì²­ì·???ì¹´ìš´??ì·¨ì†Œ
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length) {
              _localMessages.removeAt(hostIndex);
            }
            final lastHostIdx =
                _localMessages.lastIndexWhere((m) => m['role'] == 'HOST');
            if (lastHostIdx != -1) _localMessages.removeAt(lastHostIdx);
          });
          _scrollToBottom();
        }
        final mishResult =
            _buildCleanContext(removeLastSystem: true, maxMessages: 10);
        final String cleanContextStr = mishResult['contextStr']!;
        await _deleteLastExchangeFromHistory();
        await _handleRetryQuestion(cleanContextStr, targetLangName,
            isMisheard: true);
        return;
      }

      // ??[CLARIFY] ? ì? ë°œí™” ì£¼ì–´/ëª©ì ??ëª¨í˜¸ ??AI ?˜ë¬»ê¸?ë²„ë¸” + TTS + STT ?¬ì‹œ??      if (clarified) {
        _turnCounter--;
        final clarifyText =
            userTargetText.replaceFirst(RegExp(r'^\[CLARIFY\]\s*'), '');
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length)
              _localMessages.removeAt(hostIndex);
            _localMessages.add({
              'role': 'SYSTEM',
              'target': clarifyText,
              'original': '',
              'clarify': true, // Mark temporary clarify bubble for evaporation.
            });
          });
          _scrollToBottom();
        }
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

      // ?” RESTATE/GARBLED AI ì§ˆë¬¸?€ ê·¸ë?ë¡??ê³  ?¬ì²­ì·?      //   - GARBLED ì§„ì§œ ???¤ë¦¼ ??"?¤ì‹œ ë§í•´ ì£¼ì„¸?? (2???°ì†?´ë©´ ???¬ìš´ ë¬¸ì¥ ? ë„)
      //   - RESTATE ?¤í”„? í”½ ??"ì§ˆë¬¸??ë§ê²Œ ?¤ì‹œ ë§í•´ ì£¼ì„¸?? (ë¬¸ë§¥ ?•ì¸ ?†ì´ ?™ì¼ ?¨í„´)
      //   - ??ì¹´ìš´???ë³µ(?´ë²ˆ ?œë„ ë¬´íš¨ ???¤ìŒ ë°œí™”ê°€ ê°™ì? ?´ìœ¼ë¡??¬ì§„??
      //   - ë°©ê¸ˆ ë§Œë“  ë¹?HOST ë²„ë¸”ë§??œê±°. ?´ì „??ì¢‹ì? ë§¥ë½(SYSTEM ì§ˆë¬¸ ?¬í•¨)?€ ?ˆë? ?? œ ????      if (restated || garbled) {
        _turnCounter--;
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length) {
              _localMessages.removeAt(hostIndex);
            }
          });
          _scrollToBottom();
        }
        final int restateCount = ++_consecutiveRestateCount;
        String checkPhrase;
        if (restateCount >= 2) {
          checkPhrase = "ì¡°ê¸ˆ ??ì§§ê³  ?¬ìš´ ë¬¸ì¥?¼ë¡œ ë§í•´ ì£¼ì‹¤?˜ìš”?";
        } else if (restated) {
          checkPhrase = "ì§ˆë¬¸??ë§ê²Œ ?¤ì‹œ ë§í•´ ì£¼ì„¸??";
        } else {
          checkPhrase = "?????¤ë ¸?´ìš”. ?¤ì‹œ ë§í•´ ì£¼ì„¸??";
        }
        _ttsQueueManager.setUserTurn(false);
        _ttsQueueManager.setAiPaused(false);
        final restateTts = ChunkedTtsFetcher(
          _openAiKey,
          _ttsQueueManager,
          'nova',
          isUser: false,
          onLog: _log,
        );
        restateTts.addText(checkPhrase);
        int waitTicks = 0;
        while ((restateTts.pendingRequests > 0 || _ttsQueueManager.isBusy) &&
            mounted) {
          await Future.delayed(const Duration(milliseconds: 50));
          if (++waitTicks > 200) break;
        }
        // ê°™ì? AI ì§ˆë¬¸ ê·¸ë?ë¡?? ì? ??ì§ˆë¬¸ ?¬ìƒ???†ì´ STTë§??¬ì‹œ??        if (mounted && _isConversationActive) _startDeepgramListening();
        return;
      }

      // ???•ìƒ ë°œí™” ?µê³¼ ???°ì† GARBLED ì¹´ìš´??ì´ˆê¸°??      _consecutiveRestateCount = 0;

      // ?Œ± [E-2] ?˜ì´ë¸Œë¦¬?? remainder ë°œì‚¬ + ?µë¬¸??TtsCache ?€??      final String _part2FullSentence = hasDoubleNewline
          ? userTargetText.substring(userTargetText.indexOf('\n\n') + 2).trim()
          : userTargetText.trim();
      await userHybridTts.onStreamEnd(
        fullSentence: _part2FullSentence,
        remainderBuffer: userBuffer,
        fetcher: userTtsFetcher,
        swSpeechEnd: _swTTS,
      );
      _revealForReading(hostIndex, _part2FullSentence); // ?†• ê¸??€???”ë ˆ?„ë¡¬?„í„°

      // ?Œ± ? ì? original(?œêµ­?? ??²ˆ??      // 1?? ?„ì²´ ë¬¸ì¥ ??²ˆ?????€?”ë°© ?œì‹œ + Firestore ?€??      // 2??: Part1\n\nPart2 ?„ì²´ë¥???²ˆ?????€?”ë°©?ì„œ??Part2 ?œêµ­?´ë§Œ ?œì‹œ, Firestore?ëŠ” ?„ì²´ ?€??      Future<String>? userOrigFuture;
      if (currentTurnId == 1) {
        userOrigFuture = StepExpandBrain.generateCleanOriginal(
            apiKey: _openAiKey, englishText: userTargetText);
        userOrigFuture.then((cleanKorean) {
          if (mounted && _localMessages.length > hostIndex) {
            setState(() => _localMessages[hostIndex]['original'] = cleanKorean);
          }
        });
      } else if (hasDoubleNewline) {
        // 2??: Part1(ì§§ì? ?€??ë§???²ˆ?????•ì¥ë¬¸ì¥(Part2)?€ ?œêµ­??ë¶ˆí•„??        final part1English =
            userTargetText.substring(0, userTargetText.indexOf('\n\n')).trim();
        if (part1English.isNotEmpty) {
          userOrigFuture = StepExpandBrain.generateCleanOriginal(
              apiKey: _openAiKey, englishText: part1English);
          userOrigFuture.then((cleanKorean) {
            if (mounted && _localMessages.length > hostIndex) {
              setState(
                  () => _localMessages[hostIndex]['original'] = cleanKorean);
            }
          });
        }
      }

      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      // ?Œ± [StepExpand] 5???„ë£Œ ì¡°ê¸° ì¢…ë£Œ
      // 5ë²ˆì§¸ ? ì? ?µë???_localMessages??ì¶”ê???ì§í›„ ì²´í¬
      // ??AI ?‘ë‹µ???ì„±?˜ì? ?Šê³  ê²°ê³¼ ë²„íŠ¼ ë°”ë¡œ ?œì‹œ
      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      if (_turnCounter >= MAX_TURNS) {
        // ?Œ± [LAST-TURN] ë§ˆì?ë§?5????ê¸??•ì¥ ë¬¸ì¥(30~50?¨ì–´)???ê¹Œì§€ ?¤ë ¤ì¤€ ???„ë£Œ ì²˜ë¦¬
        // ? ì? TTS fetch ?„ë£Œ ?€ê¸?(10ì´??€?„ì•„??
        int waitTicks = 0;
        while (userTtsFetcher.pendingRequests > 0) {
          await Future.delayed(const Duration(milliseconds: 50));
          waitTicks++;
          if (waitTicks > 200) {
            _log('? ï¸ [PIPE-TIMEOUT]', '? ì? TTS fetch 10ì´?ì´ˆê³¼, ê°•ì œ ì§„í–‰');
            break;
          }
        }
        // ? ì? TTS ?¬ìƒ ?„ë£Œ ?€ê¸?(ìµœë? 60ì´?
        waitTicks = 0;
        bool _lastTurnTimedOut = false;
        while (_ttsQueueManager.isBusy) {
          await Future.delayed(const Duration(milliseconds: 50));
          waitTicks++;
          if (waitTicks > 1200) {
            _log('? ï¸ [PIPE-TIMEOUT]', '? ì? TTS ?¬ìƒ 60ì´?ì´ˆê³¼, ê°•ì œ ì§„í–‰');
            _lastTurnTimedOut = true;
            break;
          }
        }
        // ?ì—° ì¢…ë£Œ ??800ms ë§ˆì§„ (?ë?ë¶??´ë¦¬??ë°©ì?)
        if (!_lastTurnTimedOut) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
        _ttsQueueManager.setUserTurn(false);

        // Firestore ?€??(? ì? ?´ë§Œ, AI ?‘ë‹µ ?†ìŒ)
        // ?”§ [PRACTICE-FIX] _localMessages[hostIndex]['target']?€ Part1\n\nPart2 ?•íƒœë¡??„ì ??        //    ??Part2(expanded)ë¥?expanded_sentence ?„ë“œë¡?ë³„ë„ ì¶”ì¶œ ?€??(?µì…˜ B, ?„ë°©?¸í™˜)
        final bool _hostValid = hostIndex < _localMessages.length;
        final String hostFullTarget = _hostValid
            ? ((_localMessages[hostIndex]['target']) ?? userTargetText)
                .toString()
            : userTargetText;
        final String hostExpanded =
            _expandedSentenceFromTranslation(hostFullTarget);
        final hostLineOnly = _buildHostHistoryLine(
          originalText: _hostValid
              ? ((_localMessages[hostIndex]['original']) ?? '').toString()
              : '',
          translatedText: hostFullTarget,
        );
        // ?”§ [PRACTICE-FIX] ?œì°¨ awaitë¡?race ì°¨ë‹¨
        //   1) sessions ?€??(???ˆì—??session_ref ë°±ë§?¬ê? _myHistoryRef??ë°•í˜)
        //   2) chat_history ?€??(???ˆì—??_ensureHistoryRefê°€ _myHistoryRefë¥?ë³´ì¥)
        await _saveTurnToFirestore([hostLineOnly]);
        await _saveHistoryMessages([hostLineOnly]); // ?”§ [?ˆìŠ¤? ë¦¬] ë³‘í–‰ ?€??        // ?Œ± [PRACTICE-READY] 5???„ë£Œ ì¦‰ì‹œ ë°?ë£¨íŠ¸??Practice???°ì´??ë°•ì•„?ê¸°
        //   - ê°•ì œ ì¢…ë£Œ/?¬ë˜???¤ë¡œê°€ê¸??°íšŒ ?€ë¹?        //   - has_practice: true ê°€ chat_history_master ì¸¡ì˜ Practice ì§„ì… ?¸ë¦¬ê±?        //   - polished_sentence???´í›„ _polishSentenceInline ??_savePolishedToFirestore?ì„œ ?°ë¡œ ì±„ì?
        if (_myHistoryRef != null && hostExpanded.isNotEmpty) {
          try {
            await _myHistoryRef!.update({
              'expanded_sentence': hostExpanded,
              'has_practice': true,
            });
            _log('?Œ± [PRACTICE-READY]',
                'ë°?ë£¨íŠ¸??expanded_sentence + has_practice ?€??);
          } catch (e) {
            _log('??[PRACTICE-READY-ERR]', '$e');
          }
        }

        _stopEverything();
        if (mounted) {
          setState(() {
            _isSessionComplete = true;
            _debugResult =
                _lastTurnTimedOut ? "?‰ 5???„ë£Œ! (ê¸?ë¬¸ì¥?¼ë¡œ ?¼ë? ê°•ì œ ì¢…ë£Œ)" : "?‰ 5???„ë£Œ!";
          });
        }
        _log('?Œ± [DONE]', '5???„ë£Œ ???•ì¥ë¬¸ì¥ ì¹´ë“œ ?œì‹œ (??…?€ ? ì? ?´ì—???„ë£Œ)');
        // ?” AUTO-FLOW 1: ?„ì„±???•ì¥ ë¬¸ì¥ ë³„ë„ ?œì‹œ (ë°©ì•ˆ1: ì¤‘ë³µ ??… ?œê±°) ?”
        // ??[ë°©ì•ˆ1-ì¤‘ë³µ?œê±°] ? ì? ?´ì—???´ë? ?™ì¼ ?•ì¥ë¬¸ì¥??nova ?Œì„±?¼ë¡œ
        //   ??…?ˆìœ¼ë¯€ë¡??„ì„± ì¹´ë“œ?ëŠ” ?”ë©´ ?œì‹œë§??˜ê³  ??…?˜ì? ?ŠëŠ”??
        //   (ê¸€?ëŠ” ë²„ë¸” + ì¹´ë“œ 2???¸ì¶œ ? ì? = ê²°ê³¼ ê°•ì¡°??ì¹´ë“œ ? ì?)
        if (hostExpanded.isNotEmpty && mounted) {
          setState(() {
            _expandedFinalSentence = hostExpanded;
            _showExpandedFinalCard = true;
          });
          _scrollToBottom();
        }

        // ?€?€ AUTO-FLOW 2: Polished Sentence ?ë™ ?ì„± ????… ??Study Room ?ˆë‚´ ?€?€
        await _autoPolishAndSpeak(hostExpanded);
        return;
      }

      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      // STEP 3 & 4 (ë³‘ë ¬): AI ?‘ë‹µ ë°±ê·¸?¼ìš´???ì„±
      //   ??AI ì²?¬???ì— ?“ì´ì§€ë§?_aiPaused=true???¬ìƒ ?€ê¸?      //   ??? ì? TTS??ê³„ì† ?¬ìƒ ì¤?      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      if (mounted) {
        setState(() => _localMessages
            .add({'role': 'SYSTEM', 'target': '', 'original': ''}));
        _scrollToBottom();
      }
      int aiIndex = _localMessages.length - 1;

      // ?”§ [v3.2 ë²„ê·¸ ?˜ì •] setUserTurn(false)??? ì? ?¬ìƒ ?„ë£Œ ?„ë¡œ ?´ë™
      // ?„ì¬ ?œì ?ì„œ ? ì? TTSê°€ ?„ì§ ?¬ìƒ ì¤‘ì¸??_isUserTurn=falseë¡?ë°”ê¾¸ë©?      // TtsQueueManager._processQueueê°€ 'AI ?´ì´ê³?paused' ?ë‹¨?˜ì—¬ ? ì? ë§ˆì?ë§?ì²?¬ê¹Œì? ë©ˆì¶°ë²„ë¦¼
      _ttsQueueManager.setAiPaused(true); // AI ?¬ìƒ ?€ê¸?ëª¨ë“œ (? ì? TTS??ê³„ì† ?¬ìƒ)
      // ?”§ [v3.5] AI ?„ìš© ?ë¡œ ë³´ë‚´ê¸??„í•´ isUser: false ëª…ì‹œ
      // ?Œ± [v4.0 StepExpand] AI ëª©ì†Œë¦¬ëŠ” nova ê³ ì •
      ChunkedTtsFetcher aiTtsFetcher = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        'nova', // ?Œ± AI ëª©ì†Œë¦?nova ê³ ì •
        isUser: false, // AI ?ë¡œ ë¶„ë¦¬
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
        voice: 'nova',
        onLog: _log,
      );

      _swOpenAI.reset();
      _swOpenAI.start();
      _swTTS.reset();

      _log('?§  [PIPE-02]', 'AI ?¤íŠ¸ë¦??”ì²­: userText="$userTargetText"');

      final aiStream = StepExpandBrain.streamGrammarQuestion(
        apiKey: _openAiKey,
        contextStr: latestContextStr,
        turnNumber: _turnCounter,
        maxTurns: MAX_TURNS,
        myTarget: targetLangName, // ?Œ [v3.1] ? ì?ê°€ ? íƒ???€ê²??¸ì–´
        userId: FirebaseAuth.instance.currentUser?.uid ?? '',
      );

      // AI ?ì„±+ì²?‚¹??Futureë¡?(? ì? ?¬ìƒê³?ë³‘ë ¬)
      bool _firstAiChunkLogged = false;
      final Future<void> aiGenerationTask = () async {
        await for (String chunk in aiStream) {
          if (!_firstAiChunkLogged) {
            _log('?§  [PIPE-03]', 'GPT ì²?ì²?¬ ?˜ì‹ : "$chunk"');
            _firstAiChunkLogged = true;
          }
          if (_swOpenAI.isRunning) _swOpenAI.stop();

          if (!aiHasDoubleNewline) {
            // Part1 (?ì–´): ?„ì  + ?˜ì´ë¸Œë¦¬??ì²?ì²?¬ ë°œì‚¬
            aiTargetText += chunk;
            aiBuffer += chunk;

            if (aiTargetText.contains('\n\n')) {
              // \n\n ê°ì?: Part1 ?? Part2(?œêµ­?? ?œì‘
              aiHasDoubleNewline = true;
              final sepIdx = aiTargetText.indexOf('\n\n');
              final afterSep = aiTargetText.substring(sepIdx + 2);
              aiTargetText = aiTargetText.substring(0, sepIdx);
              final bufSepIdx = aiBuffer.indexOf('\n\n');
              if (bufSepIdx >= 0) aiBuffer = aiBuffer.substring(0, bufSepIdx);
              if (afterSep.isNotEmpty) aiOriginalText += afterSep;
            } else {
              // Part1 ?˜ì´ë¸Œë¦¬?? 4?¨ì–´/êµ¬ë‘???„ë‹¬ ??ì²?ì²?¬ ë°œì‚¬
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
            // Part2 (?œêµ­??: aiOriginalText?ë§Œ ?„ì  ??TTS ê¸ˆì?
            aiOriginalText += chunk;
          }

          // ?ìŠ¤?¸ëŠ” AI ?Œë¦¬ ?œì‘ ?œì (setAiPaused=false)???¼ê´„ ?œì‹œ
        }
        // ?¤íŠ¸ë¦?ì¢…ë£Œ: remainder ë°œì‚¬ + ?µë¬¸??TtsCache ?€??        if (!firstChunkSentToTTS) {
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

      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      // STEP 5: ? ì? TTS ëª¨ë‘ ?¬ìƒ???Œê¹Œì§€ ?€ê¸?      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      _log('?§  [PIPE-04]',
          '? ì? TTS ?€ê¸??œì‘. pending=${userTtsFetcher.pendingRequests}');

      int waitTicks = 0;
      while (userTtsFetcher.pendingRequests > 0) {
        await Future.delayed(const Duration(milliseconds: 50));
        waitTicks++;
        if (waitTicks > 200) {
          // 10ì´??€?„ì•„??          _log('? ï¸ [PIPE-TIMEOUT]', '? ì? TTS fetch 10ì´?ì´ˆê³¼, ê°•ì œ ì§„í–‰');
          break;
        }
      }
      _log(
          '?§  [PIPE-05]', '? ì? TTS fetch ?„ë£Œ. isBusy=${_ttsQueueManager.isBusy}');

      // ?”’ [Box 7 USER-DRAIN-SIGNAL] ?¤ì œ ê¸°ë°˜ drain ê²Œì´??
      //   ë§ˆì?ë§?? ì? ì²?¬??ë§ˆì?ë§??˜í”Œ ?¬ìƒ ?„ë£Œ ì¦‰ì‹œ ?´ì œ?œë‹¤.
      //   ì¶”ì •ì¹?wps, ?¨ì–´?? ì²?ì²?¬ ì°¨ê°)???œê±°?˜ê³  Box 7 ?´ë²¤??ê¸°ë°˜?¼ë¡œ ê¸°ë‹¤ë¦°ë‹¤.
      _ttsQueueManager.sealUserStream();
      await _ttsQueueManager.waitUserDrained();
      _log('?§  [PIPE-06]',
          '? ì? TTS ?¬ìƒ ?„ë£Œ ??AI ??ê°œë°©. busy=${_ttsQueueManager.isBusy}');

      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      // STEP 6: AI ??ê°œë°©
      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      // ?”§ ? ì? ?Œë¦¬ ?„ì „ ì¢…ë£Œ ??0.5ì´???ê³ ë¥´ê¸???ê·??¤ìŒ ê¸€???Œë¦¬ ?™ì‹œ ì¶œë ¥.
      //    ? ì? ?Œë¦¬?€ AI ?Œë¦¬???ˆë? ê²¹ì¹˜ì§€ ?ŠëŠ”??
      await Future.delayed(const Duration(milliseconds: 500));
      _log('?§  [PIPE-GAP]', '? ì?-AI ?„í™˜ ?ˆì „ ê°„ê²© 500ms ?„ë£Œ');

      // ???„í™˜
      _ttsQueueManager.setUserTurn(false);
      _ttsQueueManager.setAiPaused(false);
      _log('?§  [PIPE-07]', 'setUserTurn(false) + setAiPaused(false). AI ?¬ìƒ ?œì‘');
      // AI ?Œë¦¬ ?œì‘ê³??™ì‹œ??ì§€ê¸ˆê¹Œì§€ ?“ì¸ ?ìŠ¤??ì¦‰ì‹œ ?œì‹œ
      if (mounted && aiIndex < _localMessages.length) {
        setState(() {
          _localMessages[aiIndex]['target'] = aiTargetText;
          _localMessages[aiIndex]['original'] = aiOriginalText;
        });
        _revealForReading(aiIndex, aiTargetText); // ?†• ê¸??€???”ë ˆ?„ë¡¬?„í„°
      }
      // [v3.8] AI ?œêµ­???¨ì¼ ?¸ì¶œ ?µí•©
      //   streamGrammarQuestion ?„ë¡¬?„íŠ¸ê°€ "?ì–´ \n\n ?œêµ­?? ???ŒíŠ¸ë¥????¤íŠ¸ë¦¼ìœ¼ë¡?ì¶œë ¥
      //   Part1 = target + TTS, Part2 = original (TTS ë¯¸ì „??
      //   ë³„ë„ generateCleanOriginal ?¸ì¶œ ?†ìŒ ??GPT ?¸ì¶œ 1?Œë¡œ ????ì²˜ë¦¬

      await aiGenerationTask;
      // ?¤íŠ¸ë¦¬ë°???„ì§ ì§„í–‰ ì¤‘ì´?ˆë‹¤ë©?ìµœì¢… ?ìŠ¤??ë°˜ì˜
      if (mounted && aiIndex < _localMessages.length) {
        setState(() {
          _localMessages[aiIndex]['target'] = aiTargetText;
          _localMessages[aiIndex]['original'] = aiOriginalText;
        });
        _revealForReading(aiIndex, aiTargetText); // ?†• ê¸??€???”ë ˆ?„ë¡¬?„í„°
      }
      _log('?§  [PIPE-08]',
          'aiGenerationTask ?„ë£Œ. AI pending=${aiTtsFetcher.pendingRequests}');

      waitTicks = 0;
      while (aiTtsFetcher.pendingRequests > 0 || _ttsQueueManager.isBusy) {
        await Future.delayed(const Duration(milliseconds: 50));
        waitTicks++;
        if (waitTicks > 300) {
          // 15ì´??€?„ì•„??          _log('? ï¸ [PIPE-TIMEOUT]', 'AI TTS 15ì´?ì´ˆê³¼, ê°•ì œ ì§„í–‰');
          break;
        }
      }
      _log('?§  [PIPE-09]', 'AI TTS ?¬ìƒ ?„ë£Œ');

      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      // STEP 7: Firestore ?€??      // ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      // ?ˆìŠ¤? ë¦¬ ?€????Korean original ?„ë£Œ ë³´ì¥ (1??ë°?2??)
      // effectiveOriginal(?”ë©´ ?œì‹œ??ê³??¬ë¦¬, ?€??payload?ëŠ” ?¤ì œ originalRaw ?¬ìš©
      if (userOrigFuture != null) {
        try {
          final cleanKorean =
              await userOrigFuture.timeout(const Duration(seconds: 10));
          if (hostIndex < _localMessages.length &&
              (_localMessages[hostIndex]['original'] ?? '')
                  .toString()
                  .isEmpty) {
            _localMessages[hostIndex]['original'] = cleanKorean;
          }
        } catch (_) {}
      }
      final String _hostOriginal = hostIndex < _localMessages.length
          ? ((_localMessages[hostIndex]['original']) ?? '').toString()
          : '';
      final hostLine = _buildHostHistoryLine(
        originalText: _hostOriginal,
        translatedText: userTargetText,
      );
      final systemLine = {
        'role': 'SYSTEM',
        'original_text': aiOriginalText.trim(),
        'translated_text': aiTargetText,
      };
      await _saveTurnToFirestore([hostLine, systemLine]);
      await _saveHistoryMessages(
          [hostLine, systemLine]); // ?”§ [?ˆìŠ¤? ë¦¬] ë³‘í–‰ ?€??(await ë³´ì¥)
      _log('?§  [PIPE-10]', 'Firestore ?€???„ë£Œ');
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

  // Step Expand HOST ?€??payloadë¥?sessions/chat_history?ì„œ ?™ì¼?˜ê²Œ ? ì??œë‹¤.
  String _expandedSentenceFromTranslation(String translatedText) {
    final parts = translatedText.split(RegExp(r'\n\s*\n'));
    if (parts.length < 2) return '';
    return parts.sublist(1).join('\n\n').trim();
  }

  Map<String, dynamic> _buildHostHistoryLine({
    required String originalText,
    required String translatedText,
  }) {
    final expandedSentence = _expandedSentenceFromTranslation(translatedText);
    return {
      'role': 'HOST',
      'original_text': originalText,
      'translated_text': translatedText,
      if (expandedSentence.isNotEmpty) 'expanded_sentence': expandedSentence,
    };
  }

  /// ????? ì?+AI)??ChatLine 2ê°œë? Firestore???€??  /// - _sessionDocIdê°€ null?´ë©´ ???¸ì…˜ ?ì„±
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

      await _ensureHistoryRef();

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
          'mode': 'step_expand', // ?”§ [v3.1] ?ˆìŠ¤? ë¦¬ ëª¨ë“œë³??„í„°ë§ìš©
          'total_turns': _turnCounter, // ?Œ± ???¸ì…˜?ì„œ ëª??´ê¹Œì§€ ?±ì¥?ˆëŠ”ì§€
          'created_at': FieldValue.serverTimestamp(),
          'transcript': chatLines,
        });
        _sessionDocId = newSession.id;
        _log('?’¾ [SAVE-05]', '???¸ì…˜ ?ì„± ?„ë£Œ. docId=$_sessionDocId');
        // ?”§ [v3.7] chat_history ë°©ì— session_ref ë°±ë§??(Practice ?°ë™??
        if (_myHistoryRef != null) {
          try {
            await _myHistoryRef!.update({'session_ref': _sessionDocId});
            _log('?”— [HIST-LINK]', 'session_ref ë§í¬ ?„ë£Œ: $_sessionDocId');
          } catch (e) {
            _log('??[HIST-LINK-ERR]', 'session_ref ?€???¤íŒ¨: $e');
          }
        }

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
      _myHistoryRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('chat_history')
          .doc();
      await _myHistoryRef!.set({
        'created_at': FieldValue.serverTimestamp(),
        'last_active': FieldValue.serverTimestamp(),
        'room_name': "Step.Ex Mode",
        'mode': 'step_expand',
        'is_pinned': false,
        'has_practice': false,
        'last_message': '',
        'msg_count': 0
      });
      _log('?“š [HIST-NEW]', 'chat_history ë°??ì„±: ${_myHistoryRef!.id}');
    }
  }

  /// ?´ë§ˆ??chat_history/messages ?œë¸Œì»¬ë ‰?˜ì— ê¸°ë¡ ë³‘í–‰ ?€??  /// - chatLines: _saveTurnToFirestore?€ ?™ì¼??[{role, original_text, translated_text}, ...]
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

  Future<void> _saveHistoryMessages(
      List<Map<String, dynamic>> chatLines) async {
    try {
      await _ensureHistoryRef();
      if (_myHistoryRef == null) return;

      // messages ?œë¸Œì»¬ë ‰?˜ì— ê°?ë°œí™” ?€??      final List<String> savedIds = [];
      for (final line in chatLines) {
        final translated = (line['translated_text'] ?? '').toString().trim();
        if (translated.isEmpty) continue; // ë¹?ë°œí™” ?¤í‚µ
        // ?”§ [PRACTICE-FIX] expanded_sentence ?„ë“œ ?ˆìœ¼ë©??¨ê»˜ ?€??(?µì…˜ B ?„ë°©?¸í™˜)
        final String expandedSent =
            (line['expanded_sentence'] ?? '').toString().trim();
        final addedRef = await _myHistoryRef!.collection('messages').add({
          'role': line['role'] ?? '',
          'translated_text': translated,
          'original_text': (FFAppState().nativeLang.isNotEmpty &&
                  FFAppState().nativeLang == FFAppState().targetLang)
              ? ''
              : (line['original_text'] ?? '').toString(),
          if (expandedSent.isNotEmpty) 'expanded_sentence': expandedSent,
          'created_at': FieldValue.serverTimestamp(),
        });
        savedIds.add(addedRef.id);
      }
      if (savedIds.isNotEmpty) {
        _lastExchangeMsgIds = List<String>.from(savedIds);
      }

      // ?”§ [?µì‹¬] ?´ë§ˆ??msg_count/last_message ?…ë°?´íŠ¸
      //   - ?¤ë¡œê°€ê¸?ê²½ë¡œ?€ ë¬´ê??˜ê²Œ ??ƒ ê°±ì‹ ??      //   - last_message??ë§ˆì?ë§?ë¹„ì–´?ˆì? ?Šì? translated_text
      final lastTranslated = chatLines
          .map((l) => (l['translated_text'] ?? '').toString().trim())
          .lastWhere((t) => t.isNotEmpty, orElse: () => '');
      if (lastTranslated.isNotEmpty) {
        final updateMap = <String, dynamic>{
          'msg_count': FieldValue.increment(chatLines.length),
          'last_message': lastTranslated,
          'last_active': FieldValue.serverTimestamp(),
        };
        final expandedSentence = chatLines
            .map((l) => (l['expanded_sentence'] ?? '').toString().trim())
            .lastWhere((t) => t.isNotEmpty, orElse: () => '');
        if (expandedSentence.isNotEmpty) {
          updateMap['expanded_sentence'] = expandedSentence;
        }
        await _myHistoryRef!.update(updateMap);
        _log('?’¾ [HIST-UPD]',
            'msg_count+${chatLines.length}, last="$lastTranslated"');
      }
    } catch (e) {
      _log('??[HIST-ERR]', 'chat_history ?€???¤íŒ¨: $e');
    }
  }

  /// ?¤ë¡œê°€ê¸??? ë¹?ë°???ŒŒ or last_message ?…ë°?´íŠ¸ ???˜ê?ê¸?  Future<void> _handleAutoSaveAndExit() async {
    if (_isExiting) return; // ?”§ [EXIT-GUARD] ?´ë? ì¢…ë£Œ ì²˜ë¦¬ ì¤‘ì´ë©?ë¬´ì‹œ
    _isExiting = true;
    BillingTicker.instance.pause();
    try {
      if (_myHistoryRef != null) {
        // ?€?”ê? ??ë²ˆë„ ?†ì—ˆ?¼ë©´ ë°?ë¬¸ì„œ ?? œ (?°ë ˆê¸??°ì´??ë°©ì?)
        final hasUserTurn = _localMessages.any((m) => m['role'] == 'HOST');
        if (!hasUserTurn) {
          await _myHistoryRef!.delete();
          _log('?—‘ï¸?[HIST-DEL]', 'ë¹?ë°??? œ ?„ë£Œ');
        } else {
          // ë§ˆì?ë§?? íš¨ target ?ìŠ¤??ì°¾ê¸°
          String lastText = "?€??ê¸°ë¡ ?€??;
          for (int i = _localMessages.length - 1; i >= 0; i--) {
            final t = (_localMessages[i]['target'] ?? '').toString().trim();
            if (t.isNotEmpty && t != '...') {
              lastText = t;
              break;
            }
          }
          // expandedSentence ì¶”ì¶œ (ë§ˆì?ë§?HOST ë©”ì‹œì§€ Part2)
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

          // expanded_sentence ?ˆì„ ?Œë§Œ ì¶”ê? (1???¨ë‹µ??ë°??œì™¸)
          if (expandedSentence.isNotEmpty) {
            updateMap['expanded_sentence'] = expandedSentence;
          }

          // session_ref ?ˆì„ ?Œë§Œ ì¶”ê? (? ê·œ ?¸ì…˜ ?ì„±??ê²½ìš°)
          if (_sessionDocId != null) {
            updateMap['session_ref'] = _sessionDocId;
          }

          await _myHistoryRef!.update(updateMap);
          _log('?’¾ [HIST-UPD]',
              'chat_history ?…ë°?´íŠ¸ ?„ë£Œ (expanded=${expandedSentence.isNotEmpty})');
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
      // ?”§ [POPSCOPE] ?œìŠ¤???œìŠ¤ì²??˜ë‹¨ë°??¤ë¡œê°€ê¸°ë„ AutoSave ê²½ë¡œë¥??€ê²??œë‹¤.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await _handleAutoSaveAndExit();
      },
      child: Container(
        color: const Color(0xFF121212),
        child: SafeArea(
          child: Column(children: [
            _buildTopBar(),
            const SizedBox(height: 4),
            Expanded(
              child: Stack(children: [
                _buildChatList(),
                _buildIdleOverlay(),
                _buildSeedHintBalloon(),
              ]),
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
          IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white70),
              onPressed: _handleAutoSaveAndExit), // ?”§ [?ˆìŠ¤? ë¦¬] AutoSave ?°ê²°
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
            // [v3.6] ?”ì—¬?œê°„ ?œì‹œ + ê¸¸ê²Œ ?„ë¥´ë©?ë¡œê·¸ (ê°œë°œ?ìš©)
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

  Widget _buildTopControls() {
    // [v3.6] ??ì§„í–‰ ?íƒœ ?¸ë””ì¼€?´í„° (ì¶•ì†Œ ??ê³µê°„ ìµœì†Œ??
    final progressText = _isSessionComplete
        ? "??Complete ($MAX_TURNS/$MAX_TURNS)"
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

    // ì¶”ê? ?„ì ¯ ëª©ë¡ (ë©”ì‹œì§€ ëª©ë¡ ?„ë˜???œì„œ?€ë¡??œì‹œ)
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

    final double bottomPad = MediaQuery.of(context).size.height * 0.55;
    return ListView.builder(
      reverse: true,
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(16, bottomPad, 16, 16),
      itemCount: _localMessages.length + extras.length,
      itemBuilder: (context, idx) {
        if (idx < extras.length) {
          final extraIdx = extras.length - 1 - idx;
          return extras[extraIdx]();
        }
        final msgReverseIdx = idx - extras.length;
        final realIdx = _localMessages.length - 1 - msgReverseIdx;
        if (realIdx >= 0 && realIdx < _localMessages.length) {
          _itemKeys[realIdx] ??= GlobalKey();
          return Container(
              key: _itemKeys[realIdx],
              child: _buildTextBlock(_localMessages[realIdx]));
        }
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
            _isPolishing ? "Polishing..." : "??Polished Version",
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
              Text("??Completed Sentence",
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
          '?“š Study Room?ì„œ ?°ìŠµ ?˜ì„¸??,
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

  Widget _buildSeedHintBalloon() {
    return Positioned(
      top: 8,
      left: 24,
      right: 24,
      child: IgnorePointer(
        ignoring: !_showSeedHint,
        child: AnimatedOpacity(
          opacity: _showSeedHint ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF3B3B3D),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lightbulb_outline,
                    color: Color(0xFFFBBF24), size: 16),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'ì§ˆë¬¸ê³??¤ë¥¸ ?¨ì•— ë¬¸ì¥??ë§ì??˜ì…”???©ë‹ˆ??',
                    style: TextStyle(
                      color: Color(0xFFFBBF24),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
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

    // ?Œ± [PART1-HIDE] 2?? ? ì? ë²„ë¸”?€ ?•ì¥ë¬¸ì¥(Part2)ë§??”ë©´???œì‹œ?œë‹¤.
    //   - Part1(ì§§ì? ?€??ê³?Part1 ?œêµ­?´ëŠ” ?”ë©´?ì„œ ?¨ê¸´??(?ˆìŠ¤? ë¦¬ ?€?¥ê°’?€ ê·¸ë?ë¡?.
    //   - ?¤íŠ¸ë¦¬ë° ì¤?Part1ë§??¤ì–´??êµ¬ê°„(?„ì§ \n\n ë¯¸ë„ì°??€ '...' placeholderë§??¸ì¶œ.
    //   - turnId ?°ì„  ?ë‹¨(?¤íŠ¸ë¦¬ë° ê¹œë¹¡??ë°©ì?), ?†ìœ¼ë©??ŒíŠ¸ ?˜ë¡œ ?„ë°©?¸í™˜.
    final int turnId = (msg['turnId'] is int) ? msg['turnId'] as int : 0;
    final bool isExpandTurn =
        role == 'HOST' && (turnId >= 2 || targetParts.length >= 2);

    // HOST bubbles only show the target sentence; original stays available for history saves.
    final String effectiveOriginal =
        (role == 'HOST_TEMP' || role == 'HOST') ? '' : originalRaw;

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
            if (isExpandTurn) ...[
              // ?Œ± [PART1-HIDE] Part2(?•ì¥ë¬¸ì¥)ë§??œì‹œ. Part2 ë¯¸ë„ì°???'...' placeholder.
              //   ?œêµ­?´ëŠ” ?œì‹œ?˜ì? ?ŠëŠ”??(Part2?ëŠ” ?ë˜ ?œêµ­?´ê? ?†ìŒ).
              Text(
                  targetParts.length >= 2
                      ? targetParts.sublist(1).join('\n\n').trim()
                      : '...',
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
              if (_showOriginal &&
                  !(FFAppState().nativeLang.isNotEmpty &&
                      FFAppState().nativeLang == FFAppState().targetLang) &&
                  effectiveOriginal.isNotEmpty) ...[
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
  // ?¯ [Practice UI] ?˜ë??¨ìœ„ ë°˜ë³µ ?°ìŠµ ë·?  // ====================================================================

  /// Practice ë©”ì¸ ë·?(_buildChatList ?€ì²?
  Widget _buildPracticeContent() {
    return Column(
      children: [
        // ?¤ë”
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
        // ?¤í¬ë¡?ê°€?¥í•œ ì½˜í…ì¸?        Expanded(
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

  /// ?„ì²´ ë¬¸ì¥ ???˜ë??¨ìœ„ë§ˆë‹¤ ???‰ìƒ êµì°¨, ?„ì¬ ?¨ìœ„ ê°•ì¡° + ??œ¼ë¡??´ë™
  Widget _buildPracticeFullSentence() {
    const Color colorA = Color(0xFF60A5FA); // ?Œë???    const Color colorB = Color(0xFFA7F3D0); // ?¹ìƒ‰

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

  /// ì§„í–‰ ?íƒœ ??(AI ??… / ? ì? ?°ë¼ ë§í•˜ê¸?/ ?¤í‚µ ë²„íŠ¼)
  Widget _buildPracticeStatusRow() {
    String label;
    Color color;
    IconData icon;

    if (_isPracticeAiSpeaking) {
      label = 'AI ??… ì¤?..';
      color = const Color(0xFF9333EA);
      icon = Icons.volume_up_rounded;
    } else if (_isPracticeUserListening) {
      label = '?°ë¼ ë§í•˜?¸ìš” ?¤';
      color = const Color(0xFF10B981);
      icon = Icons.mic_rounded;
    } else {
      label = 'ì¤€ë¹?ì¤?..';
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

  /// ?„ë£Œ ?? AI/? ì? ?„ì²´ ?£ê¸° + ?•ì¥ë¬¸ì¥ ?°ìŠµ?˜ê¸° ?´ë™ ë²„íŠ¼
  Widget _buildPracticeCompleteArea() {
    return Column(
      children: [
        // AI Voice / My Voice (2ë²„íŠ¼ ??ì¤?
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
                  _isAiFullPlaying ? '?•ì?' : 'AI Voice',
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
                  _isUserFullPlaying ? '?•ì?' : 'My Voice',
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

  // ë§ˆì´??ë²„íŠ¼ ?†ìŒ ??AI ë°œí™” ??STT ?ë™ ?œì‘
  // ?˜ë‹¨?€ ?¸ë? ë¶ˆë¹› ?¸ë””ì¼€?´í„°ë§??œì‹œ?˜ì—¬ ì±„íŒ… ê³µê°„ ìµœë???  Widget _buildControlArea(double bp) {
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
          // [?íƒ­ ?•ì • ë²„íŠ¼ ?œê±°] ?Œì„± ?•ì •(CORRECTION/MISHEARD)?¼ë¡œ ?€ì²?          // ?‘ë™ ì¤??¸ë? ë¶ˆë¹› ?¸ë””ì¼€?´í„°
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

  // [?íƒ­ ?•ì • ?œê±°] ?Œì„± ?•ì •(CORRECTION/MISHEARD)?¼ë¡œ ?€ì²?}

// ====================================================================
// ?™ï¸?[Box 7] ê³µí†µ ?µì‹  ?”ì§„ v3 ??ëª¨ë“  ëª¨ë“œ ê³µìœ 
// ====================================================================
// ?“‚ ?œë¸Œë°•ìŠ¤ êµ¬ì„±:
//   [Box 7-A] ConversationHistory  ???¬ë¼?´ë”© ?ˆë„???€??ê¸°ì–µ
//   [Box 7-B] DeepgramV2VoiceManager ??? ì? ?Œì„± ???ìŠ¤??(STT)
//   [Box 7-C] UnifiedBrain          ??ë²”ìš© GPT ?¤íŠ¸ë¦¬ë° (Duo ??
//   [Box 7-D] TtsCache              ??TTS ë¡œì»¬ ìºì‹± (Firebase Storage ë¹„ìš© 0)
//   [Box 7-E] TtsQueueManager       ??TTS ?¤ë””????+ AI ?€ê¸??Œë˜ê·?//   [Box 7-F] ChunkedTtsFetcher     ??TTS ?˜ë??¨ìœ„ ì²?‚¹ + ìºì‹±
//   [Box 7-G] RelayPipeline         ??ë²”ìš© ?Œì´?„ë¼??(ì°¸ê³ ??
// ====================================================================

// ====================================================================
// ?“¦ [Box 7 ê³µìš© ?ìˆ˜] ?¤êµ­??TTS êµ¬ë‘???¨í„´
// ====================================================================
// ?œêµ­???¼ë³¸??ì¤‘êµ­???¼í‹´ êµ¬ë‘???µí•© (?¼í‘œ/ë§ˆì¹¨??ë¬¼ìŒ???ë‚Œ????
// ê°?Brain/?Œì´?„ë¼?¸ì—??TTS ì²?‚¹ ê¸°ì??¼ë¡œ ?¬ìš©
final RegExp kTtsDelimiterPattern = RegExp(r'[,\.?!;:?‚ã€ï¼ï¼Ÿâ€?¼Œï¼›ï¼š\n]');

// ====================================================================
// ?“¦ [Box 7-H: HybridTtsPlayer] ???˜ì´ë¸Œë¦¬??TTS (Step Expand + Roleplay ê³µìš©)
// ====================================================================
// ?¤ê³„ ?ì¹™: ì²?êµ¬ë‘??ì¦‰ì‹œ ë°œì‚¬(ì²´ê° ë¹ ë¦„) + ?µë¬¸??ìºì‹œ ?€???ˆìŠ¤? ë¦¬ ?µí•©)
//   ??onChunk: ì²?êµ¬ë‘??4?¨ì–´ ?„ë‹¬ ??ChunkedTtsFetcher??1??ë°œì‚¬
//   ??onStreamEnd: remainder ?œì°¨ ë°œì‚¬ + fullSentence TtsCache ?€??(?¬ìƒ ?†ìŒ)
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

  // 4?¨ì–´ ì¡°ê¸° ë°œì‚¬ ë³´ì¶©: êµ¬ë‘??OR 4?¨ì–´ ì¤?ë¨¼ì? ?¤ëŠ” ìª?ë°œì‚¬
  // buffer: ?„ì¬ê¹Œì? ?„ì ???ìŠ¤??ë²„í¼ (?¸ë??ì„œ ê´€ë¦?
  // ë°˜í™˜ê°? buffer?ì„œ ?ë? ?¸ë±??(>=0?´ë©´ ë°œì‚¬?? -1?´ë©´ ë¯¸ë°œ??
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
        'ë°œì‚¬(${punctMatch != null ? "êµ¬ë‘?? : "4?¨ì–´"}): "$text" ${lastFirstChunkMs}ms');
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
      // êµ¬ë‘??4?¨ì–´ ?†ì´ ?¤íŠ¸ë¦?ì¢…ë£Œ ???„ì²´ ?ìŠ¤?¸ë? ì§€ê¸?ë°œì‚¬
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
// ?“¦ [Box 7-A: ConversationHistory] ???¬ë¼?´ë”© ?ˆë„???ˆìŠ¤? ë¦¬ ê´€ë¦¬ì
// ê¸°ì¡´ ë²„ì „ ë¬¸ì œ: ?ˆìŠ¤? ë¦¬ê°€ ì£¼ì„?ë§Œ ì¡´ì¬, ?¤ì œ êµ¬í˜„ ?†ìŒ
// ê°œì„ : 2000? í° ?¬ë¼?´ë”© ?ˆë„?? ??•  êµ¬ë¶„, ì§ë ¬??ì§€??// ====================================================================
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

  /// GPT API messages ë°°ì—´ë¡?ì§ë ¬??  List<Map<String, String>> toMessages() => List.unmodifiable(_turns);

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
//   - onReconnecting / onGaveUp ì½œë°± ì¶”ê?ë¡?UI ?íƒœ ?™ê¸°??// ====================================================================
class DeepgramV2VoiceManager {
  final String apiKey;
  final AudioRecorder audioRecorder;
  final String langCode;
  final VoidCallback onConnected;
  final Function(String) onTranscriptUpdate;
  final Function(String) onTurnEnded;
  final Function(String) onError;
  final Function(int)? onReconnecting; // ?¬ì—°ê²??œë„ ?Œë¦¼ (? íƒ??
  final VoidCallback? onGaveUp; // ?¬ì—°ê²??¬ê¸° ?Œë¦¼ (? íƒ??
  final void Function(String tag, String msg)? onLog; // ?”¬ [v3.1] ë¡œê·¸ ??  final void Function(Uint8List)? onAudioData;

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
        '&utterance_end_ms=1000' // ?”§ ë°˜ì‘?ë„ ?¨ì¶•: 1200??000ms
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

      // ?”§ [v3.1 ?µì‹¬ ë²„ê·¸ ?˜ì •] ë§ˆì´???¤íŠ¸ë¦?ê°•ì œ ?¬ì‹œ??      _lg('?¤ [MIC-02]', 'ë§ˆì´???œì‘ ?œí€€??ì§„ì…');
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
              final packet = Uint8List.fromList(data);
              _channel?.sink.add(packet);
              onAudioData?.call(packet);
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
        _lg('?“¡ [DG-03]',
            'isFinal=$isFinal speechFinal=$speechFinal chunk="$chunk"');
      }

      // ?¸í„°ë¦?ê²°ê³¼??activity ? í˜¸ë¡??¬ìš© (ì¹¨ë¬µ ?€?´ë¨¸ ì·¨ì†Œ??
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
        _lg('?“¡ [DG-04]',
            'speech_final ??onTurnEnded ?¸ì¶œ ?œë„. finalText="$finalText"');
        if (!_isDisposed && finalText.isNotEmpty) {
          _lg('?“¡ [DG-05]', 'onTurnEnded ?¤ì œ ?¸ì¶œ');
          onTurnEnded(finalText);
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
    Duration timeout = const Duration(seconds: 30), // ?’¡ ? ê·œ: ?€?„ì•„??  }) async* {
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
//   1. onPlayerComplete ë¦¬ìŠ¤?ˆê? ?„ìˆ˜ ê°€??//   2. timeout 10ì´ˆê? ì§§ì? ë¬¸ì¥??ê³¼í•¨, ê¸?ë¬¸ì¥??ë¶€ì¡?// ê°œì„ :
//   - StreamSubscription?¼ë¡œ ë¦¬ìŠ¤??ëª…ì‹œ??ê´€ë¦?//   - ?¤ë””??ê¸¸ì´ ì¶”ì‚° ê¸°ë°˜ ?™ì  ?€?„ì•„??//   - stop() ??Completer ?ˆì „ ?„ë£Œ ì²˜ë¦¬
// ====================================================================
// ====================================================================
// ?“¦ [Box 7-D: TtsCache] ??TTS ?¤ë””??ë¡œì»¬ ìºì‹± (MD5 ?¤í????´ì‹œ)
// ====================================================================
// ?”§ [v3 ? ê·œ] ê°™ì? ?ìŠ¤??voice+speed???Œì¼ ?¬ì‚¬??//   ??OpenAI API ?¸ì¶œ 0, ì¦‰ì‹œ ?¬ìƒ, Firebase Storage ë¹„ìš© 0
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
  // ?”§ [v3.5] ë¶„ë¦¬??????  final List<Uint8List> _userQueue = []; // ? ì? TTS ?„ìš©
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

  // ?”’ [Box 7 USER-DRAIN-SIGNAL] ? ì? ???„ì „ drain ê°ì???  bool _userStreamSealed = false;
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
            ? 'step_expand_user_tts_start'
            : 'step_expand_ai_tts_start');
        await _player.play(BytesSource(bytes));
        await _completer!.future.timeout(estimatedDuration);
        BillingTicker.instance.resumeFromActivity(_currentChunkIsUser
            ? 'step_expand_user_tts_end'
            : 'step_expand_ai_tts_end');
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
// ?“¦ [Box 7-F: ChunkedTtsFetcher] ??ìºì‹± + ?¬ì‹œ??// ====================================================================
// ?”§ [v3] _fetch ?¨ê³„?ì„œ ë¡œì»¬ ìºì‹œ ë¨¼ì? ?•ì¸, ë¯¸ìŠ¤ ?œì—ë§?API ?¸ì¶œ + ?€??class ChunkedTtsFetcher {
  final String apiKey;
  final TtsQueueManager audioQueue;
  final String voice;
  final String language;
  final bool isUser; // ?”§ [v3.5] true=? ì? ?? false=AI ??  final void Function(String tag, String msg)? onLog; // ?”¬ [v3.1] ë¡œê·¸ ??
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
    this.isUser = true, // ?”§ [v3.5] ê¸°ë³¸ê°? ? ì? ??    this.onAllComplete,
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

    // [2?¨ê³„] API ?¸ì¶œ (?€?„ì•„???¬ë‹¤ë¦?5/8/12ì´? ìµœë? 3???œë„) ??TTS ì§€???¤íŒŒ?´í¬ ?€??    Uint8List result = Uint8List(0);
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
      onTranscriptUpdate: (_) {}, // UI?ì„œ ?¤ë²„?¼ì´??      onTurnEnded: _onUserTurnEnded,
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

  Future<void> _onUserTurnEnded(String userText) async {
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

      // ?’¡ ? ê·œ: AI ?‘ë‹µ ?„ë£Œ ???ˆìŠ¤? ë¦¬ ?€??      if (aiResponseBuffer.isNotEmpty) {
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
// ?§  [Box 7-1] StepExpandBrain v3 ???¤í…?µìŠ¤?¬ë“œ ?„ìš© AI ??// ====================================================================
// ?“‚ ?œë¸Œë°•ìŠ¤ êµ¬ì„±:
//   [Box 7-1-A] streamUserTranslation  ??ì²«í„´=?¨ìˆœë²ˆì—­, 2??=Part1+\n\n+Part2
//   [Box 7-1-B] generateCleanOriginal  ???â†’????²ˆ??(\n\n ? ì?)
//   [Box 7-1-C] streamGrammarQuestion  ????1~4: ë¬¸ë²• ? ë„, ??5: ë§ˆë¬´ë¦?//   [Box 7-1-D] polishSentence          ???¸ë ¨??ë³€???ì„± (?¤í”¼?¹ìš© ê³ ê¸‰)
// ====================================================================
class StepExpandBrain {
  // ==================================================================
  // ?“¦ [Box 7-1-0] splitIntoMeaningUnits ??Practice???˜ë??¨ìœ„ ë¶„í•´
  // ------------------------------------------------------------------
  // ë¬¸ì¥??6~12ê°œì˜ ?˜ë??¨ìœ„(ì²?¬)ë¡?ë¶„í•´. "|" êµ¬ë¶„?ë¡œ ë°˜í™˜.
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
    // ?´ë°±: ?¼í‘œ/?„ì¹˜?¬êµ¬ ê¸°ì? ?¨ìˆœ ë¶„ë¦¬
    final raw = sentence
        .split(RegExp(
            r'(?<=[,;])\s+|(?=\s+(?:because|when|although|which|who|where|that|and|but|so|to)\s)'))
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();
    return raw.isNotEmpty ? raw : [sentence];
  }

  // ==================================================================
  // ?“¦ [Box 7-1-A] streamUserTranslation ??CoT 2?¨ê³„ + ?±ì¥ ë¨¸ì§•
  // ------------------------------------------------------------------
  // ?Œ± ??ê°€ì§€ ì¼€?´ìŠ¤:
  //   CASE 1 (ì²???: ?¨ìˆœ ë²ˆì—­ 1ê°œë§Œ
  //   CASE 2 (2??): Part1(ì§§ì? ë²ˆì—­) + \n\n + Part2(?±ì¥???•ì¥ ë¬¸ì¥)
  // ==================================================================
  static Stream<String> streamUserTranslation({
    required String apiKey,
    required String textOriginal,
    required String targetLang,
    required String contextStr,
    bool disableCorrection = false,
    bool disableRestate = false,
  }) async* {
    final client = http.Client();
    try {
      final String correctionBlock = disableCorrection
          ? "NEVER output [CORRECTION] or [MISHEARD] or any bracket token. This input is the user RE-STATING what they actually meant. Output ONLY the actual intended content as natural $targetLang. STRIP all correction framing: lead-ins (\"¾Æ´Ï\" / \"¾Æ´ÏÁö\" / \"³» ¸»Àº\" / \"³» ¸»Àº¿ä\" / \"±×°Ô ¾Æ´Ï¶ó\" / \"³»°¡ ¸»ÇÑ °Ç\") AND quote-report frames (\"~¶ó°í Çß¾î¿ä\" / \"~¶ó°í Çß¾î\" / \"~¶ó°í ¸»Çß¾î¿ä\" / \"~¶ó°í ¸»Çß°í\" / \"I said\" / \"I also said\" / \"what I said was\"). When multiple quoted statements are reported, merge them into natural connected $targetLang. Examples: \"¾Æ´Ï ³» ¸»Àº¿ä ´ç½Å Àß¸øÀÌ¶ó°í¿ä\" -> \"It's clearly your fault.\" | \"³ª´Â »¡¸® ±¸ÇØ ÁÖ¼¼¿ä¶ó°í Çß¾î¿ä ÈŞÁö°¡ ¾ø¾î¿ä¶ó°í ¸»Çß°í\" -> \"Please rescue me quickly, and there's no toilet paper.\""
          : """[CASE CORRECTION] ??Check this FIRST, but only when History contains at least one 'User:' line
The user is correcting the AI's misunderstanding of a previous answer.
Signs:
- Starts with correction signals: "?„ë‹ˆ" / "?„ë‹ˆ?? / "??ê·¸ê²Œ ?„ë‹ˆ?? / "?¤ì‹œ" / "??ë§ì?" / "ê·¸ëŸ¬?ˆê¹Œ" / "?´ê? ë§í•œ ê±? / "?¼ê³  ?ˆì–?? / "?¼ê³  ë§í–ˆ?? / "I mean" / "I said" / "what I said was" / "that's not what I said" / "actually" / "no," / "wait,"
- AND the content is clearly a re-statement or clarification of the LAST 'User:' line in History (not new story info)
- The user is essentially saying "that's not what I said ??what I said was X"
If this is a correction, output EXACTLY: [CORRECTION]
Do NOT output [CORRECTION] for genuinely NEW information that merely starts with "?„ë‹ˆ" etc. BUT if the AI's previous turn clearly captured the user's earlier utterance as DIFFERENT content (a wrong word or a wrong topic) and the user is now restating what they actually meant, output [CORRECTION] even when the restatement also reads like a fresh answer. Test: would the user naturally say "that's not what I said"? If yes -> output [CORRECTION].

[CASE MISHEARD] ??Check this SECOND, only when History contains at least one 'User:' line
The user is COMPLAINING that their previous words were misheard or misunderstood, WITHOUT restating what they actually said.
Signs:
- The utterance is essentially ONLY a complaint: "??ë§ì´ ê·¸ëŸ° ?»ì´ ?„ë‹ˆ?? / "ê·¸ëŸ° ê±??„ë‹ˆ?? / "??ë§ì? ê·¸ê²Œ ?„ë‹ˆ?? / "?˜ëª» ?¤ì—ˆ?? / "?˜ëª» ?ì—ˆ?? / "?˜ëª» ?Œì•„?¤ì—ˆ?? / "that's not what I meant" / "you misheard me" / "you got my words wrong"
- AND it contains NO restated content (no actual answer, no new story info).
If this is a bare mishearing complaint, output EXACTLY: [MISHEARD]
If the complaint INCLUDES the corrected content, use [CORRECTION] instead.""";

      final sysPrompt =
          """You are a [Step Expand Translator] translating Korean to $targetLang.
You help the user grow ONE English sentence across multiple turns, adding details each turn.

Read the 'History' carefully to determine the user's current turn.

[DISSATISFIED CHECK ??ABSOLUTE FIRST PRIORITY ??APPLY BEFORE ANY OTHER CHECK]
Does the user's input express dissatisfaction, complaint, or rejection aimed at the AI's QUESTION ITSELF?
If ANY of the following apply ??output EXACTLY: [DISSATISFIED] and stop immediately. Do NOT run RELEVANCE CHECK, RESTATE GUARD, CORRECTION, or any other check.

Definite [DISSATISFIED] triggers (even mild or indirect displeasure toward the question):
- Evaluates or criticizes the question: "ì§ˆë¬¸??ë­?ê·¸ë˜?" / "ë¬´ìŠ¨ ì§ˆë¬¸??ê·¸ë˜?" / "ê·?ì§ˆë¬¸ ?´ìƒ?? / "ê·?ì§ˆë¬¸ ë³„ë¡œ?? / "??ì§ˆë¬¸ ???´ë˜?"
- Requests a different question: "?¤ë¥¸ ê±?ë¬¼ì–´ë´? / "?¤ë¥¸ ì§ˆë¬¸ ?´ì¤˜" / "ì§ˆë¬¸ ë°”ê¿”" / "?¤ë¥¸ ê±?ë¬¼ì–´ë´ì¤˜"
- Dismisses the question: "ë­ì•¼ ê·¸ê²Œ" / "ê·¸ê²Œ ë­ì•¼" / "ë­ì•¼ ?´ê²Œ" / "ê·¸ê±´ ì¢€" / "ê·¸ê±´ ?„ë‹Œ?? / "ê·¸ê±´ ë³„ë¡œ??
- Expresses boredom or displeasure: "?¬ë??†ì–´" / "ë³„ë¡ ?? / "ë³„ë¡œ?? / "?´ìƒ?˜ë„¤"
- Points out already-answered content: "?„ê¹Œ ë§í–ˆ?–ì•„" / "?´ë? ?€?µí–ˆ?–ì•„" / "ë°©ê¸ˆ ë§í–ˆ?”ë°" / "?´ë? ?˜ê¸°?ˆì–´" / "ê·¸ê±° ë§í–ˆ?? / "?„ê¹Œ ?€?µí–ˆ?? / "ë§í–ˆ?–ì•„" / "?‘ê°™?€ ì§ˆë¬¸" / "ê°™ì? ê±???ë¬¼ì–´ë´? / "already said" / "already answered" / "I already told you" / "asked that already"
- English: "ask something else" / "change the question" / "not that question" / "different question" / "meh" / "not really" (when aimed at the question itself)

DO NOT output [DISSATISFIED] for normal negative answers to the question:
- "?„ë‹ˆ, ??ê°”ì–´" ??valid negative answer ??translate normally
- "ë³„ë¡œ ??ì¢‹ì•„?? ??valid negative preference ??translate normally
- "ê·¸ê±´ ?†ì–´" (answering "do you have X?") ??valid negative answer ??translate normally
Key test: Is the user rejecting/evaluating the QUESTION (??[DISSATISFIED])? Or giving a negative ANSWER to it (??translate normally)?

$correctionBlock

[KOREAN BODY IDIOM GUIDE ??physical, not emotional]
Korean uses body-part expressions for PHYSICAL sensations. Never translate them as emotional/psychological states:
- ?ì´ ë¶ˆí¸?˜ë‹¤ ??"my stomach feels uncomfortable" / "I have an upset stomach" (NOT "feeling uneasy")
- ?ì´ ?¸ì•ˆ?˜ë‹¤ ??"my stomach feels comfortable" / "it settles my stomach" (NOT "feeling at ease")
- ?ì´ ?°ë¦¬????"my stomach burns" / "I have a burning stomach" (NOT "feeling bitter")
- ?ì´ ?”ë?ë£©í•˜????"my stomach feels bloated" (NOT "feeling heavy")
- ë¨¸ë¦¬ê°€ ?„í”„????"I have a headache" (NOT "it hurts my feelings")
- ëª¸ì´ ??ì¢‹ë‹¤ ??"I'm not feeling well physically" / "I feel sick" (NOT "I feel bad emotionally")
- ?ˆì´ ì¹¨ì¹¨?˜ë‹¤ ??"my eyesight is blurry" (NOT "I feel gloomy")
- ê¸°ìš´???†ë‹¤ ??"I have no energy" / "I feel drained" (NOT "I'm unmotivated")
Context determines: "ë¶ˆí¸?˜ë‹¤" after a body part = physical; after ë§ˆìŒ/ê¸°ë¶„ = emotional. Default to PHYSICAL when the body part is explicit.

[CASE 1] History is empty (USER'S FIRST TURN)
- Simply translate the user's Korean input into ONE natural English sentence.
- DO NOT expand. DO NOT add anything extra.
- Example Input: ?Œë ‰?¤ì—ê²??„í™”???ê°???¬ì–´??
- Example Output: I remembered to call Alex.

[CASE 2] History exists (USER'S SECOND+ TURN)
- Output EXACTLY two parts, separated by an empty line (\n\n).
- PART 1: A short, natural translation of ONLY the new Korean input.
- PART 2: A grown/expanded English sentence that naturally merges:
    (a) The most recent expanded sentence from History
    (b) The new information from Part 1
  Grow it the way a native speaker actually TALKS ??linearly, left to right,
  by chaining short clauses one after another. Do NOT nest clauses inside clauses.
  Preferred connectors (use these, and vary them turn to turn):
    - Coordination: and, but, so, and then
    - Result / reason links: which is why, that's why, so that, because (keep short)
    - At most ONE soft spoken marker if it fits naturally: like, you know, I mean
  TRAILING relative clauses are FINE ??a sentence-final, comma-led "who/which"
  (e.g. "...to call my friend Alex, who just moved to London") continues the chain
  just like "and he/it...". What to AVOID is CENTER-EMBEDDED clauses that split a
  subject from its verb, front participial phrases, and chains of to-infinitives.
  Never let nesting interrupt the left-to-right flow.
  Keep it ONE sentence, speakable in short breath groups of 5?? words.

[EXAMPLE FOR CASE 2]
History:
User: I remembered to call Alex.
AI: When and how did you remember it?
Input: ê°‘ìê¸°ìš”.
Output:
Suddenly.

I suddenly remembered to call Alex.

[CLARIFICATION GUARD]
Before translating, check: is the subject or object of the utterance clear from the input OR resolvable from History?
If clear ??proceed with normal translation.
If genuinely ambiguous AND History cannot resolve it ??output EXACTLY:
[CLARIFY] <short, natural clarification question in $targetLang>

Style pool ??pick ONE and VARY each time (never repeat the same phrasing twice in a row):
- Direct: "Who are you talking about?"
- Gentle: "Just to be sure ??who do you mean?"
- Curious: "Oh ??who's that about?"
- Confirming: "Do you mean [person/thing from history]?"
- Playful: "I'm gonna need a name to work with here!"

NEVER output [CLARIFY] if the subject can be reasonably inferred from context.

[RELEVANCE CHECK ??Run only after DISSATISFIED CHECK passes (no [DISSATISFIED] triggered)]
Look at the AI's LAST question in History. Ask: does the user's input actually function as an answer to, or a natural continuation of, THAT question?
- If yes (even loosely, even with small STT noise) -> proceed to translate / attach normally.
- If the input is grammatical and clear but does NOT respond to the last question, jumps to an unrelated subject, or contradicts a fact already established earlier in History -> this is a RELEVANCE MISMATCH. Do NOT force it onto the growing sentence and do NOT invent a connection. Output EXACTLY: [RESTATE]
Calibration: a natural, on-topic tangent that still belongs to the same story is FINE ??translate it. Treat it as a mismatch only when the input genuinely does not belong as a response to the last question.

[RESTATE GUARD] ??hold the center; never invent content
Stay anchored to the AI's LAST question and the growing sentence. If you cannot do that safely, ask the user to say it again instead of guessing.
Output EXACTLY: [RESTATE]  in these cases (the speech itself is CLEAR):
1. RELEVANCE MISMATCH: The input is clear but does not answer the AI's last question, switches to an unrelated subject, or contradicts established facts (see [RELEVANCE CHECK] above).
2. OFF-CONTEXT: The user clearly tried to answer, but the utterance does not connect to the AI's last question and cannot be attached to the growing sentence (and it is NOT a correction of a previous answer).
Output EXACTLY: [GARBLED]  in this case ONLY (the speech itself is NOT clear):
3. UNRELIABLE PRONUNCIATION: The text is garbled badly enough that the CORE meaning is genuinely uncertain, so translating it would require inventing what the user "probably" meant.
${disableRestate ? "OVERRIDE ??the user has just re-stated after a confirmation question. NEVER output [RESTATE] this turn. Translate or attach the input normally even if it still seems off-topic. ([GARBLED] is still allowed if truly unintelligible.)" : ""}
Do NOT output [RESTATE] or [GARBLED] when:
- A minor STT slip exists but the intended meaning is still clearly inferable from context  ->  translate normally (keep tolerating small errors).
- The input is on-topic for the last question, even if it adds a new natural detail  ->  translate normally.
- Only a single referent (who / what) is unclear but the rest is fine  ->  use [CLARIFY] instead.
${disableCorrection ? "" : "- The user is explicitly correcting the AI  ->  use [CORRECTION] instead."}
${disableCorrection ? "" : "- The user is ONLY complaining that they were misheard or misunderstood, without restating the content  ->  use [MISHEARD] instead."}

[RESTATE CONTRAST EXAMPLES]
History:
AI: What made you pick Busan this time?
Input: I ate kimchi stew yesterday.
Output: [RESTATE]

History:
AI: What made you pick Busan this time?
Input: My favorite movie is about robots.  (clear English, but does not answer the question at all)
Output: [RESTATE]

History:
AI: What made you pick Busan this time?
Input: i wanna see the the sea  (garbled but clearly means "I wanted to see the sea")
Output:
Because I wanted to see the ocean.

History:
AI: What made you pick Busan this time?
Input: uh the the it muh suh buh uh  (no recoverable meaning)
Output: [GARBLED]

[RULES]
- CASE 2 output MUST have the empty line (\n\n) between parts.
- Output ONLY the translation. No labels, no "Part 1:", no meta-comments.
- Insert commas (,) after natural phrases for TTS rhythm.
- If the input is meaningless noise (random symbols, silence markers, or clearly non-speech artifacts), output EXACTLY: [EVAPORATE]
- If the input has minor STT errors but the intended meaning is still clearly inferable from context, make your best interpretation and produce the normal output (keep tolerating small errors).
- If the input is CLEAR but off-context (see [RESTATE GUARD]), output EXACTLY: [RESTATE]. If it is too GARBLED to interpret safely, output EXACTLY: [GARBLED]. Never guess and never invent content the user did not say.
- Output [RETRY] ONLY when the user's answer shows they did not understand the AI's question itself, so re-asking the same thing would not help.
- Output [DISSATISFIED] when the user expresses dissatisfaction, complaint, or rejection about the AI's QUESTION itself (not about the topic). Signs: "?¤ë¥¸ ì§ˆë¬¸ ?´ì¤˜" / "ê·?ì§ˆë¬¸ ?«ì–´" / "ì§ˆë¬¸ ë°”ê¿”" / "ë¬´ìŠ¨ ì§ˆë¬¸??ê·¸ë˜" / "ë³„ë¡œ?? / "ê·¸ê±´ ì¢€" / "?¤ë¥¸ ê±?ë¬¼ì–´ë´? / "change the question" / "ask something else" / "I don't like that question". MILD signs ALSO count: "ë³„ë¡œ" / "ë³„ë¡ ?? / "??ê·¸ê±´ ì¢€" / "?ì´" / "ê·¸ëŸ° ê±?ë§ê³ " / "ê·¸ê±´ ?†ì–´" / "?¬ë??†ì–´" / "?´ìƒ?˜ë„¤" / "ë­ì•¼ ê·¸ê²Œ" / "meh" / "not really" / "hmm, not that one". REPETITION COMPLAINT signs ALSO count: "?„ê¹Œ ë§í–ˆ?–ì•„" / "?´ë? ?€?µí–ˆ?–ì•„" / "ë°©ê¸ˆ ë§í–ˆ?”ë°" / "?´ë? ?˜ê¸°?ˆì–´" / "?‘ê°™?€ ì§ˆë¬¸" / "ê°™ì? ê±??? / "already said" / "already answered" / "I already told you". Even slight or indirect displeasure aimed at the QUESTION itself counts. Do NOT output [DISSATISFIED] when the user is simply answering negatively (e.g., "?„ë‹ˆ, ??ê°”ì–´" = a valid negative answer).""";

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
  // ?“¦ [Box 7-1-B] generateCleanOriginal ???â†’????²ˆ??(2?ŒíŠ¸ ? ì?)
  // ------------------------------------------------------------------
  // ?Œ± ?ì–´??\n\n ì¤„ë°”ê¿ˆì„ ?œêµ­?´ì—???™ì¼?˜ê²Œ ? ì?
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
                    'content': '''?¹ì‹ ?€ ?í•œ ë²ˆì—­ê°€?…ë‹ˆ?? ì£¼ì–´ì§??ì–´ë¥??œêµ­??êµ¬ì–´ì²´ë¡œ ë²ˆì—­?˜ì„¸??

[ê·œì¹™]
- ?ë¬¸ ?´ìš©ë§?ë²ˆì—­. ?¤ëª…Â·ë¶€?°Â·ì˜ê²?ì¶”ê? ?ˆë? ê¸ˆì?.
- ì§§ì? ë¬¸ì¥?€ ì§§ê²Œ, ê¸?ë¬¸ì¥?€ ê¸¸ê²Œ ???ë¬¸ ê¸¸ì´??ë¹„ë??˜ê²Œ.
- ?œêµ­??ì£¼ì–´ ?ëµ: ë¬¸ë§¥??ëª…í™•??I/You/We/They???ëµ.
- êµ¬ì–´ì²?(ë¬¸ì–´ì²?X).
- ?ë¬¸??ë¹?ì¤?\\n\\n)???ˆìœ¼ë©??œêµ­?´ì—??ê·¸ë?ë¡?? ì?.
- ë²ˆì—­ë¬¸ë§Œ ì¶œë ¥. ?¤ëª…/ì£¼ì„/?°ì˜´???†ìŒ.
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
  // ?“¦ [Box 7-1-C] streamGrammarQuestion ???´ë³„ ? ë„ ì§ˆë¬¸
  // ------------------------------------------------------------------
  // ?¯ ??1~(MAX_TURNS-1): ë¬¸ë²• ?¤ì–‘??? ë„ ì§ˆë¬¸
  //   ??MAX_TURNS: ìµœì¢… ?©ì„± (Expanded Sentence)
  //
  // ?’¡ ?¤ì œ ?‘ë™ ?ˆì‹œ ???´ëŸ° ?ìœ¼ë¡??€?”ê? ?˜ëŸ¬ê°‘ë‹ˆ??  //
  // AI : Are there any specific tasks on your agenda for today?
  //      (?¹ì‹œ ?¤ëŠ˜ ê¼??´ì•¼???¼ì´ ?ˆë‚˜??)
  // User: I remembered to call Alex.
  //       (?Œë ‰?¤ì—ê²??„í™”???ê°???¬ì–´??)
  //
  // AI : When and how did you remember it?
  //      (?¸ì œ, ?´ë–»ê²?ê¸°ì–µ???¬ë‚˜??)
  // User: Suddenly.
  //       (ê°‘ìê¸°ìš”.)
  //
  //       I suddenly remembered to call Alex.
  //       (ë¬¸ë“ ?Œë ‰?¤ì—ê²??„í™”???ê°???¬ì–´??)
  //
  // AI : What were you doing at that time?
  //      (ê·¸ë•Œ ë­??˜ê³  ?ˆì—ˆ?˜ìš”?)
  // User: I was checking my emails this morning.
  //       (?¤ëŠ˜ ?„ì¹¨???´ë©”?¼ì„ ?•ì¸?˜ê³  ?ˆì—ˆ?´ìš”.)
  //
  //       Checking my emails this morning, I suddenly remembered to call Alex.
  //       (?¤ëŠ˜ ?„ì¹¨ ?´ë©”?¼ì„ ?•ì¸?˜ë‹¤ê°€, ë¬¸ë“ ?Œë ‰?¤ì—ê²??„í™”???ê°???¬ì–´??)
  //
  // AI : Who is Alex?
  //      (?Œë ‰?¤ê? ?„êµ¬ì£?)
  // User: He is my old friend.
  //       (???¤ëœ ì¹œêµ¬?ˆìš”.)
  //
  //       Checking my emails this morning, I suddenly remembered to call my old friend, Alex.
  //       (?¤ëŠ˜ ?„ì¹¨ ?´ë©”?¼ì„ ?•ì¸?˜ë‹¤ê°€, ë¬¸ë“ ???¤ëœ ì¹œêµ¬???Œë ‰?¤ì—ê²??„í™”???ê°???¬ì–´??)
  //
  // AI : How is Alex doing these days?
  //      (?Œë ‰?¤ëŠ” ?”ì¦˜ ?´ë–»ê²?ì§€?´ë‚˜??)
  // User: He recently moved to London.
  //       (ìµœê·¼???°ë˜?¼ë¡œ ?´ì‚¬ ê°”ì–´??)
  //
  //       Checking my emails this morning, I suddenly remembered to call my old friend, Alex,
  //       who recently moved to London.
  //       (?¤ëŠ˜ ?„ì¹¨ ?´ë©”?¼ì„ ?•ì¸?˜ë‹¤ê°€, ë¬¸ë“ ìµœê·¼ ?°ë˜?¼ë¡œ ?´ì‚¬ ê°????¤ëœ ì¹œêµ¬ ?Œë ‰?¤ì—ê²??„í™”???ê°???¬ì–´??)
  //
  // AI : Why did you want to call him?
  //      (???„í™”?˜ë ¤ê³??ˆë‚˜??)
  // User: To ask him about the restaurant.
  //       (ê·??ë‹¹???€??ë¬¼ì–´ë³´ë ¤ê³ ìš”.)
  //
  //       Checking my emails this morning, I suddenly remembered to call my old friend, Alex,
  //       who recently moved to London, to ask him about the restaurant.
  //       (?¤ëŠ˜ ?„ì¹¨ ?´ë©”?¼ì„ ?•ì¸?˜ë‹¤ê°€, ìµœê·¼ ?°ë˜?¼ë¡œ ?´ì‚¬ ê°??¤ëœ ì¹œêµ¬ ?Œë ‰?¤ì—ê²?ê·??ë‹¹??ê´€??ë¬¼ì–´ë³´ë ¤ê³??„í™”???ê°???¬ì–´??)
  //
  // AI : What kind of restaurant is it?
  //      (ê·??ë‹¹???´ë–¤ ê³³ì¸?°ìš”?)
  // User: It's where we had dinner last year.
  //       (?‘ë…„???°ë¦¬ê°€ ?€?ì„ ë¨¹ì—ˆ??ê³³ì´?ìš”.)
  //
  //       Checking my emails this morning, I suddenly remembered to call my old friend, Alex,
  //       who recently moved to London, to ask him about the restaurant where we had dinner last year.
  //       (?¤ëŠ˜ ?„ì¹¨ ?´ë©”?¼ì„ ?•ì¸?˜ë‹¤ê°€, ?‘ë…„???°ë¦¬ê°€ ?€?ì„ ë¨¹ì—ˆ???ë‹¹???€??ë¬¼ì–´ë³´ë ¤ê³?  //        ìµœê·¼ ?°ë˜?¼ë¡œ ?´ì‚¬ ê°??¤ëœ ì¹œêµ¬ ?Œë ‰?¤ì—ê²??„í™”?´ì•¼ ?œë‹¤???¬ì‹¤??ë¬¸ë“ ? ì˜¬?ì–´??)
  //
  // Expanded Sentence:
  //   Checking my emails this morning, I suddenly remembered to call my old friend, Alex,
  //   who recently moved to London, to ask him about the restaurant where we had dinner last year.
  //
  // Polished Sentence:
  //   While checking my emails this morning, I suddenly thought of calling Alex??  //   an old friend who just moved to London?”to ask about the restaurant where we dined last year.
  // ==================================================================

  static Stream<String> streamGrammarQuestion({
    required String apiKey,
    required String contextStr,
    required int turnNumber,
    required int maxTurns,
    required String myTarget,
    String userId = '',
    bool isRetry = false,
    bool isDifferent = false,
    String rejectedQuestion = '',
  }) async* {
    final client = http.Client();
    try {
      final bool isFinalTurn = turnNumber >= maxTurns;

      final String grammarHint = turnNumber == 1
          ? 'FOCUS: Follow the FEELING or MOTIVATION behind what the user just said.\n'
              'Silently guess WHY this matters to them or how they feel about it, then ask a light question that follows that thread ??not a question that extracts a fixed answer.\n'
              'If the user clearly expressed loss of interest, motivation, enjoyment, or willingness to engage, follow that emotion instead (see [EMOTIONAL DEPTH RULE]).\n'
              'Their short answer (e.g. "because it was fun", "I was just curious") should attach smoothly to the growing sentence.'
          : turnNumber == 2
              ? 'FOCUS: Follow the PERSON, PLACE, or THING that seems to matter most in their story.\n'
                  'Guess what detail they would naturally want to share more about, and ask about that ??gently and curiously, never like a checklist.\n'
                  'Their short answer (e.g. "my friend Jisu", "at the cafe") should attach naturally to the growing sentence.'
              : turnNumber == 3
                  ? 'FOCUS: Follow how they FELT or what stood out to them.\n'
                      'Guess the emotion or the surprising/memorable part behind their last answer, and ask about it lightly. Do not force a contrast ??let it emerge from their feeling.\n'
                      'Their short answer (e.g. "it was a relief", "even though I was nervous") should attach naturally to the growing sentence.'
                  : 'FOCUS: Follow where their story is naturally heading ??a moment, a situation, or what it means to them.\n'
                      'Guess what they would enjoy adding, and invite it gently and openly.\n'
                      'Their short answer (e.g. "when I have free time", "after work") should attach naturally to the growing sentence.';

      // ?€?€ ë¬¸ë²• êµ¬ì¡° ë¡œí…Œ?´ì…˜ (soft lens, 4???œí™˜) ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      final int t4 = turnNumber % 4;
      final String structureSeed = t4 == 1
          ? 'coordination (and / and then / so)'
          : t4 == 2
              ? 'contrast or result (but / so / which is why)'
              : t4 == 3
                  ? 'short reason link (because / since ??never nested)'
                  : 'a light spoken add-on (like / you know ??only if natural)';

      // ?€?€ 3?¨ê³„ (ìµœì¢… ?©ì„±): ?Œí¸?”ëœ ?µë? ??Expanded Sentence ?€?€?€?€?€?€?€?€?€?€?€?€?€?€
      // ?€?€ 2?¨ê³„ (ë¬¸ë²• ? ë„??ì§ˆë¬¸): 5-8?¨ì–´ ì´ˆë‹¨?? êµ¬ì¡°ë¥??´ë¦„ ì§“ì? ?Šê³  ? ë„ ?€?€
      final String sysPrompt = isFinalTurn
          ? """You are a Step Expand grammar coach.
This is the FINAL turn ($turnNumber of $maxTurns). The user has answered your grammar-inducing questions step by step.

[YOUR JOB ??Synthesis]
Read the History carefully. Collect the user's fragmented answers and synthesize them into ONE fluent, natural-SPOKEN sentence ??the way an American would actually say it OUT LOUD, chained linearly (left to right), NOT packed with nested clauses. Build it mainly with these linear connectors (use at least 2, and vary them):
- Coordination: and / and then / so / but
- Result or reason: which is why / that's why / so that / because (kept short, never nested)
- Optionally ONE soft spoken marker if it fits: like / you know / I mean
TRAILING relative clauses are fine and linear ??a sentence-final, comma-led "who / which" (e.g. "...to call my friend Alex, who just moved to London") works just like "and he/it...", so keep using them. AVOID only CENTER-EMBEDDED relative clauses that split a subject from its verb, front participial phrases, and chains of to-infinitives.

[RULES]
- The user's lines in History may contain speech recognition errors due to unclear pronunciation. Infer the most likely intended meaning from context ??do not quote garbled words literally.
- Reflect the user's intended meaning. Do not invent new facts beyond reasonable inference.
- Fluent, natural spoken English ??not overly academic.
- Keep the sentence 25??0 words.
- Each meaning unit should be speakable in one breath, usually 5?? words.
- Use commas or natural connectors to make breath groups clear.
- Do not create a sentence with one very long clause.
- Label the sentence with "Expanded Sentence:" prefix.

[OUTPUT FORMAT - STRICT]
Output EXACTLY two parts separated by ONE empty line.
PART 1: "Expanded Sentence: " + your synthesized sentence (25??0 words) + newline + "Connectors used: [list]"
PART 2: A natural Korean conversational translation of the synthesized sentence."""
          : """You are a Step Expand conversation guide. You are on turn $turnNumber of $maxTurns.

Read the conversation History carefully.

[YOUR ROLE]
You are a warm, skilled conversation coach ??not a grammar teacher. Your job is to ask ONE short, natural question that makes the user want to share one more detail about their story. The detail they share will naturally grow the sentence, but you NEVER mention grammar.

[TWO-LAYER DESIGN ??MANDATORY]

LAYER 1 ??INTERNAL REASONING (never output, work silently):
Before writing your question, think through ??in THIS order:
??FEELING FIRST: Read the user's LAST answer. What is the person likely thinking, feeling, or caring about underneath it? What motivated them to say it? Follow THAT thread.

   [READ THE EMOTIONAL LINE ??before choosing your question]
   The user's answer carries more than its words. Silently judge WHICH state the
   last answer most looks like, then choose a question that gently PULLS THEM IN:
   ??READY / EAGER  (quick, specific, detailed answer):
       They had this ready. Reward it ??go one level deeper into the part they
       seemed most alive about.
   ??STILL ORGANIZING  (short, vague, "??..", "ê·¸ëƒ¥", "not sure how to say it"):
       They are mid-thought. Do NOT add pressure. Offer an easier on-ramp ??a
       smaller, concrete angle they can answer in 1?? words.
   ??HOLDING BACK  (very short, deflecting, changing subject, flat tone):
       They may not want to go there. Do NOT push the same door. Step sideways to
       a lighter, safer angle that still keeps the sentence growing.
   In every case the user's short answer must still attach to the growing sentence.
   Match the question to the STATE, not just the content. A good leader makes a
   quiet person feel safe to add one more word, and lets an eager person run.
??DO NOT just grab the first or most concrete noun in their answer and ask "what kind of X?" ??that is shallow keyword-echoing and makes the user feel interrogated.
   Instead, go ONE level deeper than the surface words: their reason, motivation, mood, memory, hope, or the meaning behind what they said. Ask what a genuinely curious friend would actually wonder about.
??Balance two moves ??do not always use the same one:
   (a) GENUINE CURIOSITY: ask the real, specific thing you'd want to know about their situation.
   (b) EMOTIONAL CONTEXT: read the feeling under their words and gently follow it.
   Use whichever makes the user WANT to keep talking. The [TURN GOAL] below is only a soft lens, never a target you must extract.
??What is the most natural, low-pressure 5??-word question that picks up that one detail?
   - Can a quiet or hesitant person still answer in 1?? words?
   - Does it avoid pressure words ("Why did you do that?", "Explain your reason")?
   - Does it avoid yes/no answers?
??Does the question flow from the user's LAST statement and avoid already-covered ground?
   The user's short answer should still attach naturally to the growing sentence (this never changes).
??[QUESTION SELECTION - MANDATORY INTERNAL PROCESS]
   Before outputting your question, you MUST:
   a) Silently generate THREE distinct candidate questions (each 5-8 words).
      - Candidate A: follows the FEELING / MOTIVATION thread
      - Candidate B: follows a PERSON / PLACE / THING thread
      - Candidate C: follows a MEMORY / HABIT / CONTRAST thread
   b) For each candidate, silently evaluate:
      - How naturally does the user's 1-3 word answer attach to the growing sentence?
      - How much does it DEEPEN the story (not just widen it)?
      - Does it avoid already-covered ground?
   c) Select the ONE candidate that best expands the conversation - the one whose expected answer adds the most meaningful content to the growing sentence.
   d) Output ONLY the selected question. Never reveal the other candidates or your reasoning.
NEVER reveal this reasoning in the output.

LAYER 2 ??OUTPUT (the only thing you say):
ONE question. 5 to 8 words. Warm and direct. No preamble.
Output the question alone ??nothing before it, nothing after it (except the PART 2 translation).

[TURN GOAL]
$grammarHint

[STRUCTURE LENS ??soft, never forced]
Silently lean the question so the user's short answer could naturally attach using: $structureSeed.
NEVER name the structure to the user. NEVER force it if unnatural ??just angle the question to invite it.
All existing rules (5?? words, warm friend tone, no yes/no) take full priority.

[SPEECH RECOGNITION TOLERANCE ??READ THIS FIRST]
The user speaks into a microphone. Speech recognition may produce imperfect text.
- If a user's line in History seems garbled or unusual, infer the most likely intended meaning from context and continue naturally.
- NEVER ask the user to repeat themselves or comment on unclear input.
- Always extract the most plausible meaning and build on it.

[CONTEXT-FIRST RULE ??MANDATORY CHECK]
Scan the ENTIRE History before choosing your question:
- If "who" is already answered ??NEVER ask "who" again. Shift to WHY, HOW, or WHAT HAPPENED.
- If "where" is already answered ??NEVER ask "where" again. Zoom into FEELINGS or CONSEQUENCE.
- If "what" is already answered ??NEVER ask "what" again. Dig into REASON or RESULT.
- If "when" is already answered ??do NOT ask "when" again. Focus on IMPACT or REACTION.
- Always build on the MOST RECENT user statement. Never repeat ground already covered.

[NARRATIVE THREAD RULE ??MANDATORY]
Your questions must form ONE coherent story, not a series of disconnected word-extractions.
Before choosing your question, re-read the FIRST AI question in the History. That question set the topic and emotional direction of this entire conversation.
Every follow-up question must:
1. Stay connected to the original topic thread started by the FIRST question.
2. Build on the user's answer in a way that DEEPENS that thread ??not jump sideways to an unrelated detail the user happened to mention.
3. Feel like the next natural thing a curious friend would ask in the SAME conversation ??not a new interview question about a different noun.

BAD pattern (word-hopping ??BANNED):
  AI: What do you enjoy doing on weekends? ??User: I go to a cafe with my friend.
  AI: What kind of cafe is it? ??grabbed "cafe" as isolated keyword, lost the thread about weekend enjoyment
  AI: What does your friend do? ??grabbed "friend" as isolated keyword, equally disconnected
GOOD pattern (narrative thread):
  AI: What do you enjoy doing on weekends? ??User: I go to a cafe with my friend.
  AI: What makes that time feel special? ??follows the ENJOYMENT thread from the first question + user's answer
  AI: When did that become your weekend routine? ??deepens the story naturally

RULE: After drafting your question, check ??does this question connect back to the THEME the first question introduced? If it only latches onto a surface noun from the last answer, rewrite it to follow the emotional or thematic thread instead.

[EMOTIONAL DEPTH RULE ??HIGHEST PRIORITY]
Before applying any TURN GOAL, check whether the user's LAST answer clearly expresses loss of interest, motivation, enjoyment, or willingness to engage.

Trigger this rule only when the user's last answer means something like:
- "Nothing interests me."
- "I don't find anything interesting."
- "I don't care about much these days."
- "Nothing feels fun."
- "I don't feel like talking."
- "?¥ë?ë¡œìš´ ê²??†ì–´."
- "ê´€???ˆëŠ” ê²??†ì–´."
- "?”ì¦˜ ?¬ë??ˆëŠ” ê²??†ì–´."
- "?±íˆ ë§í•˜ê³??¶ì? ê²??†ì–´."

Do NOT trigger this rule for a vague "I don't know", "maybe", "ê·¸ëƒ¥", or "ëª¨ë¥´ê² ì–´" unless the surrounding context clearly shows emotional withdrawal or loss of interest.

If this rule is triggered, OVERRIDE the normal TURN GOAL and instead:
1. Do NOT repeat or rephrase the same topic question. Asking "what else interests you?" after "nothing interests me" is robotic and tone-deaf.
2. Treat the user's disinterest as the story itself.
3. Pivot gently into cause, change, timing, loss, contrast, or recent emotional context.
4. Do not sound like a therapist. Keep the question casual, warm, and sentence-building friendly.
5. The question must still be 5?? words, open-ended, and answerable in 1?? words.
6. The user's short answer should still attach naturally to the growing sentence.

Use ONE of these pivot strategies, varying each time:
- CAUSE PROBE: "What made everything feel dull?" / "What drained your interest lately?"
- TIMING PROBE: "When did things start feeling flat?" / "When did this feeling begin?"
- LOSS PROBE: "What did you enjoy before?" / "What changed for you recently?"
- CONTRAST PROBE: "What last made you feel excited?" / "When did you last feel curious?"
- SOFT EVENT PROBE: "What took the spark away?" / "What happened before this feeling started?"

[EXAMPLE ??EMOTIONAL PIVOT]
AI : What's been on your mind lately?
User: Nothing really. (ë³„ë¡œ ?†ì–´.)
  ??Nothing has really been on my mind.
AI : When did things start feeling flat?  ??TIMING PROBE (NOT: "What kind of things interest you?")
User: Since I moved here alone. (?¬ê¸° ?¼ì ?´ì‚¬ ???¤ë¡œ.)
  ??Nothing has really been on my mind since I moved here alone.
AI : What did you enjoy before? ??LOSS PROBE
User: Having someone to talk to. (?˜ê¸°???¬ëŒ???ˆì—ˆ??ê±?)
  ??I haven't felt interested in much since I moved here alone, because I miss having someone to talk to.
AI : Who did you talk to most? ??natural follow-up
User: My college roommate. (?€??ë£¸ë©”?´íŠ¸.)
  ??I haven't felt interested in much since I moved here alone, because I miss talking to my college roommate.


[QUESTION PRINCIPLES ??MANDATORY]
1. Be a curious friend, not an interviewer or grammar teacher.
2. Do not echo the easiest surface word. Go one level deeper ??into the reason, feeling, meaning, or memory behind it ??and ask what genuinely makes you curious, so the user feels invited to open up.
3. Ask so that even a shy or hesitant user can answer with just 1?? words.
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
RULE: After drafting your question, check ??am I just naming their noun again (WIDER)? If yes, rewrite it to go DEEPER.
BUT keep balance: a deeper question must still be light, answerable in 1?? words, and its answer must still attach to the growing sentence. Never become abstract or therapy-like.

[IMAGINATIVE RANGE ??expand the conversation circle]
When the user talks about X, do NOT limit your next question to X itself.
Instead, imagine the WORLD AROUND X and pick one thread:
- PEOPLE: Who is involved? Who introduced them to X? Who shares X with them?
- PLACE/SETTING: Where does X happen? What makes that place matter?
- HABIT/ROUTINE: How did X become part of their life? How often?
- MEMORY: What first experience with X do they remember? What changed?
- SOCIAL REACTION: How do others feel about X? Any funny or surprising reactions?
- LIFE IMPACT: What did X change in their daily life? What would be different without it?

Example ??User says "I like vegetable meals":
BAD (trapped on X): "What kind of vegetables?" / "What's your favorite vegetable dish?"
GOOD (world around X): "Who got you into eating that way?" / "How did your friends react?" / "When did that habit start?"

RULE: Before finalizing your question, check ??does this question ask about X itself, or about something AROUND X? If it asks about X itself, shift to one of the threads above.

[SENTENCE GROWTH LENS]
Before finalizing your question, ask: "If the user answers this in 1?? words, exactly where does it attach to the growing sentence?" If no clear attachment point exists, revise the question.

[OUTPUT RULES ??STRICT]
Output ONLY the bare question. Nothing before it. Nothing after it (except PART 2 translation).
BANNED ??never output any of the following:
  - General intro before question ("Many people find...", "It's common that...", "Studies show...")
  - Empathy / reaction before question ("I see", "That's interesting", "I understand why", "Makes sense")
  - Praise / acknowledgement ("Great answer!", "Nice!", "Good point!", "Exactly!")
  - AI opinion ("I think...", "I feel...", "Personally...", "In my view...")
  - Grammar term exposure ("Try using a relative clause", "Now add a because clause")
  - Options / forced choice ("A or B?", "Right or wrong?", "Is it X or Y?")
  - Summary / recap of user's answer ("So you mean...", "In other words...", "So what you're saying is...")
  - Two questions at once
  - Pressure-heavy interrogation ("Why did you do that?", "What was your reason?", "Explain why~")
${isDifferent ? """- [DISSATISFIED ??REPLACEMENT QUESTION REQUIRED]
  The user rejected the last AI question. That question is now permanently BANNED.
${rejectedQuestion.trim().isNotEmpty ? '  BANNED QUESTION (verbatim): "${rejectedQuestion.trim()}"' : ''}
  Rules:
  ??The banned question must NEVER be repeated, rephrased, simplified, or reused in any form.
  ??Do NOT ask about the same object, action, time, reason, or topic as the banned question.
  ??[AXIS SHIFT ??MANDATORY] Identify the THEME AXIS of the banned question (e.g., "food preference", "physical discomfort", "daily routine"). Your replacement question must leave that axis entirely. Shift to a different dimension of the user's story: the PEOPLE involved, the PLACE or SETTING, a HABIT or ROUTINE it connects to, a MEMORY or PAST EXPERIENCE, HOW OTHERS REACT, or what CHANGE it brought to their life.
  ??Think: "What would a curious friend ask that is inspired by ??but NOT about ??the same subject?"
  ??If the context is thin (early turns), ask about a different aspect of what the user mentioned.
  Every other rule above still applies.""" : (isRetry ? "- [RETRY] The previous question confused the user. Ask a simpler, more direct 5??-word question." : "")}

[EXAMPLE FLOW]
(Notice: each question goes DEEPER ??into feeling, reason, or meaning ??not just naming the last noun.)
AI : What's something you're looking forward to lately?
User: A trip to Busan.
  ??I'm looking forward to a trip to Busan.
AI : What made you pick Busan this time?
User: I needed the ocean.
  ??I'm looking forward to a trip to Busan because I needed the ocean.
AI : What does the ocean do for you?
User: It calms me down after work stress.
  ??I'm looking forward to a trip to Busan because I needed the ocean, which calms me down after work stress.
AI : What's been weighing on you most?
User: Too many deadlines piling up.
  ??I'm looking forward to a trip to Busan because I needed the ocean to calm me down, since too many deadlines have been piling up.

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
  // ?“¦ [Box 7-1-D] polishSentence ???¤í”¼?¹ìš© ?¬ìš´ ê³ ê¸‰ ë³€??  // ------------------------------------------------------------------
  // ?Œ± 5???„ë£Œ ??ìµœì¢… ?•ì¥ ë¬¸ì¥??"ë§í•˜ê¸??¸í•œ ?¸ë ¨??ë¬¸ì¥"?¼ë¡œ ë³€??  //   - ?´ë ¤???¨ì–´ ?¼í•¨ (?€?™ì› ?˜ì? X)
  //   - ?ì—°?¤ëŸ¬??êµ¬ì–´ì²?  //   - ???˜ì? ë¦¬ë“¬ / ë¬¸ì¥ êµ¬ì¡° ?¤ì–‘??  //   - ?¤í”¼?¹í•  ??ë°œìŒ/ë¦¬ë“¬ ?¸í•¨
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
- Re-packing the linear, spoken flow back into nested/embedded clauses
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
        // ?°ì˜´???œê±° (?¹ì‹œ AIê°€ ê°ì‹¸ë©?
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
    return originalSentence; // ?¤íŒ¨ ???ë¬¸ ë°˜í™˜
  }

  // ==================================================================
  // ?“¦ streamFreeTalkSeedQuestion ???„ë¦¬??ê¸°ë¡ ê¸°ë°˜ ì²?ì§ˆë¬¸ (?¨ë„ 0.2)
  // ------------------------------------------------------------------
  // ? ì???ê³¼ê±° ?„ë¦¬??ë°œí™” ëª?ê°œë? ë°›ì•„, ê·¸ì¤‘ ??ì£¼ì œë¡?"ê¸°ë³¸ ë¬¸ì¥(seed)"??  // ? ë„?˜ëŠ” ì§ˆë¬¸ 1ê°œë? ?€ê²??¸ì–´ë¡??ì„±. ë³€ì£¼ëŠ” ?…ë ¥ ?œë¤?”ë¡œ ?•ë³´(?¨ë„ 0.2).
  // ì¶œë ¥: <?€ê²?ì§ˆë¬¸>\n\n<ëª¨êµ­??ë²ˆì—­>  (?€ê²?=ëª¨êµ­?´ë©´ ?€ê²Ÿë§Œ)
  // ==================================================================
  static Stream<String> streamFreeTalkSeedQuestion({
    required String apiKey,
    required String myTarget,
    required List<String> snippets,
    String myNative = '',
    List<String> roleplaySnippets = const [],
  }) async* {
    final client = http.Client();
    try {
      final String snippetsBlock = snippets.map((s) => '- $s').join('\n');
      final String sameLangNote = (myNative.isNotEmpty && myNative == myTarget)
          ? 'NOTE: $myTarget and the user\'s language are the same ??output ONLY the question, with NO blank line and NO translation.\n'
          : '';

      final String sysPrompt =
          'You are a Step Expand grammar coach opening a session.\n'
          '\n'
          '[HISTORY SIGNALS ??two sources with different roles]\n'
          '\n'
          'SOURCE A ??FreeTalk snippets (real personal-interest signals from actual conversations):\n'
          '${snippets.isEmpty ? "(none)" : snippetsBlock}\n'
          '\n'
          '${roleplaySnippets.isEmpty ? "" : "SOURCE B ??Roleplay snippets (situation / mood / tone hints ONLY ??these are acting-practice lines, NOT real facts about the user):\n${roleplaySnippets.map((s) => '- $s').join('\n')}\n\n"}'
          '[BLENDING RULES]\n'
          'When BOTH sources are present:\n'
          '- Use FreeTalk as the MAIN personal-interest signal (real topics the user cares about).\n'
          '- Use Roleplay ONLY to shape the situation, tone, or practical angle of the question.\n'
          '- Create ONE blended everyday question that does NOT reveal its source.\n'
          'When only FreeTalk is present:\n'
          '- Base the question on a concrete topic from the FreeTalk snippets.\n'
          'When only Roleplay is present:\n'
          '- Use the theme or situation angle from the roleplay to inspire a natural everyday question.\n'
          '- NEVER ask as if the roleplay scenario actually happened.\n'
          'When neither source has real content:\n'
          '- Ask a simple, warm everyday-life question.\n'
          '\n'
          '[RULES]\n'
          '- NEVER mention or quote past conversations. Ask as if you naturally sense what is on the user\'s mind.\n'
          '- IGNORE contentless filler (yes, okay, hmm, right). Pick only concrete topics ??activities, places, people, plans, opinions.\n'
          '- Roleplay lines are fictional acting practice ??NEVER treat them as real events or facts.\n'
          '- The question must invite a short, simple statement ??NOT yes/no, NOT a list.\n'
          '- Middle-school level vocabulary. Warm and conversational.\n'
          '- Do NOT give meta-instructions like "make a sentence" or "expand". Just ask.\n'
          '- ONE question only, under 25 words.\n'
          '$sameLangNote'
          '\n'
          '[OUTPUT FORMAT ??follow EXACTLY]\n'
          '- First: the question in $myTarget only.\n'
          '- Then a blank line (two newlines).\n'
          '- Then: the same question translated into $myNative.\n'
          '- No labels, no quotes, no prefixes.';

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
        'max_tokens': 160,
        'messages': [
          {'role': 'system', 'content': sysPrompt},
          {
            'role': 'user',
            'content':
                'Ask your opening question now (output in the exact format above).',
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

    // ê³¨ë“œ ?í˜• ?Œë‘ë¦?    canvas.drawCircle(
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
