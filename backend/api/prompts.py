"""Prompt templates and helpers for chat context injection."""
from __future__ import annotations

import re
from datetime import date, datetime
from pathlib import Path
from typing import Any

import yaml

_PROMPT_CONFIG_PATH = Path(__file__).resolve().parent / "config" / "prompts.yaml"


def _load_prompt_config() -> dict[str, Any]:
    if not _PROMPT_CONFIG_PATH.exists():
        raise FileNotFoundError(f"Prompt config not found at {_PROMPT_CONFIG_PATH}")
    data = yaml.safe_load(_PROMPT_CONFIG_PATH.read_text(encoding="utf-8")) or {}
    if not isinstance(data, dict):
        raise ValueError("Prompt config must be a mapping.")
    return data


_PROMPT_CONFIG = _load_prompt_config()

DEFAULT_COMMUNICATION_STYLE = _PROMPT_CONFIG["default_communication_style"]
DEFAULT_WORKING_RELATIONSHIP = _PROMPT_CONFIG["default_working_relationship"]
SYSTEM_PROMPT_TEMPLATE = _PROMPT_CONFIG["system_prompt_template"]
CONTEXT_GUIDANCE_TEMPLATE = _PROMPT_CONFIG["context_guidance_template"]
FIRST_MESSAGE_TEMPLATE = _PROMPT_CONFIG["first_message_template"]
RECENT_ACTIVITY_WRAPPER_TEMPLATE = _PROMPT_CONFIG["recent_activity_wrapper_template"]
RECENT_ACTIVITY_EMPTY_TEXT = _PROMPT_CONFIG["recent_activity_empty_text"]
RECENT_ACTIVITY_NOTES_HEADER = _PROMPT_CONFIG["recent_activity_notes_header"]
RECENT_ACTIVITY_WEBSITES_HEADER = _PROMPT_CONFIG["recent_activity_websites_header"]
RECENT_ACTIVITY_CHATS_HEADER = _PROMPT_CONFIG["recent_activity_chats_header"]
CURRENT_OPEN_WRAPPER_TEMPLATE = _PROMPT_CONFIG["current_open_wrapper_template"]
CURRENT_OPEN_EMPTY_TEXT = _PROMPT_CONFIG["current_open_empty_text"]
CURRENT_OPEN_NOTE_HEADER = _PROMPT_CONFIG["current_open_note_header"]
CURRENT_OPEN_WEBSITE_HEADER = _PROMPT_CONFIG["current_open_website_header"]
CURRENT_OPEN_CONTENT_HEADER = _PROMPT_CONFIG["current_open_content_header"]
SUPPORTED_VARIABLES = set(_PROMPT_CONFIG.get("supported_variables", []))

_TOKEN_PATTERN = re.compile(r"\{([a-zA-Z0-9_]+)\}")


def resolve_template(template: str, variables: dict[str, Any], keep_unknown: bool = True) -> str:
    def replace(match: re.Match[str]) -> str:
        key = match.group(1)
        if key in variables and variables[key] is not None:
            return str(variables[key])
        return match.group(0) if keep_unknown else ""

    return _TOKEN_PATTERN.sub(replace, template)


def resolve_default(value: str | None, default: str) -> str:
    if value is None:
        return default
    trimmed = value.strip()
    return trimmed if trimmed else default


def detect_operating_system(user_agent: str | None) -> str | None:
    if not user_agent:
        return None
    agent = user_agent.lower()
    if "windows" in agent:
        return "Windows"
    if "mac os" in agent or "macos" in agent or "macintosh" in agent:
        return "macOS"
    if "android" in agent:
        return "Android"
    if "iphone" in agent or "ipad" in agent or "ios" in agent:
        return "iOS"
    if "linux" in agent:
        return "Linux"
    return None


def calculate_age(date_of_birth: date | None, today: date) -> int | None:
    if not date_of_birth:
        return None
    years = today.year - date_of_birth.year
    birthday_passed = (today.month, today.day) >= (date_of_birth.month, date_of_birth.day)
    return years if birthday_passed else years - 1


def _format_location_levels(levels: dict[str, Any] | str | None) -> str:
    if not levels:
        return "Unavailable"
    if isinstance(levels, str):
        return levels
    order = [
        "locality",
        "postal_town",
        "administrative_area_level_3",
        "administrative_area_level_2",
        "administrative_area_level_1",
        "country",
    ]
    parts: list[str] = []
    remaining = dict(levels)
    for key in order:
        if key in remaining:
            parts.append(f"{key}: {remaining.pop(key)}")
    for key in sorted(remaining):
        parts.append(f"{key}: {remaining[key]}")
    return " | ".join(parts) if parts else "Unavailable"


def _weather_description(code: int) -> str:
    if code == 0:
        return "clear sky"
    if code == 1:
        return "mainly clear"
    if code == 2:
        return "partly cloudy"
    if code == 3:
        return "overcast"
    if code == 45:
        return "fog"
    if code == 48:
        return "depositing rime fog"
    if code == 51:
        return "light drizzle"
    if code == 53:
        return "moderate drizzle"
    if code == 55:
        return "dense drizzle"
    if code == 56:
        return "light freezing drizzle"
    if code == 57:
        return "dense freezing drizzle"
    if code == 61:
        return "slight rain"
    if code == 63:
        return "moderate rain"
    if code == 65:
        return "heavy rain"
    if code == 66:
        return "light freezing rain"
    if code == 67:
        return "heavy freezing rain"
    if code == 71:
        return "slight snow fall"
    if code == 73:
        return "moderate snow fall"
    if code == 75:
        return "heavy snow fall"
    if code == 77:
        return "snow grains"
    if code == 80:
        return "slight rain showers"
    if code == 81:
        return "moderate rain showers"
    if code == 82:
        return "violent rain showers"
    if code == 85:
        return "slight snow showers"
    if code == 86:
        return "heavy snow showers"
    if code == 95:
        return "thunderstorm"
    if code == 96:
        return "thunderstorm with slight hail"
    if code == 99:
        return "thunderstorm with heavy hail"
    return "unavailable"


