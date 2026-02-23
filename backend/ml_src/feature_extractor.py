"""
ECG Feature Extraction for XGBoost model.
Extracts 26 signal features from single-lead ECG using NeuroKit2.
This module is shared between ml/ training and backend/ inference.
"""

import numpy as np
import neurokit2 as nk
from scipy.stats import kurtosis, skew


def extract_ecg_features(ecg_signal: np.ndarray, sample_rate: int = 100,
                         heart_rate_sensor: float = None,
                         spo2: float = None) -> dict:
    """
    Extract 26 features from single-lead ECG signal.

    Args:
        ecg_signal: 1D numpy array of ECG samples
        sample_rate: Sampling rate in Hz (100 for ESP32, 500 for PTB-XL)
        heart_rate_sensor: HR from MAX30100 (optional, for device features)
        spo2: SpO2 from MAX30100 (optional, for device features)

    Returns:
        dict of 26 features (keys match XGBoost training feature names)
    """
    features = {}

    try:
        # Clean the ECG signal
        ecg_cleaned = nk.ecg_clean(ecg_signal, sampling_rate=sample_rate)

        # Detect R-peaks
        _, rpeaks = nk.ecg_peaks(ecg_cleaned, sampling_rate=sample_rate)
        r_peak_indices = rpeaks.get("ECG_R_Peaks", np.array([]))

        if len(r_peak_indices) < 3:
            return _fallback_features(ecg_signal, heart_rate_sensor, spo2)

        # --- HRV Time-Domain Features (7) ---
        rr_intervals = np.diff(r_peak_indices) / sample_rate * 1000  # ms

        features["mean_rr"] = float(np.mean(rr_intervals))
        features["sdnn"] = float(np.std(rr_intervals, ddof=1)) if len(rr_intervals) > 1 else 0.0
        features["rmssd"] = float(np.sqrt(np.mean(np.diff(rr_intervals) ** 2))) if len(rr_intervals) > 1 else 0.0

        nn_diff = np.abs(np.diff(rr_intervals))
        features["pnn50"] = float(np.sum(nn_diff > 50) / len(nn_diff) * 100) if len(nn_diff) > 0 else 0.0

        hr_from_rr = 60000.0 / rr_intervals
        features["mean_hr_ecg"] = float(np.mean(hr_from_rr))
        features["hr_std"] = float(np.std(hr_from_rr))
        features["rr_range"] = float(np.max(rr_intervals) - np.min(rr_intervals))

        # --- ECG Morphology Features (9) ---
        try:
            # Delineate ECG waves
            _, waves = nk.ecg_delineate(ecg_cleaned, rpeaks, sampling_rate=sample_rate, method="dwt")

            # QRS duration
            qrs_onsets = [x for x in waves.get("ECG_Q_Peaks", []) if isinstance(x, (int, float)) and not np.isnan(x)]
            qrs_offsets = [x for x in waves.get("ECG_S_Peaks", []) if isinstance(x, (int, float)) and not np.isnan(x)]
            if qrs_onsets and qrs_offsets:
                qrs_durations = []
                for q, s in zip(qrs_onsets[:len(qrs_offsets)], qrs_offsets[:len(qrs_onsets)]):
                    qrs_durations.append(abs(s - q) / sample_rate * 1000)
                features["qrs_duration"] = float(np.mean(qrs_durations)) if qrs_durations else 100.0
            else:
                features["qrs_duration"] = 100.0

            # R amplitude
            r_amplitudes = ecg_cleaned[r_peak_indices.astype(int)]
            features["r_amplitude"] = float(np.mean(r_amplitudes))
            features["r_amplitude_std"] = float(np.std(r_amplitudes))

            # QT interval
            t_offsets = [x for x in waves.get("ECG_T_Offsets", []) if isinstance(x, (int, float)) and not np.isnan(x)]
            if qrs_onsets and t_offsets:
                qt_intervals = []
                for q, t in zip(qrs_onsets[:len(t_offsets)], t_offsets[:len(qrs_onsets)]):
                    qt_intervals.append(abs(t - q) / sample_rate * 1000)
                features["qt_interval"] = float(np.mean(qt_intervals)) if qt_intervals else 400.0
                # Bazett's QTc
                mean_rr_sec = features["mean_rr"] / 1000
                features["qtc"] = float(features["qt_interval"] / np.sqrt(mean_rr_sec)) if mean_rr_sec > 0 else 440.0
            else:
                features["qt_interval"] = 400.0
                features["qtc"] = 440.0

            # ST level (amplitude at J-point, ~40ms after R-peak)
            j_offset = int(0.04 * sample_rate)
            st_levels = []
            for rp in r_peak_indices.astype(int):
                j_idx = rp + j_offset
                if j_idx < len(ecg_cleaned):
                    st_levels.append(ecg_cleaned[j_idx])
            features["st_level"] = float(np.mean(st_levels)) if st_levels else 0.0

            # T-wave amplitude
            t_peaks = [x for x in waves.get("ECG_T_Peaks", []) if isinstance(x, (int, float)) and not np.isnan(x)]
            if t_peaks:
                t_amps = [ecg_cleaned[int(t)] for t in t_peaks if int(t) < len(ecg_cleaned)]
                features["t_amplitude"] = float(np.mean(t_amps)) if t_amps else 0.0
            else:
                features["t_amplitude"] = 0.0

            # P-wave ratio (P amplitude / R amplitude)
            p_peaks = [x for x in waves.get("ECG_P_Peaks", []) if isinstance(x, (int, float)) and not np.isnan(x)]
            if p_peaks and features["r_amplitude"] != 0:
                p_amps = [ecg_cleaned[int(p)] for p in p_peaks if int(p) < len(ecg_cleaned)]
                features["p_wave_ratio"] = float(np.mean(p_amps) / features["r_amplitude"]) if p_amps else 0.1
            else:
                features["p_wave_ratio"] = 0.1

        except Exception:
            features.setdefault("qrs_duration", 100.0)
            features.setdefault("r_amplitude", float(np.max(ecg_cleaned) - np.min(ecg_cleaned)))
            features.setdefault("r_amplitude_std", 0.0)
            features.setdefault("qt_interval", 400.0)
            features.setdefault("qtc", 440.0)
            features.setdefault("st_level", 0.0)
            features.setdefault("t_amplitude", 0.0)
            features.setdefault("p_wave_ratio", 0.1)

        # --- Signal Statistics (6) ---
        features["rms"] = float(np.sqrt(np.mean(ecg_cleaned ** 2)))
        features["entropy"] = float(_sample_entropy(ecg_cleaned))
        features["zero_crossing_rate"] = float(
            np.sum(np.diff(np.sign(ecg_cleaned - np.mean(ecg_cleaned))) != 0) / len(ecg_cleaned)
        )
        features["kurtosis"] = float(kurtosis(ecg_cleaned))
        features["skewness"] = float(skew(ecg_cleaned))
        features["snr"] = float(_estimate_snr(ecg_cleaned, sample_rate))

        # --- Device Sensor Features (4) ---
        features["heart_rate_sensor"] = float(heart_rate_sensor) if heart_rate_sensor else features["mean_hr_ecg"]
        features["spo2"] = float(spo2) if spo2 else 97.0

        hr_diff = abs(features["heart_rate_sensor"] - features["mean_hr_ecg"])
        features["hr_sensor_ecg_diff"] = float(hr_diff)

        # ECG quality score (based on peak regularity)
        if len(rr_intervals) > 1:
            cv = np.std(rr_intervals) / np.mean(rr_intervals)
            features["ecg_quality"] = float(max(0, 1 - cv))
        else:
            features["ecg_quality"] = 0.5

    except Exception:
        return _fallback_features(ecg_signal, heart_rate_sensor, spo2)

    return features


