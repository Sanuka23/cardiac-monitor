import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/login_screen.dart';
import 'screens/device_setup_screen.dart';
import 'navigation/app_shell.dart';

class CardiacMonitorApp extends StatelessWidget {
  const CardiacMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeProvider>().mode;

    return MaterialApp(
      title: 'Cardiac Monitor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const _AuthGate(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/device-setup': (_) => const DeviceSetupScreen(),
        '/home': (_) => const AppShell(),
      },
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  @override
  void initState() {
    super.initState();
    context.read<AuthProvider>().tryAutoLogin();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    final accent = AppTheme.accent(context);

    return switch (auth.state) {
      AuthState.initial || AuthState.loading => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    gradient: AppGradients.primary,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    PhosphorIconsBold.heartbeat,
                    size: 44,
                    color: Colors.white,
                  ),
                ).animate().fadeIn(duration: 400.ms).scale(
                      begin: const Offset(0.8, 0.8),
                      end: const Offset(1, 1),
                      duration: 400.ms,
                      curve: Curves.easeOutBack,
                    ),
                const SizedBox(height: 20),
                Text(
                  'Cardiac Monitor',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(context),
                  ),
                ).animate().fadeIn(delay: 200.ms, duration: 300.ms),
                const SizedBox(height: 4),
                Text(
                  'Your heart health companion',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary(context),
                  ),
                ).animate().fadeIn(delay: 300.ms, duration: 300.ms),
                const SizedBox(height: 32),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: accent,
                    strokeWidth: 2.5,
                  ),
                ).animate().fadeIn(delay: 400.ms, duration: 300.ms),
              ],
            ),
          ),
        ),
      AuthState.authenticated =>
        auth.deviceIds.isEmpty ? const DeviceSetupScreen() : const AppShell(),
      AuthState.unauthenticated => const LoginScreen(),
    };
  }
}
