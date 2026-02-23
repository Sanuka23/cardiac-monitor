---
title: Cardiac Monitor API
emoji: ❤️
colorFrom: red
colorTo: blue
sdk: docker
pinned: false
license: mit
app_port: 7860
short_description: Cardiac monitoring API with ML risk prediction
---

# Cardiac Monitor API

FastAPI backend for the ESP32 cardiac monitoring system. Handles user authentication, device management, vitals storage, and ML-based cardiac risk prediction.

## Live Deployment

**URL**: `https://sanuka0523-cardiac-monitor-api.hf.space`

Hosted on Hugging Face Spaces (Docker SDK). The API docs are available at `/docs` (Swagger UI).

## Tech Stack

- **Framework**: FastAPI 0.115
- **Database**: MongoDB Atlas via Motor (async)
- **Auth**: JWT (python-jose) + bcrypt password hashing
- **ML**: PyTorch (ECGFounder) + XGBoost ensemble
- **Signal Processing**: NeuroKit2, SciPy

## API Reference

### Authentication

| Method | Path | Body | Response |
|--------|------|------|----------|
| POST | `/api/v1/auth/register` | `{email, password, name}` | `{access_token, token_type}` |
| POST | `/api/v1/auth/login` | Form: `username, password` | `{access_token, token_type}` |
| GET | `/api/v1/auth/me` | — | User object |
| PUT | `/api/v1/auth/profile` | `{health_profile: {...}}` | Updated user |

### Devices

| Method | Path | Body | Response |
|--------|------|------|----------|
| POST | `/api/v1/devices/register` | `{device_id}` | Device object |
| GET | `/api/v1/devices` | — | List of devices |

### Vitals (ESP32 uploads)

| Method | Path | Auth | Body |
|--------|------|------|------|
| POST | `/api/v1/vitals` | API Key | `{device_id, timestamp, ecg_samples, heart_rate_bpm, spo2_percent, ...}` |
| GET | `/api/v1/vitals/{device_id}` | JWT | Vitals history (paginated) |
| GET | `/api/v1/vitals/{device_id}/latest` | JWT | Latest vitals reading |

### Predictions

| Method | Path | Auth | Response |
|--------|------|------|----------|
| GET | `/api/v1/predictions/{device_id}/latest` | JWT | Latest risk prediction |
| GET | `/api/v1/predictions/{device_id}` | JWT | Prediction history |

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `MONGODB_URI` | MongoDB Atlas connection string | Yes |
| `DATABASE_NAME` | Database name (default: `cardiac_monitor`) | No |
| `JWT_SECRET` | Secret key for JWT signing | Yes |
| `API_KEY` | API key for ESP32 device auth | Yes |

## Database Collections

| Collection | Purpose | Key Fields |
|------------|---------|------------|
| `users` | User accounts + health profiles | email, password_hash, health_profile |
| `devices` | Registered ESP32 devices | device_id, owner_user_id |
| `vitals` | Raw vitals readings | device_id, timestamp, ecg_samples, heart_rate_bpm |
| `predictions` | ML risk predictions | vitals_id, risk_score, risk_label, confidence |

## ML Pipeline

On each vitals upload, the backend runs an ensemble prediction:

1. **ECGFounder** (PyTorch): Deep learning model extracts features from raw ECG waveform
2. **Feature Engineering**: 14 clinical features (HRV, QRS duration, signal quality, etc.)
3. **XGBoost**: Gradient-boosted classifier on combined features
4. **Ensemble**: Weighted combination produces final risk score (0.0-1.0) and label

Risk labels: `normal`, `low`, `moderate`, `elevated`, `high`

## Local Development

```bash
cd backend
pip install -r requirements.txt

# Set environment variables
export MONGODB_URI="mongodb+srv://..."
export JWT_SECRET="your-secret"
export API_KEY="your-api-key"

# Run
uvicorn app.main:app --reload --port 8000
```

## Docker Deployment

```bash
docker build -t cardiac-api .
docker run -p 7860:7860 \
  -e MONGODB_URI="..." \
  -e JWT_SECRET="..." \
  -e API_KEY="..." \
  cardiac-api
```

## Project Structure

```
backend/
├── app/
│   ├── main.py              # FastAPI app, CORS, router mounting
│   ├── config.py            # Pydantic settings (env vars)
│   ├── database.py          # Motor client, index creation
│   ├── middleware/
│   │   └── auth.py          # JWT + API key verification
│   ├── models/              # Pydantic request/response models
│   │   ├── user.py
│   │   ├── device.py
│   │   ├── vitals.py
│   │   └── prediction.py
│   ├── routes/              # API endpoint handlers
│   │   ├── auth.py
│   │   ├── devices.py
│   │   ├── health.py
│   │   ├── vitals.py
│   │   └── predictions.py
│   └── services/
│       └── ml_service.py    # ML model loading + prediction
├── ml_src/
│   ├── ecg_foundation.py    # ECGFounder model definition
│   └── feature_engineer.py  # Clinical feature extraction
├── ml_models/               # Trained model files (LFS)
│   ├── ecgfounder_best.pt
│   └── xgboost_cardiac.joblib
├── Dockerfile
└── requirements.txt
```
