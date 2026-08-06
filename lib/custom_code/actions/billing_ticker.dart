// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'index.dart'; // Imports other custom actions

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// FlutterFlow Custom Action 등록용 더미 함수.
Future billingTicker() async {}

// =============================================================================
// BillingRate (과금 배율 enum)
// =============================================================================

/// 과금 배율은 하나뿐이다. 과금이 걸리는 모든 화면은 같은 요금으로 계산한다.
///
/// 예전에는 quarter(0.25x)가 있어 히스토리·Keepers를 4배 오래 쓸 수 있었다.
/// 2026-08-04 정책 확인 결과 그런 할인은 존재하지 않으므로 제거했다.
/// 배율을 다시 나눠야 하면 여기에 값을 추가하지 말고 먼저 정책을 확인할 것.
enum BillingRate {
  full, // 1.0x — 1초 사용 시 1초 차감
}

extension BillingRateMultiplier on BillingRate {
  double get multiplier {
    switch (this) {
      case BillingRate.full:
        return 1.0;
    }
  }
}

// =============================================================================
// BillingTicker (전역 과금 타이머 싱글톤)
// =============================================================================

const String _kBillingRegion = 'us-central1';

class BillingTicker with WidgetsBindingObserver {
  static final BillingTicker instance = BillingTicker._();
  BillingTicker._() {
    WidgetsBinding.instance.addObserver(this);
  }

  final ValueNotifier<int> remainingSecondsNotifier = ValueNotifier<int>(0);

  /// 과금 상태 인디케이터 (0=차감 안 함, 2=차감 중)
  /// 1은 예전 quarter 배율 자리였다. 배율이 하나로 합쳐져 더 이상 쓰지 않는다.
  ///
  /// ⚠️ 이 계약에 값을 추가하지 말 것. 7개 화면이 구독하는데 그중 다섯(히스토리·
  /// 히스토리 목록·스토어·스텔스룸 등)은 30분 대화 세션 자체가 없다. 세션 임박
  /// 표시는 [sessionRemainingNotifier]로 따로 내보낸다.
  final ValueNotifier<int> billingState = ValueNotifier<int>(0);

  // ── 30분 대화 세션 ────────────────────────────────────────────────────────
  // 과금 구간(usage_logs)과 다른 축이다. 과금 구간은 백그라운드·idle마다 이미
  // 쪼개지지만, 대화 세션은 30분 롤오버에서만 끊긴다. 둘을 같은 값으로 묶으면
  // 잠깐 앱을 내렸다 올린 것만으로 30분 시계가 되감긴다.
  /// 🧪 디버그 빌드에서만 세션 길이를 줄여 롤오버를 실제로 밟아 볼 수 있게 한다.
  /// 30분을 그대로 두면 경합(롤오버 × 백그라운드 × idle) 검증이 사실상 불가능하다.
  ///   flutter run --dart-define=SESSION_SECONDS=45
  /// 릴리스 빌드는 이 값을 무시하고 항상 30분이다.
  static const int _kDebugSessionSecondsOverride =
      int.fromEnvironment('SESSION_SECONDS');

  static int get kSessionSeconds =>
      (kDebugMode && _kDebugSessionSecondsOverride > 0)
          ? _kDebugSessionSecondsOverride
          : 30 * 60;

  /// 현재 30분 세션의 잔여 초. 실제로 차감이 일어난 초에만 줄어든다
  /// (idle·백그라운드로 멈춘 동안은 그대로) — 그래야 "30분 과금분"과 세션이
  /// 일치한다. 대화방 2곳만 구독한다.
  final ValueNotifier<int> sessionRemainingNotifier =
      ValueNotifier<int>(kSessionSeconds);

  /// 30분 경계에 도달했다는 신호. 엔진은 신호만 세우고 롤오버는 하지 않는다 —
  /// "진행 중인 발화·답변이 끝날 때까지 기다림"은 모드만 아는 상태이고, 엔진에
  /// UI·파이프라인을 넣지 않는다는 원칙을 지킨다.
  final ValueNotifier<bool> sessionRolloverDue = ValueNotifier<bool>(false);

  int _sessionElapsedSeconds = 0;
  DateTime? _lastRolloverAttemptAt;

