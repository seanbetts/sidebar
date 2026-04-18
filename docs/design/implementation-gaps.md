---
title: Implementation Gaps
description: Central tracker for all known divergences between the design system and the current codebase.
---

## Purpose

Single working list of every known divergence between the design system and the current codebase. This is the document to work from when planning implementation sprints.

**Design docs own the detail.** Each gap links back to the source doc where the rationale and target state are fully explained. This doc is the index, not the specification.

**Lifecycle**: When a gap is resolved, remove it from this list and update the source design doc to reflect the corrected state. Done items are not retained here — the updated design doc is the permanent record.

**Execution planning**: Grouped remediation batches, issue sizing, and review/test gates live in [Design System Gap Remediation Implementation Plan](../superpowers/plans/2026-03-30-design-system-gap-remediation.md).

---

## iOS / macOS (native)

### High priority

| Gap | File(s) | Source |
|---|---|---|
| Rate limiting on sign-in not persisted — `failedLoginAttempts` and `lockoutEndTime` are in-memory only; app restart resets the lockout, providing no meaningful brute-force protection | `SupabaseAuthAdapter.swift` | [authentication](./patterns/authentication) |
| Deep links not gated on auth completion — links arriving while auth is initialising or biometric lock is showing route to feature content that may be blank or loading indefinitely | `AppEnvironment+DeepLink.swift` | [authentication](./patterns/authentication) |
| No manual retry action for `.stale` state — app shows a toast but provides no button to immediately attempt session recovery; user must wait for background/foreground transition | `AppEnvironment+Auth.swift` | [authentication](./patterns/authentication) |
| Offline access window backed by UserDefaults — `lastAuthTimestamp` can be cleared independently of the Keychain session, making the 24-hour window trivially bypassable; should be stored in Keychain | `SupabaseAuthAdapter.swift` | [authentication](./patterns/authentication) |
| Auth error toast not cleared on state recovery — `authError` is only cleared when the sink fires; if the session recovers, a stale error toast may persist | `AppEnvironment+Setup.swift` | [authentication](./patterns/authentication) |
| Website saves not deferred during biometric lock — `consumeExtensionEvents` is gated on `authState == .active` but not on biometric lock state; saves are processed immediately even while the lock screen is showing; root cause is that `isBiometricUnlocked` is a view-layer `@State` in `ContentView+SignedIn` and is not accessible from `AppEnvironment` | `AppEnvironment+Auth.swift`, `AppEnvironment+PendingShares.swift`, `ContentView+SignedIn.swift` | [authentication](./patterns/authentication), [handoffs](./patterns/handoffs) |
| Biometric lock: `biometryNotAvailable` and `biometryNotEnrolled` do not show passcode fallback button — `showPasscodeFallback` is only set for `.biometryLockout` and `.userFallback`; both cases should also offer the passcode path since `deviceOwnerAuthentication` still succeeds | `BiometricLockView.swift` | [authentication](./patterns/authentication) |
| Biometric lock: passcode/enrollment error messages are text-only — `.passcodeNotSet` and `.biometryNotEnrolled` show inline text but no button to open device Settings; spec requires an actionable path | `BiometricLockView.swift` | [authentication](./patterns/authentication) |
| Password reset flow not implemented — no "Forgot password" entry point, no reset code UI, no reset completion flow; users who forget their password have no in-app recovery path | `LoginView.swift` | [authentication](./patterns/authentication) |
| Login fields missing AutoFill content types — email field should use username content type, password field should use password content type for `ASAuthorizationPasswordProvider` integration | `LoginView.swift` | [authentication](./patterns/authentication) |
| OTP field missing one-time-code content type — verification code input should use Apple-native one-time-code content type for AutoFill | `VerifyEmailStepView.swift` | [authentication](./patterns/authentication) |
| No biometric reauth for sensitive settings actions — changing password should require biometric reauth before proceeding; no `LocalSecurityGate` equivalent for in-session actions | `SettingsViewModel.swift` | [authentication](./patterns/authentication) |
| Sign-out does not clear extension auth state — share extension and Safari extension may retain usable auth context in the shared Keychain group after the main app signs out | `ShareExtension/`, `SafariExtension/`, sign-out flow | [authentication](./patterns/authentication) |
| Auth adapter exposes Supabase semantics — `SupabaseAuthAdapter` is called directly from product code; should be wrapped in product-shaped interfaces (`createAccount`, `issueSession`, etc.) | `SupabaseAuthAdapter.swift` | [authentication](./patterns/authentication) |
| Shared request policy not enforced across uploads, streaming, background upload, widgets, and extensions — `APIClient` is only authoritative for part of the app; custom `URLSession` flows bypass shared auth refresh, retryability, diagnostics, and connectivity reporting | `APIClient.swift`, `SettingsAPI.swift`, `IngestionAPI.swift`, `URLSessionChatStreamClient.swift`, `IngestionUploadManager.swift`, `ShareExtensionEnvironment.swift` | [request-lifecycle](./patterns/request-lifecycle) |
| No typed app-wide error envelope before presentation mapping — `APIClientError` plus status-code and substring parsing forces features and extensions to reconstruct meaning from raw failures rather than consume a stable classified error | `APIClient.swift`, `ErrorMapping.swift`, `ShareExtensionMessageMapper.swift`, `ExtensionURLMessageHandler.swift` | [error-handling](./patterns/error-handling) |
| Raw backend messages and `localizedDescription` still reach user-facing UI — unclassified backend text falls through `ErrorMapping`, and several surfaces render raw system strings directly | `ErrorMapping.swift`, `BiometricLockView.swift`, `SettingsViewModel.swift`, `SettingsSections+ProfileSupport.swift`, `ConversationsPanelView+Helpers.swift`, `QueuedChangesView.swift` | [error-handling](./patterns/error-handling), [error-presentation](./patterns/error-presentation) |
| No shared local-first offline engine across chats, notes, tasks, websites, and files — cache, optimistic writes, queueing, ID remapping, and availability rules are implemented per-surface with divergent behavior instead of one shared contract | `Stores/`, `ViewModels/`, `Services/Offline/` | [offline-and-sync](./patterns/offline-and-sync), [wait-ux](./patterns/wait-ux) |
| Selected detail panes can fall through to generic empty welcome states instead of explicit unavailable-offline states when content is missing locally | `WebsitesDetailView.swift`, `FilesViewComponents.swift`, related detail surfaces | [offline-and-sync](./patterns/offline-and-sync), [error-presentation](./patterns/error-presentation) |
| Mutation failures reuse load-failure state and can replace already-loaded content with placeholders — task and file mutation errors currently flow through shared `errorMessage` state intended for initial load failures | `TasksViewModel.swift`, `TasksPanel.swift`, `TasksDetailView.swift`, `IngestionViewModel+Public.swift`, `FilesPanel.swift`, `FilesViewComponents.swift` | [error-presentation](./patterns/error-presentation) |
| Chat stream failures double-surface through generic error channels — chat already has a dedicated pill/retry/popover pattern, but stream failures also set shared error state and show generic toasts | `ChatViewModel+Streaming.swift`, `ChatViewModel+StreamingSession.swift`, `ChatViewModel+StreamingFinalize.swift`, `ChatErrorComponents.swift`, `ChatView.swift` | [error-presentation](./patterns/error-presentation), [error-handling](./patterns/error-handling) |
| Share extension still owns its own reachability and offline-handoff policy — preflight probe failures can queue work before the real request is attempted, diverging from the shared execute-classify-recover lifecycle | `ShareNetworkMonitor.swift`, `ShareViewController+MediaHandling.swift`, `ShareExtensionEnvironment.swift` | [request-lifecycle](./patterns/request-lifecycle) |
| Phase 1.5 permission cards not implemented — `OnboardingPermissionCard` component does not exist; location and notification permission prompts have no onboarding-phase trigger; recovery CTA linking to system Settings is also absent | `Views/Onboarding/`, `ChatView.swift` | [onboarding](./patterns/onboarding) |
| Phase 2 AI-guided feature tour not implemented — `FeatureIntroCard`, `FeatureTourManager`, and `StaticFeatureCarousel` do not exist; the backend has no onboarding-aware prompt injection or onboarding SSE events | `Views/Onboarding/`, `backend/api/services/agent/` | [onboarding](./patterns/onboarding) |
| Add-key banner not implemented — users who dismiss onboarding without adding a provider key land in the main app with no persistent recovery surface; `AddKeyBannerView` does not exist | `ContentView.swift` | [onboarding](./patterns/onboarding) |
| ContentView routing incomplete for post-onboarding states — `.dismissed` (no provider) banner+carousel path and the key-added-later path are not yet wired up | `ContentView.swift` | [onboarding](./patterns/onboarding) |
| Backend chat orchestration not onboarding-aware — first-turn prompt composition does not inject onboarding context for incomplete users; no onboarding SSE events are emitted | `backend/api/services/agent/prompt/composer.py`, `stream_runner.py` | [onboarding](./patterns/onboarding) |
| `onboarding-coach` skill not implemented | `backend/skills/` | [onboarding](./patterns/onboarding) |
| Scratchpad button accessible only inside open ChatView conversation — should appear wherever the profile/settings avatar appears, to its left, presented as `.sheet` | `ChatView.swift` | [ios-conventions](./platform-strategy/ios-conventions) |
| `Design/Haptics.swift` not yet created — all haptic call sites are blocked on this; `LoginView` and `BiometricLockView` still use inline `UINotificationFeedbackGenerator` and must migrate once the helper exists | `Design/Haptics.swift` (to create), `LoginView.swift`, `BiometricLockView.swift` | [feedback-and-haptics](./patterns/feedback-and-haptics) |
| Haptic: task completion checkbox missing `.success` feedback | `TasksViewComponents.swift:87` | [ios-conventions](./platform-strategy/ios-conventions) |
| Haptic: destructive delete (swipe) missing `.error` feedback | `SidebarSwipeActions.swift` | [ios-conventions](./platform-strategy/ios-conventions) |
| Haptic: floating action button tap missing `.impact` (light) feedback | `PhoneFloatingActionDock.swift:25` | [ios-conventions](./platform-strategy/ios-conventions) |
| Haptic: Settings toggle state changes missing `.selection` feedback | `SettingsSections+Additional.swift:41` | [ios-conventions](./platform-strategy/ios-conventions) |
| Haptic: archive and pin/unpin context menu actions missing `.selection` feedback | Context menu components | [ios-conventions](./platform-strategy/ios-conventions) |
| Haptic: drag reorder completion missing `.success` feedback | Panel reorder files | [ios-conventions](./platform-strategy/ios-conventions) |
| macOS View menu missing — `Toggle Sidebar` (Cmd+Shift+S) and `Open Scratchpad` (Cmd+Shift+O) not in menu bar | `AppCommands.swift` | [menus-and-shortcuts](./patterns/menus-and-shortcuts) |
| `SidebarMenuItem` missing factory methods for `Copy Title` and `Copy URL` — both are created inline in `WebsitesPanel+ContextMenu.swift`, `WebsitesView.swift`, and `WebsitesDetailView+MenuActions.swift`, violating the rule that all action icons use factory methods | `Design/Components/SidebarMenuItem.swift`, `Views/Websites/` | [menus-and-shortcuts](./patterns/menus-and-shortcuts) |
| Files header menu on macOS uses a raw `Menu` with inline `Label` + SF Symbol strings — should use `SidebarMenuItem` factory methods; the iOS branch correctly uses `HeaderActionMenuButton` with `SidebarMenuItem` items | `Views/Files/FilesHeaderActions.swift` | [menus-and-shortcuts](./patterns/menus-and-shortcuts) |
| `success` and `warning` color tokens alias to neutral text colors — should be `#16a34a`/`#4ade80` and `#d97706`/`#fbbf24` | `DesignTokens.swift` | [colour](./foundations/colour) |

