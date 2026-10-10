"""Python port of the ESP32 ECG processing (firmware/src/ecg_filter.h + sensor_manager.cpp).

Turns raw 250 Hz AD8232 ADC samples into the exact 10 s windows the firmware uploads:
50 Hz notch -> 40 Hz low-pass -> DC removal, scaled by ECG_OUTPUT_SCALE, re-centred
at 2048 and clamped to 12 bits, with filter state reset at every window boundary.
Keep in sync with firmware/include/config.h.
"""

SAMPLE_RATE_HZ = 250
WINDOW_SAMPLES = 2500
ECG_OUTPUT_SCALE = 0.5


class _Notch50:
    b0, b1, b2, a1, a2 = 0.981334, -0.606498, 0.981334, -0.606498, 0.962668

    def __init__(self):
        self.x1 = self.x2 = self.y1 = self.y2 = 0.0

    def step(self, x):
        y = self.b0 * x + self.b1 * self.x1 + self.b2 * self.x2 - self.a1 * self.y1 - self.a2 * self.y2
        self.x2, self.x1, self.y2, self.y1 = self.x1, x, self.y1, y
        return y


class _LowPass40:
    b0, b1, b2, a1, a2 = 0.145310, 0.290620, 0.145310, -0.670919, 0.252160

    def __init__(self):
        self.z1 = self.z2 = 0.0

    def step(self, x):
        y = self.b0 * x + self.z1
        self.z1 = self.b1 * x - self.a1 * y + self.z2
        self.z2 = self.b2 * x - self.a2 * y
        return y


class _DcRemover:
    def __init__(self, alpha=0.9875):
        self.alpha, self.w = alpha, 0.0

    def step(self, x):
        old = self.w
        self.w = x + self.alpha * self.w
        return self.w - old


def firmware_windows(raw, scale=ECG_OUTPUT_SCALE, reset_each_window=True):
    """Split raw ADC samples into firmware-processed 10 s windows (lists of ints)."""
    chain = [_Notch50(), _LowPass40(), _DcRemover()]
    windows = []
    for start in range(0, len(raw) - WINDOW_SAMPLES + 1, WINDOW_SAMPLES):
        if reset_each_window:
            chain = [_Notch50(), _LowPass40(), _DcRemover()]
        window = []
        for v in raw[start:start + WINDOW_SAMPLES]:
            for f in chain:
                v = f.step(v)
            window.append(int(min(4095, max(0, round(v * scale + 2048)))))
        windows.append(window)
    return windows
