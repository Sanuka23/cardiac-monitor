import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/ble_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../config/theme.dart';
import '../widgets/vital_card.dart';
import '../widgets/risk_indicator.dart';
import '../widgets/ble_status_chip.dart';
import '../widgets/ecg_chart.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _ecgTimer;
  List<int>? _ecgSamples;
  int _sampleRateHz = 100;
  DateTime? _ecgTimestamp;
  bool _ecgLoading = false;

  @override
  void initState() {
    super.initState();
    // Fetch ECG on first load, then every 12 seconds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchEcg();
      _ecgTimer = Timer.periodic(const Duration(seconds: 12), (_) => _fetchEcg());
    });
  }

  @override
  void dispose() {
    _ecgTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchEcg() async {
    final auth = context.read<AuthProvider>();
    if (auth.deviceIds.isEmpty) return;
    if (_ecgLoading) return;

    setState(() => _ecgLoading = true);
    try {
      final api = context.read<ApiService>();
      final vitals = await api.getLatestVitalsWithEcg(auth.deviceIds.first);
      if (mounted && vitals != null) {
        setState(() {
          _ecgSamples = vitals.ecgSamples;
          _sampleRateHz = vitals.sampleRateHz ?? 100;
          _ecgTimestamp = vitals.timestamp;
        });
      }
    } catch (_) {
      // Silently fail — dashboard still shows BLE vitals
    } finally {
      if (mounted) setState(() => _ecgLoading = false);
    }
  }

  String _hrStatus(double hr) {
    if (hr < 1) return '';
    if (hr >= 60 && hr <= 100) return 'Normal';
    if (hr < 60) return 'Low';
    return 'High';
  }

  String _spo2Status(int spo2) {
    if (spo2 == 0) return '';
    if (spo2 >= 95) return 'Normal';
    if (spo2 >= 90) return 'Low';
    return 'Critical';
  }

  double _hrProgress(double hr) {
    if (hr < 1) return 0;
    return ((hr - 40) / (160 - 40)).clamp(0.0, 1.0);
  }

  double _spo2Progress(int spo2) {
    if (spo2 == 0) return 0;
    return ((spo2 - 80) / (100 - 80)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final auth = context.watch<AuthProvider>();
    final v = ble.vitals;
    final connected = ble.isConnected;
    final now = DateTime.now();
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Greeting Header ──
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello, ${auth.user?.name.split(' ').first ?? 'User'}',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary(context),
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('EEEE, MMMM d').format(now),
                          style: TextStyle(
                            color: AppTheme.textSecondary(context),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  BleStatusChip(state: ble.connectionState),
                ],
              )
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .slideX(begin: -0.02),
              const SizedBox(height: 28),

              // ── Vital Cards ──
              Row(
                children: [
                  Expanded(
                    child: VitalCard(
                      label: 'Heart Rate',
                      value: v.heartRate > 0
                          ? v.heartRate.toStringAsFixed(0)
                          : '--',
                      unit: 'bpm',
                      icon: PhosphorIconsBold.heartbeat,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF6B6B), Color(0xFFEE5A24)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      progress: _hrProgress(v.heartRate),
                      statusLabel: _hrStatus(v.heartRate),
                    )
                        .animate()
                        .fadeIn(duration: 400.ms, delay: 100.ms)
                        .slideY(begin: 0.08),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: VitalCard(
                      label: 'Blood Oxygen',
                      value: v.spo2 > 0 ? '${v.spo2}' : '--',
                      unit: '%SpO2',
                      icon: PhosphorIconsBold.drop,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      progress: _spo2Progress(v.spo2),
                      statusLabel: _spo2Status(v.spo2),
                    )
                        .animate()
                        .fadeIn(duration: 400.ms, delay: 150.ms)
                        .slideY(begin: 0.08),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Risk Assessment Card ──
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground(context),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: isLight
                          ? Colors.black.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.riskColor(v.riskScore)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            PhosphorIconsBold.shieldCheck,
                            color: AppTheme.riskColor(v.riskScore),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Risk Assessment',
                          style: TextStyle(
                            color: AppTheme.textPrimary(context),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    RiskIndicator(
                      score: v.riskScore,
                      label: v.riskLabel,
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 200.ms)
                  .slideY(begin: 0.08),
              const SizedBox(height: 24),

              // ── ECG Waveform Card ──
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground(context),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: isLight
                          ? Colors.black.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            PhosphorIconsBold.pulse,
                            color: Color(0xFF0D9488),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'ECG Waveform',
                            style: TextStyle(
                              color: AppTheme.textPrimary(context),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_ecgTimestamp != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceVariant(context),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              DateFormat.Hms().format(_ecgTimestamp!),
                              style: TextStyle(
                                color: AppTheme.textSecondary(context),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        if (_ecgLoading) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_ecgSamples != null && _ecgSamples!.isNotEmpty)
                      EcgChart(
                        samples: _ecgSamples!,
                        sampleRateHz: _sampleRateHz,
                      )
                    else
                      SizedBox(
                        height: 180,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                PhosphorIconsLight.pulse,
                                color: AppTheme.textTertiary(context),
                                size: 32,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No ECG data available',
                                style: TextStyle(
                                  color: AppTheme.textSecondary(context),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Connect device and attach ECG electrodes',
                                style: TextStyle(
                                  color: AppTheme.textTertiary(context),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 225.ms)
                  .slideY(begin: 0.08),
              const SizedBox(height: 24),

              // ── Device Status ──
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground(context),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: isLight
                          ? Colors.black.withValues(alpha: 0.04)
                          : Colors.black.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device Status',
                      style: TextStyle(
                        color: AppTheme.textSecondary(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _statusItem(context, 'Sensor', v.sensorOk,
                            PhosphorIconsLight.cpu),
                        _statusItem(context, 'WiFi', v.wifiReady,
                            PhosphorIconsLight.wifiHigh),
                        _statusItem(context, 'ECG', !v.ecgLeadOff,
                            PhosphorIconsLight.pulse),
                        _statusItem(context, 'API', v.apiReady,
                            PhosphorIconsLight.cloud),
                      ],
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 250.ms)
                  .slideY(begin: 0.08),

              // ── Connect Button ──
              if (!connected) ...[
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppGradients.primary,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0D9488).withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pushNamed('/device-setup'),
                      icon: const Icon(PhosphorIconsBold.bluetoothConnected,
                          size: 20),
                      label: const Text(
                        'Connect Device',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(duration: 400.ms, delay: 300.ms)
                    .slideY(begin: 0.08),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusItem(
      BuildContext context, String label, bool ok, IconData icon) {
    final color = ok ? const Color(0xFF22C55E) : AppTheme.textTertiary(context);
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: ok
                  ? const Color(0xFF22C55E).withValues(alpha: 0.1)
                  : AppTheme.surfaceVariant(context),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