### Medium priority

| Gap | File(s) | Source |
|---|---|---|
| Website save job polling not background-capable — polling runs as a Swift `Task` that suspends when the app is backgrounded; extension saves queued via `PendingShareStore` are only processed on foreground entry; saves should complete without requiring the app to stay active (background `URLSession` required) | `WebsitesViewModel+JobPolling.swift`, `AppEnvironment+PendingShares.swift`, `Info.plist` | [ios-conventions](./platform-strategy/ios-conventions), [handoffs](./patterns/handoffs) |
| `WriteQueue` does not flush in the background — offline writes are only processed when the app is in the foreground and network is available; if the app is backgrounded before coming online, the queue does not flush until next foreground session (`BGProcessingTask` on network availability required) | `WriteQueue.swift`, `Info.plist` | [ios-conventions](./platform-strategy/ios-conventions) |
| `ConnectivityMonitor` only observes `APIClient` request notifications and probes with `URLSession.shared` — upload and stream failures can bypass centralized health state, and probe transport can disagree with the app's pinned/default session policy | `ConnectivityMonitor.swift`, `APIClient.swift` | [request-lifecycle](./patterns/request-lifecycle) |
| Offline-capable create flows are split between `WriteQueue` and `PendingShareStore` — websites and files use a parallel queueing path instead of the same mutation system as notes and tasks | `AppEnvironment+PendingShares.swift`, `WebsitesViewModel.swift`, `IngestionViewModel.swift`, `WriteQueue.swift` | [offline-and-sync](./patterns/offline-and-sync) |
| Archived notes and archived websites are not consistently browsable offline from the locally cached subset — some paths block archive loading despite archived data already being persisted on-device | `NotesStore.swift`, `WebsitesStore.swift` | [offline-and-sync](./patterns/offline-and-sync) |
| Files cache metadata more reliably than viewable content — a file can appear in the local list while its derivative content is still unavailable offline on that device | `IngestionStore.swift`, `IngestionViewModel+Private.swift` | [offline-and-sync](./patterns/offline-and-sync) |
| Widget refresh failures are swallowed rather than classified — several providers fall back silently to cached or stale state with empty `catch` blocks and no standardized diagnostics outcome | `TodayTasksProvider.swift`, `PinnedNotesProvider.swift`, `PinnedFilesProvider.swift`, `SavedSitesProvider.swift` | [request-lifecycle](./patterns/request-lifecycle), [error-handling](./patterns/error-handling) |
| Sentry context capture and diagnostics policy are inconsistent — app-side `AppSentry.capture` drops supplied context, while some extension and widget paths still record overly sensitive detail such as raw URLs | `SentryBootstrap.swift`, `ExtensionDiagnosticsReporter.swift`, `SafariWebExtensionHandler.swift`, `WidgetDataManager.swift` | [error-handling](./patterns/error-handling) |
| Haptic: settings save missing `Haptics.selection()` on explicit save completion — `SettingsSaveStatusPill` shows visual saved state but no haptic fires | `SettingsSaveStatusPill.swift` | [wait-ux](./patterns/wait-ux) |
| Pull-to-refresh not confirmed implemented on iOS list panels — all sidebar list panels should use the `refreshable` modifier | Sidebar panel views | [wait-ux](./patterns/wait-ux) |
| Website save detail view shows static "Reading..." for the full duration of job polling (up to 5 minutes) with no stage progression — server job status stages should be surfaced | `WebsitesDetailView+PendingSave.swift`, `WebsitesViewModel+JobPolling.swift` | [wait-ux](./patterns/wait-ux) |
| Cancel website save is unavailable for queued-share saves (`canCancelWebsiteSave()` only returns true for `.directSave` sources) — cancellation should be available regardless of how the save was initiated | `WebsitesViewModel.swift` | [wait-ux](./patterns/wait-ux) |
| `IngestionCenterView` is an active per-file tracking panel — should be replaced with a lightweight ingestion history summary; active progress tracking moves to Live Activities | `IngestionCenterView.swift` | [wait-ux](./patterns/wait-ux) |
| Live Activities not implemented for file ingestion — `IngestionProgressActivityAttributes.swift` and `IngestionProgressActivityCoordinator.swift` do not exist | `Views/Files/` | [wait-ux](./patterns/wait-ux) |
| Live Activities not implemented for video transcription | `Views/Files/` | [wait-ux](./patterns/wait-ux) |
| Note content edits bypass `WriteQueue` when online — `NotesEditorViewModel` calls the API directly; should apply locally first and sync in background | `NotesEditorViewModel.swift` | [wait-ux](./patterns/wait-ux) |
| Website mutations (pin, rename, archive, delete) bypass `WriteQueue` when online — only queued when offline; should be consistently optimistic | `WebsitesViewModel.swift`, `WebsitesWriteQueueExecutor.swift` | [wait-ux](./patterns/wait-ux) |
| `WriteQueue` pauses on conflict and waits for manual resolution — should auto-resolve with `keepLocal` rebase and continue without pausing | `WriteQueue.swift` | [wait-ux](./patterns/wait-ux) |
| Note entity has no rebase logic in `WriteQueueConflictRebase.swift` — `rebaseConflictPayload()` returns `nil` for notes, which will cause infinite conflict loops under auto-resolution; rebase must be implemented before auto-resolution is enabled for notes | `WriteQueueConflictRebase.swift` | [wait-ux](./patterns/wait-ux) |
| `QueuedChangeResolutionSheet` conflict resolution modal should be removed — local always wins, no user input needed | `QueuedChangeResolutionSheet.swift`, `ContentView+SignedIn.swift` | [wait-ux](./patterns/wait-ux) |
| `QueuedChangesView` in Settings shows conflict resolution buttons ("Keep Queued Change" / "Use Server Version") — remove conflict UI; keep failed write visibility and retry only | `QueuedChangesView.swift` | [wait-ux](./patterns/wait-ux) |
| Web `TaskConflictDialog` conflict resolution modal should be removed — local always wins | `frontend/src/lib/components/tasks/TaskConflictDialog.svelte` | [wait-ux](./patterns/wait-ux) |
| Web note and website mutations are fire-and-forget — no in-session retry or error surfacing when API calls fail; should retry on transient failures before surfacing an error | `frontend/src/lib/` | [wait-ux](./patterns/wait-ux) |
| No shared hover modifier — 10 hover gaps below each require independent `@State` and `.onHover` wiring; a shared `.sidebarHover()` view modifier should manage hover state internally and be applied consistently across all interactive surfaces | `Design/Modifiers/` (to create) | [ios-conventions](./platform-strategy/ios-conventions) |
| SidebarRail section button hover gated by `#if os(macOS)` — remove guard so iPad pointer gets hover state too | `SidebarRail.swift:117` | [ios-conventions](./platform-strategy/ios-conventions) |
| SidebarRail app logo button missing `.onHover` | `SidebarRail.swift:32` | [ios-conventions](./platform-strategy/ios-conventions) |
| SidebarRail profile avatar button missing `.onHover` | `SidebarRail.swift:54` | [ios-conventions](./platform-strategy/ios-conventions) |
| Right sidebar resize handle missing `.onHover` cursor change | `WorkspaceLayout.swift:143` | [ios-conventions](./platform-strategy/ios-conventions) |
| Sidebar resize handle missing `.onHover` cursor change | `SidebarSplitView.swift:46` | [ios-conventions](./platform-strategy/ios-conventions) |
| `SelectableRow` missing `.onHover` | `SelectableRow.swift:40` | [ios-conventions](./platform-strategy/ios-conventions) |
| `HeaderActionIcon` missing `.onHover` | `HeaderActionIcon.swift:14` | [ios-conventions](./platform-strategy/ios-conventions) |
| `SiteHeaderBar` buttons missing `.onHover` | `SiteHeaderBar.swift:159,183,201` | [ios-conventions](./platform-strategy/ios-conventions) |
| Chat header buttons missing `.onHover` | `ChatHeaderView.swift:31,42,94` | [ios-conventions](./platform-strategy/ios-conventions) |
| Files header buttons missing `.onHover` | `FilesHeaderActions.swift:79,153,196` | [ios-conventions](./platform-strategy/ios-conventions) |
| iOS color tokens use UIKit semantic colors — migrate to custom hex values matching unified palette | `Color+Platform.swift` | [colour](./foundations/colour) |
| macOS `MacOSPalette` branching in `Color+Platform.swift` — remove and replace with shared implementation | `Color+Platform.swift` | [colour](./foundations/colour) |
| Icon size drift: 20px should be `Icon.md` (18) | `TasksViewComponents.swift` | [token-audit](./audits/token-audit) |
| Icon size drift: 22px should be `Icon.md` (18) | `WebsitesDetailView+MenuActions.swift` | [token-audit](./audits/token-audit) |
| Icon size drift: 28px should be `Icon.xl` (32) | `TasksDetailView.swift` | [token-audit](./audits/token-audit) |
| Icon size drift: 30px should be `Icon.xl` (32) | `StoreSkillCredentialsView.swift` | [token-audit](./audits/token-audit) |
| Icon size literals should reference tokens | `SettingsSections+Additional.swift`, `SidebarRail.swift`, `SettingsSections+Utilities.swift` | [token-audit](./audits/token-audit) |
| SidebarRail font: `.font(.system(size: 18, weight: .semibold))` should be `.appFont(.label)` or equivalent | `SidebarRail.swift` | [macos-conventions](./platform-strategy/macos-conventions) |
| `Motion.slow` missing from `Motion` enum despite `Animation.slow = 0.4` existing | `Motion.swift` | [token-audit](./audits/token-audit) |
| Missing size tokens: `railWidth = 56`, `dividerWidth = 8`, `rightSidebarDefaultWidth = 360` | `DesignTokens.swift` | [token-audit](./audits/token-audit) |
| Spacing and radius literals in several views should reference existing tokens | `PanelHeader.swift`, `SidebarRail.swift`, `WorkspaceLayout.swift`, `PhoneFloatingActionMetrics` | [token-audit](./audits/token-audit) |
| `SettingsSaveStatusPill` uses `.ultraThinMaterial` — should migrate to Liquid Glass | `SettingsSaveStatusPill.swift` | [materials-and-appearance](./foundations/materials-and-appearance) |
| `NoteFormattingBar` uses `.thinMaterial` — should migrate to Liquid Glass | `NoteFormattingBar.swift` | [materials-and-appearance](./foundations/materials-and-appearance) |
| Liquid Glass adoption plan: `MacPopoverShell`, `MacModalShell`, `SettingsMacStyles`, `SidebarRail`, `SiteHeaderBar`, `HeaderActionIcon`, `PanelHeader`, `SearchField` dock chrome, `LoginView` not yet using `glassEffect` | Multiple files | [materials-and-appearance](./foundations/materials-and-appearance) |
| No unified form field component — iOS (`ProfileIOSFieldRow`) and macOS (`SettingsMacFieldRow`) have separate field row implementations with different APIs; `SecureFieldWithToggle` is standalone; Settings, Auth, and Onboarding forms should share a single platform-adaptive form field system | `ProfileIOSFieldRow.swift`, `SettingsMacStyles.swift`, `SecureFieldWithToggle.swift`, onboarding views | [components](./components/overview) |
| Confirmation dialogs inconsistent — `DeleteConfirmationAlert` exists for destructive actions but 13 files use `.alert()` or `.confirmationDialog()` with ad hoc patterns for non-destructive confirmations; button labels, messaging tone, and structure vary | Settings, sidebar panels, Skills Store, Auth views | [error-presentation](./patterns/error-presentation) |
| Onboarding views use inline `.font(.system(size:weight:))` instead of `AppFontStyle` tokens — 7 onboarding files with 25 occurrences of hardcoded system font calls; most concentrated token violation in the codebase | `WelcomeStepView.swift`, `ChooseProviderStepView.swift`, `CreateAccountStepView.swift`, `ProfileStepView.swift`, `VerifyEmailStepView.swift`, `AddApiKeyStepView.swift`, `LocationPermissionStepView.swift`, `NotificationsPermissionStepView.swift`, `FinalStepView.swift` | [typography](./foundations/typography) |
| No shared `StatusPill` or `MetadataPill` components — 16 capsule-shaped surfaces across the app each build their own `Capsule()` + border + padding; `PillModifier` exists but is only used in 2 places; status pills (`SettingsSaveStatusPill`, sync pill, toast banner, stale retry) and metadata pills (`TaskPill`, chat role pill, tool pill) should each converge on a shared component | `SettingsSaveStatusPill.swift`, `SiteHeaderBar.swift`, `ToastCenter.swift`, `TasksViewComponents.swift`, `ChatMessageRow.swift`, `ChatToolComponents.swift` | [pills-and-docks](./components/pills-and-docks) |

