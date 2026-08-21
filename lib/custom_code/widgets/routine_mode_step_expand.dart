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
  // 🎤 [BARGE-IN] 지금 울리고 있는 안내 음성. 유저가 입을 열면 이걸 끊는다.
  ChunkedTtsFetcher? _guideTtsFetcher;
  bool _isConversationActive = false;
  bool _isExiting = false; // 🔧 [EXIT-GUARD] PopScope+버튼 이중 종료 방지
  double _fontScale = 1.0;
  // Step Expand는 대화 집중을 위해 타겟 언어(영어)를 기본 표시한다.
  // 상단 언어 버튼을 누르면 실제 한국어 대화도 함께 확인할 수 있다.
  bool _showOriginal = false;
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

  Widget _buildIdleBanner() => const SizedBox.shrink();

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
  static const String kStepExpandFinalTurnLine = '문장이 이렇게 완성됐어요. 수고하셨어요.';

  /// 대화 설계 전문(全文). 매 턴 gpt-4o-mini의 system 프롬프트로 들어간다.
  /// 예전에는 Realtime 세션을 열 때 한 번만 걸어 두고 턴마다 짧은 지시만
  /// 덧붙였다. 세션이 사라진 지금은 매 턴 이걸 같이 보내야 한다.
  String _buildStepExpandSystemInstructions() {
    final nativeLang = _nativeLangName();
    final registerPolicy = nativeLang == 'Korean'
        ? kKoreanPoliteSpeechPolicy
        : 'Use the everyday polite spoken register of $nativeLang unless the user clearly establishes another register.';
    final askBackOutputRule = buildHeardConfirmOutputRule(nativeLang);
    return '''
You are the conversation partner for Step Expand practice.

${buildNativeOutputLanguagePolicy(_nativeLangName())}

[WHAT THIS PRACTICE IS]
The user is building ONE sentence, a small piece at a time. Whatever they answer
gets folded into that same growing sentence. So your question is judged by one
thing only: does their short answer attach smoothly to the sentence so far?
What you receive is that whole sentence as it stands, not just their last words.

[GUESS FIRST, THEN ASK]
Before asking, silently guess what this person is feeling underneath what they
said, and what they would want to say next. Then open that door for them.
You are not collecting facts — you are giving them room for the thing they
already half want to say.
This guessing is about their feeling and where they are heading. It is never
about filling in a word you could not make out — for that, see [ASK BACK] below.

[NEVER INTERROGATE]
- Do not work through who / when / where / why like a checklist.
- Do not grab the most concrete noun and ask "what kind of X?" — that is
  keyword-echoing, and it makes the user feel questioned rather than heard.
- Go one level under the surface words: the reason, the mood, the memory, or
  what it meant to them.

[MAKE IT EASY TO ANSWER]
- Someone quiet or still gathering their thoughts must be able to answer in one
  to three words.
- No yes/no questions. No pressure wording like "Why did you do that?".
- Read how the answer came out. If it was quick and detailed, go deeper into the
  part they seemed most alive about. If it was short or vague, do not push —
  offer a smaller, easier angle instead.

[ONE THREAD]
Every question continues the story the first turn opened. Do not hop sideways to
an unrelated noun they happened to mention. Never ask again about something they
have already answered.

[NEVER REPEAT YOURSELF — YOU CAN SEE WHAT YOU ASKED]
[CONVERSATION SO FAR] holds your own earlier questions. Read them first.
Your new question must open ground none of them touched. Rewording an earlier
question is repeating it: "어떤 활동을 해보고 싶으세요?" and "어떤 활동을 가장
해보고 싶으세요?" are the same question. If the obvious next question is one you
already asked, go somewhere else in their story.

[MAKE THE SENTENCE RICHER, BUT STAY REAL]
Each answer adds one more piece to their sentence, so aim your question at a
piece the sentence does not have yet — who was there, when, where, what happened
next, how it felt, why it mattered. Move to a different kind of piece each turn
so the sentence gains variety instead of more of the same.
But it must stay a question a real person would actually ask in conversation.
Never reach for an unusual angle just to be different, and never ask something
that would sound odd out loud.

$registerPolicy

$kSpokenReplyLengthPolicy
- Always two parts, in this order and nothing more:
  1. One short, genuine response to what they just said — react to the content
     itself, the way a friend would. Not praise, not a summary, not a repeat of
     their words.
  2. One question that opens the next piece of their sentence.
- Keep both short. Never elaborate, never stack a second question.
- Do not explain, teach grammar, advise, summarize, list, translate, show another
  language, narrate, or mention being an AI.
- Do not invent facts, names, events, feelings, or relationships.

[ASK BACK INSTEAD OF GUESSING]
What you receive is speech-recognition output, not typed text, so it can contain
misrecognized words. You never hear the audio — judge the text itself.
Do NOT answer, and do NOT repair it by guessing, when any of these holds:
- The line does not hold together as $nativeLang, or breaks off mid-thought.
- A word sits so oddly that the meaning cannot be recovered from this session.
- Making it make sense would require inventing a subject, object, or verb.
In that case follow this output format exactly:
$askBackOutputRule
Say nothing before or after those two lines. Do not add a reaction or another question.
Being short is not by itself a reason to ask back — a clear short line is fine.
Once the user says it again, continue from their new words as if the unclear
line had never been said. Never build the conversation on a line you had to guess.
''';
  }

  void _prefetchFirstTurnTranscription() {
    final pcm = _snapshotTurnPcm();
    if (pcm == null || pcm.isEmpty || _openAiKey.isEmpty) return;
    if (_prefetchedFirstTurnTranscribe != null &&
        pcm.length <= _prefetchedFirstTurnPcmBytes) {
      return;
    }
    _prefetchedFirstTurnPcmBytes = pcm.length;
    _prefetchedFirstTurnTranscribe = _transcribeAccurately(pcmOverride: pcm);
    _log('🚀 [FIRST-TRANSCRIBE-PREFETCH]',
        'started pcmBytes=${pcm.length} commitWaitMs=$COMMIT_WAIT_FIRST_TURN_MS');
  }

  List<String> _accurateTranscriptionReasons(
    String transcript, {
    required bool isFirstTurn,
  }) {
    final reasons = <String>[];
    final text = transcript.trim();
    if (isFirstTurn) reasons.add('first_turn');
    if (_activeSttConfidence == null) {
      reasons.add('confidence_missing');
    } else if (_activeSttConfidence! < 0.70) {
      reasons.add('low_transcript_confidence');
    }
    if (RegExp(r'[가-힣]').hasMatch(text) && RegExp(r'[A-Za-z]').hasMatch(text)) {
      reasons.add('mixed_language');
    }
    if (RegExp(
      r'(그게\s*아니|내\s*(말|뜻)은|잘못\s*(들|적|알아)|다시\s*말|아니[요,.\s])',
    ).hasMatch(text)) {
      reasons.add('correction_or_misheard');
    }
    if (text.endsWith('...') ||
        text.endsWith('…') ||
        RegExp(r'(그런데|근데|그래서|하지만|했는데|하는데|라서|때문에)$')
            .hasMatch(text.replaceAll(RegExp(r'\s+'), ''))) {
      reasons.add('possibly_broken_sentence');
    }
    return reasons;
  }

  bool _sameTranscriptForSpec(String left, String right) {
    String normalize(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'[^0-9a-z가-힣]'), '');
    return normalize(left) == normalize(right);
  }

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
  static const int MAX_TURNS = 5; // 5턴 자동 마무리 룰

  /// 사용자 번역·확장과 AI 질문 생성은 모두 같은 경량 모델로 처리한다.
  static const String kStepExpandUserModel = 'gpt-4o-mini';
  bool _isSessionComplete = false; // 5턴 완료 플래그 (마이크 잠금)
  bool _isPolishing = false; // 세련된 변형 문장 생성 중
  String _polishedSentence = ""; // 생성된 세련된 변형
  bool _showPolishButton = false; // 5턴 완료 후 "Polished Version" 버튼 표시
  final GlobalKey _polishedCardKey = GlobalKey();
  final List<String> _history = []; // polish 완성 문장 누적 (세션 간 유지)

  // 🌱 [NATIVE-EXPAND] 대화방 유저 말풍선은 매 턴 "지금까지 말한 것 + 이번에
  //   말한 것"을 합친 원어 한 문장이다. 1턴은 발화 자체가 씨앗이고, 2턴부터
  //   이 문장이 자란다. Realtime 응답과 무관한 별도 경량 호출로 만든다.
  String _expandedNativeSentence = "";

  // 합치기가 실패한 턴의 발화. 버리면 그 턴 내용이 확장 문장에서 통째로
  // 사라지므로, 다음 턴 합치기에 같이 넘겨 따라잡게 한다.
  final List<String> _pendingNativeParts = [];

  // 🌱 [AUTO-FLOW] 5턴 완료 후 자동 표시 상태
  String _expandedFinalSentence = ""; // 완성된 확장 문장 (별도 표시)
  bool _showExpandedFinalCard = false; // 확장 문장 카드 표시 여부
  bool _showStudyRoomPrompt = false; // "Study Room에서 연습 하세요" 표시 여부
  int _consecutiveRestateCount = 0; // 같은 턴 연속 GARBLED 횟수 (2 이상이면 더 쉬운 문장 유도)
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
  Set<String> _practiceRecognizedWords = {};
  String? _userWavPath;

  // 오디오 및 UI
  final List<Map<String, dynamic>> _localMessages = [];
  final ScrollController _scrollController = ScrollController();
  // [SCROLL-THROTTLE] State for suppressing excessive top-pin scroll calls.
  DateTime? _lastScrollTopAt;
  int _lastScrollTopIndex = -1;
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
  }

  /// 진입 첫 마디를 말풍선 + 음성으로 한 번만 내보낸다.
  /// 문구는 gpt-4o-mini가 매번 새로 만들고, 실패하면 고정 문구로 떨어진다.
  Future<void> _speakOpeningOnce() async {
    if (_hasSpokenOpening || !mounted) return;
    _hasSpokenOpening = true;
    final nativeLang = _nativeLangName();
    // 📰 구글 뉴스를 잠깐 보고 온다. 못 받아 오면 빈 목록이고, 그때는 뉴스
    //   없이 일상 화제로 연다 — 소식이 없다고 대화가 멈추면 안 된다.
    _newsHeadlines = await StepExpandBrain.fetchNewsHeadlines(nativeLang);
    _log('📰 [NEWS]', 'headlines=${_newsHeadlines.length}');
    final opening = await StepExpandBrain.generateOpening(
      apiKey: _openAiKey,
      languageName: nativeLang,
      fallback: nativeLang == 'Korean' ? _openingNudgeText : '',
      headlines: _newsHeadlines,
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
    _log('🗣️ [OPENING]', 'model=gpt-4o-mini len=${opening.length}');
    await _speakLiveKorean(opening);
  }

  void _rememberSmallTalk(String who, String text) {
    if (text.trim().isEmpty) return;
    _smallTalkLog.add('$who: ${text.trim()}');
    // 잡담이 길어져도 프롬프트는 최근 것만 본다. 오래된 말까지 실어 보내면
    // 토큰만 먹고 AI가 이미 지나간 화제로 되돌아간다.
    while (_smallTalkLog.length > 10) {
      _smallTalkLog.removeAt(0);
    }
  }

  String _smallTalkContext() => _smallTalkLog.join(String.fromCharCode(10));

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

  /// 🌱 잡담 한 턴. 씨앗을 찾으면 **그 문장**을, 아직이면 null을 돌려준다.
  ///
  /// 씨앗을 못 찾은 턴은 어디에도 남지 않는다 — 말풍선도, 히스토리도, 턴
  /// 번호도 그대로다. AI 대답은 소리로만 나가고 마이크를 다시 연다.
  Future<String?> _runSmallTalkTurn(
    String userNative, {
    required int generation,
  }) async {
    if (mounted) {
      setState(
          () => _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP'));
    }
    _rememberSmallTalk('user', userNative);
    final result = await StepExpandBrain.smallTalkTurn(
      apiKey: _openAiKey,
      languageName: _nativeLangName(),
      userText: userNative,
      recentConversation: _smallTalkContext(),
      headlines: _newsHeadlines,
    );
    if (!mounted ||
        generation != _pipelineGeneration ||
        !_isConversationActive) {
      return null;
    }
    final seed = (result['seed'] ?? '').trim();
    if (seed.isNotEmpty) {
      _log('🌱 [SEED-FOUND]',
          'len=${seed.length} smallTalkLines=${_smallTalkLog.length}');
      return seed;
    }
    final reply = (result['reply'] ?? '').trim();
    if (reply.isNotEmpty) {
      _rememberSmallTalk('ai', reply);
      await _speakLiveKorean(reply);
    } else {
      // 말도 판정도 못 받았다(네트워크·형식 실패). 대화를 세우지는 않는다 —
      // 조용히 다시 듣고 다음 발화에서 이어 간다.
      _log('🌱 [SMALLTALK-EMPTY]', 'reply_and_seed_both_empty');
    }
    if (!mounted || generation != _pipelineGeneration) return null;
    if (_isConversationActive && !_isSessionComplete) {
      await _startUserListening();
    }
    return null;
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

    // 🔧 5턴 완료 상태면 이미 모두 저장된 상태 → 즉시 리셋 후 유저 기본 문장 대기
    if (_isSessionComplete) {
      _resetSession();
      _startSessionWaitingForUserSeed();
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
                          _startSessionWaitingForUserSeed();
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
                        _startSessionWaitingForUserSeed();
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
        _hasSpokenOpening = false; // 새 주제 진입 시 첫 마디 다시 건넨다
        _seedFound = false; // 잡담부터 다시 시작한다
        _smallTalkLog.clear();
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
        _expandedNativeSentence = "";
        _pendingNativeParts.clear();
      });
      _practiceRecognizedWords.clear();
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
        _hasSpokenOpening = false; // 새 문장 진입 시 첫 마디 다시 건넨다
        _seedFound = false;
        _smallTalkLog.clear();
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
        _expandedNativeSentence = "";
        _pendingNativeParts.clear();
      });
    }
    _practiceRecognizedWords.clear();
    _startSessionWaitingForUserSeed(); // 시작 안내 후 씨앗 재료가 될 첫 발화 대기
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

  // ====================================================================
  // 📦 [Box 4-C0: 5턴 완료 마무리 — 완성문장 확정 → 저장 → Polished]
  // ====================================================================
  /// 마지막 질문에 답까지 마친 뒤의 마무리. 지금까지 자란 한국어 문장을
  /// 완성문장으로 못 박아 카드로 올리고, 같은 언어로 한 번 다듬어 들려준다.
  ///
  /// **여기서 영어를 만들지 않는다.** 대화방은 한국어 자료만 넘기고, 영어
  /// Target과 영어 Polished는 History가 자기 규칙으로 만든다.
  Future<void> _completeStepExpandSession({required int generation}) async {
    final finalNative = _expandedNativeSentence.trim();
    if (finalNative.isEmpty) {
      _log('⚠️ [DONE]', '자란 문장이 비어 있음 → 완성문장 카드/저장 생략');
      return;
    }

    if (mounted) {
      setState(() {
        _expandedFinalSentence = finalNative;
        _showExpandedFinalCard = true;
      });
      _scrollToBottom();
    }
    _log('🌱 [DONE]', '$MAX_TURNS턴 완료 → 완성문장 확정 len=${finalNative.length}');

    // 저장이 다듬기보다 먼저다. 여기서 유저가 앱을 닫아도 공부방에서 연습을
    // 열 수 있어야 한다 — has_practice가 그 트리거다.
    await _saveExpandedSentenceToFirestore(finalNative);

    if (!mounted || generation != _pipelineGeneration) return;
    await _autoPolishAndSpeak(finalNative);
    // 여기서 공부방으로 보내지 않는다. 방은 각자 따로 돈다 — 완성문장과
    // Polished를 띄우고 끝이다. 다음 문장은 아래 "Suggest New Sentence"로 이어간다.
  }

  /// 완성된 한국어 문장을 방 문서에 박는다. `has_practice`가 공부방 Practice
  /// 진입 트리거라, 이게 없으면 5턴을 다 채워도 연습 화면이 열리지 않는다.
  Future<void> _saveExpandedSentenceToFirestore(String expanded) async {
    try {
      if (_myHistoryRef == null) {
        _log('⚠️ [PRACTICE-READY]', '_myHistoryRef 없음 → 연습 진입 불가');
        return;
      }
      await _myHistoryRef!.update({
        'expanded_sentence': expanded,
        'has_practice': true,
      });
      _log('🌱 [PRACTICE-READY]', '방 루트에 expanded_sentence + has_practice 저장');
    } catch (error) {
      _log('❌ [PRACTICE-READY-ERR]', '${error.runtimeType} $error');
    }
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
  // 📦 [Box 4-C: inline Polish — 자동 생성이 실패했을 때의 재시도 버튼]
  // ====================================================================
  /// 완료 직후 자동 다듬기가 실패하면 Polished 카드 대신 버튼이 남는다.
  /// 그 버튼이 부르는 자리. 자동 경로와 같은 것을 해야 하므로 그대로 넘긴다.
  ///
  /// 예전에는 말풍선을 거꾸로 훑어 `Part1\n\nPart2`에서 뒷부분을 떼어 썼다.
  /// 지금 유저 말풍선은 자란 한국어 문장 하나뿐이라 그 파싱은 맞지 않는다.
  Future<void> _polishSentenceInline() async {
    if (_isPolishing || _openAiKey.isEmpty) return;
    final finalExpanded = _expandedFinalSentence.trim().isNotEmpty
        ? _expandedFinalSentence.trim()
        : _expandedNativeSentence.trim();
    if (finalExpanded.isEmpty) return;
    await _autoPolishAndSpeak(finalExpanded);
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
      // 언어를 바꾸지 않는 다듬기다. 영어 Polished는 History가 따로 만들며,
      // 여기서 만든 한국어를 polished_sentence/refined_sentence에 저장하면
      // History가 그걸 영어인 줄 알고 그대로 P3에 써 버린다. 저장하지 않는다.
      final polished = await StepExpandBrain.polishNativeSentence(
        apiKey: _openAiKey,
        originalSentence: expandedSentence,
        languageName: _nativeLangName(),
      );
      if (!mounted) return;
      setState(() {
        _polishedSentence = polished;
        _isPolishing = false;
      });
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
      // Polished 문장 한 번 낭독. 대화방 음성은 TtsCache에 남기지 않는 것이
      // 3모드 공통 규칙이라 _practiceSpeakText(캐시함)가 아니라 이쪽을 쓴다.
      if (polished.isNotEmpty) await _speakAiKorean(polished);
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
    await _practiceSpeakText(_polishedSentence, _aiVoice);
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

  // 현재 유저 확장 문장을 화면 상단에 고정해 처음부터 보이게 유지.
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
    _log('🧭 [SCROLL-TOP]', 'index=$index');
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

  // 🆕 긴 대사 텔레프롬프터: 화면보다 길면 첫 줄을 상단에 고정한 뒤,
  //    읽는 시간(추정) 동안 서서히 맨 아래(끝줄)로 선형 글라이드.
  //    화면에 다 들어오면 기존 카톡식(_scrollToBottom) 유지.
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
      // 화면에 다 들어오면 기존 동작
      if (itemH <= 0 || itemH <= viewH * 0.85) {
        _scrollToBottom();
        return;
      }
      // 1) 첫 줄을 화면 상단에 고정 (즉시)
      Scrollable.ensureVisible(ctx, alignment: 0.98, duration: Duration.zero);
      // 2) 읽는 시간 동안 끝줄까지 선형 글라이드
      //    (reverse 리스트에서 offset 0 = 맨 아래)
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

  // 읽는 시간 추정 (OpenAI TTS-1 영어 ≈ 14자/초). 살짝 짧게 잡아 끝줄이 약간 먼저 도착.
  // 글라이드가 너무 빠르면 값을 낮추고, 너무 느리면 값을 올린다.
  static const double _kReadCharsPerSec = 14.0;
  int _estimateReadMs(String text) {
    final int n = text.trim().length;
    if (n <= 0) return 1500;
    final int ms = (n / _kReadCharsPerSec * 1000).round();
    return ms.clamp(1500, 25000);
  }

  /// 대화방에서만 쓰는 한국어 AI 음성. tts-1/nova로 재생하되 캐시에
  /// 저장하지 않아, 히스토리의 타겟 언어 음성 생성 규칙과 분리한다.
  Future<void> _speakLiveKorean(String text) async {
    final spoken = text.trim();
    if (spoken.isEmpty || _openAiKey.isEmpty) return;
    // 🔁 [LATE-CONTINUATION] 소리가 나기 전에 마이크를 닫아야 [MIC-ROUTING]이
    //   지켜진다. AI 질문도 되묻기도 이 길로 나간다.
    _closeContinuationWindow(reason: 'tts_enqueue');
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
    // 안내 음성이 나가는 동안은 barge-in 대상이다. 이전 안내가 남아 있으면
    // 먼저 끊어, 취소 대상이 항상 지금 울리는 하나만 되게 한다.
    _guideTtsFetcher?.cancel();
    _guideTtsFetcher = fetcher;
    _isInitialGuidePlaying = true;
    fetcher.addText(spoken);
    int ticks = 0;
    try {
      while ((fetcher.pendingRequests > 0 || _ttsQueueManager.isBusy) &&
          mounted &&
          !fetcher.isCancelled) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (++ticks > 600) {
          _log('⚠️ [KOREAN-TTS-TIMEOUT]', '한국어 안내 음성 30초 초과');
          break;
        }
      }
    } finally {
      // 그 사이 다음 안내가 시작됐다면 그쪽 상태를 건드리지 않는다.
      if (identical(_guideTtsFetcher, fetcher)) {
        _guideTtsFetcher = null;
        _isInitialGuidePlaying = false;
      }
    }
  }

  /// 유저가 직전 AI 질문에 불만을 표시했을 때, 그 질문을 지우고 새로 만든다.
  /// 불만 발화 자체는 학습 턴으로 세지 않는다 — 유저는 답을 한 게 아니라
  /// 질문을 물린 것이다. 자란 문장도 건드리지 않는다.
  Future<void> _replaceLastQuestion({required int generation}) async {
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

    final replacement = await StepExpandBrain.generateKoreanTurn(
      apiKey: _openAiKey,
      instructions: '${_buildStepExpandSystemInstructions()}\n'
          '\n[THIS TURN]\n${_buildStepExpandTurnInstructions(_turnCounter + 1)}\n'
          '\n[THE USER TURNED DOWN YOUR LAST QUESTION]\n'
          'Your previous question was: "$rejected"\n'
          'They found it repetitive, off, or hard to answer. Ask a completely '
          'different one — different angle, different wording. Never repeat or '
          'rephrase the rejected question. Do not apologize, do not mention '
          'that they complained, and do not explain yourself. Just ask.',
      userText: _expandedNativeSentence.trim().isEmpty
          ? '(아직 자란 문장이 없습니다. 유저가 첫 문장을 말하도록 다시 물어보세요.)'
          : _expandedNativeSentence,
      recentConversation: _recentKoreanConversationForValidation(),
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

  /// AI 턴 응답을 한국어 음성으로 낸다.
  /// 안내 음성과 달리 barge-in 대상이 아니다 — 답을 끝까지 들려준 뒤 마이크를 연다.
  Future<void> _speakAiKorean(String text) async {
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
    fetcher.addText(spoken);
    int ticks = 0;
    while (
        (fetcher.pendingRequests > 0 || _ttsQueueManager.isBusy) && mounted) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (++ticks > 600) {
        _log('⚠️ [AI-TTS-TIMEOUT]', 'AI 응답 음성 30초 초과');
        break;
      }
    }
  }

  Future<void> _askForUsableSeedSentence(
    String rejectedText, {
    required int generation,
  }) async {
    final guide = await StepExpandBrain.generateSeedGuidance(
      apiKey: _openAiKey,
      rejectedText: rejectedText,
      originLang: _nativeLangName(),
      targetLang: FFAppState().targetLang.isNotEmpty
          ? FFAppState().targetLang
          : 'English',
    );
    if (!mounted ||
        !_isConversationActive ||
        generation != _pipelineGeneration ||
        _turnCounter != 0) {
      return;
    }
    final englishQuestion = guide['english_question']?.trim().isNotEmpty == true
        ? guide['english_question']!.trim()
        : localizedSeedGuidanceLine(FFAppState().targetLang);
    final koreanQuestion = guide['korean_question']?.trim().isNotEmpty == true
        ? guide['korean_question']!.trim()
        : localizedSeedGuidanceLine(_nativeLangName());
    setState(() {
      _localMessages.removeWhere((message) =>
          message['role'] == 'HOST_TEMP' || message['seed_guide'] == true);
      _localMessages.add({
        'role': 'SYSTEM',
        'target': englishQuestion,
        'original': koreanQuestion,
        'seed_guide': true,
      });
    });
    _scrollToBottom();
    _log('[SEED-GUIDE]', '첫 발화 미채택 → 유도 질문 후 1턴 유지');
    await _speakLiveKorean(koreanQuestion);
    if (mounted &&
        _isConversationActive &&
        generation == _pipelineGeneration &&
        _turnCounter == 0) {
      await _startUserListening();
    }
  }

  void _stopEverything() {
    _pipelineGeneration++;
    _isConversationActive = false;
    _aiTurnActive = false;
    _commitTimer?.cancel();
    _commitTimer = null;
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
    if (clean.length < 2) return true;
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

  Future<void> _speakStepRetryAndListen() async {
    _ttsQueueManager.setUserTurn(false);
    _ttsQueueManager.setAiPaused(false);
    final retryTts = ChunkedTtsFetcher(
      _openAiKey,
      _ttsQueueManager,
      _aiVoice,
      language: _nativeLangCode(),
      cacheEnabled: false,
      isUser: false,
      onLog: _log,
    );
    retryTts.addText('죄송해요. 문장을 조금 천천히 다시 말씀해 주세요.');
    int ticks = 0;
    while (
        (retryTts.pendingRequests > 0 || _ttsQueueManager.isBusy) && mounted) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (++ticks > 200) break;
    }
    if (mounted && _isConversationActive && !_isSessionComplete) {
      await _startUserListening();
    }
  }

  Future<void> _startStreamingListening() async {
    if (_streamingCaptureOpen) {
      _log('🎤 [LISTEN-SKIP]', '이미 듣는 중 → 중복 오픈 무시');
      return;
    }
    if (_isSessionComplete || _isPracticeMode) return;
    if (_aiTurnActive || _ttsQueueManager.isBusy) {
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
    if (_aiTurnActive || _ttsQueueManager.isBusy) return;
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

    // 🌱 [SEED-PHASE] 아직 씨앗이 없다면 여기는 잡담 구간이다. 이 말은 화면에도
    //   히스토리에도 남기지 않고, 씨앗이 될 만한지만 조용히 본다. 씨앗을
    //   찾으면 그 문장이 곧 이 세션의 첫 문장이 되어 아래 정상 경로로 간다.
    if (!_seedFound) {
      final seed = await _runSmallTalkTurn(userKorean, generation: generation);
      if (!mounted || generation != _pipelineGeneration) return;
      if (seed == null) return;
      _seedFound = true;
      userKorean = seed;
    }

    // 🗣️ 방금 한 말을 검증·합치기보다 먼저 띄운다. 둘 다 gpt-4o-mini 왕복이라
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

    // 🚪 [GATE] 이 턴을 통과시킬지 판정하는 곳은 하나뿐이다.
    //
    //    1턴(씨앗)은 붙일 대상이 없어 합치기가 아무 판정도 할 수 없다. 그 턴만
    //    KoreanTurnValidator가 게이트를 맡는다.
    //
    //    2턴부터는 mergeNativeExpansion이 이미 같은 판정을 한다 — 자란 문장에
    //    실제로 붙여 보고 못 붙이겠으면 [UNCLEAR]를 돌려준다(§kUnclearToken).
    //    검증기의 반려 사유는 프롬프트상 "전사 오류" 하나뿐이고, 화제 전환·짧은
    //    답·문체는 명시적으로 통과시킨다. 즉 2턴부터는 같은 판정을 두 번 사는
    //    셈이었고, 반려된 턴에서는 더 비싼 합치기 쪽을 통째로 버리고 있었다.
    //    붙여 보고 내린 판정이 근거가 더 좋으므로 합치기 하나로 합친다.
    final previousExpandedNow = _expandedNativeSentence.trim();
    if (previousExpandedNow.isEmpty) {
      // 첫 문장은 합칠 대상이 없다 — 발화가 곧 씨앗이다.
      final validation = await KoreanTurnValidator.validate(
        apiKey: _openAiKey,
        transcribedText: userKorean,
        mode: 'step_expand',
        modeContext: 'Current growing sentence: (first seed)',
        recentConversation: _recentKoreanConversationForValidation(),
      );
      if (!mounted || generation != _pipelineGeneration) return;
      // 장애로 통과시킨 턴과 모델이 승인한 턴을 로그에서 갈라 본다. 원문은
      // 싣지 않는다 — 길이와 판정 결과까지만 남긴다.
      _log(
          '[TURN-VALIDATE]',
          'mode=step_expand gate=validator seed=true '
              'accepted=${validation.accepted} '
              'failure=${validation.failure.name} '
              'failOpen=${validation.failedOpen} '
              'proceeded=${validation.accepted} reason=${validation.reason}');
      if (!validation.accepted) {
        // 🚪 [GATE-ESCAPE] 씨앗 턴이 연달아 막히면 세션을 시작조차 못 한다.
        //   다른 두 모드와 같은 탈출구를 둔다.
        _consecutiveGateRejects++;
        if (_consecutiveGateRejects <=
            KoreanTurnValidator.maxConsecutiveRejects) {
          // 👂 되묻기는 소리로만 나간다. 글자로 남기면 지우는 사람이 없어 방을
          //   나갈 때까지 쌓이고, 그 문장이 다음 턴 컨텍스트에 섞여 AI가 따라
          //   되묻는다. 되묻기가 되묻기를 부르는 자리였다.
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
          });
          await _speakLiveKorean(originRetryLine(_nativeLangName()));
          if (mounted && _isConversationActive && !_isSessionComplete) {
            _startUserListening();
          }
          return;
        }
        _log('[GATE-ESCAPE]',
            'mode=step_expand seed=true forced_pass rejects=$_consecutiveGateRejects');
      }
      _consecutiveGateRejects = 0;

      _log('🔀 [COMMIT-03]', '전사·문맥 확정 → Step Expand 질문 생성');
      // 반려된 판정은 text가 비어 있다. 통과시킬 때는 전사 원문을 그대로 쓴다.
      await _processStepExpandTurn(
        validation.accepted ? validation.text : userKorean,
        generation: generation,
        mergedFuture: null,
      );
      return;
    }

    // 2턴부터는 합치기가 곧 게이트다. 결과는 버려지지 않고 반드시 소비된다.
    final mergedFuture = StepExpandBrain.mergeNativeExpansion(
      apiKey: _openAiKey,
      previousExpanded: previousExpandedNow,
      newUtterances: <String>[..._pendingNativeParts, userKorean],
      languageName: _nativeLangName(),
      topicContext: _topicContextForRepair(),
    );

    _log('🔀 [COMMIT-03]', '전사 확정 → 합치기 게이트 → Step Expand 질문 생성');
    await _processStepExpandTurn(
      userKorean,
      generation: generation,
      mergedFuture: mergedFuture,
    );
  }

  // ignore: unused_element
  void _commitAndProcessLegacy() async {
    final pipelineGeneration = _pipelineGeneration;
    final committed = _pendingTranscript.trim();
    _pendingTranscript = '';
    _lastPendingFinalAt = null;
    _commitTimer = null;

    if (committed.isEmpty) {
      _log('🔀 [COMMIT-00]', '빈 발화 → 마이크 재시작');
      // 🚀 [SPEC] 빈 확정이면 진행 중 투기 번역 폐기
      _cancelSpeculativeTranslation();
      _prefetchedFirstTurnTranscribe = null;
      _prefetchedFirstTurnPcmBytes = 0;
      if (_isConversationActive) _startUserListening();
      return;
    }

    _log('🔀 [COMMIT-01]', '확정: len=${committed.length} → 파이프라인 시작');

    // 마이크/VoiceManager 정리
    await _voiceManager?.dispose();
    _voiceManager = null;
    _log('🔀 [COMMIT-02]', 'VoiceManager dispose 완료');

    _runMeaningProbe(committed);
    final isFirstTurn = _turnCounter == 0;
    final accurateReasons = _accurateTranscriptionReasons(
      committed,
      isFirstTurn: isFirstTurn,
    );
    String effectiveTranscript = committed;
    if (accurateReasons.isNotEmpty) {
      final prefetched = _prefetchedFirstTurnTranscribe;
      _prefetchedFirstTurnTranscribe = null;
      _prefetchedFirstTurnPcmBytes = 0;
      final accurate = (await (prefetched ?? _transcribeAccurately()))?.trim();
      if (accurate != null && accurate.isNotEmpty) {
        effectiveTranscript = accurate;
        _log('🎧 [STT-ROUTE]',
            'selected=gpt-4o-transcribe reasons=${accurateReasons.join(",")}');
      } else {
        _log('⚠️ [STT-ROUTE]',
            'gpt-4o-transcribe failed fallback=nova3 reasons=${accurateReasons.join(",")}');
      }
    } else {
      _log('🎧 [STT-ROUTE]', 'selected=nova3 turn=$_turnCounter');
    }

    Stream<String>? userOverride;
    if (_specController != null &&
        _sameTranscriptForSpec(_specTranscript, effectiveTranscript)) {
      userOverride = _specController!.stream;
      _detachSpeculativeTranslation();
      _log('🚀 [SPEC-HANDOFF]', 'accepted transcript_match=true');
    } else {
      _cancelSpeculativeTranslation();
      _log('🚀 [SPEC-HANDOFF]', 'discarded transcript_match=false');
    }
    if (pipelineGeneration != _pipelineGeneration || !mounted) return;

    _log('🔀 [COMMIT-03]', '_processRelayPipeline 호출');
    _processRelayPipeline(
      effectiveTranscript,
      userStreamOverride: userOverride,
      expectedPipelineGeneration: pipelineGeneration,
    );
  }

  // 대화방의 라이브 턴. 누적 문장을 먼저 확정해 유저 말풍선에 올리고,
  // gpt-4o-mini가 다음 한국어 질문을 만든 뒤 별도 TTS로 읽는다.
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
    final previousExpanded = _expandedNativeSentence.trim();
    final previousPending = List<String>.from(_pendingNativeParts);
    final mergeInputs = <String>[..._pendingNativeParts, userKorean];
    Map<String, dynamic>? hostBubble;
    try {
      setState(() {
        _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
      });

      // 1️⃣ 확장 문장을 AI 질문보다 먼저 확정한다. 순서가 뒤집히면 유저는
      //    자기 문장이 어떻게 자랐는지 보기도 전에 다음 질문을 듣게 된다.
      //    1턴은 방금 한 말이 곧 씨앗이라 합치기가 필요 없다.
      var bubbleText = userKorean;
      if (previousExpanded.isEmpty) {
        // 호출부가 합치기를 던졌는데 그사이 자란 문장이 비워졌다면(방 재시작
        // 등) 여기로 온다. 받을 사람이 없으므로 명시적으로 버린다.
        mergedFuture?.ignore();
        _expandedNativeSentence = userKorean;
        _pendingNativeParts.clear();
        _log('[EXPAND-SEED]', 'turn=$turnNumber text="$userKorean"');
      } else {
        final mergeResult = await (mergedFuture ??
            StepExpandBrain.mergeNativeExpansion(
              apiKey: _openAiKey,
              previousExpanded: previousExpanded,
              newUtterances: mergeInputs,
              languageName: _nativeLangName(),
              topicContext: _topicContextForRepair(),
            ));
        if (!mounted ||
            !_isConversationActive ||
            generation != _pipelineGeneration) {
          return;
        }
        final merged = mergeResult.text.trim();
        // 🚪 [EXPAND-GATE] 2턴부터 이 줄이 이 턴의 유일한 판정이다. 장애로
        //   넘어간 턴과 모델이 붙일 수 있다고 본 턴을 로그에서 갈라 본다.
        //   원문은 싣지 않는다 — 판정 결과까지만 남긴다.
        _log(
            '[EXPAND-GATE]',
            'turn=$turnNumber gate=merge verdict=${mergeResult.isVerdict} '
                'unclear=${mergeResult.unclear} '
                'failure=${mergeResult.failure.name} '
                'failOpen=${mergeResult.failedOpen}');
        // 👂 붙이는 쪽이 못 알아들었다고 하면 거기서 멈춘다. 여기서 어물쩍
        //   다듬어 넘기면 아래 어디에서도 이상한 걸 알아챌 수 없다. 유저
        //   발화는 화면에도 문장에도 넣지 않고 보류한 뒤 다시 듣는다.
        //   장애([failedOpen])는 이 분기에 걸리면 안 된다 — 통신이 끊긴 것을
        //   "못 알아들었다"고 되묻으면 유저가 같은 말을 반복하게 된다.
        if (mergeResult.unclear) {
          askedBack = true;
          _turnCounter--;
          // 되묻기는 소리로만 나간다(위 검증 반려와 같은 이유).
          _log('[EXPAND-UNCLEAR]', 'turn=$turnNumber 되묻기 → 유저 발화 보류');
          await _speakLiveKorean(originRetryLine(_nativeLangName()));
          return;
        }
        if (mergeResult.failedOpen || merged.isEmpty) {
          // 합치기가 실패한 발화는 버리지 않고 다음 턴에 같이 넘긴다.
          // 되묻지 않는다 — 유저는 제대로 말했고 흔들린 건 우리 쪽이다.
          _pendingNativeParts
            ..clear()
            ..addAll(mergeInputs);
          _log(
              '[EXPAND-MERGE]',
              'turn=$turnNumber failed=${mergeResult.failure.name} '
                  'carry=${mergeInputs.length}');
        } else {
          bubbleText = merged;
          _expandedNativeSentence = merged;
          _pendingNativeParts.clear();
          _log(
              '[EXPAND-MERGE]',
              'turn=$turnNumber prev="$previousExpanded" add="$userKorean" '
                  'merged="$merged"');
        }
      }

      // 2️⃣ 자란 문장을 먼저 화면에 올린다.
      // 🔁 [LATE-CONTINUATION] id를 박아 둔다. 이어 말하기로 문장이 자라면
      //   새 말풍선을 만들지 않고 이 id로 찾아 글자만 바꾼다.
      if (_bubbleIndexById(_activeHostBubbleId) < 0) {
        _activeHostBubbleId = _nextBubbleId('host');
      }
      hostBubble = <String, dynamic>{
        'role': 'HOST',
        'target': bubbleText,
        'original': '',
        'msgId': _activeHostBubbleId,
      };
      setState(() => _localMessages.add(hostBubble!));
      _scrollToBottom();

      // 🌱 마지막 턴에서는 AI가 말을 얹지 않는다. 5번째 답까지 받으면 문장은
      //   다 자란 상태라 더 물을 것이 없다. 그런데도 생성을 돌리면 유저가
      //   답할 자리가 없는 여섯 번째 질문이 나간다. 지시문으로 "묻지 말라"고
      //   해봐야 모델이 지키지 않을 때가 있고, [_isAskBackReply]는 되묻기만
      //   걸러서 평범한 질문은 그대로 통과했다.
      //   → 생성을 아예 건너뛰고 곧장 완성문장으로 넘어간다. 소리는
      //     _autoPolishAndSpeak가 완성문장과 다듬은 문장을 읽어 채운다.
      if (turnNumber >= MAX_TURNS) {
        turnCompleted = true;
        if (mounted) {
          setState(() {
            _isSessionComplete = true;
            _debugResult = '🎉 $MAX_TURNS턴 완료!';
          });
          _scrollToBottom();
        }
        // AI 응답이 없으므로 유저 턴만 남긴다. 저장이 실패해도 완성문장은
        // 반드시 띄운다 — 여기서 예외가 위 catch로 빠지면 5턴을 다 채우고도
        // 카드가 안 나온다.
        final finalHostLine = <String, dynamic>{
          'role': 'HOST',
          'original_text': userKorean,
          // 🌱 [EXPAND-LADDER] 이 턴까지 자란 문장. 말풍선에 올린 것과 같은
          //   값이다 — 히스토리가 방에서 본 사다리를 그대로 재현한다.
          'expanded_sentence': bubbleText,
        };
        try {
          await _saveTurnToFirestore(<Map<String, dynamic>>[finalHostLine]);
          await _saveHistoryMessages(<Map<String, dynamic>>[finalHostLine]);
        } catch (error) {
          _log('❌ [FINAL-TURN-SAVE-ERR]', '${error.runtimeType} $error');
        }
        _log('[GPT-HISTORY]',
            'turn=$turnNumber model=none reason=final_turn_no_ai_reply');
        await _completeStepExpandSession(generation: generation);
        return;
      }

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
      //    답은 gpt-4o-mini가 한국어로 만들고, 소리는 아래에서 TTS가 낸다.
      //    방금 한 말이 아니라 지금까지 자란 문장을 통째로 준다. 다음에 무슨
      //    말이 올지 추측하려면 문장 전체가 보여야 한다.
      String aiKorean = await StepExpandBrain.generateKoreanTurn(
        apiKey: _openAiKey,
        // 대화 설계 전문 + 이번 턴 초점. 전문을 빼면 되묻기·한 줄기 유지 같은
        // 규칙이 통째로 사라져, 모델이 [_isAskBackReply]가 찾는 문장을 아예
        // 만들지 않는다.
        instructions: '${_buildStepExpandSystemInstructions()}\n'
            '\n[THIS TURN]\n${_buildStepExpandTurnInstructions(turnNumber)}',
        recentConversation: _recentKoreanConversationForValidation(),
        userText: _expandedNativeSentence,
      );
      if (aiKorean.isEmpty) {
        throw StateError('Step Expand reply did not complete.');
      }
      if (!mounted ||
          !_isConversationActive ||
          generation != _pipelineGeneration ||
          asyncTurnId != _activeAsyncTurnId) {
        return;
      }
      turnCompleted = true;
      // 🌱 마지막 턴에서는 되묻지 않는다. 더 물을 것이 없어 되묻기가 의미를
      //   잃는데, 여기서 턴을 되돌리면 5턴을 다 채우고도 완성문장이 영영 안
      //   나온다. 합치기는 이미 성공해 문장이 제대로 자란 상태이므로, 마무리
      //   멘트만 고정 문장으로 갈아 끼우고 정상 종료시킨다.
      if (turnNumber >= MAX_TURNS && _isAskBackReply(aiKorean)) {
        _log('[ASK-BACK-FINAL]', 'turn=$turnNumber 마지막 턴 되묻기 → 고정 마무리 멘트로 대체');
        aiKorean = kStepExpandFinalTurnLine;
      }
      // 👂 되묻기 턴이면 유저 발화를 버린다. 화면에도 히스토리에도 남기지
      //   않고 턴 번호도 되돌려, 유저가 다시 말한 것이 이 턴이 되게 한다.
      //   되묻는 말은 소리로만 내보낸다 — 글자로 남기면 지우는 사람이 없어
      //   쌓이고, 다음 턴 컨텍스트에 섞여 AI가 따라 되묻는다.
      if (_isAskBackReply(aiKorean)) {
        askedBack = true;
        _turnCounter--;
        // 잘못 들은 발화로 자란 문장은 없던 일로 되돌린다.
        _expandedNativeSentence = previousExpanded;
        _pendingNativeParts
          ..clear()
          ..addAll(previousPending);
        // AI 말풍선은 아래 정상 분기에서야 만들어진다(aiIndex는 여기서 아직
        // -1). 여기서는 유저 말풍선만 걷어내면 화면에 아무것도 남지 않는다.
        setState(() {
          _localMessages.remove(hostBubble);
        });
        _log('[ASK-BACK]', 'turn=$turnNumber 되묻기 → 유저 발화 폐기(화면/히스토리 미기록)');
        final spokenQuestion = stripHeardConfirmSignal(aiKorean);
        await _speakAiKorean(spokenQuestion.isEmpty
            ? originRetryLine(_nativeLangName())
            : spokenQuestion);
        return;
      }

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
        if (turnNumber >= MAX_TURNS) {
          _isSessionComplete = true;
          _debugResult = '🎉 $MAX_TURNS턴 완료!';
        }
      });
      _scrollToBottom();
      await _speakAiKorean(aiKorean);

      final hostLine = <String, dynamic>{
        'role': 'HOST',
        'original_text': userKorean,
        // 🌱 [EXPAND-LADDER] 이 턴까지 자란 문장. 말풍선에 올린 것과 같은
        //   값이다 — 히스토리가 방에서 본 사다리를 그대로 재현한다.
        'expanded_sentence': bubbleText,
      };
      final systemLine = <String, dynamic>{
        'role': 'SYSTEM',
        'original_text': aiKorean,
      };
      await _saveTurnToFirestore(<Map<String, dynamic>>[hostLine, systemLine]);
      await _saveHistoryMessages(<Map<String, dynamic>>[hostLine, systemLine]);
      _log('[GPT-HISTORY]',
          'turn=$turnNumber model=gpt-4o-mini voice=$_aiVoice tts=true');

      // 마지막 턴이면 여기서 세션을 닫는다. _saveHistoryMessages가 방금
      // _myHistoryRef를 보장했으므로 완성문장을 박을 자리가 확실하다.
      if (turnNumber >= MAX_TURNS) {
        await _completeStepExpandSession(generation: generation);
      }
    } catch (error) {
      _log('[GPT-PIPE-ERR]',
          'turn=$turnNumber reason=${error.runtimeType} error=$error');
      // 실패한 요청이 정상 턴 수를 먹지 않게 한다. 그래야 재발화가 다시 같은
      // Step 번호로 처리되고 5턴 완료 상태가 앞당겨지지 않는다.
      final turnStillActive =
          mounted && _isConversationActive && generation == _pipelineGeneration;
      if (turnStillActive &&
          !turnCompleted &&
          !askedBack &&
          _turnCounter == turnNumber) {
        _turnCounter--;
      }
      if (turnStillActive && !turnCompleted && !askedBack) {
        // 답을 못 받은 턴이므로 자란 문장도 이전 상태로 되돌린다. 유저가
        // 다시 말하면 그 발화가 같은 자리에서 다시 붙는다.
        _expandedNativeSentence = previousExpanded;
        _pendingNativeParts
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

  /// 턴마다 얹는 짧은 지시. 역할과 원칙은 세션 지시문이 이미 들고 있으므로
  /// 여기서는 이번 턴에 어느 결을 따라갈지만 정한다. 매 턴 같은 축을 주면
  /// 질문이 육하원칙 점검처럼 굳는다.
  String _buildStepExpandTurnInstructions(int turnNumber) {
    if (turnNumber >= MAX_TURNS) {
      return 'This is the final turn. In one short, warm spoken sentence, land the '
          'sentence they built. Do not ask anything, explain, or summarize at length.';
    }
    const focuses = <String>[
      // 1턴: 왜 그 말을 꺼냈는지, 그 밑의 마음을 따라간다.
      'Follow the feeling or the motivation under what they just said. Guess quietly '
          'why this matters to them, then ask something light that follows that thread.',
      // 2턴: 이야기에서 가장 무게가 실린 사람·장소·물건.
      'Follow whichever person, place, or thing seems to carry the most weight in '
          'their story. Ask about the one they would want to say more about.',
      // 3턴: 그때 어떤 기분이었는지, 무엇이 남았는지.
      'Follow how it felt, or the part that stayed with them. Let the feeling come '
          'out on its own — do not force a contrast.',
      // 4턴: 이야기가 저절로 향하는 곳.
      'Follow where their story is naturally heading — what it led to, or what it '
          'means to them now. Guess what they would enjoy adding, and invite it gently.',
    ];
    final focus = focuses[(turnNumber - 1).clamp(0, focuses.length - 1)];
    return 'Continue the practice. First give one short, genuine response to what '
        'they just said. Then ask exactly one question their one-to-three-word '
        'answer can attach to. $focus';
  }

  /// 되묻기 판정은 언어와 무관한 공통 내부 신호만 사용한다.
  static bool _isAskBackReply(String text) => hasHeardConfirmSignal(text);

  // ====================================================================
  // 🚀 [SPEC-FIRST-TURN] 첫 턴(seed) 투기적 선(先)시작
  // ------------------------------------------------------------------
  // 대기창(commit wait) 동안 GPT 번역을 미리 돌려 토큰을 StreamController에 버퍼링.
  // 확정 시 이 버퍼를 파이프라인에 그대로 넘기면 TTFT(첫 토큰 지연)가 대기창에 겹쳐
  // 사라진다. 마이크/오디오/AI응답 로직은 전혀 건드리지 않아 안전하며, 추가 발화가
  // 오면(합치기) 투기 번역을 취소·재시작하므로 짤림 위험이 없다. (첫 턴 전용)
  // ====================================================================
  void _startSpeculativeTranslation(String text) {
    _cancelSpeculativeTranslation(); // 이전 투기 번역 정리 후 재시작
    _specTranscript = text;
    final controller = StreamController<String>();
    _specController = controller;
    // 첫 턴(seed)은 대화 컨텍스트가 없으므로 contextStr은 빈 문자열(파이프라인과 동일).
    final String targetLangName = FFAppState().targetLang.isNotEmpty
        ? FFAppState().targetLang
        : 'English';
    _log('🚀 [SPEC-START]', 'first-turn 투기 번역 시작: len=${text.length}');
    _specSub = StepExpandBrain.streamUserTranslation(
      apiKey: _openAiKey,
      textOriginal: text,
      originLang: _nativeLangName(),
      targetLang: targetLangName,
      contextStr: '',
      disableCorrection: false,
      model: kStepExpandUserModel,
    ).listen(
      (chunk) {
        if (!controller.isClosed) controller.add(chunk);
      },
      onError: (_) {
        if (!controller.isClosed) controller.close();
      },
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
      cancelOnError: true,
    );
  }

  // 소유권 이전: 컨트롤러를 파이프라인이 소비하도록 필드에서만 분리(닫지 않음).
  //   백그라운드 구독은 계속 add하고 스트림 종료 시 onDone에서 controller를 닫는다.
  void _detachSpeculativeTranslation() {
    _specController = null;
    _specSub = null;
    _specTranscript = '';
  }

  void _cancelSpeculativeTranslation() {
    final sub = _specSub;
    _specSub = null;
    final c = _specController;
    _specController = null;
    _specTranscript = '';
    sub?.cancel();
    if (c != null && !c.isClosed) c.close();
  }

// ====================================================================
// 📦 [Box 5-RETRY: 재질문 처리]
// ====================================================================
  Future<void> _handleRetryQuestion(String contextStr, String targetLangName,
      {bool isDifferent = false,
      bool isMisheard = false,
      bool silentReplace = false,
      String rejectedQuestion = ''}) async {
    _log(
        '🔄 [RETRY]',
        isMisheard
            ? '오청취 재질문 모드 진입'
            : (isDifferent
                ? (silentReplace ? '불만 감지 → 조용히 질문 교체' : '다른 질문 모드 진입')
                : '재질문 모드 진입'));
    _ttsQueueManager.setUserTurn(false);
    _ttsQueueManager.setAiPaused(false);

    // 안내 멘트 TTS — silentReplace 모드이면 완전히 건너뜀
    ChunkedTtsFetcher? phraseTts;
    if (!silentReplace) {
      phraseTts = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        _aiVoice,
        language: _nativeLangCode(),
        cacheEnabled: false,
        isUser: false,
        onLog: _log,
      );
      phraseTts.addText(isMisheard
          ? "아 제가 잘못 들었어요. 다시 질문할게요."
          : (isDifferent ? "그럼 다른 질문 드릴게요." : "다시 질문할게요."));
    }

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
      originLang: _nativeLangName(),
      userId: FirebaseAuth.instance.currentUser?.uid ?? '',
      isRetry: !isDifferent && !isMisheard,
      isDifferent: isDifferent,
      rejectedQuestion: rejectedQuestion,
    );

    final questionTts = ChunkedTtsFetcher(
      _openAiKey,
      _ttsQueueManager,
      _aiVoice,
      language: _nativeLangCode(),
      cacheEnabled: false,
      isUser: false,
      onLog: _log,
    );
    String aiText = "";
    String aiOriginalRetry = "";
    bool aiRetryHasDoubleNewline = false;

    // _swTTS..reset()..start();
    _swTTS
      ..reset()
      ..start(); // 재질문 경로도 발사 ms를 새로 측정한다.

    await for (final chunk in aiStream) {
      if (!aiRetryHasDoubleNewline) {
        // Part1 (영어): 화면/히스토리용
        aiText += chunk;

        if (aiText.contains('\n\n')) {
          aiRetryHasDoubleNewline = true;
          final sepIdx = aiText.indexOf('\n\n');
          final afterSep = aiText.substring(sepIdx + 2);
          aiText = aiText.substring(0, sepIdx);
          if (afterSep.isNotEmpty) aiOriginalRetry += afterSep;
        }
      } else {
        // Part2 (한국어): 실시간 대화 음성
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
    if (StepExpandBrain.needsShortKoreanQuestionRewrite(aiOriginalRetry)) {
      final beforeRewrite = aiOriginalRetry.trim();
      aiOriginalRetry = await StepExpandBrain.rewriteToShortKoreanQuestion(
        apiKey: _openAiKey,
        text: beforeRewrite,
      );
      _log('🛡️ [AI-LENGTH-GUARD]',
          'path=retry before="$beforeRewrite" after="$aiOriginalRetry"');
      if (mounted && aiIdx < _localMessages.length) {
        setState(() => _localMessages[aiIdx]['original'] = aiOriginalRetry);
      }
    } else if (StepExpandBrain.needsNaturalPoliteRewrite(aiOriginalRetry)) {
      final beforeRewrite = aiOriginalRetry.trim();
      aiOriginalRetry = await StepExpandBrain.rewriteToNaturalPoliteKorean(
        apiKey: _openAiKey,
        text: beforeRewrite,
      );
      _log('🛡️ [AI-REGISTER-GUARD]',
          'path=retry before="$beforeRewrite" after="$aiOriginalRetry"');
      if (mounted && aiIdx < _localMessages.length) {
        setState(() => _localMessages[aiIdx]['original'] = aiOriginalRetry);
      }
    }
    questionTts.addText(aiOriginalRetry.trim());
    _revealForReading(aiIdx, aiText.trim()); // 🆕 긴 대사 텔레프롬프터

    // TTS 재생 완료 대기
    int ticks = 0;
    while ((phraseTts?.pendingRequests ?? 0) > 0 ||
        questionTts.pendingRequests > 0 ||
        _ttsQueueManager.isBusy) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (++ticks > 300) break;
    }

    if (_isConversationActive) _startUserListening();
  }

// ====================================================================
// 📦 [Box 5-A: 중앙 통제실 - 루틴 정석 "시간벌기 마술" 패턴]
// ====================================================================
// 🎯 핵심 전략:
//   STEP 1: 증발 검열 (고스트워드/너무 짧음 → 조용히 폐기)
//   STEP 2: 유저 한국어 원문 보존 + 타겟 영어 문장 스트리밍
//   STEP 3: AI 영어 화면 문장 + 한국어 대화 문장 동시 생성
//   STEP 4: AI 한국어만 tts-1/nova로 재생 (캐시하지 않음)
//   STEP 5: 한·영 글자를 Firestore/히스토리에 저장
//   STEP 6: 마이크 재개방, 5턴이면 P3 자료 저장 후 자동 종료
// ====================================================================
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
    _expandedNativeSentence = '';
    for (var index = _localMessages.length - 1; index >= 0; index--) {
      if (_localMessages[index]['role'] == 'HOST') {
        _expandedNativeSentence =
            (_localMessages[index]['target'] ?? '').toString().trim();
        break;
      }
    }
    _pendingNativeParts.clear();

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

  Future<void> _processRelayPipeline(String finalTranscript,
      {bool isCorrectionRetry = false,
      bool understandingConfirmed = false,
      Stream<String>? userStreamOverride,
      int? expectedPipelineGeneration}) async {
    final pipelineGeneration =
        expectedPipelineGeneration ?? _pipelineGeneration;
    if (!isActivePipelineGeneration(
      expected: pipelineGeneration,
      current: _pipelineGeneration,
      mounted: mounted,
      conversationActive: _isConversationActive,
    )) {
      return;
    }
    if (_turnCounter == 0 && mounted) {
      setState(() => _localMessages
          .removeWhere((message) => message['seed_guide'] == true));
    }
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
        _heardConfirmationAttempts = 0;
        _log('[HEARD-CONFIRM]', 'affirmed → 보류 발화 재개');
        return _processRelayPipeline(
          pendingHeard,
          isCorrectionRetry: isCorrectionRetry,
          understandingConfirmed: true,
          expectedPipelineGeneration: pipelineGeneration,
        );
      }
      if (bareNegatives.contains(reply)) {
        _heardConfirmationAttempts = 0;
        _log('[HEARD-CONFIRM]', 'denied_without_correction → 재청취');
        await _speakStepRetryAndListen();
        return;
      }
      _log('[HEARD-CONFIRM]', 'corrected_with_content → 새 발화 판정');
    }
    _logProbeTiming('PIPELINE_START');
    resetBillingIdle();
    // 🌱 [SEED-PHASE] 폴백 통로에서도 규칙은 같다 — 씨앗을 찾기 전까지는
    //   잡담이고, 화면에도 히스토리에도 아무것도 적지 않는다. 턴도 안 먹는다.
    if (!_seedFound) {
      final seed = await _runSmallTalkTurn(
        finalTranscript.trim(),
        generation: pipelineGeneration,
      );
      if (!mounted || pipelineGeneration != _pipelineGeneration) return;
      if (seed == null) return;
      _seedFound = true;
      finalTranscript = seed;
    }
    _turnCounter++;
    final int currentTurnId = _turnCounter;
    _log('🧠 [PIPE-01]',
        'Pipeline 시작 turn=$_turnCounter input_len=${finalTranscript.length}');
    // 🎧 [STT-RAW] 전사 원문. 이게 없으면 오역이 났을 때 "잘못 들은 것"인지
    //   "제대로 듣고 번역이 튄 것"인지 가릴 수가 없다. 화면 한국어 자막은
    //   영어 번역문을 되돌린 것이라 원문 대조에 쓸 수 없다. 실측은 이 로그
    //   하나에 걸려 있다 — 길이만 찍던 동안은 오인식 원인을 못 짚었다.
    //   유저 발화 내용이므로 디버그 빌드에서만 남긴다.
    if (kDebugMode) {
      _log('🎧 [STT-RAW]', 'source=selected text="$finalTranscript"');
    }

    // ─────────────────────────────────────────────────────
    // STEP 1: 증발 검열 (UI 풍선 찍기 전)
    // ─────────────────────────────────────────────────────
    // [GHOST-EXACT] 통째로 추임새/고스트워드일 때만 증발시킨다. 부분 일치로
    //   판정하면 그 단어를 품은 정상 문장까지 사라진다. 판정 기준은
    //   _isNoiseTranscript 하나로 모은다 — 여기 목록을 따로 두었더니 "음."이
    //   빠져나가 "Um."으로 번역됐다(Anyone에서 발생).
    final bool isGhost = _isNoiseTranscript(finalTranscript);

    if (isGhost) {
      if (_turnCounter == currentTurnId && _turnCounter > 0) _turnCounter--;
      if (mounted)
        setState(
            () => _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP'));
      if (_isConversationActive) _startUserListening();
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

    // 🔧 [FAST-LANE] 실제 이전 AI 질문이 있을 때만 질문 불만으로 처리한다.
    // 첫 발화는 어떤 내용이든 씨앗 문장 생성이 우선이다.
    final hasPriorAiQuestion = _localMessages.any((message) {
      if (message['role'] != 'SYSTEM') return false;
      final target = (message['target'] ?? '').toString().trim();
      return target.isNotEmpty && target != '...';
    });
    if (shouldRunStepQuestionDissatisfactionFastLane(
      hasPriorAiQuestion: hasPriorAiQuestion,
      rawDissatisfactionMatch: _isQuestionDissatisfactionRaw(finalTranscript),
    )) {
      _log('🟠 [FAST-DISSATISFIED]', '로컬 fast-lane 감지');
      _turnCounter--; // 불만 발화는 학습 턴 미적용
      if (mounted) {
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
      // ─────────────────────────────────────────────────────
      // STEP 2: HOST 풍선 생성 + 유저 번역 스트리밍
      // ─────────────────────────────────────────────────────
      if (mounted) {
        setState(() {
          _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
          _localMessages.add({
            'role': 'HOST',
            'target': '',
            // 유저가 실제로 말한 한국어를 그대로 보존한다. 번역문을 다시
            // 한국어로 역번역하면 말투와 의미가 달라질 수 있다.
            'original': finalTranscript.trim(),
            'turnId': currentTurnId
          });
        });
        _scrollToBottom();
      }

      int hostIndex = _localMessages.length - 1;

      final pipeResult = _buildCleanContext(maxMessages: 10);
      String contextStr = pipeResult['contextStr']!;

      String userTargetText = "";
      // 대화방에서는 유저의 한국어 원음을 그대로 듣고 영어 TTS는 만들지 않는다.
      _ttsQueueManager.setUserTurn(false);
      _ttsQueueManager.setAiPaused(false);

      // 🌐 [v3.1] 로비에서 유저가 선택한 타겟 언어로 번역
      final String targetLangName = FFAppState().targetLang.isNotEmpty
          ? FFAppState().targetLang
          : 'English';

      // 🚀 [SPEC-FIRST-TURN] 투기 번역이 넘어오면 그 버퍼 스트림을 그대로 소비한다
      //   (선반영). 없으면 지금 새로 요청. 소비 방식은 완전히 동일.
      final userStream = userStreamOverride ??
          StepExpandBrain.streamUserTranslation(
            apiKey: _openAiKey,
            textOriginal: finalTranscript,
            originLang: _nativeLangName(),
            targetLang: targetLangName,
            contextStr: contextStr,
            disableCorrection: isCorrectionRetry,
            disableHeardConfirmation: understandingConfirmed,
            model: kStepExpandUserModel,
          );

      // 첫 턴은 영어 씨앗 문장, 2턴부터는 "새 영어 문장\n\n누적 확장문장"을
      // 화면과 히스토리에 남긴다. 어느 쪽도 대화방에서는 낭독하지 않는다.
      bool evaporated = false;
      bool retried = false;
      bool corrected = false; // 유저가 AI의 오해를 정정하는 경우 → 직전 HOST+SYSTEM 쌍 삭제 후 재시작
      bool misheard = false; // 잘못 들었다는 불만만 있음 → 직전 교환 삭제 후 재질문
      bool clarified = false; // 주어/목적어 모호 → AI 되묻기
      bool heardConfirmation = false; // 특정 단어 오청취 가능성 → 사용자 확인
      bool restated = false; // 오프토픽이지만 스피킹 내용 그대로 음성 확인 질문 후 재청취
      bool garbled = false; // 진짜 발음 불확실 → "다시 말해 주세요" 요청
      bool dissatisfied = false; // [DISSATISFIED] 유저가 AI 질문에 불만 → 확인 후 재질문
      bool hasDoubleNewline = false; // 2파트 구조 여부

      await for (String chunk in userStream) {
        userTargetText += chunk;

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

        // [DISSATISFIED] 유저가 AI 질문에 불만 표시
        if (userTargetText.contains("[DISSATISFIED]")) {
          dissatisfied = true;
          _log('🟠 [DISSATISFIED]', '질문 불만 감지 → 즉시 다른 질문 생성');
          break;
        }

        // 정정 감지: 유저가 AI의 오해를 바로잡는 경우
        // → 직전 HOST(오해된 유저 발화) + SYSTEM(잘못된 AI 응답) 삭제 후 정정 발화로 재시작
        if (!isCorrectionRetry && userTargetText.contains("[CORRECTION]")) {
          corrected = true;
          _log('🔄 [CORRECTION]', '정정 감지 → 직전 HOST+SYSTEM 삭제 후 재시작');
          break;
        }

        // [MISHEARD] 잘못 들었다는 불만만 있음 → 직전 교환 삭제 후 재질문
        if (!isCorrectionRetry && userTargetText.contains("[MISHEARD]")) {
          misheard = true;
          _log('👂 [MISHEARD]', '오청취 불만 감지 → 직전 교환 삭제 후 재질문');
          break;
        }

        // 되묻기 감지: 주어/목적어 모호 → AI 되묻기
        if (!clarified && userTargetText.contains("[CLARIFY]")) {
          clarified = true;
          _log('❓ [CLARIFY]', '되묻기 감지 → 스트림 완료 후 처리 예정');
        }
        if (!heardConfirmation && hasHeardConfirmSignal(userTargetText)) {
          heardConfirmation = true;
          _log('[HEARD-CONFIRM]', '단어 확인 필요');
        }

        // 다시 말하기 감지: [RESTATE]=오프토픽 / GARBLED=진짜 안 들림
        // RESTATE는 간단 안내 후 재청취(문맥 확인 루프 제거)
        if (userTargetText.contains("[RESTATE]")) {
          restated = true;
          _log('🔁 [RESTATE]', '맥락 불일치 → 간단 안내 후 재청취');
          break;
        }
        if (userTargetText.contains("[GARBLED]")) {
          garbled = true;
          _log('👂 [GARBLED]', '발음 불확실 → 다시 말하기 요청');
          break;
        }

        if (mounted &&
            !clarified &&
            !heardConfirmation &&
            !isHeardConfirmSignalPrefix(userTargetText) &&
            hostIndex < _localMessages.length) {
          setState(() => _localMessages[hostIndex]['target'] = userTargetText);
        }
        _scrollToCurrentTop(hostIndex);

        // 🌱 \n\n 최초 감지: Part2는 누적 확장문장이다.
        if (!hasDoubleNewline && userTargetText.contains('\n\n')) {
          // 첫 턴(turn 1)에선 확장이 없다. Part2가 왔다면 모델이 지어낸 것이므로
          // Part1(씨앗 문장)만 남기고 잘라낸다.
          if (currentTurnId == 1) {
            final idx = userTargetText.indexOf('\n\n');
            userTargetText = userTargetText.substring(0, idx).trim();
            if (mounted && hostIndex < _localMessages.length)
              setState(
                  () => _localMessages[hostIndex]['target'] = userTargetText);
            break;
          }
          hasDoubleNewline = true;
          _log('🌱 [PART2-START]', 'Part2 감지 → 누적 확장문장 화면/저장');
          continue;
        }
      }

      if (evaporated) {
        final bool wasSeedAttempt = currentTurnId == 1;
        if (_turnCounter == currentTurnId && _turnCounter > 0) {
          _turnCounter--;
        }
        if (mounted) {
          setState(() {
            if (hostIndex < _localMessages.length) {
              _localMessages.removeAt(hostIndex);
            }
          });
        }
        if (_isConversationActive && wasSeedAttempt && _turnCounter == 0) {
          await _askForUsableSeedSentence(
            finalTranscript,
            generation: pipelineGeneration,
          );
        } else if (_isConversationActive) {
          _startUserListening();
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

      // [DISSATISFIED] 유저가 질문 내용에 불만 → 안내 멘트 없이 즉시 다른 질문 생성
      if (dissatisfied) {
        _turnCounter--; // 불만 발화 턴 카운트 취소
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
        // 정정된 발화로 해당 턴 재처리 (재진입이므로 [CORRECTION] 재감지 안 함)
        await _deleteLastExchangeFromHistory();
        _processRelayPipeline(
          finalTranscript,
          isCorrectionRetry: true,
          expectedPipelineGeneration: pipelineGeneration,
        );
        return;
      }

      // 👂 [MISHEARD] 유저가 "잘못 들었다"는 불만만 말함 (정정 내용 없음)
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
          await _deleteLastExchangeFromHistory();
          await _handleRetryQuestion(contextStr, targetLangName,
              isMisheard: true);
          return;
        }
        _turnCounter -= 2; // 현재 불만 턴 + 이전 오청취 턴 카운트 취소
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
        await _handleRetryQuestion(cleanContextStr, targetLangName,
            isMisheard: true);
        return;
      }

      // ❓ [CLARIFY] 유저 발화 주어/목적어 모호 → AI 되묻기 버블 + TTS + STT 재시작
      if (clarified) {
        await _deleteLastExchangeFromHistory();
        _turnCounter--;
        final clarifyText =
            userTargetText.replaceFirst(RegExp(r'^\[CLARIFY\]\s*'), '');
        final clarifyKorean = await StepExpandBrain.generateCleanOriginal(
          apiKey: _openAiKey,
          englishText: clarifyText,
        );
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length)
              _localMessages.removeAt(hostIndex);
            _localMessages.add({
              'role': 'SYSTEM',
              'target': clarifyText,
              'original': clarifyKorean,
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
          _aiVoice,
          language: _nativeLangCode(),
          cacheEnabled: false,
          isUser: false,
          onLog: _log,
        );
        clarifyTts.addText(clarifyKorean);
        int waitTicks = 0;
        while ((clarifyTts.pendingRequests > 0 || _ttsQueueManager.isBusy) &&
            mounted) {
          await Future.delayed(const Duration(milliseconds: 50));
          if (++waitTicks > 200) break;
        }
        if (mounted && _isConversationActive) _startUserListening();
        return;
      }

      if (heardConfirmation) {
        await _deleteLastExchangeFromHistory();
        _turnCounter--;
        final spokenPrompt = stripHeardConfirmSignal(userTargetText)
            .replaceAll(RegExp(r'[\r\n]+'), ' ');
        _pendingHeardConfirmation = finalTranscript.trim();
        _heardConfirmationAttempts++;
        final tooManyAttempts = _heardConfirmationAttempts > 2 ||
            _pendingHeardConfirmation!.isEmpty ||
            spokenPrompt.isEmpty;
        final prompt =
            tooManyAttempts ? originRetryLine(_nativeLangName()) : spokenPrompt;
        final promptTarget = prompt;
        if (tooManyAttempts) {
          _pendingHeardConfirmation = null;
          _heardConfirmationAttempts = 0;
        }
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length) {
              _localMessages.removeAt(hostIndex);
            }
            _localMessages.add({
              'role': 'SYSTEM',
              'target': promptTarget,
              'original': prompt,
              'clarify': true,
            });
          });
          _scrollToBottom();
        }
        _ttsQueueManager.setUserTurn(false);
        _ttsQueueManager.setAiPaused(false);
        final confirmTts = ChunkedTtsFetcher(
          _openAiKey,
          _ttsQueueManager,
          _aiVoice,
          language: _nativeLangCode(),
          cacheEnabled: false,
          isUser: false,
          onLog: _log,
        );
        confirmTts.addText(prompt);
        int ticks = 0;
        while ((confirmTts.pendingRequests > 0 || _ttsQueueManager.isBusy) &&
            mounted) {
          await Future.delayed(const Duration(milliseconds: 50));
          if (++ticks > 200) break;
        }
        if (mounted && _isConversationActive) await _startUserListening();
        return;
      }

      // 🔁 RESTATE/GARBLED AI 질문은 그대로 두고 재청취
      //   - GARBLED 진짜 안 들림 → "다시 말해 주세요" (2회 연속이면 더 쉬운 문장 유도)
      //   - RESTATE 오프토픽 → "질문에 맞게 다시 말해 주세요" (문맥 확인 없이 동일 패턴)
      //   - 턴 카운터 원복(이번 시도 무효 → 다음 발화가 같은 턴으로 재진입)
      //   - 방금 만든 빈 HOST 버블만 제거. 이전의 좋은 맥락(SYSTEM 질문 포함)은 절대 삭제 안 함
      if (restated || garbled) {
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
          checkPhrase = "조금 더 짧고 쉬운 문장으로 말해 주실래요?";
        } else if (restated) {
          checkPhrase = "질문에 맞게 다시 말해 주세요.";
        } else {
          checkPhrase = "잘 안 들렸어요. 다시 말해 주세요.";
        }
        _ttsQueueManager.setUserTurn(false);
        _ttsQueueManager.setAiPaused(false);
        final restateTts = ChunkedTtsFetcher(
          _openAiKey,
          _ttsQueueManager,
          _aiVoice,
          language: _nativeLangCode(),
          cacheEnabled: false,
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
        // 같은 AI 질문 그대로 유지 → 질문 재생성 없이 STT만 재시작
        if (mounted && _isConversationActive) _startUserListening();
        return;
      }

      // ✅ 정상 발화 통과 → 연속 GARBLED 카운터 초기화
      _consecutiveRestateCount = 0;
      _heardConfirmationAttempts = 0;

      // 화면에는 영어 번역을 남기되, 대화방에서 영어 음성은 재생하지 않는다.
      // 한국어 원문은 STT 결과를 그대로 사용하고 한·영 모두 히스토리에 저장한다.
      _revealForReading(hostIndex, userTargetText);

      // ─────────────────────────────────────────────────────
      // 🌱 [StepExpand] 5턴 완료 조기 종료
      // 5번째 유저 답변이 _localMessages에 추가된 직후 체크
      // → AI 응답을 생성하지 않고 결과 버튼 바로 표시
      // ─────────────────────────────────────────────────────
      if (_turnCounter >= MAX_TURNS) {
        // Firestore 저장 (유저 턴만, AI 응답 없음)
        // 🔧 [PRACTICE-FIX] _localMessages[hostIndex]['target']은 Part1\n\nPart2 형태로 누적됨
        //    → Part2(expanded)를 expanded_sentence 필드로 별도 추출 저장 (옵션 B, 후방호환)
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

        // 대화방에서는 영어 문장을 읽지 않지만, P3의 두 연습 선택지가 모두
        // 준비되도록 Polished Sentence를 종료 전에 생성해 히스토리에 저장한다.
        // P3 학습식은 expanded_sentence, 원어민식은 polished_sentence를 사용한다.
        final Future<void> preparePolished = () async {
          if (hostExpanded.isEmpty) return;
          final polished = await StepExpandBrain.polishSentence(
            apiKey: _openAiKey,
            originalSentence: hostExpanded,
          );
          if (polished.trim().isNotEmpty) {
            await _savePolishedToFirestore(polished.trim());
          }
        }();

        const completionTarget =
            'Your expanded sentence is complete. You can practice it in the Study Room.';
        const completionKorean = '확장 문장이 완성되었습니다. 공부방에서 연습하실 수 있습니다.';
        if (mounted) {
          setState(() {
            _isSessionComplete = true;
            _localMessages.add({
              'role': 'SYSTEM',
              'target': completionTarget,
              'original': completionKorean,
            });
            _debugResult = "🎉 5턴 완료!";
          });
          _scrollToBottom();
        }
        final completionLine = {
          'role': 'SYSTEM',
          'original_text': completionKorean,
          'translated_text': completionTarget,
        };
        await _saveTurnToFirestore([completionLine]);
        await _saveHistoryMessages([completionLine]);

        _log('🌱 [DONE]', '5턴 완료 → 한국어 안내 후 스텔스 룸 자동 복귀');
        await Future.wait([
          _speakLiveKorean(completionKorean),
          preparePolished,
        ]);
        _stopEverything();
        await _handleAutoSaveAndExit();
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
      // Step Expand AI 목소리는 Marin으로 통일한다.
      ChunkedTtsFetcher aiTtsFetcher = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        _aiVoice,
        language: _nativeLangCode(),
        cacheEnabled: false, // 실시간 한국어 음성은 히스토리 영어 캐시에 남기지 않음
        isUser: false, // AI 큐로 분리
        onLog: _log,
      );

      String latestContextStr = contextStr.isEmpty
          ? "User: $userTargetText"
          : "$contextStr\nUser: $userTargetText";
      String aiTargetText = "";
      String aiOriginalText = "";
      bool aiHasDoubleNewline = false;
      final HybridTtsPlayer aiHybridTts = HybridTtsPlayer(
        apiKey: _openAiKey,
        voice: _aiVoice,
        onLog: _log,
      );

      _swOpenAI.reset();
      _swOpenAI.start();
      _swTTS.reset();

      _log('🧠 [PIPE-02]', 'AI 스트림 요청: userText="$userTargetText"');
      _logProbeTiming('AI_REQUEST');
      _awaitingAiFirstTextProbe = true;

      final aiStream = StepExpandBrain.streamGrammarQuestion(
        apiKey: _openAiKey,
        contextStr: latestContextStr,
        turnNumber: _turnCounter,
        maxTurns: MAX_TURNS,
        myTarget: targetLangName, // 🌐 [v3.1] 유저가 선택한 타겟 언어
        originLang: _nativeLangName(),
        userId: FirebaseAuth.instance.currentUser?.uid ?? '',
      );

      // AI 생성+청킹을 Future로 (유저 재생과 병렬)
      bool _firstAiChunkLogged = false;
      final Future<void> aiGenerationTask = () async {
        await for (String chunk in aiStream) {
          if (_awaitingAiFirstTextProbe && chunk.trim().isNotEmpty) {
            _awaitingAiFirstTextProbe = false;
            _logProbeTiming('AI_FIRST_TEXT');
          }
          if (!_firstAiChunkLogged) {
            _log('🧠 [PIPE-03]', 'GPT 첫 청크 수신');
            _firstAiChunkLogged = true;
          }
          if (_swOpenAI.isRunning) _swOpenAI.stop();

          if (!aiHasDoubleNewline) {
            // Part1 (영어): 화면 표시와 히스토리 저장용으로만 누적한다.
            aiTargetText += chunk;

            if (aiTargetText.contains('\n\n')) {
              // \n\n 감지: Part1 끝, Part2(한국어) 시작
              aiHasDoubleNewline = true;
              final sepIdx = aiTargetText.indexOf('\n\n');
              final afterSep = aiTargetText.substring(sepIdx + 2);
              aiTargetText = aiTargetText.substring(0, sepIdx);
              if (afterSep.isNotEmpty) aiOriginalText += afterSep;
            }
          } else {
            // Part2 (한국어): 실제 대화방에서 Marin이 말할 문장이다.
            aiOriginalText += chunk;
          }

          // 텍스트는 AI 소리 시작 시점(setAiPaused=false)에 일괄 표시
        }
        if (StepExpandBrain.needsShortKoreanQuestionRewrite(aiOriginalText)) {
          final beforeRewrite = aiOriginalText.trim();
          aiOriginalText = await StepExpandBrain.rewriteToShortKoreanQuestion(
            apiKey: _openAiKey,
            text: beforeRewrite,
          );
          _log('🛡️ [AI-LENGTH-GUARD]',
              'path=normal before="$beforeRewrite" after="$aiOriginalText"');
        } else if (StepExpandBrain.needsNaturalPoliteRewrite(aiOriginalText)) {
          final beforeRewrite = aiOriginalText.trim();
          aiOriginalText = await StepExpandBrain.rewriteToNaturalPoliteKorean(
            apiKey: _openAiKey,
            text: beforeRewrite,
          );
          _log('🛡️ [AI-REGISTER-GUARD]',
              'path=normal before="$beforeRewrite" after="$aiOriginalText"');
        }
        // 스트림이 끝나면 한국어만 tts-1/nova로 한 번 읽는다.
        // cacheEnabled=false이므로 이 음성은 대화방을 나가면 폐기된다.
        _swTTS
          ..reset()
          ..start();
        await aiHybridTts.speakWholeSentence(
          fullSentence: aiOriginalText.trim(),
          fetcher: aiTtsFetcher,
          swSpeechEnd: _swTTS,
        );
      }();

      // ─────────────────────────────────────────────────────
      // STEP 5: 유저의 실제 한국어 발화 뒤에 짧게 쉬고 AI 한국어 큐 개방
      // ─────────────────────────────────────────────────────
      await Future.delayed(const Duration(milliseconds: 350));
      _log('🧠 [PIPE-GAP]', '유저-AI 전환 안전 간격 350ms 완료');

      // 턴 전환
      _ttsQueueManager.setUserTurn(false);
      _awaitingAiFirstAudioProbe = true;
      _ttsQueueManager.setAiPaused(false);
      _log('🧠 [PIPE-07]', 'setUserTurn(false) + setAiPaused(false). AI 재생 시작');
      // AI 소리 시작과 동시에 지금까지 쌓인 텍스트 즉시 표시
      if (mounted && aiIndex < _localMessages.length) {
        setState(() {
          _localMessages[aiIndex]['target'] = aiTargetText;
          _localMessages[aiIndex]['original'] = aiOriginalText;
        });
        _revealForReading(aiIndex, aiTargetText); // 🆕 긴 대사 텔레프롬프터
      }
      // Part1 영어는 화면/히스토리용, Part2 한국어는 실시간 대화용이다.

      await aiGenerationTask;
      // 스트리밍이 아직 진행 중이었다면 최종 텍스트 반영
      if (mounted && aiIndex < _localMessages.length) {
        setState(() {
          _localMessages[aiIndex]['target'] = aiTargetText;
          _localMessages[aiIndex]['original'] = aiOriginalText;
        });
        _revealForReading(aiIndex, aiTargetText); // 🆕 긴 대사 텔레프롬프터
      }
      _log('🧠 [PIPE-08]',
          'aiGenerationTask 완료. AI pending=${aiTtsFetcher.pendingRequests}');

      int waitTicks = 0;
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
      // 유저 원문은 STT로 받은 한국어를 그대로 저장한다.
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
          [hostLine, systemLine]); // 🔧 [히스토리] 병행 저장 (await 보장)
      _log('🧠 [PIPE-10]', 'Firestore 저장 완료');
    } catch (e) {
      _log('❌ [PIPE-ERR]', 'Relay Error: $e');
    } finally {
      _log('🧠 [PIPE-END]',
          'finally 진입. active=$_isConversationActive turn=$_turnCounter/current=$currentTurnId mounted=$mounted');
      if (mounted && _isConversationActive && _turnCounter == currentTurnId) {
        _log('🧠 [PIPE-RESTART]', '마이크 재시작 시도');
        _startUserListening();
      } else {
        _log('⚠️ [PIPE-NORESTART]', '마이크 재시작 조건 불충족');
      }
    }
  }

  // Step Expand HOST 저장 payload를 sessions/chat_history에서 동일하게 유지한다.
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
            IconButton(
              icon: CustomPaint(
                size: const Size(26, 26),
                painter: _LangIconPainter(active: _showOriginal),
              ),
              onPressed: () => setState(() => _showOriginal = !_showOriginal),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
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
        // ElevatedButton.icon 대신 직접 조립한다. 글꼴 배율이 큰 기기에서
        // 라벨이 버튼 폭을 넘겨 화면이 깨졌는데, Flexible로 감싸야 줄바꿈이
        // 되기 때문이다. 가로 여백도 28→18로 줄여 한 줄이 버티는 폭을 넓혔다.
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1F2937),
            side: const BorderSide(color: Color(0xFFFBBF24), width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          onPressed: _isPolishing ? null : _polishSentenceInline,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _isPolishing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, color: Color(0xFFFBBF24)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _isPolishing ? "Polishing..." : "✨ Polished Version",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestNewButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Center(
        // 위 Polished 버튼과 같은 이유로 직접 조립한다.
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF9333EA),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          onPressed: _suggestNewSentence,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh_rounded, color: Colors.white),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  "Suggest New Sentence",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ],
          ),
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
          // 헤더 글자는 시스템 글꼴 배율을 그대로 탄다. 실기기(font_scale 1.7,
          // 밀도 540)에서 이 줄이 카드 폭을 넘어 화면이 깨졌다. Flexible로
          // 감싸 줄바꿈을 허용한다 — 잘라내면 무슨 카드인지 안 보인다.
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.check_circle_outline,
                    color: Color(0xFF60A5FA), size: 15),
              ),
              SizedBox(width: 6),
              Flexible(
                child: Text("✅ Completed Sentence",
                    style: TextStyle(
                        color: Color(0xFF60A5FA),
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ),
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
          // 완성문장 카드와 같은 이유로 감싼다.
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.auto_awesome,
                    color: Color(0xFFFBBF24), size: 15),
              ),
              SizedBox(width: 6),
              Flexible(
                child: Text("Polished Sentence",
                    style: TextStyle(
                        color: Color(0xFFFBBF24),
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ),
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

    // 🌱 [PART1-HIDE] 2턴+ 유저 버블은 확장문장(Part2)만 화면에 표시한다.
    //   - Part1(짧은 대답)과 Part1 한국어는 화면에서 숨긴다 (히스토리 저장값은 그대로).
    //   - 스트리밍 중 Part1만 들어온 구간(아직 \n\n 미도착)은 '...' placeholder만 노출.
    //   - turnId 우선 판단(스트리밍 깜빡임 방지), 없으면 파트 수로 후방호환.
    final int turnId = (msg['turnId'] is int) ? msg['turnId'] as int : 0;
    final bool isExpandTurn =
        role == 'HOST' && (turnId >= 2 || targetParts.length >= 2);

    final String effectiveOriginal = role == 'HOST_TEMP' ? '' : originalRaw;

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
              // 🌱 [PART1-HIDE] Part2(확장문장)만 표시. Part2 미도착 시 '...' placeholder.
              //   한국어는 표시하지 않는다 (Part2에는 원래 한국어가 없음).
              Text(
                  targetParts.length >= 2
                      ? targetParts.sublist(1).join('\n\n').trim()
                      : '...',
                  textAlign: isHost ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16 * _fontScale,
                      fontWeight: FontWeight.bold)),
              if (_showOriginal && originalRaw.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  originalRaw,
                  textAlign: isHost ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 10 * _fontScale,
                  ),
                ),
              ],
            ] else ...[
              Text(displayTarget,
                  textAlign: isHost ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16 * _fontScale,
                      fontWeight: FontWeight.bold)),
              if (_showOriginal &&
                  // ORIGIN과 TARGET이 같으면 원문 줄이 배울글과 똑같아진다.
                  // 세션에서 확정된 ORIGIN으로 봐야 한다 — 로비값과 다를 수 있다.
                  _nativeLangName() != FFAppState().targetLang &&
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
    this.failure = StepExpandMergeFailure.none,
  });

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
- Output [DISSATISFIED] only when History contains an AI question and the user expresses dissatisfaction, complaint, or rejection about that QUESTION itself (not about the topic). Signs: "다른 질문 해줘" / "그 질문 싫어" / "질문 바꿔" / "무슨 질문이 그래" / "별로야" / "그건 좀" / "다른 거 물어봐" / "change the question" / "ask something else" / "I don't like that question". MILD signs ALSO count: "별로" / "별론데" / "아 그건 좀" / "에이" / "그런 거 말고" / "그건 없어" / "재미없어" / "이상하네" / "뭐야 그게" / "meh" / "not really" / "hmm, not that one". REPETITION COMPLAINT signs ALSO count: "아까 말했잖아" / "이미 대답했잖아" / "방금 말했는데" / "이미 얘기했어" / "똑같은 질문" / "같은 걸 또" / "already said" / "already answered" / "I already told you". Even slight or indirect displeasure aimed at the QUESTION itself counts. Do NOT output [DISSATISFIED] when History is empty or when the user is simply answering negatively (e.g., "아니, 안 갔어" = a valid negative answer).""";

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
  // 📦 [TURN] 매 턴 AI 질문 — gpt-4o-mini가 한국어로 만든다.
  // ------------------------------------------------------------------
  // Realtime이 만들던 자리다. 한두 문장짜리 짧은 말이라 스트리밍 없이 통째로
  // 받는다. 소리는 호출부가 TTS로 낸다.
  // ==================================================================
  static Future<String> generateKoreanTurn({
    required String apiKey,
    required String instructions,
    required String userText,
    // 자란 문장만 주면 모델은 자기가 앞서 무엇을 물었는지 모른다. 그래서
    // "어떤 활동을 해보고 싶으세요?"를 1턴과 3턴에 그대로 다시 물었다(실측).
    // 지나간 대화를 같이 줘야 [ONE THREAD]와 반복 금지가 실제로 지켜진다.
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
              'model': 'gpt-4o-mini',
              'temperature': 0.7,
              'max_tokens': 160,
              'messages': [
                {'role': 'system', 'content': instructions},
                {
                  'role': 'user',
                  'content': recentConversation.trim().isEmpty
                      ? userText
                      : '[CONVERSATION SO FAR]\n${recentConversation.trim()}\n\n'
                          '[THE SENTENCE THEY HAVE BUILT]\n$userText',
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
  // 📦 [OPENING] 진입 첫 마디 — gpt-4o-mini가 만든다.
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
    final String newsBlock =
        headlines.take(5).map((h) => '- $h').join(String.fromCharCode(10));
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
              'max_tokens': 60,
              'messages': [
                {
                  'role': 'system',
                  'content': headlines.isEmpty
                      ? '''You start a light, friendly conversation in $languageName by speaking first.
Say ONE short, warm line about an easy everyday topic — the weather, the season, weekends, food, feeling busy — and end it with one small question.
It must be answerable in a few words by someone who is quiet or still gathering their thoughts.
Never ask a yes/no question. Never mention English, practice, study, sentences, AI, or how this works.
No greeting, no preamble, no explanation, no emoji.
Use a natural everyday polite spoken register in $languageName, one or two short sentences only.
Return only the line.'''
                      : '''You start a light, friendly conversation in $languageName by speaking first.
Here is what the news is saying right now:
$newsBlock

Pick ONE of those items that an ordinary person would casually bring up, mention it in one short, plain line, and end with one small question asking how they feel about it or whether they heard about it.
State nothing beyond what the headline itself says — do not add numbers, names, causes, or outcomes of your own.
Keep it light. Avoid anything grim, political, or upsetting; if every item is like that, drop the news and open with an easy everyday topic instead.
The question must be answerable in a few words. Never ask a yes/no question.
Never mention English, practice, study, sentences, AI, or how this works. No greeting, no preamble, no emoji.
Use a natural everyday polite spoken register in $languageName, two short sentences at most.
Return only the line.'''
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
  }) async {
    const empty = <String, String>{'reply': '', 'seed': ''};
    if (apiKey.isEmpty || userText.trim().isEmpty) return empty;
    final String newsBlock = headlines.isEmpty
        ? ''
        : 'Headlines you may keep chatting about:'
            '${String.fromCharCode(10)}'
            '${headlines.take(5).map((h) => '- $h').join(String.fromCharCode(10))}'
            '${String.fromCharCode(10)}';
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
              'temperature': 0.7,
              'max_tokens': 220,
              'response_format': {'type': 'json_object'},
              'messages': [
                {
                  'role': 'system',
                  'content':
                      """You are a friendly person making easy conversation in $languageName. Two jobs, one answer.

