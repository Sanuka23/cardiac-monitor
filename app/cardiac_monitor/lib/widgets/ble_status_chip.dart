import 'package:flutter/material.dart';
import '../services/ble_service.dart';

class BleStatusChip extends StatelessWidget {
  final BleConnectionState state;

  const BleStatusChip({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (state) {
      BleConnectionState.connected => ('Connected', const Color(0xFF4CAF50), Icons.bluetooth_connected),
      BleConnectionState.connecting => ('Connecting...', const Color(0xFFFFC107), Icons.bluetooth_searching),
      BleConnectionState.scanning => ('Scanning...', const Color(0xFF2196F3), Icons.bluetooth_searching),
      BleConnectionState.disconnected => ('Disconnected', Colors.grey, Icons.bluetooth_disabled),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
