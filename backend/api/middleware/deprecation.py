"""Deprecation warning middleware."""

from __future__ import annotations

import logging

from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

logger = logging.getLogger(__name__)

DEPRECATED_PATHS = {
    "/api/chat": "/api/v1/chat",
    "/api/conversations": "/api/v1/conversations",
    "/api/notes": "/api/v1/notes",
    "/api/files": "/api/v1/files",
    "/api/ingestion": "/api/v1/ingestion",
    "/api/websites": "/api/v1/websites",
    "/api/scratchpad": "/api/v1/scratchpad",
    "/api/settings": "/api/v1/settings",
    "/api/memories": "/api/v1/memories",
    "/api/places": "/api/v1/places",
    "/api/skills": "/api/v1/skills",
    "/api/weather": "/api/v1/weather",
    "/api/things": "/api/v1/things",
}


class DeprecationMiddleware(BaseHTTPMiddleware):
    """Add deprecation warnings to legacy endpoints."""

    async def dispatch(self, request: Request, call_next):
        """Handle request and append deprecation warnings when needed."""
        path = request.url.path

        for old_path, new_path in DEPRECATED_PATHS.items():
            if path.startswith(old_path):
                logger.warning(
                    "Deprecated API path used",
                    extra={
                        "path": path,
                        "client": request.client.host if request.client else None,
                    },
                )
                response = await call_next(request)
                response.headers["X-API-Deprecated"] = "true"
                response.headers["X-API-Deprecated-Path"] = old_path
                response.headers["X-API-New-Path"] = new_path
                response.headers["X-API-Sunset-Date"] = "2026-06-01"
                return response

        return await call_next(request)