[WHO YOU ARE]
Someone chatting, nothing more. Not a teacher, not an assistant, not an interviewer.
Never mention practice, study, sentences, learning, AI, or how any of this works. Never explain yourself.

$newsBlock
[JOB 1 — REPLY: what you say out loud this turn]
- One short, genuine reaction to what they just said, then one small question that keeps the talk going.
- React to the content the way a friend would. Not praise, not a summary, not their own words handed back.
- Never a yes/no question. Two short sentences at most. No greeting, no preamble, no emoji, no advice, no teaching.
- Everyday polite spoken register of $languageName.
- Stay on the thread they are on. Move to something else only when theirs has clearly run out.
- If news is listed above, you may bring up ONE item an ordinary person would casually mention. Say only what the headline itself says — never add numbers, names, causes, or outcomes of your own. Keep it light, and drop it the moment they are not interested.

[JOB 2 — SEED: chosen silently, never announced]
Somewhere in this conversation they will say something a longer sentence can grow out of. Your second job is to notice it.
They must never learn you are looking: do not announce it, do not ask permission, do not comment on their wording.
Usable: ONE complete statement about their own concrete action, plan, experience, thought, or feeling.
Not usable: a question, a bare yes/no or backchannel, a fragment, a remark about this app or this conversation, or anything you had to guess at.
When usable, write it as ONE short, natural, well-formed $languageName sentence in their own words, viewpoint, tense, and register. Keep their content exactly. Repair only broken grammar and words the recognizer clearly got wrong. Never add a fact, name, place, time, reason, or feeling they did not say.
Every word of that sentence must make sense in the conversation you two just had. If one does not, you have not recovered it — return an empty seed.

