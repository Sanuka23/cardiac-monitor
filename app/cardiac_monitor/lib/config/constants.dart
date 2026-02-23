// BLE Service UUIDs (must match firmware config.h exactly)
class BleUuids {
  static const String provService = '0000ff00-1234-5678-9abc-def012345678';
  static const String provSsid = '0000ff01-1234-5678-9abc-def012345678';
  static const String provPass = '0000ff02-1234-5678-9abc-def012345678';
  static const String provCmd = '0000ff03-1234-5678-9abc-def012345678';
  static const String provStatus = '0000ff04-1234-5678-9abc-def012345678';
  static const String provScanResult = '0000ff05-1234-5678-9abc-def012345678';

  static const String cardiacService = '0000cc00-1234-5678-9abc-def012345678';
  static const String cardiacHr = '0000cc01-1234-5678-9abc-def012345678';
  static const String cardiacSpo2 = '0000cc02-1234-5678-9abc-def012345678';
  static const String cardiacRisk = '0000cc03-1234-5678-9abc-def012345678';
  static const String cardiacLabel = '0000cc04-1234-5678-9abc-def012345678';
  static const String cardiacStatus = '0000cc05-1234-5678-9abc-def012345678';
  static const String cardiacEcg = '0000cc06-1234-5678-9abc-def012345678';
}

// BLE provisioning commands (write to provCmd)
class BleCmds {
  static const int connect = 0x01;
  static const int clearCreds = 0x02;
  static const int wifiScan = 0x03;
}

// BLE provisioning status codes (read from provStatus notifications)
class BleStatus {
  static const int idle = 0x00;
  static const int connecting = 0x01;
  static const int ntpSync = 0x02;
  static const int ready = 0x05;
  static const int wifiFail = 0x03;
  static const int cleared = 0x04;
}

// Device status bitmask (from cardiacStatus notifications)
class DeviceStatusBits {
  static const int sensorOk = 0x01;
  static const int wifiReady = 0x02;
  static const int ecgLeadOff = 0x04;
  static const int apiReady = 0x08;
}

// BLE device name prefix for scanning
const String bleDeviceNamePrefix = 'CardiacMon';

// API paths
class ApiPaths {
  static const String register = '/api/v1/auth/register';
  static const String login = '/api/v1/auth/login';
  static const String me = '/api/v1/auth/me';
  static const String profile = '/api/v1/auth/profile';
  static const String devicesRegister = '/api/v1/devices/register';
  static const String devices = '/api/v1/devices';
  static String vitalsLatest(String deviceId) =>
      '/api/v1/vitals/$deviceId/latest';
  static String vitals(String deviceId) => '/api/v1/vitals/$deviceId';
  static String predictionsLatest(String deviceId) =>
      '/api/v1/predictions/$deviceId/latest';
  static String predictions(String deviceId) =>
      '/api/v1/predictions/$deviceId';

  // User-based endpoints (across all devices)
  static const String myVitalsLatest = '/api/v1/vitals/me/latest';
  static const String myVitalsHistory = '/api/v1/vitals/me/history';
  static const String myPredictionsLatest = '/api/v1/predictions/me/latest';
  static const String myPredictionsHistory = '/api/v1/predictions/me/history';
}

// Default API base URL
const String defaultApiBaseUrl = 'https://sanuka0523-cardiac-monitor-api.hf.space';

// Storage keys
class StorageKeys {
  static const String accessToken = 'access_token';
  static const String apiBaseUrl = 'api_base_url';
}
