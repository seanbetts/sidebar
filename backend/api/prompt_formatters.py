"""Formatting helpers for prompt templates."""

from __future__ import annotations

from datetime import date
from typing import Any


def detect_operating_system(user_agent: str | None) -> str | None:
    """Infer operating system from a user agent string."""
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
    """Calculate age from a date of birth."""
    if not date_of_birth:
        return None
    years = today.year - date_of_birth.year
    birthday_passed = (today.month, today.day) >= (
        date_of_birth.month,
        date_of_birth.day,
    )
    return years if birthday_passed else years - 1


def format_location_levels(levels: dict[str, Any] | str | None) -> str:
    """Format location levels into a readable string."""
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


def format_weather(weather: dict[str, Any] | str | None) -> str:
    """Format weather payload into a readable sentence."""
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
        wind_dir_label = (
            _wind_direction_label(float(wind_direction))
            if wind_direction is not None
            else None
        )
        wind_text = f"{round(wind_speed)} km/h" + (
            f" {wind_dir_label}" if wind_dir_label else ""
        )
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
            precip_text = (
                f"{precip}% chance of precipitation" if precip is not None else None
            )
            forecast_bits = [f"{label}: {round(min_c)}–{round(max_c)}°C, {desc}"]
            if precip_text:
                forecast_bits.append(precip_text)
            forecast_parts.append(", ".join(forecast_bits))

        if forecast_parts:
            sentence = sentence + " Forecast: " + ". ".join(forecast_parts) + "."

    return sentence


def truncate_content(value: str | None, limit: int) -> str | None:
    """Truncate content to a maximum character limit."""
    if value is None:
        return None
    if len(value) <= limit:
        return value
    return value[:limit]
