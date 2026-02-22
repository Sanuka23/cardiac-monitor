"""
Fine-tune ECGFounder (single-lead) for binary cardiac classification.
Uses PTB-XL Lead II at 500Hz → normal vs abnormal.
"""

import os
import sys
import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader
from huggingface_hub import hf_hub_download
from sklearn.metrics import roc_auc_score, f1_score, accuracy_score
from tqdm import tqdm

sys.path.insert(0, os.path.dirname(__file__))
from net1d import Net1D


class ECGDataset(Dataset):
    def __init__(self, signals, labels):
        self.signals = torch.FloatTensor(signals)  # (N, 1, 5000)
        self.labels = torch.FloatTensor(labels).unsqueeze(1)  # (N, 1)

    def __len__(self):
        return len(self.labels)

    def __getitem__(self, idx):
        return self.signals[idx], self.labels[idx]


def build_model(n_classes=1, device="cpu"):
    """Build Net1D for single-lead ECG."""
    model = Net1D(
        in_channels=1,
        base_filters=64,
        ratio=1,
        filter_list=[64, 160, 160, 400, 400, 1024, 1024],
        m_blocks_list=[2, 2, 2, 3, 3, 4, 4],
        kernel_size=16,
        stride=2,
        groups_width=16,
        verbose=False,
        use_bn=False,
        use_do=False,
        n_classes=n_classes,
    )
    return model.to(device)


def load_pretrained_weights(model, device="cpu"):
    """Load single-lead ECGFounder pre-trained weights."""
    print("[MODEL] Downloading ECGFounder single-lead weights from HuggingFace...")
    checkpoint_path = hf_hub_download(
        repo_id="PKUDigitalHealth/ECGFounder",
        filename="1_lead_ECGFounder.pth",
    )

    checkpoint = torch.load(checkpoint_path, map_location=device, weights_only=False)
    state_dict = checkpoint.get("state_dict", checkpoint)

    # Remove classification head weights (we'll use our own)
    state_dict = {k: v for k, v in state_dict.items() if not k.startswith("dense.")}

    # Load backbone (strict=False since dense layer is different)
    missing, unexpected = model.load_state_dict(state_dict, strict=False)
    print(f"[MODEL] Loaded pre-trained weights. Missing: {len(missing)}, Unexpected: {len(unexpected)}")
    if missing:
        print(f"  Missing keys (expected — new head): {missing}")

    return model


def train_epoch(model, loader, criterion, optimizer, device):
    model.train()
    total_loss = 0
    all_preds, all_labels = [], []

    for signals, labels in loader:
        signals, labels = signals.to(device), labels.to(device)

        optimizer.zero_grad()
        logits = model(signals)
        loss = criterion(logits, labels)
        loss.backward()
        optimizer.step()

        total_loss += loss.item() * len(labels)
        probs = torch.sigmoid(logits).detach().cpu().numpy()
        all_preds.extend(probs.flatten())
        all_labels.extend(labels.cpu().numpy().flatten())

    avg_loss = total_loss / len(all_labels)
    auc = roc_auc_score(all_labels, all_preds) if len(set(all_labels)) > 1 else 0
    return avg_loss, auc


@torch.no_grad()
def evaluate(model, loader, criterion, device):
    model.eval()
    total_loss = 0
    all_preds, all_labels = [], []

    for signals, labels in loader:
        signals, labels = signals.to(device), labels.to(device)
        logits = model(signals)
        loss = criterion(logits, labels)

        total_loss += loss.item() * len(labels)
        probs = torch.sigmoid(logits).cpu().numpy()
        all_preds.extend(probs.flatten())
        all_labels.extend(labels.cpu().numpy().flatten())

    avg_loss = total_loss / len(all_labels)
    auc = roc_auc_score(all_labels, all_preds) if len(set(all_labels)) > 1 else 0

    # F1 at threshold 0.5
    binary_preds = [1 if p > 0.5 else 0 for p in all_preds]
    f1 = f1_score(all_labels, binary_preds)
    acc = accuracy_score(all_labels, binary_preds)

    return avg_loss, auc, f1, acc, np.array(all_preds), np.array(all_labels)


