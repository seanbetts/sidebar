from types import SimpleNamespace

import pytest

from api.config import settings
from api.services.ai.gateway import AIProviderGateway
from api.services.ai.policy import (
    AICapabilityUnavailableError,
    AIPolicyService,
    AIUserPolicy,
)


def test_policy_defaults_to_managed_provider_when_unset() -> None:
    selection = AIPolicyService.select_provider(
        "audio_transcription",
        AIUserPolicy(primary_provider=None, fallback_to_managed=True),
    )
    assert selection.provider == "openai"
    assert selection.used_managed_fallback is True


def test_policy_requires_primary_provider_in_strict_mode_when_unset() -> None:
    with pytest.raises(AICapabilityUnavailableError):
        AIPolicyService.select_provider(
            "audio_transcription",
            AIUserPolicy(primary_provider=None, fallback_to_managed=False),
        )


def test_policy_uses_primary_provider_when_supported() -> None:
    selection = AIPolicyService.select_provider(
        "title",
        AIUserPolicy(primary_provider="anthropic", fallback_to_managed=True),
    )
    assert selection.provider == "anthropic"
    assert selection.used_managed_fallback is False


def test_policy_falls_back_to_managed_when_primary_unsupported() -> None:
    selection = AIPolicyService.select_provider(
        "chat",
        AIUserPolicy(primary_provider="openai", fallback_to_managed=True),
    )
    assert selection.provider == "anthropic"
    assert selection.used_managed_fallback is True


def test_policy_raises_when_primary_unsupported_and_fallback_disabled() -> None:
    with pytest.raises(AICapabilityUnavailableError):
        AIPolicyService.select_provider(
            "audio_transcription",
            AIUserPolicy(primary_provider="google", fallback_to_managed=False),
        )


def test_gateway_resolves_transcription_default_model() -> None:
    gateway = AIProviderGateway(settings)
    resolution = gateway.resolve_transcription(
        settings_record=SimpleNamespace(
            ai_primary_provider=None,
            ai_fallback_to_managed=True,
        ),
        requested_model=None,
    )
    assert resolution.provider == "openai"
    assert resolution.model == "gpt-4o-transcribe"


def test_policy_resolve_from_settings_defaults_to_strict_mode() -> None:
    policy = AIPolicyService.resolve_from_settings(None)
    assert policy.primary_provider is None
    assert policy.fallback_to_managed is False


def test_gateway_resolve_transcription_respects_strict_policy() -> None:
    gateway = AIProviderGateway(settings)
    with pytest.raises(AICapabilityUnavailableError):
        gateway.resolve_transcription(
            settings_record=SimpleNamespace(
                ai_primary_provider="google",
                ai_fallback_to_managed=False,
            ),
            requested_model=None,
        )
