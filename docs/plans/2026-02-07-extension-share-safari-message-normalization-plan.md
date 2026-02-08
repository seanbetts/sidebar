---
title: "Execution Plan: Share Sheet + Safari Extension Message and Style Normalization"
description: "Centralize success/failure messaging, UI state styling, and duplicated extension logic across ShareExtension and Safari extension targets."
created: "2026-02-07"
status: "in_progress"
---

# Execution Plan: Share Sheet + Safari Extension Message and Style Normalization

## Goal

Create one shared UX contract for extension states so Share Sheet, iOS Safari extension, and macOS Safari extension all use:

- identical message semantics
- consistent tone/copy
- consistent visual styling rules
- shared implementation paths instead of duplicated logic

## Non-Goals

- No behavior changes to backend APIs.
- No new feature work in extension flows beyond normalization/refactor.
- No broad redesign of the main app UI.

## Success Criteria

- [x] One canonical message catalog exists for extension UX states.
- [x] Share Sheet and Safari extension responses map to the same state keys.
- [x] iOS/macOS Safari native handlers are no longer duplicated.
- [x] iOS/macOS popup UX uses one shared resource set (markup/style/state mapping).
- [x] No double-prefix errors (for example `Upload failed: Upload failed: ...`).
- [x] Tests cover message mapping and key success/failure paths.

## Current Gaps to Fix

- [x] Success/failure copy varies across flows (`Website saved`, `Saved for later`, `Save failed`, checkmark variants).
- [x] Error detail policy is inconsistent (raw `localizedDescription` in some places, generic fallback in others).
- [x] iOS and macOS Safari handlers are duplicated line-for-line.
- [x] iOS and macOS Safari popup JS/CSS/HTML diverge.
- [x] Share extension queue-success/queue-failure handling is repeated in multiple methods.
- [x] Share extension view classes duplicate common visual shell structure.

## Extension UX Contract (Implemented)

### Message Matrix (code -> user copy)

| Code | Message |
|---|---|
| `saved_for_later` | Saved for later. |
| `website_saved` | Website saved. |
| `image_saved` | Image saved. |
| `file_saved` | File saved. |
| `saving_website` | Saving website... |
| `preparing_image` | Preparing image... |
| `preparing_file` | Preparing file... |
| `uploading_image` | Uploading image... |
| `uploading_file` | Uploading file... |
| `unsupported_action` | This action is not supported. |
| `missing_url` | No active tab URL found. |
| `invalid_url` | That URL is invalid. |
| `no_active_url` | No active tab URL found. |
| `queue_failed` | Could not save for later. |
| `not_authenticated` | Please sign in to sideBar first. |
| `invalid_base_url` | Invalid API base URL. |
| `invalid_share_payload` | Could not read the shared content. |
| `unsupported_content` | This content type is not supported. |
| `image_load_failed` | Could not load the image. |
| `image_process_failed` | Could not process the image. |
| `file_load_failed` | Could not load the file. |
| `file_read_failed` | Could not read the file. |
| `upload_failed` | Upload failed. Please try again. |
| `network_error` | Network error. Please try again. |
| `unknown_failure` | Something went wrong. Please try again. |

### Failure Mapping Rules

- All Safari native handler responses carry stable machine codes.
- Share extension error surfaces map through shared code-to-message helpers.
- Upload failures sanitize detail and prevent nested prefix formatting.
- Transport/system fallback strings are not shown directly to users.
- Popup surfaces use code-based mapping and do not expose raw JS exception text.

## Canonical UX Contract

### 1) Unified State Keys

- [x] Define shared state keys, for example:
- `saving`
- `saved_now`
- `saved_for_later`
- `no_active_url`
- `not_authenticated`
- `network_unavailable_saved_for_later`
- `upload_failed`
- `unsupported_content`
- `generic_failure`

### 1.1) Failure Taxonomy (Required)

- [x] Define one shared error taxonomy for extension flows, for example:
- `auth_required`
- `offline`
- `network_timeout`
- `invalid_payload`
- `unsupported_content`
- `upload_rejected`
- `queue_failed`
- `native_bridge_failed`
- `unknown_failure`
- [x] Every thrown/returned error must map to exactly one taxonomy code before UI display.
- [x] Keep taxonomy values stable so tests and analytics do not drift.

