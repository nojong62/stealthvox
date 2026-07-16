import 'dart:math' as math;

import 'package:flutter/material.dart';

class AuthProgressView extends StatefulWidget {
  const AuthProgressView({
    super.key,
    this.compact = false,
    this.showStepLabel = true,
    this.accentColor = const Color(0xFFD4AF37),
  });

  final bool compact;
  final bool showStepLabel;
  final Color accentColor;

  @override
  State<AuthProgressView> createState() => _AuthProgressViewState();
}

class _AuthProgressViewState extends State<AuthProgressView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _steps = [
    '계정 확인중',
    '학습 기록 연결 중',
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.compact ? const Color(0xFF202020) : Colors.white;
    final mutedColor =
        widget.compact ? const Color(0xFF6F6F76) : const Color(0xFFB6B6C2);
    final panelColor =
        widget.compact ? const Color(0xFFF8F8F8) : const Color(0xFF18181D);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final stepIndex =
            (_controller.value * _steps.length).floor() % _steps.length;
        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 18 : 24,
            vertical: widget.compact ? 22 : 30,
          ),
          decoration: BoxDecoration(
            color: panelColor,
            borderRadius: BorderRadius.circular(widget.compact ? 14 : 18),
            border: Border.all(
              color: (widget.compact ? Colors.black : Colors.white)
                  .withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: widget.compact ? 118 : 148,
                height: widget.compact ? 72 : 88,
                child: CustomPaint(
                  painter: _AuthProgressPainter(
                    progress: _controller.value,
                    accentColor: widget.accentColor,
                    compact: widget.compact,
                  ),
                ),
              ),
              SizedBox(height: widget.compact ? 16 : 22),
              if (widget.showStepLabel) ...[
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: Text(
                    _steps[stepIndex],
                    key: ValueKey(stepIndex),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textColor,
                      fontSize: widget.compact ? 15 : 17,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                '잠시만 기다려 주세요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: mutedColor,
                  fontSize: widget.compact ? 12 : 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: 0.18 + (_controller.value * 0.76),
                  minHeight: 5,
                  backgroundColor:
                      (widget.compact ? Colors.black : Colors.white)
                          .withValues(alpha: 0.10),
                  valueColor: AlwaysStoppedAnimation(widget.accentColor),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AuthProgressPainter extends CustomPainter {
  const _AuthProgressPainter({
    required this.progress,
    required this.accentColor,
    required this.compact,
  });

  final double progress;
  final Color accentColor;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final basePaint = Paint()
      ..color = compact ? const Color(0xFFE9E9ED) : const Color(0xFF272730)
      ..style = PaintingStyle.fill;
    final accentPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: compact ? 0.10 : 0.24)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final center = Offset(size.width * 0.50, size.height * 0.52);
    final radius = size.height * 0.24;
    final pulse = (math.sin(progress * math.pi * 2) + 1) / 2;

    canvas.drawCircle(
      Offset(center.dx, center.dy + 5),
      radius * (1.04 + pulse * 0.08),
      shadowPaint,
    );
    canvas.drawCircle(center, radius * (1.18 + pulse * 0.08), basePaint);
    canvas.drawCircle(center, radius, accentPaint);

    final bubblePaint = Paint()
      ..color = const Color(0xFF191919)
      ..style = PaintingStyle.fill;
    final tailPath = Path()
      ..moveTo(center.dx + radius * 0.20, center.dy + radius * 0.66)
      ..lineTo(center.dx + radius * 0.50, center.dy + radius * 0.92)
      ..lineTo(center.dx + radius * 0.42, center.dy + radius * 0.55)
      ..close();
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center,
          width: radius * 1.26,
          height: radius * 0.82,
        ),
        Radius.circular(radius * 0.38),
      ),
      bubblePaint,
    );
    canvas.drawPath(tailPath, bubblePaint);

    for (var i = 0; i < 3; i++) {
      final local = ((progress + i * 0.22) % 1.0);
      final x = size.width * (0.16 + i * 0.34);
      final y = size.height * (0.72 - local * 0.44);
      final dotRadius = size.height * (0.045 + (1 - local) * 0.025);
      final dotPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.22 + (1 - local) * 0.50);
      canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuthProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.compact != compact;
  }
}
