import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../config/theme.dart';

class BleStatusChip extends StatefulWidget {
  final BleConnectionState state;

  const BleStatusChip({super.key, required this.state});

  @override
  State<BleStatusChip> createState() => _BleStatusChipState();
}

class _BleStatusChipState extends State<BleStatusChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _updatePulse();
  }

  @override
  void didUpdateWidget(BleStatusChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _updatePulse();
  }

  void _updatePulse() {
    final isAnimating = widget.state == BleConnectionState.connecting ||
        widget.state == BleConnectionState.scanning;
    if (isAnimating) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disconnectedColor = AppTheme.textSecondary(context);
    final (label, color, icon) = switch (widget.state) {
      BleConnectionState.connected => (
          'Connected',
          const Color(0xFF4CAF50),
          Icons.bluetooth_connected
        ),
      BleConnectionState.connecting => (
          'Connecting...',
          const Color(0xFFFFC107),
          Icons.bluetooth_searching
        ),
      BleConnectionState.scanning => (
          'Scanning...',
          const Color(0xFF2196F3),
          Icons.bluetooth_searching
        ),
      BleConnectionState.disconnected => (
          'Disconnected',
          disconnectedColor,
          Icons.bluetooth_disabled
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: CardStyles.card(context, borderRadius: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: _pulseController.value),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(
                          alpha: 0.4 * _pulseController.value),
                      blurRadius: 6,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
