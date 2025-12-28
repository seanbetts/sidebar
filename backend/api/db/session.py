"""Database session management."""
from fastapi import Depends
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session
from typing import Generator

from api.config import settings
from api.db.dependencies import get_current_user_id

# Create engine - Always use PostgreSQL
engine = create_engine(
    settings.database_url,
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10
)

# Create SessionLocal class
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine, expire_on_commit=False)


def get_db(
    user_id: str = Depends(get_current_user_id),
) -> Generator[Session, None, None]:
    """Dependency for getting database session."""
    db = SessionLocal()
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
    if user_id:
        db.execute(text("SET app.user_id = :user_id"), {"user_id": user_id})
