"""Supabase JWT validation utilities."""
from __future__ import annotations

import json
import time
from typing import Any

import httpx
import jwt

from api.config import settings

_jwks_cache: dict[str, Any] | None = None
_jwks_expires_at: float = 0.0


class JWTValidationError(Exception):
    """Raised when a JWT cannot be validated."""


class SupabaseJWTValidator:
    """Validate Supabase-issued JWTs using cached JWKS."""

    def __init__(self, supabase_url: str | None = None) -> None:
        self.supabase_url = supabase_url or settings.supabase_url
        if not self.supabase_url:
            raise JWTValidationError("Supabase URL is not configured.")

    async def _fetch_jwks(self) -> dict[str, Any]:
        global _jwks_cache, _jwks_expires_at

        now = time.time()
        if _jwks_cache and now < _jwks_expires_at:
            return _jwks_cache

        jwks_url = f"{self.supabase_url}/auth/v1/.well-known/jwks.json"
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(jwks_url)
            response.raise_for_status()
            data = response.json()

        _jwks_cache = data
        _jwks_expires_at = now + settings.jwks_cache_ttl_seconds
        return data

    def _get_issuer(self) -> str:
        if settings.jwt_issuer:
            return settings.jwt_issuer
        return f"{self.supabase_url}/auth/v1"

    async def validate_token(self, token: str) -> dict[str, Any]:
        """Validate JWT and return payload.

        Args:
            token: Supabase JWT token string.

        Returns:
            Decoded JWT payload.

        Raises:
            JWTValidationError: If token is invalid or missing required claims.
        """
        if not token:
            raise JWTValidationError("Missing token.")

        jwks = await self._fetch_jwks()
        header = jwt.get_unverified_header(token)
        kid = header.get("kid")
        alg = header.get("alg") or settings.jwt_algorithm
        if alg not in settings.jwt_algorithms:
            raise JWTValidationError(f"Unsupported JWT algorithm: {alg}")
        if not kid:
            raise JWTValidationError("Missing key ID in token header.")

        keys = jwks.get("keys", [])
        key = next((item for item in keys if item.get("kid") == kid), None)
        if not key:
            raise JWTValidationError("No matching JWKS key found.")

        algorithms = jwt.algorithms.get_default_algorithms()
        algorithm = algorithms.get(alg)
        if not algorithm:
            raise JWTValidationError(f"Unsupported JWT algorithm: {alg}")
        public_key = algorithm.from_jwk(json.dumps(key))
        try:
            payload = jwt.decode(
                token,
                public_key,
                algorithms=[alg],
                audience=settings.jwt_audience,
                issuer=self._get_issuer(),
            )
        except jwt.PyJWTError as exc:
            raise JWTValidationError(str(exc)) from exc

        return payload
