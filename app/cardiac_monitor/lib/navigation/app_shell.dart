import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
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
          color: AppTheme.cardBackground(context),
          border: Border(
            top: BorderSide(
              color: AppTheme.dividerColor(context),
              width: 1,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: Colors.transparent,
          indicatorColor: AppTheme.accent(context).withValues(alpha: 0.12),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 70,
          destinations: [
            NavigationDestination(
              icon: Icon(PhosphorIconsLight.heartbeat, color: AppTheme.textSecondary(context)),
              selectedIcon: Icon(PhosphorIconsLight.heartbeat, color: AppTheme.accent(context)),
              label: 'Monitor',
            ),
            NavigationDestination(
              icon: Icon(PhosphorIconsLight.chartLine, color: AppTheme.textSecondary(context)),
              selectedIcon: Icon(PhosphorIconsLight.chartLine, color: AppTheme.accent(context)),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(PhosphorIconsLight.user, color: AppTheme.textSecondary(context)),
              selectedIcon: Icon(PhosphorIconsLight.user, color: AppTheme.accent(context)),
              label: 'Profile',
            ),
            NavigationDestination(
              icon: Icon(PhosphorIconsLight.gear, color: AppTheme.textSecondary(context)),
              selectedIcon: Icon(PhosphorIconsLight.gear, color: AppTheme.accent(context)),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
