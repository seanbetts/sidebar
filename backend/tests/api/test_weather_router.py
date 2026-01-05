import time
import pytest

from api.config import settings
from api.exceptions import ExternalServiceError
from api.routers import weather as weather_router


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_weather_uses_cache(test_client):
    payload = {"temperature_c": 10, "fetched_at": time.time()}
    weather_router._weather_cache["1.0:2.0"] = {"fetched_at": time.time(), "payload": payload}

    response = test_client.get("/api/weather", params={"lat": 1.0, "lon": 2.0}, headers=_auth_headers())
    assert response.status_code == 200
    assert response.json()["temperature_c"] == 10


def test_weather_handles_invalid_json(monkeypatch):
    class FakeResponse:
        def __init__(self, payload: bytes):
            self._payload = payload

        def read(self):
            return self._payload

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

    def fake_urlopen(*_args, **_kwargs):
        return FakeResponse(b"{invalid")

    monkeypatch.setattr(weather_router, "urlopen", fake_urlopen)
    with pytest.raises(ExternalServiceError):
        weather_router._fetch_weather(1.0, 2.0)
