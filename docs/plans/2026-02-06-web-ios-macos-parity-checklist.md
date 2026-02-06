---
title: "Checklist: Web parity with iOS/macOS"
description: "Execution checklist and ownership for the web parity plan."
---

# Checklist: Web parity with iOS/macOS

## Phase 0 decision
- Search behavior decision: Keep server full-text website search on web as an accepted divergence for now (native uses local title/domain/url filtering).

## Ownership
- Frontend: web UI/store/API wiring
- Backend: only if API/service gaps are found
- Tests: frontend vitest + backend pytest where needed

## Items
- [x] 1. Weather unit setting parity
  - Owner: Frontend + Tests
  - Status: Implemented (local persisted parity), targeted tests passing
- [ ] 2. Ingestion status center parity
  - Owner: Frontend + Tests
  - Status: Pending
- [ ] 3. Quick-capture/save-website UX parity
  - Owner: Frontend + Tests
  - Status: Pending
- [ ] 4. Restore-on-launch state parity
  - Owner: Frontend + Tests
  - Status: Pending
- [ ] 5. Chat/tool execution feedback parity
  - Owner: Frontend + Tests
  - Status: Pending
- [x] 6. Website favicon display in sidebar rows
  - Owner: Frontend + Tests
  - Status: Implemented, tests pending
- [x] 7. Website favicon display in website header/title bar
  - Owner: Frontend + Tests
  - Status: Implemented, tests pending
- [x] 8. Website title/subtitle structure + formatting parity in left sidebar
  - Owner: Frontend + Tests
  - Status: Implemented, tests pending
- [x] 9. Website title/subtitle structure + formatting parity in title bar
  - Owner: Frontend + Tests
  - Status: Implemented, tests pending
- [x] 10. Reading-time display in website subtitles
  - Owner: Frontend + Tests
  - Status: Implemented, tests pending
- [x] 11. Domain formatting/extraction parity
  - Owner: Frontend + Tests
  - Status: Implemented, tests pending
- [x] 12. Click website title in title bar to open source URL
  - Owner: Frontend + Tests
  - Status: Implemented, tests pending
- [x] 13. Add `Copy URL` in website context menu(s)
  - Owner: Frontend + Tests
  - Status: Implemented, tests pending
- [x] 14. Add `Copy` (website content) in sidebar website context menu
  - Owner: Frontend + Tests
  - Status: Implemented, tests pending
- [x] 15. Archived websites loading/display parity
  - Owner: Frontend + Tests
  - Status: Implemented, tests pending
- [x] 16. Website API/frontend model parity (`favicon_*`, `reading_time`, `deleted_at`, `url_full`)
  - Owner: Frontend + Tests
  - Status: Implemented, tests pending
- [x] 17. Website search behavior alignment decision
  - Owner: Frontend
  - Status: Completed (accepted divergence)

## Validation gate
- [ ] `npm test` passes
- [ ] `npm run lint` passes
- [ ] `tsc` passes
- [ ] Any touched backend tests pass if backend changes are introduced
