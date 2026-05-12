---
title: Implementation Gaps
description: Central tracker for all known divergences between the design system and the current codebase.
---

## Purpose

Single working list of every known divergence between the design system and the current codebase. This is the document to work from when planning implementation sprints.

**Design docs own the detail.** Each gap links back to the source doc where the rationale and target state are fully explained. This doc is the index, not the specification.

**Lifecycle**: When a gap is resolved, remove it from this list and update the source design doc to reflect the corrected state. Done items are not retained here; the updated design doc is the permanent record.

**Execution planning**: Grouped remediation batches, issue sizing, and review/test gates live in [Design System Gap Remediation Implementation Plan](../superpowers/plans/2026-03-30-design-system-gap-remediation.md).

**Last audit**: Reviewed against the codebase on 2026-05-12. Resolved Task 15 auth construction, write-queue background scheduling, archive-cache policy, file derivative offline availability, deprecated ingestion-center cleanup, onboarding permission recovery card consolidation, signed-off feature discovery scope, color palette consolidation, icon size token cleanup, and stale rows were removed; partially addressed gaps remain narrowed to the remaining divergence. `AppIcon` foundation work now covers the central icon vocabulary, core owners, chat conversation share/export actions, the rationalization table, the sidebar/panel/menu action slice, and shared empty/search/status/offline component icons, while remaining feature-level direct symbols stay tracked. Remaining count: 15 gaps.

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
| Native icon usage remains only partially centralized through `AppIcon` - shared `AppIcon` vocabulary now exists and `AppSection`, header action controls, `SidebarMenuItem` factories, `SkillIconResolver`, chat conversation share/export actions, sidebar/panel/menu action symbols, and shared empty/search/status/offline component icons route through it, with a rationalization table recording canonical choices. Direct SF Symbol literals remain across non-menu feature views, widgets, extensions, platform bridges, dynamic symbol bridges, and strict source-check scope; continue migrating app-owned symbols to `AppIcon` in smaller slices | `ios/sideBar/**/*.swift` | [iconography](./foundations/iconography), [apple-icon-inventory](./audits/apple-icon-inventory-2026-05-04), [apple-icon-rationalization](./audits/apple-icon-rationalization-2026-05-09) |
| Spacing and radius literals in several views should reference existing tokens | `PanelHeader.swift`, `SidebarRail.swift`, `WorkspaceLayout.swift`, `PhoneFloatingActionMetrics` | [token-audit](./audits/token-audit) |
| Liquid Glass adoption plan remains partially complete - key chrome surfaces now use `GlassChrome`/glass-style abstractions, but adoption is not complete across all listed surfaces and should be checked against the iOS/macOS 26 target APIs | Multiple files | [materials-and-appearance](./foundations/materials-and-appearance) |
| Unified form field adoption remains incomplete - `FormField` exists and many Settings/Auth fields use it, but legacy wrappers (`ProfileIOSFieldRow`, `SettingsMacFieldRow`) and standalone auth fields still need to converge on one platform-adaptive form field system | `ProfileIOSFieldRow.swift`, `SettingsMacStyles.swift`, `SecureFieldWithToggle.swift`, onboarding views | [components](./components/overview) |
| Confirmation dialogs are still inconsistent outside destructive deletes - `DeleteConfirmationAlert` and shared patterns exist, but non-destructive confirmations still use ad hoc `.alert()`/`.confirmationDialog()` copy and structure | Settings, sidebar panels, Skills Store, Auth views | [error-presentation](./patterns/error-presentation) |
| Shared pill adoption remains incomplete - `StatusPill` and `MetadataPill` exist and toast/status surfaces use them, but tracked task/chat/tool rows still build custom `Capsule()` pill surfaces | `SiteHeaderBar.swift`, `ToastCenter.swift`, `TasksViewComponents.swift`, `ChatMessageRow.swift`, `ChatToolComponents.swift` | [pills-and-docks](./components/pills-and-docks) |

### Widget gaps

| Gap | File(s) | Source |
|---|---|---|
| Widget action intents are only partially routed through deep links - widget add/open intents now use `sidebar://` URLs, but app-side execution still relies on bespoke deferred flags such as `pendingNewTaskDeepLink` and `pendingNewNoteDeepLink` | `AppEnvironment+Widgets.swift`, `TasksViewModel.swift`, `NotesViewModel.swift` | [handoffs](./patterns/handoffs) |

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
