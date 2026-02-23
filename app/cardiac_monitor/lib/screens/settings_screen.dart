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
        backgroundColor: const Color(0xFF22C55E),
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
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Text(
              'Settings',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary(context),
              ),
            ).animate().fadeIn(duration: 300.ms),
            const SizedBox(height: 24),

            // ── Appearance ──
            _sectionHeader('Appearance', PhosphorIconsLight.paintBrush, const Color(0xFF8B5CF6)),
            const SizedBox(height: 10),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme',
                      style: TextStyle(
                          color: AppTheme.textSecondary(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _themeOption(
                        label: 'Light',
                        icon: PhosphorIconsLight.sun,
                        mode: ThemeMode.light,
                        prov: themeProv,
                        color: const Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 10),
                      _themeOption(
                        label: 'Dark',
                        icon: PhosphorIconsLight.moon,
                        mode: ThemeMode.dark,
                        prov: themeProv,
                        color: const Color(0xFF6366F1),
                      ),
                      const SizedBox(width: 10),
                      _themeOption(
                        label: 'Auto',
                        icon: PhosphorIconsLight.circleHalf,
                        mode: ThemeMode.system,
                        prov: themeProv,
                        color: AppTheme.accent(context),
                      ),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms, delay: 30.ms).slideY(begin: 0.05),
            const SizedBox(height: 20),

            // ── Connection ──
            _sectionHeader('Connection', PhosphorIconsLight.globe, const Color(0xFF3B82F6)),
            const SizedBox(height: 10),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('API Server URL',
                      style: TextStyle(
                          color: AppTheme.textSecondary(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _urlC,
                          style: TextStyle(
                              color: AppTheme.textPrimary(context),
                              fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'https://your-api.com',
                            hintStyle: TextStyle(
                                color: AppTheme.textTertiary(context)),
                            prefixIcon: Icon(PhosphorIconsLight.globe,
                                size: 18,
                                color: AppTheme.textSecondary(context)),
                            filled: true,
                            fillColor: AppTheme.surfaceVariant(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: AppTheme.accent(context), width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.accent(context),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          onPressed: _saveUrl,
                          icon: const Icon(PhosphorIconsLight.checkCircle,
                              color: Colors.white, size: 20),
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
                                  ? const Color(0xFF22C55E)
                                  : AppTheme.textTertiary(context),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            connected ? 'BLE Connected' : 'BLE Disconnected',
                            style: TextStyle(
                              color: connected
                                  ? const Color(0xFF22C55E)
                                  : AppTheme.textSecondary(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          if (connected)
                            TextButton(
                              onPressed: () => ble.disconnect(),
                              child: const Text('Disconnect',
                                  style: TextStyle(
                                      color: Colors.red, fontSize: 12)),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms, delay: 50.ms).slideY(begin: 0.05),
            const SizedBox(height: 20),

            // ── Devices ──
            _sectionHeader('Devices', PhosphorIconsLight.cpu, const Color(0xFF0D9488)),
            const SizedBox(height: 10),
            _card(
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
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.accent(context)
                                  .withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(PhosphorIconsLight.cpu,
                                size: 28,
                                color: AppTheme.accent(context)),
                          ),
                          const SizedBox(height: 8),
                          Text('No devices registered',
                              style: TextStyle(
                                  color: AppTheme.textSecondary(context),
                                  fontSize: 13)),
                        ],
                      ),
                    )
                  else
                    ...List.generate(_devices.length, (i) {
                      final d = _devices[i];
                      return Container(
                        margin: EdgeInsets.only(
                            bottom: i < _devices.length - 1 ? 10 : 0),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant(context),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.accent(context)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(PhosphorIconsLight.cpu,
                                  color: AppTheme.accent(context), size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(d.deviceId,
                                      style: TextStyle(
                                        color: AppTheme.textPrimary(context),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      )),
                                  if (d.registeredAt != null)
                                    Text(
                                      'Registered ${d.registeredAt!.toLocal().toString().substring(0, 10)}',
                                      style: TextStyle(
                                        color: AppTheme.textTertiary(context),
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
                                color: const Color(0xFF22C55E)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('Active',
                                  style: TextStyle(
                                    color: Color(0xFF22C55E),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  )),
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
                          size: 16, color: AppTheme.accent(context)),
                      label: Text('Add Device',
                          style: TextStyle(color: AppTheme.accent(context))),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: AppTheme.accent(context)
                                .withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms, delay: 100.ms).slideY(begin: 0.05),
            const SizedBox(height: 20),

            // ── Account ──
            _sectionHeader('Account', PhosphorIconsLight.user, const Color(0xFFEF4444)),
            const SizedBox(height: 10),
            _card(
              child: Column(
                children: [
                  Consumer<AuthProvider>(
                    builder: (_, auth, _) => Row(
                      children: [
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
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(auth.user?.name ?? 'User',
                                  style: TextStyle(
                                    color: AppTheme.textPrimary(context),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  )),
                              Text(auth.user?.email ?? '',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary(context),
                                    fontSize: 12,
                                  )),
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
                        backgroundColor: Colors.red[600],
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms, delay: 150.ms).slideY(begin: 0.05),

            const SizedBox(height: 24),
            Center(
              child: Text('Cardiac Monitor v1.1.0',
                  style: TextStyle(
                      color: AppTheme.textTertiary(context), fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Text(text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary(context),
            )),
      ],
    );
  }

  Widget _card({required Widget child}) {
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
      child: child,
    );
  }

  Widget _themeOption({
    required String label,
    required IconData icon,
    required ThemeMode mode,
    required ThemeProvider prov,
    required Color color,
  }) {
    final selected = prov.mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => prov.setMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.12)
                : AppTheme.surfaceVariant(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : AppTheme.dividerColor(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: selected ? color : AppTheme.textSecondary(context)),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                    color: selected ? color : AppTheme.textSecondary(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
