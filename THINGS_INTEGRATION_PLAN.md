# Things Integration Plan

## Goal

Expose the user’s Things data in the web app with **read + write** support, while keeping Things as the system of record. Build the integration so it can later slot into a native macOS/iOS app without rework.

Key direction changes:
- Include **Projects** and **Areas** alongside Today/Upcoming.
- Focus on Things now; GoodLinks is deferred to a later phase.
- Avoid user-editable markdown as the primary UI to prevent fragile edits. Use a **structured UI** and keep a markdown/structured snapshot for the AI assistant behind the scenes.
- Inbox view removed from the UI (Today/Upcoming + Areas/Projects only).

---

## Current Workflow Fit

This integration should reflect the current Things usage patterns:
- Day-to-day work happens in **Today**.
- Every task has a **deadline** (drives Today) and some **repeat**.
- Tasks live under two **Areas** (Home, Work) with multiple projects.
- Daily flow is **complete** or **defer** to a later date.
- Things remains the cross-device sync source until a native sideBar app exists.

Implication: build a **Today-first UI** that supports complete/defer/adjust-deadline, while leaving recurring rules and full task authoring in Things for now.

---

## Long-Term Architecture Considerations

### 1) Native App Future
If a native macOS/iOS app is planned, design the integration so:
- **Bridge layer** can be swapped for native APIs later.
- The app communicates with a **local integration service** (bridge) via a stable API surface.
- The backend expects a **normalized Things schema**, not AppleScript-specific fields.

### 2) Structured UI + Hidden Markdown
Instead of editable markdown:
- UI is **fixed and structured** (lists, projects, areas).
- The AI assistant sees a **generated markdown snapshot** (read-only to user).
- Any edits from the assistant are translated into structured changes, not raw markdown edits.

### 3) Local Database Access (Optional, Advanced)
Things data can be read from:
`~/Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac/ThingsData-{code}`
- `{code}` is a 5‑char alphanumeric identifier (ex: `VZEBC`, `G47SK`).
- This enables **faster, richer reads**, but requires careful syncing and compatibility.

### 4) Sidebar DB Mirror (Optional)
We may want a **Things mirror** in the sidebar database to:
- Allow cross-device syncing
- Drive realtime UI updates
- Let the AI work against a stable dataset

If we do this, Things remains the source of truth, and the mirror is **eventually consistent**.

---

## Bridge Deployment Model

Plan for **multiple bridges** (e.g., Work MacBook + Home Mac Studio) to ensure coverage:
- Each bridge registers with a `device_id` and sends a periodic heartbeat.
- Backend selects the **most recently seen** bridge for requests.
- If no bridge is online, UI shows a “bridge offline” state and falls back to cached data.
- Things Cloud keeps devices in sync, so any online bridge can serve the latest data.

This avoids relying on a single always-on host and improves availability across locations.

---

## Bridge Registry (Schema + API)

**Table**: `things_bridges`
- `id` (uuid, primary key)
- `user_id` (text)
- `device_id` (text, unique per user)
- `device_name` (text)
- `base_url` (text)
- `bridge_token` (text) — shared secret for backend → bridge calls
- `last_seen_at` (timestamptz)
- `created_at`, `updated_at` (timestamptz)

**Active bridge selection**
- Choose the **most recently seen** bridge within a staleness window (e.g. 2 minutes).
- If none are fresh, show “bridge offline”.

**API contracts**
```
POST /api/things/bridges/register
Body: {
  "deviceId": "mac-studio",
  "deviceName": "Mac Studio",
  "baseUrl": "https://bridge-home.example.com",
  "capabilities": { "read": true, "write": true }
}
Response: {
  "bridgeId": "uuid",
  "bridgeToken": "secret",
  "lastSeenAt": "2026-01-10T12:00:00Z"
}

POST /api/things/bridges/heartbeat
Body: { "bridgeId": "uuid" }
Response: { "lastSeenAt": "2026-01-10T12:01:00Z" }

GET /api/things/bridges
Response: [{ "bridgeId": "uuid", "deviceName": "...", "lastSeenAt": "...", "baseUrl": "..." }]
```

Notes:
- Register is idempotent by `device_id` and reuses existing `bridge_token`.
- Heartbeats should be sent every 30–60 seconds while the bridge is running.

---

## Decision Matrix

| Option | Read Coverage | Write Coverage | Reliability | Complexity | UX Latency | Future-Proof | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AppleScript API | Good | Good | Medium | Medium | Medium | Medium | Best macOS v1; no iOS; can be brittle with permissions. |
| Direct DB Read | Excellent | None | Low-Medium | High | Fast | Low | Schema changes and locking risks; macOS only. |
| Native App | Good | Good | High | High | Fast | High | Most future-proof; supports share sheet + local mirror. |

Recommended path: start with AppleScript/URL scheme for v1, add a local mirror for speed and AI snapshots, and keep direct DB reads as a last-resort optimization.

---

