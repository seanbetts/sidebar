"""Live provider API key verification before persisting BYOK credentials."""

from __future__ import annotations

import ssl

import httpx

from api.config import Settings, settings
from api.services.ai.registry import AIProvider
from api.services.user_ai_provider_key_service import UserAIProviderKeyService


class ProviderKeyVerificationService:
    """Verify provider API keys against upstream provider auth endpoints."""

    _OPENAI_MODELS_URL = "https://api.openai.com/v1/models"
    _ANTHROPIC_MODELS_URL = "https://api.anthropic.com/v1/models"
    _GOOGLE_MODELS_URL = "https://generativelanguage.googleapis.com/v1beta/models"
    _VERIFICATION_ERROR_MESSAGE = (
        "Could not verify provider API key right now. Please try again."
    )

    @classmethod
    async def verify_provider_key(
        cls,
        provider: AIProvider,
        api_key: str,
        *,
        app_settings: Settings = settings,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        """Raise when a provider API key is invalid or cannot be verified."""
        normalized = api_key.strip()
        if not UserAIProviderKeyService._is_valid_provider_key(provider, normalized):
            raise ValueError("Invalid provider API key")

        owns_client = client is None
        resolved_client = client or cls._create_http_client(app_settings)
        try:
            response = await cls._send_verification_request(
                resolved_client,
                provider=provider,
                api_key=normalized,
            )
        except httpx.HTTPError as exc:
            raise RuntimeError(cls._VERIFICATION_ERROR_MESSAGE) from exc
        finally:
            if owns_client:
                await resolved_client.aclose()

        cls._raise_for_unsuccessful_verification(response)

    @classmethod
    async def _send_verification_request(
        cls,
        client: httpx.AsyncClient,
        *,
        provider: AIProvider,
        api_key: str,
    ) -> httpx.Response:
        """Call the provider's lightweight models endpoint."""
        if provider == "openai":
            return await client.get(
                cls._OPENAI_MODELS_URL,
                headers={"Authorization": f"Bearer {api_key}"},
            )

        if provider == "anthropic":
            return await client.get(
                cls._ANTHROPIC_MODELS_URL,
                headers={
                    "x-api-key": api_key,
                    "anthropic-version": "2023-06-01",
                },
            )

        return await client.get(
            cls._GOOGLE_MODELS_URL,
            params={"key": api_key, "pageSize": 1},
        )

    @classmethod
    def _raise_for_unsuccessful_verification(cls, response: httpx.Response) -> None:
        """Translate provider verification responses into user-facing errors."""
        if 200 <= response.status_code <= 299:
            return

        if response.status_code in {400, 401, 403}:
            raise ValueError("Invalid provider API key")

        raise RuntimeError(cls._VERIFICATION_ERROR_MESSAGE)

    @staticmethod
    def _create_http_client(app_settings: Settings) -> httpx.AsyncClient:
        """Create HTTP client with repo-standard TLS and timeout settings."""
        ssl_verify: bool | ssl.SSLContext = True
        ssl_context: ssl.SSLContext | None = None

        if (
            app_settings.app_env in {"local", "development", "dev", "test"}
            and app_settings.disable_ssl_verify
        ):
            ssl_context = ssl.create_default_context()
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl.CERT_NONE
        elif app_settings.custom_ca_bundle:
            ssl_context = ssl.create_default_context()
            ssl_context.load_verify_locations(cafile=app_settings.custom_ca_bundle)

        if ssl_context is not None:
            ssl_verify = ssl_context

        return httpx.AsyncClient(
            verify=ssl_verify,
            timeout=httpx.Timeout(10.0, connect=5.0),
        )
