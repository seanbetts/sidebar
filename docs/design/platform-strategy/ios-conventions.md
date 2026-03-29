---
title: iOS Conventions
description: iPhone and iPad conventions for navigation, layout, input, and interaction in sideBar.
---

| Field | Value |
|---|---|
| Status | approved |
| Owner | AI coding agent |
| Outputs | this doc |
| Dependencies | [overview](./overview) |

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

Scratchpad on iPhone is presented as a `.sheet` (same presentation as Settings) and is accessible from the navigation bar of any section that shows the profile/settings avatar — positioned immediately to the left of it.

**Rules**:
- Scratchpad button appears wherever the profile/settings avatar appears in a section title bar
- Scratchpad button is always to the left of the profile/settings avatar
- Presented as `.sheet` with grab indicator, matching the Settings presentation pattern
- Scratchpad is not accessible from the Chat section (remove the current `ChatView` nav bar button)

**Current state**: The scratchpad button exists only in `ChatView` nav bar when a conversation is open. This should be removed and replaced with the above pattern.

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

**Rule**: Any interactive element that has a hover state on macOS must have an equivalent iPad pointer hover state. Use `.onHover` without `#if os(macOS)` guards where the behaviour should apply to both platforms.

**Current state — audit complete**:

| Element | File | Has hover | Fix needed |
|---|---|---|---|
| SidebarRail section buttons | `SidebarRail.swift:117` | macOS only (`#if os(macOS)` guard) | Remove guard |
| SidebarRail app logo button | `SidebarRail.swift:32` | No | Add `.onHover` |
| SidebarRail profile avatar button | `SidebarRail.swift:54` | No | Add `.onHover` |
| Right sidebar resize handle | `WorkspaceLayout.swift:143` | No | Add `.onHover` cursor change |
| Sidebar resize handle | `SidebarSplitView.swift:46` | No | Add `.onHover` cursor change |
| SelectableRow (list rows) | `SelectableRow.swift:40` | No | Add `.onHover` |
| HeaderActionIcon / header buttons | `HeaderActionIcon.swift:14` | No | Add `.onHover` |
| SiteHeaderBar buttons | `SiteHeaderBar.swift:159,183,201` | No | Add `.onHover` |
| Chat header buttons | `ChatHeaderView.swift:31,42,94` | No | Add `.onHover` |
| Files header buttons | `FilesHeaderActions.swift:79,153,196` | No | Add `.onHover` |

The highest-priority fix is removing the `#if os(macOS)` guard on `SidebarRail` section buttons — the hover logic already exists and just needs to apply on iPad too.

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

All haptic feedback is implemented via `Haptics.*` (`Design/Haptics.swift`). Never call `UINotificationFeedbackGenerator`, `UIImpactFeedbackGenerator`, or `UISelectionFeedbackGenerator` directly in views.

For the full interaction map and feedback taxonomy, see [feedback-and-haptics](../patterns/feedback-and-haptics).

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

## Background execution

User-initiated operations must complete regardless of whether the app stays in the foreground. If the user saves a website, queues a file upload, or makes an edit while offline, those operations must finish even if the user immediately backgrounds the app.

This is the other half of the "Saved for later" contract: the messaging is honest only if the save will eventually happen without requiring the user to return to the app.

**Rule**: Any operation that makes a promise to the user must be capable of completing in the background. Use the appropriate mechanism for each operation type:

| Operation type | Background mechanism |
|---|---|
| File uploads | `URLSessionConfiguration.background` (already implemented) |
| Website save job polling | `BGProcessingTask` or background URLSession |
| WriteQueue flush (offline writes) | `BGProcessingTask` on network availability |
| Long-running processing | Live Activities + completion notification |

Operations that are already optimistic (note edits, task mutations) do not need background execution — they apply locally immediately and the WriteQueue handles eventual sync.

---

## iOS accessibility conventions

- Minimum touch target: 44pt (enforced via `DesignTokens.Size.touchTarget`)
- Dynamic Type: supported via app font scaling system
- VoiceOver: accessibility labels on all navigation items
- Reduce Motion: respected in all animations via `Motion.quick/standard(reduceMotion:)`
- Increase Contrast: inherited from system color semantics on iOS

---

## Rules summary

1. **Tab bar is navigation only.** Do not customise beyond tint color. Do not replace it with a custom bottom bar.
2. **Search belongs in the search dock.** Use the search dock pattern for all panel-level search on iPhone. Do not add search to the navigation bar.
3. **Create actions belong in the floating action dock on iPhone.** Do not add create actions to the navigation bar on iPhone.
4. **iPhone settings = sheet.** No other presentation.
5. **Minimum touch target is 44pt.** No interactive element smaller than 44pt in the compact layout.
6. **Use `Haptics.*` for all haptic calls.** Never instantiate feedback generators directly in views.
7. **iPad pointer hover must match macOS hover.** Any `.onHover` behaviour that applies to both iPad and Mac must not be gated behind `#if os(macOS)`.
8. **User-initiated operations must complete in the background.** Any operation that makes a promise to the user must be capable of finishing without requiring the app to stay in the foreground. See [background execution](#background-execution).

---

## Related docs

- `platform-strategy/overview.md`
- `platform-strategy/macos-conventions.md`
- `system-inheritance.md`
- `audits/system-framework-usage-audit.md`
