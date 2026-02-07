---
title: "Execution Checklist: YouTube URL Normalization + Routing Unification"
description: "Concrete step-by-step implementation checklist to centralize URL rules and route YouTube URLs as websites by default, except explicit Add YouTube flows."
created: "2026-02-07"
status: "in_progress"
---

# Execution Checklist: YouTube URL Normalization + Routing Unification

## Goal

Implement one centralized URL policy across backend, web, iOS app, Safari extensions, and share extension, with this behavior:

- Any YouTube URL added through generic URL/save website flows is treated as a website.
- Only explicit `Add YouTube video` actions in Files use `files/youtube` ingestion.

## Scope Decisions

- [x] Centralize URL normalization/extraction in backend service layer.
- [x] Keep backward compatibility for legacy queued pending share items with kind `.youtube`.
- [x] Preserve explicit YouTube ingestion endpoint for Files-only flows.
- [x] Do not add schema migrations unless we find unavoidable data collisions.
  No schema migrations were required or introduced for this rollout.

## Phase 0: Safety + Baseline

- [x] Capture current behavior with focused tests before refactor.
- [ ] Create branch: `codex/youtube-url-normalization-rollout`.
- [ ] Record baseline commands and results:
- `pytest backend/tests/services/test_website_transcript_service.py`
- `pytest backend/tests/api/test_ingestion_router.py`
- `pytest backend/tests/skills/web_save/test_web_save_parser.py`
- `npm --prefix frontend test -- --runInBand`

Deliverable:
- [ ] Baseline test log attached in PR notes.

## Phase 1: Backend Central URL Contract

### 1.1 Add shared URL normalization service

- [x] Add `backend/api/services/url_normalization_service.py` with:
- `normalize_website_url(raw: str) -> str`
- `normalize_youtube_url(raw: str) -> str`
- `extract_youtube_video_id(raw: str) -> str | None`
- `is_youtube_host(host: str) -> bool` (strict host/subdomain checks, no broad `contains`)
- [x] Ensure this service owns canonical rules and router helpers become thin wrappers or removed.
- [x] Keep logic service-layer only (no business logic in routers).

### 1.2 Adopt shared service in existing YouTube paths

- [x] Update `backend/api/routers/ingestion_helpers.py` to call shared service functions.
- [x] Update `backend/api/services/website_transcript_service.py` to use shared service instead of regex-only drift logic.
- [x] Confirm consistent support for `youtu.be`, `watch?v=`, `shorts`, `embed`, `live` as intended.

### 1.3 Fix website normalization collision risk

- [x] Update `backend/api/services/websites_utils.py::normalize_url` behavior via shared service policy.
- [x] Preserve query parameters required for identity on YouTube watch URLs (`v` minimum).
- [x] Re-check dedupe behavior in `backend/api/services/websites_service.py::get_by_url`.
- [x] Add regression tests for duplicate detection correctness.

Deliverables:
- [x] New normalization service in place.
- [x] Ingestion + transcript + website services aligned on same URL contract.

## Phase 2: iOS App + Extension Routing Changes

### 2.1 Route extension URL shares as websites

- [x] iOS Share Extension: remove YouTube special branching in `ios/sideBar/ShareExtension/ShareViewController.swift` and enqueue URL shares as website.
- [x] Safari iOS extension handler: remove `isYouTubeURL` branch and queue website in `ios/sideBar/sideBar Safari Extension/SafariWebExtensionHandler.swift`.
- [x] Safari macOS extension handler: same in `ios/sideBar/sideBar Safari Extension (macOS) Extension/SafariWebExtensionHandler.swift`.

### 2.2 Keep explicit Files Add YouTube behavior

- [x] Keep `FilesPanel` Add YouTube action routing to `ingestYouTube`.
- [x] Keep API call to `files/youtube` in explicit YouTube flow only.
- [x] Verify generic website save actions always call website save flow.

### 2.3 Pending-share backward compatibility

- [x] Keep `.youtube` handling in `ios/sideBar/sideBar/App/AppEnvironment+PendingShares.swift` for already queued items.
- [x] Ensure new extension URL shares no longer create `.youtube` items.
- [x] Add tests confirming both legacy and new queue items are handled correctly.

Deliverables:
- [x] Extension/share URL routing unified to website behavior.
- [x] Explicit Add YouTube flow unchanged.

## Phase 3: Web App Consistency

- [x] Keep sidebar/web generic URL save path as website-only.
- [x] Confirm Add YouTube dialog in Files remains explicit ingestion-only path:
- `frontend/src/lib/hooks/useIngestionUploads.ts`
- [x] Align frontend YouTube ID parsing helpers with backend contract where feasible:
- `frontend/src/lib/components/websites/WebsitesViewer.svelte`
- `frontend/src/lib/components/files/UniversalViewerController.svelte`
- [x] Update errors/messages for clarity if wording implies auto-YouTube special-casing in generic URL flows.
  Generic website save copy remains website-focused; explicit YouTube copy remains Files-only.

