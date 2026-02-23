import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Renders an ECG waveform from raw ADC samples.
///
/// Downsamples to ~200 points for smooth rendering performance.
/// X-axis shows time in seconds, Y-axis shows raw ADC values.
class EcgChart extends StatelessWidget {
  final List<int> samples;
  final int sampleRateHz;

  const EcgChart({
    super.key,
    required this.samples,
    this.sampleRateHz = 100,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final gridColor = isLight ? Colors.grey[300]! : Colors.grey[800]!;
    final labelColor = isLight ? Colors.grey[600]! : Colors.grey[500]!;
    const lineColor = Color(0xFF0D9488);

    if (samples.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text('No ECG data', style: TextStyle(color: labelColor)),
        ),
      );
    }

    // Downsample: pick every Nth sample to get ~200 points
    final step = max(1, samples.length ~/ 200);
    final spots = <FlSpot>[];
    for (int i = 0; i < samples.length; i += step) {
      final timeSec = i / sampleRateHz;
      spots.add(FlSpot(timeSec, samples[i].toDouble()));
    }

    // Compute Y range with padding
    double minVal = spots.first.y;
    double maxVal = spots.first.y;
    for (final s in spots) {
      if (s.y < minVal) minVal = s.y;
      if (s.y > maxVal) maxVal = s.y;
    }
    final range = maxVal - minVal;
    final padding = range * 0.1;
    final yMin = minVal - padding;
    final yMax = maxVal + padding;
    final totalSec = samples.length / sampleRateHz;

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: range > 0 ? (range / 4).ceilToDouble() : 100,
            verticalInterval: 1,
            getDrawingHorizontalLine: (value) =>
                FlLine(color: gridColor, strokeWidth: 0.3),
            getDrawingVerticalLine: (value) =>
                FlLine(color: gridColor, strokeWidth: 0.3),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: totalSec > 5 ? 2 : 1,
                getTitlesWidget: (value, meta) {
                  if (value < 0 || value > totalSec) return const SizedBox();
                  return Text(
                    '${value.toInt()}s',
                    style: TextStyle(color: labelColor, fontSize: 10),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: totalSec,
          minY: yMin,
          maxY: yMax,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.15,
              color: lineColor,
              barWidth: 1.5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: lineColor.withValues(alpha: 0.08),
              ),
            ),
          ],
          lineTouchData: const LineTouchData(enabled: false),
        ),
      ),
    );
  }
}
