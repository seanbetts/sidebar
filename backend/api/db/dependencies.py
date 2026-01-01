"""FastAPI dependencies for database and auth."""
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials

from api.auth import bearer_scheme
from api.config import settings
from sqlalchemy import text
from api.models.user_settings import UserSettings
from api.supabase_jwt import SupabaseJWTValidator, JWTValidationError


DEFAULT_USER_ID = settings.default_user_id


async def get_current_user_id(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> str:
    """Extract user ID from Supabase JWT token."""
    if settings.auth_dev_mode:
        return settings.default_user_id
    if not credentials or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization header",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user_id = getattr(request.state, "user_id", None)
    if user_id:
        return user_id

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

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token: missing user ID",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return user_id
