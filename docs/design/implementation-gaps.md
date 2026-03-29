---
title: Implementation Gaps
description: Central tracker for all known divergences between the design system and the current codebase.
---

| Field | Value |
|---|---|
| Status | live |
| Owner | both |
| Updated | 2026-03-29 |
| Dependencies | all approved design docs |

## Purpose

Single working list of every known divergence between the design system and the current codebase. This is the document to work from when planning implementation sprints.

**Design docs own the detail.** Each gap links back to the source doc where the rationale and target state are fully explained. This doc is the index, not the specification.

**Lifecycle**: When a gap is resolved, remove it from this list and update the source design doc to reflect the corrected state. Done items are not retained here — the updated design doc is the permanent record.

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
| Website saves not deferred during biometric lock — `consumeExtensionEvents` is gated on `authState == .active` but not on biometric lock state; saves from the share extension or Safari extension are processed immediately even while the lock screen is showing | `AppEnvironment+Auth.swift`, `AppEnvironment+PendingShares.swift` | [authentication](./patterns/authentication) |
| Biometric lock: `biometryNotAvailable` and `biometryNotEnrolled` do not show passcode fallback button — `showPasscodeFallback` is only set for `.biometryLockout` and `.userFallback`; both cases should also offer the passcode path since `deviceOwnerAuthentication` still succeeds | `BiometricLockView.swift` | [authentication](./patterns/authentication) |
| Biometric lock: passcode/enrollment error messages are text-only — `.passcodeNotSet` and `.biometryNotEnrolled` show inline text but no button to open device Settings; spec requires an actionable path | `BiometricLockView.swift` | [authentication](./patterns/authentication) |
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
| macOS View menu missing — `Toggle Sidebar` (Cmd+Shift+S) and `Open Scratchpad` (Cmd+Shift+O) not in menu bar | `AppCommands.swift` | [macos-conventions](./platform-strategy/macos-conventions) |
| `success` and `warning` color tokens alias to neutral text colors — should be `#16a34a`/`#4ade80` and `#d97706`/`#fbbf24` | `DesignTokens.swift` | [colour](./foundations/colour) |

### Medium priority

| Gap | File(s) | Source |
|---|---|---|
| Website save job polling not background-capable — polling runs as a Swift `Task` that suspends when the app is backgrounded; share queue URLs queued via the extension are only processed on foreground entry; saves should complete without requiring the app to stay active (`BGProcessingTask` or background `URLSession` required) | `WebsitesViewModel+JobPolling.swift`, `WebsitesViewModel+ExtensionHandoff.swift`, `Info.plist` | [ios-conventions](./platform-strategy/ios-conventions) |
| `WriteQueue` does not flush in the background — offline writes are only processed when the app is in the foreground and network is available; if the app is backgrounded before coming online, the queue does not flush until next foreground session (`BGProcessingTask` on network availability required) | `WriteQueue.swift`, `Info.plist` | [ios-conventions](./platform-strategy/ios-conventions) |
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

### Widget gaps

