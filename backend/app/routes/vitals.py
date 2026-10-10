from datetime import datetime

from bson import ObjectId
from fastapi import APIRouter, Depends, HTTPException, Query

from app.database import get_db
from app.middleware.auth import verify_api_key, get_current_user
from app.models.vitals import VitalsCreate, VitalsResponse, VitalsListResponse
from app.services.shared_devices import user_scope_filter
from app.services.signal_quality import assess_ecg_quality

router = APIRouter()


def _ecg_heart_rate(features: dict):
    """Heart rate the feature extractor measured from the ECG R-peaks, if plausible."""
    hr = (features or {}).get("mean_hr_ecg")
    return round(float(hr), 1) if hr and 30 <= hr <= 220 else None


def _vitals_doc_to_response(doc: dict, prediction: dict = None) -> VitalsResponse:
    ecg = doc.get("ecg_samples")
    return VitalsResponse(
        id=str(doc["_id"]),
        device_id=doc["device_id"],
        timestamp=doc["timestamp"],
        heart_rate_bpm=doc["heart_rate_bpm"],
        heart_rate_source=doc.get("heart_rate_source"),
        spo2_percent=doc["spo2_percent"],
        ecg_lead_off=doc["ecg_lead_off"],
        sample_count=len(ecg) if ecg else 0,
        ecg_samples=ecg,
        sample_rate_hz=doc.get("sample_rate_hz"),
        prediction=prediction,
        signal_quality=doc.get("signal_quality"),
        source=doc.get("source"),
        created_at=doc["created_at"],
    )


async def _verify_device_ownership(device_id: str, user: dict):
    """Verify the requesting user owns this device."""
    if device_id not in user.get("device_ids", []):
        raise HTTPException(
            status_code=403, detail="Device not registered to your account"
        )


@router.post("", response_model=VitalsResponse)
async def upload_vitals(data: VitalsCreate, _=Depends(verify_api_key)):
    db = get_db()

    # Resolve device → owner user_id
    device_doc = await db.devices.find_one({"device_id": data.device_id})
    user_id = device_doc.get("owner_user_id") if device_doc else None

    # Signal-quality gate: the lead-off pins miss unattached electrodes, so
    # check the waveform itself before letting the model score it.
    signal_quality = signal_quality_reason = None
    if data.ecg_lead_off:
        signal_quality = signal_quality_reason = "lead_off"
    elif len(data.ecg_samples) >= 100:
        try:
            quality = assess_ecg_quality(data.ecg_samples, data.sample_rate_hz)
            signal_quality, signal_quality_reason = quality["quality"], quality["reason"]
        except Exception as e:
            print(f"[SQ] Signal quality check error: {e}")
            signal_quality, signal_quality_reason = "poor", "quality_check_error"

    vitals_doc = {
        "device_id": data.device_id,
        "user_id": user_id,
        "timestamp": datetime.utcfromtimestamp(data.timestamp),
        "window_ms": data.window_ms,
        "sample_rate_hz": data.sample_rate_hz,
        "heart_rate_bpm": data.heart_rate_bpm,
        "heart_rate_source": "sensor" if data.heart_rate_bpm > 0 else None,
        "spo2_percent": data.spo2_percent,
        "ecg_lead_off": data.ecg_lead_off,
        "ecg_samples": data.ecg_samples,
        "beat_timestamps_ms": data.beat_timestamps_ms,
        "signal_quality": signal_quality,
        "signal_quality_reason": signal_quality_reason,
        "source": data.source,
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

        if signal_quality == "good":
            # Get user profile for personalized prediction
            user_profile = None
            history_features = None

            if device_doc and user_id:
                user = await db.users.find_one({"_id": ObjectId(user_id)})
                if user and user.get("profile"):
                    user_profile = user["profile"]

                # Compute historical baselines (across all user's devices)
                from datetime import timedelta
                now = datetime.utcnow()
                pipeline_24h = [
                    {"$match": {"user_id": user_id,
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
                    {"$match": {"user_id": user_id,
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

            # No pulse sensor reading (e.g. MAX30100 disabled): use the HR measured from the ECG
            if data.heart_rate_bpm <= 0:
                ecg_hr = _ecg_heart_rate(ml_result.get("features"))
                if ecg_hr:
                    vitals_doc.update(heart_rate_bpm=ecg_hr, heart_rate_source="ecg")
                    await db.vitals.update_one(
                        {"_id": result.inserted_id},
                        {"$set": {"heart_rate_bpm": ecg_hr, "heart_rate_source": "ecg"}},
                    )

            if ml_result["risk_label"] != "unknown":
                pred_doc = {
                    "vitals_id": str(result.inserted_id),
                    "device_id": data.device_id,
                    "user_id": user_id,
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


# ── User-based endpoints (must be before /{device_id} routes) ──


@router.get("/me/latest", response_model=VitalsResponse)
async def get_user_latest_vitals(
    include_ecg: bool = Query(default=False),
    user=Depends(get_current_user),
):
    db = get_db()

    projection = None if include_ecg else {"ecg_samples": 0, "beat_timestamps_ms": 0}
    doc = await db.vitals.find_one(
        user_scope_filter(user),
        projection=projection,
        sort=[("timestamp", -1)],
    )
    if not doc:
        raise HTTPException(status_code=404, detail="No vitals found")

    pred = await db.predictions.find_one({"vitals_id": str(doc["_id"])})
    pred_dict = None
    if pred:
        pred_dict = {
            "risk_score": pred["risk_score"],
            "risk_label": pred["risk_label"],
            "confidence": pred["confidence"],
        }

    return _vitals_doc_to_response(doc, pred_dict)


@router.get("/me/history", response_model=VitalsListResponse)
async def get_user_vitals_history(
    limit: int = Query(default=50, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    user=Depends(get_current_user),
):
    db = get_db()
    scope = user_scope_filter(user)

    total = await db.vitals.count_documents(scope)
    cursor = (
        db.vitals.find(
            scope,
            {"ecg_samples": 0},
        )
        .sort("timestamp", -1)
        .skip(offset)
        .limit(limit)
    )
    docs = await cursor.to_list(length=limit)

    vitals_list = [_vitals_doc_to_response(doc) for doc in docs]
    return VitalsListResponse(vitals=vitals_list, total=total)


# ── Device-specific endpoints (with ownership verification) ──


@router.get("/{device_id}/latest", response_model=VitalsResponse)
async def get_latest_vitals(
    device_id: str,
    include_ecg: bool = Query(default=False),
    user=Depends(get_current_user),
):
    db = get_db()
    await _verify_device_ownership(device_id, user)

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
    user=Depends(get_current_user),
):
    db = get_db()
    await _verify_device_ownership(device_id, user)

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
