"""Claude API client with streaming and tool support."""
import ssl
from typing import AsyncIterator, Dict, Any, List

import httpx
from anthropic import AsyncAnthropic

from api.config import Settings
from api.services.claude_streaming import stream_with_tools
from api.services.tool_mapper import ToolMapper


class ClaudeClient:
    """Handles Claude API interactions with streaming and tool execution."""

    def __init__(self, settings: Settings):
        """Initialize the client with model settings and HTTP configuration.

        Args:
            settings: Application settings object.
        """
        # Create custom httpx client that bypasses SSL verification
        # TEMPORARY WORKAROUND for corporate SSL interception
        # TODO: Replace with proper CA certificate installation
        ssl_context = ssl.create_default_context()
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl.CERT_NONE

        http_client = httpx.AsyncClient(
            verify=False,  # Disable SSL verification
            timeout=httpx.Timeout(60.0, connect=10.0)
        )

        self.client = AsyncAnthropic(
            api_key=settings.anthropic_api_key,
            http_client=http_client
        )
        self.model = settings.model_name
        self.tool_mapper = ToolMapper()

    async def stream_with_tools(
        self,
        message: str,
        conversation_history: List[Dict[str, Any]] = None,
        system_prompt: str | None = None,
        allowed_skills: List[str] | None = None,
        tool_context: Dict[str, Any] | None = None,
    ) -> AsyncIterator[Dict[str, Any]]:
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
