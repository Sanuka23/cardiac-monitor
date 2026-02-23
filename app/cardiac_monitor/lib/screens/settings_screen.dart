import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/ble_provider.dart';
import '../providers/theme_provider.dart';
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
    final themeProv = context.watch<ThemeProvider>();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text(
              'Settings',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary(context),
              ),
            ).animate().fadeIn(duration: 400.ms),
            const SizedBox(height: 24),

            // Appearance
            _sectionLabel('APPEARANCE'),
            const SizedBox(height: 10),
            GlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Theme',
                    style: TextStyle(
                      color: AppTheme.textSecondary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _themeChip('Light', ThemeMode.light, themeProv),
                      const SizedBox(width: 8),
                      _themeChip('Dark', ThemeMode.dark, themeProv),
                      const SizedBox(width: 8),
                      _themeChip('System', ThemeMode.system, themeProv),
                    ],
                  ),
                ],
              ),
            )
                .animate()
                .fadeIn(duration: 500.ms, delay: 50.ms)
                .slideY(begin: 0.1),

            const SizedBox(height: 20),

            // Connection
            _sectionLabel('CONNECTION'),
            const SizedBox(height: 10),
            GlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'API Server URL',
                    style: TextStyle(
                      color: AppTheme.textSecondary(context),
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
                          style: TextStyle(
                              color: AppTheme.textPrimary(context), fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'https://your-api.com',
                            hintStyle: TextStyle(
                                color: AppTheme.textSecondary(context)),
                            prefixIcon: Icon(PhosphorIconsLight.globe,
                                size: 20, color: AppTheme.textSecondary(context)),
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
                          icon: const Icon(PhosphorIconsLight.checkCircle,
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
                                  : AppTheme.textSecondary(context),
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
                                  : AppTheme.textSecondary(context),
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
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: CircularProgressIndicator(
                          color: AppTheme.accent(context), strokeWidth: 2),
                    )
                  else if (_devices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          Icon(PhosphorIconsLight.cpu,
                              size: 36, color: AppTheme.textSecondary(context)),
                          const SizedBox(height: 8),
                          Text(
                            'No devices registered',
                            style: TextStyle(
                                color: AppTheme.textSecondary(context),
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
                          color: AppTheme.surfaceVariant(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppTheme.dividerColor(context)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.accent(context)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(PhosphorIconsLight.cpu,
                                  color: AppTheme.accent(context), size: 20),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    d.deviceId,
                                    style: TextStyle(
                                      color: AppTheme.textPrimary(context),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (d.registeredAt != null)
                                    Text(
                                      'Registered ${d.registeredAt!.toLocal().toString().substring(0, 10)}',
                                      style: TextStyle(
                                        color: AppTheme.textSecondary(context),
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
                      icon: Icon(PhosphorIconsLight.plus,
                          size: 18, color: AppTheme.accent(context)),
                      label: Text('Add Device',
                          style: TextStyle(color: AppTheme.accent(context))),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: AppTheme.accent(context).withValues(alpha: 0.3)),
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
                            color: AppTheme.accent(context).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(PhosphorIconsLight.user,
                              color: AppTheme.accent(context), size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                auth.user?.name ?? 'User',
                                style: TextStyle(
                                  color: AppTheme.textPrimary(context),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                auth.user?.email ?? '',
                                style: TextStyle(
                                  color: AppTheme.textSecondary(context),
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
                      icon: const Icon(PhosphorIconsLight.signOut,
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
                    color: AppTheme.textSecondary(context), fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _themeChip(String label, ThemeMode mode, ThemeProvider prov) {
    final selected = prov.mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => prov.setMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: selected ? AppGradients.primary : null,
            color: selected ? null : AppTheme.surfaceVariant(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : AppTheme.dividerColor(context),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppTheme.textSecondary(context),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppTheme.accent(context),
        letterSpacing: 1.2,
      ),
    );
  }
}
