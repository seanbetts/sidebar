# Typecheck Fixes Plan (Mypy + Svelte-Check)

## Goals
- Resolve mypy errors in backend without weakening type safety or masking issues.
- Resolve svelte-check errors in frontend with correct typings.
- Keep behavior unchanged; only type correctness and safe refactors.

## Scope
- Backend: mypy across `backend/api` and `backend/workers`.
- Frontend: svelte-check across `frontend/src` and tests.

## Approach
1. **Baseline + config**
   - Confirm mypy/svelte-check configs.
   - Add or update typing stubs where missing.
   - Avoid ignoring broad paths unless necessary; prefer precise fixes.
2. **Backend mypy errors**
   - Fix missing stubs (alembic, yaml types) or exclude migrations if required.
   - Address Optional defaults (implicit Optional) in MCP tools.
   - Resolve SQLAlchemy Column vs value typing issues with proper model types or cast.
   - Fix any incorrect types in services/routers/helpers.
3. **Frontend svelte-check errors**
   - Fix env typing for Supabase config.
   - Fix `unknown` API response types by narrowing or typing return values.
   - Fix Svelte component typing issues (lucide icons, Collapsible.Root props).
   - Fix editor markdown storage typing and tests.
   - Fix any nullable and union issues surfaced by svelte-check.
4. **Verification**
   - Re-run `uv run mypy api workers`.
   - Re-run `npm run check`.
   - Re-run existing lint/tests as needed if typing changes touch logic.

## Notes
- Avoid schema or API behavior changes.
- Keep file size limits in mind.