### Push notification gaps

| Gap | File(s) | Source |
|---|---|---|
| No user-facing notification categories implemented — only silent badge updates exist; the full category model (task reminders, morning digest, assistant replies, assistant proactive nudges) is not implemented; all require a backend notification policy and delivery layer before any category can ship | `push_notification_service.py`, `AppEnvironment+Push.swift` | [handoffs](./patterns/handoffs) |
| No user notification preferences in settings model — `task_reminders_enabled`, `morning_digest_enabled`, `assistant_reply_notifications_enabled`, `assistant_proactive_notifications_enabled`, and `morning_digest_time` fields do not exist in user settings; defaults cannot be applied or persisted | `backend/api/models/user_settings.py`, `SettingsModels.swift`, `SettingsViewModel.swift` | [handoffs](./patterns/handoffs) |
| Device token registration carries no capability or presence metadata — tokens are registered without platform capability markers (e.g. Live Activity support) or foreground/away-state hints; the backend cannot apply the away-state rule or make capability-aware delivery decisions | `backend/api/models/device_token.py`, `AppEnvironment+Push.swift` | [handoffs](./patterns/handoffs) |
| No iOS Live Activities for ingestion progress — file upload, video transcription, and other long-running ingestion operations have no persistent progress surface; `ActivityKit` attributes, coordinator, and ingestion view model integration do not exist | `IngestionViewModel.swift`, `IngestionViewModel+ListPolling.swift` | [handoffs](./patterns/handoffs) |

