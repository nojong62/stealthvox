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

import 'dart:ui';
import 'dart:ui' as ui;
import '/auth/firebase_auth/auth_util.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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
import 'package:share_plus/share_plus.dart';
import '/custom_code/actions/billing_ticker.dart';

class RoutineModeDuo extends StatefulWidget {
  const RoutineModeDuo({
    Key? key,
    this.width,
    this.height,
    this.roomId,
  }) : super(key: key);
  final double? width;
  final double? height;
  final String? roomId;

  @override
  _RoutineModeDuoState createState() => _RoutineModeDuoState();
}

class _RoutineModeDuoState extends State<RoutineModeDuo> {
  // ============================================================================
  // 📦 [1. 상태 변수 (STATE VARIABLES)]
  // 앱의 전반적인 상태, UI 설정, 데이터 보관용 변수 모음
  // ============================================================================
  String _openAiKey = "";
  bool _isConversationActive = false;
  bool _isPartnerOnline = false;
  bool _isExiting = false;
  int _turnCounter = 0;
  double _fontScale = 1.0;
  bool _showOriginal = true;

  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _localMessages = [];
  final Map<int, GlobalKey> _itemKeys = {}; // 상단 고정 렌더링을 위한 추적기
  DateTime? _lastScrollThrottle; // 스크롤 throttle 타임스탬프 (Roleplay 이식)

  DocumentReference? _myHistoryRef;
  DocumentReference? _duoSessionRef;
  StreamSubscription? _partnerJoinedSubscription;

  // ============================================================================
  // 📦 [2. 오디오 컨트롤러 (AUDIO CONTROLLERS)]
  // 녹음, 재생, 타이머 관리를 위한 오디오 변수 모음
  // ============================================================================
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _ttsPlayer = AudioPlayer();

  Timer? _silenceTimer;
  int _silenceCounter = 0;
  bool _hasSpoken = false;
  bool _isTtsActive = false;
  Completer<void>? _ttsCompleter;

  // ============================================================================
  // 📦 [3. 라이프사이클 (LIFECYCLE)]
  // 위젯의 시작(initState)과 끝(dispose) 및 초기 설정
  // ============================================================================
  @override
  void initState() {
    super.initState();
    _fetchKeys();
    _audioPlayer.setVolume(1.0);
    _ttsPlayer.setVolume(1.0);

    BillingTicker.instance.setRate(BillingRate.full);
    BillingTicker.instance.resume();
    BillingTicker.instance.logMode('duo');

    _ttsPlayer.onPlayerComplete.listen((_) {
      _isTtsActive = false;
      if (_ttsCompleter != null && !_ttsCompleter!.isCompleted) {
        _ttsCompleter!.complete();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // widget.roomId 우선 사용, 없으면 FFAppState 폴백
      final String? pendingRoomId =
          (widget.roomId != null && widget.roomId!.isNotEmpty)
              ? widget.roomId
              : (FFAppState().isGuestSession &&
                      FFAppState().duoRoomId.isNotEmpty
                  ? FFAppState().duoRoomId
                  : null);
      if (pendingRoomId != null) {
        debugPrint(
            '[Duo] initState — auto joining as guest, roomId: $pendingRoomId');
        _joinAsGuest(pendingRoomId);
      }
    });
  }

  @override
  void dispose() {
    _partnerJoinedSubscription?.cancel();
    _silenceTimer?.cancel();
    _cancelAudio();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _ttsPlayer.dispose();
    BillingTicker.instance.pause();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchKeys() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: const Duration(minutes: 1)));
      await remoteConfig.fetchAndActivate();
      if (mounted)
        setState(() => _openAiKey = remoteConfig.getString('OpenAIAPIKey'));
    } catch (e) {}
  }

  Future<void> _initPermissions() async {
    await [Permission.microphone, Permission.storage].request();
  }

  // ============================================================================
  // 📦 [4. 오디오 관리 로직 (AUDIO MANAGEMENT)]
  // TTS 재생, 취소 및 마이크 입력 감지
  // ============================================================================
  void _cancelAudio() {
    _audioPlayer.stop();
    _ttsPlayer.stop();
    if (_ttsCompleter != null && !_ttsCompleter!.isCompleted) {
      _ttsCompleter!.complete();
    }
    _isTtsActive = false;
  }

  Future<void> _playAudioAndWait(Uint8List? bytes) async {
    if (bytes == null || !_isConversationActive) return;
    _isTtsActive = true;
    _ttsCompleter = Completer<void>();
    try {
      await _ttsPlayer.play(BytesSource(bytes));
      await _ttsCompleter!.future;
    } catch (e) {}
    _ttsCompleter = null;
    _isTtsActive = false;
  }

  Future<void> _startWhisperRecording() async {
    if (!_isConversationActive || _openAiKey.isEmpty) return;
    if (await _audioRecorder.hasPermission()) {
      _hasSpoken = false;
      _silenceCounter = 0;
      try {
        final dir = await getTemporaryDirectory();
        final path =
            '${dir.path}/whisper_stt_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(
            const RecordConfig(
                encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1),
            path: path);
        _silenceTimer?.cancel();
        _silenceTimer =
            Timer.periodic(const Duration(milliseconds: 100), (timer) async {
          if (await _audioRecorder.isRecording()) {
            final amp = await _audioRecorder.getAmplitude();
            if (amp.current > -25.0) {
              _hasSpoken = true;
              _silenceCounter = 0;
            } else {
              _silenceCounter++;
              if (_hasSpoken && _silenceCounter >= 15) {
                timer.cancel();
                _stopAndSendToWhisper();
              } else if (!_hasSpoken && _silenceCounter >= 50) {
                timer.cancel();
                await _audioRecorder.stop();
                _startWhisperRecording();
              }
            }
          } else {
            timer.cancel();
          }
        });
      } catch (e) {}
    }
  }

