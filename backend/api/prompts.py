"""Prompt templates and helpers for chat context injection."""
from __future__ import annotations

import re
from datetime import datetime
from typing import Any

from api.prompt_config import (
    CONTEXT_GUIDANCE_TEMPLATE,
    CURRENT_OPEN_ATTACHMENTS_HEADER,
    CURRENT_OPEN_CONTENT_HEADER,
    CURRENT_OPEN_EMPTY_TEXT,
    CURRENT_OPEN_FILE_HEADER,
    CURRENT_OPEN_NOTE_HEADER,
    CURRENT_OPEN_WEBSITE_HEADER,
    CURRENT_OPEN_WRAPPER_TEMPLATE,
    DEFAULT_COMMUNICATION_STYLE,
    DEFAULT_WORKING_RELATIONSHIP,
    FIRST_MESSAGE_TEMPLATE,
    RECENT_ACTIVITY_CHATS_HEADER,
    RECENT_ACTIVITY_EMPTY_TEXT,
    RECENT_ACTIVITY_FILES_HEADER,
    RECENT_ACTIVITY_NOTES_HEADER,
    RECENT_ACTIVITY_WEBSITES_HEADER,
    RECENT_ACTIVITY_WRAPPER_TEMPLATE,
    SUPPORTED_VARIABLES,
    SYSTEM_PROMPT_TEMPLATE,
)
from api.prompt_formatters import (
    calculate_age,
    detect_operating_system,
    format_location_levels,
    format_weather,
    truncate_content,
)

_TOKEN_PATTERN = re.compile(r"\{([a-zA-Z0-9_]+)\}")


def resolve_template(template: str, variables: dict[str, Any], keep_unknown: bool = True) -> str:
    """Resolve template variables into a string.

    Args:
        template: Template string with {tokens}.
        variables: Mapping of token to value.
        keep_unknown: Keep unknown tokens when True. Defaults to True.

    Returns:
        Resolved template string.
    """
    def replace(match: re.Match[str]) -> str:
        """Replace a matched token with its resolved value."""
        key = match.group(1)
        if key in variables and variables[key] is not None:
            return str(variables[key])
        return match.group(0) if keep_unknown else ""

    return _TOKEN_PATTERN.sub(replace, template)


def resolve_default(value: str | None, default: str) -> str:
    """Return a trimmed value or the default."""
    if value is None:
        return default
    trimmed = value.strip()
    return trimmed if trimmed else default


def build_prompt_variables(
    settings_record: Any,
    current_location: str,
    current_location_levels: dict[str, Any] | str | None,
    current_weather: dict[str, Any] | str | None,
    operating_system: str | None,
    now: datetime,
) -> dict[str, Any]:
    """Build template variables for prompt rendering.

    Args:
        settings_record: User settings record or None.
        current_location: Current location label.
        current_location_levels: Structured location levels.
        current_weather: Weather payload.
        operating_system: Detected operating system label.
        now: Current timestamp.

    Returns:
        Variables mapping for prompt templates.
    """
    name = (
        getattr(settings_record, "name", "") or ""
    ).strip() if settings_record else None
    owner = name or "the user"
    gender = (
        getattr(settings_record, "gender", "") or ""
    ).strip() if settings_record else None
    pronouns = (
        getattr(settings_record, "pronouns", "") or ""
    ).strip() if settings_record else None
    job_title = (
        getattr(settings_record, "job_title", "") or ""
    ).strip() if settings_record else None
    employer = (
        getattr(settings_record, "employer", "") or ""
    ).strip() if settings_record else None
    home_location = (
        getattr(settings_record, "location", "") or ""
    ).strip() if settings_record else None
    date_of_birth = getattr(settings_record, "date_of_birth", None) if settings_record else None
    age = calculate_age(date_of_birth, now.date())
    timezone_label = now.tzname() or "UTC"
    current_date = now.strftime("%Y-%m-%d")
    current_time = f"{now.strftime('%H:%M')} {timezone_label}"
    formatted_levels = format_location_levels(current_location_levels)
    formatted_weather = format_weather(current_weather)
    things_snapshot_raw = getattr(settings_record, "things_ai_snapshot", "") if settings_record else ""
    things_snapshot = things_snapshot_raw.strip() if isinstance(things_snapshot_raw, str) else ""
    things_snapshot_block = f"<tasks>\n{things_snapshot}\n</tasks>" if things_snapshot else ""

    return {
        "owner": owner,
        "name": name or owner,
        "currentDate": current_date,
        "currentTime": current_time,
        "homeLocation": home_location or "Unknown",
        "currentLocationLevels": formatted_levels,
        "currentWeather": formatted_weather,
        "timezone": timezone_label,
        "gender": gender,
        "pronouns": pronouns,
        "age": age,
        "jobTitle": job_title,
        "employer": employer,
        "occupation": job_title,
        "operatingSystem": operating_system,
        "current_date": current_date,
        "current_time": current_time,
        "current_location_levels": formatted_levels,
        "current_weather": formatted_weather,
        "home_location": home_location,
        "operating_system": operating_system,
        "thingsSnapshot": things_snapshot_block,
    }


