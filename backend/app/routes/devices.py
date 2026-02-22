from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.device import DeviceRegister, DeviceResponse

router = APIRouter()


@router.post("/register", response_model=DeviceResponse)
async def register_device(data: DeviceRegister, user=Depends(get_current_user)):
    db = get_db()

    existing = await db.devices.find_one({"device_id": data.device_id})
    if existing:
        # If device already exists, link to this user if not already linked
        if existing.get("owner_user_id") and str(existing["owner_user_id"]) != str(
            user["_id"]
        ):
            raise HTTPException(
                status_code=400, detail="Device already registered to another user"
            )
        await db.devices.update_one(
            {"device_id": data.device_id},
            {
                "$set": {
                    "owner_user_id": str(user["_id"]),
                    "name": data.name or existing.get("name"),
                }
            },
        )
        existing["owner_user_id"] = str(user["_id"])
        if data.name:
            existing["name"] = data.name
        doc = existing
    else:
        doc = {
            "device_id": data.device_id,
            "name": data.name,
            "owner_user_id": str(user["_id"]),
            "last_seen": None,
            "registered_at": datetime.utcnow(),
        }
        await db.devices.insert_one(doc)

    # Add device_id to user's device list
    await db.users.update_one(
        {"_id": user["_id"]},
        {"$addToSet": {"device_ids": data.device_id}},
    )

    return DeviceResponse(
        device_id=doc["device_id"],
        name=doc.get("name"),
        owner_user_id=doc.get("owner_user_id"),
        last_seen=doc.get("last_seen"),
        registered_at=doc.get("registered_at", datetime.utcnow()),
    )


@router.get("", response_model=list[DeviceResponse])
async def list_devices(user=Depends(get_current_user)):
    db = get_db()

    device_ids = user.get("device_ids", [])
    if not device_ids:
        return []

    cursor = db.devices.find({"device_id": {"$in": device_ids}})
    docs = await cursor.to_list(length=100)

    return [
        DeviceResponse(
            device_id=doc["device_id"],
            name=doc.get("name"),
            owner_user_id=doc.get("owner_user_id"),
            last_seen=doc.get("last_seen"),
            registered_at=doc.get("registered_at", datetime.utcnow()),
        )
        for doc in docs
    ]
