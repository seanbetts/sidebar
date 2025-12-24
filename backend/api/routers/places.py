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

    data = await run_in_threadpool(_fetch_autocomplete, trimmed)
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
