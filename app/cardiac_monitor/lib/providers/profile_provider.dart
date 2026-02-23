import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class ProfileProvider extends ChangeNotifier {
  final ApiService _api;

  bool _saving = false;
  String? _error;
  bool _saved = false;

  ProfileProvider(this._api);

  bool get saving => _saving;
  String? get error => _error;
  bool get saved => _saved;

  Future<bool> saveProfile(HealthProfile profile) async {
    _saving = true;
    _error = null;
    _saved = false;
    notifyListeners();

    try {
      await _api.updateProfile(profile.toJson());
      _saved = true;
      _saving = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _saving = false;
      notifyListeners();
      return false;
    }
  }

  void resetState() {
    _saved = false;
    _error = null;
  }
}
