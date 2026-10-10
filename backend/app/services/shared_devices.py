"""Devices visible to every logged-in account (e.g. a single demo device used by several people).

Configured with the SHARED_DEVICE_IDS setting: a comma-separated list of device IDs.
Shared devices are added to every user's device list, pass ownership checks, and their
data is included in the user-scoped (/me) endpoints. Uploads are unaffected.
"""

from app.config import settings


def parse_device_ids(value: str) -> list:
    return [d.strip() for d in (value or "").split(",") if d.strip()]


def shared_device_ids() -> list:
    return parse_device_ids(settings.SHARED_DEVICE_IDS)


def with_shared_devices(device_ids: list) -> list:
    """The user's own devices first, then shared devices they don't already have."""
    own = list(device_ids or [])
    return own + [d for d in shared_device_ids() if d not in own]


def user_scope_filter(user: dict) -> dict:
    """Mongo filter for a user's own data plus all data from shared devices."""
    mine = {"user_id": str(user["_id"])}
    shared = shared_device_ids()
    return {"$or": [mine, {"device_id": {"$in": shared}}]} if shared else mine
