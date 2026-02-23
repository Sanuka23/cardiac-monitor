from fastapi import APIRouter, Depends, HTTPException, Query

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.prediction import PredictionResponse

router = APIRouter()


def _pred_doc_to_response(doc: dict) -> PredictionResponse:
    return PredictionResponse(
        id=str(doc["_id"]),
        vitals_id=doc["vitals_id"],
        device_id=doc["device_id"],
        risk_score=doc["risk_score"],
        risk_label=doc["risk_label"],
        confidence=doc["confidence"],
        features=doc.get("features", {}),
        model_version=doc.get("model_version", "none"),
        created_at=doc["created_at"],
    )


async def _verify_device_ownership(device_id: str, user: dict):
    """Verify the requesting user owns this device."""
    if device_id not in user.get("device_ids", []):
        raise HTTPException(
            status_code=403, detail="Device not registered to your account"
        )


# ── User-based endpoints (must be before /{device_id} routes) ──


@router.get("/me/latest", response_model=PredictionResponse)
async def get_user_latest_prediction(user=Depends(get_current_user)):
    db = get_db()
    user_id = str(user["_id"])

    doc = await db.predictions.find_one(
        {"user_id": user_id},
        sort=[("created_at", -1)],
    )
    if not doc:
        raise HTTPException(status_code=404, detail="No predictions found")

    return _pred_doc_to_response(doc)


@router.get("/me/history")
async def get_user_prediction_history(
    limit: int = Query(default=50, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    user=Depends(get_current_user),
):
    db = get_db()
    user_id = str(user["_id"])

    cursor = (
        db.predictions.find({"user_id": user_id})
        .sort("created_at", -1)
        .skip(offset)
        .limit(limit)
    )
    docs = await cursor.to_list(length=limit)

    results = [_pred_doc_to_response(doc) for doc in docs]
    total = await db.predictions.count_documents({"user_id": user_id})
    return {"predictions": results, "total": total}


# ── Device-specific endpoints (with ownership verification) ──


@router.get("/{device_id}/latest", response_model=PredictionResponse)
async def get_latest_prediction(device_id: str, user=Depends(get_current_user)):
    db = get_db()
    await _verify_device_ownership(device_id, user)

    doc = await db.predictions.find_one(
        {"device_id": device_id},
        sort=[("created_at", -1)],
    )
    if not doc:
        raise HTTPException(
            status_code=404, detail="No predictions found for this device"
        )

    return _pred_doc_to_response(doc)


@router.get("/{device_id}")
async def get_prediction_history(
    device_id: str,
    limit: int = Query(default=50, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    user=Depends(get_current_user),
):
    db = get_db()
    await _verify_device_ownership(device_id, user)

    cursor = (
        db.predictions.find({"device_id": device_id})
        .sort("created_at", -1)
        .skip(offset)
        .limit(limit)
    )
    docs = await cursor.to_list(length=limit)

    results = [_pred_doc_to_response(doc) for doc in docs]
    total = await db.predictions.count_documents({"device_id": device_id})
    return {"predictions": results, "total": total}
