"""Provider key orchestration for user settings responses and BYOK endpoints."""

from __future__ import annotations

from typing import Any, cast

from fastapi import HTTPException

from api.services.ai.registry import VALID_AI_PROVIDERS, AIProvider
from api.services.user_ai_provider_key_service import UserAIProviderKeyService
from api.services.user_settings_service import UserSettingsService


class UserAIProviderSettingsService:
    """Service methods for provider-key status and CRUD payloads."""

    @staticmethod
    def _normalize_provider(value: Any) -> AIProvider | None:
        """Return a canonical provider value when valid."""
        if not isinstance(value, str):
            return None
        candidate = value.strip().lower()
        if candidate in VALID_AI_PROVIDERS:
            return cast(AIProvider, candidate)
        return None

    @staticmethod
    def _resolve_primary_provider(db, user_id: str) -> AIProvider | None:
        """Return the user's selected primary provider when configured."""
        settings_record = UserSettingsService.get_settings(db, user_id)
        return UserAIProviderSettingsService._normalize_provider(
            getattr(settings_record, "ai_primary_provider", None)
            if settings_record
            else None
        )

    @staticmethod
    def attach_primary_provider_key_status(
        db,
        *,
        user_id: str,
        payload: dict[str, Any],
    ) -> dict[str, Any]:
        """Attach selected primary provider key status fields to payload."""
        provider = UserAIProviderSettingsService._normalize_provider(
            payload.get("ai_primary_provider")
        )
        if provider is None:
            payload["ai_primary_provider_has_key"] = False
            payload["ai_primary_provider_key_last4"] = None
            return payload

        record = UserAIProviderKeyService.get_active_record(db, user_id, provider)
        payload["ai_primary_provider_has_key"] = record is not None
        payload["ai_primary_provider_key_last4"] = record.key_last4 if record else None
        return payload

    @staticmethod
    def get_provider_key_status(
        db,
        user_id: str,
        *,
        provider: str | None = None,
    ) -> dict[str, Any]:
        """Return BYOK status for a provider or the selected primary provider."""
        selected_provider = (
            UserAIProviderSettingsService._resolve_primary_provider(db, user_id)
            if provider is None
            else UserAIProviderSettingsService._normalize_provider(provider)
        )
        if provider is not None and selected_provider is None:
            raise HTTPException(status_code=400, detail="provider required")
        if selected_provider is None:
            return {"provider": None, "has_key": False, "key_last4": None}

        record = UserAIProviderKeyService.get_active_record(
            db,
            user_id,
            selected_provider,
        )
        return {
            "provider": selected_provider,
            "has_key": record is not None,
            "key_last4": record.key_last4 if record else None,
        }

    @staticmethod
    def upsert_provider_key(
        db,
        user_id: str,
        *,
        provider: str,
        api_key: str,
    ) -> dict[str, Any]:
        """Create or update a BYOK provider key."""
        selected_provider = UserAIProviderSettingsService._normalize_provider(provider)
        if selected_provider is None:
            raise HTTPException(status_code=400, detail="provider required")

        normalized_key = api_key.strip()
        if not normalized_key:
            raise HTTPException(status_code=400, detail="api_key required")

        record = UserAIProviderKeyService.upsert_key(
            db,
            user_id=user_id,
            provider=selected_provider,
            api_key=normalized_key,
        )
        return {
            "provider": selected_provider,
            "has_key": True,
            "key_last4": record.key_last4,
        }

    @staticmethod
    def delete_provider_key(
        db,
        user_id: str,
        *,
        provider: str | None = None,
    ) -> dict[str, Any]:
        """Soft delete a BYOK provider key."""
        selected_provider = (
            UserAIProviderSettingsService._resolve_primary_provider(db, user_id)
            if provider is None
            else UserAIProviderSettingsService._normalize_provider(provider)
        )
        if provider is not None and selected_provider is None:
            raise HTTPException(status_code=400, detail="provider required")
        if selected_provider is None:
            return {"provider": None, "has_key": False, "key_last4": None}

        UserAIProviderKeyService.soft_delete_key(db, user_id, selected_provider)
        return {"provider": selected_provider, "has_key": False, "key_last4": None}