[YOU ARE READING SPEECH RECOGNITION, NOT TYPED TEXT]
Their line was produced by speech recognition, so a word can come out as a different word that merely sounds similar. You never hear the audio.
What the two of you are talking about is the authority on meaning — not the letters in front of you.
If a word makes no sense in that topic but is close in sound to one that fits it naturally, they said the fitting one. Read it that way, silently, in both your reply and the seed.
Never build on a word that contradicts the topic just because the text says so. That is how a conversation goes wrong and never recovers.

[THERE IS NO HURRY]
The sentence work can begin anywhere in this conversation. The tenth turn is as good as the second, and there is no limit on how long you may chat.
A seed built on a line you were unsure of ruins everything that comes after it. Waiting costs nothing; guessing costs the whole session.
So when their line is odd, or a word does not fit, or you simply are not sure: ask about that very point again, as a curious listener would, and let them say it in their own words.
Ask about the content. Never say you did not hear them, never ask them to repeat, never mention recognition, text, or anything technical. Come at the same point from a slightly different angle so answering feels like conversation, not correction.
Only once their meaning is clear do you turn it into a seed.
Do not force it — a natural conversation matters more than an early seed. If nothing has fit after several turns, steer gently toward what they did today, what they plan to do, or how they felt.

[OUTPUT]
Return only JSON: {"reply":"<what you say out loud>","seed":"<one sentence, or empty string>"}
"reply" is always filled. "seed" stays empty unless you are sure."""
                },
                {
                  'role': 'user',
                  'content': 'Conversation so far:'
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
        'seed': (parsed['seed'] ?? '').toString().trim(),
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
    required String originLang,
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

      // ── 문법 구조 로테이션 (soft lens, 4턴 순환) ─────────────────────
      final int t4 = turnNumber % 4;
      final String structureSeed = t4 == 1
          ? 'coordination (and / and then / so)'
          : t4 == 2
              ? 'contrast or result (but / so / which is why)'
              : t4 == 3
                  ? 'short reason link (because / since — never nested)'
                  : 'a light spoken add-on (like / you know — only if natural)';

      // ── 3단계 (최종 합성): 파편화된 답변 → Expanded Sentence ──────────────
      // ── 2단계 (문법 유도형 질문): 5-8단어 초단형, 구조를 이름 짓지 않고 유도 ──
      final String sysPrompt = isFinalTurn
          ? """You are a Step Expand grammar coach.
