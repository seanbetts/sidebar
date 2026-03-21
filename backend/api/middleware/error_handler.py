"""Error handling middleware."""

from __future__ import annotations

import logging
from typing import Any

from fastapi import HTTPException as FastAPIHTTPException
from fastapi import Request
from fastapi.responses import JSONResponse
from sqlalchemy.exc import DBAPIError, OperationalError

from api.exceptions import APIError

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
        "API error %s %s status=%s code=%s message=%s",
        request.method,
        request.url.path,
        exc.status_code,
        exc.code,
        exc.message,
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
        return JSONResponse(
            status_code=exc.status_code,
            content=detail,
            headers=exc.headers,
        )

    message = detail if isinstance(detail, str) else "Request failed"
    code = "HTTP_ERROR"
    return JSONResponse(
        status_code=exc.status_code,
        content=_error_payload(code, message, {"status_code": exc.status_code}),
        headers=exc.headers,
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


def _db_error_code(exc: Exception) -> str | None:
    orig = getattr(exc, "orig", None)
    code = getattr(orig, "pgcode", None)
    if code is None:
        return None
    return str(code)


def _db_error_message(exc: Exception) -> str:
    orig = getattr(exc, "orig", None)
    detail = orig or exc
    return str(detail)


async def db_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Handle database connectivity/timeouts with a fast 503."""
    is_timeout = isinstance(exc, DBAPIError) and _is_db_timeout(exc)
    is_operational = isinstance(exc, OperationalError)
    if not (is_timeout or is_operational):
        return await unhandled_exception_handler(request, exc)

    message = "Service unavailable"
    if is_timeout:
        message = "Database request timed out"

    db_error_code = _db_error_code(exc)
    db_error_message = _db_error_message(exc)

    logger.error(
        "Database error %s %s type=%s code=%s message=%s",
        request.method,
        request.url.path,
        exc.__class__.__name__,
        db_error_code or "-",
        db_error_message,
        extra={
            "path": request.url.path,
            "method": request.method,
            "db_error_type": exc.__class__.__name__,
            "db_error_code": db_error_code,
            "db_error_message": db_error_message,
        },
    )

    return JSONResponse(
        status_code=503,
        content=_error_payload("SERVICE_UNAVAILABLE", message),
    )
