import 'package:dio/dio.dart';
import '../config/constants.dart';
import '../models/user.dart';
import '../models/device.dart';
import '../models/vitals.dart';
import '../models/prediction.dart';
import 'auth_storage.dart';
import 'settings_service.dart';

class ApiService {
  late Dio _dio;
  final AuthStorage _authStorage;
  final SettingsService _settingsService;

  ApiService(this._authStorage, this._settingsService) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));
    _dio.interceptors.add(_JwtInterceptor(_authStorage));
  }

  String get _baseUrl => _settingsService.apiBaseUrl;

  void updateBaseUrl() {
    // Called after settings change — Dio uses _baseUrl dynamically
  }

  // --- Auth ---

  Future<TokenResponse> register(
      String email, String password, String name) async {
    final resp = await _dio.post('$_baseUrl${ApiPaths.register}', data: {
      'email': email,
      'password': password,
      'name': name,
    });
    return TokenResponse.fromJson(resp.data);
  }

  Future<TokenResponse> login(String email, String password) async {
    final resp = await _dio.post(
      '$_baseUrl${ApiPaths.login}',
      data: FormData.fromMap({
        'username': email,
        'password': password,
      }),
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    return TokenResponse.fromJson(resp.data);
  }

  Future<User> getMe() async {
    final resp = await _dio.get('$_baseUrl${ApiPaths.me}');
    return User.fromJson(resp.data);
  }

  Future<User> updateProfile(Map<String, dynamic> profileData) async {
    final resp = await _dio.put(
      '$_baseUrl${ApiPaths.profile}',
      data: {'health_profile': profileData},
    );
    return User.fromJson(resp.data);
  }

  // --- Devices ---

  Future<Device> registerDevice(String deviceId) async {
    final resp = await _dio.post(
      '$_baseUrl${ApiPaths.devicesRegister}',
      data: {'device_id': deviceId},
    );
    return Device.fromJson(resp.data);
  }

  Future<List<Device>> getDevices() async {
    final resp = await _dio.get('$_baseUrl${ApiPaths.devices}');
    final list = resp.data as List;
    return list.map((d) => Device.fromJson(d)).toList();
  }

  // --- Vitals ---

  Future<Vitals?> getLatestVitals(String deviceId) async {
    try {
      final resp =
          await _dio.get('$_baseUrl${ApiPaths.vitalsLatest(deviceId)}');
      return Vitals.fromJson(resp.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<Vitals>> getVitalsHistory(String deviceId,
      {int limit = 100, int skip = 0}) async {
    final resp = await _dio.get(
      '$_baseUrl${ApiPaths.vitals(deviceId)}',
      queryParameters: {'limit': limit, 'skip': skip},
    );
    final list = resp.data as List;
    return list.map((v) => Vitals.fromJson(v)).toList();
  }

  // --- Predictions ---

  Future<Prediction?> getLatestPrediction(String deviceId) async {
    try {
      final resp =
          await _dio.get('$_baseUrl${ApiPaths.predictionsLatest(deviceId)}');
      return Prediction.fromJson(resp.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<Prediction>> getPredictionHistory(String deviceId,
      {int limit = 100, int skip = 0}) async {
    final resp = await _dio.get(
      '$_baseUrl${ApiPaths.predictions(deviceId)}',
      queryParameters: {'limit': limit, 'skip': skip},
    );
    final list = resp.data as List;
    return list.map((p) => Prediction.fromJson(p)).toList();
  }
}

class _JwtInterceptor extends Interceptor {
  final AuthStorage _authStorage;

  _JwtInterceptor(this._authStorage);

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _authStorage.getToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
