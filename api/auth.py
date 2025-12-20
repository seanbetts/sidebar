"""Unified authentication for both MCP and REST endpoints."""
from fastapi import Security, HTTPException, status, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from api.config import settings

# Unified bearer token authentication (both MCP and REST)
bearer_scheme = HTTPBearer(auto_error=True)


async def verify_bearer_token(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme)
) -> str:
    """Verify bearer token for all endpoints."""
    if credentials.credentials != settings.bearer_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid bearer token",
            headers={"WWW-Authenticate": "Bearer"}
        )
    return credentials.credentials


# Future: JWT-based authentication with user identity
# from jose import jwt, JWTError
#
# async def verify_jwt_token(
#     credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme)
# ):
#     """Verify JWT token with expiry and user identity."""
#     try:
#         payload = jwt.decode(
#             credentials.credentials,
#             settings.jwt_secret,
#             algorithms=[settings.jwt_algorithm]
#         )
#         user_id = payload.get("sub")
#         if not user_id:
#             raise HTTPException(status_code=401, detail="Invalid token")
#         return {"user_id": user_id}
#     except JWTError:
#         raise HTTPException(status_code=401, detail="Invalid token")
