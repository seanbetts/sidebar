import pytest

from api.config import settings
from api.supabase_jwt import SupabaseJWTValidator


@pytest.mark.asyncio
async def test_validate_token_accepts_test_bearer_token_without_supabase_url(
    monkeypatch,
):
    monkeypatch.setattr(settings, "supabase_url", "")

    validator = SupabaseJWTValidator()
    payload = await validator.validate_token(settings.bearer_token or "")

    assert payload["sub"] == settings.require_test_user_id()
