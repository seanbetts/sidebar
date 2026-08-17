"""Immediate purge of all user-scoped data."""

from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy.orm import Session

from api.models.conversation import Conversation
from api.models.device_installation import DeviceInstallation, DeviceInstallationUser
from api.models.file_ingestion import FileDerivative, FileProcessingJob, IngestedFile
from api.models.note import Note
from api.models.task import Task
from api.models.task_group import TaskGroup
from api.models.task_operation_log import TaskOperationLog
from api.models.task_project import TaskProject
from api.models.task_reminder_delivery_state import TaskReminderDeliveryState
from api.models.user_ai_provider_key import UserAIProviderKey
from api.models.user_memory import UserMemory
from api.models.user_settings import UserSettings
from api.models.user_skill_state import UserSkillState
from api.models.website import Website
from api.models.website_processing_job import WebsiteProcessingJob
from api.services.file_ingestion_service import FileIngestionService
from api.services.settings_service import SettingsService
from api.services.storage.service import get_storage_backend


@dataclass
class UserPurgeSummary:
    """Aggregate counts for an immediate user-data purge."""

    rows_deleted: dict[str, int]
    storage_objects_deleted: int = 0

    @property
    def total_rows_deleted(self) -> int:
        """Return the total number of deleted database rows."""
        return sum(self.rows_deleted.values())


class UserDataPurgeService:
    """Delete all user-owned rows and storage-backed artifacts."""

    _SUMMARY_TABLES = (
        "website_processing_jobs",
        "task_operation_log",
        "task_reminder_delivery_states",
        "file_processing_jobs",
        "file_derivatives",
        "tasks",
        "task_projects",
        "task_groups",
        "notes",
        "websites",
        "ingested_files",
        "conversations",
        "user_memories",
        "user_ai_provider_keys",
        "user_skill_states",
        "device_installation_users",
        "device_installations",
        "user_settings",
    )

    @staticmethod
    def purge_user_data(db: Session, user_id: str) -> UserPurgeSummary:
        """Immediately delete all data owned by a user."""
        summary = UserPurgeSummary(
            rows_deleted=dict.fromkeys(UserDataPurgeService._SUMMARY_TABLES, 0)
        )
        storage_backend = get_storage_backend()
        if SettingsService.clear_profile_image(db, user_id, storage=storage_backend):
            summary.storage_objects_deleted = 1

        summary.rows_deleted["website_processing_jobs"] = (
            db.query(WebsiteProcessingJob)
            .filter(WebsiteProcessingJob.user_id == user_id)
            .delete(synchronize_session=False)
        )
        summary.rows_deleted["task_operation_log"] = (
            db.query(TaskOperationLog)
            .filter(TaskOperationLog.user_id == user_id)
            .delete(synchronize_session=False)
        )
        summary.rows_deleted["task_reminder_delivery_states"] = (
            db.query(TaskReminderDeliveryState)
            .filter(TaskReminderDeliveryState.user_id == user_id)
            .delete(synchronize_session=False)
        )

        file_ids = [
            file_id
            for (file_id,) in db.query(IngestedFile.id)
            .filter(IngestedFile.user_id == user_id)
            .all()
        ]
        if file_ids:
            summary.rows_deleted["file_processing_jobs"] = (
                db.query(FileProcessingJob)
                .filter(FileProcessingJob.file_id.in_(file_ids))
                .count()
            )
            summary.rows_deleted["file_derivatives"] = (
                db.query(FileDerivative)
                .filter(FileDerivative.file_id.in_(file_ids))
                .count()
            )
            for file_id in file_ids:
                FileIngestionService.hard_delete_file_metadata(db, file_id)
            summary.rows_deleted["ingested_files"] = len(file_ids)

        summary.rows_deleted["tasks"] = (
            db.query(Task)
            .filter(Task.user_id == user_id)
            .delete(synchronize_session=False)
        )
        summary.rows_deleted["task_projects"] = (
            db.query(TaskProject)
            .filter(TaskProject.user_id == user_id)
            .delete(synchronize_session=False)
        )
        summary.rows_deleted["task_groups"] = (
            db.query(TaskGroup)
            .filter(TaskGroup.user_id == user_id)
            .delete(synchronize_session=False)
        )
        summary.rows_deleted["notes"] = (
            db.query(Note)
            .filter(Note.user_id == user_id)
            .delete(synchronize_session=False)
        )
        summary.rows_deleted["websites"] = (
            db.query(Website)
            .filter(Website.user_id == user_id)
            .delete(synchronize_session=False)
        )
        summary.rows_deleted["conversations"] = (
            db.query(Conversation)
            .filter(Conversation.user_id == user_id)
            .delete(synchronize_session=False)
        )
        summary.rows_deleted["user_memories"] = (
            db.query(UserMemory)
            .filter(UserMemory.user_id == user_id)
            .delete(synchronize_session=False)
        )
        summary.rows_deleted["user_ai_provider_keys"] = (
            db.query(UserAIProviderKey)
            .filter(UserAIProviderKey.user_id == user_id)
            .delete(synchronize_session=False)
        )
        summary.rows_deleted["user_skill_states"] = (
            db.query(UserSkillState)
            .filter(UserSkillState.user_id == user_id)
            .delete(synchronize_session=False)
        )

        installation_ids = [
            installation_pk
            for (installation_pk,) in db.query(DeviceInstallationUser.installation_pk)
            .filter(DeviceInstallationUser.user_id == user_id)
            .distinct()
            .all()
        ]
        summary.rows_deleted["device_installation_users"] = (
            db.query(DeviceInstallationUser)
            .filter(DeviceInstallationUser.user_id == user_id)
            .delete(synchronize_session=False)
        )
        if installation_ids:
            orphaned_installation_ids = [
                installation_id
                for (installation_id,) in db.query(DeviceInstallation.id)
                .outerjoin(
                    DeviceInstallationUser,
                    DeviceInstallationUser.installation_pk == DeviceInstallation.id,
                )
                .filter(
                    DeviceInstallation.id.in_(installation_ids),
                    DeviceInstallationUser.id.is_(None),
                )
                .all()
            ]
            if orphaned_installation_ids:
                summary.rows_deleted["device_installations"] = (
                    db.query(DeviceInstallation)
                    .filter(DeviceInstallation.id.in_(orphaned_installation_ids))
                    .delete(synchronize_session=False)
                )

        summary.rows_deleted["user_settings"] = (
            db.query(UserSettings)
            .filter(UserSettings.user_id == user_id)
            .delete(synchronize_session=False)
        )

        db.commit()
        return summary
