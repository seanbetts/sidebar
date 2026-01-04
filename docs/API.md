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
| `SERVICE_UNAVAILABLE` | 503 | Required service unavailable (e.g., Things bridge). |
| `INTERNAL_ERROR` | 500 | Unhandled server error. |
| `EXTERNAL_SERVICE_ERROR` | 502 | Upstream service failed. |
| `HTTP_ERROR` | varies | Legacy FastAPI HTTPException normalization. |
