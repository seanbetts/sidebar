"""Weather API proxy endpoints."""
from __future__ import annotations

import json
import time
import ssl
from typing import Any
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from fastapi import APIRouter, Depends, HTTPException
from fastapi.concurrency import run_in_threadpool

from api.auth import verify_bearer_token
from api.config import settings


router = APIRouter(prefix="/weather", tags=["weather"])

_CACHE_TTL_SECONDS = 1800
_weather_cache: dict[str, dict[str, Any]] = {}


def _as_list(value: Any) -> list:
    """Return a list if value is already a list.

    Args:
        value: Value to normalize.

    Returns:
        List value or an empty list.
    """
    if isinstance(value, list):
        return value
    return []


def _fetch_weather(lat: float, lon: float) -> dict:
    """Fetch weather data from Open-Meteo.

    Args:
        lat: Latitude.
        lon: Longitude.

    Returns:
        Parsed JSON response payload.
    """
    query = urlencode(
        {
            "latitude": lat,
            "longitude": lon,
            "current": "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,wind_direction_10m,precipitation,cloud_cover",
            "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
            "forecast_days": 3,
            "timezone": "Europe/London",
        }
    )
    url = f"https://api.open-meteo.com/v1/forecast?{query}"
    request = Request(url, headers={"Accept": "application/json"})
    if settings.disable_ssl_verify:
        ssl_context = ssl.create_default_context()
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl.CERT_NONE
    elif settings.custom_ca_bundle:
        ssl_context = ssl.create_default_context(cafile=settings.custom_ca_bundle)
    else:
        ssl_context = ssl.create_default_context()
    with urlopen(request, timeout=10, context=ssl_context) as response:
        data = response.read()
        return json.loads(data.decode("utf-8"))


def _cache_key(lat: float, lon: float) -> str:
    """Build a cache key for weather lookups.

    Args:
        lat: Latitude.
        lon: Longitude.

    Returns:
        Cache key string with rounded coordinates.
    """
    return f"{round(lat, 2)}:{round(lon, 2)}"


@router.get("")
async def get_weather(
    lat: float,
    lon: float,
    _: str = Depends(verify_bearer_token),
):
    """Fetch weather data with caching.

    Args:
        lat: Latitude.
        lon: Longitude.
        _: Authorization token (validated).

    Returns:
        Weather payload with current and daily summary.

    Raises:
        HTTPException: 502 if the upstream lookup fails.
    """
    cache_key = _cache_key(lat, lon)
    now = time.time()
    cached = _weather_cache.get(cache_key)
    if cached and now - cached["fetched_at"] < _CACHE_TTL_SECONDS:
        return cached["payload"]

    try:
        data = await run_in_threadpool(_fetch_weather, lat, lon)
    except Exception as exc:
        raise HTTPException(status_code=502, detail="Weather lookup failed") from exc

    current = data.get("current") or {}
    temperature_c = current.get("temperature_2m")
    feels_like_c = current.get("apparent_temperature")
    weather_code = current.get("weather_code")
    is_day = current.get("is_day")
    wind_speed_kph = current.get("wind_speed_10m")
    wind_direction = current.get("wind_direction_10m")
    precipitation_mm = current.get("precipitation")
    cloud_cover = current.get("cloud_cover")

    if temperature_c is None or weather_code is None or is_day is None:
        raise HTTPException(status_code=502, detail="Weather lookup failed")

    daily = data.get("daily") or {}
    daily_codes = _as_list(daily.get("weather_code"))
    daily_max = _as_list(daily.get("temperature_2m_max"))
    daily_min = _as_list(daily.get("temperature_2m_min"))
    daily_precip = _as_list(daily.get("precipitation_probability_max"))

    daily_summary = []
    for index in range(min(3, len(daily_codes), len(daily_max), len(daily_min))):
        daily_summary.append(
            {
                "weather_code": daily_codes[index],
                "temperature_max_c": daily_max[index],
                "temperature_min_c": daily_min[index],
                "precipitation_probability_max": (
                    daily_precip[index] if index < len(daily_precip) else None
                ),
            }
        )

    payload = {
        "temperature_c": temperature_c,
        "feels_like_c": feels_like_c,
        "weather_code": weather_code,
        "is_day": is_day,
        "wind_speed_kph": wind_speed_kph,
        "wind_direction_degrees": wind_direction,
        "precipitation_mm": precipitation_mm,
        "cloud_cover_percent": cloud_cover,
        "daily": daily_summary,
        "fetched_at": now,
    }

    _weather_cache[cache_key] = {"fetched_at": now, "payload": payload}
    return payload
