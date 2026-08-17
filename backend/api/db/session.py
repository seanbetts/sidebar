"""Database session management."""

import logging
import os
import time
import traceback
from collections.abc import Callable, Generator
from contextlib import contextmanager
from typing import Any

from fastapi import Depends
from sqlalchemy import create_engine, event, inspect, text
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session, sessionmaker

from api.config import settings
from api.db.dependencies import get_current_user_id
from api.metrics import db_connections_active
from api.models.website import Website

logger = logging.getLogger(__name__)
_pending_website_column_lazy_loads: dict[int, dict[str, str]] = {}
_SESSION_BOOTSTRAP_MAX_ATTEMPTS = 3

# Create engine - Always use PostgreSQL
use_pooler = "pooler." in settings.database_url
pool_size = settings.db_pool_size
max_overflow = settings.db_max_overflow

engine = create_engine(
    settings.database_url,
    pool_pre_ping=True,
    pool_size=pool_size,
    max_overflow=max_overflow,
    pool_timeout=5,
    pool_recycle=300,
    connect_args={
        "connect_timeout": 5,
        "keepalives": 1,
        "keepalives_idle": 30,
        "keepalives_interval": 10,
        "keepalives_count": 5,
    },
)

_slow_query_ms = settings.db_slow_query_ms
if _slow_query_ms > 0:

    @event.listens_for(engine, "before_cursor_execute")
    def _track_query_start(conn, cursor, statement, parameters, context, executemany):
        context._query_start_time = time.monotonic()

    @event.listens_for(engine, "after_cursor_execute")
    def _log_slow_query(conn, cursor, statement, parameters, context, executemany):
        start = getattr(context, "_query_start_time", None)
        if start is None:
            return
        elapsed_ms = int((time.monotonic() - start) * 1000)
        if elapsed_ms < _slow_query_ms:
            return
        preview = " ".join(str(statement).split())
        preview = preview[:240]
        logger.warning("Slow query %sms %s", elapsed_ms, preview)


# Create SessionLocal class
SessionLocal = sessionmaker(
    autocommit=False, autoflush=False, bind=engine, expire_on_commit=False
)


@event.listens_for(engine, "checkout")
def _track_db_checkout(dbapi_connection, connection_record, connection_proxy) -> None:
    db_connections_active.inc()


@event.listens_for(engine, "checkin")
def _track_db_checkin(dbapi_connection, connection_record) -> None:
    db_connections_active.dec()


def _apply_session_settings(
    connection,
    user_id: str | None,
    force_public_search_path: bool,
    notification_worker_scope: str | None = None,
    website_worker_scope: str | None = None,
    retention_worker_scope: str | None = None,
    ingestion_worker_scope: str | None = None,
) -> None:
    if user_id:
        connection.execute(text("SET app.user_id = :user_id"), {"user_id": user_id})
    else:
        connection.execute(text("SELECT set_config('app.user_id', '', false)"))
    if notification_worker_scope:
        connection.execute(
            text("SET LOCAL app.notification_worker_scope = :worker_scope"),
            {"worker_scope": notification_worker_scope},
        )
    if website_worker_scope:
        connection.execute(
            text("SET LOCAL app.website_worker_scope = :worker_scope"),
            {"worker_scope": website_worker_scope},
        )
    if retention_worker_scope:
        connection.execute(
            text("SET LOCAL app.retention_worker_scope = :worker_scope"),
            {"worker_scope": retention_worker_scope},
        )
    if ingestion_worker_scope:
        connection.execute(
            text("SET LOCAL app.ingestion_scope = :worker_scope"),
            {"worker_scope": ingestion_worker_scope},
        )
    timeout_ms = settings.db_statement_timeout_ms
    if timeout_ms > 0:
        connection.execute(
            text("SET LOCAL statement_timeout = :timeout_ms"),
            {"timeout_ms": timeout_ms},
        )
    if force_public_search_path:
        connection.execute(text("SET search_path TO public"))