This is the FINAL turn ($turnNumber of $maxTurns). The user has answered your grammar-inducing questions step by step.

[YOUR JOB — Synthesis]
Read the History carefully. Collect the user's fragmented answers and synthesize them into ONE fluent, natural-SPOKEN sentence — the way an American would actually say it OUT LOUD, chained linearly (left to right), NOT packed with nested clauses. Build it mainly with these linear connectors (use at least 2, and vary them):
- Coordination: and / and then / so / but
- Result or reason: which is why / that's why / so that / because (kept short, never nested)
- Optionally ONE soft spoken marker if it fits: like / you know / I mean
TRAILING relative clauses are fine and linear — a sentence-final, comma-led "who / which" (e.g. "...to call my friend Alex, who just moved to London") works just like "and he/it...", so keep using them. AVOID only CENTER-EMBEDDED relative clauses that split a subject from its verb, front participial phrases, and chains of to-infinitives.

[RULES]
- The user's lines in History may contain speech recognition errors due to unclear pronunciation. Infer the most likely intended meaning from context — do not quote garbled words literally.
- Reflect the user's intended meaning. Do not invent new facts beyond reasonable inference.
- Fluent, natural spoken $myTarget — not overly academic.
- Keep the sentence 25–40 words.
- Each meaning unit should be speakable in one breath, usually 5–7 words.
- Use commas or natural connectors to make breath groups clear.
- Do not create a sentence with one very long clause.
- Label the sentence with "Expanded Sentence:" prefix.

