---
title: "Execution Plan: Share Sheet + Safari Extension Message and Style Normalization"
description: "Centralize success/failure messaging, UI state styling, and duplicated extension logic across ShareExtension and Safari extension targets."
created: "2026-02-07"
status: "proposed"
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

- [ ] One canonical message catalog exists for extension UX states.
- [ ] Share Sheet and Safari extension responses map to the same state keys.
- [ ] iOS/macOS Safari native handlers are no longer duplicated.
- [ ] iOS/macOS popup UX uses one shared resource set (markup/style/state mapping).
- [ ] No double-prefix errors (for example `Upload failed: Upload failed: ...`).
- [ ] Tests cover message mapping and key success/failure paths.

## Current Gaps to Fix

- [ ] Success/failure copy varies across flows (`Website saved`, `Saved for later`, `Save failed`, checkmark variants).
- [ ] Error detail policy is inconsistent (raw `localizedDescription` in some places, generic fallback in others).
- [ ] iOS and macOS Safari handlers are duplicated line-for-line.
- [ ] iOS and macOS Safari popup JS/CSS/HTML diverge.
- [ ] Share extension queue-success/queue-failure handling is repeated in multiple methods.
- [ ] Share extension view classes duplicate common visual shell structure.

## Canonical UX Contract

### 1) Unified State Keys

- [ ] Define shared state keys, for example:
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

- [ ] Define one shared error taxonomy for extension flows, for example:
- `auth_required`
- `offline`
- `network_timeout`
- `invalid_payload`
- `unsupported_content`
- `upload_rejected`
- `queue_failed`
- `native_bridge_failed`
- `unknown_failure`
- [ ] Every thrown/returned error must map to exactly one taxonomy code before UI display.
- [ ] Keep taxonomy values stable so tests and analytics do not drift.

### 2) Message Policy

- [ ] Each state key has exactly one user-facing default message.
- [ ] Preserve detail only where safe and useful:
- `upload_failed` may include sanitized short reason.
- auth/network errors should use product copy, not raw transport errors.
- [ ] Ensure punctuation/checkmark style is consistent across all targets.

### 2.1) Failure Message Rules

- [ ] Never surface raw transport/system strings directly (`localizedDescription`, JS exception text, HTTP internals).
- [ ] Use a deterministic mapper: `error taxonomy code -> user-facing message key`.
- [ ] Support optional short detail only for allow-listed cases (for example validation failure reason).
- [ ] Enforce one fallback message for unclassified errors.
- [ ] Remove double-prefix or nested prefix patterns (`Upload failed: Upload failed: ...`).

### 2.2) Recovery Hints

- [ ] Define which failures should include a user action hint, for example:
- auth -> sign in
- offline -> saved for later (if queue succeeds) or retry when online
- unsupported content -> supported types guidance
- [ ] Keep hints concise and consistent across Share Sheet and Safari popup surfaces.

### 3) Timing Policy

- [ ] Standardize success/failure auto-dismiss timings for Share Sheet.
- [ ] Standardize Safari popup close behavior across iOS/macOS (either both close or both stay).

### 4) Style Policy

- [ ] Define one shared visual token set for Safari popup (spacing, button style, status text style, dark mode).
- [ ] Define one shared shell style for Share views (title/logo/icon/message spacing and typography).

## Refactor Architecture

### A) Share Extension (Swift)

- [ ] Add a shared messaging helper for Share extension state keys.
- [ ] Add a shared error-mapping helper (`Error` -> taxonomy code -> message key).
- [ ] Replace ad-hoc string literals in:
- `ios/sideBar/ShareExtension/ShareViewController.swift`
- `ios/sideBar/ShareExtension/ShareExtensionEnvironment.swift`
- [ ] Eliminate double-prefix upload error formatting by returning structured error reason and formatting once.
- [ ] Consolidate duplicated queue result handling (`queuePendingWebsite`, `queuePendingFile`, `queuePendingFile(at:)`) behind one helper.

### B) Safari Extensions (Swift native handlers)

- [ ] Move shared handler logic into one reusable unit in shared code.
- [ ] Keep thin target-specific wrappers for platform registration only.
- [ ] Return stable machine error codes in native response payload (not only free-form `error` strings).
- [ ] Update both handler files to call shared logic:
- `ios/sideBar/sideBar Safari Extension/SafariWebExtensionHandler.swift`
- `ios/sideBar/sideBar Safari Extension (macOS) Extension/SafariWebExtensionHandler.swift`

### C) Safari Popup (Web resources)

- [ ] Create one shared popup logic module for status mapping + save flow.
- [ ] Map native machine error codes to shared user message keys in one place.
- [ ] Create one shared popup style sheet for both iOS and macOS targets.
- [ ] Align HTML structure across both popup targets so shared JS/CSS works without forks.
- [ ] Keep target-specific UI only if strictly required by platform constraints.

### D) Share UI Shell (UIKit)

