import httpx
import pytest

from api.services.provider_key_verification_service import (
    ProviderKeyVerificationService,
)


def _response(
    status_code: int,
    *,
    method: str,
    url: str,
) -> httpx.Response:
    request = httpx.Request(method, url)
    return httpx.Response(status_code, request=request)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("provider", "api_key", "expected_url"),
    [
        ("openai", "sk-proj-valid-openai-key-1234", "https://api.openai.com/v1/models"),
        ("anthropic", "sk-ant-valid-anthropic-key-1234", "https://api.anthropic.com/v1/models"),
        ("google", "AIzaValidGoogleKey12345", "https://generativelanguage.googleapis.com/v1beta/models?key=AIzaValidGoogleKey12345&pageSize=1"),
    ],
)
async def test_verify_provider_key_calls_models_endpoint(
    provider,
    api_key,
    expected_url,
) -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        assert str(request.url) == expected_url
        if provider == "openai":
            assert request.headers["Authorization"] == f"Bearer {api_key}"
        elif provider == "anthropic":
            assert request.headers["x-api-key"] == api_key
            assert request.headers["anthropic-version"] == "2023-06-01"
        return _response(200, method=request.method, url=str(request.url))

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as client:
        await ProviderKeyVerificationService.verify_provider_key(
            provider,
            api_key,
            client=client,
        )


@pytest.mark.asyncio
async def test_verify_provider_key_rejects_provider_auth_failure() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        return _response(401, method=request.method, url=str(request.url))

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as client:
        with pytest.raises(ValueError, match="Invalid provider API key"):
            await ProviderKeyVerificationService.verify_provider_key(
                "openai",
                "sk-proj-invalid-openai-key-1234",
                client=client,
            )


@pytest.mark.asyncio
async def test_verify_provider_key_surfaces_provider_outage() -> None:
    async def handler(_request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("boom")

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as client:
        with pytest.raises(
            RuntimeError,
            match="Could not verify provider API key right now. Please try again.",
        ):
            await ProviderKeyVerificationService.verify_provider_key(
                "openai",
                "sk-proj-valid-openai-key-1234",
                client=client,
            )
