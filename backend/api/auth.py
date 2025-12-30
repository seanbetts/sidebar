"""Unified authentication for both MCP and REST endpoints."""
import logging
from fastapi import HTTPException, status, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from api.config import settings
from api.supabase_jwt import SupabaseJWTValidator, JWTValidationError

# Unified bearer authentication (Supabase JWTs)
bearer_scheme = HTTPBearer(auto_error=False)
logger = logging.getLogger(__name__)


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


# Backward-compatible alias for existing router dependencies
verify_bearer_token = verify_supabase_jwt
