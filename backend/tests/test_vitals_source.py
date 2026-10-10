from datetime import datetime

from bson import ObjectId

from app.models.vitals import VitalsCreate
from app.routes.vitals import _vitals_doc_to_response

PLAYBACK_SOURCE = "PTB-XL #8473 · cardiologist label: MI"


def _payload(**overrides):
    payload = {
        "device_id": "PLAYBACK_PTBXL",
        "timestamp": 1760000000,
        "heart_rate_bpm": 71.3,
        "spo2_percent": 0,
        "ecg_samples": [2048] * 2500,
    }
    payload.update(overrides)
    return payload


def _doc(**overrides):
    doc = {
        "_id": ObjectId(),
        "device_id": "PLAYBACK_PTBXL",
        "timestamp": datetime(2026, 10, 9),
        "heart_rate_bpm": 71.3,
        "spo2_percent": 0,
        "ecg_lead_off": False,
        "ecg_samples": [2048] * 2500,
        "created_at": datetime(2026, 10, 9),
    }
    doc.update(overrides)
    return doc


def test_upload_accepts_optional_source_label():
    assert VitalsCreate(**_payload(source=PLAYBACK_SOURCE)).source == PLAYBACK_SOURCE
    assert VitalsCreate(**_payload()).source is None


def test_response_includes_source_label():
    assert _vitals_doc_to_response(_doc(source=PLAYBACK_SOURCE)).source == PLAYBACK_SOURCE


def test_response_source_is_none_for_live_device_docs():
    assert _vitals_doc_to_response(_doc(device_id="ESP32_21E5F0")).source is None
