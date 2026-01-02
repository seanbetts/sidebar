# Things Integration Plan

## Goal

Expose the user’s Things data in the web app with **read + write** support, while keeping Things as the system of record. Build the integration so it can later slot into a native macOS/iOS app without rework.

Key direction changes:
- Include **Projects** and **Areas** alongside Today/Inbox/Upcoming.
- Focus on Things now; GoodLinks is deferred to a later phase.
- Avoid user-editable markdown as the primary UI to prevent fragile edits. Use a **structured UI** and keep a markdown/structured snapshot for the AI assistant behind the scenes.

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

## Recommended Approach (Phased)

### Phase 1: Mac Host Bridge (Read + Write via AppleScript / URL Scheme)

**Why**: Safest path that does not rely on private DB structure.

Bridge runs on macOS and exposes HTTP to the FastAPI backend.

#### Bridge Responsibilities
- Read Things data (Today/Inbox/Upcoming/Projects/Areas)
- Apply mutations via:
  - Things URL scheme when possible
  - AppleScript for fields not supported by URL scheme

#### Bridge Endpoints
```
GET /health
GET /lists/{scope}           # today | inbox | upcoming | projects | areas
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

## Open Questions for Implementation

- Should Things task edits in the UI apply immediately or require a “Sync” button?
- How should conflicts be surfaced (Things updated elsewhere)?
- What is the minimal schema required for AI snapshots?