def _apply_session_settings_with_retry(
    connection,
    user_id: str | None,
    force_public_search_path: bool,
    notification_worker_scope: str | None = None,
    website_worker_scope: str | None = None,
    retention_worker_scope: str | None = None,
    ingestion_worker_scope: str | None = None,
) -> None:
    """Apply session settings and invalidate dropped connections for caller retry."""
    try:
        _apply_session_settings(
            connection,
            user_id,
            force_public_search_path,
            notification_worker_scope,
            website_worker_scope,
            retention_worker_scope,
            ingestion_worker_scope,
        )
    except OperationalError as exc:
        connection.invalidate(exc)
        raise


def _retry_session_bootstrap_operation(
    db: Session,
    operation_name: str,
    operation: Callable[[], Any],
) -> None:
    """Retry session bootstrap work after invalidating a dropped connection."""
    for attempt in range(1, _SESSION_BOOTSTRAP_MAX_ATTEMPTS + 1):
        try:
            operation()
            return
        except OperationalError:
            if attempt == _SESSION_BOOTSTRAP_MAX_ATTEMPTS:
                raise
            logger.warning(
                "Database session bootstrap failed during %s on attempt %s/%s; "
                "retrying with a fresh connection",
                operation_name,
                attempt,
                _SESSION_BOOTSTRAP_MAX_ATTEMPTS,
                exc_info=True,
            )
            db.rollback()
            db.invalidate()


@event.listens_for(Session, "after_begin")
def _set_app_user_id(session: Session, transaction, connection) -> None:
    user_id = session.info.get("app_user_id")
    force_public = bool(session.info.get("force_public_search_path")) and not bool(
        session.info.get("skip_search_path")
    )
    notification_worker_scope = session.info.get("notification_worker_scope")
    website_worker_scope = session.info.get("website_worker_scope")
    retention_worker_scope = session.info.get("retention_worker_scope")
    ingestion_worker_scope = session.info.get("ingestion_worker_scope")
    _apply_session_settings_with_retry(
        connection,
        user_id,
        force_public,
        notification_worker_scope,
        website_worker_scope,
        retention_worker_scope,
        ingestion_worker_scope,
    )


def _record_website_column_lazy_load(orm_execute_state) -> None:
    """Record SQL and stack for an upcoming deferred Website column load."""
    if not getattr(orm_execute_state, "is_column_load", False):
        return
    mapper = (getattr(orm_execute_state, "bind_arguments", {}) or {}).get("mapper")
    if mapper is None or mapper.class_ is not Website:
        return
    load_options = getattr(orm_execute_state, "load_options", None)
    refresh_state = getattr(load_options, "_refresh_state", None)
    if refresh_state is None:
        return
    _pending_website_column_lazy_loads[id(refresh_state)] = {
        "sql": " ".join(str(orm_execute_state.statement).split()),
        "stack": "".join(traceback.format_stack(limit=12)[:-1]),
    }


def _log_website_column_refresh(target: Website, context, attrs) -> None:
    """Log a deferred Website column load with SQL and stack context."""
    if target.__class__ is not Website:
        return
    if not attrs:
        return
    state = inspect(target)
    pending_trace = _pending_website_column_lazy_loads.pop(id(state), None)
    if pending_trace is None:
        return
    attr_names = ",".join(sorted(str(attr) for attr in attrs))
    logger.warning(
        "LAZY LOAD: websites.columns id=%s attrs=%s sql=%s\n%s",
        getattr(target, "id", "?"),
        attr_names,
        pending_trace["sql"],
        pending_trace["stack"],
    )


if os.getenv("TRACE_WEBSITE_CONTENT_LAZY_LOAD"):
    event.listen(Session, "do_orm_execute", _record_website_column_lazy_load)
    event.listen(Website, "refresh", _log_website_column_refresh)


def _close_session(db: Session) -> None:
    """Close a session defensively, invalidating dropped connections if needed."""
    try:
        db.close()
    except OperationalError:
        logger.warning(
            "Database session close failed; invalidating connection",
            exc_info=True,
        )
        invalidate = getattr(db, "invalidate", None)
        if callable(invalidate):
            try:
                invalidate()
            except Exception:  # pragma: no cover - defensive cleanup path
                logger.warning(
                    "Database session invalidate failed after close error",
                    exc_info=True,
                )


