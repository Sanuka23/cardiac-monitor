import asyncio

from app import database
from app.routes.health import health_check

# A mongodb+srv URI whose SRV record does not exist (e.g. a deleted Atlas
# cluster). pymongo resolves SRV when the client is constructed.
MISSING_CLUSTER_URI = "mongodb+srv://user:pass@cluster0.missing.invalid"


def test_connect_db_does_not_raise_when_cluster_dns_missing():
    asyncio.run(database.connect_db(MISSING_CLUSTER_URI, "cardiac_monitor"))


def test_health_reports_db_disconnected_when_cluster_dns_missing():
    asyncio.run(database.connect_db(MISSING_CLUSTER_URI, "cardiac_monitor"))

    result = asyncio.run(health_check())

    assert result["status"] == "ok"
    assert result["db"] == "disconnected"
