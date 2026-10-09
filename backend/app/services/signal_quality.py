"""
ECG signal-quality gate for single-lead (AD8232) windows.

Decides whether a ~10 s window plausibly contains a human ECG before it is
scored by the risk model. The AD8232 lead-off pins do not reliably detect
missing electrodes, so without this gate the model scores sine waves, mains
noise, flat lines and electrode-pop transients as "high risk".

Every rule is simple and explainable, and the first failing rule becomes the
reason. Thresholds were set on PTB-XL lead II converted to device-like 12-bit
ADC counts (1 mV ~ 400 counts) at 250 Hz and 100 Hz (all 2,198 records of
test fold 10), on synthetic noise, and on windows our ESP32s uploaded with no
electrodes attached (see tests/test_signal_quality.py). The figures quoted
below are from that data.
"""

import numpy as np
from scipy.signal import butter, find_peaks, sosfiltfilt

ADC_MAX = 4095
MIN_DURATION_S = 4.0

# 1. Saturation: share of samples sitting on the ADC rails (0 / 4095).
#    Real ECG in range never touches them; rail-to-rail mains noise does.
RAIL_MARGIN = 2
MAX_RAIL_FRACTION = 0.01
# 2. Stuck signal: longest run of identical consecutive samples
#    (PTB-XL <= 0.37 s).
MAX_FLAT_RUN_S = 1.0
# 3. Amplitude: 1st-99th percentile range of the 0.5-40 Hz signal, in counts
#    (~0.1 mV at 400 counts/mV; PTB-XL lead II >= ~60).
MIN_AMPLITUDE = 40.0
# 4. Out-of-band noise: power above 40 Hz relative to power in 0.5-40 Hz.
#    Mains, aliased mains at 100 Hz and white noise are >= 1; PTB-XL <= 0.41.
MAX_HF_RATIO = 0.5
# 5. QRS content: power in 5-40 Hz relative to 0.5-40 Hz. A sinusoid or
#    slow drift has ~0; PTB-XL lead II >= 0.059 (99% >= 0.17).
MIN_QRS_BAND_FRACTION = 0.03
# 6. One dominant transient (electrode pop, step + exponential decay): the
#    largest QRS-band energy burst vs the typical beat, as an amplitude ratio.
#    Pops measure 20-45; PTB-XL <= 8 (large ectopic beats).
MAX_TRANSIENT_RATIO = 10.0
# 7. Beats and heart rate.
MIN_BEATS = 4
MIN_HR_BPM = 30.0
MAX_HR_BPM = 200.0
# 8. Beats must stand out from the background: median QRS-band energy at the
#    beats vs the median energy between beats. Random noise gives ~2-5;
#    99% of PTB-XL windows are >= 5.
MIN_PEAK_RATIO = 5.0
# 9. A QRS goes up and comes back (or down and back) within ~80 ms; a step or
#    sawtooth edge only moves one way. Steps ~0.03-0.09; PTB-XL >= 0.30.
MIN_SLOPE_SYMMETRY = 0.25
# 10. Beats should look alike: median correlation of each beat with the
#     median beat. Random noise ~0.4; 99% of PTB-XL >= 0.6.
MIN_TEMPLATE_CORR = 0.5
# 11. RR irregularity (coefficient of variation). Deliberately lenient so
#     atrial fibrillation and ectopy pass (PTB-XL AF <= 0.58).
MAX_RR_CV = 0.8

# Beat detector (Pan-Tompkins-like energy envelope of the 5-15 Hz band).
_QRS_BAND = (5.0, 15.0)
_ENVELOPE_WINDOW_S = 0.15
_REFRACTORY_S = 0.25
# A beat is an envelope peak >= 30% of the "typical" beat energy, taken as
# the 4th-largest peak so up to three PVCs or artefacts cannot inflate it.
_PEAK_THRESHOLD = 0.3
_REFERENCE_RANK = 4
_QRS_EXCLUDE_S = 0.1
_BEAT_HALF_WIDTH_S = 0.12
_ALIGN_LAG_S = 0.03
_SLOPE_SMOOTH_S = 0.03
_SLOPE_WINDOW_S = 0.08