### Widget gaps

| Gap | File(s) | Source |
|---|---|---|
| `ExtensionEventStore.recordWebsiteSaved(website:)` and the `applySavedWebsiteEvent` branch in `consumeExtensionEvents()` are dead code — the extension never calls the full-metadata path; only the URL-queue path via `PendingShareStore` is used | `ExtensionEventStore.swift`, `AppEnvironment+Auth.swift` | [handoffs](./patterns/handoffs) |
| Tasks are not indexed for Spotlight — only notes, files, and websites are currently indexed; tasks should be indexed so users can navigate directly to a task from system search | `SpotlightIndexer.swift` (or equivalent) | [handoffs](./patterns/handoffs) |
| Widget action intents use bespoke deferred flags (`pendingNewTaskDeepLink`, `pendingNewNoteDeepLink`) rather than routing through the deep link system — target state is to convert all widget action intents to `sidebar://` deep links and let the deep link handler own deferred execution | `AppEnvironment+Widgets.swift`, `TasksViewModel.swift`, `NotesViewModel.swift` | [handoffs](./patterns/handoffs) |
| Files have no share sheet action — files can only be exported to the Files app via `fileExporter`; sharing a binary file directly via `UIActivityViewController` (to Mail, Messages, AirDrop, etc.) is not supported | `FilesHeaderActions.swift`, `FilesPanel+ContextMenu.swift` | [handoffs](./patterns/handoffs) |
| Chat conversations cannot be exported or shared — individual messages can be copied but there is no action to share or export a full conversation as text | `ChatView.swift`, `ChatMessageRow.swift` | [handoffs](./patterns/handoffs) |
| Non-task lock screen widgets are still static configurations — notes, websites, and files have no intent-based customisation for dynamic content selection | `sideBarWidgets/` | [widgets](./platform-strategy/widgets) |
| Non-task home screen widgets have no content filtering — notes cannot be filtered by folder, websites by collection, or files by category from widget configuration | `sideBarWidgets/` | [widgets](./platform-strategy/widgets) |

