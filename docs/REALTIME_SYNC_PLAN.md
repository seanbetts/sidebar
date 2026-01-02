# Realtime Sync Plan (Notes, Websites, Ingested Files, Scratchpad)

## Goal

Provide near-instant UI updates when data changes outside the app (Shortcuts, Scriptable, background jobs) by subscribing to database changes and updating local stores + cache.

**Target impact:**
- New notes/websites/files appear without refresh.
- Scratchpad updates show immediately.
- Minimal extra API load.
- No duplicate items or flicker.

---

## Current State Analysis

### What We Have
- Svelte stores with local cache (localStorage) for websites, notes, files, scratchpad.
- UI mutations update store first (optimistic) then call API.
- Background changes only visible on reload or cache revalidation.

### The Gap
- External writes (Scriptable/Shortcuts/backend jobs) do not update stores in real time.
- Cached lists can stay stale for up to TTL (e.g., websites list).

---

## Proposed Solution

Use **Supabase Realtime** subscriptions to Postgres changes and apply them to local stores.

**Tables to watch:**
- `notes`
- `websites`
- `ingested_files` and `file_processing_jobs` (ingestion status)
- `scratchpad`

**Event handling:**
- `INSERT` → add to store
- `UPDATE` → update store item
- `DELETE` → remove from store

**Key principle:**
Realtime events update the local store + cache. UI stays in sync without explicit refresh while still using localStorage for instant boot and offline recovery.

---

## Architecture

### New Frontend Module
- `frontend/src/lib/realtime/realtime.ts`
  - Create and manage Supabase Realtime client
  - Provide `subscribe*` helpers
  - Centralize cleanup on logout

### Store Integration
Each store gets a small handler to apply realtime events:
- Notes: update tree + cache
- Websites: update list + cache
- Ingested files: update ingestion stores + sidebar list
- Scratchpad: update content + timestamp

### Cache + Realtime Contract
- localStorage remains the cold start source (instant UI load).
- Realtime events mutate the in-memory store **and** update localStorage cache.
- Background revalidation is retained as a safety net (missed events/offline gaps).

### Auth
- Use Supabase anon key + access token from current session.
- Ensure Realtime uses the current logged-in user.
 - Add SELECT policies using `auth.uid()` for tables used by realtime subscriptions.

---

## Implementation Phases

### Phase 1: Realtime Client Infrastructure (2–3 hours)

**Tasks:**
1. Create `realtime.ts` helper that:
   - Initializes Supabase client with Realtime enabled
   - Attaches session token for authenticated subscriptions
   - Exposes `subscribeToTable(table, handlers)`
   - Supports `unsubscribeAll()`
2. Hook into auth lifecycle to:
   - start subscriptions on login
   - stop subscriptions on logout/session expiry

**Acceptance:**
- Realtime client connects without errors.
- Subscriptions can be started/stopped reliably.

---

### Phase 2: Websites Realtime (2–3 hours)

**Tasks:**
1. Subscribe to `websites` table changes for the current user.
2. On `INSERT`:
   - Add website to `websitesStore.items` (top of list by `saved_at`).
   - Update cache (`websites.list`).
3. On `UPDATE`:
   - Update matching item + active view.
   - Update cache.
4. On `DELETE`:
   - Remove item.
   - Update cache.

**Acceptance:**
- Website saved via Scriptable appears in UI within seconds.

---

### Phase 3: Notes Realtime (3–4 hours)

**Tasks:**
1. Subscribe to `notes` table changes.
2. Map events to the notes tree:
   - INSERT → add note node
   - UPDATE → rename/move/archived/pinned changes
   - DELETE → remove note node
3. Update cache (`notes.tree`) on every change.

**Acceptance:**
- Notes created externally appear without refresh.
- Rename/move/archived changes reflect immediately.

---

### Phase 4: Ingested Files Realtime (3–4 hours)

**Tasks:**
1. Subscribe to `ingested_files` (metadata changes) and `file_processing_jobs` (status changes).
2. Update ingestion stores:
   - New file appears in sidebar when inserted.
   - Status updates (queued → ready/failed) reflect immediately.
3. Update cache for files list.

**Acceptance:**
- Files uploaded via API appear immediately.
- Processing state updates without refresh.

---

### Phase 5: Scratchpad Realtime (1–2 hours)

**Tasks:**
1. Subscribe to `scratchpad` table changes.
2. Update scratchpad store content + last_updated.
3. Ensure no flicker when local edits happen (ignore self-originated updates if needed).

**Acceptance:**
- Scratchpad updates from other clients appear instantly.

---

## Open Questions / Decisions

- Do we need a debounce or conflict resolution for rapid updates?
- Should we ignore updates originating from the same client (based on `updated_at` or a local marker)?
- Do we need row-level filters in subscriptions to ensure user isolation?
- Do we need to surface notifications for incoming changes (e.g., “New website saved”)?
 - Do we want a light periodic revalidate (e.g., on app focus) as a safety net?

---

## Risks & Mitigations

- **Duplicate updates:** Mitigate by checking IDs before inserting.
- **Out-of-order events:** Use `updated_at` to ignore stale updates.
- **Cache mismatch:** Always update cache when store changes.
- **Supabase token expiry:** Refresh session token in realtime client.

---

## Testing Plan

- Save website via Scriptable → appears in UI within 1–5s.
- Create note via API → appears in notes tree instantly.
- Upload file via API → appears and transitions to ready status.
- Scratchpad updated externally → content updates without refresh.
- Logout/login → subscriptions reset and no duplicate listeners.

---

## Estimated Effort

- Total: ~10–14 hours depending on tree/ingestion mapping complexity.
