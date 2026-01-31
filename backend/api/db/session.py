"""Database session management."""

import logging
import os
import time
from collections.abc import Generator

from fastapi import Depends
from sqlalchemy import create_engine, event, text
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session, sessionmaker

from api.config import settings
from api.db.dependencies import get_current_user_id
from api.metrics import db_connections_active

logger = logging.getLogger(__name__)

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
    connection, user_id: str | None, force_public_search_path: bool
) -> None:
    if user_id:
        connection.execute(text("SET app.user_id = :user_id"), {"user_id": user_id})
    timeout_ms = settings.db_statement_timeout_ms
    if timeout_ms > 0:
        connection.execute(
            text("SET LOCAL statement_timeout = :timeout_ms"),
            {"timeout_ms": timeout_ms},
        )
    if force_public_search_path:
        connection.execute(text("SET search_path TO public"))


@event.listens_for(Session, "after_begin")
def _set_app_user_id(session: Session, transaction, connection) -> None:
    user_id = session.info.get("app_user_id")
    force_public = bool(session.info.get("force_public_search_path")) and not bool(
        session.info.get("skip_search_path")
    )
    try:
        _apply_session_settings(connection, user_id, force_public)
    except OperationalError:
        connection.invalidate()
        _apply_session_settings(connection, user_id, force_public)


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
        db.close()


def set_session_user_id(db: Session, user_id: str | None) -> None:
    """Set the PostgreSQL session user_id for row-level security.

    Args:
        db: Active database session.
        user_id: User ID to set, or None to skip.
    """
    if not user_id:
        db.info.pop("app_user_id", None)
        return
    db.info["app_user_id"] = user_id
    try:
        db.execute(text("SET app.user_id = :user_id"), {"user_id": user_id})
    except OperationalError:
        db.invalidate()
        db.execute(text("SET app.user_id = :user_id"), {"user_id": user_id})
