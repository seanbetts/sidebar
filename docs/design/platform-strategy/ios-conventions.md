---
title: iOS Conventions
description: iPhone and iPad conventions for navigation, layout, input, and interaction in sideBar.
---

| Field | Value |
|---|---|
| Status | drafted |
| Owner | AI coding agent |
| Outputs | this doc |
| Dependencies | [overview](./overview) |
| Blocking approval | hover state audit, haptics audit, scratchpad iPhone UX decision |

## Purpose

Document iOS-specific (iPhone and iPad) design conventions for sideBar. This covers navigation, layout, input, and interaction patterns specific to touch-based Apple platforms.

---

## iPhone conventions

### Navigation

Primary navigation: `TabView` with system tab bar.

Tab items use `Label` with `Image(systemName:)` and `.symbolVariant(.none)`. Tint set via `.tint(tabBarTint)`. The tab bar uses the system appearance without customisation.

Tabs visible at once: varies by section count. When sections exceed the tab limit, overflow goes into a "More" tab (NavigationStack destination with a list of additional sections).

**Rule**: Do not customise the tab bar beyond tint color. Do not replace it with a custom bottom bar.

### Search

A floating `SearchField` dock appears above the tab bar, pinned to the bottom safe area via `safeAreaInset(edge: .bottom)`. It expands to full width when tapped/focused, or stays collapsed (trailing alignment) when inactive.

On sections that support search, the search dock replaces the floating action dock when the user taps it.

**Rule**: Use the search dock pattern for all panel-level search on iPhone. Do not add search to the navigation bar.

### Create actions

A `PhoneFloatingActionDock` (Liquid Glass capsule) provides section-specific create actions above the tab bar, trailing-aligned. It contains `PhoneFloatingActionButton` instances and `PhoneFloatingActionDivider` separators.

Section-specific actions:
- Chat: New chat
- Notes: New note + New folder
- Tasks: New task (or menu with New task / New group / New project when in list view)
- Websites: Add website
- Files: Add file + Add YouTube video

**Rule**: All create actions on iPhone must appear in the floating action dock. Do not add create actions to the navigation bar on iPhone.

### Settings

Settings presented as `.sheet`. Grab indicator visible (`.presentationDragIndicator(.visible)`).

**Rule**: iPhone settings = sheet. No other presentation.

### Scratchpad

Scratchpad is accessible on iPhone via a button in the Chat view navigation bar (`ChatView.swift`). It presents as a `.sheet`. There is no global entry point for scratchpad on iPhone outside of Chat. The best UX for scratchpad on compact devices is an open question.

### Layout

iPhone always uses compact layout: one section visible at a time. The workspace right-sidebar is not available on iPhone.

Screen safe areas are respected throughout. Content does not overlap system chrome.

Soft keyboard visibility is tracked to adjust floating dock bottom padding.

### Touch targets

Minimum touch target: `DesignTokens.Size.touchTarget = 44pt`. All interactive elements must meet this minimum.

`PhoneFloatingActionButton` uses 44pt frame. Tab bar targets are system-standard.

**Rule**: No interactive element smaller than 44pt in the compact layout.

### Typography

Use `.appFont(style)` throughout. No raw `.font(.system(size:))` calls.

Body text: `.appFont(.body)` = 16pt base, scales with app text size preference.

---

## iPad conventions

### Navigation

Same `WorkspaceLayout` as Mac: `SidebarRail` + left panel + main content + optional right sidebar.

The layout adapts based on `horizontalSizeClass == .regular`. On iPad this is always true (all orientations).

**Note**: iPad uses the same NavigationStack per section as iPhone but the panels are always visible alongside the detail view. The user does not navigate "into" a detail, they select it in the panel.

### Keyboard

Hardware keyboard supported. `onKeyPress(.escape)` already handles search dock dismissal.

Future: keyboard shortcuts for common actions should be documented and implemented following Mac conventions.

### Settings

Uses `.sheet` presentation, same as iPhone. The sheet is correctly sized on iPad - no change needed.

