import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
    debugPrint('[AUTH] tryAutoLogin: token=${token != null ? "present" : "null"}');
    if (token == null) {
      _state = AuthState.unauthenticated;
      notifyListeners();
      return;
    }

    _state = AuthState.loading;
    notifyListeners();

    try {
      _user = await _api.getMe();
      debugPrint('[AUTH] autoLogin success: user=${_user?.name}');
      _state = AuthState.authenticated;
    } on DioException catch (e) {
      debugPrint('[AUTH] autoLogin failed: ${e.type} status=${e.response?.statusCode}');
      await _authStorage.deleteToken();
      _state = AuthState.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    debugPrint('[AUTH] login called: email=$email');
    _state = AuthState.loading;
    _error = null;
    notifyListeners();

    try {
      final token = await _api.login(email, password);
      debugPrint('[AUTH] login got token: ${token.accessToken.substring(0, 20)}...');
      await _authStorage.saveToken(token.accessToken);
      _user = await _api.getMe();
      debugPrint('[AUTH] login success: user=${_user?.name} devices=${_user?.deviceIds}');
      _state = AuthState.authenticated;
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _error = _extractError(e);
      debugPrint('[AUTH] login error: $_error (type=${e.type} status=${e.response?.statusCode})');
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString();
      debugPrint('[AUTH] login unexpected error: $e');
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(String email, String password, String name) async {
    debugPrint('[AUTH] register called: email=$email name=$name');
    _state = AuthState.loading;
    _error = null;
    notifyListeners();

    try {
      final token = await _api.register(email, password, name);
      debugPrint('[AUTH] register got token: ${token.accessToken.substring(0, 20)}...');
      await _authStorage.saveToken(token.accessToken);
      _user = await _api.getMe();
      debugPrint('[AUTH] register success: user=${_user?.name} devices=${_user?.deviceIds}');
      _state = AuthState.authenticated;
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _error = _extractError(e);
      debugPrint('[AUTH] register error: $_error (type=${e.type} status=${e.response?.statusCode})');
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString();
      debugPrint('[AUTH] register unexpected error: $e');
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
