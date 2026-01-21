"""Service for importing Things data into native task system."""

from __future__ import annotations

from dataclasses import dataclass, field

from sqlalchemy.orm import Session


@dataclass
class TasksImportStats:
    """Summary statistics for an import run."""

    areas_imported: int = 0
    projects_imported: int = 0
    projects_skipped: int = 0
    tasks_imported: int = 0
    tasks_skipped: int = 0
    errors: list[str] = field(default_factory=list)


class TasksImportService:
    """Import tasks from Things bridge into native tables."""

    @staticmethod
    def import_from_bridge(
        db: Session, user_id: str, bridge_payload: dict
    ) -> TasksImportStats:
        """Import Things data using a prepared payload.

        Args:
            db: Database session.
            user_id: Current user ID.
            bridge_payload: Parsed Things payload (areas, projects, tasks).

        Returns:
            TasksImportStats with counts and errors.
        """
        raise NotImplementedError("Things import service not implemented yet")