[OUTPUT FORMAT - STRICT]
Output EXACTLY two parts separated by ONE empty line.
PART 1: "Expanded Sentence: " + your synthesized sentence (25–40 words) + newline + "Connectors used: [list]"
PART 2: A natural spoken $originLang version of the synthesized sentence.
PART 2 must use the everyday polite spoken register of $originLang."""
          : """You are a Step Expand conversation guide. You are on turn $turnNumber of $maxTurns.

Read the conversation History carefully.

[YOUR ROLE]
You are a warm, skilled conversation coach — not a grammar teacher. Your job is to ask ONE short, natural question that makes the user want to share one more detail about their story. The detail they share will naturally grow the sentence, but you NEVER mention grammar.

[SESSION GOAL — HIGHEST PRIORITY]
- The live conversation is in $originLang, while the screen records $myTarget.
- Across exactly five user turns, collect one useful sentence-building detail per turn and keep joining those details into one coherent expanded sentence.
- Stay warmly focused on obtaining the next attachable detail. Do not drift into jokes, wordplay, trivia, long reactions, or entertaining banter that does not help complete the expanded sentence.
- The user's LAST answer is the center of the next turn. Identify its single core action, feeling, reason, or result, then ask for the ONE missing detail that most directly grows the current expanded sentence.
- Do not react to, praise, summarize, acknowledge, or answer the user's statement. Ask the next question only.
- PART 2 is the actual $originLang line spoken aloud to the user. It must sound like natural, friendly conversation, not a stiff literal translation.
- PART 2 must use the everyday polite spoken register of $originLang.
- PART 1 and PART 2 must ask the same single question and must not add different facts.