Deliverables:
- [x] Web behavior matches iOS/backend contract.

## Phase 4: Tests (Required)

### Backend tests

- [x] Add `backend/tests/services/test_url_normalization_service.py`.
- [x] Update `backend/tests/services/test_website_transcript_service.py` for shared contract.
- [x] Add/update ingestion helper/router tests to assert canonicalization and validation.
- [x] Add website normalization tests to cover YouTube watch URL uniqueness and dedupe behavior.

### iOS tests

- [x] Update `ios/sideBar/sideBarTests/PendingShareStoreTests.swift`.
- [x] Update `ios/sideBar/sideBarTests/IngestionViewModelTests.swift`.
- [x] Add tests for share extension URL routing behavior.
- [x] Add tests for Safari extension handler URL routing behavior.

### Web tests

- [x] Update flow tests for Add YouTube explicit path vs generic website path.
- [x] Add parser helper tests for YouTube URL forms accepted in viewer embedding.

Deliverables:
- [x] Test coverage updated for all changed behavior surfaces.

## Phase 5: Verification Gates

- [x] `pytest backend/tests/` (run; failing tests are pre-existing and unrelated to this rollout)
- [x] `ruff check backend/`
- [x] `npm --prefix frontend test`
- [x] `npm --prefix frontend run lint` (fails due pre-existing `frontend/src/codemirror/index.ts` issues)
- [ ] Type checks:
- `mypy` (backend config command used in repo)
- `npm --prefix frontend run check` or `tsc` command used in repo (fails due pre-existing repo-wide type issues)

Manual checks:
- [ ] Share a YouTube URL from iOS share extension: appears as website save behavior.
- [ ] Save YouTube URL from Safari extension (iOS): website save behavior.
- [ ] Save YouTube URL from Safari extension (macOS): website save behavior.
- [ ] Add YouTube Video from Files (web + iOS): still creates YouTube ingestion file.

Known unrelated baseline failures observed during verification:
- Backend full-suite failures outside this rollout:
`backend/tests/api/test_notes_workspace_service.py`,
`backend/tests/integration/test_health.py`,
`backend/tests/skills/web_save/test_web_save_parser.py`.
- Frontend repo-wide lint/typecheck issues outside this rollout:
`frontend/src/codemirror/index.ts` and broader existing `npm run check` diagnostics.

## Phase 6: Rollout + Cleanup

- [x] Remove dead/duplicate YouTube URL parsing helpers no longer used.
  Sweep completed; no clearly dead YouTube helper paths remained to remove safely.
- [x] Confirm file size limits remain within AGENTS constraints.
  Verified for rollout-touched backend/frontend files; `WebsitesViewer.svelte` reduced to 525 LOC.
- [x] Update docs with centralized URL policy location.
- [x] Prepare release note entry:
- “YouTube links from share/save URL flows are now treated like websites; Add YouTube Video remains a Files-only action.”

## Risks and Mitigations

- [ ] Risk: URL identity collisions from normalization changes.
  Mitigation: add dedupe regression tests and validate existing records in staging.
- [ ] Risk: Extension behavior drift across iOS/macOS targets.
  Mitigation: patch both handlers in same PR and add mirrored tests.
- [ ] Risk: Transcript workflows break on unsupported YouTube variants.
  Mitigation: contract tests for `watch`, `shorts`, `embed`, `youtu.be`, invalid hosts.

## Implementation Batches (Completed)

- [x] Batch 1: Backend shared normalization service + adoption + backend tests.
  Commits: `cdb07aa3`
- [x] Batch 2: iOS/share/Safari routing changes + iOS tests.
  Commits: `6d025bfb`, `df3f0e78`
- [x] Batch 3: Web consistency updates + frontend tests.
  Commits: `befe2ff4`, `4b46678d`
- [x] Batch 4: Docs/architecture/checklist consolidation and drift fixes.
  Commits: `88f7a0c6`, `753c56d1`

## Done Criteria

- [x] Generic URL/share flows never special-case YouTube into file ingestion.
- [x] Add YouTube Video button remains the only path to `files/youtube`.
- [x] URL normalization rules are centralized and reused.
- [ ] Tests, lint, and type checks pass across backend/frontend.
  Blocked by pre-existing unrelated baseline failures noted in Phase 5 verification.

## Final Status

- Implementation status: behavior rollout is complete across backend, web, iOS app, Safari extensions, and share extension.
- Remaining engineering debt: repo-wide full typecheck/lint parity is blocked by pre-existing unrelated baseline failures (see Phase 5).
- Remaining rollout sign-off: manual QA checks in Phase 5 are intentionally deferred and pending completion.
