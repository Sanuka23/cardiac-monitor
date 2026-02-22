"""
PTB-XL dataset loader for ECG classification.
Downloads and preprocesses PTB-XL for both ECGFounder and XGBoost training.
"""

import os
import ast
import numpy as np
import pandas as pd
import wfdb
from scipy.signal import resample
from tqdm import tqdm


# PTB-XL SCP code to superclass mapping
SCP_SUPERCLASS = {
    "NORM": "NORM",
    "IMI": "MI", "AMI": "MI", "ALMI": "MI", "ILMI": "MI",
    "ASMI": "MI", "INJAL": "MI", "INJAS": "MI", "INJIL": "MI",
    "INJIN": "MI", "INJLA": "MI", "LMI": "MI", "PMI": "MI",
    "IPLMI": "MI",
    "STTC": "STTC", "NST_": "STTC", "ISC_": "STTC", "ISCA": "STTC",
    "ISCAL": "STTC", "ISCI": "STTC", "ISCIL": "STTC", "ISCIN": "STTC",
    "ISCLA": "STTC", "DIG": "STTC", "LNGQT": "STTC", "APTS": "STTC",
    "NDT": "STTC", "STD_": "STTC", "STE_": "STTC",
    "IVCD": "CD", "LAFB": "CD", "LPFB": "CD", "IRBBB": "CD",
    "CRBBB": "CD", "CLBBB": "CD", "1AVB": "CD", "2AVB": "CD",
    "3AVB": "CD", "WPW": "CD",
    "LVH": "HYP", "RVH": "HYP", "LAO/LAE": "HYP", "RAO/RAE": "HYP",
    "SEHYP": "HYP",
}


def download_ptbxl(data_dir: str):
    """Download PTB-XL from PhysioNet using wfdb."""
    if os.path.exists(os.path.join(data_dir, "ptbxl_database.csv")):
        print("[DATA] PTB-XL already downloaded.")
        return

    print("[DATA] Downloading PTB-XL from PhysioNet...")
    os.makedirs(data_dir, exist_ok=True)
    wfdb.dl_database("ptb-xl", dl_dir=data_dir)
    print("[DATA] Download complete.")


def load_ptbxl_metadata(data_dir: str) -> pd.DataFrame:
    """Load and parse PTB-XL metadata."""
    csv_path = os.path.join(data_dir, "ptbxl_database.csv")
    df = pd.read_csv(csv_path, index_col="ecg_id")
    df.scp_codes = df.scp_codes.apply(ast.literal_eval)
    return df


def get_superclass_label(scp_codes: dict) -> str:
    """Map SCP codes to superclass. Returns dominant superclass."""
    superclasses = {}
    for code, likelihood in scp_codes.items():
        if likelihood >= 50 and code in SCP_SUPERCLASS:
            sc = SCP_SUPERCLASS[code]
            superclasses[sc] = superclasses.get(sc, 0) + likelihood
    if not superclasses:
        return "OTHER"
    return max(superclasses, key=superclasses.get)


def get_binary_label(scp_codes: dict) -> int:
    """0 = Normal, 1 = Abnormal."""
    sc = get_superclass_label(scp_codes)
    return 0 if sc == "NORM" else 1


def load_ecg_signal(data_dir: str, filename: str, target_length: int = 5000) -> np.ndarray:
    """
    Load a single ECG record and extract Lead II.

    Returns:
        numpy array of shape (1, target_length) — single-lead, preprocessed.
    """
    record_path = os.path.join(data_dir, filename)
    record = wfdb.rdrecord(record_path)
    signal = record.p_signal  # (n_samples, n_leads)
    fs = record.fs

    # Extract Lead II (index 1 in standard 12-lead order)
    lead_ii = signal[:, 1]

    # Resample to target_length if needed
    if len(lead_ii) != target_length:
        lead_ii = resample(lead_ii, target_length)

    # Z-score normalization (required for ECGFounder)
    mean = np.mean(lead_ii)
    std = np.std(lead_ii) + 1e-8
    lead_ii = (lead_ii - mean) / std

    # Handle NaN
    lead_ii = np.nan_to_num(lead_ii, nan=0.0)

    return lead_ii.reshape(1, -1).astype(np.float32)  # (1, target_length)


