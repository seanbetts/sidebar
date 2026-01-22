# Frontend Task Sync Plan (Phase 4)

## Goals
- Add offline-first cache/outbox for tasks.
- Wire `/api/v1/tasks/sync` into the store for replay + delta merges.
- Keep UI responsive with optimistic updates and conflict handling.

## Steps
1. Add IndexedDB-backed cache + outbox utilities for tasks.
2. Implement sync orchestrator (flush outbox, merge deltas, track last_sync).
3. Update `tasks` store to use the sync orchestrator and optimistic writes.
4. Add tests for sync queue behavior and conflict merge.

## Completion
- All steps above implemented.
- Tests pass.
- Remove this plan file.
