from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    MONGODB_URI: str = "mongodb://localhost:27017"
    DATABASE_NAME: str = "cardiac_monitor"
    JWT_SECRET: str = "changeme"
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRY_HOURS: int = 24
    API_KEY: str = "dev-api-key"
    SHARED_DEVICE_IDS: str = ""  # comma-separated devices visible to every account

    class Config:
        env_file = ".env"


settings = Settings()
