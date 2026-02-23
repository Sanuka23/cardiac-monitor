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
    final limit = switch (_rangeHours) {
      24 => 200,
      168 => 500,
      _ => 1000,
    };

    // User-based query — loads vitals across all user's devices
    context.read<VitalsProvider>().loadMyHistory(limit: limit);
  }

  @override
  Widget build(BuildContext context) {
    final vitals = context.watch<VitalsProvider>();
    final auth = context.watch<AuthProvider>();
    final isLight = Theme.of(context).brightness == Brightness.light;

    if (auth.deviceIds.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: AppGradients.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(PhosphorIconsLight.chartLineUp,
                    size: 40, color: Colors.white),
              ),
              const SizedBox(height: 20),
              Text('No device registered',
                  style: TextStyle(
                    color: AppTheme.textPrimary(context),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 6),
              Text('Connect a device to see trends',
                  style: TextStyle(
                    color: AppTheme.textSecondary(context),
                    fontSize: 14,
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
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──
                Text(
                  'Trends',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary(context),
                  ),
                ).animate().fadeIn(duration: 400.ms),
                const SizedBox(height: 6),
                Text(
                  'Track your vitals over time',
                  style: TextStyle(
                    color: AppTheme.textSecondary(context),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Time Range Selector ──
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant(context),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      _rangeTab('24h', 24),
                      _rangeTab('7d', 168),
                      _rangeTab('30d', 720),
                    ],
                  ),
                ).animate().fadeIn(duration: 400.ms, delay: 50.ms),
                const SizedBox(height: 28),

                if (vitals.loading)
                  ..._buildShimmerCharts()
                else if (vitals.error != null)
                  _buildErrorState()
                else ...[
                  // ── Summary Stats ──
                  if (hrValues.isNotEmpty || spo2Values.isNotEmpty)
                    _buildSummaryRow(hrValues, spo2Values, isLight)
                        .animate()
                        .fadeIn(duration: 400.ms, delay: 100.ms)
                        .slideY(begin: 0.06),
                  const SizedBox(height: 24),

                  // ── Heart Rate Chart ──
                  _buildChartCard(
                    color: const Color(0xFFFF6B6B),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6B6B), Color(0xFFEE5A24)],
                    ),
                    icon: PhosphorIconsBold.heartbeat,
                    title: 'Heart Rate',
                    spots: hrSpots,
                    chart: VitalsLineChart(
                      title: '',
                      spots: hrSpots,
                      lineColor: const Color(0xFFFF6B6B),
                      minY: 40,
                      maxY: 160,
                      normalMin: 60,
                      normalMax: 100,
                    ),
                    isLight: isLight,
                  )
                      .animate()
                      .fadeIn(duration: 400.ms, delay: 150.ms)
                      .slideY(begin: 0.06),
                  const SizedBox(height: 20),

                  // ── SpO2 Chart ──
                  _buildChartCard(
                    color: const Color(0xFF667EEA),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                    ),
                    icon: PhosphorIconsBold.drop,
                    title: 'Blood Oxygen',
                    spots: spo2Spots,
                    chart: VitalsLineChart(
                      title: '',
                      spots: spo2Spots,
                      lineColor: const Color(0xFF667EEA),
                      minY: 85,
                      maxY: 100,
                      normalMin: 95,
                      normalMax: 100,
                    ),
                    isLight: isLight,
                  )
                      .animate()
                      .fadeIn(duration: 400.ms, delay: 200.ms)
                      .slideY(begin: 0.06),
                  const SizedBox(height: 20),

                  // ── Risk Chart ──
                  _buildChartCard(
                    color: const Color(0xFFF97316),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF97316), Color(0xFFEF4444)],
                    ),
                    icon: PhosphorIconsBold.shieldCheck,
                    title: 'Risk Score',
                    spots: riskSpots,
                    chart: VitalsLineChart(
                      title: '',
                      spots: riskSpots,
                      lineColor: const Color(0xFFF97316),
                      minY: 0,
                      maxY: 1,
                    ),
                    isLight: isLight,
                  )
                      .animate()
                      .fadeIn(duration: 400.ms, delay: 250.ms)
                      .slideY(begin: 0.06),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Summary Row ──
  Widget _buildSummaryRow(
      List<double> hrValues, List<double> spo2Values, bool isLight) {
    return Row(
      children: [
        if (hrValues.isNotEmpty) ...[
          Expanded(
            child: _summaryCard(
              label: 'Avg HR',
              value:
                  '${(hrValues.reduce((a, b) => a + b) / hrValues.length).round()}',
              unit: 'bpm',
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B6B), Color(0xFFEE5A24)],
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        if (spo2Values.isNotEmpty) ...[
          Expanded(
            child: _summaryCard(
              label: 'Avg SpO2',
              value:
                  '${(spo2Values.reduce((a, b) => a + b) / spo2Values.length).round()}',
              unit: '%',
              gradient: const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: _summaryCard(
            label: 'Readings',
            value: '${filteredVitals.length}',
            unit: 'total',
            gradient: AppGradients.primary,
          ),
        ),
      ],
    );
  }

  List<dynamic> get filteredVitals {
    final cutoff = DateTime.now().subtract(Duration(hours: _rangeHours));
    return context
        .read<VitalsProvider>()
        .vitalsHistory
        .where((v) => v.timestamp.isAfter(cutoff))
        .toList();
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required String unit,
    required LinearGradient gradient,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.first.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      height: 1)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(unit,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Chart Card ──
  Widget _buildChartCard({
    required Color color,
    required LinearGradient gradient,
    required IconData icon,
    required String title,
    required List<FlSpot> spots,
    required Widget chart,
    required bool isLight,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: isLight
                ? Colors.black.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Gradient header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                if (spots.isNotEmpty)
                  Text('${spots.length} points',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 11)),
              ],
            ),
          ),
          // Chart
          if (spots.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text('No data in this range',
                  style: TextStyle(
                      color: AppTheme.textTertiary(context), fontSize: 13)),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
              child: SizedBox(height: 180, child: chart),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(PhosphorIconsLight.warning,
                size: 32, color: Color(0xFFEF4444)),
          ),
          const SizedBox(height: 16),
          Text('Could not load data',
              style: TextStyle(
                  color: AppTheme.textPrimary(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Pull down to retry',
              style: TextStyle(
                  color: AppTheme.textSecondary(context), fontSize: 13)),
        ],
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
              borderRadius: BorderRadius.circular(24),
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
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppTheme.accent(context).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : AppTheme.textSecondary(context),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
