import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/auth_storage.dart';

/// Authentication lifecycle states.
enum AuthState { initial, loading, authenticated, unauthenticated }

/// Manages user authentication state, JWT storage, and auto-login.
///
/// On app start, [tryAutoLogin] checks for a stored JWT and validates it
/// against the backend. Exposes [user], [deviceIds], and [error] for the UI.
class AuthProvider extends ChangeNotifier {
  final ApiService _api;
  final AuthStorage _authStorage;

  AuthState _state = AuthState.initial;
  User? _user;
  String? _error;

  AuthProvider(this._api, this._authStorage);

  AuthState get state => _state;
  User? get user => _user;
  String? get error => _error;
  bool get isAuthenticated => _state == AuthState.authenticated;
  List<String> get deviceIds => _user?.deviceIds ?? [];

  Future<void> tryAutoLogin() async {
    final token = await _authStorage.getToken();
    if (token == null) {
      _state = AuthState.unauthenticated;
      notifyListeners();
      return;
    }

    _state = AuthState.loading;
    notifyListeners();

    try {
      _user = await _api.getMe();
      _state = AuthState.authenticated;
    } on DioException {
      await _authStorage.deleteToken();
      _state = AuthState.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _state = AuthState.loading;
    _error = null;
    notifyListeners();

    try {
      final token = await _api.login(email, password);
      await _authStorage.saveToken(token.accessToken);
      _user = await _api.getMe();
      _state = AuthState.authenticated;
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _error = _extractError(e);
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(String email, String password, String name) async {
    _state = AuthState.loading;
    _error = null;
    notifyListeners();

    try {
      final token = await _api.register(email, password, name);
      await _authStorage.saveToken(token.accessToken);
      _user = await _api.getMe();
      _state = AuthState.authenticated;
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _error = _extractError(e);
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshUser() async {
    try {
      _user = await _api.getMe();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> logout() async {
    await _authStorage.deleteToken();
    _user = null;
    _state = AuthState.unauthenticated;
    notifyListeners();
  }

  String _extractError(DioException e) {
    if (e.response?.data is Map) {
      return e.response!.data['detail']?.toString() ?? 'Request failed';
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError) {
      return 'Cannot reach server. Check API URL in Settings.';
    }
    return 'Something went wrong';
  }
}
