import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

class SettingsService {
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String get apiBaseUrl =>
      _prefs?.getString(StorageKeys.apiBaseUrl) ?? defaultApiBaseUrl;

  Future<void> setApiBaseUrl(String url) async {
    await _prefs?.setString(StorageKeys.apiBaseUrl, url);
  }
}
