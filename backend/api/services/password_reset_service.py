"""Password reset delivery via Supabase Auth."""

from __future__ import annotations

import httpx

from api.config import settings
from api.exceptions import ExternalServiceError, ServiceUnavailableError


class PasswordResetService:
    """Start password reset delivery without exposing account existence."""

    @staticmethod
    async def request_password_reset(email: str) -> None:
        """Request a password reset email from the auth provider.

        Args:
            email: User email address, already normalized by the router.

        Raises:
            ServiceUnavailableError: Backend auth provider config is missing.
            ExternalServiceError: The provider request failed.
        """
        supabase_url = settings.supabase_url.strip()
        api_key = (
            settings.supabase_service_role_key or ""
        ).strip() or settings.supabase_anon_key.strip()
        if not supabase_url or not api_key:
            raise ServiceUnavailableError("Password reset is unavailable.")

        request_url = f"{supabase_url.rstrip('/')}/auth/v1/recover"
        headers = {
            "apikey": api_key,
            "Content-Type": "application/json",
        }

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                response = await client.post(
                    request_url,
                    headers=headers,
                    json={"email": email},
                )
                response.raise_for_status()
        except httpx.HTTPError as exc:
            raise ExternalServiceError(
                "Supabase Auth",
                "Unable to start password reset.",
            ) from exc
