<div align="center">

# Cardiac Monitor

### Real-time IoT Heart Monitoring System with ML-Powered Risk Prediction

[![Flutter CI](https://img.shields.io/github/actions/workflow/status/Sanuka23/cardiac-monitor/flutter-ci.yml?label=Flutter%20CI&logo=flutter&logoColor=white&style=for-the-badge)](https://github.com/Sanuka23/cardiac-monitor/actions/workflows/flutter-ci.yml)
[![Backend CI](https://img.shields.io/github/actions/workflow/status/Sanuka23/cardiac-monitor/backend-ci.yml?label=Backend%20CI&logo=fastapi&logoColor=white&style=for-the-badge)](https://github.com/Sanuka23/cardiac-monitor/actions/workflows/backend-ci.yml)
[![Firmware CI](https://img.shields.io/github/actions/workflow/status/Sanuka23/cardiac-monitor/firmware-ci.yml?label=Firmware%20CI&logo=espressif&logoColor=white&style=for-the-badge)](https://github.com/Sanuka23/cardiac-monitor/actions/workflows/firmware-ci.yml)
[![Security](https://img.shields.io/github/actions/workflow/status/Sanuka23/cardiac-monitor/security-scan.yml?label=Security&logo=githubactions&logoColor=white&style=for-the-badge)](https://github.com/Sanuka23/cardiac-monitor/actions/workflows/security-scan.yml)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.11+-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Python](https://img.shields.io/badge/Python-3.11-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.115-009688?style=for-the-badge&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)

---

[**API Swagger Docs**](https://sanuka0523-cardiac-monitor-api.hf.space/docs) &nbsp;&bull;&nbsp; [**Download APK**](https://github.com/Sanuka23/cardiac-monitor/releases/latest) &nbsp;&bull;&nbsp; [**API Health Check**](https://sanuka0523-cardiac-monitor-api.hf.space/api/v1/health)

</div>

---

## About

A full-stack IoT cardiac monitoring system that captures **real-time heart rate, SpO2, and single-lead ECG** data from an ESP32 wearable device, streams it to a cloud backend with **ML-based risk prediction** (ECGFounder + XGBoost ensemble), and displays everything in a **Flutter mobile app** with dual-theme glassmorphic UI.

---

## Architecture

```
┌─────────────────┐     BLE      ┌──────────────┐     HTTPS    ┌──────────────────┐
│   ESP32 Device  │─────────────>│  Flutter App │─────────────>│  FastAPI Backend │
│  MAX30100+AD8232│              │  (Provider)  │              │  (HF Spaces)     │
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

---

## Tech Stack

<table>
<tr>
<td align="center" width="25%">

**Mobile App**

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat-square&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=flat-square&logo=dart&logoColor=white)
![Provider](https://img.shields.io/badge/Provider-State_Mgmt-6C63FF?style=flat-square)
![BLE](https://img.shields.io/badge/BLE-flutter__blue__plus-0082FC?style=flat-square&logo=bluetooth&logoColor=white)

</td>
<td align="center" width="25%">

**Backend API**

![FastAPI](https://img.shields.io/badge/FastAPI-009688?style=flat-square&logo=fastapi&logoColor=white)
![MongoDB](https://img.shields.io/badge/MongoDB-47A248?style=flat-square&logo=mongodb&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white)
![JWT](https://img.shields.io/badge/JWT-Auth-000000?style=flat-square&logo=jsonwebtokens&logoColor=white)

</td>
<td align="center" width="25%">

**ML Pipeline**

![PyTorch](https://img.shields.io/badge/PyTorch-EE4C2C?style=flat-square&logo=pytorch&logoColor=white)
![XGBoost](https://img.shields.io/badge/XGBoost-Ensemble-189FDD?style=flat-square)
![NeuroKit2](https://img.shields.io/badge/NeuroKit2-ECG_Signal-4CAF50?style=flat-square)
![NumPy](https://img.shields.io/badge/NumPy-013243?style=flat-square&logo=numpy&logoColor=white)

</td>
<td align="center" width="25%">

**Firmware**

![ESP32](https://img.shields.io/badge/ESP32-E7352C?style=flat-square&logo=espressif&logoColor=white)
![PlatformIO](https://img.shields.io/badge/PlatformIO-FF7F00?style=flat-square&logo=platformio&logoColor=white)
![Arduino](https://img.shields.io/badge/Arduino-00878F?style=flat-square&logo=arduino&logoColor=white)
![NimBLE](https://img.shields.io/badge/NimBLE-BLE_Stack-0082FC?style=flat-square)

</td>
</tr>
</table>

---

## Features

### Monitoring

- **Real-time vitals** — Heart rate, SpO2, and single-lead ECG via BLE streaming
- **Historical baselines** — 24h and 7-day running averages for deviation detection
- **Interactive charts** — Zoomable vitals history with time-range filtering

### Intelligence

- **ML risk prediction** — ECGFounder 1D CNN + XGBoost ensemble model
- **Personalized risk** — Uses health profile (age, conditions, medications) for better predictions
- **5-level risk scoring** — Normal, Low, Moderate, Elevated, High with confidence scores

### Connectivity

- **BLE provisioning** — WiFi credentials sent to ESP32 via BLE GATT service
- **Dual data path** — BLE for real-time display, WiFi for cloud upload
- **JWT authentication** — Secure user accounts with health profiles

### Design

- **Dual theme UI** — Light and dark glassmorphic Material 3 themes
- **Animated transitions** — Smooth value changes and screen transitions
- **Responsive layout** — Adaptive cards and charts across screen sizes

---

## Project Structure

```
cardiac-monitor/
├── app/cardiac_monitor/       # Flutter mobile app
│   ├── lib/
│   │   ├── screens/           # 6 UI screens (login, dashboard, history...)
│   │   ├── widgets/           # Reusable components (vital cards, charts...)
│   │   ├── services/          # API client, BLE, auth storage
│   │   ├── providers/         # State management (auth, vitals, BLE...)
│   │   ├── models/            # Data models (user, device, vitals...)
│   │   └── config/            # Theme & constants
│   └── pubspec.yaml
├── backend/                   # FastAPI cloud backend
│   ├── app/                   # Routes, models, services, middleware
│   ├── ml_src/                # ML model architecture & feature extraction
│   ├── ml_models/             # Trained model files (Git LFS)
│   ├── Dockerfile             # Production container
│   └── requirements.txt
├── firmware/                  # ESP32 embedded firmware
│   ├── src/                   # C++ source (sensors, BLE, WiFi, data sender)
│   ├── include/config.h       # All configuration constants
│   └── platformio.ini
├── ml/                        # ML training & research (offline)
│   ├── src/                   # Training scripts
│   ├── notebooks/             # Jupyter experiments
│   └── data/                  # PTB-XL dataset
├── docs/                      # Hardware wiring & setup guides
└── .github/workflows/         # CI/CD pipelines
```

---

## Quick Start

### 1. Backend (Already Deployed)

> **Live API**: <https://sanuka0523-cardiac-monitor-api.hf.space>
>
> **Swagger Docs**: <https://sanuka0523-cardiac-monitor-api.hf.space/docs>

To run locally:
```bash
cd backend
pip install -r requirements.txt

# Set environment variables
export MONGODB_URI="your-mongodb-uri"
export JWT_SECRET="your-secret"
export API_KEY="your-api-key"

uvicorn app.main:app --reload --port 7860
```

### 2. Firmware

```bash
cd firmware
pio run --target upload    # Build & flash to ESP32
pio device monitor         # View serial output
```

> See [firmware/README.md](firmware/README.md) for hardware wiring, BLE services, and configuration.

### 3. Mobile App

```bash
cd app/cardiac_monitor
flutter pub get
flutter run
```

> See [app/cardiac_monitor/README.md](app/cardiac_monitor/README.md) for build instructions and BLE data format.

---

## API Reference

> **Full interactive docs**: [Swagger UI](https://sanuka0523-cardiac-monitor-api.hf.space/docs) &nbsp;|&nbsp; [ReDoc](https://sanuka0523-cardiac-monitor-api.hf.space/redoc)

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/api/v1/health` | - | Health check |
| `POST` | `/api/v1/auth/register` | - | Create account |
| `POST` | `/api/v1/auth/login` | - | Get JWT token |
| `GET` | `/api/v1/auth/me` | JWT | Current user profile |
| `PUT` | `/api/v1/auth/profile` | JWT | Update health profile |
| `POST` | `/api/v1/devices/register` | JWT | Register ESP32 device |
| `GET` | `/api/v1/devices` | JWT | List registered devices |
| `POST` | `/api/v1/vitals` | API Key | Upload vitals + trigger ML prediction |
| `GET` | `/api/v1/vitals/{device_id}` | JWT | Vitals history |
| `GET` | `/api/v1/predictions/{device_id}` | JWT | Prediction history |

---

## Hardware

| Component | Description |
|-----------|-------------|
| **ESP32 CP2102** | 30-pin DevKit with WiFi + BLE |
| **MAX30100** | Pulse oximeter (HR + SpO2 via I2C) |
| **AD8232** | Single-lead ECG analog front-end |
| **ECG Electrodes** | 3-lead cable (RA, LA, RL placement) |

> See [docs/WIRING.md](docs/WIRING.md) for pin connections, electrode placement, and the critical I2C pull-up resistor fix.

---

## CI/CD Pipeline

All workflows run via [GitHub Actions](https://github.com/Sanuka23/cardiac-monitor/actions):

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| **Flutter CI** | Tag push (`v*`) | Analyze, test, build release APK |
| **Backend CI** | Tag push (`v*`) | Flake8 lint, Docker image build |
| **Firmware CI** | Push/PR to `main` | PlatformIO ESP32 build |
| **Security Scan** | Push/PR + weekly | CodeQL, Bandit, pip-audit |
| **Release** | Tag push (`v*`) | Build all + deploy to HF Spaces + GitHub Release |

---

## Documentation

| Document | Description |
|----------|-------------|
| [App README](app/cardiac_monitor/README.md) | Flutter app architecture, BLE data format, build setup |
| [Backend README](backend/README.md) | API endpoints, ML pipeline, Docker deployment |
| [Firmware README](firmware/README.md) | ESP32 config, BLE services, sensor setup |
| [ML Pipeline](backend/ml_src/README.md) | ECGFounder + XGBoost model architecture |
| [Wiring Guide](docs/WIRING.md) | Hardware connections and troubleshooting |

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
