"""
ML inference service for cardiac risk prediction.
Loads ECGFounder + XGBoost ensemble and runs prediction on incoming vitals.
"""

import os
import sys
import numpy as np
from scipy.signal import resample
import torch
import joblib

# Import model architecture from bundled ml_src/
BACKEND_ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
ML_SRC = os.path.join(BACKEND_ROOT, "ml_src")
sys.path.insert(0, ML_SRC)

from net1d import Net1D  # noqa: E402
from feature_extractor import extract_ecg_features, features_to_array, FEATURE_NAMES  # noqa: E402

# Model paths — bundled in backend/ml_models/
MODEL_DIR = os.path.join(BACKEND_ROOT, "ml_models")

# Ensemble weights
ECG_WEIGHT = 0.60
XGB_WEIGHT = 0.40

# Risk labels
RISK_LABELS = {
    (0.0, 0.2): "normal",
    (0.2, 0.4): "low",
    (0.4, 0.6): "moderate",
    (0.6, 0.8): "elevated",
    (0.8, 1.01): "high",
}

# Global model instances
_ecg_model = None
_xgb_model = None
_device = None
_models_loaded = False


def get_risk_label(score: float) -> str:
    for (low, high), label in RISK_LABELS.items():
        if low <= score < high:
            return label
    return "high"


def load_models():
    """Load both models into memory. Called once at startup."""
    global _ecg_model, _xgb_model, _device, _models_loaded

    if _models_loaded:
        return True

    # Select device
    if torch.cuda.is_available():
        _device = torch.device("cuda:0")
    elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
        _device = torch.device("mps")
    else:
        _device = torch.device("cpu")

    ecg_path = os.path.join(MODEL_DIR, "ecgfounder_best.pt")
    xgb_path = os.path.join(MODEL_DIR, "xgboost_cardiac.joblib")

    # Load ECGFounder
    if os.path.exists(ecg_path):
        try:
            _ecg_model = Net1D(
                in_channels=1,
                base_filters=64,
                ratio=1,
                filter_list=[64, 160, 160, 400, 400, 1024, 1024],
                m_blocks_list=[2, 2, 2, 3, 3, 4, 4],
                kernel_size=16,
                stride=2,
                groups_width=16,
                verbose=False,
                use_bn=False,
                use_do=False,
                n_classes=1,
            )
            state_dict = torch.load(ecg_path, map_location=_device, weights_only=False)
            _ecg_model.load_state_dict(state_dict)
            _ecg_model.to(_device)
            _ecg_model.eval()
            print(f"[ML] ECGFounder loaded on {_device}")
        except Exception as e:
            print(f"[ML] Failed to load ECGFounder: {e}")
            _ecg_model = None
    else:
        print(f"[ML] ECGFounder not found at {ecg_path}")

    # Load XGBoost
    if os.path.exists(xgb_path):
        try:
            _xgb_model = joblib.load(xgb_path)
            print("[ML] XGBoost loaded")
        except Exception as e:
            print(f"[ML] Failed to load XGBoost: {e}")
            _xgb_model = None
    else:
        print(f"[ML] XGBoost not found at {xgb_path}")

    _models_loaded = True
    return _ecg_model is not None or _xgb_model is not None


