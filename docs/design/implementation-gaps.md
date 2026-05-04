---
title: Implementation Gaps
description: Central tracker for all known divergences between the design system and the current codebase.
---

## Purpose

Single working list of every known divergence between the design system and the current codebase. This is the document to work from when planning implementation sprints.

**Design docs own the detail.** Each gap links back to the source doc where the rationale and target state are fully explained. This doc is the index, not the specification.

**Lifecycle**: When a gap is resolved, remove it from this list and update the source design doc to reflect the corrected state. Done items are not retained here; the updated design doc is the permanent record.

**Execution planning**: Grouped remediation batches, issue sizing, and review/test gates live in [Design System Gap Remediation Implementation Plan](../superpowers/plans/2026-03-30-design-system-gap-remediation.md).

**Last audit**: Reviewed against the codebase on 2026-05-04. Resolved gaps were removed; partially addressed gaps were narrowed to the remaining divergence. Remaining count: 67 gaps, 39 open and 28 partial.

---

## iOS / macOS (native)

### High priority

| Gap | File(s) | Source |
|---|---|---|
| Auth error toast not cleared on state recovery - `authError` is only cleared when the sink fires; if the session recovers, a stale error toast may persist | `AppEnvironment+Setup.swift` | [authentication](./patterns/authentication) |
| Auth adapter still leaks as concrete Supabase implementation in app construction - product-facing protocol extensions exist, but the app still directly instantiates and depends on `SupabaseAuthAdapter`; finish isolating product code behind product-shaped auth interfaces | `SupabaseAuthAdapter.swift`, app composition | [authentication](./patterns/authentication) |
| Shared request policy still not fully enforced across uploads, streaming, widgets, and extensions - `RequestExecutionPolicy` and `AppError` exist, but custom `URLSession` and extension flows still do not uniformly share auth refresh, retryability, diagnostics, and connectivity reporting | `APIClient.swift`, `SettingsAPI.swift`, `IngestionAPI.swift`, `URLSessionChatStreamClient.swift`, `IngestionUploadManager.swift`, `ShareExtensionEnvironment.swift` | [request-lifecycle](./patterns/request-lifecycle) |
| Raw backend messages and `localizedDescription` still reach user-facing UI - unclassified backend text falls through `ErrorMapping`, and several surfaces render raw system strings directly | `ErrorMapping.swift`, `BiometricLockView.swift`, `SettingsViewModel.swift`, `SettingsSections+ProfileSupport.swift`, `ConversationsPanelView+Helpers.swift`, `QueuedChangesView.swift` | [error-handling](./patterns/error-handling), [error-presentation](./patterns/error-presentation) |
| Shared local-first offline engine remains incomplete across chats, notes, tasks, websites, and files - `OfflineStore`, `WriteQueue`, and local-first helpers exist, but cache, optimistic writes, queueing, ID remapping, and availability rules are still not one shared contract across all surfaces | `Stores/`, `ViewModels/`, `Services/Offline/` | [offline-and-sync](./patterns/offline-and-sync), [wait-ux](./patterns/wait-ux) |
| Offline-unavailable detail states remain inconsistent - some detail panes now use explicit unavailable-offline states, but not all selected missing-local-content paths have converged on that pattern | `WebsitesDetailView.swift`, `FilesViewComponents.swift`, related detail surfaces | [offline-and-sync](./patterns/offline-and-sync), [error-presentation](./patterns/error-presentation) |
| Mutation failure state remains mixed with load-failure state on some surfaces - several mutations now use toasts or header status, but task and file paths still have shared `errorMessage` patterns that can compete with already-loaded content | `TasksViewModel.swift`, `TasksPanel.swift`, `TasksDetailView.swift`, `IngestionViewModel+Public.swift`, `FilesPanel.swift`, `FilesViewComponents.swift` | [error-presentation](./patterns/error-presentation) |
| Chat stream failures double-surface through generic error channels - chat already has a dedicated pill/retry/popover pattern, but stream failures also set shared error state and show generic toasts | `ChatViewModel+Streaming.swift`, `ChatViewModel+StreamingSession.swift`, `ChatViewModel+StreamingFinalize.swift`, `ChatErrorComponents.swift`, `ChatView.swift` | [error-presentation](./patterns/error-presentation), [error-handling](./patterns/error-handling) |
| Share extension still has partly separate reachability/offline-handoff policy - shared classifiers and queue handlers exist, but extension preflight/queue behavior still does not fully follow the app-wide execute-classify-recover lifecycle | `ShareNetworkMonitor.swift`, `ShareViewController+MediaHandling.swift`, `ShareExtensionEnvironment.swift` | [request-lifecycle](./patterns/request-lifecycle) |
| Phase 1.5 onboarding permission cards are only partially implemented - location and notification onboarding steps/requesters exist, but the shared `OnboardingPermissionCard` component and complete onboarding-phase recovery surface are still missing | `Views/Onboarding/`, `ChatView.swift` | [onboarding](./patterns/onboarding) |
| Phase 2 AI-guided feature tour is partially implemented - `FeatureIntroCard`, `StaticFeatureCarousel`, onboarding-aware backend context, SSE events, and `onboarding-coach` exist, but a complete `FeatureTourManager`-owned tour flow is still missing | `Views/Onboarding/`, `backend/api/services/agent/` | [onboarding](./patterns/onboarding) |
| Files header menu still has inline action construction - macOS now uses the shared header menu path with `SidebarMenuItem` items, but remaining file actions such as Share should use factory methods instead of inline item construction | `Views/Files/FilesHeaderActions.swift` | [menus-and-shortcuts](./patterns/menus-and-shortcuts) |
| `warning` color tokens still alias neutral text colors - `success` has moved to a green token, but `warning`/warning background/border still need the target amber palette `#d97706`/`#fbbf24` | `DesignTokens.swift` | [colour](./foundations/colour) |

