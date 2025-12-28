from api.config import settings


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_places_autocomplete_requires_api_key(test_client, monkeypatch):
    monkeypatch.setattr(settings, "google_places_api_key", "")
    response = test_client.get("/api/places/autocomplete", params={"input": "Lo"}, headers=_auth_headers())
    assert response.status_code == 503
    assert response.json()["detail"] == "Google Places API key not configured"
