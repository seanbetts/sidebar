"""Helpers for provider web search payloads and result normalization."""

from __future__ import annotations

import json
from typing import Any

from google.genai import types


def build_web_search_location(
    current_location_levels: Any,
    timezone: str | None,
) -> dict[str, str] | None:
    """Build a web search location payload from location levels.

    Args:
        current_location_levels: Location levels or None.
        timezone: Optional timezone label.

    Returns:
        Location payload dict or None.
    """
    if not isinstance(current_location_levels, dict):
        return None
    city = current_location_levels.get("locality") or current_location_levels.get(
        "postal_town"
    )
    region = current_location_levels.get(
        "administrative_area_level_1"
    ) or current_location_levels.get("administrative_area_level_2")
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
    location: dict[str, str] = {"type": "approximate"}
    if city:
        location["city"] = city
    if region:
        location["region"] = region
    if country_code:
        location["country"] = country_code
    if timezone:
        location["timezone"] = timezone
    return location if len(location) > 1 else None


def build_openai_web_search_tool(
    *,
    current_location_levels: Any,
    timezone: str | None,
) -> dict[str, Any]:
    """Build an OpenAI Responses API web search tool payload."""
    tool: dict[str, Any] = {"type": "web_search"}
    user_location = build_web_search_location(current_location_levels, timezone)
    if user_location:
        tool["user_location"] = user_location
    return tool


def build_google_web_search_tool(
    function_declarations: list[types.FunctionDeclaration],
) -> types.Tool:
    """Build a Gemini tool declaration combining search and custom functions."""
    tool_kwargs: dict[str, Any] = {"google_search": types.GoogleSearch()}
    if function_declarations:
        tool_kwargs["function_declarations"] = function_declarations
    return types.Tool(**tool_kwargs)


def extract_openai_response_text(response: Any) -> str:
    """Extract text from an OpenAI Responses API response."""
    output_text = getattr(response, "output_text", None)
    if isinstance(output_text, str) and output_text:
        return output_text

    output = getattr(response, "output", None) or []
    text_parts: list[str] = []
    for item in output:
        item_type = getattr(item, "type", None)
        if item_type != "message":
            continue
        content = getattr(item, "content", None) or []
        for part in content:
            part_text = getattr(part, "text", None)
            if isinstance(part_text, str) and part_text:
                text_parts.append(part_text)
    return "".join(text_parts)


def parse_openai_response_function_calls(response: Any) -> list[dict[str, Any]]:
    """Extract custom function calls from an OpenAI Responses API response."""
    parsed: list[dict[str, Any]] = []
    for item in getattr(response, "output", None) or []:
        item_type = getattr(item, "type", None)
        if item_type != "function_call":
            continue

        name = getattr(item, "name", None)
        if not isinstance(name, str) or not name:
            continue

        call_id = getattr(item, "call_id", None) or getattr(item, "id", None)
        if not isinstance(call_id, str) or not call_id:
            continue

        arguments_raw = getattr(item, "arguments", None) or "{}"
        if isinstance(arguments_raw, str):
            try:
                decoded = json.loads(arguments_raw)
            except json.JSONDecodeError:
                decoded = {}
        else:
            decoded = arguments_raw

        parsed.append(
            {
                "call_id": call_id,
                "name": name,
                "arguments": decoded if isinstance(decoded, dict) else {},
            }
        )
    return parsed


def serialize_web_search_result(content_block: Any) -> dict[str, Any]:
    """Serialize a web search tool result block into a dict.

    Args:
        content_block: Web search result block.

    Returns:
        Serialized result dict.
    """
    if hasattr(content_block, "model_dump"):
        return content_block.model_dump()
    result = {"type": "web_search_tool_result"}
    if hasattr(content_block, "tool_use_id"):
        result["tool_use_id"] = content_block.tool_use_id
    if hasattr(content_block, "content"):
        result["content"] = content_block.content
    return result


def web_search_error(content_block: Any) -> str | None:
    """Extract error code from a web search result block, if any."""
    content = getattr(content_block, "content", None)
    if (
        isinstance(content, dict)
        and content.get("type") == "web_search_tool_result_error"
    ):
        return content.get("error_code")
    if isinstance(content, list):
        for item in content:
            if (
                isinstance(item, dict)
                and item.get("type") == "web_search_tool_result_error"
            ):
                return item.get("error_code")
    return None


def web_search_status(content_block: Any) -> str:
    """Return success/error status for a web search result block."""
    return "error" if web_search_error(content_block) else "success"
