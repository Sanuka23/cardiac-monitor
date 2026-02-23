# Cardiac Monitor

A full-stack IoT cardiac monitoring system that captures real-time heart rate, SpO2, and ECG data from an ESP32 wearable device, streams it to a cloud backend with ML-based risk prediction, and displays everything in a Flutter mobile app.

## Architecture

```
┌─────────────────┐     BLE      ┌──────────────┐     HTTPS     ┌──────────────────┐
│   ESP32 Device  │─────────────>│  Flutter App  │──────────────>│  FastAPI Backend  │
│  MAX30100+AD8232│              │  (Provider)   │              │  (HF Spaces)     │
└────────┬────────┘              └──────────────┘              └────────┬─────────┘
         │ WiFi                                                         │
         └─────────────────── POST /api/v1/vitals ─────────────────────>│
                                                                        │
                                                              ┌─────────┴─────────┐
                                                              │  ML Pipeline      │
                                                              │  ECGFounder +     │
                                                              │  XGBoost Ensemble │
                                                              └─────────┬─────────┘
                                                                        │
                                                              ┌─────────┴─────────┐
                                                              │  MongoDB Atlas    │
                                                              │  (vitals, users,  │
                                                              │   predictions)    │
                                                              └───────────────────┘
```

## Components

| Component | Directory | Tech Stack |
|-----------|-----------|------------|
| Backend API | `backend/` | FastAPI, Motor (MongoDB), JWT auth |
| ML Pipeline | `backend/ml_src/` | PyTorch (ECGFounder), XGBoost, NeuroKit2 |
| Firmware | `firmware/` | ESP32, PlatformIO, MAX30100, AD8232 |
| Mobile App | `app/cardiac_monitor/` | Flutter, Provider, flutter_blue_plus |

## Features

- **Real-time vitals**: Heart rate, SpO2, and single-lead ECG via BLE
- **ML risk prediction**: ECGFounder deep learning + XGBoost ensemble model
- **Personalized risk**: Uses health profile (age, conditions, medications) for better predictions
- **Historical baselines**: 24h and 7-day running averages for deviation detection
- **BLE provisioning**: WiFi credentials sent to ESP32 via BLE GATT
- **JWT authentication**: Secure user accounts with health profiles
- **Dark glassmorphic UI**: Modern Material 3 dark theme with animations

## Quick Start

### 1. Backend (deployed)

The API is deployed at: `https://sanuka0523-cardiac-monitor-api.hf.space`

To run locally:
```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload
```

### 2. Firmware

```bash
cd firmware
pio run --target upload
pio device monitor
```

See [firmware/README.md](firmware/README.md) for hardware wiring and setup.

### 3. Mobile App

```bash
cd app/cardiac_monitor
flutter pub get
flutter run
```

See [app/cardiac_monitor/README.md](app/cardiac_monitor/README.md) for build instructions.

## API Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/v1/health` | None | Health check |
| POST | `/api/v1/auth/register` | None | Create account |
| POST | `/api/v1/auth/login` | None | Get JWT token |
| GET | `/api/v1/auth/me` | JWT | Current user |
| PUT | `/api/v1/auth/profile` | JWT | Update health profile |
| POST | `/api/v1/devices/register` | JWT | Register device |
| GET | `/api/v1/devices` | JWT | List devices |
| POST | `/api/v1/vitals` | API Key | Upload vitals + ML prediction |
| GET | `/api/v1/vitals/{device_id}` | JWT | Vitals history |
| GET | `/api/v1/predictions/{device_id}` | JWT | Prediction history |

## Hardware

- ESP32 CP2102 DevKit (30-pin)
- MAX30100 Pulse Oximeter
- AD8232 ECG Front-End
- 3-lead ECG electrode cable

## License

MIT
