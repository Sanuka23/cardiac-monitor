from fastapi import APIRouter

from app.database import get_db

router = APIRouter()


@router.get("/health")
async def health_check():
    db = get_db()
    try:
        await db.command("ping")
        db_status = "connected"
    except Exception:
        db_status = "disconnected"

    return {"status": "ok", "db": db_status, "version": "1.0.0"}
