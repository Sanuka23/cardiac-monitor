import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../config/theme.dart';
import '../screens/dashboard_screen.dart';
import '../screens/history_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _screens = [
    DashboardScreen(),
    HistoryScreen(),
    ProfileScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.06),
              width: 1,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: Colors.transparent,
          indicatorColor: AppTheme.accent.withValues(alpha: 0.12),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 70,
          destinations: const [
            NavigationDestination(
              icon: Icon(Iconsax.heart, color: AppTheme.textSecondary),
              selectedIcon: Icon(Iconsax.heart, color: AppTheme.accent),
              label: 'Monitor',
            ),
            NavigationDestination(
              icon: Icon(Iconsax.chart, color: AppTheme.textSecondary),
              selectedIcon: Icon(Iconsax.chart, color: AppTheme.accent),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(Iconsax.user, color: AppTheme.textSecondary),
              selectedIcon: Icon(Iconsax.user, color: AppTheme.accent),
              label: 'Profile',
            ),
            NavigationDestination(
              icon: Icon(Iconsax.setting_2, color: AppTheme.textSecondary),
              selectedIcon: Icon(Iconsax.setting_2, color: AppTheme.accent),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
