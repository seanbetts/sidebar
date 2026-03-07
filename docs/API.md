---
title: "API Reference Notes"
description: "Notes on API versioning and error payload conventions."
---

# API Reference Notes

This document summarizes API versioning and error payload conventions for sideBar.

## Versioning

- **Base path:** `/api/v1` for all backend routes.
- **Legacy path:** `/api/*` routes are supported but deprecated.

### Deprecation headers

When a legacy `/api/*` route is used, the backend responds with:

- `X-API-Deprecated: true`
- `X-API-Deprecated-Path: /api/...`
- `X-API-New-Path: /api/v1/...`
- `X-API-Sunset-Date: 2026-06-01`

## Error responses

All API errors return a consistent JSON payload:

```json
{
  "error": {
    "code": "BAD_REQUEST",
    "message": "query required",
    "details": {
      "field": "query"
    }
  }
}
```

### Error codes

These are the standardized error codes returned by the backend:

| Code | HTTP | Description |
| --- | --- | --- |
| `BAD_REQUEST` | 400 | Invalid request payload or missing input. |
| `VALIDATION_ERROR` | 400 | Validation failed for a specific field. |
| `AUTHENTICATION_REQUIRED` | 401 | Missing authentication credentials. |
| `INVALID_TOKEN` | 401 | Invalid or expired token. |
| `PERMISSION_DENIED` | 403 | User lacks permission for the action. |
| `NOT_FOUND` | 404 | Resource does not exist. |
| `CONFLICT` | 409 | Resource state conflict (e.g., in-progress processing). |
| `PAYLOAD_TOO_LARGE` | 413 | Upload exceeded size limits. |
| `RANGE_NOT_SATISFIABLE` | 416 | Invalid content range requested. |
| `SERVICE_UNAVAILABLE` | 503 | Required service unavailable. |
| `INTERNAL_ERROR` | 500 | Unhandled server error. |
| `EXTERNAL_SERVICE_ERROR` | 502 | Upstream service failed. |
| `HTTP_ERROR` | varies | Legacy FastAPI HTTPException normalization. |

## Capability Platform Vocabulary

The capability-platform migration keeps **skills** as the user-facing unit for
catalog display, install state, and toggles. Internal **toolsets** remain an
execution detail and are never exposed as a user-facing toggle surface.

### Source Of Truth

- `user_skill_states` becomes the normalized source of truth for per-user skill
  enablement and install state.
- settings responses still expose `enabled_skills` and
  `installed_store_skills`, but those payloads are now derived from normalized
  runtime state rather than stored as legacy arrays on `user_settings`.
- Static capability metadata remains code-backed in the backend registry rather
  than being user-editable database content.

### Capability Registry Metadata

Each registry-backed skill record may expose compact discovery and execution
metadata without loading the full skill instructions:

- `required_toolsets`: internal executable tool groups required by the skill
- `instruction_ref`: stable reference to the full workflow instructions
- `token_estimate`: compact estimate for resolver/loader budgeting
- compact discovery metadata such as `tags`, `triggers`, and examples

### Runtime Availability Semantics

Availability is derived at runtime from registry metadata, normalized
`user_skill_states`, and any required external connections. Skills remain
visible in the catalog even when they are not executable.

Current capability availability vocabulary:

- `ready`: skill is enabled and executable
- `needs_connection`: skill is installed or enabled but blocked on a required
  external connection
- `scope_upgrade_required`: connection exists but required scopes/capabilities
  are insufficient
- `error`: skill is blocked by a recoverable runtime or dependency error

Runtime-facing metadata for blocked or degraded skills:

- `availability_status`
- `availability_reason`
- `availability_remediation`

### Resolver And Loader Boundary

- The resolver operates on the enabled skill catalog and may still select
  blocked skills when they are relevant for remediation.
- The loader only loads full instructions, examples, and runnable tool schemas
  for the selected executable subset.
- `executable_skill_ids` must therefore be a strict subset of
  `selected_skill_ids` whenever blocked skills are selected for explanation or
  reconnect guidance.

### Prompt Assembly Contract

- Blocked-skill metadata stays primarily in resolver/runtime state, not in the
  full prompt by default.
- Prompt assembly may include only compact, turn-relevant blocked-skill
  summaries when the current turn benefits from reconnect or remediation
  guidance.
- Runnable tool schemas must be assembled from the executable subset only, even
  when blocked skills remain visible to the assistant as part of capability
  reasoning.

## Chat Streaming API

Base path: `/api/v1/chat/stream` (legacy `/api/chat/stream` supported with deprecation headers).

Response is Server-Sent Events (SSE). Events are emitted as:

```text
event: <event_name>
data: <json_payload>
```

### Workspace-Related SSE Events

#### `prompt_preview`

Emitted when prompt preview tooling returns diagnostic payloads.

