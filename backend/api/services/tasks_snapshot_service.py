"""Build tasks AI snapshot content."""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from typing import Any


class TasksSnapshotService:
    """Helpers for tasks AI snapshot rendering."""

    @staticmethod
    def build_snapshot(
        *,
        today_tasks: list[dict[str, Any]],
        tomorrow_tasks: list[dict[str, Any]],
        completed_today: list[dict[str, Any]],
        groups: list[dict[str, Any]],
        projects: list[dict[str, Any]],
        now: datetime | None = None,
    ) -> str:
        """Build the tasks snapshot markdown from task payloads."""
        timestamp = now or datetime.now(UTC)
        today_date = timestamp.date()
        group_map = {group.get("id"): group.get("title") for group in groups}
        project_map = {project.get("id"): project.get("title") for project in projects}

        def parse_deadline(task: dict[str, Any]) -> date | None:
            deadline = task.get("deadline")
            if not deadline:
                return None
            try:
                return date.fromisoformat(str(deadline)[:10])
            except ValueError:
                return None

        def format_task(task: dict[str, Any], *, checked: bool) -> list[str]:
            title = task.get("title") or "Untitled task"
            group = group_map.get(task.get("groupId"))
            project = project_map.get(task.get("projectId"))
            context_parts = [v for v in [group, project] if v]

            # Check for overdue status
            deadline = parse_deadline(task)
            if deadline and deadline < today_date and not checked:
                days_overdue = (today_date - deadline).days
                if days_overdue == 1:
                    context_parts.append("overdue 1 day")
                else:
                    context_parts.append(f"overdue {days_overdue} days")

            label = f"- [{'x' if checked else ' '}] {title}"
            if context_parts:
                label = f"{label} ({', '.join(context_parts)})"
            lines = [label]
            notes = (task.get("notes") or "").strip()
            if notes:
                lines.append(f"  - Notes: {notes}")
            return lines

        # Separate overdue from today
        overdue_tasks = []
        due_today_tasks = []
        for task in today_tasks:
            deadline = parse_deadline(task)
            if deadline and deadline < today_date:
                overdue_tasks.append(task)
            else:
                due_today_tasks.append(task)

        blocks: list[str] = []

        if overdue_tasks:
            blocks.append("Overdue")
            for task in overdue_tasks:
                blocks.extend(format_task(task, checked=False))
            blocks.append("")

        blocks.append("Today")
        if due_today_tasks:
            for task in due_today_tasks:
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
            date_value = task.get("deadline")
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
