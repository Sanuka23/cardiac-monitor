import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/auth_storage.dart';
import 'services/settings_service.dart';
import 'services/api_service.dart';
import 'services/ble_service.dart';
import 'providers/auth_provider.dart';
import 'providers/ble_provider.dart';
import 'providers/vitals_provider.dart';
import 'providers/profile_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final authStorage = AuthStorage();
  final settingsService = SettingsService();
  await settingsService.init();

  final apiService = ApiService(authStorage, settingsService);
  final bleService = BleService();

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: settingsService),
        Provider.value(value: apiService),
        Provider.value(value: bleService),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(apiService, authStorage),
        ),
        ChangeNotifierProvider(create: (_) => BleProvider(bleService)),
        ChangeNotifierProvider(create: (_) => VitalsProvider(apiService)),
        ChangeNotifierProvider(create: (_) => ProfileProvider(apiService)),
      ],
      child: const CardiacMonitorApp(),
    ),
  );
}
