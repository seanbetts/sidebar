"""Build Things AI snapshot content."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any


class ThingsSnapshotService:
    """Helpers for Things AI snapshot rendering."""

    @staticmethod
    def build_snapshot(
        *,
        today_tasks: list[dict[str, Any]],
        tomorrow_tasks: list[dict[str, Any]],
        completed_today: list[dict[str, Any]],
        areas: list[dict[str, Any]],
        projects: list[dict[str, Any]],
    ) -> str:
        """Build the Things snapshot markdown from task payloads."""
        area_map = {area.get("id"): area.get("title") for area in areas}
        project_map = {project.get("id"): project.get("title") for project in projects}

        def format_task(task: dict[str, Any], *, checked: bool) -> list[str]:
            title = task.get("title") or "Untitled task"
            area = area_map.get(task.get("areaId"))
            project = project_map.get(task.get("projectId"))
            context = "/".join([value for value in [area, project] if value])
            label = f"- [{'x' if checked else ' '}] {title}"
            if context:
                label = f"{label} ({context})"
            lines = [label]
            notes = (task.get("notes") or "").strip()
            if notes:
                lines.append(f"  - Notes: {notes}")
            return lines

        blocks: list[str] = []
        blocks.append("Today")
        if today_tasks:
            for task in today_tasks:
                blocks.extend(format_task(task, checked=False))
        else:
            blocks.append("- [ ] None")

        blocks.append("")
        blocks.append("Tomorrow")
        if tomorrow_tasks:
            for task in tomorrow_tasks:
                blocks.extend(format_task(task, checked=False))
        else:
            blocks.append("- [ ] None")

        blocks.append("")
        blocks.append("Completed today")
        if completed_today:
            for task in completed_today:
                blocks.extend(format_task(task, checked=True))
        else:
            blocks.append("- [ ] None")

        return "\n".join(blocks).strip()

    @staticmethod
    def filter_tomorrow(
        tasks: list[dict[str, Any]], now: datetime | None = None
    ) -> list[dict[str, Any]]:
        """Filter tasks with a deadline date matching tomorrow."""
        timestamp = now or datetime.now(UTC)
        tomorrow = (timestamp + timedelta(days=1)).date()

        def task_date(task: dict[str, Any]) -> datetime | None:
            date_value = task.get("deadline") or task.get("deadlineStart")
            if not date_value:
                return None
            try:
                return datetime.fromisoformat(str(date_value).replace("Z", "+00:00"))
            except ValueError:
                return None

        filtered: list[dict[str, Any]] = []
        for task in tasks:
            parsed = task_date(task)
            if parsed and parsed.date() == tomorrow:
                filtered.append(task)
        return filtered
