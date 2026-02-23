import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/ble_provider.dart';
import '../providers/auth_provider.dart';
import '../config/theme.dart';
import '../widgets/vital_card.dart';
import '../widgets/risk_indicator.dart';
import '../widgets/ble_status_chip.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

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

  double _hrNormalized(double hr) {
    if (hr < 1) return 0;
    return ((hr - 40) / (160 - 40)).clamp(0.0, 1.0);
  }

  double _spo2Normalized(int spo2) {
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

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              Row(
                children: [
                  // Avatar circle
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppGradients.primary,
                    ),
                    child: Center(
                      child: Text(
                        (auth.user?.name ?? 'U')[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello, ${auth.user?.name.split(' ').first ?? 'User'}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        Text(
                          DateFormat('EEEE, MMM d').format(now),
                          style: TextStyle(
                            color: AppTheme.textSecondary(context),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  BleStatusChip(state: ble.connectionState),
                ],
              )
                  .animate()
                  .fadeIn(duration: 300.ms)
                  .slideX(begin: -0.03),
              const SizedBox(height: 24),

              // ── Vitals Grid ──
              Row(
                children: [
                  Expanded(
                    child: VitalCard(
                      label: 'Heart Rate',
                      value: v.heartRate > 0
                          ? v.heartRate.toStringAsFixed(0)
                          : '--',
                      unit: 'bpm',
                      icon: PhosphorIconsLight.heartbeat,
                      color: const Color(0xFFEF4444),
                      gradient: AppGradients.hr,
                      normalizedValue: _hrNormalized(v.heartRate),
                      statusLabel: _hrStatus(v.heartRate),
                    )
                        .animate()
                        .fadeIn(duration: 300.ms, delay: 50.ms)
                        .slideY(begin: 0.05),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: VitalCard(
                      label: 'Blood Oxygen',
                      value: v.spo2 > 0 ? '${v.spo2}' : '--',
                      unit: '%',
                      icon: PhosphorIconsLight.drop,
                      color: const Color(0xFF3B82F6),
                      gradient: AppGradients.spo2,
                      normalizedValue: _spo2Normalized(v.spo2),
                      statusLabel: _spo2Status(v.spo2),
                    )
                        .animate()
                        .fadeIn(duration: 300.ms, delay: 100.ms)
                        .slideY(begin: 0.05),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Risk Assessment ──
              _buildRiskCard(context, v.riskScore, v.riskLabel)
                  .animate()
                  .fadeIn(duration: 300.ms, delay: 150.ms)
                  .slideY(begin: 0.05),
              const SizedBox(height: 16),

              // ── Device Status ──
              _buildDeviceStatus(context, v)
                  .animate()
                  .fadeIn(duration: 300.ms, delay: 200.ms)
                  .slideY(begin: 0.05),

              // ── Connect Button ──
              if (!connected) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushNamed('/device-setup');
                    },
                    icon: const Icon(PhosphorIconsLight.bluetooth, size: 20),
                    label: const Text(
                      'Connect Device',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent(context),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(duration: 300.ms, delay: 250.ms)
                    .slideY(begin: 0.05),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRiskCard(BuildContext context, double riskScore, String riskLabel) {
    final color = AppTheme.riskColor(riskScore);
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isLight
            ? color.withValues(alpha: 0.06)
            : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: isLight ? 0.1 : 0.15),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(PhosphorIconsLight.shieldCheck,
                    color: color, size: 14),
              ),
              const SizedBox(width: 8),
              Text(
                'RISK ASSESSMENT',
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              if (riskScore > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${(riskScore * 100).round()}%',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          RiskIndicator(
            score: riskScore,
            label: riskLabel,
            size: 140,
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceStatus(BuildContext context, dynamic v) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(16),
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
          Text(
            'DEVICE STATUS',
            style: TextStyle(
              color: AppTheme.textTertiary(context),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _statusDot(context, 'Sensor', v.sensorOk, PhosphorIconsLight.cpu),
              _statusDot(context, 'WiFi', v.wifiReady, PhosphorIconsLight.wifiHigh),
              _statusDot(context, 'ECG', !v.ecgLeadOff, PhosphorIconsLight.pulse),
              _statusDot(context, 'API', v.apiReady, PhosphorIconsLight.cloud),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusDot(BuildContext context, String label, bool ok, IconData icon) {
    final color = ok ? const Color(0xFF22C55E) : AppTheme.textTertiary(context);
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
