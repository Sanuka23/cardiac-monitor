"""Replay a raw AD8232 recording from the ESP32 through the vitals API, window by window.

Each 10 s window is processed exactly as the firmware does (firmware_ecg.py) and sent
from a playback device (default PLAYBACK_DEVICE_REC) with a source label, so stored
data is never mistaken for a live session. HR/SpO2 are sent as 0 (no pulse sensor);
the server derives HR from the ECG.

Input: a serial capture with "D:v,v,..." lines (ECG diagnostic sketch, 250 Hz raw) or
a JSON file {"sample_rate_hz": 250, "samples": [...]}.

Usage (from backend/):
  API_KEY=... uv run --quiet --no-project --python 3.11 --with httpx \
      python scripts/replay_recording.py recording.raw --api http://localhost:7860 \
      --label "Recorded on this device · 2026-10-11 · healthy adult at rest" \
      [--start-time 2026-10-11T01:50:38+05:30] [--email demo@example.com --password ...] [--interval 10]
"""

import argparse
import json
from datetime import datetime
import os
import time
from collections import Counter

import httpx

from firmware_ecg import SAMPLE_RATE_HZ, firmware_windows

DEVICE_ID = "PLAYBACK_DEVICE_REC"
DEVICE_NAME = "Recorded session from the ESP32 (replayed)"


def load_raw(path: str) -> list:
    text = open(path, "rb").read().decode("ascii", "ignore")
    if text.lstrip().startswith("{"):
        data = json.loads(text)
        assert data.get("sample_rate_hz", SAMPLE_RATE_HZ) == SAMPLE_RATE_HZ
        return data["samples"]
    return [int(v) for line in text.replace("\r", "").splitlines() if line.startswith("D:")
            for v in line[2:].split(",") if v.isdigit()]


def register_device(client: httpx.Client, device_id: str, email: str, password: str):
    r = client.post("/api/v1/auth/login", json={"email": email, "password": password})
    r.raise_for_status()
    headers = {"Authorization": f"Bearer {r.json()['access_token']}"}
    r = client.post("/api/v1/devices/register", headers=headers,
                    json={"device_id": device_id, "name": DEVICE_NAME})
    r.raise_for_status()
    print(f"Registered {device_id} to {email}")


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("recording", help="serial capture (.raw) or JSON recording")
    p.add_argument("--api", required=True, help="API base URL")
    p.add_argument("--api-key", default=os.environ.get("API_KEY"), help="device API key (default: $API_KEY)")
    p.add_argument("--label", required=True, help="source label shown with every window")
    p.add_argument("--device-id", default=DEVICE_ID)
    p.add_argument("--email", help="account to register the playback device to")
    p.add_argument("--password")
    p.add_argument("--interval", type=float, default=0, help="seconds between windows")
    p.add_argument("--start-time", help="when the recording started (ISO 8601 with offset); windows are "
                                        "timestamped start + 10 s each instead of the time they are sent")
    args = p.parse_args()
    if not args.api_key:
        p.error("--api-key or $API_KEY is required")
    if len(args.label) > 120:
        p.error("--label must be at most 120 characters")

    start = int(datetime.fromisoformat(args.start_time).timestamp()) if args.start_time else None
    windows = firmware_windows(load_raw(args.recording))
    print(f"{len(windows)} windows of 10 s from {args.recording}")

    with httpx.Client(base_url=args.api, timeout=120) as client:
        if args.email:
            register_device(client, args.device_id, args.email, args.password)

        labels = Counter()
        print(f"{'t':>5}  {'quality':8}  {'HR':>5}  {'risk':>6}  label")
        for n, window in enumerate(windows):
            if n and args.interval:
                time.sleep(args.interval)
            r = client.post("/api/v1/vitals", headers={"X-API-Key": args.api_key}, json={
                "device_id": args.device_id,
                "timestamp": start + n * 10 if start is not None else int(time.time()),
                "window_ms": 10000,
                "sample_rate_hz": SAMPLE_RATE_HZ,
                "heart_rate_bpm": 0,
                "spo2_percent": 0,
                "ecg_lead_off": False,
                "ecg_samples": window,
                "source": args.label,
            })
            r.raise_for_status()
            body = r.json()
            pred = body.get("prediction") or {}
            label = pred.get("risk_label", "-")
            labels[label] += 1
            score = f"{pred['risk_score']:.3f}" if pred else "-"
            quality = body.get("signal_quality") or "-"
            print(f"{n * 10:>4}s  {quality:8}  {body['heart_rate_bpm']:>5}  {score:>6}  {label}")

    print(f"\nSummary: {dict(labels)}")


if __name__ == "__main__":
    main()
