import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/constants.dart';

class AuthStorage {
  static const _storage = FlutterSecureStorage();

  Future<void> saveToken(String token) =>
      _storage.write(key: StorageKeys.accessToken, value: token);

  Future<String?> getToken() =>
      _storage.read(key: StorageKeys.accessToken);

  Future<void> deleteToken() =>
      _storage.delete(key: StorageKeys.accessToken);
}
