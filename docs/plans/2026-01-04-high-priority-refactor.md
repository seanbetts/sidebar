# High Priority Refactor Plan (2026-01-04)

## Scope
Start P0 items from REFACTORING_PLAN_2026Q1.md:
1. Move DB queries out of routers into services (P0-1).
2. Fix LOC violation in backend/api/routers/ingestion.py by extracting helpers (P0-2a).
3. Centralize UUID validation (P0-4).
4. Frontend API proxy consolidation (P0-3) will be queued after backend P0s.

## Steps
1. Inventory current router DB access and UUID parsing sites; identify affected services/tests.
2. Implement service methods + router updates for ingestion/chat/memories/conversations/websites; add/adjust tests.
3. Extract ingestion helpers into ingestion_helpers.py; update references and add tests.
4. Add validation utility; replace inline UUID parsing; add tests.
5. Prepare API proxy utility and migrate first domain (notes) with tests.

## Validation
- pytest backend tests touched (service + validation + ingestion helpers)
- frontend unit tests for proxy utility (vitest)
- ruff and eslint/tsc if feasible for touched areas

## Notes
- Keep DB access in services only.
- Soft delete only; avoid data deletion.
- Ensure JSONB updates still flag_modified.
- File size limits: services <=600 LOC, routers <=500 LOC.
