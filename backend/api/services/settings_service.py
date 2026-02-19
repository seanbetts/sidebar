"""Settings orchestration for profile and preference management."""

from __future__ import annotations

import logging
import secrets
from datetime import UTC, datetime
from typing import Any

from fastapi import HTTPException

from api.config import settings
from api.services.agent.skills.catalog import SkillCatalogService
from api.services.storage.service import get_storage_backend
from api.services.user_settings_service import UserSettingsService

logger = logging.getLogger(__name__)

DEFAULT_COMMUNICATION_STYLE = """Use UK English.

Be concise and direct.

Always use markdown formatting in your response

Never use em dashes.

Follow explicit user constraints strictly
(for example, if asked for two sentences, produce exactly two sentences).

Default to a casual, colleague style.

Use minimal formatting by default. Prefer prose and paragraphs over headings and lists.

Avoid bullet points and numbered lists unless I explicitly ask for a list
or the response is genuinely complex.

Do not use emojis unless I use one immediately before."""

DEFAULT_WORKING_RELATIONSHIP = """Challenge my assumptions constructively when useful.

Help with brainstorming questions, simplifying complex topics, and polishing prose.

Critique drafts and use Socratic dialogue to surface blind spots.

Any non obvious claim, statistic, or figure must be backed by an authentic
published source. Never fabricate citations. If you cannot source it,
say you do not know."""

MAX_STYLE_CHARS = 4000
MAX_PROFILE_FIELD_CHARS = 200
MAX_ASSISTANT_IDENTITY_NAME_CHARS = 120
MAX_ASSISTANT_IDENTITY_TEXT_CHARS = 2000
MAX_ASSISTANT_SOUL_TEXT_CHARS = 3000

DEFAULT_ASSISTANT_IDENTITY = {
    "name": "sideBar",
    "tone": "Pragmatic, direct, and collaborative.",
    "boundaries": (
        "Never fabricate facts or citations, never reveal secrets, and "
        "defer to user intent when requests are ambiguous."
    ),
    "values": "Clarity, pragmatism, and rigor.",
}

DEFAULT_ASSISTANT_SOUL = {
    "purpose": (
        "Help the user think clearly, execute reliably, and make durable progress "
        "on meaningful work."
    ),
    "operating_principles": (
        "Be direct, grounded in evidence, and explicit about uncertainty."
    ),
    "adaptation_policy": (
        "Update behavior based on durable user preferences and repeated feedback, "
        "not one-off phrasing."
    ),
    "success_signals": (
        "Fewer misunderstandings, faster iteration, and outputs the user "
        "can use immediately."
    ),
}

storage_backend = get_storage_backend()


