"""Encryption helpers for user-provided BYOK credentials."""

from __future__ import annotations

import base64
import hashlib
import logging
import os

from cryptography.fernet import Fernet, InvalidToken

from api.config import settings

logger = logging.getLogger(__name__)


class ProviderKeyEncryptionService:
    """Encrypt and decrypt provider API keys at rest."""

    _fernet: Fernet | None = None

    @classmethod
    def encrypt(cls, api_key: str) -> str:
        """Encrypt a provider API key."""
        payload = api_key.encode("utf-8")
        return cls._fernet_client().encrypt(payload).decode("utf-8")

    @classmethod
    def decrypt(cls, encrypted_api_key: str) -> str:
        """Decrypt an encrypted provider API key.

        Raises:
            ValueError: If decryption fails with the current encryption key.
        """
        try:
            payload = cls._fernet_client().decrypt(encrypted_api_key.encode("utf-8"))
        except InvalidToken as exc:
            raise ValueError("Invalid encrypted provider key") from exc
        return payload.decode("utf-8")

    @classmethod
    def _fernet_client(cls) -> Fernet:
        """Return a cached Fernet client."""
        if cls._fernet is None:
            cls._fernet = Fernet(cls._resolve_fernet_key())
        return cls._fernet

    @staticmethod
    def _resolve_fernet_key() -> bytes:
        """Resolve a stable Fernet key for the current environment.

        Production requires an explicit BYOK_ENCRYPTION_KEY so encrypted user keys
        are not tied to rotatable infrastructure secrets. Non-production
        environments keep a deterministic fallback for local development and tests.
        """
        configured = settings.byok_encryption_key
        if configured:
            key_bytes = configured.encode("utf-8")
            try:
                Fernet(key_bytes)
                return key_bytes
            except Exception:
                # Allow plain strings by deriving a Fernet-compatible key.
                return base64.urlsafe_b64encode(
                    hashlib.sha256(configured.encode("utf-8")).digest()
                )

        if settings.app_env in {"prod", "production"}:
            raise ValueError("BYOK_ENCRYPTION_KEY is required in production")

        if os.getenv("TESTING"):
            return base64.urlsafe_b64encode(
                hashlib.sha256(b"sidebar-test-byok-key").digest()
            )

        fallback_secret = (
            settings.supabase_jwt_secret
            or settings.supabase_service_role_key
            or settings.bearer_token
        )
        if not fallback_secret:
            raise ValueError(
                "BYOK encryption key is not configured. Set BYOK_ENCRYPTION_KEY."
            )
        logger.warning(
            "BYOK_ENCRYPTION_KEY not set, using non-production fallback secret"
        )
        return base64.urlsafe_b64encode(
            hashlib.sha256(fallback_secret.encode("utf-8")).digest()
        )
