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
  full, // 1.0x — 1초 사용 시 1초 차감
  discounted, // 0.25x — 1초 사용 시 0.25초 차감 (4배 더 길게 사용 가능)
}

extension BillingRateMultiplier on BillingRate {
  double get multiplier {
    switch (this) {
      case BillingRate.full:
        return 1.0;
      case BillingRate.discounted:
        return 0.25;
    }
  }
}

// =============================================================================
// BillingTicker (전역 과금 타이머 싱글톤)
// =============================================================================

const String _kBillingRegion = 'us-central1';

class BillingTicker {
  static final BillingTicker instance = BillingTicker._();
  BillingTicker._();

  final ValueNotifier<int> remainingSecondsNotifier = ValueNotifier<int>(0);

  Timer? _tickTimer;
  BillingRate _rate = BillingRate.discounted;
  bool _paused = true;
  double _fractionalDebt = 0.0;
  int _unflushedDeducted = 0;
  DateTime _lastFlushAt = DateTime.now();
  String? _lastFlushResult;
  final List<Map<String, dynamic>> _history = [];
  static const int _kMaxHistory = 10;

  BillingRate get currentRate => _rate;
  bool get isPaused => _paused;
  double get fractionalDebt => _fractionalDebt;
  int get unflushedDeducted => _unflushedDeducted;
  DateTime get lastFlushAt => _lastFlushAt;
  String? get lastFlushResult => _lastFlushResult;
  List<Map<String, dynamic>> get history => List.unmodifiable(_history);

  void start() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void setRate(BillingRate rate) {
    _rate = rate;
  }

  void pause() {
    _paused = true;
    flushNow();
  }

  void resume() {
    _paused = false;
  }

  void _onTick() {
    if (_paused) return;
    if (FFAppState().remainingTime <= 0) return;

    _fractionalDebt += _rate.multiplier;
    final whole = _fractionalDebt.floor();
    if (whole >= 1) {
      _fractionalDebt -= whole;
      final next = (FFAppState().remainingTime - whole).clamp(0, 1 << 31);
      FFAppState().remainingTime = next;
      _unflushedDeducted += whole;
      remainingSecondsNotifier.value = next;
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
      _lastFlushResult =
          'OK (-${seconds}s) @ ${DateTime.now().toIso8601String().substring(11, 19)}';
    }
  }
}