| Gap | File(s) | Source |
|---|---|---|
| `QuickSaveIntent` is dead code — not surfaced in any widget view, only registered as a Siri shortcut phrase; remove intent, Shortcuts registration, and `WidgetDataManager.recordQuickSaveIntent()` | `WebsiteIntents.swift`, `TaskIntents.swift` (shortcuts provider), `WidgetDataManager.swift` | [widgets](./platform-strategy/widgets) |
| No widget gallery preview images configured — widget picker shows generic previews | `sideBarWidgets/` | [widgets](./platform-strategy/widgets) |
| Empty states are inconsistent across widget types — tasks has a purpose-built "All done!" state; behaviour for empty pinned notes, files, and websites needs auditing and alignment | `sideBarWidgets/` | [widgets](./platform-strategy/widgets) |
| Lock screen task widgets have no interactive completion — the home screen task widget supports `CompleteTaskIntent` but the lock screen rectangular widget is tap-only; iOS 17+ supports interactive lock screen elements | `LockScreenWidgets.swift` | [widgets](./platform-strategy/widgets) |
| No StandBy mode optimisation for tasks widget — `TodayTasksWidget` displays in StandBy on iOS 17+ via `systemMedium` but without StandBy-specific layout (larger type, higher contrast, fewer items suited to ~1m viewing distance) | `TodayTasksWidget.swift` | [widgets](./platform-strategy/widgets) |
| Lock screen widgets are all static configurations — no intent-based customisation for dynamic content selection (e.g. choose which note or project to show) | `sideBarWidgets/` | [widgets](./platform-strategy/widgets) |
| Home screen widgets have no content filtering — tasks cannot be filtered by project, notes by folder, etc. from widget configuration | `sideBarWidgets/` | [widgets](./platform-strategy/widgets) |
| Favicons fetched fresh on every timeline generation — no disk cache; repeated fetches on 15-minute cadence for unchanged data | `SavedSitesProvider.swift` | [widgets](./platform-strategy/widgets) |
| Notes, files, and websites use a fixed 15-minute refresh interval — unlike tasks, no smart timeline boundaries are calculated from data changes | `PinnedNotesProvider.swift`, `PinnedFilesProvider.swift`, `SavedSitesProvider.swift` | [widgets](./platform-strategy/widgets) |

### Low priority

| Gap | File(s) | Source |
|---|---|---|
| `AppFontStyle` scale rationalisation: reduce 25 styles to 13 by removing all semibold weight variants (structural styles become bold, content styles become regular), removing redundant size-named styles, and renaming remaining styles semantically. Highest-impact rename: `.labelMd` → `.label` has 32 call sites across the codebase. Full plan in [typography](./foundations/typography#scale-rationalisation). | `AppFontStyle.swift` + callers | [typography](./foundations/typography) |
| `SearchField` uses `.appFont(.subheadline)` — `.subheadline` is removed in the rationalisation; correct replacement is `.body` (search input text is body-weight content, not a subheading) | `SearchField.swift` | [typography](./foundations/typography) |
| `ToastBanner` uses `.appFont(.subheadlineSemibold)` — removed in rationalisation; replace with `.subheading` | `ToastCenter.swift` | [typography](./foundations/typography) |
| `SettingsMoreTabView` uses `.appFont(.subheadline)` — removed in rationalisation; replace with `.body` | `SettingsMoreTabView.swift` | [typography](./foundations/typography) |
| `SettingsTabsView` applies `.appFont(.subheadline)` as a global modifier on the whole tab view — removed in rationalisation; replace with `.body` | `SettingsTabsView.swift` | [typography](./foundations/typography) |
| `MacModalShell` inspector sheet `maxWidth: 1_120` is hardcoded — should be a `Size` token (`Size.inspectorMaxWidth`) | `MacModalShell.swift` | [components](./components/overview) |
| `DesignTokens.Typography` is unused — parallel system to `AppFontStyle`, should be removed | `DesignTokens.swift` | [token-audit](./audits/token-audit) |
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
| Web keyboard shortcuts incomplete — full shortcut audit needed | `frontend/src/` | [web-conventions](./platform-strategy/web-conventions) |
| Web tasks detail view is a modal form only — native has a dedicated detail panel; web should have an equivalent | `frontend/src/` | [web-conventions](./platform-strategy/web-conventions) |
| Skills Store is nested inside the Settings modal on web — should be a standalone section matching native | `frontend/src/` | [web-conventions](./platform-strategy/web-conventions) |

---

## Related docs

- [iOS Conventions](./platform-strategy/ios-conventions)
- [macOS Conventions](./platform-strategy/macos-conventions)
- [Web Conventions](./platform-strategy/web-conventions)
- [Colour](./foundations/colour)
- [Materials and Appearance](./foundations/materials-and-appearance)
- [Components](./components/overview)
- [Token Audit](./audits/token-audit)
