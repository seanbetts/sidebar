import pytest
from fastapi import HTTPException

from api.services.settings_service import SettingsService
from api.services.store_skills_service import StoreSkillsService
from api.services.user_ai_provider_settings_service import (
    UserAIProviderSettingsService,
)


def test_attach_primary_provider_key_status_uses_selected_provider(test_db) -> None:
    user_id = "provider-status-attach-user"
    SettingsService.update_settings(
        test_db,
        user_id,
        {"ai_primary_provider": "anthropic"},
    )
    UserAIProviderSettingsService.upsert_provider_key(
        test_db,
        user_id,
        provider="anthropic",
        api_key="sk-ant-settings-1111",
    )

    payload = SettingsService.get_settings(test_db, user_id)
    result = UserAIProviderSettingsService.attach_primary_provider_key_status(
        test_db,
        user_id=user_id,
        payload=payload,
    )
    assert result["ai_primary_provider_has_key"] is True
    assert result["ai_primary_provider_key_last4"] == "1111"


def test_get_provider_key_status_rejects_invalid_provider(test_db) -> None:
    with pytest.raises(HTTPException) as exc_info:
        UserAIProviderSettingsService.get_provider_key_status(
            test_db,
            "provider-status-invalid",
            provider="not-a-provider",
        )
    assert exc_info.value.status_code == 400


def test_delete_provider_key_defaults_to_primary_provider(test_db) -> None:
    user_id = "provider-status-delete-user"
    SettingsService.update_settings(
        test_db,
        user_id,
        {"ai_primary_provider": "openai"},
    )
    UserAIProviderSettingsService.upsert_provider_key(
        test_db,
        user_id,
        provider="openai",
        api_key="sk-openai-provider-9999",
    )

    deleted = UserAIProviderSettingsService.delete_provider_key(
        test_db,
        user_id,
    )
    assert deleted["provider"] == "openai"
    assert deleted["has_key"] is False


def test_disconnect_skill_source_deletes_provider_key_for_last_consumer(
    test_db,
) -> None:
    user_id = "provider-disconnect-skill-last-consumer-user"
    StoreSkillsService.install_store_skill(
        test_db,
        user_id=user_id,
        skill_id="audio-transcribe",
        provider_keys=[{"provider": "openai", "api_key": "sk-openai-audio-1111"}],
    )

    result = UserAIProviderSettingsService.disconnect_provider_consumer(
        test_db,
        user_id,
        provider="openai",
        source="skill",
        skill_id="audio-transcribe",
    )

    assert result["actions"]["disabled_skill_ids"] == ["audio-transcribe"]
    assert result["actions"]["detached_ai_provider"] is False
    assert result["actions"]["deleted_provider_key"] is True
    assert result["remaining_consumers"]["ai_provider"] is False
    assert result["remaining_consumers"]["skill_ids"] == []
    assert "audio-transcribe" not in result["settings"]["enabled_skills"]

    key_status = UserAIProviderSettingsService.get_provider_key_status(
        test_db,
        user_id,
        provider="openai",
    )
    assert key_status["has_key"] is False


def test_disconnect_skill_source_keeps_key_when_ai_provider_still_uses_it(
    test_db,
) -> None:
    user_id = "provider-disconnect-skill-ai-consumer-user"
    SettingsService.update_settings(
        test_db,
        user_id,
        {"ai_primary_provider": "openai"},
    )
    StoreSkillsService.install_store_skill(
        test_db,
        user_id=user_id,
        skill_id="audio-transcribe",
        provider_keys=[{"provider": "openai", "api_key": "sk-openai-audio-2222"}],
    )

    result = UserAIProviderSettingsService.disconnect_provider_consumer(
        test_db,
        user_id,
        provider="openai",
        source="skill",
        skill_id="audio-transcribe",
    )

    assert result["actions"]["disabled_skill_ids"] == ["audio-transcribe"]
    assert result["actions"]["deleted_provider_key"] is False
    assert result["remaining_consumers"]["ai_provider"] is True

    key_status = UserAIProviderSettingsService.get_provider_key_status(
        test_db,
        user_id,
        provider="openai",
    )
    assert key_status["has_key"] is True


def test_disconnect_ai_provider_source_keeps_key_when_skill_still_uses_it(
    test_db,
) -> None:
    user_id = "provider-disconnect-ai-skill-consumer-user"
    SettingsService.update_settings(
        test_db,
        user_id,
        {"ai_primary_provider": "openai"},
    )
    StoreSkillsService.install_store_skill(
        test_db,
        user_id=user_id,
        skill_id="audio-transcribe",
        provider_keys=[{"provider": "openai", "api_key": "sk-openai-audio-3333"}],
    )

    result = UserAIProviderSettingsService.disconnect_provider_consumer(
        test_db,
        user_id,
        provider="openai",
        source="ai_provider",
    )

    assert result["actions"]["detached_ai_provider"] is True
    assert result["actions"]["deleted_provider_key"] is False
    assert result["remaining_consumers"]["ai_provider"] is False
    assert result["remaining_consumers"]["skill_ids"] == ["audio-transcribe"]
    assert result["settings"]["ai_primary_provider"] is None
    assert "audio-transcribe" in result["settings"]["enabled_skills"]

    key_status = UserAIProviderSettingsService.get_provider_key_status(
        test_db,
        user_id,
        provider="openai",
    )
    assert key_status["has_key"] is True