def prepare_ptbxl_dataset(data_dir: str, sample_rate: int = 500):
    """
    Prepare PTB-XL dataset for training.

    Args:
        data_dir: Path to PTB-XL data directory
        sample_rate: 100 or 500

    Returns:
        dict with keys: X_train, y_train, X_val, y_val, X_test, y_test,
                        meta_train, meta_val, meta_test
    """
    df = load_ptbxl_metadata(data_dir)

    # Add labels
    df["superclass"] = df.scp_codes.apply(get_superclass_label)
    df["binary_label"] = df.scp_codes.apply(get_binary_label)

    # Filter out "OTHER" (records with no clear diagnosis)
    df = df[df.superclass != "OTHER"]

    # PTB-XL standard splits (folds 1-8: train, 9: val, 10: test)
    train_df = df[df.strat_fold <= 8]
    val_df = df[df.strat_fold == 9]
    test_df = df[df.strat_fold == 10]

    # Choose record path based on sample rate
    record_col = f"filename_hr" if sample_rate == 500 else "filename_lr"
    target_length = sample_rate * 10  # 10 seconds

    print(f"[DATA] Loading ECG signals at {sample_rate}Hz...")
    print(f"  Train: {len(train_df)}, Val: {len(val_df)}, Test: {len(test_df)}")

    datasets = {}
    for split_name, split_df in [("train", train_df), ("val", val_df), ("test", test_df)]:
        signals = []
        labels = []
        meta = []
        for _, row in tqdm(split_df.iterrows(), total=len(split_df), desc=f"Loading {split_name}"):
            try:
                sig = load_ecg_signal(data_dir, row[record_col], target_length)
                signals.append(sig)
                labels.append(row["binary_label"])
                meta.append({
                    "age": row.get("age", None),
                    "sex": 1 if row.get("sex", 0) == 1 else 0,  # 1=male, 0=female
                    "superclass": row["superclass"],
                })
            except Exception as e:
                print(f"  Skipping {row[record_col]}: {e}")
                continue

        datasets[f"X_{split_name}"] = np.array(signals)  # (N, 1, length)
        datasets[f"y_{split_name}"] = np.array(labels)
        datasets[f"meta_{split_name}"] = meta

    # Print class distribution
    for split in ["train", "val", "test"]:
        y = datasets[f"y_{split}"]
        n_normal = (y == 0).sum()
        n_abnormal = (y == 1).sum()
        print(f"  {split}: {len(y)} total, {n_normal} normal, {n_abnormal} abnormal "
              f"({n_abnormal / len(y) * 100:.1f}% abnormal)")

    return datasets


if __name__ == "__main__":
    import sys
    data_dir = sys.argv[1] if len(sys.argv) > 1 else "data/ptb-xl"

    print("Downloading PTB-XL...")
    download_ptbxl(data_dir)

    print("\nPreparing 500Hz dataset (for ECGFounder)...")
    ds_500 = prepare_ptbxl_dataset(data_dir, sample_rate=500)

    # Save preprocessed data
    os.makedirs("data/processed", exist_ok=True)
    np.savez_compressed("data/processed/ptbxl_500hz.npz",
                        X_train=ds_500["X_train"], y_train=ds_500["y_train"],
                        X_val=ds_500["X_val"], y_val=ds_500["y_val"],
                        X_test=ds_500["X_test"], y_test=ds_500["y_test"])
    print("\nSaved to data/processed/ptbxl_500hz.npz")

    print("\nPreparing 100Hz dataset (for XGBoost features)...")
    ds_100 = prepare_ptbxl_dataset(data_dir, sample_rate=100)
    np.savez_compressed("data/processed/ptbxl_100hz.npz",
                        X_train=ds_100["X_train"], y_train=ds_100["y_train"],
                        X_val=ds_100["X_val"], y_val=ds_100["y_val"],
                        X_test=ds_100["X_test"], y_test=ds_100["y_test"])
    print("Saved to data/processed/ptbxl_100hz.npz")
