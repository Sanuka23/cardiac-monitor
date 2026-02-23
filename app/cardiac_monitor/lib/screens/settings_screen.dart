import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/ble_provider.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../models/device.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlC = TextEditingController();
  List<Device> _devices = [];
  bool _loadingDevices = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _urlC.text = settings.apiBaseUrl;
    _loadDevices();
  }

  @override
  void dispose() {
    _urlC.dispose();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    setState(() => _loadingDevices = true);
    try {
      final api = context.read<ApiService>();
      _devices = await api.getDevices();
    } catch (_) {}
    if (mounted) setState(() => _loadingDevices = false);
  }

  Future<void> _saveUrl() async {
    final settings = context.read<SettingsService>();
    await settings.setApiBaseUrl(_urlC.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API URL saved')),
    );
  }

  Future<void> _logout() async {
    final ble = context.read<BleProvider>();
    await ble.disconnect();
    if (!mounted) return;
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // API URL
          _sectionTitle('Server'),
          const SizedBox(height: 8),
          TextField(
            controller: _urlC,
            decoration: InputDecoration(
              hintText: 'http://192.168.1.100:8000',
              suffixIcon: IconButton(
                icon: const Icon(Icons.save, size: 20),
                onPressed: _saveUrl,
              ),
            ),
          ),

          const SizedBox(height: 28),
          _sectionTitle('Registered Devices'),
          const SizedBox(height: 8),
          if (_loadingDevices)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ))
          else if (_devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('No devices registered',
                  style: TextStyle(color: Colors.grey[500])),
            )
          else
            ...List.generate(_devices.length, (i) {
              final d = _devices[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.devices,
                      color: Color(0xFF00BFA5)),
                  title: Text(d.deviceId),
                  subtitle: d.registeredAt != null
                      ? Text(
                          'Registered: ${d.registeredAt!.toLocal().toString().substring(0, 16)}',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 12),
                        )
                      : null,
                ),
              );
            }),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.of(context).pushNamed('/device-setup'),
            icon: const Icon(Icons.add),
            label: const Text('Add Device'),
          ),

          const SizedBox(height: 28),
          _sectionTitle('Bluetooth'),
          const SizedBox(height: 8),
          Consumer<BleProvider>(
            builder: (_, ble, _) {
              if (ble.isConnected) {
                return OutlinedButton.icon(
                  onPressed: () => ble.disconnect(),
                  icon: const Icon(Icons.bluetooth_disabled),
                  label: const Text('Disconnect BLE'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red[400]),
                );
              }
              return Text('Not connected',
                  style: TextStyle(color: Colors.grey[500]));
            },
          ),

          const SizedBox(height: 28),
          _sectionTitle('Account'),
          const SizedBox(height: 8),
          Consumer<AuthProvider>(
            builder: (_, auth, _) => Text(
              auth.user?.email ?? '',
              style: TextStyle(color: Colors.grey[400]),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
            ),
          ),

          const SizedBox(height: 28),
          Center(
            child: Text(
              'Cardiac Monitor v1.0.0',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Color(0xFF00BFA5),
        ),
      );
}
