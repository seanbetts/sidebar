"""Claude API client with streaming and tool support."""

import ssl
from collections.abc import AsyncIterator
from typing import Any

import httpx
from anthropic import AsyncAnthropic

from api.config import Settings
from api.schemas.tool_context import ToolExecutionContext
from api.services.claude_streaming import stream_with_tools
from api.services.tool_mapper import ToolMapper


class ClaudeClient:
    """Handles Claude API interactions with streaming and tool execution."""

    def __init__(self, settings: Settings):
        """Initialize the client with model settings and HTTP configuration.

        Args:
            settings: Application settings object.
        """
        self.client = AsyncAnthropic(
            api_key=settings.anthropic_api_key,
            http_client=self._create_http_client(settings),
        )
        self.model = settings.model_name
        self.tool_mapper = ToolMapper()

    def _create_http_client(self, settings: Settings) -> httpx.AsyncClient:
        """Create HTTP client with SSL configuration.

        Args:
            settings: Application settings object.

        Returns:
            Configured HTTP client.
        """
        ssl_verify: bool | ssl.SSLContext = True
        ssl_context: ssl.SSLContext | None = None

        if (
            settings.app_env in {"local", "development", "dev", "test"}
            and settings.disable_ssl_verify
        ):
            ssl_context = ssl.create_default_context()
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl.CERT_NONE
        elif settings.custom_ca_bundle:
            ssl_context = ssl.create_default_context()
            ssl_context.load_verify_locations(cafile=settings.custom_ca_bundle)

        if ssl_context is not None:
            ssl_verify = ssl_context

        return httpx.AsyncClient(
            verify=ssl_verify,
            timeout=httpx.Timeout(60.0, connect=10.0),
        )

    async def stream_with_tools(
        self,
        message: str,
        conversation_history: list[dict[str, Any]] | None = None,
        system_prompt: str | None = None,
        allowed_skills: list[str] | None = None,
        tool_context: ToolExecutionContext | dict[str, Any] | None = None,
    ) -> AsyncIterator[dict[str, Any]]:
        """Stream model responses while handling tool calls.

        Args:
            message: User message text.
            conversation_history: Prior chat messages.
            system_prompt: Optional system prompt.
            allowed_skills: Optional list of enabled skills.
            tool_context: Optional tool execution context.

        Yields:
            Streaming events from the Claude client.
        """
        async for event in stream_with_tools(
            client=self.client,
            tool_mapper=self.tool_mapper,
            model=self.model,
            message=message,
            conversation_history=conversation_history,
            system_prompt=system_prompt,
            allowed_skills=allowed_skills,
            tool_context=tool_context,
        ):
            yield event
