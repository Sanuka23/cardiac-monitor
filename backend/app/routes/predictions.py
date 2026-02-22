from fastapi import APIRouter, Depends, HTTPException, Query

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.prediction import PredictionResponse

router = APIRouter()


@router.get("/{device_id}/latest", response_model=PredictionResponse)
async def get_latest_prediction(device_id: str, _=Depends(get_current_user)):
    db = get_db()

    doc = await db.predictions.find_one(
        {"device_id": device_id},
        sort=[("created_at", -1)],
    )
    if not doc:
        raise HTTPException(
            status_code=404, detail="No predictions found for this device"
        )

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


@router.get("/{device_id}")
async def get_prediction_history(
    device_id: str,
    limit: int = Query(default=50, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    _=Depends(get_current_user),
):
    db = get_db()

    cursor = (
        db.predictions.find({"device_id": device_id})
        .sort("created_at", -1)
        .skip(offset)
        .limit(limit)
    )
    docs = await cursor.to_list(length=limit)

    results = [
        PredictionResponse(
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
        for doc in docs
    ]

    total = await db.predictions.count_documents({"device_id": device_id})
    return {"predictions": results, "total": total}
