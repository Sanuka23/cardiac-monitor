import 'dart:math';
import 'package:flutter/material.dart';
import '../config/theme.dart';

class RiskIndicator extends StatelessWidget {
  final double score;
  final String label;
  final double size;

  const RiskIndicator({
    super.key,
    required this.score,
    required this.label,
    this.size = 160,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.riskColor(score);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RiskArcPainter(score: score, color: color),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                score > 0 ? score.toStringAsFixed(2) : '--',
                style: TextStyle(
                  color: color,
                  fontSize: size * 0.22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label.isNotEmpty ? label.toUpperCase() : 'N/A',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: size * 0.085,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RiskArcPainter extends CustomPainter {
  final double score;
  final Color color;

  _RiskArcPainter({required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    const startAngle = 0.75 * pi;
    const sweepTotal = 1.5 * pi;

    // Background arc
    final bgPaint = Paint()
      ..color = Colors.grey[800]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotal,
      false,
      bgPaint,
    );

    // Value arc
    if (score > 0) {
      final valuePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepTotal * score.clamp(0, 1),
        false,
        valuePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RiskArcPainter old) =>
      old.score != score || old.color != color;
}