def predict(ecg_samples: list, sample_rate_hz: int = 100,
            heart_rate_bpm: float = None, spo2_percent: float = None,
            user_profile: dict = None, history_features: dict = None) -> dict:
    """
    Run ensemble prediction on ECG data.

    Args:
        ecg_samples: list of ECG ADC values from ESP32
        sample_rate_hz: device sample rate (100Hz for ESP32)
        heart_rate_bpm: HR from MAX30100
        spo2_percent: SpO2 from MAX30100
        user_profile: dict with age, sex, bmi, is_diabetic, etc.
        history_features: dict with hr_baseline_24h, etc.

    Returns:
        dict with risk_score, risk_label, confidence, features, model_version
    """
    if not _models_loaded:
        load_models()

    ecg = np.array(ecg_samples, dtype=np.float32)
    result = {
        "risk_score": 0.0,
        "risk_label": "unknown",
        "confidence": 0.0,
        "features": {},
        "model_version": "v1.0-ensemble",
    }

    prob_ecg = None
    prob_xgb = None

    # --- ECGFounder Prediction ---
    if _ecg_model is not None:
        try:
            # Upsample from device rate to 500Hz (5000 samples for 10s)
            target_length = 5000
            if len(ecg) != target_length:
                ecg_500hz = resample(ecg, target_length)
            else:
                ecg_500hz = ecg.copy()

            # Z-score normalize
            mean = np.mean(ecg_500hz)
            std = np.std(ecg_500hz) + 1e-8
            ecg_500hz = (ecg_500hz - mean) / std
            ecg_500hz = np.nan_to_num(ecg_500hz, nan=0.0)

            # Shape: (1, 1, 5000)
            tensor = torch.FloatTensor(ecg_500hz).reshape(1, 1, -1).to(_device)

            with torch.no_grad():
                logit = _ecg_model(tensor)
                prob_ecg = float(torch.sigmoid(logit).cpu().item())

        except Exception as e:
            print(f"[ML] ECGFounder inference error: {e}")
            prob_ecg = None

    # --- XGBoost Prediction ---
    if _xgb_model is not None:
        try:
            # Extract features at device sample rate
            features = extract_ecg_features(
                ecg, sample_rate=sample_rate_hz,
                heart_rate_sensor=heart_rate_bpm,
                spo2=spo2_percent,
            )

            # Add user profile features
            if user_profile:
                features["age"] = user_profile.get("age", 50)
                features["sex"] = 1 if user_profile.get("sex") == "male" else 0
                h = user_profile.get("height_cm", 170) / 100
                w = user_profile.get("weight_kg", 70)
                features["bmi"] = w / (h * h) if h > 0 else 25.0
                features["is_diabetic"] = 1 if user_profile.get("is_diabetic") else 0
                features["is_hypertensive"] = 1 if user_profile.get("is_hypertensive") else 0
                features["is_smoker"] = 1 if user_profile.get("is_smoker") else 0
                features["family_history"] = 1 if user_profile.get("family_history") else 0

            # Add historical baseline features
            if history_features:
                for key in ["hr_baseline_24h", "hr_baseline_7d", "spo2_baseline_24h",
                            "hr_deviation", "spo2_deviation", "resting_hr_trend",
                            "readings_count_24h"]:
                    features[key] = history_features.get(key, 0.0)

            # Convert to array (25 ECG features only for base model)
            feat_array = features_to_array(features, include_profile=False).reshape(1, -1)
            prob_xgb = float(_xgb_model.predict_proba(feat_array)[0, 1])

            # Store features in result
            result["features"] = {k: round(v, 4) for k, v in features.items()
                                  if k in FEATURE_NAMES[:10]}  # Top 10 for response size

        except Exception as e:
            print(f"[ML] XGBoost inference error: {e}")
            prob_xgb = None

    # --- Ensemble ---
    if prob_ecg is not None and prob_xgb is not None:
        risk_score = ECG_WEIGHT * prob_ecg + XGB_WEIGHT * prob_xgb
        confidence = 1.0 - abs(prob_ecg - prob_xgb)  # Higher when models agree
        result["model_version"] = "v1.0-ensemble"
    elif prob_ecg is not None:
        risk_score = prob_ecg
        confidence = 0.7
        result["model_version"] = "v1.0-ecgfounder-only"
    elif prob_xgb is not None:
        risk_score = prob_xgb
        confidence = 0.6
        result["model_version"] = "v1.0-xgboost-only"
    else:
        return result  # No models available

    result["risk_score"] = round(float(risk_score), 4)
    result["risk_label"] = get_risk_label(risk_score)
    result["confidence"] = round(float(confidence), 4)

    return result