### AI assistant UI gaps

| Gap | File(s) | Source |
|---|---|---|
| Tool call popover shows raw parameters as the primary detail — skill results should lead with a human-readable summary (e.g. "Deleted note: My Shopping List") rather than raw key-value parameters; parameters and result payload should move to a collapsible technical detail section | `ChatToolComponents.swift`, `ToolCallDetailView` | [ai-assistant-ui](./patterns/ai-assistant-ui) |
| Tool call popover always shows a skill list even for single-skill results — single-skill messages should skip the list and go straight to detail | `ChatToolComponents.swift`, `ToolCallPopoverContent` | [ai-assistant-ui](./patterns/ai-assistant-ui) |
| Prompt preview is presented as the primary content in skill detail — it should be a collapsible secondary section so the human-readable summary leads | `ChatToolComponents.swift`, `ToolCallDetailView`, `PromptPreviewView` | [ai-assistant-ui](./patterns/ai-assistant-ui) |
| No completion indicator on assistant messages — when streaming ends, the loading indicator disappears with no positive confirmation; target is a brief `SuccessCheckBadge` (14px) in the header that fades after ~1.5s | `ChatMessageRow.swift`, `ChatMessagePresentation` | [ai-assistant-ui](./patterns/ai-assistant-ui) |
| No shared inline action card component — navigational handoff actions use loose buttons (`WorkspaceSurfaceInlineActionsBar`) while confirmation and undo are specified as cards; all three variants should share a single container component with visual differentiation | `ChatToolComponents.swift`, `WorkspaceSurfaceInlineActionsBar` | [ai-assistant-ui](./patterns/ai-assistant-ui) |
| No confirmation gate for destructive skill actions — delete tools (note, folder, website, task, project, group, file) execute immediately without pausing for user confirmation; `SkillsGuardService`, `tool_confirmation_requested`/`tool_confirmation_resolved` SSE events, confirmation decision endpoint, and inline confirmation card UI all need to be built | `backend/api/services/agent/tools/skills_guard.py` (new), `stream_runner.py`, `tool_event_mapper.py`, `chat.py`, `ChatToolComponents.swift` | [ai-assistant-ui](./patterns/ai-assistant-ui) |
| No undo for reversible destructive skill actions — notes, folders, websites, tasks, projects, and groups are soft-delete-backed but have no restore service methods, no `undo_available` SSE event, no undo token endpoint, and no inline undo card UI | `notes_service.py`, `websites_service.py`, `tasks_service.py`, `projects_service.py`, `groups_service.py`, `ChatToolComponents.swift` | [ai-assistant-ui](./patterns/ai-assistant-ui) |
| Thinking dismissal body animation does not respect reduce motion — the character-by-character erasure loop in `startThinkingDismissalAnimationIfNeeded` runs unconditionally; target is an instant transition when `accessibilityReduceMotion` is active | `ChatMessageRow.swift` | [ai-assistant-ui](./patterns/ai-assistant-ui) |
| Chart workspace surface is a placeholder — target is native SwiftUI Charts rendering; currently shows a static rounded rectangle with a chart icon and summary text | `AgentWorkspaceSurfaceView.swift` | [ai-assistant-ui](./patterns/ai-assistant-ui) |
| Map workspace surface is a placeholder — target is native MapKit rendering; currently shows a static rounded rectangle with a map icon, location label, and summary text | `AgentWorkspaceSurfaceView.swift` | [ai-assistant-ui](./patterns/ai-assistant-ui) |
| Form and action panel workspace surfaces are scaffolded stubs — form fields are disabled and non-interactive; action panel buttons have no wiring; both surface types need real implementation before they can be used by skills | `AgentWorkspaceSurfaceView.swift` | [ai-assistant-ui](./patterns/ai-assistant-ui) |

