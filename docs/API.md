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
      "deadlineStart": "2026-01-22",
      "notes": "Optional",
      "projectId": "uuid",
      "areaId": "uuid",
      "repeating": false,
      "repeatTemplate": false,
      "tags": [],
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
