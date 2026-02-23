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
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularPercentIndicator(
          radius: size / 2,
          lineWidth: 12,
          percent: clampedScore,
          animation: true,
          animationDuration: 800,
          animateFromLastPercent: true,
          circularStrokeCap: CircularStrokeCap.round,
          backgroundColor: isLight
              ? Colors.black.withValues(alpha: 0.05)
              : Colors.white.withValues(alpha: 0.06),
          linearGradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.6),
              color,
            ],
          ),
          center: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                score > 0 ? '${(score * 100).round()}' : '--',
                style: TextStyle(
                  color: AppTheme.textPrimary(context),
                  fontSize: size * 0.28,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              Text(
                '%',
                style: TextStyle(
                  color: AppTheme.textSecondary(context),
                  fontSize: size * 0.1,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label.isNotEmpty ? label : 'N/A',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
