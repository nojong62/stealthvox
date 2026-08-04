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
  final ValueNotifier<int> billingState = ValueNotifier<int>(0);

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
        // 포그라운드 복귀: 새 구간 시작 — before_seconds를 현재 잔여시간으로 재설정
        if (_sessionMode.isNotEmpty) {
          _sessionBeforeSeconds = FFAppState().remainingTime;
          _sessionStartTime = DateTime.now();
          _usageLogSaved = false;
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
  void logMode(String mode) {
    AppLogLedger.instance.onSessionStart(mode);
    _sessionMode = mode;
    _sessionRateValue = _rate.multiplier;
    _sessionBeforeSeconds = FFAppState().remainingTime;
    _sessionStartTime = DateTime.now();
    _usageLogSaved = false;
    _addBillingLog(
        '[BILLING] mode=$mode (session start before=$_sessionBeforeSeconds rate=$_sessionRateValue)');
  }

  void pause() {
    if (_paused) return; // 이중 호출 방지
    _cancelLifecyclePause('manual_pause');
    _recoverableLifecyclePause = false;
    _paused = true;
    _addBillingLog('[BILLING] pause');
    _updateBillingState();
    flushNow();
    saveUsageLog(); // 세션 종료 시 사용시간 이력 1회 저장 (중복 방지 포함)
  }

  /// 세션 종료 시 users/{uid}/usage_logs에 사용시간 이력 1회 저장
  /// - seconds_used <= 0 이면 저장 안 함
  /// - currentUser == null 이면 저장 안 함
  /// - before_seconds <= after_seconds 이면 저장 안 함 (차감 없음)
  /// - _usageLogSaved == true 이면 중복 저장 안 함
  Future<void> saveUsageLog() async {
    if (_usageLogSaved) return;
    if (_sessionMode.isEmpty || _sessionStartTime == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _addBillingLog('[USAGE_LOG] skip: no user');
      return;
    }

    final afterSeconds = FFAppState().remainingTime;
    final beforeSeconds = _sessionBeforeSeconds;
    final secondsUsed = beforeSeconds - afterSeconds;

    if (secondsUsed <= 0 || beforeSeconds <= afterSeconds) {
      _addBillingLog(
          '[USAGE_LOG] skip: no deduction before=$beforeSeconds after=$afterSeconds');
      return;
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
    } catch (e) {
      // 저장 실패 시 플래그 초기화 → 다음 호출에서 재시도 가능
      _usageLogSaved = false;
      _addBillingLog('[USAGE_LOG] error: $e');
      debugPrint('[BillingTicker] saveUsageLog failed: $e');
    }
  }

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

    _sessionBeforeSeconds = FFAppState().remainingTime;
    _sessionStartTime = DateTime.now();
    _usageLogSaved = false;
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
    flushNow();
    saveUsageLog();
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
    }

    if (DateTime.now().difference(_lastFlushAt).inSeconds >= 60) {
      flushNow();
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
  const BillingDotPainter(this.state);

  static const _green = Color(0xFF34D399);
  static const _gray = Color(0xFF4B5563);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;

    switch (state) {
      case 1:
      case 2:
        canvas.drawCircle(c, r, Paint()..color = _green);
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
      oldDelegate.state != state;
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
