"""Database session management."""

import os
from collections.abc import Generator

from fastapi import Depends
from sqlalchemy import create_engine, event, text
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session, sessionmaker

from api.config import settings
from api.db.dependencies import get_current_user_id
from api.metrics import db_connections_active

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


@event.listens_for(Session, "after_begin")
def _set_app_user_id(session: Session, transaction, connection) -> None:
    user_id = session.info.get("app_user_id")
    if user_id:
        try:
            connection.execute(text("SET app.user_id = :user_id"), {"user_id": user_id})
        except OperationalError:
            connection.invalidate()
            connection.execute(text("SET app.user_id = :user_id"), {"user_id": user_id})
    if session.info.get("force_public_search_path") and not session.info.get(
        "skip_search_path"
    ):
        try:
            connection.execute(text("SET search_path TO public"))
        except OperationalError:
            connection.invalidate()
            connection.execute(text("SET search_path TO public"))


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
