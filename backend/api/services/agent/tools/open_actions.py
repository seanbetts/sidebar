"""Route-backed assistant open actions."""

from __future__ import annotations

from typing import Any
from urllib.parse import quote

OPEN_ACTION_TOOL_NAMES = {
    "Open Note",
    "Open Website",
    "Open File",
    "Open Chat",
    "Open Scratchpad",
    "Open Tasks",
}

_ENTITY_CONFIG = {
    "Open Note": {
        "entity_type": "note",
        "id_field": "note_id",
        "section": "notes",
        "route_prefix": "notes",
        "label": "note",
    },
    "Open Website": {
        "entity_type": "website",
        "id_field": "website_id",
        "section": "websites",
        "route_prefix": "websites",
        "label": "website",
    },
    "Open File": {
        "entity_type": "file",
        "id_field": "file_id",
        "section": "files",
        "route_prefix": "files",
        "label": "file",
    },
    "Open Chat": {
        "entity_type": "conversation",
        "id_field": "conversation_id",
        "section": "chat",
        "route_prefix": "chat",
        "label": "chat",
    },
}


def handle_open_action(display_name: str, parameters: dict[str, Any]) -> dict[str, Any]:
    """Build a route-backed workspace patch for a built-in app destination."""
    if display_name == "Open Scratchpad":
        return _open_scratchpad()
    if display_name == "Open Tasks":
        return _open_tasks(parameters)

    config = _ENTITY_CONFIG.get(display_name)
    if config is None:
        return {"success": False, "error": f"Unsupported open action: {display_name}"}

    entity_id = _required_text(parameters, str(config["id_field"]))
    title = _optional_text(parameters, "title")
    route_url = _route(str(config["route_prefix"]), entity_id)
    entity = {
        "type": config["entity_type"],
        "id": entity_id,
    }
    if title:
        entity["title"] = title

    return _success(
        summary=_summary(str(config["label"]), title),
        entity=entity,
        route_url=route_url,
        section=str(config["section"]),
    )


def _open_scratchpad() -> dict[str, Any]:
    return _success(
        summary="Open scratchpad",
        entity={"type": "scratchpad", "id": "scratchpad", "title": "Scratchpad"},
        route_url="sidebar://scratchpad",
        section="chat",
    )


def _open_tasks(parameters: dict[str, Any]) -> dict[str, Any]:
    target = _required_text(parameters, "target")
    title = _optional_text(parameters, "title")
    if target == "today":
        entity = {"type": "task_scope", "id": "today", "title": title or "Today"}
        return _success(
            summary="Open tasks today",
            entity=entity,
            route_url="sidebar://tasks/today",
            section="tasks",
        )
    if target == "task":
        task_id = _required_text(parameters, "task_id")
        entity = {"type": "task", "id": task_id}
        if title:
            entity["title"] = title
        return _success(
            summary=_summary("task", title),
            entity=entity,
            route_url=_route("tasks/task", task_id),
            section="tasks",
        )
    if target == "project":
        project_id = _required_text(parameters, "project_id")
        entity = {"type": "task_project", "id": project_id}
        if title:
            entity["title"] = title
        return _success(
            summary=_summary("task project", title),
            entity=entity,
            route_url=_route("tasks/project", project_id),
            section="tasks",
        )
    if target == "group":
        group_id = _required_text(parameters, "group_id")
        entity = {"type": "task_group", "id": group_id}
        if title:
            entity["title"] = title
        return _success(
            summary=_summary("task group", title),
            entity=entity,
            route_url=_route("tasks/group", group_id),
            section="tasks",
        )
    raise ValueError("target must be one of: today, task, project, group")


def _success(
    *,
    summary: str,
    entity: dict[str, Any],
    route_url: str,
    section: str,
) -> dict[str, Any]:
    return {
        "success": True,
        "data": {
            "summary": summary,
            "workspace_patch": {
                "version": 1,
                "operations": [
                    {
                        "op": "open_entity",
                        "entity": entity,
                        "route_url": route_url,
                        "section": section,
                        "pane": "primary",
                    }
                ],
            },
        },
    }


def _route(prefix: str, entity_id: str) -> str:
    return f"sidebar://{prefix}/{quote(entity_id, safe='')}"


def _required_text(parameters: dict[str, Any], key: str) -> str:
    value = _optional_text(parameters, key)
    if not value:
        raise ValueError(f"{key} is required")
    return value


def _optional_text(parameters: dict[str, Any], key: str) -> str | None:
    value = parameters.get(key)
    if value is None:
        return None
    normalized = str(value).strip()
    return normalized or None


def _summary(label: str, title: str | None) -> str:
    if title:
        return f"Open {label} {title}"
    return f"Open {label}"