def build_recent_activity_block(
    notes: list[dict[str, Any]],
    websites: list[dict[str, Any]],
    conversations: list[dict[str, Any]],
    files: list[dict[str, Any]],
) -> str:
    """Render the recent activity block for prompts.

    Args:
        notes: Recent note items.
        websites: Recent website items.
        conversations: Recent conversation items.
        files: Recent file items.

    Returns:
        Rendered recent activity block string.
    """
    lines: list[str] = []

    if notes:
        lines.append(RECENT_ACTIVITY_NOTES_HEADER)
        for note in notes:
            folder = f", folder: {note['folder']}" if note.get("folder") else ""
            lines.append(
                f"- {note['title']} (last_opened_at: {note['last_opened_at']}, id: {note['id']}{folder})"
            )

    if websites:
        if lines:
            lines.append("")
        lines.append(RECENT_ACTIVITY_WEBSITES_HEADER)
        for website in websites:
            domain = f", domain: {website['domain']}" if website.get("domain") else ""
            url = f", url: {website['url']}" if website.get("url") else ""
            lines.append(
                f"- {website['title']} (last_opened_at: {website['last_opened_at']}, id: {website['id']}{domain}{url})"
            )

    if conversations:
        if lines:
            lines.append("")
        lines.append(RECENT_ACTIVITY_CHATS_HEADER)
        for conversation in conversations:
            message_count = (
                f", messages: {conversation['message_count']}"
                if conversation.get("message_count") is not None
                else ""
            )
            lines.append(
                f"- {conversation['title']} (last_opened_at: {conversation['last_opened_at']}, id: {conversation['id']}{message_count})"
            )

    if files:
        if lines:
            lines.append("")
        lines.append(RECENT_ACTIVITY_FILES_HEADER)
        for file in files:
            mime = f", type: {file['mime']}" if file.get("mime") else ""
            lines.append(
                f"- {file['filename']} (last_opened_at: {file['last_opened_at']}, id: {file['id']}{mime})"
            )

    if not lines:
        return resolve_template(
            RECENT_ACTIVITY_WRAPPER_TEMPLATE,
            {"content": RECENT_ACTIVITY_EMPTY_TEXT},
            keep_unknown=False,
        )

    return resolve_template(
        RECENT_ACTIVITY_WRAPPER_TEMPLATE,
        {"content": "\n".join(lines)},
        keep_unknown=False,
    )