class SettingsService:
    """High-level settings operations for the API layer."""

    SHORTCUTS_PAT_PREFIX = "sb_pat_"
    ASSISTANT_IDENTITY_FIELDS = ("name", "tone", "boundaries", "values")
    ASSISTANT_SOUL_FIELDS = (
        "purpose",
        "operating_principles",
        "adaptation_policy",
        "success_signals",
    )
    USER_SETTINGS_FIELDS = (
        "communication_style",
        "working_relationship",
        "name",
        "job_title",
        "employer",
        "date_of_birth",
        "gender",
        "pronouns",
        "location",
        "enabled_skills",
    )
    AGENT_SETTINGS_FIELDS = ("assistant_identity", "assistant_soul")

    @staticmethod
    def _generate_shortcuts_pat() -> str:
        """Generate a new shortcuts PAT token."""
        return f"{SettingsService.SHORTCUTS_PAT_PREFIX}{secrets.token_urlsafe(24)}"

    @staticmethod
    def _resolve_default(value: str | None, default: str) -> str | None:
        """Return a trimmed value or the default.

        Args:
            value: Candidate value.
            default: Default to use when value is empty.

        Returns:
            Trimmed value or default.
        """
        if value is None:
            return default
        trimmed = value.strip()
        return trimmed if trimmed else default

    @staticmethod
    def _profile_image_url(settings_record) -> str | None:
        """Build a profile image URL for a settings record.

        Args:
            settings_record: User settings record or None.

        Returns:
            Profile image URL or None.
        """
        if (
            settings_record
            and settings_record.profile_image_path
            and storage_backend.object_exists(settings_record.profile_image_path)
        ):
            return "/api/settings/profile-image"
        return None

    @staticmethod
    def _required_skill_ids(catalog: list[dict[str, str | bool]]) -> list[str]:
        """Return skill IDs that users are not allowed to disable."""
        return [
            str(skill["id"])
            for skill in catalog
            if skill.get("user_toggleable", True) is False
        ]

    @staticmethod
    def _normalize_enabled_skills(
        requested: list[str],
        *,
        catalog: list[dict[str, str | bool]],
    ) -> list[str]:
        """Normalize enabled skills, preserving order and forcing required skills."""
        allowed = {str(skill["id"]) for skill in catalog}
        required = SettingsService._required_skill_ids(catalog)
        normalized: list[str] = []
        seen: set[str] = set()

        for skill_id in requested:
            if skill_id in allowed and skill_id not in seen:
                normalized.append(skill_id)
                seen.add(skill_id)

        for skill_id in required:
            if skill_id not in seen:
                normalized.append(skill_id)
                seen.add(skill_id)

        return normalized

    @staticmethod
    def _resolve_enabled_skills(settings_record) -> list[str]:
        """Resolve enabled skills against the skill catalog.

        Args:
            settings_record: User settings record or None.

        Returns:
            List of enabled skill IDs.
        """
        catalog = SkillCatalogService.list_skills(settings.skills_dir)
        all_ids = [str(skill["id"]) for skill in catalog]
        if not settings_record or settings_record.enabled_skills is None:
            return all_ids
        requested = [
            skill_id
            for skill_id in settings_record.enabled_skills
            if isinstance(skill_id, str)
        ]
        return SettingsService._normalize_enabled_skills(requested, catalog=catalog)

    @staticmethod
    def resolve_enabled_skills(settings_record) -> list[str]:
        """Return enabled skills for runtime consumers.

        Args:
            settings_record: User settings record or None.

        Returns:
            List of enabled skill IDs.
        """
        return SettingsService._resolve_enabled_skills(settings_record)

    @staticmethod
    def _resolve_assistant_identity(settings_record) -> dict[str, str]:
        """Resolve assistant identity settings with defaults.

        Args:
            settings_record: User settings record or None.

        Returns:
            Assistant identity payload.
        """
        raw = (
            getattr(settings_record, "assistant_identity", None)
            if settings_record
            else None
        )
        if not isinstance(raw, dict):
            raw = {}

        resolved: dict[str, str] = {}
        for field_name in SettingsService.ASSISTANT_IDENTITY_FIELDS:
            default = DEFAULT_ASSISTANT_IDENTITY[field_name]
            value = raw.get(field_name)
            if isinstance(value, str):
                trimmed = value.strip()
                resolved[field_name] = trimmed if trimmed else default
            else:
                resolved[field_name] = default

        return resolved

    @staticmethod
    def _resolve_assistant_soul(settings_record) -> dict[str, str]:
        """Resolve assistant soul settings with defaults."""
        raw = (
            getattr(settings_record, "assistant_soul", None)
            if settings_record
            else None
        )
        if not isinstance(raw, dict):
            raw = {}

        resolved: dict[str, str] = {}
        for field_name in SettingsService.ASSISTANT_SOUL_FIELDS:
            default = DEFAULT_ASSISTANT_SOUL[field_name]
            value = raw.get(field_name)
            if isinstance(value, str):
                trimmed = value.strip()
                resolved[field_name] = trimmed if trimmed else default
            else:
                resolved[field_name] = default
        return resolved

    @staticmethod
    def _resolve_agent_field_meta(raw_value: Any) -> dict[str, Any] | None:
        """Resolve agent field metadata from stored JSON payload."""
        if not isinstance(raw_value, dict):
            return None
        raw_meta = raw_value.get("_meta")
        if not isinstance(raw_meta, dict):
            return None

        updated_at = raw_meta.get("updated_at")
        reason = raw_meta.get("reason")
        version = raw_meta.get("version")
        if not isinstance(updated_at, str) or not updated_at.strip():
            return None
        if not isinstance(version, int) or version < 1:
            return None

        return {
            "updated_at": updated_at.strip(),
            "version": version,
            "reason": reason.strip()
            if isinstance(reason, str) and reason.strip()
            else None,
        }

    @staticmethod
    def _clean_text_field(
        value: str | None, field_name: str, max_length: int
    ) -> str | None:
        """Validate and normalize a text field.

        Args:
            value: Field value.
            field_name: Field name for error messages.
            max_length: Maximum allowed length.

        Returns:
            Trimmed value or None.

        Raises:
            HTTPException: 400 if the value exceeds max_length.
        """
        if value is None:
            return None
        trimmed = value.strip()
        if not trimmed:
            return None
        if len(trimmed) > max_length:
            raise HTTPException(
                status_code=400,
                detail=f"{field_name} exceeds max length ({max_length} characters)",
            )
        return trimmed

    @staticmethod
    def _clean_assistant_identity(value: Any) -> dict[str, str] | None:
        """Validate and normalize the assistant identity payload."""
        if value is None:
            return None
        if not isinstance(value, dict):
            raise HTTPException(
                status_code=400,
                detail="assistant_identity must be an object",
            )

        unknown_fields = sorted(
            field
            for field in value
            if field not in SettingsService.ASSISTANT_IDENTITY_FIELDS
        )
        if unknown_fields:
            raise HTTPException(
                status_code=400,
                detail=(
                    "assistant_identity has invalid fields: "
                    f"{', '.join(unknown_fields)}"
                ),
            )

        cleaned = {
            "name": SettingsService._clean_text_field(
                value.get("name"),
                "assistant_identity.name",
                MAX_ASSISTANT_IDENTITY_NAME_CHARS,
            ),
            "tone": SettingsService._clean_text_field(
                value.get("tone"),
                "assistant_identity.tone",
                MAX_ASSISTANT_IDENTITY_TEXT_CHARS,
            ),
            "boundaries": SettingsService._clean_text_field(
                value.get("boundaries"),
                "assistant_identity.boundaries",
                MAX_ASSISTANT_IDENTITY_TEXT_CHARS,
            ),
            "values": SettingsService._clean_text_field(
                value.get("values"),
                "assistant_identity.values",
                MAX_ASSISTANT_IDENTITY_TEXT_CHARS,
            ),
        }
        compact = {key: item for key, item in cleaned.items() if item is not None}
        return compact or None

    @staticmethod
    def _clean_assistant_soul(value: Any) -> dict[str, str] | None:
        """Validate and normalize the assistant soul payload."""
        if value is None:
            return None
        if not isinstance(value, dict):
            raise HTTPException(
                status_code=400,
                detail="assistant_soul must be an object",
            )

        unknown_fields = sorted(
            field
            for field in value
            if field not in SettingsService.ASSISTANT_SOUL_FIELDS
        )
        if unknown_fields:
            raise HTTPException(
                status_code=400,
                detail=(
                    "assistant_soul has invalid fields: " f"{', '.join(unknown_fields)}"
                ),
            )

        cleaned = {
            "purpose": SettingsService._clean_text_field(
                value.get("purpose"),
                "assistant_soul.purpose",
                MAX_ASSISTANT_SOUL_TEXT_CHARS,
            ),
            "operating_principles": SettingsService._clean_text_field(
                value.get("operating_principles"),
                "assistant_soul.operating_principles",
                MAX_ASSISTANT_SOUL_TEXT_CHARS,
            ),
            "adaptation_policy": SettingsService._clean_text_field(
                value.get("adaptation_policy"),
                "assistant_soul.adaptation_policy",
                MAX_ASSISTANT_SOUL_TEXT_CHARS,
            ),
            "success_signals": SettingsService._clean_text_field(
                value.get("success_signals"),
                "assistant_soul.success_signals",
                MAX_ASSISTANT_SOUL_TEXT_CHARS,
            ),
        }
        compact = {key: item for key, item in cleaned.items() if item is not None}
        return compact or None

    @staticmethod
    def _apply_agent_field_meta(
        value: dict[str, str] | None,
        *,
        existing_value: Any,
        reason: str | None,
    ) -> dict[str, Any]:
        """Attach update metadata to an agent-managed JSON payload."""
        payload: dict[str, Any] = dict(value or {})
        existing_meta = SettingsService._resolve_agent_field_meta(existing_value) or {}
        next_version = int(existing_meta.get("version", 0)) + 1
        timestamp = (
            datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")
        )
        trimmed_reason = (
            reason.strip() if isinstance(reason, str) and reason.strip() else None
        )
        payload["_meta"] = {
            "updated_at": timestamp,
            "version": next_version,
            "reason": trimmed_reason,
        }
        return payload

    @staticmethod
    def _reject_unknown_fields(
        updates: dict, *, allowed_fields: tuple[str, ...], scope_name: str
    ) -> None:
        """Reject unknown fields in a scoped settings update payload."""
        unknown_fields = sorted(
            field for field in updates if field not in allowed_fields
        )
        if unknown_fields:
            raise HTTPException(
                status_code=400,
                detail=f"{scope_name} has invalid fields: {', '.join(unknown_fields)}",
            )

    @staticmethod
    def build_response(settings_record, user_id: str) -> dict:
        """Build a settings response payload.

        Args:
            settings_record: User settings record or None.
            user_id: Current user ID.

        Returns:
            Settings response payload.
        """
        return {
            "user_id": user_id,
            "communication_style": SettingsService._resolve_default(
                settings_record.communication_style if settings_record else None,
                DEFAULT_COMMUNICATION_STYLE,
            ),
            "working_relationship": SettingsService._resolve_default(
                settings_record.working_relationship if settings_record else None,
                DEFAULT_WORKING_RELATIONSHIP,
            ),
            "name": settings_record.name if settings_record else None,
            "job_title": settings_record.job_title if settings_record else None,
            "employer": settings_record.employer if settings_record else None,
            "date_of_birth": settings_record.date_of_birth if settings_record else None,
            "gender": settings_record.gender if settings_record else None,
            "pronouns": settings_record.pronouns if settings_record else None,
            "location": settings_record.location if settings_record else None,
            "profile_image_url": SettingsService._profile_image_url(settings_record),
            "enabled_skills": SettingsService._resolve_enabled_skills(settings_record),
            "assistant_identity": SettingsService._resolve_assistant_identity(
                settings_record
            ),
            "assistant_identity_meta": SettingsService._resolve_agent_field_meta(
                getattr(settings_record, "assistant_identity", None)
                if settings_record
                else None
            ),
            "assistant_soul": SettingsService._resolve_assistant_soul(settings_record),
            "assistant_soul_meta": SettingsService._resolve_agent_field_meta(
                getattr(settings_record, "assistant_soul", None)
                if settings_record
                else None
            ),
        }

    @staticmethod
    def clean_updates(updates: dict) -> dict:
        """Normalize and validate updates payload.

        Args:
            updates: Raw updates dict.

        Returns:
            Cleaned updates dict.

        Raises:
            HTTPException: 400 for invalid values or skills.
        """
        SettingsService._reject_unknown_fields(
            updates,
            allowed_fields=SettingsService.USER_SETTINGS_FIELDS,
            scope_name="settings",
        )

        if "communication_style" in updates:
            updates["communication_style"] = SettingsService._clean_text_field(
                updates.get("communication_style"),
                "communication_style",
                MAX_STYLE_CHARS,
            )
        if "working_relationship" in updates:
            updates["working_relationship"] = SettingsService._clean_text_field(
                updates.get("working_relationship"),
                "working_relationship",
                MAX_STYLE_CHARS,
            )
        if "name" in updates:
            updates["name"] = SettingsService._clean_text_field(
                updates.get("name"),
                "name",
                MAX_PROFILE_FIELD_CHARS,
            )
        if "job_title" in updates:
            updates["job_title"] = SettingsService._clean_text_field(
                updates.get("job_title"),
                "job_title",
                MAX_PROFILE_FIELD_CHARS,
            )
        if "employer" in updates:
            updates["employer"] = SettingsService._clean_text_field(
                updates.get("employer"),
                "employer",
                MAX_PROFILE_FIELD_CHARS,
            )
        if "gender" in updates:
            updates["gender"] = SettingsService._clean_text_field(
                updates.get("gender"),
                "gender",
                MAX_PROFILE_FIELD_CHARS,
            )
        if "pronouns" in updates:
            updates["pronouns"] = SettingsService._clean_text_field(
                updates.get("pronouns"),
                "pronouns",
                MAX_PROFILE_FIELD_CHARS,
            )
        if "location" in updates:
            updates["location"] = SettingsService._clean_text_field(
                updates.get("location"),
                "location",
                MAX_PROFILE_FIELD_CHARS,
            )
        if "enabled_skills" in updates and updates["enabled_skills"] is not None:
            catalog = SkillCatalogService.list_skills(settings.skills_dir)
            allowed = {str(skill["id"]) for skill in catalog}
            invalid = [
                skill for skill in updates["enabled_skills"] if skill not in allowed
            ]
            if invalid:
                raise HTTPException(
                    status_code=400,
                    detail=f"Invalid skills: {', '.join(invalid)}",
                )
            updates["enabled_skills"] = SettingsService._normalize_enabled_skills(
                updates["enabled_skills"],
                catalog=catalog,
            )
        return updates

    @staticmethod
    def clean_agent_updates(updates: dict) -> dict:
        """Normalize and validate agent-managed settings payload."""
        SettingsService._reject_unknown_fields(
            updates,
            allowed_fields=SettingsService.AGENT_SETTINGS_FIELDS,
            scope_name="agent_settings",
        )
        if "assistant_identity" in updates:
            updates["assistant_identity"] = SettingsService._clean_assistant_identity(
                updates.get("assistant_identity")
            )
        if "assistant_soul" in updates:
            updates["assistant_soul"] = SettingsService._clean_assistant_soul(
                updates.get("assistant_soul")
            )
        return updates

    @staticmethod
    def get_settings(db, user_id: str) -> dict:
        """Fetch settings for a user.

        Args:
            db: Database session.
            user_id: Current user ID.

        Returns:
            Settings response payload.
        """
        settings_record = UserSettingsService.get_settings(db, user_id)
        return SettingsService.build_response(settings_record, user_id)

    @staticmethod
    def update_settings(db, user_id: str, updates: dict) -> dict:
        """Update settings for a user.

        Args:
            db: Database session.
            user_id: Current user ID.
            updates: Updates payload.

        Returns:
            Updated settings response payload.
        """
        cleaned = SettingsService.clean_updates(updates)
        user_settings = UserSettingsService.upsert_settings(db, user_id, **cleaned)
        return SettingsService.build_response(user_settings, user_id)

    @staticmethod
    def update_agent_settings(
        db, user_id: str, updates: dict, *, reason: str | None = None
    ) -> dict:
        """Update agent-managed settings fields for a user."""
        cleaned = SettingsService.clean_agent_updates(updates)
        current_settings = UserSettingsService.get_settings(db, user_id)
        if "assistant_identity" in cleaned:
            cleaned["assistant_identity"] = SettingsService._apply_agent_field_meta(
                cleaned["assistant_identity"],
                existing_value=(
                    getattr(current_settings, "assistant_identity", None)
                    if current_settings
                    else None
                ),
                reason=reason,
            )
        if "assistant_soul" in cleaned:
            cleaned["assistant_soul"] = SettingsService._apply_agent_field_meta(
                cleaned["assistant_soul"],
                existing_value=(
                    getattr(current_settings, "assistant_soul", None)
                    if current_settings
                    else None
                ),
                reason=reason,
            )
        user_settings = UserSettingsService.upsert_settings(db, user_id, **cleaned)
        return SettingsService.build_response(user_settings, user_id)

    @staticmethod
    def upload_profile_image(
        db,
        user_id: str,
        *,
        content_type: str,
        contents: bytes,
        filename: str,
    ) -> dict:
        """Upload a profile image to storage and update settings.

        Args:
            db: Database session.
            user_id: Current user ID.
            content_type: Image MIME type.
            contents: Image bytes.
            filename: Original filename for extension fallback.

        Returns:
            Upload result payload with profile_image_url.

        Raises:
            HTTPException: 400 for invalid payload, 500 on storage errors.
        """
        if not contents:
            raise HTTPException(status_code=400, detail="Empty image payload")

        if not content_type.startswith("image/"):
            raise HTTPException(status_code=400, detail="Invalid image type")

        if len(contents) > 2 * 1024 * 1024:
            raise HTTPException(status_code=400, detail="Image too large (max 2MB)")

        extension = "png"
        if content_type in {"image/jpeg", "image/jpg"}:
            extension = "jpg"
        elif content_type == "image/png":
            extension = "png"
        elif content_type == "image/webp":
            extension = "webp"
        elif content_type == "image/gif":
            extension = "gif"
        elif filename and "." in filename:
            extension = filename.rsplit(".", 1)[-1].lower()

        object_key = f"{user_id}/profile-images/{user_id}.{extension}"
        storage_backend.put_object(object_key, contents, content_type=content_type)

        settings_record = UserSettingsService.upsert_settings(
            db,
            user_id,
            profile_image_path=object_key,
        )
        return {
            "profile_image_url": SettingsService._profile_image_url(settings_record)
        }

    @staticmethod
    def get_profile_image(db, user_id: str) -> bytes:
        """Retrieve profile image bytes for a user.

        Args:
            db: Database session.
            user_id: Current user ID.

        Returns:
            Profile image bytes.

        Raises:
            HTTPException: 404 if no image exists.
        """
        settings_record = UserSettingsService.get_settings(db, user_id)
        if not settings_record or not settings_record.profile_image_path:
            raise HTTPException(status_code=404, detail="Profile image not found")

        try:
            return storage_backend.get_object(settings_record.profile_image_path)
        except Exception as exc:
            logger.warning(
                "Failed to load profile image from storage",
                exc_info=exc,
                extra={
                    "user_id": user_id,
                    "storage_key": settings_record.profile_image_path,
                },
            )
            raise HTTPException(
                status_code=404, detail="Profile image not found"
            ) from exc

    @staticmethod
    def delete_profile_image(db, user_id: str) -> dict:
        """Delete the user's profile image.

        Args:
            db: Database session.
            user_id: Current user ID.

        Returns:
            Delete result payload.

        Raises:
            HTTPException: 404 if no image exists, 500 on storage errors.
        """
        settings_record = UserSettingsService.get_settings(db, user_id)
        if not settings_record or not settings_record.profile_image_path:
            raise HTTPException(status_code=404, detail="Profile image not found")

        try:
            storage_backend.delete_object(settings_record.profile_image_path)
        except Exception as exc:
            logger.error(
                "Failed to delete profile image from storage",
                exc_info=exc,
                extra={
                    "user_id": user_id,
                    "storage_key": settings_record.profile_image_path,
                },
            )
            raise HTTPException(
                status_code=500, detail="Failed to delete profile image"
            ) from exc

        UserSettingsService.upsert_settings(
            db,
            user_id,
            profile_image_path=None,
        )
        return {"success": True}

    @staticmethod
    def get_or_create_shortcuts_pat(db, user_id: str) -> str:
        """Fetch the current shortcuts PAT or create a new one."""
        settings_record = UserSettingsService.get_settings(db, user_id)
        if settings_record and settings_record.shortcuts_pat:
            return settings_record.shortcuts_pat
        token = SettingsService._generate_shortcuts_pat()
        UserSettingsService.upsert_settings(db, user_id, shortcuts_pat=token)
        return token

    @staticmethod
    def rotate_shortcuts_pat(db, user_id: str) -> str:
        """Rotate the shortcuts PAT token for a user."""
        token = SettingsService._generate_shortcuts_pat()
        UserSettingsService.upsert_settings(db, user_id, shortcuts_pat=token)
        return token
