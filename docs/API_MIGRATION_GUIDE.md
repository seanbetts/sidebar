# API Migration Guide

This guide covers the transition to the versioned API surface.

## Summary

- **New base path:** `/api/v1/*`
- **Legacy path:** `/api/*` (kept for backwards compatibility)
- **Frontend:** uses `/api/v1` via the SvelteKit proxy routes

## What Changed

- Versioned routes are now the default for new clients.
- Legacy routes are still available while clients migrate.
- Error payloads are standardized across versioned routes.

## Client Update Checklist

1. Update your base URL to `/api/v1`.
2. Keep auth headers the same (`Authorization: Bearer ...`).
3. Confirm error handling uses `error.code` + `error.message` fields.

## Deprecation Window

Legacy routes will be maintained for 2–3 release cycles. Deprecation warnings will be added before removal.

