"""FastAPI dependencies for database and auth."""

import os
from pathlib import Path

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy import text

from api.auth import bearer_scheme
from api.config import settings
from api.models.user_settings import UserSettings
from api.supabase_jwt import JWTValidationError, SupabaseJWTValidator

_LOCAL_APP_ENVS = {"local", "dev", "development", "test", "testing"}
_ACTIVE_USER_FILE_ENV = "INGESTION_ACTIVE_USER_FILE"
_DEFAULT_ACTIVE_USER_FILE = "/tmp/sidebar-active-user-id"


def _resolve_test_user_id() -> str:
    user_id = settings.get_test_user_id()
    if user_id:
        return user_id
    if settings.auth_dev_mode or os.getenv("TESTING"):
        raise RuntimeError(
            "TEST_USER_ID must be set when AUTH_DEV_MODE or TESTING is enabled."
        )
    return ""


def get_tool_user_id() -> str:
    """Return user ID used for scoped tool execution paths."""
    return _resolve_test_user_id()


def _persist_local_active_user_id(user_id: str) -> None:
    app_env = (settings.app_env or "").strip().lower()
    if app_env not in _LOCAL_APP_ENVS:
        return
    normalized = (user_id or "").strip()
    if not normalized:
        return
    target = Path(os.getenv(_ACTIVE_USER_FILE_ENV, _DEFAULT_ACTIVE_USER_FILE))
    tmp_target = target.with_suffix(f"{target.suffix}.tmp")
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        tmp_target.write_text(normalized, encoding="utf-8")
        tmp_target.replace(target)
    except OSError:
        # Best-effort hint for local ingestion worker scoping.
        return


async def get_current_user_id(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),  # noqa: B008
) -> str:
    """Extract user ID from Supabase JWT token."""
    if settings.auth_dev_mode and not settings.allow_auth_dev_mode:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="AUTH_DEV_MODE requires APP_ENV=local",
            headers={"WWW-Authenticate": "Bearer"},
        )
    if settings.auth_dev_mode and (not credentials or not credentials.credentials):
        user_id = _resolve_test_user_id()
        _persist_local_active_user_id(user_id)
        return user_id
    if not credentials or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization header",
            headers={"WWW-Authenticate": "Bearer"},
        )

    state_user_id = getattr(request.state, "user_id", None)
    if state_user_id:
        state_user_id_str = str(state_user_id)
        _persist_local_active_user_id(state_user_id_str)
        return state_user_id_str

    token = credentials.credentials
    if token.startswith("sb_pat_"):
        from api.db.session import SessionLocal

        with SessionLocal() as db:
            db.execute(text("SET app.pat_token = :token"), {"token": token})
            record = (
                db.query(UserSettings)
                .filter(UserSettings.shortcuts_pat == token)
                .first()
            )
        if not record:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid API token",
                headers={"WWW-Authenticate": "Bearer"},
            )
        request.state.user_id = record.user_id
        _persist_local_active_user_id(str(record.user_id))
        return record.user_id

    validator = SupabaseJWTValidator()
    try:
        payload = await validator.validate_token(token)
    except JWTValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid JWT: {exc}",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc

    jwt_user_id = payload.get("sub")
    if not isinstance(jwt_user_id, str) or not jwt_user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token: missing user ID",
            headers={"WWW-Authenticate": "Bearer"},
        )

    _persist_local_active_user_id(jwt_user_id)
    return jwt_user_id
