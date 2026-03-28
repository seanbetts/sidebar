---
title: macOS Conventions
description: Draft macOS conventions for layout, windowing, input, and navigation in sideBar.
---

| Field | Value |
|---|---|
| Status | drafted |
| Owner | AI coding agent |
| Inputs needed | codebase inspection (complete), Sean's Mac design priorities |
| Outputs | this doc |
| Dependencies | [overview](./overview) |
| Codebase review required | yes (complete) |
| Human judgement required | yes - menu bar structure, window management, keyboard shortcut scope |

## Purpose

Document macOS-specific design conventions for sideBar. This covers the Mac layout model, settings presentation, keyboard navigation, window management, and AppKit integration.

---

## Mac layout

sideBar on Mac always uses `WorkspaceLayout`:

```
[ SidebarRail 56px ] [ Left panel ~280px ] [ Divider 8px ] [ Main content ] [ Right sidebar (optional) ]
```

There is no compact/tablet fallback on macOS. The Mac is always regular layout.

The left panel is user-resizable (min 200px, max 500px, snap points at 33/40/50% of available width). Width persisted via `@AppStorage`.

The right sidebar is available in workspace mode (expand/collapse toggle). Width is user-resizable (min 280px, default 360px). Width persisted via `@AppStorage`.

---

## Mac navigation

### SidebarRail

The `SidebarRail` serves as the primary navigation on Mac. It is always visible. It provides:
- Section navigation buttons (icon-only, 32x32pt hit area, 44pt touch target equivalent with hover)
- Skills Store button (pinned bottom)
- Profile avatar button (Settings, pinned bottom)
- App logo (top, toggles left panel expand/collapse)

`.onHover` is used for hover state highlighting. Active section uses `Color.accentColor.opacity(0.18)` background. Hovered non-active uses `Color.primary.opacity(0.08)`.

**Gap**: Icon font uses `.font(.system(size: 18, weight: .semibold))` directly. Should use `.appFont()`.

### Keyboard shortcuts

`KeyboardShortcuts/` folder exists in the codebase, suggesting a keyboard shortcut system is in place. The escape key is handled for search dock dismissal. Full shortcut documentation is needed (separate audit).

**Rule**: All common actions should have keyboard shortcuts on Mac. New Mac features must include shortcuts as a default, not an afterthought.

### Mac menu bar

Not inspected in detail in this audit. macOS apps are expected to have a complete menu bar with standard menu categories (File, Edit, View, Window, Help). The current state of the menu bar is unknown.

**To do**: Audit the menu bar structure separately.

---

## Mac settings

Settings on macOS uses a dedicated window, not a sheet. Opened via `environment.presentMacSettings()` which uses AppKit window management.

The settings window uses `MacModalShell` which applies:
- `.formStyle(.grouped)` for grouped form appearance
- `.scrollContentBackground(.hidden)` for custom backgrounds
- `DesignTokens.Colors.settingsBackground` as the window background
- `.presentationSizing(.fitted)` for appropriate sizing

On Mac, settings has a tab-based structure (`SettingsView+Tabs.swift`) similar to native macOS Settings panes.

**Rule**: Mac settings = dedicated window. Do not present settings as a sheet on macOS.

---

## Mac-specific components

### MacModalShell

Used for all modal/sheet presentations on macOS. Provides correct background, sizing, and presentation. iOS stub passes through content unchanged.

Source: `Design/Components/MacModalShell.swift`

### MacPopoverShell

Used for popover presentations on macOS.

Source: `Design/Components/MacPopoverShell.swift`

### MacModalPresentation

Higher-level window/panel presentation helper.

Source: `Design/Components/MacModalPresentation.swift`

### SettingsMacStyles

Mac-specific styling for settings sections.

Source: `Views/Settings/SettingsMacStyles.swift`

### AppKit editor surfaces

- `AppKitNoteTextEditorSurface`: `NSTextView`-based rich text editor
- `AppKitNoteFormattingBar`: macOS formatting toolbar
- `AppKitNoteFormattingPopoverView`: NSPopover for formatting options
- `ChatInputAppKit`: AppKit text input for chat

These are necessary and correct uses of AppKit where SwiftUI doesn't provide adequate text editing capabilities.

---

## macOS color palette

macOS uses the `MacOSPalette` from `Color+Platform.swift` instead of iOS system semantic colors. These are hand-coded sRGB `NSColor` values:

| Token | Light | Dark |
|---|---|---|
| background | #ffffff | #0a0a0a |
| card | #ffffff | #171717 |
| muted | #f5f5f5 | #262626 |
| sidebar | #fafafa | #171717 |
| sidebarAccent | #f5f5f5 | #262626 |
| border | #e5e5e5 | white 10% |
| input | #e5e5e5 | white 15% |

`NSColor.separatorColor` is used directly in `SidebarRail` for the rail/panel border, which correctly inherits system separator color.

**Implication**: The custom palette is deliberately near-neutral. In dark mode it uses very dark (near-black) surfaces rather than the default macOS dark window chrome. This is a deliberate design stance.

**Implication**: If macOS default backgrounds change significantly (e.g. in a future macOS version), these values will not adapt automatically. They need manual review.

---

## Pointer and hover

Mac UI should handle hover states for all interactive elements:

- `SidebarRail` section buttons: hover state with `Color.primary.opacity(0.08)` background
- Header action icons: hover state (via `HeaderActionIcon`)
- List rows: hover state via `SelectableRow` (if implemented - needs verification)

**Rule**: Any interactive element on macOS should have a hover state. `.onHover` should be wrapped in `#if os(macOS)`.

---

## Window management

sideBar is a single-window Mac app. There is one workspace window. Settings opens as a separate window via AppKit window management, but only one workspace window exists at a time.

---

## Liquid Glass on macOS 26

macOS 26 supports Liquid Glass. The adoption plan covers Mac-specific surfaces:
- `MacPopoverShell`
- `MacModalShell`
- `SettingsMacStyles`
- `SettingsSaveStatusPill` (macOS branch)
- `SidebarRail`
- `SiteHeaderBar`

**Rule for agent**: Follow the Liquid Glass adoption plan for Mac surfaces. The rollout order matters: primitives first, then individual surfaces one at a time.

---

## macOS accessibility conventions

- Keyboard navigation: all interactive elements reachable by Tab key
- Focus ring: system focus ring on interactive controls
- VoiceOver: accessibility labels on navigation items
- Keyboard shortcuts: document all shortcuts; support standard macOS shortcuts (Cmd+N, Cmd+F, etc.)
- Menu bar: complete menu structure following macOS HIG
- Reduce Motion: respected via `Motion.*` helpers

---

## macOS notes on specific patterns

### Section header (PanelHeader)

On macOS in light mode, `PanelHeader` uses `.sidebar` background. In dark mode, it uses `.surface`. This is the only component with explicit light/dark Mac-specific background selection.

Source: `PanelHeader.swift:76-81`

### SiteHeaderBar

A custom header bar for the Website section. Not fully inspected. Likely platform-adaptive.

Source: `Views/Websites/SiteHeaderBar.swift`

---

## Open questions

- What is the current state of the Mac menu bar (commands, structure)? (In discussion.)
- What keyboard shortcuts are currently implemented?
- Should the Mac color palette attempt to use more NSColor semantic values?
- Should the sidebar rail width (56px) be tokenised in `DesignTokens.Size`?

---

## Related docs

- `platform-strategy/overview.md`
- `platform-strategy/ios-conventions.md`
- `system-inheritance.md`
- `audits/system-framework-usage-audit.md`