def _sample_entropy(signal, m=2, r_factor=0.2):
    """Approximate sample entropy."""
    try:
        r = r_factor * np.std(signal)
        N = len(signal)
        if N < m + 2 or r == 0:
            return 0.0

        # Use simplified approach for speed
        templates_m = np.array([signal[i:i + m] for i in range(N - m)])
        templates_m1 = np.array([signal[i:i + m + 1] for i in range(N - m - 1)])

        count_m = 0
        count_m1 = 0

        # Sample subset for speed
        n_check = min(200, len(templates_m))
        indices = np.random.choice(len(templates_m), n_check, replace=False) if len(templates_m) > n_check else range(len(templates_m))

        for i in indices:
            dist_m = np.max(np.abs(templates_m - templates_m[i]), axis=1)
            count_m += np.sum(dist_m < r) - 1

            if i < len(templates_m1):
                dist_m1 = np.max(np.abs(templates_m1 - templates_m1[i]), axis=1)
                count_m1 += np.sum(dist_m1 < r) - 1

        if count_m == 0 or count_m1 == 0:
            return 0.0

        return -np.log(count_m1 / count_m)
    except Exception:
        return 0.0


def _estimate_snr(signal, sample_rate):
    """Estimate signal-to-noise ratio."""
    try:
        cleaned = nk.ecg_clean(signal, sampling_rate=sample_rate)
        noise = signal - cleaned
        signal_power = np.mean(cleaned ** 2)
        noise_power = np.mean(noise ** 2)
        if noise_power == 0:
            return 30.0
        return float(10 * np.log10(signal_power / noise_power))
    except Exception:
        return 10.0


