Things & Good Links Integration Plan

Goal

Expose the user’s Things to‑do list inside the web app as an editable markdown document, while keeping Things as the system of record.

The app stack is:
	•	Svelte frontend
	•	FastAPI backend (Docker, via Colima)
	•	Markdown as the canonical document format for AI agents

Because Things has no HTTP API, integration is achieved via a macOS host bridge using AppleScript and the Things URL scheme.

⸻

High‑Level Architecture

+-------------------+        HTTP        +-------------------+
|  Svelte Frontend  |  <--------------> |   FastAPI (Docker)|
+-------------------+                    +-------------------+
                                                |
                                                | HTTP (LAN)
                                                v
                                       +-------------------+
                                       |  Things Bridge    |
                                       |  (macOS host)    |
                                       +-------------------+
                                                |
                                                | AppleScript / URL scheme
                                                v
                                       +-------------------+
                                       |     Things 3      |
                                       +-------------------+

Key principle:
	•	Docker never talks to Things directly.
	•	All automation runs as a normal macOS process.

⸻

Networking (Colima defaults)
	•	Containers run inside a Lima VM.
	•	The macOS host is reachable from containers at:

192.168.5.2

Bridge binding:
	•	Bridge listens on 127.0.0.1:8787 on the host.
	•	Containers call it via http://192.168.5.2:8787.

Environment variables (FastAPI):

THINGS_BRIDGE_URL=http://192.168.5.2:8787
THINGS_BRIDGE_TOKEN=<shared-secret>


⸻

Repository Layout

/app                # Svelte frontend
/api                # FastAPI backend (Docker)
/bridge              # macOS-only Things bridge
/docker-compose.yml
/Makefile

Rules:
	•	/bridge code is never containerised.
	•	Bridge is started manually or via make bridge.

⸻

Things Bridge (macOS Host Service)

Responsibilities
	•	Read data from Things using AppleScript.
	•	Write changes to Things using the Things URL scheme.
	•	Expose a small HTTP API to FastAPI.

Runtime
	•	Plain Python (or Node) process on macOS.
	•	Uses osascript for AppleScript execution.
	•	Uses open "things:///..." to apply mutations.
	•	Requires macOS Automation permission to control Things.

Security
	•	Bind only to 127.0.0.1.
	•	Require X-Things-Token header for all requests.

⸻

Bridge API (Initial Contract)

GET /health

Returns { status: "ok" }.

⸻

GET /lists/{scope}

Examples:
	•	/lists/today
	•	/lists/inbox
	•	/lists/upcoming

Response:

{
  "items": [...],
  "generated_at": "ISO-8601"
}

