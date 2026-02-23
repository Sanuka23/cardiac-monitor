import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../providers/vitals_provider.dart';
import '../providers/auth_provider.dart';
import '../config/theme.dart';
import '../widgets/vitals_line_chart.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _rangeHours = 24;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final auth = context.read<AuthProvider>();
    if (auth.deviceIds.isEmpty) return;
    final deviceId = auth.deviceIds.first;

    final limit = switch (_rangeHours) {
      24 => 200,
      168 => 500,
      _ => 1000,
    };

    context.read<VitalsProvider>().loadHistory(deviceId, limit: limit);
  }

  @override
  Widget build(BuildContext context) {
    final vitals = context.watch<VitalsProvider>();
    final auth = context.watch<AuthProvider>();

    if (auth.deviceIds.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.accent(context).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(PhosphorIconsLight.chartLine,
                    size: 40, color: AppTheme.accent(context)),
              ),
              const SizedBox(height: 16),
              Text('No device registered',
                  style: TextStyle(
                    color: AppTheme.textSecondary(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  )),
            ],
          ),
        ),
      );
    }

    final cutoff = DateTime.now().subtract(Duration(hours: _rangeHours));

    final filteredVitals = vitals.vitalsHistory
        .where((v) => v.timestamp.isAfter(cutoff))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final filteredPredictions = vitals.predictionHistory
        .where((p) => p.timestamp.isAfter(cutoff))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final hrValues = filteredVitals
        .where((v) => v.heartRate > 0)
        .map((v) => v.heartRate)
        .toList();
    final spo2Values = filteredVitals
        .where((v) => v.spo2 > 0)
        .map((v) => v.spo2.toDouble())
        .toList();

    final hrSpots = filteredVitals
        .where((v) => v.heartRate > 0)
        .map((v) => FlSpot(
              v.timestamp.millisecondsSinceEpoch.toDouble(),
              v.heartRate,
            ))
        .toList();

    final spo2Spots = filteredVitals
        .where((v) => v.spo2 > 0)
        .map((v) => FlSpot(
              v.timestamp.millisecondsSinceEpoch.toDouble(),
              v.spo2.toDouble(),
            ))
        .toList();

    final riskSpots = filteredPredictions
        .map((p) => FlSpot(
              p.timestamp.millisecondsSinceEpoch.toDouble(),
              p.riskScore,
            ))
        .toList();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _loadData(),
          color: AppTheme.accent(context),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trends',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(context),
                  ),
                ).animate().fadeIn(duration: 300.ms),
                const SizedBox(height: 4),
                Text(
                  'Track your vitals over time',
                  style: TextStyle(
                    color: AppTheme.textSecondary(context),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),

                // Range selector
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _rangeTab('24h', 24),
                      _rangeTab('7d', 168),
                      _rangeTab('30d', 720),
                    ],
                  ),
                ).animate().fadeIn(duration: 300.ms, delay: 50.ms),
                const SizedBox(height: 20),

                if (vitals.loading)
                  ..._buildShimmerCharts()
                else if (vitals.error != null)
                  _buildErrorState()
                else ...[
                  // HR Section
                  _buildChartCard(
                    color: const Color(0xFFEF4444),
                    icon: PhosphorIconsLight.heartbeat,
                    title: 'Heart Rate',
                    unit: 'bpm',
                    values: hrValues,
                    chart: VitalsLineChart(
                      title: '',
                      spots: hrSpots,
                      lineColor: const Color(0xFFEF4444),
                      minY: 40,
                      maxY: 160,
                      normalMin: 60,
                      normalMax: 100,
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 300.ms, delay: 100.ms)
                      .slideY(begin: 0.05),
                  const SizedBox(height: 16),

                  // SpO2 Section
                  _buildChartCard(
                    color: const Color(0xFF3B82F6),
                    icon: PhosphorIconsLight.drop,
                    title: 'Blood Oxygen',
                    unit: '%',
                    values: spo2Values,
                    chart: VitalsLineChart(
                      title: '',
                      spots: spo2Spots,
                      lineColor: const Color(0xFF3B82F6),
                      minY: 85,
                      maxY: 100,
                      normalMin: 95,
                      normalMax: 100,
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 300.ms, delay: 150.ms)
                      .slideY(begin: 0.05),
                  const SizedBox(height: 16),

                  // Risk Section
                  _buildChartCard(
                    color: const Color(0xFFF97316),
                    icon: PhosphorIconsLight.shieldCheck,
                    title: 'Risk Score',
                    unit: '',
                    values: filteredPredictions.map((p) => p.riskScore).toList(),
                    chart: VitalsLineChart(
                      title: '',
                      spots: riskSpots,
                      lineColor: const Color(0xFFF97316),
                      minY: 0,
                      maxY: 1,
                    ),
                    formatValue: (v) => '${(v * 100).round()}%',
                  )
                      .animate()
                      .fadeIn(duration: 300.ms, delay: 200.ms)
                      .slideY(begin: 0.05),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChartCard({
    required Color color,
    required IconData icon,
    required String title,
    required String unit,
    required List<double> values,
    required Widget chart,
    String Function(double)? formatValue,
  }) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final fmt = formatValue ?? (v) => '${v.round()}';

    double minVal = 0, maxVal = 0, avgVal = 0;
    final hasStats = values.isNotEmpty;
    if (hasStats) {
      minVal = values.reduce((a, b) => a < b ? a : b);
      maxVal = values.reduce((a, b) => a > b ? a : b);
      avgVal = values.reduce((a, b) => a + b) / values.length;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.dividerColor(context)),
        boxShadow: isLight
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with colored accent
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isLight ? 0.06 : 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 14, color: color),
                ),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    '($unit)',
                    style: TextStyle(
                      color: color.withValues(alpha: 0.6),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Stats row
          if (hasStats)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _statItem('Min', fmt(minVal), color),
                  _statDivider(),
                  _statItem('Avg', fmt(avgVal), color),
                  _statDivider(),
                  _statItem('Max', fmt(maxVal), color),
                ],
              ),
            ),

          // Chart
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SizedBox(height: 160, child: chart),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textTertiary(context),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(
      width: 1,
      height: 28,
      color: AppTheme.dividerColor(context),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(PhosphorIconsLight.warning,
                  size: 32, color: Colors.red[400]),
            ),
            const SizedBox(height: 12),
            Text(
              'Error loading data',
              style: TextStyle(
                color: AppTheme.textPrimary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pull down to retry',
              style: TextStyle(
                color: AppTheme.textSecondary(context),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildShimmerCharts() {
    return List.generate(
      3,
      (i) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Shimmer.fromColors(
          baseColor: AppTheme.surfaceVariant(context),
          highlightColor: AppTheme.cardBackground(context),
          child: Container(
            height: 240,
            decoration: BoxDecoration(
              color: AppTheme.cardBackground(context),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rangeTab(String label, int hours) {
    final selected = _rangeHours == hours;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _rangeHours = hours);
          _loadData();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppTheme.textSecondary(context),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
