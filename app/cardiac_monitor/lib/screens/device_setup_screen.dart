import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/ble_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/ble_service.dart';
import '../config/constants.dart';

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

  @override
  void dispose() {
    _ssidC.dispose();
    _passC.dispose();
    _deviceIdC.dispose();
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
        const SnackBar(
            content:
                Text('Enter the device ID shown on ESP32 serial output')),
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
              backgroundColor: Colors.red[700]),
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
      appBar: AppBar(
        title: const Text('Device Setup'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pushReplacementNamed('/home'),
            child: const Text('Skip'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: switch (_step) {
          0 => _buildScanStep(),
          1 => _buildWifiStep(),
          2 => _buildProvisioningStep(),
          _ => const SizedBox(),
        },
      ),
    );
  }

  Widget _buildScanStep() {
    final ble = context.watch<BleProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Find Your Device',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Make sure your ESP32 Cardiac Monitor is powered on.',
          style: TextStyle(color: Colors.grey[500]),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: ble.connectionState == BleConnectionState.scanning
              ? null
              : _startScan,
          icon: const Icon(Icons.bluetooth_searching),
          label: Text(
            ble.connectionState == BleConnectionState.scanning
                ? 'Scanning...'
                : 'Scan for Devices',
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: ListView.builder(
            itemCount: ble.scanResults.length,
            itemBuilder: (_, i) {
              final r = ble.scanResults[i];
              final name = r.advertisementData.advName.isNotEmpty
                  ? r.advertisementData.advName
                  : 'Unknown';
              return Card(
                child: ListTile(
                  leading:
                      const Icon(Icons.bluetooth, color: Color(0xFF00BFA5)),
                  title: Text(name),
                  subtitle: Text(
                    '${r.device.remoteId}  •  RSSI: ${r.rssi} dBm',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _connectDevice(r.device),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWifiStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WiFi Configuration',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your WiFi credentials to connect the device.',
            style: TextStyle(color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _ssidC,
            decoration: const InputDecoration(
              hintText: 'WiFi Network Name (SSID)',
              prefixIcon: Icon(Icons.wifi),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passC,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: 'WiFi Password',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _sendCredentials,
            child: const Text('Connect Device'),
          ),
        ],
      ),
    );
  }

  Widget _buildProvisioningStep() {
    final ble = context.watch<BleProvider>();
    final status = ble.provisioningStatus;
    final isDone = status == BleStatus.ready;
    final isFailed = status == BleStatus.wifiFail;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isDone && !isFailed)
            const CircularProgressIndicator(color: Color(0xFF00BFA5)),
          if (isDone)
            const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 64),
          if (isFailed)
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
          const SizedBox(height: 24),
          Text(
            _provStatusText(status),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          if (isFailed) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => setState(() => _step = 1),
              child: const Text('Try Again'),
            ),
          ],
          if (isDone) ...[
            const SizedBox(height: 32),
            TextField(
              controller: _deviceIdC,
              decoration: const InputDecoration(
                hintText: 'Device ID (e.g. ESP32_AABBCC)',
                prefixIcon: Icon(Icons.devices),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Find this in the ESP32 serial output: [WIFI] Device ID: ...',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _registerAndContinue,
              child: const Text('Register & Continue'),
            ),
          ],
        ],
      ),
    );
  }
}