Each item includes:
	•	id (Things internal ID)
	•	title
	•	status (open / completed / cancelled)
	•	due_date
	•	start_date
	•	tags
	•	notes
	•	project
	•	area
	•	deep_link (things:///show?id=…)

⸻

POST /apply

Apply a set of mutations derived from edited markdown.

Request:

{
  "operations": [
    { "op": "complete", "id": "..." },
    { "op": "rename", "id": "...", "title": "New title" }
  ]
}

Response:

{
  "applied": [...],
  "failed": [...]
}


⸻

FastAPI Responsibilities
	•	Acts as the integration hub.
	•	Calls the Things bridge.
	•	Normalises data into:
	•	JSON (for UI state)
	•	Markdown (for editing and AI agents)

Endpoints (example):
	•	GET /things/today → returns markdown + JSON
	•	POST /things/apply-markdown → parses markdown, applies diff, re-syncs

⸻

Canonical Markdown Format

Markdown must be stable and round‑trippable.

Example:

# Today

- [ ] Buy milk (things:///show?id=UUID)
  - due: 2025-12-26
  - tags: errand, personal
  - notes: Semi-skimmed

- [x] Send report (things:///show?id=UUID)

Rules:
	•	Checkbox state maps to completion.
	•	Title line maps to task title.
	•	Deep link preserves identity.
	•	Metadata lines are optional but structured.

⸻

Markdown → Things Diff Strategy
	1.	Parse markdown into structured tasks.
	2.	Match tasks by Things ID (from deep link).
	3.	Generate a diff:
	•	completion toggles
	•	title changes
	•	due/start date changes
	•	notes updates
	4.	Convert diff into bridge operations.
	5.	Apply operations via bridge.
	6.	Re-fetch from Things and regenerate markdown.

Important:
	•	Things always wins in conflicts.
	•	Markdown edits are treated as proposals.

⸻

Failure Handling
	•	AppleScript failures are expected (Things closed, app restarting).
	•	Bridge returns clear errors.
	•	FastAPI surfaces failure and offers re-sync.
	•	Operations should be idempotent where possible.

⸻

Dev Workflow

colima start
make bridge
docker compose up

Bridge must be running before Things endpoints are used.

⸻

Minimal Python Bridge Implementation (Sketch)

This is a minimal, host-only bridge service intended to run on macOS (not in Docker). It provides:
	•	Token-authenticated HTTP endpoints
	•	AppleScript-based reads via osascript
	•	Mutations via the Things URL scheme using open

Dependencies
	•	Python 3.11+
	•	fastapi, uvicorn

Install:

python -m venv .venv
source .venv/bin/activate
pip install fastapi uvicorn

Suggested files

/bridge
  main.py
  things_applescript.py
  things_urls.py
  security.py

bridge/security.py

import os
from fastapi import Header, HTTPException

def require_token(x_things_token: str | None = Header(default=None)) -> None:
    expected = os.environ.get("THINGS_BRIDGE_TOKEN")
    if not expected:
        raise RuntimeError("THINGS_BRIDGE_TOKEN is not set")
    if not x_things_token or x_things_token != expected:
        raise HTTPException(status_code=401, detail="Unauthorized")

bridge/things_applescript.py

import json
import subprocess
from typing import Any

# NOTE: This script is a placeholder. You will need to implement one script per scope
# (Today, Inbox, Upcoming, Projects, Areas) depending on what you want to expose.
#
# The simplest pattern is:
# - AppleScript gathers fields into a list of records
# - AppleScript converts to JSON text
# - Python parses JSON and returns structured data

APPLE_SCRIPT_TODAY = r'''
-- Return JSON for Today tasks
-- You will need to refine this to match Things' AppleScript dictionary.
-- Keep output small and predictable.

on esc(s)
  set s to my replaceText("\", "\\", s)
  set s to my replaceText("\"", "\\"", s)
  return s
end esc

on replaceText(find, repl, s)
  set AppleScript's text item delimiters to find
  set parts to text items of s
  set AppleScript's text item delimiters to repl
  set s to parts as text
  set AppleScript's text item delimiters to ""
  return s
end replaceText

tell application "Things3"
  set theList to to dos of list "Today"
  set out to "["
  repeat with t in theList
    set tid to id of t
    set ttl to name of t
    set st to status of t as text
    set out to out & "{\"id\":\"" & (my esc(tid)) & "\",\"title\":\"" & (my esc(ttl)) & "\",\"status\":\"" & (my esc(st)) & "\"},"
  end repeat
  if out ends with "," then set out to text 1 thru -2 of out
  set out to out & "]"
  return out
end tell
'''


def run_osascript(script: str) -> str:
    proc = subprocess.run(
        ["osascript", "-e", script],
        check=False,
        capture_output=True,
        text=True,
        timeout=10,
    )
    if proc.returncode != 0:
        stderr = (proc.stderr or "").strip()
        raise RuntimeError(f"osascript failed: {stderr}")
    return (proc.stdout or "").strip()


def get_today() -> list[dict[str, Any]]:
    raw = run_osascript(APPLE_SCRIPT_TODAY)
    try:
        return json.loads(raw)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"Invalid JSON from AppleScript: {e}")

bridge/things_urls.py

import subprocess
import urllib.parse
from typing import Any

# Things URL scheme commands (add/complete/etc) are executed by opening the URL.
# The exact supported operations depend on Things' URL scheme documentation.


def open_things_url(url: str) -> None:
    proc = subprocess.run(
        ["open", url],
        check=False,
        capture_output=True,
        text=True,
        timeout=10,
    )
    if proc.returncode != 0:
        stderr = (proc.stderr or "").strip()
        raise RuntimeError(f"open URL failed: {stderr}")


def build_show_url(things_id: str) -> str:
    q = urllib.parse.urlencode({"id": things_id})
    return f"things:///show?{q}"


def build_add_url(title: str, notes: str | None = None) -> str:
    params: dict[str, Any] = {"title": title}
    if notes:
        params["notes"] = notes
    q = urllib.parse.urlencode(params)
    return f"things:///add?{q}"

# For completing/cancelling/updating tasks, prefer URL actions if supported.
# If not supported for a field you care about, fall back to AppleScript mutations.

bridge/main.py

import os
from datetime import datetime, timezone
from fastapi import Depends, FastAPI, HTTPException
from pydantic import BaseModel

from security import require_token
from things_applescript import get_today
from things_urls import open_things_url

app = FastAPI(title="things-bridge")


class Operation(BaseModel):
    op: str
    id: str | None = None
    title: str | None = None
    notes: str | None = None


class ApplyRequest(BaseModel):
    operations: list[Operation]


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/lists/today")
def lists_today(_: None = Depends(require_token)):
    items = get_today()
    return {
        "items": items,
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }


@app.post("/apply")
def apply_ops(req: ApplyRequest, _: None = Depends(require_token)):
    applied = []
    failed = []

    for op in req.operations:
        try:
            # Placeholder: implement supported operations.
            # Examples:
            # - Add: open_things_url(build_add_url(...))
            # - Show: open_things_url(build_show_url(op.id))
            # - Complete: build the proper Things URL if supported
            #
            # If a required operation isn't supported by URL scheme,
            # implement it with AppleScript.
            if op.op == "noop":
                applied.append({"op": op.op})
            else:
                raise HTTPException(status_code=400, detail=f"Unsupported op: {op.op}")
        except Exception as e:
            failed.append({"op": op.op, "error": str(e)})

    return {"applied": applied, "failed": failed}


if __name__ == "__main__":
    # Run as: THINGS_BRIDGE_TOKEN=... python bridge/main.py
    import uvicorn

    port = int(os.environ.get("THINGS_BRIDGE_PORT", "8787"))
    uvicorn.run("main:app", host="127.0.0.1", port=port, reload=True)

Running the bridge

cd bridge
source .venv/bin/activate
export THINGS_BRIDGE_TOKEN="dev-secret"
python main.py

FastAPI (container) calling the bridge
	•	Use THINGS_BRIDGE_URL=http://192.168.5.2:8787
	•	Add header X-Things-Token: <secret>

Notes
	•	You will almost certainly need to refine the AppleScript to fetch the right fields.
	•	Prefer URL scheme for mutations when possible; fall back to AppleScript mutations for anything not supported.
	•	Keep the bridge responses small and predictable; let FastAPI do formatting and markdown generation.

⸻

GoodLinks Integration (Sync Saved URLs into the App)

Goal

Sync links saved in GoodLinks into the app so they can be rendered as markdown documents (and shared with AI agents).

Constraints
	•	goodlinks:// URL scheme is excellent for actions (save/open/show list) but not ideal for exporting full lists.
	•	For reliable list export, use GoodLinks Shortcuts actions (Find Links / filter by unread/starred/tagged) and run the Shortcut from the macOS host bridge.

⸻

Architecture

Use the same macOS host bridge pattern as Things:
	•	FastAPI (Docker/Colima) calls the host bridge over HTTP.
	•	Host bridge executes a macOS Shortcut via the shortcuts CLI.
	•	Shortcut returns JSON (stdout) which the bridge returns to FastAPI.
	•	FastAPI converts JSON → canonical markdown.

⸻

GoodLinks Shortcuts Export (Recommended)

Shortcut: Export GoodLinks Links

Create a macOS Shortcut that:
	1.	Accepts optional inputs (scope + filters) such as:
	•	scope: unread | starred | tag | all (pick what you need)
	•	tag: string (when scope = tag)
	2.	Uses GoodLinks actions to retrieve links matching the filter.
	3.	Transforms results into a JSON array, each item with a stable schema:

Suggested JSON item shape:

{
  "url": "https://example.com",
  "title": "Example",
  "summary": "Optional",
  "tags": ["ai", "reading"],
  "starred": true,
  "read": false,
  "added_at": "2025-12-25T19:00:00Z"
}

	4.	Outputs the JSON as text (final action should be Text output).

Notes:
	•	Keep output predictable (always JSON, never empty strings).
	•	If there are no links, output [].

⸻

Bridge Implementation for GoodLinks

New files

/bridge
  goodlinks_shortcuts.py
  goodlinks_urls.py

bridge/goodlinks_shortcuts.py

import json
import subprocess
from typing import Any


def run_shortcut(name: str, input_text: str | None = None) -> str:
    cmd = ["shortcuts", "run", name]
    if input_text is not None:
        cmd += ["--input", input_text]

    proc = subprocess.run(
        cmd,
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )

    if proc.returncode != 0:
        stderr = (proc.stderr or "").strip()
        raise RuntimeError(f"shortcuts run failed: {stderr}")

    return (proc.stdout or "").strip()


def export_links(scope: str, tag: str | None = None) -> list[dict[str, Any]]:
    # Pass a tiny JSON input to the Shortcut so it can branch.
    payload = {"scope": scope}
    if tag:
        payload["tag"] = tag

    raw = run_shortcut("Export GoodLinks Links", input_text=json.dumps(payload))

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"Invalid JSON from Shortcut: {e}")

    if not isinstance(data, list):
        raise RuntimeError("Shortcut output must be a JSON array")

    return data

bridge/goodlinks_urls.py (writes via URL scheme)

import urllib.parse


def build_save_url(
    url: str | None = None,
    title: str | None = None,
    summary: str | None = None,
    tags: list[str] | None = None,
    starred: bool | None = None,
    read: bool | None = None,
    quick: bool = True,
) -> str:
    params: dict[str, str] = {}

    if url:
        params["url"] = url
    if title:
        params["title"] = title
    if summary:
        params["summary"] = summary
    if tags:
        params["tags"] = " ".join(tags)
    if starred is True:
        params["starred"] = "1"
    if read is True:
        params["read"] = "1"
    if quick:
        params["quick"] = "1"

    q = urllib.parse.urlencode(params, quote_via=urllib.parse.quote)
    return f"goodlinks://x-callback-url/save?{q}"


def build_open_url(url: str) -> str:
    q = urllib.parse.urlencode({"url": url}, quote_via=urllib.parse.quote)
    return f"goodlinks://x-callback-url/open?{q}"


⸻

Bridge API Endpoints for GoodLinks

Add these to bridge/main.py.

GET /goodlinks/{scope}

Examples:
	•	/goodlinks/unread
	•	/goodlinks/starred
	•	/goodlinks/tag?name=apple

Response:

{
  "items": [...],
  "generated_at": "ISO-8601"
}

Implementation sketch:
	•	scope in {unread, starred, all} maps directly to export_links(scope).
	•	For tag: export_links("tag", tag=name).

POST /goodlinks/save

Request:

{
  "url": "https://example.com",
  "title": "Optional",
  "summary": "Optional",
  "tags": ["ai"],
  "starred": true,
  "read": false
}

Bridge behaviour:
	•	Build URL with build_save_url(...).
	•	Execute via open <url>.
	•	Return { "status": "ok" }.

⸻

Canonical Markdown for GoodLinks

Example:

# GoodLinks: Unread

- [ ] Example article title
  - url: https://example.com
  - tags: ai, reading
  - starred: true
  - summary: Optional summary

Rules:
	•	Treat each link item as a bullet.
	•	For identity, use the URL as the primary key.
	•	If you need deep links back to GoodLinks, include an open action link:
	•	goodlinks://x-callback-url/open?url=...

⸻

Sync Strategy
	•	Default: pull on demand when the document is opened.
	•	Optional: add a periodic refresh (cron-like loop in bridge, or scheduled job in the app) that caches the last export.

Caching suggestion:
	•	Cache exports for 30–120 seconds to avoid repeated Shortcut executions during rapid UI refreshes.

⸻

Future Extensions
	•	Implement x-callback x-success flows for interactive pick-based workflows if you want user-driven selection.
	•	Add a markdown → GoodLinks “apply” path (primarily adding/saving links) rather than editing existing GoodLinks metadata.
	•	Add dedupe logic (do not re-save URLs that already exist).