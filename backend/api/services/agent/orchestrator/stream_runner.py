"""Streaming handler for Claude tool-enabled conversations."""

from __future__ import annotations

import json
import logging
from collections.abc import AsyncIterator
from typing import Any

from api.constants import ChatConstants
from api.schemas.tool_context import ToolExecutionContext
from api.services.agent.orchestrator.event_emitter import (
    build_onboarding_milestone_completed_event,
    iter_initial_onboarding_events,
)
from api.services.agent.tools.skills_guard import skills_guard_service
from api.services.ai.chat_stream_debug_trace import (
    is_chat_stream_debug_enabled,
    visible_whitespace_preview,
)
from api.services.ai.chat_stream_error_contract import build_chat_stream_error_event
from api.services.ai.chat_stream_sync_events import build_tool_status
from api.services.ai.tool_event_mapper import (
    tool_result_content,
    tool_side_effect_events,
)
from api.services.ai.tool_result_normalizer import normalize_tool_result
from api.services.web_search_builder import (
    build_web_search_location,
    serialize_web_search_result,
    web_search_status,
)

logger = logging.getLogger(__name__)


def _is_connection_setup_error(error: Exception) -> bool:
    """Return True when the error indicates stream connection setup failed."""
    error_name = error.__class__.__name__
    if error_name in {"APIConnectionError", "APITimeoutError"}:
        return True
    message = str(error).lower()
    return any(
        marker in message
        for marker in {
            "connection error",
            "connection reset",
            "timed out",
            "timeout",
        }
    )


