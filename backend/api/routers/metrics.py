"""Metrics endpoint."""

from __future__ import annotations

from fastapi import APIRouter, Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel, Field

from api.metrics import (
    chat_first_token_latency_seconds,
    chat_sse_connect_seconds,
    chat_stream_errors_total,
    chat_streaming_duration_seconds,
    chat_tool_duration_seconds,
    web_vitals_observations_total,
    web_vitals_value,
)

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


class ChatMetricPayload(BaseModel):
    """Payload for chat metric events."""

    name: str = Field(..., min_length=1)
    value: float
    tool_name: str | None = None
    status: str | None = None
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


@router.post("/api/v1/metrics/chat", status_code=204)
def record_chat_metrics(payload: ChatMetricPayload) -> Response:
    """Record a chat metric measurement."""
    name = payload.name
    if name == "first_token_latency_ms":
        chat_first_token_latency_seconds.observe(payload.value / 1000)
    elif name == "stream_duration_ms":
        chat_streaming_duration_seconds.observe(payload.value / 1000)
    elif name == "sse_connect_ms":
        chat_sse_connect_seconds.observe(payload.value / 1000)
    elif name == "tool_duration_ms":
        tool_name = (payload.tool_name or "unknown").strip() or "unknown"
        status = (payload.status or "success").strip() or "success"
        chat_tool_duration_seconds.labels(tool_name=tool_name, status=status).observe(
            payload.value / 1000
        )
    elif name in {"sse_error", "stream_error"}:
        chat_stream_errors_total.labels(type=name).inc()
    else:
        return Response(status_code=400)

    return Response(status_code=204)
