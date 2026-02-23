---
title: Cardiac Monitor API
emoji: ❤️
colorFrom: red
colorTo: blue
sdk: docker
pinned: false
license: mit
app_port: 7860
---

# Cardiac Monitor API

FastAPI backend for ESP32 Heart Rate, SpO2 & ECG cardiac monitoring system with ML-based risk prediction.

## Endpoints

- `GET /api/v1/health` — Health check
- `POST /api/v1/auth/register` — Register
- `POST /api/v1/auth/login` — Login (JWT)
- `GET /api/v1/vitals/{device_id}` — Vitals history
- `GET /api/v1/predictions/{device_id}` — Risk predictions
