"""Tests for API error handling middleware."""

from __future__ import annotations

import asyncio
import logging

from fastapi import Request
from sqlalchemy.exc import OperationalError

from api.middleware.error_handler import db_exception_handler


class _FakeDBError(Exception):
    def __init__(self, message: str, pgcode: str | None) -> None:
        super().__init__(message)
        self.pgcode = pgcode


def _request(path: str = "/api/v1/websites") -> Request:
    return Request(
        {
            "type": "http",
            "method": "GET",
            "path": path,
            "headers": [],
        }
    )


def _operational_error(*, pgcode: str | None, message: str) -> OperationalError:
    orig = _FakeDBError(message, pgcode)
    return OperationalError("SET LOCAL app.website_worker_scope = %(worker_scope)s", {}, orig)


def test_db_exception_handler_logs_operational_error_details(caplog) -> None:
    """Operational DB errors should log the underlying database detail."""
    exc = _operational_error(
        pgcode="08006",
        message="SSL connection has been closed unexpectedly",
    )

    with caplog.at_level(logging.ERROR):
        response = asyncio.run(db_exception_handler(_request(), exc))

    assert response.status_code == 503
    assert b"Service unavailable" in response.body
    assert "Database error GET /api/v1/websites" in caplog.text
    assert "type=OperationalError" in caplog.text
    assert "code=08006" in caplog.text
    assert "SSL connection has been closed unexpectedly" in caplog.text


def test_db_exception_handler_logs_timeout_details(caplog) -> None:
    """Timeout-classified DB errors should expose timeout context in logs."""
    exc = _operational_error(
        pgcode="57014",
        message="canceling statement due to statement timeout",
    )

    with caplog.at_level(logging.ERROR):
        response = asyncio.run(db_exception_handler(_request("/api/v1/health"), exc))

    assert response.status_code == 503
    assert b"Database request timed out" in response.body
    assert "Database error GET /api/v1/health" in caplog.text
    assert "code=57014" in caplog.text
    assert "statement timeout" in caplog.text