def _fallback_features(ecg_signal, heart_rate_sensor=None, spo2=None) -> dict:
    """Return default features when ECG processing fails."""
    return {
        "mean_rr": 800.0, "sdnn": 50.0, "rmssd": 30.0, "pnn50": 10.0,
        "mean_hr_ecg": 75.0, "hr_std": 5.0, "rr_range": 200.0,
        "qrs_duration": 100.0, "r_amplitude": 1.0, "r_amplitude_std": 0.1,
        "qt_interval": 400.0, "qtc": 440.0, "st_level": 0.0,
        "t_amplitude": 0.3, "p_wave_ratio": 0.1,
        "rms": float(np.sqrt(np.mean(ecg_signal ** 2))) if len(ecg_signal) > 0 else 0.5,
        "entropy": 0.5, "zero_crossing_rate": 0.1,
        "kurtosis": 0.0, "skewness": 0.0, "snr": 10.0,
        "heart_rate_sensor": float(heart_rate_sensor) if heart_rate_sensor else 75.0,
        "spo2": float(spo2) if spo2 else 97.0,
        "hr_sensor_ecg_diff": 0.0, "ecg_quality": 0.5,
    }


# Ordered feature names for XGBoost (must match training order)
FEATURE_NAMES = [
    "mean_rr", "sdnn", "rmssd", "pnn50", "mean_hr_ecg", "hr_std", "rr_range",
    "qrs_duration", "r_amplitude", "r_amplitude_std", "qt_interval", "qtc",
    "st_level", "t_amplitude", "p_wave_ratio",
    "rms", "entropy", "zero_crossing_rate", "kurtosis", "skewness", "snr",
    "heart_rate_sensor", "spo2", "hr_sensor_ecg_diff", "ecg_quality",
]

# User profile feature names (appended after ECG features)
PROFILE_FEATURE_NAMES = [
    "age", "sex", "bmi", "is_diabetic", "is_hypertensive",
    "is_smoker", "family_history",
]

# Historical baseline feature names
HISTORY_FEATURE_NAMES = [
    "hr_baseline_24h", "hr_baseline_7d", "spo2_baseline_24h",
    "hr_deviation", "spo2_deviation", "resting_hr_trend", "readings_count_24h",
]

ALL_FEATURE_NAMES = FEATURE_NAMES + PROFILE_FEATURE_NAMES + HISTORY_FEATURE_NAMES


def features_to_array(features: dict, include_profile: bool = False) -> np.ndarray:
    """Convert feature dict to numpy array in correct order for XGBoost."""
    names = ALL_FEATURE_NAMES if include_profile else FEATURE_NAMES
    return np.array([features.get(name, 0.0) for name in names], dtype=np.float32)
