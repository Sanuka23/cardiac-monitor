import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/ble_provider.dart';
import '../providers/auth_provider.dart';
import '../config/theme.dart';
import '../widgets/vital_card.dart';
import '../widgets/risk_indicator.dart';
import '../widgets/ble_status_chip.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final auth = context.watch<AuthProvider>();
    final v = ble.vitals;
    final connected = ble.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: BleStatusChip(state: ble.connectionState),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Greeting
            Text(
              'Hello, ${auth.user?.name ?? 'User'}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              connected ? 'Live monitoring active' : 'Connect device to begin',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
            const SizedBox(height: 24),

            // HR + SpO2 cards
            Row(
              children: [
                Expanded(
                  child: VitalCard(
                    label: 'Heart Rate',
                    value: v.heartRate > 0
                        ? v.heartRate.toStringAsFixed(1)
                        : '--.-',
                    unit: 'bpm',
                    icon: Icons.favorite,
                    color: AppTheme.hrColor(v.heartRate),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: VitalCard(
                    label: 'SpO2',
                    value: v.spo2 > 0 ? '${v.spo2}' : '--',
                    unit: '%',
                    icon: Icons.water_drop,
                    color: AppTheme.spo2Color(v.spo2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Risk assessment
            Card(
              color: const Color(0xFF161B22),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield_outlined,
                            color: Colors.grey[400], size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Risk Assessment',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    RiskIndicator(
                      score: v.riskScore,
                      label: v.riskLabel,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Device status chips
            Card(
              color: const Color(0xFF161B22),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device Status',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _statusChip('Sensor', v.sensorOk, Icons.sensors),
                        _statusChip('WiFi', v.wifiReady, Icons.wifi),
                        _statusChip(
                          'ECG Leads',
                          !v.ecgLeadOff,
                          Icons.cable,
                        ),
                        _statusChip('API', v.apiReady, Icons.cloud),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            if (!connected) ...[
              const SizedBox(height: 24),
              Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamed('/device-setup');
                  },
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Connect Device'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String label, bool ok, IconData icon) {
    final color = ok ? const Color(0xFF4CAF50) : Colors.grey[600]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