// ============================================================================
  // 📦 [5. 핵심 AI 파이프라인 (CORE AI LOGIC)]
  // STT(1.5초) -> UI 즉시 출력 -> 동시 통역(gpt-4o-mini) -> TTS 재생 (1초 강제 대기 삭제!)
  // ============================================================================
  Future<void> _stopAndSendToWhisper() async {
    _silenceTimer?.cancel();
    final path = await _audioRecorder.stop();
    if (path == null) {
      if (_isConversationActive) _startWhisperRecording();
      return;
    }

    try {
      Uri uri = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
      var request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $_openAiKey';
      request.fields['model'] = 'whisper-1';
      request.files.add(await http.MultipartFile.fromPath('file', path));

      // ⏱️ 타임아웃 10초 적용
      var response = await request.send().timeout(const Duration(seconds: 10));
      var responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        String transcript = jsonDecode(responseData)['text'] ?? "";
        String lowerClean =
            transcript.trim().toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
        // 💡 듀오 모드 특화 환각 필터 (불필요한 mbc, also 등 제거)
        List<String> ghostWords = [
          'thank you',
          'thanks for watching',
          'subtitles by',
          'you',
          'yeah',
          'okay',
          'i',
          'also',
          'mbc',
          'share this video',
          '시청해 주셔서',
          '시청해주셔서',
          '감사합니다',
          '구독과 좋아요'
        ];
        bool isGhost = ghostWords.any(
                (ghost) => lowerClean.contains(ghost.replaceAll(' ', ''))) &&
            transcript.length < 30;

        if (lowerClean.isEmpty || isGhost || transcript.length <= 2) {
          await _handleContextualError();
          return;
        }

        if (transcript.trim().isNotEmpty) {
          _processRelayPipeline(transcript);
        } else {
          if (_isConversationActive) _startWhisperRecording();
        }
      } else {
        if (_isConversationActive) _startWhisperRecording();
      }
    } catch (e) {
      if (_isConversationActive) _startWhisperRecording();
    }
  }

  // 💡 공통 에러 방어 핸들러 추가
  Future<void> _handleContextualError() async {
    String fallbackTarget =
        "I'm sorry, I didn't quite catch that. Could you say it again?";
    if (mounted) {
      setState(() {
        _localMessages.add({
          'role': 'SYSTEM',
          'target': fallbackTarget,
          'original': '',
          'type': 'error'
        });
      });
      _scrollToCurrent(_localMessages.length - 1);
    }
    Uint8List? errorTts = await _fetchTTSBytes(fallbackTarget, "nova");
    if (errorTts != null && _isConversationActive) {
      await _playAudioAndWait(errorTts);
    }
    if (mounted) setState(() => _localMessages.removeLast());
    if (_isConversationActive) _startWhisperRecording();
  }

  Future<Uint8List?> _fetchTTSBytes(String text, String voice) async {
    if (_openAiKey.isEmpty || text.trim().isEmpty) return null;
    try {
      Uri ttsUri = Uri.parse('https://api.openai.com/v1/audio/speech');
      // ⏱️ 타임아웃 15초 적용
      var response = await DuoBrain.client
          .post(ttsUri,
              headers: {
                'Authorization': 'Bearer $_openAiKey',
                'Content-Type': 'application/json'
              },
              body: jsonEncode({
                "model": "tts-1",
                "input": text,
                "voice": voice,
                "speed": 1.0
              }))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (e) {}
    return null;
  }

  // 🚀 불필요한 딜레이를 싹 걷어낸 즉시 통역 파이프라인
  Future<void> _processRelayPipeline(String finalTranscript) async {
    _turnCounter++;
    final int currentTurnId = _turnCounter;
    String myTarget = FFAppState().targetLang.isNotEmpty
        ? FFAppState().targetLang
        : 'English';
    String myOriginal =
        FFAppState().nativeLang.isNotEmpty ? FFAppState().nativeLang : 'Korean';
    String aiVoice = "nova";

    // 🚀 1. STT 결과물(유저가 한 말)을 화면에 먼저 즉시 띄웁니다!
    if (mounted) {
      setState(() {
        _localMessages
            .add({'role': 'HOST', 'target': finalTranscript, 'original': ''});
      });
      // HOST 말풍선은 상단 고정 — 사용자 발화가 화면 안에 안정적으로 보이도록
      _scrollToCurrentTop(_localMessages.length - 1);
    }
    await _saveHistoryMessage(finalTranscript, "", 'HOST');

    if (!_isConversationActive || _turnCounter != currentTurnId) return;

    // ⏱️ 2. 화면에 띄워두고 백그라운드에서 동시통역(gpt-4o-mini) 진행
    // 현재 턴 직전까지의 대화 히스토리(에러 메시지 제외)를 컨텍스트로 전달
    final recentHistory = _localMessages.length > 1
        ? _localMessages
            .sublist(0, _localMessages.length - 1)
            .where((m) => m['type'] == null)
            .toList()
        : <Map<String, dynamic>>[];

    Map<String, String>? translationResult = await DuoBrain.processTranslation(
        key: _openAiKey,
        text: finalTranscript,
        targetLang: myTarget,
        originalLang: myOriginal,
        recentHistory: recentHistory);

    if (!_isConversationActive || _turnCounter != currentTurnId) return;

    String aiReplyTarget = "🚨 통신 에러가 발생했습니다.";
    String aiReplyOriginal = finalTranscript;
    Uint8List? aiTtsBytes;

    if (translationResult != null) {
      aiReplyTarget = translationResult['translated_text'] ?? aiReplyTarget;
      aiReplyOriginal = translationResult['original_input'] ?? finalTranscript;
      // ⏱️ 3. 통역본을 소리로 읽어주기 위해 TTS 다운로드
      aiTtsBytes = await _fetchTTSBytes(aiReplyTarget, aiVoice);
    } else {
      // 통신 실패 시 빠른 에러 처리
      if (mounted) {
        setState(() {
          _localMessages.add({
            'role': 'SYSTEM',
            'target': 'Network Error. Please try again.',
            'original': '',
            'type': 'error'
          });
        });
        _scrollToCurrent(_localMessages.length - 1);
      }
      if (_isConversationActive && _turnCounter == currentTurnId)
        _startWhisperRecording();
      return;
    }

    if (!_isConversationActive || _turnCounter != currentTurnId) return;

    // 💡 4. [수술 핵심] 기존에 있던 'await Future.delayed(1초)' 강제 대기를 삭제하여 통역본 즉시 출력!
    if (mounted) {
      setState(() {
        _localMessages.add({
          'role': 'SYSTEM',
          'target': aiReplyTarget,
          'original': aiReplyOriginal
        });
      });
      // AI 응답은 중앙 고정 — 읽기 좋은 위치에서 흔들리지 않도록
      _scrollToCurrent(_localMessages.length - 1);
    }

    await _saveHistoryMessage(aiReplyTarget, aiReplyOriginal, 'SYSTEM');

    // 5. TTS 재생 후 마이크 다시 켜기
    if (aiTtsBytes != null) {
      await _playAudioAndWait(aiTtsBytes);
    }

    if (_isConversationActive && _turnCounter == currentTurnId) {
      _startWhisperRecording();
    }
  }

// ============================================================================
  // 📦 [6. 데이터베이스 및 스크롤 관리 (DB & SCROLL)]
  // 히스토리 저장 및 화면 상단 고정 제어
  // ============================================================================
  // fallback: GlobalKey context를 못 찾을 때만 사용. 첫 메시지는 건너뜀
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (_localMessages.length <= 1) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  // 250ms throttle — 연속 setState 중 스크롤 남발 방지 (Roleplay 이식)
  void _scrollToBottomThrottled() {
    final now = DateTime.now();
    if (_lastScrollThrottle == null ||
        now.difference(_lastScrollThrottle!) >=
            const Duration(milliseconds: 250)) {
      _lastScrollThrottle = now;
      _scrollToBottom();
    }
  }

  // 현재 말풍선을 화면 중앙에 고정 — AI 응답 추가 시 사용 (Roleplay 이식)
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

  // 현재 말풍선을 화면 상단에 고정 — HOST 발화 추가 시 사용 (Roleplay 이식)
  void _scrollToCurrentTop(int index) {
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

  void _handleMicTap() {
    setState(() => _isConversationActive = !_isConversationActive);
    if (_isConversationActive) {
      _startWhisperRecording();
    } else {
      _silenceTimer?.cancel();
      _cancelAudio();
      _turnCounter++;
    }
  }

  void _showFontSizeDialog() {
    double tempScale = _fontScale;
    showDialog(
      context: context,
      barrierColor: Colors.black38,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('글자 크기',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Slider(
            value: tempScale,
            min: 0.8,
            max: 1.5,
            divisions: 7,
            label: '${(tempScale * 100).round()}%',
            activeColor: const Color(0xFF2563EB),
            onChanged: (v) {
              setS(() => tempScale = v);
              setState(() => _fontScale = v);
            },
          ),
          contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('확인', style: TextStyle(color: Color(0xFF2563EB))),
            ),
          ],
        );
      }),
    );
  }

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
        'room_name': "Duo Connect Mode",
        'is_pinned': true,
        'msg_count': 0
      });
    }
  }

  Future<void> _saveHistoryMessage(
      String target, String original, String role) async {
    if (target.trim().isEmpty) return;
    await _ensureHistoryRef();
    if (_myHistoryRef == null) return;
    try {
      await _myHistoryRef!.collection('messages').add({
        'role': role,
        'translated_text': target,
        'original_text': original,
        'created_at': FieldValue.serverTimestamp()
      });
    } catch (e) {}
  }

  Future<void> _shareInviteCode() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      // 1) 세션이 없으면 생성
      if (_duoSessionRef == null) {
        _duoSessionRef =
            FirebaseFirestore.instance.collection('duo_sessions').doc();
        await _duoSessionRef!.set({
          'hostUid': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
          'isDuoEnabled': false,
          'isPartnerJoined': false,
        });
      }
      // 2) listener 항상 재등록 (cancel 후 재등록으로 중복 구독 방지)
      _listenForPartnerJoined();
      // 3) 세션 활성화
      await _duoSessionRef!.update({
        'isDuoEnabled': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // 4) OneLink URL 생성 (roomId 정상 주입)
      final String _roomId = _duoSessionRef!.id;
      final Map<String, String> _params = {
        'deep_link_value': 'duo_chat',
        'invite_type': 'duo',
        'entry_mode': 'guest',
        'room_id': _roomId,
        'duo_room_id': _roomId,
        'deep_link_sub1': user.uid,
        'deep_link_sub2': _roomId,
        'inviter_id': user.uid,
        'af_dp': 'stealthvox://duo',
        'af_force_deeplink': 'true',
        'pid': 'friend_invite',
        'c': 'in_app_share',
      };
      debugPrint('[Duo] inviteLink roomId: $_roomId');
      final String inviteLink =
          Uri.parse('https://stealthvox.onelink.me/31o1/fipsp75p')
              .replace(queryParameters: _params)
              .toString();
      debugPrint('[Duo] inviteLink: $inviteLink');
      // 5) 클립보드 복사 + 공유 시트
      await Clipboard.setData(ClipboardData(text: inviteLink));
      await Share.share(
        '저와 함께 Duo 대화 연습해요! 👉 $inviteLink',
        subject: 'StealthVox Duo 초대',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('초대 링크가 복사되었고 공유창이 열렸습니다.'),
          backgroundColor: Color(0xFF2563EB),
          duration: Duration(seconds: 3),
        ));
      }
    } catch (e) {
      debugPrint('[Duo] Share invite error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('초대 링크 발행에 실패했습니다. 다시 시도해주세요.')));
      }
    }
  }

  Future<void> _joinAsGuest(String roomId) async {
    // 초대 상태는 여기서 지우지 않음 — Firestore 업데이트 성공 후에만 삭제
    try {
      _duoSessionRef =
          FirebaseFirestore.instance.collection('duo_sessions').doc(roomId);
      final snap = await _duoSessionRef!.get();
      if (!snap.exists) {
        debugPrint('[Duo] _joinAsGuest: session not found ($roomId)');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('초대된 방을 찾을 수 없습니다.')),
          );
          StealthRoomMaster.exitCurrentMode?.call();
        }
        return;
      }
      final data = snap.data() as Map<String, dynamic>?;
      if (data == null || data['isDuoEnabled'] != true) {
        debugPrint('[Duo] _joinAsGuest: isDuoEnabled is not true ($roomId)');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이 방은 현재 사용할 수 없습니다.')),
          );
          StealthRoomMaster.exitCurrentMode?.call();
        }
        return;
      }

      final String? firebaseUid = FirebaseAuth.instance.currentUser?.uid;
      final String guestUid =
          firebaseUid ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';

      await _duoSessionRef!.update({
        'isPartnerJoined': true,
        'partnerUid': guestUid,
        'partnerJoinedAt': FieldValue.serverTimestamp(),
      });

      // 입장 성공 후에만 초대 상태 정리 (3개 세트)
      FFAppState().isGuestSession = false;
      FFAppState().duoRoomId = '';
      FFAppState().pendingInviteType = '';
      debugPrint('[AppState] duo invite state cleared (after successful join)');

      debugPrint('[Duo] _joinAsGuest success — guestUid: $guestUid, roomId: $roomId');

      if (mounted) {
        setState(() {
          _isConversationActive = true;
          _isPartnerOnline = true;
        });
      }
      _startWhisperRecording();
    } catch (e) {
      debugPrint('[Duo] Guest join error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('연결 중 오류가 발생했습니다. 다시 시도해주세요.')),
        );
        StealthRoomMaster.exitCurrentMode?.call();
      }
    }
  }

  void _listenForPartnerJoined() {
    if (_duoSessionRef == null) return;
    _partnerJoinedSubscription?.cancel();
    _partnerJoinedSubscription = _duoSessionRef!.snapshots().listen((snap) {
      if (_isExiting || !mounted) return;

      // 세션 문서가 삭제된 경우 (호스트가 먼저 나가 세션 delete됨)
      if (!snap.exists) {
        _handleAutoSaveAndExit();
        return;
      }

      final data = snap.data() as Map<String, dynamic>?;
      if (data == null) return;
      final bool partnerJoined = data['isPartnerJoined'] == true;

      // 게스트 퇴장 감지: _isPartnerOnline이 true → false로 떨어지는 순간
      final bool guestJustLeft = _isPartnerOnline && !partnerJoined;

      final bool shouldStartRecording = partnerJoined && !_isConversationActive;
      if (mounted) {
        setState(() {
          _isPartnerOnline = partnerJoined;
          if (shouldStartRecording) _isConversationActive = true;
        });
        if (shouldStartRecording) _startWhisperRecording();
        // 게스트 퇴장 → 호스트 강제 종료 (1:1 대칭 종료 모델)
        if (guestJustLeft) _handleAutoSaveAndExit();
      }
    });
  }

  Future<void> _handleAutoSaveAndExit() async {
    if (_isExiting) return;
    _isExiting = true;

    // listener 즉시 해제 — 본인의 Firestore 업데이트가 listener를 재트리거하지 않도록
    _partnerJoinedSubscription?.cancel();
    _partnerJoinedSubscription = null;

    _cancelAudio();
    _silenceTimer?.cancel();
    if (mounted) setState(() => _isConversationActive = false);

    // 호스트/게스트 분기: duo_sessions 처리
    if (_duoSessionRef != null) {
      try {
        final snap = await _duoSessionRef!.get();
        if (snap.exists) {
          final data = snap.data() as Map<String, dynamic>?;
          final String? hostUid = data?['hostUid']?.toString();
          final String? myUid = FirebaseAuth.instance.currentUser?.uid;
          if (hostUid != null && myUid != null && hostUid == myUid) {
            // 호스트: 세션 삭제 (1:1 대칭 종료)
            await _duoSessionRef!.delete();
          } else {
            // 게스트: isPartnerJoined=false 업데이트
            await _duoSessionRef!.update({
              'isPartnerJoined': false,
              'partnerLeftAt': FieldValue.serverTimestamp(),
            });
          }
        }
      } catch (e) {
        debugPrint('[Duo] session cleanup error: $e');
      }
    }

    if (_myHistoryRef != null) {
      if (_localMessages.isEmpty) {
        await _myHistoryRef!.delete();
      } else {
        String lastText =
            _localMessages.last['target']?.toString() ?? "대화 기록 저장";
        await _myHistoryRef!.update({
          'last_message': lastText.isNotEmpty ? lastText : "대화 기록 저장",
          'last_message_time': FieldValue.serverTimestamp(),
          'msg_count': _localMessages.length,
          'last_active': FieldValue.serverTimestamp()
        });
      }
    }
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

  // ============================================================================
  // 📦 [7. UI 빌더 (UI BUILDERS)]
  // 화면 레이아웃 (TopBar, ControlArea, TextBlock)
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    final effectiveBottomPadding =
        MediaQuery.of(context).viewPadding.bottom == 0
            ? 24.0
            : MediaQuery.of(context).viewPadding.bottom + 8.0;

    return PopScope(
        canPop: false,
        onPopInvoked: (didPop) async {
          if (didPop) return;
          await _handleAutoSaveAndExit();
        },
        child: Container(
          width: widget.width,
          height: widget.height,
          color: const Color(0xFF121212),
          child: SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: _localMessages.isEmpty
                      ? const Center(
                          child: Text("하단의 마이크 버튼을 눌러 통역을 시작하세요.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white54, height: 1.5)))
                      : ListView.builder(
                          controller: _scrollController,
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.only(
                              left: 8,
                              right: 8,
                              top: 40,
                              bottom: MediaQuery.of(context).size.height * 0.4),
                          itemCount: _localMessages.length,
                          itemBuilder: (context, index) {
                            if (!_itemKeys.containsKey(index))
                              _itemKeys[index] = GlobalKey();
                            return Container(
                              key: _itemKeys[index],
                              child: _buildTextBlock(_localMessages[index]),
                            );
                          }),
                ),
                _buildControlArea(effectiveBottomPadding),
              ],
            ),
          ),
        ));
  }

  Widget _buildPartnerIndicator() {
    if (!_isPartnerOnline) return const SizedBox.shrink();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.person, color: Colors.white70, size: 20),
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF34D399),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white70),
                  onPressed: _handleAutoSaveAndExit),
              _buildPartnerIndicator(),
            ],
          ),
          Row(children: [
            IconButton(
              icon: const Icon(Icons.format_size,
                  color: Colors.white70, size: 26),
              tooltip: '글자 크기 조절',
              onPressed: _showFontSizeDialog,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
            IconButton(
              icon: const Icon(Icons.person_add_alt_1,
                  color: Colors.white70, size: 22),
              tooltip: 'Duo 초대장 발행',
              onPressed: _shareInviteCode,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ]),
          ValueListenableBuilder<int>(
              valueListenable: BillingTicker.instance.remainingSecondsNotifier,
              builder: (context, remaining, child) {
                return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        borderRadius: BorderRadius.circular(20)),
                    child: Row(children: [
                      const Icon(Icons.timer_outlined,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text("${remaining ~/ 60}m",
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold))
                    ]));
              }),
        ],
      ),
    );
  }

  Widget _buildControlArea(double bottomPadding) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPadding),
      decoration: const BoxDecoration(color: Color(0xFF121212)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Duo Connect",
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5)),
          GestureDetector(
            onTap: _handleMicTap,
            child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                    color: _isConversationActive
                        ? Colors.redAccent.withOpacity(0.15)
                        : const Color(0xFF2563EB).withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _isConversationActive
                            ? Colors.redAccent
                            : const Color(0xFF2563EB),
                        width: 2)),
                child: Icon(
                    _isConversationActive
                        ? Icons.stop_rounded
                        : Icons.mic_rounded,
                    color: _isConversationActive
                        ? Colors.redAccent
                        : const Color(0xFF2563EB),
                    size: 36)),
          ),
        ],
      ),
    );
  }

  Widget _buildTextBlock(Map<String, dynamic> msg) {
    String target = msg['target']?.toString() ?? '';
    String original = msg['original']?.toString() ?? '';
    bool isHost = msg['role'] == 'HOST';

    if (target.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: isHost ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isHost
              ? const Color(0xFF2C2C2E)
              : const Color(0xFF2563EB).withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        child: Column(
            crossAxisAlignment:
                isHost ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(target,
                  textAlign: isHost ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                      color: isHost ? Colors.white : const Color(0xFF93C5FD),
                      fontSize: 16 * _fontScale,
                      fontWeight: FontWeight.w600,
                      height: 1.3)),
              if (_showOriginal && original.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(original,
                    textAlign: isHost ? TextAlign.right : TextAlign.left,
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14 * _fontScale,
                        height: 1.3))
              ]
            ]),
      ),
    );
  }
}

