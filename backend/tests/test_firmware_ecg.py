import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

from firmware_ecg import WINDOW_SAMPLES, firmware_windows  # noqa: E402


def test_splits_into_full_ten_second_windows():
    windows = firmware_windows([1800] * (WINDOW_SAMPLES * 3 + 100))
    assert len(windows) == 3
    assert all(len(w) == WINDOW_SAMPLES for w in windows)


def test_constant_input_settles_to_the_2048_centre():
    window = firmware_windows([1800] * WINDOW_SAMPLES)[0]
    assert abs(window[-1] - 2048) <= 1
    assert all(0 <= v <= 4095 for v in window)


def test_scaling_keeps_clipped_device_peaks_off_the_rails():
    # Raw device-like window: baseline 1774 with R-peaks clipped at the ADC limit
    raw = [1774] * WINDOW_SAMPLES
    for beat in range(100, WINDOW_SAMPLES, 210):
        raw[beat - 2:beat + 3] = [2600, 3600, 4095, 3600, 2600]
    scaled = firmware_windows(raw)[0]
    unscaled = firmware_windows(raw, scale=1.0)[0]
    assert max(scaled) < 4093
    assert max(unscaled) >= 4093


def test_matches_values_in_device_garbage_fixture_range():
    # The firmware output is 12-bit, so it must be a valid VitalsCreate payload
    path = os.path.join(os.path.dirname(__file__), "fixtures", "device_garbage.json")
    raw = json.load(open(path))
    windows = raw["windows"] if isinstance(raw, dict) else raw
    samples = [v for w in windows for v in w["ecg_samples"]]
    out = firmware_windows(samples)
    assert out and all(0 <= v <= 4095 for w in out for v in w)
