"""Summarise an ecg_diag capture: lead-off status, ADC stats, server quality-gate verdict, and a plot.

Usage (from the repo root):
  uv run --no-project --python 3.11 --with numpy --with 'scipy==1.14.1' --with matplotlib \
      python firmware/tools/ecg_analyze.py capture.raw capture.png

The quality verdict uses backend/app/services/signal_quality.py on the last 10 s of the
unfiltered capture (the real firmware also filters and scales before uploading).
"""
import os
import re
import sys

import matplotlib
import numpy as np

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "backend"))
from app.services.signal_quality import assess_ecg_quality  # noqa: E402

FS = 250
raw_path, png_path = sys.argv[1], sys.argv[2]
text = open(raw_path, "rb").read().decode("ascii", "ignore").replace("\r", "")
lines = text.splitlines()
samples = [int(v) for line in lines if line.startswith("D:") for v in line[2:].split(",") if v.isdigit()]
reports = [line for line in lines if line.startswith("[ECG]")]
print(f"{len(samples)} samples ({len(samples) / FS:.1f} s) | {len(reports)} status lines")
for r in reports[-3:]:
    print("  ", re.sub(r"\s+n=\d+$", "", r))

x = np.array(samples, float)
if len(x):
    rails = np.mean((x <= 2) | (x >= 4093)) * 100
    print(f"ADC: mean={x.mean():.0f} median={np.median(x):.0f} std={x.std():.0f} at-rails={rails:.1f}%")
    window = x[-2500:] if len(x) >= 2500 else x
    q = assess_ecg_quality(window.astype(int).tolist(), FS)
    print(f"quality gate on last {len(window) / FS:.0f} s: {q['quality']} ({q['reason']})")
    t = np.arange(len(x)) / FS
    fig, ax = plt.subplots(2, 1, figsize=(14, 6))
    ax[0].plot(t, x, lw=0.5)
    ax[0].set_title("AD8232 raw output (GPIO34, 250 Hz, 4x oversampled)")
    zoom = slice(max(0, len(x) - 750), len(x))
    ax[1].plot(t[zoom], x[zoom], lw=0.8)
    ax[1].set_title("last 3 s")
    ax[1].set_xlabel("s")
    fig.tight_layout()
    fig.savefig(png_path, dpi=75)
    print("plot:", png_path)
