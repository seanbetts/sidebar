"""Runtime availability helpers for connection-backed skills."""

from __future__ import annotations

from typing import Any, cast

from sqlalchemy.orm import Session

from api.services.ai.registry import AIProvider
from api.services.user_ai_provider_key_service import UserAIProviderKeyService

_PROVIDER_LABELS: dict[str, str] = {
    "anthropic": "Anthropic",
    "openai": "OpenAI",
}


class ExternalConnectionAvailabilityService:
    """Compute compact skill availability summaries from current connection state."""

    @staticmethod
    def _required_provider_keys(skill_entry: dict[str, Any]) -> list[AIProvider]:
        requirements = skill_entry.get("credential_requirements")
        if not isinstance(requirements, list):
            return []

        required: list[AIProvider] = []
        seen: set[AIProvider] = set()
        for requirement in requirements:
            if not isinstance(requirement, dict):
                continue
            if not bool(requirement.get("required", False)):
                continue
            if str(requirement.get("key_kind", "api_key")).strip().lower() != "api_key":
                continue
            provider = requirement.get("provider")
            if not isinstance(provider, str):
                continue
            normalized_provider = provider.strip().lower()
            if normalized_provider in _PROVIDER_LABELS:
                typed_provider = cast(AIProvider, normalized_provider)
                if typed_provider not in seen:
                    required.append(typed_provider)
                    seen.add(typed_provider)
        return required

    @staticmethod
    def _provider_label(provider: AIProvider) -> str:
        return _PROVIDER_LABELS.get(provider, provider.title())

    @classmethod
    def resolve_skill_availability(
        cls,
        db: Session,
        *,
        user_id: str,
        skill_entry: dict[str, Any],
    ) -> tuple[str, str | None, dict[str, Any] | None]:
        """Return runtime availability fields for one skill."""
        required_providers = cls._required_provider_keys(skill_entry)
        if not required_providers:
            return "ready", None, None

        for provider in required_providers:
            if UserAIProviderKeyService.has_active_key(db, user_id, provider):
                continue
            return (
                "needs_connection",
                f"Missing required {cls._provider_label(provider)} connection.",
                {
                    "action": "add_provider_key",
                    "provider": provider,
                },
            )
        return "ready", None, None
