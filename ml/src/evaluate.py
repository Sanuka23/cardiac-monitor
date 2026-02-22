"""
Evaluate individual models and the ensemble.
Generates metrics, ROC curves, and confusion matrices.
"""

import os
import sys
import numpy as np
import matplotlib.pyplot as plt
from sklearn.metrics import (
    roc_auc_score, roc_curve, f1_score, accuracy_score,
    precision_score, recall_score, confusion_matrix,
    classification_report, precision_recall_curve, average_precision_score
)

sys.path.insert(0, os.path.dirname(__file__))


def evaluate_ensemble(ecg_preds_path: str, xgb_preds_path: str,
                      ecg_weight: float = 0.60, xgb_weight: float = 0.40,
                      output_dir: str = "models"):
    """
    Evaluate the ensemble of ECGFounder + XGBoost on test set predictions.
    """
    ecg_data = np.load(ecg_preds_path)
    xgb_data = np.load(xgb_preds_path)

    ecg_preds = ecg_data["preds"]
    ecg_labels = ecg_data["labels"]
    xgb_preds = xgb_data["preds"]
    xgb_labels = xgb_data["labels"]

    # Align predictions (use minimum length in case of slight mismatches)
    n = min(len(ecg_preds), len(xgb_preds))
    ecg_preds, xgb_preds = ecg_preds[:n], xgb_preds[:n]
    labels = ecg_labels[:n]

    # Ensemble
    ensemble_preds = ecg_weight * ecg_preds + xgb_weight * xgb_preds

    print("=" * 60)
    print("MODEL EVALUATION RESULTS")
    print("=" * 60)

    results = {}
    for name, preds in [("ECGFounder", ecg_preds), ("XGBoost", xgb_preds), ("Ensemble", ensemble_preds)]:
        binary = (preds > 0.5).astype(int)
        auc = roc_auc_score(labels, preds)
        f1 = f1_score(labels, binary)
        acc = accuracy_score(labels, binary)
        prec = precision_score(labels, binary)
        rec = recall_score(labels, binary)
        ap = average_precision_score(labels, preds)

        results[name] = {"auc": auc, "f1": f1, "acc": acc, "prec": prec, "rec": rec, "ap": ap}

        print(f"\n--- {name} ---")
        print(f"  AUC-ROC:   {auc:.4f}")
        print(f"  AP:        {ap:.4f}")
        print(f"  F1:        {f1:.4f}")
        print(f"  Accuracy:  {acc:.4f}")
        print(f"  Precision: {prec:.4f}")
        print(f"  Recall:    {rec:.4f}")

        if name == "Ensemble":
            print(f"\n  Classification Report:")
            print(classification_report(labels, binary, target_names=["Normal", "Abnormal"]))
            print(f"  Confusion Matrix:")
            cm = confusion_matrix(labels, binary)
            print(cm)

    # Plot ROC curves
    os.makedirs(output_dir, exist_ok=True)

    plt.figure(figsize=(10, 8))
    for name, preds, color in [
        ("ECGFounder", ecg_preds, "blue"),
        ("XGBoost", xgb_preds, "green"),
        ("Ensemble", ensemble_preds, "red"),
    ]:
        fpr, tpr, _ = roc_curve(labels, preds)
        auc = results[name]["auc"]
        plt.plot(fpr, tpr, color=color, linewidth=2, label=f"{name} (AUC={auc:.4f})")

    plt.plot([0, 1], [0, 1], "k--", linewidth=1)
    plt.xlabel("False Positive Rate", fontsize=12)
    plt.ylabel("True Positive Rate", fontsize=12)
    plt.title("ROC Curves - Cardiac Risk Prediction", fontsize=14)
    plt.legend(fontsize=12)
    plt.grid(alpha=0.3)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "roc_curves.png"), dpi=150)
    print(f"\n[PLOT] ROC curves saved to {output_dir}/roc_curves.png")

    # Plot Precision-Recall curves
    plt.figure(figsize=(10, 8))
    for name, preds, color in [
        ("ECGFounder", ecg_preds, "blue"),
        ("XGBoost", xgb_preds, "green"),
        ("Ensemble", ensemble_preds, "red"),
    ]:
        prec_arr, rec_arr, _ = precision_recall_curve(labels, preds)
        ap = results[name]["ap"]
        plt.plot(rec_arr, prec_arr, color=color, linewidth=2, label=f"{name} (AP={ap:.4f})")

    plt.xlabel("Recall", fontsize=12)
    plt.ylabel("Precision", fontsize=12)
    plt.title("Precision-Recall Curves - Cardiac Risk Prediction", fontsize=14)
    plt.legend(fontsize=12)
    plt.grid(alpha=0.3)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "pr_curves.png"), dpi=150)
    print(f"[PLOT] PR curves saved to {output_dir}/pr_curves.png")

    # Optimal threshold analysis for ensemble
    fpr, tpr, thresholds = roc_curve(labels, ensemble_preds)
    j_scores = tpr - fpr
    optimal_idx = np.argmax(j_scores)
    optimal_threshold = thresholds[optimal_idx]
    print(f"\n[THRESHOLD] Optimal ensemble threshold (Youden's J): {optimal_threshold:.4f}")
    print(f"  At this threshold: TPR={tpr[optimal_idx]:.4f}, FPR={fpr[optimal_idx]:.4f}")

    # Save results
    np.savez(os.path.join(output_dir, "evaluation_results.npz"),
             ensemble_preds=ensemble_preds, labels=labels,
             optimal_threshold=optimal_threshold,
             ecg_auc=results["ECGFounder"]["auc"],
             xgb_auc=results["XGBoost"]["auc"],
             ensemble_auc=results["Ensemble"]["auc"])

    return results


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--ecg-preds", default="models/ecgfounder_test_preds.npz")
    parser.add_argument("--xgb-preds", default="models/xgboost_test_preds.npz")
    parser.add_argument("--ecg-weight", type=float, default=0.60)
    parser.add_argument("--xgb-weight", type=float, default=0.40)
    parser.add_argument("--output", default="models")
    args = parser.parse_args()

    evaluate_ensemble(
        args.ecg_preds, args.xgb_preds,
        ecg_weight=args.ecg_weight, xgb_weight=args.xgb_weight,
        output_dir=args.output,
    )
