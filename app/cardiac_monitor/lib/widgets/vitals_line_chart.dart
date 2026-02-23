import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class VitalsLineChart extends StatelessWidget {
  final List<FlSpot> spots;
  final Color lineColor;
  final String title;
  final double? minY;
  final double? maxY;
  final double? normalMin;
  final double? normalMax;

  const VitalsLineChart({
    super.key,
    required this.spots,
    required this.lineColor,
    required this.title,
    this.minY,
    this.maxY,
    this.normalMin,
    this.normalMax,
  });

  @override
  Widget build(BuildContext context) {
    if (spots.isEmpty) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Text('No data', style: TextStyle(color: Colors.grey[600])),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: _calcInterval(),
                getDrawingHorizontalLine: (value) => FlLine(
                  color: Colors.grey[800]!,
                  strokeWidth: 0.5,
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) => Text(
                      value.toInt().toString(),
                      style: TextStyle(color: Colors.grey[600], fontSize: 10),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: _calcTimeInterval(),
                    getTitlesWidget: (value, meta) {
                      final dt =
                          DateTime.fromMillisecondsSinceEpoch(value.toInt());
                      return Text(
                        DateFormat.Hm().format(dt),
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 10),
                      );
                    },
                  ),
                ),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              minY: minY,
              maxY: maxY,
              lineBarsData: [
                if (normalMin != null && normalMax != null)
                  LineChartBarData(
                    spots: [
                      FlSpot(spots.first.x, normalMax!),
                      FlSpot(spots.last.x, normalMax!),
                    ],
                    isCurved: false,
                    color: Colors.transparent,
                    belowBarData: BarAreaData(
                      show: true,
                      color: lineColor.withValues(alpha: 0.05),
                    ),
                    dotData: const FlDotData(show: false),
                    barWidth: 0,
                  ),
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.2,
                  color: lineColor,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: lineColor.withValues(alpha: 0.1),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touchedSpots) => touchedSpots
                      .map((spot) => LineTooltipItem(
                            spot.y.toStringAsFixed(1),
                            TextStyle(color: lineColor, fontSize: 12),
                          ))
                      .toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _calcInterval() {
    if (maxY != null && minY != null) {
      return ((maxY! - minY!) / 4).ceilToDouble().clamp(1, 100);
    }
    return 20;
  }

  double _calcTimeInterval() {
    if (spots.length < 2) return 60000;
    final range = spots.last.x - spots.first.x;
    if (range < 3600000) return 600000; // 10min intervals
    if (range < 86400000) return 3600000; // 1h intervals
    return 86400000; // 1d intervals
  }
}