### Medium priority

| Gap | File(s) | Source |
|---|---|---|
| Website save background completion remains incomplete - pending jobs can continue briefly during background continuation, but website saves still are not backed by a durable background transfer/task model that completes independently of foreground sessions | `WebsitesViewModel+JobPolling.swift`, `AppEnvironment+PendingShares.swift`, `Info.plist` | [ios-conventions](./platform-strategy/ios-conventions), [handoffs](./patterns/handoffs) |
| `WriteQueue` background flush remains incomplete - background inspection/recovery paths exist, but queue flushing is still not driven by a durable `BGProcessingTask` on network availability | `WriteQueue.swift`, `Info.plist` | [ios-conventions](./platform-strategy/ios-conventions) |
| `ConnectivityMonitor` still has incomplete shared transport coverage - it observes central request notifications, but probe transport and some upload/stream paths can still diverge from app request policy | `ConnectivityMonitor.swift`, `APIClient.swift` | [request-lifecycle](./patterns/request-lifecycle) |
| Offline-capable create flows remain split between `WriteQueue` and `PendingShareStore` - shared queue infrastructure exists, but websites and files still use parallel pending-share/local-upload paths instead of one mutation system | `AppEnvironment+PendingShares.swift`, `WebsitesViewModel.swift`, `IngestionViewModel.swift`, `WriteQueue.swift` | [offline-and-sync](./patterns/offline-and-sync) |
| Archived notes and archived websites are only partially browsable offline from cached data - archive paths have improved, but cached archive access is still not consistently available across notes and websites | `NotesStore.swift`, `WebsitesStore.swift` | [offline-and-sync](./patterns/offline-and-sync) |
| Files cache metadata more reliably than viewable content - a file can appear in the local list while its derivative content is still unavailable offline on that device | `IngestionStore.swift`, `IngestionViewModel+Private.swift` | [offline-and-sync](./patterns/offline-and-sync) |
| Widget refresh failure diagnostics remain inconsistent - providers have more shared refresh/diagnostic infrastructure, but silent fallback and non-standardized classification still remain in widget refresh paths | `TodayTasksProvider.swift`, `PinnedNotesProvider.swift`, `PinnedFilesProvider.swift`, `SavedSitesProvider.swift` | [request-lifecycle](./patterns/request-lifecycle), [error-handling](./patterns/error-handling) |
| Sentry context capture and diagnostics policy remain inconsistent - app-side context handling has improved, but extension/widget diagnostics still need a single privacy-filtered policy for values such as raw URLs | `SentryBootstrap.swift`, `ExtensionDiagnosticsReporter.swift`, `SafariWebExtensionHandler.swift`, `WidgetDataManager.swift` | [error-handling](./patterns/error-handling) |
| Website save progress still lacks complete stage presentation - pending save rows now distinguish queued/reading/retrying states, but the detail view still does not surface the full server job stage progression for long polling | `WebsitesDetailView+PendingSave.swift`, `WebsitesViewModel+JobPolling.swift` | [wait-ux](./patterns/wait-ux) |
| `IngestionCenterView` still acts as an active per-file tracking panel - Live Activity infrastructure exists, but the center has not been reduced to a lightweight ingestion history summary | `IngestionCenterView.swift` | [wait-ux](./patterns/wait-ux) |
| Note content edits bypass `WriteQueue` when online - `NotesEditorViewModel` calls the API directly; should apply locally first and sync in background | `NotesEditorViewModel.swift` | [wait-ux](./patterns/wait-ux) |
| Website mutations (pin, rename, archive, delete) bypass `WriteQueue` when online - only queued when offline; should be consistently optimistic | `WebsitesViewModel.swift`, `WebsitesWriteQueueExecutor.swift` | [wait-ux](./patterns/wait-ux) |
| `QueuedChangeResolutionSheet` conflict resolution modal should be removed - local always wins, no user input needed | `QueuedChangeResolutionSheet.swift`, `ContentView+SignedIn.swift` | [wait-ux](./patterns/wait-ux) |
| `QueuedChangesView` in Settings shows conflict resolution buttons ("Keep Queued Change" / "Use Server Version") - remove conflict UI; keep failed write visibility and retry only | `QueuedChangesView.swift` | [wait-ux](./patterns/wait-ux) |
| Web `TaskConflictDialog` conflict resolution modal should be removed - local always wins | `frontend/src/lib/components/tasks/TaskConflictDialog.svelte` | [wait-ux](./patterns/wait-ux) |
| Web note and website mutations still have uneven in-session retry/error surfacing - note edit paths use foreground retry helpers, but website mutations and several note/sidebar mutations still perform one-shot calls before surfacing errors | `frontend/src/lib/` | [wait-ux](./patterns/wait-ux) |
| iOS color tokens use UIKit semantic colors - migrate to custom hex values matching unified palette | `Color+Platform.swift` | [colour](./foundations/colour) |
| macOS `MacOSPalette` branching in `Color+Platform.swift` - remove and replace with shared implementation | `Color+Platform.swift` | [colour](./foundations/colour) |
| Native icon usage is not centralized through `AppIcon` - 287 direct SF Symbol literal occurrences remain across the Apple app, widgets, and share extension; rationalize low-use symbols, hard-migrate app-owned symbols to the shared `AppIcon` namespace, and add strict source checks | `ios/sideBar/**/*.swift` | [iconography](./foundations/iconography), [apple-icon-inventory](./audits/apple-icon-inventory-2026-05-04) |
| Icon size drift: 20px should be `Icon.md` (18) | `TasksViewComponents.swift` | [token-audit](./audits/token-audit) |
| Icon size drift: 30px should be `Icon.xl` (32) | `StoreSkillCredentialsView.swift` | [token-audit](./audits/token-audit) |
| Icon size literals should reference tokens | `SettingsSections+Additional.swift`, `SidebarRail.swift`, `SettingsSections+Utilities.swift` | [token-audit](./audits/token-audit) |
| SidebarRail font: `.font(.system(size: 18, weight: .semibold))` should be `.appFont(.label)` or equivalent | `SidebarRail.swift` | [macos-conventions](./platform-strategy/macos-conventions) |
| Missing size tokens: `railWidth = 56`, `dividerWidth = 8`, `rightSidebarDefaultWidth = 360` | `DesignTokens.swift` | [token-audit](./audits/token-audit) |
| Spacing and radius literals in several views should reference existing tokens | `PanelHeader.swift`, `SidebarRail.swift`, `WorkspaceLayout.swift`, `PhoneFloatingActionMetrics` | [token-audit](./audits/token-audit) |
| Liquid Glass adoption plan remains partially complete - key chrome surfaces now use `GlassChrome`/glass-style abstractions, but adoption is not complete across all listed surfaces and should be checked against the iOS/macOS 26 target APIs | Multiple files | [materials-and-appearance](./foundations/materials-and-appearance) |
| Unified form field adoption remains incomplete - `FormField` exists and many Settings/Auth fields use it, but legacy wrappers (`ProfileIOSFieldRow`, `SettingsMacFieldRow`) and standalone auth fields still need to converge on one platform-adaptive form field system | `ProfileIOSFieldRow.swift`, `SettingsMacStyles.swift`, `SecureFieldWithToggle.swift`, onboarding views | [components](./components/overview) |
| Confirmation dialogs are still inconsistent outside destructive deletes - `DeleteConfirmationAlert` and shared patterns exist, but non-destructive confirmations still use ad hoc `.alert()`/`.confirmationDialog()` copy and structure | Settings, sidebar panels, Skills Store, Auth views | [error-presentation](./patterns/error-presentation) |
| Onboarding views use inline `.font(.system(size:weight:))` instead of `AppFontStyle` tokens - 7 onboarding files with 25 occurrences of hardcoded system font calls; most concentrated token violation in the codebase | `WelcomeStepView.swift`, `ChooseProviderStepView.swift`, `CreateAccountStepView.swift`, `ProfileStepView.swift`, `VerifyEmailStepView.swift`, `AddApiKeyStepView.swift`, `LocationPermissionStepView.swift`, `NotificationsPermissionStepView.swift`, `FinalStepView.swift` | [typography](./foundations/typography) |
| Shared pill adoption remains incomplete - `StatusPill` and `MetadataPill` exist and toast/status surfaces use them, but tracked task/chat/tool rows still build custom `Capsule()` pill surfaces | `SiteHeaderBar.swift`, `ToastCenter.swift`, `TasksViewComponents.swift`, `ChatMessageRow.swift`, `ChatToolComponents.swift` | [pills-and-docks](./components/pills-and-docks) |

