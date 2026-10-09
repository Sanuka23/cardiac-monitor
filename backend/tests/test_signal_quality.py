"""Tests for the ECG signal-quality gate (app/services/signal_quality.py).

Fixtures (see tests/fixtures/):
  ptbxl_lead2.json    real lead-II ECG from PTB-XL (CC BY 4.0), device-like ADC ints
  device_garbage.json windows uploaded by our ESP32 with no ECG in them
"""

import asyncio
import json
import os
import sys
import time
import types

import numpy as np
import pytest
from scipy.signal import butter, sosfiltfilt

from app.services.signal_quality import assess_ecg_quality

FIXTURES = os.path.join(os.path.dirname(__file__), "fixtures")


def _load(name):
    with open(os.path.join(FIXTURES, name)) as f:
        return json.load(f)


PTBXL = _load("ptbxl_lead2.json")["records"]
RATE_KEYS = {250: "samples_250hz", 100: "samples_100hz"}


def _pass_rate(label, fs):
    recs = [r for r in PTBXL if r["label"] == label]
    results = [assess_ecg_quality(r[RATE_KEYS[fs]], fs) for r in recs]
    rejected = [(rec["ecg_id"], res["reason"]) for rec, res in zip(recs, results)
                if res["quality"] != "good"]
    return 1 - len(rejected) / len(recs), rejected


# ── Real ECG must pass ──────────────────────────────────────────────


@pytest.mark.parametrize("fs", [250, 100])
@pytest.mark.parametrize("label", ["NORM", "MI"])
def test_real_ptbxl_ecg_is_mostly_good(label, fs):
    rate, rejected = _pass_rate(label, fs)
    print(f"{label} @ {fs} Hz: {rate:.0%} good; rejected {rejected}")
    assert rate >= 0.9, f"{label} @ {fs} Hz only {rate:.0%} good; rejected {rejected}"


@pytest.mark.parametrize("fs", [250, 100])
def test_atrial_fibrillation_is_not_rejected_for_irregularity(fs):
    rate, rejected = _pass_rate("AFIB", fs)
    print(f"AFIB @ {fs} Hz: {rate:.0%} good; rejected {rejected}")
    assert rate >= 0.8, f"AFIB @ {fs} Hz only {rate:.0%} good; rejected {rejected}"
    assert not any(reason == "irregular_rr" for _, reason in rejected)


def test_result_does_not_depend_on_dc_offset():
    # Old 100 Hz firmware sent raw ADC values centred around ~1800, not 2048.
    for rec in PTBXL:
        x = np.asarray(rec["samples_100hz"])
        centred = assess_ecg_quality(x, 100)
        shifted = assess_ecg_quality(np.clip(x - 250, 0, 4095), 100)
        assert shifted["quality"] == centred["quality"], rec["ecg_id"]


def test_heart_rate_agrees_between_sample_rates():
    for rec in PTBXL:
        r250 = assess_ecg_quality(rec["samples_250hz"], 250)
        r100 = assess_ecg_quality(rec["samples_100hz"], 100)
        if r250["quality"] == "good" and r100["quality"] == "good":
            assert 30 <= r250["hr_bpm"] <= 200
            assert abs(r250["hr_bpm"] - r100["hr_bpm"]) < 5, rec["ecg_id"]


# ── Garbage must fail ───────────────────────────────────────────────


def _t(fs, seconds=10.0):
    return np.arange(int(fs * seconds)) / fs


def _sine(fs, freq=1.2, amp=500):
    return 2048 + amp * np.sin(2 * np.pi * freq * _t(fs))


def _flat(fs):
    return 2048 + np.random.default_rng(1).normal(0, 2, _t(fs).size)


def _alternating_rails(fs):
    return np.resize([0, 4095], _t(fs).size)


def _mains(fs, freq=50.0, amp=3000, phase=0.7):
    return np.clip(2048 + amp * np.sin(2 * np.pi * freq * _t(fs) + phase), 0, 4095)


def _white_noise(fs):
    return np.clip(2048 + np.random.default_rng(2).normal(0, 300, _t(fs).size), 0, 4095)


def _step_decay(fs, step_at=1.27, height=700, tau=0.3):
    # What an unattached 250 Hz device produced: flat baseline with a small
    # residual ripple, one step, then exponential decay back to baseline.
    t = _t(fs)
    rng = np.random.default_rng(3)
    x = 2060 + 15 * np.sin(2 * np.pi * 22 * t) + rng.normal(0, 3, t.size)
    after = t >= step_at
    x[after] += height * np.exp(-(t[after] - step_at) / tau)
    return x


def _sawtooth(fs, freq=1.0, amp=100):
    return 2048 + amp * ((_t(fs) * freq) % 1.0)


def _filtered_noise(fs, seed, colour="lowpass"):
    # A floating input after the new firmware's 40 Hz low-pass, or 1/f noise.
    rng = np.random.default_rng(seed)
    w = rng.normal(0, 1, _t(fs).size)
    if colour == "lowpass":
        x = sosfiltfilt(butter(4, 40 if fs > 100 else 35, fs=fs, output="sos"), w)
    else:
        f = np.fft.rfftfreq(w.size, 1 / fs)
        f[0] = 1.0
        x = np.fft.irfft(np.fft.rfft(w) / np.sqrt(f), w.size)
    return np.clip(2048 + 300 * x / x.std(), 0, 4095)


