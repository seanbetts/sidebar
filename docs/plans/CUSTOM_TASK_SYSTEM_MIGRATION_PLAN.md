# Custom Task System Migration Plan

**Date**: 2026-01-11
**Feature**: Native PostgreSQL Task System (Things Replacement)

---

## Overview

Replace the Things bridge-based task system with a native PostgreSQL implementation to achieve data ownership, offline-first capability, and dramatically improved performance. This migration eliminates the three-layer architecture (Backend → Bridge → AppleScript → Things) in favor of direct database access.

### Current Architecture

```
Frontend → Backend API → Bridge (127.0.0.1:8787) → AppleScript → Things DB
- 5-minute cache TTL
- 10-second AppleScript timeout
- Requires local bridge running
- macOS only
```

### Target Architecture

```
Frontend → Backend API → PostgreSQL
- Direct SQL queries (<50ms)
- Offline-first (data in our DB)
- Cross-platform ready
- Full data ownership
```

---

## Key Design Decisions

**Data Migration:**
- ✅ One-time import of all Things data via existing bridge
- ✅ Preserve Things IDs for reference/rollback
- ✅ Import areas, projects, and tasks with full metadata
- ✅ Create snapshot before migration for safety

**Database Schema:**
- ✅ Mirror Things structure: Areas → Projects → Tasks hierarchy
- ✅ Store tags as JSONB array for flexibility
- ✅ Track completion with `completed_at` timestamp
- ✅ Support task status: inbox, today, upcoming, someday, completed, trashed

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
- ✅ Optionally maintain read-only Things sync
- ✅ Archive bridge in separate branch for reference

---

## Success Criteria

