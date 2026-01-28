# Near-Realtime Sync Plan (Web + iOS + macOS)

## Goal
Use lightweight change notifications to keep clients fresh, while continuing to rely on existing REST/sync endpoints for data.

## Scope
- Tasks domain only (counts + list updates)
- Near‑realtime delivery:
  - Web via SSE
  - iOS/macOS via silent APNs

## Non‑Goals
- Full realtime data streaming
- Cross-domain events (notes, files, etc.)

## Architecture Summary
1) Task changes emit a minimal change event.
2) Backend fans out events:
   - SSE to web clients
   - Silent APNs to iOS/macOS clients
3) Clients react by calling `/tasks/sync` or `/tasks/counts`.

---

## Implementation Plan

### 1) Backend: Device Tokens
- Add model: `backend/api/models/device_token.py`
  - fields: id, user_id, token, platform (ios/macos), environment (dev/prod), created_at, updated_at, disabled_at
- Add migration.
- Add service: `backend/api/services/device_token_service.py`
  - register(token)
  - disable(token)
  - list_active(user_id, platform)
- Add router: `backend/api/routers/device_tokens.py`
  - `POST /device-tokens` (register)
  - `DELETE /device-tokens` (disable)

### 2) Backend: Change Bus + SSE
- Add service: `backend/api/services/change_bus.py`
  - in-memory per-user async queues
  - TTL + cleanup
  - `publish(user_id, event)`
- Add router: `backend/api/routers/events.py`
  - `GET /events` (SSE)
  - Auth required (bearer)
- Event schema (minimal):
  - scope: "tasks"
  - hints: { todayCountChanged, changedScopes, updatedTaskIds }
  - occurredAt

### 3) Backend: APNs Push
- Add service: `backend/api/services/push_notification_service.py`
  - APNs auth key config
  - send silent push (`content-available: 1`, `badge`)
  - push‑type: background, priority: 5
- Integrate with `device_tokens` to fan out per user.

### 4) Backend: Emit Change Events
- In `backend/api/services/task_sync_service.py`:
  - compute `before = TaskService.get_counts(...)`
  - apply operations
  - compute `after = TaskService.get_counts(...)`
  - if `before.today != after.today`, emit change event
  - debounce per user (e.g., 60s window)
- Use service layer only (no business logic in router).

### 5) Web Client
- Add EventSource to `/events` after auth.
- On `scope == tasks` event:
  - debounce and call `/tasks/sync` or `/tasks/counts`.

### 6) iOS/macOS Client
- Register for remote notifications and send token to backend on login.
- Handle silent push:
  - call `/tasks/sync` or `/tasks/counts`
  - update badge + widgets
- Enable Background Modes → Remote Notifications.

---

## Tests
- Backend:
  - device token register/disable
  - change bus publish + SSE stream
  - task change emits event when today count changes
- Client:
  - web: SSE handler triggers refresh (unit/integ)
  - iOS/macOS: token registration path (unit)

---

## Open Questions
- Should “today” use server date or user timezone? (currently server)
- Preferred refresh endpoint: `/tasks/sync` vs `/tasks/counts`?
- Debounce interval for pushes/events?

## Decisions (Locked)
- APNs credentials: token-based auth key (.p8) via env vars; support dev/prod bundle IDs with `APNS_ENV`.
- Web delivery: SSE (near-realtime).
- Refresh endpoint: `/tasks/sync` for correctness (optimize later if needed).
- Timezone semantics: keep server date for v1; document as known limitation.
- Debounce/rate limits: APNs 60s per user/scope; SSE 1s per user/scope.
- Payload scope: minimal hints only (`todayCountChanged`, `changedScopes`).
- Persistence: in-memory event queues (no durable event log for v1).

---

## Rollout
- Implement backend + web SSE first (easiest to verify).
- Add APNs registration + silent push next.
- Monitor rate/latency and adjust debounce.
