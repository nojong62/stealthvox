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

  // 🆕 [게스트 언어 오버레이] 초대 게스트(회원·비회원)가 입장 전 언어쌍 선택
  bool _showLangOverlay = false;
  String? _pendingJoinRoomId;

  // 🆕 [PTT] Duo 무전기 상태기계
  // idle: 대기 / recording: 녹음 중 / processing: STT·번역 중 / playing: TTS 재생 중 / cooldown: 재생 후 짧은 잠금
  String _duoState = 'idle';
  // 🆕 [과금정책] 게스트 입장 후에만 과금 시작 (호스트 대기 중 정지)
  bool _billingStarted = false;
  void _startDuoBilling() {
    // 🆕 [과금정책] 게스트(회원·비회원 무관)는 차감 안 함 — 초대한 호스트만 과금
    if (!_amIHost) return;
    BillingTicker.instance.setRate(BillingRate.full);
    BillingTicker.instance.start();
    if (!_billingStarted) {
      _billingStarted = true;
      BillingTicker.instance.logMode('duo');
    }
    if (BillingTicker.instance.isPaused) {
      BillingTicker.instance.resume();
    }
  }

  void _stopDuoBilling() {
    if (!_amIHost) return;
    _billingStarted = false;
    BillingTicker.instance.pause();
  }

  // 🆕 [PTT 에코 차단] 최근 앱이 생성/표시한 문장 보관 (target/original 혼합, 최대 10개)
  final List<String> _recentGenerated = [];
  DateTime? _lastTtsEndAt; // 🆕 마지막 TTS 종료 시각(엄격 필터 윈도우용)

  String _normForEcho(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\w가-힣]'), '');

  void _rememberGenerated(String s) {
    final t = s.trim();
    if (t.isEmpty) return;
    _recentGenerated.add(t);
    while (_recentGenerated.length > 10) _recentGenerated.removeAt(0);
  }

  // 토큰 자카드 유사도 (0~1)
  double _jaccard(String a, String b) {
    final sa = a
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toSet();
    final sb = b
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toSet();
    if (sa.isEmpty || sb.isEmpty) return 0.0;
    final inter = sa.intersection(sb).length;
    final uni = sa.union(sb).length;
    return uni == 0 ? 0.0 : inter / uni;
  }

  bool _looksLikeEcho(String transcript) {
    final t = transcript.trim();
    if (t.length < 4) return false;
    final tn = _normForEcho(t);

    // TTS 종료 직후 1.2초는 엄격 모드(임계값 완화 → 더 잘 버림)
    final bool strict = _lastTtsEndAt != null &&
        DateTime.now().difference(_lastTtsEndAt!).inMilliseconds < 1200;
    final double simThreshold = strict ? 0.6 : 0.8;

    for (final g in _recentGenerated) {
      if (g.isEmpty) continue;
      final gn = _normForEcho(g);
      if (gn.isEmpty) continue;
      // ① 정규화 포함 관계
      if (gn == tn || gn.contains(tn) || tn.contains(gn)) return true;
      // ② 토큰 자카드 유사도
      if (_jaccard(g, t) >= simThreshold) return true;
    }
    return false;
  }

  void _setDuoState(String s) {
    if (!mounted) return;
    setState(() => _duoState = s);
  }

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

  // ── 🆕 [양방향 통역] 역할/메시지 채널 상태 ────────────────────────────────
  // _amIHost: 게스트로 합류했으면 false, 아니면 호스트(true)
  bool _amIHost = true;
  // _myUid: 메시지 발신자 식별용 (호스트=firebase uid, 게스트=합류 시 부여된 uid)
  String _myUid = '';
  // 내 역할 문자열 ('HOST' 또는 'GUEST') — 발신/필터 기준
  String get _myRole => _amIHost ? 'HOST' : 'GUEST';
  // 공유 메시지 채널(duo_sessions/{roomId}/messages) 구독
  StreamSubscription? _messageSubscription;
  // 이미 처리한 메시지 doc id (중복 렌더 방지)
  final Set<String> _processedMsgIds = {};
  // 리스너 첫 스냅샷 priming 여부 (기존 메시지 replay 방지)
  bool _messagesPrimed = false;
  // 상대 메시지 처리 큐 (순차 처리 — 음성 겹침 방지)
  final List<Map<String, dynamic>> _incomingQueue = [];
  bool _isDrainingIncoming = false;
  // 오디오 재생 직렬화 체인 (내 음성 ↔ 상대 음성 동시재생 방지)
  Future<void> _audioChain = Future.value();
  // ──────────────────────────────────────────────────────────────────────────

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

  // ── 🆕 [양방향 통역] 언어쌍/보이스 헬퍼 (로비 값 매번 참조) ────────────────
  String _myTarget() =>
      FFAppState().targetLang.isNotEmpty ? FFAppState().targetLang : 'English';
  String _myNative() =>
      FFAppState().nativeLang.isNotEmpty ? FFAppState().nativeLang : 'Korean';
  String _myVoice() =>
      FFAppState().aiVoice.isNotEmpty ? FFAppState().aiVoice : 'nova';
  // ──────────────────────────────────────────────────────────────────────────

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

    // 🆕 발신자 식별용 uid 확보 (게스트는 _joinAsGuest에서 덮어씀)
    _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // 🆕 [과금정책] Duo는 게스트 입장 시점에 과금 시작 — 진입 시엔 rate만 설정하고 pause 유지
    BillingTicker.instance.setRate(BillingRate.full);
    _stopDuoBilling();
    _billingStarted = false;

    _ttsPlayer.onPlayerComplete.listen((_) {
      _isTtsActive = false;
      if (_ttsCompleter != null && !_ttsCompleter!.isCompleted) {
        _ttsCompleter!.complete();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // widget.roomId 우선 사용, 없으면 FFAppState 폴백
      final String? pendingRoomId = (widget.roomId != null &&
              widget.roomId!.isNotEmpty)
          ? widget.roomId
          : (FFAppState().isGuestSession && FFAppState().duoRoomId.isNotEmpty
              ? FFAppState().duoRoomId
              : null);
      if (pendingRoomId != null) {
        debugPrint(
            '[Duo] initState — guest entry, show lang overlay: $pendingRoomId');
        // 🆕 입장 전 언어 선택 오버레이 — 기본값 보정 후 표시
        if (FFAppState().nativeLang.isEmpty) FFAppState().nativeLang = 'Korean';
        if (FFAppState().targetLang.isEmpty)
          FFAppState().targetLang = 'English';
        if (mounted) {
          setState(() {
            _pendingJoinRoomId = pendingRoomId;
            _showLangOverlay = true;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _partnerJoinedSubscription?.cancel();
    _messageSubscription?.cancel(); // 🆕 메시지 채널 구독 해제
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
    await [Permission.microphone].request();
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
    _lastTtsEndAt = DateTime.now();
  }

  // 🆕 오디오 재생 직렬화: 내 음성과 상대 음성이 동시에 겹쳐 재생되지 않도록 큐잉
  Future<void> _playSerialized(Uint8List? bytes) {
    final Future<void> prev = _audioChain;
    final Completer<void> done = Completer<void>();
    _audioChain = done.future;
    () async {
      try {
        await prev;
      } catch (_) {}
      try {
        await _playAudioAndWait(bytes);
      } finally {
        if (!done.isCompleted) done.complete();
      }
    }();
    return done.future;
  }

  Future<void> _startWhisperRecording() async {
    if (_openAiKey.isEmpty) return;
    // 🆕 [PTT] idle 상태가 아니면 시작 금지 (TTS·처리·쿨다운·이미 녹음 중 차단)
    if (_duoState != 'idle') return;
    if (_isTtsActive || _isDrainingIncoming) return;
    if (await _audioRecorder.isRecording()) return;
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
        _setDuoState('recording');
        _silenceTimer?.cancel();
        // 침묵 자동 종료만 유지(누른 채로 말 끝나면 자동 전송). 자동 "재시작"은 제거.
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
              } else if (!_hasSpoken && _silenceCounter >= 80) {
                // 말이 한 번도 없으면 그냥 종료(재시작 안 함)
                timer.cancel();
                await _audioRecorder.stop();
                _setDuoState('idle');
              }
            }
          } else {
            timer.cancel();
          }
        });
      } catch (e) {
        _setDuoState('idle');
      }
    }
  }

