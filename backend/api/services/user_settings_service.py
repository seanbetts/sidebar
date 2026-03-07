"""Service layer for user settings."""

from __future__ import annotations

import secrets
from datetime import UTC, datetime
from typing import Any

from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

from api.models.user_settings import UserSettings


class UserSettingsService:
    """Service for managing per-user settings."""

    UNSET = object()

    @staticmethod
    def get_settings(db: Session, user_id: str) -> UserSettings | None:
        """Fetch settings for a user.

        Args:
            db: Database session.
            user_id: Current user ID.

        Returns:
            UserSettings record or None.
        """
        return db.query(UserSettings).filter(UserSettings.user_id == user_id).first()

    @staticmethod
    def get_user_id_for_shortcuts_pat(db: Session, token: str) -> str | None:
        """Resolve a user_id for a shortcuts PAT token."""
        record = (
            db.query(UserSettings).filter(UserSettings.shortcuts_pat == token).first()
        )
        if (
            record
            and record.shortcuts_pat
            and secrets.compare_digest(record.shortcuts_pat, token)
        ):
            return record.user_id
        return None

    @staticmethod
    def _sync_installed_store_skills(
        db: Session,
        *,
        user_id: str,
        installed_store_skills: list[str],
    ) -> None:
        """Mirror installed Store skills into normalized skill-state rows."""
        from api.services.capabilities.skill_state_service import SkillStateService

        catalog = SkillStateService._catalog()
        store_skill_ids = SkillStateService._store_skill_ids(catalog)
        requested_skill_ids = SkillStateService._normalize_requested_skill_ids(
            installed_store_skills,
            allowed_skill_ids=store_skill_ids,
        )
        active_states = {
            state.skill_id: state
            for state in SkillStateService.list_active_skill_states(db, user_id)
        }
        target_skill_ids = set(requested_skill_ids) | {
            skill_id for skill_id in active_states if skill_id in store_skill_ids
        }
        for skill_id in target_skill_ids:
            existing_state = active_states.get(skill_id)
            next_installed = skill_id in requested_skill_ids
            next_enabled = existing_state.enabled if existing_state else False
            if not next_installed:
                next_enabled = False
            SkillStateService.upsert_skill_state(
                db,
                user_id=user_id,
                skill_id=skill_id,
                enabled=next_enabled,
                installed=next_installed,
                metadata_=(dict(existing_state.metadata_) if existing_state else {}),
                commit=False,
            )

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
        installed_store_skills: Any = UNSET,
        assistant_identity: Any = UNSET,
        assistant_soul: Any = UNSET,
        ai_primary_provider: Any = UNSET,
        shortcuts_pat: Any = UNSET,
        tasks_ai_snapshot: Any = UNSET,
        commit: bool = True,
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
            installed_store_skills: Optional list of installed store skills.
            assistant_identity: Optional assistant identity payload.
            assistant_soul: Optional assistant soul payload.
            ai_primary_provider: Optional primary AI provider override.
            shortcuts_pat: Optional shortcuts PAT token.
            tasks_ai_snapshot: Optional tasks AI snapshot payload.
            commit: Whether to commit the transaction before returning.

        Returns:
            Upserted UserSettings record.
        """
        now = datetime.now(UTC)
        should_sync_skill_states = (
            enabled_skills is not UserSettingsService.UNSET
            or installed_store_skills is not UserSettingsService.UNSET
        )
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
            if assistant_identity is not UserSettingsService.UNSET:
                settings.assistant_identity = assistant_identity
                flag_modified(settings, "assistant_identity")
            if assistant_soul is not UserSettingsService.UNSET:
                settings.assistant_soul = assistant_soul
                flag_modified(settings, "assistant_soul")
            if ai_primary_provider is not UserSettingsService.UNSET:
                settings.ai_primary_provider = ai_primary_provider
            if shortcuts_pat is not UserSettingsService.UNSET:
                settings.shortcuts_pat = shortcuts_pat
            if tasks_ai_snapshot is not UserSettingsService.UNSET:
                settings.tasks_ai_snapshot = tasks_ai_snapshot
            settings.updated_at = now
        else:
            settings = UserSettings(
                user_id=user_id,
                system_prompt=None
                if system_prompt is UserSettingsService.UNSET
                else system_prompt,
                first_message_prompt=None
                if first_message_prompt is UserSettingsService.UNSET
                else first_message_prompt,
                communication_style=None
                if communication_style is UserSettingsService.UNSET
                else communication_style,
                working_relationship=None
                if working_relationship is UserSettingsService.UNSET
                else working_relationship,
                name=None if name is UserSettingsService.UNSET else name,
                job_title=None if job_title is UserSettingsService.UNSET else job_title,
                employer=None if employer is UserSettingsService.UNSET else employer,
                date_of_birth=None
                if date_of_birth is UserSettingsService.UNSET
                else date_of_birth,
                gender=None if gender is UserSettingsService.UNSET else gender,
                pronouns=None if pronouns is UserSettingsService.UNSET else pronouns,
                location=None if location is UserSettingsService.UNSET else location,
                profile_image_path=None
                if profile_image_path is UserSettingsService.UNSET
                else profile_image_path,
                assistant_identity=None
                if assistant_identity is UserSettingsService.UNSET
                else assistant_identity,
                assistant_soul=None
                if assistant_soul is UserSettingsService.UNSET
                else assistant_soul,
                ai_primary_provider=None
                if ai_primary_provider is UserSettingsService.UNSET
                else ai_primary_provider,
                shortcuts_pat=None
                if shortcuts_pat is UserSettingsService.UNSET
                else shortcuts_pat,
                tasks_ai_snapshot=None
                if tasks_ai_snapshot is UserSettingsService.UNSET
                else tasks_ai_snapshot,
                created_at=now,
                updated_at=now,
            )
            db.add(settings)

        db.flush()
        if should_sync_skill_states:
            from api.services.capabilities.skill_state_service import SkillStateService

            if installed_store_skills is not UserSettingsService.UNSET:
                UserSettingsService._sync_installed_store_skills(
                    db,
                    user_id=user_id,
                    installed_store_skills=list(installed_store_skills or []),
                )
            if enabled_skills is not UserSettingsService.UNSET:
                SkillStateService.replace_enabled_skill_selection(
                    db,
                    user_id,
                    list(enabled_skills or []),
                    commit=False,
                )
        if commit:
            db.commit()
        return settings

    @staticmethod
    def update_tasks_snapshot(db: Session, user_id: str, snapshot: str) -> None:
        """Update the tasks AI snapshot if it has changed."""
        settings = UserSettingsService.get_settings(db, user_id)
        if settings and settings.tasks_ai_snapshot == snapshot:
            return
        UserSettingsService.upsert_settings(db, user_id, tasks_ai_snapshot=snapshot)