### Widget gaps

| Gap | File(s) | Source |
|---|---|---|
| `ExtensionEventStore.recordWebsiteSaved(website:)` and the `applySavedWebsiteEvent` branch in `consumeExtensionEvents()` are dead code - the extension never calls the full-metadata path; only the URL-queue path via `PendingShareStore` is used | `ExtensionEventStore.swift`, `AppEnvironment+Auth.swift` | [handoffs](./patterns/handoffs) |
| Widget action intents are only partially routed through deep links - widget add/open intents now use `sidebar://` URLs, but app-side execution still relies on bespoke deferred flags such as `pendingNewTaskDeepLink` and `pendingNewNoteDeepLink` | `AppEnvironment+Widgets.swift`, `TasksViewModel.swift`, `NotesViewModel.swift` | [handoffs](./patterns/handoffs) |
| Chat conversations can be exported but not fully shared - transcript export exists, but the share action still falls back to an unavailable toast instead of presenting a share sheet | `ChatView.swift`, `ChatMessageRow.swift` | [handoffs](./patterns/handoffs) |

### AI assistant UI gaps

| Gap | File(s) | Source |
|---|---|---|
| No confirmation gate for destructive skill actions - delete tools (note, folder, website, task, project, group, file) execute immediately without pausing for user confirmation; `SkillsGuardService`, `tool_confirmation_requested`/`tool_confirmation_resolved` SSE events, confirmation decision endpoint, and inline confirmation card UI all need to be built | `backend/api/services/agent/tools/skills_guard.py` (new), `stream_runner.py`, `tool_event_mapper.py`, `chat.py`, `ChatToolComponents.swift` | [ai-assistant-ui](./patterns/ai-assistant-ui) |
| No undo for reversible destructive skill actions - notes, folders, websites, tasks, projects, and groups are soft-delete-backed but have no restore service methods, no `undo_available` SSE event, no undo token endpoint, and no inline undo card UI | `notes_service.py`, `websites_service.py`, `tasks_service.py`, `projects_service.py`, `groups_service.py`, `ChatToolComponents.swift` | [ai-assistant-ui](./patterns/ai-assistant-ui) |

