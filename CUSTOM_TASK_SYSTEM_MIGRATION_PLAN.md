# Custom Task System Migration Plan

**Date**: 2026-01-11
**Feature**: Native PostgreSQL Task System (LegacyTasks Replacement)

---

## Overview

Replace the LegacyTasks bridge-based task system with a native PostgreSQL implementation to achieve data ownership, offline-first capability, and dramatically improved performance. This migration eliminates the three-layer architecture (Backend → Bridge → AppleScript → LegacyTasks) in favor of direct database access.

**Key Feature:** Full repeating task support with auto-creation of next instances (covers 100% of user's 20 existing repeating tasks).

### Current Architecture

```
Frontend → Backend API → Bridge (127.0.0.1:8787) → AppleScript → LegacyTasks DB
- 5-minute cache TTL
- 10-second AppleScript timeout
- Requires local bridge running
- macOS only
```

### Target Architecture

```
Frontend → Backend API → PostgreSQL
- Direct SQL queries (<50ms)
- Offline-first with client-side cache + outbox sync
- Cross-platform ready
- Full data ownership
- Native recurrence logic (daily, weekly, monthly with intervals)
```

---

## Key Design Decisions

**Data Migration:**
- ✅ One-time import of active LegacyTasks data via existing bridge
- ✅ **Filter out** completed, trashed, and canceled tasks (keep only active/open tasks)
- ✅ Import active areas and projects only
- ✅ Preserve LegacyTasks IDs for reference/rollback
- ✅ Create snapshot before migration for safety

**Database Schema:**
- ✅ Mirror LegacyTasks structure: Areas → Projects → Tasks hierarchy
- ✅ Store tags as JSONB array for flexibility
- ✅ Track completion with `completed_at` timestamp
- ✅ Soft deletes only via `deleted_at` (no hard deletes for user data)
- ✅ Define status semantics: store inbox/someday/completed/trashed; today/upcoming derived from dates in service layer
- ✅ Store recurrence rules as JSONB (daily, weekly, monthly with intervals)
- ✅ Auto-create next instances when repeating tasks completed (idempotent with template linkage)
- ✅ RLS enforced with per-request `SET LOCAL app.current_user_id` session setting

**API Compatibility:**
- ✅ Keep existing REST endpoint structure
- ✅ Minimal frontend changes (same API contract)
- ✅ Replace bridge client with direct DB queries
- ✅ Maintain response schemas for backward compatibility

**Performance Strategy:**
- ✅ PostgreSQL indexes on frequently queried fields
- ✅ Materialized view for counts (optional optimization)
- ✅ Frontend cache TTL reduced from 5 minutes to 1 minute
- ✅ Optimistic updates for instant UI feedback

**Bridge Decommission:**
- ✅ Keep bridge code for emergency data sync
- ✅ Disable bridge auto-start after migration
- ✅ Optionally maintain read-only LegacyTasks sync
- ✅ Archive bridge in separate branch for reference

---

## Success Criteria

- ✅ All **active** LegacyTasks data imported successfully (completed/trashed filtered out)
- ✅ All 20 repeating tasks imported with correct recurrence rules
- ✅ Repeating tasks auto-create next instance on completion
- ✅ Task list loads in <100ms (vs current ~500ms with bridge)
- ✅ Full CRUD operations working (create, read, update, complete, soft-delete)
- ✅ Search functionality matches or exceeds current capability
- ✅ Counts/badges update in real-time
- ✅ No regressions in existing UI/UX
- ✅ Offline-first: local tasks readable offline; queued edits sync on reconnect
- ✅ Zero downtime migration path
- ✅ Rollback plan if issues arise

---

## Phase 1: Database Schema & Models (2-3 days)

### Objectives
- Design PostgreSQL schema for tasks, projects, areas
- Create SQLAlchemy models
- Add indexes for performance
- Run migrations

### 1.1 Database Schema Design

**File: `/backend/api/alembic/versions/20260111_1500-030_create_task_system_schema.py` (NEW)**

```python
"""Create native task system schema"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID, JSONB

def upgrade() -> None:
    # Areas table
    op.create_table(
        'task_areas',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('tasks_id', sa.String(255), nullable=True, unique=True, index=True),  # Original LegacyTasks ID
        sa.Column('title', sa.String(500), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.Index('idx_task_areas_user_id', 'user_id'),
        sa.Index('idx_task_areas_deleted_at', 'deleted_at'),
    )

    # Projects table
    op.create_table(
        'task_projects',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('tasks_id', sa.String(255), nullable=True, unique=True, index=True),
        sa.Column('area_id', UUID(as_uuid=True), nullable=True),  # FK to task_areas
        sa.Column('title', sa.String(500), nullable=False),
        sa.Column('status', sa.String(50), nullable=False, default='active'),  # active, completed, canceled
        sa.Column('notes', sa.Text, nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['area_id'], ['task_areas.id'], ondelete='SET NULL'),
        sa.Index('idx_task_projects_user_id', 'user_id'),
        sa.Index('idx_task_projects_area_id', 'area_id'),
        sa.Index('idx_task_projects_status', 'status'),
        sa.Index('idx_task_projects_deleted_at', 'deleted_at'),
    )

    # Tasks table
    op.create_table(
        'tasks',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('tasks_id', sa.String(255), nullable=True, unique=True, index=True),
        sa.Column('project_id', UUID(as_uuid=True), nullable=True),  # FK to task_projects
        sa.Column('area_id', UUID(as_uuid=True), nullable=True),     # FK to task_areas (for tasks without project)

        # Core fields
        sa.Column('title', sa.String(1000), nullable=False),
        sa.Column('notes', sa.Text, nullable=True),
        sa.Column('status', sa.String(50), nullable=False, default='inbox'),  # inbox, someday, completed, trashed (today/upcoming derived from dates)

        # Dates
        sa.Column('deadline', sa.Date, nullable=True),           # When task is due
        sa.Column('deadline_start', sa.Date, nullable=True),     # When task becomes active (LegacyTasks "start date")
        sa.Column('scheduled_date', sa.Date, nullable=True),     # User-scheduled date

        # Metadata
        sa.Column('tags', JSONB, nullable=True, default=sa.text("'[]'::jsonb")),  # Array of tag strings
        sa.Column('repeating', sa.Boolean, nullable=False, default=False),
        sa.Column('repeat_template', sa.Boolean, nullable=False, default=False),
        sa.Column('repeat_template_id', UUID(as_uuid=True), nullable=True),  # FK to tasks.id for idempotent repeats

        # Recurrence support
        sa.Column('recurrence_rule', JSONB, nullable=True),  # Structured recurrence rule (see Phase 2.5)
        sa.Column('next_instance_date', sa.Date, nullable=True),  # When to auto-create next instance

        # Timestamps
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('trashed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),

        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['project_id'], ['task_projects.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['area_id'], ['task_areas.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['repeat_template_id'], ['tasks.id'], ondelete='SET NULL'),

        # Indexes for performance
        sa.Index('idx_tasks_user_id', 'user_id'),
        sa.Index('idx_tasks_project_id', 'project_id'),
        sa.Index('idx_tasks_area_id', 'area_id'),
        sa.Index('idx_tasks_status', 'status'),
        sa.Index('idx_tasks_deadline', 'deadline'),
        sa.Index('idx_tasks_deadline_start', 'deadline_start'),
        sa.Index('idx_tasks_scheduled_date', 'scheduled_date'),
        sa.Index('idx_tasks_completed_at', 'completed_at'),
        sa.Index('idx_tasks_next_instance_date', 'next_instance_date'),  # For recurrence processing
        sa.Index('idx_tasks_deleted_at', 'deleted_at'),
        sa.Index('idx_tasks_repeat_template_id', 'repeat_template_id'),
        sa.Index(
            'uq_tasks_repeat_template_date',
            'repeat_template_id',
            'scheduled_date',
            unique=True,
            postgresql_where=sa.text('repeat_template_id IS NOT NULL')
        ),

        # GIN index for tags array search
        sa.Index('idx_tasks_tags_gin', 'tags', postgresql_using='gin'),

        # Composite index for common queries
        sa.Index('idx_tasks_user_status', 'user_id', 'status'),
    )

    # Offline sync idempotency log (outbox replay protection)
    op.create_table(
        'task_operation_log',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('operation_id', sa.String(255), nullable=False),
        sa.Column('operation_type', sa.String(50), nullable=False),
        sa.Column('payload', JSONB, nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.Index('idx_task_operation_log_user_id', 'user_id'),
        sa.Index('idx_task_operation_log_operation_id', 'operation_id'),
        sa.Index('uq_task_operation_log_user_operation', 'user_id', 'operation_id', unique=True),
    )

    # Enable RLS
    op.execute("ALTER TABLE task_areas ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE task_projects ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE tasks ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE task_operation_log ENABLE ROW LEVEL SECURITY")

    # RLS policies
    op.execute("""
        CREATE POLICY task_areas_user_isolation ON task_areas
        USING (user_id = current_setting('app.current_user_id')::uuid)
    """)
    op.execute("""
        CREATE POLICY task_projects_user_isolation ON task_projects
        USING (user_id = current_setting('app.current_user_id')::uuid)
    """)
    op.execute("""
        CREATE POLICY tasks_user_isolation ON tasks
        USING (user_id = current_setting('app.current_user_id')::uuid)
    """)
    op.execute("""
        CREATE POLICY task_operation_log_user_isolation ON task_operation_log
        USING (user_id = current_setting('app.current_user_id')::uuid)
    """)

def downgrade() -> None:
    op.drop_table('task_operation_log')
    op.drop_table('tasks')
    op.drop_table('task_projects')
    op.drop_table('task_areas')
```

### 1.1.1 RLS Session Context

RLS policies require setting `app.current_user_id` on every request. Add this to the DB session dependency so queries fail fast if the setting is missing:

```python
# In db session dependency or middleware
def with_user_context(db: Session, user_id: uuid.UUID) -> Session:
    db.execute(sa.text("SET LOCAL app.current_user_id = :user_id"), {"user_id": str(user_id)})
    return db
```

If no user context is set, reject the request with 401/403 before running queries.

### 1.2 SQLAlchemy Models

**File: `/backend/api/models/task_area.py` (NEW)**

```python
"""Task Area model"""
import uuid
from datetime import datetime
from sqlalchemy import String, DateTime, ForeignKey, Index
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from api.db.base import Base

class TaskArea(Base):
    __tablename__ = "task_areas"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    tasks_id: Mapped[str | None] = mapped_column(String(255), unique=True, index=True)
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default="now()")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default="now()")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # Relationships
    projects: Mapped[list["TaskProject"]] = relationship(back_populates="area")
    tasks: Mapped[list["Task"]] = relationship(back_populates="area")

    __table_args__ = (
        Index("idx_task_areas_user_id", "user_id"),
        Index("idx_task_areas_deleted_at", "deleted_at"),
    )
```

**File: `/backend/api/models/task_project.py` (NEW)**

```python
"""Task Project model"""
import uuid
from datetime import datetime
from sqlalchemy import String, Text, DateTime, ForeignKey, Index
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from api.db.base import Base

class TaskProject(Base):
    __tablename__ = "task_projects"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    tasks_id: Mapped[str | None] = mapped_column(String(255), unique=True, index=True)
    area_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("task_areas.id", ondelete="SET NULL"))
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    status: Mapped[str] = mapped_column(String(50), nullable=False, default="active")
    notes: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default="now()")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default="now()")
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # Relationships
    area: Mapped["TaskArea"] = relationship(back_populates="projects")
    tasks: Mapped[list["Task"]] = relationship(back_populates="project")

    __table_args__ = (
        Index("idx_task_projects_user_id", "user_id"),
        Index("idx_task_projects_area_id", "area_id"),
        Index("idx_task_projects_status", "status"),
        Index("idx_task_projects_deleted_at", "deleted_at"),
    )
```

**File: `/backend/api/models/task.py` (NEW)**

```python
"""Task model"""
import uuid
from datetime import datetime, date
from sqlalchemy import String, Text, Date, DateTime, Boolean, ForeignKey, Index
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship
from api.db.base import Base

class Task(Base):
    __tablename__ = "tasks"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    tasks_id: Mapped[str | None] = mapped_column(String(255), unique=True, index=True)
    project_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("task_projects.id", ondelete="SET NULL"))
    area_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("task_areas.id", ondelete="SET NULL"))

    title: Mapped[str] = mapped_column(String(1000), nullable=False)
    notes: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(50), nullable=False, default="inbox")

    deadline: Mapped[date | None] = mapped_column(Date)
    deadline_start: Mapped[date | None] = mapped_column(Date)
    scheduled_date: Mapped[date | None] = mapped_column(Date)

    tags: Mapped[list[str] | None] = mapped_column(JSONB, default=list)
    repeating: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    repeat_template: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    repeat_template_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("tasks.id", ondelete="SET NULL"))

    # Recurrence support (see Phase 2.5)
    recurrence_rule: Mapped[dict | None] = mapped_column(JSONB)
    next_instance_date: Mapped[date | None] = mapped_column(Date)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default="now()")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default="now()")
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    trashed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # Relationships
    project: Mapped["TaskProject"] = relationship(back_populates="tasks")
    area: Mapped["TaskArea"] = relationship(back_populates="tasks")

    __table_args__ = (
        Index("idx_tasks_user_id", "user_id"),
        Index("idx_tasks_project_id", "project_id"),
        Index("idx_tasks_area_id", "area_id"),
        Index("idx_tasks_status", "status"),
        Index("idx_tasks_deadline", "deadline"),
        Index("idx_tasks_deadline_start", "deadline_start"),
        Index("idx_tasks_scheduled_date", "scheduled_date"),
        Index("idx_tasks_completed_at", "completed_at"),
        Index("idx_tasks_next_instance_date", "next_instance_date"),
        Index("idx_tasks_deleted_at", "deleted_at"),
        Index("idx_tasks_repeat_template_id", "repeat_template_id"),
        Index("idx_tasks_tags_gin", "tags", postgresql_using="gin"),
        Index("idx_tasks_user_status", "user_id", "status"),
        Index("uq_tasks_repeat_template_date", "repeat_template_id", "scheduled_date", unique=True),
    )
```

### Deliverables
- ✅ Migration script creates tables with indexes
- ✅ SQLAlchemy models for TaskArea, TaskProject, Task
- ✅ Row-level security policies enforced
- ✅ Migration tested on development database

---

## Phase 2: One-Time LegacyTasks Import (2-3 days)

### Objectives
- Create import script using existing bridge
- Fetch all data from LegacyTasks (areas, projects, tasks)
- Parse recurrence rules from LegacyTasks SQLite database
- Insert into PostgreSQL with LegacyTasks IDs preserved
- Validate import completeness

### 2.1 Import Service

**File: `/backend/api/services/tasks_import_service.py` (NEW)**

```python
"""One-time import service from LegacyTasks to native task system"""
import logging
from datetime import datetime
from sqlalchemy.orm import Session
from api.services.tasks_bridge_client import LegacyTasksBridgeClient
from api.models.task_area import TaskArea
from api.models.task_project import TaskProject
from api.models.task import Task

logger = logging.getLogger(__name__)

class TasksImportService:
    """Import tasks from LegacyTasks bridge into native task system"""

    @staticmethod
    async def import_all_data(db: Session, user_id: str, bridge_client: LegacyTasksBridgeClient):
        """
        Import all LegacyTasks data for a user.

        Returns:
            dict with import statistics
        """
        stats = {
            "areas_imported": 0,
            "projects_imported": 0,
            "projects_skipped": 0,
            "tasks_imported": 0,
            "tasks_skipped": 0,
            "errors": []
        }

        try:
            # 1. Fetch all areas
            logger.info(f"Fetching areas for user {user_id}")
            areas_response = await bridge_client.get_lists("inbox")  # Areas included in any list response
            areas_data = areas_response.get("areas", [])

            area_id_map = {}  # Map LegacyTasks ID -> New UUID
            for area_data in areas_data:
                area = TaskArea(
                    user_id=user_id,
                    tasks_id=area_data["id"],
                    title=area_data["title"],
                    created_at=datetime.fromisoformat(area_data.get("updatedAt", datetime.now().isoformat())),
                    updated_at=datetime.fromisoformat(area_data.get("updatedAt", datetime.now().isoformat()))
                )
                db.add(area)
                db.flush()  # Get ID assigned
                area_id_map[area_data["id"]] = area.id
                stats["areas_imported"] += 1

            db.commit()
            logger.info(f"Imported {stats['areas_imported']} areas")

            # 2. Fetch all projects (filter active only)
            logger.info(f"Fetching projects for user {user_id}")
            projects_data = areas_response.get("projects", [])

            project_id_map = {}  # Map LegacyTasks ID -> New UUID
            for project_data in projects_data:
                # Skip completed, canceled projects
                status = project_data.get("status", "active")
                if status in ["completed", "canceled"]:
                    logger.debug(f"Skipping {status} project: {project_data['title']}")
                    stats["projects_skipped"] += 1
                    continue

                project = TaskProject(
                    user_id=user_id,
                    tasks_id=project_data["id"],
                    area_id=area_id_map.get(project_data.get("areaId")),
                    title=project_data["title"],
                    status=status,
                    created_at=datetime.fromisoformat(project_data.get("updatedAt", datetime.now().isoformat())),
                    updated_at=datetime.fromisoformat(project_data.get("updatedAt", datetime.now().isoformat()))
                )
                db.add(project)
                db.flush()
                project_id_map[project_data["id"]] = project.id
                stats["projects_imported"] += 1

            db.commit()
            logger.info(f"Imported {stats['projects_imported']} active projects")

            # 3. Fetch all tasks (from all lists)
            logger.info(f"Fetching tasks for user {user_id}")
            all_tasks = []

            # Fetch from multiple scopes
            for scope in ["inbox", "today", "upcoming"]:
                tasks_response = await bridge_client.get_lists(scope)
                all_tasks.extend(tasks_response.get("tasks", []))

            # Fetch tasks from each project
            for project_tasks_id in project_id_map.keys():
                project_tasks = await bridge_client.get_project_tasks(project_tasks_id)
                all_tasks.extend(project_tasks.get("tasks", []))

            # Deduplicate by LegacyTasks ID
            tasks_by_id = {t["id"]: t for t in all_tasks}

            # Filter and import only active tasks
            for task_data in tasks_by_id.values():
                # Skip completed, trashed, or canceled tasks
                status = task_data.get("status", "inbox")
                if status in ["completed", "trashed", "canceled"]:
                    logger.debug(f"Skipping {status} task: {task_data['title']}")
                    stats["tasks_skipped"] += 1
                    continue

                # Skip repeat templates (keep only active instances)
                if task_data.get("repeatTemplate", False):
                    logger.debug(f"Skipping repeat template: {task_data['title']}")
                    stats["tasks_skipped"] += 1
                    continue

                task = Task(
                    user_id=user_id,
                    tasks_id=task_data["id"],
                    project_id=project_id_map.get(task_data.get("projectId")),
                    area_id=area_id_map.get(task_data.get("areaId")),
                    title=task_data["title"],
                    notes=task_data.get("notes"),
                    status=status,
                    deadline=datetime.fromisoformat(task_data["deadline"]).date() if task_data.get("deadline") else None,
                    deadline_start=datetime.fromisoformat(task_data["deadlineStart"]).date() if task_data.get("deadlineStart") else None,
                    tags=task_data.get("tags", []),
                    repeating=task_data.get("repeating", False),
                    repeat_template=False,  # Never import templates
                    created_at=datetime.fromisoformat(task_data.get("updatedAt", datetime.now().isoformat())),
                    updated_at=datetime.fromisoformat(task_data.get("updatedAt", datetime.now().isoformat()))
                )
                db.add(task)
                stats["tasks_imported"] += 1

            db.commit()
            logger.info(f"Imported {stats['tasks_imported']} active tasks")

        except Exception as e:
            logger.error(f"Import failed: {str(e)}")
            stats["errors"].append(str(e))
            db.rollback()

        return stats
```

### 2.2 Import CLI Script

**File: `/backend/scripts/import_tasks_data.py` (NEW)**

```python
#!/usr/bin/env python3
"""CLI script to import LegacyTasks data into native task system"""
import asyncio
import sys
from sqlalchemy.orm import Session
from api.db.session import SessionLocal
from api.services.tasks_import_service import TasksImportService
from api.services.tasks_bridge_client import LegacyTasksBridgeClient
from api.services.tasks_bridge_service import LegacyTasksBridgeService

async def main(user_id: str):
    db: Session = SessionLocal()

    try:
        # Get active bridge for user
        bridge = LegacyTasksBridgeService.get_active_bridge(db, user_id)
        if not bridge:
            print(f"No active LegacyTasks bridge found for user {user_id}")
            sys.exit(1)

        print(f"Found bridge: {bridge.device_name} at {bridge.base_url}")

        # Create bridge client
        bridge_client = LegacyTasksBridgeClient(
            base_url=bridge.base_url,
            token=bridge.bridge_token
        )

        # Run import
        print("Starting import...")
        stats = await TasksImportService.import_all_data(db, user_id, bridge_client)

        print("\n=== Import Complete ===")
        print(f"Areas imported: {stats['areas_imported']}")
        print(f"Projects imported: {stats['projects_imported']} (skipped: {stats['projects_skipped']} completed/canceled)")
        print(f"Tasks imported: {stats['tasks_imported']} (skipped: {stats['tasks_skipped']} completed/trashed/templates)")

        if stats["errors"]:
            print(f"\nErrors: {len(stats['errors'])}")
            for error in stats["errors"]:
                print(f"  - {error}")
        else:
            print("\n✅ Import successful with no errors")

    finally:
        db.close()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python import_tasks_data.py <user_id>")
        sys.exit(1)

    user_id = sys.argv[1]
    asyncio.run(main(user_id))
```

### 2.3 Import Endpoint (Optional Admin Route)

**File: `/backend/api/routers/tasks_admin.py` (NEW)**

```python
"""Admin endpoints for task management"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from api.db.dependencies import get_db, get_current_user_id
from api.auth import verify_bearer_token
from api.services.tasks_import_service import TasksImportService
from api.services.tasks_bridge_client import LegacyTasksBridgeClient
from api.services.tasks_bridge_service import LegacyTasksBridgeService

router = APIRouter(prefix="/tasks/admin", tags=["tasks-admin"])

@router.post("/import-from-tasks")
async def import_from_tasks(
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db),
    _: str = Depends(verify_bearer_token)
):
    """
    One-time import of all LegacyTasks data into native task system.

    Requires active LegacyTasks bridge.
    """
    # Get active bridge
    bridge = LegacyTasksBridgeService.get_active_bridge(db, user_id)
    if not bridge:
        raise HTTPException(status_code=404, detail="No active LegacyTasks bridge found")

    # Create client
    bridge_client = LegacyTasksBridgeClient(
        base_url=bridge.base_url,
        token=bridge.bridge_token
    )

    # Run import
    stats = await TasksImportService.import_all_data(db, user_id, bridge_client)

    return {
        "success": len(stats["errors"]) == 0,
        "stats": stats
    }
```

### Deliverables
- ✅ Import service handles all LegacyTasks data types
- ✅ **Filters out** completed, trashed, canceled tasks and projects
- ✅ **Skips** repeat templates (imports only active instances)
- ✅ CLI script for manual import with skip statistics
- ✅ Admin API endpoint for web-based import
- ✅ LegacyTasks IDs preserved for reference
- ✅ Import statistics including skipped counts

### Import Filter Summary

**What Gets Imported:**
- ✅ All areas
- ✅ Active projects (status = "active")
- ✅ Active tasks (status in "inbox"/"someday"; today/upcoming derived from dates)
- ✅ Repeating tasks (active instances with recurrence rules)

**What Gets Filtered Out:**
- ❌ Completed projects (status = "completed")
- ❌ Canceled projects (status = "canceled")
- ❌ Completed tasks (status = "completed")
- ❌ Trashed tasks (status = "trashed")
- ❌ Canceled tasks (status = "canceled")
- ❌ Repeat templates (repeatTemplate = true, keep only active instances)

**Why Filter?**
- Reduces database size and improves performance
- Only migrates actionable data (what you need going forward)
- Completed/trashed items remain in LegacyTasks as historical archive
- Can always reference LegacyTasks backup if historical data needed

---

## Phase 2.5: Recurrence Implementation (2-3 days)

### Objectives
- Parse LegacyTasks proprietary recurrence format from SQLite
- Implement recurrence logic for task completion
- Auto-create next instances when repeating tasks are completed
- Support daily, weekly, and monthly patterns with intervals

### Background

**User's Repeating Task Audit (20 tasks):**
- **9 daily tasks** (e.g., "Moisturise", "Breakfast", "Pill")
  - Pattern: Every 1-2 days
- **7 weekly tasks** (e.g., "Put Bins Out", "Write News Stand")
  - Pattern: Every 1-4 weeks on specific weekday
- **3 monthly tasks** (e.g., "Monthly Budget", "Update Revenue Tracker")
  - Pattern: Every month on specific day (1st, 9th, 22nd)

**LegacyTasks Recurrence Format:**
LegacyTasks stores recurrence in binary plist format with these fields:
- `fu` (frequency unit): 16=Daily, 256=Weekly, 8=Monthly
- `fa` (frequency amount): Interval multiplier (1-4)
- `of` (occurrence frequency): `{'wd': N}` for weekday or `{'dy': N}` for day of month
- `sr` (start recurrence): Start date
- `ed` (end date): Recurrence end date (usually far future)

### 2.5.1 Recurrence Rule Schema

**JSONB Structure in `tasks.recurrence_rule`:**

```json
{
  "type": "daily" | "weekly" | "monthly",
  "interval": 1,              // Every N days/weeks/months
  "weekday": 0,              // For weekly: 0=Sun, 1=Mon, ..., 6=Sat (optional)
  "day_of_month": 1,         // For monthly: 1-31 (optional)
  "start_date": "2025-01-01", // When recurrence started
  "end_date": null           // When to stop (null = indefinite)
}
```

**Examples:**

```json
// Every 2 days (e.g., "Pill")
{"type": "daily", "interval": 2, "start_date": "2025-01-01"}

// Every 2 weeks on Monday (e.g., "Put Bins Out - Recycling")
{"type": "weekly", "interval": 2, "weekday": 1, "start_date": "2025-01-01"}

// Every month on the 22nd (e.g., "Book Madisons")
{"type": "monthly", "interval": 1, "day_of_month": 22, "start_date": "2025-01-01"}
```

**Template linkage:** For imported repeating tasks, set `repeat_template=True` and `repeat_template_id=task.id` after insert so subsequent instances can be deduped and linked.

### 2.5.2 Parse LegacyTasks Plist Recurrence

**File: `/backend/api/services/tasks_recurrence_parser.py` (NEW)**

```python
"""Parse LegacyTasks proprietary plist recurrence format"""
import plistlib
from datetime import date
from typing import Optional

class LegacyTasksRecurrenceParser:
    """Parse LegacyTasks recurrence rules from SQLite plist data"""

    @staticmethod
    def parse_recurrence_rule(plist_data: bytes) -> Optional[dict]:
        """
        Parse LegacyTasks binary plist recurrence data.

        Args:
            plist_data: Raw bytes from LegacyTasks SQLite rt1_recurrenceRule column

        Returns:
            Recurrence rule dict or None if not repeating
        """
        if not plist_data:
            return None

        try:
            plist = plistlib.loads(plist_data)

            fu = plist.get('fu')  # Frequency unit
            fa = plist.get('fa', 1)  # Frequency amount (interval)
            of = plist.get('of', {})  # Occurrence frequency
            sr = plist.get('sr')  # Start recurrence date
            ed = plist.get('ed')  # End date

            # Map frequency unit to type
            type_map = {
                16: 'daily',
                256: 'weekly',
                8: 'monthly'
            }

            recurrence_type = type_map.get(fu)
            if not recurrence_type:
                return None

            rule = {
                'type': recurrence_type,
                'interval': fa,
                'start_date': LegacyTasksRecurrenceParser._parse_tasks_date(sr) if sr else None,
                'end_date': LegacyTasksRecurrenceParser._parse_tasks_date(ed) if ed and ed < 64092211200 else None
            }

            # Add weekday for weekly recurrence
            if recurrence_type == 'weekly' and 'wd' in of:
                rule['weekday'] = of['wd']

            # Add day of month for monthly recurrence
            if recurrence_type == 'monthly' and 'dy' in of:
                rule['day_of_month'] = of['dy']

            return rule

        except Exception as e:
            logger.error(f"Failed to parse recurrence plist: {e}")
            return None

    @staticmethod
    def _parse_tasks_date(tasks_timestamp: int) -> str:
        """
        Convert LegacyTasks timestamp to ISO date.

        LegacyTasks uses: 2001-01-01 + ((timestamp - 131611392) / 128) days
        """
        from datetime import timedelta

        base_date = date(2001, 1, 1)
        days_offset = (tasks_timestamp - 131611392) / 128
        result_date = base_date + timedelta(days=days_offset)
        return result_date.isoformat()
```

### 2.5.3 Update Import Service

**File: `/backend/api/services/tasks_import_service.py`**

Add recurrence parsing to import:

```python
import sqlite3
from api.services.tasks_recurrence_parser import LegacyTasksRecurrenceParser

class TasksImportService:
    @staticmethod
    async def import_all_data(db: Session, user_id: str, bridge_client: LegacyTasksBridgeClient):
        # ... existing code ...

        # Open LegacyTasks SQLite database for recurrence data
        tasks_db_path = LegacyTasksRecurrenceParser.find_tasks_database()
        tasks_conn = sqlite3.connect(tasks_db_path)
        tasks_cursor = tasks_conn.cursor()

        # Fetch recurrence rules
        tasks_cursor.execute("""
            SELECT uuid, rt1_recurrenceRule
            FROM TMTask
            WHERE rt1_recurrenceRule IS NOT NULL
        """)
        recurrence_map = {
            row[0]: LegacyTasksRecurrenceParser.parse_recurrence_rule(row[1])
            for row in tasks_cursor.fetchall()
        }
        tasks_conn.close()

        # ... when creating tasks ...
        for task_data in tasks_by_id.values():
            recurrence_rule = recurrence_map.get(task_data["id"])

            task = Task(
                # ... existing fields ...
                recurrence_rule=recurrence_rule,
                next_instance_date=LegacyTasksRecurrenceParser.calculate_next_occurrence(
                    recurrence_rule
                ) if recurrence_rule else None
            )
            # ... rest of import logic ...
```

### 2.5.4 Recurrence Service

**File: `/backend/api/services/recurrence_service.py` (NEW)**

```python
"""Handle repeating task logic"""
import uuid
from datetime import date, timedelta
from calendar import monthrange
from sqlalchemy.orm import Session
from api.models.task import Task

class RecurrenceService:
    """Manage repeating task instances"""

    @staticmethod
    def calculate_next_occurrence(recurrence_rule: dict, from_date: date = None) -> date:
        """
        Calculate next occurrence date based on recurrence rule.

        Args:
            recurrence_rule: Recurrence rule dict
            from_date: Calculate from this date (default: today)

        Returns:
            Next occurrence date
        """
        if not recurrence_rule:
            raise ValueError("No recurrence rule provided")

        if from_date is None:
            from_date = date.today()

        rule_type = recurrence_rule['type']
        interval = recurrence_rule.get('interval', 1)

        if rule_type == 'daily':
            return from_date + timedelta(days=interval)

        elif rule_type == 'weekly':
            target_weekday = recurrence_rule.get('weekday', from_date.weekday())
            # Find next occurrence of target weekday, N weeks out
            days_ahead = (target_weekday - from_date.weekday()) % 7
            if days_ahead == 0:
                days_ahead = 7 * interval
            else:
                days_ahead += 7 * (interval - 1)
            return from_date + timedelta(days=days_ahead)

        elif rule_type == 'monthly':
            target_day = recurrence_rule.get('day_of_month', from_date.day)
            # Add N months
            month = from_date.month + interval
            year = from_date.year + (month - 1) // 12
            month = ((month - 1) % 12) + 1

            # Handle month boundaries (e.g., Jan 31 -> Feb 28)
            max_day = monthrange(year, month)[1]
            day = min(target_day, max_day)

            return date(year, month, day)

        else:
            raise ValueError(f"Unknown recurrence type: {rule_type}")

    @staticmethod
    def complete_repeating_task(db: Session, task: Task) -> Task | None:
        """
        When completing a repeating task, create next instance.

        Args:
            db: Database session
            task: The completed task

        Returns:
            New task instance or None if not repeating
        """
        if not task.recurrence_rule:
            return None

        # Idempotency guard: use repeat_template_id to avoid duplicates on retries
        template_id = task.repeat_template_id or task.id

        # Calculate next occurrence
        next_date = RecurrenceService.calculate_next_occurrence(
            task.recurrence_rule,
            from_date=task.completed_at.date() if task.completed_at else date.today()
        )

        existing_task = db.execute(
            select(Task).where(
                Task.repeat_template_id == template_id,
                Task.scheduled_date == next_date,
                Task.deleted_at.is_(None)
            )
        ).scalar_one_or_none()
        if existing_task:
            return existing_task

        # Create new task instance
        new_task = Task(
            user_id=task.user_id,
            project_id=task.project_id,
            area_id=task.area_id,
            title=task.title,
            notes=task.notes,
            status='inbox',  # New instance starts in inbox
            recurrence_rule=task.recurrence_rule,
            next_instance_date=RecurrenceService.calculate_next_occurrence(
                task.recurrence_rule,
                from_date=next_date
            ),
            scheduled_date=next_date,
            tags=task.tags,
            repeating=True,
            repeat_template=False,
            repeat_template_id=template_id
        )

        db.add(new_task)
        db.flush()

        return new_task

    @staticmethod
    def find_tasks_database() -> str:
        """Find LegacyTasks SQLite database path"""
        import glob
        pattern = os.path.expanduser(
            "~/Library/Group Containers/JLMPQHK86H.com.culturedcode.LegacyTasksMac/LegacyTasksData-*/LegacyTasks Database.tasksdatabase/main.sqlite"
        )
        matches = glob.glob(pattern)
        if not matches:
            raise FileNotFoundError("LegacyTasks database not found")
        return matches[0]
```

### 2.5.5 Update Task Service Complete Logic

**File: `/backend/api/services/task_service.py`**

Modify complete_task to handle recurrence:

```python
from api.services.recurrence_service import RecurrenceService

class TaskService:
    # ... existing methods ...

    @staticmethod
    def complete_task(db: Session, user_id: str, task_id: str) -> dict:
        """Mark task as complete and create next instance if repeating"""
        task = db.execute(
            select(Task).where(
                Task.id == uuid.UUID(task_id),
                Task.user_id == user_id,
                Task.deleted_at.is_(None)
            )
        ).scalar_one_or_none()

        if not task:
            raise ValueError("Task not found")

        # Mark as complete
        task.status = "completed"
        task.completed_at = datetime.now()
        task.updated_at = datetime.now()

        # If repeating, create next instance
        next_task = None
        if task.recurrence_rule:
            next_task = RecurrenceService.complete_repeating_task(db, task)

        db.commit()

        result = {"success": True}
        if next_task:
            result["next_task"] = TaskService._task_to_dict(next_task)

        return result
```

### Deliverables
- ✅ LegacyTasks plist recurrence parser
- ✅ Recurrence rule schema defined
- ✅ Import updated to parse and store recurrence rules
- ✅ RecurrenceService implements next occurrence calculation
- ✅ Task completion auto-creates next instance
- ✅ 100% coverage of user's 20 repeating tasks

---

## Phase 3: Backend API Migration (3-4 days)

### Objectives
- Create native task CRUD service
- Replace bridge client calls with direct DB queries
- Update `/api/v1/tasks/*` endpoints to use new service
- Maintain existing API response schemas
- Keep business logic in services (routers stay thin)

### 3.1 Native Task Service

**File: `/backend/api/services/task_service.py` (NEW)**

Normalize incoming status values so legacy clients can send "today"/"upcoming" without persisting them:
- Map "today"/"upcoming" to `status="inbox"` and rely on `scheduled_date`/`deadline` for scope.

```python
"""Native task management service"""
import uuid
from datetime import datetime, date, timedelta
from sqlalchemy import select, func, and_, or_
from sqlalchemy.orm import Session, joinedload
from api.models.task import Task
from api.models.task_project import TaskProject
from api.models.task_area import TaskArea

class TaskService:
    """CRUD operations for native task system"""

    @staticmethod
    def get_tasks_by_scope(db: Session, user_id: str, scope: str) -> dict:
        """
        Get tasks by scope (today, upcoming, inbox).

        Returns response matching LegacyTasks API format.
        """
        today = date.today()

        query = select(Task).where(
            Task.user_id == user_id,
            Task.status != "completed",
            Task.status != "trashed",
            Task.deleted_at.is_(None)
        ).options(
            joinedload(Task.project),
            joinedload(Task.area)
        )

        if scope == "today":
            # Tasks scheduled for today or overdue
            query = query.where(
                Task.status != "someday",
                or_(
                    Task.scheduled_date == today,
                    and_(Task.deadline <= today, Task.deadline.isnot(None))
                )
            )
        elif scope == "upcoming":
            # Tasks with future dates
            query = query.where(
                Task.status != "someday",
                or_(
                    Task.scheduled_date > today,
                    and_(Task.deadline > today, Task.deadline.isnot(None))
                )
            )
        elif scope == "inbox":
            query = query.where(Task.status == "inbox")

        tasks = db.execute(query).scalars().all()

        # Get related projects and areas
        projects = db.execute(
            select(TaskProject).where(
                TaskProject.user_id == user_id,
                TaskProject.deleted_at.is_(None)
            )
        ).scalars().all()

        areas = db.execute(
            select(TaskArea).where(
                TaskArea.user_id == user_id,
                TaskArea.deleted_at.is_(None)
            )
        ).scalars().all()

        return {
            "scope": scope,
            "generatedAt": datetime.now().isoformat(),
            "tasks": [TaskService._task_to_dict(t) for t in tasks],
            "projects": [TaskService._project_to_dict(p) for p in projects],
            "areas": [TaskService._area_to_dict(a) for a in areas]
        }

    @staticmethod
    def search_tasks(db: Session, user_id: str, query: str) -> dict:
        """Full-text search across task titles and notes"""
        tasks = db.execute(
            select(Task).where(
                Task.user_id == user_id,
                Task.status != "trashed",
                Task.deleted_at.is_(None),
                or_(
                    Task.title.ilike(f"%{query}%"),
                    Task.notes.ilike(f"%{query}%")
                )
            ).options(
                joinedload(Task.project),
                joinedload(Task.area)
            )
        ).scalars().all()

        return {
            "scope": "search",
            "generatedAt": datetime.now().isoformat(),
            "tasks": [TaskService._task_to_dict(t) for t in tasks]
        }

    @staticmethod
    def get_counts(db: Session, user_id: str) -> dict:
        """Get task counts for badges"""
        today = date.today()

        # Inbox count
        inbox_count = db.execute(
            select(func.count(Task.id)).where(
                Task.user_id == user_id,
                Task.status == "inbox",
                Task.deleted_at.is_(None)
            )
        ).scalar()

        # Today count
        today_count = db.execute(
            select(func.count(Task.id)).where(
                Task.user_id == user_id,
                Task.status != "completed",
                Task.status != "trashed",
                Task.deleted_at.is_(None),
                Task.status != "someday",
                or_(
                    Task.scheduled_date == today,
                    and_(Task.deadline <= today, Task.deadline.isnot(None))
                )
            )
        ).scalar()

        # Upcoming count
        upcoming_count = db.execute(
            select(func.count(Task.id)).where(
                Task.user_id == user_id,
                Task.status != "completed",
                Task.status != "trashed",
                Task.deleted_at.is_(None),
                Task.status != "someday",
                or_(
                    Task.scheduled_date > today,
                    and_(Task.deadline > today, Task.deadline.isnot(None))
                )
            )
        ).scalar()

        # Counts per project
        project_counts = db.execute(
            select(
                Task.project_id,
                func.count(Task.id).label("count")
            ).where(
                Task.user_id == user_id,
                Task.status != "completed",
                Task.status != "trashed",
                Task.deleted_at.is_(None),
                Task.project_id.isnot(None)
            ).group_by(Task.project_id)
        ).all()

        # Counts per area
        area_counts = db.execute(
            select(
                Task.area_id,
                func.count(Task.id).label("count")
            ).where(
                Task.user_id == user_id,
                Task.status != "completed",
                Task.status != "trashed",
                Task.deleted_at.is_(None),
                Task.area_id.isnot(None)
            ).group_by(Task.area_id)
        ).all()

        return {
            "counts": {
                "inbox": inbox_count,
                "today": today_count,
                "upcoming": upcoming_count
            },
            "projects": [{"id": str(pc.project_id), "count": pc.count} for pc in project_counts],
            "areas": [{"id": str(ac.area_id), "count": ac.count} for ac in area_counts]
        }

    @staticmethod
    def create_task(db: Session, user_id: str, data: dict) -> dict:
        """Create new task"""
        status = data.get("status", "inbox")
        if status in {"today", "upcoming"}:
            status = "inbox"

        task = Task(
            user_id=user_id,
            title=data["title"],
            notes=data.get("notes"),
            status=status,
            deadline=datetime.fromisoformat(data["due_date"]).date() if data.get("due_date") else None,
            project_id=uuid.UUID(data["project_id"]) if data.get("project_id") else None,
            area_id=uuid.UUID(data["area_id"]) if data.get("area_id") else None,
            tags=data.get("tags", [])
        )
        db.add(task)
        db.commit()
        db.refresh(task)
        return TaskService._task_to_dict(task)

    @staticmethod
    def complete_task(db: Session, user_id: str, task_id: str) -> dict:
        """Mark task as complete"""
        task = db.execute(
            select(Task).where(
                Task.id == uuid.UUID(task_id),
                Task.user_id == user_id,
                Task.deleted_at.is_(None)
            )
        ).scalar_one_or_none()

        if not task:
            raise ValueError("Task not found")

        task.status = "completed"
        task.completed_at = datetime.now()
        task.updated_at = datetime.now()
        db.commit()

        return {"success": True}

    @staticmethod
    def rename_task(db: Session, user_id: str, task_id: str, new_title: str) -> dict:
        """Rename a task"""
        task = db.execute(
            select(Task).where(
                Task.id == uuid.UUID(task_id),
                Task.user_id == user_id,
                Task.deleted_at.is_(None)
            )
        ).scalar_one_or_none()

        if not task:
            raise ValueError("Task not found")

        task.title = new_title
        task.updated_at = datetime.now()
        db.commit()

        return TaskService._task_to_dict(task)

    @staticmethod
    def update_notes(db: Session, user_id: str, task_id: str, notes: str) -> dict:
        """Update task notes"""
        task = db.execute(
            select(Task).where(
                Task.id == uuid.UUID(task_id),
                Task.user_id == user_id,
                Task.deleted_at.is_(None)
            )
        ).scalar_one_or_none()

        if not task:
            raise ValueError("Task not found")

        task.notes = notes
        task.updated_at = datetime.now()
        db.commit()

        return TaskService._task_to_dict(task)

    @staticmethod
    def move_task(db: Session, user_id: str, task_id: str, project_id: str = None, area_id: str = None) -> dict:
        """Move task to different project or area"""
        task = db.execute(
            select(Task).where(
                Task.id == uuid.UUID(task_id),
                Task.user_id == user_id,
                Task.deleted_at.is_(None)
            )
        ).scalar_one_or_none()

        if not task:
            raise ValueError("Task not found")

        if project_id:
            task.project_id = uuid.UUID(project_id)
            task.area_id = None  # Tasks belong to project OR area, not both
        elif area_id:
            task.area_id = uuid.UUID(area_id)
            task.project_id = None
        else:
            # Move to inbox
            task.project_id = None
            task.area_id = None

        task.updated_at = datetime.now()
        db.commit()

        return TaskService._task_to_dict(task)

    @staticmethod
    def trash_task(db: Session, user_id: str, task_id: str) -> dict:
        """Move task to trash"""
        task = db.execute(
            select(Task).where(
                Task.id == uuid.UUID(task_id),
                Task.user_id == user_id,
                Task.deleted_at.is_(None)
            )
        ).scalar_one_or_none()

        if not task:
            raise ValueError("Task not found")

        task.status = "trashed"
        task.trashed_at = datetime.now()
        task.deleted_at = datetime.now()
        task.updated_at = datetime.now()
        db.commit()

        return {"success": True}

    @staticmethod
    def set_due_date(db: Session, user_id: str, task_id: str, due_date: str = None) -> dict:
        """Set or clear task due date"""
        task = db.execute(
            select(Task).where(
                Task.id == uuid.UUID(task_id),
                Task.user_id == user_id,
                Task.deleted_at.is_(None)
            )
        ).scalar_one_or_none()

        if not task:
            raise ValueError("Task not found")

        if due_date:
            task.deadline = datetime.fromisoformat(due_date).date()
        else:
            task.deadline = None

        task.updated_at = datetime.now()
        db.commit()

        return TaskService._task_to_dict(task)

    # Helper methods
    @staticmethod
    def _task_to_dict(task: Task) -> dict:
        """Convert Task model to API response dict"""
        return {
            "id": str(task.id),
            "title": task.title,
            "status": task.status,
            "deadline": task.deadline.isoformat() if task.deadline else None,
            "deadlineStart": task.deadline_start.isoformat() if task.deadline_start else None,
            "scheduledDate": task.scheduled_date.isoformat() if task.scheduled_date else None,
            "notes": task.notes,
            "projectId": str(task.project_id) if task.project_id else None,
            "areaId": str(task.area_id) if task.area_id else None,
            "repeating": task.repeating,
            "repeatTemplate": task.repeat_template,
            "recurrenceRule": task.recurrence_rule,  # Include for frontend display
            "tags": task.tags or [],
            "updatedAt": task.updated_at.isoformat() if task.updated_at else None
        }

    @staticmethod
    def _project_to_dict(project: TaskProject) -> dict:
        return {
            "id": str(project.id),
            "title": project.title,
            "areaId": str(project.area_id) if project.area_id else None,
            "status": project.status,
            "updatedAt": project.updated_at.isoformat() if project.updated_at else None
        }

    @staticmethod
    def _area_to_dict(area: TaskArea) -> dict:
        return {
            "id": str(area.id),
            "title": area.title,
            "updatedAt": area.updated_at.isoformat() if area.updated_at else None
        }
```

**JSONB updates:** When mutating `tags` or `recurrence_rule`, call `flag_modified(task, "tags")` / `flag_modified(task, "recurrence_rule")` so SQLAlchemy persists changes.

### 3.2 Update LegacyTasks Router

**File: `/backend/api/routers/tasks.py`**

Replace bridge calls with native task service:

```python
from api.services.task_service import TaskService

# Before (bridge-based):
@router.get("/lists/{scope}")
async def get_list(
    scope: str,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
    bridge_client = get_bridge_client(db, user_id)
    return await bridge_client.get_lists(scope)

# After (native):
@router.get("/lists/{scope}")
async def get_list(
    scope: str,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
    return TaskService.get_tasks_by_scope(db, user_id, scope)

@router.get("/search")
async def search_tasks(
    query: str,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
    return TaskService.search_tasks(db, user_id, query)

@router.get("/counts")
async def get_counts(
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
    return TaskService.get_counts(db, user_id)

@router.post("/apply")
async def apply_operation(
    operation: dict,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
    """Handle all task operations (create, complete, rename, etc.)"""
    op = operation.get("op")

    if op == "add":
        return TaskService.create_task(db, user_id, operation)
    elif op == "complete":
        return TaskService.complete_task(db, user_id, operation["id"])
    elif op == "rename":
        return TaskService.rename_task(db, user_id, operation["id"], operation["title"])
    elif op == "notes":
        return TaskService.update_notes(db, user_id, operation["id"], operation["notes"])
    elif op == "move":
        return TaskService.move_task(
            db, user_id, operation["id"],
            project_id=operation.get("project_id"),
            area_id=operation.get("area_id")
        )
    elif op == "trash":
        return TaskService.trash_task(db, user_id, operation["id"])
    elif op == "set_due":
        return TaskService.set_due_date(db, user_id, operation["id"], operation.get("due_date"))
    else:
        raise HTTPException(status_code=400, detail=f"Unknown operation: {op}")
```

### 3.3 Offline Sync via `/apply`

Extend `/apply` to accept batch operations and sync metadata for offline outbox replay:

```python
@router.post("/apply")
async def apply_operation(
    payload: dict,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
    """
    Payload:
      {
        "last_sync": "2026-01-11T12:00:00Z" | null,
        "operations": [
          {"operation_id": "uuid", "op": "add", "client_updated_at": "...", ...}
        ]
      }
    """
    return TaskService.apply_operations(db, user_id, payload)
```

Server-side behavior:
- Deduplicate by `(user_id, operation_id)` using `task_operation_log`.
- Apply operations in order within a transaction.
- Return `applied`, `conflicts`, and `server_updated_since` to let clients pull deltas.
- Conflict rule: last-write-wins by `client_updated_at`, with server values returned on conflict.

### Deliverables
- ✅ TaskService implements all CRUD operations
- ✅ All `/api/v1/tasks/*` endpoints updated
- ✅ `/api/v1/tasks/apply` supports offline outbox replay (batch operations)
- ✅ API response schemas unchanged (frontend compatibility)
- ✅ Direct DB queries replace bridge HTTP calls
- ✅ Performance improvements measured (<100ms queries)

---

## Phase 4: Frontend Migration (3 days)

### Objectives
- Update LegacyTasks store to work with new API
- Remove bridge-specific logic
- Reduce cache TTL (5min → 1min)
- Add optimistic updates
- Implement offline cache + outbox sync

### 4.1 Update LegacyTasks Store

**File: `/frontend/src/lib/stores/tasks.ts`**

Minimal changes needed (API contract unchanged):

```typescript
// Update cache TTL
const CACHE_TTL_MS = 60 * 1000; // 1 minute (down from 5)

// Remove bridge health checks (no longer needed)
// All other code remains the same since API responses match
```

### 4.2 Add Optimistic Updates

```typescript
export const tasksStore = {
  // ... existing methods

  async completeTaskOptimistic(taskId: string) {
    // Immediately update UI
    update(state => ({
      ...state,
      tasks: state.tasks.filter(t => t.id !== taskId)
    }));

    // Send to backend
    try {
      const result = await tasksAPI.completeTask(taskId);

      // Handle repeating task response (see 4.3)
      if (result.next_task) {
        this.handleNextTaskCreated(result.next_task);
      }
    } catch (error) {
      // Rollback on error
      console.error("Failed to complete task:", error);
      await this.loadSelection(currentSelection, { force: true });
    }
  }
};
```

### 4.3 Frontend Recurrence Handling

**Handle Next Instance Creation:**

When backend creates next instance of repeating task, frontend needs to:

```typescript
// In tasks store
handleNextTaskCreated(nextTask: LegacyTasksTask) {
  // Show subtle notification
  toast.info(`"${nextTask.title}" scheduled for ${formatDate(nextTask.scheduledDate)}`);

  // If viewing today/upcoming and next task is in that scope, add to cache
  const nextDate = new Date(nextTask.scheduledDate);
  const today = new Date();

  // Refresh cache to show new task
  this.loadSelection(this.currentSelection, { silent: true });
}
```

**Display Recurrence Indicator:**

Update task display to show recurrence info:

```typescript
// In LegacyTasksTask component
function getRecurrenceLabel(task: LegacyTasksTask): string | null {
  if (!task.recurrenceRule) return null;

  const { type, interval } = task.recurrenceRule;

  if (type === 'daily') {
    return interval === 1 ? 'Daily' : `Every ${interval} days`;
  } else if (type === 'weekly') {
    const day = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][task.recurrenceRule.weekday || 0];
    return interval === 1 ? `Weekly on ${day}` : `Every ${interval} weeks on ${day}`;
  } else if (type === 'monthly') {
    const day = task.recurrenceRule.day_of_month;
    return interval === 1 ? `Monthly on day ${day}` : `Every ${interval} months on day ${day}`;
  }
  return null;
}
```

```svelte
<!-- In task UI -->
{#if task.repeating}
  <span class="recurrence-badge" title={getRecurrenceLabel(task)}>
    <RepeatIcon size={12} />
  </span>
{/if}
```

### 4.4 Offline-First Sync + Queue

Implement a local cache and outbox so tasks remain usable offline:

- Persist tasks and metadata in IndexedDB (e.g., `tasks`, `projects`, `areas`, `sync_state` stores).
- Store mutations in an outbox (`operations` store) with `operation_id`, `client_updated_at`, and payload.
- On app start: render from IndexedDB immediately, then call `/sync` with `last_sync`.
- When online: flush outbox in order via `/sync`; remove applied ops and merge server deltas.
- When offline: queue operations and update UI optimistically; reconcile on reconnect.
- Conflict handling: if server returns conflicts, show a non-blocking banner and refresh affected items.

Suggested structure:

```typescript
const outbox = new OutboxQueue("task-ops");

async function enqueueOperation(op: TaskOperation) {
  await outbox.add(op);
  applyOptimisticUpdate(op);
  if (navigator.onLine) {
    await flushOutbox();
  }
}

async function flushOutbox() {
  const batch = await outbox.peekBatch(50);
  if (!batch.length) return;
  const response = await tasksAPI.apply({ lastSync, operations: batch });
  await outbox.removeApplied(response.applied);
  await mergeServerDeltas(response.updated_since);
}
```

Suggested files:
- `frontend/src/lib/services/task_sync.ts` (sync + outbox logic)
- `frontend/src/lib/stores/task_cache.ts` (IndexedDB-backed cache)

### Deliverables
- ✅ Cache TTL reduced to 1 minute
- ✅ Optimistic updates for complete/create/rename
- ✅ Bridge health checks removed
- ✅ Recurrence: Toast notification when next instance created
- ✅ Recurrence: Visual indicator (repeat icon) on repeating tasks
- ✅ Recurrence: Auto-refresh to show new task
- ✅ Offline-first: IndexedDB cache + outbox replay + conflict handling
- ✅ No visual regressions

---

## Phase 5: Performance Optimization (1-2 days)

### Objectives
- Add database indexes
- Implement query result caching (optional)
- Optimize N+1 queries with eager loading
- Monitor and validate <100ms query times

### 5.1 Additional Indexes

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Composite index for today's/upcoming tasks query
CREATE INDEX idx_tasks_today_lookup ON tasks(user_id, status, scheduled_date, deadline)
WHERE deleted_at IS NULL AND status NOT IN ('completed', 'trashed', 'someday');

-- Index for search queries
CREATE INDEX idx_tasks_title_trgm ON tasks USING gin(title gin_trgm_ops);
CREATE INDEX idx_tasks_notes_trgm ON tasks USING gin(notes gin_trgm_ops);
```

### 5.2 Query Optimization

Use `joinedload` to prevent N+1 queries:

```python
# Load tasks with projects and areas in single query
tasks = db.execute(
    select(Task)
    .options(
        joinedload(Task.project).joinedload(TaskProject.area),
        joinedload(Task.area)
    )
    .where(Task.user_id == user_id)
).scalars().all()
```

### Deliverables
- ✅ All common queries under 100ms
- ✅ No N+1 query issues
- ✅ Search queries optimized with trigram indexes
- ✅ Performance benchmarks documented

---

## Phase 6: Bridge Decommission (1 day)

### Objectives
- Disable bridge auto-start
- Archive bridge code
- Update documentation
- Provide rollback instructions

### 6.1 Disable Bridge

**File: `/backend/api/routers/tasks.py`**

Add feature flag to toggle between bridge and native:

```python
from api.config import settings

USE_NATIVE_TASKS = settings.use_native_task_system  # Default: True

if USE_NATIVE_TASKS:
    return TaskService.get_tasks_by_scope(db, user_id, scope)
else:
    # Fallback to bridge (for rollback)
    bridge_client = get_bridge_client(db, user_id)
    return await bridge_client.get_lists(scope)
```

### 6.2 Archive Bridge Code

```bash
# Create archive branch
git checkout -b archive/tasks-bridge
git push origin archive/tasks-bridge

# Remove bridge from main
git checkout main
# Keep bridge files but disable in production
```

### Deliverables
- ✅ Feature flag for native vs bridge
- ✅ Bridge code archived
- ✅ LaunchAgent disabled
- ✅ Rollback procedure documented

---

## Testing & Validation

### Unit Tests

**File: `/backend/tests/api/test_task_service.py` (NEW)**

```python
def test_get_tasks_today(db, test_user):
    """Test fetching today's tasks"""
    # Create test task
    task = Task(
        user_id=test_user.id,
        title="Test task",
        status="inbox",
        scheduled_date=date.today()
    )
    db.add(task)
    db.commit()

    # Fetch
    result = TaskService.get_tasks_by_scope(db, test_user.id, "today")

    assert result["scope"] == "today"
    assert len(result["tasks"]) == 1
    assert result["tasks"][0]["title"] == "Test task"

def test_complete_task(db, test_user):
    """Test completing a task"""
    task = Task(user_id=test_user.id, title="Complete me", status="inbox")
    db.add(task)
    db.commit()

    TaskService.complete_task(db, test_user.id, str(task.id))

    db.refresh(task)
    assert task.status == "completed"
    assert task.completed_at is not None

def test_complete_repeating_task_daily(db, test_user):
    """Test completing a daily repeating task creates next instance"""
    task = Task(
        user_id=test_user.id,
        title="Daily task",
        status="inbox",
        recurrence_rule={"type": "daily", "interval": 1},
        repeating=True
    )
    db.add(task)
    db.commit()

    result = TaskService.complete_task(db, test_user.id, str(task.id))

    # Original task completed
    db.refresh(task)
    assert task.status == "completed"

    # New instance created
    assert "next_task" in result
    assert result["next_task"]["title"] == "Daily task"
    assert result["next_task"]["recurrence_rule"]["type"] == "daily"

def test_calculate_next_occurrence_weekly(db, test_user):
    """Test weekly recurrence calculation"""
    rule = {"type": "weekly", "interval": 2, "weekday": 1}  # Every 2 weeks on Monday
    from_date = date(2026, 1, 12)  # A Monday

    next_date = RecurrenceService.calculate_next_occurrence(rule, from_date)

    assert next_date == date(2026, 1, 26)  # 2 weeks later, still Monday

def test_parse_tasks_recurrence_plist(db, test_user):
    """Test parsing LegacyTasks binary plist recurrence data"""
    # Mock plist data for daily every 2 days
    plist_bytes = plistlib.dumps({"fu": 16, "fa": 2, "of": {"dy": 1}})

    rule = LegacyTasksRecurrenceParser.parse_recurrence_rule(plist_bytes)

    assert rule["type"] == "daily"
    assert rule["interval"] == 2
```

### Integration Tests

1. **Import Validation**: Run import script, verify all data migrated
2. **Recurrence Import**: Verify all 20 repeating tasks imported with correct rules
3. **API Parity**: Compare bridge responses vs native responses
4. **Performance**: Measure query times (<100ms requirement)
5. **Search**: Test full-text search accuracy
6. **Counts**: Verify badge counts match across all views
7. **Offline Sync**: Queue operations offline and verify `/apply` replay + conflict handling
7. **Recurrence Flow**: Complete repeating task, verify next instance created with correct date

### Manual Testing Checklist

- [ ] View Today tasks
- [ ] View Upcoming tasks
- [ ] View Inbox
- [ ] Create new task
- [ ] Complete task
- [ ] Rename task
- [ ] Move task to project
- [ ] Search for tasks
- [ ] Verify counts/badges
- [ ] Test on slow connection (performance)
- [ ] Go offline: tasks still visible from local cache
- [ ] Go offline: create/complete task, then reconnect and verify sync
- [ ] Force a conflict (edit same task on two devices), verify conflict handling
- [ ] Complete daily repeating task, verify next instance appears
- [ ] Complete weekly repeating task, verify correct weekday
- [ ] Complete monthly repeating task, verify correct day of month
- [ ] Verify all 20 repeating tasks imported correctly

---

## User Communication & Migration UX

### Pre-Migration Communication

**Settings Page Notice:**
```svelte
<!-- In SettingsLegacyTasksSection.svelte -->
<div class="migration-notice">
  <h3>📦 Native Task Management Available</h3>
  <p>
    We're upgrading to a native task system with improved performance and offline support.
    Your LegacyTasks data will be imported automatically.
  </p>
  <button on:click={startMigration}>
    Migrate to Native Tasks
  </button>
  <details>
    <summary>What will be imported?</summary>
    <ul>
      <li>✅ All active tasks, projects, and areas</li>
      <li>✅ Repeating tasks with full recurrence rules</li>
      <li>❌ Completed and trashed tasks (remain in LegacyTasks)</li>
    </ul>
  </details>
</div>
```

### During Migration

**Progress Indicator:**
```typescript
// Show modal with progress
{
  step: 'importing_areas',
  message: 'Importing areas and projects...',
  progress: 33
}

{
  step: 'importing_tasks',
  message: 'Importing tasks and recurrence rules...',
  progress: 66
}

{
  step: 'finalizing',
  message: 'Finalizing migration...',
  progress: 90
}
```

**Visual States:**
```svelte
<div class="migration-modal">
  <div class="progress-bar" style="width: {progress}%"></div>
  <p>{message}</p>
  <p class="small">This may take a minute...</p>
</div>
```

### Post-Migration

**Success Message:**
```svelte
<div class="migration-success">
  <h3>✅ Migration Complete!</h3>
  <p>
    Imported {stats.tasks_imported} tasks, {stats.projects_imported} projects,
    and {stats.areas_imported} areas.
  </p>
  {#if stats.tasks_skipped > 0}
    <p class="muted">
      {stats.tasks_skipped} completed/trashed tasks remain in LegacyTasks as archive.
    </p>
  {/if}
  <button on:click={viewTasks}>View My Tasks</button>
</div>
```

**Failure Handling:**
```svelte
<div class="migration-error">
  <h3>⚠️ Migration Failed</h3>
  <p>We couldn't complete the migration: {error.message}</p>
  <p>Your LegacyTasks data is safe and unchanged.</p>
  <button on:click={retryMigration}>Try Again</button>
  <button on:click={contactSupport}>Contact Support</button>
</div>
```

### Notifications

**Repeating Task Completion:**
```typescript
// Toast when next instance created
toast.info({
  title: 'Task repeated',
  message: '"Morning routine" scheduled for tomorrow',
  duration: 3000
});
```

---

## Edge Cases & Error Handling

### 1. LegacyTasks Database Not Found

**Issue:** `glob.glob` returns empty list when searching for LegacyTasks database

**Handling:**
```python
@staticmethod
def find_tasks_database() -> str:
    """Find LegacyTasks SQLite database path"""
    import glob
    import os

    pattern = os.path.expanduser(
        "~/Library/Group Containers/JLMPQHK86H.com.culturedcode.LegacyTasksMac/LegacyTasksData-*/LegacyTasks Database.tasksdatabase/main.sqlite"
    )
    matches = glob.glob(pattern)

    if not matches:
        # Try alternative location (LegacyTasks 3.x vs 4.x)
        alt_pattern = os.path.expanduser("~/Library/Containers/com.culturedcode.LegacyTasksMac/*/LegacyTasks Database.tasksdatabase/main.sqlite")
        matches = glob.glob(alt_pattern)

    if not matches:
        raise FileNotFoundError(
            "LegacyTasks database not found. Please ensure LegacyTasks 3 is installed and you've granted Full Disk Access."
        )

    return matches[0]
```

**User Message:** "LegacyTasks database not found. Please ensure LegacyTasks is installed and try again."

### 2. Malformed Recurrence Rules

**Issue:** LegacyTasks plist data is corrupt or unparseable

**Handling:**
```python
try:
    plist = plistlib.loads(plist_data)
    # ... parse recurrence
except Exception as e:
    logger.warning(f"Failed to parse recurrence for task {task_id}: {e}")
    return None  # Fallback to non-repeating task
```

**Result:** Task is imported but loses repeating status (user can manually recreate recurrence)

### 3. Duplicate Task Titles

**Issue:** User has multiple tasks with identical titles

**Handling:** Allowed by design - tasks distinguished by UUID

**Note:** Document that duplicates are fine, UUIDs ensure uniqueness

### 4. Timezone Handling

**Issue:** LegacyTasks stores dates without timezone, need consistency

**Handling:**
```python
# All dates stored as naive dates (no time component)
deadline: Mapped[date | None] = mapped_column(Date)

# Convert to ISO date string (YYYY-MM-DD) for API
deadline_iso = task.deadline.isoformat() if task.deadline else None
```

**Strategy:** Use local date only, no timezone conversion needed for date-only fields

### 5. Import Interrupted Mid-Process

**Issue:** Network failure, system crash during import

**Handling:**
```python
try:
    # Import wrapped in transaction
    db.begin()

    # ... import logic ...

    db.commit()
except Exception as e:
    db.rollback()  # All-or-nothing import
    logger.error(f"Import failed, rolled back: {e}")
    raise
```

**Result:** Import is atomic - either fully succeeds or fully rolls back

**User Action:** Retry import, previous partial import is cleaned up

### 6. Very Large Task Lists

**Issue:** User has 10,000+ tasks (unlikely but possible)

**Handling:**
```python
# Batch import in chunks
BATCH_SIZE = 500

for i in range(0, len(tasks), BATCH_SIZE):
    batch = tasks[i:i+BATCH_SIZE]
    for task_data in batch:
        # ... create task
        db.add(task)

    db.commit()  # Commit per batch
    logger.info(f"Imported batch {i//BATCH_SIZE + 1}")
```

**UI:** Show progress bar updating per batch

### 7. Recurrence Date Edge Cases

**Issue:** Monthly recurrence on day 31, but next month has 30 days

**Handling:**
```python
# In calculate_next_occurrence
max_day = monthrange(year, month)[1]
day = min(target_day, max_day)  # Clamp to valid day
```

**Example:** Task on Jan 31 → Feb 28 (or 29) → Mar 31

### 8. Bridge Unavailable During Import

**Issue:** LegacyTasks bridge is offline or not responding

**Handling:**
```python
try:
    response = await bridge_client.get_lists("inbox", timeout=30)
except httpx.TimeoutException:
    raise HTTPException(
        status_code=503,
        detail="LegacyTasks bridge is not responding. Please ensure the bridge is running."
    )
```

**User Message:** "Couldn't connect to LegacyTasks. Please check that LegacyTasks is running and try again."

### 9. Missing Permissions

**Issue:** App lacks Full Disk Access to read LegacyTasks database

**Handling:**
```python
try:
    conn = sqlite3.connect(tasks_db_path)
    conn.execute("SELECT 1 FROM TMTask LIMIT 1")
except sqlite3.OperationalError as e:
    if "unable to open database" in str(e):
        raise PermissionError(
            "Cannot access LegacyTasks database. Please grant Full Disk Access in System Settings > Privacy & Security."
        )
```

**User Message:** Show macOS permission instructions with screenshot

### 10. Concurrent Modifications

**Issue:** User modifies tasks in LegacyTasks while import is running

**Handling:** Import is point-in-time snapshot

**Note:** Document that users should not modify LegacyTasks during migration (takes ~1 minute)

**After Migration:** Bridge remains functional until decommissioned, so changes made during migration can be manually synced if needed

---

## Rollout Strategy

### Pre-Migration

1. **Backup LegacyTasks data**: Export full LegacyTasks backup
2. **Test import on staging**: Validate with real user data
3. **Performance baseline**: Measure current response times
4. **Feature flag ready**: Can toggle back to bridge if needed

### Migration Steps

1. **Deploy database schema** (Phase 1)
2. **Run import script** for all users with LegacyTasks connected
3. **Deploy backend API changes** with feature flag OFF
4. **Test native system** in production with flag ON for internal users
5. **Enable for all users** once validated
6. **Monitor performance** and error rates
7. **Disable bridge** after 1 week of stable operation

### Rollback Plan

If issues arise:

```python
# Set in environment
USE_NATIVE_TASK_SYSTEM=false

# Restart backend
# System reverts to bridge-based operation
# Native task data preserved for debugging
```

---

## Success Metrics

| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| Task list load time | ~500ms | <100ms | API response time |
| Search query time | ~800ms | <150ms | API response time |
| Cache TTL | 5 minutes | 1 minute | Code config |
| Bridge dependency | Required | Optional | Architecture |
| Offline support | None | Full | Feature availability |
| Data ownership | LegacyTasks | sideBar | Data location |
| Repeating tasks | 20 tasks | 100% working | Manual verification |

---

## Estimated Timeline

| Phase | Effort | Dependencies |
|-------|--------|-------------|
| 1. Database Schema | 2-3 days | None |
| 2. LegacyTasks Import | 2-3 days | Phase 1 |
| 2.5. Recurrence Implementation | 2-3 days | Phase 2 |
| 3. Backend API | 3-4 days | Phase 1, 2, 2.5 |
| 4. Frontend Update | 3 days | Phase 3 |
| 5. Performance Optimization | 1-2 days | Phase 3, 4 |
| 6. Bridge Decommission | 1 day | All phases |
| Testing & Validation | 2-3 days | Ongoing |
| **Total** | **16-22 days** | |

---

## Critical Files Summary

### Backend (Create)

```
backend/
├── api/
│   ├── models/
│   │   ├── task.py
│   │   ├── task_project.py
│   │   └── task_area.py
│   ├── services/
│   │   ├── task_service.py
│   │   ├── tasks_import_service.py
│   │   ├── recurrence_service.py              # NEW: Phase 2.5
│   │   └── tasks_recurrence_parser.py        # NEW: Phase 2.5
│   ├── routers/
│   │   └── tasks_admin.py
│   └── alembic/versions/
│       └── 20260111_1500-030_create_task_system_schema.py
└── scripts/
    └── import_tasks_data.py
```

### Backend (Modify)

```
backend/
└── api/
    ├── routers/
    │   └── tasks.py  # Replace bridge calls with TaskService
    └── config.py      # Add USE_NATIVE_TASK_SYSTEM flag
```

### Frontend (Modify)

```
frontend/
└── src/lib/
    ├── services/
    │   └── task_sync.ts   # Offline sync + outbox replay
    └── stores/
        ├── task_cache.ts  # IndexedDB-backed cache
        └── tasks.ts      # Reduce cache TTL, add optimistic updates
```

---

## Next Steps

1. ✅ Review and approve this migration plan
2. ⏭️ Begin Phase 1: Create database schema and models (2-3 days)
3. ⏭️ Execute Phase 2: Import all LegacyTasks data (2-3 days)
4. ⏭️ Implement Phase 2.5: Recurrence support (2-3 days)
5. ⏭️ Implement Phase 3: Migrate backend API to native queries (3-4 days)
6. ⏭️ Update Phase 4: Frontend optimizations (3 days)
7. ⏭️ Optimize Phase 5: Database performance tuning (1-2 days)
8. ⏭️ Complete Phase 6: Decommission bridge (1 day)
9. ⏭️ Validate: Run full test suite and performance benchmarks (including 20 repeating tasks)
10. ⏭️ Deploy: Execute rollout strategy with feature flag

---

## Plan Completeness Summary

This migration plan now includes:

### ✅ Core Migration (Complete)
- Full database schema with recurrence support
- One-time import with filtering (active tasks only)
- Complete TaskService with all CRUD operations
- API router with all endpoints implemented
- Frontend store updates with recurrence handling
- Performance optimization strategy

### ✅ Recurrence System (Complete)
- LegacyTasks plist parser for 20 existing repeating tasks
- Support for daily, weekly, monthly patterns with intervals
- Auto-creation of next instances on completion
- Frontend display of recurrence indicators
- Toast notifications for next instance creation
- 100% coverage of user's actual recurrence patterns

### ✅ User Experience (Complete)
- Pre-migration communication and setup UI
- Progress indicators during import
- Success/failure messaging
- Repeating task notifications
- Migration retry and error recovery

### ✅ Error Handling (Complete)
- Database not found (with fallback paths)
- Malformed recurrence rules (graceful degradation)
- Import interruption (atomic transactions)
- Large task lists (batch processing)
- Permission issues (clear user guidance)
- Edge cases for date calculations
- Timezone handling strategy
- Concurrent modification handling

### ✅ Testing Strategy (Complete)
- Unit tests for all CRUD operations
- Unit tests for recurrence calculation
- Integration tests for import and API parity
- Manual test checklist for all features
- Performance benchmarks (<100ms requirement)

### ✅ Deployment (Complete)
- Feature flag for safe rollout
- Rollback procedure documented
- Bridge archival strategy
- Monitoring and validation plan

### 📊 Coverage Metrics
- **CRUD Operations**: 7/7 (create, read, complete, rename, update notes, move, trash, set due date)
- **Recurrence Patterns**: 3/3 (daily, weekly, monthly with intervals)
- **User's Repeating Tasks**: 20/20 (100% coverage)
- **Edge Cases**: 10 documented with solutions
- **API Endpoints**: 4/4 (lists, search, counts, apply)

**Status**: ✅ **Ready for Implementation**

The plan is comprehensive, addresses all identified gaps, and provides clear implementation guidance for each phase.