def _bandpass(x, fs, lo, hi):
    sos = butter(2, [lo, min(hi, 0.45 * fs)], btype="bandpass", fs=fs, output="sos")
    return sosfiltfilt(sos, x)


def _longest_flat_run(x):
    change = np.flatnonzero(np.diff(x) != 0)
    edges = np.concatenate(([-1], change, [x.size - 1]))
    return int(np.max(np.diff(edges)))


def _band_power(x, fs):
    spec = np.abs(np.fft.rfft(x - x.mean())) ** 2
    f = np.fft.rfftfreq(x.size, 1.0 / fs)
    ecg_band = spec[(f >= 0.5) & (f < 40)].sum() + 1e-12
    hf_ratio = spec[f >= 40].sum() / ecg_band
    qrs_fraction = spec[(f >= 5) & (f < 40)].sum() / ecg_band
    return float(hf_ratio), float(qrs_fraction)


def _detect_beats(x, fs):
    """Return (beat indices, energy envelope, typical beat energy, largest burst)."""
    q = _bandpass(x, fs, *_QRS_BAND)
    w = max(1, int(round(_ENVELOPE_WINDOW_S * fs)))
    env = np.convolve(np.gradient(q) ** 2, np.ones(w) / w, mode="same")
    cand, props = find_peaks(env, height=0, distance=max(1, int(round(_REFRACTORY_S * fs))))
    heights = np.sort(props["peak_heights"])[::-1]
    if heights.size == 0 or heights[0] <= 0:
        return cand[:0], env, 0.0, 0.0
    typical = float(heights[min(_REFERENCE_RANK, heights.size) - 1])
    beats = cand[props["peak_heights"] >= _PEAK_THRESHOLD * typical]
    return beats, env, typical, float(heights[0])


def _peak_ratio(env, beats, fs):
    between = np.ones(env.size, dtype=bool)
    ex = int(round(_QRS_EXCLUDE_S * fs))
    for b in beats:
        between[max(0, b - ex):b + ex + 1] = False
    background = np.median(env[between]) if between.any() else np.median(env)
    return float(np.median(env[beats]) / (background + 1e-12))


def _slope_symmetry(x, beats, fs):
    # Boxcar smoothing keeps a step monotonic (no filter ringing).
    k = max(1, int(round(_SLOPE_SMOOTH_S * fs)))
    d = np.diff(np.convolve(x, np.ones(k) / k, mode="same"))
    win = max(1, int(round(_SLOPE_WINDOW_S * fs)))
    ok = beats[(beats - win >= k) & (beats + win < d.size - k)]
    if ok.size == 0:
        return None
    seg = d[ok[:, None] + np.arange(-win, win)[None, :]]
    up, down = seg.max(axis=1), -seg.min(axis=1)
    sym = np.minimum(up, down) / np.maximum(np.maximum(up, down), 1e-9)
    return float(max(np.median(sym), 0.0))


def _template_correlation(y, beats, fs):
    half = int(round(_BEAT_HALF_WIDTH_S * fs))
    lag = max(1, int(round(_ALIGN_LAG_S * fs)))
    ok = beats[(beats - half - lag >= 0) & (beats + half + lag < y.size)]
    if ok.size < 2:
        return None
    segs = y[ok[:, None] + np.arange(-half - lag, half + lag + 1)[None, :]]
    width = 2 * half + 1
    tmpl = np.median(segs[:, lag:lag + width], axis=0)
    tmpl = (tmpl - tmpl.mean()) / (tmpl.std() + 1e-9)
    best = np.full(ok.size, -1.0)
    for shift in range(2 * lag + 1):  # tolerate +-30 ms misalignment
        c = segs[:, shift:shift + width]
        c = (c - c.mean(axis=1, keepdims=True)) / (c.std(axis=1, keepdims=True) + 1e-9)
        best = np.maximum(best, c @ tmpl / width)
    return float(np.median(best))


