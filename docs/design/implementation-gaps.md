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
| Haptic: settings save missing `Haptics.selection()` on explicit save completion — `SettingsSaveStatusPill` shows visual saved state but no haptic fires | `SettingsSaveStatusPill.swift` | [wait-ux](./patterns/wait-ux) |
| Pull-to-refresh not confirmed implemented on iOS list panels — all sidebar list panels should use the `refreshable` modifier | Sidebar panel views | [wait-ux](./patterns/wait-ux) |
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
| Chat pre-first-token state shows "Working..." animated dot — should be replaced with an inline thinking indicator in the message row, matching native | `frontend/src/lib/components/chat/Message.svelte` | [wait-ux](./patterns/wait-ux) |
| Native chat missing inline tool execution states — web shows "Using {name}" / "Used {name}" / "Failed to use {name}" per message; native has no equivalent | `ChatToolBanners.swift` / chat message components | [wait-ux](./patterns/wait-ux) |
| `prefers-reduced-motion` not confirmed implemented — should be respected in all animations | `frontend/src/` | [web-conventions](./platform-strategy/web-conventions) |
| Web dark mode surface values lighter than native — `--background` dark is `oklch(0.145 0 0)` (≈ `#1a1a1a`), should be `oklch(0.065 0 0)` (≈ `#0a0a0a`) | `frontend/src/app.css` | [colour](./foundations/colour) |

### Low priority

| Gap | File(s) | Source |
|---|---|---|
| Web keyboard shortcuts incomplete — full shortcut audit needed | `frontend/src/` | [web-conventions](./platform-strategy/web-conventions) |

---

## Related docs

- [iOS Conventions](./platform-strategy/ios-conventions)
- [macOS Conventions](./platform-strategy/macos-conventions)
- [Web Conventions](./platform-strategy/web-conventions)
- [Colour](./foundations/colour)
- [Materials and Appearance](./foundations/materials-and-appearance)
- [Components](./components/overview)
- [Token Audit](./audits/token-audit)
