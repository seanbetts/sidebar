"""Unified authentication for both MCP and REST endpoints."""
from fastapi import HTTPException, status, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from api.config import settings
from api.supabase_jwt import SupabaseJWTValidator, JWTValidationError

# Unified bearer authentication (Supabase JWTs)
bearer_scheme = HTTPBearer(auto_error=True)


async def verify_supabase_jwt(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme)
) -> dict:
    """Verify Supabase JWT token and return payload."""
    if settings.auth_dev_mode:
        return {"sub": settings.default_user_id}

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