### 2) Message Policy

- [x] Each state key has exactly one user-facing default message.
- [x] Preserve detail only where safe and useful:
- `upload_failed` may include sanitized short reason.
- auth/network errors should use product copy, not raw transport errors.
- [x] Ensure punctuation/checkmark style is consistent across all targets.

### 2.1) Failure Message Rules

- [x] Never surface raw transport/system strings directly (`localizedDescription`, JS exception text, HTTP internals).
- [x] Use a deterministic mapper: `error taxonomy code -> user-facing message key`.
- [x] Support optional short detail only for allow-listed cases (for example validation failure reason).
- [x] Enforce one fallback message for unclassified errors.
- [x] Remove double-prefix or nested prefix patterns (`Upload failed: Upload failed: ...`).

### 2.2) Recovery Hints

- [x] Define which failures should include a user action hint, for example:
- auth -> sign in
- offline -> saved for later (if queue succeeds) or retry when online
- unsupported content -> supported types guidance
- [x] Keep hints concise and consistent across Share Sheet and Safari popup surfaces.

### 3) Timing Policy

- [x] Standardize success/failure auto-dismiss timings for Share Sheet.
- [x] Standardize Safari popup close behavior across iOS/macOS (either both close or both stay).

### 4) Style Policy

- [x] Define one shared visual token set for Safari popup (spacing, button style, status text style, dark mode).
- [x] Define one shared shell style for Share views (title/logo/icon/message spacing and typography).

## Refactor Architecture

### A) Share Extension (Swift)

- [x] Add a shared messaging helper for Share extension state keys.
- [x] Add a shared error-mapping helper (`Error` -> taxonomy code -> message key).
- [x] Replace ad-hoc string literals in:
- `ios/sideBar/ShareExtension/ShareViewController.swift`
- `ios/sideBar/ShareExtension/ShareExtensionEnvironment.swift`
- [x] Eliminate double-prefix upload error formatting by returning structured error reason and formatting once.
- [x] Consolidate duplicated queue result handling (`queuePendingWebsite`, `queuePendingFile`, `queuePendingFile(at:)`) behind one helper.

### B) Safari Extensions (Swift native handlers)

- [x] Move shared handler logic into one reusable unit in shared code.
- [x] Keep thin target-specific wrappers for platform registration only.
- [x] Return stable machine error codes in native response payload (not only free-form `error` strings).
- [x] Update both handler files to call shared logic:
- `ios/sideBar/sideBar Safari Extension/SafariWebExtensionHandler.swift`
- `ios/sideBar/sideBar Safari Extension (macOS) Extension/SafariWebExtensionHandler.swift`

### C) Safari Popup (Web resources)

- [x] Create one shared popup logic module for status mapping + save flow.
- [x] Map native machine error codes to shared user message keys in one place.
- [x] Create one shared popup style sheet for both iOS and macOS targets.
- [x] Align HTML structure across both popup targets so shared JS/CSS works without forks.
- [x] Keep target-specific UI only if strictly required by platform constraints.

### D) Share UI Shell (UIKit)

- [x] Extract common shell component/base view used by:
- `ShareLoadingView`
- `ShareProgressView`
- `ShareSuccessView`
- `ShareErrorView`
- [x] Keep only state-specific icon/progress behavior in concrete subclasses.

## Implementation Phases

## Phase 0: Contract First

- [x] Add `ExtensionUXContract` doc section in this plan (or a dedicated extension UX doc) with:
- state keys
- message text
- timing behavior
- close behavior
- error-detail policy
- error taxonomy and code mapping table
- fallback behavior when mapping fails

Deliverable:
- [x] Approved state/message matrix before code edits.

## Phase 1: Message Catalog + Share Extension Adoption

- [x] Implement shared Swift message catalog/types.
- [x] Implement shared Swift error taxonomy + mapper.
- [x] Replace string literals in Share extension flow with catalog lookups.
- [x] Remove double-prefix upload failure formatting.
- [x] Normalize offline/auth handling to catalog states.
- [x] Replace raw `localizedDescription` display with mapped/sanitized message paths.

