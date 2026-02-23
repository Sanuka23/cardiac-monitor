import 'package:flutter/material.dart';
import '../config/theme.dart';

class RiskIndicator extends StatelessWidget {
  final double score;
  final String label;

  const RiskIndicator({
    super.key,
    required this.score,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.riskColor(score);
    final clamped = score.clamp(0.0, 1.0);
    final hasData = score > 0;
    final percentage = (clamped * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Score + label row
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              hasData ? '$percentage' : '--',
              style: TextStyle(
                color: color,
                fontSize: 48,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            if (hasData) ...[
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '%',
                  style: TextStyle(
                    color: color.withValues(alpha: 0.7),
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label.isNotEmpty ? label : 'N/A',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Gradient progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: Stack(
              children: [
                // Background track with gradient
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF22C55E),
                        Color(0xFF84CC16),
                        Color(0xFFEAB308),
                        Color(0xFFF97316),
                        Color(0xFFEF4444),
                      ],
                    ),
                  ),
                ),
                // Overlay to dim unfilled portion
                if (hasData)
                  FractionallySizedBox(
                    alignment: Alignment.centerRight,
                    widthFactor: 1 - clamped,
                    child: Container(
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.white.withValues(alpha: 0.75)
                          : Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
                if (!hasData)
                  Container(
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.white.withValues(alpha: 0.75)
                        : Colors.black.withValues(alpha: 0.6),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Scale labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Low',
                style: TextStyle(
                    color: AppTheme.textTertiary(context),
                    fontSize: 10,
                    fontWeight: FontWeight.w500)),
            Text('High',
                style: TextStyle(
                    color: AppTheme.textTertiary(context),
                    fontSize: 10,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }
}
