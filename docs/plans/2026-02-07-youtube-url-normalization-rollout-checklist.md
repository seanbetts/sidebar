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
- [ ] Keep backward compatibility for legacy queued pending share items with kind `.youtube`.
- [ ] Preserve explicit YouTube ingestion endpoint for Files-only flows.
- [ ] Do not add schema migrations unless we find unavoidable data collisions.

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
- [ ] New normalization service in place.
- [ ] Ingestion + transcript + website services aligned on same URL contract.

## Phase 2: iOS App + Extension Routing Changes

### 2.1 Route extension URL shares as websites

- [x] iOS Share Extension: remove YouTube special branching in `ios/sideBar/ShareExtension/ShareViewController.swift` and enqueue URL shares as website.
- [x] Safari iOS extension handler: remove `isYouTubeURL` branch and queue website in `ios/sideBar/sideBar Safari Extension/SafariWebExtensionHandler.swift`.
- [x] Safari macOS extension handler: same in `ios/sideBar/sideBar Safari Extension (macOS) Extension/SafariWebExtensionHandler.swift`.

### 2.2 Keep explicit Files Add YouTube behavior

- [ ] Keep `FilesPanel` Add YouTube action routing to `ingestYouTube`.
- [ ] Keep API call to `files/youtube` in explicit YouTube flow only.
- [ ] Verify generic website save actions always call website save flow.

### 2.3 Pending-share backward compatibility

- [ ] Keep `.youtube` handling in `ios/sideBar/sideBar/App/AppEnvironment+PendingShares.swift` for already queued items.
- [ ] Ensure new extension URL shares no longer create `.youtube` items.
- [ ] Add tests confirming both legacy and new queue items are handled correctly.

Deliverables:
- [x] Extension/share URL routing unified to website behavior.
- [x] Explicit Add YouTube flow unchanged.

## Phase 3: Web App Consistency

- [x] Keep sidebar/web generic URL save path as website-only.
- [ ] Confirm Add YouTube dialog in Files remains explicit ingestion-only path:
- `frontend/src/lib/hooks/useIngestionUploads.ts`
- [x] Align frontend YouTube ID parsing helpers with backend contract where feasible:
- `frontend/src/lib/components/websites/WebsitesViewer.svelte`
- `frontend/src/lib/components/files/UniversalViewerController.svelte`
- [ ] Update errors/messages for clarity if wording implies auto-YouTube special-casing in generic URL flows.

Deliverables:
- [x] Web behavior matches iOS/backend contract.

## Phase 4: Tests (Required)

### Backend tests

- [x] Add `backend/tests/services/test_url_normalization_service.py`.
- [x] Update `backend/tests/services/test_website_transcript_service.py` for shared contract.
- [x] Add/update ingestion helper/router tests to assert canonicalization and validation.
- [x] Add website normalization tests to cover YouTube watch URL uniqueness and dedupe behavior.

### iOS tests

- [ ] Update `ios/sideBar/sideBarTests/PendingShareStoreTests.swift`.
- [x] Update `ios/sideBar/sideBarTests/IngestionViewModelTests.swift`.
- [ ] Add tests for share extension URL routing behavior.
- [ ] Add tests for Safari extension handler URL routing behavior.

### Web tests

- [ ] Update flow tests for Add YouTube explicit path vs generic website path.
- [x] Add parser helper tests for YouTube URL forms accepted in viewer embedding.

Deliverables:
- [ ] Test coverage updated for all changed behavior surfaces.

## Phase 5: Verification Gates

- [ ] `pytest backend/tests/`
- [ ] `ruff check backend/`
- [ ] `npm --prefix frontend test`
- [ ] `npm --prefix frontend run lint`
- [ ] Type checks:
- `mypy` (backend config command used in repo)
- `npm --prefix frontend run check` or `tsc` command used in repo

Manual checks:
- [ ] Share a YouTube URL from iOS share extension: appears as website save behavior.
- [ ] Save YouTube URL from Safari extension (iOS): website save behavior.
- [ ] Save YouTube URL from Safari extension (macOS): website save behavior.
- [ ] Add YouTube Video from Files (web + iOS): still creates YouTube ingestion file.

## Phase 6: Rollout + Cleanup

- [ ] Remove dead/duplicate YouTube URL parsing helpers no longer used.
- [ ] Confirm file size limits remain within AGENTS constraints.
- [ ] Update docs with centralized URL policy location.
- [ ] Prepare release note entry:
- “YouTube links from share/save URL flows are now treated like websites; Add YouTube Video remains a Files-only action.”

## Risks and Mitigations

- [ ] Risk: URL identity collisions from normalization changes.
  Mitigation: add dedupe regression tests and validate existing records in staging.
- [ ] Risk: Extension behavior drift across iOS/macOS targets.
  Mitigation: patch both handlers in same PR and add mirrored tests.
- [ ] Risk: Transcript workflows break on unsupported YouTube variants.
  Mitigation: contract tests for `watch`, `shorts`, `embed`, `youtu.be`, invalid hosts.

## PR Batching Plan

- [ ] PR 1: Backend shared normalization service + adoption + backend tests.
- [ ] PR 2: iOS/share/Safari routing changes + iOS tests.
- [ ] PR 3: Web consistency updates + frontend tests.
- [ ] PR 4: Cleanup/docs/final verification.

## Done Criteria

- [ ] Generic URL/share flows never special-case YouTube into file ingestion.
- [ ] Add YouTube Video button remains the only path to `files/youtube`.
- [ ] URL normalization rules are centralized and reused.
- [ ] Tests, lint, and type checks pass across backend/frontend.
