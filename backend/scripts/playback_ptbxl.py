"""Play real PTB-XL ECG recordings through the vitals API as a labelled playback device.

Shows how the deployed pipeline (signal-quality gate -> ECGFounder + XGBoost) scores
real, clinically labelled ECGs, since a live wearer cannot be made to have an
abnormal ECG on demand. Every window is sent from device PLAYBACK_PTBXL so it can
never be mistaken for live sensor data.

What is sent per window (10 s, lead II, 250 Hz, 1 mV -> 400 ADC counts, centred 2048):
  heart_rate_bpm  heart rate measured from the recording's R-peaks (no pulse sensor in PTB-XL)
  spo2_percent    0 = unknown (PTB-XL has no SpO2; the model then uses its default)

Data: PTB-XL v1.0.3, Wagner et al., PhysioNet, doi:10.13026/kfzx-aw45, CC BY 4.0.
Records come from strat_fold 10 (the PTB-XL test fold, never used for training),
as a seeded random sample unless --ids is given.

Usage (from backend/):
  API_KEY=... uv run --quiet --no-project --python 3.11 --with wfdb --with pandas \
      --with httpx --with 'neurokit2>=0.2.7' --with 'numpy==1.26.4' --with 'scipy==1.14.1' \
      python scripts/playback_ptbxl.py --ptbxl ../ml/data/ptb-xl --api http://localhost:7860 \
      [--email demo@example.com --password ...] [--per-label 5] [--ids 9,41] [--interval 10]
"""

import argparse
import ast
import os
import time
from collections import Counter, defaultdict

import httpx
import neurokit2 as nk
import numpy as np
import pandas as pd
import wfdb
from scipy.signal import resample_poly

DEVICE_ID = "PLAYBACK_PTBXL"
DEVICE_NAME = "PTB-XL playback (recorded clinical ECGs)"
MI_CODES = {"IMI", "AMI", "ASMI", "ALMI", "ILMI", "LMI", "PMI", "IPLMI"}
LABEL_TEXT = {"NORM": "normal ECG", "MI": "myocardial infarction"}
COUNTS_PER_MV = 400.0
CENTER = 2048
SAMPLE_RATE_HZ = 250


def _label(codes: dict):
    if any(codes.get(c, 0) >= 50 for c in MI_CODES):
        return "MI"
    if codes.get("NORM", 0) >= 50:
        return "NORM"
    return None


def _to_adc(sig_mv: np.ndarray) -> list:
    centred = sig_mv - np.median(sig_mv)
    adc = np.clip(np.round(CENTER + COUNTS_PER_MV * centred), 0, 4095)
    return [int(v) for v in adc]


def select_records(ptbxl_dir: str, per_label: int, ids: list, seed: int) -> pd.DataFrame:
    df = pd.read_csv(os.path.join(ptbxl_dir, "ptbxl_database.csv"))
    df["label"] = df.scp_codes.apply(ast.literal_eval).apply(_label)
    if ids:
        return df[df.ecg_id.isin(ids)]
    test = df[(df.strat_fold == 10) & df.label.notna()].sort_values("ecg_id")
    rng = np.random.default_rng(seed)
    picks = []
    for label in ("NORM", "MI"):
        pool = test[test.label == label]
        picks.append(pool.iloc[np.sort(rng.choice(len(pool), size=per_label, replace=False))])
    # Alternate NORM, MI, NORM, ... so a live audience sees both kinds early
    sample = pd.concat(picks)
    sample["pos"] = sample.groupby("label").cumcount()
    return sample.sort_values(["pos", "label"], ascending=[True, False])


def build_window(ptbxl_dir: str, filename_hr: str):
    rec = wfdb.rdrecord(os.path.join(ptbxl_dir, filename_hr))
    lead2 = np.nan_to_num(rec.p_signal[:, 1].astype(float))  # 500 Hz, 10 s
    samples = _to_adc(resample_poly(lead2, SAMPLE_RATE_HZ, rec.fs))
    # Heart rate from neurokit2 R-peaks on the original 500 Hz signal; the quality
    # gate's own beat estimate over-counts on some morphologies (e.g. ecg_id 6230).
    _, info = nk.ecg_peaks(nk.ecg_clean(lead2, sampling_rate=rec.fs), sampling_rate=rec.fs)
    rr = np.diff(info["ECG_R_Peaks"]) / rec.fs
    hr = 60 / np.median(rr) if len(rr) else 0.0
    return samples, round(float(hr), 1)


def register_device(client: httpx.Client, email: str, password: str):
    r = client.post("/api/v1/auth/login", json={"email": email, "password": password})
    r.raise_for_status()
    headers = {"Authorization": f"Bearer {r.json()['access_token']}"}
    r = client.post("/api/v1/devices/register", headers=headers,
                    json={"device_id": DEVICE_ID, "name": DEVICE_NAME})
    r.raise_for_status()
    print(f"Registered {DEVICE_ID} to {email}")


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--ptbxl", required=True, help="PTB-XL dataset directory")
    p.add_argument("--api", required=True, help="API base URL, e.g. http://localhost:7860")
    p.add_argument("--api-key", default=os.environ.get("API_KEY"), help="device API key (default: $API_KEY)")
    p.add_argument("--email", help="account to register the playback device to")
    p.add_argument("--password")
    p.add_argument("--per-label", type=int, default=5, help="records per label (NORM, MI)")
    p.add_argument("--ids", default="", help="comma-separated PTB-XL ecg_ids instead of a random sample")
    p.add_argument("--seed", type=int, default=20261009)
    p.add_argument("--interval", type=float, default=0, help="seconds between windows")
    args = p.parse_args()
    if not args.api_key:
        p.error("--api-key or $API_KEY is required")

    ids = [int(i) for i in args.ids.split(",") if i.strip()]
    records = select_records(args.ptbxl, args.per_label, ids, args.seed)

    with httpx.Client(base_url=args.api, timeout=120) as client:
        if args.email:
            register_device(client, args.email, args.password)

        results = defaultdict(Counter)
        print(f"{'ecg_id':>7}  {'truth':5}  {'HR':>5}  {'quality':8}  {'risk':>6}  label")
        for n, row in enumerate(records.itertuples()):
            if n and args.interval:
                time.sleep(args.interval)
            samples, hr = build_window(args.ptbxl, row.filename_hr)
            r = client.post("/api/v1/vitals", headers={"X-API-Key": args.api_key}, json={
                "device_id": DEVICE_ID,
                "timestamp": int(time.time()),
                "window_ms": 10000,
                "sample_rate_hz": SAMPLE_RATE_HZ,
                "heart_rate_bpm": hr,
                "spo2_percent": 0,
                "ecg_lead_off": False,
                "ecg_samples": samples,
                "source": f"PTB-XL #{row.ecg_id} · label: {LABEL_TEXT.get(row.label, row.label)}",
            })
            r.raise_for_status()
            body = r.json()
            pred = body.get("prediction") or {}
            label = pred.get("risk_label", "-")
            results[row.label][label] += 1
            score = f"{pred['risk_score']:.3f}" if pred else "-"
            quality = body.get("signal_quality") or "-"
            print(f"{row.ecg_id:>7}  {row.label:5}  {hr:>5}  {quality:8}  {score:>6}  {label}")

    print("\nSummary (true label -> predicted risk labels):")
    for truth, counts in results.items():
        print(f"  {truth:5} {dict(counts)}")


if __name__ == "__main__":
    main()
