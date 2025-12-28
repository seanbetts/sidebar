"""FastAPI dependencies for database and auth."""
from fastapi import Header, HTTPException, status
from typing import Annotated


DEFAULT_USER_ID = "81326b53-b7eb-42e2-b645-0c03cb5d5dd4"


def get_current_user_id(
    x_user_id: Annotated[str | None, Header()] = None
) -> str:
    """Get current user ID from X-User-ID header.

    For now, this is a simple header-based auth.
    In production, this would validate JWT tokens and extract user_id.
    """
    if not x_user_id:
        # Default to a stable UUID for development
        return DEFAULT_USER_ID

    return x_user_id
