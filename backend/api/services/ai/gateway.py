"""Centralized AI gateway for provider/model routing and execution."""

from __future__ import annotations

import asyncio
import logging
import os
from collections.abc import AsyncIterator, Callable
from dataclasses import dataclass
from typing import Any

from anthropic import AsyncAnthropic
from google import genai
from google.genai import types

from api.config import Settings
from api.services.ai.policy import AICapabilityUnavailableError, AIPolicyService
from api.services.ai.registry import (
    AIProvider,
    get_default_model,
    is_provider_supported_for_capability,
    managed_default_provider,
)

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class TitleGenerationResult:
    """Structured title generation result."""

    raw_title: str
    provider: AIProvider
    used_managed_fallback: bool


@dataclass(frozen=True)
class TranscriptionResolution:
    """Resolved provider/model tuple for transcription."""

    provider: AIProvider
    model: str
    used_managed_fallback: bool


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

    async def stream_chat_with_tools(
        self,
        *,
        message: str,
        conversation_history: list[dict[str, Any]] | None,
        system_prompt: str | None,
        allowed_skills: list[str] | None,
        tool_context: Any,
        settings_record: Any,
    ) -> AsyncIterator[dict[str, Any]]:
        """Route chat streaming through the selected provider."""
        policy = AIPolicyService.resolve_from_settings(settings_record)
        selection = AIPolicyService.select_provider("chat", policy)
        if selection.provider != "anthropic":
            raise AICapabilityUnavailableError(
                f"Provider '{selection.provider}' is not supported for chat in sideBar"
            )
        self._ensure_provider_key_available("anthropic")
        client = self._claude_client
        if client is None:
            from api.services.claude_client import ClaudeClient

            client = ClaudeClient(self._settings)

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
    ) -> TitleGenerationResult:
        """Generate title text using provider policy and graceful fallback."""
        policy = AIPolicyService.resolve_from_settings(settings_record)
        selection = AIPolicyService.select_provider("title", policy)
        prompt = (
            "Generate ONLY a 3-5 word title for this conversation.\n"
            "Output the title directly without quotes, punctuation, or prefixes.\n\n"
            f"User: {user_message[:200]}\n"
            f"Assistant: {assistant_message[:200]}\n\n"
            "Title:"
        )

        provider_order = self._title_provider_order(
            selected_provider=selection.provider,
            fallback_to_managed=policy.fallback_to_managed,
        )
        first_provider = selection.provider
        last_error: Exception | None = None

        for provider in provider_order:
            try:
                raw_title = await self._generate_title_with_provider(
                    provider=provider,
                    prompt=prompt,
                )
                return TitleGenerationResult(
                    raw_title=raw_title,
                    provider=provider,
                    used_managed_fallback=provider != first_provider,
                )
            except Exception as error:
                last_error = error
                logger.warning(
                    "Title generation provider failed",
                    extra={
                        "provider": provider,
                        "error_type": type(error).__name__,
                    },
                )
                if not policy.fallback_to_managed:
                    raise
                continue

        if last_error:
            raise last_error
        raise ValueError("No title provider available")

    def resolve_transcription(
        self,
        *,
        settings_record: Any,
        requested_model: str | None,
    ) -> TranscriptionResolution:
        """Resolve transcription provider/model under the active policy."""
        policy = AIPolicyService.resolve_from_settings(settings_record)
        selection = AIPolicyService.select_provider("audio_transcription", policy)
        if selection.provider != "openai":
            raise AICapabilityUnavailableError(
                "Provider "
                f"'{selection.provider}' is not supported for audio transcription"
            )
        self._ensure_provider_key_available("openai")
        model = requested_model or get_default_model(
            "openai",
            "audio_transcription",
            self._settings,
        )
        return TranscriptionResolution(
            provider="openai",
            model=model,
            used_managed_fallback=selection.used_managed_fallback,
        )

    def _title_provider_order(
        self, *, selected_provider: AIProvider, fallback_to_managed: bool
    ) -> list[AIProvider]:
        """Build ordered provider list for title generation attempts."""
        ordered: list[AIProvider] = [selected_provider]
        if not fallback_to_managed:
            return ordered

        managed = managed_default_provider("title")
        for provider in (managed, "anthropic", "google", "openai"):
            if provider in ordered:
                continue
            if is_provider_supported_for_capability(provider, "title"):
                ordered.append(provider)
        return ordered

    async def _generate_title_with_provider(
        self, *, provider: AIProvider, prompt: str
    ) -> str:
        """Generate a title with retries for a specific provider."""
        last_error: Exception | None = None
        for attempt in range(3):
            try:
                if provider == "google":
                    return await self._generate_title_google(prompt)
                if provider == "anthropic":
                    return await self._generate_title_anthropic(prompt)
                if provider == "openai":
                    return await self._generate_title_openai(prompt)
                raise ValueError(f"Unsupported provider for title: {provider}")
            except Exception as error:
                last_error = error
                if not self._is_retryable_error(error) or attempt == 2:
                    raise
                await asyncio.sleep(0.5 * (2**attempt))

        if last_error:
            raise last_error
        raise ValueError("Title generation failed without provider error")

    async def _generate_title_google(self, prompt: str) -> str:
        """Generate title with Google Gemini."""
        api_key = os.getenv("GOOGLE_API_KEY")
        if not api_key:
            raise ValueError("GOOGLE_API_KEY not configured")
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

    async def _generate_title_anthropic(self, prompt: str) -> str:
        """Generate title with Anthropic."""
        self._ensure_provider_key_available("anthropic")
        client = AsyncAnthropic(api_key=self._settings.anthropic_api_key)
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

    async def _generate_title_openai(self, prompt: str) -> str:
        """Generate title with OpenAI."""
        api_key = os.getenv("OPENAI_API_KEY")
        if not api_key:
            raise ValueError("OPENAI_API_KEY not configured")
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

    def _ensure_provider_key_available(self, provider: AIProvider) -> None:
        """Raise when a required managed provider key is unavailable."""
        if provider == "anthropic" and not self._settings.anthropic_api_key:
            raise ValueError("ANTHROPIC_API_KEY not configured")
        if provider == "google" and not os.getenv("GOOGLE_API_KEY"):
            raise ValueError("GOOGLE_API_KEY not configured")
        if provider == "openai" and not os.getenv("OPENAI_API_KEY"):
            raise ValueError("OPENAI_API_KEY not configured")

    @staticmethod
    def _is_retryable_error(error: Exception) -> bool:
        """Return False for common non-retryable provider/auth errors."""
        if isinstance(error, ValueError):
            return False
        error_name = error.__class__.__name__
        non_retryable = {"AuthenticationError", "PermissionDenied", "InvalidArgument"}
        return error_name not in non_retryable