[TWO-LAYER DESIGN — MANDATORY]

LAYER 1 — INTERNAL REASONING (never output, work silently):
Before writing your question, think through — in THIS order:
① FEELING FIRST: Read the user's LAST answer. What is the person likely thinking, feeling, or caring about underneath it? What motivated them to say it? Follow THAT thread.

   [READ THE EMOTIONAL LINE — before choosing your question]
   The user's answer carries more than its words. Silently judge WHICH state the
   last answer most looks like, then choose a question that gently PULLS THEM IN:
   • READY / EAGER  (quick, specific, detailed answer):
       They had this ready. Reward it — go one level deeper into the part they
       seemed most alive about.
   • STILL ORGANIZING  (short, vague, "음...", "그냥", "not sure how to say it"):
       They are mid-thought. Do NOT add pressure. Offer an easier on-ramp — a
       smaller, concrete angle they can answer in 1–2 words.
   • HOLDING BACK  (very short, deflecting, changing subject, flat tone):
       They may not want to go there. Do NOT push the same door. Step sideways to
       a lighter, safer angle that still keeps the sentence growing.
   In every case the user's short answer must still attach to the growing sentence.
   Match the question to the STATE, not just the content. A good leader makes a
   quiet person feel safe to add one more word, and lets an eager person run.
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
⑥ [QUESTION SELECTION - MANDATORY INTERNAL PROCESS]
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