## Recommended Approach (Phased)

### Phase 1: Mac Host Bridge (Read + Write via AppleScript / URL Scheme)

**Why**: Safest path that does not rely on private DB structure.

Bridge runs on macOS and exposes HTTP to the FastAPI backend.

#### Bridge Responsibilities
- Read Things data with **Today-first scope** (Today + project/area context)
- Apply mutations needed for daily flow:
  - complete task
  - defer task (adjust deadline)
  - set deadline
- Use Things URL scheme when possible, AppleScript otherwise
- Expose diagnostics for DB access (repeating metadata availability).

#### Explicit v1 Non-Goals
- Creating recurring tasks or editing repeat rules
- Full task authoring from sideBar (outside Today flow)
- Non-Today list management (Someday/Anytime)

#### Bridge Execution
Apply mutations via:
  - Things URL scheme when possible
  - AppleScript for fields not supported by URL scheme

#### Bridge Endpoints
```
GET /health
GET /lists/{scope}           # today | upcoming | projects | areas
POST /apply                  # apply operations
```

#### Operations (examples)
```
{ "op": "complete", "id": "..." }
{ "op": "rename", "id": "...", "title": "..." }
{ "op": "move", "id": "...", "project_id": "..." }
{ "op": "set_due", "id": "...", "due_date": "2026-01-10" }
```

---

### Phase 2: Structured UI + Markdown Snapshot

- UI lists tasks/projects/areas with editing controls.
- Backend generates **read-only markdown snapshot** for AI use.
- No user-facing markdown editing.

---

### Phase 3: Optional DB Mirror

Sync Things data into the sidebar DB:
- Table: `things_tasks`, `things_projects`, `things_areas`
- Store Things IDs + timestamps
- Bridge applies writes and updates the mirror

This enables realtime UI updates and fast search.

---

### Phase 4: Optional Direct DB Reads

Only if needed:
- Read from Things SQLite store directly
- Requires per‑version migration handling
- Higher risk, but richer data access

---

## Security

- Bridge only listens on `127.0.0.1`
- Requests require `X-Things-Token`
- FastAPI uses env config:
  ```
  THINGS_BRIDGE_URL=http://192.168.5.2:8787
  THINGS_BRIDGE_TOKEN=...
```

---

## Notes on Projects and Areas

We need AppleScript/URL coverage for:
- Listing projects by area
- Listing tasks per project
- Marking project/task complete
- Renaming and moving tasks between projects

If URL scheme doesn’t support a mutation, use AppleScript.

---

## Bridge Data Schema (v1)

The bridge returns a **normalized payload** so the backend/UI stay stable even if AppleScript/URL details change.

### Core Entities

**Task**
```
{
  "id": "things-task-id",
  "title": "Call supplier",
  "status": "open|completed|canceled",
  "deadline": "2026-01-10",
  "deadlineStart": "2026-01-10",
  "notes": "optional notes",
  "projectId": "things-project-id",
  "areaId": "things-area-id",
  "repeating": true,
  "repeatTemplate": false,
  "tags": ["phone", "ops"],
  "updatedAt": "2026-01-10T10:00:00Z"
}
```

**Project**
```
{
  "id": "things-project-id",
  "title": "Marketing Ops",
  "areaId": "things-area-id",
  "status": "open|completed|canceled",
  "updatedAt": "2026-01-10T10:00:00Z"
}
```

**Area**
```
{
  "id": "things-area-id",
  "title": "Work",
  "updatedAt": "2026-01-10T10:00:00Z"
}
```

### List Response Shape

**GET /lists/{scope}**
```
{
  "scope": "today",
  "generatedAt": "2026-01-10T10:00:00Z",
  "tasks": [ ...Task ],
  "projects": [ ...Project ],
  "areas": [ ...Area ]
}
```

Scope values: `today | inbox | upcoming | projects | areas`
Scope values (current UI): `today | upcoming | projects | areas`

Notes:
- `deadline` and `deadlineStart` are optional; use ISO date strings.
- `repeating` flags tasks that are part of a repeat pattern.
- `repeatTemplate` distinguishes the underlying repeating template from daily instances.
- `projectId`/`areaId` let the UI render context for Today tasks.

---

## Open Questions for Implementation

- Should Things task edits in the UI apply immediately or require a “Sync” button?
- How should conflicts be surfaced (Things updated elsewhere)?
- What is the minimal schema required for AI snapshots?

---

## Status (Current)

Completed
- Bridge registry + heartbeat + active bridge selection.
- Bridge endpoints for lists/projects/areas + apply + counts.
- Today-first UI with Areas/Projects and task completion.
- Repeating metadata + due dates via local Things DB (with diagnostics).
- Multi-bridge support (most-recent heartbeat).

Partially complete
- Defer/adjust deadline UI (backend supports `set_due`, UI not yet).
- URL scheme usage (currently AppleScript only).

Deferred
- Sidebar DB mirror.
- AI markdown snapshot.