def build_open_context_block(
    note: dict[str, Any] | None,
    website: dict[str, Any] | None,
    file_item: dict[str, Any] | None = None,
    attachments: list[dict[str, Any]] | None = None,
    max_chars: int = 20000,
) -> str:
    """Render the currently open note/website block.

    Args:
        note: Open note payload.
        website: Open website payload.
        max_chars: Max characters to include for content. Defaults to 20000.

    Returns:
        Rendered open context block string.
    """
    lines: list[str] = []

    if note:
        lines.append(CURRENT_OPEN_NOTE_HEADER)
        title = note.get("title") or "Untitled"
        note_id = note.get("id") or "unknown"
        path = note.get("path") or note.get("folder")
        path_text = f", path: {path}" if path else ""
        lines.append(f"- {title} (id: {note_id}{path_text})")
        content = truncate_content(note.get("content"), max_chars)
        if content:
            lines.append(CURRENT_OPEN_CONTENT_HEADER)
            lines.append(content)

    if website:
        if lines:
            lines.append("")
        lines.append(CURRENT_OPEN_WEBSITE_HEADER)
        title = website.get("title") or "Untitled"
        website_id = website.get("id") or "unknown"
        domain = website.get("domain")
        url = website.get("url")
        domain_text = f", domain: {domain}" if domain else ""
        url_text = f", url: {url}" if url else ""
        lines.append(f"- {title} (id: {website_id}{domain_text}{url_text})")
        content = truncate_content(website.get("content"), max_chars)
        if content:
            lines.append(CURRENT_OPEN_CONTENT_HEADER)
            lines.append(content)

    if file_item:
        if lines:
            lines.append("")
        lines.append(CURRENT_OPEN_FILE_HEADER)
        filename = file_item.get("filename") or "Untitled"
        file_id = file_item.get("id") or "unknown"
        mime = file_item.get("mime")
        category = file_item.get("category")
        meta_bits = [f"id: {file_id}"]
        if mime:
            meta_bits.append(f"type: {mime}")
        if category:
            meta_bits.append(f"category: {category}")
        meta_text = ", ".join(meta_bits)
        lines.append(f"- {filename} ({meta_text})")
        content = truncate_content(file_item.get("content"), max_chars)
        if content:
            lines.append(CURRENT_OPEN_CONTENT_HEADER)
            lines.append(content)

    if attachments:
        if lines:
            lines.append("")
        lines.append(CURRENT_OPEN_ATTACHMENTS_HEADER)
        for attachment in attachments:
            filename = attachment.get("filename") or "Untitled"
            file_id = attachment.get("id") or "unknown"
            mime = attachment.get("mime")
            category = attachment.get("category")
            meta_bits = [f"id: {file_id}"]
            if mime:
                meta_bits.append(f"type: {mime}")
            if category:
                meta_bits.append(f"category: {category}")
            meta_text = ", ".join(meta_bits)
            lines.append(f"- {filename} ({meta_text})")
            content = truncate_content(attachment.get("content"), max_chars)
            if content:
                lines.append(CURRENT_OPEN_CONTENT_HEADER)
                lines.append(content)

    if not lines:
        return resolve_template(
            CURRENT_OPEN_WRAPPER_TEMPLATE,
            {"content": CURRENT_OPEN_EMPTY_TEXT},
            keep_unknown=False,
        )

    return resolve_template(
        CURRENT_OPEN_WRAPPER_TEMPLATE,
        {"content": "\n".join(lines)},
        keep_unknown=False,
    )


def build_system_prompt(
    settings_record: Any,
    current_location: str,
    current_location_levels: dict[str, Any] | str | None,
    current_weather: dict[str, Any] | str | None,
    now: datetime,
) -> str:
    """Build the system prompt for the chat model."""
    variables = build_prompt_variables(
        settings_record,
        current_location,
        current_location_levels,
        current_weather,
        None,
        now,
    )
    return resolve_template(SYSTEM_PROMPT_TEMPLATE, variables)


def build_first_message_prompt(
    settings_record: Any,
    operating_system: str | None,
    now: datetime,
) -> str:
    """Build the initial user message prompt."""
    communication_style = resolve_default(
        settings_record.communication_style if settings_record else None,
        DEFAULT_COMMUNICATION_STYLE,
    )
    working_relationship = resolve_default(
        settings_record.working_relationship if settings_record else None,
        DEFAULT_WORKING_RELATIONSHIP,
    )
    variables = build_prompt_variables(settings_record, "", None, None, operating_system, now)
    age = variables.get("age")
    name = variables.get("name")
    gender = variables.get("gender")
    pronouns = variables.get("pronouns")
    job_title = variables.get("jobTitle")
    employer = variables.get("employer")

    context_lines = []
    intro_parts = []
    if name:
        intro_parts.append(f"I am {name}.")
    if gender:
        intro_parts.append(f"I am {gender}.")
    if pronouns:
        intro_parts.append(f"My pronouns are {pronouns}.")
    if age is not None:
        intro_parts.append(f"I am {age} years old.")
    if intro_parts:
        context_lines.append(" ".join(intro_parts))
    if operating_system:
        context_lines.append(f"I use {operating_system}.")
    if job_title and employer:
        context_lines.append(f"I am the {job_title} at {employer}.")
    elif job_title:
        context_lines.append(f"I am {job_title}.")

    conversation_context = "\n\n".join(context_lines) if context_lines else "I am the user."
    variables.update(
        {
            "conversation_context": conversation_context,
            "communication_style": communication_style,
            "working_relationship": working_relationship,
        }
    )
    return resolve_template(FIRST_MESSAGE_TEMPLATE, variables)
