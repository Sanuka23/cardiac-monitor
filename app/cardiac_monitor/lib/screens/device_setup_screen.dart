import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/ble_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/ble_service.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../widgets/glass_card.dart';

class DeviceSetupScreen extends StatefulWidget {
  const DeviceSetupScreen({super.key});

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends State<DeviceSetupScreen> {
  int _step = 0; // 0=scan, 1=wifi creds, 2=provisioning
  final _ssidC = TextEditingController();
  final _passC = TextEditingController();
  final _deviceIdC = TextEditingController();
  bool _manualEntry = false;
  final _passFocus = FocusNode();

  @override
  void dispose() {
    _ssidC.dispose();
    _passC.dispose();
    _deviceIdC.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<void> _startScan() async {
    await _requestPermissions();
    if (!mounted) return;
    context.read<BleProvider>().startScan();
  }

  Future<void> _connectDevice(dynamic device) async {
    final ble = context.read<BleProvider>();
    await ble.stopScan();
    await ble.connectToDevice(device);
    if (mounted && ble.isConnected) {
      setState(() => _step = 1);
    }
  }

  Future<void> _sendCredentials() async {
    if (_ssidC.text.isEmpty) return;
    setState(() => _step = 2);
    final ble = context.read<BleProvider>();
    await ble.sendWifiCredentials(_ssidC.text, _passC.text);
  }

  Future<void> _registerAndContinue() async {
    final deviceId = _deviceIdC.text.trim();
    if (deviceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              const Text('Enter the device ID shown on ESP32 serial output'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    try {
      final api = context.read<ApiService>();
      await api.registerDevice(deviceId);
      if (!mounted) return;
      await context.read<AuthProvider>().refreshUser();
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  String _provStatusText(int status) => switch (status) {
        BleStatus.connecting => 'Connecting to WiFi...',
        BleStatus.ntpSync => 'Syncing time (NTP)...',
        BleStatus.ready => 'Device ready!',
        BleStatus.wifiFail => 'WiFi connection failed',
        BleStatus.cleared => 'Credentials cleared',
        _ => 'Sending credentials...',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // App bar
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(PhosphorIconsLight.arrowLeft,
                        color: AppTheme.textPrimary(context)),
                  ),
                  Expanded(
                    child: Text(
                      'Device Setup',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context)
                        .pushReplacementNamed('/home'),
                    child: Text('Skip',
                        style: TextStyle(color: AppTheme.accent(context))),
                  ),
                ],
              ),
            ),

            // Step indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                children: [
                  _stepDot(0, 'Scan'),
                  _stepLine(0),
                  _stepDot(1, 'WiFi'),
                  _stepLine(1),
                  _stepDot(2, 'Done'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: switch (_step) {
                    0 => _buildScanStep(),
                    1 => _buildWifiStep(),
                    2 => _buildProvisioningStep(),
                    _ => const SizedBox(),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepDot(int step, String label) {
    final isActive = _step >= step;
    final isCurrent = _step == step;
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: isCurrent ? 36 : 28,
          height: isCurrent ? 36 : 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isActive ? AppGradients.primary : null,
            color: isActive ? null : AppTheme.surfaceVariant(context),
            border: isCurrent
                ? Border.all(
                    color: AppTheme.accent(context).withValues(alpha: 0.3), width: 3)
                : null,
          ),
          child: Center(
            child: Text(
              '${step + 1}',
              style: TextStyle(
                color: isActive ? Colors.white : AppTheme.textSecondary(context),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: isActive ? AppTheme.textPrimary(context) : AppTheme.textSecondary(context),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _stepLine(int afterStep) {
    final isActive = _step > afterStep;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Container(
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            gradient: isActive ? AppGradients.primary : null,
            color: isActive ? null : AppTheme.surfaceVariant(context),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }

  Widget _buildScanStep() {
    final ble = context.watch<BleProvider>();
    return Column(
      key: const ValueKey('scan'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Find Your Device',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Make sure your ESP32 Cardiac Monitor is powered on.',
          style: TextStyle(color: AppTheme.textSecondary(context)),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppGradients.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ElevatedButton.icon(
              onPressed: ble.connectionState == BleConnectionState.scanning
                  ? null
                  : _startScan,
              icon: Icon(
                PhosphorIconsLight.bluetooth,
                color: ble.connectionState == BleConnectionState.scanning
                    ? Colors.white54
                    : Colors.white,
              ),
              label: Text(
                ble.connectionState == BleConnectionState.scanning
                    ? 'Scanning...'
                    : 'Scan for Devices',
                style: const TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: ListView.builder(
            itemCount: ble.scanResults.length,
            itemBuilder: (_, i) {
              final r = ble.scanResults[i];
              final name = r.advertisementData.advName.isNotEmpty
                  ? r.advertisementData.advName
                  : 'Unknown';
              final rssi = r.rssi;
              final signalBars = rssi > -50
                  ? 4
                  : rssi > -65
                      ? 3
                      : rssi > -80
                          ? 2
                          : 1;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: InkWell(
                    onTap: () => _connectDevice(r.device),
                    borderRadius: BorderRadius.circular(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.accent(context).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(PhosphorIconsLight.bluetooth,
                              color: AppTheme.accent(context), size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary(context),
                                ),
                              ),
                              Text(
                                '${r.device.remoteId}',
                                style: TextStyle(
                                  color: AppTheme.textSecondary(context),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(4, (j) {
                            return Container(
                              width: 3,
                              height: 6.0 + (j * 4),
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: j < signalBars
                                    ? AppTheme.accent(context)
                                    : AppTheme.surfaceVariant(context),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(width: 8),
                        Icon(PhosphorIconsLight.arrowRight,
                            color: AppTheme.textSecondary(context), size: 18),
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: (100 * i).ms).slideX(begin: 0.05);
            },
          ),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildWifiStep() {
    final ble = context.watch<BleProvider>();
    final networks = ble.wifiNetworks;
    final scanning = ble.isWifiScanning;

    return SingleChildScrollView(
      key: const ValueKey('wifi'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WiFi Configuration',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Scan for available networks or enter manually.',
            style: TextStyle(color: AppTheme.textSecondary(context)),
          ),
          const SizedBox(height: 20),

          // Scan button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: scanning ? null : () => ble.requestWifiScan(),
              icon: scanning
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.accent(context),
                      ),
                    )
                  : Icon(PhosphorIconsLight.wifiHigh,
                      color: AppTheme.accent(context), size: 20),
              label: Text(
                scanning ? 'Scanning...' : 'Scan for Networks',
                style: TextStyle(color: AppTheme.accent(context)),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                    color: AppTheme.accent(context).withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),

          // Network list
          if (networks.isNotEmpty && !_manualEntry) ...[
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: networks.length,
                itemBuilder: (_, i) {
                  final net = networks[i];
                  final isSelected = _ssidC.text == net.ssid;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: GlassCard(
                      padding: EdgeInsets.zero,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _ssidC.text = net.ssid;
                          });
                          _passFocus.requestFocus();
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                net.isOpen
                                    ? PhosphorIconsLight.wifiHigh
                                    : PhosphorIconsLight.lock,
                                color: isSelected
                                    ? AppTheme.accent(context)
                                    : AppTheme.textSecondary(context),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      net.ssid,
                                      style: TextStyle(
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color:
                                            AppTheme.textPrimary(context),
                                        fontSize: 14,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      net.securityLabel,
                                      style: TextStyle(
                                        color: AppTheme.textSecondary(
                                            context),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Signal bars
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(4, (j) {
                                  return Container(
                                    width: 3,
                                    height: 6.0 + (j * 4),
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 1),
                                    decoration: BoxDecoration(
                                      color: j < net.signalBars
                                          ? AppTheme.accent(context)
                                          : AppTheme.surfaceVariant(
                                              context),
                                      borderRadius:
                                          BorderRadius.circular(2),
                                    ),
                                  );
                                }),
                              ),
                              if (isSelected) ...[
                                const SizedBox(width: 8),
                                Icon(PhosphorIconsLight.checkCircle,
                                    color: AppTheme.accent(context),
                                    size: 18),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          // Manual entry toggle
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => setState(() {
                _manualEntry = !_manualEntry;
                if (_manualEntry) _ssidC.clear();
              }),
              child: Text(
                _manualEntry ? 'Select from scan results' : 'Enter manually',
                style: TextStyle(
                  color: AppTheme.accent(context),
                  fontSize: 13,
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Show SSID field if manual or no selection
                if (_manualEntry || _ssidC.text.isEmpty)
                  TextField(
                    controller: _ssidC,
                    style: TextStyle(color: AppTheme.textPrimary(context)),
                    decoration: InputDecoration(
                      hintText: 'WiFi Network Name (SSID)',
                      hintStyle:
                          TextStyle(color: AppTheme.textSecondary(context)),
                      prefixIcon: Icon(PhosphorIconsLight.wifiHigh,
                          color: AppTheme.textSecondary(context)),
                      filled: true,
                      fillColor: AppTheme.surfaceVariant(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                            color: AppTheme.accent(context), width: 1.5),
                      ),
                    ),
                  )
                else
                  // Show selected network chip
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.accent(context).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color:
                              AppTheme.accent(context).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(PhosphorIconsLight.wifiHigh,
                            color: AppTheme.accent(context), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _ssidC.text,
                            style: TextStyle(
                              color: AppTheme.textPrimary(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _ssidC.clear()),
                          child: Icon(PhosphorIconsLight.x,
                              color: AppTheme.textSecondary(context),
                              size: 18),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                TextField(
                  controller: _passC,
                  focusNode: _passFocus,
                  obscureText: true,
                  style: TextStyle(color: AppTheme.textPrimary(context)),
                  decoration: InputDecoration(
                    hintText: 'WiFi Password',
                    hintStyle:
                        TextStyle(color: AppTheme.textSecondary(context)),
                    prefixIcon: Icon(PhosphorIconsLight.lock,
                        color: AppTheme.textSecondary(context)),
                    filled: true,
                    fillColor: AppTheme.surfaceVariant(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                          color: AppTheme.accent(context), width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppGradients.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: ElevatedButton(
                onPressed: _sendCredentials,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  'Connect Device',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildProvisioningStep() {
    final ble = context.watch<BleProvider>();
    final status = ble.provisioningStatus;
    final isDone = status == BleStatus.ready;
    final isFailed = status == BleStatus.wifiFail;

    return Center(
      key: const ValueKey('prov'),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isDone && !isFailed)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accent(context).withValues(alpha: 0.1),
                ),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    color: AppTheme.accent(context),
                    strokeWidth: 3,
                  ),
                ),
              ),
            if (isDone)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
                ),
                child: const Icon(PhosphorIconsLight.checkCircle,
                    color: Color(0xFF4CAF50), size: 56),
              ),
            if (isFailed)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withValues(alpha: 0.12),
                ),
                child: const Icon(PhosphorIconsLight.xCircle,
                    color: Colors.red, size: 56),
              ),
            const SizedBox(height: 24),
            Text(
              _provStatusText(status),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary(context),
              ),
              textAlign: TextAlign.center,
            ),
            if (isFailed) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => setState(() => _step = 1),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.surfaceVariant(context),
                ),
                child: const Text('Try Again'),
              ),
            ],
            if (isDone) ...[
              const SizedBox(height: 32),
              GlassCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    TextField(
                      controller: _deviceIdC,
                      style: TextStyle(color: AppTheme.textPrimary(context)),
                      decoration: InputDecoration(
                        hintText: 'Device ID (e.g. ESP32_AABBCC)',
                        hintStyle: TextStyle(
                            color: AppTheme.textSecondary(context)),
                        prefixIcon: Icon(PhosphorIconsLight.cpu,
                            color: AppTheme.textSecondary(context)),
                        filled: true,
                        fillColor: AppTheme.surfaceVariant(context),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                              color: AppTheme.accent(context), width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Find this in the ESP32 serial output:\n[WIFI] Device ID: ...',
                      style: TextStyle(
                          color: AppTheme.textSecondary(context), fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppGradients.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ElevatedButton(
                    onPressed: _registerAndContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      'Register & Continue',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}
