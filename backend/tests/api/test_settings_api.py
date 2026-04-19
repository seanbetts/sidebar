import os

from api.config import settings
from api.services.capabilities.skill_state_service import SkillStateService
from api.services.user_settings_service import UserSettingsService
from api.services import settings_service

from tests.helpers import error_message


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


async def _accept_provider_key(*_args, **_kwargs) -> None:
    return None


async def _reject_provider_key(*_args, **_kwargs) -> None:
    raise ValueError("Invalid provider API key")


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
        json={"enabled_skills": ["files", "not-a-skill"]},
    )
    assert response.status_code == 400
    assert "Invalid skills" in error_message(response)


def test_update_settings_forces_required_skills(test_client):
    response = test_client.patch(
        "/api/settings",
        headers=_auth_headers(),
        json={"enabled_skills": ["files"]},
    )
    assert response.status_code == 200
    assert "files" in response.json()["enabled_skills"]
    assert "fs" not in response.json()["enabled_skills"]
    assert "assistant-identity" in response.json()["enabled_skills"]
    assert "assistant-soul" in response.json()["enabled_skills"]
    assert "enabled_toolsets" not in response.json()


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


def test_get_settings_includes_notification_preference_defaults(test_client):
    response = test_client.get(
        "/api/settings",
        headers=_auth_headers(),
    )

    assert response.status_code == 200
    body = response.json()
    assert body["notification_preferences"] == {
        "task_reminders_enabled": True,
        "task_reminder_time": None,
        "morning_digest_enabled": False,
        "morning_digest_time": None,
        "assistant_reply_notifications_enabled": False,
        "assistant_proactive_notifications_enabled": False,
        "schedule_timezone": None,
    }


def test_get_settings_includes_internal_diagnostics_capability(test_client, monkeypatch):
    monkeypatch.setenv("INTERNAL_DIAGNOSTICS_ENABLED", "true")
    monkeypatch.setenv("INTERNAL_DIAGNOSTIC_USER_IDS", settings.require_test_user_id())

    response = test_client.get(
        "/api/settings",
        headers=_auth_headers(),
    )

    assert response.status_code == 200
    assert response.json()["can_access_internal_diagnostics"] is True


