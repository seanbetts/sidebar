"""Unified authentication for both MCP and REST endpoints."""
import logging
from fastapi import HTTPException, status, Depends, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy import text

from api.config import settings
from api.models.user_settings import UserSettings
from api.supabase_jwt import SupabaseJWTValidator, JWTValidationError

# Unified bearer authentication (Supabase JWTs)
bearer_scheme = HTTPBearer(auto_error=False)
logger = logging.getLogger(__name__)


async def verify_bearer_token(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> dict:
    """Verify Supabase JWT or Shortcuts PAT token and return payload."""
    if settings.auth_dev_mode:
        if not settings.allow_auth_dev_mode:
            logger.warning("AUTH_DEV_MODE is enabled outside local/test environment.")
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="AUTH_DEV_MODE requires APP_ENV=local",
            )
        request.state.user_id = settings.default_user_id
        return {"sub": settings.default_user_id}
    if not credentials or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization header",
            headers={"WWW-Authenticate": "Bearer"},
        )

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
        return {"sub": record.user_id}

    validator = SupabaseJWTValidator()
    try:
        payload = await validator.validate_token(token)
    except JWTValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid JWT: {exc}",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    user_id = payload.get("sub")
    if user_id:
        request.state.user_id = user_id
    return payload


async def verify_supabase_jwt(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme)
) -> dict:
    """Verify Supabase JWT token and return payload."""
    if settings.auth_dev_mode:
        if not settings.allow_auth_dev_mode:
            logger.warning("AUTH_DEV_MODE is enabled outside local/test environment.")
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="AUTH_DEV_MODE requires APP_ENV=local",
            )
        return {"sub": settings.default_user_id}
    if not credentials or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization header",
            headers={"WWW-Authenticate": "Bearer"},
        )

    validator = SupabaseJWTValidator()
    try:
        return await validator.validate_token(credentials.credentials)
    except JWTValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid JWT: {exc}",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
