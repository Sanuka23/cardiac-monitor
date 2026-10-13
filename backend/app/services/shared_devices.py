"""Devices visible to every logged-in account (e.g. a single demo device used by several people).

Configured with the SHARED_DEVICE_IDS setting: a comma-separated list of device IDs.
Shared devices are added to every user's device list, pass ownership checks, and their
data is included in the user-scoped (/me) endpoints. Uploads are unaffected.

The entry "*" shares every device that has uploaded data, without registering it to an
account. Playback devices (IDs starting with PLAYBACK_) are excluded from "*": they hold
recorded or dataset ECG, so they are shared only when listed by name.
"""

from datetime import datetime

from app.config import settings

ALL_DEVICES = "*"
PLAYBACK_PREFIX = "PLAYBACK_"


def parse_device_ids(value: str) -> list:
    return [d.strip() for d in (value or "").split(",") if d.strip()]


def shared_device_ids() -> list:
    """Device IDs listed by name ("*" is not a device ID)."""
    return [d for d in parse_device_ids(settings.SHARED_DEVICE_IDS) if d != ALL_DEVICES]


def all_devices_shared() -> bool:
    return ALL_DEVICES in parse_device_ids(settings.SHARED_DEVICE_IDS)


def with_shared_devices(device_ids: list) -> list:
    """The user's own devices first, then shared devices they don't already have."""
    own = list(device_ids or [])
    return own + [d for d in shared_device_ids() if d not in own]


async def visible_device_ids(db, device_ids: list) -> list:
    """with_shared_devices, plus (with "*") every non-playback device that has uploaded data."""
    ids = with_shared_devices(device_ids)
    if all_devices_shared():
        uploaded = await db.vitals.distinct("device_id")
        ids += sorted(d for d in uploaded if d and not d.startswith(PLAYBACK_PREFIX) and d not in ids)
    return ids


async def ensure_shared_device_docs(db):
    """Create an unowned device record for each shared device that has none (never modifies existing ones)."""
    for device_id in shared_device_ids():
        await db.devices.update_one(
            {"device_id": device_id},
            {"$setOnInsert": {"device_id": device_id, "name": None, "owner_user_id": None,
                              "last_seen": None, "registered_at": datetime.utcnow()}},
            upsert=True,
        )


def user_scope_filter(user: dict) -> dict:
    """Mongo filter for a user's own data plus all data from shared devices."""
    mine = {"user_id": str(user["_id"])}
    # With "*", the user's device list (from visible_device_ids) already holds every visible device
    shared = user.get("device_ids", []) if all_devices_shared() else shared_device_ids()
    return {"$or": [mine, {"device_id": {"$in": shared}}]} if shared else mine
