"""One-off generator for tests/fixtures/ptbxl_lead2.json (not run by pytest).

Builds device-like 10 s lead-II windows from PTB-XL so the signal-quality
tests can run without the dataset.

Data source and attribution
---------------------------
PTB-XL, a large publicly available electrocardiography dataset (v1.0.3),
Wagner P., Strodthoff N., Bousseljot R., Samek W., Schaeffter T.,
PhysioNet, https://doi.org/10.13026/kfzx-aw45 (dataset) and
Scientific Data 7, 154 (2020), https://doi.org/10.1038/s41597-020-0495-6.
Licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/).
Changes made: lead II only, resampled to 250 Hz and 100 Hz, scaled to 12-bit
ADC counts (1 mV -> 400 counts), centred at 2048, clipped to 0..4095.

Selection (deterministic, strat_fold == 10, i.e. the PTB-XL test fold;
no filtering on the noise / artefact annotations):
  NORM : 'NORM' likelihood >= 50, no MI code
  MI   : any of IMI/AMI/ASMI/ALMI/ILMI/LMI/PMI/IPLMI with likelihood >= 50
  AFIB : 'AFIB' present (rhythm codes carry likelihood 0 in PTB-XL)
A seeded random sample of each group is taken (seed below).

Usage (from backend/):
  uv run --quiet --no-project --python 3.11 --with wfdb --with pandas \
      --with 'numpy==1.26.4' --with 'scipy==1.14.1' \
      python tests/fixtures/make_ptbxl_fixture.py \
      "../ml/data/ptb-xl" tests/fixtures/ptbxl_lead2.json
"""

import ast
import json
import os
import sys

import numpy as np
import pandas as pd
import wfdb
from scipy.signal import resample_poly

SEED = 20260224
N_PER_LABEL = {"NORM": 15, "MI": 15, "AFIB": 10}
MI_CODES = {"IMI", "AMI", "ASMI", "ALMI", "ILMI", "LMI", "PMI", "IPLMI"}
COUNTS_PER_MV = 400.0
CENTER = 2048


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


def main(ptbxl_dir: str, out_path: str):
    df = pd.read_csv(os.path.join(ptbxl_dir, "ptbxl_database.csv"))
    df = df[df.strat_fold == 10].copy()
    df["codes"] = df.scp_codes.apply(ast.literal_eval)
    df["label"] = df.codes.apply(_label)
    df.loc[df.codes.apply(lambda c: "AFIB" in c), "label"] = "AFIB"

    rng = np.random.default_rng(SEED)
    records = []
    for label, n in N_PER_LABEL.items():
        pool = df[df.label == label].sort_values("ecg_id")
        idx = np.sort(rng.choice(len(pool), size=n, replace=False))
        for _, row in pool.iloc[idx].iterrows():
            rec = wfdb.rdrecord(os.path.join(ptbxl_dir, row.filename_hr))
            assert rec.fs == 500 and rec.sig_name[1].upper() == "II"
            lead2 = np.nan_to_num(rec.p_signal[:, 1].astype(float))
            records.append({
                "ecg_id": int(row.ecg_id),
                "label": label,
                "samples_250hz": _to_adc(resample_poly(lead2, 1, 2)),
                "samples_100hz": _to_adc(resample_poly(lead2, 1, 5)),
            })

    fixture = {
        "source": "PTB-XL v1.0.3 (Wagner et al., PhysioNet, doi:10.13026/kfzx-aw45)",
        "license": "CC BY 4.0 - https://creativecommons.org/licenses/by/4.0/",
        "changes": "lead II; resampled to 250/100 Hz; 1 mV = 400 ADC counts; "
                   "centred at 2048; clipped 0..4095",
        "selection": f"strat_fold == 10, seeded sample (seed={SEED}), {N_PER_LABEL}",
        "records": records,
    }
    with open(out_path, "w") as f:
        json.dump(fixture, f, separators=(",", ":"))
    print(f"wrote {len(records)} records to {out_path} ({os.path.getsize(out_path) / 1e6:.2f} MB)")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
