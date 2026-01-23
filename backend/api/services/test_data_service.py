"""Service for seeding and cleaning test data for a user."""

from __future__ import annotations

import uuid
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from sqlalchemy.orm import Session

from api.models.conversation import Conversation
from api.models.note import Note
from api.models.task import Task
from api.models.task_area import TaskArea
from api.models.task_project import TaskProject
from api.models.user_memory import UserMemory
from api.models.user_settings import UserSettings
from api.services.conversation_service import ConversationService
from api.services.memory_service import MemoryService
from api.services.notes_service import NotesService
from api.services.notes_workspace_service import NotesWorkspaceService
from api.services.task_service import TaskService
from api.services.tasks_snapshot_service import TasksSnapshotService
from api.services.test_data_plan import (
    SCRATCHPAD_TITLE,
    SeedPlan,
    build_seed_plan,
)
from api.services.user_settings_service import UserSettingsService
from api.services.websites_service import WebsitesService


@dataclass(frozen=True)
class SeedSummary:
    """Summary counts for seed operations."""

    notes: int = 0
    websites: int = 0
    conversations: int = 0
    memories: int = 0
    task_areas: int = 0
    task_projects: int = 0
    tasks: int = 0
    settings: int = 0
    scratchpad: int = 0


class TestDataService:
    """Service to seed and clear demo content for a user."""

    @staticmethod
    def build_seed_plan(seed_tag: str, *, now: datetime | None = None) -> SeedPlan:
        """Build a deterministic seed plan."""
        return build_seed_plan(seed_tag, now=now)

    @staticmethod
    def seed_user_data(db: Session, user_id: str, plan: SeedPlan) -> SeedSummary:
        """Seed database content for a user."""
        for folder in plan.folders:
            NotesWorkspaceService.create_folder(db, user_id, folder)

        note_ids: list[uuid.UUID] = []
        for note in plan.notes:
            created_note = NotesService.create_note(
                db,
                user_id,
                content=note.content,
                title=note.title,
                folder=note.folder,
                pinned=note.pinned,
                tags=note.tags,
            )
            note_ids.append(created_note.id)
            if note.pinned:
                NotesService.update_pinned(db, user_id, created_note.id, True)

        scratchpad_note = NotesService.get_note_by_title(
            db, user_id, SCRATCHPAD_TITLE, mark_opened=False
        )
        if scratchpad_note:
            NotesService.update_note(db, user_id, scratchpad_note.id, plan.scratchpad)
        else:
            NotesService.create_note(
                db,
                user_id,
                content=plan.scratchpad,
                title=SCRATCHPAD_TITLE,
                folder="",
                tags=["scratchpad"],
            )

        website_ids: list[uuid.UUID] = []
        for website in plan.websites:
            created_website = WebsitesService.save_website(
                db,
                user_id,
                url=website.url,
                title=website.title,
                content=website.content,
                source=website.source,
                url_full=website.url_full,
                saved_at=website.saved_at,
                published_at=website.published_at,
                pinned=website.pinned,
                archived=website.archived,
            )
            website_ids.append(created_website.id)
            if website.pinned:
                WebsitesService.update_pinned(db, user_id, created_website.id, True)

        conversation_ids: list[uuid.UUID] = []
        for conversation in plan.conversations:
            created_conversation = ConversationService.create_conversation(
                db, user_id, conversation.title
            )
            conversation_ids.append(created_conversation.id)
            for message in conversation.messages:
                ConversationService.add_message(
                    db, user_id, created_conversation.id, message
                )

        memory_ids: list[uuid.UUID] = []
        for memory in plan.memories:
            created_memory = MemoryService.create_memory(
                db, user_id, memory.path, memory.content
            )
            memory_ids.append(created_memory.id)

        area_map: dict[str, str] = {}
        project_map: dict[str, str] = {}
        for area in plan.task_areas:
            created_area = TaskService.create_task_area(
                db, user_id, area.title, source_id=plan.seed_tag
            )
            area_map[area.key] = str(created_area.id)

        for project in plan.task_projects:
            area_id = area_map.get(project.area_key) if project.area_key else None
            created_project = TaskService.create_task_project(
                db,
                user_id,
                project.title,
                area_id=area_id,
                status=project.status,
                notes=project.notes,
                source_id=plan.seed_tag,
            )
            project_map[project.key] = str(created_project.id)

        task_ids: list[uuid.UUID] = []
        for task in plan.tasks:
            project_id = project_map.get(task.project_key) if task.project_key else None
            area_id = area_map.get(task.area_key) if task.area_key else None
            created_task = TaskService.create_task(
                db,
                user_id,
                task.title,
                status=task.status,
                project_id=project_id,
                area_id=area_id,
                notes=task.notes,
                deadline=task.deadline,
                recurrence_rule=task.recurrence_rule,
                repeating=task.repeating,
                repeat_template=task.repeat_template,
                repeat_template_id=None,
                next_instance_date=task.next_instance_date,
                source_id=plan.seed_tag,
            )
            task_ids.append(created_task.id)

        db.commit()

        snapshot = TestDataService._build_tasks_snapshot(
            db, user_id, task_ids, project_map, area_map
        )
        UserSettingsService.upsert_settings(
            db,
            user_id,
            system_prompt=plan.settings.system_prompt,
            first_message_prompt=plan.settings.first_message_prompt,
            communication_style=plan.settings.communication_style,
            working_relationship=plan.settings.working_relationship,
            name=plan.settings.name,
            job_title=plan.settings.job_title,
            employer=plan.settings.employer,
            location=plan.settings.location,
            pronouns=plan.settings.pronouns,
            enabled_skills=plan.settings.enabled_skills,
            tasks_ai_snapshot=snapshot,
        )

        return SeedSummary(
            notes=len(note_ids),
            websites=len(website_ids),
            conversations=len(conversation_ids),
            memories=len(memory_ids),
            task_areas=len(area_map),
            task_projects=len(project_map),
            tasks=len(task_ids),
            settings=1,
            scratchpad=1,
        )

    @staticmethod
    def preview_delete(db: Session, user_id: str, plan: SeedPlan) -> SeedSummary:
        """Preview deletions without modifying data."""
        targets = TestDataService._collect_seed_targets(db, user_id, plan)
        return SeedSummary(
            notes=len(targets["notes"]),
            websites=len(targets["websites"]),
            conversations=len(targets["conversations"]),
            memories=len(targets["memories"]),
            task_areas=len(targets["task_areas"]),
            task_projects=len(targets["task_projects"]),
            tasks=len(targets["tasks"]),
            settings=1 if targets["settings"] else 0,
            scratchpad=1 if targets["scratchpad"] else 0,
        )

    @staticmethod
    def delete_seed_data(db: Session, user_id: str, plan: SeedPlan) -> SeedSummary:
        """Delete seed data for a user."""
        targets = TestDataService._collect_seed_targets(db, user_id, plan)

        for note in targets["notes"]:
            NotesService.delete_note(db, user_id, note.id)

        if targets["scratchpad"]:
            scratchpad_note = targets["scratchpad"]
            NotesService.update_note(
                db,
                user_id,
                scratchpad_note.id,
                f"# {SCRATCHPAD_TITLE}\n\n",
                title=SCRATCHPAD_TITLE,
            )

        for website in targets["websites"]:
            WebsitesService.delete_website(db, user_id, website.id)

        for conversation in targets["conversations"]:
            ConversationService.update_conversation(
                db, user_id, conversation.id, is_archived=True
            )

        for memory in targets["memories"]:
            MemoryService.delete_memory(db, user_id, memory.id)

        for task in targets["tasks"]:
            TaskService.delete_task(db, user_id, str(task.id))
        for project in targets["task_projects"]:
            TaskService.delete_task_project(db, user_id, str(project.id))
        for area in targets["task_areas"]:
            TaskService.delete_task_area(db, user_id, str(area.id))
        db.commit()

        if targets["settings"]:
            UserSettingsService.upsert_settings(
                db,
                user_id,
                system_prompt=None,
                first_message_prompt=None,
                communication_style=None,
                working_relationship=None,
                name=None,
                job_title=None,
                employer=None,
                location=None,
                pronouns=None,
                enabled_skills=None,
                tasks_ai_snapshot=None,
            )

        return SeedSummary(
            notes=len(targets["notes"]),
            websites=len(targets["websites"]),
            conversations=len(targets["conversations"]),
            memories=len(targets["memories"]),
            task_areas=len(targets["task_areas"]),
            task_projects=len(targets["task_projects"]),
            tasks=len(targets["tasks"]),
            settings=1 if targets["settings"] else 0,
            scratchpad=1 if targets["scratchpad"] else 0,
        )

    @staticmethod
    def _collect_seed_targets(
        db: Session, user_id: str, plan: SeedPlan
    ) -> dict[str, Any]:
        title_prefix = plan.title_prefix
        seed_tag = plan.seed_tag
        folder_set = set(plan.folders)

        notes: list[Note] = []
        for note in NotesService.list_notes(db, user_id):
            if note.title == SCRATCHPAD_TITLE:
                continue
            metadata = note.metadata_ or {}
            tags = metadata.get("tags") or []
            folder = metadata.get("folder") or ""
            if seed_tag in tags:
                notes.append(note)
                continue
            if metadata.get("folder_marker") and folder in folder_set:
                notes.append(note)

        websites = [
            website
            for website in WebsitesService.list_websites(db, user_id)
            if (website.title or "").startswith(title_prefix)
        ]

        conversations = (
            db.query(Conversation)
            .filter(
                Conversation.user_id == user_id,
                Conversation.title.startswith(title_prefix),
            )
            .all()
        )

        memories = (
            db.query(UserMemory)
            .filter(
                UserMemory.user_id == user_id,
                UserMemory.path.startswith(f"/memories/seed/{seed_tag}"),
            )
            .all()
        )

        task_areas = (
            db.query(TaskArea)
            .filter(TaskArea.user_id == user_id, TaskArea.source_id == seed_tag)
            .all()
        )
        task_projects = (
            db.query(TaskProject)
            .filter(TaskProject.user_id == user_id, TaskProject.source_id == seed_tag)
            .all()
        )
        tasks = (
            db.query(Task)
            .filter(Task.user_id == user_id, Task.source_id == seed_tag)
            .all()
        )

        settings = (
            db.query(UserSettings).filter(UserSettings.user_id == user_id).one_or_none()
        )
        if (
            settings
            and settings.system_prompt
            and seed_tag not in settings.system_prompt
        ):
            settings = None

        scratchpad_note = NotesService.get_note_by_title(
            db, user_id, SCRATCHPAD_TITLE, mark_opened=False
        )

        return {
            "notes": notes,
            "websites": websites,
            "conversations": conversations,
            "memories": memories,
            "task_areas": task_areas,
            "task_projects": task_projects,
            "tasks": tasks,
            "settings": settings,
            "scratchpad": scratchpad_note,
        }

    @staticmethod
    def _build_tasks_snapshot(
        db: Session,
        user_id: str,
        task_ids: Iterable[uuid.UUID],
        project_map: dict[str, str],
        area_map: dict[str, str],
    ) -> str | None:
        if not task_ids:
            return None
        tasks = (
            db.query(Task).filter(Task.user_id == user_id, Task.id.in_(task_ids)).all()
        )
        if not tasks:
            return None

        def task_payload(item: Task) -> dict[str, Any]:
            return {
                "id": str(item.id),
                "title": item.title,
                "status": item.status,
                "deadline": item.deadline.isoformat() if item.deadline else None,
                "notes": item.notes,
                "projectId": str(item.project_id) if item.project_id else None,
                "areaId": str(item.area_id) if item.area_id else None,
            }

        project_ids = [uuid.UUID(value) for value in project_map.values()]
        area_ids = [uuid.UUID(value) for value in area_map.values()]
        projects = (
            db.query(TaskProject)
            .filter(TaskProject.user_id == user_id, TaskProject.id.in_(project_ids))
            .all()
            if project_ids
            else []
        )
        areas = (
            db.query(TaskArea)
            .filter(TaskArea.user_id == user_id, TaskArea.id.in_(area_ids))
            .all()
            if area_ids
            else []
        )
        projects_payload = [
            {"id": str(project.id), "title": project.title} for project in projects
        ]
        areas_payload = [{"id": str(area.id), "title": area.title} for area in areas]
        return TasksSnapshotService.build_snapshot(
            today_tasks=[task_payload(task) for task in tasks],
            tomorrow_tasks=TasksSnapshotService.filter_tomorrow(
                [task_payload(task) for task in tasks]
            ),
            completed_today=[],
            areas=areas_payload,
            projects=projects_payload,
        )
