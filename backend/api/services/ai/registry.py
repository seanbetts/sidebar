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
    "openai": {"chat", "title", "audio_transcription"},
    "google": {"chat", "title"},
}

_DEFAULT_MODELS: dict[tuple[AIProvider, AICapability], str] = {
    ("anthropic", "chat"): "claude-sonnet-4-6",
    ("anthropic", "title"): "claude-haiku-4-5",
    ("google", "chat"): "gemini-3.1-pro",
    ("google", "title"): "gemini-3-flash-preview",
    ("openai", "chat"): "gpt-5.2",
    ("openai", "title"): "gpt-5-nano",
    ("openai", "audio_transcription"): "gpt-4o-transcribe",
}

_DEFAULT_MODEL_ATTRS: dict[tuple[AIProvider, AICapability], str] = {
    ("anthropic", "chat"): "anthropic_chat_model",
    ("anthropic", "title"): "anthropic_title_model",
    ("google", "chat"): "google_chat_model",
    ("google", "title"): "google_title_model",
    ("openai", "chat"): "openai_chat_model",
    ("openai", "title"): "openai_title_model",
    ("openai", "audio_transcription"): "openai_transcription_model",
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
    attr = _DEFAULT_MODEL_ATTRS.get((provider, capability))
    if attr:
        configured = getattr(app_settings, attr, None)
        if isinstance(configured, str) and configured.strip():
            return configured.strip()

    model = _DEFAULT_MODELS.get((provider, capability))
    if not model:
        raise ValueError(f"No default model for {provider}:{capability}")
    return model
