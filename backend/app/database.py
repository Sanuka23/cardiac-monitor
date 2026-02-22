from motor.motor_asyncio import AsyncIOMotorClient

client: AsyncIOMotorClient = None
db = None


async def connect_db(uri: str, db_name: str):
    global client, db
    client = AsyncIOMotorClient(uri, serverSelectionTimeoutMS=5000)
    db = client[db_name]

    # Create indexes (non-blocking — if DB is unreachable, server still starts)
    try:
        await db.users.create_index("email", unique=True)
        await db.devices.create_index("device_id", unique=True)
        await db.vitals.create_index([("device_id", 1), ("timestamp", -1)])
        await db.predictions.create_index([("device_id", 1), ("created_at", -1)])
        print("[DB] Connected and indexes created.")
    except Exception as e:
        print(f"[DB] Warning: Could not create indexes: {e}")
        print("[DB] Server will start but DB operations may fail until MongoDB is available.")


async def close_db():
    global client
    if client:
        client.close()


def get_db():
    return db