GARBAGE = {
    "sine_1.2hz": _sine,
    "sine_0.8hz": lambda fs: _sine(fs, freq=0.8),
    "sine_2.5hz": lambda fs: _sine(fs, freq=2.5, amp=800),
    "flat_tiny_noise": _flat,
    "alternating_0_4095": _alternating_rails,
    "mains_50hz_clipped": _mains,
    "mains_50.3hz_clipped": lambda fs: _mains(fs, freq=50.3),
    "mains_50hz_unclipped": lambda fs: _mains(fs, amp=600, phase=1.1),
    "white_noise": _white_noise,
    "lowpass_noise_a": lambda fs: _filtered_noise(fs, 4),
    "lowpass_noise_b": lambda fs: _filtered_noise(fs, 5),
    "pink_noise": lambda fs: _filtered_noise(fs, 6, colour="pink"),
    "step_exponential_decay": _step_decay,
    "small_step_exponential_decay": lambda fs: _step_decay(fs, height=120),
    "sawtooth_1hz": _sawtooth,
}


@pytest.mark.parametrize("fs", [250, 100])
@pytest.mark.parametrize("name", sorted(GARBAGE))
def test_synthetic_garbage_is_poor(name, fs):
    x = np.round(GARBAGE[name](fs)).astype(int)
    result = assess_ecg_quality(list(x), fs)
    assert result["quality"] == "poor", f"{name} @ {fs} Hz: {result}"
    assert result["reason"] != "ok"


def test_too_short_window_is_poor():
    x = PTBXL[0]["samples_250hz"][:250]  # 1 s
    assert assess_ecg_quality(x, 250)["quality"] == "poor"


def test_real_device_garbage_is_poor():
    windows = _load("device_garbage.json")["windows"]
    assert 1 <= len(windows) <= 8
    for i, w in enumerate(windows):
        result = assess_ecg_quality(w["ecg_samples"], w["sample_rate_hz"])
        assert result["quality"] == "poor", f"device window {i}: {result}"


# ── Contract / performance ─────────────────────────────────────────


def test_result_shape():
    good = assess_ecg_quality(PTBXL[0]["samples_250hz"], 250)
    assert set(good) >= {"quality", "reason", "hr_bpm"}
    assert good["quality"] in ("good", "poor")
    assert isinstance(good["reason"], str)
    json.dumps(good)  # must be serialisable as-is

    flat = assess_ecg_quality(np.full(2500, 2048), 250)
    assert flat["quality"] == "poor"
    assert flat["hr_bpm"] is None


def test_runtime_per_window_is_small():
    windows = [(r["samples_250hz"], 250) for r in PTBXL] + [(r["samples_100hz"], 100) for r in PTBXL]
    assess_ecg_quality(*windows[0])  # warm-up
    start = time.perf_counter()
    for samples, fs in windows:
        assess_ecg_quality(samples, fs)
    per_window_ms = (time.perf_counter() - start) * 1000 / len(windows)
    print(f"mean runtime {per_window_ms:.2f} ms/window")
    assert per_window_ms < 25


# ── Route wiring (no MongoDB: fake db + fake ml_service) ────────────


class _FakeCollection:
    def __init__(self):
        self.inserted = []

    async def find_one(self, *args, **kwargs):
        return None

    async def insert_one(self, doc):
        self.inserted.append(doc)
        return types.SimpleNamespace(inserted_id=f"id{len(self.inserted)}")

    async def update_one(self, *args, **kwargs):
        return None


def _upload(monkeypatch, samples, fs, lead_off=False):
    from app.models.vitals import VitalsCreate
    from app.routes import vitals as vitals_route

    db = types.SimpleNamespace(devices=_FakeCollection(), vitals=_FakeCollection(),
                               predictions=_FakeCollection(), users=_FakeCollection())
    calls = []

    def fake_predict(**kwargs):
        calls.append(kwargs)
        return {"risk_label": "unknown"}

    fake_ml = types.ModuleType("app.services.ml_service")
    fake_ml.predict = fake_predict
    fake_ml._models_loaded = True
    fake_ml.load_models = lambda: True
    monkeypatch.setitem(sys.modules, "app.services.ml_service", fake_ml)
    monkeypatch.setattr(vitals_route, "get_db", lambda: db)

    data = VitalsCreate(device_id="ESP32_TEST", timestamp=1700000000, sample_rate_hz=fs,
                        heart_rate_bpm=72, spo2_percent=98, ecg_lead_off=lead_off,
                        ecg_samples=[int(v) for v in samples])
    response = asyncio.run(vitals_route.upload_vitals(data))
    return db.vitals.inserted[0], calls, response


def test_upload_skips_prediction_for_poor_signal(monkeypatch):
    doc, calls, response = _upload(monkeypatch, np.round(_sine(250)), 250)
    assert doc["signal_quality"] == "poor"
    assert doc["signal_quality_reason"]
    assert calls == []
    assert response.signal_quality == "poor"


def test_upload_runs_prediction_for_good_signal(monkeypatch):
    rec = next(r for r in PTBXL if r["label"] == "NORM")
    doc, calls, response = _upload(monkeypatch, rec["samples_250hz"], 250)
    assert doc["signal_quality"] == "good"
    assert len(calls) == 1
    assert response.signal_quality == "good"


def test_upload_marks_lead_off(monkeypatch):
    rec = next(r for r in PTBXL if r["label"] == "NORM")
    doc, calls, response = _upload(monkeypatch, rec["samples_250hz"], 250, lead_off=True)
    assert doc["signal_quality"] == "lead_off"
    assert calls == []
    assert response.signal_quality == "lead_off"


def test_response_tolerates_old_docs_without_quality():
    from datetime import datetime

    from app.routes.vitals import _vitals_doc_to_response

    doc = {"_id": "x", "device_id": "d", "timestamp": datetime(2026, 1, 1), "heart_rate_bpm": 70,
           "spo2_percent": 98, "ecg_lead_off": False, "created_at": datetime(2026, 1, 1)}
    assert _vitals_doc_to_response(doc).signal_quality is None
