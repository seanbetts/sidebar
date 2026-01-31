"""Error handling middleware."""

from __future__ import annotations

import logging
from typing import Any

from api.exceptions import APIError
from fastapi import HTTPException as FastAPIHTTPException
from fastapi import Request
from fastapi.responses import JSONResponse
from sqlalchemy.exc import DBAPIError, OperationalError

logger = logging.getLogger(__name__)


def _error_payload(
    code: str, message: str, details: dict[str, Any] | None = None
) -> dict[str, Any]:
    return {
        "error": {
            "code": code,
            "message": message,
            "details": details or {},
        }
    }


async def api_error_handler(request: Request, exc: APIError) -> JSONResponse:
    """Handle APIError exceptions."""
    logger.error(
        "API Error",
        extra={
            "status_code": exc.status_code,
            "code": exc.code,
            "error_message": exc.message,
            "details": exc.details,
            "path": request.url.path,
            "method": request.method,
        },
    )

    return JSONResponse(
        status_code=exc.status_code,
        content=_error_payload(exc.code, exc.message, exc.details),
    )


async def http_exception_handler(
    request: Request,
    exc: FastAPIHTTPException,
) -> JSONResponse:
    """Handle FastAPI HTTPException and normalize the response."""
    detail = exc.detail
    if isinstance(detail, dict) and "error" in detail:
        return JSONResponse(status_code=exc.status_code, content=detail)

    message = detail if isinstance(detail, str) else "Request failed"
    code = "HTTP_ERROR"
    return JSONResponse(
        status_code=exc.status_code,
        content=_error_payload(code, message, {"status_code": exc.status_code}),
    )


async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Handle unhandled exceptions."""
    logger.exception(
        "Unhandled exception",
        extra={"path": request.url.path, "method": request.method},
    )
    return JSONResponse(
        status_code=500,
        content=_error_payload("INTERNAL_ERROR", "An internal error occurred"),
    )


def _is_db_timeout(exc: DBAPIError) -> bool:
    orig = getattr(exc, "orig", None)
    code = getattr(orig, "pgcode", None)
    if code in {"57014", "55P03"}:
        return True
    message = str(orig or exc).lower()
    return any(
        token in message
        for token in (
            "statement timeout",
            "canceling statement",
            "lock timeout",
            "timeout expired",
        )
    )


async def db_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Handle database connectivity/timeouts with a fast 503."""
    is_timeout = isinstance(exc, DBAPIError) and _is_db_timeout(exc)
    is_operational = isinstance(exc, OperationalError)
    if not (is_timeout or is_operational):
        return await unhandled_exception_handler(request, exc)

    message = "Service unavailable"
    if is_timeout:
        message = "Database request timed out"

    logger.error(
        "Database error",
        extra={
            "path": request.url.path,
            "method": request.method,
            "db_error_type": exc.__class__.__name__,
        },
    )

    return JSONResponse(
        status_code=503,
        content=_error_payload("SERVICE_UNAVAILABLE", message),
    )