Deliverable:
- [x] Share extension emits only catalog-backed messages.

## Phase 2: Safari Native Handler Consolidation

- [x] Extract shared native handler logic used by both targets.
- [x] Delete duplicate branching/error text from per-target handlers.
- [x] Ensure response payload shape remains backward compatible (`ok`, `error`, optional metadata).
- [x] Add machine code field in responses (for example `code`) and keep `error` for compatibility.

Deliverable:
- [x] One logic path for both iOS/macOS Safari native handling.

## Phase 3: Shared Popup UX (iOS + macOS)

- [x] Unify popup HTML structure.
- [x] Unify popup JS status/state mapping.
- [x] Unify popup CSS tokens and controls.
- [x] Confirm UX parity for no-tab, save success, and failure states.
- [x] Ensure popup never displays raw exception text to users.

Deliverable:
- [x] Popup behavior and styling are consistent across platforms.

## Phase 4: Share UI Shell Consolidation

- [x] Introduce base/shell view to reduce repeated layout code.
- [x] Keep existing visuals unless style contract specifies changes.
- [x] Ensure no regressions in extension load/perf.

Deliverable:
- [x] Shared shell powers all Share extension state views.

## Phase 5: Tests + Verification

### Automated

- [x] Add/expand iOS unit tests for message mapping and share flow state selection.
- [x] Add tests for Safari native handler success/failure mapping.
- [x] Add tests that verify duplicated copy does not drift between targets.
- [x] Add table-driven tests for taxonomy-code -> message-key mapping.
- [x] Add regression tests for fallback message on unknown/unexpected errors.
- [x] Add tests asserting no duplicated prefix in rendered upload failures.
- [x] Add tests that confirm user-facing copy does not include raw `NSError`/JS exception payloads.

### Manual

- [ ] Share URL online -> `saved_now` UX.
- [ ] Share URL offline -> `saved_for_later` UX.
- [ ] Share file/image online -> `saved_now` UX.
- [ ] Share file/image offline -> `saved_for_later` UX.
- [x] Safari iOS popup save success/failure/no-active-tab parity with macOS popup.
- [x] Auth-missing path shows consistent sign-in message everywhere.
- [x] Force server-side validation failure and verify sanitized, user-safe message.
- [x] Force queue write failure and verify consistent fallback failure copy.
- [x] Force network timeout and verify mapped timeout/offline copy and recovery hint.

Note: Remaining unchecked items in this section require simulator/device runtime verification.

## Phase 6: Cleanup

- [x] Remove dead helper methods and duplicate resource variants no longer needed.
- [x] Keep files under AGENTS size limits.
- [x] Update any extension docs that describe legacy message behavior.

## Risks and Mitigations

- [x] Risk: over-centralization makes platform-specific edge cases harder.
  Mitigation: keep small platform adapters with a shared core.
- [x] Risk: message normalization hides useful diagnostics.
  Mitigation: preserve detailed diagnostics in logs, show concise user copy in UI.
- [x] Risk: code-level error mapping drifts between Swift and JS surfaces.
  Mitigation: derive both mappings from one shared contract table and add parity tests.
- [x] Risk: popup behavior differences are intentional for one platform.
  Mitigation: confirm desired close behavior explicitly before finalizing Phase 3.

## Proposed PR Split

- [x] PR 1: Message catalog + Share extension integration + tests.
- [x] PR 2: Safari handler consolidation + tests.
- [x] PR 3: Shared popup resources + parity validation.
- [x] PR 4: Share UI shell refactor + cleanup.

## Done Criteria

- [x] No hardcoded user-facing success/failure strings remain in share/safari flow logic outside the catalog.
- [x] iOS/macOS Safari extension logic uses a shared core path.
- [x] Popup styling and message semantics are platform-consistent.
- [x] Error handling uses shared taxonomy + mapping with sanitized user-facing copy.
- [ ] Verification checks pass and behavior parity is confirmed manually.
