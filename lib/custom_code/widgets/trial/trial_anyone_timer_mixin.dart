import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

mixin TrialAnyoneTimerMixin<T extends StatefulWidget> on State<T> {
  bool trialMode = false;
  int trialSeconds = 30;

  Timer? _trialTimer;
  int _trialRemaining = 30;
  bool _trialTimeUp = false;

  bool get isTrialTimeUp => _trialTimeUp;
  int get trialRemaining => _trialRemaining;

  void startTrialTimer() {
    if (!trialMode) return;
    _trialRemaining = trialSeconds;
    _trialTimeUp = false;
    _trialTimer?.cancel();
    _trialTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _trialTimer?.cancel();
        return;
      }
      setState(() {
        _trialRemaining--;
        if (_trialRemaining <= 0) {
          _trialRemaining = 0;
          _trialTimeUp = true;
          _trialTimer?.cancel();
        }
      });
    });
  }

  void disposeTrialTimer() {
    _trialTimer?.cancel();
    _trialTimer = null;
  }

  Widget buildTrialCountdown() {
    if (!trialMode) return const SizedBox.shrink();
    final minutes = _trialRemaining ~/ 60;
    final seconds = _trialRemaining % 60;
    return Positioned(
      top: 8,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: _trialRemaining <= 5
              ? const Color(0xFFFF4444).withValues(alpha: 0.85)
              : const Color(0xFF000000).withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