def _result(quality, reason, metrics, hr_bpm=None):
    rounded = {k: (round(v, 4) if isinstance(v, float) else v) for k, v in metrics.items()}
    return {"quality": quality, "reason": reason, "hr_bpm": hr_bpm, "metrics": rounded}


def assess_ecg_quality(samples, sample_rate_hz) -> dict:
    """Classify one ECG window as "good" or "poor".

    Args:
        samples: ECG samples as 12-bit ADC counts (list or numpy array).
        sample_rate_hz: sampling rate (100 Hz old firmware, 250 Hz new).

    Returns:
        {"quality": "good" | "poor", "reason": str, "hr_bpm": float | None,
         "metrics": dict}. reason is "ok" for good windows, otherwise the
        name of the first failing rule. hr_bpm (median-RR heart rate) is
        only reported for good windows. Runs in ~1 ms per 10 s window.
    """
    x = np.asarray(samples, dtype=float).ravel()
    fs = float(sample_rate_hz or 0)
    m = {"duration_s": x.size / fs if fs > 0 else 0.0}

    if fs <= 0 or m["duration_s"] < MIN_DURATION_S:
        return _result("poor", "too_short", m)
    if not np.all(np.isfinite(x)):
        return _result("poor", "invalid_samples", m)

    m["rail_fraction"] = float(np.mean((x <= RAIL_MARGIN) | (x >= ADC_MAX - RAIL_MARGIN)))
    if m["rail_fraction"] > MAX_RAIL_FRACTION:
        return _result("poor", "saturated", m)

    m["flat_run_s"] = _longest_flat_run(x) / fs
    if m["flat_run_s"] > MAX_FLAT_RUN_S:
        return _result("poor", "flat_segment", m)

    x = x - np.median(x)  # old firmware sends raw, un-centred ADC values
    y = _bandpass(x, fs, 0.5, 40.0)
    m["amplitude"] = float(np.percentile(y, 99) - np.percentile(y, 1))
    if m["amplitude"] < MIN_AMPLITUDE:
        return _result("poor", "low_amplitude", m)

    m["hf_ratio"], m["qrs_band_fraction"] = _band_power(x, fs)
    if m["hf_ratio"] > MAX_HF_RATIO:
        return _result("poor", "high_frequency_noise", m)
    if m["qrs_band_fraction"] < MIN_QRS_BAND_FRACTION:
        return _result("poor", "no_qrs_content", m)

    beats, env, typical, largest = _detect_beats(x, fs)
    m["beats"] = int(beats.size)
    m["transient_ratio"] = float(np.sqrt(largest / typical)) if typical > 0 else 0.0
    if m["transient_ratio"] > MAX_TRANSIENT_RATIO:
        return _result("poor", "transient_artifact", m)
    if beats.size < MIN_BEATS:
        return _result("poor", "too_few_beats", m)

    rr = np.diff(beats) / fs
    m["hr_bpm"] = float(60.0 / np.median(rr))
    if not MIN_HR_BPM <= m["hr_bpm"] <= MAX_HR_BPM:
        return _result("poor", "hr_out_of_range", m)

    m["peak_ratio"] = _peak_ratio(env, beats, fs)
    if m["peak_ratio"] < MIN_PEAK_RATIO:
        return _result("poor", "no_distinct_qrs", m)

    m["slope_symmetry"] = _slope_symmetry(x, beats, fs)
    if m["slope_symmetry"] is not None and m["slope_symmetry"] < MIN_SLOPE_SYMMETRY:
        return _result("poor", "step_artifact", m)

    m["template_corr"] = _template_correlation(y, beats, fs)
    if m["template_corr"] is not None and m["template_corr"] < MIN_TEMPLATE_CORR:
        return _result("poor", "inconsistent_beats", m)

    m["rr_cv"] = float(np.std(rr) / np.mean(rr))
    if m["rr_cv"] > MAX_RR_CV:
        return _result("poor", "irregular_rr", m)

    return _result("good", "ok", m, hr_bpm=round(m["hr_bpm"], 1))
