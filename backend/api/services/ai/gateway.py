"""Centralized AI gateway for provider/model routing and execution."""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator, Callable
from dataclasses import dataclass
from typing import Any

from google import genai
from google.genai import types

from api.config import Settings
from api.schemas.tool_context import ToolExecutionContext
from api.services.ai.policy import (
    AICapabilityUnavailableError,
    AIPolicyService,
)
from api.services.ai.registry import (
    AIProvider,
    get_default_model,
    is_provider_supported_for_capability,
)
from api.services.ai.tool_orchestrator import ProviderToolOrchestrator

ProviderKeyLookup = Callable[[AIProvider], str | None]


@dataclass(frozen=True)
class TitleGenerationResult:
    """Structured title generation result."""

    raw_title: str
    provider: AIProvider


@dataclass(frozen=True)
class PromptGenerationResult:
    """Structured single-shot prompt generation result."""

    raw_text: str
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
        openai_client_factory: Callable[..., Any] | None = None,
    ):
        """Initialize the gateway with app settings and provider clients."""
        self._settings = app_settings
        self._claude_client = claude_client
        self._google_client_factory = google_client_factory or genai.Client
        self._openai_client_factory = (
            openai_client_factory or self._default_openai_client_factory
        )
        self._tool_mapper: Any | None = None

    def resolve_chat(
        self,
        *,
        settings_record: Any,
        provider_key_lookup: ProviderKeyLookup | None = None,
    ) -> ChatResolution:
        """Resolve provider/model/key for chat under the active policy."""
        policy = AIPolicyService.resolve_from_settings(settings_record)
        selection = AIPolicyService.select_provider("chat", policy)
        api_key = self._resolve_provider_api_key(
            provider=selection.provider,
            provider_key_lookup=provider_key_lookup,
        )
        model = get_default_model(selection.provider, "chat", self._settings)
        return ChatResolution(
            provider=selection.provider,
            model=model,
            api_key=api_key,
        )

    def get_chat_tool_definitions(
        self,
        allowed_skills: list[str] | None = None,
    ) -> list[dict[str, Any]]:
        """Return canonical chat tool definitions for the allowed skills."""
        return self._get_tool_mapper().get_claude_tools(allowed_skills)

    async def stream_chat_with_tools(
        self,
        *,
        message: str,
        conversation_history: list[dict[str, Any]] | None,
        system_prompt: str | None,
        allowed_skills: list[str] | None,
        tool_context: Any,
        settings_record: Any,
        tool_definitions: list[dict[str, Any]] | None = None,
        provider_key_lookup: ProviderKeyLookup | None = None,
        chat_resolution: ChatResolution | None = None,
    ) -> AsyncIterator[dict[str, Any]]:
        """Route chat streaming through the selected provider."""
        resolution = chat_resolution or self.resolve_chat(
            settings_record=settings_record,
            provider_key_lookup=provider_key_lookup,
        )
        tool_mapper = self._get_tool_mapper()
        resolved_allowed_skills = allowed_skills
        if (
            tool_definitions
            and not resolved_allowed_skills
            and hasattr(tool_mapper, "get_skill_ids_for_tool_definitions")
        ):
            resolved_allowed_skills = tool_mapper.get_skill_ids_for_tool_definitions(
                tool_definitions
            )
        if resolution.provider == "anthropic":
            claude_client = self._claude_client
            owns_client = False
            if claude_client is None:
                from api.services.claude_client import ClaudeClient

                claude_client = ClaudeClient(
                    self._settings,
                    api_key=resolution.api_key,
                    model=resolution.model,
                )
                owns_client = True

            try:
                async for event in claude_client.stream_with_tools(
                    message,
                    conversation_history,
                    system_prompt=system_prompt,
                    allowed_skills=resolved_allowed_skills,
                    tool_context=tool_context,
                ):
                    yield event
            finally:
                if owns_client:
                    await self._close_async_client_if_possible(
                        getattr(claude_client, "client", None)
                    )
            return

        if resolution.provider == "openai":
            async for event in self._stream_chat_openai(
                message=message,
                conversation_history=conversation_history,
                system_prompt=system_prompt,
                allowed_skills=resolved_allowed_skills,
                tool_definitions=tool_definitions,
                tool_context=tool_context,
                tool_mapper=tool_mapper,
                model=resolution.model,
                api_key=resolution.api_key,
            ):
                yield event
            return

        if resolution.provider == "google":
            async for event in self._stream_chat_google(
                message=message,
                conversation_history=conversation_history,
                system_prompt=system_prompt,
                allowed_skills=resolved_allowed_skills,
                tool_definitions=tool_definitions,
                tool_context=tool_context,
                tool_mapper=tool_mapper,
                model=resolution.model,
                api_key=resolution.api_key,
            ):
                yield event
            return

        raise AICapabilityUnavailableError(
            f"Provider '{resolution.provider}' is not supported for chat in sideBar"
        )

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

    async def generate_text(
        self,
        *,
        prompt: str,
        settings_record: Any,
        system_prompt: str | None = None,
        preferred_provider: AIProvider | None = None,
        provider_key_lookup: ProviderKeyLookup | None = None,
        max_output_tokens: int = 800,
        temperature: float = 0.3,
    ) -> PromptGenerationResult:
        """Generate a single non-streaming text response using the chat provider."""
        policy = AIPolicyService.resolve_from_settings(settings_record)
        if preferred_provider is not None:
            if not is_provider_supported_for_capability(preferred_provider, "chat"):
                raise AICapabilityUnavailableError(
                    "Provider "
                    f"'{preferred_provider}' is not supported for text generation"
                )
            selected_provider = preferred_provider
        else:
            selection = AIPolicyService.select_provider("chat", policy)
            selected_provider = selection.provider

        api_key = self._resolve_provider_api_key(
            provider=selected_provider,
            provider_key_lookup=provider_key_lookup,
        )
        raw_text = await self._generate_text_with_provider(
            provider=selected_provider,
            prompt=prompt,
            api_key=api_key,
            model=get_default_model(selected_provider, "chat", self._settings),
            system_prompt=system_prompt,
            max_output_tokens=max_output_tokens,
            temperature=temperature,
        )
        return PromptGenerationResult(
            raw_text=raw_text,
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
                    raw_title = await self._generate_title_google(
                        prompt, api_key=api_key
                    )
                elif provider == "anthropic":
                    raw_title = await self._generate_title_anthropic(
                        prompt, api_key=api_key
                    )
                elif provider == "openai":
                    raw_title = await self._generate_title_openai(
                        prompt, api_key=api_key
                    )
                else:
                    raise ValueError(f"Unsupported provider for title: {provider}")

                cleaned_title = raw_title.strip()
                if cleaned_title:
                    return cleaned_title
                raise RuntimeError(f"Empty title response from provider '{provider}'")
            except Exception as error:
                last_error = error
                if not self._is_retryable_error(error) or attempt == 2:
                    raise
                await asyncio.sleep(0.5 * (2**attempt))

        if last_error:
            raise last_error
        raise ValueError("Title generation failed without provider error")

    async def _generate_text_with_provider(
        self,
        *,
        provider: AIProvider,
        prompt: str,
        api_key: str,
        model: str,
        system_prompt: str | None,
        max_output_tokens: int,
        temperature: float,
    ) -> str:
        """Generate plain text with retries for a specific provider."""
        last_error: Exception | None = None
        for attempt in range(3):
            try:
                if provider == "google":
                    raw_text = await self._generate_text_google(
                        prompt,
                        api_key=api_key,
                        model=model,
                        system_prompt=system_prompt,
                        max_output_tokens=max_output_tokens,
                        temperature=temperature,
                    )
                elif provider == "anthropic":
                    raw_text = await self._generate_text_anthropic(
                        prompt,
                        api_key=api_key,
                        model=model,
                        system_prompt=system_prompt,
                        max_output_tokens=max_output_tokens,
                        temperature=temperature,
                    )
                elif provider == "openai":
                    raw_text = await self._generate_text_openai(
                        prompt,
                        api_key=api_key,
                        model=model,
                        system_prompt=system_prompt,
                        max_output_tokens=max_output_tokens,
                        temperature=temperature,
                    )
                else:
                    raise ValueError(
                        f"Unsupported provider for text generation: {provider}"
                    )

                cleaned_text = raw_text.strip()
                if cleaned_text:
                    return cleaned_text
                raise RuntimeError(
                    f"Empty text generation response from provider '{provider}'"
                )
            except Exception as error:
                last_error = error
                if not self._is_retryable_error(error) or attempt == 2:
                    raise
                await asyncio.sleep(0.5 * (2**attempt))

        if last_error:
            raise last_error
        raise ValueError("Text generation failed without provider error")

    async def _generate_title_google(self, prompt: str, *, api_key: str) -> str:
        """Generate title with Google Gemini."""
        client = self._google_client_factory(api_key=api_key)
        response = client.models.generate_content(
            model=get_default_model("google", "title", self._settings),
            contents=prompt,
            config=types.GenerateContentConfig(
                temperature=0,
                max_output_tokens=64,
                response_mime_type="text/plain",
                thinking_config=types.ThinkingConfig(thinking_budget=0),
            ),
        )
        text = getattr(response, "text", None)
        if text:
            return text.strip()

        candidates = getattr(response, "candidates", None) or []
        for candidate in candidates:
            content = getattr(candidate, "content", None)
            parts = getattr(content, "parts", None) or []
            for part in parts:
                part_text = getattr(part, "text", None)
                if part_text:
                    return part_text.strip()
        return ""

    async def _generate_text_google(
        self,
        prompt: str,
        *,
        api_key: str,
        model: str,
        system_prompt: str | None,
        max_output_tokens: int,
        temperature: float,
    ) -> str:
        """Generate plain text with Google Gemini."""
        client = self._google_client_factory(api_key=api_key)
        contents = prompt
        if isinstance(system_prompt, str) and system_prompt.strip():
            contents = f"{system_prompt.strip()}\n\n{prompt}"
        response = client.models.generate_content(
            model=model,
            contents=contents,
            config=types.GenerateContentConfig(
                temperature=temperature,
                max_output_tokens=max_output_tokens,
                response_mime_type="text/plain",
                thinking_config=types.ThinkingConfig(thinking_budget=0),
            ),
        )
        text = getattr(response, "text", None)
        if text:
            return text.strip()

        candidates = getattr(response, "candidates", None) or []
        for candidate in candidates:
            content = getattr(candidate, "content", None)
            parts = getattr(content, "parts", None) or []
            for part in parts:
                part_text = getattr(part, "text", None)
                if part_text:
                    return part_text.strip()
        return ""

    async def _generate_title_anthropic(self, prompt: str, *, api_key: str) -> str:
        """Generate title with Anthropic."""
        from api.services.claude_client import ClaudeClient

        claude_client = ClaudeClient(
            self._settings,
            api_key=api_key,
            model=get_default_model("anthropic", "title", self._settings),
        )
        client = claude_client.client
        try:
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
        finally:
            await self._close_async_client_if_possible(client)
        return ""

    async def _generate_text_anthropic(
        self,
        prompt: str,
        *,
        api_key: str,
        model: str,
        system_prompt: str | None,
        max_output_tokens: int,
        temperature: float,
    ) -> str:
        """Generate plain text with Anthropic."""
        from api.services.claude_client import ClaudeClient

        claude_client = ClaudeClient(
            self._settings,
            api_key=api_key,
            model=model,
        )
        client = claude_client.client
        request_kwargs: dict[str, Any] = {
            "model": model,
            "max_tokens": max_output_tokens,
            "temperature": temperature,
            "messages": [{"role": "user", "content": prompt}],
        }
        if isinstance(system_prompt, str) and system_prompt.strip():
            request_kwargs["system"] = system_prompt.strip()
        try:
            response = await client.messages.create(**request_kwargs)
            for block in response.content:
                if getattr(block, "type", None) == "text":
                    text_value = getattr(block, "text", "")
                    if text_value:
                        return text_value
        finally:
            await self._close_async_client_if_possible(client)
        return ""

    async def _generate_title_openai(self, prompt: str, *, api_key: str) -> str:
        """Generate title with OpenAI."""
        client = self._openai_client_factory(api_key=api_key)
        model = get_default_model("openai", "title", self._settings)
        request_kwargs: dict[str, Any] = {
            "model": model,
            "messages": [
                {
                    "role": "system",
                    "content": (
                        "Generate concise 3-5 word conversation titles only. "
                        "Return plain title text with no punctuation or prefixes."
                    ),
                },
                {"role": "user", "content": prompt},
            ],
        }
        if model.startswith("gpt-5"):
            request_kwargs["max_completion_tokens"] = 64
            request_kwargs["reasoning_effort"] = "minimal"
        else:
            request_kwargs["temperature"] = 0
            request_kwargs["max_tokens"] = 20

        try:
            response = await client.chat.completions.create(
                **request_kwargs,
            )
            choice = response.choices[0] if response.choices else None
            if not choice:
                return ""
            return (choice.message.content or "").strip()
        finally:
            await self._close_async_client_if_possible(client)

    async def _generate_text_openai(
        self,
        prompt: str,
        *,
        api_key: str,
        model: str,
        system_prompt: str | None,
        max_output_tokens: int,
        temperature: float,
    ) -> str:
        """Generate plain text with OpenAI."""
        client = self._openai_client_factory(api_key=api_key)
        request_kwargs: dict[str, Any] = {
            "model": model,
            "messages": [],
        }
        if isinstance(system_prompt, str) and system_prompt.strip():
            request_kwargs["messages"].append(
                {"role": "system", "content": system_prompt.strip()}
            )
        request_kwargs["messages"].append({"role": "user", "content": prompt})
        if model.startswith("gpt-5"):
            request_kwargs["max_completion_tokens"] = max_output_tokens
            request_kwargs["reasoning_effort"] = "minimal"
        else:
            request_kwargs["temperature"] = temperature
            request_kwargs["max_tokens"] = max_output_tokens

        try:
            response = await client.chat.completions.create(**request_kwargs)
            choice = response.choices[0] if response.choices else None
            if not choice:
                return ""
            return (choice.message.content or "").strip()
        finally:
            await self._close_async_client_if_possible(client)

    async def _stream_chat_openai(
        self,
        *,
        message: str,
        conversation_history: list[dict[str, Any]] | None,
        system_prompt: str | None,
        allowed_skills: list[str] | None,
        tool_context: Any,
        tool_mapper: Any,
        model: str,
        api_key: str,
        tool_definitions: list[dict[str, Any]] | None = None,
    ) -> AsyncIterator[dict[str, Any]]:
        """Stream assistant tokens from OpenAI chat completions."""
        client = self._openai_client_factory(api_key=api_key)
        try:
            orchestrator = ProviderToolOrchestrator(
                tool_mapper=tool_mapper,
                allowed_skills=allowed_skills,
                tool_definitions=tool_definitions,
                tool_context=self._normalize_tool_context(tool_context),
            )
            async for event in orchestrator.run_openai(
                client=client,
                model=model,
                message=message,
                conversation_history=conversation_history,
                system_prompt=system_prompt,
            ):
                yield event
        finally:
            await self._close_async_client_if_possible(client)

    async def _stream_chat_google(
        self,
        *,
        message: str,
        conversation_history: list[dict[str, Any]] | None,
        system_prompt: str | None,
        allowed_skills: list[str] | None,
        tool_context: Any,
        tool_mapper: Any,
        model: str,
        api_key: str,
        tool_definitions: list[dict[str, Any]] | None = None,
    ) -> AsyncIterator[dict[str, Any]]:
        """Generate assistant tokens from Google chat (single-response stream shim)."""
        client = self._google_client_factory(api_key=api_key)
        orchestrator = ProviderToolOrchestrator(
            tool_mapper=tool_mapper,
            allowed_skills=allowed_skills,
            tool_definitions=tool_definitions,
            tool_context=self._normalize_tool_context(tool_context),
        )
        async for event in orchestrator.run_google(
            client=client,
            model=model,
            message=message,
            conversation_history=conversation_history,
            system_prompt=system_prompt,
        ):
            yield event

    @staticmethod
    def _default_openai_client_factory(*, api_key: str) -> Any:
        """Build an AsyncOpenAI client instance."""
        openai_module = __import__("openai")
        return openai_module.AsyncOpenAI(api_key=api_key)

    def _get_tool_mapper(self) -> Any:
        """Lazily construct a tool mapper to avoid import cycles."""
        if self._tool_mapper is None:
            from api.services.agent.tools.mapper import ToolMapper

            self._tool_mapper = ToolMapper()
        return self._tool_mapper

    @staticmethod
    def _normalize_tool_context(tool_context: Any) -> dict[str, Any] | None:
        """Convert tool context payloads to dictionary form."""
        if tool_context is None:
            return None
        if isinstance(tool_context, ToolExecutionContext):
            return tool_context.to_dict()
        if isinstance(tool_context, dict):
            return tool_context
        return None

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

    @staticmethod
    async def _close_async_client_if_possible(client: Any | None) -> None:
        """Close provider SDK clients when they expose an async close method."""
        if client is None:
            return
        close_method = getattr(client, "close", None)
        if not callable(close_method):
            return
        try:
            close_result = close_method()
            if asyncio.iscoroutine(close_result):
                await close_result
        except Exception:
            # Avoid surfacing close-time cleanup errors to request flows.
            return
