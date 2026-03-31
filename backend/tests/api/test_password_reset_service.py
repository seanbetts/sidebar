import pytest

from api.config import settings
from api.services.password_reset_service import PasswordResetService


class _FakeResponse:
    def raise_for_status(self) -> None:
        return


class _CapturingAsyncClient:
    captured_requests: list[dict] = []

    def __init__(self, *args, **kwargs) -> None:
        self.timeout = kwargs.get("timeout")

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb) -> None:
        return None

    async def post(self, url: str, *, headers: dict, json: dict):
        self.captured_requests.append(
            {
                "url": url,
                "headers": headers,
                "json": json,
                "timeout": self.timeout,
            }
        )
        return _FakeResponse()


@pytest.mark.asyncio
async def test_password_reset_service_includes_app_redirect(monkeypatch) -> None:
    _CapturingAsyncClient.captured_requests = []
    monkeypatch.setattr(settings, "supabase_url", "https://project-ref.supabase.co")
    monkeypatch.setattr(settings, "supabase_anon_key", "anon-key")
    monkeypatch.setattr(settings, "supabase_service_role_key", None)
    monkeypatch.setattr(
        settings,
        "password_reset_redirect_to",
        "sidebar://auth/callback",
    )
    monkeypatch.setattr(
        "api.services.password_reset_service.httpx.AsyncClient",
        _CapturingAsyncClient,
    )

    await PasswordResetService.request_password_reset("person@example.com")

    assert _CapturingAsyncClient.captured_requests == [
        {
            "url": "https://project-ref.supabase.co/auth/v1/recover",
            "headers": {
                "apikey": "anon-key",
                "Content-Type": "application/json",
                "redirect_to": "sidebar://auth/callback",
            },
            "json": {
                "email": "person@example.com",
            },
            "timeout": 10.0,
        }
    ]
