#!/usr/bin/env python3
"""Things bridge service (macOS)."""
from __future__ import annotations

import json
import os
import subprocess
import threading
import time
from urllib import request as urlrequest
from typing import Any, Optional

from fastapi import FastAPI, Header, HTTPException, status


app = FastAPI(title="sideBar Things Bridge", version="0.1.0")

BRIDGE_TOKEN = os.getenv("THINGS_BRIDGE_TOKEN", "")
THINGS_APP_NAME = os.getenv("THINGS_APP_NAME", "Things3")
BACKEND_URL = os.getenv("THINGS_BACKEND_URL", "http://localhost:8001")
BRIDGE_ID = os.getenv("THINGS_BRIDGE_ID", "")
HEARTBEAT_INTERVAL = int(os.getenv("THINGS_BRIDGE_HEARTBEAT_SECONDS", "60"))


def require_token(x_things_token: Optional[str] = Header(default=None)) -> None:
    token = _get_bridge_token()
    if not token:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="THINGS_BRIDGE_TOKEN is not set",
        )
    if not x_things_token or x_things_token != token:
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


def _heartbeat_loop() -> None:
    bridge_id = _get_bridge_id()
    bridge_token = _get_bridge_token()
    if not bridge_id or not bridge_token:
        bridge_id = bridge_id or _read_keychain_value("bridge-id")
        bridge_token = bridge_token or _read_keychain_value("bridge-token")
    if not BACKEND_URL or not bridge_id or not bridge_token:
        return
    url = f"{BACKEND_URL.rstrip('/')}/api/things/bridges/heartbeat"
    headers = {
        "X-Bridge-Id": bridge_id,
        "X-Bridge-Token": bridge_token,
        "Content-Type": "application/json",
    }
    payload = json.dumps({"bridgeId": bridge_id}).encode("utf-8")
    while True:
        try:
            req = urlrequest.Request(url, data=payload, headers=headers, method="POST")
            with urlrequest.urlopen(req, timeout=10):
                pass
        except Exception:
            pass
        time.sleep(HEARTBEAT_INTERVAL)


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


def _build_project_tasks_script(project_id: str) -> str:
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

    const project = app.projects.byId("{project_id}");
    const tasks = project ? project.toDos() : [];
    JSON.stringify({{
      scope: "project",
      generatedAt: new Date().toISOString(),
      tasks: tasks.map(normalizeTodo)
    }});
    """


def _build_area_tasks_script(area_id: str) -> str:
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

    const area = app.areas.byId("{area_id}");
    const tasks = area ? area.toDos() : [];
    JSON.stringify({{
      scope: "area",
      generatedAt: new Date().toISOString(),
      tasks: tasks.map(normalizeTodo)
    }});
    """


def _build_counts_script() -> str:
    return f"""
    const app = Application("{THINGS_APP_NAME}");
    app.includeStandardAdditions = true;

    function safe(fn, fallback) {{
      try {{
        const value = fn();
        return value === undefined ? fallback : value;
      }} catch (e) {{
        return fallback;
      }}
    }}
    const projectIds = {{}};
    function isTask(t) {{
      try {{
        const todoId = safe(() => String(t.id()), "");
        if (todoId && projectIds[todoId]) {{
          return false;
        }}
        const className = String(t.class && t.class());
        if (className && className.toLowerCase().includes("project")) {{
          return false;
        }}
        const hasChildren = safe(() => t.toDos && typeof t.toDos === "function", false);
        if (hasChildren) {{
          return false;
        }}
        return String(t.status()) !== "project";
      }} catch (e) {{
        return true;
      }}
    }}
    function countTasks(todos) {{
      if (!todos) return 0;
      let count = 0;
      for (let i = 0; i < todos.length; i += 1) {{
        if (isTask(todos[i])) count += 1;
      }}
      return count;
    }}
    function countProjectTasks(project) {{
      return safe(() => countTasks(project.toDos()), 0);
    }}
    function countAreaTasks(area) {{
      const areaTodos = safe(() => area.toDos(), []);
      return countTasks(areaTodos);
    }}

    const inbox = app.lists.byName("Inbox");
    const today = app.lists.byName("Today");
    const upcoming = app.lists.byName("Upcoming");

    const projects = app.projects();
    const areas = app.areas();
    for (let i = 0; i < projects.length; i += 1) {{
      const projectId = safe(() => String(projects[i].id()), "");
      if (projectId) projectIds[projectId] = true;
    }}

    const payload = {{
      generatedAt: new Date().toISOString(),
      counts: {{
        inbox: countTasks(safe(() => inbox.toDos(), [])),
        today: countTasks(safe(() => today.toDos(), [])),
        upcoming: countTasks(safe(() => upcoming.toDos(), []))
      }},
      projects: projects.map(function(p) {{
        return {{
          id: String(p.id()),
          count: countProjectTasks(p)
        }};
      }}),
      areas: areas.map(function(a) {{
        return {{
          id: String(a.id()),
          count: countAreaTasks(a)
        }};
      }})
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


def _read_keychain_value(account: str) -> str:
    try:
        result = subprocess.run(
            ["security", "find-generic-password", "-s", "sidebar-things-bridge", "-a", account, "-w"],
            check=True,
            capture_output=True,
            text=True,
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return ""


def _get_bridge_token() -> str:
    return BRIDGE_TOKEN or _read_keychain_value("bridge-token")


def _get_bridge_id() -> str:
    return BRIDGE_ID or _read_keychain_value("bridge-id")


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


@app.get("/lists/{scope}")
async def get_list(scope: str, x_things_token: Optional[str] = Header(default=None)) -> dict:
    require_token(x_things_token)
    script = _build_list_script(scope)
    return _run_jxa(script)


@app.post("/apply")
async def apply_operation(request: dict, x_things_token: Optional[str] = Header(default=None)) -> dict:
    require_token(x_things_token)
    script = _build_apply_script(request)
    return _run_jxa(script)


@app.get("/projects/{project_id}/tasks")
async def get_project_tasks(project_id: str, x_things_token: Optional[str] = Header(default=None)) -> dict:
    require_token(x_things_token)
    script = _build_project_tasks_script(project_id)
    return _run_jxa(script)


@app.get("/areas/{area_id}/tasks")
async def get_area_tasks(area_id: str, x_things_token: Optional[str] = Header(default=None)) -> dict:
    require_token(x_things_token)
    script = _build_area_tasks_script(area_id)
    return _run_jxa(script)


@app.get("/counts")
async def get_counts(x_things_token: Optional[str] = Header(default=None)) -> dict:
    require_token(x_things_token)
    script = _build_counts_script()
    return _run_jxa(script)


if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("THINGS_BRIDGE_PORT", "8787"))
    if BACKEND_URL:
        thread = threading.Thread(target=_heartbeat_loop, daemon=True)
        thread.start()
    uvicorn.run(app, host="127.0.0.1", port=port)
