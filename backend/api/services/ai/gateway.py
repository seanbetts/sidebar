"""Centralized AI gateway for provider/model routing and execution."""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator, Callable
from dataclasses import dataclass
from typing import Any

from anthropic import AsyncAnthropic
from google import genai
from google.genai import types

from api.config import Settings
from api.services.ai.policy import (
    AICapabilityUnavailableError,
    AIPolicyService,
)
from api.services.ai.registry import (
    AIProvider,
    get_default_model,
    is_provider_supported_for_capability,
)

ProviderKeyLookup = Callable[[AIProvider], str | None]


@dataclass(frozen=True)
class TitleGenerationResult:
    """Structured title generation result."""

    raw_title: str
    provider: AIProvider


@dataclass(frozen=True)
class ChatResolution:
    """Resolved provider/model/key tuple for assistant chat."""

    provider: AIProvider
    model: str
    api_key: str


@dataclass(frozen=True)
class TranscriptionResolution:
    """Resolved provider/model tuple for transcription."""

    provider: AIProvider
    model: str
    api_key: str


class AIProviderGateway:
    """Single entry point for AI provider routing and model calls."""

    def __init__(
        self,
        app_settings: Settings,
        *,
        claude_client: Any | None = None,
        google_client_factory: Callable[..., Any] | None = None,
    ):
        """Initialize the gateway with app settings and provider clients."""
        self._settings = app_settings
        self._claude_client = claude_client
        self._google_client_factory = google_client_factory or genai.Client

    def resolve_chat(
        self,
        *,
        settings_record: Any,
        provider_key_lookup: ProviderKeyLookup | None = None,
    ) -> ChatResolution:
        """Resolve provider/model/key for chat under the active policy."""
        policy = AIPolicyService.resolve_from_settings(settings_record)
        selection = AIPolicyService.select_provider("chat", policy)
        if selection.provider != "anthropic":
            raise AICapabilityUnavailableError(
                f"Provider '{selection.provider}' is not supported for chat in sideBar"
            )
        api_key = self._resolve_provider_api_key(
            provider=selection.provider,
            provider_key_lookup=provider_key_lookup,
        )
        model = get_default_model("anthropic", "chat", self._settings)
        return ChatResolution(
            provider=selection.provider,
            model=model,
            api_key=api_key,
        )

    async def stream_chat_with_tools(
        self,
        *,
        message: str,
        conversation_history: list[dict[str, Any]] | None,
        system_prompt: str | None,
        allowed_skills: list[str] | None,
        tool_context: Any,
        settings_record: Any,
        provider_key_lookup: ProviderKeyLookup | None = None,
        chat_resolution: ChatResolution | None = None,
    ) -> AsyncIterator[dict[str, Any]]:
        """Route chat streaming through the selected provider."""
        resolution = chat_resolution or self.resolve_chat(
            settings_record=settings_record,
            provider_key_lookup=provider_key_lookup,
        )
        if resolution.provider != "anthropic":
            raise AICapabilityUnavailableError(
                f"Provider '{resolution.provider}' is not supported for chat in sideBar"
            )
        client = self._claude_client
        if client is None:
            from api.services.claude_client import ClaudeClient

            client = ClaudeClient(
                self._settings,
                api_key=resolution.api_key,
                model=resolution.model,
            )

        async for event in client.stream_with_tools(
            message,
            conversation_history,
            system_prompt=system_prompt,
            allowed_skills=allowed_skills,
            tool_context=tool_context,
        ):
            yield event

    async def generate_title(
        self,
        *,
        user_message: str,
        assistant_message: str,
        settings_record: Any,
        preferred_provider: AIProvider | None = None,
        provider_key_lookup: ProviderKeyLookup | None = None,
    ) -> TitleGenerationResult:
        """Generate title text using strict BYOK provider policy."""
        policy = AIPolicyService.resolve_from_settings(settings_record)
        if preferred_provider is not None:
            if not is_provider_supported_for_capability(preferred_provider, "title"):
                raise AICapabilityUnavailableError(
                    "Provider "
                    f"'{preferred_provider}' is not supported for title generation"
                )
            selected_provider = preferred_provider
        else:
            selection = AIPolicyService.select_provider("title", policy)
            selected_provider = selection.provider

        prompt = (
            "Generate ONLY a 3-5 word title for this conversation.\n"
            "Output the title directly without quotes, punctuation, or prefixes.\n\n"
            f"User: {user_message[:200]}\n"
            f"Assistant: {assistant_message[:200]}\n\n"
            "Title:"
        )

        can_use_byok = policy.primary_provider == selected_provider or (
            preferred_provider is not None and policy.primary_provider is None
        )
        provider_lookup = (
            provider_key_lookup
            if can_use_byok or preferred_provider is not None
            else None
        )
        api_key = self._resolve_provider_api_key(
            provider=selected_provider,
            provider_key_lookup=provider_lookup,
        )
        raw_title = await self._generate_title_with_provider(
            provider=selected_provider,
            prompt=prompt,
            api_key=api_key,
        )
        return TitleGenerationResult(
            raw_title=raw_title,
            provider=selected_provider,
        )

    def resolve_transcription(
        self,
        *,
        settings_record: Any,
        requested_model: str | None,
        provider_key_lookup: ProviderKeyLookup | None = None,
    ) -> TranscriptionResolution:
        """Resolve transcription provider/model under the active policy."""
        policy = AIPolicyService.resolve_from_settings(settings_record)
        selection = AIPolicyService.select_provider("audio_transcription", policy)
        if selection.provider != "openai":
            raise AICapabilityUnavailableError(
                "Provider "
                f"'{selection.provider}' is not supported for audio transcription"
            )
        api_key = self._resolve_provider_api_key(
            provider="openai",
            provider_key_lookup=provider_key_lookup,
        )
        model = requested_model or get_default_model(
            "openai",
            "audio_transcription",
            self._settings,
        )
        return TranscriptionResolution(
            provider="openai",
            model=model,
            api_key=api_key,
        )

    async def _generate_title_with_provider(
        self,
        *,
        provider: AIProvider,
        prompt: str,
        api_key: str,
    ) -> str:
        """Generate a title with retries for a specific provider."""
        last_error: Exception | None = None
        for attempt in range(3):
            try:
                if provider == "google":
                    return await self._generate_title_google(prompt, api_key=api_key)
                if provider == "anthropic":
                    return await self._generate_title_anthropic(prompt, api_key=api_key)
                if provider == "openai":
                    return await self._generate_title_openai(prompt, api_key=api_key)
                raise ValueError(f"Unsupported provider for title: {provider}")
            except Exception as error:
                last_error = error
                if not self._is_retryable_error(error) or attempt == 2:
                    raise
                await asyncio.sleep(0.5 * (2**attempt))

        if last_error:
            raise last_error
        raise ValueError("Title generation failed without provider error")

    async def _generate_title_google(self, prompt: str, *, api_key: str) -> str:
        """Generate title with Google Gemini."""
        client = self._google_client_factory(api_key=api_key)
        response = client.models.generate_content(
            model=get_default_model("google", "title", self._settings),
            contents=prompt,
            config=types.GenerateContentConfig(
                temperature=0,
                max_output_tokens=20,
                response_mime_type="text/plain",
                automatic_function_calling=types.AutomaticFunctionCallingConfig(
                    disable=True
                ),
                thinking_config=types.ThinkingConfig(thinking_budget=0),
            ),
        )
        text = getattr(response, "text", None)
        if text:
            return text

        candidates = getattr(response, "candidates", None) or []
        for candidate in candidates:
            content = getattr(candidate, "content", None)
            parts = getattr(content, "parts", None) or []
            for part in parts:
                part_text = getattr(part, "text", None)
                if part_text:
                    return part_text
        return ""

    async def _generate_title_anthropic(self, prompt: str, *, api_key: str) -> str:
        """Generate title with Anthropic."""
        client = AsyncAnthropic(api_key=api_key)
        response = await client.messages.create(
            model=get_default_model("anthropic", "title", self._settings),
            max_tokens=20,
            temperature=0,
            messages=[{"role": "user", "content": prompt}],
        )
        for block in response.content:
            if getattr(block, "type", None) == "text":
                text_value = getattr(block, "text", "")
                if text_value:
                    return text_value
        return ""

    async def _generate_title_openai(self, prompt: str, *, api_key: str) -> str:
        """Generate title with OpenAI."""
        openai_module = __import__("openai")
        client = openai_module.AsyncOpenAI(api_key=api_key)
        response = await client.chat.completions.create(
            model=get_default_model("openai", "title", self._settings),
            messages=[
                {
                    "role": "system",
                    "content": (
                        "Generate concise 3-5 word conversation titles only. "
                        "Return plain title text with no punctuation or prefixes."
                    ),
                },
                {"role": "user", "content": prompt},
            ],
            temperature=0,
            max_tokens=20,
        )
        choice = response.choices[0] if response.choices else None
        if not choice:
            return ""
        return (choice.message.content or "").strip()

    def _resolve_provider_api_key(
        self,
        *,
        provider: AIProvider,
        provider_key_lookup: ProviderKeyLookup | None,
    ) -> str:
        """Resolve a user BYOK provider API key."""
        byok_key = provider_key_lookup(provider) if provider_key_lookup else None
        if isinstance(byok_key, str) and byok_key.strip():
            return byok_key.strip()

        raise ValueError(f"No API key configured for provider '{provider}'")

    @staticmethod
    def _is_retryable_error(error: Exception) -> bool:
        """Return False for common non-retryable provider/auth errors."""
        if isinstance(error, ValueError):
            return False
        error_name = error.__class__.__name__
        non_retryable = {"AuthenticationError", "PermissionDenied", "InvalidArgument"}
        return error_name not in non_retryable
