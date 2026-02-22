"""Service layer for encrypted per-user AI provider credentials."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy.orm import Session

from api.models.user_ai_provider_key import UserAIProviderKey
from api.services.ai.key_encryption import ProviderKeyEncryptionService
from api.services.ai.registry import AIProvider


class UserAIProviderKeyService:
    """Manage encrypted BYOK provider keys per user."""

    @staticmethod
    def get_active_record(
        db: Session, user_id: str, provider: AIProvider
    ) -> UserAIProviderKey | None:
        """Fetch an active provider key record."""
        return (
            db.query(UserAIProviderKey)
            .filter(
                UserAIProviderKey.user_id == user_id,
                UserAIProviderKey.provider == provider,
                UserAIProviderKey.deleted_at.is_(None),
            )
            .first()
        )

    @staticmethod
    def get_active_key(db: Session, user_id: str, provider: AIProvider) -> str | None:
        """Return the decrypted active key for a provider, if present."""
        record = UserAIProviderKeyService.get_active_record(db, user_id, provider)
        if not record:
            return None
        return ProviderKeyEncryptionService.decrypt(record.encrypted_api_key)

    @staticmethod
    def has_active_key(db: Session, user_id: str, provider: AIProvider) -> bool:
        """Return True when an active key exists for this user/provider."""
        record = UserAIProviderKeyService.get_active_record(db, user_id, provider)
        return record is not None

    @staticmethod
    def upsert_key(
        db: Session,
        user_id: str,
        provider: AIProvider,
        api_key: str,
        *,
        commit: bool = True,
    ) -> UserAIProviderKey:
        """Create or update an encrypted key for a user/provider."""
        normalized = api_key.strip()
        if len(normalized) < 8:
            raise ValueError("Invalid provider API key")

        now = datetime.now(UTC)
        encrypted = ProviderKeyEncryptionService.encrypt(normalized)
        key_last4 = normalized[-4:]
        existing = UserAIProviderKeyService.get_active_record(db, user_id, provider)
        if existing:
            existing.encrypted_api_key = encrypted
            existing.key_last4 = key_last4
            existing.updated_at = now
            if commit:
                db.commit()
                db.refresh(existing)
            else:
                db.flush()
            return existing

        record = UserAIProviderKey(
            user_id=user_id,
            provider=provider,
            encrypted_api_key=encrypted,
            key_last4=key_last4,
            created_at=now,
            updated_at=now,
            deleted_at=None,
        )
        db.add(record)
        if commit:
            db.commit()
            db.refresh(record)
        else:
            db.flush()
        return record

    @staticmethod
    def soft_delete_key(
        db: Session,
        user_id: str,
        provider: AIProvider,
        *,
        commit: bool = True,
    ) -> bool:
        """Soft delete the active key for a user/provider."""
        existing = UserAIProviderKeyService.get_active_record(db, user_id, provider)
        if not existing:
            return False
        now = datetime.now(UTC)
        existing.deleted_at = now
        existing.updated_at = now
        if commit:
            db.commit()
        else:
            db.flush()
        return True
