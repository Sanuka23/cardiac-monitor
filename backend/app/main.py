from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.database import connect_db, close_db
from app.routes import vitals, auth, devices, health, predictions


@asynccontextmanager
async def lifespan(app: FastAPI):
    await connect_db(settings.MONGODB_URI, settings.DATABASE_NAME)
    yield
    await close_db()


app = FastAPI(
    title="Cardiac Monitor API",
    version="1.0.0",
    description="Backend for ESP32 Heart Rate, SpO2 & ECG Monitor",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router, prefix="/api/v1", tags=["health"])
app.include_router(auth.router, prefix="/api/v1/auth", tags=["auth"])
app.include_router(vitals.router, prefix="/api/v1/vitals", tags=["vitals"])
app.include_router(predictions.router, prefix="/api/v1/predictions", tags=["predictions"])
app.include_router(devices.router, prefix="/api/v1/devices", tags=["devices"])
