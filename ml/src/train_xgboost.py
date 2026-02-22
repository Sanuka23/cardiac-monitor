"""
Train XGBoost model on engineered ECG features for cardiac risk prediction.
Uses 26 ECG features + optional profile/history features.
"""

import os
import sys
import numpy as np
import pandas as pd
from tqdm import tqdm
from sklearn.metrics import (
    roc_auc_score, f1_score, accuracy_score,
    classification_report, confusion_matrix
)
import xgboost as xgb
import joblib

sys.path.insert(0, os.path.dirname(__file__))
from feature_extractor import extract_ecg_features, FEATURE_NAMES, features_to_array


def extract_features_from_dataset(X: np.ndarray, y: np.ndarray,
                                  sample_rate: int = 100,
                                  meta: list = None) -> tuple:
    """
    Extract features from all ECG signals in dataset.

    Args:
        X: (N, 1, length) ECG signals
        y: (N,) labels
        sample_rate: Hz
        meta: list of dicts with age, sex etc.

    Returns:
        features_array: (N, n_features) numpy array
        valid_labels: (N,) labels for successfully processed signals
    """
    all_features = []
    valid_labels = []

    for i in tqdm(range(len(X)), desc="Extracting features"):
        ecg = X[i].flatten()
        feats = extract_ecg_features(ecg, sample_rate=sample_rate)

        # Add metadata features if available
        if meta and i < len(meta):
            m = meta[i]
            feats["age"] = float(m.get("age", 50)) if m.get("age") else 50.0
            feats["sex"] = float(m.get("sex", 0))

        feat_array = features_to_array(feats, include_profile=False)

        # Skip if all features are default/fallback
        if not np.all(feat_array == 0):
            all_features.append(feat_array)
            valid_labels.append(y[i])

    return np.array(all_features), np.array(valid_labels)


def train_xgboost(data_path: str = None, output_dir: str = "models",
                  n_estimators: int = 500, max_depth: int = 6,
                  learning_rate: float = 0.05):
    """
    Train XGBoost on ECG features from PTB-XL 100Hz data.
    """
    # Load data
    if data_path is None:
        data_path = os.path.join(os.path.dirname(__file__), "..", "data", "processed", "ptbxl_100hz.npz")
    data = np.load(data_path)
    X_train, y_train = data["X_train"], data["y_train"]
    X_val, y_val = data["X_val"], data["y_val"]
    X_test, y_test = data["X_test"], data["y_test"]

    print(f"[DATA] Train: {len(y_train)}, Val: {len(y_val)}, Test: {len(y_test)}")

    # Extract features
    print("\n[FEATURES] Extracting training features...")
    X_train_feat, y_train_valid = extract_features_from_dataset(X_train, y_train, sample_rate=100)
    print(f"  Train features: {X_train_feat.shape}")

    print("[FEATURES] Extracting validation features...")
    X_val_feat, y_val_valid = extract_features_from_dataset(X_val, y_val, sample_rate=100)
    print(f"  Val features: {X_val_feat.shape}")

    print("[FEATURES] Extracting test features...")
    X_test_feat, y_test_valid = extract_features_from_dataset(X_test, y_test, sample_rate=100)
    print(f"  Test features: {X_test_feat.shape}")

    # Handle class imbalance
    n_pos = (y_train_valid == 1).sum()
    n_neg = (y_train_valid == 0).sum()
    scale_pos_weight = n_neg / max(n_pos, 1)
    print(f"\n[DATA] Class balance: {n_neg} normal, {n_pos} abnormal, weight={scale_pos_weight:.2f}")

    # Train XGBoost
    print(f"\n[TRAIN] Training XGBoost (n_estimators={n_estimators}, max_depth={max_depth})...")
    model = xgb.XGBClassifier(
        n_estimators=n_estimators,
        max_depth=max_depth,
        learning_rate=learning_rate,
        scale_pos_weight=scale_pos_weight,
        objective="binary:logistic",
        eval_metric="auc",
        tree_method="hist",
        random_state=42,
        use_label_encoder=False,
        early_stopping_rounds=30,
    )

    model.fit(
        X_train_feat, y_train_valid,
        eval_set=[(X_val_feat, y_val_valid)],
        verbose=True,
    )

    # Evaluate on test set
    print("\n[TEST] Evaluating on test set...")
    test_probs = model.predict_proba(X_test_feat)[:, 1]
    test_preds = (test_probs > 0.5).astype(int)

    test_auc = roc_auc_score(y_test_valid, test_probs)
    test_f1 = f1_score(y_test_valid, test_preds)
    test_acc = accuracy_score(y_test_valid, test_preds)

    print(f"  Test AUC:  {test_auc:.4f}")
    print(f"  Test F1:   {test_f1:.4f}")
    print(f"  Test Acc:  {test_acc:.4f}")
    print(f"\n  Classification Report:")
    print(classification_report(y_test_valid, test_preds, target_names=["Normal", "Abnormal"]))
    print(f"  Confusion Matrix:")
    print(confusion_matrix(y_test_valid, test_preds))

    # Feature importance
    print("\n[FEATURES] Top 10 most important features:")
    importance = model.feature_importances_
    feat_imp = sorted(zip(FEATURE_NAMES[:len(importance)], importance), key=lambda x: x[1], reverse=True)
    for name, imp in feat_imp[:10]:
        print(f"  {name:25s}: {imp:.4f}")

    # Save model and test predictions
    os.makedirs(output_dir, exist_ok=True)
    model_path = os.path.join(output_dir, "xgboost_cardiac.joblib")
    joblib.dump(model, model_path)
    print(f"\n[DONE] Model saved to {model_path}")

    np.savez(os.path.join(output_dir, "xgboost_test_preds.npz"),
             preds=test_probs, labels=y_test_valid)

    return test_auc


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", default=None, help="Path to ptbxl_100hz.npz")
    parser.add_argument("--output", default="models", help="Output directory")
    parser.add_argument("--n-estimators", type=int, default=500)
    parser.add_argument("--max-depth", type=int, default=6)
    parser.add_argument("--lr", type=float, default=0.05)
    args = parser.parse_args()

    train_xgboost(
        data_path=args.data,
        output_dir=args.output,
        n_estimators=args.n_estimators,
        max_depth=args.max_depth,
        learning_rate=args.lr,
    )
