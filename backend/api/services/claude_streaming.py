"""Streaming handler for Claude tool-enabled conversations."""
from __future__ import annotations

import json
import logging
from typing import Any, AsyncIterator, Dict, List

from api.constants import ChatConstants
from api.services.web_search_builder import (
    build_web_search_location,
    serialize_web_search_result,
    web_search_status,
)

logger = logging.getLogger(__name__)


async def stream_with_tools(
    *,
    client: Any,
    tool_mapper: Any,
    model: str,
    message: str,
    conversation_history: List[Dict[str, Any]] | None = None,
    system_prompt: str | None = None,
    allowed_skills: List[str] | None = None,
    tool_context: Dict[str, Any] | None = None,
) -> AsyncIterator[Dict[str, Any]]:
    """Stream chat with tool execution and multi-turn conversation.

    Args:
        message: User message.
        conversation_history: Previous messages (optional).
        tool_context: Context passed to tool execution (optional).

    Yields:
        Events: token, tool_call, tool_result, error.
    """
    messages = conversation_history or []
    messages.append({"role": "user", "content": message})

    tools = tool_mapper.get_claude_tools(allowed_skills)
    if allowed_skills is None or "web-search" in allowed_skills:
        user_location = None
        if tool_context:
            user_location = build_web_search_location(
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

    max_rounds = ChatConstants.MAX_TOOL_ROUNDS
    current_round = 0

    try:
        while current_round < max_rounds:
            current_round += 1

            stream_args: Dict[str, Any] = {
                "model": model,
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

            async with client.messages.stream(**stream_args) as stream:
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
                                current_text = ""
                            elif event.content_block.type == "tool_use":
                                tool_uses.append({
                                    "id": event.content_block.id,
                                    "name": event.content_block.name,
                                    "input": {},
                                    "input_partial": "",
                                })
                                yield {
                                    "type": "tool_start",
                                    "data": {
                                        "name": tool_mapper.get_tool_display_name(
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
                                web_search_pending_status = web_search_status(event.content_block)
                                web_search_result_seen = True
                                suppress_web_search_preamble = False
                                content_blocks.append(
                                    serialize_web_search_result(event.content_block)
                                )

                    elif event.type == "content_block_delta":
                        if hasattr(event.delta, "type"):
                            if event.delta.type == "text_delta":
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
                                yield {"type": "token", "content": event.delta.text}
                            elif event.delta.type == "input_json_delta":
                                if tool_uses:
                                    tool_uses[-1]["input_partial"] += event.delta.partial_json
                                elif current_server_tool:
                                    current_server_tool["input_partial"] += event.delta.partial_json

                    elif event.type == "content_block_stop":
                        if current_text:
                            content_blocks.append({
                                "type": "text",
                                "text": current_text,
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
                        if not tool_uses:
                            return

                        for tool_use in tool_uses:
                            try:
                                if tool_use["input_partial"]:
                                    tool_use["input"] = json.loads(tool_use["input_partial"])
                            except json.JSONDecodeError:
                                tool_use["input"] = {}

                            content_blocks.append({
                                "type": "tool_use",
                                "id": tool_use["id"],
                                "name": tool_use["name"],
                                "input": tool_use["input"],
                            })

                        messages.append({
                            "role": "assistant",
                            "content": content_blocks,
                        })

                        tool_results = []
                        for tool_use in tool_uses:
                            display_name = tool_mapper.get_tool_display_name(tool_use["name"])
                            yield {
                                "type": "tool_call",
                                "id": tool_use["id"],
                                "name": display_name,
                                "parameters": tool_use["input"],
                                "status": "pending",
                            }

                            result = await tool_mapper.execute_tool(
                                tool_use["name"],
                                tool_use["input"],
                                allowed_skills=allowed_skills,
                                context=tool_context,
                            )

                            status = "success" if result.get("success") else "error"
                            yield {
                                "type": "tool_result",
                                "id": tool_use["id"],
                                "name": display_name,
                                "result": result,
                                "status": status,
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
                                            "folder": result_data.get("folder"),
                                        },
                                    }
                                elif display_name == "Update Note":
                                    yield {
                                        "type": "note_updated",
                                        "data": {
                                            "id": result_data.get("id"),
                                            "title": result_data.get("title"),
                                        },
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
                                            },
                                        }
                                elif display_name == "Save Website":
                                    yield {
                                        "type": "website_saved",
                                        "data": {
                                            "id": result_data.get("id"),
                                            "title": result_data.get("title"),
                                            "url": result_data.get("url"),
                                        },
                                    }
                                elif display_name == "Delete Note":
                                    yield {
                                        "type": "note_deleted",
                                        "data": {"id": result_data.get("id")},
                                    }
                                elif display_name == "Delete Website":
                                    yield {
                                        "type": "website_deleted",
                                        "data": {"id": result_data.get("id")},
                                    }
                                elif display_name == "Set UI Theme":
                                    yield {
                                        "type": "ui_theme_set",
                                        "data": {"theme": result_data.get("theme")},
                                    }
                                elif display_name == "Update Scratchpad":
                                    yield {
                                        "type": "scratchpad_updated",
                                        "data": {"id": result_data.get("id")},
                                    }
                                elif display_name == "Clear Scratchpad":
                                    yield {
                                        "type": "scratchpad_cleared",
                                        "data": {"id": result_data.get("id")},
                                    }
                                elif display_name == "Generate Prompts":
                                    yield {
                                        "type": "prompt_preview",
                                        "data": {
                                            "system_prompt": result_data.get("system_prompt"),
                                            "first_message_prompt": result_data.get(
                                                "first_message_prompt"
                                            ),
                                        },
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
                                            "data": {"result": result_data},
                                        }

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
                                "content": content_value,
                            })

                        messages.append({
                            "role": "user",
                            "content": tool_results,
                        })
                        break

        if current_round >= max_rounds:
            logger.warning(
                "Hit max tool rounds limit",
                extra={
                    "max_rounds": max_rounds,
                    "current_round": current_round,
                    "messages_count": len(messages),
                },
            )

    except Exception as e:
        import traceback

        error_details = f"{type(e).__name__}: {str(e)}\n{traceback.format_exc()}"
        logger.error(
            "Chat streaming error",
            exc_info=e,
            extra={"error_details": error_details},
        )
        yield {"type": "error", "error": str(e)}
