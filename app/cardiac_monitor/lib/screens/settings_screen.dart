import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/ble_provider.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../models/device.dart';
import '../config/theme.dart';
import '../widgets/glass_card.dart';

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
      SnackBar(
        content: const Text('API URL saved'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF4CAF50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
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
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              const Text(
                'Settings',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ).animate().fadeIn(duration: 400.ms),
              const SizedBox(height: 24),

              // Connection
              _sectionLabel('CONNECTION'),
              const SizedBox(height: 10),
              GlassCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'API Server URL',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _urlC,
                            style: const TextStyle(
                                color: AppTheme.textPrimary, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'https://your-api.com',
                              hintStyle: const TextStyle(
                                  color: AppTheme.textSecondary),
                              prefixIcon: const Icon(Iconsax.global,
                                  size: 20, color: AppTheme.textSecondary),
                              filled: true,
                              fillColor:
                                  Colors.white.withValues(alpha: 0.04),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                    color: AppTheme.accent, width: 1.5),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          decoration: BoxDecoration(
                            gradient: AppGradients.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            onPressed: _saveUrl,
                            icon: const Icon(Iconsax.tick_circle,
                                color: Colors.white, size: 22),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Consumer<BleProvider>(
                      builder: (_, ble, _) {
                        final connected = ble.isConnected;
                        return Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: connected
                                    ? const Color(0xFF4CAF50)
                                    : AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              connected
                                  ? 'BLE Connected'
                                  : 'BLE Disconnected',
                              style: TextStyle(
                                color: connected
                                    ? const Color(0xFF4CAF50)
                                    : AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            if (connected)
                              TextButton(
                                onPressed: () => ble.disconnect(),
                                child: const Text(
                                  'Disconnect',
                                  style: TextStyle(
                                      color: Colors.red, fontSize: 12),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: 500.ms, delay: 100.ms)
                  .slideY(begin: 0.1),

              const SizedBox(height: 20),
              _sectionLabel('DEVICES'),
              const SizedBox(height: 10),
              GlassCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    if (_loadingDevices)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(
                            color: AppTheme.accent, strokeWidth: 2),
                      )
                    else if (_devices.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Column(
                          children: [
                            Icon(Iconsax.cpu,
                                size: 36, color: AppTheme.textSecondary),
                            const SizedBox(height: 8),
                            const Text(
                              'No devices registered',
                              style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    else
                      ...List.generate(_devices.length, (i) {
                        final d = _devices[i];
                        return Container(
                          margin: EdgeInsets.only(
                              bottom: i < _devices.length - 1 ? 10 : 0),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color:
                                    Colors.white.withValues(alpha: 0.06)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppTheme.accent
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Iconsax.cpu,
                                    color: AppTheme.accent, size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d.deviceId,
                                      style: const TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (d.registeredAt != null)
                                      Text(
                                        'Registered ${d.registeredAt!.toLocal().toString().substring(0, 10)}',
                                        style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4CAF50)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Active',
                                  style: TextStyle(
                                    color: Color(0xFF4CAF50),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            Navigator.of(context).pushNamed('/device-setup'),
                        icon: const Icon(Iconsax.add,
                            size: 18, color: AppTheme.accent),
                        label: const Text('Add Device',
                            style: TextStyle(color: AppTheme.accent)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: AppTheme.accent.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: 500.ms, delay: 200.ms)
                  .slideY(begin: 0.1),

              const SizedBox(height: 20),
              _sectionLabel('ACCOUNT'),
              const SizedBox(height: 10),
              GlassCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Consumer<AuthProvider>(
                      builder: (_, auth, _) => Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Iconsax.user,
                                color: AppTheme.accent, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  auth.user?.name ?? 'User',
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  auth.user?.email ?? '',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Iconsax.logout,
                            size: 18, color: Colors.white),
                        label: const Text('Logout',
                            style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[700],
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: 500.ms, delay: 300.ms)
                  .slideY(begin: 0.1),

              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Cardiac Monitor v1.1.0',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppTheme.accent,
        letterSpacing: 1.2,
      ),
    );
  }
}
