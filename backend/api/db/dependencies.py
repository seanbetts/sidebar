"""FastAPI dependencies for database and auth."""
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials

from api.auth import bearer_scheme
from api.config import settings
from api.supabase_jwt import SupabaseJWTValidator, JWTValidationError


DEFAULT_USER_ID = settings.default_user_id


async def get_current_user_id(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> str:
    """Extract user ID from Supabase JWT token."""
    if settings.auth_dev_mode:
        return settings.default_user_id

    user_id = getattr(request.state, "user_id", None)
    if user_id:
        return user_id

    validator = SupabaseJWTValidator()
    try:
        payload = await validator.validate_token(credentials.credentials)
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
