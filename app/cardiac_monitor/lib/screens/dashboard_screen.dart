import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/ble_provider.dart';
import '../providers/auth_provider.dart';
import '../config/theme.dart';
import '../widgets/vital_card.dart';
import '../widgets/risk_indicator.dart';
import '../widgets/ble_status_chip.dart';
import '../widgets/glass_card.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final auth = context.watch<AuthProvider>();
    final v = ble.vitals;
    final connected = ble.isConnected;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hello, ${auth.user?.name ?? 'User'}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            connected
                                ? 'Live monitoring active'
                                : 'Connect device to begin',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
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
                    .fadeIn(duration: 500.ms)
                    .slideX(begin: -0.05),
                const SizedBox(height: 24),

                // HR + SpO2 cards
                Row(
                  children: [
                    Expanded(
                      child: VitalCard(
                        label: 'Heart Rate',
                        value: v.heartRate > 0
                            ? v.heartRate.toStringAsFixed(1)
                            : '--',
                        unit: 'bpm',
                        icon: PhosphorIconsLight.heartbeat,
                        color: AppTheme.hrColor(v.heartRate),
                        gradient: AppGradients.hr,
                      )
                          .animate()
                          .fadeIn(duration: 500.ms, delay: 100.ms)
                          .slideY(begin: 0.15),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: VitalCard(
                        label: 'SpO2',
                        value: v.spo2 > 0 ? '${v.spo2}' : '--',
                        unit: '%',
                        icon: PhosphorIconsLight.drop,
                        color: AppTheme.spo2Color(v.spo2),
                        gradient: AppGradients.spo2,
                      )
                          .animate()
                          .fadeIn(duration: 500.ms, delay: 200.ms)
                          .slideY(begin: 0.15),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Risk assessment
                GlassCard(
                  topAccent: AppGradients.risk,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color:
                                  const Color(0xFFFF9800).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(PhosphorIconsLight.shieldCheck,
                                color: Color(0xFFFF9800), size: 18),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'RISK ASSESSMENT',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const Spacer(),
                          if (v.riskScore > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.riskColor(v.riskScore)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${(v.riskScore * 100).round()}%',
                                style: TextStyle(
                                  color: AppTheme.riskColor(v.riskScore),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      RiskIndicator(
                        score: v.riskScore,
                        label: v.riskLabel,
                        size: 150,
                      ),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 300.ms)
                    .slideY(begin: 0.15),
                const SizedBox(height: 14),

                // Device status
                GlassCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DEVICE STATUS',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _statusChip('Sensor', v.sensorOk, PhosphorIconsLight.cpu),
                          const SizedBox(width: 8),
                          _statusChip('WiFi', v.wifiReady, PhosphorIconsLight.wifiHigh),
                          const SizedBox(width: 8),
                          _statusChip(
                              'ECG', !v.ecgLeadOff, PhosphorIconsLight.pulse),
                          const SizedBox(width: 8),
                          _statusChip('API', v.apiReady, PhosphorIconsLight.cloud),
                        ],
                      ),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 400.ms)
                    .slideY(begin: 0.15),

                if (!connected) ...[
                  const SizedBox(height: 24),
                  Center(
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppGradients.primary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pushNamed('/device-setup');
                          },
                          icon: const Icon(PhosphorIconsLight.bluetooth,
                              color: Colors.white),
                          label: const Text(
                            'Connect Device',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 500.ms)
                      .slideY(begin: 0.15),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String label, bool ok, IconData icon) {
    final color = ok ? const Color(0xFF4CAF50) : AppTheme.textSecondary;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
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
      ),
    );
  }
}
