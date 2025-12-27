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

    @staticmethod
    def _build_web_search_location(
        current_location_levels: Any,
        timezone: str | None,
    ) -> Dict[str, str] | None:
        if not isinstance(current_location_levels, dict):
            return None
        city = current_location_levels.get("locality") or current_location_levels.get("postal_town")
        region = (
            current_location_levels.get("administrative_area_level_1")
            or current_location_levels.get("administrative_area_level_2")
        )
        country = current_location_levels.get("country")
        country_code = None
        if isinstance(country, str):
            normalized = country.strip()
            if len(normalized) == 2:
                country_code = normalized.upper()
            else:
                country_map = {
                    "united states": "US",
                    "united states of america": "US",
                    "usa": "US",
                    "united kingdom": "GB",
                    "uk": "GB",
                    "great britain": "GB",
                    "england": "GB",
                    "scotland": "GB",
                    "wales": "GB",
                    "northern ireland": "GB",
                }
                mapped = country_map.get(normalized.lower())
                if mapped:
                    country_code = mapped
        if not (city or region or country):
            return None
        location: Dict[str, str] = {"type": "approximate"}
        if city:
            location["city"] = city
        if region:
            location["region"] = region
        if country_code:
            location["country"] = country_code
        if timezone:
            location["timezone"] = timezone
        return location if len(location) > 1 else None

    @staticmethod
    def _serialize_web_search_result(content_block: Any) -> Dict[str, Any]:
        if hasattr(content_block, "model_dump"):
            return content_block.model_dump()
        result = {"type": "web_search_tool_result"}
        if hasattr(content_block, "tool_use_id"):
            result["tool_use_id"] = content_block.tool_use_id
        if hasattr(content_block, "content"):
            result["content"] = content_block.content
        return result

    @staticmethod
    def _web_search_error(content_block: Any) -> str | None:
        content = getattr(content_block, "content", None)
        if isinstance(content, dict) and content.get("type") == "web_search_tool_result_error":
            return content.get("error_code")
        if isinstance(content, list):
            for item in content:
                if isinstance(item, dict) and item.get("type") == "web_search_tool_result_error":
                    return item.get("error_code")
        return None

    @staticmethod
    def _web_search_status(content_block: Any) -> str:
        return "error" if ClaudeClient._web_search_error(content_block) else "success"

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
        system_prompt: str | None = None,
        allowed_skills: List[str] | None = None,
        tool_context: Dict[str, Any] | None = None
    ) -> AsyncIterator[Dict[str, Any]]:
        """
        Stream chat with tool execution and multi-turn conversation.

        Args:
            message: User message
            conversation_history: Previous messages (optional)
            tool_context: Context passed to tool execution (optional)

        Yields:
            Events: token, tool_call, tool_result, error
        """
        # Build messages list
        messages = conversation_history or []
        messages.append({"role": "user", "content": message})

        # Get Claude tools from mapper
        tools = self.tool_mapper.get_claude_tools(allowed_skills)
        if allowed_skills is None or "web-search" in allowed_skills:
            user_location = None
            if tool_context:
                user_location = ClaudeClient._build_web_search_location(
                    tool_context.get("current_location_levels"),
                    tool_context.get("current_timezone"),
                )
            web_search_tool: Dict[str, Any] = {
                "type": "web_search_20250305",
                "name": "web_search",
                "max_uses": 5,
            }
            if user_location:
                web_search_tool["user_location"] = user_location
            tools.append(web_search_tool)

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
                if allowed_skills is None or "memory" in allowed_skills:
                    stream_args["extra_headers"] = {
                        "anthropic-beta": "context-management-2025-06-27"
                    }
                if system_prompt:
                    stream_args["system"] = system_prompt

                async with self.client.messages.stream(**stream_args) as stream:
                    # Track content blocks for building assistant message
                    content_blocks = []
                    tool_uses = []
                    current_text = ""
                    current_server_tool = None
                    web_search_pending_end = False
                    web_search_pending_status = None
                    web_search_result_seen = False
                    suppress_web_search_preamble = False

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
                                    yield {
                                        "type": "tool_start",
                                        "data": {
                                            "name": self.tool_mapper.get_tool_display_name(
                                                event.content_block.name
                                            ),
                                            "status": "running",
                                        },
                                    }
                                elif event.content_block.type == "server_tool_use":
                                    current_server_tool = {
                                        "id": event.content_block.id,
                                        "name": event.content_block.name,
                                        "input": {},
                                        "input_partial": "",
                                    }
                                    if event.content_block.name == "web_search":
                                        yield {
                                            "type": "tool_start",
                                            "data": {
                                                "name": "Web Search",
                                                "status": "running",
                                            },
                                        }
                                        suppress_web_search_preamble = True
                                elif event.content_block.type == "web_search_tool_result":
                                    web_search_pending_end = True
                                    web_search_pending_status = ClaudeClient._web_search_status(event.content_block)
                                    web_search_result_seen = True
                                    suppress_web_search_preamble = False
                                    content_blocks.append(
                                        ClaudeClient._serialize_web_search_result(event.content_block)
                                    )

                        elif event.type == "content_block_delta":
                            if hasattr(event.delta, "type"):
                                if event.delta.type == "text_delta":
                                    # Accumulate and stream text token
                                    if suppress_web_search_preamble and not web_search_result_seen:
                                        continue
                                    if web_search_pending_end:
                                        yield {
                                            "type": "tool_end",
                                            "data": {
                                                "name": "Web Search",
                                                "status": web_search_pending_status or "success",
                                            },
                                        }
                                        web_search_pending_end = False
                                        web_search_pending_status = None
                                    current_text += event.delta.text
                                    yield {
                                        "type": "token",
                                        "content": event.delta.text
                                    }
                                elif event.delta.type == "input_json_delta":
                                    # Tool input being streamed
                                    if tool_uses:
                                        tool_uses[-1]["input_partial"] += event.delta.partial_json
                                    elif current_server_tool:
                                        current_server_tool["input_partial"] += event.delta.partial_json

                        elif event.type == "content_block_stop":
                            # Content block finished - save to content_blocks
                            if current_text:
                                content_blocks.append({
                                    "type": "text",
                                    "text": current_text
                                })
                                current_text = ""
                            elif current_server_tool:
                                try:
                                    if current_server_tool["input_partial"]:
                                        current_server_tool["input"] = json.loads(
                                            current_server_tool["input_partial"]
                                        )
                                except json.JSONDecodeError:
                                    current_server_tool["input"] = {}
                                content_blocks.append(
                                    {
                                        "type": "server_tool_use",
                                        "id": current_server_tool["id"],
                                        "name": current_server_tool["name"],
                                        "input": current_server_tool["input"],
                                    }
                                )
                                current_server_tool = None

                        elif event.type == "message_stop":
                            if web_search_pending_end:
                                yield {
                                    "type": "tool_end",
                                    "data": {
                                        "name": "Web Search",
                                        "status": web_search_pending_status or "success",
                                    },
                                }
                                web_search_pending_end = False
                                web_search_pending_status = None
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
                                display_name = self.tool_mapper.get_tool_display_name(tool_use["name"])
                                # Announce tool call
                                yield {
                                    "type": "tool_call",
                                    "id": tool_use["id"],
                                    "name": display_name,
                                    "parameters": tool_use["input"],
                                    "status": "pending"
                                }

                                # Execute tool
                                result = await self.tool_mapper.execute_tool(
                                    tool_use["name"],
                                    tool_use["input"],
                                    allowed_skills=allowed_skills,
                                    context=tool_context
                                )

                                # Return result
                                status = "success" if result.get("success") else "error"
                                yield {
                                    "type": "tool_result",
                                    "id": tool_use["id"],
                                    "name": display_name,
                                    "result": result,
                                    "status": status
                                }
                                yield {
                                    "type": "tool_end",
                                    "data": {
                                        "name": display_name,
                                        "status": status,
                                    },
                                }

                                if result.get("success"):
                                    result_data = result.get("data") or {}
                                    if display_name == "Create Note":
                                        yield {
                                            "type": "note_created",
                                            "data": {
                                                "id": result_data.get("id"),
                                                "title": result_data.get("title"),
                                                "folder": result_data.get("folder")
                                            }
                                        }
                                    elif display_name == "Update Note":
                                        yield {
                                            "type": "note_updated",
                                            "data": {
                                                "id": result_data.get("id"),
                                                "title": result_data.get("title")
                                            }
                                        }
                                    elif display_name in {"Transcribe Audio", "Transcribe YouTube"}:
                                        note_data = (result_data.get("note") or {})
                                        if note_data.get("id"):
                                            yield {
                                                "type": "note_created",
                                                "data": {
                                                    "id": note_data.get("id"),
                                                    "title": note_data.get("title"),
                                                    "folder": note_data.get("folder"),
                                                }
                                            }
                                    elif display_name == "Save Website":
                                        yield {
                                            "type": "website_saved",
                                            "data": {
                                                "id": result_data.get("id"),
                                                "title": result_data.get("title"),
                                                "url": result_data.get("url")
                                            }
                                        }
                                    elif display_name == "Delete Note":
                                        yield {
                                            "type": "note_deleted",
                                            "data": {
                                                "id": result_data.get("id")
                                            }
                                        }
                                    elif display_name == "Delete Website":
                                        yield {
                                            "type": "website_deleted",
                                            "data": {
                                                "id": result_data.get("id")
                                            }
                                        }
                                    elif display_name == "Set UI Theme":
                                        yield {
                                            "type": "ui_theme_set",
                                            "data": {
                                                "theme": result_data.get("theme")
                                            }
                                        }
                                    elif display_name == "Update Scratchpad":
                                        yield {
                                            "type": "scratchpad_updated",
                                            "data": {
                                                "id": result_data.get("id")
                                            }
                                        }
                                    elif display_name == "Clear Scratchpad":
                                        yield {
                                            "type": "scratchpad_cleared",
                                            "data": {
                                                "id": result_data.get("id")
                                            }
                                        }
                                    elif display_name == "Generate Prompts":
                                        yield {
                                            "type": "prompt_preview",
                                            "data": {
                                                "system_prompt": result_data.get("system_prompt"),
                                                "first_message_prompt": result_data.get("first_message_prompt"),
                                            }
                                        }
                                    elif display_name == "Memory Tool":
                                        command = result_data.get("command")
                                        if command == "create":
                                            event_type = "memory_created"
                                        elif command == "delete":
                                            event_type = "memory_deleted"
                                        elif command in {"str_replace", "insert", "rename"}:
                                            event_type = "memory_updated"
                                        else:
                                            event_type = None
                                        if event_type:
                                            yield {
                                                "type": event_type,
                                                "data": {
                                                    "result": result_data
                                                }
                                            }

                                # Add to tool results for next turn
                                content_value = json.dumps(result)
                                if display_name == "Memory Tool":
                                    if result.get("success"):
                                        result_data = result.get("data") or {}
                                        content_value = result_data.get("content") or ""
                                    else:
                                        content_value = result.get("error") or "Unknown error"
                                tool_results.append({
                                    "type": "tool_result",
                                    "tool_use_id": tool_use["id"],
                                    "content": content_value
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
