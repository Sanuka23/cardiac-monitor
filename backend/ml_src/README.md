# ML Pipeline

Cardiac risk prediction using an ensemble of ECGFounder (deep learning) and XGBoost (gradient boosting).

## Model Architecture

```
Raw ECG (1000 samples @ 100Hz)
        │
        ├──> ECGFounder (1D CNN)──> 128-dim embedding
        │                                │
        ├──> Feature Engineering ────────>├──> 14 clinical features
        │    (NeuroKit2 + SciPy)         │
        │                                v
        │                          XGBoost Classifier
        │                                │
        └── Ensemble ────────────────────>│──> Risk Score (0.0-1.0)
             (weighted average)               Risk Label
```

### ECGFounder

- **Architecture**: 1D convolutional neural network (`net1d.py`)
- **Input**: 1000 ECG samples (10s window at 100Hz), bandpass filtered 0.5-40Hz
- **Output**: 128-dimensional feature embedding
- **Model file**: `ml_models/ecgfounder_best.pt` (117 MB)

### XGBoost Classifier

- **Input**: 14 features (ECG embedding + clinical features)
- **Output**: Binary risk probability
- **Model file**: `ml_models/xgboost_cardiac.joblib` (752 KB)

## Feature Engineering

The `feature_extractor.py` module computes clinical features from raw ECG:

| Feature | Source | Description |
|---------|--------|-------------|
| Heart Rate | Input | BPM from MAX30100 |
| SpO2 | Input | Blood oxygen percentage |
| HRV (SDNN) | NeuroKit2 | Heart rate variability |
| HRV (RMSSD) | NeuroKit2 | Root mean square of successive RR differences |
| QRS Duration | NeuroKit2 | Ventricular depolarization time |
| PR Interval | NeuroKit2 | Atrial-ventricular conduction |
| Signal Quality | SciPy | SNR estimate of ECG signal |
| Mean RR | Computed | Average R-R interval |
| RR Irregularity | Computed | Coefficient of variation of RR |
| Age | Profile | User age (if available) |
| Sex | Profile | Binary encoded |
| BMI | Profile | Computed from height/weight |
| Comorbidity Score | Profile | Count of risk factors |
| HR Deviation | History | Z-score vs 24h baseline |

## Inference Flow

1. Vitals uploaded to `POST /api/v1/vitals`
2. If ECG leads are connected and >= 100 samples:
   a. Load user health profile from database
   b. Compute 24h and 7d historical baselines
   c. Extract features from ECG waveform
   d. Run ECGFounder for deep features
   e. Combine and run XGBoost
   f. Store prediction in `predictions` collection
3. Return vitals + prediction in API response

## Risk Labels

| Score Range | Label | Description |
|-------------|-------|-------------|
| 0.00 - 0.20 | normal | No concerning patterns |
| 0.20 - 0.40 | low | Minor irregularities |
| 0.40 - 0.60 | moderate | Some risk indicators |
| 0.60 - 0.80 | elevated | Multiple risk factors |
| 0.80 - 1.00 | high | Significant cardiac risk |

## Files

```
ml_src/
├── __init__.py
├── net1d.py               # ECGFounder 1D CNN model definition
└── feature_extractor.py   # Clinical feature extraction

ml_models/
├── ecgfounder_best.pt     # Trained ECGFounder weights (Git LFS)
└── xgboost_cardiac.joblib # Trained XGBoost model (Git LFS)
```

## Dependencies

- `torch` (CPU-only, installed from pytorch.org/whl/cpu)
- `xgboost >= 2.0.0`
- `neurokit2 >= 0.2.7`
- `scipy >= 1.14.1`
- `numpy >= 1.26.4`
- `joblib >= 1.3.0`