// ============================================================================
  // 📦 [5. 핵심 양방향 통역 파이프라인 (CORE INTERPRETER LOGIC)]
  // 내 발화: STT → 내 폰 즉시 렌더 → 내 타겟 통역/TTS → 공유 채널 업로드
  // 상대 발화: 채널 리스너 수신 → 내 언어쌍으로 통역 → 좌측 렌더 + 내 타겟 TTS
  // ============================================================================
  Future<void> _stopAndSendToWhisper() async {
    _silenceTimer?.cancel();
    _setDuoState('processing');
    final path = await _audioRecorder.stop();
    if (path == null) {
      _setDuoState('idle');
      if (_incomingQueue.isNotEmpty) _drainIncoming();
      return;
    }
    try {
      Uri uri = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
      var request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $_openAiKey';
      request.fields['model'] = 'whisper-1';
      request.files.add(await http.MultipartFile.fromPath('file', path));
      var response = await request.send().timeout(const Duration(seconds: 10));
      var responseData = await response.stream.bytesToString();
      if (response.statusCode == 200) {
        String transcript = jsonDecode(responseData)['text'] ?? "";
        final String trimmed = transcript.trim();
        final String lowerRaw = trimmed.toLowerCase();
        final String lowerClean =
            lowerRaw.replaceAll(RegExp(r'[^\w\s가-힣]'), '').trim();
        final String collapsed = lowerClean.replaceAll(' ', '');
        const List<String> hardGhosts = [
          'thank you so much for watching',
          'thank you for watching',
          'thanks for watching',
          'please subscribe',
          'subtitles by',
          'share this video',
          '시청해 주셔서',
          '시청해주셔서',
          '구독과 좋아요',
          '감사합니다 시청',
        ];
        final bool isHardGhost = hardGhosts.any((g) => lowerRaw.contains(g));
        const List<String> shortGhosts = [
          'thank you',
          'yeah',
          'okay',
          'mbc',
          'you',
          'also',
          'i',
          '감사합니다',
        ];
        final bool isShortGhost = trimmed.length < 30 &&
            shortGhosts.any((g) => collapsed == g.replaceAll(' ', ''));
        // 🆕 에코 차단: 최근 앱이 만든 문장과 거의 같으면 버림
        final bool isEcho = _looksLikeEcho(trimmed);
        if (lowerClean.isEmpty ||
            isHardGhost ||
            isShortGhost ||
            isEcho ||
            trimmed.length <= 2) {
          _setDuoState('idle'); // 조용히 대기 복귀(자동 재녹음 금지)
          if (_incomingQueue.isNotEmpty) _drainIncoming();
          return;
        }
        if (trimmed.isNotEmpty) {
          await _processRelayPipeline(trimmed);
        } else {
          _setDuoState('idle');
          if (_incomingQueue.isNotEmpty) _drainIncoming();
        }
      } else {
        _setDuoState('idle');
        if (_incomingQueue.isNotEmpty) _drainIncoming();
      }
    } catch (e) {
      _setDuoState('idle');
      if (_incomingQueue.isNotEmpty) _drainIncoming();
    }
  }

  Future<void> _handleContextualError() async {
    _setDuoState('idle'); // AI 사과 없음, 자동 재녹음 없음 — 조용히 대기 복귀
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

  // 🚀 [내 발화 처리] 내가 말한 것을 내 폰에 즉시 띄우고, 내 타겟으로 통역/TTS, 채널 업로드
  Future<void> _processRelayPipeline(String finalTranscript) async {
    _turnCounter++;
    final int currentTurnId = _turnCounter;
    final String myTarget = _myTarget();
    final String myNative = _myNative();

    // 1. 즉시 표시 제거 - 번역 완료 후 단계 4에서 새 말풍선으로 표시

    // 2. 공유 채널 업로드 — 상대 폰이 이 원문을 받아 자기 언어쌍으로 통역함 (백그라운드)
    _uploadMyMessage(finalTranscript, myNative);

    if (!_isConversationActive || _turnCounter != currentTurnId) return;

    // 3. 내 발화를 내 타겟으로 통역 (+ 내 오리지널 정돈) — 단일 GPT 호출
    Map<String, String>? result = await DuoBrain.processTranslation(
        key: _openAiKey,
        text: finalTranscript,
        srcLang: myNative,
        myTargetLang: myTarget,
        myNativeLang: myNative);

    if (!_isConversationActive || _turnCounter != currentTurnId) return;

    final String tgt =
        (result != null && (result['target'] ?? '').trim().isNotEmpty)
            ? result['target']!
            : finalTranscript;
    final String org =
        (result != null && (result['original'] ?? '').trim().isNotEmpty)
            ? result['original']!
            : finalTranscript;

    // 4. 번역 완료 후 내 말풍선을 [타겟 + 오리지널]로 새 말풍선에 표시
    if (mounted) {
      setState(() {
        _localMessages.add({'role': 'HOST', 'target': tgt, 'original': org});
      });
      _scrollToCurrentTop(_localMessages.length - 1);
    }
    await _saveHistoryMessage(tgt, org, 'HOST');

    // 5. 내 타겟 소리 재생 (직렬화)
    _rememberGenerated(tgt);
    _rememberGenerated(org);
    final Uint8List? bytes = await _fetchTTSBytes(tgt, _myVoice());
    if (bytes != null &&
        _isConversationActive &&
        _turnCounter == currentTurnId) {
      _setDuoState('playing');
      await _playSerialized(bytes);
    }
    // 🆕 [PTT] 자동 재녹음 제거 — 쿨다운 후 대기 상태로 복귀
    _setDuoState('cooldown');
    await Future.delayed(const Duration(milliseconds: 800));
    _setDuoState('idle');
    // 🆕 내 발화 처리 끝 → 보류돼 있던 상대 메시지 처리 재개
    if (_incomingQueue.isNotEmpty) _drainIncoming();
  }

  // 🆕 [채널 업로드] 내 원문을 duo_sessions/{roomId}/messages 에 기록
  Future<void> _uploadMyMessage(String raw, String srcLang) async {
    if (_duoSessionRef == null || raw.trim().isEmpty) return;
    try {
      // 🆕 내 메시지 doc id를 업로드 전에 _processedMsgIds에 선등록한다.
      //    → 리스너(605행)가 내 발화를 항상 스킵하므로, 내 글이 절대
      //      상대(SYSTEM/좌측) 말풍선으로 되돌아오지 않는다. 역할/계정 무관.
      final docRef = _duoSessionRef!.collection('messages').doc();
      _processedMsgIds.add(docRef.id);
      await docRef.set({
        'senderUid': _myUid,
        'senderRole': _myRole,
        'text': raw,
        'srcLang': srcLang,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[Duo] upload message error: $e');
    }
  }

  // 🆕 [상대 발화 리스너] 공유 채널 구독 → 상대(senderRole≠나) 메시지만 처리
  void _listenForMessages() {
    if (_duoSessionRef == null) return;
    _messageSubscription?.cancel();
    _messagesPrimed = false;
    _messageSubscription = _duoSessionRef!
        .collection('messages')
        .orderBy('createdAt')
        .snapshots()
        .listen((snap) {
      if (_isExiting || !mounted) return;

      // 첫 스냅샷: 기존 메시지는 '이미 본 것'으로 처리만 하고 렌더하지 않음 (replay 방지)
      if (!_messagesPrimed) {
        for (final d in snap.docs) {
          _processedMsgIds.add(d.id);
        }
        _messagesPrimed = true;
        return;
      }

      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final doc = change.doc;
        if (_processedMsgIds.contains(doc.id)) continue;
        _processedMsgIds.add(doc.id);

        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        final String msgRole = data['senderRole']?.toString() ?? '';
        if (msgRole == _myRole) continue; // 내가 올린 것 — 이미 로컬 렌더됨, 스킵

        _enqueueIncoming(data);
      }
    });
  }

  // 🆕 상대 메시지 순차 처리 큐 (음성 겹침/순서 꼬임 방지)
  void _enqueueIncoming(Map<String, dynamic> data) {
    _incomingQueue.add(data);
    _drainIncoming();
  }

  Future<void> _drainIncoming() async {
    if (_isDrainingIncoming) return;
    _isDrainingIncoming = true;
    while (_incomingQueue.isNotEmpty) {
      // 🆕 내가 녹음 중이면 상대 메시지 처리 보류 — 내 발화 끊김 방지
      if (_duoState == 'recording') break;
      final data = _incomingQueue.removeAt(0);
      await _handleIncomingMessage(data);
    }
    _isDrainingIncoming = false;
  }

  // 🆕 [상대 발화 처리] 원문을 내 언어쌍으로 통역 → 좌측 말풍선 + 내 타겟 TTS
  Future<void> _handleIncomingMessage(Map<String, dynamic> data) async {
    if (!mounted || _isExiting) return;
    final String raw = data['text']?.toString() ?? '';
    final String srcLang = data['srcLang']?.toString() ?? 'English';
    if (raw.trim().isEmpty) return;

    // 상대 발화를 들려주는 동안 내 녹음 일시 정지 (스피커 음성이 마이크에 새는 것 방지)
    _silenceTimer?.cancel();
    try {
      await _audioRecorder.stop();
    } catch (_) {}
    _setDuoState('processing');

    final String myTarget = _myTarget();
    final String myNative = _myNative();

    Map<String, String>? result = await DuoBrain.processTranslation(
        key: _openAiKey,
        text: raw,
        srcLang: srcLang,
        myTargetLang: myTarget,
        myNativeLang: myNative);

    if (!mounted || _isExiting) return;

    final String tgt =
        (result != null && (result['target'] ?? '').trim().isNotEmpty)
            ? result['target']!
            : raw;
    final String org =
        (result != null && (result['original'] ?? '').trim().isNotEmpty)
            ? result['original']!
            : '';

    // 상대 말풍선: 좌측 (role='SYSTEM')
    if (mounted) {
      setState(() {
        _localMessages.add({'role': 'SYSTEM', 'target': tgt, 'original': org});
      });
      _scrollToCurrent(_localMessages.length - 1);
    }
    await _saveHistoryMessage(tgt, org, 'SYSTEM');

    // 내 타겟 소리로 재생 (직렬화)
    _rememberGenerated(tgt);
    _rememberGenerated(org);
    final Uint8List? bytes = await _fetchTTSBytes(tgt, _myVoice());
    if (bytes != null && _isConversationActive && !_isExiting) {
      _setDuoState('playing');
      await _playSerialized(bytes);
    }
    // 🆕 [PTT] 상대 발화 재생 후에도 자동 재녹음 금지 — 쿨다운 후 대기 복귀
    _setDuoState('cooldown');
    await Future.delayed(const Duration(milliseconds: 800));
    _setDuoState('idle');
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

  // 현재 말풍선을 화면 중앙에 고정 — 상대 응답 추가 시 사용 (Roleplay 이식)
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

  // 현재 말풍선을 화면 상단에 고정 — 내 발화 추가 시 사용 (Roleplay 이식)
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

  // 🆕 [PTT] 버튼 누름 — 녹음 시작
  void _onPttStart() {
    if (!_isConversationActive) {
      setState(() => _isConversationActive = true);
    }
    // idle일 때만 시작(재생/처리/쿨다운 중이면 무시)
    if (_duoState == 'idle') {
      _startWhisperRecording();
    }
  }

  // 🆕 [PTT] 버튼 뗌 — 녹음 종료 후 전송
  void _onPttEnd() {
    if (_duoState == 'recording') {
      _silenceTimer?.cancel();
      _stopAndSendToWhisper();
    }
  }

  // 🆕 [PTT] 버튼 상태별 표시 문구
  String _pttLabel() {
    switch (_duoState) {
      case 'recording':
        return 'Release to send';
      case 'processing':
        return 'Processing…';
      case 'playing':
        return 'Playing…';
      case 'cooldown':
        return '…';
      default:
        return 'Hold to talk';
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
        'last_active': FieldValue.serverTimestamp(),
        'last_message_time': FieldValue.serverTimestamp(),
        'room_name': "Duo Connect Mode",
        'is_pinned': false,
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
        'original_text': (FFAppState().nativeLang.isNotEmpty &&
                FFAppState().nativeLang == FFAppState().targetLang)
            ? ''
            : original,
        'created_at': FieldValue.serverTimestamp()
      });
      await _myHistoryRef!.update({
        'last_message': target,
        'last_active': FieldValue.serverTimestamp(),
        'last_message_time': FieldValue.serverTimestamp(),
        'msg_count': FieldValue.increment(1),
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
      // 🆕 호스트 식별 확정 + uid 확보
      _amIHost = true;
      _myUid = user.uid;
      // 2) listener 항상 재등록 (cancel 후 재등록으로 중복 구독 방지)
      _listenForPartnerJoined();
      _listenForMessages(); // 🆕 공유 메시지 채널 리스너 시작
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

      // 🆕 게스트 식별 확정
      _amIHost = false;
      _myUid = guestUid;

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

      debugPrint(
          '[Duo] _joinAsGuest success — guestUid: $guestUid, roomId: $roomId');

      // 🆕 공유 메시지 채널 리스너 시작 (게스트도 상대=호스트 발화 수신)
      _listenForMessages();

      if (mounted) {
        setState(() {
          _isConversationActive = true;
          _isPartnerOnline = true;
        });
      }
      // 🆕 [과금정책] 게스트 본인 입장 성공 — 과금은 호스트 리스너에서만 시작
      // 🆕 [PTT] 세션만 열고 녹음은 버튼으로 시작 — 자동 녹음 제거
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
      debugPrint(
          '[Duo][Billing] partnerJoined=$partnerJoined amIHost=$_amIHost '
          'paused=${BillingTicker.instance.isPaused} '
          'billingState=${BillingTicker.instance.billingState.value} '
          'billingStarted=$_billingStarted');

      // 게스트 퇴장 감지: _isPartnerOnline이 true → false로 떨어지는 순간
      final bool guestJustLeft = _isPartnerOnline && !partnerJoined;

      final bool shouldStartRecording = partnerJoined && !_isConversationActive;
      if (mounted) {
        setState(() {
          _isPartnerOnline = partnerJoined;
          if (shouldStartRecording) _isConversationActive = true;
        });
        // 🆕 [과금정책] 게스트 입장 확정 시 과금 시작 / 퇴장 시 정지
        if (partnerJoined) {
          _startDuoBilling();
        } else {
          _stopDuoBilling();
        }
        // 🆕 [PTT] 입장 시 자동 녹음 제거 — 버튼으로만 시작
        // 게스트 퇴장 → 호스트 강제 종료 (1:1 대칭 종료 모델)
        if (guestJustLeft) _handleAutoSaveAndExit();
      }
    });
  }

  Future<void> _handleAutoSaveAndExit() async {
    if (_isExiting) return;
    _isExiting = true;
    _stopDuoBilling();

    // listener 즉시 해제 — 본인의 Firestore 업데이트가 listener를 재트리거하지 않도록
    _partnerJoinedSubscription?.cancel();
    _partnerJoinedSubscription = null;
    _messageSubscription?.cancel(); // 🆕 메시지 채널 구독도 해제
    _messageSubscription = null;

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
        child: Stack(children: [
          Container(
            width: widget.width,
            height: widget.height,
            color: const Color(0xFF121212),
            child: SafeArea(
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: Stack(children: [
                      _localMessages.isEmpty
                          ? const Center(
                              child: Text("마이크는 말하는 동안만 누르세요.",
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
                                  bottom:
                                      MediaQuery.of(context).size.height * 0.4),
                              itemCount: _localMessages.length,
                              itemBuilder: (context, index) {
                                if (!_itemKeys.containsKey(index))
                                  _itemKeys[index] = GlobalKey();
                                return Container(
                                  key: _itemKeys[index],
                                  child: _buildTextBlock(_localMessages[index]),
                                );
                              }),
                    ]),
                  ),
                  _buildControlArea(effectiveBottomPadding),
                ],
              ),
            ),
          ),
          if (_showLangOverlay) _buildGuestLangOverlay(),
        ]));
  }

  // 🆕 [게스트 언어 오버레이] 초대 게스트 입장 전 ORIGIN/TARGET 선택 게이트
  Widget _buildGuestLangOverlay() {
    const List<String> langs = [
      'English',
      'Japanese',
      'Chinese',
      'Spanish',
      'French',
      'German',
      'Korean'
    ];
    String native = langs.contains(FFAppState().nativeLang)
        ? FFAppState().nativeLang
        : 'Korean';
    String target = langs.contains(FFAppState().targetLang)
        ? FFAppState().targetLang
        : 'English';

    Widget dropdown(String label, String value, Color labelColor,
        ValueChanged<String?> onChanged,
        {String? subtitle, bool subtitleBelow = false}) {
      Widget labelWidget;
      if (subtitle != null && !subtitleBelow) {
        labelWidget = Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(label,
                  style: TextStyle(
                      color: labelColor,
                      fontSize: 12,
                      letterSpacing: 1,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Text(subtitle,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
            ]);
      } else if (subtitle != null && subtitleBelow) {
        labelWidget =
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  color: labelColor,
                  fontSize: 12,
                  letterSpacing: 1,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 10, letterSpacing: 0.3)),
        ]);
      } else {
        labelWidget = Text(label,
            style: TextStyle(
                color: labelColor,
                fontSize: 12,
                letterSpacing: 1,
                fontWeight: FontWeight.bold));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          labelWidget,
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: value,
                dropdownColor: const Color(0xFF1E1E1E),
                icon: const Icon(Icons.unfold_more_rounded,
                    color: Colors.white54, size: 20),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
                items: langs
                    .map((l) =>
                        DropdownMenuItem<String>(value: l, child: Text(l)))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      );
    }

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.78),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: const Color(0xFF2563EB), width: 1.5)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("대화 언어 설정",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text("내 언어와 통역받을 언어를 선택하세요.",
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                  const SizedBox(height: 24),
                  dropdown("ORIGIN", native, const Color(0xFF93C5FD), (val) {
                    if (val != null)
                      setState(() => FFAppState().nativeLang = val);
                  }, subtitle: "(My Language)", subtitleBelow: false),
                  const SizedBox(height: 18),
                  dropdown("TARGET", target, const Color(0xFF4ADE80), (val) {
                    if (val != null)
                      setState(() => FFAppState().targetLang = val);
                  },
                      subtitle: "(Listening Language or Learning Language)",
                      subtitleBelow: true),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    onPressed: () {
                      final String? roomId = _pendingJoinRoomId;
                      setState(() {
                        _showLangOverlay = false;
                        _pendingJoinRoomId = null;
                      });
                      if (roomId != null && roomId.isNotEmpty) {
                        _joinAsGuest(roomId);
                      }
                    },
                    child: const Text("입장하기",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
              IconButton(
                icon: const Icon(Icons.person_add_alt_1,
                    color: Colors.white70, size: 22),
                tooltip: 'Duo 초대장 발행',
                onPressed: _shareInviteCode,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
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
                      ValueListenableBuilder<int>(
                        valueListenable: BillingTicker.instance.billingState,
                        builder: (_, s, __) => CustomPaint(
                          size: const Size(14, 14),
                          painter: BillingDotPainter(s),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(() {
                        final int s = remaining.clamp(0, 999999);
                        final int h = s ~/ 3600;
                        final int m = (s % 3600) ~/ 60;
                        return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
                      }(),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold))
                    ]));
              }),
        ],
      ),
    );
  }

  Widget _buildControlArea(double bottomPadding) {
    final bool isRec = _duoState == 'recording';
    final bool isBusy = _duoState == 'processing' ||
        _duoState == 'playing' ||
        _duoState == 'cooldown';
    final Color accent = isRec
        ? Colors.redAccent
        : (isBusy ? Colors.white38 : const Color(0xFF2563EB));
    return Container(
      padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPadding),
      decoration: const BoxDecoration(color: Color(0xFF121212)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(_pttLabel(),
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0)),
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _onPttStart(),
            onPointerUp: (_) => _onPttEnd(),
            onPointerCancel: (_) => _onPttEnd(),
            child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                    color: accent.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: accent, width: 2.5)),
                child: Icon(isRec ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: accent, size: 38)),
          ),
        ],
      ),
    );
  }

  Widget _buildTextBlock(Map<String, dynamic> msg) {
    String target = msg['target']?.toString() ?? '';
    String original = msg['original']?.toString() ?? '';
    bool isHost = msg['role'] == 'HOST'; // 'HOST'=내 말(우측) / 그 외=상대 말(좌측)

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
              if (_showOriginal &&
                  !(FFAppState().nativeLang.isNotEmpty &&
                      FFAppState().nativeLang == FFAppState().targetLang) &&
                  original.trim().isNotEmpty) ...[
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
// 통역 전용 클래스 — 원문 1개를 받아 [내 타겟 + 내 오리지널] 동시 생성 (단일 GPT 호출)
// ⚠️ 절대 대화에 끼어들지 않음. 오직 번역만 수행 (양방향 통역폰 규칙).
// ============================================================================
class DuoBrain {
  static final http.Client client = http.Client();

  static Future<Map<String, String>?> processTranslation({
    required String key,
    required String text,
    required String srcLang,
    required String myTargetLang,
    required String myNativeLang,
  }) async {
    try {
      Uri uri = Uri.parse('https://api.openai.com/v1/chat/completions');

      String prompt =
          "You are a translation engine for a live interpreter app.\n"
          "You receive ONE utterance and render it into TWO languages.\n"
          "You are NOT a chat assistant. NEVER reply, comment, answer, or ask questions.\n"
          "NEVER continue the conversation. Translate the utterance only.\n\n"
          "Utterance language: $srcLang\n"
          "Output A (target): $myTargetLang\n"
          "Output B (native): $myNativeLang\n\n"
          "Rules:\n"
          "1. \"target\" = the utterance translated into $myTargetLang.\n"
          "2. \"original\" = the utterance translated into $myNativeLang.\n"
          "3. If the utterance is already in one of these languages, just clean it up (fix spacing/typos) for that field.\n"
          "4. Preserve tone, intent, names, and numbers exactly. Do not add or remove meaning.\n"
          "5. If the utterance is unclear or empty, output an empty string for both fields. Never invent content.\n"
          "6. Output strict JSON only, nothing else.\n\n"
          "Output format:\n"
          "{\n"
          "  \"target\": \"<utterance in $myTargetLang>\",\n"
          "  \"original\": \"<utterance in $myNativeLang>\"\n"
          "}\n\n"
          "Utterance: \"$text\"";

      var res = await client
          .post(uri,
              headers: {
                'Authorization': 'Bearer $key',
                'Content-Type': 'application/json; charset=utf-8'
              },
              body: jsonEncode({
                'model': 'gpt-4o-mini',
                'temperature': 0.2,
                'max_tokens': 400,
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
          'target': parsed['target']?.toString() ?? "",
          'original': parsed['original']?.toString() ?? "",
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