  /// 정산 실패로 롤오버가 튕겼을 때 매 초 재시도하지 않도록 두는 간격.
  static const Duration _kRolloverRetryCooldown = Duration(seconds: 30);
  // ─────────────────────────────────────────────────────────────────────────

  /// 지금 이 순간 실제로 차감이 도는가.
  /// [_onTick]의 차감 조건과 **같은 식**을 쓴다. 표시등이 따로 판단하면
  /// 갈린다 — 예전에는 `!_paused`만 봐서, 잔여시간이 0이거나 아직 로딩되지
  /// 않아 한 푼도 안 나가는 동안에도 초록불이 켜져 있었다.
  bool get _isActuallyBilling =>
      !_paused &&
      FFAppState().remainingTimeLoaded &&
      !FFAppState().hasConfirmedZeroTime;

  void _updateBillingState() {
    final next = _isActuallyBilling ? 2 : 0;
    if (billingState.value == next) return;
    billingState.value = next;
    _addBillingLog('[BILLING] indicator=${next == 2 ? 'on' : 'off'}');
  }

  Timer? _tickTimer;
  BillingRate _rate = BillingRate.full;
  bool _paused = true;
  bool _wasRunningBeforeBackground = false;
  bool _recoverableLifecyclePause = false;
  Timer? _lifecyclePauseTimer;
  double _fractionalDebt = 0.0;
  int _unflushedDeducted = 0;
  DateTime _lastFlushAt = DateTime.now();
  String? _lastFlushResult;
  final List<Map<String, dynamic>> _history = [];
  static const int _kMaxHistory = 10;

  // ── Session Tracking (usage_logs 저장용) ──────────────────────────────────
  String _sessionMode = '';
  double _sessionRateValue = 1.0;
  int _sessionBeforeSeconds = 0;
  DateTime? _sessionStartTime;
  bool _usageLogSaved = false;
  String? _sessionDocIdForUsage;
  String? _roomIdForUsage;
  // ─────────────────────────────────────────────────────────────────────────

  void _addBillingLog(String msg) {
    debugPrint(msg);
    if (!msg.contains('tick before=')) {
      AppLogLedger.instance.add('BILLING', msg);
    }
  }

  BillingRate get currentRate => _rate;
  bool get isPaused => _paused;
  double get fractionalDebt => _fractionalDebt;
  int get unflushedDeducted => _unflushedDeducted;
  DateTime get lastFlushAt => _lastFlushAt;
  String? get lastFlushResult => _lastFlushResult;
  List<Map<String, dynamic>> get history => List.unmodifiable(_history);

  /// usage_logs 식별자 연결. mode 진입 시 null로 초기화하고,
  /// Firestore 세션/방 문서가 확정되면 각 모드에서 다시 설정한다.
  void setSessionIdentifiers({String? sessionDocId, String? roomId}) {
    final normalizedSessionDocId = sessionDocId?.trim();
    final normalizedRoomId = roomId?.trim();
    _sessionDocIdForUsage =
        normalizedSessionDocId != null && normalizedSessionDocId.isNotEmpty
            ? normalizedSessionDocId
            : null;
    _roomIdForUsage = normalizedRoomId != null && normalizedRoomId.isNotEmpty
        ? normalizedRoomId
        : null;
    _addBillingLog(
        '[BILLING] identifiers session=${_sessionDocIdForUsage ?? ''} room=${_roomIdForUsage ?? ''}');
  }