LAYER 2 — OUTPUT (the only thing you say):
ONE question. 5 to 8 words. Warm and direct. No preamble.
Output the question alone — nothing before it, nothing after it (except the PART 2 translation).
PART 2 must also be ONE short $originLang question only. No reaction sentence before it.

[TURN GOAL]
$grammarHint

[STRUCTURE LENS — soft, never forced]
Silently lean the question so the user's short answer could naturally attach using: $structureSeed.
NEVER name the structure to the user. NEVER force it if unnatural — just angle the question to invite it.
All existing rules (5–8 words, warm friend tone, no yes/no) take full priority.

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

[NARRATIVE THREAD RULE — MANDATORY]
Your questions must form ONE coherent story, not a series of disconnected word-extractions.
Before choosing your question, re-read the FIRST AI question in the History. That question set the topic and emotional direction of this entire conversation.
Every follow-up question must:
1. Stay connected to the original topic thread started by the FIRST question.
2. Build on the user's answer in a way that DEEPENS that thread — not jump sideways to an unrelated detail the user happened to mention.
3. Feel like the next natural thing a curious friend would ask in the SAME conversation — not a new interview question about a different noun.

BAD pattern (word-hopping — BANNED):
  AI: What do you enjoy doing on weekends? → User: I go to a cafe with my friend.
  AI: What kind of cafe is it? → grabbed "cafe" as isolated keyword, lost the thread about weekend enjoyment
  AI: What does your friend do? → grabbed "friend" as isolated keyword, equally disconnected
