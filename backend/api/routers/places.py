"""Places API proxy endpoints."""
import json
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from fastapi import APIRouter, Depends
from fastapi.concurrency import run_in_threadpool

from api.config import settings
from api.auth import verify_bearer_token
from api.exceptions import ExternalServiceError, ServiceUnavailableError


router = APIRouter(prefix="/places", tags=["places"])


def _fetch_autocomplete(input_text: str) -> dict:
    """Fetch autocomplete predictions from Google Places.

    Args:
        input_text: User input string.

    Returns:
        Parsed JSON response payload.
    """
    query = urlencode(
        {
            "input": input_text,
            "key": settings.google_places_api_key,
            "types": "(cities)",
        }
    )
    url = f"https://maps.googleapis.com/maps/api/place/autocomplete/json?{query}"
    request = Request(url, headers={"Accept": "application/json"})
    with urlopen(request, timeout=10) as response:
        data = response.read()
        return json.loads(data.decode("utf-8"))


def _fetch_nearby_place(lat: float, lng: float) -> dict:
    """Fetch nearby place results for coordinates.

    Args:
        lat: Latitude.
        lng: Longitude.

    Returns:
        Parsed JSON response payload.
    """
    query = urlencode(
        {
            "location": f"{lat},{lng}",
            "rankby": "distance",
            "type": "locality",
            "key": settings.google_places_api_key,
        }
    )
    url = f"https://maps.googleapis.com/maps/api/place/nearbysearch/json?{query}"
    request = Request(url, headers={"Accept": "application/json"})
    with urlopen(request, timeout=10) as response:
        data = response.read()
        return json.loads(data.decode("utf-8"))


def _fetch_place_details(place_id: str) -> dict:
    """Fetch detailed place info by place ID.

    Args:
        place_id: Google Places place ID.

    Returns:
        Parsed JSON response payload.
    """
    query = urlencode(
        {
            "place_id": place_id,
            "fields": "address_component,name",
            "key": settings.google_places_api_key,
        }
    )
    url = f"https://maps.googleapis.com/maps/api/place/details/json?{query}"
    request = Request(url, headers={"Accept": "application/json"})
    with urlopen(request, timeout=10) as response:
        data = response.read()
        return json.loads(data.decode("utf-8"))


def _extract_component(components: list[dict], component_type: str) -> str | None:
    """Extract a named address component from Google Places data.

    Args:
        components: List of address components.
        component_type: Component type to match.

    Returns:
        Component long name or None.
    """
    for component in components:
        if component_type in component.get("types", []):
            return component.get("long_name")
    return None


def _collect_levels(components: list[dict]) -> dict[str, str]:
    """Collect administrative levels from address components.

    Args:
        components: List of address components.

    Returns:
        Mapping of component type to name.
    """
    levels: dict[str, str] = {}
    for component in components:
        name = component.get("long_name")
        if not name:
            continue
        for ctype in component.get("types", []):
            if ctype.startswith("administrative_area_level_") or ctype in {
                "locality",
                "postal_town",
                "sublocality",
                "country",
            }:
                levels[ctype] = name
    return levels


@router.get("/autocomplete")
async def autocomplete_places(
    input: str,
    _: str = Depends(verify_bearer_token),
):
    """Return place autocomplete predictions.

    Args:
        input: User input string.
        _: Authorization token (validated).

    Returns:
        Predictions list payload.

    Raises:
        ServiceUnavailableError: If API key missing.
        ExternalServiceError: On upstream failure.
    """
    if not settings.google_places_api_key:
        raise ServiceUnavailableError("Google Places API key not configured")
    trimmed = input.strip()
    if len(trimmed) < 2:
        return {"predictions": []}

    try:
        data = await run_in_threadpool(_fetch_autocomplete, trimmed)
    except Exception as exc:
        raise ExternalServiceError("Google Places", "Places lookup failed") from exc
    status = data.get("status")
    if status not in {"OK", "ZERO_RESULTS"}:
        raise ExternalServiceError(
            "Google Places",
            data.get("error_message", "Places lookup failed"),
        )

    predictions = [
        {
            "description": item.get("description"),
            "place_id": item.get("place_id"),
        }
        for item in data.get("predictions", [])
    ]
    return {"predictions": predictions}


@router.get("/reverse")
async def reverse_geocode(
    lat: float,
    lng: float,
    _: str = Depends(verify_bearer_token),
):
    """Reverse geocode coordinates into a locality label.

    Args:
        lat: Latitude.
        lng: Longitude.
        _: Authorization token (validated).

    Returns:
        Label and administrative levels payload.

    Raises:
        ServiceUnavailableError: If API key missing.
        ExternalServiceError: On upstream failure.
    """
    if not settings.google_places_api_key:
        raise ServiceUnavailableError("Google Places API key not configured")

    try:
        data = await run_in_threadpool(_fetch_nearby_place, lat, lng)
    except Exception as exc:
        raise ExternalServiceError("Google Places", "Places lookup failed") from exc
    status = data.get("status")
    if status not in {"OK", "ZERO_RESULTS"}:
        raise ExternalServiceError(
            "Google Places",
            data.get("error_message", "Places lookup failed"),
        )

    results = data.get("results") or []
    if not results:
        return {"label": None}

    place_id = results[0].get("place_id")
    if not place_id:
        return {"label": None}

    try:
        details = await run_in_threadpool(_fetch_place_details, place_id)
    except Exception as exc:
        raise ExternalServiceError("Google Places", "Places lookup failed") from exc

    detail_status = details.get("status")
    if detail_status not in {"OK", "ZERO_RESULTS"}:
        raise ExternalServiceError(
            "Google Places",
            details.get("error_message", "Places lookup failed"),
        )

    components = (details.get("result") or {}).get("address_components") or []
    levels = _collect_levels(components)
    locality = _extract_component(components, "locality")
    country = _extract_component(components, "country")

    if not locality or not country:
        return {"label": None, "levels": levels}

    return {"label": f"{locality}, {country}", "levels": levels}
