"""Metrics endpoint."""
from __future__ import annotations

from fastapi import APIRouter, Response
from pydantic import BaseModel, Field
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest

from api.metrics import web_vitals_observations_total, web_vitals_value


router = APIRouter(tags=["metrics"])

_ALLOWED_VITALS = {"CLS", "FCP", "INP", "LCP", "TTFB"}
_ALLOWED_RATINGS = {"good", "needs-improvement", "poor"}


class WebVitalPayload(BaseModel):
    """Payload for web-vitals events."""

    name: str = Field(..., min_length=1)
    value: float
    rating: str = Field(..., min_length=1)
    route: str | None = None
    timestamp: str | None = None


@router.get("/metrics")
def metrics() -> Response:
    """Expose Prometheus metrics."""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@router.post("/api/v1/metrics/web-vitals", status_code=204)
def record_web_vitals(payload: WebVitalPayload) -> Response:
    """Record a web-vitals measurement."""
    name = payload.name.upper()
    rating = payload.rating.lower()
    if name not in _ALLOWED_VITALS or rating not in _ALLOWED_RATINGS:
        return Response(status_code=400)

    web_vitals_observations_total.labels(name=name, rating=rating).inc()
    web_vitals_value.labels(name=name, rating=rating).observe(payload.value)

    return Response(status_code=204)