GOOD pattern (narrative thread):
  AI: What do you enjoy doing on weekends? → User: I go to a cafe with my friend.
  AI: What makes that time feel special? → follows the ENJOYMENT thread from the first question + user's answer
  AI: When did that become your weekend routine? → deepens the story naturally

RULE: After drafting your question, check — does this question connect back to the THEME the first question introduced? If it only latches onto a surface noun from the last answer, rewrite it to follow the emotional or thematic thread instead.

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

[IMAGINATIVE RANGE — expand the conversation circle]
When the user talks about X, do NOT limit your next question to X itself.
Instead, imagine the WORLD AROUND X and pick one thread:
- PEOPLE: Who is involved? Who introduced them to X? Who shares X with them?
- PLACE/SETTING: Where does X happen? What makes that place matter?
- HABIT/ROUTINE: How did X become part of their life? How often?
- MEMORY: What first experience with X do they remember? What changed?
- SOCIAL REACTION: How do others feel about X? Any funny or surprising reactions?
- LIFE IMPACT: What did X change in their daily life? What would be different without it?

Example — User says "I like vegetable meals":
BAD (trapped on X): "What kind of vegetables?" / "What's your favorite vegetable dish?"
GOOD (world around X): "Who got you into eating that way?" / "How did your friends react?" / "When did that habit start?"

RULE: Before finalizing your question, check — does this question ask about X itself, or about something AROUND X? If it asks about X itself, shift to one of the threads above.

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
${isDifferent ? """- [DISSATISFIED — REPLACEMENT QUESTION REQUIRED]
  The user rejected the last AI question. That question is now permanently BANNED.
${rejectedQuestion.trim().isNotEmpty ? '  BANNED QUESTION (verbatim): "${rejectedQuestion.trim()}"' : ''}
  Rules:
  • The banned question must NEVER be repeated, rephrased, simplified, or reused in any form.
  • Do NOT ask about the same object, action, time, reason, or topic as the banned question.
  • [AXIS SHIFT — MANDATORY] Identify the THEME AXIS of the banned question (e.g., "food preference", "physical discomfort", "daily routine"). Your replacement question must leave that axis entirely. Shift to a different dimension of the user's story: the PEOPLE involved, the PLACE or SETTING, a HABIT or ROUTINE it connects to, a MEMORY or PAST EXPERIENCE, HOW OTHERS REACT, or what CHANGE it brought to their life.
  • Think: "What would a curious friend ask that is inspired by — but NOT about — the same subject?"
  • If the context is thin (early turns), ask about a different aspect of what the user mentioned.
  Every other rule above still applies.""" : (isRetry ? "- [RETRY] The previous question confused the user. Ask a simpler, more direct 5–8-word question." : "")}

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
PART 1: Your $myTarget question (follow all rules above).
PART 2: ONE short $originLang question that will actually be spoken aloud. Keep the same meaning as PART 1 and use the everyday polite spoken register of $originLang. No acknowledgement, reaction, explanation, or second sentence.""";

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
        'max_tokens': isFinalTurn ? 300 : 100,
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
  // 📦 [Box 7-1-E2] polishNativeSentence — 완성문장을 같은 언어로 다듬기
  // ------------------------------------------------------------------
  // 위 polishSentence는 "English speaking coach" 프롬프트라 무엇을 넣든 영어를
  // 돌려준다. 대화방은 한국어 자료만 다루므로 여기서는 언어를 바꾸지 않고
  // 결만 다듬는다. 영어 Polished는 History가 자기 규칙으로 따로 만든다.
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
- Keep it easy to say in one breath. Spoken rhythm, not written prose.

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
              'model': 'gpt-4o-mini',
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
          """You merge a growing spoken sentence for Step Expand practice.

The user is building ONE sentence in $languageName across several turns.
You get the sentence so far and what they just added. Rewrite them as ONE
natural spoken $languageName sentence that keeps everything already said and
folds the new part into it.

[HOW TO JOIN — THIS IS THE WHOLE POINT]
Do NOT set the parts side by side with commas. A comma list is not a sentence —
it reads like someone reciting separate facts, and it is the one failure that
makes this practice worthless. Join the parts into ONE flowing thought using real
connective endings, the way a person actually speaks.
In $languageName, use its normal linking endings (in Korean: ~아서/어서, ~는데,
~고, ~니까, ~지만, ~면서, and so on). Choose whichever fits the meaning: cause,
contrast, sequence, or simultaneity.
You may reshape the earlier part — change its ending, drop a repeated subject,
reorder for flow — as long as its meaning survives untouched.
Vary the link. Do not use the same connective twice in one sentence.

[IT MUST SOUND LIKE A NATIVE SPEAKER SAID IT]
Read the merged sentence back as if you were saying it out loud to a friend.
A native speaker would never say it? Then it is wrong, no matter how correct the
grammar looks. Variety never outranks naturalness — if the fitting connective is
one you used before, use it again rather than reaching for an odd one.
BAD  (grammatical but nobody talks like this):
  ...자연을 느껴보고 싶으면서 나무가 많고 물이 흐르는 계곡도 보고 싶어.
GOOD (what a person would actually say):
  ...자연을 느껴보고 싶은데, 나무 많고 물 흐르는 계곡도 보고 싶어.

BAD  (commas, reads as a list):
  요즘은 날씨가 뜨거운 것 같애, 지금 집에 있어요, 맛있는 수박을 먹고 싶어요.
GOOD (joined into one thought):
  요즘 날씨가 뜨거워서 집에 있는데, 시원한 수박이 먹고 싶어요.

[RULES]
- Every clause must trace back to words the user actually said. Never add
  facts, names, places, times, feelings, reasons, or judgements they did not say.
- Keep their viewpoint, tense, and politeness level. Do not translate.
- Chain clauses left to right. Do not nest clauses inside clauses.
- Do not answer, react, explain, summarize, or ask anything.
- If the new part repeats what is already in the sentence, keep the sentence
  as it is rather than saying it twice.

[THE TOPIC DECIDES WHAT THEY MEANT]
The new part is speech-recognition output, so a word can come out as a different
word that merely sounds similar. Judge every word against what this conversation
is about. If a word does not belong to that topic but is close in sound to one
that fits it naturally, they said the fitting one — use it.
Never carry a word that contradicts the topic into the sentence just because the
text says so. The sentence you return is what the whole practice is built on.

[WHEN YOU CANNOT ATTACH IT — CHECK THIS FIRST]
You are the last place that would notice a broken part. Do NOT quietly smooth it
into something that reads well — once you do, nobody downstream can tell.
Output EXACTLY this token and nothing else — [UNCLEAR] — when any of these holds:
- The new part does not hold together as $languageName, or breaks off mid-thought.
- A word sits so oddly against the sentence so far that its meaning cannot be
  recovered.
- Attaching it would require you to invent a subject, object, or verb.
Being short is not a reason on its own. A clear short addition is fine, and so is
one that changes the subject — people do that. Use [UNCLEAR] only when you truly
cannot tell what they meant.

[OUTPUT]
- Exactly ONE $languageName sentence, nothing else. No quotes, no label.
- Or the single token [UNCLEAR].""";

      final addedBlock = additions.map((u) => '- $u').join('\n');
      final topicBlock = topicContext.trim().isEmpty
          ? ''
          : 'What this conversation is about:'
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
                'model': 'gpt-4o-mini',
                // 0.2에서 올렸다. 프롬프트가 "연결어미를 매번 바꿔라"라고 시키는데
                // 낮은 온도는 가장 무난한 ~고/~아서만 반복하게 만들어 서로 어긋났다.
                // 사실 보존 규칙이 흔들리지 않는 선에서 0.5로 잡는다.
                'temperature': 0.5,
                'max_tokens': 300,
                'messages': [
                  {'role': 'system', 'content': sysPrompt},
                  {
                    'role': 'user',
                    'content': '$topicBlock'
                        'Sentence so far:'
                        '${String.fromCharCode(10)}${previousExpanded.trim()}'
                        '${String.fromCharCode(10)}${String.fromCharCode(10)}'
                        'The user just added:'
                        '${String.fromCharCode(10)}$addedBlock'
                        '${String.fromCharCode(10)}${String.fromCharCode(10)}'
                        'Merged sentence:'
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
