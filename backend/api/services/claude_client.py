"""Claude API client with streaming and tool support."""
import json
import ssl
from typing import AsyncIterator, Dict, Any, List
from anthropic import AsyncAnthropic
import httpx
from api.config import Settings
from api.services.tool_mapper import ToolMapper


class ClaudeClient:
    """Handles Claude API interactions with streaming and tool execution."""

    def __init__(self, settings: Settings):
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
        system_prompt: str | None = None
    ) -> AsyncIterator[Dict[str, Any]]:
        """
        Stream chat with tool execution and multi-turn conversation.

        Args:
            message: User message
            conversation_history: Previous messages (optional)

        Yields:
            Events: token, tool_call, tool_result, error
        """
        # Build messages list
        messages = conversation_history or []
        messages.append({"role": "user", "content": message})

        # Get Claude tools from mapper
        tools = self.tool_mapper.get_claude_tools()

        # Allow up to 5 tool use rounds to prevent infinite loops
        max_rounds = 5
        current_round = 0

        try:
            while current_round < max_rounds:
                current_round += 1

                stream_args = {
                    "model": self.model,
                    "max_tokens": 4096,
                    "messages": messages,
                    "tools": tools,
                }
                if system_prompt:
                    stream_args["system"] = system_prompt

                async with self.client.messages.stream(**stream_args) as stream:
                    # Track content blocks for building assistant message
                    content_blocks = []
                    tool_uses = []
                    current_text = ""

                    async for event in stream:
                        if event.type == "content_block_start":
                            if hasattr(event.content_block, "type"):
                                if event.content_block.type == "text":
                                    # New text block
                                    current_text = ""
                                elif event.content_block.type == "tool_use":
                                    # Tool use started
                                    tool_uses.append({
                                        "id": event.content_block.id,
                                        "name": event.content_block.name,
                                        "input": {},
                                        "input_partial": ""
                                    })

                        elif event.type == "content_block_delta":
                            if hasattr(event.delta, "type"):
                                if event.delta.type == "text_delta":
                                    # Accumulate and stream text token
                                    current_text += event.delta.text
                                    yield {
                                        "type": "token",
                                        "content": event.delta.text
                                    }
                                elif event.delta.type == "input_json_delta":
                                    # Tool input being streamed
                                    if tool_uses:
                                        tool_uses[-1]["input_partial"] += event.delta.partial_json

                        elif event.type == "content_block_stop":
                            # Content block finished - save to content_blocks
                            if current_text:
                                content_blocks.append({
                                    "type": "text",
                                    "text": current_text
                                })
                                current_text = ""

                        elif event.type == "message_stop":
                            # Message complete - check if we have tools to execute
                            if not tool_uses:
                                # No tools used - conversation complete
                                return

                            # Parse tool inputs
                            for tool_use in tool_uses:
                                try:
                                    if tool_use["input_partial"]:
                                        tool_use["input"] = json.loads(tool_use["input_partial"])
                                except json.JSONDecodeError:
                                    tool_use["input"] = {}

                                # Add tool use to content blocks
                                content_blocks.append({
                                    "type": "tool_use",
                                    "id": tool_use["id"],
                                    "name": tool_use["name"],
                                    "input": tool_use["input"]
                                })

                            # Add assistant message with tool uses to conversation
                            messages.append({
                                "role": "assistant",
                                "content": content_blocks
                            })

                            # Execute tools and build tool result messages
                            tool_results = []
                            for tool_use in tool_uses:
                                # Announce tool call
                                yield {
                                    "type": "tool_call",
                                    "id": tool_use["id"],
                                    "name": tool_use["name"],
                                    "parameters": tool_use["input"],
                                    "status": "pending"
                                }

                                # Execute tool
                                result = await self.tool_mapper.execute_tool(
                                    tool_use["name"],
                                    tool_use["input"]
                                )

                                # Return result
                                status = "success" if result.get("success") else "error"
                                yield {
                                    "type": "tool_result",
                                    "id": tool_use["id"],
                                    "name": tool_use["name"],
                                    "result": result,
                                    "status": status
                                }

                                if result.get("success"):
                                    result_data = result.get("data") or {}
                                    if tool_use["name"] == "Create Note":
                                        yield {
                                            "type": "note_created",
                                            "data": {
                                                "id": result_data.get("id"),
                                                "title": result_data.get("title"),
                                                "folder": result_data.get("folder")
                                            }
                                        }
                                    elif tool_use["name"] == "Update Note":
                                        yield {
                                            "type": "note_updated",
                                            "data": {
                                                "id": result_data.get("id"),
                                                "title": result_data.get("title")
                                            }
                                        }
                                    elif tool_use["name"] == "Save Website":
                                        yield {
                                            "type": "website_saved",
                                            "data": {
                                                "id": result_data.get("id"),
                                                "title": result_data.get("title"),
                                                "url": result_data.get("url")
                                            }
                                        }
                                    elif tool_use["name"] == "Delete Note":
                                        yield {
                                            "type": "note_deleted",
                                            "data": {
                                                "id": result_data.get("id")
                                            }
                                        }
                                    elif tool_use["name"] == "Delete Website":
                                        yield {
                                            "type": "website_deleted",
                                            "data": {
                                                "id": result_data.get("id")
                                            }
                                        }
                                    elif tool_use["name"] == "Set UI Theme":
                                        yield {
                                            "type": "ui_theme_set",
                                            "data": {
                                                "theme": result_data.get("theme")
                                            }
                                        }
                                    elif tool_use["name"] == "Update Scratchpad":
                                        yield {
                                            "type": "scratchpad_updated",
                                            "data": {
                                                "id": result_data.get("id")
                                            }
                                        }
                                    elif tool_use["name"] == "Clear Scratchpad":
                                        yield {
                                            "type": "scratchpad_cleared",
                                            "data": {
                                                "id": result_data.get("id")
                                            }
                                        }

                                # Add to tool results for next turn
                                tool_results.append({
                                    "type": "tool_result",
                                    "tool_use_id": tool_use["id"],
                                    "content": json.dumps(result)
                                })

                            # Add tool results as user message for next turn
                            messages.append({
                                "role": "user",
                                "content": tool_results
                            })

                            # Break out of stream to start next round
                            break

            # If we hit max rounds, just end gracefully
            if current_round >= max_rounds:
                print(f"Warning: Hit max tool rounds ({max_rounds})", flush=True)

        except Exception as e:
            import traceback
            error_details = f"{type(e).__name__}: {str(e)}\n{traceback.format_exc()}"
            print(f"Chat streaming error: {error_details}", flush=True)
            yield {
                "type": "error",
                "error": str(e)
            }
