import certifi
from motor.motor_asyncio import AsyncIOMotorClient

client: AsyncIOMotorClient = None
db = None


async def connect_db(uri: str, db_name: str):
    global client, db

    # Connect and create indexes (non-blocking — if DB is unreachable, server still starts).
    # Client creation is inside the try: mongodb+srv URIs resolve DNS here and raise
    # if the cluster no longer exists.
    try:
        client = AsyncIOMotorClient(
            uri,
            serverSelectionTimeoutMS=5000,
            tlsCAFile=certifi.where(),
        )
        db = client[db_name]

        await db.users.create_index("email", unique=True)
        await db.devices.create_index("device_id", unique=True)
        await db.vitals.create_index([("device_id", 1), ("timestamp", -1)])
        await db.vitals.create_index([("user_id", 1), ("timestamp", -1)])
        await db.predictions.create_index([("device_id", 1), ("created_at", -1)])
        await db.predictions.create_index([("user_id", 1), ("created_at", -1)])
        print("[DB] Connected and indexes created.")
    except Exception as e:
        print(f"[DB] Warning: Could not connect or create indexes: {e}")
        print("[DB] Server will start but DB operations may fail until MongoDB is available.")


async def close_db():
    if client:
        client.close()


def get_db():
    return db
