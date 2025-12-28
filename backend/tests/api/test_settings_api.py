from api.config import settings
from api.services import settings_service


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_update_settings_trims_fields(test_client):
    response = test_client.patch(
        "/api/settings",
        headers=_auth_headers(),
        json={"name": "  Sam  "},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["name"] == "Sam"


def test_update_settings_rejects_long_style(test_client):
    long_value = "a" * (settings_service.MAX_STYLE_CHARS + 1)
    response = test_client.patch(
        "/api/settings",
        headers=_auth_headers(),
        json={"communication_style": long_value},
    )
    assert response.status_code == 400
    assert "communication_style exceeds" in response.json()["detail"]


def test_update_settings_rejects_invalid_skills(test_client):
    response = test_client.patch(
        "/api/settings",
        headers=_auth_headers(),
        json={"enabled_skills": ["fs", "not-a-skill"]},
    )
    assert response.status_code == 400
    assert "Invalid skills" in response.json()["detail"]
