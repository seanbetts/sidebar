"""Shared Sentry bootstrap for standalone scripts and workers."""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import sentry_sdk
from sentry_sdk.integrations.sqlalchemy import SqlalchemyIntegration

from api.config import settings

_DEFAULT_PROCESS_TYPE = "script"
_sentry_initialized = False


def initialize_script_sentry(
    script_name: str,
    *,
    process_type: str = _DEFAULT_PROCESS_TYPE,
    integrations: Sequence[Any] | None = None,
) -> bool:
    """Initialize Sentry for standalone processes when configured."""
    global _sentry_initialized

    if not settings.sentry_dsn:
        return False

    if not _sentry_initialized:
        merged_integrations = _merge_integrations(integrations)
        sentry_sdk.init(
            dsn=settings.sentry_dsn,
            integrations=merged_integrations,
            traces_sample_rate=settings.sentry_traces_sample_rate,
            profiles_sample_rate=settings.sentry_profiles_sample_rate,
            environment=settings.app_env or None,
        )
        _sentry_initialized = True

    scope = sentry_sdk.get_current_scope()
    scope.set_tag("process_type", process_type)
    scope.set_tag("script_name", script_name)

    return True


def capture_script_exception(
    exc: BaseException,
    *,
    extras: dict[str, Any] | None = None,
) -> None:
    """Capture a handled exception from a standalone process."""
    if not settings.sentry_dsn:
        return

    with sentry_sdk.push_scope() as scope:
        for key, value in (extras or {}).items():
            scope.set_extra(key, value)
        sentry_sdk.capture_exception(exc)


def _merge_integrations(integrations: Sequence[Any] | None) -> list[Any]:
    merged: list[Any] = []
    seen_sqlalchemy = False

    for integration in integrations or ():
        merged.append(integration)
        if isinstance(integration, SqlalchemyIntegration):
            seen_sqlalchemy = True

    if not seen_sqlalchemy:
        merged.append(SqlalchemyIntegration())

    return merged