// ============================================================================
// 📦 [Box 7-1: 듀오 전용 AI 뇌 (DuoBrain)]
// OpenAI API 호출(양방향 동시 통역) 전용 클래스
// ============================================================================
class DuoBrain {
  static final http.Client client = http.Client();

  static Future<Map<String, String>?> processTranslation(
      {required String key,
      required String text,
      required String targetLang,
      required String originalLang,
      List<Map<String, dynamic>> recentHistory = const []}) async {
    try {
      Uri uri = Uri.parse('https://api.openai.com/v1/chat/completions');

      // 최근 대화 히스토리를 GPT 컨텍스트로 변환 (최대 6턴)
      final historyLines = <String>[];
      for (final msg
          in recentHistory.reversed.take(6).toList().reversed) {
        final role = msg['role'] == 'HOST' ? 'User' : 'AI';
        final content = msg['target']?.toString() ?? '';
        if (content.isNotEmpty) historyLines.add('[$role]: $content');
      }
      final historyContext = historyLines.isEmpty
          ? '(No prior conversation)'
          : historyLines.join('\n');

      String prompt = "You are a Duo Mode AI conversation partner.\n"
          "The user speaks $originalLang. Respond in $targetLang.\n\n"
          "=== RECENT CONVERSATION ===\n"
          "$historyContext\n\n"
          "=== SUBJECT AMBIGUITY GUARD ===\n"
          "Before responding, determine: is it clear WHO or WHAT the user is asking about?\n"
          "Trigger clarification if ANY of these apply:\n"
          "• A person name/role (호진, 아들, 엄마, 선생님, 걔, 그 사람) appears but the referent is unclear\n"
          "• The question involves scores, exams, schedules, or states — and WHOSE is not established\n"
          "• Short utterance uses pronouns only (걔, 그거, 이번에) with no context to resolve them\n"
          "• Examples that MUST trigger clarification: '몇 점 받을 것 같아?', '괜찮을까?', '어떻게 됐어?'\n\n"
          "Decision rule:\n"
          "✅ Subject is clear from utterance OR resolved from history → respond naturally in $targetLang\n"
          "❌ Subject is ambiguous AND history cannot resolve it → ask a SHORT clarification question\n\n"
          "ABSOLUTE PROHIBITION:\n"
          "• NEVER assume the speaker ('I/you') is the subject when a third person was mentioned or implied\n"
          "• NEVER produce: 'I think I'll score…', 'You might get…', '제가 받을 것 같아요'\n\n"
          "=== OUTPUT (strict JSON) ===\n"
          "{\n"
          "  \"needs_clarification\": <true or false>,\n"
          "  \"translated_text\": \"<$targetLang: your response OR clarification question>\",\n"
          "  \"original_input\": \"<Korean: gloss of your response OR clarification note>\"\n"
          "}\n\n"
          "User said: \"$text\"";

      var res = await client
          .post(uri,
              headers: {
                'Authorization': 'Bearer $key',
                'Content-Type': 'application/json; charset=utf-8'
              },
              body: jsonEncode({
                'model': 'gpt-4o-mini',
                'temperature': 0.3,
                'max_tokens': 300,
                'response_format': {'type': 'json_object'},
                'messages': [
                  {'role': 'user', 'content': prompt}
                ]
              }))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        String cleanJson = _cleanJsonString(
            jsonDecode(utf8.decode(res.bodyBytes))['choices'][0]['message']
                ['content']);
        var parsed = jsonDecode(cleanJson);
        return {
          'translated_text': parsed['translated_text']?.toString() ?? "",
          'original_input': parsed['original_input']?.toString() ?? "",
          'needs_clarification':
              (parsed['needs_clarification'] == true).toString(),
        };
      }
    } catch (e) {
      print("DuoBrain Error: $e");
    }
    return null;
  }

  static String _cleanJsonString(String text) {
    String clean = text.trim();
    if (clean.startsWith('```json')) {
      clean = clean.substring(7);
    } else if (clean.startsWith('```')) {
      clean = clean.substring(3);
    }
    if (clean.endsWith('```')) {
      clean = clean.substring(0, clean.length - 3);
    }
    return clean.trim();
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

    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()
          ..color = active ? const Color(0xFF1E7DB5) : const Color(0xFF2A2A2A));

    if (active) {
      canvas.drawPath(
        Path()
          ..moveTo(size.width * 0.05, size.height)
          ..lineTo(size.width, size.height * 0.05)
          ..lineTo(size.width, size.height)
          ..close(),
        Paint()..color = const Color(0xFF0B4870),
      );
    }

    canvas.drawLine(
      Offset(size.width * 0.04, size.height * 0.96),
      Offset(size.width * 0.96, size.height * 0.04),
      Paint()
        ..color = active ? const Color(0xFFD4AF37) : Colors.white12
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(
      center,
      r - 1.5,
      Paint()
        ..color = active ? const Color(0xFFD4AF37) : Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // 상단 좌측 "T" (원어) — 비활성 시 거의 투명
    _drawText(canvas, 'T', Offset(size.width * 0.09, size.height * 0.06),
        size.width * 0.34, active ? Colors.white : const Color(0x22FFFFFF));

    if (active) {
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

    // 하단 우측 "T" (타겟) — 항상 흰색
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
