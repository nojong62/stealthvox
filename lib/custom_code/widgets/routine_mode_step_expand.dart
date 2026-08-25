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
// 🏷️ [용어 대응표]
//   · 파일/클래스 이름 : step_expand    (코드에서 쓰는 이름)
//   · Firestore 저장 id : step_expand   (mode 필드 값)
//   · room_name        : "Step.Ex Mode"
//   · 화면 표시명       : Step Expand
//
//   다른 모드 이름 대응은 각 파일 상단 참고:
//     routine_mode_anyone.dart   → 저장 free_talk / 표시 Circle Talk
//     routine_mode_roleplay.dart → 저장 roleplay  / 표시 Scenario Talk
//   별칭 해석 테이블: chat_history_master.dart _inferHistoryMode()
// ====================================================================

import 'index.dart'; // Imports other custom widgets

import '/custom_code/widgets/index.dart';
// 아래 클래스들은 roleplay 사본과 완전히 동일해 이 파일에서는 제거하고 공유한다.
import 'routine_mode_roleplay.dart'
    show TtsCache, ConversationHistory, UnifiedBrain, RelayPipeline;
import '/custom_code/actions/index.dart';
import '/flutter_flow/custom_functions.dart';
import 'package:flutter/services.dart'; // 🔬 [v3.1] Clipboard용
import 'package:flutter/foundation.dart'; // 🎧 [STT-RAW] kDebugMode

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
import 'package:permission_handler/permission_handler.dart';
// 🔧 [v3 추가] TTS 로컬 캐싱 + Firestore 저장용
import 'dart:io';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '/custom_code/actions/billing_ticker.dart';
import '/custom_code/actions/billing_idle_mixin.dart';
import '/custom_code/services/ai_style.dart';
import '/custom_code/services/openai_connection_pool.dart';
import '/custom_code/services/deepgram_prewarm_session.dart';
import '/custom_code/services/origin_language_session.dart';
import '/custom_code/services/openai_streaming_transcribe_prewarm.dart';
import '/custom_code/services/late_continuation.dart';
import '/custom_code/services/conversation_cancel_command.dart';
import '/custom_code/services/openai_streaming_transcribe_session.dart';
import '/custom_code/services/openai_transcribe_service.dart';
import '/custom_code/services/pcm_audio_utils.dart';
import '/custom_code/services/korean_turn_validator.dart';
import '/custom_code/services/step_expansion_builder.dart';
import '/custom_code/services/step_expansion_finalizer.dart';
import 'deepgram_confidence_probe.dart';
import 'first_utterance_context_judge.dart';

/// ==================================================================== [Box
/// 2: 클래스 선언부]
/// ====================================================================
class RoutineModeStepExpand extends StatefulWidget {
  const RoutineModeStepExpand({
    super.key,
    this.width,
    this.height,
    this.onListeningReady,
  });
  final double? width;
  final double? height;
  final VoidCallback? onListeningReady;

  @override
  State<RoutineModeStepExpand> createState() => _RoutineModeStepExpandState();
}

