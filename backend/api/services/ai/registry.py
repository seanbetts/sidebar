"""Registry for supported AI providers, capabilities, and default models."""

from __future__ import annotations

from typing import Literal

from api.config import Settings

AIProvider = Literal["anthropic", "openai", "google"]
AICapability = Literal["chat", "title", "audio_transcription"]

VALID_AI_PROVIDERS: tuple[AIProvider, ...] = ("anthropic", "openai", "google")

# "Supported" here means supported by sideBar's current implementation.
_SUPPORTED_PROVIDER_CAPABILITIES: dict[AIProvider, set[AICapability]] = {
    "anthropic": {"chat", "title"},
    "openai": {"title", "audio_transcription"},
    "google": {"title"},
}

_DEFAULT_MODELS: dict[tuple[AIProvider, AICapability], str] = {
    ("google", "title"): "gemini-3-flash-preview",
    ("openai", "title"): "gpt-4o-mini",
    ("openai", "audio_transcription"): "gpt-4o-transcribe",
}


def is_provider_supported_for_capability(
    provider: AIProvider, capability: AICapability
) -> bool:
    """Return True when sideBar supports this provider/capability pair."""
    return capability in _SUPPORTED_PROVIDER_CAPABILITIES.get(provider, set())


def get_default_model(
    provider: AIProvider, capability: AICapability, app_settings: Settings
) -> str:
    """Return the default model for a provider/capability pair."""
    if provider == "anthropic" and capability in {"chat", "title"}:
        return app_settings.model_name

    model = _DEFAULT_MODELS.get((provider, capability))
    if not model:
        raise ValueError(f"No default model for {provider}:{capability}")
    return model
