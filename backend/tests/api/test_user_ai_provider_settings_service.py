import pytest
from fastapi import HTTPException

from api.services.settings_service import SettingsService
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
