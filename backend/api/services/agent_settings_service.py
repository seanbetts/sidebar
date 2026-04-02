"""Helpers for agent-managed assistant settings updates."""

from __future__ import annotations

from typing import Any

from sqlalchemy.orm import Session

from api.services.settings_service import SettingsService
from api.services.user_settings_service import UserSettingsService


class AgentSettingsService:
    """Prepare and persist assistant identity and soul updates."""

    @staticmethod
    def _merge_agent_field_update(
        value: dict[str, str] | None,
        *,
        existing_value: Any,
        allowed_fields: tuple[str, ...],
    ) -> dict[str, str] | None:
        """Merge a partial agent field update onto the existing stored payload."""
        if value is None:
            return None

        merged: dict[str, str] = {}
        if isinstance(existing_value, dict):
            for field_name in allowed_fields:
                existing_item = SettingsService._trim_text_value(
                    existing_value.get(field_name)
                )
                if existing_item is not None:
                    merged[field_name] = existing_item

        merged.update(value)
        return merged

    @staticmethod
    def prepare_agent_updates(
        db: Session,
        user_id: str,
        updates: dict[str, Any],
        *,
        reason: str | None = None,
    ) -> dict[str, Any]:
        """Validate, merge, and annotate agent-managed updates."""
        cleaned = SettingsService.clean_agent_updates(dict(updates))
        current_settings = UserSettingsService.get_settings(db, user_id)

        if "assistant_identity" in cleaned:
            merged_identity = AgentSettingsService._merge_agent_field_update(
                cleaned["assistant_identity"],
                existing_value=(
                    getattr(current_settings, "assistant_identity", None)
                    if current_settings
                    else None
                ),
                allowed_fields=SettingsService.ASSISTANT_IDENTITY_FIELDS,
            )
            cleaned["assistant_identity"] = SettingsService._apply_agent_field_meta(
                merged_identity,
                existing_value=(
                    getattr(current_settings, "assistant_identity", None)
                    if current_settings
                    else None
                ),
                reason=reason,
            )

        if "assistant_soul" in cleaned:
            merged_soul = AgentSettingsService._merge_agent_field_update(
                cleaned["assistant_soul"],
                existing_value=(
                    getattr(current_settings, "assistant_soul", None)
                    if current_settings
                    else None
                ),
                allowed_fields=SettingsService.ASSISTANT_SOUL_FIELDS,
            )
            cleaned["assistant_soul"] = SettingsService._apply_agent_field_meta(
                merged_soul,
                existing_value=(
                    getattr(current_settings, "assistant_soul", None)
                    if current_settings
                    else None
                ),
                reason=reason,
            )

        return cleaned

    @staticmethod
    def update_with_onboarding(
        db: Session,
        user_id: str,
        updates: dict[str, Any],
        *,
        onboarding: dict[str, Any],
        reason: str | None = None,
    ) -> dict[str, Any]:
        """Persist assistant settings plus onboarding state in one write."""
        cleaned = AgentSettingsService.prepare_agent_updates(
            db,
            user_id,
            updates,
            reason=reason,
        )
        user_settings = UserSettingsService.upsert_settings(
            db,
            user_id,
            onboarding=onboarding,
            assistant_identity=cleaned.get(
                "assistant_identity",
                UserSettingsService.UNSET,
            ),
            assistant_soul=cleaned.get(
                "assistant_soul",
                UserSettingsService.UNSET,
            ),
        )
        return SettingsService.build_response(user_settings, user_id, db=db)
