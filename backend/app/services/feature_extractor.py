"""
ECG Feature Extraction for backend inference.
Thin wrapper that imports from ml/src/feature_extractor.py to stay in sync.
"""

import os
import sys

# Import from the bundled ML source
ML_SRC = os.path.join(os.path.dirname(__file__), "..", "..", "ml_src")
sys.path.insert(0, ML_SRC)

from feature_extractor import (
    extract_ecg_features,
    features_to_array,
    FEATURE_NAMES,
    PROFILE_FEATURE_NAMES,
    HISTORY_FEATURE_NAMES,
    ALL_FEATURE_NAMES,
)

__all__ = [
    "extract_ecg_features",
    "features_to_array",
    "FEATURE_NAMES",
    "PROFILE_FEATURE_NAMES",
    "HISTORY_FEATURE_NAMES",
    "ALL_FEATURE_NAMES",
]
