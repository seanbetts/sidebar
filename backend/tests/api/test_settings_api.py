from api.config import settings
from api.services import settings_service

from tests.helpers import error_message


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
    assert "communication_style exceeds" in error_message(response)


def test_update_settings_rejects_invalid_skills(test_client):
    response = test_client.patch(
        "/api/settings",
        headers=_auth_headers(),
        json={"enabled_skills": ["fs", "not-a-skill"]},
    )
    assert response.status_code == 400
    assert "Invalid skills" in error_message(response)


def test_update_settings_trims_assistant_identity_fields(test_client):
    response = test_client.patch(
        "/api/settings",
        headers=_auth_headers(),
        json={
            "assistant_identity": {
                "name": "  Navigator  ",
                "tone": "  Calm and technical.  ",
            }
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["assistant_identity"]["name"] == "Navigator"
    assert body["assistant_identity"]["tone"] == "Calm and technical."
    assert body["assistant_identity"]["values"] == settings_service.DEFAULT_ASSISTANT_IDENTITY["values"]


def test_update_settings_rejects_long_assistant_identity_name(test_client):
    long_name = "a" * (settings_service.MAX_ASSISTANT_IDENTITY_NAME_CHARS + 1)
    response = test_client.patch(
        "/api/settings",
        headers=_auth_headers(),
        json={
            "assistant_identity": {
                "name": long_name,
            }
        },
    )
    assert response.status_code == 400
    assert "assistant_identity.name exceeds" in error_message(response)
