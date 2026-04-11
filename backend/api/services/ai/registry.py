"""Registry for supported AI providers, capabilities, and model compatibility."""

from __future__ import annotations

from typing import Any, Literal

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
    ("google", "chat"): "gemini-3.1-pro-preview",
    ("google", "title"): "gemini-3-flash-preview",
    ("openai", "chat"): "gpt-5.3-chat-latest",
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

_OPENAI_WEB_SEARCH_MODEL_PREFIXES: tuple[str, ...] = (
    "gpt-5",
    "gpt-4.1",
)
_GOOGLE_WEB_SEARCH_MODEL_PREFIXES: tuple[str, ...] = (
    "gemini-3.1-flash-image-preview",
    "gemini-3.1-pro-preview",
    "gemini-3-pro-image-preview",
    "gemini-3-flash-preview",
    "gemini-3",
    "gemini-2.5-pro",
    "gemini-2.5-flash",
    "gemini-2.5-flash-lite",
    "gemini-2.0-flash",
)
_GOOGLE_WEB_SEARCH_TOOL_COMBINATION_PREFIXES: tuple[str, ...] = ("gemini-3",)


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


def _normalized_model_name(model: str | None) -> str:
    """Return a normalized model identifier for compatibility checks."""
    if not isinstance(model, str):
        return ""
    return model.strip().lower()


def _matches_model_prefixes(model: str | None, prefixes: tuple[str, ...]) -> bool:
    """Return whether a normalized model name matches any supported prefix."""
    normalized = _normalized_model_name(model)
    return bool(normalized) and any(
        normalized.startswith(prefix) for prefix in prefixes
    )


def supports_openai_web_search(model: str | None) -> bool:
    """Return whether an OpenAI model supports built-in web search."""
    return _matches_model_prefixes(model, _OPENAI_WEB_SEARCH_MODEL_PREFIXES)


def supports_google_web_search(
    model: str | None,
    *,
    requires_tool_combination: bool = False,
) -> bool:
    """Return whether a Google model supports built-in web search."""
    if not _matches_model_prefixes(model, _GOOGLE_WEB_SEARCH_MODEL_PREFIXES):
        return False
    if not requires_tool_combination:
        return True
    return _matches_model_prefixes(
        model,
        _GOOGLE_WEB_SEARCH_TOOL_COMBINATION_PREFIXES,
    )


def build_web_search_fallback_summary(
    provider: AIProvider,
    model: str,
    *,
    requires_tool_combination: bool = False,
) -> dict[str, Any] | None:
    """Return provider-specific remediation when built-in web search is unsupported."""
    if provider == "openai":
        if supports_openai_web_search(model):
            return None
        return {
            "skill_id": "web-search",
            "availability_status": "provider_model_unsupported",
            "availability_reason": (
                f"Web Search is unavailable for OpenAI model '{model}'. "
                "sideBar will continue without web search. Switch to a GPT-5 "
                "or GPT-4.1 model to enable it."
            ),
            "availability_remediation": {
                "action": "switch_model",
                "provider": "openai",
            },
        }

    if provider == "google":
        if supports_google_web_search(
            model,
            requires_tool_combination=requires_tool_combination,
        ):
            return None
        if requires_tool_combination and supports_google_web_search(model):
            reason = (
                f"Web Search with other tools is unavailable for Google model "
                f"'{model}'. sideBar will continue without web search. Switch "
                "to a Gemini 3 model to enable combined search and tool use."
            )
        else:
            reason = (
                f"Web Search is unavailable for Google model '{model}'. "
                "sideBar will continue without web search. Switch to a supported "
                "Gemini model to enable it."
            )
        return {
            "skill_id": "web-search",
            "availability_status": "provider_model_unsupported",
            "availability_reason": reason,
            "availability_remediation": {
                "action": "switch_model",
                "provider": "google",
            },
        }

    return None