async def stream_with_tools(
    *,
    client: Any,
    tool_mapper: Any,
    model: str,
    message: str,
    conversation_history: list[dict[str, Any]] | None = None,
    system_prompt: str | None = None,
    allowed_skills: list[str] | None = None,
    tool_context: ToolExecutionContext | dict[str, Any] | None = None,
) -> AsyncIterator[dict[str, Any]]:
    """Stream chat with tool execution and multi-turn conversation.

    Args:
        client: Claude client instance.
        tool_mapper: Tool mapper for skill definitions.
        model: Claude model identifier.
        message: User message.
        conversation_history: Previous messages (optional).
        system_prompt: System prompt override (optional).
        allowed_skills: Allowed skill names (optional).
        tool_context: Context passed to tool execution (optional).

    Yields:
        Events: token, tool_call, tool_result, error.
    """
    context_dict: dict[str, Any] | None = None
    if tool_context:
        if isinstance(tool_context, ToolExecutionContext):
            context_dict = tool_context.to_dict()
        else:
            context_dict = tool_context

    messages = conversation_history or []
    messages.append({"role": "user", "content": message})

    onboarding_state = None
    if isinstance(context_dict, dict):
        raw_onboarding_state = context_dict.get("onboarding_state")
        if isinstance(raw_onboarding_state, dict):
            onboarding_state = raw_onboarding_state

    for onboarding_event in iter_initial_onboarding_events(onboarding_state):
        yield onboarding_event

    base_tools = tool_mapper.get_claude_tools(allowed_skills)
    user_location = None
    if context_dict:
        user_location = build_web_search_location(
            context_dict.get("current_location_levels"),
            context_dict.get("current_timezone"),
        )
    web_search_tool: dict[str, Any] = {
        "type": "web_search_20250305",
        "name": "web_search",
        "max_uses": 5,
    }
    if user_location:
        web_search_tool["user_location"] = user_location
    web_search_enabled = allowed_skills is None or "web-search" in allowed_skills
    memory_beta_enabled = allowed_skills is None or "memory" in allowed_skills
    optional_fallback_used = False

    max_rounds = ChatConstants.MAX_TOOL_ROUNDS
    current_round = 0

    try:
        while current_round < max_rounds:
            current_round += 1
            saw_stream_event = False
            tools = list(base_tools)
            if web_search_enabled:
                tools.append(web_search_tool)

            stream_args: dict[str, Any] = {
                "model": model,
                "max_tokens": 4096,
                "messages": messages,
                "tools": tools,
            }
            if memory_beta_enabled:
                stream_args["extra_headers"] = {
                    "anthropic-beta": "context-management-2025-06-27"
                }
            if system_prompt:
                stream_args["system"] = system_prompt

            try:
                async with client.messages.stream(**stream_args) as stream:
                    content_blocks = []
                    tool_uses = []
                    current_text = ""
                    current_server_tool = None
                    web_search_tool_call_id = None
                    web_search_pending_end = False
                    web_search_pending_status = None
                    web_search_result_seen = False
                    suppress_web_search_preamble = False

                    async for event in stream:
                        saw_stream_event = True
                        if event.type == "content_block_start":
                            if hasattr(event.content_block, "type"):
                                if event.content_block.type == "text":
                                    current_text = ""
                                elif event.content_block.type == "tool_use":
                                    tool_uses.append(
                                        {
                                            "id": event.content_block.id,
                                            "name": event.content_block.name,
                                            "input": {},
                                            "input_partial": "",
                                        }
                                    )
                                    display_name = tool_mapper.get_tool_display_name(
                                        event.content_block.name
                                    )
                                    yield build_tool_status(
                                        tool_call_id=event.content_block.id,
                                        status="running",
                                        display_name=display_name,
                                    )
                                elif event.content_block.type == "server_tool_use":
                                    current_server_tool = {
                                        "id": event.content_block.id,
                                        "name": event.content_block.name,
                                        "input": {},
                                        "input_partial": "",
                                    }
                                    if event.content_block.name == "web_search":
                                        web_search_tool_call_id = event.content_block.id
                                        yield build_tool_status(
                                            tool_call_id=event.content_block.id,
                                            status="running",
                                            display_name="Web Search",
                                        )
                                        suppress_web_search_preamble = True
                                elif (
                                    event.content_block.type == "web_search_tool_result"
                                ):
                                    web_search_tool_call_id = (
                                        getattr(event.content_block, "id", None)
                                        or web_search_tool_call_id
                                    )
                                    web_search_pending_end = True
                                    web_search_pending_status = web_search_status(
                                        event.content_block
                                    )
                                    web_search_result_seen = True
                                    suppress_web_search_preamble = False
                                    content_blocks.append(
                                        serialize_web_search_result(event.content_block)
                                    )

                        elif event.type == "content_block_delta":
                            if hasattr(event.delta, "type"):
                                if event.delta.type == "text_delta":
                                    if (
                                        suppress_web_search_preamble
                                        and not web_search_result_seen
                                    ):
                                        continue
                                    if web_search_pending_end:
                                        tool_call_id = (
                                            web_search_tool_call_id or "web_search"
                                        )
                                        yield build_tool_status(
                                            tool_call_id=tool_call_id,
                                            status=(
                                                "completed"
                                                if (
                                                    web_search_pending_status
                                                    or "success"
                                                )
                                                == "success"
                                                else "failed"
                                            ),
                                            display_name="Web Search",
                                        )
                                        web_search_pending_end = False
                                        web_search_pending_status = None
                                    current_text += event.delta.text
                                    if is_chat_stream_debug_enabled():
                                        logger.info(
                                            (
                                                "Chat stream model token "
                                                'chars=%s content="%s"'
                                            ),
                                            len(event.delta.text),
                                            visible_whitespace_preview(
                                                event.delta.text
                                            ),
                                        )
                                    yield {"type": "token", "content": event.delta.text}
                                elif event.delta.type == "input_json_delta":
                                    if tool_uses:
                                        tool_uses[-1]["input_partial"] += (
                                            event.delta.partial_json
                                        )
                                    elif current_server_tool:
                                        current_server_tool["input_partial"] += (
                                            event.delta.partial_json
                                        )

                        elif event.type == "content_block_stop":
                            if current_text:
                                if is_chat_stream_debug_enabled():
                                    logger.info(
                                        (
                                            "Chat stream model block "
                                            'chars=%s content="%s"'
                                        ),
                                        len(current_text),
                                        visible_whitespace_preview(current_text),
                                    )
                                content_blocks.append(
                                    {
                                        "type": "text",
                                        "text": current_text,
                                    }
                                )
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
                                tool_call_id = web_search_tool_call_id or "web_search"
                                yield build_tool_status(
                                    tool_call_id=tool_call_id,
                                    status=(
                                        "completed"
                                        if (web_search_pending_status or "success")
                                        == "success"
                                        else "failed"
                                    ),
                                    display_name="Web Search",
                                )
                                web_search_pending_end = False
                                web_search_pending_status = None
                            if not tool_uses:
                                return

                            for tool_use in tool_uses:
                                try:
                                    if tool_use["input_partial"]:
                                        tool_use["input"] = json.loads(
                                            tool_use["input_partial"]
                                        )
                                except json.JSONDecodeError:
                                    tool_use["input"] = {}

                                content_blocks.append(
                                    {
                                        "type": "tool_use",
                                        "id": tool_use["id"],
                                        "name": tool_use["name"],
                                        "input": tool_use["input"],
                                    }
                                )

                            messages.append(
                                {
                                    "role": "assistant",
                                    "content": content_blocks,
                                }
                            )

                            tool_results = []
                            for tool_use in tool_uses:
                                display_name = tool_mapper.get_tool_display_name(
                                    tool_use["name"]
                                )
                                skill_id = None
                                icon_key = None
                                if hasattr(tool_mapper, "get_tool_skill_id"):
                                    skill_id = tool_mapper.get_tool_skill_id(
                                        tool_use["name"]
                                    )
                                if hasattr(tool_mapper, "get_tool_icon_key"):
                                    icon_key = tool_mapper.get_tool_icon_key(
                                        tool_use["name"]
                                    )
                                tool_call_event: dict[str, Any] = {
                                    "type": "tool_call",
                                    "id": tool_use["id"],
                                    "name": display_name,
                                    "parameters": tool_use["input"],
                                    "status": "pending",
                                }
                                if isinstance(skill_id, str) and skill_id:
                                    tool_call_event["skill_id"] = skill_id
                                if isinstance(icon_key, str) and icon_key:
                                    tool_call_event["icon_key"] = icon_key
                                yield tool_call_event

                                user_id = (
                                    str(context_dict.get("user_id"))
                                    if isinstance(context_dict, dict)
                                    and context_dict.get("user_id")
                                    else ""
                                )
                                if (
                                    user_id
                                    and skills_guard_service.requires_confirmation(
                                        display_name
                                    )
                                ):
                                    create_confirmation = (
                                        skills_guard_service
                                    ).create_confirmation_requested_event
                                    confirmation_event = create_confirmation(
                                        user_id=user_id,
                                        tool_call_id=tool_use["id"],
                                        tool_name=tool_use["name"],
                                        display_name=display_name,
                                        parameters=tool_use["input"],
                                        skill_id=skill_id,
                                        icon_key=icon_key,
                                    )
                                    yield confirmation_event
                                    yield build_tool_status(
                                        tool_call_id=tool_use["id"],
                                        status="awaiting_confirmation",
                                        display_name=display_name,
                                    )
                                    return

                                result = await tool_mapper.execute_tool(
                                    tool_use["name"],
                                    tool_use["input"],
                                    allowed_skills=allowed_skills,
                                    context=context_dict,
                                )

                                status = "success" if result.get("success") else "error"
                                normalized_result = normalize_tool_result(
                                    display_name, result
                                )
                                tool_result_event: dict[str, Any] = {
                                    "type": "tool_result",
                                    "id": tool_use["id"],
                                    "name": display_name,
                                    "result": normalized_result,
                                    "status": status,
                                }
                                if isinstance(skill_id, str) and skill_id:
                                    tool_result_event["skill_id"] = skill_id
                                if isinstance(icon_key, str) and icon_key:
                                    tool_result_event["icon_key"] = icon_key
                                yield tool_result_event
                                yield build_tool_status(
                                    tool_call_id=tool_use["id"],
                                    status="completed"
                                    if status == "success"
                                    else "failed",
                                    display_name=display_name,
                                    summary=normalized_result.get("summary")
                                    if isinstance(normalized_result.get("summary"), str)
                                    else None,
                                )

                                result_data = normalized_result.get("data") or {}
                                for side_effect_event in tool_side_effect_events(
                                    display_name, normalized_result
                                ):
                                    yield side_effect_event
                                if user_id:
                                    create_undo = (
                                        skills_guard_service.create_undo_available_event
                                    )
                                    undo_event = create_undo(
                                        user_id=user_id,
                                        display_name=display_name,
                                        parameters=tool_use["input"],
                                        result_data=result_data,
                                    )
                                    if undo_event is not None:
                                        yield undo_event
                                if normalized_result.get("success"):
                                    updated_onboarding_state = result_data.get(
                                        "onboarding_state"
                                    )
                                    if isinstance(updated_onboarding_state, dict):
                                        onboarding_state = updated_onboarding_state
                                    onboarding_milestone_event = (
                                        build_onboarding_milestone_completed_event(
                                            onboarding_state,
                                            result_data.get("onboarding_milestone"),
                                        )
                                    )
                                    if onboarding_milestone_event:
                                        yield onboarding_milestone_event

                                content_value = tool_result_content(
                                    display_name, normalized_result
                                )
                                tool_results.append(
                                    {
                                        "type": "tool_result",
                                        "tool_use_id": tool_use["id"],
                                        "content": content_value,
                                    }
                                )

                            messages.append(
                                {
                                    "role": "user",
                                    "content": tool_results,
                                }
                            )
                            break
            except Exception as stream_error:
                optional_features_enabled = web_search_enabled or memory_beta_enabled
                if (
                    optional_features_enabled
                    and not optional_fallback_used
                    and not saw_stream_event
                    and _is_connection_setup_error(stream_error)
                ):
                    had_web_search = web_search_enabled
                    had_memory_beta = memory_beta_enabled
                    optional_fallback_used = True
                    web_search_enabled = False
                    memory_beta_enabled = False
                    current_round -= 1
                    logger.warning(
                        "Retrying stream without optional features after setup failure",
                        extra={
                            "error_type": type(stream_error).__name__,
                            "had_web_search": had_web_search,
                            "had_memory_beta": had_memory_beta,
                        },
                    )
                    continue
                raise

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
        if context_dict:
            db = context_dict.get("db")
            if db:
                try:
                    db.rollback()
                except Exception as rollback_error:
                    logger.error(
                        "Failed to rollback streaming session",
                        exc_info=rollback_error,
                    )
        yield build_chat_stream_error_event(e, provider="anthropic")
