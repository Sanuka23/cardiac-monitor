import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
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
    final clampedScore = score.clamp(0.0, 1.0);

    return CircularPercentIndicator(
      radius: size / 2,
      lineWidth: 10,
      percent: clampedScore,
      animation: true,
      animationDuration: 800,
      animateFromLastPercent: true,
      circularStrokeCap: CircularStrokeCap.round,
      backgroundColor: Theme.of(context).brightness == Brightness.light
          ? Colors.black.withValues(alpha: 0.06)
          : Colors.white.withValues(alpha: 0.06),
      linearGradient: LinearGradient(
        colors: [
          color.withValues(alpha: 0.7),
          color,
        ],
      ),
      center: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            score > 0 ? score.toStringAsFixed(2) : '--',
            style: TextStyle(
              color: AppTheme.textPrimary(context),
              fontSize: size * 0.22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label.isNotEmpty ? label.toUpperCase() : 'N/A',
              style: TextStyle(
                color: color,
                fontSize: size * 0.075,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
