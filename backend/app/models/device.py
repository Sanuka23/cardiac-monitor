from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class DeviceRegister(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=50)
    name: Optional[str] = Field(None, max_length=100)


class DeviceResponse(BaseModel):
    device_id: str
    name: Optional[str] = None
    owner_user_id: Optional[str] = None
    last_seen: Optional[datetime] = None
    registered_at: datetime
