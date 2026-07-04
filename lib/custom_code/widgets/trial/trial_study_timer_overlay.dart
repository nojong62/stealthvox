import 'dart:async';
import 'package:flutter/material.dart';

class TrialStudyTimerOverlay extends StatefulWidget {
  const TrialStudyTimerOverlay({
    super.key,
    this.durationSeconds = 120,
    required this.onTimeUp,
  });

  final int durationSeconds;
  final VoidCallback onTimeUp;

  @override
  State<TrialStudyTimerOverlay> createState() => _TrialStudyTimerOverlayState();
}

class _TrialStudyTimerOverlayState extends State<TrialStudyTimerOverlay> {
  late int _remaining;
  Timer? _timer;
  bool _showEndMessage = false;
  bool _didComplete = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.durationSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _timer?.cancel();
        return;
      }
      setState(() {
        _remaining--;
        if (_remaining <= 0) {
          _remaining = 0;
          _timer?.cancel();
          _showEndMessage = true;
        }
      });
      if (_remaining <= 0 && !_didComplete) {
        _didComplete = true;
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) widget.onTimeUp();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showEndMessage) return _buildEndMessage();
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: _remaining <= 10
              ? const Color(0xFFFF4444).withValues(alpha: 0.85)
              : const Color(0xFF000000).withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '${(_remaining ~/ 60).toString().padLeft(2, '0')}:${(_remaining % 60).toString().padLeft(2, '0')}',
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

  Widget _buildEndMessage() {
    return Container(
      color: const Color(0xCC1A1A2E),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bookmark_added, size: 48, color: Color(0xFFD4AF37)),
              SizedBox(height: 16),
              Text(
                'Your conversation was saved.\nRecharge to keep studying.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Moving to sign up...',
                style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