def _wind_direction_label(degrees: float) -> str:
    directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    index = int((degrees + 22.5) // 45) % 8
    return directions[index]


def _format_weather(weather: dict[str, Any] | str | None) -> str:
    if not weather:
        return "Unavailable"
    if isinstance(weather, str):
        return weather

    temperature = weather.get("temperature_c")
    feels_like = weather.get("feels_like_c")
    weather_code = weather.get("weather_code")
    is_day = weather.get("is_day")
    wind_speed = weather.get("wind_speed_kph")
    wind_direction = weather.get("wind_direction_degrees")
    precipitation = weather.get("precipitation_mm")
    cloud_cover = weather.get("cloud_cover_percent")
    daily = weather.get("daily") or []

    if temperature is None or weather_code is None or is_day is None:
        return "Unavailable"

    description = _weather_description(weather_code)
    day_label = "daytime" if is_day == 1 else "nighttime"
    temp_text = f"{round(temperature)}°C"
    feels_like_text = f"{round(feels_like)}°C" if feels_like is not None else None
    wind_text = None
    if wind_speed is not None:
        wind_dir_label = _wind_direction_label(float(wind_direction)) if wind_direction is not None else None
        wind_text = f"{round(wind_speed)} km/h" + (f" {wind_dir_label}" if wind_dir_label else "")
    precip_text = f"{precipitation} mm" if precipitation is not None else None
    cloud_text = f"{cloud_cover}%" if cloud_cover is not None else None

    parts = [f"It is {day_label}, {description}, {temp_text}"]
    if feels_like_text:
        parts.append(f"feels like {feels_like_text}")
    if wind_text:
        parts.append(f"wind {wind_text}")
    if precip_text:
        parts.append(f"precipitation {precip_text}")
    if cloud_text:
        parts.append(f"cloud cover {cloud_text}")

    sentence = ", ".join(parts) + "."

    if daily:
        forecast_parts = []
        for index, entry in enumerate(daily[:3]):
            max_c = entry.get("temperature_max_c")
            min_c = entry.get("temperature_min_c")
            code = entry.get("weather_code")
            precip = entry.get("precipitation_probability_max")
            if max_c is None or min_c is None or code is None:
                continue
            desc = _weather_description(code)
            label = "Today" if index == 0 else "Tomorrow" if index == 1 else "Next day"
            precip_text = f"{precip}% chance of precipitation" if precip is not None else None
            forecast_bits = [f"{label}: {round(min_c)}–{round(max_c)}°C, {desc}"]
            if precip_text:
                forecast_bits.append(precip_text)
            forecast_parts.append(", ".join(forecast_bits))

        if forecast_parts:
            sentence = sentence + " Forecast: " + ". ".join(forecast_parts) + "."

    return sentence


def build_prompt_variables(
    settings_record: Any,
    current_location: str,
    current_location_levels: dict[str, Any] | str | None,
    current_weather: dict[str, Any] | str | None,
    operating_system: str | None,
    now: datetime,
) -> dict[str, Any]:
    name = settings_record.name.strip() if settings_record and settings_record.name else None
    owner = name or "the user"
    gender = settings_record.gender.strip() if settings_record and settings_record.gender else None
    pronouns = settings_record.pronouns.strip() if settings_record and settings_record.pronouns else None
    job_title = settings_record.job_title.strip() if settings_record and settings_record.job_title else None
    employer = settings_record.employer.strip() if settings_record and settings_record.employer else None
    home_location = settings_record.location.strip() if settings_record and settings_record.location else None
    date_of_birth = settings_record.date_of_birth if settings_record else None
    age = calculate_age(date_of_birth, now.date())
    timezone_label = now.tzname() or "UTC"
    current_date = now.strftime("%Y-%m-%d")
    current_time = f"{now.strftime('%H:%M')} {timezone_label}"
    formatted_levels = _format_location_levels(current_location_levels)
    formatted_weather = _format_weather(current_weather)

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
    }


def build_recent_activity_block(
    notes: list[dict[str, Any]],
    websites: list[dict[str, Any]],
    conversations: list[dict[str, Any]],
) -> str:
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


def _truncate_content(value: str | None, limit: int) -> str | None:
    if value is None:
        return None
    if len(value) <= limit:
        return value
    return value[:limit]


def build_open_context_block(
    note: dict[str, Any] | None,
    website: dict[str, Any] | None,
    max_chars: int = 20000,
) -> str:
    lines: list[str] = []

    if note:
        lines.append(CURRENT_OPEN_NOTE_HEADER)
        title = note.get("title") or "Untitled"
        note_id = note.get("id") or "unknown"
        path = note.get("path") or note.get("folder")
        path_text = f", path: {path}" if path else ""
        lines.append(f"- {title} (id: {note_id}{path_text})")
        content = _truncate_content(note.get("content"), max_chars)
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
        content = _truncate_content(website.get("content"), max_chars)
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