### Low priority

| Gap | File(s) | Source |
|---|---|---|
| Accessibility label coverage remains incomplete on list rows - chat message rows now have message labels, but notes and task content rows still do not have confirmed row-level `.accessibilityLabel` coverage | `ChatMessageRow.swift`, `NotesViewComponents.swift`, `TasksViewComponents.swift` | [accessibility](./foundations/accessibility) |
| `AppFontStyle` scale rationalisation: reduce 25 styles to 13 by removing all semibold weight variants (structural styles become bold, content styles become regular), removing redundant size-named styles, and renaming remaining styles semantically. Highest-impact rename: `.labelMd` -> `.label` has 32 call sites across the codebase. Full plan in [typography](./foundations/typography#scale-rationalisation). | `AppFontStyle.swift` + callers | [typography](./foundations/typography) |
| `SearchField` uses `.appFont(.subheadline)` - `.subheadline` is removed in the rationalisation; correct replacement is `.body` (search input text is body-weight content, not a subheading) | `SearchField.swift` | [typography](./foundations/typography) |
| `SettingsMoreTabView` uses `.appFont(.subheadline)` - removed in rationalisation; replace with `.body` | `SettingsMoreTabView.swift` | [typography](./foundations/typography) |
| `MacModalShell` inspector sheet `maxWidth: 1_120` is hardcoded - should be a `Size` token (`Size.inspectorMaxWidth`) | `MacModalShell.swift` | [components](./components/overview) |
| `SkillsStoreDetailView` "Unable to load Skills Store" placeholder has no retry action - user cannot recover without navigating away and back | `SkillsStoreDetailView.swift:117` | [error-presentation](./patterns/error-presentation) |
| `DesignTokens.Typography` is unused - parallel system to `AppFontStyle`, should be removed | `DesignTokens.swift` | [token-audit](./audits/token-audit) |
| `SwiftUINoteTextEditorSurface.swift` is dead code - no callers, not mounted at runtime; safe to delete | `Views/Notes/SwiftUINoteTextEditorSurface.swift` | [system-framework-usage-audit](./audits/system-framework-usage-audit) |
| `PlatformTokens.panelHeaderBackground` is a single-value alias for `DesignTokens.Colors.sidebar` - remove and update callers | `PlatformTokens.swift` | [token-audit](./audits/token-audit) |
| `SidebarSplitView.swift` contains remnant `DragGesture`-based resize handle code - remove | `SidebarSplitView.swift` | [macos-conventions](./platform-strategy/macos-conventions) |

---

## Web

### High priority

| Gap | File(s) | Source |
|---|---|---|
| Settings presented as modal `AlertDialog` - should be a dedicated `/settings` route with browser navigation support | `frontend/src/` | [web-conventions](./platform-strategy/web-conventions) |

### Medium priority

| Gap | File(s) | Source |
|---|---|---|
| `SidebarLoading` has CSS shimmer animation (`loading-shimmer`) - remove and replace with static placeholder rows matching native `SidebarListSkeleton` | `frontend/src/lib/components/left-sidebar/SidebarLoading.svelte` | [wait-ux](./patterns/wait-ux) |
| `SyncStatusIndicator` dead component remains - settings usage appears removed, but the unused component file still exists and should be deleted | `SyncStatusIndicator.swift` | [wait-ux](./patterns/wait-ux) |
| Native chat missing inline tool execution states - web shows "Using {name}" / "Used {name}" / "Failed to use {name}" per message; native has no equivalent | `ChatToolBanners.swift` / chat message components | [wait-ux](./patterns/wait-ux) |
| Web dark mode surface values lighter than native - `--background` dark is `oklch(0.16 0 0)`, should be `oklch(0.065 0 0)` (about `#0a0a0a`) | `frontend/src/app.css` | [colour](./foundations/colour) |

### Low priority

| Gap | File(s) | Source |
|---|---|---|
| Web keyboard shortcuts incomplete - full shortcut audit needed | `frontend/src/` | [menus-and-shortcuts](./patterns/menus-and-shortcuts) |
| Web tasks detail view is a modal form only - native has a dedicated detail panel; web should have an equivalent | `frontend/src/` | [web-conventions](./platform-strategy/web-conventions) |
| Skills Store is nested inside the Settings modal on web - should be a standalone section matching native | `frontend/src/` | [web-conventions](./platform-strategy/web-conventions) |

---

## Backend / system prompt

### High priority

| Gap | File(s) | Source |
|---|---|---|
| `<memory_guidance>` instructs the assistant to "Use Write File only for project files or documents in the workspace" - no Write File capability exists in the Files skill; the instruction should be removed | `backend/api/config/prompts.yaml` | [sideBar model](./patterns/sidebar-model) |

---

## Related docs

- [iOS Conventions](./platform-strategy/ios-conventions)
- [macOS Conventions](./platform-strategy/macos-conventions)
- [Web Conventions](./platform-strategy/web-conventions)
- [Colour](./foundations/colour)
- [Materials and Appearance](./foundations/materials-and-appearance)
- [Components](./components/overview)
- [Token Audit](./audits/token-audit)
