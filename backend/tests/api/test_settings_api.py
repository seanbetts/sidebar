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


def test_update_settings_forces_required_skills(test_client):
    response = test_client.patch(
        "/api/settings",
        headers=_auth_headers(),
        json={"enabled_skills": ["fs"]},
    )
    assert response.status_code == 200
    assert "files" in response.json()["enabled_skills"]
    assert "fs" not in response.json()["enabled_skills"]
    assert "assistant-identity" in response.json()["enabled_skills"]
    assert "assistant-soul" in response.json()["enabled_skills"]


def test_update_settings_rejects_agent_owned_fields(test_client):
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
    assert response.status_code == 422


def test_update_settings_accepts_ai_provider_preferences(test_client):
    response = test_client.patch(
        "/api/settings",
        headers=_auth_headers(),
        json={"ai_primary_provider": "anthropic"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["ai_primary_provider"] == "anthropic"


def test_provider_key_crud_flow(test_client):
    update_response = test_client.patch(
        "/api/settings",
        headers=_auth_headers(),
        json={"ai_primary_provider": "openai"},
    )
    assert update_response.status_code == 200

    empty_status = test_client.get(
        "/api/settings/ai/provider-key",
        headers=_auth_headers(),
    )
    assert empty_status.status_code == 200
    assert empty_status.json() == {
        "provider": "openai",
        "has_key": False,
        "key_last4": None,
    }

    save_status = test_client.put(
        "/api/settings/ai/provider-key",
        headers=_auth_headers(),
        json={"provider": "openai", "api_key": "sk-openai-provider-1234"},
    )
    assert save_status.status_code == 200
    assert save_status.json() == {
        "provider": "openai",
        "has_key": True,
        "key_last4": "1234",
    }

    loaded_status = test_client.get(
        "/api/settings/ai/provider-key?provider=openai",
        headers=_auth_headers(),
    )
    assert loaded_status.status_code == 200
    assert loaded_status.json() == {
        "provider": "openai",
        "has_key": True,
        "key_last4": "1234",
    }

    delete_status = test_client.delete(
        "/api/settings/ai/provider-key?provider=openai",
        headers=_auth_headers(),
    )
    assert delete_status.status_code == 200
    assert delete_status.json() == {
        "provider": "openai",
        "has_key": False,
        "key_last4": None,
    }


def test_provider_key_disconnect_flow_skill_then_ai_provider(test_client):
    save_status = test_client.put(
        "/api/settings/ai/provider-key",
        headers=_auth_headers(),
        json={"provider": "openai", "api_key": "sk-openai-provider-5678"},
    )
    assert save_status.status_code == 200

    install_response = test_client.post(
        "/api/skills/store/install",
        headers=_auth_headers(),
        json={"skill_id": "audio-transcribe"},
    )
    assert install_response.status_code == 200

    set_provider = test_client.patch(
        "/api/settings",
        headers=_auth_headers(),
        json={"ai_primary_provider": "openai"},
    )
    assert set_provider.status_code == 200

    disconnect_skill = test_client.post(
        "/api/settings/ai/provider-key/disconnect",
        headers=_auth_headers(),
        json={
            "provider": "openai",
            "source": "skill",
            "skill_id": "audio-transcribe",
        },
    )
    assert disconnect_skill.status_code == 200
    disconnect_skill_body = disconnect_skill.json()
    assert disconnect_skill_body["actions"]["disabled_skill_ids"] == [
        "audio-transcribe"
    ]
    assert disconnect_skill_body["actions"]["detached_ai_provider"] is False
    assert disconnect_skill_body["actions"]["deleted_provider_key"] is False
    assert disconnect_skill_body["remaining_consumers"]["ai_provider"] is True
    assert "audio-transcribe" not in disconnect_skill_body["settings"]["enabled_skills"]

    disconnect_ai = test_client.post(
        "/api/settings/ai/provider-key/disconnect",
        headers=_auth_headers(),
        json={"provider": "openai", "source": "ai_provider"},
    )
    assert disconnect_ai.status_code == 200
    disconnect_ai_body = disconnect_ai.json()
    assert disconnect_ai_body["actions"]["disabled_skill_ids"] == []
    assert disconnect_ai_body["actions"]["detached_ai_provider"] is True
    assert disconnect_ai_body["actions"]["deleted_provider_key"] is True
    assert disconnect_ai_body["remaining_consumers"]["ai_provider"] is False
    assert disconnect_ai_body["remaining_consumers"]["skill_ids"] == []
    assert disconnect_ai_body["settings"]["ai_primary_provider"] is None

    final_status = test_client.get(
        "/api/settings/ai/provider-key?provider=openai",
        headers=_auth_headers(),
    )
    assert final_status.status_code == 200
    assert final_status.json()["has_key"] is False
