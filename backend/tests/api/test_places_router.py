from api.config import settings
from tests.helpers import error_message


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_places_autocomplete_requires_api_key(test_client, monkeypatch):
    monkeypatch.setattr(settings, "google_places_api_key", "")
    response = test_client.get("/api/places/autocomplete", params={"input": "Lo"}, headers=_auth_headers())
    assert response.status_code == 503
    assert error_message(response) == "Google Places API key not configured"


def test_places_autocomplete_short_input_returns_empty(test_client, monkeypatch):
    monkeypatch.setattr(settings, "google_places_api_key", "test-key")
    response = test_client.get("/api/places/autocomplete", params={"input": "A"}, headers=_auth_headers())
    assert response.status_code == 200
    assert response.json()["predictions"] == []
