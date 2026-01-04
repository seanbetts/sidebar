# Contributing

## General Guidelines

- Prefer small, focused PRs over large refactors.
- Keep API work versioned under `/api/v1`.
- Use shared services/helpers instead of duplicating logic across routers.

## Frontend Patterns

- Keep stores/services covered by tests; UI component tests are optional unless behavior is complex.
- Favor controller + presentational split for large Svelte components.
- Avoid full sidebar reloads; prefer store updates + targeted cache events.

## Backend Patterns

- Use shared service layers for workspace operations.
- Standardize error responses with `error.code` and `error.message`.
- Preserve SSL verification in production; use `CUSTOM_CA_BUNDLE` for corporate MITM.

## Testing

- Frontend: run `npm run coverage` in `frontend/`.
- Backend: run `pytest` from `backend/`.

