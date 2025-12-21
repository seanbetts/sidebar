"""FastAPI dependencies for database and auth."""
from fastapi import Header, HTTPException, status
from typing import Annotated


def get_current_user_id(
    x_user_id: Annotated[str | None, Header()] = None
) -> str:
    """
    Get current user ID from X-User-ID header.

    For now, this is a simple header-based auth.
    In production, this would validate JWT tokens and extract user_id.
    """
    if not x_user_id:
        # Default to 'default_user' for development
        return "default_user"

    return x_user_id
