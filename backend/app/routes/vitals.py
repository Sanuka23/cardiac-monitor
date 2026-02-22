from datetime import datetime

from bson import ObjectId
from fastapi import APIRouter, Depends, HTTPException, Query

from app.database import get_db
from app.middleware.auth import verify_api_key, get_current_user
from app.models.vitals import VitalsCreate, VitalsResponse, VitalsListResponse

router = APIRouter()


def _vitals_doc_to_response(doc: dict, prediction: dict = None) -> VitalsResponse:
    return VitalsResponse(
        id=str(doc["_id"]),
        device_id=doc["device_id"],
        timestamp=doc["timestamp"],
        heart_rate_bpm=doc["heart_rate_bpm"],
        spo2_percent=doc["spo2_percent"],
        ecg_lead_off=doc["ecg_lead_off"],
        sample_count=len(doc.get("ecg_samples", [])),
        prediction=prediction,
        created_at=doc["created_at"],
    )


@router.post("", response_model=VitalsResponse)
async def upload_vitals(data: VitalsCreate, _=Depends(verify_api_key)):
    db = get_db()

    vitals_doc = {
        "device_id": data.device_id,
        "timestamp": datetime.utcfromtimestamp(data.timestamp),
        "window_ms": data.window_ms,
        "sample_rate_hz": data.sample_rate_hz,
        "heart_rate_bpm": data.heart_rate_bpm,
        "spo2_percent": data.spo2_percent,
        "ecg_lead_off": data.ecg_lead_off,
        "ecg_samples": data.ecg_samples,
        "beat_timestamps_ms": data.beat_timestamps_ms,
        "created_at": datetime.utcnow(),
    }
    result = await db.vitals.insert_one(vitals_doc)
    vitals_doc["_id"] = result.inserted_id

    # Update device last_seen
    await db.devices.update_one(
        {"device_id": data.device_id},
        {"$set": {"last_seen": datetime.utcnow()}},
    )

    # TODO: Phase 2 — run ML prediction here and store result
    # For now, return without prediction
    return _vitals_doc_to_response(vitals_doc)


@router.get("/{device_id}/latest", response_model=VitalsResponse)
async def get_latest_vitals(device_id: str, _=Depends(get_current_user)):
    db = get_db()

    doc = await db.vitals.find_one(
        {"device_id": device_id},
        sort=[("timestamp", -1)],
    )
    if not doc:
        raise HTTPException(status_code=404, detail="No vitals found for this device")

    # Attach latest prediction if exists
    pred = await db.predictions.find_one(
        {"vitals_id": str(doc["_id"])},
    )
    pred_dict = None
    if pred:
        pred_dict = {
            "risk_score": pred["risk_score"],
            "risk_label": pred["risk_label"],
            "confidence": pred["confidence"],
        }

    return _vitals_doc_to_response(doc, pred_dict)


@router.get("/{device_id}", response_model=VitalsListResponse)
async def get_vitals_history(
    device_id: str,
    limit: int = Query(default=50, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    _=Depends(get_current_user),
):
    db = get_db()

    total = await db.vitals.count_documents({"device_id": device_id})
    cursor = (
        db.vitals.find(
            {"device_id": device_id},
            {"ecg_samples": 0},  # Exclude raw samples from list view
        )
        .sort("timestamp", -1)
        .skip(offset)
        .limit(limit)
    )
    docs = await cursor.to_list(length=limit)

    vitals_list = [_vitals_doc_to_response(doc) for doc in docs]
    return VitalsListResponse(vitals=vitals_list, total=total)
