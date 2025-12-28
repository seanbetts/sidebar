"""Settings orchestration for profile and preference management."""
from __future__ import annotations

from datetime import date
from typing import Optional

from fastapi import HTTPException

from api.config import settings
from api.services.skill_catalog_service import SkillCatalogService
from api.services.storage.service import get_storage_backend
from api.services.user_settings_service import UserSettingsService

DEFAULT_COMMUNICATION_STYLE = """Use UK English.

Be concise and direct.

Always use markdown formatting in your response

Never use em dashes.

Follow explicit user constraints strictly (for example, if asked for two sentences, produce exactly two sentences).

Default to a casual, colleague style.

Use minimal formatting by default. Prefer prose and paragraphs over headings and lists.

Avoid bullet points and numbered lists unless I explicitly ask for a list or the response is genuinely complex.

Do not use emojis unless I use one immediately before."""

DEFAULT_WORKING_RELATIONSHIP = """Challenge my assumptions constructively when useful.

Help with brainstorming questions, simplifying complex topics, and polishing prose.

Critique drafts and use Socratic dialogue to surface blind spots.

Any non obvious claim, statistic, or figure must be backed by an authentic published source. Never fabricate citations. If you cannot source it, say you do not know."""

MAX_STYLE_CHARS = 4000
MAX_PROFILE_FIELD_CHARS = 200

storage_backend = get_storage_backend()


class SettingsService:
    @staticmethod
    def _resolve_default(value: Optional[str], default: str) -> Optional[str]:
        if value is None:
            return default
        trimmed = value.strip()
        return trimmed if trimmed else default

    @staticmethod
    def _profile_image_url(settings_record) -> Optional[str]:
        if settings_record and settings_record.profile_image_path:
            return "/api/settings/profile-image"
        return None

    @staticmethod
    def _resolve_enabled_skills(settings_record) -> list[str]:
        catalog = SkillCatalogService.list_skills(settings.skills_dir)
        all_ids = [skill["id"] for skill in catalog]
        if not settings_record or settings_record.enabled_skills is None:
            return all_ids
        enabled = [skill_id for skill_id in settings_record.enabled_skills if skill_id in all_ids]
        return enabled

    @staticmethod
    def _clean_text_field(value: Optional[str], field_name: str, max_length: int) -> Optional[str]:
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
    def build_response(settings_record, user_id: str) -> dict:
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
        }

    @staticmethod
    def clean_updates(updates: dict) -> dict:
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
            allowed = {skill["id"] for skill in catalog}
            invalid = [skill for skill in updates["enabled_skills"] if skill not in allowed]
            if invalid:
                raise HTTPException(
                    status_code=400,
                    detail=f"Invalid skills: {', '.join(invalid)}",
                )
        return updates

    @staticmethod
    def get_settings(db, user_id: str) -> dict:
        settings_record = UserSettingsService.get_settings(db, user_id)
        return SettingsService.build_response(settings_record, user_id)

    @staticmethod
    def update_settings(db, user_id: str, updates: dict) -> dict:
        cleaned = SettingsService.clean_updates(updates)
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
        return {"profile_image_url": SettingsService._profile_image_url(settings_record)}

    @staticmethod
    def get_profile_image(db, user_id: str) -> bytes:
        settings_record = UserSettingsService.get_settings(db, user_id)
        if not settings_record or not settings_record.profile_image_path:
            raise HTTPException(status_code=404, detail="Profile image not found")

        try:
            return storage_backend.get_object(settings_record.profile_image_path)
        except Exception as exc:
            raise HTTPException(status_code=404, detail="Profile image not found") from exc

    @staticmethod
    def delete_profile_image(db, user_id: str) -> dict:
        settings_record = UserSettingsService.get_settings(db, user_id)
        if not settings_record or not settings_record.profile_image_path:
            raise HTTPException(status_code=404, detail="Profile image not found")

        try:
            storage_backend.delete_object(settings_record.profile_image_path)
        except Exception as exc:
            raise HTTPException(status_code=500, detail="Failed to delete profile image") from exc

        UserSettingsService.upsert_settings(
            db,
            user_id,
            profile_image_path=None,
        )
        return {"success": True}
