from datetime import datetime

from bson import ObjectId
from fastapi import APIRouter, Depends, HTTPException, Query

from app.database import get_db
from app.middleware.auth import verify_api_key, get_current_user
from app.models.vitals import VitalsCreate, VitalsResponse, VitalsListResponse

router = APIRouter()


def _vitals_doc_to_response(doc: dict, prediction: dict = None) -> VitalsResponse:
    ecg = doc.get("ecg_samples")
    return VitalsResponse(
        id=str(doc["_id"]),
        device_id=doc["device_id"],
        timestamp=doc["timestamp"],
        heart_rate_bpm=doc["heart_rate_bpm"],
        spo2_percent=doc["spo2_percent"],
        ecg_lead_off=doc["ecg_lead_off"],
        sample_count=len(ecg) if ecg else 0,
        ecg_samples=ecg,
        sample_rate_hz=doc.get("sample_rate_hz"),
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

    # Run ML prediction if models are available
    prediction = None
    try:
        from app.services.ml_service import predict, _models_loaded, load_models

        if not _models_loaded:
            load_models()

        if not data.ecg_lead_off and len(data.ecg_samples) >= 100:
            # Get user profile for personalized prediction
            device_doc = await db.devices.find_one({"device_id": data.device_id})
            user_profile = None
            history_features = None

            if device_doc and device_doc.get("owner_user_id"):
                user = await db.users.find_one({"_id": ObjectId(device_doc["owner_user_id"])})
                if user and user.get("profile"):
                    user_profile = user["profile"]

                # Compute historical baselines
                from datetime import timedelta
                now = datetime.utcnow()
                pipeline_24h = [
                    {"$match": {"device_id": data.device_id,
                                "created_at": {"$gte": now - timedelta(hours=24)}}},
                    {"$group": {
                        "_id": None,
                        "avg_hr": {"$avg": "$heart_rate_bpm"},
                        "std_hr": {"$stdDevPop": "$heart_rate_bpm"},
                        "avg_spo2": {"$avg": "$spo2_percent"},
                        "std_spo2": {"$stdDevPop": "$spo2_percent"},
                        "count": {"$sum": 1},
                    }},
                ]
                pipeline_7d = [
                    {"$match": {"device_id": data.device_id,
                                "created_at": {"$gte": now - timedelta(days=7)}}},
                    {"$group": {
                        "_id": None,
                        "avg_hr": {"$avg": "$heart_rate_bpm"},
                        "avg_spo2": {"$avg": "$spo2_percent"},
                    }},
                ]

                stats_24h = await db.vitals.aggregate(pipeline_24h).to_list(1)
                stats_7d = await db.vitals.aggregate(pipeline_7d).to_list(1)

                if stats_24h:
                    s = stats_24h[0]
                    hr_std = s.get("std_hr", 1) or 1
                    spo2_std = s.get("std_spo2", 1) or 1
                    history_features = {
                        "hr_baseline_24h": s.get("avg_hr", 0),
                        "spo2_baseline_24h": s.get("avg_spo2", 0),
                        "hr_deviation": abs(data.heart_rate_bpm - s.get("avg_hr", data.heart_rate_bpm)) / hr_std,
                        "spo2_deviation": abs(data.spo2_percent - s.get("avg_spo2", data.spo2_percent)) / spo2_std,
                        "readings_count_24h": s.get("count", 0),
                    }
                if stats_7d:
                    if history_features is None:
                        history_features = {}
                    history_features["hr_baseline_7d"] = stats_7d[0].get("avg_hr", 0)

            ml_result = predict(
                ecg_samples=data.ecg_samples,
                sample_rate_hz=data.sample_rate_hz,
                heart_rate_bpm=data.heart_rate_bpm,
                spo2_percent=data.spo2_percent,
                user_profile=user_profile,
                history_features=history_features,
            )

            if ml_result["risk_label"] != "unknown":
                pred_doc = {
                    "vitals_id": str(result.inserted_id),
                    "device_id": data.device_id,
                    "risk_score": ml_result["risk_score"],
                    "risk_label": ml_result["risk_label"],
                    "confidence": ml_result["confidence"],
                    "features": ml_result["features"],
                    "model_version": ml_result["model_version"],
                    "created_at": datetime.utcnow(),
                }
                await db.predictions.insert_one(pred_doc)
                prediction = {
                    "risk_score": ml_result["risk_score"],
                    "risk_label": ml_result["risk_label"],
                    "confidence": ml_result["confidence"],
                }
    except ImportError:
        pass  # ML dependencies not installed, skip prediction
    except Exception as e:
        print(f"[ML] Prediction error: {e}")

    return _vitals_doc_to_response(vitals_doc, prediction)


@router.get("/{device_id}/latest", response_model=VitalsResponse)
async def get_latest_vitals(
    device_id: str,
    include_ecg: bool = Query(default=False),
    _=Depends(get_current_user),
):
    db = get_db()

    projection = None if include_ecg else {"ecg_samples": 0, "beat_timestamps_ms": 0}
    doc = await db.vitals.find_one(
        {"device_id": device_id},
        projection=projection,
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
