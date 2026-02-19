from types import SimpleNamespace

import pytest

from api.config import settings
from api.services.ai.gateway import AIProviderGateway
from api.services.ai.policy import (
    AICapabilityUnavailableError,
    AIPolicyService,
    AIUserPolicy,
)


def test_policy_requires_primary_provider_when_unset() -> None:
    with pytest.raises(AICapabilityUnavailableError):
        AIPolicyService.select_provider(
            "audio_transcription",
            AIUserPolicy(primary_provider=None),
        )


def test_policy_uses_primary_provider_when_supported() -> None:
    selection = AIPolicyService.select_provider(
        "title",
        AIUserPolicy(primary_provider="anthropic"),
    )
    assert selection.provider == "anthropic"


def test_policy_raises_when_primary_unsupported() -> None:
    with pytest.raises(AICapabilityUnavailableError):
        AIPolicyService.select_provider(
            "audio_transcription",
            AIUserPolicy(primary_provider="google"),
        )


def test_gateway_resolves_transcription_default_model() -> None:
    gateway = AIProviderGateway(settings)
    resolution = gateway.resolve_transcription(
        settings_record=SimpleNamespace(
            ai_primary_provider="openai",
        ),
        requested_model=None,
        provider_key_lookup=lambda _provider: "sk-openai-test-key",
    )
    assert resolution.provider == "openai"
    assert resolution.model == "gpt-4o-transcribe"


def test_policy_resolve_from_settings_defaults_to_strict_mode() -> None:
    policy = AIPolicyService.resolve_from_settings(None)
    assert policy.primary_provider is None


def test_gateway_resolve_transcription_respects_strict_policy() -> None:
    gateway = AIProviderGateway(settings)
    with pytest.raises(AICapabilityUnavailableError):
        gateway.resolve_transcription(
            settings_record=SimpleNamespace(
                ai_primary_provider="google",
            ),
            requested_model=None,
            provider_key_lookup=lambda _provider: "sk-openai-test-key",
        )
