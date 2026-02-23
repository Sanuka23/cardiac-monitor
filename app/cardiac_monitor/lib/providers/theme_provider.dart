import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const _key = 'theme_mode';
  final SharedPreferences _prefs;
  ThemeMode _mode;

  ThemeProvider(this._prefs)
      : _mode = _parseMode(_prefs.getString(_key));

  ThemeMode get mode => _mode;

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    await _prefs.setString(_key, mode.name);
    notifyListeners();
  }

  static ThemeMode _parseMode(String? value) {
    switch (value) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.light;
    }
  }
}