def finetune(data_path: str = None, output_dir: str = "models",
             epochs: int = 30, batch_size: int = 64, lr: float = 1e-4,
             freeze_epochs: int = 5):
    """
    Fine-tune ECGFounder on PTB-XL for binary classification.

    Strategy:
        1. First `freeze_epochs`: freeze backbone, train only classification head
        2. Remaining epochs: unfreeze all, train end-to-end with lower LR
    """
    # Device selection: CUDA > MPS (Apple Silicon) > CPU
    if torch.cuda.is_available():
        device = torch.device("cuda:0")
    elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
        device = torch.device("mps")
    else:
        device = torch.device("cpu")
    print(f"[TRAIN] Using device: {device}")

    # Load data
    if data_path is None:
        data_path = os.path.join(os.path.dirname(__file__), "..", "data", "processed", "ptbxl_500hz.npz")
    data = np.load(data_path)
    X_train, y_train = data["X_train"], data["y_train"]
    X_val, y_val = data["X_val"], data["y_val"]
    X_test, y_test = data["X_test"], data["y_test"]

    print(f"[DATA] Train: {len(y_train)} ({y_train.sum():.0f} abnormal)")
    print(f"[DATA] Val:   {len(y_val)} ({y_val.sum():.0f} abnormal)")
    print(f"[DATA] Test:  {len(y_test)} ({y_test.sum():.0f} abnormal)")

    # Class weights for imbalanced data
    pw = float((y_train == 0).sum()) / max(float((y_train == 1).sum()), 1)
    pos_weight = torch.tensor([pw], dtype=torch.float32).to(device)
    print(f"[DATA] Pos weight: {pos_weight.item():.2f}")

    train_ds = ECGDataset(X_train, y_train)
    val_ds = ECGDataset(X_val, y_val)
    test_ds = ECGDataset(X_test, y_test)

    train_loader = DataLoader(train_ds, batch_size=batch_size, shuffle=True, num_workers=0, pin_memory=True)
    val_loader = DataLoader(val_ds, batch_size=batch_size, shuffle=False, num_workers=0)
    test_loader = DataLoader(test_ds, batch_size=batch_size, shuffle=False, num_workers=0)

    # Build and load pre-trained model
    model = build_model(n_classes=1, device=device)
    model = load_pretrained_weights(model, device=device)

    criterion = nn.BCEWithLogitsLoss(pos_weight=pos_weight)

    # Phase 1: Freeze backbone, train head only
    print(f"\n[TRAIN] Phase 1: Frozen backbone ({freeze_epochs} epochs, lr={lr * 10})")
    for name, param in model.named_parameters():
        if not name.startswith("dense."):
            param.requires_grad = False

    optimizer = torch.optim.Adam(filter(lambda p: p.requires_grad, model.parameters()), lr=lr * 10)

    best_auc = 0
    os.makedirs(output_dir, exist_ok=True)

    for epoch in range(freeze_epochs):
        train_loss, train_auc = train_epoch(model, train_loader, criterion, optimizer, device)
        val_loss, val_auc, val_f1, val_acc, _, _ = evaluate(model, val_loader, criterion, device)
        print(f"  Epoch {epoch + 1}/{freeze_epochs}: "
              f"train_loss={train_loss:.4f} train_auc={train_auc:.4f} | "
              f"val_loss={val_loss:.4f} val_auc={val_auc:.4f} val_f1={val_f1:.4f}")

        if val_auc > best_auc:
            best_auc = val_auc
            torch.save(model.state_dict(), os.path.join(output_dir, "ecgfounder_best.pt"))

    # Phase 2: Unfreeze all, fine-tune end-to-end
    remaining = epochs - freeze_epochs
    print(f"\n[TRAIN] Phase 2: Full fine-tune ({remaining} epochs, lr={lr})")
    for param in model.parameters():
        param.requires_grad = True

    optimizer = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=1e-5)
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
        optimizer, mode="max", factor=0.5, patience=5
    )
    patience_counter = 0
    early_stop_patience = 10

    for epoch in range(remaining):
        train_loss, train_auc = train_epoch(model, train_loader, criterion, optimizer, device)
        val_loss, val_auc, val_f1, val_acc, _, _ = evaluate(model, val_loader, criterion, device)
        scheduler.step(val_auc)

        print(f"  Epoch {freeze_epochs + epoch + 1}/{epochs}: "
              f"train_loss={train_loss:.4f} train_auc={train_auc:.4f} | "
              f"val_loss={val_loss:.4f} val_auc={val_auc:.4f} val_f1={val_f1:.4f}")

        if val_auc > best_auc:
            best_auc = val_auc
            patience_counter = 0
            torch.save(model.state_dict(), os.path.join(output_dir, "ecgfounder_best.pt"))
            print(f"    -> New best AUC: {best_auc:.4f}")
        else:
            patience_counter += 1
            if patience_counter >= early_stop_patience:
                print(f"    -> Early stopping at epoch {freeze_epochs + epoch + 1}")
                break

    # Final evaluation on test set
    print("\n[TEST] Loading best model and evaluating on test set...")
    model.load_state_dict(torch.load(os.path.join(output_dir, "ecgfounder_best.pt"), map_location=device))
    test_loss, test_auc, test_f1, test_acc, test_preds, test_labels = evaluate(
        model, test_loader, criterion, device
    )
    print(f"  Test AUC:  {test_auc:.4f}")
    print(f"  Test F1:   {test_f1:.4f}")
    print(f"  Test Acc:  {test_acc:.4f}")

    # Save test predictions for ensemble evaluation
    np.savez(os.path.join(output_dir, "ecgfounder_test_preds.npz"),
             preds=test_preds, labels=test_labels)

    print(f"\n[DONE] Best model saved to {output_dir}/ecgfounder_best.pt")
    print(f"[DONE] Best validation AUC: {best_auc:.4f}")

    return best_auc


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", default=None, help="Path to ptbxl_500hz.npz")
    parser.add_argument("--output", default="models", help="Output directory")
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--lr", type=float, default=1e-4)
    parser.add_argument("--freeze-epochs", type=int, default=5)
    args = parser.parse_args()

    finetune(
        data_path=args.data,
        output_dir=args.output,
        epochs=args.epochs,
        batch_size=args.batch_size,
        lr=args.lr,
        freeze_epochs=args.freeze_epochs,
    )
