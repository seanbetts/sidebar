#!/usr/bin/env python3
"""Things bridge service (macOS)."""
from __future__ import annotations

import json
import os
import subprocess
from typing import Any

from fastapi import FastAPI, Header, HTTPException, status


app = FastAPI(title="sideBar Things Bridge", version="0.1.0")

BRIDGE_TOKEN = os.getenv("THINGS_BRIDGE_TOKEN", "")
THINGS_APP_NAME = os.getenv("THINGS_APP_NAME", "Things3")


def require_token(x_things_token: str | None = Header(default=None)) -> None:
    if not BRIDGE_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="THINGS_BRIDGE_TOKEN is not set",
        )
    if not x_things_token or x_things_token != BRIDGE_TOKEN:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid bridge token")


def _run_jxa(script: str) -> dict[str, Any]:
    command = ["osascript", "-l", "JavaScript", "-e", script]
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Things AppleScript failed: {exc.stderr.strip() or exc.stdout.strip()}",
        ) from exc
    output = result.stdout.strip()
    if not output:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Things AppleScript returned empty output",
        )
    try:
        return json.loads(output)
    except json.JSONDecodeError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Things AppleScript returned invalid JSON",
        ) from exc


def _build_list_script(scope: str) -> str:
    return f"""
    const app = Application("{THINGS_APP_NAME}");
    app.includeStandardAdditions = true;

    function toIso(value) {{
      if (!value) return null;
      try {{ return (new Date(value)).toISOString(); }} catch (e) {{ return null; }}
    }}
    function safe(fn, fallback) {{
      try {{
        const value = fn();
        return value === undefined ? fallback : value;
      }} catch (e) {{
        return fallback;
      }}
    }}
    function normalizeTodo(t) {{
      return {{
        id: String(t.id()),
        title: String(t.name()),
        status: String(t.status()),
        deadline: safe(() => toIso(t.dueDate()), null),
        deadlineStart: safe(() => toIso(t.activationDate()), null),
        notes: safe(() => String(t.notes()), null),
        projectId: safe(() => {{
          const p = t.project();
          return p ? String(p.id()) : null;
        }}, null),
        areaId: safe(() => {{
          const a = t.area();
          return a ? String(a.id()) : null;
        }}, null),
        repeating: safe(() => Boolean(t.repeating()), false),
        tags: safe(() => t.tags().map(tag => String(tag.name())), []),
        updatedAt: safe(() => toIso(t.modificationDate()), null)
      }};
    }}
    function normalizeProject(p) {{
      return {{
        id: String(p.id()),
        title: String(p.name()),
        areaId: safe(() => {{
          const a = p.area();
          return a ? String(a.id()) : null;
        }}, null),
        status: String(p.status()),
        updatedAt: safe(() => toIso(p.modificationDate()), null)
      }};
    }}
    function normalizeArea(a) {{
      return {{
        id: String(a.id()),
        title: String(a.name()),
        updatedAt: safe(() => toIso(a.modificationDate()), null)
      }};
    }}

    let tasks = [];
    switch ("{scope}") {{
      case "today":
        tasks = app.lists.byName("Today").toDos();
        break;
      case "inbox":
        tasks = app.lists.byName("Inbox").toDos();
        break;
      case "upcoming":
        tasks = app.lists.byName("Upcoming").toDos();
        break;
      default:
        tasks = [];
    }}

    const projects = app.projects();
    const areas = app.areas();
    const payload = {{
      scope: "{scope}",
      generatedAt: new Date().toISOString(),
      tasks: tasks.map(normalizeTodo),
      projects: projects.map(normalizeProject),
      areas: areas.map(normalizeArea)
    }};
    JSON.stringify(payload);
    """


def _build_apply_script(payload: dict[str, Any]) -> str:
    op = payload.get("op")
    todo_id = payload.get("id")
    deadline = payload.get("due_date") or payload.get("dueDate") or payload.get("deadline")
    if not op or not todo_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="op and id are required")
    deadline_value = json.dumps(deadline)
    return f"""
    const app = Application("{THINGS_APP_NAME}");
    app.includeStandardAdditions = true;
    const todo = app.toDos.byId("{todo_id}");
    if (!todo) {{
      throw new Error("Todo not found");
    }}
    switch ("{op}") {{
      case "complete":
        todo.status = "completed";
        break;
      case "set_due":
      case "defer":
        if ({deadline_value} === null) {{
          throw new Error("due_date required");
        }}
        todo.dueDate = new Date({deadline_value});
        break;
      default:
        throw new Error("Unsupported op");
    }}
    JSON.stringify({{"status":"ok"}});
    """


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


@app.get("/lists/{scope}")
async def get_list(scope: str, x_things_token: str | None = Header(default=None)) -> dict:
    require_token(x_things_token)
    script = _build_list_script(scope)
    return _run_jxa(script)


@app.post("/apply")
async def apply_operation(request: dict, x_things_token: str | None = Header(default=None)) -> dict:
    require_token(x_things_token)
    script = _build_apply_script(request)
    return _run_jxa(script)


if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("THINGS_BRIDGE_PORT", "8787"))
    uvicorn.run(app, host="127.0.0.1", port=port)
