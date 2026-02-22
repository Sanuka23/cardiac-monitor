#!/usr/bin/env python3
"""
Master training script: downloads data, preprocesses, trains both models, evaluates ensemble.

Usage:
    cd ml/
    python3 train_all.py              # Full pipeline
    python3 train_all.py --skip-download  # Skip download if data exists
    python3 train_all.py --xgboost-only   # Train only XGBoost (faster)
"""

import os
import sys
import argparse
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "src"))


def main():
    parser = argparse.ArgumentParser(description="Train cardiac risk prediction models")
    parser.add_argument("--skip-download", action="store_true", help="Skip PTB-XL download")
    parser.add_argument("--xgboost-only", action="store_true", help="Train only XGBoost")
    parser.add_argument("--ecgfounder-only", action="store_true", help="Train only ECGFounder")
    parser.add_argument("--epochs", type=int, default=30, help="ECGFounder training epochs")
    parser.add_argument("--batch-size", type=int, default=64, help="Batch size for ECGFounder")
    args = parser.parse_args()

    data_dir = os.path.join(os.path.dirname(__file__), "data", "ptb-xl")
    processed_dir = os.path.join(os.path.dirname(__file__), "data", "processed")
    model_dir = os.path.join(os.path.dirname(__file__), "models")

    os.makedirs(processed_dir, exist_ok=True)
    os.makedirs(model_dir, exist_ok=True)

    total_start = time.time()

    # Step 1: Download PTB-XL
    if not args.skip_download:
        print("\n" + "=" * 60)
        print("STEP 1: Downloading PTB-XL dataset")
        print("=" * 60)
        from data_loader import download_ptbxl
        download_ptbxl(data_dir)
    else:
        print("\n[SKIP] Download (--skip-download)")

    # Step 2: Preprocess data
    data_500hz = os.path.join(processed_dir, "ptbxl_500hz.npz")
    data_100hz = os.path.join(processed_dir, "ptbxl_100hz.npz")

    if not args.xgboost_only and not os.path.exists(data_500hz):
        print("\n" + "=" * 60)
        print("STEP 2a: Preprocessing PTB-XL at 500Hz (for ECGFounder)")
        print("=" * 60)
        from data_loader import prepare_ptbxl_dataset
        import numpy as np
        ds = prepare_ptbxl_dataset(data_dir, sample_rate=500)
        np.savez_compressed(data_500hz,
                            X_train=ds["X_train"], y_train=ds["y_train"],
                            X_val=ds["X_val"], y_val=ds["y_val"],
                            X_test=ds["X_test"], y_test=ds["y_test"])
        print(f"Saved to {data_500hz}")
    else:
        print(f"\n[SKIP] 500Hz preprocessing ({'xgboost-only' if args.xgboost_only else 'already exists'})")

    if not args.ecgfounder_only and not os.path.exists(data_100hz):
        print("\n" + "=" * 60)
        print("STEP 2b: Preprocessing PTB-XL at 100Hz (for XGBoost)")
        print("=" * 60)
        from data_loader import prepare_ptbxl_dataset
        import numpy as np
        ds = prepare_ptbxl_dataset(data_dir, sample_rate=100)
        np.savez_compressed(data_100hz,
                            X_train=ds["X_train"], y_train=ds["y_train"],
                            X_val=ds["X_val"], y_val=ds["y_val"],
                            X_test=ds["X_test"], y_test=ds["y_test"])
        print(f"Saved to {data_100hz}")
    else:
        print(f"\n[SKIP] 100Hz preprocessing ({'ecgfounder-only' if args.ecgfounder_only else 'already exists'})")

    # Step 3: Train ECGFounder
    if not args.xgboost_only:
        print("\n" + "=" * 60)
        print("STEP 3: Fine-tuning ECGFounder")
        print("=" * 60)
        from finetune_ecgfounder import finetune
        ecg_auc = finetune(
            data_path=data_500hz,
            output_dir=model_dir,
            epochs=args.epochs,
            batch_size=args.batch_size,
        )
    else:
        print("\n[SKIP] ECGFounder training (--xgboost-only)")

    # Step 4: Train XGBoost
    if not args.ecgfounder_only:
        print("\n" + "=" * 60)
        print("STEP 4: Training XGBoost")
        print("=" * 60)
        from train_xgboost import train_xgboost
        xgb_auc = train_xgboost(
            data_path=data_100hz,
            output_dir=model_dir,
        )
    else:
        print("\n[SKIP] XGBoost training (--ecgfounder-only)")

    # Step 5: Evaluate ensemble
    ecg_preds_path = os.path.join(model_dir, "ecgfounder_test_preds.npz")
    xgb_preds_path = os.path.join(model_dir, "xgboost_test_preds.npz")

    if os.path.exists(ecg_preds_path) and os.path.exists(xgb_preds_path):
        print("\n" + "=" * 60)
        print("STEP 5: Evaluating Ensemble")
        print("=" * 60)
        from evaluate import evaluate_ensemble
        results = evaluate_ensemble(ecg_preds_path, xgb_preds_path, output_dir=model_dir)
    else:
        print("\n[SKIP] Ensemble evaluation (need both model predictions)")

    total_time = time.time() - total_start
    print("\n" + "=" * 60)
    print(f"DONE! Total time: {total_time / 60:.1f} minutes")
    print("=" * 60)
    print(f"\nModel files in {model_dir}/:")
    for f in sorted(os.listdir(model_dir)):
        if not f.startswith("."):
            size = os.path.getsize(os.path.join(model_dir, f))
            print(f"  {f:40s} {size / 1024 / 1024:.1f} MB")


if __name__ == "__main__":
    main()
