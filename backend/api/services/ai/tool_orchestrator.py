"""Provider-agnostic tool orchestration for non-Anthropic chat providers."""

from __future__ import annotations

import asyncio
import json
import logging
import uuid
from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Any

from google.genai import types

from api.constants import ChatConstants
from api.services.ai.tool_event_mapper import (
    tool_result_content,
    tool_side_effect_events,
)

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class LLMToolCall:
    """Normalized function/tool-call payload from provider responses."""

    call_id: str
    name: str
    arguments: dict[str, Any]


class ProviderToolOrchestrator:
    """Execute provider chat loops with unified tool handling and events."""

    def __init__(
        self,
        *,
        tool_mapper: Any,
        allowed_skills: list[str] | None,
        tool_context: dict[str, Any] | None,
    ):
        """Store tool execution dependencies for a provider chat session."""
        self._tool_mapper = tool_mapper
        self._allowed_skills = allowed_skills
        self._tool_context = tool_context

    async def run_openai(
        self,
        *,
        client: Any,
        model: str,
        message: str,
        conversation_history: list[dict[str, Any]] | None,
        system_prompt: str | None,
    ) -> AsyncIterator[dict[str, Any]]:
        """Run OpenAI chat with multi-turn function calling."""
        tools = self._tool_mapper.get_claude_tools(self._allowed_skills)
        openai_tools = [
            {
                "type": "function",
                "function": {
                    "name": tool["name"],
                    "description": tool["description"],
                    "parameters": tool["input_schema"],
                },
            }
            for tool in tools
        ]
        messages = self._build_openai_messages(
            message=message,
            conversation_history=conversation_history,
            system_prompt=system_prompt,
        )

        for _ in range(ChatConstants.MAX_TOOL_ROUNDS):
            response = await client.chat.completions.create(
                model=model,
                messages=messages,
                tools=openai_tools,
                tool_choice="auto",
            )
            choices = getattr(response, "choices", None) or []
            if not choices:
                return

            assistant_message = getattr(choices[0], "message", None)
            if assistant_message is None:
                return
            content_text = self._extract_openai_message_text(assistant_message)
            if content_text:
                yield {"type": "token", "content": content_text}

            tool_calls = self._parse_openai_tool_calls(assistant_message)
            if not tool_calls:
                return

            messages.append(
                {
                    "role": "assistant",
                    "content": content_text or "",
                    "tool_calls": [
                        {
                            "id": call.call_id,
                            "type": "function",
                            "function": {
                                "name": call.name,
                                "arguments": json.dumps(call.arguments),
                            },
                        }
                        for call in tool_calls
                    ],
                }
            )

            async for event in self._execute_tool_calls(tool_calls):
                if isinstance(event, dict) and event.get("_openai_tool_message"):
                    messages.append(event["payload"])
                    continue
                if isinstance(event, dict) and event.get("_google_tool_part"):
                    continue
                yield event
            continue

        yield {
            "type": "error",
            "error": "Maximum tool rounds reached before completion",
        }

    async def run_google(
        self,
        *,
        client: Any,
        model: str,
        message: str,
        conversation_history: list[dict[str, Any]] | None,
        system_prompt: str | None,
    ) -> AsyncIterator[dict[str, Any]]:
        """Run Google chat with multi-turn function calling."""
        tools = self._tool_mapper.get_claude_tools(self._allowed_skills)
        function_declarations = self._build_google_function_declarations(tools)
        google_tools: list[Any] = [
            types.Tool(function_declarations=function_declarations)
        ]
        contents = self._build_google_contents(
            message=message,
            conversation_history=conversation_history,
        )
        config = self._build_google_config(
            system_prompt=system_prompt,
            tools=google_tools,
        )
        fallback_no_tools_config = self._build_google_config(
            system_prompt=system_prompt,
            tools=[],
        )
        empty_response_retry_used = False

        for _ in range(ChatConstants.MAX_TOOL_ROUNDS):
            response = await asyncio.to_thread(
                client.models.generate_content,
                model=model,
                contents=contents,
                config=config,
            )
            text = self._extract_google_text(response)
            if text:
                yield {"type": "token", "content": text}

            function_calls = self._parse_google_tool_calls(response)
            if not function_calls:
                if not text:
                    if (
                        not empty_response_retry_used
                        and not self._google_response_is_blocked(response)
                    ):
                        empty_response_retry_used = True
                        logger.warning(
                            (
                                "Google returned empty response; "
                                "retrying once without tools"
                            ),
                            extra={"model": model},
                        )
                        retry_response = await asyncio.to_thread(
                            client.models.generate_content,
                            model=model,
                            contents=contents,
                            config=fallback_no_tools_config,
                        )
                        retry_text = self._extract_google_text(retry_response)
                        retry_function_calls = self._parse_google_tool_calls(
                            retry_response
                        )
                        if retry_text:
                            yield {"type": "token", "content": retry_text}
                        if retry_function_calls:
                            response = retry_response
                            function_calls = retry_function_calls
                        else:
                            if retry_text:
                                return
                            error_message = self._google_empty_response_error(
                                retry_response
                            )
                            logger.warning(
                                (
                                    "Google retry without tools still "
                                    "returned empty response"
                                ),
                                extra={"model": model, "error": error_message},
                            )
                            yield {"type": "error", "error": error_message}
                            return
                    else:
                        error_message = self._google_empty_response_error(response)
                        logger.warning(
                            "Google response contained no text and no tool calls",
                            extra={"model": model, "error": error_message},
                        )
                        yield {"type": "error", "error": error_message}
                        return
                else:
                    return

            candidate_content = self._extract_google_candidate_content(response)
            if candidate_content is not None:
                contents.append(candidate_content)

            response_parts: list[types.Part] = []
            async for event in self._execute_tool_calls(function_calls):
                if isinstance(event, dict) and event.get("_google_tool_part"):
                    response_parts.append(event["payload"])
                    continue
                if isinstance(event, dict) and event.get("_openai_tool_message"):
                    continue
                yield event

            if response_parts:
                contents.append(types.Content(role="user", parts=response_parts))
            continue

        yield {
            "type": "error",
            "error": "Maximum tool rounds reached before completion",
        }

    @staticmethod
    def _build_openai_messages(
        *,
        message: str,
        conversation_history: list[dict[str, Any]] | None,
        system_prompt: str | None,
    ) -> list[dict[str, Any]]:
        messages: list[dict[str, Any]] = []
        if isinstance(system_prompt, str) and system_prompt.strip():
            messages.append({"role": "system", "content": system_prompt.strip()})
        for item in conversation_history or []:
            if not isinstance(item, dict):
                continue
            role = item.get("role")
            if role not in {"user", "assistant", "system"}:
                continue
            content = item.get("content")
            if isinstance(content, str) and content:
                messages.append({"role": role, "content": content})
        messages.append({"role": "user", "content": message})
        return messages

    @staticmethod
    def _build_google_contents(
        *,
        message: str,
        conversation_history: list[dict[str, Any]] | None,
    ) -> list[types.Content]:
        contents: list[types.Content] = []
        for item in conversation_history or []:
            if not isinstance(item, dict):
                continue
            role = item.get("role")
            if role not in {"user", "assistant"}:
                continue
            content = item.get("content")
            if not isinstance(content, str) or not content:
                continue
            google_role = "user" if role == "user" else "model"
            contents.append(
                types.Content(
                    role=google_role,
                    parts=[types.Part.from_text(text=content)],
                )
            )
        contents.append(
            types.Content(role="user", parts=[types.Part.from_text(text=message)])
        )
        return contents

    @staticmethod
    def _extract_openai_message_text(message: Any) -> str:
        content = getattr(message, "content", None)
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            parts: list[str] = []
            for item in content:
                if isinstance(item, dict):
                    value = item.get("text")
                else:
                    value = getattr(item, "text", None)
                if isinstance(value, str) and value:
                    parts.append(value)
            return "".join(parts)
        return ""

    @staticmethod
    def _parse_openai_tool_calls(message: Any) -> list[LLMToolCall]:
        parsed: list[LLMToolCall] = []
        for call in getattr(message, "tool_calls", None) or []:
            function = getattr(call, "function", None)
            name = getattr(function, "name", None)
            if not isinstance(name, str) or not name:
                continue
            arguments_raw = getattr(function, "arguments", None) or "{}"
            arguments: dict[str, Any]
            try:
                decoded = json.loads(arguments_raw)
                arguments = decoded if isinstance(decoded, dict) else {}
            except json.JSONDecodeError:
                arguments = {}
            call_id = getattr(call, "id", None) or str(uuid.uuid4())
            parsed.append(LLMToolCall(call_id=call_id, name=name, arguments=arguments))
        return parsed

    @staticmethod
    def _extract_google_text(response: Any) -> str:
        text = getattr(response, "text", None)
        if isinstance(text, str) and text:
            return text
        candidates = getattr(response, "candidates", None) or []
        for candidate in candidates:
            content = getattr(candidate, "content", None)
            parts = getattr(content, "parts", None) or []
            for part in parts:
                part_text = getattr(part, "text", None)
                if isinstance(part_text, str) and part_text:
                    return part_text
        return ""

    @staticmethod
    def _extract_google_candidate_content(response: Any) -> types.Content | None:
        candidates = getattr(response, "candidates", None) or []
        if not candidates:
            return None
        content = getattr(candidates[0], "content", None)
        if isinstance(content, types.Content):
            return content
        return None

    @staticmethod
    def _parse_google_tool_calls(response: Any) -> list[LLMToolCall]:
        parsed: list[LLMToolCall] = []
        for call in getattr(response, "function_calls", None) or []:
            name = getattr(call, "name", None)
            if not isinstance(name, str) or not name:
                continue
            call_id = getattr(call, "id", None) or str(uuid.uuid4())
            args = getattr(call, "args", None)
            arguments = args if isinstance(args, dict) else {}
            parsed.append(LLMToolCall(call_id=call_id, name=name, arguments=arguments))
        if parsed:
            return parsed

        # Some Google responses surface function calls only in candidate parts.
        candidates = getattr(response, "candidates", None) or []
        for candidate in candidates:
            content = getattr(candidate, "content", None)
            parts = getattr(content, "parts", None) or []
            for part in parts:
                function_call = getattr(part, "function_call", None)
                if function_call is None:
                    function_call = getattr(part, "functionCall", None)
                if function_call is None and isinstance(part, dict):
                    function_call = part.get("function_call") or part.get(
                        "functionCall"
                    )
                if function_call is None:
                    continue

                if isinstance(function_call, dict):
                    name = function_call.get("name")
                    call_id = (
                        function_call.get("id")
                        or function_call.get("call_id")
                        or str(uuid.uuid4())
                    )
                    args = function_call.get("args") or function_call.get("arguments")
                else:
                    name = getattr(function_call, "name", None)
                    call_id = getattr(function_call, "id", None) or str(uuid.uuid4())
                    args = getattr(function_call, "args", None)
                if not isinstance(name, str) or not name:
                    continue

                arguments = args if isinstance(args, dict) else {}
                parsed.append(
                    LLMToolCall(call_id=call_id, name=name, arguments=arguments)
                )
        return parsed

    @staticmethod
    def _build_google_config(
        *,
        system_prompt: str | None,
        tools: list[Any],
    ) -> types.GenerateContentConfig:
        return types.GenerateContentConfig(
            system_instruction=system_prompt.strip()
            if isinstance(system_prompt, str) and system_prompt.strip()
            else None,
            tools=tools,
            automatic_function_calling=types.AutomaticFunctionCallingConfig(
                disable=True
            ),
            thinking_config=types.ThinkingConfig(thinking_budget=0),
        )

    @staticmethod
    def _build_google_function_declarations(
        tools: list[dict[str, Any]],
    ) -> list[types.FunctionDeclaration]:
        declarations: list[types.FunctionDeclaration] = []
        for tool in tools:
            parameters = ProviderToolOrchestrator._normalize_google_schema(
                tool.get("input_schema", {})
            )
            declarations.append(
                types.FunctionDeclaration(
                    name=tool["name"],
                    description=tool["description"],
                    parameters=parameters,
                )
            )
        return declarations

    @staticmethod
    def _normalize_google_schema(value: Any) -> Any:
        if isinstance(value, dict):
            normalized: dict[str, Any] = {}
            nullable = False
            schema_type = value.get("type")
            if isinstance(schema_type, list):
                type_options = [
                    option.lower() for option in schema_type if isinstance(option, str)
                ]
                non_null_options = [
                    option for option in type_options if option != "null"
                ]
                nullable = "null" in type_options
                if non_null_options:
                    normalized["type"] = non_null_options[0]
            for key, entry in value.items():
                if key == "type":
                    if "type" not in normalized and isinstance(entry, str):
                        normalized["type"] = entry.lower()
                    continue
                normalized[key] = ProviderToolOrchestrator._normalize_google_schema(
                    entry
                )
            if nullable:
                normalized["nullable"] = True
            return normalized
        if isinstance(value, list):
            return [
                ProviderToolOrchestrator._normalize_google_schema(item)
                for item in value
            ]
        return value

    @staticmethod
    def _google_response_is_blocked(response: Any) -> bool:
        prompt_feedback = getattr(response, "prompt_feedback", None)
        if getattr(prompt_feedback, "block_reason", None):
            return True

        candidates = getattr(response, "candidates", None) or []
        for candidate in candidates:
            for rating in getattr(candidate, "safety_ratings", None) or []:
                if getattr(rating, "blocked", False):
                    return True
        return False

    @staticmethod
    def _google_empty_response_error(response: Any) -> str:
        """Describe why Google returned no text and no tool calls."""
        details: list[str] = []

        prompt_feedback = getattr(response, "prompt_feedback", None)
        block_reason = getattr(prompt_feedback, "block_reason", None)
        if block_reason:
            details.append(f"prompt_block_reason={block_reason}")

        candidates = getattr(response, "candidates", None) or []
        if candidates:
            candidate = candidates[0]
            finish_reason = getattr(candidate, "finish_reason", None)
            if finish_reason:
                details.append(f"finish_reason={finish_reason}")

            blocked_categories: list[str] = []
            for rating in getattr(candidate, "safety_ratings", None) or []:
                if getattr(rating, "blocked", False):
                    category = getattr(rating, "category", None)
                    blocked_categories.append(str(category) if category else "unknown")
            if blocked_categories:
                details.append(
                    "safety_blocked_categories=" + ",".join(blocked_categories)
                )

        base = "Google response contained no text and no tool calls"
        if not details:
            return base
        return f"{base} ({'; '.join(details)})"

    async def _execute_tool_calls(
        self, tool_calls: list[LLMToolCall]
    ) -> AsyncIterator[dict[str, Any]]:
        for tool_call in tool_calls:
            display_name = self._tool_mapper.get_tool_display_name(tool_call.name)
            yield {
                "type": "tool_start",
                "data": {"name": display_name, "status": "running"},
            }
            yield {
                "type": "tool_call",
                "id": tool_call.call_id,
                "name": display_name,
                "parameters": tool_call.arguments,
                "status": "pending",
            }
            result = await self._tool_mapper.execute_tool(
                tool_call.name,
                tool_call.arguments,
                allowed_skills=self._allowed_skills,
                context=self._tool_context,
            )
            status = "success" if result.get("success") else "error"
            yield {
                "type": "tool_result",
                "id": tool_call.call_id,
                "name": display_name,
                "result": result,
                "status": status,
            }
            yield {
                "type": "tool_end",
                "data": {"name": display_name, "status": status},
            }
            for event in tool_side_effect_events(display_name, result):
                yield event

            content_value = tool_result_content(display_name, result)
            yield {
                "_openai_tool_message": True,
                "payload": {
                    "role": "tool",
                    "tool_call_id": tool_call.call_id,
                    "content": content_value,
                },
            }
            yield {
                "_google_tool_part": True,
                "payload": types.Part.from_function_response(
                    name=tool_call.name,
                    response={"result": content_value},
                ),
            }