def get_db(
    user_id: str = Depends(get_current_user_id),
) -> Generator[Session, None, None]:
    """Dependency for getting database session."""
    db = SessionLocal()
    if os.getenv("TESTING"):
        db.info["force_public_search_path"] = True
    try:
        set_session_user_id(db, user_id)
        yield db
    finally:
        _close_session(db)


@contextmanager
def user_scoped_session(user_id: str | None) -> Generator[Session, None, None]:
    """Create a short-lived session with the same RLS scoping as requests."""
    db = SessionLocal()
    if os.getenv("TESTING"):
        db.info["force_public_search_path"] = True
    try:
        set_session_user_id(db, user_id)
        yield db
    finally:
        _close_session(db)


def set_session_user_id(db: Session, user_id: str | None) -> None:
    """Set the PostgreSQL session user_id for row-level security.

    Args:
        db: Active database session.
        user_id: User ID to set, or None to skip.
    """
    if not user_id:
        db.info.pop("app_user_id", None)
        _retry_session_bootstrap_operation(
            db,
            "RESET app.user_id",
            lambda: db.execute(text("SELECT set_config('app.user_id', '', false)")),
        )
        return
    db.info["app_user_id"] = user_id
    _retry_session_bootstrap_operation(
        db,
        "SET app.user_id",
        lambda: db.execute(text("SET app.user_id = :user_id"), {"user_id": user_id}),
    )


def set_website_worker_scope(db: Session, enabled: bool) -> None:
    """Set website worker scope for the current and future transactions.

    Args:
        db: Active database session.
        enabled: Whether cross-user worker scope should be enabled.
    """
    if enabled:
        db.info["website_worker_scope"] = "all"
        _retry_session_bootstrap_operation(
            db,
            "SET LOCAL app.website_worker_scope",
            lambda: db.execute(
                text("SET LOCAL app.website_worker_scope = :worker_scope"),
                {"worker_scope": "all"},
            ),
        )
        return

    db.info.pop("website_worker_scope", None)


def set_ingestion_worker_scope(db: Session, enabled: bool) -> None:
    """Set ingestion worker scope for the current and future transactions.

    Args:
        db: Active database session.
        enabled: Whether cross-user ingestion worker scope should be enabled.
    """
    if enabled:
        db.info["ingestion_worker_scope"] = "all"
        _retry_session_bootstrap_operation(
            db,
            "SET LOCAL app.ingestion_scope",
            lambda: db.execute(
                text("SET LOCAL app.ingestion_scope = :worker_scope"),
                {"worker_scope": "all"},
            ),
        )
        return

    db.info.pop("ingestion_worker_scope", None)


def set_notification_worker_scope(db: Session, enabled: bool) -> None:
    """Set notification-worker scope for the current and future transactions.

    Args:
        db: Active database session.
        enabled: Whether cross-user notification worker scope should be enabled.
    """
    if enabled:
        db.info["notification_worker_scope"] = "all"
        _retry_session_bootstrap_operation(
            db,
            "SET LOCAL app.notification_worker_scope",
            lambda: db.execute(
                text("SET LOCAL app.notification_worker_scope = :worker_scope"),
                {"worker_scope": "all"},
            ),
        )
        return

    db.info.pop("notification_worker_scope", None)


def set_retention_worker_scope(db: Session, enabled: bool) -> None:
    """Set retention-worker scope for the current and future transactions.

    Args:
        db: Active database session.
        enabled: Whether cross-user retention scope should be enabled.
    """
    if enabled:
        db.info["retention_worker_scope"] = "all"
        _retry_session_bootstrap_operation(
            db,
            "SET LOCAL app.retention_worker_scope",
            lambda: db.execute(
                text("SET LOCAL app.retention_worker_scope = :worker_scope"),
                {"worker_scope": "all"},
            ),
        )
        return

    db.info.pop("retention_worker_scope", None)