```json
{
  "system_prompt": "<assistant_prompt>...</assistant_prompt>",
  "first_message_prompt": "<first_message_prompt>...</first_message_prompt>",
  "system_prompt_sections": [],
  "first_message_prompt_sections": [],
  "prompt_report": {
    "system_prompt": {
      "total_chars": 1234,
      "max_chars": 20000,
      "truncated": false,
      "sections": []
    }
  },
  "workspace_context_menu_actions": ["copy_markdown", "share_text", "download"]
}
```

#### `workspace_patch`

Emitted when a tool result includes `workspace_patch` or `workspace_patches`.

```json
{
  "version": 1,
  "operations": [
    {
      "op": "present_agent_surface",
      "pane": "primary",
      "surface": {
        "type": "markdown",
        "surface_id": "prompt-preview",
        "title": "System Prompt",
        "payload": {
          "markdown": "## Prompt"
        },
        "context_menu_actions": ["copy_markdown", "share_text", "download"],
        "capabilities": {
          "can_refresh": false,
          "can_close": true
        }
      }
    }
  ]
}
```

Supported operation names in v1:

- `present_agent_surface` (`upsert_agent_surface` and `update_agent_surface` are accepted aliases)
- `close_pane`
- `set_surface_pinned`
- `swap_panes`

## Tasks API

Base path: `/api/v1/tasks`

### GET `/lists/{scope}`

Scopes: `inbox`, `today`, `upcoming`, `someday`, `search` (use `/search` endpoint), `project`, `area`.

Response (example):

```json
{
  "scope": "today",
  "generatedAt": "2026-01-22T10:15:00Z",
  "tasks": [
    {
      "id": "uuid",
      "title": "Do the thing",
      "status": "inbox",
      "deadline": "2026-01-22",
      "notes": "Optional",
      "projectId": "uuid",
      "areaId": "uuid",
      "repeating": false,
      "repeatTemplate": false,
      "updatedAt": "2026-01-22T10:14:00Z"
    }
  ],
  "projects": [{ "id": "uuid", "title": "Project", "areaId": "uuid", "status": "active" }],
  "areas": [{ "id": "uuid", "title": "Area" }]
}
```

### GET `/search?query=...`

Response (example):

```json
{
  "scope": "search",
  "generatedAt": "2026-01-22T10:15:00Z",
  "tasks": [{ "id": "uuid", "title": "Find me", "status": "inbox" }]
}
```

### GET `/counts`

Response (example):

```json
{
  "generatedAt": "2026-01-22T10:15:00Z",
  "counts": { "inbox": 3, "today": 1, "upcoming": 2 },
  "projects": [{ "id": "uuid", "count": 1 }],
  "areas": [{ "id": "uuid", "count": 2 }]
}
```

### POST `/apply`

Applies task operations (single or batched) with idempotency.

Request (single op example):

```json
{ "op": "add", "title": "New Task", "operation_id": "op-1" }
```

Request (batch example):

```json
{ "operations": [{ "op": "add", "title": "New Task", "operation_id": "op-1" }] }
```

Response (example):

```json
{
  "applied": ["op-1"],
  "tasks": [{ "id": "uuid", "title": "New Task", "status": "inbox" }],
  "nextTasks": [],
  "conflicts": [],
  "serverUpdatedSince": "2026-01-22T10:15:00Z"
}
```

### POST `/sync`

Offline-first sync endpoint. Applies outbox operations and returns deltas since
`last_sync`. Conflicts return the server version without applying the client op.

Request (example):

```json
{
  "last_sync": "2026-01-22T09:00:00Z",
  "operations": [
    {
      "operation_id": "op-2",
      "op": "rename",
      "id": "uuid",
      "title": "Updated title",
      "client_updated_at": "2026-01-22T09:01:00Z"
    }
  ]
}
```

Response (example):

```json
{
  "applied": ["op-2"],
  "tasks": [],
  "nextTasks": [],
  "conflicts": [
    {
      "operationId": "op-2",
      "op": "rename",
      "id": "uuid",
      "clientUpdatedAt": "2026-01-22T09:01:00Z",
      "serverUpdatedAt": "2026-01-22T09:05:00Z",
      "serverTask": {
        "id": "uuid",
        "title": "Server title",
        "status": "inbox",
        "updatedAt": "2026-01-22T09:05:00Z",
        "deletedAt": null
      }
    }
  ],
  "updates": {
    "tasks": [{ "id": "uuid", "title": "Server title", "deletedAt": null }],
    "projects": [{ "id": "uuid", "title": "Project", "deletedAt": null }],
    "areas": [{ "id": "uuid", "title": "Area", "deletedAt": null }]
  },
  "serverUpdatedSince": "2026-01-22T10:15:00Z"
}
```
