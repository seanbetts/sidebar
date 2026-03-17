import pytest

from api.config import settings
from api.services.ai.key_encryption import ProviderKeyEncryptionService
from api.services.user_ai_provider_key_service import UserAIProviderKeyService


def test_upsert_and_get_active_key_round_trip(test_db):
    record = UserAIProviderKeyService.upsert_key(
        test_db,
        user_id="user-1",
        provider="openai",
        api_key="sk-openai-abcdef1234",
    )
    assert record.key_last4 == "1234"

    resolved = UserAIProviderKeyService.get_active_key(
        test_db,
        user_id="user-1",
        provider="openai",
    )
    assert resolved == "sk-openai-abcdef1234"


def test_soft_delete_key_marks_record_deleted(test_db):
    UserAIProviderKeyService.upsert_key(
        test_db,
        user_id="user-2",
        provider="anthropic",
        api_key="sk-ant-api-key-5678",
    )
    deleted = UserAIProviderKeyService.soft_delete_key(
        test_db,
        user_id="user-2",
        provider="anthropic",
    )
    assert deleted is True
    assert (
        UserAIProviderKeyService.get_active_key(
            test_db,
            user_id="user-2",
            provider="anthropic",
        )
        is None
    )


def test_provider_key_encryption_requires_explicit_key_in_production(monkeypatch):
    monkeypatch.setattr(settings, "app_env", "production")
    monkeypatch.setattr(settings, "byok_encryption_key", None)
    monkeypatch.setattr(settings, "supabase_jwt_secret", "jwt-secret")
    monkeypatch.setattr(settings, "supabase_service_role_key", "service-role")
    monkeypatch.setattr(settings, "bearer_token", "bearer-token")
    ProviderKeyEncryptionService._fernet = None

    with pytest.raises(ValueError, match="BYOK_ENCRYPTION_KEY is required in production"):
        ProviderKeyEncryptionService._resolve_fernet_key()


def test_provider_key_encryption_uses_fallback_outside_production(monkeypatch):
    monkeypatch.setattr(settings, "app_env", "local")
    monkeypatch.setattr(settings, "byok_encryption_key", None)
    monkeypatch.setattr(settings, "supabase_jwt_secret", "jwt-secret")
    monkeypatch.setattr(settings, "supabase_service_role_key", None)
    monkeypatch.setattr(settings, "bearer_token", None)
    ProviderKeyEncryptionService._fernet = None

    encrypted = ProviderKeyEncryptionService.encrypt("sk-local-12345678")

    assert ProviderKeyEncryptionService.decrypt(encrypted) == "sk-local-12345678"
