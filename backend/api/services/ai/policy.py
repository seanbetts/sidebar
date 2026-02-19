"""AI provider policy resolution for per-user capability routing."""

from __future__ import annotations

from dataclasses import dataclass
from typing import cast

from api.services.ai.registry import (
    VALID_AI_PROVIDERS,
    AICapability,
    AIProvider,
    is_provider_supported_for_capability,
)


class AICapabilityUnavailableError(ValueError):
    """Raised when a capability is unavailable for the user's provider policy."""


@dataclass(frozen=True)
class AIUserPolicy:
    """Per-user AI routing policy."""

    primary_provider: AIProvider | None


@dataclass(frozen=True)
class ProviderSelection:
    """Selected provider for a capability under a given policy."""

    provider: AIProvider
    capability: AICapability


class AIPolicyService:
    """Resolve AI provider policy and capability routing decisions."""

    @staticmethod
    def resolve_from_settings(settings_record) -> AIUserPolicy:
        """Build a policy object from a user settings record."""
        raw_provider = (
            getattr(settings_record, "ai_primary_provider", None)
            if settings_record
            else None
        )
        provider: AIProvider | None = None
        if isinstance(raw_provider, str):
            candidate = raw_provider.strip().lower()
            if candidate in VALID_AI_PROVIDERS:
                provider = cast(AIProvider, candidate)

        return AIUserPolicy(primary_provider=provider)

    @staticmethod
    def select_provider(
        capability: AICapability, policy: AIUserPolicy
    ) -> ProviderSelection:
        """Select provider for a capability using strict BYOK rules."""
        primary = policy.primary_provider

        if not primary:
            raise AICapabilityUnavailableError(
                "No primary AI provider configured for strict BYOK mode"
            )

        if is_provider_supported_for_capability(primary, capability):
            return ProviderSelection(provider=primary, capability=capability)

        raise AICapabilityUnavailableError(
            f"Capability '{capability}' is unavailable for provider '{primary}'"
        )
