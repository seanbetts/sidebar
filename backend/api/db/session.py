"""Database session management."""
import os
from fastapi import Depends
from sqlalchemy import create_engine, event, text
from sqlalchemy.orm import sessionmaker, Session
from typing import Generator

from api.config import settings
from api.db.dependencies import get_current_user_id

# Create engine - Always use PostgreSQL
use_pooler = "pooler." in settings.database_url
pool_size = settings.db_pool_size
max_overflow = settings.db_max_overflow

engine = create_engine(
    settings.database_url,
    pool_pre_ping=True,
    pool_size=pool_size,
    max_overflow=max_overflow,
    pool_timeout=5
)

# Create SessionLocal class
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine, expire_on_commit=False)


@event.listens_for(Session, "after_begin")
def _set_app_user_id(session: Session, transaction, connection) -> None:
    user_id = session.info.get("app_user_id")
    if user_id:
        connection.execute(text("SET app.user_id = :user_id"), {"user_id": user_id})
    if session.info.get("force_public_search_path") and not session.info.get("skip_search_path"):
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
    db.execute(text("SET app.user_id = :user_id"), {"user_id": user_id})
