from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException

from app.database import get_db
from app.middleware.auth import (
    hash_password,
    verify_password,
    create_access_token,
    get_current_user,
)
from app.models.user import (
    UserRegister,
    UserLogin,
    UserResponse,
    TokenResponse,
    HealthProfile,
)

router = APIRouter()


@router.post("/register", response_model=TokenResponse)
async def register(data: UserRegister):
    db = get_db()

    existing = await db.users.find_one({"email": data.email})
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

    user_doc = {
        "email": data.email,
        "password_hash": hash_password(data.password),
        "name": data.name,
        "device_ids": [],
        "profile": None,
        "created_at": datetime.utcnow(),
    }
    result = await db.users.insert_one(user_doc)
    token = create_access_token(str(result.inserted_id))
    return TokenResponse(access_token=token)


@router.post("/login", response_model=TokenResponse)
async def login(data: UserLogin):
    db = get_db()

    user = await db.users.find_one({"email": data.email})
    if not user or not verify_password(data.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    token = create_access_token(str(user["_id"]))
    return TokenResponse(access_token=token)


@router.get("/me", response_model=UserResponse)
async def get_me(user=Depends(get_current_user)):
    return UserResponse(
        id=str(user["_id"]),
        email=user["email"],
        name=user["name"],
        device_ids=user.get("device_ids", []),
        profile=user.get("profile"),
        created_at=user["created_at"],
    )


@router.put("/profile", response_model=UserResponse)
async def update_profile(profile: HealthProfile, user=Depends(get_current_user)):
    db = get_db()

    await db.users.update_one(
        {"_id": user["_id"]},
        {"$set": {"profile": profile.model_dump()}},
    )

    user["profile"] = profile.model_dump()
    return UserResponse(
        id=str(user["_id"]),
        email=user["email"],
        name=user["name"],
        device_ids=user.get("device_ids", []),
        profile=user["profile"],
        created_at=user["created_at"],
    )
