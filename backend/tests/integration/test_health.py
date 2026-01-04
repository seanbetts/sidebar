import pytest
from fastapi.testclient import TestClient

pytest.importorskip("sentry_sdk")

from api.main import app


def test_health_endpoint() -> None:
    client = TestClient(app)
    response = client.get("/api/health")
    assert response.status_code == 200