### Multitasking

sideBar runs its own three-column workspace structure. Designing specifically for Slide Over, Split View, and Stage Manager adds complexity on top of that without sufficient return. The compact/regular size class split handles Slide Over gracefully as a side effect. No further multitasking-specific design work is planned.

### Pointer and hover

iPad is a first-class productivity platform for sideBar. Pointer and hover states must be supported when a mouse or trackpad is connected.

`SidebarRail` already implements `.onHover` for macOS. The same hover behaviour should apply on iPad. All interactive elements in the workspace layout - rail buttons, list rows, header actions, resize handles - should have defined hover states.

**Rule**: Any element with a macOS hover state must have an equivalent iPad pointer hover state. Use `.onHover` without `#if os(macOS)` guards where the behaviour should apply to both platforms.

---

## iOS-specific design patterns

### Liquid Glass (iOS 26)

iOS 26 is the minimum deployment target. Liquid Glass (`glassEffect`) is available as a first-class primitive.

Current usage: `PhoneFloatingActionDock`.

Planned usage (per adoption plan): `SettingsSaveStatusPill`, `SearchField` (dock chrome), `PanelHeader`, `SidebarRail`, `SiteHeaderBar`, `HeaderActionIcon`, `NoteFormattingBar`, `MacPopoverShell`, `MacModalShell`, `SettingsMacStyles`, `LoginView`.

**Rule for agent**: New transient surface chrome (pills, action bars, popovers) on iOS 26+ should use Liquid Glass where the adoption plan specifies it. Solid fills are used for persistent surfaces (panels, backgrounds).

### System materials

On iOS 26, system materials (`.regularMaterial`, `.ultraThinMaterial`) are superseded by Liquid Glass for interactive chrome. For non-interactive backgrounds, system materials may still be appropriate. Default is solid adaptive color via `DesignTokens.Colors`.

### Haptics

Haptics are currently minimal. Only auth flows use haptic feedback (`LoginView`, `BiometricLockView`) via `UINotificationFeedbackGenerator`. No haptics found in panel lists, floating action dock, or chat. A full haptics audit is needed before approving this document. Full guidance belongs in `patterns/feedback-and-haptics.md`.

---

## iOS-specific notes on components

### SidebarRail (iPad)

On iPad, the SidebarRail is always visible as the leftmost 56px strip. It does not collapse or overlay.

**Gap**: `SidebarRail` uses `.font(.system(size: 18, weight: .semibold))` directly. Should be `.appFont(.labelMd)` or equivalent. This bypasses the app text size preference.

### TabView tint

The `TabView` tint is set from a computed `tabBarTint` value. The value should be `Color.accentColor` (the system accent). If it differs, document why.

### Pull to refresh

Confirmed. All panel lists use native SwiftUI `.refreshable`: Chat, Notes, Tasks, Websites, Files. Settings lists also use `.refreshable` where appropriate. This is correct — no custom pull-to-refresh implementation.

---

## iOS accessibility conventions

- Minimum touch target: 44pt (enforced via `DesignTokens.Size.touchTarget`)
- Dynamic Type: supported via app font scaling system
- VoiceOver: accessibility labels on all navigation items
- Reduce Motion: respected in all animations via `Motion.quick/standard(reduceMotion:)`
- Increase Contrast: inherited from system color semantics on iOS

---

## Open questions

- Hover state audit: `.onHover` is currently only implemented in `SidebarRail`. All other interactive elements in WorkspaceLayout (list rows, header actions, resize handles) lack hover states on iPad. This needs to be resolved before approving this document.
- Scratchpad UX: the best entry point for scratchpad on iPhone (beyond the Chat nav bar button) is undecided.
- Haptics audit: a full review of where haptic feedback should be used is needed before approving this document.

---

## Related docs

- `platform-strategy/overview.md`
- `platform-strategy/macos-conventions.md`
- `system-inheritance.md`
- `audits/system-framework-usage-audit.md`
