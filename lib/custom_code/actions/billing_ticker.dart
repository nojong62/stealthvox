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

enum BillingRate {
  full,    // 1.0x — 1초 사용 시 1초 차감 (실시간 AI 대화/훈련 모드)
  quarter, // 0.25x — 1초 사용 시 0.25초 차감 (복습/히스토리 체류 계열, 4배 오래 사용 가능)
}

extension BillingRateMultiplier on BillingRate {
  double get multiplier {
    switch (this) {
      case BillingRate.full:
        return 1.0;
      // 복습/히스토리 체류 계열:
      // 0.25 = 25% billing rate (StealthVox 서비스 정책 — 변경 금지).
      // 사용자가 일반 대화보다 4배 오래 복습 가능.
      case BillingRate.quarter:
        return 0.25;
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

  Timer? _tickTimer;
  BillingRate _rate = BillingRate.quarter;
  bool _paused = true;
  bool _wasRunningBeforeBackground = false;
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
  // ─────────────────────────────────────────────────────────────────────────

  // ── BILLING DEBUG LOG ──────────────────────────────────────────────────────
  static const int _kMaxLogs = 200;
  final List<String> _billingLogs = [];

  void _addBillingLog(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    final line = '[$ts] $msg';
    _billingLogs.insert(0, line);
    if (_billingLogs.length > _kMaxLogs) {
      _billingLogs.removeRange(_kMaxLogs, _billingLogs.length);
    }
    debugPrint(msg);
  }

  /// BILLING DEBUG LOG 전체 목록 (최신순)
  List<String> get billingLogs => List.unmodifiable(_billingLogs);

  /// BILLING DEBUG LOG 초기화
  void clearBillingLogs() => _billingLogs.clear();
  // ──────────────────────────────────────────────────────────────────────────

  BillingRate get currentRate => _rate;
  bool get isPaused => _paused;
  double get fractionalDebt => _fractionalDebt;
  int get unflushedDeducted => _unflushedDeducted;
  DateTime get lastFlushAt => _lastFlushAt;
  String? get lastFlushResult => _lastFlushResult;
  List<Map<String, dynamic>> get history => List.unmodifiable(_history);

  // ── Foreground / Background Lifecycle ─────────────────────────────────────
  /// 앱이 백그라운드로 가면 billing 정지 → 포그라운드 복귀 시 이전 상태로 재개
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (!_paused) {
        _wasRunningBeforeBackground = true;
        _addBillingLog('[BILLING] background paused');
        // pause() 내부에서 saveUsageLog() 가 호출되어 백그라운드 이전 구간 저장
        pause();
      } else {
        // billing이 이미 정지 상태이면 flush만 안전하게 시도
        flushNow();
      }
    } else if (state == AppLifecycleState.resumed) {
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
    final rateStr = rate == BillingRate.full ? 'rate=full' : 'rate=quarter';
    _addBillingLog('[BILLING] $rateStr');
  }

  /// 현재 모드 로그 기록 + 세션 시작 상태 캡처
  /// 반드시 setRate() 이후에 호출해야 rate가 정확히 기록됨
  void logMode(String mode) {
    _sessionMode = mode;
    _sessionRateValue = _rate.multiplier;
    _sessionBeforeSeconds = FFAppState().remainingTime;
    _sessionStartTime = DateTime.now();
    _usageLogSaved = false;
    _addBillingLog(
        '[BILLING] mode=$mode (session start before=$_sessionBeforeSeconds rate=$_sessionRateValue)');
  }

  void pause() {
    _paused = true;
    _addBillingLog('[BILLING] pause');
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
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('usage_logs')
          .add({
        'created_at': FieldValue.serverTimestamp(),
        'mode': _sessionMode,
        'seconds_used': secondsUsed,
        'actual_seconds': actualSeconds,
        'rate': _sessionRateValue,
        'before_seconds': beforeSeconds,
        'after_seconds': afterSeconds,
      });
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
    _paused = false;
    _addBillingLog('[BILLING] resume');
  }

  void _onTick() {
    if (_paused) return;
    if (FFAppState().remainingTime <= 0) return;

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
    _tickTimer?.cancel();
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
}
