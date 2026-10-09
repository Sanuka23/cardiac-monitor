"""One-off generator for tests/fixtures/device_garbage.json (not run by pytest).

Reads (read-only, find() only) a hand-picked set of ECG windows that our
ESP32 (device ESP32_21E5F0) uploaded with ecg_lead_off == False although no
electrodes were attached. All 57 such windows in the `vitals` collection were
inspected visually; these 8 cover the failure shapes seen: rail-to-rail
saturation, aliased mains, single-sample dropouts on a noisy baseline, and a
step followed by exponential decay. Only ecg_samples and sample_rate_hz are
written. The MongoDB URI comes from backend/.env via app.config.settings and
is never printed.

Usage (from backend/):
  uv run --quiet --no-project --python 3.11 --with 'pymongo>=4.9,<4.10' \
      --with certifi --with 'pydantic-settings>=2.7' \
      python tests/fixtures/fetch_device_garbage.py tests/fixtures/device_garbage.json
"""

import json
import os
import sys
from datetime import datetime

import certifi
from pymongo import MongoClient

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from app.config import settings  # noqa: E402

DEVICE_ID = "ESP32_21E5F0"
# created_at of the selected windows (UTC) -> what they look like
SELECTED = {
    datetime(2026, 2, 23, 14, 52, 43, 413000): "chaotic rail-to-rail saturation",
    datetime(2026, 2, 23, 17, 13, 19, 345000): "~1800 baseline with noise bursts",
    datetime(2026, 2, 23, 17, 13, 29, 811000): "noise bursts plus a step artefact",
    datetime(2026, 2, 23, 17, 14, 41, 484000): "dense near-Nyquist oscillation (aliased mains)",
    datetime(2026, 2, 23, 17, 15, 24, 490000): "noisy baseline with single-sample dropouts to 0",
    datetime(2026, 2, 24, 6, 28, 43, 690000): "alternating 0 / 4095 saturation",
    datetime(2026, 2, 27, 12, 2, 55, 870000): "step then exponential decay to a flat line",
    datetime(2026, 2, 27, 12, 3, 21, 679000): "slow decay with growing high-frequency oscillation",
}


def main(out_path: str):
    client = MongoClient(settings.MONGODB_URI, tlsCAFile=certifi.where(), serverSelectionTimeoutMS=15000)
    try:
        vitals = client[settings.DATABASE_NAME].vitals
        query = {
            "ecg_lead_off": False,
            "ecg_samples.99": {"$exists": True},
            "device_id": DEVICE_ID,
            "created_at": {"$in": list(SELECTED)},
        }
        projection = {"_id": 0, "ecg_samples": 1, "sample_rate_hz": 1, "created_at": 1}
        docs = list(vitals.find(query, projection).sort("created_at", 1).limit(8))
    finally:
        client.close()

    windows = [{"ecg_samples": [int(v) for v in d["ecg_samples"]],
                "sample_rate_hz": int(d.get("sample_rate_hz") or 100)} for d in docs]
    fixture = {
        "description": "ECG windows uploaded by an ESP32 + AD8232 with no electrodes attached "
                       "(lead-off pins did not fire). None contains an ECG.",
        "shapes": [SELECTED[d["created_at"]] for d in docs],
        "windows": windows,
    }
    with open(out_path, "w") as f:
        json.dump(fixture, f, separators=(",", ":"))
    print(f"wrote {len(windows)} windows to {out_path}")


if __name__ == "__main__":
    main(sys.argv[1])