- [ ] Extract common shell component/base view used by:
- `ShareLoadingView`
- `ShareProgressView`
- `ShareSuccessView`
- `ShareErrorView`
- [ ] Keep only state-specific icon/progress behavior in concrete subclasses.

## Implementation Phases

## Phase 0: Contract First

- [ ] Add `ExtensionUXContract` doc section in this plan (or a dedicated extension UX doc) with:
- state keys
- message text
- timing behavior
- close behavior
- error-detail policy
- error taxonomy and code mapping table
- fallback behavior when mapping fails

Deliverable:
- [ ] Approved state/message matrix before code edits.

## Phase 1: Message Catalog + Share Extension Adoption

- [ ] Implement shared Swift message catalog/types.
- [ ] Implement shared Swift error taxonomy + mapper.
- [ ] Replace string literals in Share extension flow with catalog lookups.
- [ ] Remove double-prefix upload failure formatting.
- [ ] Normalize offline/auth handling to catalog states.
- [ ] Replace raw `localizedDescription` display with mapped/sanitized message paths.

Deliverable:
- [ ] Share extension emits only catalog-backed messages.

## Phase 2: Safari Native Handler Consolidation

- [ ] Extract shared native handler logic used by both targets.
- [ ] Delete duplicate branching/error text from per-target handlers.
- [ ] Ensure response payload shape remains backward compatible (`ok`, `error`, optional metadata).
- [ ] Add machine code field in responses (for example `code`) and keep `error` for compatibility.

Deliverable:
- [ ] One logic path for both iOS/macOS Safari native handling.

## Phase 3: Shared Popup UX (iOS + macOS)

- [ ] Unify popup HTML structure.
- [ ] Unify popup JS status/state mapping.
- [ ] Unify popup CSS tokens and controls.
- [ ] Confirm UX parity for no-tab, save success, and failure states.
- [ ] Ensure popup never displays raw exception text to users.

Deliverable:
- [ ] Popup behavior and styling are consistent across platforms.

## Phase 4: Share UI Shell Consolidation

- [ ] Introduce base/shell view to reduce repeated layout code.
- [ ] Keep existing visuals unless style contract specifies changes.
- [ ] Ensure no regressions in extension load/perf.

Deliverable:
- [ ] Shared shell powers all Share extension state views.

## Phase 5: Tests + Verification

### Automated

- [ ] Add/expand iOS unit tests for message mapping and share flow state selection.
- [ ] Add tests for Safari native handler success/failure mapping.
- [ ] Add tests that verify duplicated copy does not drift between targets.
- [ ] Add table-driven tests for taxonomy-code -> message-key mapping.
- [ ] Add regression tests for fallback message on unknown/unexpected errors.
- [ ] Add tests asserting no duplicated prefix in rendered upload failures.
- [ ] Add tests that confirm user-facing copy does not include raw `NSError`/JS exception payloads.

### Manual

- [ ] Share URL online -> `saved_now` UX.
- [ ] Share URL offline -> `saved_for_later` UX.
- [ ] Share file/image online -> `saved_now` UX.
- [ ] Share file/image offline -> `saved_for_later` UX.
- [ ] Safari iOS popup save success/failure/no-active-tab parity with macOS popup.
- [ ] Auth-missing path shows consistent sign-in message everywhere.
- [ ] Force server-side validation failure and verify sanitized, user-safe message.
- [ ] Force queue write failure and verify consistent fallback failure copy.
- [ ] Force network timeout and verify mapped timeout/offline copy and recovery hint.

## Phase 6: Cleanup

- [ ] Remove dead helper methods and duplicate resource variants no longer needed.
- [ ] Keep files under AGENTS size limits.
- [ ] Update any extension docs that describe legacy message behavior.

## Risks and Mitigations

- [ ] Risk: over-centralization makes platform-specific edge cases harder.
  Mitigation: keep small platform adapters with a shared core.
- [ ] Risk: message normalization hides useful diagnostics.
  Mitigation: preserve detailed diagnostics in logs, show concise user copy in UI.
- [ ] Risk: code-level error mapping drifts between Swift and JS surfaces.
  Mitigation: derive both mappings from one shared contract table and add parity tests.
- [ ] Risk: popup behavior differences are intentional for one platform.
  Mitigation: confirm desired close behavior explicitly before finalizing Phase 3.

## Proposed PR Split

- [ ] PR 1: Message catalog + Share extension integration + tests.
- [ ] PR 2: Safari handler consolidation + tests.
- [ ] PR 3: Shared popup resources + parity validation.
- [ ] PR 4: Share UI shell refactor + cleanup.

## Done Criteria

- [ ] No hardcoded user-facing success/failure strings remain in share/safari flow logic outside the catalog.
- [ ] iOS/macOS Safari extension logic uses a shared core path.
- [ ] Popup styling and message semantics are platform-consistent.
- [ ] Error handling uses shared taxonomy + mapping with sanitized user-facing copy.
- [ ] Verification checks pass and behavior parity is confirmed manually.