class _RoutineModeStepExpandState extends State<RoutineModeStepExpand>
    with
        SingleTickerProviderStateMixin,
        BillingIdleMixin<RoutineModeStepExpand> {
  // ====================================================================
  // 📦 [Box 3: 상태 변수 및 초기화]
  // ====================================================================
  String _deepgramKey = "";
  String _openAiKey = "";
  static const String _aiVoice = 'nova';
  bool _micPermissionReady = false; // 🆕 마이크 권한 준비 여부(첫 진입 race 방지)
  bool _initialSessionStarted = false; // 🆕 초기 자동 시작 1회성 보장
  bool _isInitialGuidePlaying = false; // 첫 안내 중 유저 발화 시 즉시 중단(barge-in)

  // ── 🙋 [BARGE-IN] AI가 말하는 중에 유저가 끼어들면 즉시 멈춘다 ─────────
  //
  // 오래 비어 있던 자리다. 취소 손잡이(_guideTtsFetcher)는 진작 걸어 뒀지만
  // **소리 나는 동안 마이크가 닫혀 있어** 끊을 방법이 없었다. 이제 AI가 말하는
  // 동안에도 마이크를 열어 두고, 발화가 감지되면 그 자리에서 음성을 자른다.
  //
  // 잘라 놓고 아무 말도 안 하면 유저는 앱이 죽은 줄 안다. 사람이 말을 끊겼을
  // 때 하는 것과 같은 것을 한다 — 짧게 받고, 듣는다.

  /// 지금 나가는 AI 음성이 끼어들기 대상인가. 받아주는 말(ack) 자체는
  /// 대상이 아니다 — 그걸 또 끊으면 무한히 되돌게 된다.
  bool _bargeInArmed = false;

  /// 이번 재생에서 이미 끊었다. 한 번 자른 음성을 두 번 자르지 않는다.
  bool _bargeInFired = false;

  /// 끼어들기로 이미 열려 있는 캡처를 넘겨받는 중. 재생이 끝난 뒤 호출부가
  /// 부르는 [_startUserListening]을 **한 번만** 건너뛴다 — 거기서 캡처를
  /// 다시 열면 유저가 지금 하고 있는 말이 통째로 날아간다.
  bool _bargeInHandoff = false;

  /// AI 음성이 실제로 나가기 시작한 시각. 재생 시작 직후의 짧은 구간은
  /// 무시한다 — 스피커가 열리는 순간의 잡음이 발화로 잡히는 일이 있다.
  DateTime? _bargeInArmedAt;

  /// 이만큼 지난 뒤부터 끼어들기를 받는다.
  static const Duration _kBargeInGrace = Duration(milliseconds: 700);
  // 🎤 [BARGE-IN] 지금 울리고 있는 안내 음성. 유저가 입을 열면 이걸 끊는다.
  ChunkedTtsFetcher? _guideTtsFetcher;
  bool _isConversationActive = false;
  bool _isExiting = false; // 🔧 [EXIT-GUARD] PopScope+버튼 이중 종료 방지
  double _fontScale = 1.0;
  // Step Expand는 대화 집중을 위해 타겟 언어(영어)를 기본 표시한다.
  // 상단 언어 버튼을 누르면 실제 한국어 대화도 함께 확인할 수 있다.
  int _turnCounter = 0;

  /// 🌱 [SEED-PHASE] 씨앗을 아직 못 찾았으면 잡담 구간이다.
  ///
  /// 이 구간에서는 **아무 말도 글로 적지 않는다** — 화면에도, 히스토리에도
  /// 남기지 않고 턴 번호도 먹지 않는다. 씨앗이 잡히는 순간 그 문장 하나가
  /// 화면에 적히고, 5턴 사다리는 거기서부터 선다.
  bool _seedFound = false;

  /// 잡담 구간에서 오간 말. 글로 안 적는 대신 여기에만 쌓아 다음 턴의 문맥으로
  /// 쓴다. 방을 나가면 사라진다 — 저장되는 것은 씨앗부터다.
  final List<String> _smallTalkLog = <String>[];

  /// 구글 뉴스 헤드라인. 방에 들어올 때 한 번 받아 잡담 재료로 쓴다.
  /// 못 받으면 빈 목록이고, 그때는 뉴스 없이 일상 화제로 연다.
  List<String> _newsHeadlines = const <String>[];

  // ── 🔇 [SILENCE-PUSH] 유저가 대답을 안 할 때 AI가 이어 말한다 ──────────
  //
  // 씨앗 전 구간에서 침묵은 거절이 아니라 **아직 유대가 없다는 신호**다.
  // 여기서 가만히 기다리면 유저는 무슨 말을 해야 할지 모르는 채로 남는다.
  // AI가 한 겹 더 얹거나, 각도를 틀거나, 더 쉬운 화제로 갈아탄다.
  //
  // 씨앗이 잡힌 뒤에는 걸지 않는다 — 그때부터는 유저가 답할 차례가 분명하고,
  // 5턴 사다리가 대화를 끌고 간다.
  Timer? _smallTalkSilenceTimer;

  /// 감시를 건 시각. 풀릴 때 "몇 초 만에 유저가 말했는지"를 로그로 남긴다.
  DateTime? _smallTalkSilenceArmedAt;

  /// AI가 연속으로 혼자 이어 말한 횟수. 유저가 입을 열면 0으로 돌아간다.
  int _smallTalkSelfPushes = 0;

  /// 이어 말하기 연속 상한. 3회째부터는 대화가 아니라 방송이 된다.
  static const int _kMaxSmallTalkSelfPushes = 2;

  /// 마지막 말이 끝나고 이만큼 조용하면 AI가 다시 입을 연다.
  static const Duration _kSmallTalkSilenceGap = Duration(seconds: 7);

  String? _pendingHeardConfirmation;
  int _heardConfirmationAttempts = 0;
  String? _sessionDocId; // 🔧 [v3 추가] 첫 대화 후 세션 ID (클론 변경 시 null 리셋)
  DocumentReference? _myHistoryRef; // 🔧 [히스토리] chat_history 문서 참조 (Duo 패턴)
  List<String> _lastExchangeMsgIds = []; // [??] ?? ?? messages docId

  // 🆕 [Anyone 형태 진입 안내] 채팅 말풍선/소리 없이 화면 중앙 사각형 텍스트로
  //    안내만 띄우고 2초 후 자동 페이드아웃. 마이크는 처음부터 열려 있어서
  //    안내가 떠 있는 동안 유저가 말하면 그 발화가 그대로 파이프라인에 들어간다.
  static const String _openingNudgeText = kStepExpandOpeningNudgeText;
  bool _hasSpokenOpening = false; // 세션당 1회 발화 가드
  bool _listeningReadyReported = false;

  // ── Idle Timeout v2 ───────────────────────────────────────────────
  // 기준: "유저도 AI도 아무 작동이 없는 상태"가 연속 60초 지속되면 pause.
  //  - AI 작동 = _ttsQueueManager.isBusy (TTS 재생/대기)
  //  - 유저 작동 = _voiceManager != null (마이크 연결/녹음)
  // 1초 주기 감시 타이머가 작동 여부를 보고 idle 누적초를 증감한다.
  @override
  String get billingModeName => 'study_room';

  @override
  bool get isBillingBusy {
    // 🔊 [IDLE] 연습 재생도 "작동 중"이다. 이 둘이 빠져 있어서, 문장을
    //   반복해 들으며 공부하는 동안 유휴 카운터가 올라가 60초 뒤 과금이
    //   멈췄다 — 가만히 듣기만 하는 연습이 정확히 그 구간이다.
    //   Circle Talk·Scenario Talk은 재생기가 모두 포함돼 있어 이 문제가 없다.
    return _ttsQueueManager.isBusy ||
        _aiTurnActive ||
        _isAiFullPlaying ||
        _isUserFullPlaying;
  }

  // ──────────────────────────────────────────────────────────────────

  // ── [FAST-LANE] 로컬 질문 불만 판정 ───────────────────────────────
  // 모델 호출 전 raw 한국어 transcript에서 질문 불만 표현을 감지.
  // 정상 부정 답변("아니, 안 갔어")은 잡지 않도록 질문 대상 표현 위주로 판정.
  bool _isQuestionDissatisfactionRaw(String text) {
    final t = text.trim().toLowerCase();
    const kws = [
      '질문이 뭐',
      '무슨 질문이',
      '그 질문',
      '이 질문',
      '다른 거 물어봐',
      '다른 질문',
      '다른 걸 물어봐',
      '뭐야 그게',
      '뭐야 이게',
      '그게 뭐야',
      '별론데',
      '재미없어',
      '이상한 질문',
      '이상하네',
      '그건 좀 아닌',
      '그건 별로',
      '그건 싫어',
      '그런 거 말고',
      '질문 바꿔',
      '바꿔줘',
      '다른 걸로',
      '마음에 안 들어',
      '맘에 안 들어',
      '같은 질문',
      // 이미 답한 내용을 다시 묻는 반복 질문 불만
      '아까 말했',
      '이미 말했',
      '방금 말했',
      '이미 대답',
      '아까 대답',
      '그거 말했',
      '말했잖아',
      '대답했잖아',
      '물어봤잖아',
      '같은 걸',
      '또 물어',
      '반복',
      '똑같은 질문',
      // "이거는 조금 전에 질문하고 똑같이…" — 실기기에서 이 어순이 안 잡혀
      //   검증기로 넘어갔고, 전사 오류로 오판돼 되묻기가 나갔다.
      '질문하고 똑같',
      '질문이랑 똑같',
      '질문과 똑같',
      '아까 질문',
      '전에 질문',
      '아까 얘기',
      '이미 얘기',
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

  Widget _buildIdleOverlay() => const SizedBox.shrink();
  // ─────────────────────────────────────────────────────────────────────────

  // 🔧 [v3.4 발화 합치기] 유저 더듬거림 대응
  // 이벤트 종류에 따라 조건부 대기: speech_final=1200ms, UtteranceEnd=500ms
  // 대기 중 새 발화 오면 합쳐서 처리 (최종 한 덩어리로)
  String _pendingTranscript = ''; // 대기 중인 유저 발화 누적
  DateTime? _lastPendingFinalAt;
  Timer? _commitTimer; // "진짜 끝났는지" 확정 타이머
  // 🚀 [SPEC-FIRST-TURN] 첫 턴(seed) 투기적 선시작: 대기창 동안 GPT 번역을 미리 돌려
  //   토큰을 이 컨트롤러에 버퍼링. 확정 시 파이프라인에 그대로 넘겨 TTFT를 겹쳐 없앤다.
  StreamController<String>? _specController;
  StreamSubscription<String>? _specSub;
  String _specTranscript = '';
  Future<String?>? _prefetchedFirstTurnTranscribe;
  int _prefetchedFirstTurnPcmBytes = 0;
  final List<Uint8List> _turnPcmChunks = <Uint8List>[];
  int _turnPcmBytes = 0;
  static const int _turnPcmBufferMaxBytes = 32000 * 60;
  static const Duration _accurateTranscribeTimeout = Duration(seconds: 12);
  static const int COMMIT_WAIT_SPEECH_FINAL_MS = 1200; // speech_final: 1200ms
  static const int COMMIT_WAIT_UNCERTAIN_MS = 500; // UtteranceEnd: 500ms
  // 🚀 [FIRST-TURN] 첫 유저 발화(seed)만: 안전값보다는 짧지만, 말 중간의 짧은 쉼을
  //   견뎌 이어 말하기를 한 덩어리로 합칠 만큼은 준다(짤림 방지). 속도는 투기적
  //   선시작(TTFT 은닉)이 담당하므로 이 대기를 과하게 줄일 필요가 없다.
  static const int COMMIT_WAIT_FIRST_TURN_MS = 650;

  // Deepgram 신뢰도 측정값은 선택적 gpt-4o-transcribe 전사 여부에만 사용한다.
  static const String _probeMode = 'STEP_EXPAND';
  final List<DeepgramTurnResult> _pendingDeepgramResults = [];
  DateTime? _activeProbeDgFinalAt;
  bool _awaitingAiFirstTextProbe = false;
  bool _awaitingAiFirstAudioProbe = false;
  double? _activeSttConfidence;
  int _pipelineGeneration = 0;

  /// 🧹 [DISPOSE-GUARD] dispose 진행 중. 위젯이 이미 defunct라 setState가
  /// 금지된다. GPT 스트리밍 중에 방을 나가면 늦게 도착한 조각이 화면을
  /// 건드리려다 예외를 낸다 — Circle Talk에는 있던 가드가 여기엔 없었다.
  bool _isDisposing = false;

  bool _aiTurnActive = false;

  // 🎙️ 메인 한국어 대화 전용 OpenAI 스트리밍 전사. 완성문장 뒤의 외국어
  // 따라 말하기 Practice는 아래 기존 Deepgram 16kHz 경로를 계속 쓴다.
  OpenAiStreamingTranscribeSession? _streamingStt;
  StreamSubscription<Uint8List>? _streamingCaptureSub;
  Future<void>? _streamingCaptureStopping;
  bool _streamingCaptureOpen = false;
  bool _streamingSessionStarting = false;
  bool _streamingConnectFailed = false;
  bool _streamingTurnInFlight = false;
  bool _streamingPipelineRunning = false;
  int _listenGeneration = 0;
  final Set<String> _handledStreamingItemIds = <String>{};
  String _streamingDeltaItemId = '';
  final StringBuffer _streamingDeltaBuffer = StringBuffer();
  int _streamingDeltaCount = 0;
  Timer? _streamingTranscriptTimeout;
  static const int _kStreamingTranscriptTimeoutMs = 8000;

  // ── 🔁 [LATE-CONTINUATION] 늦은 이어 말하기 (Circle Talk과 같은 규칙) ──
  // 판정·합치기·말풍선 규칙은 `services/late_continuation.dart` 공용 함수를
  // 쓴다. 여기에 규칙을 다시 구현하면 한쪽만 고쳐진다.
  //
  // ⚠️ 이 모드만의 축이 둘이다.
  //   1. **학습 Step 수와 비동기 턴 식별자가 `_turnCounter` 하나에 겹쳐 있다.**
  //      되묻기·실패 턴은 5턴에 세지 않으려고 이 값을 되돌린다. 그래서 늦은
  //      콜백 차단에 이 값을 쓰면 되돌린 번호가 새 턴과 다시 같아진다.
  //      → 차단 전용으로 **되돌지 않는** `_asyncTurnSeq`를 따로 둔다.
  //      학습 진행 계산은 기존 `_turnCounter` 그대로다(감소도 그대로).
  //   2. busy 플래그가 둘(`_streamingPipelineRunning`, `_aiTurnActive`)이고
  //      서로 다른 함수의 finally에서 내려간다. 세대 가드가 없으면 취소된
  //      파이프라인이 새 파이프라인의 busy를 꺼서 [TURN-SKIP]이 뚫린다.

  /// 늦은 콜백 차단 전용 식별자. **절대 되돌지 않는다.**
  /// 학습 진행 수(`_turnCounter`)와 역할이 다르다.
  int _asyncTurnSeq = 0;
  int _activeAsyncTurnId = 0;

  int _userTurnSeq = 0;
  int _activeUserTurnId = 0;
  final List<UserTurnSegment> _turnSegments = <UserTurnSegment>[];
  String _pendingUserTranscript = '';
  int _fallbackSegmentOrder = 0;

  bool _continuationWindowOpen = false;
  DateTime? _speechStoppedAt;
  DateTime? _continuationWaitStartedAt;
  int _continuationWindowSeq = 0;
  int _continuationCandidate = 0;
  int _continuationCandidateSeq = 0;
  bool _aiPlaybackStarted = false;
  Timer? _continuationWindowTimer;
  Timer? _continuationTranscriptTimeout;

  bool get _continuationCandidateAlive => _continuationCandidate != 0;

  int _bubbleSeq = 0;
  String _activeHostBubbleId = '';
  String _activeAiBubbleId = '';

  /// 게이트가 연달아 반려한 횟수. 통과하면 0으로 돌아간다. [GATE-ESCAPE] 참조.
  int _consecutiveGateRejects = 0;
  void _log(String tag, String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    final line = '[$ts] $tag $msg';
    print(line);
    AppLogLedger.instance.add('STEPEXPAND', '$tag $msg');
  }

  void _onDeepgramTurnResult(DeepgramTurnResult result) {
    if (result.transcript.trim().length < 2) return;
    _pendingDeepgramResults.add(result);
    _log(
      '⏱️ [DG_FINAL]',
      'mode=$_probeMode words=${result.words.length} '
          'finalChunks=${result.chunkTranscriptConfidences.length}',
    );
  }

  void _runMeaningProbe(String committedTranscript) {
    _log('⏱️ [MEANING_PROBE_START]', 'mode=$_probeMode');
    final probeStopwatch = Stopwatch()..start();
    final hadDeepgramResult = _pendingDeepgramResults.isNotEmpty;
    final turn = DeepgramTurnResult.merge(
      transcript: committedTranscript,
      results: List<DeepgramTurnResult>.from(_pendingDeepgramResults),
    );
    _pendingDeepgramResults.clear();
    final languageCode = _nativeLangCode();
    // Decision/classification logic always runs (keeps the probe pathway live).
    final probe = DeepgramConfidenceProbe.evaluate(
      turn,
      languageCode: languageCode,
    );
    _activeSttConfidence =
        probe.chunkTranscriptConfidenceMean ?? probe.wordConfidenceMean;
    probeStopwatch.stop();
    _activeProbeDgFinalAt = hadDeepgramResult ? turn.finalizedAt : null;
    final meaningProbeMs =
        (probeStopwatch.elapsedMicroseconds / 1000).toStringAsFixed(3);
    // Verbose line carries the transcript + per-word confidence (PII):
    // debug builds or --dart-define=PROBE_DIAGNOSTICS=true only.
    if (DeepgramConfidenceProbe.detailedLoggingEnabled) {
      final formattedProbe = DeepgramConfidenceProbe.formatLog(
        mode: _probeMode,
        languageCode: languageCode,
        turn: turn,
        probe: probe,
      );
      _log(
        '📊 [MEANING-PROBE]',
        '$formattedProbe meaningProbeMs=$meaningProbeMs',
      );
    }
    _log(
      '⏱️ [MEANING_PROBE_END]',
      'mode=$_probeMode meaningProbeMs=$meaningProbeMs',
    );
  }

  void _logProbeTiming(String event) {
    final dgFinalAt = _activeProbeDgFinalAt;
    if (dgFinalAt == null) return;
    final elapsed = DateTime.now().difference(dgFinalAt).inMilliseconds;
    _log(
      '⏱️ [PERF-PROBE]',
      'mode=$_probeMode event=$event DG_FINAL_TO_$event=${elapsed < 0 ? 0 : elapsed}',
    );
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
    int offset = 0;
    for (final chunk in _turnPcmChunks) {
      pcm.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return pcm;
  }

  Future<String?> _transcribeAccurately({Uint8List? pcmOverride}) {
    final pcm = pcmOverride ?? _snapshotTurnPcm();
    if (pcm == null || pcm.isEmpty || _openAiKey.isEmpty) {
      return Future<String?>.value(null);
    }
    return OpenAiTranscribeService.transcribePcm16(
      apiKey: _openAiKey,
      pcm: pcm,
      language: _sttLangCode(),
      model: OpenAiTranscribeService.firstTurnModel,
      timeout: _accurateTranscribeTimeout,
      onLog: _log,
    );
  }

  /// 🌱 마지막 턴 고정 마무리 문장. 마지막 턴에는 더 물을 것이 없어 되묻기가
  /// 의미를 잃는데, "묻지 말라"는 지시에도 모델이 되묻는 말을 내놓을 때가 있다.
  /// 그대로 두면 [_isAskBackReply]가 턴을 되돌려 완성문장이 영영 나오지 않으므로,
  /// 그때 이 문장으로 갈아 끼워 세션을 정상 종료시킨다.

  /// 🔚 세션을 닫는 고정 한마디. 완성문장 카드와 세련문장 낭독이 다 끝난 뒤
  /// 소리로만 한 번 나간다.
  ///
  /// 고정 문구로 두는 이유: 이걸 만들자고 GPT 호출을 하나 더 붙이면 5턴이
  /// 끝난 자리에서 왕복 지연이 더 생기고, 실패하면 세션이 말없이 끝난다.
  /// 히스토리·완성문장·세련문장 어디에도 넣지 않는다 — 학습 재료가 아니라
  /// 방을 닫는 신호다.
  static const String kStepExpandClosingLine = '이제 확장문장이 완성되었습니다.';

  /// 대화 설계 전문(全文). 매 턴 gpt-4.1-mini의 system 프롬프트로 들어간다.
  /// 예전에는 Realtime 세션을 열 때 한 번만 걸어 두고 턴마다 짧은 지시만
  /// 덧붙였다. 세션이 사라진 지금은 매 턴 이걸 같이 보내야 한다.
  String _buildStepExpandSystemInstructions() =>
      buildStepExpandConsultInstructions(_nativeLangName());

  /// 🌐 [ORIGIN-RESOLVE] 로비값이 아니라 **이 세션에서 확정된 ORIGIN**을 준다.
  ///   유저가 첫 마디를 로비 설정과 다른 언어로 했으면 그 언어가 여기서
  ///   나온다. 세션 한정이라 방을 나가면 로비값으로 돌아간다.
  String _nativeLangName() => resolveNativeLanguageName(
      OriginLanguageSession.instance.resolve(FFAppState().nativeLang));

  String _nativeLangCode() => deepgramLanguageCode(_nativeLangName());

  /// 첫 발화 전사에 넘길 언어 코드. 판정 전에는 **빈 문자열 = 자동 감지**다.
  /// 언어를 박아 두면 다른 언어 발화가 그 언어 문자로 음차되어 나와,
  /// 어긋났다는 사실 자체가 전사문에서 사라진다.
  String _sttLangCode() =>
      OriginLanguageSession.instance.settled ? _nativeLangCode() : '';

  /// 🌐 [ORIGIN-RESOLVE] 첫 발화 전사문으로 이 세션의 ORIGIN을 확정한다.
  /// **세션당 딱 한 번만 돈다** — 대화 도중 외국어가 한 마디 섞여도 안 뒤집힌다.
  Future<void> _settleOriginLanguage(String transcript) async {
    final session = OriginLanguageSession.instance;
    if (session.settled) return;
    final lobbyOrigin = resolveNativeLanguageName(FFAppState().nativeLang);
    final detected = await resolveOriginFromFirstUtterance(
      apiKey: _openAiKey,
      transcript: transcript,
      lobbyOrigin: lobbyOrigin,
      onLog: _log,
    );
    session.adopt(detected);
    // 확정 뒤에는 소켓에도 언어를 박는다. 자동 감지로 계속 두면 짧은 발화에서
    // 언어가 흔들려 전사 정확도가 떨어진다.
    unawaited(_streamingStt?.switchLanguage(_nativeLangCode()) ??
        Future<bool>.value(false));
    if (detected == null) return;
    _log('🌐 [ORIGIN-RESOLVE]',
        'session origin $lobbyOrigin → $detected (this room only)');
    _showOriginSwitchedNotice(detected);
  }

  /// 로비 설정을 바꿔 달라는 안내 말풍선. 세션당 한 번, **감지된 언어로** 뜬다.
  void _showOriginSwitchedNotice(String detectedLanguage) {
    if (!OriginLanguageSession.instance.takeNoticeSlot()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(originLanguageSwitchedNoticeLine(detectedLanguage)),
          duration: const Duration(seconds: 7),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
    });
  }

  String _mapLanguageToCode(String lang) => deepgramLanguageCode(lang);

  // 🌱 스텝익스팬드 전용 상태
  // 🗣️ [ORIGIN-ONLY] MAX_TURNS(5턴 자동 마무리)는 없앴다.
  //   대화는 생각이 충분해졌을 때 끝나지, 다섯 번째 턴에서 끝나지 않는다.
  //   AI는 마무리 분위기만 만들고, 실제 종료는 유저가 방을 나갈 때다.

  /// 사용자 번역·확장과 AI 질문 생성은 모두 같은 경량 모델로 처리한다.
  static const String kStepExpandUserModel = 'gpt-4o-mini';
  // 완성문장 카드가 떠서 마이크를 잠근 상태. 이제 턴 수로는 서지 않고,
  // 유저가 대화를 끝냈을 때만 선다.
  bool _isSessionComplete = false;
  // ⚠️ 아무 데서도 값이 들어가지 않는 죽은 칸이다. 아래 방 안 Practice 패널
  //   전체가 _isPracticeMode를 true로 만드는 곳이 없어 닿지 않는다.
  String _roomPracticeAiSentence = "";
  // 🌱 [NATIVE-EXPAND] 대화방 유저 말풍선은 매 턴 "지금까지 말한 것 + 이번에
  //   말한 것"을 합친 원어 한 문장이다. 1턴은 발화 자체가 씨앗이고, 2턴부터
  //   이 문장이 자란다. Realtime 응답과 무관한 별도 경량 호출로 만든다.
  /// 🚪 [TURN-GATE] 이 턴을 통과시킬지 판정하기 위해서만 들고 있는 문장.
  ///
  /// **더 이상 학습 자료가 아니다.** 예전에는 이 값이 곧 완성문장이었고
  /// P2·P3가 이걸 먹었다. 지금 P2의 원본은 상담 transcript 전체이고,
  /// 사다리는 방을 나간 뒤 [finalizeStepExpansions]가 만든다.
  ///
  /// 그런데 2턴부터의 턴 게이트가 아직 이 값에 붙어 있다 — 자란 문장에 실제로
  /// 붙여 보고 못 붙이면 되묻는 구조([StepExpandBrain.mergeNativeExpansion])라,
  /// 이 값이 없으면 `meta`(대화에 대한 말)·`unclear`(못 알아들음) 판정이 함께
  /// 사라진다. 그래서 계산은 남기고 **바깥으로 나가는 길만 끊었다.**
  String _turnGateSentence = "";

  // 합치기가 실패한 턴의 발화. 버리면 그 턴 내용이 확장 문장에서 통째로
  // 사라지므로, 다음 턴 합치기에 같이 넘겨 따라잡게 한다.
  final List<String> _turnGatePendingParts = [];

  /// 🧩 [MENU-TURN] 직전 턴에 내놓은 후보 문장 셋.
  ///
  /// 유저가 "2번"이라고만 말했을 때 그것이 무슨 문장이었는지 아는 유일한
  /// 근거다. 다음 턴 요청에 그대로 실어 보낸다.
  List<String> _lastMenuOptions = <String>[];

  // 🎯 [PRACTICE] 의미단위 반복 연습 모드
  bool _isPracticeMode = false;
  List<String> _practiceUnits = [];
  int _currentUnitIdx = 0;
  bool _practiceComplete = false;
  bool _isPracticeAiSpeaking = false;
  bool _isPracticeUserListening = false;
  bool _isAiFullPlaying = false;
  bool _isUserFullPlaying = false;
  final AudioPlayer _practicePlayer = AudioPlayer();
  List<int> _userPcmAccumulator = [];
  Set<String> _practiceRecognizedWords = {};
  String? _userWavPath;

  // 오디오 및 UI
  final List<Map<String, dynamic>> _localMessages = [];
  final ScrollController _scrollController = ScrollController();
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
    // 🌐 [ORIGIN-RESOLVE] 이 방의 ORIGIN 판정을 처음 상태로 되돌린다.
    //   전환은 **세션 한정**이다 — prefs에는 쓰지 않으므로 방을 나가면
    //   로비값 그대로다. 여기서 비워야 다음 입장이 새로 판정한다.
    OriginLanguageSession.instance.begin();
    // 잔여시간 소진 시 StealthRoom이 이 경로로 방을 닫는다(저장·정리 포함).
    StealthRoomMaster.saveAndExitCurrentMode = _handleAutoSaveAndExit;
    BillingTicker.instance.appInForeground.addListener(_onForegroundChanged);
    _ttsQueueManager = TtsQueueManager(onPlayStart: () {
      // 🔁 [LATE-CONTINUATION] **실제로 소리가 나기 시작한 순간.** 이 턴의
      //   복구 창을 확실히 닫는다 — 평소에는 enqueue에서 이미 닫힌다.
      _aiPlaybackStarted = true;
      _closeContinuationWindow(reason: 'ai_playback_started');
      if (_awaitingAiFirstAudioProbe) {
        _awaitingAiFirstAudioProbe = false;
        _logProbeTiming('AI_FIRST_AUDIO');
      }
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
    BillingTicker.instance.setSessionIdentifiers();
    // 💰 [BILLING-IDLE] 입장 즉시 과금 + 60초 유휴 감시. 규칙은 공용이다.
    startBillingRoom();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) resetBillingIdle();
    });
  }

  @override
  void dispose() {
    _isDisposing = true;
    _continuationPulse.dispose();
    if (StealthRoomMaster.saveAndExitCurrentMode == _handleAutoSaveAndExit) {
      StealthRoomMaster.saveAndExitCurrentMode = null;
    }
    BillingTicker.instance.appInForeground.removeListener(_onForegroundChanged);
    clearBillingIdle();
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
    final statuses = await [Permission.microphone].request();
    _micPermissionReady = statuses[Permission.microphone]?.isGranted ?? false;
    // 🆕 권한이 늦게 잡히는 경우(재설치 직후 등) 초기 세션 시작을 재트리거.
    if (mounted) _startSessionWhenReady();
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
        // 키 로드 완료 → (권한까지 준비됐을 때만) 시작 안내 후 유저 기본 문장 대기
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startSessionWhenReady();
        });
      }
    } catch (e) {
      print('❌ Key Load Error: $e');
    }
  }

  /// 🆕 첫 진입 race 방지: 키(OpenAI+Deepgram)와 마이크 권한이 "둘 다" 준비됐을
  /// 때만 초기 세션을 1회 시작한다. 준비 안 된 항목이 있으면 조용히 대기 →
  /// 키 로드 콜백(_fetchKeys) 또는 권한 콜백(_initPermissions) 중 늦게 끝나는
  /// 쪽이 이 함수를 다시 호출해 시작을 유발한다. (버튼 재시작 경로와는 분리)
  Future<void> _startSessionWhenReady() async {
    if (!mounted || _initialSessionStarted) return;
    if (_openAiKey.isEmpty) {
      _log('🎤 [START-GATE]', '키 미준비 → 시작 보류');
      return;
    }
    bool hasPerm = _micPermissionReady;
    if (!hasPerm) hasPerm = await _audioRecorder.hasPermission();
    if (!mounted || _initialSessionStarted) return;
    if (!hasPerm) {
      _log('🎤 [START-GATE]', '마이크 권한 미준비 → 시작 보류');
      return;
    }
    _initialSessionStarted = true;
    _startSessionWaitingForUserSeed();
  }

  // ====================================================================
  // 🎯 [스텝익스팬드 대화 설계 원칙]
  // ====================================================================
  // 1. 유저가 먼저 무엇이든 말하면 AI가 기본 씨앗 문장을 만든다 (User-First)
  //    - 세션 시작 시 AI는 시작 안내만 하고 대기
  //    - 유저 첫 발화의 핵심 의미로 짧고 완전한 확장 seed를 생성
  //
  // 2. AI는 시작 안내와 동시에 듣기 시작 (Guided Barge-in)
  //    - "오늘은 어떤 순간을 영어로 풀어 볼까요?"
  //    - OpenAI 질문 생성 API 호출 없음
  //    - STT를 먼저 열고, 유저가 말하면 안내 TTS를 즉시 중단
  //
  // 3. 마이크 버튼 없음 (No Mic Button)
  //    - 안내문 재생 전 STT 자동 시작 (유저가 버튼 누를 필요 없음)
  //    - 화면 하단은 노란 불빛 인디케이터만 표시 → 채팅 공간 최대화
  //
  // 4. 이후 AI는 기존 5턴 확장 패턴대로 짧은 유도 질문을 한다
  //    - 대화 패턴과 확장 로직은 기존 유지
  // ====================================================================

  /// 세션 시작: 안내문을 표시하고 씨앗 재료가 될 유저 첫 발화 대기
  Future<void> _startSessionWaitingForUserSeed() async {
    if (_openAiKey.isEmpty || !mounted) return;
    if (_isSessionComplete) return;
    resetBillingIdle();
    _isConversationActive = true;

    _ttsQueueManager.setUserTurn(false);
    _ttsQueueManager.setAiPaused(false);

    // 🗣️ 첫 마디를 끝까지 들려준 뒤에 마이크를 연다.
    //    동시에 열어 봤더니 Deepgram이 빈 전사(chunk="")만 돌려줬다. 스피커로
    //    AI 목소리가 나가는 동안에는 echoCancel이 입력을 통째로 눌러, 유저가
    //    무슨 말을 해도 아무것도 안 잡힌다. 바지인보다 입력이 먼저다.
    await _speakOpeningOnce();
    await _startUserListening();
    // 🔇 [SILENCE-PUSH] 첫 마디에 대답이 없는 자리가 가장 위험하다. 처음 만난
    //   사람에게 말을 걸어 놓고 그대로 침묵하면 유저는 무슨 말을 해야 할지
    //   모르는 채로 남는다. 여기서부터 감시를 건다.
    _armSmallTalkSilence(_pipelineGeneration);
  }

  /// 진입 첫 마디를 말풍선 + 음성으로 한 번만 내보낸다.
  /// 문구는 gpt-4.1-mini가 매번 새로 만들고, 실패하면 고정 문구로 떨어진다.
  Future<void> _speakOpeningOnce() async {
    if (_hasSpokenOpening || !mounted) return;
    _hasSpokenOpening = true;
    final nativeLang = _nativeLangName();
    // 첫인상은 매번 달라지는 잡담이 아니라 이 방의 약속이어야 한다.
    // 날씨·뉴스로 열면 유저는 글짓기 코치가 아니라 자유대화방으로 받아들인다.
    final opening = nativeLang == 'Korean'
        ? _openingNudgeText
        : await StepExpandBrain.generateOpening(
            apiKey: _openAiKey,
            languageName: nativeLang,
            fallback: localizedSeedGuidanceLine(nativeLang),
          );
    // 문구를 기다리는 동안 유저가 먼저 입을 열었으면 첫 마디는 접는다.
    if (!mounted ||
        !_isConversationActive ||
        _turnCounter != 0 ||
        opening.isEmpty) {
      return;
    }
    if (_pendingTranscript.isNotEmpty) {
      _log('🗣️ [OPENING-SKIP]', '유저가 먼저 말함 → 첫 마디 생략');
      return;
    }
    // 🌱 첫 마디도 글로 적지 않는다. 여기는 아직 잡담 구간이다.
    _rememberSmallTalk('ai', opening);
    // AI가 실제로 뭐라고 했는지 남긴다. 길이만 찍던 동안은 말투가 어떻게
    // 나가는지 로그로 확인할 방법이 아예 없었다 — 유저 체감에만 의존했다.
    // 유저 발화가 아니라 AI 자기 출력이라 릴리스에서도 남긴다.
    _log('💬 [AI-LINE]', 'phase=opening text="$opening"');
    _lastAiSpokenLine = opening;
    // 오프닝도 끼어들 수 있다. speech_started만으로 자르지 않고 completed
    // 전사문을 자기 에코와 비교한 뒤 실제 유저 말일 때만 자른다.
    await _speakKoreanInternal(opening,
        timeoutTag: '⚠️ [OPENING-TTS-TIMEOUT]', allowBargeIn: true);
  }

  void _rememberSmallTalk(String who, String text) {
    if (text.trim().isEmpty) return;
    _smallTalkLog.add('$who: ${text.trim()}');
    // 잡담이 길어져도 프롬프트는 최근 것만 본다. 오래된 말까지 실어 보내면
    // 토큰만 먹고 AI가 이미 지나간 화제로 되돌아간다.
    //
    // 10줄에서 16줄로 늘렸다. 실기기(2026-08-21)에서 씨앗이 잡힌 순간
    // smallTalkLines=10 — 상한에 닿아 **뉴스로 연 초반 화제가 이미 창 밖으로
    // 밀려난 뒤**였다. 잘못 들은 낱말을 가리는 근거가 그 화제인데, 정작 판정할
    // 때 그게 없으면 "공약/공격"을 또 놓친다.
    //
    // 16줄에서 30줄로 다시 늘렸다. 씨앗을 늦게 잡도록 바꾼 뒤로는 잡담이 그만큼
    // 길어지는데, 씨앗 판정의 근거가 "아까 꺼냈던 말로 다시 돌아왔는가"다.
    // 그 근거가 창 밖으로 밀려나면 판정 자체가 성립하지 않는다.
    while (_smallTalkLog.length > 30) {
      _smallTalkLog.removeAt(0);
    }
  }

  String _smallTalkContext() => _smallTalkLog.join(String.fromCharCode(10));

  // ====================================================================
  // ❓ [ASK-RATIO] 반영 2 : 질문 1
  // --------------------------------------------------------------------
  // 동기면담(Motivational Interviewing)의 실제 훈련 기준이다 — 숙련 상담자는
  // 질문보다 반영을 두 배 많이 한다. 초심자는 정반대로 질문을 쌓는다.
  //
  // 실기기(2026-08-23)에서 확장 4턴이 전부 질문으로 끝났다. 프롬프트로 "질문은
  // 꼬리"라고 시켜도 안 지켜진다 — 모델은 자기가 직전에 몇 번 물었는지 세지
  // 않는다. 그래서 세는 일은 코드가 하고, 프롬프트에는 판정만 넘긴다.
  //
  // 규칙: **한 번 물었으면 다음 두 턴은 묻지 않는다.** 직전 두 턴 중 하나라도
  // 질문이면 이번 턴은 금지. 그러면 질문이 세 턴에 한 번으로 떨어진다.
  // ====================================================================

  /// 물음표는 한국어에서도 그대로 쓴다. 전각까지 함께 본다.
  static bool _hasQuestionMark(String text) =>
      text.contains('?') || text.contains('？');

  /// 질문 금지 턴인데 모델이 물었다. 물음표가 든 문장을 잘라낸다.
  ///
  /// 코드가 "이번 턴은 묻지 마라"를 넘겼는데도 모델이 물었다(실기기
  /// 2026-08-23: `avoidQ=true asked=true`). 시켜서 안 되면 잘라낸다.
  /// 잘라낸 뒤 아무것도 안 남으면 원문을 그대로 쓴다 — 질문이라도 있는 편이
  /// 침묵보다 낫다.
  static String _stripQuestions(String text) {
    final parts = text.split(RegExp(r'(?<=[.!?？。！])\s*'));
    final kept = parts
        .where((p) => p.trim().isNotEmpty && !_hasQuestionMark(p))
        .map((p) => p.trim())
        .toList();
    if (kept.isEmpty) return text;
    return kept.join(' ');
  }

  /// 유저 말을 요약해 판정으로 되돌려주는 첫머리. 관찰자의 말투다.
  ///
  /// 프롬프트 BANNED 목록 맨 앞에 적어 뒀는데도 그대로 나왔다(실기기
  /// 2026-08-23: "그러니까 집을 단순히 자산으로 보는 게 아니라 … 말이네요").
  static final RegExp _kSummaryVerdict = RegExp(
    r'^(그러니까|그럼|결국|정리하자면|말하자면)[^.!?]{0,80}'
    r'(거네요|거군요|말이네요|말씀이네요|뜻이네요|셈이네요)'
    r'|(보다는|보다도)[^.!?]{0,60}(더\s*중요|더\s*의미|더\s*큰\s*의미)[^.!?]{0,20}(네요|보네요)'
    r'|결국[^.!?]{0,60}(닿아\s*있|이어져\s*있)',
  );

  static bool _looksLikeSummaryVerdict(String text) =>
      _kSummaryVerdict.hasMatch(text.trim());

  /// 확장 구간: 같은 규칙. 화면에 올라간 AI 말풍선을 본다.
  bool _expandMustNotAsk() {
    final aiLines = _localMessages
        .where((m) =>
            m['role'] == 'SYSTEM' &&
            (m['target'] ?? '').toString().trim().isNotEmpty)
        .toList(growable: false);
    if (aiLines.isEmpty) return false;
    final recent =
        aiLines.length > 2 ? aiLines.sublist(aiLines.length - 2) : aiLines;
    return recent.any((m) => _hasQuestionMark(m['target'].toString()));
  }

  /// 잘못 들은 낱말을 가려낼 때 쓰는 배경.
  ///
  /// 문장만 보면 "공약"과 "공격"을 구분할 방법이 없다. 뉴스로 연 잡담과 지금까지
  /// 오간 말이 함께 있어야 어느 쪽을 말한 것인지 판정할 수 있다.
  String _topicContextForRepair() {
    final parts = <String>[];
    final chat = _smallTalkContext().trim();
    if (chat.isNotEmpty) parts.add(chat);
    final recent = _recentKoreanConversationForValidation().trim();
    if (recent.isNotEmpty) parts.add(recent);
    return parts.join(String.fromCharCode(10));
  }

  // ====================================================================
  // 🔇 [SILENCE-PUSH] 유저가 조용하면 AI가 이어 말한다 (씨앗 전 구간 전용)
  // ====================================================================

  /// 침묵 감시를 건다. 마이크를 연 **뒤에** 부른다 — 소리가 나는 동안 걸면
  /// AI 자기 목소리가 끝나기 전에 타이머가 익는다.
  void _armSmallTalkSilence(int generation) {
    _smallTalkSilenceTimer?.cancel();
    if (_seedFound || !_isConversationActive || _isSessionComplete) {
      _log('🔇 [SILENCE-ARM]',
          'skip reason=phase seed=$_seedFound active=$_isConversationActive');
      return;
    }
    if (_smallTalkSelfPushes >= _kMaxSmallTalkSelfPushes) {
      _log('🔇 [SILENCE-ARM]',
          'skip reason=cap pushes=$_smallTalkSelfPushes/$_kMaxSmallTalkSelfPushes → 조용히 기다린다');
      return;
    }
    // 🔎 [관측] 건 시점을 남긴다. 이걸 안 남겼더니 실기기 로그(2026-08-23)에서
    //   "감시를 걸었는데 유저가 먼저 말해 조용히 풀린 것"과 "애초에 안 걸린 것"을
    //   구분할 방법이 없었다 — 발동 로그만으로는 판정이 안 된다.
    _smallTalkSilenceArmedAt = DateTime.now();
    _log('🔇 [SILENCE-ARM]',
        'armed gap=${_kSmallTalkSilenceGap.inSeconds}s pushes=$_smallTalkSelfPushes');
    _smallTalkSilenceTimer = Timer(_kSmallTalkSilenceGap, () {
      unawaited(_pushSmallTalkAlone(generation));
    });
  }

  /// 유저가 입을 열었다. 감시를 풀고 연속 횟수도 되돌린다.
  void _cancelSmallTalkSilence({required String reason}) {
    final hadTimer = _smallTalkSilenceTimer != null;
    if (!hadTimer && _smallTalkSelfPushes == 0) return;
    _smallTalkSilenceTimer?.cancel();
    _smallTalkSilenceTimer = null;
    if (hadTimer) {
      final armedAt = _smallTalkSilenceArmedAt;
      final waited = armedAt == null
          ? -1
          : DateTime.now().difference(armedAt).inMilliseconds;
      _log('🔇 [SILENCE-ARM]',
          'cancel reason=$reason waitedMs=$waited pushes=$_smallTalkSelfPushes');
    }
    _smallTalkSilenceArmedAt = null;
    _smallTalkSelfPushes = 0;
  }

  /// 대답이 없다. AI가 혼자 한 마디 더 얹는다.
  Future<void> _pushSmallTalkAlone(int generation) async {
    if (!mounted ||
        generation != _pipelineGeneration ||
        !_isConversationActive ||
        _isSessionComplete ||
        _seedFound) {
      return;
    }
    // 그사이 유저가 말을 시작했으면 이어 말하지 않는다. 말을 겹치면 안 된다.
    if (_pendingTranscript.trim().isNotEmpty || _ttsQueueManager.isBusy) {
      _log('🔇 [SILENCE-PUSH]', 'abort reason=user_or_tts_active');
      return;
    }
    _smallTalkSelfPushes++;
    _log(
        '🔇 [SILENCE-PUSH]',
        'fire push=$_smallTalkSelfPushes/$_kMaxSmallTalkSelfPushes '
            'smallTalkLines=${_smallTalkLog.length}');
    // 침묵했다고 날씨·뉴스 잡담으로 새지 않는다. 코치의 역할을 한 번 더
    // 분명히 하고, 유저가 완성문장을 준비해야 한다는 부담만 낮춘다.
    final nativeLang = _nativeLangName();
    final result = <String, String>{
      'reply': nativeLang == 'Korean'
          ? '완성된 문장이 아니어도 괜찮아요. 떠오르는 단어 하나면 제가 시작점을 잡아드릴게요.'
          : localizedSeedGuidanceLine(nativeLang),
    };
    if (!mounted ||
        generation != _pipelineGeneration ||
        !_isConversationActive ||
        _seedFound) {
      return;
    }
    final reply = (result['reply'] ?? '').trim();
    if (reply.isEmpty) {
      _log('🔇 [SILENCE-PUSH]', 'empty_reply → 조용히 기다린다');
      return;
    }
    // 말하기 직전에 한 번 더 본다. 생성을 기다리는 동안 유저가 입을 열었을 수 있다.
    if (_pendingTranscript.trim().isNotEmpty) {
      _log('🔇 [SILENCE-PUSH]', 'abort_before_speak reason=user_started');
      return;
    }
    _rememberSmallTalk('ai', reply);
    _log('💬 [AI-LINE]',
        'phase=silence_push attempt=$_smallTalkSelfPushes text="$reply"');
    await _speakLiveKorean(reply);
    if (!mounted || generation != _pipelineGeneration || _seedFound) return;
    if (_isConversationActive && !_isSessionComplete) {
      await _startUserListening();
      _armSmallTalkSilence(generation);
    }
  }

  // ====================================================================
  // 📦 [Box 4: 주제 관리 (5턴 사이클 + 새 주제 버튼)]
  // ====================================================================
  // 💡 매 턴마다 Firestore에 저장되므로(_saveTurnToFirestore arrayUnion)
  //    별도의 "저장 후 리셋" 로직 불필요 — 새 주제 버튼은 UI 리셋만 수행
  //    단, 완성된 문장이 없으면 유저에게 안내 다이얼로그 표시

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
    await _practiceSpeakText(unit, _aiVoice);
    if (!mounted) return;
    setState(() {
      _isPracticeAiSpeaking = false;
      _isPracticeUserListening = true;
    });
    _practiceRecognizedWords.clear();
    _startPracticeListening();
  }

  /// 유저 따라 말하기 STT 시작 (target 언어로 인식)
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
      // Practice 모드: commit 대기창 미사용, 시그니처만 맞춤
      onTurnEnded: (transcript, {bool speechFinal = false}) {
        BillingTicker.instance.resumeFromActivity('step_expand_practice_stt');
        _checkPracticeWordRatio(transcript);
      },
      onError: (_) => _practiceAdvanceUnit(),
      onAudioData: (bytes) => _userPcmAccumulator.addAll(bytes),
    );
    _voiceManager!.connectAndStart();
    BillingTicker.instance.resumeFromActivity('step_expand_practice_start');
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
    if (_roomPracticeAiSentence.isEmpty) return;
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
    await _practiceSpeakText(_roomPracticeAiSentence, _aiVoice);
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

  String _recentKoreanConversationForValidation() {
    final turns = _localMessages.where((message) {
      final role = message['role']?.toString() ?? '';
      final text = message['target']?.toString().trim() ?? '';
      return (role == 'HOST' || role == 'SYSTEM') && text.isNotEmpty;
    }).toList();
    final recent = turns.length > 10 ? turns.sublist(turns.length - 10) : turns;
    return recent.map((message) {
      final speaker = message['role'] == 'HOST' ? 'USER' : 'AI';
      return '$speaker: ${message['target']}';
    }).join('\n');
  }

  /// 다음 질문을 만드는 모델에게 주는 **대화 전부**.
  ///
  /// 씨앗을 찾기 전 잡담은 화면에 적히지 않으므로 [_localMessages]에 없다.
  /// 그래서 질문 생성기만 "지금까지 무슨 이야기를 하고 있었는지"를 못 봤다.
  /// 씨앗 턴에 모델이 받는 문맥은 문장 한 줄뿐이었고, 문맥이 한 줄이면 붙잡을
  /// 것이 그 문장 속 명사밖에 없다 — 실기기에서 "부정이 있었으면 세월이 지나도
  /// 밝혀내야 되겠지"가 "그 부정은 어떤 형태여야 할까요?"로 돌아온 이유다.
  /// 합치기는 이미 [_topicContextForRepair]로 잡담을 받고 있었다. 질문
  /// 생성기만 빠져 있었다.
  String _questionContext({String currentUserLine = ''}) {
    final lines = <String>[];
    final chat = _smallTalkContext().trim();
    if (chat.isNotEmpty) {
      lines.add('[HOW THIS CONVERSATION STARTED]');
      // 잡담 로그는 'user:'/'ai:'로 적는다. 확장 턴 쪽 표기와 맞춰 둔다 —
      // 한 덩어리 안에서 화자 표기가 두 가지면 모델이 다른 대화로 읽는다.
      for (final line in chat.split(String.fromCharCode(10))) {
        lines.add(line
            .replaceFirst(RegExp(r'^user:\s*'), 'USER: ')
            .replaceFirst(RegExp(r'^ai:\s*'), 'AI: '));
      }
    }
    final recent = _recentKoreanConversationForValidation().trim();
    if (recent.isNotEmpty) {
      if (lines.isNotEmpty) lines.add('');
      lines.add('[SINCE THEN]');
      lines.addAll(recent.split(String.fromCharCode(10)));
    }
    final current = currentUserLine.trim();
    if (current.isNotEmpty) {
      if (lines.isNotEmpty) lines.add('');
      lines.add('[WHAT THEY JUST SAID, IN THEIR OWN WORDS]');
      lines.add('USER: $current');
    }
    return lines.join(String.fromCharCode(10));
  }

  /// 대화방에서만 쓰는 한국어 AI 음성. tts-1/nova로 재생하되 캐시에
  /// 저장하지 않아, 히스토리의 타겟 언어 음성 생성 규칙과 분리한다.
  Future<void> _speakLiveKorean(String text) async {
    // 🔁 [LATE-CONTINUATION] 소리가 나기 전에 마이크를 닫아야 [MIC-ROUTING]이
    //   지켜진다. AI 질문도 되묻기도 이 길로 나간다.
    _closeContinuationWindow(reason: 'tts_enqueue');
    _lastAiSpokenLine = text.trim();
    await _speakKoreanInternal(text,
        timeoutTag: '⚠️ [KOREAN-TTS-TIMEOUT]', allowBargeIn: true);
  }

  /// AI 음성을 낸다. [allowBargeIn]이면 소리 나는 동안 마이크를 열어 두고,
  /// 유저가 입을 열면 그 자리에서 음성을 자른다(§[BARGE-IN]).
  Future<void> _speakKoreanInternal(
    String text, {
    required String timeoutTag,
    required bool allowBargeIn,
  }) async {
    final spoken = text.trim();
    if (spoken.isEmpty || _openAiKey.isEmpty) return;
    _ttsQueueManager.setUserTurn(false);
    _ttsQueueManager.setAiPaused(false);
    final fetcher = ChunkedTtsFetcher(
      _openAiKey,
      _ttsQueueManager,
      _aiVoice,
      language: _nativeLangCode(),
      cacheEnabled: false,
      isUser: false,
      onLog: _log,
    );
    // 이전 안내가 남아 있으면 먼저 끊어, 취소 대상이 항상 지금 울리는 하나만
    // 되게 한다.
    _guideTtsFetcher?.cancel();
    _guideTtsFetcher = fetcher;
    _isInitialGuidePlaying = true;

    // 🙋 [BARGE-IN] TTS보다 마이크를 먼저 연다. 비동기로 열면 직전 턴의
    // capture_stopped와 경합해 armed만 남고 실제 캡처가 닫힐 수 있다.
    //   받아주는 말(ack) 자체는 대상이 아니다. 그걸 또 끊으면 되돌게 된다.
    if (allowBargeIn) {
      _bargeInFired = false;
      _bargeInArmed = true;
      _bargeInArmedAt = DateTime.now();
      _log('🙋 [BARGE-IN]', 'armed graceMs=${_kBargeInGrace.inMilliseconds}');
      final stopping = _streamingCaptureStopping;
      if (stopping != null) await stopping;
      await _startUserListening();
      if (kFreeTalkUseStreamingStt && !_streamingCaptureOpen) {
        _bargeInHandoff = false;
        await _startUserListening();
      }
      _log('🙋 [BARGE-IN]',
          'mic_ready=$_streamingCaptureOpen gate=${_streamingStt?.audioGateOpen == true}');
    }
    // 실제 캡처 준비가 끝난 뒤에만 코치 음성을 시작한다.
    fetcher.addText(spoken);

    int ticks = 0;
    try {
      while ((fetcher.pendingRequests > 0 || _ttsQueueManager.isBusy) &&
          mounted &&
          !fetcher.isCancelled) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (++ticks > 600) {
          _log(timeoutTag, 'AI 음성 30초 초과');
          break;
        }
      }
    } finally {
      if (allowBargeIn) {
        _bargeInArmed = false;
        _bargeInArmedAt = null;
      }
      // 그 사이 다음 안내가 시작됐다면 그쪽 상태를 건드리지 않는다.
      if (identical(_guideTtsFetcher, fetcher)) {
        _guideTtsFetcher = null;
        _isInitialGuidePlaying = false;
      }
    }
  }

  /// 유저가 AI 말을 끊고 들어왔다. 소리를 그 자리에서 자르고 짧게 받는다.
  ///
  /// 캡처는 **닫지 않는다.** 지금 유저가 말하는 중이고 그 소리는 이미 세션으로
  /// 흘러가고 있다. 여기서 마이크를 다시 열면 그 발화가 통째로 사라진다.
  /// 그래서 [_bargeInHandoff]를 세워, 재생이 끝난 뒤 호출부가 부르는
  /// [_startUserListening]을 한 번 건너뛰게 한다.
  void _handleBargeIn() {
    if (!_bargeInArmed || _bargeInFired) return;
    final armedAt = _bargeInArmedAt;
    if (armedAt != null &&
        DateTime.now().difference(armedAt) < _kBargeInGrace) {
      // 스피커가 열리는 순간의 잡음이 발화로 잡히는 일이 있다. 이 구간은 흘린다.
      _log('🙋 [BARGE-IN]', 'ignored reason=grace');
      return;
    }
    _bargeInFired = true;
    _bargeInArmed = false;
    _bargeInHandoff = true;
    _log('🙋 [BARGE-IN]', 'fired → AI 음성만 중단, 전사 내용으로 바로 응답');
    // 기존 AI 턴의 busy 소유권을 폐기해야 바로 뒤의 실제 유저 전사가
    // [TURN-SKIP]에서 버려지지 않고 새 턴을 소유한다.
    if (_aiTurnActive || _streamingPipelineRunning) {
      _invalidateAssistantTurn(reason: 'barge_in');
    }
    _guideTtsFetcher?.cancel();
    _guideTtsFetcher = null;
    _ttsQueueManager.stop();
    _isInitialGuidePlaying = false;
    // "네, 말씀하세요" 같은 별도 TTS를 넣지 않는다. 마이크는 AI가 말하기
    // 전부터 계속 PCM을 보내고 있어 유저 발화의 첫머리까지 이미 서버에 있다.
    // 전사 완료 콜백이 그 내용을 방금 대화 문맥과 함께 정상 파이프라인으로
    // 넘긴다. 중간 확인 음성을 재생하면 오히려 유저 발화와 겹친다.
  }

  /// 유저가 직전 AI 질문에 불만을 표시했을 때, 그 질문을 지우고 새로 만든다.
  /// 불만 발화 자체는 학습 턴으로 세지 않는다 — 유저는 답을 한 게 아니라
  /// 질문을 물린 것이다. 자란 문장도 건드리지 않는다.
  Future<void> _replaceLastQuestion({
    required int generation,

    /// 유저가 질문을 물리면서 실제로 한 말. 있으면 그대로 넘긴다 — "다른 질문을
    /// 해라"만 시키면 방금 "학문적으로 묻지 말라"고 한 유저에게 또 학문적인
    /// 질문이 나갈 수 있다. 무엇이 싫었는지는 유저가 이미 말해 줬다.
    String userAsk = '',
  }) async {
    var rejected = '';
    setState(() {
      _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
      final idx = _localMessages.lastIndexWhere((m) => m['role'] == 'SYSTEM');
      if (idx != -1) {
        rejected = (_localMessages[idx]['target'] ?? '').toString().trim();
        _localMessages.removeAt(idx);
      }
    });
    _scrollToBottom();

    final askedFor = userAsk.trim().isEmpty
        ? ''
        : 'What they said about it: "${userAsk.trim()}"\n'
            'Take that at face value and give them exactly what they asked for.\n';
    final replacement = await StepExpandBrain.generateKoreanTurn(
      apiKey: _openAiKey,
      instructions: '${_buildStepExpandSystemInstructions()}\n'
          '\n[THIS TURN]\n${_buildStepExpandTurnInstructions(_turnCounter + 1)}\n'
          '\n[THE USER TURNED DOWN YOUR LAST QUESTION]\n'
          'Your previous question was: "$rejected"\n'
          '$askedFor'
          'They found it repetitive, off, or hard to answer. Ask a completely '
          'different one — different angle, different wording. Never repeat or '
          'rephrase the rejected question. Do not apologize, do not mention '
          'that they complained, and do not explain yourself. Just ask.',
      // 🚪 합쳐진 문장을 먹이지 않는다. 프롬프트가 "지금까지 말한 것의
      //   합본을 읽어 주지 말라"고 못 박은 그 물건이다. 질문 생성기는
      //   대화 자체를 본다.
      userText: userAsk.trim(),
      recentConversation: _questionContext(),
    );
    if (!mounted ||
        !_isConversationActive ||
        generation != _pipelineGeneration) {
      return;
    }
    if (replacement.isEmpty) {
      _log('🟠 [FAST-DISSATISFIED-ERR]', '새 질문 생성 실패 → 다시 듣기');
      if (!_isSessionComplete) _startUserListening();
      return;
    }
    setState(() {
      _localMessages.add(<String, dynamic>{
        'role': 'SYSTEM',
        'target': replacement,
        'original': '',
      });
    });
    _scrollToBottom();
    _log('🟠 [FAST-DISSATISFIED]', 'rejected="$rejected" new="$replacement"');
    await _speakAiKorean(replacement);
    if (mounted && _isConversationActive && !_isSessionComplete) {
      _startUserListening();
    }
  }

  /// 확장 턴 질문을 소리로 낸다. 잡담 쪽과 같은 길을 쓴다.
  ///
  /// 오랫동안 "손잡이는 걸어 뒀지만 소리 나는 동안 마이크가 닫혀 있어 끊을 수
  /// 없다"는 상태였다. 이제 [_speakKoreanInternal]이 재생 중에도 마이크를
  /// 열어 두므로 이 길도 실제로 끊긴다(§[BARGE-IN]).
  /// 코치가 방금 소리 내어 말한 줄. [_looksLikeSelfEcho]가 이걸 본다.
  String _lastAiSpokenLine = '';

  Future<void> _speakAiKorean(String text) async {
    _lastAiSpokenLine = text;
    await _speakKoreanInternal(text,
        timeoutTag: '⚠️ [AI-TTS-TIMEOUT]', allowBargeIn: true);
  }

  void _stopEverything() {
    _pipelineGeneration++;
    _isConversationActive = false;
    _aiTurnActive = false;
    _commitTimer?.cancel();
    _commitTimer = null;
    _cancelSmallTalkSilence(reason: 'stop_everything');
    _bargeInArmed = false;
    _bargeInFired = false;
    _bargeInHandoff = false;
    _bargeInArmedAt = null;
    _cancelSpeculativeTranslation(); // 🚀 [SPEC] 진행 중 투기 번역 정리
    _prefetchedFirstTurnTranscribe = null;
    _prefetchedFirstTurnPcmBytes = 0;
    _resetTurnPcmBuffer();
    _pendingHeardConfirmation = null;
    _heardConfirmationAttempts = 0;
    _pendingTranscript = '';
    _lastPendingFinalAt = null;
    _pendingDeepgramResults.clear();
    _activeProbeDgFinalAt = null;
    _awaitingAiFirstTextProbe = false;
    _awaitingAiFirstAudioProbe = false;
    // 메인 대화의 스트리밍 소켓은 턴 사이에는 유지하지만, 방/주제 종료와
    // Practice 진입에서는 마이크와 함께 완전히 닫는다.
    _listenGeneration++;
    _streamingTranscriptTimeout?.cancel();
    _streamingTranscriptTimeout = null;
    _handledStreamingItemIds.clear();
    _streamingDeltaItemId = '';
    _streamingDeltaBuffer.clear();
    _streamingDeltaCount = 0;
    _streamingTurnInFlight = false;
    _streamingPipelineRunning = false;
    unawaited(_stopStreamingCapture(reason: 'stop_everything'));
    // 🔁 [LATE-CONTINUATION] 타이머와 잠정 상태를 놓는다. 남겨 두면 화면을
    //   떠난 뒤 타이머가 깨어나 defunct 위젯에 손을 댄다.
    _streamingTurnInFlight = false;
    _closeContinuationWindow(reason: 'stop_everything');
    _resetContinuationState();
    final closingStreamingStt = _streamingStt;
    _streamingStt = null;
    if (closingStreamingStt != null) unawaited(closingStreamingStt.dispose());
    _voiceManager?.dispose();
    _voiceManager = null;
    _ttsQueueManager.setAiPaused(false); // 🔧 [v3.6] TTS 대기 플래그 초기화
    _ttsQueueManager.setUserTurn(false);
    _ttsQueueManager.stop();
    _practicePlayer.stop();
    if (mounted) setState(() {});
  }

  /// 전사가 발화가 아니라 잡음·추임새인지 판정한다. 파이프라인 진입 전 검열이
  /// 이 함수 하나를 쓴다. 추임새를 통과시키면 "음." 같은 게 "Um."으로 번역돼
  /// 유저 목소리로 나가고 AI가 거기에 대답한다(Anyone 실기기에서 발생).
  bool _isNoiseTranscript(String text) {
    final clean = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s가-힣]'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
    if (clean.isEmpty) return true;
    // 한 글자짜리 한국어 명사도 Step Expand에서는 훌륭한 씨앗이다.
    // 꿈/돈/집/일을 길이만 보고 잡음으로 버리면 "한 단어부터" 시작할 수 없다.
    if (clean.length == 1 && !RegExp(r'^[가-힣]$').hasMatch(clean)) return true;
    const ghostWords = <String>[
      'thankyou',
      'thanks',
      'yeah',
      'okay',
      '감사합니다',
      '네',
      '응',
    ];
    if (ghostWords.contains(clean)) return true;
    // 단독 추임새/감탄사만으로 이뤄진 발화 (흠, 음음, 어어, 아아 ...)
    if (RegExp(r'^[흠음어아으네넵응윽허헐하흐엄음]{1,4}$').hasMatch(clean)) {
      return true;
    }
    return false;
  }

  /// 메인 한국어 대화의 STT 진입점. 기본은 Circle Talk과 같은 OpenAI
  /// Server VAD + 스트리밍 전사이고, 소켓 연결 자체가 실패할 때만 기존
  /// Deepgram 경계 + WAV 재전사 경로로 폴백한다.
  Future<void> _startUserListening() async {
    // 🙋 [BARGE-IN] 끼어들기로 열려 있는 캡처를 그대로 쓴다. 여기서 다시 열면
    //   유저가 지금 하고 있는 말이 사라진다. 한 번만 건너뛴다.
    if (_bargeInHandoff) {
      _bargeInHandoff = false;
      _log('🙋 [BARGE-IN]', 'listen_handoff — 열려 있는 캡처를 그대로 이어 쓴다');
      return;
    }
    if (!kFreeTalkUseStreamingStt) {
      await _startDeepgramListening();
      return;
    }
    _streamingConnectFailed = false;
    await _startStreamingListening();
    if (_streamingCaptureOpen) return;
    if (!_streamingConnectFailed || _deepgramKey.isEmpty) return;
    _log('🛟 [STT-FALLBACK]',
        'streaming_stt_unavailable → deepgram (이 턴은 측정 대상에서 제외)');
    await _startDeepgramListening();
  }

  void _reportListeningReady() {
    if (_listeningReadyReported || !mounted) return;
    _listeningReadyReported = true;
    widget.onListeningReady?.call();
  }

  /// 지금 잡힌 전사가 **코치 자기 목소리**인가.
  ///
  /// 전이중으로 열어 두면 AEC가 약한 기기에서 스피커 소리가 마이크로 새고,
  /// 그게 유저 발화로 확정되면 대화가 자기 말에 자기가 답하는 꼴이 된다.
  /// 방금 코치가 한 말과 글자가 겹치는지로 가른다 — 완벽한 판정은 아니지만
  /// 되먹임은 원문이 거의 그대로 돌아오므로 이걸로 잡힌다.
  bool _looksLikeSelfEcho(String transcript) {
    final said = _lastAiSpokenLine.trim();
    final heard = transcript.trim();
    if (said.isEmpty || heard.length < 6) return false;
    final norm = RegExp(r'[^가-힣a-zA-Z0-9]');
    final a = said.replaceAll(norm, '');
    final b = heard.replaceAll(norm, '');
    if (a.isEmpty || b.isEmpty) return false;
    // 들린 말이 코치 대사 안에 통째로 들어 있으면 되먹임으로 본다.
    if (a.contains(b)) return true;
    // 앞 12자가 같아도 마찬가지다(뒤가 잘려 들어온 경우).
    final head = b.length < 12 ? b : b.substring(0, 12);
    return head.length >= 8 && a.contains(head);
  }

  /// 완성 전사가 오기 전 조각이 코치 음성의 일부일 가능성이 있는가.
  bool _couldBeSelfEchoPrefix(String transcript) {
    final norm = RegExp(r'[^가-힣a-zA-Z0-9]');
    final said = _lastAiSpokenLine.replaceAll(norm, '').toLowerCase();
    final heard = transcript.replaceAll(norm, '').toLowerCase();
    if (said.isEmpty || heard.isEmpty) return true;
    return said.contains(heard);
  }

  Future<void> _startStreamingListening() async {
    if (_streamingCaptureOpen) {
      _log('🎤 [LISTEN-SKIP]', '이미 듣는 중 → 중복 오픈 무시');
      return;
    }
    if (_isSessionComplete || _isPracticeMode) return;
    // 🙋 [FULL-DUPLEX] 예전에는 코치가 말하는 동안 마이크를 아예 닫았다.
    //   그래서 [_handleBargeIn]은 손잡이만 있고 잡을 손이 없었다 — 말로
    //   끼어들 방법이 없는 무전기가 됐다.
    //
    //   바지인이 걸려 있는 동안에는 연다. 녹음이 `echoCancel: true`라 스피커로
    //   나가는 코치 목소리는 지워지고 유저 목소리만 남는 것이 정상 동작이다.
    //   혹시 새어 들어오면 [_looksLikeSelfEcho]가 그 턴을 버린다.
    if (!_bargeInArmed && (_aiTurnActive || _ttsQueueManager.isBusy)) {
      _log('🎤 [LISTEN-SKIP]', 'turn/tts busy');
      return;
    }
    if (_openAiKey.isEmpty || !(await _audioRecorder.hasPermission())) return;
    if (!BillingTicker.instance.appInForeground.value) {
      _log('🎤 [LISTEN-SKIP]', 'app in background');
      return;
    }

    final int listenGeneration = ++_listenGeneration;
    resetBillingIdle();
    _isConversationActive = true;
    _resetTurnPcmBuffer();
    _streamingDeltaItemId = '';
    _streamingDeltaBuffer.clear();
    _streamingDeltaCount = 0;
    if (mounted) {
      setState(() {
        _debugResult = '⏱️ 듣는 중...';
        _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
      });
    }

    final session = await _ensureStreamingSession();
    if (session == null) {
      _log('❌ [LISTEN-ERR]', '스트리밍 전사 세션 준비 실패');
      return;
    }
    if (!mounted || listenGeneration != _listenGeneration) return;
    if (!await _startStreamingCapture(listenGeneration)) {
      _log('❌ [LISTEN-ERR]', '스트리밍 전사 마이크 캡처 실패');
      return;
    }
    session.openAudioGate(reason: 'turn_start');
    BillingTicker.instance.resumeFromActivity('step_expand_mic_start');
    _reportListeningReady();
    _log('🎤 [LISTEN-05]',
        'OpenAI streaming listening 시작 generation=$listenGeneration');
  }

  Future<OpenAiStreamingTranscribeSession?> _ensureStreamingSession() async {
    final existing = _streamingStt;
    if (existing != null && existing.isConnected) return existing;
    if (existing != null) {
      _streamingStt = null;
      await existing.dispose();
    }
    if (_streamingSessionStarting) {
      _log('🎙️ [STREAM-STT]', 'connect 진행 중 → 중복 연결 생략');
      return null;
    }
    _streamingSessionStarting = true;
    try {
      final languageCode = _sttLangCode();
      var session = OpenAiStreamingTranscribePrewarm.instance.take(
        apiKey: _openAiKey,
        languageCode: languageCode,
        onLog: _log,
      );
      if (session == null) {
        session = OpenAiStreamingTranscribeSession(
          apiKey: _openAiKey,
          languageCode: languageCode,
          onLog: _log,
        );
        if (!await session.connect()) {
          await session.dispose();
          _streamingConnectFailed = true;
          return null;
        }
      }
      if (!mounted) {
        await session.dispose();
        return null;
      }
      _bindStreamingHandlers(session);
      _streamingStt = session;
      return session;
    } finally {
      _streamingSessionStarting = false;
    }
  }

  void _bindStreamingHandlers(OpenAiStreamingTranscribeSession session) {
    session.onLog = _log;
    session.shouldReconnect = () =>
        mounted &&
        _isConversationActive &&
        BillingTicker.instance.appInForeground.value &&
        !_isPracticeMode &&
        !_isSessionComplete;
    session.onSpeechStarted = _onStreamingSpeechStarted;
    session.onSpeechStopped = _onStreamingSpeechStopped;
    session.onTranscriptDelta = _onStreamingTranscriptDelta;
    session.onTranscriptCompleted = _onStreamingTranscriptCompleted;
    session.onReconnecting =
        (attempt) => _log('🎤 [LISTEN-RETRY]', '스트리밍 전사 재연결 시도 $attempt');
    session.onGaveUp = () => _log('❌ [LISTEN-GIVEUP]', '스트리밍 전사 재연결 포기');
    session.onFatalError = (reason) {
      if (!mounted) return;
      _log('❌ [LISTEN-ERR]', '스트리밍 전사 fatal reason=$reason');
      _stopEverything();
    };
  }

  Future<bool> _startStreamingCapture(int listenGeneration) async {
    await _stopStreamingCapture(reason: 'restart');
    try {
      try {
        if (await _audioRecorder.isRecording()) await _audioRecorder.stop();
      } catch (_) {}
      final stream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: kStealthVoxSttSampleRate,
          numChannels: 1,
          // Step Expand의 기존 메인 입력 특성을 유지한다.
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      if (!mounted || listenGeneration != _listenGeneration) {
        try {
          await _audioRecorder.stop();
        } catch (_) {}
        return false;
      }
      _streamingCaptureOpen = true;
      // 🔁 [LATE-CONTINUATION] 새 유저 턴 = 이 턴의 AI 음성은 아직 없다.
      //   안 내리면 안내 음성이 세운 플래그가 남아 복구 창이 안 열린다.
      _aiPlaybackStarted = false;
      _streamingCaptureSub = stream.listen(
        (data) {
          if (data.isEmpty || listenGeneration != _listenGeneration) return;
          final session = _streamingStt;
          if (session == null || !session.audioGateOpen) return;
          session.appendAudio(data);
        },
        onError: (Object error) =>
            _log('❌ [MIC-ERR-B]', '오디오 스트림 에러: ${error.runtimeType}'),
      );
      return true;
    } catch (error) {
      _log('❌ [MIC-ERR-C]', '스트리밍 전사 capture 실패 reason=${error.runtimeType}');
      return false;
    }
  }

  Future<void> _stopStreamingCapture({required String reason}) {
    final pending = _streamingCaptureStopping;
    final next = pending == null
        ? _stopStreamingCaptureInner(reason)
        : pending.then((_) => _stopStreamingCaptureInner(reason));
    _streamingCaptureStopping = next;
    return next.whenComplete(() {
      if (identical(_streamingCaptureStopping, next)) {
        _streamingCaptureStopping = null;
      }
    });
  }

  Future<void> _stopStreamingCaptureInner(String reason) async {
    final sub = _streamingCaptureSub;
    _streamingCaptureSub = null;
    await sub?.cancel();
    if (!_streamingCaptureOpen) return;
    _streamingCaptureOpen = false;
    try {
      if (await _audioRecorder.isRecording()) await _audioRecorder.stop();
    } catch (_) {}
    _log('🎤 [MIC-ROUTING]', 'capture_stopped reason=$reason');
  }

  void _onForegroundChanged() {
    if (!mounted || !kFreeTalkUseStreamingStt) return;
    if (!BillingTicker.instance.appInForeground.value) {
      if (_streamingCaptureOpen) {
        _log('🎤 [LISTEN-BG]', '백그라운드 진입 → 마이크/전송 중지');
        _streamingStt?.closeAudioGate(reason: 'app_background');
        unawaited(_stopStreamingCapture(reason: 'app_background'));
        _streamingDeltaItemId = '';
        _streamingDeltaBuffer.clear();
        _streamingDeltaCount = 0;
      }
      return;
    }
    if (!_isConversationActive ||
        _isSessionComplete ||
        _isPracticeMode ||
        _streamingPipelineRunning ||
        _aiTurnActive ||
        _ttsQueueManager.isBusy ||
        _streamingCaptureOpen) {
      return;
    }
    _log('🎤 [LISTEN-FG]', '포그라운드 복귀 → STT 재개');
    unawaited(_startUserListening());
  }

  bool _isStreamingTurnOwner() =>
      mounted && _isConversationActive && _streamingCaptureOpen;

  void _onStreamingSpeechStarted() {
    if (!_isStreamingTurnOwner()) {
      _log('🎤 [LISTEN-STALE]', 'speech_started ignored');
      return;
    }
    resetBillingIdle();
    // 🙋 [BARGE-IN] speech_started만으로 AI 음성을 자르지 않는다. 폰 스피커의
    //   자기 에코도 이 이벤트를 만들기 때문이다. completed 전사문이 도착한 뒤
    //   [_looksLikeSelfEcho]를 통과한 실제 유저 발화일 때만 자른다.
    // 🔇 [SILENCE-PUSH] 유저가 입을 열었다. 이어 말하기 감시를 여기서 푼다 —
    //   전사가 끝나기를 기다리면 그사이 타이머가 익어 말이 겹친다.
    _cancelSmallTalkSilence(reason: 'speech_started');
    _swDeepgram
      ..reset()
      ..start();
    _log('⏱️ [PERF]', 'SPEECH_STARTED');
    _maybeStartContinuation();
  }

  /// 발화 종료 신호일 뿐이다. 사용자 턴 확정은 completed 한 곳에서만 한다.
  void _onStreamingSpeechStopped() {
    if (!_isStreamingTurnOwner()) {
      _log('🎤 [LISTEN-STALE]', 'speech_stopped ignored');
      return;
    }
    _log('⏱️ [PERF]', 'SPEECH_STOPPED');
    final now = DateTime.now();
    _speechStoppedAt = now;
    if (_continuationCandidateAlive) {
      _continuationWaitStartedAt = now;
      _armContinuationTranscriptTimeout();
    }
    _streamingTurnInFlight = true;
    // 🔁 [LATE-CONTINUATION] 여기서 마이크를 닫으면 뒷말이 서버에 닿지 못해
    //   두 번째 speech_started 자체가 생기지 않는다. 복구 창이 만료되거나
    //   TTS를 걸기 직전까지 녹음과 게이트를 살려 둔다.
    _openContinuationWindow();
    _armStreamingTranscriptTimeout();
  }

  // ====================================================================
  // 🔁 [LATE-CONTINUATION] 복구 창
  // ====================================================================

  void _openContinuationWindow() {
    if (!_isStreamingTurnOwner() || _aiPlaybackStarted) {
      _closeContinuationWindow(reason: 'not_eligible');
      return;
    }
    _continuationWindowTimer?.cancel();
    final int windowSeq = ++_continuationWindowSeq;
    _continuationWindowOpen = true;
    _continuationWindowTimer = Timer(
      const Duration(milliseconds: kFreeTalkContinuationWindowMs),
      () {
        _continuationWindowTimer = null;
        if (!mounted || windowSeq != _continuationWindowSeq) return;
        if (!_continuationWindowOpen) return;
        if (_continuationCandidateAlive) {
          _log('🔁 [CONT-WINDOW]', 'expiry_deferred reason=candidate_alive');
          return;
        }
        _closeContinuationWindow(reason: 'window_expired');
      },
    );
    _log('🔁 [CONT-WINDOW]',
        'open seq=$windowSeq windowMs=$kFreeTalkContinuationWindowMs');
  }

  /// 창을 닫고 녹음·게이트를 정리한다. **[MIC-ROUTING] 규칙을 지키는 자리다.**
  /// 후보 상태는 건드리지 않는다 — 창은 마이크 수명, 후보는 자격이다.
  void _closeContinuationWindow({required String reason}) {
    final bool wasOpen = _continuationWindowOpen;
    _continuationWindowTimer?.cancel();
    _continuationWindowTimer = null;
    _continuationWindowOpen = false;
    _streamingStt?.closeAudioGate(reason: reason);
    unawaited(_stopStreamingCapture(reason: reason));
    if (wasOpen) {
      _log('🔁 [CONT-WINDOW]',
          'close seq=$_continuationWindowSeq reason=$reason');
      _repaintContinuationHint();
    }
  }

  void _clearContinuationCandidate() {
    _continuationCandidate = 0;
    _continuationWaitStartedAt = null;
    _continuationTranscriptTimeout?.cancel();
    _continuationTranscriptTimeout = null;
  }

  void _maybeStartContinuation() {
    final stoppedAt = _speechStoppedAt;
    final int elapsed = stoppedAt == null
        ? -1
        : DateTime.now().difference(stoppedAt).inMilliseconds;
    if (!shouldTreatAsLateContinuation(
      msSinceSpeechStopped: elapsed,
      candidateAlive: _continuationCandidateAlive,
      aiPlaybackStarted: _aiPlaybackStarted,
    )) {
      return;
    }
    _continuationCandidate = ++_continuationCandidateSeq;
    _continuationWaitStartedAt = DateTime.now();
    _log(
        '🔁 [CONT-DETECT]',
        'candidate=$_continuationCandidate afterMs=$elapsed '
            'gen=$_pipelineGeneration segments=${_turnSegments.length}');
    if (_streamingPipelineRunning ||
        _aiTurnActive ||
        _turnSegments.isNotEmpty) {
      _invalidateAssistantTurn(reason: 'late_continuation');
    }
    _armContinuationTranscriptTimeout();
  }

  void _armContinuationTranscriptTimeout() {
    _continuationTranscriptTimeout?.cancel();
    final int candidate = _continuationCandidate;
    if (candidate == 0) return;
    _continuationTranscriptTimeout = Timer(
      const Duration(milliseconds: kFreeTalkContinuationTranscriptTimeoutMs),
      () {
        _continuationTranscriptTimeout = null;
        if (!mounted || candidate != _continuationCandidate) return;
        final bool speaking = _streamingStt?.isUserSpeaking ?? false;
        final bool serverBusy = _streamingStt?.hasPendingUtterance ?? false;
        final waitStart = _continuationWaitStartedAt;
        final int waitedMs = waitStart == null
            ? 0
            : DateTime.now().difference(waitStart).inMilliseconds;
        if (decideContinuationWait(
              isUserSpeaking: speaking,
              serverHasPendingUtterance: serverBusy,
              msSinceWaitStarted: waitedMs,
            ) ==
            ContinuationWaitAction.keepWaiting) {
          _log('🔁 [CONT-TIMEOUT]',
              'extended candidate=$candidate waitedMs=$waitedMs speaking=$speaking');
          _armContinuationTranscriptTimeout();
          return;
        }
        _log('🔁 [CONT-TIMEOUT]',
            'candidate=$candidate segments=${_turnSegments.length} → 확보분으로 진행');
        _resolveContinuation(
            safetyExpired: true, reason: 'continuation_timeout');
      },
    );
  }

  /// 진행 중인 결과를 통째로 무효화한다.
  ///
  /// 이 모드는 **합치기(`mergeNativeExpansion`)와 질문 생성이 따로** 돌고,
  /// 음성은 `TtsQueueManager` + `ChunkedTtsFetcher`로 나간다. 세대를 올려
  /// 늦게 온 결과를 막고, 음성은 fetcher와 큐를 함께 끊는다.
  void _invalidateAssistantTurn({required String reason}) {
    _pipelineGeneration++;
    _guideTtsFetcher?.cancel();
    _guideTtsFetcher = null;
    _ttsQueueManager.stop();
    _isInitialGuidePlaying = false;
    // busy 플래그는 새 파이프라인이 다시 세운다. 여기서 내려 두지 않으면
    // 취소된 쪽 finally가 나중에 새 턴의 것을 끈다.
    _streamingPipelineRunning = false;
    _aiTurnActive = false;
    // 확정하지 않은 AI 말풍선을 걷어낸다.
    _removeBubbleById(_activeAiBubbleId);
    _activeAiBubbleId = '';
    _log('🔁 [CONT-INVALIDATE]', 'reason=$reason newGen=$_pipelineGeneration');
  }

  void _resolveContinuation({
    required bool safetyExpired,
    required String reason,
  }) {
    if (!mounted || !_isConversationActive) return;
    final bool speaking = _streamingStt?.isUserSpeaking ?? false;
    final bool serverBusy = _streamingStt?.hasPendingUtterance ?? false;
    final bool hasMeaningful =
        _turnSegments.any((s) => !isHesitationOnlyTranscript(s.text));
    final decision = decideContinuationNext(
      isUserSpeaking: speaking,
      serverHasPendingUtterance: serverBusy,
      hasMeaningfulSegment: hasMeaningful,
      safetyExpired: safetyExpired,
    );
    _log(
        '🔁 [CONT-RESOLVE]',
        'candidate=$_continuationCandidate decision=${decision.name} '
            'speaking=$speaking serverBusy=$serverBusy '
            'meaningful=$hasMeaningful expired=$safetyExpired '
            'segments=${_turnSegments.length}');
    switch (decision) {
      case ContinuationDecision.wait:
        _armContinuationTranscriptTimeout();
        return;
      case ContinuationDecision.startAssistant:
        final merged = _pendingUserTranscript;
        _clearContinuationCandidate();
        _closeContinuationWindow(reason: reason);
        _updateBubbleText(_activeHostBubbleId, merged);
        _startAssistantTurn(merged, reason: reason);
        return;
      case ContinuationDecision.abandon:
        _clearContinuationCandidate();
        _closeContinuationWindow(reason: reason);
        _abortStreamingTurn(reason: reason);
        return;
    }
  }

  /// 합친 문장 **하나**로 다시 시작한다.
  ///
  /// `mergeNativeExpansion`의 `newUtterances`에 조각을 각각 넣으면 안 된다 —
  /// 그 목록은 API 실패로 밀린 **이전 학습 턴**을 싣는 자리다. 갈린 조각을
  /// 거기 넣으면 한 턴이 두 턴으로 세어져 5턴 진행과 History가 어긋난다.
  void _startAssistantTurn(String userKorean, {required String reason}) {
    if (!mounted || !_isConversationActive || _isSessionComplete) return;
    _aiPlaybackStarted = false;
    _streamingTurnInFlight = true;
    final int generation = _pipelineGeneration;
    _log('🔁 [CONT-RESTART]', 'gen=$generation reason=$reason');
    unawaited(_processFinalUserKorean(userKorean, generation: generation));
  }

  /// 🔁 [LATE-CONTINUATION] 복구 창이 열려 있는 동안 마이크 표시를 살려 둔다.
  ///
  /// 떠 있는 안내 알약을 쓰다가 걷어냈다 — 최대 1.2초, 그것도 말을 멈춘 뒤에만
  /// 떠서 정작 이어 말하려는 사람은 볼 틈이 없었다. 대신 이미 보고 있던
  /// 마이크 점을 **꺼지지 않게** 두는 쪽이 자연스럽다: 점이 살아 있으면
  /// 아직 듣고 있다는 뜻이고, 유저는 설명을 읽지 않아도 안다.
  bool get _continuationListening =>
      _continuationWindowOpen && !_aiPlaybackStarted;

  /// 🔁 [LATE-CONTINUATION] 복구 창 동안 점을 **반복해서 뛰게** 한다.
  ///
  /// 크기만 12→16px로 키워 봤더니 화면에서는 4픽셀이라, 말풍선을 보고 있으면
  /// 주변시로 거의 안 잡혔다(실장님 확인). 사람 눈은 크기 차이보다 **반복
  /// 움직임**을 훨씬 잘 잡는다. 창이 열려 있는 동안만 돌리고 닫히면 세운다 —
  /// 늘 돌리면 쓸데없이 매 프레임을 그린다.
  late final AnimationController _continuationPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  /// 창 상태가 바뀌면 위 표시를 다시 그린다.
  void _repaintContinuationHint() {
    if (!mounted || _isDisposing) return;
    if (_continuationListening) {
      if (!_continuationPulse.isAnimating) {
        _continuationPulse.repeat(reverse: true);
      }
    } else if (_continuationPulse.isAnimating) {
      _continuationPulse.stop();
      _continuationPulse.value = 0;
    }
    setState(() {});
  }

  void _resetContinuationState() {
    _continuationWindowTimer?.cancel();
    _continuationWindowTimer = null;
    _continuationTranscriptTimeout?.cancel();
    _continuationTranscriptTimeout = null;
    _continuationWindowOpen = false;
    _continuationCandidate = 0;
    _continuationWaitStartedAt = null;
    _turnSegments.clear();
    _pendingUserTranscript = '';
    _speechStoppedAt = null;
    _activeUserTurnId = 0;
    _aiPlaybackStarted = false;
    _activeHostBubbleId = '';
    _activeAiBubbleId = '';
  }

  String _nextBubbleId(String prefix) => '$prefix-${++_bubbleSeq}';

  int _bubbleIndexById(String id) => bubbleIndexById(_localMessages, id);

  void _removeBubbleById(String id) {
    if (!mounted || _isDisposing) {
      removeBubbleById(_localMessages, id);
      return;
    }
    setState(() => removeBubbleById(_localMessages, id));
  }

  bool _updateBubbleText(String id, String text) {
    if (!mounted || _isDisposing) {
      return updateBubbleTextById(_localMessages, id, text);
    }
    var updated = false;
    setState(() => updated = updateBubbleTextById(_localMessages, id, text));
    return updated;
  }

  /// 🔁 [LATE-CONTINUATION] 후보가 살아 있는 동안 도착한 조각을 받는다.
  /// 앞말이든 뒷말이든, 도착 순서와 무관하게 전부 여기로 온다.
  void _ingestContinuationSegment(
    String transcript, {
    required String itemId,
    required int order,
  }) {
    final next = transcript.trim();
    _streamingTranscriptTimeout?.cancel();
    _streamingTranscriptTimeout = null;
    _streamingDeltaItemId = '';
    _streamingDeltaBuffer.clear();
    _streamingDeltaCount = 0;
    if (!mounted || !_isConversationActive) return;

    if (next.isEmpty) {
      _log('🔁 [CONT-INGEST]', 'item=$itemId dropped=empty');
      _resolveContinuation(safetyExpired: false, reason: 'continuation_empty');
      return;
    }
    if (_isNoiseTranscript(next) && !isHesitationOnlyTranscript(next)) {
      _log('🔁 [CONT-INGEST]', 'item=$itemId dropped=noise');
      _resolveContinuation(safetyExpired: false, reason: 'continuation_noise');
      return;
    }
    // ⛔ 같은 item_id 재수신만 막는다. 글자가 같다는 이유로는 버리지 않는다.
    if (!mergeUserTurnSegments(
      _turnSegments,
      UserTurnSegment(itemId: itemId, order: order, text: next),
    )) {
      _log('🔁 [CONT-INGEST]', 'item=$itemId duplicate_item → 무시');
      return;
    }
    _pendingUserTranscript =
        composeUserTurnText(_turnSegments.map((s) => s.text));
    _ensureUserTurnOpen();
    _updateBubbleText(_activeHostBubbleId, _pendingUserTranscript);
    _log(
        '🔁 [CONT-INGEST]',
        'item=$itemId order=$order segments=${_turnSegments.length} '
            'len=${_pendingUserTranscript.length}');
    _resolveContinuation(safetyExpired: false, reason: 'continuation_merged');
  }

  bool _ensureUserTurnOpen() {
    if (_activeUserTurnId != 0) return false;
    _userTurnSeq++;
    _activeUserTurnId = _userTurnSeq;
    _aiPlaybackStarted = false;
    return true;
  }

  void _armStreamingTranscriptTimeout() {
    _streamingTranscriptTimeout?.cancel();
    final int generation = _pipelineGeneration;
    _streamingTranscriptTimeout = Timer(
      const Duration(milliseconds: _kStreamingTranscriptTimeoutMs),
      () {
        _streamingTranscriptTimeout = null;
        if (!mounted || generation != _pipelineGeneration) return;
        if (!_streamingTurnInFlight) return;
        _log('⚠️ [STREAM-STT]', 'transcription_timeout → 턴 폐기 후 마이크 재개');
        _abortStreamingTurn(reason: 'transcription_timeout');
      },
    );
  }

  void _abortStreamingTurn({required String reason}) {
    _streamingTranscriptTimeout?.cancel();
    _streamingTranscriptTimeout = null;
    _streamingDeltaItemId = '';
    _streamingDeltaBuffer.clear();
    _streamingDeltaCount = 0;
    _streamingTurnInFlight = false;
    if (mounted) {
      setState(() {
        _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
      });
    }
    _log('🎙️ [STREAM-STT]', 'turn_aborted reason=$reason');
    // ⚠️ 마이크를 다시 열기 **전에** 정리한다. 순서가 뒤바뀌면 방금 연 캡처를
    //   창 종료가 도로 죽인다.
    _closeContinuationWindow(reason: reason);
    _resetContinuationState();
    if (_isConversationActive && !_isSessionComplete && !_isPracticeMode) {
      unawaited(_startUserListening());
    }
  }

  /// UI 미리보기 전용. 확장·저장·턴 카운트에는 절대 사용하지 않는다.
  void _onStreamingTranscriptDelta(String itemId, String delta) {
    if (!mounted || !_isConversationActive || _isPracticeMode) return;
    if (itemId.isNotEmpty && _handledStreamingItemIds.contains('rt:$itemId')) {
      return;
    }
    BillingTicker.instance.resumeFromActivity('step_expand_stt_partial');
    if (_streamingDeltaItemId != itemId) {
      _streamingDeltaItemId = itemId;
      _streamingDeltaBuffer.clear();
      _streamingDeltaCount = 0;
      _log('🖼️ [STREAM-DELTA]', 'first item=$itemId');
    }
    _streamingDeltaCount++;
    _streamingDeltaBuffer.write(delta);
    final preview = _streamingDeltaBuffer.toString().trim();
    if (preview.isEmpty) return;
    // 🙋 [EARLY BARGE-IN] 코치 대사에 없는 두 글자가 잡히면 완성 전사와
    // VAD 종료를 기다리지 않고 그 자리에서 TTS를 자른다.
    if (_bargeInArmed &&
        !_bargeInFired &&
        preview.characters.length >= 2 &&
        !_couldBeSelfEchoPrefix(preview)) {
      _log('🙋 [BARGE-IN]',
          'early_delta item=$itemId chars=${preview.characters.length}');
      _handleBargeIn();
    }
    if (_aiTurnActive || _ttsQueueManager.isBusy) return;
    // 🌱 씨앗을 찾기 전까지는 글로 적지 않는다. 잡담은 소리로만 오간다.
    if (!_seedFound) return;
    setState(() {
      _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
      _localMessages.add(<String, dynamic>{
        'role': 'HOST_TEMP',
        'target': preview,
        'original': '',
      });
    });
    _scrollToBottom();
  }

  void _onStreamingTranscriptCompleted(String itemId, String text) {
    if (!mounted || !_isConversationActive || _isPracticeMode) {
      _log('[STEP-STT]', 'stale_dropped item=$itemId reason=room_closed');
      return;
    }
    final dedupeKey = itemId.isNotEmpty
        ? 'rt:$itemId'
        : 'rt-hash:${text.trim().hashCode.toUnsigned(32).toRadixString(16)}';
    if (!_handledStreamingItemIds.add(dedupeKey)) {
      _log('[STEP-STT]', 'duplicate_dropped item=$itemId len=${text.length}');
      return;
    }
    if (_handledStreamingItemIds.length > 64) {
      _handledStreamingItemIds.remove(_handledStreamingItemIds.first);
    }
    _log('[STEP-STT]',
        'final_received item=$itemId generation=$_listenGeneration len=${text.length}');
    // 🔊 [SELF-ECHO] 전이중으로 열어 둔 마이크에 코치 목소리가 새어 들어온
    //   경우다. 이걸 유저 발화로 확정하면 코치가 자기 말에 자기가 답한다.
    if (_looksLikeSelfEcho(text)) {
      _log('🔊 [SELF-ECHO]', 'dropped len=${text.length} text="$text"');
      return;
    }
    // 🙋 [BARGE-IN] 코치가 말하는 중에 잡힌 유저 발화다. 여기서 말을 끊는다 —
    //   화면 탭과 같은 자리로 보낸다.
    if (_bargeInArmed && !_bargeInFired) {
      _handleBargeIn();
    }
    // 🔁 발화 순서는 소켓의 committed 순번이 원본이다. 도착 순서로 이으면
    //   뒷말이 먼저 끝났을 때 문장이 뒤집힌다.
    final int order =
        _streamingStt?.utteranceOrderOf(itemId) ?? (++_fallbackSegmentOrder);
    unawaited(
        _processStreamingFinalTranscript(text, itemId: itemId, order: order));
  }

  Future<void> _processStreamingFinalTranscript(
    String transcript, {
    required String itemId,
    required int order,
  }) async {
    // 🌐 [ORIGIN-RESOLVE] 이 세션의 ORIGIN을 확정하는 자리. 아래 파이프라인이
    //   전부 ORIGIN에 기대므로 무엇보다 먼저 끝나야 한다. 두 번째 턴부터는
    //   이미 확정돼 있어 즉시 반환한다.
    await _settleOriginLanguage(transcript);
    if (!mounted || _isDisposing) return;
    // 🔁 [LATE-CONTINUATION] 후보가 살아 있으면 조각은 전부 이리로 온다.
    //   **아래 가드를 타면 안 된다** — 유저가 복구 창 안에서 이미 다시 말했고,
    //   그 말은 버릴 수 없다.
    if (_continuationCandidateAlive) {
      _ingestContinuationSegment(transcript, itemId: itemId, order: order);
      return;
    }
    if (_streamingPipelineRunning || _aiTurnActive) {
      _log('[TURN-SKIP]', 'reason=pipeline_busy item=$itemId');
      return;
    }
    _streamingPipelineRunning = true;
    _streamingTranscriptTimeout?.cancel();
    _streamingTranscriptTimeout = null;
    final int generation = _pipelineGeneration;
    final int deltaCount = _streamingDeltaCount;
    _streamingDeltaItemId = '';
    _streamingDeltaBuffer.clear();
    _streamingDeltaCount = 0;
    _streamingTurnInFlight = true;
    try {
      // 🔁 [LATE-CONTINUATION] 여기서 마이크를 닫지 않는다. 복구 창이 만료되거나
      //   TTS를 걸기 직전에 닫힌다.
      final userKorean = transcript.trim();
      if (!mounted || generation != _pipelineGeneration) return;
      if (userKorean.isEmpty) {
        _abortStreamingTurn(reason: 'empty_transcript');
        return;
      }
      if (_swDeepgram.isRunning) _swDeepgram.stop();
      BillingTicker.instance.resumeFromActivity('step_expand_stt_result');
      _log(
        '[STT-ROUTE]',
        'selected=streaming model=$kStreamingSttModel item=$itemId '
            'len=${userKorean.length} deltas=$deltaCount',
      );
      if (kDebugMode) {
        _log('🎧 [STT-RAW]', 'source=streaming text="$userKorean"');
      }
      _cancelSpeculativeTranslation();
      _prefetchedFirstTurnTranscribe = null;
      _prefetchedFirstTurnPcmBytes = 0;

      // 🔁 [LATE-CONTINUATION] 잠정 사용자 턴으로 접수한다. 복구 창이 닫힐
      //   때까지 이 문장은 아직 자랄 수 있다.
      _turnSegments.clear();
      mergeUserTurnSegments(
        _turnSegments,
        UserTurnSegment(itemId: itemId, order: order, text: userKorean),
      );
      _pendingUserTranscript =
          composeUserTurnText(_turnSegments.map((s) => s.text));
      _ensureUserTurnOpen();

      await _processFinalUserKorean(_pendingUserTranscript,
          generation: generation);
    } finally {
      // 🔐 [GEN-OWNERSHIP] 이어 말하기로 세대가 갈리면 이 파이프라인과 새
      //   파이프라인이 잠시 겹친다. 그때 이전 세대의 finally가 새 턴의 busy를
      //   끄면 [TURN-SKIP] 가드가 통째로 뚫린다. 주인일 때만 내린다.
      if (generation == _pipelineGeneration) {
        if (!_continuationCandidateAlive) _streamingTurnInFlight = false;
        _streamingPipelineRunning = false;
      } else {
        _log('[GEN-OWNERSHIP]', 'stale finally skipped gen=$generation');
      }
    }
  }

  Future<void> _startDeepgramListening() async {
    // 이미 듣고 있으면 새로 열지 않는다. 첫 마디 재생과 마이크 열기가 겹치고
    // 방을 드나들면 여기가 여러 번 불리는데, 그대로 두면 VoiceManager가 계속
    // 새로 생겨 버려진 Deepgram 소켓이 쌓인다. 턴이 끝나면 _voiceManager가
    // null이 되므로 다음 턴 재개는 막히지 않는다.
    if (_voiceManager != null) {
      _log('🎤 [LISTEN-SKIP]', '이미 듣는 중 → 중복 오픈 무시');
      return;
    }
    if (_deepgramKey.isEmpty || !(await _audioRecorder.hasPermission())) return;
    // 🌱 5턴 완료 시 마이크 잠김 (유저가 "새 주제" 버튼 눌러야 리셋됨)
    if (_isSessionComplete) return;
    resetBillingIdle();
    _isConversationActive = true;
    _resetTurnPcmBuffer();
    if (mounted) {
      setState(() {
        _debugResult = "⏱️ 듣는 중...";
      });
    }

    _log('🎤 [LISTEN-01]', '_startDeepgramListening 진입, VoiceManager 생성');

    // 🌐 [v3.1] 로비에서 유저가 고른 ORIGIN(대화 언어)으로 Deepgram 인식.
    //   변수명이 `nativeLang`이지만 모국어가 아니라 **지금 말하고 듣는 언어**다.
    // 유저가 한국어로 말하면 Deepgram이 한국어로 인식 → Brain이 영어로 번역
    final String dgLangCode = _nativeLangCode();
    _log('🌐 [LANG]', 'Deepgram boundary language=$dgLangCode');

    _voiceManager = DeepgramV2VoiceManager(
      apiKey: _deepgramKey,
      audioRecorder: _audioRecorder,
      langCode: dgLangCode,
      onLog: _log, // 🔬 로그 훅 주입
      onConnected: () {
        _log('✅ [LISTEN-02]', 'onConnected 콜백 실행');
        _reportListeningReady();
      },
      onTranscriptUpdate: (transcript) {
        BillingTicker.instance.resumeFromActivity('step_expand_stt_partial');
        if (transcript.trim().isNotEmpty && mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
          });
        }
        if (_isInitialGuidePlaying && transcript.trim().isNotEmpty) {
          _isInitialGuidePlaying = false;
          // 아직 안 돌아온 TTS 응답까지 막아야 안내가 되살아나지 않는다.
          _guideTtsFetcher?.cancel();
          _guideTtsFetcher = null;
          _ttsQueueManager.stop();
          _log('🎤 [BARGE-IN]', '첫 유저 발화 감지 → 시작 안내 TTS 즉시 중단');
        }
        _swDeepgram.reset();
        _swDeepgram.start();
      },
      onTurnResult: _onDeepgramTurnResult,
      onAudioData: _appendTurnPcm,
      onTurnEnded: (transcript, {bool speechFinal = false}) {
        _log('🔀 [LISTEN-03]',
            'onTurnEnded 콜백 수신: len=${transcript.length} speechFinal=$speechFinal');
        BillingTicker.instance.resumeFromActivity('step_expand_stt_result');
        _swDeepgram.stop();
        // source(speechFinal)를 인자로 직접 전달 → 비동기 다음 이벤트에 상태값이 덮이는 위험 제거
        _stopMicAndProcess(transcript, speechFinal: speechFinal);
      },
      onError: (err) {
        _log('❌ [LISTEN-ERR]', 'Deepgram Error: $err');
        _stopEverything();
      },
    );
    _log('🎤 [LISTEN-04]', 'connectAndStart 호출 직전');
    await _voiceManager!.connectAndStart();
    BillingTicker.instance.resumeFromActivity('step_expand_mic_start');
    _log('🎤 [LISTEN-05]', 'connectAndStart 완료');
  }

  // 🔧 [v3.4] Deepgram speech_final / UtteranceEnd 수신 시 호출됨
  // 조건부 대기창(speech_final=1200ms, UtteranceEnd=500ms) 안에서 추가 발화 합치기
  // → 완전히 끝나면 파이프라인 시작
  // speechFinal은 인자로 직접 받아 이 함수 안에서만 사용 (상태 필드 미사용)
  void _stopMicAndProcess(String transcript, {bool speechFinal = false}) async {
    resetBillingIdle();
    final clean = transcript.trim();
    final source = speechFinal ? 'speech_final' : 'utterance_end';
    // 🚀 [FIRST-TURN] 아직 완료된 턴이 없으면(_turnCounter==0) 첫 유저 발화 →
    //   대기창을 짧게 잡아 파이프라인을 일찍 시작한다. 이후 턴은 기존 안전값.
    final bool isFirstUtterance = _turnCounter == 0;
    final waitMs = isFirstUtterance
        ? COMMIT_WAIT_FIRST_TURN_MS
        : (speechFinal
            ? COMMIT_WAIT_SPEECH_FINAL_MS
            : COMMIT_WAIT_UNCERTAIN_MS);
    _log('🔀 [STOP-01]',
        '$source 수신: len=${clean.length} waitMs=$waitMs first=$isFirstUtterance');

    if (clean.length < 2) {
      _log('🔀 [STOP-02]', '너무 짧음 → 조용히 계속 청취');
      _resetTurnPcmBuffer();
      return;
    }

    // 🔧 기존 대기 중인 발화가 있으면 공백으로 연결 (더듬거림 합치기)
    final finalReceivedAt = DateTime.now();
    final isDuplicateFinal = isDuplicateFinalTranscript(
      _pendingTranscript,
      clean,
      sincePreviousFinal: _lastPendingFinalAt == null
          ? null
          : finalReceivedAt.difference(_lastPendingFinalAt!),
    );
    _lastPendingFinalAt = finalReceivedAt;
    if (_pendingTranscript.isEmpty) {
      _pendingTranscript = clean;
      _log('🔀 [STOP-03]', '신규 발화 접수. ${waitMs}ms 대기창 시작 (source=$source)');
    } else if (isDuplicateFinal) {
      _log('🔀 [STOP-04]',
          '동일 final 중복 무시 (${waitMs}ms 대기창 리셋, source=$source)');
    } else {
      _pendingTranscript = '$_pendingTranscript $clean';
      _log('🔀 [STOP-04]',
          '합치기: len=${_pendingTranscript.length} (${waitMs}ms 대기창 리셋, source=$source)');
    }

    // Deepgram은 발화 종료 경계만 잡는다. gpt-4o-transcribe가 확정한 한국어
    // 문장이 나오기 전에는 임시 말풍선(점 3개)을 띄우지 않는다 — 내용이 없는
    // 풍선이 먼저 떴다가 글자로 바뀌면 화면이 두 번 움직인다.
    // (Circle Talk과 같은 규칙)
    if (mounted) {
      setState(() {
        _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
      });
    }

    // 기존 타이머 취소 (새 발화가 왔으므로 대기창 리셋)
    _commitTimer?.cancel();

    // 조건부 대기 후 파이프라인 시작 예약 (source별 waitMs)
    _commitTimer = Timer(
      Duration(milliseconds: waitMs),
      () => _commitAndProcess(),
    );
  }

  // Deepgram은 발화 종료 경계만 제공한다. 사용자 한국어 문장은 매 턴 PCM을
  // gpt-4o-transcribe로 전사한 결과만 사용한다.
  void _commitAndProcess() async {
    final generation = _pipelineGeneration;
    final boundaryTranscript = _pendingTranscript.trim();
    _pendingTranscript = '';
    _lastPendingFinalAt = null;
    _commitTimer = null;
    _cancelSpeculativeTranslation();
    _prefetchedFirstTurnTranscribe = null;
    _prefetchedFirstTurnPcmBytes = 0;
    if (boundaryTranscript.isEmpty) {
      if (_isConversationActive && !_isSessionComplete) _startUserListening();
      return;
    }

    final pcm = _snapshotTurnPcm();
    final closingManager = _voiceManager;
    _voiceManager = null;
    if (closingManager != null) await closingManager.dispose();
    if (pcm == null || pcm.isEmpty) {
      _log('[STT-ROUTE]', 'gpt-4o-transcribe skipped reason=empty_pcm');
      if (_isConversationActive && !_isSessionComplete) _startUserListening();
      return;
    }

    final userKorean =
        (await _transcribeAccurately(pcmOverride: pcm))?.trim() ?? '';
    if (!mounted || generation != _pipelineGeneration) return;
    if (userKorean.isEmpty) {
      _log('[STT-ROUTE]', 'gpt-4o-transcribe failed; Deepgram text discarded');
      if (_isConversationActive && !_isSessionComplete) _startUserListening();
      return;
    }
    _log('[STT-ROUTE]',
        'selected=gpt-4o-transcribe every_turn=true len=${userKorean.length}');
    _runMeaningProbe(userKorean);

    await _processFinalUserKorean(userKorean, generation: generation);
  }

  /// 전사 엔진들의 단일 합류점. 여기부터는 Step Expand 고유의 검증·한국어
  /// 문장 병합·질문 생성·5턴 저장 로직이며, 스트리밍 이식으로 변경하지 않는다.
  Future<void> _processFinalUserKorean(
    String userKorean, {
    required int generation,
  }) async {
    if (!mounted || generation != _pipelineGeneration) return;

    if (isConversationCancelCommand(userKorean)) {
      await _handleConversationCancelCommand(generation);
      return;
    }

    // 🔇 [NOISE-GATE] 로컬 잡음 검열은 화면과 API보다 먼저 온다. 뒤에 두면
    //   잡음에도 임시 말풍선이 먼저 뜨고 validator·합치기 왕복이 나간다.
    //   여기서 걸린 발화는 말풍선·validator·AI 응답·TTS·저장 어디에도 닿지
    //   않고 턴 수도 먹지 않는다 — 잡음이 5턴을 갉아먹으면 안 된다.
    //   마이크를 열 때 달아 둔 "..." 말풍선이 남아 있으므로 같이 걷어낸다.
    if (_isNoiseTranscript(userKorean)) {
      _log('🔇 [NOISE-GATE]',
          'mode=step_expand dropped=true len=${userKorean.length}');
      if (mounted) {
        setState(() {
          _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
        });
      }
      if (_isConversationActive && !_isSessionComplete) _startUserListening();
      return;
    }

    // 🟠 [FAST-DISSATISFIED] 질문 불만은 전사 오류가 아니다. 검증기보다 먼저
    //    본다. 뒤에 두면 "이거 아까 질문하고 똑같잖아" 같은 말이
    //    transcription_is_irrelevant_to_context로 걸려 "제가 잘 못 들은 것
    //    같아요"로 되받고, 질문 교체까지 가지도 못한다(실기기에서 확인).
    if (_turnCounter > 0 && _isQuestionDissatisfactionRaw(userKorean)) {
      _log('🟠 [FAST-DISSATISFIED]', '질문 불만 감지 → 직전 질문 교체');
      await _replaceLastQuestion(generation: generation);
      return;
    }

    // 🌱 [SEED] AI 첫마디에 이어 **유저가 처음 한 말이 곧 씨앗**이다.
    //
    //   한동안은 잡담을 여러 턴 이어가며 그 안에서 씨앗이 될 만한 생각을
    //   골라내는 구조였다. 그러다 보니 5턴이 시작되기 전에 대화가 길어졌고,
    //   골라낸 씨앗이 유저의 생각이 아니라 AI 말에 대한 동의인 경우도 있었다.
    //   원칙으로 되돌린다 — 유저가 무엇을 말하든 그 말에서 문장을 키운다.
    //
    //   씨앗 판정은 여기 없다. 아래 [KoreanTurnValidator]가 이 턴의 게이트고,
    //   못 알아들은 발화는 거기서 되묻기로 걸린다.
    if (!_seedFound) {
      _seedFound = true;
      // 씨앗이 섰다. 여기서부터는 5턴 사다리가 대화를 끌고 가므로
      // 이어 말하기는 두 번 다시 걸지 않는다.
      _cancelSmallTalkSilence(reason: 'seed_found');
      _log('🌱 [SEED]',
          'len=${userKorean.characters.length} text="$userKorean"');
    }

    // 🗣️ 방금 한 말을 검증·합치기보다 먼저 띄운다. 둘 다 GPT 왕복이라
    //   (검증은 gpt-4o-mini, 합치기는 gpt-4.1-mini)
    //   그 뒤에 두면 유저가 자기 말을 글자로 보기까지 한참을 "..."로 기다린다.
    //   여기 뜨는 건 방금 한 말이고, 합치기가 끝나면 자란 문장으로 바뀐다 —
    //   문장이 어떻게 자랐는지 보여주는 것이 이 모드의 핵심이라 최종 말풍선은
    //   그대로 자란 문장을 쓴다. 반려·되묻기 분기는 이 임시 말풍선을 걷어낸다.
    if (mounted) {
      setState(() {
        _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
        _localMessages.add(<String, dynamic>{
          'role': 'HOST_TEMP',
          'target': userKorean,
          'original': '',
        });
      });
      _scrollToBottom();
    }

    // ⚡ [HISTORY FAST PATH]
    // 이 방의 원본은 매 턴의 실제 발화와 대화 히스토리다. 화면에도 원문만
    // 보이고, 완성 글은 세션이 끝난 뒤 전체 히스토리를 읽는 Expansion Builder가
    // 만든다. 그런데 예전에는 첫 턴에 별도 검증 API, 2턴부터 별도 합치기 API를
    // 답변 앞에 하나 더 샀다. 보이지도, 최종 글에 쓰이지도 않는 중간 문장을
    // 만들기 위해 반응을 늦춘 셈이다.
    //
    // 이제 확정 STT 원문을 바로 히스토리에 싣고 강사 생성 한 번으로 간다.
    // 잡음은 위 로컬 게이트가 이미 제거하고, 못 알아들은 말은 강사 프롬프트의
    // [IF YOU CANNOT MAKE IT OUT] 규칙이 같은 응답 안에서 처리한다.
    final previousExpandedNow = _turnGateSentence.trim();
    final localPassThrough = previousExpandedNow.isEmpty
        ? null
        : Future<StepExpandMergeResult>.value(
            StepExpandMergeResult(text: userKorean),
          );
    _log('⚡ [HISTORY-FAST]', '전사 확정 → 중간 검증·합치기 생략 → 강사 응답 1회');
    await _processStepExpandTurn(
      userKorean,
      generation: generation,
      mergedFuture: localPassThrough,
    );
  }

  // 대화방의 라이브 턴. 누적 문장을 먼저 확정해 유저 말풍선에 올리고,
  // gpt-4.1-mini가 다음 한국어 질문을 만든 뒤 별도 TTS로 읽는다.
  Future<void> _processStepExpandTurn(
    String userKorean, {
    required int generation,
    // 2턴부터 이 턴의 게이트. 호출부가 던져 둔 합치기를 여기서 받아 쓴다.
    // 1턴(씨앗)은 붙일 대상이 없어 null이고, 그 턴은 호출부의 검증기가
    // 게이트였다.
    Future<StepExpandMergeResult>? mergedFuture,
  }) async {
    if (!mounted ||
        !_isConversationActive ||
        generation != _pipelineGeneration) {
      // 방을 나갔거나 세대가 바뀌었다. 결과를 받을 사람이 없으므로 명시적으로
      // 버린다 — 그냥 두면 대기자 없는 Future로 남는다.
      mergedFuture?.ignore();
      return;
    }
    if (_isNoiseTranscript(userKorean)) {
      mergedFuture?.ignore();
      if (_isConversationActive && !_isSessionComplete) _startUserListening();
      return;
    }
    _turnCounter++;
    final turnNumber = _turnCounter;
    // 🔁 [LATE-CONTINUATION] 학습 진행 수(`_turnCounter`)는 되묻기·실패에서
    //   되돌아간다. 늦은 콜백 차단에 그 값을 쓰면 되돌린 번호가 새 턴과 다시
    //   같아진다. 차단은 **되돌지 않는** 이 값으로 한다.
    final int asyncTurnId = ++_asyncTurnSeq;
    _activeAsyncTurnId = asyncTurnId;
    _aiTurnActive = true;
    var aiIndex = -1;
    var askedBack = false;
    var turnCompleted = false;

    // 🌱 [NATIVE-EXPAND] 이번 턴이 이어 붙일 대상. 되묻기나 실패로 이 턴을
    //   무를 때 여기로 되돌린다.
    final previousExpanded = _turnGateSentence.trim();
    final previousPending = List<String>.from(_turnGatePendingParts);
    final mergeInputs = <String>[..._turnGatePendingParts, userKorean];
    Map<String, dynamic>? hostBubble;
    // ⚡ [PARALLEL] 합치기 게이트와 나란히 띄우는 코치 대사. try 밖에 두는
    //   이유는 하나다 — 게이트 도중에 터져도 catch에서 버릴 수 있어야 한다.
    //   받을 사람 없는 future의 실패는 잡히지 않은 예외로 새어 나온다.
    Future<String>? aiKoreanFuture;
    var aiKoreanClaimed = false;
    void discardPendingReply() {
      if (!aiKoreanClaimed) aiKoreanFuture?.ignore();
    }

    try {
      setState(() {
        _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
      });

      // 🧩 [MENU-TURN] 한 턴의 모양은 하나다 — 지금까지 자란 글과, 이어 붙일
      //   완성 문장 셋. 모델에게 누적 글과 **직전에 내놓은 후보 셋**을 함께
      //   준다. 후보를 안 주면 "2번이 좋아"가 무슨 문장인지 알 수 없어서,
      //   모델이 그럴듯한 다른 문장을 지어내 붙인다.
      //
      //   예전에 여기 있던 합치기 게이트는 걷어냈다. 그건 유저가 **자기 말로**
      //   답하던 시절의 물건이라, "2번"을 문장에 병합하려다 매번 반려했다.
      //   무엇이 붙었는지는 이제 유저가 고른 문장으로 정해진다.
      mergedFuture?.ignore();
      final bool isFirstTurn = previousExpanded.isEmpty;
      final questionContext = _questionContext(currentUserLine: userKorean);
      aiKoreanFuture = StepExpandBrain.generateKoreanTurn(
        apiKey: _openAiKey,
        instructions: _buildStepExpandSystemInstructions(),
        recentConversation: questionContext,
        userText: buildStepExpandMenuState(
          growingText: previousExpanded,
          lastOptions: _lastMenuOptions,
          userLine: userKorean,
          turnNumber: turnNumber,
        ),
      );
      // 유저 말풍선에 걸 글. 누적 글은 아래에서 모델 응답을 읽은 뒤 확정된다.
      var bubbleText = previousExpanded.isEmpty ? userKorean : previousExpanded;

      // 2️⃣ 자란 문장을 먼저 화면에 올린다.
      // 🔁 [LATE-CONTINUATION] id를 박아 둔다. 이어 말하기로 문장이 자라면
      //   새 말풍선을 만들지 않고 이 id로 찾아 글자만 바꾼다.
      if (_bubbleIndexById(_activeHostBubbleId) < 0) {
        _activeHostBubbleId = _nextBubbleId('host');
      }
      hostBubble = <String, dynamic>{
        'role': 'HOST',
        // 🌱 [BRIDGE] 자란 원어 문장. **화면에는 안 나온다.** Stage 3에서
        //   Expansion Builder가 이 자리를 가져가면 함께 사라진다.
        'target': bubbleText,
        // 🗣️ [ORIGIN-ONLY] 방이 보여 주는 건 유저가 실제로 한 말뿐이다.
        'original': userKorean,
        'msgId': _activeHostBubbleId,
      };
      setState(() => _localMessages.add(hostBubble!));
      _scrollToBottom();

      // 🌱 마지막 턴에서는 AI가 말을 얹지 않는다. 5번째 답까지 받으면 문장은
      //   다 자란 상태라 더 물을 것이 없다. 그런데도 생성을 돌리면 유저가
      // 유저 문장이 화면에 올라온 뒤에만 AI 대기 점을 표시한다.
      // 청취 시작 전에는 점 3개를 만들지 않는다.
      // 🔁 [LATE-CONTINUATION] 취소 시 이 id로 정확히 집어 걷어낸다.
      _activeAiBubbleId = _nextBubbleId('ai');
      setState(() {
        _localMessages.add(<String, dynamic>{
          'role': 'SYSTEM',
          'target': '',
          'original': '',
          'msgId': _activeAiBubbleId,
        });
        aiIndex = _localMessages.length - 1;
      });
      _scrollToBottom();

      // 3️⃣ 그 다음에 AI가 다음 질문을 건다.
      //    답은 gpt-4.1-mini가 한국어로 만들고, 소리는 아래에서 TTS가 낸다.
      //    방금 한 말이 아니라 지금까지 자란 문장을 통째로 준다. 다음에 무슨
      //    말이 올지 추측하려면 문장 전체가 보여야 한다.
      // ⚡ [PARALLEL] 합치기와 나란히 띄워 둔 결과를 여기서 받는다. 게이트가
      //   통과했으므로 이 대사는 실제로 쓰인다.
      aiKoreanClaimed = true;
      final String rawReply = await aiKoreanFuture;
      if (rawReply.isEmpty) {
        throw StateError('Step Expand reply did not complete.');
      }
      final menu = closeStepExpandMenuIfLast(
        parseStepExpandMenuTurn(rawReply),
        turnNumber: turnNumber,
      );
      _log(
          '🧩 [MENU-TURN]',
          'turn=$turnNumber options=${menu.options.length} pick=${menu.pick} '
              'done=${menu.done} askBack=${menu.askBack.isNotEmpty} '
              'textLen=${menu.text.characters.length}');
      if (!mounted ||
          !_isConversationActive ||
          generation != _pipelineGeneration ||
          asyncTurnId != _activeAsyncTurnId) {
        return;
      }
      turnCompleted = true;
      // 👂 되묻기 턴이면 유저 발화를 버린다. 화면에도 히스토리에도 남기지
      //   않고 턴 번호도 되돌려, 유저가 다시 말한 것이 이 턴이 되게 한다.
      //   되묻는 말은 소리로만 내보낸다 — 글자로 남기면 지우는 사람이 없어
      //   쌓이고, 다음 턴 컨텍스트에 섞여 AI가 따라 되묻는다.
      if (menu.askBack.isNotEmpty) {
        askedBack = true;
        _turnCounter--;
        // 잘못 들은 발화로 자란 글은 없던 일로 되돌린다. 후보 셋도 그대로
        // 살려 둔다 — 유저가 다시 말하면 같은 번호를 고를 수 있어야 한다.
        _turnGateSentence = previousExpanded;
        _turnGatePendingParts
          ..clear()
          ..addAll(previousPending);
        setState(() {
          _localMessages.remove(hostBubble);
        });
        _log('[ASK-BACK]', 'turn=$turnNumber 되묻기 → 유저 발화 폐기(화면/히스토리 미기록)');
        final spokenQuestion = stripHeardConfirmSignal(menu.askBack);
        await _speakAiKorean(spokenQuestion.isEmpty
            ? originRetryLine(_nativeLangName())
            : spokenQuestion);
        return;
      }
      // 🧩 틀이 깨져 걸 것이 없으면 이 턴은 실패다. 아무 글이나 화면에 올려
      //   유저가 후보인 줄 알고 고르는 것보다, 다시 듣는 쪽이 낫다.
      if (!menu.isUsable) {
        askedBack = true;
        _turnCounter--;
        _turnGateSentence = previousExpanded;
        setState(() {
          _localMessages.remove(hostBubble);
        });
        _log('⚠️ [MENU-BROKEN]', 'turn=$turnNumber raw="$rawReply"');
        await _speakLiveKorean(originRetryLine(_nativeLangName()));
        return;
      }

      // ✅ 이번 턴에 무엇이 붙었는지가 여기서 확정된다. 유저가 고른 문장이든
      //   자기 말이든, 모델이 돌려준 누적 글이 곧 이 방의 사다리 한 칸이다.
      _turnGateSentence = menu.text.isEmpty ? previousExpanded : menu.text;
      _turnGatePendingParts.clear();
      _lastMenuOptions = List<String>.from(menu.options);
      bubbleText = _turnGateSentence;
      hostBubble['target'] = bubbleText;
      final String aiKorean =
          composeStepExpandMenuSpeech(menu, isFirstTurn: isFirstTurn);
      _log('💬 [AI-LINE]',
          'phase=expand turn=$turnNumber len=${aiKorean.characters.length}');

      // 🧹 [DISPOSE-GUARD] GPT 스트리밍을 기다리는 동안 방을 나갔을 수 있다.
      //   defunct 위젯에 setState하면 예외가 나고 아래 정리까지 건너뛴다.
      if (!mounted || _isDisposing) return;
      setState(() {
        // 델타가 한 번도 안 왔으면(전체가 finalText로만 도착) 여기서 만든다.
        if (aiIndex < 0) {
          _localMessages.add(<String, dynamic>{
            'role': 'SYSTEM',
            'target': aiKorean,
            'original': '',
          });
          aiIndex = _localMessages.length - 1;
        } else {
          _localMessages[aiIndex]['target'] = aiKorean;
          _localMessages[aiIndex]['original'] = '';
        }
      });
      _scrollToBottom();
      await _speakAiKorean(aiKorean);

      // 🪜 [LADDER] 이 턴까지 자란 글을 줄에 함께 싣는다.
      //   사다리는 이제 **방 안에서 확정된다** — 유저가 고른 문장이 곧 한 칸이라,
      //   대화가 끝난 뒤 다시 추측할 것이 없다. 이 값을 안 남기면 히스토리가
      //   "2번이 좋아"를 유저의 생각으로 읽는다.
      final hostLine = <String, dynamic>{
        'role': 'HOST',
        'original_text': userKorean,
        'expanded_sentence': _turnGateSentence,
      };
      final systemLine = <String, dynamic>{
        'role': 'SYSTEM',
        'original_text': aiKorean,
      };
      await _saveTurnToFirestore(<Map<String, dynamic>>[hostLine, systemLine]);
      await _saveHistoryMessages(<Map<String, dynamic>>[hostLine, systemLine]);
      _log('[GPT-HISTORY]',
          'turn=$turnNumber model=gpt-4.1-mini voice=$_aiVoice tts=true');

      // 🏁 글이 다 자랐다. 마이크를 닫고 공부방으로 안내한 채 끝낸다.
      if (menu.done && mounted && _isConversationActive) {
        _log('🏁 [MENU-DONE]', 'turn=$turnNumber 확장 종료 → 세션 완료');
        setState(() => _isSessionComplete = true);
        // 마이크를 닫는다. 아래 finally의 재청취 분기도 `_isSessionComplete`를
        // 보고 스스로 비켜선다.
        unawaited(_stopStreamingCapture(reason: 'menu_done'));
        return;
      }
    } catch (error) {
      // ⚡ [PARALLEL] 게이트 도중에 터졌으면 나란히 띄운 대사가 주인 없이
      //   남는다. 안 받은 future의 실패는 잡히지 않은 예외로 새어 나온다.
      discardPendingReply();
      _log('[GPT-PIPE-ERR]',
          'turn=$turnNumber reason=${error.runtimeType} error=$error');
      // 실패한 요청이 정상 턴 수를 먹지 않게 한다. 그래야 재발화가 다시 같은
      // Step 번호로 처리되고 5턴 완료 상태가 앞당겨지지 않는다.
      // 턴 번호 회수는 아래 finally의 [TURN-ROLLBACK] 한 곳에서만 한다 —
      // 여기서도 깎으면 되돌리는 자리가 둘이 되어 어느 쪽이 깎았는지 로그로
      // 가릴 수 없다.
      final turnStillActive =
          mounted && _isConversationActive && generation == _pipelineGeneration;
      if (turnStillActive && !turnCompleted && !askedBack) {
        // 답을 못 받은 턴이므로 자란 문장도 이전 상태로 되돌린다. 유저가
        // 다시 말하면 그 발화가 같은 자리에서 다시 붙는다.
        _turnGateSentence = previousExpanded;
        _turnGatePendingParts
          ..clear()
          ..addAll(previousPending);
        setState(() {
          // 확정되지 못한 유저 말풍선과 placeholder는 남기지 않는다.
          _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
          if (hostBubble != null) _localMessages.remove(hostBubble);
          if (aiIndex >= 0 &&
              aiIndex < _localMessages.length &&
              (_localMessages[aiIndex]['target'] ?? '').toString().isEmpty) {
            _localMessages.removeAt(aiIndex);
          }
        });
        // 유저에게는 실패 원인이 아니라 다시 말해 달라는 말만 필요하고, 그
        // 말은 소리로만 나간다. 진짜 원인은 위 [GPT-PIPE-ERR] 로그에 남는다.
        // 글자로 남기면 API가 흔들린 턴마다 말풍선이 쌓인다.
        await _speakLiveKorean(originRetryLine(_nativeLangName()));
      }
    } finally {
      // 🔢 [TURN-ROLLBACK] 이 턴은 맨 위에서 이미 _turnCounter를 올려 뒀다.
      //   되묻기·[META]·예외는 각자 되돌리지만, **세대가 갈려 중간에서 그냥
      //   return한 길**에는 되돌리는 곳이 없었다. 이어 말하기가 턴을 무를
      //   때마다 번호가 하나씩 새어, 실기기에서 1→3→4→5로 뛰고 유저 답 네
      //   개에 5턴이 끝났다(2026-08-22).
      //   _turnCounter가 아직 이 턴 번호일 때만 되돌린다 — 그사이 새 턴이
      //   올려 놨다면 남의 번호를 깎는 셈이 된다.
      if (!turnCompleted && !askedBack) {
        if (_turnCounter == turnNumber) {
          _turnCounter--;
          _log('🔢 [TURN-ROLLBACK]',
              'turn=$turnNumber → $_turnCounter (미완료 턴 회수)');
        } else {
          _log('🔢 [TURN-ROLLBACK]',
              'skipped turn=$turnNumber counter=$_turnCounter (새 턴이 이미 진행)');
        }
      }
      // 🔐 [GEN-OWNERSHIP] 이어 말하기로 세대가 갈렸으면 이 파이프라인은 더
      //   이상 주인이 아니다. 여기서 busy를 내리면 새 턴이 [TURN-SKIP] 가드
      //   없이 노출된다.
      if (generation == _pipelineGeneration &&
          asyncTurnId == _activeAsyncTurnId) {
        _aiTurnActive = false;
      } else {
        _log('[GEN-OWNERSHIP]',
            'stale finally skipped asyncTurn=$asyncTurnId gen=$generation');
      }
      // 🔁 [LATE-CONTINUATION] **턴이 끝나면 잠정 상태를 반드시 놓는다.**
      //   빠지면 AI 첫 재생이 세운 _aiPlaybackStarted가 영구히 남아 복구 창이
      //   두 번 다시 열리지 않고, 조각·말풍선 id가 다음 턴으로 새어 앞 턴
      //   문장에 새 말이 붙는다. 주인일 때만 정리한다.
      if (generation == _pipelineGeneration &&
          asyncTurnId == _activeAsyncTurnId &&
          !_continuationCandidateAlive) {
        _resetContinuationState();
      }
      // 되묻기 턴은 _turnCounter를 되돌렸으므로 turnNumber와 어긋난다.
      // 그 경우에도 마이크는 반드시 다시 열어야 대화가 이어진다.
      if (mounted &&
          _isConversationActive &&
          !_isSessionComplete &&
          generation == _pipelineGeneration &&
          (askedBack || turnCompleted || turnNumber - 1 == _turnCounter)) {
        _startUserListening();
      }
    }
  }

  /// 턴마다 얹는 짧은 지시.
  ///
  /// 예전에는 턴 번호로 축을 고정했다 — 1턴 감정, 2턴 사람·장소·사물, 3턴
  /// 기분, 4턴 이야기가 향하는 곳. 이야기(narrative) 씨앗에만 맞는 축들이라,
  /// "부정은 밝혀져야 한다" 같은 **의견** 씨앗이 오면 1턴 지시가 걸 데가 없어
  /// 모델이 문장 속 명사로 도망쳤다. 방향은 턴 번호가 아니라 문맥이 고른다.
  String _buildStepExpandTurnInstructions(int turnNumber,
      {bool mustNotAsk = false}) {
    return '''Look at the whole conversation, not just their last line. First decide
which MATERIAL STAGE you are holding:
- RAW WORD OR TOPIC: establish what the user wants to say about it. Offer one sharp
  editorial direction yourself, then ask for the smallest concrete material that
  direction needs. Do not make the user choose the writing strategy, do not demand
  a complete sentence, and do not ask an open question.
- ROUGH CLAUSE: find its center and help choose the precise subject and verb.
- WORKING SENTENCE: improve it with the single most valuable missing move — reason,
  concrete evidence, contrast, limit, consequence, or a sharper point.
- RICH SENTENCE: stop adding. Cut dilution or improve rhythm and precision.
Make an editorial decision. If learning something would only add another fact
about the subject, it is the wrong thing. Improve the THOUGHT, not the inventory.
${mustNotAsk ? '''
You asked within the last two turns, so this turn ends without a question mark.
Give one concrete editorial direction and leave the opening there.''' : '''
If you ask, one question only, after your editorial direction. Make it easy to
answer with one word, a choice, or the end of a phrase.'''}''';
  }

  /// 되묻기 판정은 언어와 무관한 공통 내부 신호만 사용한다.
  static bool _isAskBackReply(String text) => hasHeardConfirmSignal(text);

  void _cancelSpeculativeTranslation() {
    final sub = _specSub;
    _specSub = null;
    final c = _specController;
    _specController = null;
    _specTranscript = '';
    sub?.cancel();
    if (c != null && !c.isClosed) c.close();
  }

  Future<void> _handleConversationCancelCommand(int generation) async {
    _log('[VOICE-CANCEL]', '직전 사용자 턴부터 삭제 시작');
    _streamingStt?.closeAudioGate(reason: 'voice_cancel_command');
    await _stopStreamingCapture(reason: 'voice_cancel_command');
    _ttsQueueManager.stop();
    _ttsQueueManager.setUserTurn(false);
    _ttsQueueManager.setAiPaused(false);
    _pendingHeardConfirmation = null;
    _heardConfirmationAttempts = 0;
    _closeContinuationWindow(reason: 'voice_cancel_command');
    _resetContinuationState();

    var removedUserTurn = false;
    if (mounted) {
      setState(() {
        _localMessages.removeWhere((message) => message['role'] == 'HOST_TEMP');
        removedUserTurn = removeFromLastUserTurn(_localMessages);
        _isSessionComplete = false;
        _debugResult = '⏱️ 듣는 중...';
      });
      if (_localMessages.isNotEmpty) _scrollToBottom();
    }
    if (removedUserTurn && _turnCounter > 0) _turnCounter--;
    _turnGateSentence = '';
    for (var index = _localMessages.length - 1; index >= 0; index--) {
      if (_localMessages[index]['role'] == 'HOST') {
        _turnGateSentence =
            (_localMessages[index]['target'] ?? '').toString().trim();
        break;
      }
    }
    _turnGatePendingParts.clear();

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (removedUserTurn && user != null) {
        await rollbackLastPersistedUserTurn(
          firestore: FirebaseFirestore.instance,
          uid: user.uid,
          sessionDocId: _sessionDocId,
          historyRef: _myHistoryRef,
        );
      }
      _lastExchangeMsgIds = <String>[];
      _log('[VOICE-CANCEL]', '직전 사용자 턴 삭제 완료 removed=$removedUserTurn');
    } catch (error) {
      _log('[VOICE-CANCEL-ERR]', '저장본 삭제 실패 reason=${error.runtimeType}');
    }

    if (mounted &&
        _isConversationActive &&
        generation == _pipelineGeneration &&
        !_isSessionComplete) {
      await _startUserListening();
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

      await _ensureHistoryRef();

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
        BillingTicker.instance.setSessionIdentifiers(
          sessionDocId: _sessionDocId,
          roomId: _myHistoryRef?.id,
        );
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
        'last_active': FieldValue.serverTimestamp(),
        'room_name': "Step.Ex Mode",
        'mode': 'step_expand',
        'is_pinned': false,
        'has_practice': false,
        'last_message': '',
        'msg_count': 0,
        // 세션 생성 당시 언어 식별값 보존(History 동일 언어 판정용)
        'native_lang': _nativeLangName(),
        'target_lang': FFAppState().targetLang,
      });
      BillingTicker.instance.setSessionIdentifiers(
        sessionDocId: _sessionDocId,
        roomId: _myHistoryRef?.id,
      );
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
      final List<String> savedIds = [];
      for (final line in chatLines) {
        final original = (line['original_text'] ?? '').toString().trim();
        if (original.isEmpty) continue;
        // 🌱 [EXPAND-LADDER] 이 턴까지 자란 원어 문장. 유저 줄에만 실린다.
        //   히스토리 P2가 이 값으로 확장 사다리를 재현한다 — 없으면 조각
        //   문장으로 폴백해 P1과 똑같아진다.
        final expanded = (line['expanded_sentence'] ?? '').toString().trim();
        final addedRef = await _myHistoryRef!.collection('messages').add({
          'role': line['role'] ?? '',
          // Target은 History 진입 시 gpt-4o-mini로 최초 1회 생성한다.
          'original_text': original,
          // 누적 문장의 배울글도 같은 자리에서 함께 만든다.
          if (expanded.isNotEmpty) 'expanded_sentence': expanded,
          'created_at': FieldValue.serverTimestamp(),
        });
        savedIds.add(addedRef.id);
      }
      if (savedIds.isNotEmpty) {
        _lastExchangeMsgIds = List<String>.from(savedIds);
      }

      // 🔧 [핵심] 턴마다 msg_count/last_message 업데이트
      //   - 뒤로가기 경로와 무관하게 항상 갱신됨
      //   - last_message는 마지막 비어있지 않은 translated_text
      final lastOriginal = chatLines
          .map((l) => (l['original_text'] ?? '').toString().trim())
          .lastWhere((t) => t.isNotEmpty, orElse: () => '');
      if (lastOriginal.isNotEmpty) {
        final updateMap = <String, dynamic>{
          'msg_count': FieldValue.increment(chatLines.length),
          'last_message': lastOriginal,
          'last_active': FieldValue.serverTimestamp(),
        };
        await _myHistoryRef!.update(updateMap);
        _log('💾 [HIST-UPD]',
            'msg_count+${chatLines.length}, korean_text_only=true');
      }
    } catch (e) {
      _log('❌ [HIST-ERR]', 'chat_history 저장 실패: $e');
    }
  }

  /// 뒤로가기 시: 빈 방 폭파 or last_message 업데이트 후 나가기
  Future<void> _handleAutoSaveAndExit() async {
    if (_isExiting) return; // 🔧 [EXIT-GUARD] 이미 종료 처리 중이면 무시
    _isExiting = true;
    // 🔇 소리부터 끊는다. 아래 Firestore 저장은 몇 초씩 걸릴 수 있는데, 그동안
    //   Realtime 세션이 살아 있으면 방을 나온 뒤에도 AI 목소리가 계속 들린다.
    //   5턴 완료 경로는 이미 이 순서인데 뒤로가기 경로만 빠져 있었다.
    _stopEverything();
    BillingTicker.instance.pause();
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
          // 🌱 [EXPANSION] 이 방의 영어는 여기서 시작한다.
          //
          //   전사는 턴마다 이미 저장돼 있다(_saveHistoryMessages). 그래서
          //   지금 할 일은 방 문서를 마감하고 사다리 제작을 거는 것뿐이다.
          //   순서가 이 방향인 이유는 하나다 — 사다리 만들기가 실패해도
          //   유저가 나눈 대화는 이미 남아 있어야 한다(§18).
          final transcript = stepExpansionTranscriptFrom(_localMessages);

          final updateMap = <String, dynamic>{
            'last_message': lastText,
            'last_message_time': FieldValue.serverTimestamp(),
            'msg_count': _localMessages.length,
            'last_active': FieldValue.serverTimestamp(),
          };

          // session_ref 있을 때만 추가 (신규 세션 생성된 경우)
          if (_sessionDocId != null) {
            updateMap['session_ref'] = _sessionDocId;
          }

          // 🎓 [PRACTICE-GATE] 나가는 순간에는 Practice를 **잠근 채로** 둔다.
          //   여기서 미리 열어 두면 사다리가 실패한 방도 공부방에 연습으로
          //   떠서, 눌렀을 때 빈 화면이 나온다. 여는 건 사다리가 실제로
          //   생긴 뒤 [finalizeStepExpansions]가 한다.
          final bool willBuild = transcript.any((turn) => turn.isUser);
          if (willBuild) {
            updateMap['expansion_status'] = StepExpansionStatus.building;
            // stale 판정의 기준점. [finalizeStepExpansions]가 시작할 때 다시
            //   찍지만, 그 첫 쓰기 전에 앱이 죽는 창이 있다.
            updateMap['expansion_started_at'] = FieldValue.serverTimestamp();
            updateMap['has_practice'] = false;
          }

          await _myHistoryRef!.update(updateMap);
          _log('💾 [HIST-UPD]',
              'chat_history 마감 (turns=${transcript.length} build=$willBuild)');

          // 사다리 제작은 위젯 생명주기와 끊어서 던진다. 유저를 40초 붙잡아
          // 둘 이유가 없고, Firestore 쓰기는 화면이 사라져도 끝난다.
          // 도중에 앱이 죽으면 `building`으로 남고, 히스토리가 재시도를 건다.
          if (willBuild) {
            final roomRef = _myHistoryRef!;
            final apiKey = _openAiKey;
            final originLang = _nativeLangName();
            final targetLang = FFAppState().targetLang;
            unawaited(finalizeStepExpansions(
              roomRef: roomRef,
              apiKey: apiKey,
              ladder: stepExpandLadderFrom(_localMessages),
              originLang: originLang,
              targetLang: targetLang,
              onLog: _log,
            ));
          }
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

  /// 🏫 [SR] 대화방 → 공부방.
  ///
  /// 방을 켜 둔 채 목록만 얹으면 안 된다. 공부방 목록은 dispose에서 과금
  /// 티커를 멈추므로, 돌아왔을 때 밑에 깔린 이 방의 차감이 죽는다. 뒤로가기와
  /// 같은 저장·정리 경로를 그대로 태워 방을 닫은 뒤에 옮긴다.
  /// 라우터는 await 전에 잡아 둔다 — 나온 뒤의 context는 이미 죽어 있다.
  Future<void> _goToStudyRoom() async {
    if (_isExiting) return; // 연타·뒤로가기 직후에 목록이 두 번 얹히지 않게
    final router = GoRouter.of(context);
    await _handleAutoSaveAndExit();
    router.pushNamed('ChatHistory');
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
      // 🔧 [POPSCOPE] 시스템 제스처/하단바 뒤로가기도 AutoSave 경로를 타게 한다.
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
              ]),
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
      // 📏 오른쪽 끝에 붙여 두었더니 잔여시간이 세 자리(274:33)로 길어질 때
      //   화면 밖으로 잘려 나갔다. 한 줄로 이어 붙여 왼쪽부터 채우고, 남는
      //   자리는 오른쪽에 둔다. 시간표는 남는 폭 안에서 줄어든다.
      child: Row(
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white70),
                tooltip: '이전 단계',
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
                onPressed: _handleAutoSaveAndExit), // 🔧 [히스토리] AutoSave 연결
            // 🏫 [SR] 방금 한 대화를 그대로 들고 공부방으로 건너간다.
            Tooltip(
              message: '공부방 (Study Room)',
              child: GestureDetector(
                onTap: _goToStudyRoom,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0x33FFFFFF)),
                  ),
                  child: const Text(
                    "SR",
                    maxLines: 1,
                    style: TextStyle(
                      color: Color(0xFFE7E9EE),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ]),
          Flexible(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
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
            // 🗣️ [ORIGIN-ONLY] 원어/번역 토글을 뺐다. 예전에는 영어 줄 아래
            //   회색 원어 줄을 켜고 끄는 버튼이었는데, 이제 말풍선이 처음부터
            //   원어라 토글할 대상이 없다. 눌러도 아무 일이 없는 버튼을 남기면
            //   유저는 기능이 고장 났다고 읽는다.
            const SizedBox(width: 6),
            // [v3.6] 잔여시간 표시 + 길게 누르면 로그 (개발자용)
            Flexible(
                child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(children: [
                    ValueListenableBuilder<int>(
                      valueListenable: BillingTicker.instance.billingState,
                      builder: (_, s, __) => GestureDetector(
                        onTap: s == 0 ? resetBillingIdle : null,
                        child: CustomPaint(
                          size: const Size(14, 14),
                          painter: BillingDotPainter(s),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 🐞 [잔여시간] 예전에는 billingState 리스너 안에서
                    //   FFAppState().remainingTime을 직접 읽어, 과금 점 색이 바뀔
                    //   때만 다시 그려졌다. 초 단위로 줄어드는 값인데 화면은 멈춰
                    //   보였다. 표시만 고친다 — 이 모드는 5턴이 세션 경계라
                    //   30분 롤오버를 쓰지 않는다.
                    ValueListenableBuilder<int>(
                      valueListenable:
                          BillingTicker.instance.remainingSecondsNotifier,
                      builder: (_, remaining, __) {
                        final int s = remaining.clamp(0, 999999);
                        final int h = s ~/ 3600;
                        final int m = (s % 3600) ~/ 60;
                        return Text(
                          '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                  ]),
                ),
              ),
            )),
          ])),
        ],
      ),
    );
  }

  /// 🔇 [VOICE-ONLY] 이 방은 글자를 띄우지 않는다.
  ///
  /// 코치와 주고받는 말은 소리로만 오간다. 말풍선이 뜨면 눈이 글자를 좇고,
  /// 유저는 말하는 대신 읽게 된다 — 이 방에서 만들려는 건 읽을거리가 아니라
  /// 입으로 굴려 본 생각이다.
  ///
  /// ⚠️ **[_localMessages]는 계속 채운다.** 화면에 안 그릴 뿐, 방을 나갈 때
  ///   Expansion Builder에 넘길 transcript를 저기서 뽑는다
  ///   (`stepExpansionTranscriptFrom`). 히스토리 P1이 쓰는 글은 이것과 별개로
  ///   턴마다 Firestore에 따로 저장된다.
  Widget _buildChatList() {
    if (_isPracticeMode) return _buildPracticeContent();
    return _buildVoiceStage();
  }

  /// 소리만 오가는 방의 화면. 지금 누구 차례인지만 조용히 알려 준다.
  Widget _buildVoiceStage() {
    final bool aiSpeaking = _aiTurnActive;
    final bool started = _seedFound || _localMessages.isNotEmpty;
    final Color accent =
        aiSpeaking ? const Color(0xFF9333EA) : const Color(0xFF22D3EE);
    final String line = !_isConversationActive
        ? "잠시만요"
        : aiSpeaking
            ? "듣고 계세요"
            : started
                ? "말씀하세요"
                : "무슨 생각이든 한마디로 시작해 보세요";

    // 🙋 [BARGE-IN] 코치가 말하는 동안 화면 아무 데나 누르면 말을 끊는다.
    //
    //   말로 끊는 길은 이 모드에서 막혀 있다 — 녹음이 `echoCancel: true`라,
    //   스피커로 AI 목소리가 나가는 동안에는 입력이 통째로 눌려 유저가 무슨
    //   말을 해도 아무것도 잡히지 않는다. 그래서 [_handleBargeIn]은 만들어
    //   두고도 부를 손이 없었다. 손잡이를 화면 전체로 준다.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: aiSpeaking ? _handleBargeIn : null,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🖼️ 코치와 나란히 앉아 같이 만든다 — 이 방이 무슨 자리인지
            //   한 장으로 말한다. 폰에서는 칠판 글씨가 읽히지 않을 만큼
            //   작게 들어가서, 남는 건 장면뿐이다.
            //
            //   테두리는 장식이 아니다. 음성 전용이라 "지금 누구 차례인가"를
            //   알려 주는 신호가 이것 하나뿐이다.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: accent.withValues(alpha: aiSpeaking ? 0.95 : 0.35),
                    width: aiSpeaking ? 3 : 1.5,
                  ),
                  boxShadow: aiSpeaking
                      ? <BoxShadow>[
                          BoxShadow(
                            color: accent.withValues(alpha: 0.35),
                            blurRadius: 22,
                            spreadRadius: 1,
                          ),
                        ]
                      : const <BoxShadow>[],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: Stack(
                    children: [
                      Image.asset(
                        'assets/images/step_expand_coach.png',
                        fit: BoxFit.cover,
                        alignment: const Alignment(0, -0.25),
                      ),
                      // 유저 차례일 때는 그림을 한 겹 가라앉힌다. 화면이
                      // 기다리고 있다는 걸 눈으로도 알 수 있게.
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        color: Colors.black
                            .withValues(alpha: aiSpeaking ? 0.0 : 0.35),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  aiSpeaking
                      ? Icons.graphic_eq_rounded
                      : Icons.mic_none_rounded,
                  color: accent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    line,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 15 * _fontScale,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            // 끊을 수 있다는 걸 알려 주지 않으면 아무도 화면을 누르지 않는다.
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: aiSpeaking ? 1.0 : 0.0,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  "화면을 누르면 말을 끊고 들어요",
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12 * _fontScale,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
              const Text('Practice',
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
          // 작동 중 노란 불빛 인디케이터
          // 🔁 [LATE-CONTINUATION] 복구 창이 열려 있으면 점이 커지고 초록으로
          //   살아난다 — "아직 듣고 있다"를 글자 없이 알린다.
          AnimatedBuilder(
            animation: _continuationPulse,
            builder: (context, _) {
              final double t = _continuationListening
                  ? Curves.easeInOut.transform(_continuationPulse.value)
                  : 0.0;
              final double size = 10 + (15 - 10) * t;
              return Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _continuationListening
                      ? const Color(0xFF4ADE80)
                      : (_isConversationActive
                          ? const Color(0xFFFBBF24)
                          : Colors.transparent),
                  border: Border.all(
                    color: _continuationListening
                        ? const Color(0xFF4ADE80)
                        : (_isConversationActive
                            ? const Color(0xFFFBBF24)
                            : Colors.white24),
                    width: 1.5,
                  ),
                  boxShadow: _continuationListening
                      ? <BoxShadow>[
                          BoxShadow(
                            color: const Color(0x664ADE80),
                            blurRadius: 6 + 6 * t,
                            spreadRadius: 1 + 2 * t,
                          ),
                        ]
                      : null,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ====================================================================

  // ====================================================================
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

  // 🚀 [FIRST-TURN] 첫 발사 임계(단어 수). 첫 턴은 2로 낮춰 첫 TTS fetch를 앞당긴다.
  final int fireWordThreshold;

  HybridTtsPlayer({
    required this.apiKey,
    this.voice = 'marin',
    this.onLog,
    this.fireWordThreshold = 4,
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

    if (punctMatch == null && wordCount < fireWordThreshold) return -1;

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
        '발사(${punctMatch != null ? "구두점" : "$fireWordThreshold단어"}): "$text" ${lastFirstChunkMs}ms');
    return cutIdx;
  }

  /// 🔊 [WHOLE-SENTENCE] 문장을 쪼개지 않고 tts-1 한 번으로 읽는다.
  ///
  /// `fetcher.addText`가 캐시 확인 → (없으면) API 1회 → 캐시 저장 → 재생 큐를
  /// 모두 처리하므로, 히스토리용 통문장 캐시(`_cacheFullSentenceInBackground`)를
  /// 따로 부를 필요가 없다. 한 턴에 나가던 tts-1 요청 4개가 1개로 줄고, 같은
  /// 문장을 다시 들을 때는 호출이 0개가 된다.
  ///
  /// 조각내지 않는 것이 핵심이다. tts-1은 넘겨준 텍스트를 완결된 발화로 읽으므로,
  /// 쪼개면 조각마다 억양이 새로 시작하고 끝에서 내려간다. 한 번에 주면 문장
  /// 전체가 하나의 호흡으로 나온다.
  Future<void> speakWholeSentence({
    required String fullSentence,
    required ChunkedTtsFetcher fetcher,
    required Stopwatch swSpeechEnd,
  }) async {
    final sentence = fullSentence.trim();
    if (sentence.isEmpty) return;
    _firstChunkFired = true;
    lastFirstChunkMs = swSpeechEnd.elapsedMilliseconds;
    fetcher.addText(sentence);
    onLog?.call(
        '[HYB-WHOLE]', '통문장 1회 발사 (${sentence.length}c) ${lastFirstChunkMs}ms');
  }

  // GPT 스트림 종료 시 호출:
  //   1) remainder 청크 순차 발사 (기존 큐에 이어서)
  //   2) fullSentence TtsCache 저장 (재생 없음 — 히스토리 뷰 HIT 유도)
  Future<void> onStreamEnd({
    required String fullSentence,
    required String remainderBuffer,
    required ChunkedTtsFetcher fetcher,
    required Stopwatch swSpeechEnd,
    // 🎙️ [FIRST-TURN-REALTIME] 낭독 음성이 이미 다른 엔진(Realtime)에서 공급된 턴.
    //   tts-1 발사는 건너뛰고 히스토리용 통문장 캐시 저장만 그대로 수행한다.
    bool speechAlreadySupplied = false,
  }) async {
    if (speechAlreadySupplied) {
      final sentence = fullSentence.trim();
      if (sentence.isNotEmpty)
        unawaited(_cacheFullSentenceInBackground(sentence));
      return;
    }
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
// 📦 [Box 7-A: ConversationHistory] — routine_mode_roleplay.dart로 일원화
//   동일 구현이 두 벌이라 이 파일 사본을 제거하고 import로 대체했다.
// ====================================================================

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
  final Function(DeepgramTurnResult)? onTurnResult;
  final Function(String) onError;
  final Function(int)? onReconnecting; // 재연결 시도 알림 (선택적)
  final VoidCallback? onGaveUp; // 재연결 포기 알림 (선택적)
  final void Function(String tag, String msg)? onLog; // 🔬 [v3.1] 로그 훅
  final void Function(Uint8List)? onAudioData;

  IOWebSocketChannel? _channel;
  StreamSubscription? _audioSub;
  StreamSubscription? _wsSub;
  String _currentTranscript = '';
  final List<DeepgramWordResult> _finalWords = [];
  final List<double> _chunkTranscriptConfidences = [];
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
    this.onTurnResult,
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

      final channel = IOWebSocketChannel.connect(
        uri,
        headers: {'Authorization': 'Token $apiKey'},
        pingInterval: const Duration(seconds: 10),
      );
      _channel = channel;
      _lg('🎤 [DG-01]',
          'WebSocket 연결 요청 전송 keyLen=${apiKey.length} lang=$langCode');

      // 🔬 핸드셰이크가 실제로 끝났는지 본다. IOWebSocketChannel.connect는
      //   즉시 반환하고 뒤에서 붙으므로, 이 로그가 없으면 소켓이 아직 안 붙은
      //   것이고 그 사이 sink.add로 넣은 오디오는 어디에도 도달하지 않는다.
      unawaited(channel.ready.then<void>((_) {
        if (_isDisposed) return;
        _lg('🎤 [DG-READY]', 'WebSocket 핸드셰이크 완료');
      }).catchError((Object e) {
        _lg('❌ [DG-READY-FAIL]', '핸드셰이크 실패: ${e.runtimeType} $e');
      }));

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
            echoCancel: true,
            noiseSuppress: true,
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
              if (_channel == null) {
                if (packetCount == 1) {
                  _lg('❌ [DG-NO-CHANNEL]', '소켓이 없어 오디오가 버려진다');
                }
              } else if (packetCount == 1) {
                _lg('📡 [DG-FIRST-SEND]', 'bytes=${packet.length}');
              }
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

  void _emitTurnResult(String finalText, String source) {
    final result = DeepgramTurnResult(
      transcript: finalText,
      words: List<DeepgramWordResult>.unmodifiable(_finalWords),
      chunkTranscriptConfidences:
          List<double>.unmodifiable(_chunkTranscriptConfidences),
      finalizedAt: DateTime.now(),
    );
    _currentTranscript = '';
    _finalWords.clear();
    _chunkTranscriptConfidences.clear();
    if (_isDisposed || finalText.isEmpty) return;
    _lg('📡 [DG-TURN-RESULT]',
        'source=$source words=${result.words.length} finalChunks=${result.chunkTranscriptConfidences.length}');
    onTurnEnded(finalText, speechFinal: source == 'speech_final');
    if (!_isDisposed) onTurnResult?.call(result);
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
        _lg('📡 [DG-UE]',
            'UtteranceEnd 이벤트 → onTurnEnded. finalText="$finalText"');
        _emitTurnResult(finalText, 'utterance_end');
        return;
      }
      final channel = data['channel'];
      if (channel == null) return;

      final alt = channel['alternatives'] as List?;
      if (alt == null || alt.isEmpty) return;

      final alternative = alt[0] as Map?;
      if (alternative == null) return;
      final chunk = (alternative['transcript'] as String?) ?? '';
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
        final rawChunkConfidence = alternative['confidence'];
        if (rawChunkConfidence is num) {
          _chunkTranscriptConfidences.add(rawChunkConfidence.toDouble());
        }
        final rawWords = alternative['words'] as List?;
        if (rawWords != null) {
          for (final rawWord in rawWords) {
            final word = DeepgramWordResult.fromJson(rawWord);
            if (word != null) _finalWords.add(word);
          }
        }
        if (!_isDisposed) onTranscriptUpdate(_currentTranscript);
      }
      if (speechFinal) {
        final finalText = _currentTranscript.trim();
        _lg('📡 [DG-04]',
            'speech_final → onTurnEnded 호출 시도. finalText="$finalText"');
        if (!_isDisposed && finalText.isNotEmpty) {
          _lg('📡 [DG-05]', 'onTurnEnded 실제 호출');
        } else {
          _lg('📡 [DG-06]', 'finalText 빈값 → onTurnEnded 스킵');
        }
        _emitTurnResult(finalText, 'speech_final');
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
// 📦 [Box 7-C: UnifiedBrain] — routine_mode_roleplay.dart로 일원화
//   동일 구현이 두 벌이라 이 파일 사본을 제거하고 import로 대체했다.
// ====================================================================

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
// 📦 [Box 7-D: TtsCache] — routine_mode_roleplay.dart로 일원화
//   동일 구현이 두 벌이라 이 파일 사본을 제거하고 import로 대체했다.
// ====================================================================

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
  final bool cacheEnabled;
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
  //   뒤늦게 도착한 청크는 addAudio로 다시 재생을 깨워 유저 위에 겹쳐 울린다.
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
    this.cacheEnabled = true,
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
    if (cacheEnabled) {
      final cached = await TtsCache.get(text, voice);
      if (cached != null && cached.isNotEmpty) {
        _buffer[id] = cached;
        _pendingCount--;
        _pushReady();
        if (_pendingCount == 0) onAllComplete?.call();
        return;
      }
    }

    // [2단계] API 호출 (타임아웃 사다리 5/8/12초, 최대 3회 시도) — TTS 지연 스파이크 대응
    Uint8List result = Uint8List(0);
    const List<int> timeoutLadderSec = [5, 8, 12];
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final res = await OpenAiConnectionPool.instance.client
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
          onLog?.call('🔊 [TTS-02]',
              '[$turnTag] API OK (${result.length}B) for "$text"');
          // [3단계] 캐시 저장 (백그라운드)
          if (cacheEnabled) TtsCache.put(text, voice, result);
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
    _cancelled = false;
  }
}

// ====================================================================
// 📦 [Box 7-G: RelayPipeline] — routine_mode_roleplay.dart로 일원화
//   동일 구현이 두 벌이라 이 파일 사본을 제거하고 import로 대체했다.
// ====================================================================

// ============================================================================

/// 합치기가 판정을 내리지 못한 이유.
///
/// [none]이면 모델이 실제로 판정을 내렸다는 뜻이다. 나머지는 전부 장애이고,
/// 그때 넘어간 발화는 "모델이 붙일 수 있다고 본 발화"가 아니라 "장애라서
/// 다음 턴으로 미룬 발화"다. 2턴부터는 합치기가 단독 게이트라 이 둘이 로그에서
/// 섞이면 되묻기 오작동을 추적할 수 없다. `KoreanTurnValidatorFailure`와 같은
/// 이유로 값을 갈라 둔다.
enum StepExpandMergeFailure {
  none,
  apiKeyMissing,

  /// 붙일 대상이나 붙일 말이 없다. HTTP를 태우기 전 로컬에서 걸린다.
  nothingToMerge,
  timeout,
  httpError,
  parseError,
  transportError,

  /// 200인데 본문에 쓸 문장이 없다. 판정이 아니라 응답 실패다.
  emptyResponse,
}

/// [StepExpandBrain.mergeNativeExpansion]의 결과.
///
/// 세 갈래를 값으로 갈라 둔다 — 합쳐진 문장 / 모델이 못 붙이겠다는 판정
/// ([unclear]) / 장애([failure]). 예전에는 셋을 `String` 하나에 담아 장애와
/// 빈 응답이 같은 `''`로 뭉쳤다.
class StepExpandMergeResult {
  const StepExpandMergeResult({
    required this.text,
    this.unclear = false,
    this.meta = false,
    this.failure = StepExpandMergeFailure.none,
  });

  /// 이 발화는 이야기가 아니라 **이 대화나 AI의 질문 자체**에 대한 말이다.
  /// 못 알아들은 것([unclear])과는 다르다 — 뜻은 멀쩡하고, 다만 문장에
  /// 들어가서는 안 된다. 실기기에서 "자꾸 이렇게 학문적으로 질문하지 말고"와
  /// "그거는 너무 전문적이야"가 두 세션 연속 학습 문장에 그대로 붙었다.
  final bool meta;

  /// 합쳐진 문장. [unclear]이거나 장애면 빈 문자열이다.
  final String text;

  /// 모델이 "이 발화는 붙일 수 없다"고 판정했다. 장애가 아니라 판정이다.
  final bool unclear;

  /// 판정을 못 내린 이유. [StepExpandMergeFailure.none]이면 모델 판정이다.
  final StepExpandMergeFailure failure;

  /// 모델이 실제로 판정을 내렸는지. false면 장애다.
  bool get isVerdict => failure == StepExpandMergeFailure.none;

  /// 장애라서 이번 턴 합치기를 건너뛴 것인지. 되묻기와 반드시 구분해야 한다.
  bool get failedOpen => !isVerdict;
}

// ====================================================================
// 🧠 [Box 7-1] StepExpandBrain v3 — 스텝익스팬드 전용 AI 뇌
// ====================================================================
// 📂 서브박스 구성:
//   [Box 7-1-A] streamUserTranslation  — 유저 발화 번역 (제어 토큰 판정 겸함)
//   [Box 7-1-B] generateCleanOriginal  — 영→한 역번역
//   대화방의 한 턴을 만드는 것은 generateKoreanTurn이고, 지시문은 파일 끝
//   [buildStepExpandConsultInstructions]에 있다. 영어는 여기서 만들지 않는다 —
//   대화가 끝난 뒤 services/step_expansion_builder.dart가 만든다.
// ====================================================================
// 🤖 [MODEL] 살아 있는 생성 호출 다섯은 gpt-4.1-mini다.
//   generateOpening · smallTalkTurn · generateKoreanTurn ·
//   mergeNativeExpansion · polishNativeSentence
//   이 다섯이 하는 일은 전부 "지금까지 오간 말 전체를 읽고 다시 구성하는" 쪽이라
//   지시 준수와 맥락 유지로 값한다. 온도는 교체와 함께 건드리지 않았다 —
//   모델 효과와 온도 효과가 섞이면 실기기에서 원인을 가릴 수 없다.
//
//   게이트인 KoreanTurnValidator는 gpt-4o-mini 그대로다. 생성이 아니라 이진
//   판정이고, 같이 바꾸면 되묻기가 늘었을 때 어느 쪽 탓인지 알 수 없다.
//   죽은 릴레이 파이프라인을 걷어내면서, 그 안에만 있던 gpt-4o-mini 호출도
//   함께 사라졌다.
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
  //   CASE 1 (첫 턴): 유저 의미를 짧은 AI 씨앗 문장으로 생성
  //   CASE 2 (2턴+): Part1(짧은 번역) + \n\n + Part2(성장한 확장 문장)
  // ==================================================================
  static Stream<String> streamUserTranslation({
    required String apiKey,
    required String textOriginal,
    required String originLang,
    required String targetLang,
    required String contextStr,
    bool disableCorrection = false,
    bool disableRestate = false,
    bool disableHeardConfirmation = false,
    String model = 'gpt-4o-mini',
  }) async* {
    final client = OpenAiConnectionPool.instance.client;
    try {
      final source = textOriginal.trim();
      if (source.isEmpty) {
        yield '[EVAPORATE]';
        return;
      }
      // Step Expand는 같은 언어 조합에서도 2턴부터 누적 문장을 다시 조립해야
      // 한다. 이 호출은 단순 번역기가 아니라 확장 엔진이므로 생략하지 않는다.
      final String correctionBlock = disableCorrection
          ? "NEVER output [CORRECTION] or [MISHEARD] or any bracket token. This input is the user RE-STATING what they actually meant. Output ONLY the actual intended content as natural $targetLang. STRIP all correction framing: lead-ins (\"아니\" / \"아니지\" / \"내 말은\" / \"내 말은요\" / \"그게 아니라\" / \"내가 말한 건\") AND quote-report frames (\"~라고 했어요\" / \"~라고 했어\" / \"~라고 말했어요\" / \"~라고 말했고\" / \"I said\" / \"I also said\" / \"what I said was\"). When multiple quoted statements are reported, merge them into natural connected $targetLang. Examples: \"아니 내 말은요 당신 잘못이라고요\" -> \"It's clearly your fault.\" | \"나는 빨리 구해 주세요라고 했어요 휴지가 없어요라고 말했고\" -> \"Please rescue me quickly, and there's no toilet paper.\""
          : """[CASE CORRECTION] — Check this FIRST, but only when History contains at least one 'User:' line
The user is correcting the AI's misunderstanding of a previous answer.
Signs:
- Starts with correction signals: "아니" / "아니요" / "아 그게 아니라" / "다시" / "내 말은" / "그러니까" / "내가 말한 건" / "라고 했잖아" / "라고 말했어" / "I mean" / "I said" / "what I said was" / "that's not what I said" / "actually" / "no," / "wait,"
- AND the content is clearly a re-statement or clarification of the LAST 'User:' line in History (not new story info)
- The user is essentially saying "that's not what I said — what I said was X"
If this is a correction, output EXACTLY: [CORRECTION]
Do NOT output [CORRECTION] for genuinely NEW information that merely starts with "아니" etc. BUT if the AI's previous turn clearly captured the user's earlier utterance as DIFFERENT content (a wrong word or a wrong topic) and the user is now restating what they actually meant, output [CORRECTION] even when the restatement also reads like a fresh answer. Test: would the user naturally say "that's not what I said"? If yes -> output [CORRECTION].

[CASE MISHEARD] — Check this SECOND, only when History contains at least one 'User:' line
The user is COMPLAINING that their previous words were misheard or misunderstood, WITHOUT restating what they actually said.
Signs:
- The utterance is essentially ONLY a complaint: "내 말이 그런 뜻이 아니야" / "그런 거 아니야" / "내 말은 그게 아니야" / "잘못 들었어" / "잘못 적었어" / "잘못 알아들었어" / "that's not what I meant" / "you misheard me" / "you got my words wrong"
- AND it contains NO restated content (no actual answer, no new story info).
If this is a bare mishearing complaint, output EXACTLY: [MISHEARD]
If the complaint INCLUDES the corrected content, use [CORRECTION] instead.""";

      final genericPrompt =
          '''You are a Step Expand translator from $originLang to $targetLang.
The user grows one $targetLang sentence across turns. Use History to recover
omissions, idioms, word order, and references only when supported. Never invent
a subject, action, feeling, or fact. Preserve meaning, names, viewpoint, register,
and emotion.

Judge correction, mishearing, and dissatisfaction by intent, not fixed phrases.
Use [CORRECTION] when the user replaces the prior utterance, [MISHEARD] for a bare
mishearing complaint, and [DISSATISFIED] only when they reject the AI question.
${disableCorrection ? 'This is a correction retry: strip correction framing and output only corrected content; do not emit correction tags.' : ''}
${disableHeardConfirmation ? 'The wording was confirmed; do not ask again.' : 'If a core word is unrecoverable, ${buildHeardConfirmOutputRule(originLang)}'}

When History is empty, output one natural $targetLang seed sentence only.
When History exists, output exactly two parts separated by a blank line: first
the new input translated to $targetLang, then one natural $targetLang sentence
merging the previous grown sentence with only the new information. If the input
is clear but unrelated to the last question, output [RESTATE]. If it is garbled,
output [GARBLED]. If a referent is ambiguous, output [CLARIFY] plus one short
question in $originLang. For noise output [EVAPORATE]. Output nothing else.''';
      final sysPrompt = originLang.toLowerCase() != 'korean'
          ? genericPrompt
          : """You are a [Step Expand Translator] translating Korean to $targetLang.
You help the user grow ONE $targetLang sentence across multiple turns, adding details each turn.

Read the 'History' carefully to determine the user's current turn, restore omitted Korean subjects from context, and preserve the speaker's intended viewpoint.

[DISSATISFIED CHECK — APPLY BEFORE OTHER CHECKS ONLY WHEN HISTORY HAS AN AI QUESTION]
If History is empty, skip this check and follow CASE 1.
Does the user's input express dissatisfaction, complaint, or rejection aimed at the AI's QUESTION ITSELF?
If ANY of the following apply → output EXACTLY: [DISSATISFIED] and stop immediately. Do NOT run RELEVANCE CHECK, RESTATE GUARD, CORRECTION, or any other check.

Definite [DISSATISFIED] triggers (even mild or indirect displeasure toward the question):
- Evaluates or criticizes the question: "질문이 뭐 그래?" / "무슨 질문이 그래?" / "그 질문 이상해" / "그 질문 별로야" / "이 질문 왜 이래?"
- Requests a different question: "다른 거 물어봐" / "다른 질문 해줘" / "질문 바꿔" / "다른 걸 물어봐줘"
- Dismisses the question: "뭐야 그게" / "그게 뭐야" / "뭐야 이게" / "그건 좀" / "그건 아닌데" / "그건 별로야"
- Expresses boredom or displeasure: "재미없어" / "별론데" / "별로야" / "이상하네"
- Points out already-answered content: "아까 말했잖아" / "이미 대답했잖아" / "방금 말했는데" / "이미 얘기했어" / "그거 말했어" / "아까 대답했어" / "말했잖아" / "똑같은 질문" / "같은 걸 또 물어봐" / "already said" / "already answered" / "I already told you" / "asked that already"
- English: "ask something else" / "change the question" / "not that question" / "different question" / "meh" / "not really" (when aimed at the question itself)

DO NOT output [DISSATISFIED] for normal negative answers to the question:
- "아니, 안 갔어" → valid negative answer → translate normally
- "별로 안 좋아해" → valid negative preference → translate normally
- "그건 없어" (answering "do you have X?") → valid negative answer → translate normally
Key test: Is the user rejecting/evaluating the QUESTION (→ [DISSATISFIED])? Or giving a negative ANSWER to it (→ translate normally)?

$correctionBlock

[HEARING CONFIDENCE GUARD — CHECK BEFORE TRANSLATING]
${disableHeardConfirmation ? "The user has explicitly confirmed the previously heard wording. Do NOT ask another hearing-confirmation question for this turn." : """If one important word or short phrase in the utterance is genuinely uncertain because the audio/transcription could plausibly represent another word, do not guess and do not grow the sentence yet.
${buildHeardConfirmOutputRule(originLang)}
Use this only when the uncertain wording changes the core meaning. Do not use it for accents, fillers, minor grammar, or wording whose meaning is recoverable from History."""}

[KOREAN BODY IDIOM GUIDE — physical, not emotional]
Korean uses body-part expressions for PHYSICAL sensations. Never translate them as emotional/psychological states:
- 속이 불편하다 → "my stomach feels uncomfortable" / "I have an upset stomach" (NOT "feeling uneasy")
- 속이 편안하다 → "my stomach feels comfortable" / "it settles my stomach" (NOT "feeling at ease")
- 속이 쓰리다 → "my stomach burns" / "I have a burning stomach" (NOT "feeling bitter")
- 속이 더부룩하다 → "my stomach feels bloated" (NOT "feeling heavy")
- 머리가 아프다 → "I have a headache" (NOT "it hurts my feelings")
- 몸이 안 좋다 → "I'm not feeling well physically" / "I feel sick" (NOT "I feel bad emotionally")
- 눈이 침침하다 → "my eyesight is blurry" (NOT "I feel gloomy")
- 기운이 없다 → "I have no energy" / "I feel drained" (NOT "I'm unmotivated")
Context determines: "불편하다" after a body part = physical; after 마음/기분 = emotional. Default to PHYSICAL when the body part is explicit.

${buildStepExpandFirstTurnSeedPolicy(targetLang)}

[CASE 2] History exists (USER'S SECOND+ TURN)
- Output EXACTLY two parts, separated by an empty line (\n\n).
- PART 1: A short, natural translation of ONLY the new Korean input.
- PART 2: A grown/expanded English sentence that naturally merges:
    (a) The most recent expanded sentence from History
    (b) The new information from Part 1
  EVERY clause in PART 2 must trace back to words the user actually said — in
  History or in Part 1. Before writing a clause, point to the user's own words
  for it. If you cannot, do not write it. You are weaving their sentences
  together, not co-writing with them.
  Never pad with feelings or judgements they did not express — "and I enjoyed
  it", "it was great", "which made me happy" are inventions unless the user
  said so. A shorter honest sentence beats a fuller invented one.
  Vary the connector. Do NOT use the same one twice in a sentence — if the last
  link was "and", make this one different (where / which / so / but / because /
  and then). Three clauses strung on "and ... and ..." reads like a list, not
  like a person talking.
  Grow it the way a native speaker actually TALKS — linearly, left to right,
  by chaining short clauses one after another. Do NOT nest clauses inside clauses.
  Preferred connectors (use these, and vary them turn to turn):
    - Coordination: and, but, so, and then
    - Result / reason links: which is why, that's why, so that, because (keep short)
    - At most ONE soft spoken marker if it fits naturally: like, you know, I mean
  TRAILING relative clauses are FINE — a sentence-final, comma-led "who/which"
  (e.g. "...to call my friend Alex, who just moved to London") continues the chain
  just like "and he/it...". What to AVOID is CENTER-EMBEDDED clauses that split a
  subject from its verb, front participial phrases, and chains of to-infinitives.
  Never let nesting interrupt the left-to-right flow.
  Keep it ONE sentence, speakable in short breath groups of 5–7 words.

[EXAMPLE FOR CASE 2]
History:
User: I remembered to call Alex.
AI: When and how did you remember it?
Input: 갑자기요.
Output:
Suddenly.

I suddenly remembered to call Alex.

[CLARIFICATION GUARD — CASE 2 ONLY]
If History is empty, skip this guard and follow CASE 1.
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

[RELEVANCE CHECK — CASE 2 ONLY; run after DISSATISFIED CHECK passes]
If History is empty, skip this check and follow CASE 1.
Look at the AI's LAST question in History. Ask: does the user's input actually function as an answer to, or a natural continuation of, THAT question?
- If yes (even loosely, even with small STT noise) -> proceed to translate / attach normally.
- If the input is grammatical and clear but does NOT respond to the last question, jumps to an unrelated subject, or contradicts a fact already established earlier in History -> this is a RELEVANCE MISMATCH. Do NOT force it onto the growing sentence and do NOT invent a connection. Output EXACTLY: [RESTATE]
Calibration: a natural, on-topic tangent that still belongs to the same story is FINE — translate it. Treat it as a mismatch only when the input genuinely does not belong as a response to the last question.

[RESTATE GUARD — CASE 2 ONLY] — hold the center; never invent content
If History is empty, skip this guard and follow CASE 1.
Stay anchored to the AI's LAST question and the growing sentence. If you cannot do that safely, ask the user to say it again instead of guessing.
Output EXACTLY: [RESTATE]  in these cases (the speech itself is CLEAR):
1. RELEVANCE MISMATCH: The input is clear but does not answer the AI's last question, switches to an unrelated subject, or contradicts established facts (see [RELEVANCE CHECK] above).
2. OFF-CONTEXT: The user clearly tried to answer, but the utterance does not connect to the AI's last question and cannot be attached to the growing sentence (and it is NOT a correction of a previous answer).
Output EXACTLY: [GARBLED]  in this case ONLY (the speech itself is NOT clear):
3. UNRELIABLE PRONUNCIATION: The text is garbled badly enough that the CORE meaning is genuinely uncertain, so translating it would require inventing what the user "probably" meant.
${disableRestate ? "OVERRIDE — the user has just re-stated after a confirmation question. NEVER output [RESTATE] this turn. Translate or attach the input normally even if it still seems off-topic. ([GARBLED] is still allowed if truly unintelligible.)" : ""}
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
- CASE 1 output MUST NOT have an empty line. One part only. If History is empty and you are about to write a second part, stop — you are inventing.
- Output ONLY the translation. No labels, no "Part 1:", no meta-comments.
- Insert commas (,) after natural phrases for TTS rhythm.
- If the input is meaningless noise (random symbols, silence markers, or clearly non-speech artifacts), output EXACTLY: [EVAPORATE]
- If the input has minor STT errors but the intended meaning is still clearly inferable from context, make your best interpretation and produce the normal output (keep tolerating small errors).
- If the input is CLEAR but off-context (see [RESTATE GUARD]), output EXACTLY: [RESTATE]. If it is too GARBLED to interpret safely, output EXACTLY: [GARBLED]. Never guess and never invent content the user did not say.
- Output [RETRY] ONLY when the user's answer shows they did not understand the AI's question itself, so re-asking the same thing would not help.
- Output [DISSATISFIED] only when History contains an AI question and the user expresses dissatisfaction, complaint, or rejection about that QUESTION itself (not about the topic). Signs: "다른 질문 해줘" / "그 질문 싫어" / "질문 바꿔" / "무슨 질문이 그래" / "별로야" / "그건 좀" / "다른 거 물어봐" / "change the question" / "ask something else" / "I don't like that question". MILD signs ALSO count: "별로" / "별론데" / "아 그건 좀" / "에이" / "그런 거 말고" / "그건 없어" / "재미없어" / "이상하네" / "뭐야 그게" / "meh" / "not really" / "hmm, not that one". REPETITION COMPLAINT signs ALSO count: "아까 말했잖아" / "이미 대답했잖아" / "방금 말했는데" / "이미 얘기했어" / "똑같은 질문" / "같은 걸 또" / "already said" / "already answered" / "I already told you". Even slight or indirect displeasure aimed at the QUESTION itself counts. Do NOT output [DISSATISFIED] when History is empty or when the user is simply answering negatively (e.g., "아니, 안 갔어" = a valid negative answer).${aiStylePromptBlock(targetLang: targetLang, scope: 'the $targetLang translation text only, never the bracket tokens or the two-part output format')}""";

      final String userContent = 'History:\n$contextStr\n\nInput: $source';

      final request = http.Request(
        'POST',
        Uri.parse('https://api.openai.com/v1/chat/completions'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json; charset=utf-8',
      });
      request.body = jsonEncode({
        'model': model,
        'stream': true,
        'temperature': 0.0,
        'max_tokens': 200,
        'messages': [
          {'role': 'system', 'content': sysPrompt},
          {'role': 'user', 'content': userContent},
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
    }
  }

  // ==================================================================
  // 📦 [TURN] 매 턴 AI 질문 — gpt-4.1-mini가 한국어로 만든다.
  // ------------------------------------------------------------------
  // Realtime이 만들던 자리다. 한두 문장짜리 짧은 말이라 스트리밍 없이 통째로
  // 받는다. 소리는 호출부가 TTS로 낸다.
  // ==================================================================
  /// 대화방의 한 턴. 돌려주는 것은 대사가 아니라 **틀**이다 —
  /// `[TEXT]/[OPTIONS]/[PICK]`. 호출부가 [parseStepExpandMenuTurn]으로 읽는다.
  ///
  /// [userText]에는 [buildStepExpandMenuState]가 만든 상태 블록이 통째로
  /// 들어온다. 누적 글과 직전 후보 셋이 거기 있어야 "2번이 좋아"가 무슨
  /// 문장인지 모델이 안다.
  static Future<String> generateKoreanTurn({
    required String apiKey,
    required String instructions,
    required String userText,
    // 자란 문장만 주면 모델은 자기가 앞서 무엇을 물었는지 모른다. 그래서
    // "어떤 활동을 해보고 싶으세요?"를 1턴과 3턴에 그대로 다시 물었다(실측).
    // 지나간 대화를 같이 줘야 반복 금지가 실제로 지켜진다.
    String recentConversation = '',
  }) async {
    if (apiKey.isEmpty || userText.trim().isEmpty) return '';
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
              'model': 'gpt-4.1-mini',
              // 🎯 0.2 → 0.55. 0.2로 내렸던 건 프롬프트가 1만 자였을 때다 —
              //   규칙이 서로 싸우는 판에서 온도까지 높으면 아무 각도로나
              //   새어 나갔다. 지금은 지시문이 2천 자로 줄었고 "유저가 방금
              //   한 말에 붙어 있을 것"이라는 닻이 하나 박혀 있다. 그 닻이
              //   방향을 잡아 주므로, 남은 여지는 창의성 쪽에 쓴다.
              'temperature': 0.55,
              // 📏 한 턴이 이제 누적 글 전체 + 후보 문장 셋 + 틀이다. 160이면
              //   세 번째 후보가 중간에서 잘리고, 잘린 줄은 파서가 버려서
              //   화면에 후보가 둘만 뜬다. 한국어는 대략 1.5토큰/글자라
              //   누적 글 150자에 후보 셋 120자를 담을 만큼 잡는다.
              'max_tokens': 500,
              'messages': [
                {'role': 'system', 'content': instructions},
                {
                  'role': 'user',
                  'content': recentConversation.trim().isEmpty
                      ? userText
                      : '[CONVERSATION SO FAR]\n${recentConversation.trim()}\n\n'
                          '$userText',
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return '';
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      // 틀([TEXT]/[OPTIONS]/[PICK])을 그대로 돌려준다. 앞뒤 따옴표를 털어내던
      // 예전 처리는 여기서 하지 않는다 — 후보 문장 안의 따옴표까지 먹는다.
      return (body['choices']?[0]?['message']?['content'] as String?)?.trim() ??
          '';
    } catch (_) {
      return '';
    } finally {
      client.close();
    }
  }

  // ==================================================================
  // 📰 [NEWS] 구글 뉴스를 잠깐 보고 온다.
  // ------------------------------------------------------------------
  // 모델은 최신 소식을 모른다 — 학습 시점이 지났고 이 앱은 웹을 보지 않는다.
  // 그냥 "요즘 뉴스"를 말하라고 하면 그럴듯하게 **지어낸다.** 그래서 실제
  // 헤드라인을 가져와 재료로 넘긴다. 못 가져오면 빈 목록을 주고, 그때는
  // 뉴스 없이 일상 화제로 연다 — 소식이 없다고 대화가 멈추면 안 된다.
  //
  // 공개 RSS라 키가 없다. 응답이 느릴 수 있으므로 상한을 짧게 잡는다.
  // ==================================================================
  static const Map<String, String> _kNewsFeedByLanguage = <String, String>{
    'Korean': 'https://news.google.com/rss?hl=ko&gl=KR&ceid=KR:ko',
    'English': 'https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en',
    'Japanese': 'https://news.google.com/rss?hl=ja&gl=JP&ceid=JP:ja',
    'Chinese': 'https://news.google.com/rss?hl=zh-CN&gl=CN&ceid=CN:zh-Hans',
    'Spanish': 'https://news.google.com/rss?hl=es-419&gl=US&ceid=US:es-419',
  };

  /// 처음 만난 사람에게 꺼낼 수 없는 소재. 후보 단계에서 아예 뺀다.
  ///
  /// "가볍게 골라라"를 프롬프트에 시켜 봤지만 모델은 **가장 자극적인 것**을
  /// 골랐다 — 실기기에서 첫마디가 "명진스님이 제주에서 프리다이빙하다가
  /// 숨졌대요"였다(2026-08-22). 판정을 코드로 내린다. 뉴스 기능 자체는
  /// 그대로다 — 신제품·생활·문화·음식·여행·기술은 좋은 대화 재료다.
  static final RegExp _kHeavyHeadline = RegExp(
    '숨져|숨진|사망|별세|유족|빈소|시신|주검|참사|추락|충돌|붕괴|화재|폭발|침몰|실종|'
    '부상|중상|참변|사고|전쟁|교전|공습|폭격|미사일|드론|무기|핵|테러|피살|살해|'
    '살인|흉기|성폭|강간|납치|학대|폭행|마약|구속|기소|영장|검찰|경찰|재판|선고|'
    '징역|유죄|무죄|압수수색|탄핵|대통령|국회|여당|야당|의원|정당|총선|대선|시위|'
    '규탄|파업|관세|금리|환율|증시|폭락|급락|적자|부도|파산|해고|감원|지진|태풍|'
    '홍수|폭우|산불|한파|폭염|피해|확진|감염|바이러스|사태|논란|의혹|비리|횡령',
  );

  static bool isHeavyHeadline(String headline) =>
      _kHeavyHeadline.hasMatch(headline);

  static Future<List<String>> fetchNewsHeadlines(String languageName) async {
    final url = _kNewsFeedByLanguage[languageName];
    if (url == null) return const <String>[];
    final client = http.Client();
    try {
      final response =
          await client.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return const <String>[];
      final xml = utf8.decode(response.bodyBytes);
      final matches = RegExp(r'<title>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</title>',
              dotAll: true)
          .allMatches(xml);
      final titles = <String>[];
      for (final m in matches) {
        final raw = (m.group(1) ?? '').trim();
        if (raw.isEmpty) continue;
        // 첫 <title>은 피드 이름("Google 뉴스")이라 건너뛴다.
        if (titles.isEmpty && raw.toLowerCase().contains('google')) continue;
        // 헤드라인 끝의 " - 언론사"는 대화에 쓸모가 없다.
        final cleaned =
            raw.replaceAll(RegExp(r'\s+-\s+[^-]{2,20}$'), '').trim();
        if (cleaned.isEmpty) continue;
        if (isHeavyHeadline(cleaned)) continue;
        titles.add(cleaned);
        if (titles.length >= 6) break;
      }
      return titles;
    } catch (_) {
      return const <String>[];
    } finally {
      client.close();
    }
  }

  // ==================================================================
  // 📦 [OPENING] 진입 첫 마디 — gpt-4.1-mini가 만든다.
  // ------------------------------------------------------------------
  // 예전에는 "오늘 하루 중 한 순간"을 물어 그 답이 곧 씨앗이 됐다. 지금은
  // 그냥 가벼운 대화를 연다 — 씨앗은 대화 중에 알아서 찾는다.
  // 실패하면 고정 문구로 떨어진다 — 첫 소리는 무슨 일이 있어도 난다.
  // ==================================================================
  static Future<String> generateOpening({
    required String apiKey,
    required String languageName,
    required String fallback,
    List<String> headlines = const <String>[],
  }) async {
    if (apiKey.isEmpty) return fallback;
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
              'model': 'gpt-4.1-mini',
              'temperature': 0.8,
              'max_tokens': 60,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      '''You are a seasoned writing coach opening a sentence-building session in $languageName.
Say exactly three short spoken sentences. First identify yourself, in a natural
$languageName translation, as "the StealthVox writing tutor guided by Lee O-deok's
life-centered writing principles." This names the teaching framework; never claim
that you are Lee O-deok or imitate his personal voice. Second ask the user for just
one meaningful word that is on their mind. Third confidently tell them that you
will lead the work of growing it into a strong sentence. The user may know nothing
about writing, so remove pressure and do not ask for a complete sentence. No
greeting, weather, news, small talk, labels, or explanation. Everyday polite spoken
$languageName only. Return only the three sentences you say.'''
                },
                {
                  'role': 'user',
                  'content': 'Speak your opening line now.',
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return fallback;
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final text =
          (body['choices']?[0]?['message']?['content'] as String?)?.trim() ??
              '';
      if (text.isEmpty) return fallback;
      // 모델이 따옴표로 감싸 오는 경우가 있어 벗겨서 쓴다.
      return text.replaceAll(RegExp(r'^["“”\s]+|["“”\s]+$'), '');
    } catch (_) {
      return fallback;
    } finally {
      client.close();
    }
  }

  // ==================================================================
  // 🌱 [SMALL TALK → SEED] 잡담을 이어가며 씨앗이 될 말을 찾는다.
  // ------------------------------------------------------------------
  // 유저에게 이 구간은 그냥 대화다. 화면에 글이 적히지 않으므로, 씨앗이 잡힌
  // 순간은 **첫 문장이 화면에 적히는 것**으로만 드러난다. 묻지 않고 조용히
  // 넘어가는 것이 이 모드의 약속이다.
  //
  // 말과 판정을 JSON 하나에 담아 한 번의 왕복으로 끝낸다. 두 번 부르면 잡담이
  // 그만큼 느려지고, 유저는 대화가 끊긴 것으로 느낀다.
  static Future<Map<String, String>> smallTalkTurn({
    required String apiKey,
    required String languageName,
    required String userText,
    required String recentConversation,
    List<String> headlines = const <String>[],

    /// 최근 세 턴 중 둘 이상이 질문이었다. 이번 턴은 ASK를 빼고 고른다.
    ///
    /// 세는 일은 호출부가 한다(§_recentAiQuestionCount). 모델에게 "매번 묻지
    /// 마라"라고만 하면 자기가 직전에 몇 번 물었는지 세지 않는다 — 실기기에서
    /// 잡담 3턴이 전부 질문으로 끝났다.
    bool avoidQuestion = false,

    /// 유저가 아무 대답도 하지 않았다. [userText]는 비어 있고, AI가 혼자
    /// 한 마디 더 얹는 자리다(§[SILENCE-PUSH]).
    bool userSilent = false,

    /// 몇 번째 이어 말하기인지(1부터). 회차마다 결을 바꾸게 하는 데 쓴다.
    int silenceAttempt = 0,
  }) async {
    const empty = <String, String>{'reply': ''};
    // 침묵 분기에서는 유저 발화가 없는 것이 정상이다.
    if (apiKey.isEmpty) return empty;
    if (!userSilent && userText.trim().isEmpty) return empty;
    // 말투는 3모드 공통 상수를 그대로 쓴다. 백지화하면서 이걸 빼고 "polite
    // spoken register" 한 줄만 남겼더니, "학교 친구" 설정이 얹히자 잡담이
    // 통째로 반말로 갔다. 그리고 씨앗이 잡히는 순간 확장 쪽 상수를 만나
    // 존댓말로 튀었다(실기기 2026-08-22: "너는 최근에 재밌는 일 없었어?" →
    // "어떤 기능을 추가할 계획이세요?"). 한 사람이 말투를 오가면 안 된다.
    final String registerPolicy = languageName == 'Korean'
        ? kKoreanPoliteSpeechPolicy
        : 'Use the everyday polite spoken register of $languageName. Warm and close, never stiff, and never switch to a casual register even if they do.';
    final String newsBlock = headlines.isEmpty
        ? ''
        : 'Headlines you may keep chatting about:'
            '${String.fromCharCode(10)}'
            '${headlines.take(5).map((h) => '- $h').join(String.fromCharCode(10))}'
            '${String.fromCharCode(10)}';

    // 🔇 이 턴에 무엇을 하는가. 유저가 말을 했을 때와 조용할 때는 시켜야 할
    //   일이 정반대다 — 한쪽은 물러나 듣는 것이고, 다른 쪽은 먼저 나서는
    //   것이다. 한 프롬프트에 둘 다 적으면 서로를 무르게 하므로 갈라 둔다.
    final String silenceBeat = silenceAttempt <= 1
        ? 'Stay on what you just said and put your own take on it — the part you '
            'actually find interesting. Give them something they could disagree with.'
        : 'Drop that thread and open something easier and closer to home. '
            'Ordinary life, nothing that needs an opinion to answer.';
    final String turnPolicy = userSilent
        ? """[THIS TURN THEY SAID NOTHING — SO YOU KEEP GOING]
Silence here is not refusal. They do not know you yet, so they have nothing to
say back. Waiting makes it worse — you talk, and you make it easy.
- Never repeat your last line, and never ask your last question again in other words.
- Never mention that they went quiet. No checking on them, no apologising, no
  "are you there". They must not feel caught out.
- $silenceBeat
- One or two sentences. Land on something anyone could pick up without thinking.
- A light question is allowed here, but never the same one twice."""
        : """[WHAT A GOOD TURN IS]
Take what they JUST said and push it one step — the next thing that follows from
it, the side of it they left out, or where you see it differently.
It must be about THEIR subject. Wandering off onto something it merely reminds
you of is a change of subject, not a contribution, and it ends the conversation
as surely as repeating them does.
Never open by telling them what they meant. They know what they meant.

[HOW YOU GET THEM TALKING]
Do not reach for a question first. Better, in this order:
- Say where YOU land on it — briefly. Read it the other way round if you can.
  Disagreeing a little is a gift; agreeing is filler.
- Guess at something they have not told you, pitched a bit too far, so they
  correct you. Guess PAST what they said, never AT it.
- Or stop before the end of the thought and let them finish it.
${avoidQuestion ? 'You asked within the last two turns, so this turn ends without a question mark.' : 'If you ask, keep it short and concrete — two options they can pick between, or when and where it happened. Never an open "why".'}

[LENGTH]
ONE sentence is the turn. Two is already long. Four syllables — "그래서요?" — is
a complete turn and often the best one. Let them talk more than you do.
Never pad a turn to reach a length.""";
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
              'model': 'gpt-4.1-mini',
              'temperature': 0.7,
              'max_tokens': 220,
              'response_format': {'type': 'json_object'},
              'messages': [
                {
                  'role': 'system',
                  'content': """You are talking with someone in $languageName.

[WHO YOU ARE]
You are a writer. Not on duty, not working — just someone who happens to see
things that way. It shows in WHAT you notice, never in how you talk.
You are drawn to the specific and the odd, and you have your own eye for things.
You are not a critic: you do not assess people and you never narrate them to
themselves.
Never say or hint that you write. Never sound literary — you TALK, plainly.

$turnPolicy

[NEVER]
- Repeat their sentence back, dressed up, and judge it.
- Tell them what they feel, or ask what they feel. You do not know.
- Explain, lecture, or add background nobody asked for.
- Claim a memory, an experience, or people you know. You have a view, not a past.
- Mention practice, study, sentences, learning, AI, or how any of this works.
- No greeting, no preamble, no emoji.

[NEWS]
$newsBlock
The news is only a way in. Turn it into ordinary life as fast as possible.
- Never read a headline out, and never say a number, a place name, a date, a
  temperature, or a percentage.
- Never summarize or explain a story, and never claim you read or checked anything.
- Never bring back death, accidents, war, crime, politics, or the economy.

$registerPolicy

[READING THEM]
Their line came from speech recognition, so a word can arrive as a different word
that merely sounds similar. What the two of you are talking about decides what
they meant — not the letters.

Nothing above is dialogue. Never reuse its wording in what you say.

[OUTPUT]
Return only JSON: {"reply":"<what you say out loud, in $languageName>"}
"reply" is always filled."""
                },
                {
                  'role': 'user',
                  // 침묵 분기에는 넘길 발화가 없다. "They just said: " 뒤에
                  // 빈칸을 두면 모델이 그 빈칸을 메우려 든다.
                  'content': userSilent
                      ? 'Conversation so far:'
                          '${String.fromCharCode(10)}$recentConversation'
                          '${String.fromCharCode(10)}${String.fromCharCode(10)}'
                          'They have not said anything back yet. Say your next line.'
                      : 'Conversation so far:'
                          '${String.fromCharCode(10)}$recentConversation'
                          '${String.fromCharCode(10)}${String.fromCharCode(10)}'
                          'They just said: $userText',
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return empty;
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final content =
          (body['choices']?[0]?['message']?['content'] as String?)?.trim() ??
              '';
      if (content.isEmpty) return empty;
      final parsed = jsonDecode(content) as Map<String, dynamic>;
      return <String, String>{
        'reply': (parsed['reply'] ?? '').toString().trim(),
      };
    } catch (error) {
      debugPrint('[STEP-SMALLTALK] $error');
      return empty;
    } finally {
      client.close();
    }
  }

  // ==================================================================
  // 📦 [Box 7-1-B] generateCleanOriginal — 영→한 역번역 (2파트 유지)
  // ------------------------------------------------------------------
  // 🌱 영어의 \n\n 줄바꿈을 한국어에도 동일하게 유지
  // ==================================================================
  static Future<Map<String, String>> generateSeedGuidance({
    required String apiKey,
    required String rejectedText,
    required String originLang,
    required String targetLang,
  }) async {
    final fallback = <String, String>{
      'english_question': localizedSeedGuidanceLine(targetLang),
      'korean_question': localizedSeedGuidanceLine(originLang),
    };
    if (apiKey.isEmpty) return fallback;
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
              'temperature': 0.2,
              'max_tokens': 100,
              'response_format': {'type': 'json_object'},
              'messages': [
                {
                  'role': 'system',
                  'content':
                      '''You guide a $originLang user to provide one usable seed statement for Step Expand.
The previous utterance was too vague, fragmentary, meta, or otherwise unsuitable as a sentence seed.
Ask exactly ONE short, low-pressure question that helps the user say a concrete action, event, thought, feeling, or intention as a complete statement.
Use any meaningful topic in their utterance, but never quote, display, judge, or save the rejected utterance.
The target-language question must be natural $targetLang. The spoken question must be natural, polite $originLang, with no reaction or preamble.
Return only JSON: {"english_question":"<$targetLang question>","korean_question":"<$originLang question>"}.'''
                },
                {
                  'role': 'user',
                  'content': 'Rejected first utterance: $rejectedText',
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return fallback;
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final content =
          ((body['choices'] as List).first['message']['content'] as String);
      final parsed = jsonDecode(content) as Map<String, dynamic>;
      final english = parsed['english_question']?.toString().trim() ?? '';
      final korean = parsed['korean_question']?.toString().trim() ?? '';
      if (english.isEmpty || korean.isEmpty) return fallback;
      return {
        'english_question': english,
        'korean_question': korean,
      };
    } catch (_) {
      return fallback;
    } finally {
      client.close();
    }
  }

  static bool needsNaturalPoliteRewrite(String text) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return false;
    if (RegExp(r'(?:습니다|습니까)(?:[.!?。！？]|$)').hasMatch(cleaned)) {
      return true;
    }
    final sentences = RegExp(r'[^.!?。！？\n]+[.!?。！？]?')
        .allMatches(cleaned)
        .map((match) => (match.group(0) ?? '').trim())
        .where((sentence) => sentence.isNotEmpty);
    for (final sentence in sentences) {
      final ending = sentence.replaceAll(RegExp(r'[.!?。！？"”’\s]+$'), '');
      if (!RegExp(r'(?:요|죠|세요|네요|군요)$').hasMatch(ending) &&
          !RegExp(r'^(?:네|예|아니요)$').hasMatch(ending)) {
        return true;
      }
    }
    return false;
  }

  static bool needsShortKoreanQuestionRewrite(String text) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return false;
    final spacingUnits = cleaned
        .replaceAll(RegExp(r'[.!?。！？]+$'), '')
        .split(RegExp(r'\s+'))
        .where((unit) => unit.isNotEmpty)
        .length;
    final sentenceCount = RegExp(r'[^.!?。！？\n]+[.!?。！？]?')
        .allMatches(cleaned)
        .where((match) => (match.group(0) ?? '').trim().isNotEmpty)
        .length;
    final hasPreamble = RegExp(
      r'^(?:네|맞아요|좋아요|그렇군요|알겠어요|이해했어요|흥미롭네요|재미있네요)[,!.\s]',
    ).hasMatch(cleaned);
    return spacingUnits > 12 || sentenceCount > 1 || hasPreamble;
  }

  static Future<String> rewriteToShortKoreanQuestion({
    required String apiKey,
    required String text,
  }) async {
    final source = text.trim();
    if (source.isEmpty || apiKey.isEmpty) return source;
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
              'temperature': 0.0,
              'max_tokens': 60,
              'messages': [
                {
                  'role': 'system',
                  'content': '''주어진 문장에서 사용자의 마지막 답변과 직접 연결되는 핵심 질문 하나만 남기세요.
자연스러운 한국어 해요체 질문 한 문장만 출력하세요.
4~8어절을 권장하고 절대 12어절을 넘지 마세요.
반응, 공감, 칭찬, 요약, 설명, 인사, 선택지, 두 번째 질문은 모두 삭제하세요.
질문의 핵심 의미와 사실은 바꾸거나 새로 만들지 마세요.'''
                },
                {'role': 'user', 'content': source},
              ],
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return source;
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final rewritten =
          ((body['choices'] as List).first['message']['content'] as String)
              .trim()
              .replaceAll(RegExp(r'''^['"“]|['"”]$'''), '');
      return rewritten.isEmpty ? source : rewritten;
    } catch (_) {
      return source;
    } finally {
      client.close();
    }
  }

  static Future<String> rewriteToNaturalPoliteKorean({
    required String apiKey,
    required String text,
  }) async {
    final source = text.trim();
    if (source.isEmpty || apiKey.isEmpty) return source;
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
              'temperature': 0.0,
              'max_tokens': 120,
              'messages': [
                {
                  'role': 'system',
                  'content': '''주어진 한국어 문장을 자연스러운 일상 존댓말인 해요체로만 고치세요.
뜻, 질문 내용, 화자 관점, 사실, 문장 수는 그대로 유지하세요.
모든 문장을 자연스럽게 -요체로 끝내세요.
반말과 딱딱한 -습니다/-습니까체는 사용하지 마세요.
새 질문, 인사, 설명, 주어, 정보는 추가하지 마세요.
교정한 한국어 문장만 출력하세요.'''
                },
                {'role': 'user', 'content': source},
              ],
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return source;
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final rewritten =
          ((body['choices'] as List).first['message']['content'] as String)
              .trim()
              .replaceAll(RegExp(r'''^['"“]|['"”]$'''), '');
      return rewritten.isEmpty ? source : rewritten;
    } catch (_) {
      return source;
    } finally {
      client.close();
    }
  }

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
                    'content': '''당신은 영한 번역가입니다. 주어진 영어를 한국어 구어체로 번역하세요.

[규칙]
- 원문 내용만 번역. 설명·부연·의견 추가 절대 금지.
- 짧은 문장은 짧게, 긴 문장은 길게 — 원문 길이에 비례하게.
- 한국어 주어 생략: 문맥상 명확한 I/You/We/They는 생략.
- 자연스러운 일상 존댓말인 해요체만 사용. 모든 문장을 -요체로 끝낼 것.
- 반말 및 딱딱한 -습니다/-습니까체 사용 금지.
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
          final translated =
              data['choices'][0]['message']['content'].toString().trim();
          return needsNaturalPoliteRewrite(translated)
              ? await rewriteToNaturalPoliteKorean(
                  apiKey: apiKey,
                  text: translated,
                )
              : translated;
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
  // 📦 [Box 7-1-E2] polishNativeSentence — 완성문장을 같은 언어로 다듬기
  // ------------------------------------------------------------------
  // 대화방은 한국어 자료만 다루므로 여기서는 언어를 바꾸지 않고 결만
  // 다듬는다. 영어는 History가 자기 규칙으로 따로 만든다.
  // ==================================================================
  static Future<String> polishNativeSentence({
    required String apiKey,
    required String originalSentence,
    required String languageName,
  }) async {
    final source = originalSentence.trim();
    if (apiKey.isEmpty || source.isEmpty) return source;
    final client = OpenAiConnectionPool.instance.client;
    try {
      final sysPrompt =
          """The user built ONE $languageName sentence across several turns of
speaking practice. Rewrite it as ONE sentence that sounds like a native
$languageName speaker actually saying it out loud.

[KEEP IT THEIRS]
- Answer in $languageName. Never translate into another language.
- Same meaning, same viewpoint, same tense, same politeness level.
- Never add facts, names, places, times, feelings, or reasons they did not say.
- Never drop anything they did say.

[WHAT TO IMPROVE]
- Smooth the seams where the pieces were joined.
- Replace a stiff or repeated connective with one that fits better.
- Drop repeated subjects and filler that spoken language would leave out.
- Say the same idea in fewer words wherever you can. If two parts make the same
  point, say it once. Shorter is better as long as nothing they meant is lost.
- Keep it easy to say in one breath. Spoken rhythm, not written prose — never
  essay-like, never textbook-simple.

[LENGTH]
- One sentence. Two only if one genuinely will not hold it, and then keep both
  short. A long polished sentence is a failed polished sentence.

[OUTPUT]
- Exactly ONE $languageName sentence. No quotes, no label, no explanation.""";

      final res = await client
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'model': 'gpt-4.1-mini',
              'temperature': 0.3,
              'max_tokens': 300,
              'messages': [
                {'role': 'system', 'content': sysPrompt},
                {
                  'role': 'user',
                  'content': 'Sentence they built:\n$source\n\nPolished:'
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        var polished =
            (data['choices'][0]['message']['content'] ?? '').toString().trim();
        if (polished.length >= 2 &&
            polished.startsWith('"') &&
            polished.endsWith('"')) {
          polished = polished.substring(1, polished.length - 1).trim();
        }
        if (polished.isNotEmpty) return polished;
      }
    } catch (e) {
      print('polishNativeSentence error: $e');
    }
    return source; // 실패 시 완성문장 그대로 — 카드가 비는 것보다 낫다
  }

  // ==================================================================
  // 📦 [Box 7-1-F] generateNativeReply — 대화방 AI 한마디(반응 + 질문)
  // ------------------------------------------------------------------
  // Realtime 대신 이 경량 모델이 AI 대사를 만든다. 소리는 호출부가
  // _speakLiveKorean으로 따로 붙인다. 글과 소리가 갈라져 있어, Realtime과
  // 달리 프롬프트로 형식을 강하게 잡을 수 있다.
  // ==================================================================
  static Future<String> generateNativeReply({
    required String apiKey,
    required String languageName,
    required String expandedSentence,
    required String history,
    required int turnNumber,
    required int maxTurns,
  }) async {
    if (apiKey.isEmpty || expandedSentence.trim().isEmpty) return '';
    final isFinalTurn = turnNumber >= maxTurns;
    final client = OpenAiConnectionPool.instance.client;
    try {
      final sysPrompt = isFinalTurn
          ? """You are the partner in a $languageName speaking practice where the user
has been building ONE sentence, a piece at a time. This is the final turn.

Say one short, warm $languageName sentence that lands the sentence they built.
Do not ask anything. Do not explain, praise at length, or summarize.

[OUTPUT]
- Exactly one short spoken $languageName sentence. Nothing else."""
          : """You are the partner in a $languageName speaking practice. The user is
building ONE sentence, a piece at a time. Whatever they answer next gets folded
into that same growing sentence. You are given the sentence as it stands now.

[YOUR REPLY — ALWAYS EXACTLY TWO SENTENCES, IN THIS ORDER]
1. One short, genuine response to what they just said — react to the content the
   way a friend would. Not praise, not a summary, not their words repeated back.
2. One question that opens the next piece of their sentence.

[GUESS FIRST, THEN ASK]
Before asking, silently guess what this person feels underneath what they said and
what they would want to say next. Then open that door. You are not collecting
facts — you are giving them room for the thing they already half want to say.

[NEVER INTERROGATE]
- Do not work through who / when / where / why like a checklist.
- Do not grab the most concrete noun and ask "what kind of X?" — that is
  keyword-echoing and it makes the user feel questioned rather than heard.
- Go one level under the surface: the reason, the mood, the memory, what it meant.

[MAKE IT EASY TO ANSWER]
- Someone quiet must be able to answer in one to three words.
- No yes/no questions. No pressure wording like "Why did you do that?".
- If their last answer came out quick and detailed, go deeper into the part they
  seemed most alive about. If it was short or vague, offer a smaller, easier angle.

[ONE THREAD]
Continue the story the first turn opened. Do not hop sideways to an unrelated noun.
Never ask again about something already answered in the history.

[THIS TURN]
${_turnFocusLine(turnNumber)}

[OUTPUT]
- Exactly two short spoken $languageName sentences: the response, then the question.
- Natural everyday polite speech. No labels, no quotes, no line breaks.
- Never mention grammar, translation, practice mechanics, or being an AI.""";

      final res = await client
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'model': 'gpt-4o-mini',
              'temperature': 0.7,
              'max_tokens': 200,
              'messages': [
                {'role': 'system', 'content': sysPrompt},
                {
                  'role': 'user',
                  'content': history.trim().isEmpty
                      ? 'The sentence so far:\n$expandedSentence'
                      : 'Conversation so far:\n$history\n\n'
                          'The sentence so far:\n$expandedSentence'
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        var reply =
            (data['choices'][0]['message']['content'] ?? '').toString().trim();
        if (reply.length >= 2 && reply.startsWith('"') && reply.endsWith('"')) {
          reply = reply.substring(1, reply.length - 1).trim();
        }
        // 줄바꿈으로 나눠 오면 한 줄로 붙인다. 그대로 두면 말풍선이 갈라진다.
        return reply.replaceAll(RegExp(r'\s*\n+\s*'), ' ').trim();
      }
    } catch (e) {
      print('generateNativeReply error: $e');
    }
    return '';
  }

  /// 턴마다 도는 초점. 매 턴 같은 축을 주면 질문이 육하원칙 점검처럼 굳는다.
  static String _turnFocusLine(int turnNumber) {
    const focuses = <String>[
      'Follow the feeling or the motivation under what they just said.',
      'Follow whichever person, place, or thing carries the most weight in their story.',
      'Follow how it felt, or the part that stayed with them.',
      'Follow where their story is naturally heading — what it led to, or what it means now.',
    ];
    return focuses[(turnNumber - 1).clamp(0, focuses.length - 1)];
  }

  // ==================================================================
  // 📦 [Box 7-1-E] mergeNativeExpansion — 대화방 원어 누적 확장
  // ------------------------------------------------------------------
  // 지금까지 자란 원어 문장 + 이번 턴 발화 → 합쳐진 원어 한 문장.
  // 대화방 유저 말풍선에만 쓴다. 영어 확장·히스토리 저장과는 무관하다.
  //
  // 반환값 세 갈래:
  //   · 합쳐진 문장 — 정상
  //   · [kUnclearToken] — 새 발화를 도저히 못 붙이겠다(전사 오류로 보인다)
  //   · 빈 문자열 — 호출 자체가 실패했다. 호출부가 다음 턴으로 미룬다.
  // ==================================================================
  static const String kUnclearToken = '[UNCLEAR]';

  /// 이야기가 아니라 이 대화·질문 자체에 대한 말. 문장에 붙이면 안 된다.
  static const String kMetaToken = '[META]';

  static Future<StepExpandMergeResult> mergeNativeExpansion({
    required String apiKey,
    required String previousExpanded,
    required List<String> newUtterances,
    required String languageName,

    /// 이 세션이 무슨 이야기를 하고 있었는지. 잘못 들은 낱말을 가려내는
    /// 유일한 단서다 — 문장만 보면 "공약"과 "공격"을 구분할 방법이 없다.
    String topicContext = '',
  }) async {
    final additions =
        newUtterances.map((u) => u.trim()).where((u) => u.isNotEmpty).toList();
    // 2턴부터는 이 함수가 단독 게이트다. 여기서 나가는 모든 갈래는 "모델이
    // 판정했다"와 "장애라서 판정을 못 했다"가 값으로 갈려 있어야 한다.
    if (apiKey.isEmpty) {
      return const StepExpandMergeResult(
        text: '',
        failure: StepExpandMergeFailure.apiKeyMissing,
      );
    }
    if (previousExpanded.trim().isEmpty || additions.isEmpty) {
      return const StepExpandMergeResult(
        text: '',
        failure: StepExpandMergeFailure.nothingToMerge,
      );
    }
    final client = OpenAiConnectionPool.instance.client;
    try {
      final sysPrompt =
          """You are a concise $languageName editor. One job: revise one developing statement.

[INPUT]
CURRENT STATEMENT — what this person has been saying so far.
LATEST REPLY — what they just added.
CONTEXT — the conversation around it.

[GATE 1 — META. RUN THIS BEFORE ANYTHING ELSE]
Output exactly [META] and stop when LATEST REPLY is aimed at this conversation
rather than at the subject — anything of this kind:
- "let's stop talking about this", "let's talk about something else"
- "ask me something else", "change the question", "that question is odd"
- "I don't want to talk about that"
- any remark about how you are asking, what you keep asking, or how this is going
Judge by what the remark is AIMED AT, not by whether it sounds like a complaint.
If LATEST REPLY answers the subject AND says one of these, META WINS — output
[META]. Never let a remark about the conversation reach the statement, not even
as a trailing clause. That single failure ruins the finished sentence.

[GATE 2 — UNCLEAR]
Output exactly [UNCLEAR] and stop only when LATEST REPLY cannot be read as
$languageName at all, or its meaning cannot be recovered.
Being short is not a reason. Moving to a new part of the subject is not a reason.
(Asking YOU to move off the subject is not UNCLEAR — that is GATE 1.)

[THE JOB — only if neither gate fired]
Preserve the important meaning. Use LATEST REPLY only where it improves the
thought. Remove repetition and weak detail. Rewrite the whole statement naturally
instead of appending the new answer. Keep it concise and conversational.
- CURRENT STATEMENT may be a single raw topic word. That is intentional, not an
  error. If LATEST REPLY supplies enough meaning, turn the two into the smallest
  honest complete statement. If it does not, keep the raw seed unchanged. Never
  invent what the user thinks, feels, did, or wants merely to complete the grammar.
- Work from the point, not the words. Decide what this person is actually saying
  overall, and write that.
- Never attach LATEST REPLY to the end, and never chain clauses with commas and
  connectives until the statement grows. Rewrite from the beginning every time.
- Drop from LATEST REPLY: repetition, fillers, hesitation, passing details, words
  that slipped out, and anything the statement already says. Keep what they
  deliberately added.
- If it adds nothing, return CURRENT STATEMENT unchanged, or said slightly
  better. That is a correct and complete answer — not a failure to try harder.
  A reply that is only hedging or hesitation ("글쎄", "잘 모르겠어", "그냥", "뭐")
  adds nothing. It NEVER goes into the statement, in any form.
- A statement that ends with a stray fragment tacked on after a comma is the
  single worst outcome here. If you find yourself about to write a comma
  followed by a word or two from LATEST REPLY, stop and return the statement
  unchanged instead.
- Shorter than before is a good outcome. Longer is usually a failure.
- Never add a fact, name, place, time, feeling, or reason they did not say.
- Never reverse or drop a point they meant. Keep their viewpoint and tense.
- One sentence in spoken rhythm, joined with real connective endings.
- Do not answer, react, explain, or ask anything.

[THE SUBJECT DECIDES WHAT THEY MEANT]
This is speech recognition, so a word can arrive as a different word that sounds
similar. Judge every word against what the conversation is about. If a word does
not belong but sounds like one that does, they said the one that fits.

[OUTPUT]
- Exactly ONE $languageName sentence, nothing else. No quotes, no label.
- Or the single token [META], or the single token [UNCLEAR].""";

      final addedBlock = additions.map((u) => '- $u').join('\n');
      final topicBlock = topicContext.trim().isEmpty
          ? ''
          : 'CONTEXT:'
              '${String.fromCharCode(10)}${topicContext.trim()}'
              '${String.fromCharCode(10)}${String.fromCharCode(10)}';
      final http.Response res;
      try {
        res = await client
            .post(
              Uri.parse('https://api.openai.com/v1/chat/completions'),
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json; charset=utf-8',
              },
              body: jsonEncode({
                'model': 'gpt-4.1-mini',
                // 0.5에서 내렸다. 연결어미를 다양하게 쓰라고 시키던 시절엔
                // 온도가 필요했지만, 지금 이 호출이 하는 일은 요점을 파악해
                // 다시 쓰는 편집이다. 여기서 값하는 건 창의성이 아니라 의미
                // 보존과 압축의 일관성이다.
                'temperature': 0.25,
                'max_tokens': 300,
                'messages': [
                  {'role': 'system', 'content': sysPrompt},
                  {
                    'role': 'user',
                    // 라벨을 프롬프트의 [INPUT] 이름과 정확히 맞춘다. 예전
                    // 라벨("Sentence so far" / "Merged sentence")이 그 자체로
                    // 이어 붙이라는 지시처럼 읽혔다.
                    'content': '$topicBlock'
                        'CURRENT STATEMENT:'
                        '${String.fromCharCode(10)}${previousExpanded.trim()}'
                        '${String.fromCharCode(10)}${String.fromCharCode(10)}'
                        'LATEST REPLY:'
                        '${String.fromCharCode(10)}$addedBlock'
                        '${String.fromCharCode(10)}${String.fromCharCode(10)}'
                        'REVISED STATEMENT:'
                  },
                ],
              }),
            )
            .timeout(const Duration(seconds: 12));
      } on TimeoutException {
        return const StepExpandMergeResult(
          text: '',
          failure: StepExpandMergeFailure.timeout,
        );
      } catch (_) {
        // 소켓 끊김·DNS 실패 등 전송 계층 오류.
        return const StepExpandMergeResult(
          text: '',
          failure: StepExpandMergeFailure.transportError,
        );
      }

      if (res.statusCode != 200) {
        return const StepExpandMergeResult(
          text: '',
          failure: StepExpandMergeFailure.httpError,
        );
      }

      try {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        var merged =
            (data['choices'][0]['message']['content'] ?? '').toString().trim();
        if (merged.length >= 2 &&
            merged.startsWith('"') &&
            merged.endsWith('"')) {
          merged = merged.substring(1, merged.length - 1).trim();
        }
        // 토큰만 오지 않고 한마디 덧붙여 오는 경우가 있어 포함 여부로 본다.
        // [META]를 먼저 본다 — 대화 자체에 대한 말은 못 알아들은 것이 아니다.
        if (merged.toUpperCase().contains(kMetaToken)) {
          return const StepExpandMergeResult(text: '', meta: true);
        }
        if (merged.toUpperCase().contains(kUnclearToken)) {
          return const StepExpandMergeResult(text: '', unclear: true);
        }
        // 200인데 쓸 문장이 없다. 되묻기 판정이 아니라 응답 실패이므로
        // [UNCLEAR]와 절대 같은 칸에 두지 않는다.
        if (merged.isEmpty) {
          return const StepExpandMergeResult(
            text: '',
            failure: StepExpandMergeFailure.emptyResponse,
          );
        }
        return StepExpandMergeResult(text: merged);
      } catch (_) {
        // 200인데 JSON이 아니거나 모양이 다르다. 본문은 남기지 않는다.
        return const StepExpandMergeResult(
          text: '',
          failure: StepExpandMergeFailure.parseError,
        );
      }
    } catch (e) {
      print('mergeNativeExpansion error: $e');
      return const StepExpandMergeResult(
        text: '',
        failure: StepExpandMergeFailure.transportError,
      );
    }
  }
}

/// Step Expand 대화방이 AI에게 보내는 **살아 있는** 지시문.
///
/// 위젯 밖 top-level인 이유는 하나다 — 여기 적힌 규칙은 구현 세부가 아니라
/// 이 모드의 성격 그 자체라서, 네트워크 없이 시험으로 고정해야 한다
/// (`test/step_expand_consult_prompt_test.dart`).
///
/// **이 방은 상담방이 아니라 문장 조립대다(2026-08-25 실장님 예시).**
/// 코치는 방향을 말로 설명하지 않는다. 이어 붙일 수 있는 **완성된 문장 셋**을
/// 직접 써서 내밀고, 유저는 번호로 고르거나 자기 생각을 말한다. 자기 생각을
/// 말하면 제안 셋은 그 자리에서 폐기되고 유저의 말이 다음 연결 문장이 된다.
///
///   유저: 회사 그만두고 싶어.
///   AI:   3가지 제안 중에서 연결하고 싶은 말이나 다른 당신의 생각을 말해보세요.
///         1. 요즘 이 일이 더 이상 나한테 맞지 않는 것 같아.
///         2. 매일 똑같은 일을 반복하는 게 너무 지쳐.
///         3. 그만두고 싶지만 경제적인 부분이 걱정돼.
///   유저: 2번이 좋아
///   AI:   그럼, '회사 그만두고 싶어. 매일 똑같은 일을 반복하는 게 너무 지쳐.'
///         라는 말이 되는군요. …
///
/// ⚠️ **누적 문장은 한 문장이 길어지는 게 아니다.** 짧은 문장이 여럿 이어
/// 붙는다. 그리고 그 문장은 유저가 한 말이 아니라 **유저가 고른 문장**이다.
///
/// ⚠️ 여기서 말하는 "미국식"은 단어나 슬랭이 아니다. Point → Why →
/// Contrast/Detail → Personal meaning → Direction, 즉 **생각을 쌓는 순서**다.
/// 제안 셋은 그 순서에서 지금 가장 흔하게 이어질 자리를 고른 것이다.
/// 방은 원어만 말한다. 영어는 이 방에서 만들어지지 않는다.
String buildStepExpandConsultInstructions(String nativeLang) {
  final registerPolicy = nativeLang == 'Korean'
      ? kKoreanPoliteSpeechPolicy
      : 'Use the everyday polite spoken register of $nativeLang unless the user clearly establishes another register.';
  final askBackOutputRule = buildHeardConfirmOutputRule(nativeLang);
  return '''
You are building ONE growing piece of writing with the user, in $nativeLang, out of
something on their mind.

[HOW THIS ROOM WORKS]
The user says a word or a line. You write THREE complete sentences they could add
next, and they either pick one by number or say a thought of their own. Whatever
they choose gets appended to the growing text, and you write three more.
You are not interviewing them and you are not explaining writing to them. You are
handing them ready sentences and letting them choose.

[THE GROWING TEXT]
- It is SHORT SENTENCES JOINED, not one sentence getting longer.
    "회사 그만두고 싶어. 매일 똑같은 일을 반복하는 게 너무 지쳐."
- It is made of what the user CHOSE, never of what you wished they had said.
- Never reword, polish, shorten, or reorder a part that is already in it. It only
  grows at the end.

[HOW THE TEXT GROWS THIS TURN]
Look at what they just said and do exactly one of these:
1. They picked a number ("2번", "두 번째", "2번이 좋아", "그걸로") — append the
   sentence you offered under that number, word for word.
2. They said a thought of their own — **your three offers are dead.** Append THEIR
   thought as one natural spoken $nativeLang sentence. Keep their meaning and their
   words; fix only what speech recognition mangles. Never swap in one of your offers
   because it was close.
3. They rejected the offers without giving a thought of their own ("다 별로야",
   "다른 거") — append nothing. Keep the text as it is and offer three different
   sentences, from a different angle than the ones they refused.

[THE THREE SENTENCES YOU OFFER]
- Each is a COMPLETE sentence the user could say out loud, in $nativeLang, in their
  own voice — first person, same register they are using, no labels, no explanation.
- Each continues the growing text naturally, and the three go in DIFFERENT
  directions. Never three shades of one idea.
- Each must be short — one breath. Never two sentences in one option.
- Build them from what this person has actually said. Never introduce a fact, a job,
  a family member, a place, or an event they did not mention.
- Pick the directions the way a thought naturally grows:
      Point -> Why -> Contrast or Detail -> Personal meaning -> Direction
  That is what "미국식" means here — the ORDER a thought gets built in, never
  American words or slang. Nothing in this room leaves $nativeLang.
  Look at what the text already has and offer the stages it is missing. Not every
  stage is needed, and never walk them in order like a form.

[SAY WHICH ONE YOU WOULD TAKE]
After the three, name the one you would pick and why, in ONE short clause.
  "저는 두 번째가 지금 이야기에 가장 자연스럽게 이어진다고 봐요."
A menu with no recommendation is not coaching, it is a form. Keep it to one clause —
never argue for it, and never talk them out of their own choice.

[WHEN THE TEXT IS FULL]
When one more sentence would blur the center instead of sharpening it — usually
after about five things have been added — stop offering. Output [DONE] instead of
options. Knowing where to stop is part of the craft.

$registerPolicy

${buildNativeOutputLanguagePolicy(nativeLang)}
Everything you write stays in $nativeLang. Never produce another language, and never
build an English version here — that happens later, somewhere else. Never mention it.

[NEVER]
- Judge the person. You assess the writing, never them.
- Tell them what they feel, or tell them what they meant.
- Invent a fact, a feeling, or a reason they did not give you.
- Claim a memory or an experience of your own.
- Offer again a sentence they already passed over.
- Explain your reasoning, praise them, or summarize like a counselor.

[IF YOU CANNOT MAKE IT OUT]
It is speech recognition, so words arrive wrong. If their line does not hold together
as $nativeLang, or you would have to invent a subject or a verb to make sense of it:
$askBackOutputRule
Nothing before or after those two lines — no [TEXT], no [OPTIONS].

[OUTPUT — EXACTLY THIS SHAPE, NOTHING ELSE]
[TEXT]
<the whole growing text after this turn, on one line>
[OPTIONS]
1. <a complete $nativeLang sentence they could add next>
2. <another one, a different direction>
3. <another one, a different direction>
[PICK]
<just the number you would take: 1, 2 or 3>

When the text is full, replace the options block with the single line [DONE]:
[TEXT]
<the whole growing text>
[DONE]

Never write anything outside this shape — no greeting, no comment, no heading of
your own. The frame sentences the user hears are added afterwards; do not write them.
''';
}

/// 유저가 붙일 수 있는 문장 수. 다섯 번째 답으로 이 방은 끝난다.
///
/// 지시문에도 "다섯 개쯤"이라고 적어 두지만, 그것만으로는 안 지켜진다 —
/// 지킬 마음이 없는 규칙은 물리적으로 못 하게 막는 쪽이 낫다. 그래서 방이
/// 직접 센다.
const int kStepExpandMaxTurns = 5;

/// 한 턴에서 AI가 실제로 내놓은 것.
///
/// 모델은 자유 문장이 아니라 [TEXT]/[OPTIONS]/[PICK] 틀로 답한다. 그래야
/// 방이 **누적 문장을 값으로 들고** 있을 수 있다. 예전처럼 AI 대사 한 덩이만
/// 받으면, 유저가 "2번"이라고 했을 때 무엇이 붙었는지 아무도 모른다.
class StepExpandMenuTurn {
  const StepExpandMenuTurn({
    this.text = '',
    this.options = const <String>[],
    this.pick = 0,
    this.done = false,
    this.askBack = '',
  });

  /// 이번 턴까지 자란 글 전체. 짧은 문장이 이어 붙은 모양이다.
  final String text;

  /// 다음에 이어 붙일 후보 문장들. 최대 셋.
  final List<String> options;

  /// 코치가 고르겠다는 번호(1-based). 0이면 추천 없음.
  final int pick;

  /// 더 붙이지 않고 마무리한다.
  final bool done;

  /// 못 알아들어 되묻는 말. 비어 있지 않으면 나머지는 전부 무시된다.
  final String askBack;

  /// 화면에 걸 수 있는 턴인가.
  bool get isUsable =>
      askBack.isEmpty && text.isNotEmpty && (done || options.isNotEmpty);
}

final RegExp _kMenuOptionLine = RegExp(r'^\s*(\d)\s*[.)\]]\s*(.+)$');

/// 모델 응답을 [StepExpandMenuTurn]으로 읽는다.
///
/// **여기가 실제로 틀리는 자리다.** 모델은 틀을 흘리고, 번호를 빠뜨리고,
/// 옵션을 넷 내놓는다. 네트워크 없이 시험할 수 있어야 한다.
StepExpandMenuTurn parseStepExpandMenuTurn(String raw) {
  final source = raw.trim();
  if (source.isEmpty) return const StepExpandMenuTurn();

  // 되묻기가 먼저다. 이게 있으면 이번 턴은 유저 발화를 버리는 턴이라
  // 나머지를 읽을 이유가 없다.
  if (source.contains(kHeardConfirmSignal)) {
    return StepExpandMenuTurn(askBack: source);
  }

  final lines = source.split('\n');
  final textParts = <String>[];
  final options = <String>[];
  var pick = 0;
  var done = false;
  var section = '';

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final upper = line.toUpperCase();
    if (upper == '[TEXT]') {
      section = 'text';
      continue;
    }
    if (upper == '[OPTIONS]') {
      section = 'options';
      continue;
    }
    if (upper == '[PICK]') {
      section = 'pick';
      continue;
    }
    if (upper == '[DONE]') {
      done = true;
      section = 'done';
      continue;
    }
    switch (section) {
      case 'text':
        textParts.add(line);
        break;
      case 'options':
        final match = _kMenuOptionLine.firstMatch(line);
        // 번호가 안 붙은 줄은 옵션이 아니다. 모델이 흘린 설명이라 버린다 —
        // 그걸 옵션으로 실으면 유저가 설명문을 자기 문장으로 고른다.
        if (match == null) break;
        final body = match.group(2)!.trim();
        if (body.isEmpty) break;
        if (options.length < 3) options.add(body);
        break;
      case 'pick':
        final digit = RegExp(r'\d').firstMatch(line)?.group(0);
        if (digit != null) pick = int.parse(digit);
        break;
      default:
        // 틀 밖의 줄. [TEXT]를 아예 안 붙이고 글만 보낸 응답을 살린다.
        if (textParts.isEmpty && options.isEmpty) textParts.add(line);
        break;
    }
  }

  // 있지도 않은 번호를 추천으로 실으면 화면이 거짓말을 한다.
  if (pick < 1 || pick > options.length) pick = 0;

  return StepExpandMenuTurn(
    text: textParts.join(' ').trim(),
    options: List<String>.unmodifiable(options),
    pick: pick,
    done: done && options.isEmpty,
  );
}

/// 유저가 실제로 듣고 보는 대사. 틀 문장은 여기서 붙인다.
///
/// 모델에게 틀까지 맡기면 매 턴 조금씩 다른 말로 흘러서, 유저가 화면의 어디를
/// 봐야 하는지 매번 다시 찾아야 한다. 틀은 고정하고 모델은 내용만 낸다.
///
/// [isFirstTurn]이면 되짚지 않는다 — 방금 자기가 한 말을 그대로 들려주는 건
/// 되짚기가 아니라 메아리다.
String composeStepExpandMenuSpeech(
  StepExpandMenuTurn turn, {
  required bool isFirstTurn,
}) {
  final lines = <String>[];
  final text = turn.text.trim();

  if (!isFirstTurn && text.isNotEmpty) {
    lines.add("그럼, '$text' 라는 말이 되는군요.");
  }

  if (turn.done) {
    if (lines.isEmpty && text.isNotEmpty) {
      lines.add("그럼, '$text' 라는 말이 되는군요.");
    }
    lines.add('이제 공부방에서 점진적 확장 문장을 다양하게 연습해 보세요.');
    return lines.join('\n');
  }

  lines.add(isFirstTurn
      ? '3가지 제안 중에서 연결하고 싶은 말이나 다른 당신의 생각을 말해보세요.'
      : '그 다음 연결할 말을 선택하거나, 혹은 당신의 생각을 말해보세요.');
  for (var i = 0; i < turn.options.length; i++) {
    lines.add('${i + 1}. ${turn.options[i]}');
  }
  if (turn.pick >= 1 && turn.pick <= turn.options.length) {
    lines.add('저는 ${turn.pick}번이 지금 이야기에 가장 자연스럽게 이어진다고 봐요.');
  }
  return lines.join('\n');
}

/// 모델에게 넘길 이번 턴의 상태.
///
/// 누적 글과 **직전에 내놓은 후보 셋**을 함께 준다. 후보를 안 주면 "2번이
/// 좋아"가 무슨 문장인지 모델이 알 수 없어서, 그럴듯한 다른 문장을 지어내
/// 붙인다.
String buildStepExpandMenuState({
  required String growingText,
  required List<String> lastOptions,
  required String userLine,
  /// 이번 턴이 몇 번째인가(1부터). 마지막 턴이면 모델도 알고 닫는다.
  int turnNumber = 0,
}) {
  final buffer = StringBuffer();
  final text = growingText.trim();
  buffer.writeln('[TEXT SO FAR]');
  buffer.writeln(text.isEmpty ? '(nothing yet — this is their first line)' : text);
  if (lastOptions.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('[THE THREE YOU OFFERED LAST TURN]');
    for (var i = 0; i < lastOptions.length; i++) {
      buffer.writeln('${i + 1}. ${lastOptions[i]}');
    }
  }
  buffer.writeln();
  buffer.writeln('[WHAT THEY JUST SAID]');
  buffer.writeln(userLine.trim());
  if (turnNumber >= kStepExpandMaxTurns) {
    buffer.writeln();
    buffer.writeln(
        '[THIS IS THE LAST TURN] The text is full. Output [DONE] instead of options.');
  }
  return buffer.toString().trimRight();
}

/// 마지막 턴이면 후보를 걷어내고 마무리로 바꾼다.
///
/// 모델에게 "이번이 마지막"이라고 알려도 후보 셋을 내놓는 일이 있다. 그때
/// 그대로 걸면 유저가 고른 뒤에 방이 닫혀, 고른 문장이 어디에도 안 남는다.
StepExpandMenuTurn closeStepExpandMenuIfLast(
  StepExpandMenuTurn turn, {
  required int turnNumber,
}) {
  if (turn.done || turn.askBack.isNotEmpty) return turn;
  if (turnNumber < kStepExpandMaxTurns) return turn;
  return StepExpandMenuTurn(text: turn.text, done: true);
}
