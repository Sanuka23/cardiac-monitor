from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime


class VitalsCreate(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=50)
    timestamp: int = Field(..., description="Unix epoch seconds from ESP32")
    window_ms: int = Field(default=10000, ge=1000, le=60000)
    sample_rate_hz: int = Field(default=100, ge=50, le=1000)
    heart_rate_bpm: float = Field(..., ge=0, le=300)
    spo2_percent: int = Field(..., ge=0, le=100)
    ecg_lead_off: bool = Field(default=False)
    ecg_samples: List[int] = Field(..., min_length=100, max_length=6000)
    beat_timestamps_ms: List[int] = Field(default_factory=list)


class VitalsResponse(BaseModel):
    id: str
    device_id: str
    timestamp: datetime
    heart_rate_bpm: float
    spo2_percent: int
    ecg_lead_off: bool
    sample_count: int
    ecg_samples: Optional[List[int]] = None
    sample_rate_hz: Optional[int] = None
    prediction: Optional[dict] = None
    created_at: datetime


class VitalsListResponse(BaseModel):
    vitals: List[VitalsResponse]
    total: int
