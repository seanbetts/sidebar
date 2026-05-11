---
title: Implementation Gaps
description: Central tracker for all known divergences between the design system and the current codebase.
---

## Purpose

Single working list of every known divergence between the design system and the current codebase. This is the document to work from when planning implementation sprints.

**Design docs own the detail.** Each gap links back to the source doc where the rationale and target state are fully explained. This doc is the index, not the specification.

**Lifecycle**: When a gap is resolved, remove it from this list and update the source design doc to reflect the corrected state. Done items are not retained here; the updated design doc is the permanent record.

**Execution planning**: Grouped remediation batches, issue sizing, and review/test gates live in [Design System Gap Remediation Implementation Plan](../superpowers/plans/2026-03-30-design-system-gap-remediation.md).

**Last audit**: Reviewed against the codebase on 2026-05-11. Resolved Task 15 auth construction and stale rows were removed; partially addressed gaps remain narrowed to the remaining divergence. Remaining count: 24 gaps.

---

## iOS / macOS (native)

### High priority

| Gap | File(s) | Source |
|---|---|---|
| Shared local-first offline engine remains incomplete across chats, notes, tasks, websites, and files - `OfflineStore`, `WriteQueue`, and local-first helpers exist, but cache, optimistic writes, queueing, ID remapping, and availability rules are still not one shared contract across all surfaces | `Stores/`, `ViewModels/`, `Services/Offline/` | [offline-and-sync](./patterns/offline-and-sync), [wait-ux](./patterns/wait-ux) |
| Phase 1.5 onboarding permission cards are only partially implemented - location and notification onboarding steps/requesters exist, but the shared `OnboardingPermissionCard` component and complete onboarding-phase recovery surface are still missing | `Views/Onboarding/`, `ChatView.swift` | [onboarding](./patterns/onboarding) |
| Phase 2 AI-guided feature tour is partially implemented - `FeatureIntroCard`, `StaticFeatureCarousel`, onboarding-aware backend context, SSE events, and `onboarding-coach` exist, but a complete `FeatureTourManager`-owned tour flow is still missing | `Views/Onboarding/`, `backend/api/services/agent/` | [onboarding](./patterns/onboarding) |

### Medium priority

| Gap | File(s) | Source |
|---|---|---|
| Website save background completion remains incomplete - pending jobs can continue briefly during background continuation, but website saves still are not backed by a durable background transfer/task model that completes independently of foreground sessions | `WebsitesViewModel+JobPolling.swift`, `AppEnvironment+PendingShares.swift`, `Info.plist` | [ios-conventions](./platform-strategy/ios-conventions), [handoffs](./patterns/handoffs) |
| `WriteQueue` background flush remains incomplete - background inspection/recovery paths exist, but queue flushing is still not driven by a durable `BGProcessingTask` on network availability | `WriteQueue.swift`, `Info.plist` | [ios-conventions](./platform-strategy/ios-conventions) |
| Offline-capable create flows remain split between `WriteQueue` and `PendingShareStore` - shared queue infrastructure exists, but websites and files still use parallel pending-share/local-upload paths instead of one mutation system | `AppEnvironment+PendingShares.swift`, `WebsitesViewModel.swift`, `IngestionViewModel.swift`, `WriteQueue.swift` | [offline-and-sync](./patterns/offline-and-sync) |
| Archived notes and archived websites are only partially browsable offline from cached data - archive paths have improved, but cached archive access is still not consistently available across notes and websites | `NotesStore.swift`, `WebsitesStore.swift` | [offline-and-sync](./patterns/offline-and-sync) |
| Files cache metadata more reliably than viewable content - a file can appear in the local list while its derivative content is still unavailable offline on that device | `IngestionStore.swift`, `IngestionViewModel+Private.swift` | [offline-and-sync](./patterns/offline-and-sync) |
| Sentry context capture and diagnostics policy remain inconsistent - app-side context handling has improved, but extension/widget diagnostics still need a single privacy-filtered policy for values such as raw URLs | `SentryBootstrap.swift`, `ExtensionDiagnosticsReporter.swift`, `SafariWebExtensionHandler.swift`, `WidgetDataManager.swift` | [error-handling](./patterns/error-handling) |
| `IngestionCenterView` still acts as an active per-file tracking panel - Live Activity infrastructure exists, but the center has not been reduced to a lightweight ingestion history summary | `IngestionCenterView.swift` | [wait-ux](./patterns/wait-ux) |
| iOS color tokens use UIKit semantic colors - migrate to custom hex values matching unified palette | `Color+Platform.swift` | [colour](./foundations/colour) |
| macOS `MacOSPalette` branching in `Color+Platform.swift` - remove and replace with shared implementation | `Color+Platform.swift` | [colour](./foundations/colour) |
| Native icon usage is not centralized through `AppIcon` - 287 direct SF Symbol literal occurrences remain across the Apple app, widgets, and share extension; rationalize low-use symbols, hard-migrate app-owned symbols to the shared `AppIcon` namespace, and add strict source checks | `ios/sideBar/**/*.swift` | [iconography](./foundations/iconography), [apple-icon-inventory](./audits/apple-icon-inventory-2026-05-04) |
| Icon size literals should reference tokens | `SettingsSections+Additional.swift`, `SidebarRail.swift`, `SettingsSections+Utilities.swift` | [token-audit](./audits/token-audit) |
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
