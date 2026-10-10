from app.routes.vitals import _ecg_heart_rate


def test_uses_ecg_measured_heart_rate_from_model_features():
    assert _ecg_heart_rate({"mean_hr_ecg": 71.3456, "rmssd": 30.1}) == 71.3


def test_ignores_missing_or_implausible_values():
    assert _ecg_heart_rate({}) is None
    assert _ecg_heart_rate(None) is None
    assert _ecg_heart_rate({"mean_hr_ecg": 0}) is None
    assert _ecg_heart_rate({"mean_hr_ecg": 12.0}) is None
    assert _ecg_heart_rate({"mean_hr_ecg": 260.0}) is None
