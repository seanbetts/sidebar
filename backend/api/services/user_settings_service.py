"""Service layer for user settings."""
from __future__ import annotations

from datetime import datetime, timezone
import secrets
from typing import Optional, Any

from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

from api.models.user_settings import UserSettings


class UserSettingsService:
    """Service for managing per-user settings."""

    UNSET = object()

    @staticmethod
    def get_settings(db: Session, user_id: str) -> Optional[UserSettings]:
        """Fetch settings for a user.

        Args:
            db: Database session.
            user_id: Current user ID.

        Returns:
            UserSettings record or None.
        """
        return db.query(UserSettings).filter(UserSettings.user_id == user_id).first()

    @staticmethod
    def get_user_id_for_shortcuts_pat(db: Session, token: str) -> Optional[str]:
        """Resolve a user_id for a shortcuts PAT token."""
        record = (
            db.query(UserSettings)
            .filter(UserSettings.shortcuts_pat == token)
            .first()
        )
        if record and record.shortcuts_pat and secrets.compare_digest(record.shortcuts_pat, token):
            return record.user_id
        return None

    @staticmethod
    def upsert_settings(
        db: Session,
        user_id: str,
        *,
        system_prompt: Any = UNSET,
        first_message_prompt: Any = UNSET,
        communication_style: Any = UNSET,
        working_relationship: Any = UNSET,
        name: Any = UNSET,
        job_title: Any = UNSET,
        employer: Any = UNSET,
        date_of_birth: Any = UNSET,
        gender: Any = UNSET,
        pronouns: Any = UNSET,
        location: Any = UNSET,
        profile_image_path: Any = UNSET,
        enabled_skills: Any = UNSET,
        shortcuts_pat: Any = UNSET,
        things_ai_snapshot: Any = UNSET,
    ) -> UserSettings:
        """Create or update a user's settings.

        Args:
            db: Database session.
            user_id: Current user ID.
            system_prompt: Optional system prompt override.
            first_message_prompt: Optional first-message prompt override.
            communication_style: Optional communication style.
            working_relationship: Optional working relationship text.
            name: Optional name.
            job_title: Optional job title.
            employer: Optional employer.
            date_of_birth: Optional date of birth.
            gender: Optional gender.
            pronouns: Optional pronouns.
            location: Optional location.
            profile_image_path: Optional profile image path.
            enabled_skills: Optional list of enabled skills.
            shortcuts_pat: Optional shortcuts PAT token.

        Returns:
            Upserted UserSettings record.
        """
        now = datetime.now(timezone.utc)
        settings = UserSettingsService.get_settings(db, user_id)
        if settings:
            if system_prompt is not UserSettingsService.UNSET:
                settings.system_prompt = system_prompt
            if first_message_prompt is not UserSettingsService.UNSET:
                settings.first_message_prompt = first_message_prompt
            if communication_style is not UserSettingsService.UNSET:
                settings.communication_style = communication_style
            if working_relationship is not UserSettingsService.UNSET:
                settings.working_relationship = working_relationship
            if name is not UserSettingsService.UNSET:
                settings.name = name
            if job_title is not UserSettingsService.UNSET:
                settings.job_title = job_title
            if employer is not UserSettingsService.UNSET:
                settings.employer = employer
            if date_of_birth is not UserSettingsService.UNSET:
                settings.date_of_birth = date_of_birth
            if gender is not UserSettingsService.UNSET:
                settings.gender = gender
            if pronouns is not UserSettingsService.UNSET:
                settings.pronouns = pronouns
            if location is not UserSettingsService.UNSET:
                settings.location = location
            if profile_image_path is not UserSettingsService.UNSET:
                settings.profile_image_path = profile_image_path
            if enabled_skills is not UserSettingsService.UNSET:
                settings.enabled_skills = enabled_skills
                flag_modified(settings, "enabled_skills")
            if shortcuts_pat is not UserSettingsService.UNSET:
                settings.shortcuts_pat = shortcuts_pat
            if things_ai_snapshot is not UserSettingsService.UNSET:
                settings.things_ai_snapshot = things_ai_snapshot
            settings.updated_at = now
        else:
            settings = UserSettings(
                user_id=user_id,
                system_prompt=None if system_prompt is UserSettingsService.UNSET else system_prompt,
                first_message_prompt=None if first_message_prompt is UserSettingsService.UNSET else first_message_prompt,
                communication_style=None if communication_style is UserSettingsService.UNSET else communication_style,
                working_relationship=None if working_relationship is UserSettingsService.UNSET else working_relationship,
                name=None if name is UserSettingsService.UNSET else name,
                job_title=None if job_title is UserSettingsService.UNSET else job_title,
                employer=None if employer is UserSettingsService.UNSET else employer,
                date_of_birth=None if date_of_birth is UserSettingsService.UNSET else date_of_birth,
                gender=None if gender is UserSettingsService.UNSET else gender,
                pronouns=None if pronouns is UserSettingsService.UNSET else pronouns,
                location=None if location is UserSettingsService.UNSET else location,
                profile_image_path=None if profile_image_path is UserSettingsService.UNSET else profile_image_path,
                enabled_skills=None if enabled_skills is UserSettingsService.UNSET else enabled_skills,
                shortcuts_pat=None if shortcuts_pat is UserSettingsService.UNSET else shortcuts_pat,
                things_ai_snapshot=None if things_ai_snapshot is UserSettingsService.UNSET else things_ai_snapshot,
                created_at=now,
                updated_at=now,
            )
            db.add(settings)

        db.flush()
        db.commit()
        return settings

    @staticmethod
    def update_things_snapshot(db: Session, user_id: str, snapshot: str) -> None:
        """Update the Things AI snapshot if it has changed."""
        settings = UserSettingsService.get_settings(db, user_id)
        if settings and settings.things_ai_snapshot == snapshot:
            return
        UserSettingsService.upsert_settings(db, user_id, things_ai_snapshot=snapshot)
