# Offline Archived + Backend Resilience Plan (2026-01-31)

## Context
Recent offline-sync work revealed that the `/websites` list (including archived content) can trigger long DB calls that block the API event loop, making the app appear offline and starving logs. A short-term mitigation now excludes archived items from the default list and offline cache.

## Goals
- Keep archived items usable offline **without** caching full content for everything.
- Prevent DB-heavy endpoints from blocking the event loop.
- Fail fast when DB is unhealthy to avoid long hangs.
- Add lightweight observability to identify slow queries.

## Non-goals
- Rewriting the DB layer or moving to async drivers.
- Changing Supabase RLS policies (unless needed for perf later).
- Offline support for full archived history.

## Decisions (Recommended)
- **Archived offline strategy:**
  - Always cache **archived headers** (names/metadata) for offline browsing.
  - Cache **full content only for recent archived items** (e.g., last 7–14 days).
  - Older archived content is **online-only** and **not cached**.
- **Backend resilience:**
  - Convert DB-heavy routes to `def` (threadpool) or wrap DB work in `run_in_threadpool`.
  - Add statement timeouts and 503 fast-fail for DB timeouts/unavailability.
  - Add slow-query logging (threshold-based) for visibility.

## Plan

## Status (as of 2026-01-31)
- ✅ Phase 1 complete (DB-heavy endpoints running sync/threadpool, fast-fail timeouts, slow-query logging).
- ✅ Phase 2 core complete (archived endpoints + offline header caching + recent-content retention window).
- ✅ Phase 2 metadata complete (archived_count + archived_last_updated).
- ✅ Phase 3 minimal polish complete (clearer archived empty states without badges).
- ✅ Phase 4 validation complete (offline archived content + DB outage checks verified).

### Phase 1 — Backend resilience (highest priority)
- [x] Convert DB-heavy endpoints to sync (`def`) or `run_in_threadpool`.
  - Targets: `notes`, `websites`, `files`, `tasks`, `conversations`, `settings`.
- [x] Add a fast-fail path for DB timeouts/unavailability:
  - Configure statement timeout (per-connection or per-request).
  - Return 503 for timeouts/OperationalError.
- [x] Add slow query instrumentation:
  - SQLAlchemy `before_cursor_execute` / `after_cursor_execute` logging.
  - Emit warnings for queries > 2s (tunable).

### Phase 2 — Archived websites + notes strategy
- [x] Backend API:
  - Add `GET /websites/archived` (summaries only, paginated).
  - Add `GET /notes/archived` (summaries only, paginated).
  - Fix archived pagination ordering (order before limit/offset).
- [x] Add optional `archived_count` + `archived_last_updated` to main list response.
- [x] iOS/macOS:
  - Cache **archived headers** in offline store.
  - Cache **full content only for recent archived** items (7-day retention window).
  - Offline behavior for older archived content: show a native placeholder and allow refresh when online.

### Phase 3 — UI/UX polish + native feel
- [x] Archived list UI:
  - Separate section with native list styling.
  - Clearer empty-state copy for online/offline/loaded states.
- [ ] Clear offline badges for content availability (deferred).
- [ ] Settings toggle (optional):
  - “Keep archived content offline for the last X days.”

### Phase 4 — Validation
- [x] Stress test: load large archive and verify no API hangs (archived list slow but non-blocking; concurrent calls still fast).
- [x] Offline test: archived headers visible; recent archived content available; older content shows placeholder.
- [x] Verify logs show slow queries and 503s during DB outage simulation.

### Validation notes (2026-01-31)
- `/websites/archived?limit=500` can take ~22–23s on large archives (non-blocking for other requests).
- Concurrent `/notes/tree` requests remain sub-second while archived requests run.
- Offline validation: archived headers load; recent archived content is cached; older archived items show placeholder.
- DB outage simulation returns fast 503s and logs slow queries/timeouts.

## Risks & Mitigations
- **Risk:** Threadpool saturation if too many heavy queries.
  - **Mitigation:** add pagination + statement timeout; reduce list sizes.
- **Risk:** Users expect archived content offline.
  - **Mitigation:** clear messaging + “recent only” option.

## Definition of Done
- DB-heavy endpoints no longer block the event loop.
- Slow DB calls return fast 503s.
- Archived headers always available offline; recent archived content cached; older archived content online-only.
- Logging provides visibility into slow queries.
