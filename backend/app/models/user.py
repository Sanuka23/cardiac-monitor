from pydantic import BaseModel, EmailStr, Field
from typing import List, Optional
from datetime import datetime


class HealthProfile(BaseModel):
    age: Optional[int] = Field(None, ge=1, le=120)
    sex: Optional[str] = Field(None, pattern="^(male|female|other)$")
    height_cm: Optional[float] = Field(None, ge=50, le=300)
    weight_kg: Optional[float] = Field(None, ge=10, le=500)
    is_diabetic: bool = False
    is_hypertensive: bool = False
    is_smoker: bool = False
    family_history: bool = False
    known_conditions: List[str] = Field(default_factory=list)
    medications: List[str] = Field(default_factory=list)


class UserRegister(BaseModel):
    email: str = Field(..., min_length=5, max_length=100)
    password: str = Field(..., min_length=6, max_length=100)
    name: str = Field(..., min_length=1, max_length=100)


class UserLogin(BaseModel):
    email: str
    password: str


class UserResponse(BaseModel):
    id: str
    email: str
    name: str
    device_ids: List[str] = Field(default_factory=list)
    profile: Optional[HealthProfile] = None
    created_at: datetime


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
