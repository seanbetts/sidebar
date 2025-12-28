"""Helpers for web search tool payloads and status."""
from __future__ import annotations

from typing import Any, Dict


def build_web_search_location(
    current_location_levels: Any,
    timezone: str | None,
) -> Dict[str, str] | None:
    """Build a web search location payload from location levels.

    Args:
        current_location_levels: Location levels or None.
        timezone: Optional timezone label.

    Returns:
        Location payload dict or None.
    """
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


def serialize_web_search_result(content_block: Any) -> Dict[str, Any]:
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
    if isinstance(content, dict) and content.get("type") == "web_search_tool_result_error":
        return content.get("error_code")
    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict) and item.get("type") == "web_search_tool_result_error":
                return item.get("error_code")
    return None


def web_search_status(content_block: Any) -> str:
    """Return success/error status for a web search result block."""
    return "error" if web_search_error(content_block) else "success"
