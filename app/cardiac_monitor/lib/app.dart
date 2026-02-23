import 'package:flutter/material.dart';
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
                Icon(Icons.monitor_heart_outlined,
                    size: 56, color: accent),
                const SizedBox(height: 20),
                CircularProgressIndicator(color: accent),
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