  // ── Foreground / Background Lifecycle ─────────────────────────────────────
  /// 앱이 백그라운드로 가면 billing 정지 → 포그라운드 복귀 시 이전 상태로 재개
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _lifecyclePauseTimer?.cancel();
      if (!_paused) {
        _wasRunningBeforeBackground = true;
        _addBillingLog('[BILLING] lifecycle pause pending: 3s grace started');
        _lifecyclePauseTimer = Timer(const Duration(seconds: 3), () {
          _lifecyclePauseTimer = null;
          if (_wasRunningBeforeBackground && !_paused) {
            _addBillingLog('[BILLING] lifecycle pause confirmed');
            _pauseFromLifecycle();
          }
        });
      } else {
        // billing이 이미 정지 상태이면 flush만 안전하게 시도
        flushNow();
      }
    } else if (state == AppLifecycleState.resumed) {
      _cancelLifecyclePause('lifecycle_resumed');
      _addBillingLog('[BILLING] foreground resumed');
      if (_wasRunningBeforeBackground) {
        _wasRunningBeforeBackground = false;
        // 포그라운드 복귀: 과금 구간만 새로 연다. 30분 시계는 그대로 둔다 —
        // 앱을 잠깐 내렸다 올린 것으로 세션이 되감기면 안 된다.
        if (_sessionMode.isNotEmpty) {
          _openSegment('foreground');
          _addBillingLog(
              '[BILLING] session resumed from bg, new before=$_sessionBeforeSeconds');
        }
        resume();
      }
    }
  }
  // ──────────────────────────────────────────────────────────────────────────

  void start() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  /// 과금 배율 설정. 변경 시 로그 자동 기록.
  void setRate(BillingRate rate) {
    _rate = rate;
    _addBillingLog('[BILLING] rate=${rate.name}');
    _updateBillingState();
  }

  /// 현재 모드 로그 기록 + 세션 시작 상태 캡처
  /// 반드시 setRate() 이후에 호출해야 rate가 정확히 기록됨
  ///
  /// [startNewConversation]은 30분 시계를 처음으로 되돌릴지다. 방에 새로 들어올
  /// 때만 true다. **idle 복귀에서도 이 함수가 불리므로**(대화방 두 곳이 그렇다)
  /// 거기서는 반드시 false를 넘겨야 한다 — 60초 쉬었다 돌아올 때마다 30분이
  /// 되감기면 롤오버가 영영 오지 않는다.
  void logMode(String mode, {bool startNewConversation = true}) {
    AppLogLedger.instance.onSessionStart(mode);
    _sessionMode = mode;
    _sessionRateValue = _rate.multiplier;
    _openSegment(startNewConversation ? 'mode_enter' : 'idle_resume');
    if (startNewConversation) resetConversationSession();
    _addBillingLog(
        '[BILLING] mode=$mode (session start before=$_sessionBeforeSeconds rate=$_sessionRateValue newConv=$startNewConversation)');
  }

  // ── 과금 구간 단일 진입/종료 경로 ─────────────────────────────────────────
  // 불변식 두 개로 중복 정산과 누락을 동시에 막는다.
  //   ① usage_logs에 쓰는 곳은 [_closeSegment] 하나뿐이다.
  //   ② 기준선([_sessionBeforeSeconds])은 저장이 성공한 뒤에만 앞으로 간다.
  //
  // ②가 없으면 이렇게 샌다 — 기준선을 먼저 옮기면 secondsUsed가 0이 되어
  // saveUsageLog가 조용히 반환하고(구간 증발), 저장 실패인데 기준선만 옮기면
  // 재시도해도 지나간 구간을 계산할 수 없다(이력 손실).
  bool _segmentClosing = false;

  void _openSegment(String reason) {
    _sessionBeforeSeconds = FFAppState().remainingTime;
    _sessionStartTime = DateTime.now();
    _usageLogSaved = false;
    _addBillingLog(
        '[BILLING-SEG] open reason=$reason before=$_sessionBeforeSeconds');
  }

  /// 과금 구간 하나를 닫는다. usage_logs에 쓰는 유일한 경로.
  ///
  /// [reopen]이 true면 과금을 멈추지 않고 구간만 교체한다(30분 롤오버).
  /// 반환값이 false면 정산이 실패한 것이다 — 호출부는 History를 교체하면 안 된다.
  Future<bool> _closeSegment(String reason, {required bool reopen}) async {
    if (_segmentClosing) {
      _addBillingLog('[BILLING-SEG] close skipped reason=$reason busy=true');
      return false;
    }
    _segmentClosing = true;
    try {
      await flushNow();
      final persisted = await _persistSegment();
      _addBillingLog(
          '[BILLING-SEG] close reason=$reason persisted=$persisted reopen=$reopen');
      if (!persisted) return false;
      if (reopen) _openSegment(reason);
      return true;
    } finally {
      _segmentClosing = false;
    }
  }

  /// 이 구간을 usage_logs에 남긴다.
  ///
  /// 반환값은 "기준선을 앞으로 옮겨도 안전한가"다. 저장할 것이 애초에 없던
  /// 경우(차감 0, 비로그인, 이미 저장됨)도 true다 — 잃을 것이 없다. 저장을
  /// 시도했다가 실패한 경우에만 false를 돌려 기준선을 붙잡아 둔다.
  Future<bool> _persistSegment() async {
    if (_usageLogSaved) return true;
    if (_sessionMode.isEmpty || _sessionStartTime == null) return true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _addBillingLog('[USAGE_LOG] skip: no user');
      return true;
    }

    final afterSeconds = FFAppState().remainingTime;
    final beforeSeconds = _sessionBeforeSeconds;
    final secondsUsed = beforeSeconds - afterSeconds;

    if (secondsUsed <= 0 || beforeSeconds <= afterSeconds) {
      _addBillingLog(
          '[USAGE_LOG] skip: no deduction before=$beforeSeconds after=$afterSeconds');
      return true;
    }

    final actualSeconds =
        DateTime.now().difference(_sessionStartTime!).inSeconds;

    // 중복 저장 방지: 이 플래그는 await 이전에 true로 설정
    _usageLogSaved = true;

    try {
      // [B-BILLING] Remove direct client write; server callable owns the log.
      await _callLogUsageSession(
        secondsUsed: secondsUsed,
        actualSeconds: actualSeconds,
      );
      _addBillingLog(
          '[USAGE_LOG] saved mode=$_sessionMode seconds_used=${secondsUsed}s actual=${actualSeconds}s before=$beforeSeconds after=$afterSeconds');
      return true;
    } catch (e) {
      // 저장 실패 시 플래그 초기화 → 다음 호출에서 재시도 가능.
      // 기준선은 옮기지 않는다(false 반환) — 옮기면 이 구간이 영영 사라진다.
      _usageLogSaved = false;
      _addBillingLog('[USAGE_LOG] error: $e');
      debugPrint('[BillingTicker] saveUsageLog failed: $e');
      return false;
    }
  }

  /// 30분 시계를 처음으로 되돌린다. 방 진입과 롤오버 성공에서만 부른다.
  void resetConversationSession() {
    _sessionElapsedSeconds = 0;
    _lastRolloverAttemptAt = null;
    if (sessionRemainingNotifier.value != kSessionSeconds) {
      sessionRemainingNotifier.value = kSessionSeconds;
    }
    if (sessionRolloverDue.value) sessionRolloverDue.value = false;
  }

  /// 30분 경계에서 모드가 부른다. 과금을 멈추지 않고 구간만 교체한다.
  ///
  /// false면 정산이 실패했거나 재시도 대기 중이다. 그때 호출부는 History를
  /// 새로 만들면 안 된다 — 직전 30분 이력이 새 방 id로 붙어 버린다.
  Future<bool> rollSegment() async {
    final lastAttempt = _lastRolloverAttemptAt;
    if (lastAttempt != null &&
        DateTime.now().difference(lastAttempt) < _kRolloverRetryCooldown) {
      return false;
    }
    _lastRolloverAttemptAt = DateTime.now();
    final ok = await _closeSegment('rollover_30m', reopen: true);
    if (ok) resetConversationSession();
    return ok;
  }
  // ─────────────────────────────────────────────────────────────────────────

  void pause() {
    if (_paused) return; // 이중 호출 방지
    _cancelLifecyclePause('manual_pause');
    _recoverableLifecyclePause = false;
    _paused = true;
    _addBillingLog('[BILLING] pause');
    _updateBillingState();
    // void 함수라 await할 수 없다. 종료 경로는 하나로 묶여 있으므로 순서
    // (flush → 저장 → 기준선)는 _closeSegment 안에서 지켜진다.
    unawaited(_closeSegment('pause', reopen: false));
  }

  /// 세션 종료 시 users/{uid}/usage_logs에 사용시간 이력 1회 저장.
  ///
  /// 실제 저장은 [_closeSegment]가 소유한다 — 저장과 기준선 이동이 갈라지면
  /// 중복 정산이나 구간 증발이 생기기 때문이다. 이 이름은 외부 호환용으로만
  /// 남긴다.
  Future<void> saveUsageLog() => _closeSegment('manual', reopen: false);

  void resume() {
    _cancelLifecyclePause('manual_resume');
    _recoverableLifecyclePause = false;
    _paused = false;
    if (_tickTimer == null) start();
    _addBillingLog('[BILLING] resume');
    _updateBillingState();
  }

  void resumeFromActivity(String reason) {
    final hadPendingLifecyclePause = _lifecyclePauseTimer?.isActive == true;
    _cancelLifecyclePause(reason);

    if (!_canResumeFromActivity ||
        (_paused && !_recoverableLifecyclePause && !hadPendingLifecyclePause)) {
      _addBillingLog('[BILLING-RECOVER-SKIP] reason=$reason');
      return;
    }

    if (!_paused) {
      if (hadPendingLifecyclePause) {
        _addBillingLog('[BILLING-RECOVER] reason=$reason');
      }
      return;
    }

    // 과금 구간만 새로 연다. 30분 시계는 건드리지 않는다 — idle로 잠깐 멈춘
    // 것이 30분 세션을 되감으면 안 된다.
    _openSegment(reason);
    _addBillingLog('[BILLING-RECOVER] reason=$reason');
    resume();
  }

  bool get _canResumeFromActivity =>
      _sessionMode.isNotEmpty &&
      _sessionStartTime != null &&
      FFAppState().hasConfirmedPositiveTime;

  void _pauseFromLifecycle() {
    if (_paused) return;
    _recoverableLifecyclePause = true;
    _paused = true;
    _addBillingLog('[BILLING] pause');
    _updateBillingState();
    unawaited(_closeSegment('lifecycle', reopen: false));
  }

  void _cancelLifecyclePause(String reason) {
    if (_lifecyclePauseTimer?.isActive == true) {
      _lifecyclePauseTimer?.cancel();
      _addBillingLog('[BILLING] lifecycle pause canceled by $reason');
    }
    _lifecyclePauseTimer = null;
    _wasRunningBeforeBackground = false;
  }

  void _onTick() {
    // 잔여시간 로딩 완료·소진은 pause/resume과 무관하게 일어나므로 매 초
    // 다시 판정한다. 아래 차감 조건과 같은 식이라 표시등이 어긋날 수 없다.
    _updateBillingState();
    if (!_isActuallyBilling) return;

    _fractionalDebt += _rate.multiplier;
    final whole = _fractionalDebt.floor();
    if (whole >= 1) {
      final before = FFAppState().remainingTime;
      _fractionalDebt -= whole;
      final next = (before - whole).clamp(0, 1 << 31);
      FFAppState().remainingTime = next;
      _unflushedDeducted += whole;
      remainingSecondsNotifier.value = next;
      _addBillingLog('[BILLING] tick before=$before after=$next');
      _addHistory({
        'time': DateTime.now().toIso8601String().substring(11, 19),
        'rate': _rate.name,
        'deducted': whole,
        'remaining': next,
      });
      // 30분 시계는 실제로 차감된 초만 센다. 벽시계로 재면 idle·백그라운드로
      // 멈춘 시간까지 흘러가서 "30분 과금분"과 세션이 어긋난다.
      _advanceConversationSession(whole);
    }

    if (DateTime.now().difference(_lastFlushAt).inSeconds >= 60) {
      flushNow();
    }
  }

  void _advanceConversationSession(int seconds) {
    if (seconds <= 0) return;
    _sessionElapsedSeconds += seconds;
    final remaining =
        (kSessionSeconds - _sessionElapsedSeconds).clamp(0, kSessionSeconds);
    if (sessionRemainingNotifier.value != remaining) {
      sessionRemainingNotifier.value = remaining;
    }
    if (remaining <= 0 && !sessionRolloverDue.value) {
      sessionRolloverDue.value = true;
      _addBillingLog('[BILLING-SEG] rollover_due elapsed=$_sessionElapsedSeconds');
    }
  }

  Future<void> flushNow() async {
    if (_unflushedDeducted <= 0) return;
    final amount = _unflushedDeducted;
    _unflushedDeducted = 0;
    _lastFlushAt = DateTime.now();
    try {
      await _callDeductTime(amount);
    } catch (e) {
      _unflushedDeducted += amount;
      _addBillingLog('[BILLING] firestore save error: $e');
      debugPrint('[BillingTicker] flush failed: $e');
      _lastFlushResult =
          'FAIL: $e @ ${DateTime.now().toIso8601String().substring(11, 19)}';
    }
  }

  Future<void> disposeTicker() async {
    _lifecyclePauseTimer?.cancel();
    _lifecyclePauseTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;
    // 타이머를 끄면 차감도 멈춘다. 표시등을 같이 끄지 않으면 초록불만
    // 남는다. 지금은 호출하는 곳이 없지만 나중에 쓸 때 걸리지 않게 막아둔다.
    _paused = true;
    _updateBillingState();
    await flushNow();
  }

  void _addHistory(Map<String, dynamic> entry) {
    _history.insert(0, entry);
    if (_history.length > _kMaxHistory) {
      _history.removeRange(_kMaxHistory, _history.length);
    }
  }

  Future<void> _callDeductTime(int seconds) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final idToken = await user.getIdToken();
    final projectId = FirebaseFirestore.instance.app.options.projectId;

    final response = await http
        .post(
          Uri.parse(
              'https://$_kBillingRegion-$projectId.cloudfunctions.net/deductRemainingTime'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({
            'data': {'seconds': seconds}
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final result = body['result'] as Map<String, dynamic>?;
      final updated = (result?['remainingTime'] as num?)?.toInt();
      if (updated != null) {
        FFAppState().remainingTime = updated;
        remainingSecondsNotifier.value = updated;
      }
      _addBillingLog('[BILLING] firestore save success');
      _lastFlushResult =
          'OK (-${seconds}s) @ ${DateTime.now().toIso8601String().substring(11, 19)}';
    }
  }

  /// [B-BILLING] Calls the server-owned usage_logs writer.
  /// created_at/after_seconds/before_seconds are derived on the server.
  /// room_id/session_id are supplied when the current mode has resolved them.
  Future<void> _callLogUsageSession({
    required int secondsUsed,
    required int actualSeconds,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final idToken = await user.getIdToken();
    final projectId = FirebaseFirestore.instance.app.options.projectId;

    final response = await http
        .post(
          Uri.parse(
              'https://$_kBillingRegion-$projectId.cloudfunctions.net/logUsageSession'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({
            'data': {
              'mode': _sessionMode,
              'rate': _sessionRateValue,
              'seconds_used': secondsUsed,
              'actual_seconds': actualSeconds,
              'room_id': _roomIdForUsage ?? '',
              'session_id': _sessionDocIdForUsage ?? '',
            }
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception(
          'logUsageSession HTTP ${response.statusCode}: ${response.body}');
    }
  }
}

// =============================================================================
// BillingDotPainter (과금 상태 인디케이터 아이콘)
// =============================================================================
// state 0: paused - green outline + gray core
// state 1: billing active - solid green
// state 2: billing active - solid green

class BillingDotPainter extends CustomPainter {
  final int state;

  /// 30분 세션 종료 임박(10초 이하). 차감 중인 점만 주황으로 바꾼다.
  ///
  /// 기본값이 false라 이 값을 넘기지 않는 화면(히스토리·목록·스토어·스텔스룸)은
  /// 그대로다. 30분 세션이 없는 화면에 주황이 새면 안 되므로 billingState에
  /// 값을 더하는 대신 이 플래그로 받는다.
  final bool warning;

  const BillingDotPainter(this.state, {this.warning = false});

  static const _green = Color(0xFF34D399);
  static const _gray = Color(0xFF4B5563);
  static const _amber = Color(0xFFF59E0B);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;

    switch (state) {
      case 1:
      case 2:
        canvas.drawCircle(c, r, Paint()..color = warning ? _amber : _green);
        break;
      default:
        canvas.drawCircle(c, r * 0.75, Paint()..color = _gray);
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..color = _green
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.3,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(BillingDotPainter oldDelegate) =>
      oldDelegate.state != state || oldDelegate.warning != warning;
}

// =============================================================================
// 30분 세션 표시 (대화방 전용)
// =============================================================================
// 기존 HH:MM은 전체 보유시간이라 의미가 다르다. 그 자리를 덮지 않고 옆에 붙는다.
// 30분 세션이 없는 화면(히스토리·목록·스토어·스텔스룸)은 이 위젯을 쓰지 않으므로
// 아무 영향이 없다.

/// 마지막 10초 동안 주황으로 깜박이는 과금 점.
///
/// 점멸은 AnimationController 없이 [BillingTicker.sessionRemainingNotifier]가
/// 매초 바뀌는 것에 얹는다 — 1초 주기로 흐려졌다 진해진다. 컨트롤러를 두면
/// dispose 경로가 하나 늘고 방을 빠르게 드나들 때 새는 자리가 된다.
class BillingSessionDot extends StatelessWidget {
  const BillingSessionDot({
    super.key,
    this.size = 14,
    this.onTapWhenPaused,
    this.warnAtSeconds = 10,
  });

  final double size;
  final VoidCallback? onTapWhenPaused;
  final int warnAtSeconds;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: BillingTicker.instance.billingState,
      builder: (_, state, __) => ValueListenableBuilder<int>(
        valueListenable: BillingTicker.instance.sessionRemainingNotifier,
        builder: (_, remaining, __) {
          final warning = state != 0 && remaining <= warnAtSeconds;
          final dot = CustomPaint(
            size: Size(size, size),
            painter: BillingDotPainter(state, warning: warning),
          );
          return GestureDetector(
            onTap: state == 0 ? onTapWhenPaused : null,
            child: warning
                ? Opacity(opacity: remaining.isEven ? 1.0 : 0.35, child: dot)
                : dot,
          );
        },
      ),
    );
  }
}

/// 과금 배지의 시간 칸 하나. 새 요소를 옆에 붙이지 않고 이 칸을 나눠 쓴다 —
/// 상단 바가 좁아 배지를 하나 더 달면 큰 글꼴에서 바로 넘친다.
///
/// 평소에는 전체 보유시간(HH:MM). 30분 세션이 30초 남으면 그 30초 동안만
/// 카운트다운 숫자로 바뀌고, 새 세션이 시작되면 곧바로 보유시간으로 돌아온다.
/// 보유시간의 의미는 그대로다 — 잠깐 자리를 빌려줄 뿐이다.
class BillingTimeLabel extends StatelessWidget {
  const BillingTimeLabel({
    super.key,
    this.style,
    this.countdownAtSeconds = 30,
  });

  final TextStyle? style;
  final int countdownAtSeconds;

  static const TextStyle _defaultStyle =
      TextStyle(color: Colors.white, fontWeight: FontWeight.bold);

  @override
  Widget build(BuildContext context) {
    final base = style ?? _defaultStyle;
    return ValueListenableBuilder<int>(
      valueListenable: BillingTicker.instance.billingState,
      builder: (_, state, __) => ValueListenableBuilder<int>(
        valueListenable: BillingTicker.instance.sessionRemainingNotifier,
        builder: (_, sessionRemaining, __) {
          final counting = state != 0 &&
              sessionRemaining > 0 &&
              sessionRemaining <= countdownAtSeconds;
          if (counting) {
            return Text(
              '$sessionRemaining',
              style: base.copyWith(color: const Color(0xFFF59E0B)),
            );
          }
          return ValueListenableBuilder<int>(
            valueListenable: BillingTicker.instance.remainingSecondsNotifier,
            builder: (_, remaining, __) {
              final int s = remaining.clamp(0, 999999);
              final int h = s ~/ 3600;
              final int m = (s % 3600) ~/ 60;
              return Text(
                '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
                style: base,
              );
            },
          );
        },
      ),
    );
  }
}

/// "대화가 저장되었습니다" — 종료가 아니라 저장이라는 신호.
class SessionSavedNotice extends StatelessWidget {
  const SessionSavedNotice({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 220),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Text(
            '대화가 저장되었습니다',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// AppLogLedger (global debug log collector for admin-only inspection)
// =============================================================================
class AppLogLedger {
  static final AppLogLedger instance = AppLogLedger._();
  AppLogLedger._();

  static const int _kMax = 300;
  final List<String> _lines = [];

  void onSessionStart(String mode) {
    _lines.clear();
    add('SYSTEM', '---- session start: $mode ----');
  }

  void add(String tag, String message) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    _lines.add('[$ts] [$tag] $message');
    if (_lines.length > _kMax) {
      _lines.removeRange(0, _lines.length - _kMax);
    }
  }

  List<String> get lines => List.unmodifiable(_lines);

  String get joined => _lines.join('\n');

  void clear() => _lines.clear();
}