- ✅ All Things data (areas, projects, tasks) imported successfully
- ✅ Task list loads in <100ms (vs current ~500ms with bridge)
- ✅ Full CRUD operations working (create, read, update, delete, complete)
- ✅ Search functionality matches or exceeds current capability
- ✅ Counts/badges update in real-time
- ✅ No regressions in existing UI/UX
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
        sa.Column('things_id', sa.String(255), nullable=True, unique=True, index=True),  # Original Things ID
        sa.Column('title', sa.String(500), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.Index('idx_task_areas_user_id', 'user_id'),
    )

    # Projects table
    op.create_table(
        'task_projects',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('things_id', sa.String(255), nullable=True, unique=True, index=True),
        sa.Column('area_id', UUID(as_uuid=True), nullable=True),  # FK to task_areas
        sa.Column('title', sa.String(500), nullable=False),
        sa.Column('status', sa.String(50), nullable=False, default='active'),  # active, completed, canceled
        sa.Column('notes', sa.Text, nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['area_id'], ['task_areas.id'], ondelete='SET NULL'),
        sa.Index('idx_task_projects_user_id', 'user_id'),
        sa.Index('idx_task_projects_area_id', 'area_id'),
        sa.Index('idx_task_projects_status', 'status'),
    )

    # Tasks table
    op.create_table(
        'tasks',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('things_id', sa.String(255), nullable=True, unique=True, index=True),
        sa.Column('project_id', UUID(as_uuid=True), nullable=True),  # FK to task_projects
        sa.Column('area_id', UUID(as_uuid=True), nullable=True),     # FK to task_areas (for tasks without project)

        # Core fields
        sa.Column('title', sa.String(1000), nullable=False),
        sa.Column('notes', sa.Text, nullable=True),
        sa.Column('status', sa.String(50), nullable=False, default='inbox'),  # inbox, today, upcoming, someday, completed, trashed

        # Dates
        sa.Column('deadline', sa.Date, nullable=True),           # When task is due
        sa.Column('deadline_start', sa.Date, nullable=True),     # When task becomes active (Things "start date")
        sa.Column('scheduled_date', sa.Date, nullable=True),     # User-scheduled date

        # Metadata
        sa.Column('tags', JSONB, nullable=True, default=sa.text("'[]'::jsonb")),  # Array of tag strings
        sa.Column('repeating', sa.Boolean, nullable=False, default=False),
        sa.Column('repeat_template', sa.Boolean, nullable=False, default=False),

        # Timestamps
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('trashed_at', sa.DateTime(timezone=True), nullable=True),

        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['project_id'], ['task_projects.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['area_id'], ['task_areas.id'], ondelete='SET NULL'),

        # Indexes for performance
        sa.Index('idx_tasks_user_id', 'user_id'),
        sa.Index('idx_tasks_project_id', 'project_id'),
        sa.Index('idx_tasks_area_id', 'area_id'),
        sa.Index('idx_tasks_status', 'status'),
        sa.Index('idx_tasks_deadline', 'deadline'),
        sa.Index('idx_tasks_deadline_start', 'deadline_start'),
        sa.Index('idx_tasks_scheduled_date', 'scheduled_date'),
        sa.Index('idx_tasks_completed_at', 'completed_at'),

        # GIN index for tags array search
        sa.Index('idx_tasks_tags_gin', 'tags', postgresql_using='gin'),

        # Composite index for common queries
        sa.Index('idx_tasks_user_status', 'user_id', 'status'),
    )

    # Enable RLS
    op.execute("ALTER TABLE task_areas ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE task_projects ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE tasks ENABLE ROW LEVEL SECURITY")

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

def downgrade() -> None:
    op.drop_table('tasks')
    op.drop_table('task_projects')
    op.drop_table('task_areas')
```

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
    things_id: Mapped[str | None] = mapped_column(String(255), unique=True, index=True)
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default="now()")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default="now()")

    # Relationships
    projects: Mapped[list["TaskProject"]] = relationship(back_populates="area", cascade="all, delete-orphan")
    tasks: Mapped[list["Task"]] = relationship(back_populates="area", cascade="all, delete-orphan")

    __table_args__ = (
        Index("idx_task_areas_user_id", "user_id"),
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
    things_id: Mapped[str | None] = mapped_column(String(255), unique=True, index=True)
    area_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("task_areas.id", ondelete="SET NULL"))
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    status: Mapped[str] = mapped_column(String(50), nullable=False, default="active")
    notes: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default="now()")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default="now()")
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # Relationships
    area: Mapped["TaskArea"] = relationship(back_populates="projects")
    tasks: Mapped[list["Task"]] = relationship(back_populates="project", cascade="all, delete-orphan")

    __table_args__ = (
        Index("idx_task_projects_user_id", "user_id"),
        Index("idx_task_projects_area_id", "area_id"),
        Index("idx_task_projects_status", "status"),
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
    things_id: Mapped[str | None] = mapped_column(String(255), unique=True, index=True)
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

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default="now()")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default="now()")
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    trashed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

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
        Index("idx_tasks_tags_gin", "tags", postgresql_using="gin"),
        Index("idx_tasks_user_status", "user_id", "status"),
    )
```

### Deliverables
- ✅ Migration script creates tables with indexes
- ✅ SQLAlchemy models for TaskArea, TaskProject, Task
- ✅ Row-level security policies enforced
- ✅ Migration tested on development database

---

## Phase 2: One-Time Things Import (2-3 days)

### Objectives
- Create import script using existing bridge
- Fetch all data from Things (areas, projects, tasks)
- Insert into PostgreSQL with Things IDs preserved
- Validate import completeness

### 2.1 Import Service

**File: `/backend/api/services/tasks_import_service.py` (NEW)**

```python
"""One-time import service from Things to native task system"""
import logging
from datetime import datetime
from sqlalchemy.orm import Session
from api.services.things_bridge_client import ThingsBridgeClient
from api.models.task_area import TaskArea
from api.models.task_project import TaskProject
from api.models.task import Task

logger = logging.getLogger(__name__)

class TasksImportService:
    """Import tasks from Things bridge into native task system"""

    @staticmethod
    async def import_all_data(db: Session, user_id: str, bridge_client: ThingsBridgeClient):
        """
        Import all Things data for a user.

        Returns:
            dict with import statistics
        """
        stats = {
            "areas_imported": 0,
            "projects_imported": 0,
            "tasks_imported": 0,
            "errors": []
        }

        try:
            # 1. Fetch all areas
            logger.info(f"Fetching areas for user {user_id}")
            areas_response = await bridge_client.get_lists("inbox")  # Areas included in any list response
            areas_data = areas_response.get("areas", [])

            area_id_map = {}  # Map Things ID -> New UUID
            for area_data in areas_data:
                area = TaskArea(
                    user_id=user_id,
                    things_id=area_data["id"],
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

            # 2. Fetch all projects
            logger.info(f"Fetching projects for user {user_id}")
            projects_data = areas_response.get("projects", [])

            project_id_map = {}  # Map Things ID -> New UUID
            for project_data in projects_data:
                project = TaskProject(
                    user_id=user_id,
                    things_id=project_data["id"],
                    area_id=area_id_map.get(project_data.get("areaId")),
                    title=project_data["title"],
                    status=project_data.get("status", "active"),
                    created_at=datetime.fromisoformat(project_data.get("updatedAt", datetime.now().isoformat())),
                    updated_at=datetime.fromisoformat(project_data.get("updatedAt", datetime.now().isoformat()))
                )
                db.add(project)
                db.flush()
                project_id_map[project_data["id"]] = project.id
                stats["projects_imported"] += 1

            db.commit()
            logger.info(f"Imported {stats['projects_imported']} projects")

            # 3. Fetch all tasks (from all lists)
            logger.info(f"Fetching tasks for user {user_id}")
            all_tasks = []

            # Fetch from multiple scopes
            for scope in ["inbox", "today", "upcoming"]:
                tasks_response = await bridge_client.get_lists(scope)
                all_tasks.extend(tasks_response.get("tasks", []))

            # Fetch tasks from each project
            for project_things_id in project_id_map.keys():
                project_tasks = await bridge_client.get_project_tasks(project_things_id)
                all_tasks.extend(project_tasks.get("tasks", []))

            # Deduplicate by Things ID
            tasks_by_id = {t["id"]: t for t in all_tasks}

            for task_data in tasks_by_id.values():
                task = Task(
                    user_id=user_id,
                    things_id=task_data["id"],
                    project_id=project_id_map.get(task_data.get("projectId")),
                    area_id=area_id_map.get(task_data.get("areaId")),
                    title=task_data["title"],
                    notes=task_data.get("notes"),
                    status=task_data.get("status", "inbox"),
                    deadline=datetime.fromisoformat(task_data["deadline"]).date() if task_data.get("deadline") else None,
                    deadline_start=datetime.fromisoformat(task_data["deadlineStart"]).date() if task_data.get("deadlineStart") else None,
                    tags=task_data.get("tags", []),
                    repeating=task_data.get("repeating", False),
                    repeat_template=task_data.get("repeatTemplate", False),
                    created_at=datetime.fromisoformat(task_data.get("updatedAt", datetime.now().isoformat())),
                    updated_at=datetime.fromisoformat(task_data.get("updatedAt", datetime.now().isoformat()))
                )
                db.add(task)
                stats["tasks_imported"] += 1

            db.commit()
            logger.info(f"Imported {stats['tasks_imported']} tasks")

        except Exception as e:
            logger.error(f"Import failed: {str(e)}")
            stats["errors"].append(str(e))
            db.rollback()

        return stats
```

### 2.2 Import CLI Script

**File: `/backend/scripts/import_things_data.py` (NEW)**

```python
#!/usr/bin/env python3
"""CLI script to import Things data into native task system"""
import asyncio
import sys
from sqlalchemy.orm import Session
from api.db.session import SessionLocal
from api.services.tasks_import_service import TasksImportService
from api.services.things_bridge_client import ThingsBridgeClient
from api.services.things_bridge_service import ThingsBridgeService

async def main(user_id: str):
    db: Session = SessionLocal()

    try:
        # Get active bridge for user
        bridge = ThingsBridgeService.get_active_bridge(db, user_id)
        if not bridge:
            print(f"No active Things bridge found for user {user_id}")
            sys.exit(1)

        print(f"Found bridge: {bridge.device_name} at {bridge.base_url}")

        # Create bridge client
        bridge_client = ThingsBridgeClient(
            base_url=bridge.base_url,
            token=bridge.bridge_token
        )

        # Run import
        print("Starting import...")
        stats = await TasksImportService.import_all_data(db, user_id, bridge_client)

        print("\n=== Import Complete ===")
        print(f"Areas imported: {stats['areas_imported']}")
        print(f"Projects imported: {stats['projects_imported']}")
        print(f"Tasks imported: {stats['tasks_imported']}")

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
        print("Usage: python import_things_data.py <user_id>")
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
from api.services.things_bridge_client import ThingsBridgeClient
from api.services.things_bridge_service import ThingsBridgeService

router = APIRouter(prefix="/tasks/admin", tags=["tasks-admin"])

@router.post("/import-from-things")
async def import_from_things(
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db),
    _: str = Depends(verify_bearer_token)
):
    """
    One-time import of all Things data into native task system.

    Requires active Things bridge.
    """
    # Get active bridge
    bridge = ThingsBridgeService.get_active_bridge(db, user_id)
    if not bridge:
        raise HTTPException(status_code=404, detail="No active Things bridge found")

    # Create client
    bridge_client = ThingsBridgeClient(
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
- ✅ Import service handles all Things data types
- ✅ CLI script for manual import
- ✅ Admin API endpoint for web-based import
- ✅ Things IDs preserved for reference
- ✅ Import statistics and error reporting

---

## Phase 3: Backend API Migration (3-4 days)

### Objectives
- Create native task CRUD service
- Replace bridge client calls with direct DB queries
- Update `/api/v1/things/*` endpoints to use new service
- Maintain existing API response schemas

### 3.1 Native Task Service

**File: `/backend/api/services/task_service.py` (NEW)**

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

        Returns response matching Things API format.
        """
        today = date.today()

        query = select(Task).where(
            Task.user_id == user_id,
            Task.status != "completed",
            Task.status != "trashed"
        ).options(
            joinedload(Task.project),
            joinedload(Task.area)
        )

        if scope == "today":
            # Tasks scheduled for today or overdue
            query = query.where(
                or_(
                    Task.scheduled_date == today,
                    and_(Task.deadline <= today, Task.deadline.isnot(None)),
                    Task.status == "today"
                )
            )
        elif scope == "upcoming":
            # Tasks with future dates
            query = query.where(
                or_(
                    Task.scheduled_date > today,
                    and_(Task.deadline > today, Task.deadline.isnot(None)),
                    Task.status == "upcoming"
                )
            )
        elif scope == "inbox":
            query = query.where(Task.status == "inbox")

        tasks = db.execute(query).scalars().all()

        # Get related projects and areas
        projects = db.execute(
            select(TaskProject).where(TaskProject.user_id == user_id)
        ).scalars().all()

        areas = db.execute(
            select(TaskArea).where(TaskArea.user_id == user_id)
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
                Task.status == "inbox"
            )
        ).scalar()

        # Today count
        today_count = db.execute(
            select(func.count(Task.id)).where(
                Task.user_id == user_id,
                Task.status != "completed",
                Task.status != "trashed",
                or_(
                    Task.scheduled_date == today,
                    and_(Task.deadline <= today, Task.deadline.isnot(None)),
                    Task.status == "today"
                )
            )
        ).scalar()

        # Upcoming count
        upcoming_count = db.execute(
            select(func.count(Task.id)).where(
                Task.user_id == user_id,
                Task.status != "completed",
                Task.status != "trashed",
                or_(
                    Task.scheduled_date > today,
                    and_(Task.deadline > today, Task.deadline.isnot(None)),
                    Task.status == "upcoming"
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
        task = Task(
            user_id=user_id,
            title=data["title"],
            notes=data.get("notes"),
            status=data.get("status", "inbox"),
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
            select(Task).where(Task.id == uuid.UUID(task_id), Task.user_id == user_id)
        ).scalar_one_or_none()

        if not task:
            raise ValueError("Task not found")

        task.status = "completed"
        task.completed_at = datetime.now()
        task.updated_at = datetime.now()
        db.commit()

        return {"success": True}

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
            "notes": task.notes,
            "projectId": str(task.project_id) if task.project_id else None,
            "areaId": str(task.area_id) if task.area_id else None,
            "repeating": task.repeating,
            "repeatTemplate": task.repeat_template,
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

### 3.2 Update Things Router

**File: `/backend/api/routers/things.py`**

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

# Similar updates for:
# - /search
# - /counts
# - /apply (create, complete, rename, etc.)
```

### Deliverables
- ✅ TaskService implements all CRUD operations
- ✅ All `/api/v1/things/*` endpoints updated
- ✅ API response schemas unchanged (frontend compatibility)
- ✅ Direct DB queries replace bridge HTTP calls
- ✅ Performance improvements measured (<100ms queries)

---

## Phase 4: Frontend Migration (2 days)

### Objectives
- Update Things store to work with new API
- Remove bridge-specific logic
- Reduce cache TTL (5min → 1min)
- Add optimistic updates

### 4.1 Update Things Store

**File: `/frontend/src/lib/stores/things.ts`**

Minimal changes needed (API contract unchanged):

```typescript
// Update cache TTL
const CACHE_TTL_MS = 60 * 1000; // 1 minute (down from 5)

// Remove bridge health checks (no longer needed)
// All other code remains the same since API responses match
```

### 4.2 Add Optimistic Updates

```typescript
export const thingsStore = {
  // ... existing methods

  async completeTaskOptimistic(taskId: string) {
    // Immediately update UI
    update(state => ({
      ...state,
      tasks: state.tasks.filter(t => t.id !== taskId)
    }));

    // Send to backend
    try {
      await thingsAPI.completeTask(taskId);
    } catch (error) {
      // Rollback on error
      console.error("Failed to complete task:", error);
      await this.loadSelection(currentSelection, { force: true });
    }
  }
};
```

### Deliverables
- ✅ Cache TTL reduced to 1 minute
- ✅ Optimistic updates for complete/create/rename
- ✅ Bridge health checks removed
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
-- Composite index for today's tasks query
CREATE INDEX idx_tasks_today_lookup ON tasks(user_id, status, scheduled_date, deadline)
WHERE status != 'completed' AND status != 'trashed';

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

**File: `/backend/api/routers/things.py`**

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
git checkout -b archive/things-bridge
git push origin archive/things-bridge

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
        status="today",
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
```

### Integration Tests

1. **Import Validation**: Run import script, verify all data migrated
2. **API Parity**: Compare bridge responses vs native responses
3. **Performance**: Measure query times (<100ms requirement)
4. **Search**: Test full-text search accuracy
5. **Counts**: Verify badge counts match across all views

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

---

## Rollout Strategy

### Pre-Migration

1. **Backup Things data**: Export full Things backup
2. **Test import on staging**: Validate with real user data
3. **Performance baseline**: Measure current response times
4. **Feature flag ready**: Can toggle back to bridge if needed

### Migration Steps

1. **Deploy database schema** (Phase 1)
2. **Run import script** for all users with Things connected
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
| Data ownership | Things | sideBar | Data location |

---

## Estimated Timeline

| Phase | Effort | Dependencies |
|-------|--------|-------------|
| 1. Database Schema | 2-3 days | None |
| 2. Things Import | 2-3 days | Phase 1 |
| 3. Backend API | 3-4 days | Phase 1, 2 |
| 4. Frontend Update | 2 days | Phase 3 |
| 5. Performance Optimization | 1-2 days | Phase 3, 4 |
| 6. Bridge Decommission | 1 day | All phases |
| Testing & Validation | 2 days | Ongoing |
| **Total** | **13-17 days** | |

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
│   │   └── tasks_import_service.py
│   ├── routers/
│   │   └── tasks_admin.py
│   └── alembic/versions/
│       └── 20260111_1500-030_create_task_system_schema.py
└── scripts/
    └── import_things_data.py
```

### Backend (Modify)

```
backend/
└── api/
    ├── routers/
    │   └── things.py  # Replace bridge calls with TaskService
    └── config.py      # Add USE_NATIVE_TASK_SYSTEM flag
```

### Frontend (Modify)

```
frontend/
└── src/lib/
    └── stores/
        └── things.ts  # Reduce cache TTL, add optimistic updates
```

---

## Next Steps

1. ✅ Review and approve this migration plan
2. ⏭️ Begin Phase 1: Create database schema and models (2-3 days)
3. ⏭️ Execute Phase 2: Import all Things data (2-3 days)
4. ⏭️ Implement Phase 3: Migrate backend API to native queries (3-4 days)
5. ⏭️ Update Phase 4: Frontend optimizations (2 days)
6. ⏭️ Optimize Phase 5: Database performance tuning (1-2 days)
7. ⏭️ Complete Phase 6: Decommission bridge (1 day)
8. ⏭️ Validate: Run full test suite and performance benchmarks
9. ⏭️ Deploy: Execute rollout strategy with feature flag
