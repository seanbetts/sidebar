---
title: Implementation Gaps
description: Central tracker for all known divergences between the design system and the current codebase.
---

## Purpose

Single working list of every known divergence between the design system and the current codebase. This is the document to work from when planning implementation sprints.

**Design docs own the detail.** Each gap links back to the source doc where the rationale and target state are fully explained. This doc is the index, not the specification.

**Lifecycle**: When a gap is resolved, remove it from this list and update the source design doc to reflect the corrected state. Done items are not retained here; the updated design doc is the permanent record.

**Execution planning**: Grouped remediation batches, issue sizing, and review/test gates live in [Design System Gap Remediation Implementation Plan](../superpowers/plans/2026-03-30-design-system-gap-remediation.md).

**Last audit**: Reviewed against the codebase on 2026-05-17. Resolved Task 15 auth construction, write-queue background scheduling, archive-cache policy, file derivative offline availability, deprecated ingestion-center cleanup, onboarding permission recovery card consolidation, signed-off feature discovery scope, color palette consolidation, icon size token cleanup, spacing/radius token cleanup, shared form field adoption, shared pill adoption cleanup, widget deep-link deferred-route cleanup, Liquid Glass surface reconciliation, native icon centralization, and stale rows were removed; partially addressed gaps remain narrowed to the remaining divergence. `AppIcon` now owns the central native icon vocabulary, app-owned icon catalogs, shortcut/menu image catalogs, note formatting controls, source-guard coverage, and documented external payload boundaries. Remaining count: 8 gaps.

---

## iOS / macOS (native)

### High priority

| Gap | File(s) | Source |
|---|---|---|
| Shared local-first offline status and mutation-channel contract remains incomplete across chats, notes, tasks, websites, and files - `OfflineCapabilityPolicy`, `SyncCoordinator`, `WriteQueue`, `LocalFirstRepository`, and archive-cache policy helpers now define shared read/write/cache rules, but `WriteQueue`, `PendingShareStore`, and background upload paths still expose separate status, retry, and recovery surfaces | `Services/Offline/`, `AppEnvironment+PendingShares.swift`, `IngestionUploadManager.swift`, stores/view models | [offline-and-sync](./patterns/offline-and-sync), [wait-ux](./patterns/wait-ux) |

### Medium priority

| Gap | File(s) | Source |
|---|---|---|
| Direct in-app website save background completion remains incomplete - extension queued website saves now persist accepted backend job IDs through `PendingShareStore` and can resume `jobStatus` after relaunch/background continuation, but direct foreground saves still keep accepted job state only in `WebsitesViewModel.pendingWebsites` | `WebsitesViewModel+JobPolling.swift`, `WebsitesViewModel+PendingWebsites.swift`, `AppEnvironment+PendingShares.swift`, `PendingShareStore.swift`, `Info.plist` | [ios-conventions](./platform-strategy/ios-conventions), [handoffs](./patterns/handoffs) |
| Offline-capable create-flow status remains split across `WriteQueue`, `PendingShareStore`, and background uploads - product design intentionally uses separate mechanisms for optimistic writes, extension website handoffs, and file background uploads, but retry/error/status reconciliation is still handled per channel | `AppEnvironment+PendingShares.swift`, `WebsitesViewModel.swift`, `IngestionViewModel.swift`, `WriteQueue.swift`, `IngestionUploadManager.swift` | [offline-and-sync](./patterns/offline-and-sync) |
| Sentry context capture and diagnostics policy remain inconsistent - app-side context handling has improved, but extension/widget diagnostics still need a single privacy-filtered policy for values such as raw URLs | `SentryBootstrap.swift`, `ExtensionDiagnosticsReporter.swift`, `SafariWebExtensionHandler.swift`, `WidgetDataManager.swift` | [error-handling](./patterns/error-handling) |

### Low priority

| Gap | File(s) | Source |
|---|---|---|

---

## Web

### High priority

| Gap | File(s) | Source |
|---|---|---|
| Settings presented as modal `AlertDialog` - should be a dedicated `/settings` route with browser navigation support | `frontend/src/` | [web-conventions](./platform-strategy/web-conventions) |

### Medium priority

| Gap | File(s) | Source |
|---|---|---|

### Low priority

| Gap | File(s) | Source |
|---|---|---|
| Web keyboard shortcuts incomplete - full shortcut audit needed | `frontend/src/` | [menus-and-shortcuts](./patterns/menus-and-shortcuts) |
| Web tasks detail view is a modal form only - native has a dedicated detail panel; web should have an equivalent | `frontend/src/` | [web-conventions](./platform-strategy/web-conventions) |
| Skills Store is nested inside the Settings modal on web - should be a standalone section matching native | `frontend/src/` | [web-conventions](./platform-strategy/web-conventions) |

---

## Related docs

- [iOS Conventions](./platform-strategy/ios-conventions)
- [macOS Conventions](./platform-strategy/macos-conventions)
- [Web Conventions](./platform-strategy/web-conventions)
- [Colour](./foundations/colour)
- [Materials and Appearance](./foundations/materials-and-appearance)
- [Components](./components/overview)
- [Token Audit](./audits/token-audit)
