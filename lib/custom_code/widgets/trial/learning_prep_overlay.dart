import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class LearningPrepOverlay {
  static Future<void> show(
    BuildContext context, {
    required DocumentReference historyRef,
    required void Function(DocumentReference ref) onReady,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xE01A1A2E),
      builder: (ctx) {
        return _LearningPrepContent(
          historyRef: historyRef,
          onReady: (ref) {
            Navigator.pop(ctx);
            onReady(ref);
          },
        );
      },
    );
  }
}

class _LearningPrepContent extends StatefulWidget {
  const _LearningPrepContent({required this.historyRef, required this.onReady});

  final DocumentReference historyRef;
  final void Function(DocumentReference ref) onReady;

  @override
  State<_LearningPrepContent> createState() => _LearningPrepContentState();
}

class _LearningPrepContentState extends State<_LearningPrepContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressCtrl;

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..forward();
    Timer(const Duration(milliseconds: 2600), () {
      if (mounted) widget.onReady(widget.historyRef);
    });
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_stories, size: 48, color: Color(0xFFD4AF37)),
            const SizedBox(height: 20),
            const Text(
              'Building your study room...',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your conversation is being prepared as practice material.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 13),
            ),
            const SizedBox(height: 24),
            AnimatedBuilder(
              animation: _progressCtrl,
              builder: (_, __) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progressCtrl.value,
                  backgroundColor: const Color(0xFF2A2A3E),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFFD4AF37)),
                  minHeight: 6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
