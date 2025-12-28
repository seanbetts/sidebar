import time

from api.config import settings
from api.routers import weather as weather_router


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_weather_uses_cache(test_client):
    payload = {"temperature_c": 10, "fetched_at": time.time()}
    weather_router._weather_cache["1.0:2.0"] = {"fetched_at": time.time(), "payload": payload}

    response = test_client.get("/api/weather", params={"lat": 1.0, "lon": 2.0}, headers=_auth_headers())
    assert response.status_code == 200
    assert response.json()["temperature_c"] == 10