### Low priority

| Gap | File(s) | Source |
|---|---|---|
| Accessibility label coverage incomplete on list rows — chat message rows, notes list rows, and task rows have no confirmed `.accessibilityLabel`; navigation and action elements have labels but content rows do not | `ChatMessageRow.swift`, `NotesViewComponents.swift`, `TasksViewComponents.swift` | [accessibility](./foundations/accessibility) |
| `AppFontStyle` scale rationalisation: reduce 25 styles to 13 by removing all semibold weight variants (structural styles become bold, content styles become regular), removing redundant size-named styles, and renaming remaining styles semantically. Highest-impact rename: `.labelMd` → `.label` has 32 call sites across the codebase. Full plan in [typography](./foundations/typography#scale-rationalisation). | `AppFontStyle.swift` + callers | [typography](./foundations/typography) |
| `SearchField` uses `.appFont(.subheadline)` — `.subheadline` is removed in the rationalisation; correct replacement is `.body` (search input text is body-weight content, not a subheading) | `SearchField.swift` | [typography](./foundations/typography) |
| `ToastBanner` uses `.appFont(.subheadlineSemibold)` — removed in rationalisation; replace with `.subheading` | `ToastCenter.swift` | [typography](./foundations/typography) |
| `SettingsMoreTabView` uses `.appFont(.subheadline)` — removed in rationalisation; replace with `.body` | `SettingsMoreTabView.swift` | [typography](./foundations/typography) |
| `SettingsTabsView` applies `.appFont(.subheadline)` as a global modifier on the whole tab view — removed in rationalisation; replace with `.body` | `SettingsTabsView.swift` | [typography](./foundations/typography) |
| `MacModalShell` inspector sheet `maxWidth: 1_120` is hardcoded — should be a `Size` token (`Size.inspectorMaxWidth`) | `MacModalShell.swift` | [components](./components/overview) |
| `SkillsStoreDetailView` "Unable to load Skills Store" placeholder has no retry action — user cannot recover without navigating away and back | `SkillsStoreDetailView.swift:117` | [error-presentation](./patterns/error-presentation) |
| `ChatViewModel.toastCenter` is optional via `ui.toastCenter` — if nil at runtime, stream error toasts silently drop with no user feedback | `ChatViewModel.swift:132`, `ChatViewModel+StreamingErrors.swift:52` | [error-presentation](./patterns/error-presentation) |
| `DesignTokens.Typography` is unused — parallel system to `AppFontStyle`, should be removed | `DesignTokens.swift` | [token-audit](./audits/token-audit) |
| `SwiftUINoteTextEditorSurface.swift` is dead code — no callers, not mounted at runtime; safe to delete | `Views/Notes/SwiftUINoteTextEditorSurface.swift` | [system-framework-usage-audit](./audits/system-framework-usage-audit) |
| `PlatformTokens.panelHeaderBackground` is a single-value alias for `DesignTokens.Colors.sidebar` — remove and update callers | `PlatformTokens.swift` | [token-audit](./audits/token-audit) |
| `SidebarSplitView.swift` contains remnant `DragGesture`-based resize handle code — remove | `SidebarSplitView.swift` | [macos-conventions](./platform-strategy/macos-conventions) |

---

## Web

### High priority

| Gap | File(s) | Source |
|---|---|---|
| Settings presented as modal `AlertDialog` — should be a dedicated `/settings` route with browser navigation support | `frontend/src/` | [web-conventions](./platform-strategy/web-conventions) |

### Medium priority

| Gap | File(s) | Source |
|---|---|---|
| `SidebarLoading` has CSS shimmer animation (`loading-shimmer`) — remove and replace with static placeholder rows matching native `SidebarListSkeleton` | `frontend/src/lib/components/left-sidebar/SidebarLoading.svelte` | [wait-ux](./patterns/wait-ux) |
| `ConversationsPanel` skeleton uses 6 rows — standardise to 8 to match all other panels | `ConversationsPanel.swift` | [wait-ux](./patterns/wait-ux) |
| `SyncStatusIndicator` component and its usage in settings should be removed — background writes are silent | `SyncStatusIndicator.swift`, `SettingsSections+System.swift` | [wait-ux](./patterns/wait-ux) |
| Note save status indicator shows visible text labels ("Saving note...", "Saved just now", etc.) — remove text, keep icons only; ensure accessibility labels are set on each state | `NotesDetailView.swift` | [wait-ux](./patterns/wait-ux) |
| Chat pre-first-token state shows "Working..." animated dot — should be replaced with an inline thinking indicator in the message row, matching native | `frontend/src/lib/components/chat/Message.svelte` | [wait-ux](./patterns/wait-ux) |
| Native chat missing inline tool execution states — web shows "Using {name}" / "Used {name}" / "Failed to use {name}" per message; native has no equivalent | `ChatToolBanners.swift` / chat message components | [wait-ux](./patterns/wait-ux) |
| `prefers-reduced-motion` not confirmed implemented — should be respected in all animations | `frontend/src/` | [web-conventions](./platform-strategy/web-conventions) |
| Web dark mode surface values lighter than native — `--background` dark is `oklch(0.145 0 0)` (≈ `#1a1a1a`), should be `oklch(0.065 0 0)` (≈ `#0a0a0a`) | `frontend/src/app.css` | [colour](./foundations/colour) |

### Low priority

| Gap | File(s) | Source |
|---|---|---|
| Web keyboard shortcuts incomplete — full shortcut audit needed | `frontend/src/` | [menus-and-shortcuts](./patterns/menus-and-shortcuts) |
| Web tasks detail view is a modal form only — native has a dedicated detail panel; web should have an equivalent | `frontend/src/` | [web-conventions](./platform-strategy/web-conventions) |
| Skills Store is nested inside the Settings modal on web — should be a standalone section matching native | `frontend/src/` | [web-conventions](./platform-strategy/web-conventions) |

---

## Backend / system prompt

### High priority

| Gap | File(s) | Source |
|---|---|---|
| `<memory_guidance>` instructs the assistant to "Use Write File only for project files or documents in the workspace" — no Write File capability exists in the Files skill; the instruction should be removed | `backend/api/config/prompts.yaml` | [sideBar model](./patterns/sidebar-model) |

---

## Related docs

- [iOS Conventions](./platform-strategy/ios-conventions)
- [macOS Conventions](./platform-strategy/macos-conventions)
- [Web Conventions](./platform-strategy/web-conventions)
- [Colour](./foundations/colour)
- [Materials and Appearance](./foundations/materials-and-appearance)
- [Components](./components/overview)
- [Token Audit](./audits/token-audit)
