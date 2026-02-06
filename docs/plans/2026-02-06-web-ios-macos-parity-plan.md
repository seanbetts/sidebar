---
title: "Plan: Web parity with iOS/macOS"
description: "Phased plan to bring the web app to parity with iOS/macOS for agreed in-scope features."
---

# Plan: Web parity with iOS/macOS

## Goal
Bring the web app to practical feature parity with iOS/macOS for the agreed scope, while explicitly excluding native-only and offline features.

## Scope (agreed)
1. Weather unit setting parity.
2. Ingestion status center parity.
3. Quick-capture/save-website UX parity (including pending/processing visibility).
4. Restore-on-launch state parity.
5. Chat/tool execution feedback parity.
6. Website favicon display in sidebar rows.
7. Website favicon display in website header/title bar.
8. Website title/subtitle structure + formatting parity in left sidebar.
9. Website title/subtitle structure + formatting parity in title bar.
10. Reading-time display in website subtitles where available.
11. Domain formatting/extraction parity with native behavior.
12. Click website title in title bar to open source URL.
13. Add `Copy URL` in website context menu(s).
14. Add `Copy` (website content) in sidebar website context menu.
15. Archived websites loading/display parity.
16. Website API/frontend model parity (`favicon_*`, `reading_time`, `deleted_at`, `url_full`, etc.).
17. Website search behavior alignment decision (native-like local filter vs intentional server search divergence).

## Explicitly out of scope
- Deep-linking
- Keyboard shortcuts
- Push notifications
- App lock modes
- Offline functionality

## Current-state summary (what we know)
- Backend website payload already includes key fields (`favicon_url`, `favicon_r2_key`, `reading_time`, `deleted_at`, `url_full` on detail route).
- Web website store/realtime mappings currently omit some parity fields.
- Web website row/header currently use globe icon and do not render website favicons.
- iOS website row/header includes favicon and subtitle logic (`baseDomain | readingTime` when available).
- iOS sidebar context menu includes both `Copy` and `Copy URL`; web sidebar row menu is missing these.
- iOS loads archived websites when archive section is expanded; web API/store path currently centers on non-archived list.

## Delivery strategy
Implement in 4 phases to reduce risk and keep behavior testable.

## Phase 0 — Foundation and decisions
### Tasks
- Create a parity checklist (17 items) with checkboxes and owner per item (frontend/backend/tests).
- Confirm target behavior for website search:
  - Option A: migrate web to native-style local filtering (title/domain/url).
  - Option B: keep server full-text search and document as intentional divergence.
- Define shared website formatting helpers in web (domain extraction + subtitle composition).

### Exit criteria
- A single approved behavior decision for website search.
- Shared helper contract for subtitle/domain formatting documented and ready for implementation.

## Phase 1 — Website parity (highest priority)
### Track 1: Data contract parity
- Extend web `WebsiteItem`/`WebsiteDetail` typing to include parity fields.
- Update realtime website mapper to propagate favicon + reading-time-related metadata consistently.
- Ensure delete/soft-delete semantics remain correct with `deleted_at` handling.

### Track 2: Sidebar row parity
- Replace globe placeholder with favicon rendering in website rows.
- Implement native-like title/subtitle composition:
  - title fallback behavior
  - subtitle as base-domain plus reading-time when present.
- Add `Copy` and `Copy URL` actions to sidebar website context menu.

### Track 3: Website header/title bar parity
- Render favicon in website header/title bar.
- Align header title/subtitle formatting with native.
- Make title clickable to open source URL.
- Ensure `Copy URL` action exists in header/menu parity paths.

### Track 4: Archived websites parity
- Add archived listing path in web API/service layer usage.
- Load archived list on archive-section expand (native-like behavior).
- Preserve existing non-archived list performance and avoid regressions.

### Exit criteria
- All website-specific parity items (6–16 except 1–5 and 17 decision item) are implemented.
- Website flows have passing frontend tests for row rendering, header behavior, context actions, and archived loading.

## Phase 2 — Cross-feature parity
### Track 1: Weather setting parity
- Add weather unit setting in web settings.
- Ensure setting is persisted and used by web assistant/UI where relevant.

### Track 2: Ingestion status center parity
- Implement consolidated ingestion status view with queue/progress/error surfaces.
- Ensure updates are reactive with existing realtime/event mechanisms.

### Track 3: Quick-capture/save UX parity
- Add clearer pending/processing states for website capture in web.
- Ensure transitions from pending -> available detail are deterministic and visible.

### Track 4: Restore-on-launch parity
- Restore key workspace state (selected section/item/view mode) on reload.
- Validate behavior in both split and focused layouts.

### Track 5: Chat/tool feedback parity
- Improve tool execution status visibility and transitions in chat UI.
- Ensure error and completion states are explicit and consistent.

### Exit criteria
- Items 1–5 implemented and covered by targeted tests.
- No regressions to existing chat, website, and ingestion flows.

## Phase 3 — QA, hardening, and rollout
### Tasks
- Run full checks:
  - `pytest backend/tests/`
  - `npm test` (frontend)
  - `ruff check backend/`
  - `npm run lint`
  - type checks (`mypy`, `tsc`)
- Add/update parity-focused tests:
  - website row/header rendering
  - context menu actions (`Copy`, `Copy URL`)
  - archived load behavior
  - title click open behavior
  - restore-on-launch behavior
- Perform manual parity pass against iOS/macOS reference behaviors.

### Exit criteria
- Test/lint/typecheck passes.
- Parity checklist marked complete for all in-scope items (except any explicitly accepted divergence).

## Work breakdown by area
### Frontend (primary)
- `frontend/src/lib/stores/websites.ts`
- `frontend/src/lib/realtime/realtime.ts`
- `frontend/src/lib/components/websites/WebsiteRow.svelte`
- `frontend/src/lib/components/websites/WebsiteHeader.svelte`
- `frontend/src/lib/components/websites/WebsitesPanel.svelte`
- `frontend/src/lib/components/websites/WebsitesViewer.svelte`
- `frontend/src/lib/hooks/useWebsiteActions.ts`
- `frontend/src/lib/services/api.ts`
- Settings/chat/ingestion components touched by items 1–5

### Backend (targeted)
- Verify existing endpoints/fields suffice; add only if gaps appear during implementation.
- Keep business logic in service layer (`backend/api/services/`).

### Tests
- `frontend/src/tests/stores/websites.test.ts`
- Website component tests (new or expanded)
- Backend tests only where API/service behavior is adjusted

## Risks and mitigations
- Risk: UI parity changes introduce layout regressions in narrow widths.
  - Mitigation: Add responsive test coverage and manual mobile/desktop checks.
- Risk: Data-contract drift between realtime/list/detail payloads.
  - Mitigation: Normalize mapping in one place and add mapper tests.
- Risk: Search behavior ambiguity delays implementation.
  - Mitigation: Make search decision in Phase 0 before code changes.

## Milestones
1. M1: Phase 0 complete (decision + helper contract).
2. M2: Website parity complete (Phase 1).
3. M3: Cross-feature parity complete (Phase 2).
4. M4: QA hardening + ready for release (Phase 3).

## Definition of done for this plan
- All 17 agreed in-scope items are implemented, or explicitly documented as accepted divergences.
- Out-of-scope native/offline items remain excluded.
- Tests, lint, and type checks pass.
- No service-layer or soft-delete policy violations.
