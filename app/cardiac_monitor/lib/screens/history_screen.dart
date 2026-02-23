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
import '../widgets/glass_card.dart';

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
        body: Container(
          decoration: const BoxDecoration(gradient: AppGradients.background),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIconsLight.chartLine, size: 48, color: AppTheme.textSecondary),
                const SizedBox(height: 16),
                const Text('No device registered',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ],
            ),
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
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async => _loadData(),
            color: AppTheme.accent,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'History',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ).animate().fadeIn(duration: 400.ms),
                  const SizedBox(height: 6),
                  const Text(
                    'Track your vitals over time',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Range chips
                  Row(
                    children: [
                      _rangeChip('24h', 24),
                      const SizedBox(width: 10),
                      _rangeChip('7d', 168),
                      const SizedBox(width: 10),
                      _rangeChip('30d', 720),
                    ],
                  ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                  const SizedBox(height: 24),

                  if (vitals.loading)
                    ..._buildShimmerCharts()
                  else if (vitals.error != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          children: [
                            Icon(PhosphorIconsLight.warning,
                                size: 40, color: Colors.red[400]),
                            const SizedBox(height: 12),
                            Text(
                              'Error loading data',
                              style: TextStyle(color: Colors.red[400]),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    _chartSection(
                      title: 'Heart Rate',
                      unit: 'bpm',
                      icon: PhosphorIconsLight.heartbeat,
                      gradient: AppGradients.hr,
                      child: VitalsLineChart(
                        title: '',
                        spots: hrSpots,
                        lineColor: const Color(0xFF00BFA5),
                        minY: 40,
                        maxY: 160,
                        normalMin: 60,
                        normalMax: 100,
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 500.ms, delay: 200.ms)
                        .slideY(begin: 0.1),
                    const SizedBox(height: 16),
                    _chartSection(
                      title: 'SpO2',
                      unit: '%',
                      icon: PhosphorIconsLight.drop,
                      gradient: AppGradients.spo2,
                      child: VitalsLineChart(
                        title: '',
                        spots: spo2Spots,
                        lineColor: const Color(0xFF448AFF),
                        minY: 85,
                        maxY: 100,
                        normalMin: 95,
                        normalMax: 100,
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 500.ms, delay: 300.ms)
                        .slideY(begin: 0.1),
                    const SizedBox(height: 16),
                    _chartSection(
                      title: 'Risk Score',
                      unit: '',
                      icon: PhosphorIconsLight.shieldCheck,
                      gradient: AppGradients.risk,
                      child: VitalsLineChart(
                        title: '',
                        spots: riskSpots,
                        lineColor: const Color(0xFFFF9800),
                        minY: 0,
                        maxY: 1,
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 500.ms, delay: 400.ms)
                        .slideY(begin: 0.1),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chartSection({
    required String title,
    required String unit,
    required IconData icon,
    required Gradient gradient,
    required Widget child,
  }) {
    return GlassCard(
      topAccent: gradient,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              Text(
                '${title.toUpperCase()} ${unit.isNotEmpty ? "($unit)" : ""}',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(height: 180, child: child),
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
          baseColor: AppTheme.surfaceLight,
          highlightColor: AppTheme.cardBg,
          child: Container(
            height: 220,
            decoration: BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rangeChip(String label, int hours) {
    final selected = _rangeHours == hours;
    return GestureDetector(
      onTap: () {
        setState(() => _rangeHours = hours);
        _loadData();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected ? AppGradients.primary : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
