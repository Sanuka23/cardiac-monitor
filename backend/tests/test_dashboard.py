from fastapi.testclient import TestClient

from app.main import app

# Not used as a context manager, so the lifespan (DB connect, model loading) does not run
client = TestClient(app)


def test_dashboard_is_served_as_html():
    r = client.get("/dashboard")
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/html")
    assert "<title>Cardiac Monitor" in r.text


def test_dashboard_uses_the_existing_api():
    html = client.get("/dashboard").text
    for path in ("/api/v1/auth/login", "/api/v1/auth/me", "/api/v1/vitals/", "/api/v1/predictions/"):
        assert path in html


def test_dashboard_is_hidden_from_the_api_schema():
    assert "/dashboard" not in client.get("/openapi.json").json()["paths"]
