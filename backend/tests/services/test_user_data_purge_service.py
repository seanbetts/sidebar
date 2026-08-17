"""Tests for immediate user-data purge coverage."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, date, datetime

from api.models.conversation import Conversation
from api.models.device_installation import DeviceInstallation, DeviceInstallationUser
from api.models.file_ingestion import FileDerivative, FileProcessingJob, IngestedFile
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
from api.services.device_installation_service import DeviceInstallationService
from api.services.file_ingestion_service import FileIngestionService
from api.services.notes_document_types import note_document_from_plain_text
from api.services.notes_service import NotesService
from api.services.task_service import TaskService
from api.services.task_reminder_delivery_state_service import (
    TaskReminderDeliveryStateService,
)
from api.services.user_ai_provider_key_service import UserAIProviderKeyService
from api.services.user_data_purge_service import UserDataPurgeService
from api.services.user_settings_service import UserSettingsService
from api.services.websites_service import WebsitesService


@dataclass
class FakeStorage:
    """Minimal storage backend test double."""

    deleted_keys: list[str] = field(default_factory=list)

    def delete_object(self, key: str) -> None:
        """Record deleted object keys."""
        self.deleted_keys.append(key)


def _seed_user_scope(test_db, *, user_id: str, with_profile_image: bool) -> None:
    note = NotesService.create_note(
        test_db,
        user_id,
        note_document_from_plain_text("# Purge note\n\nBody"),
    )
    WebsitesService.save_website(
        test_db,
        user_id,
        url="https://example.com/purge",
        title="Purge website",
        content="website body",
    )
    file_record, file_job = FileIngestionService.create_ingestion(
        test_db,
        user_id,
        filename_original="purge.pdf",
        path=f"{user_id}/files/purge.pdf",
        mime_original="application/pdf",
        size_bytes=128,
    )
    derivative = FileDerivative(
        file_id=file_record.id,
        kind="viewer_pdf",
        storage_key=f"{user_id}/files/purge/viewer.pdf",
        mime="application/pdf",
        size_bytes=64,
    )
    group = TaskGroup(user_id=user_id, title="Purge group")
    test_db.add(group)
    test_db.flush()
    project = TaskProject(user_id=user_id, title="Purge project", group_id=group.id)
    test_db.add(project)
    test_db.flush()
    task = TaskService.create_task(test_db, user_id, "Purge task")
    task.project_id = project.id
    task.group_id = group.id
    installation = DeviceInstallationService.register_installation(
        test_db,
        user_id,
        installation_id=f"install-{user_id}",
        token=f"token-{user_id}",
        platform="ios",
        environment="prod",
    )

    test_db.add_all(
        [
            derivative,
            Conversation(
                user_id=user_id,
                title="Purge conversation",
                messages=[{"role": "user", "content": "hello"}],
                message_count=1,
            ),
            UserMemory(
                user_id=user_id,
                path="memory.md",
                content="Important memory",
            ),
            UserSkillState(
                user_id=user_id,
                skill_id="test-skill",
                enabled=True,
                installed=True,
            ),
            WebsiteProcessingJob(
                user_id=user_id,
                url="https://example.com/purge-job",
                status="queued",
                website_id=None,
            ),
            TaskOperationLog(
                user_id=user_id,
                operation_id="purge-op-1",
                operation_type="add",
                payload={},
            ),
        ]
    )
    UserAIProviderKeyService.upsert_key(
        test_db,
        user_id=user_id,
        provider="openai",
        api_key="sk-openai-abcdef1234",
    )
    profile_image_path = None
    if with_profile_image:
        profile_image_path = f"{user_id}/profile-images/{user_id}.png"
    UserSettingsService.upsert_settings(
        test_db,
        user_id,
        profile_image_path=profile_image_path,
    )
    test_db.flush()
    TaskReminderDeliveryStateService.mark_delivery_accepted(
        test_db,
        user_id=user_id,
        schedule_timezone="Europe/London",
        local_date=date(2026, 1, 15),
        delivery_key="ios:task:purge-task",
        accepted_at=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )

    # Seed a second user on the same installation so purge does not delete
    # installations that still belong to another account.
    DeviceInstallationService.register_installation(
        test_db,
        "user-2",
        installation_id=f"install-{user_id}",
        token=f"token-{user_id}",
        platform="ios",
        environment="prod",
    )
    orphan_installation = DeviceInstallation(
        installation_id=f"orphan-{user_id}",
        token=f"orphan-token-{user_id}",
        platform="ios",
        environment="prod",
        capabilities={},
    )
    test_db.add(orphan_installation)
    test_db.flush()
    test_db.add(
        DeviceInstallationUser(
            installation_pk=orphan_installation.id,
            user_id=user_id,
        )
    )
    test_db.commit()

    assert note.id is not None
    assert file_job.id is not None


def test_purge_user_data_removes_all_user_scoped_rows_and_profile_image(
    test_db, monkeypatch
) -> None:
    storage = FakeStorage()
    monkeypatch.setattr(
        "api.services.user_data_purge_service.get_storage_backend",
        lambda: storage,
    )
    _seed_user_scope(test_db, user_id="user-1", with_profile_image=True)

    summary = UserDataPurgeService.purge_user_data(test_db, "user-1")

    assert summary.rows_deleted["notes"] == 1
    assert summary.rows_deleted["websites"] == 1
    assert summary.rows_deleted["conversations"] == 1
    assert summary.rows_deleted["user_settings"] == 1
    assert summary.rows_deleted["task_reminder_delivery_states"] == 1
    assert summary.rows_deleted["file_processing_jobs"] == 1
    assert summary.rows_deleted["file_derivatives"] == 1
    assert summary.rows_deleted["device_installation_users"] == 2
    assert summary.rows_deleted["device_installations"] == 1
    assert summary.storage_objects_deleted == 1
    assert storage.deleted_keys == ["user-1/profile-images/user-1.png"]

    assert test_db.query(Conversation).filter_by(user_id="user-1").count() == 0
    assert (
        test_db.query(DeviceInstallationUser).filter_by(user_id="user-1").count() == 0
    )
    assert test_db.query(FileProcessingJob).count() == 0
    assert test_db.query(IngestedFile).filter_by(user_id="user-1").count() == 0
    assert test_db.query(Task).filter_by(user_id="user-1").count() == 0
    assert test_db.query(TaskProject).filter_by(user_id="user-1").count() == 0
    assert test_db.query(TaskGroup).filter_by(user_id="user-1").count() == 0
    assert test_db.query(UserAIProviderKey).filter_by(user_id="user-1").count() == 0
    assert test_db.query(UserMemory).filter_by(user_id="user-1").count() == 0
    assert test_db.query(UserSettings).filter_by(user_id="user-1").count() == 0
    assert test_db.query(UserSkillState).filter_by(user_id="user-1").count() == 0
    assert test_db.query(Website).filter_by(user_id="user-1").count() == 0
    assert test_db.query(WebsiteProcessingJob).filter_by(user_id="user-1").count() == 0
    assert test_db.query(TaskOperationLog).filter_by(user_id="user-1").count() == 0
    assert (
        test_db.query(TaskReminderDeliveryState).filter_by(user_id="user-1").count()
        == 0
    )

    assert (
        test_db.query(DeviceInstallationUser).filter_by(user_id="user-2").count() == 1
    )
    assert test_db.query(DeviceInstallation).count() == 1


def test_purge_user_data_is_idempotent(test_db, monkeypatch) -> None:
    monkeypatch.setattr(
        "api.services.user_data_purge_service.get_storage_backend",
        lambda: FakeStorage(),
    )
    _seed_user_scope(test_db, user_id="user-1", with_profile_image=False)

    first = UserDataPurgeService.purge_user_data(test_db, "user-1")
    second = UserDataPurgeService.purge_user_data(test_db, "user-1")

    assert first.total_rows_deleted > 0
    assert first.storage_objects_deleted == 0
    assert second.total_rows_deleted == 0
    assert second.storage_objects_deleted == 0
