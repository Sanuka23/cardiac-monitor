import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import '../config/theme.dart';
import 'animated_value.dart';

class VitalCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final LinearGradient? gradient;
  final double? normalizedValue;
  final String? statusLabel;

  const VitalCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    this.gradient,
    this.normalizedValue,
    this.statusLabel,
  });

  @override
  Widget build(BuildContext context) {
    final numericValue = double.tryParse(value) ?? 0;
    final hasDecimals = value.contains('.');
    final isLight = Theme.of(context).brightness == Brightness.light;
    final percent = (normalizedValue ?? 0).clamp(0.0, 1.0);
    final hasData = value != '--';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLight
            ? color.withValues(alpha: 0.08)
            : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: isLight ? 0.12 : 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + Label
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Circular progress + value
          Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularPercentIndicator(
                    radius: 50,
                    lineWidth: 8,
                    percent: hasData ? percent : 0,
                    animation: true,
                    animationDuration: 800,
                    animateFromLastPercent: true,
                    circularStrokeCap: CircularStrokeCap.round,
                    backgroundColor: color.withValues(alpha: 0.1),
                    linearGradient: gradient ??
                        LinearGradient(
                          colors: [
                            color.withValues(alpha: 0.7),
                            color,
                          ],
                        ),
                    center: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedValue(
                          value: numericValue,
                          decimals: hasDecimals ? 1 : 0,
                          style: TextStyle(
                            color: AppTheme.textPrimary(context),
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          unit,
                          style: TextStyle(
                            color: AppTheme.textSecondary(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (statusLabel != null && statusLabel!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusLabel!,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
