from pydantic import BaseModel, Field
from datetime import datetime


class PredictionResponse(BaseModel):
    id: str
    vitals_id: str
    device_id: str
    risk_score: float = Field(..., ge=0.0, le=1.0)
    risk_label: str
    confidence: float = Field(..., ge=0.0, le=1.0)
    features: dict
    model_version: str
    created_at: datetime
