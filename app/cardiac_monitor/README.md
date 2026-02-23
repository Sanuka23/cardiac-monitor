# Cardiac Monitor App

Flutter mobile app for the ESP32 cardiac monitoring system. Connects to the device via BLE for real-time vitals and to the cloud backend for history and ML predictions.

## Features

- **BLE Device Setup**: Scan, connect, and provision WiFi credentials to ESP32
- **Real-time Dashboard**: Live heart rate, SpO2, and risk score from BLE
- **History Charts**: HR, SpO2, and risk trends over 24h/7d/30d
- **Health Profile**: Personal and medical data for personalized predictions
- **JWT Authentication**: Secure login/register with backend API
- **Dark Glassmorphic UI**: Modern Material 3 design with animations

## Tech Stack

| Category | Package |
|----------|---------|
| State Management | provider |
| BLE | flutter_blue_plus |
| HTTP | dio (JWT interceptor) |
| Charts | fl_chart |
| Storage | flutter_secure_storage, shared_preferences |
| Animations | flutter_animate |
| Icons | iconsax_flutter |
| Loading | shimmer |
| Gauges | percent_indicator |
| Fonts | google_fonts (Inter) |

## Architecture

```
lib/
├── main.dart                  # MultiProvider + runApp
├── app.dart                   # MaterialApp, theme, routing
├── config/
│   ├── constants.dart         # BLE UUIDs, API paths
│   └── theme.dart             # Dark theme, gradients, glass helpers
├── models/                    # Data classes with fromJson/toJson
├── services/
│   ├── api_service.dart       # Dio client + all API endpoints
│   ├── ble_service.dart       # BLE scan/connect/provision/notify
│   ├── auth_storage.dart      # Secure JWT storage
│   └── settings_service.dart  # SharedPreferences wrapper
├── providers/
│   ├── auth_provider.dart     # Login/register/auto-login
│   ├── ble_provider.dart      # BLE state + live vitals stream
│   ├── vitals_provider.dart   # History from API
│   └── profile_provider.dart  # Health profile CRUD
├── screens/                   # 6 screens (login, dashboard, etc.)
├── widgets/                   # Reusable UI components
│   ├── glass_card.dart        # Glassmorphic container
│   ├── animated_value.dart    # Smooth number transitions
│   ├── vital_card.dart        # HR/SpO2 metric card
│   ├── risk_indicator.dart    # Circular risk gauge
│   ├── ble_status_chip.dart   # Connection indicator
│   └── vitals_line_chart.dart # fl_chart wrapper
└── navigation/
    └── app_shell.dart         # Bottom navigation (4 tabs)
```

## Screens

1. **Login/Register** — Animated toggle, glassmorphic form, gradient buttons
2. **Device Setup** — 3-step wizard: scan, WiFi config, provisioning
3. **Dashboard** — Live HR/SpO2 cards, risk gauge, device status chips
4. **History** — Time-range filtered line charts with shimmer loading
5. **Profile** — Grouped health form (personal, medical, medications)
6. **Settings** — API URL, devices list, BLE controls, account

## Setup

### Prerequisites

- Flutter SDK 3.11+
- Android Studio or Xcode
- Physical device (BLE not available on emulators)

### Build

```bash
cd app/cardiac_monitor
flutter pub get
flutter run
```

### Android Permissions

The app requests at runtime:
- `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` — BLE scanning and connection
- `ACCESS_FINE_LOCATION` — Required for BLE on Android
- `INTERNET` — API communication

### iOS Permissions

Configured in `Info.plist`:
- `NSBluetoothAlwaysUsageDescription`
- `NSBluetoothPeripheralUsageDescription`
- `NSLocationWhenInUseUsageDescription`

## BLE Data Format

The app parses BLE notifications from the ESP32 Cardiac Monitor service:

| Characteristic | UUID Suffix | Dart Parsing |
|---------------|-------------|--------------|
| Heart Rate | CC01 | `ByteData.getUint16(0, Endian.little) / 10.0` |
| SpO2 | CC02 | `bytes[0]` |
| Risk Score | CC03 | `ByteData.getFloat32(0, Endian.little)` |
| Risk Label | CC04 | `utf8.decode(bytes)` |
| Status | CC05 | `bytes[0]` bitmask |

## API Connection

Default: `https://sanuka0523-cardiac-monitor-api.hf.space`

Configurable in Settings screen. The app uses JWT tokens stored in flutter_secure_storage, with automatic header injection via Dio interceptor.