def test_update_settings_accepts_notification_preferences(test_client):
    response = test_client.patch(
        "/api/settings",
        headers=_auth_headers(),
        json={
            "notification_preferences": {
                "task_reminders_enabled": True,
                "task_reminder_time": "09:30",
                "morning_digest_enabled": False,
                "morning_digest_time": None,
                "assistant_reply_notifications_enabled": True,
                "assistant_proactive_notifications_enabled": False,
                "schedule_timezone": "Europe/London",
            }
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["notification_preferences"]["task_reminder_time"] == "09:30"
    assert body["notification_preferences"]["schedule_timezone"] == "Europe/London"
    assert body["notification_preferences"]["assistant_reply_notifications_enabled"] is True


def test_update_settings_rejects_enabled_reminders_without_time_and_timezone(
    test_client,
):
    response = test_client.patch(
        "/api/settings",
        headers=_auth_headers(),
        json={
            "notification_preferences": {
                "task_reminders_enabled": True,
                "task_reminder_time": None,
                "morning_digest_enabled": False,
                "morning_digest_time": None,
                "assistant_reply_notifications_enabled": False,
                "assistant_proactive_notifications_enabled": False,
                "schedule_timezone": None,
            }
        },
    )

    assert response.status_code == 400
    assert "task_reminder_time" in error_message(response)


def test_provider_key_crud_flow(test_client, monkeypatch):
    monkeypatch.setattr(
        "api.routers.settings.ProviderKeyVerificationService.verify_provider_key",
        _accept_provider_key,
    )
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


def test_provider_key_rejects_invalid_format(test_client, monkeypatch):
    monkeypatch.setattr(
        "api.routers.settings.ProviderKeyVerificationService.verify_provider_key",
        _reject_provider_key,
    )
    save_status = test_client.put(
        "/api/settings/ai/provider-key",
        headers=_auth_headers(),
        json={"provider": "openai", "api_key": "not-a-real-openai-key"},
    )
    assert save_status.status_code == 400
    assert error_message(save_status) == "Invalid provider API key"


def test_provider_key_rejects_invalid_openai_key_even_with_valid_prefix(
    test_client,
    monkeypatch,
):
    monkeypatch.setattr(
        "api.routers.settings.ProviderKeyVerificationService.verify_provider_key",
        _reject_provider_key,
    )
    save_status = test_client.put(
        "/api/settings/ai/provider-key",
        headers=_auth_headers(),
        json={"provider": "openai", "api_key": "sk-proj-definitely-not-real-1234"},
    )
    assert save_status.status_code == 400
    assert error_message(save_status) == "Invalid provider API key"


def test_provider_key_disconnect_flow_skill_then_ai_provider(test_client, monkeypatch):
    monkeypatch.setattr(
        "api.routers.settings.ProviderKeyVerificationService.verify_provider_key",
        _accept_provider_key,
    )
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


def test_get_settings_reads_normalized_skill_state_over_legacy_arrays(
    test_client,
    test_db,
):
    user_id = os.environ["TEST_USER_ID"]
    UserSettingsService.upsert_settings(
        test_db,
        user_id,
        enabled_skills=["files", "assistant-identity", "assistant-soul"],
        installed_store_skills=[],
    )
    SkillStateService.upsert_skill_state(
        test_db,
        user_id=user_id,
        skill_id="files",
        enabled=False,
        installed=False,
        commit=False,
    )
    SkillStateService.upsert_skill_state(
        test_db,
        user_id=user_id,
        skill_id="assistant-identity",
        enabled=True,
        installed=False,
        commit=False,
    )
    SkillStateService.upsert_skill_state(
        test_db,
        user_id=user_id,
        skill_id="assistant-soul",
        enabled=True,
        installed=False,
        commit=False,
    )
    SkillStateService.upsert_skill_state(
        test_db,
        user_id=user_id,
        skill_id="audio-transcribe",
        enabled=True,
        installed=True,
        commit=True,
    )

    response = test_client.get("/api/settings", headers=_auth_headers())

    assert response.status_code == 200
    body = response.json()
    assert "files" not in body["enabled_skills"]
    assert "audio-transcribe" in body["enabled_skills"]
    assert body["installed_store_skills"] == ["audio-transcribe"]


def test_update_settings_preserves_skill_toggle_ux_without_legacy_columns(
    test_client,
    test_db,
):
    response = test_client.patch(
        "/api/settings",
        headers=_auth_headers(),
        json={"enabled_skills": ["files"]},
    )

    assert response.status_code == 200
    body = response.json()
    assert "files" in body["enabled_skills"]
    assert "assistant-identity" in body["enabled_skills"]
    assert "assistant-soul" in body["enabled_skills"]

    user_id = os.environ["TEST_USER_ID"]
    settings_record = UserSettingsService.get_settings(test_db, user_id)
    assert settings_record is not None
    assert not hasattr(settings_record, "enabled_skills")


def test_store_install_preserves_installed_skill_payload_without_legacy_columns(
    test_client,
    test_db,
    monkeypatch,
):
    monkeypatch.setattr(
        "api.routers.settings.ProviderKeyVerificationService.verify_provider_key",
        _accept_provider_key,
    )
    save_key = test_client.put(
        "/api/settings/ai/provider-key",
        headers=_auth_headers(),
        json={"provider": "openai", "api_key": "sk-openai-provider-2222"},
    )
    assert save_key.status_code == 200

    response = test_client.post(
        "/api/skills/store/install",
        headers=_auth_headers(),
        json={"skill_id": "audio-transcribe"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["installed"] is True
    assert body["enabled"] is True
    assert "audio-transcribe" in body["enabled_skills"]
    assert body["installed_store_skills"] == ["audio-transcribe"]

    user_id = os.environ["TEST_USER_ID"]
    settings_record = UserSettingsService.get_settings(test_db, user_id)
    assert settings_record is None or not hasattr(
        settings_record, "installed_store_skills"
    )
