"""Places API proxy endpoints."""
import json
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from fastapi import APIRouter, Depends, HTTPException
from fastapi.concurrency import run_in_threadpool

from api.config import settings
from api.auth import verify_bearer_token


router = APIRouter(prefix="/places", tags=["places"])


def _fetch_autocomplete(input_text: str) -> dict:
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
    for component in components:
        if component_type in component.get("types", []):
            return component.get("long_name")
    return None


@router.get("/autocomplete")
async def autocomplete_places(
    input: str,
    _: str = Depends(verify_bearer_token),
):
    if not settings.google_places_api_key:
        raise HTTPException(status_code=503, detail="Google Places API key not configured")
    trimmed = input.strip()
    if len(trimmed) < 2:
        return {"predictions": []}

    try:
        data = await run_in_threadpool(_fetch_autocomplete, trimmed)
    except Exception as exc:
        raise HTTPException(status_code=502, detail="Places lookup failed") from exc
    status = data.get("status")
    if status not in {"OK", "ZERO_RESULTS"}:
        raise HTTPException(status_code=502, detail=data.get("error_message", "Places lookup failed"))

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
    if not settings.google_places_api_key:
        raise HTTPException(status_code=503, detail="Google Places API key not configured")

    try:
        data = await run_in_threadpool(_fetch_nearby_place, lat, lng)
    except Exception as exc:
        raise HTTPException(status_code=502, detail="Places lookup failed") from exc
    status = data.get("status")
    if status not in {"OK", "ZERO_RESULTS"}:
        raise HTTPException(status_code=502, detail=data.get("error_message", "Places lookup failed"))

    results = data.get("results") or []
    if not results:
        return {"label": None}

    place_id = results[0].get("place_id")
    if not place_id:
        return {"label": None}

    try:
        details = await run_in_threadpool(_fetch_place_details, place_id)
    except Exception as exc:
        raise HTTPException(status_code=502, detail="Places lookup failed") from exc

    detail_status = details.get("status")
    if detail_status not in {"OK", "ZERO_RESULTS"}:
        raise HTTPException(
            status_code=502,
            detail=details.get("error_message", "Places lookup failed"),
        )

    components = (details.get("result") or {}).get("address_components") or []
    city = (
        _extract_component(components, "locality")
        or _extract_component(components, "postal_town")
        or _extract_component(components, "administrative_area_level_2")
        or _extract_component(components, "sublocality")
    )
    region = _extract_component(components, "administrative_area_level_1")

    if not city or not region:
        return {"label": None}

    return {"label": f"{city}, {region}"}
