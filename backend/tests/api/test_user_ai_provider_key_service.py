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
