import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
        appBar: AppBar(title: const Text('History')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.devices, size: 48, color: Colors.grey[600]),
              const SizedBox(height: 16),
              Text('No device registered',
                  style: TextStyle(color: Colors.grey[500])),
            ],
          ),
        ),
      );
    }

    final cutoff =
        DateTime.now().subtract(Duration(hours: _rangeHours));

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
      appBar: AppBar(title: const Text('History')),
      body: RefreshIndicator(
        onRefresh: () async => _loadData(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Range chips
              Row(
                children: [
                  _rangeChip('24h', 24),
                  const SizedBox(width: 8),
                  _rangeChip('7d', 168),
                  const SizedBox(width: 8),
                  _rangeChip('30d', 720),
                ],
              ),
              const SizedBox(height: 24),

              if (vitals.loading)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ))
              else if (vitals.error != null)
                Center(
                  child: Text(
                    'Error loading data',
                    style: TextStyle(color: Colors.red[400]),
                  ),
                )
              else ...[
                VitalsLineChart(
                  title: 'Heart Rate (bpm)',
                  spots: hrSpots,
                  lineColor: AppTheme.riskNormal,
                  minY: 40,
                  maxY: 160,
                  normalMin: 60,
                  normalMax: 100,
                ),
                const SizedBox(height: 32),
                VitalsLineChart(
                  title: 'SpO2 (%)',
                  spots: spo2Spots,
                  lineColor: const Color(0xFF42A5F5),
                  minY: 85,
                  maxY: 100,
                  normalMin: 95,
                  normalMax: 100,
                ),
                const SizedBox(height: 32),
                VitalsLineChart(
                  title: 'Risk Score',
                  spots: riskSpots,
                  lineColor: AppTheme.riskElevated,
                  minY: 0,
                  maxY: 1,
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _rangeChip(String label, int hours) {
    final selected = _rangeHours == hours;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _rangeHours = hours);
        _loadData();
      },
      selectedColor: const Color(0xFF00BFA5),
      labelStyle: TextStyle(
        color: selected ? Colors.black : Colors.grey[400],
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
