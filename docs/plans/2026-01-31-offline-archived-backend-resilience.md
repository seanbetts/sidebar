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

### Phase 1 — Backend resilience (highest priority)
1. Convert DB-heavy endpoints to sync (`def`) or `run_in_threadpool`.
   - Targets: `notes`, `websites`, `files`, `tasks`, `conversations`, `settings`.
2. Add a fast-fail path for DB timeouts/unavailability:
   - Configure statement timeout (per-connection or per-request).
   - Return 503 for timeouts/OperationalError.
3. Add slow query instrumentation:
   - SQLAlchemy `before_cursor_execute` / `after_cursor_execute` logging.
   - Emit warnings for queries > 2s (tunable).

### Phase 2 — Archived websites + notes strategy
1. Backend API:
   - Add `GET /websites/archived` (summaries only, paginated).
   - Add `GET /notes/archived` (summaries only, paginated).
   - Add optional `archived_count` or `archived_last_updated` to main list response.
2. iOS/macOS:
   - Cache **archived headers** in offline store.
   - Cache **full content only for recent archived** items.
   - Offline behavior for older archived content: show a native placeholder and allow refresh when online.

### Phase 3 — UI/UX polish + native feel
1. Archived list UI:
   - Separate section with native list styling.
   - Clear offline badges for content availability.
2. Settings toggle (optional):
   - “Keep archived content offline for the last X days.”

### Phase 4 — Validation
1. Stress test: load large archive and verify no API hangs.
2. Offline test: archived headers visible; recent archived content available; older content shows placeholder.
3. Verify logs show slow queries and 503s during DB outage simulation.

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
