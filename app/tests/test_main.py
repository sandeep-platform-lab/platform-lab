from fastapi.testclient import TestClient

from src.main import app

client = TestClient(app)


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_info_defaults():
    body = client.get("/api/info").json()
    assert body["service"] == "lab-api"
    assert body["version"] == "dev"
