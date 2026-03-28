---
title: macOS Conventions
description: macOS conventions for layout, windowing, input, and navigation in sideBar.
---

| Field | Value |
|---|---|
| Status | approved |
| Owner | AI coding agent |
| Outputs | this doc |
| Dependencies | [overview](./overview) |

## Purpose

Document macOS-specific design conventions for sideBar. This covers the Mac layout model, settings presentation, keyboard navigation, window management, and AppKit integration.

---

## Mac layout

sideBar on Mac always uses `WorkspaceLayout`:

```
[ SidebarRail 56px ] [ Left panel ~280px ] [ Divider 8px ] [ Main content ] [ Right sidebar (optional) ]
```

There is no compact/tablet fallback on macOS. The Mac is always regular layout.

The left panel is a fixed width (280px). It is not user-resizable. `SidebarSplitView.swift` contains a remnant `DragGesture`-based resize handle and `@AppStorage` width persistence that should be removed.

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

Keyboard shortcuts are implemented across the app. Universal shortcuts and section-specific shortcuts are documented in the Mac menu bar section below. The `KeyboardShortcuts/` folder handles shortcut registration. Escape is handled for search dock dismissal.

**Rule**: All common actions should have keyboard shortcuts on Mac. New Mac features must include shortcuts as a default, not an afterthought.

### Mac menu bar

Implemented in `Views/AppCommands.swift` via `SidebarCommands: Commands`.

**Menu structure:**

| Menu | Contents |
|---|---|
| App | Settings… (Cmd+,) — replaces system default |
| Navigate | Cmd+1–N for each primary section |
| Format | Text styles (Title, Heading, Subheading, Body) + Bold, Italic, Underline, Strikethrough, Inline Code — Notes only, macOS 26+, disabled when not editing |
| [Section] | Context-aware: shows one menu for whichever section is focused (Chat, Notes, Websites, Files, or Tasks) |

**Section menu commands:**

| Section | Commands |
|---|---|
| Chat | Send Message (Cmd+Return), Attach File (Cmd+Shift+F), Rename (Cmd+Shift+R), Delete (Cmd+Delete) |
| Notes | New Folder (Cmd+Shift+N), Pin (Cmd+Shift+P), Archive (Cmd+Shift+A), Delete (Cmd+Shift+Delete) |
| Websites | Pin (Cmd+Opt+P), Archive (Cmd+Opt+A), Open in Browser (Cmd+Shift+Return), Delete (Cmd+Opt+Delete) |
| Files | Quick Look (Space), Delete (Cmd+Opt+Shift+Delete) |
| Tasks | Complete (Cmd+Return), Edit Notes (Cmd+Shift+N), Move (Cmd+Shift+M), Set Due Date (Cmd+D), Edit Repeat (Cmd+Shift+R), Delete (Cmd+Shift+Delete) |

**Escape** closes the open item or settings panel depending on state.

**Universal shortcuts** (handled outside `AppCommands` via `onKeyPress` and separate Commands):

| Shortcut | Action |
|---|---|
| Cmd+1–6 | Navigate to each section |
| Cmd+N | New item |
| Cmd+F | Search |
| Cmd+, | Open Settings |
| Cmd+W | Close |
| Cmd+R | Refresh |
| Cmd+Shift+O | Open Scratchpad |
| Cmd+Shift+S | Toggle sidebar |
| Cmd+Shift+/ | Show all shortcuts |

**What is working well:**
- Context-aware section menus are the right pattern. One relevant menu, not all sections at once.
- The Format menu for Notes behaves like a proper document-app menu. Toggle state for Bold/Italic is correctly reflected.
- Cmd+Return serves two purposes (Send Message in Chat, Complete Task in Tasks). This is intentional and correct given the context-aware model.
- The product docs and `AppCommands.swift` are in sync — everything documented is implemented.
- Files is deliberately sparse. Files are passive content and the menu reflects that.

**One gap:**
Several universal shortcuts (Cmd+Shift+S, Cmd+Shift+O, Cmd+N, Cmd+F, Cmd+R) are not represented in the menu bar. There is no View menu, so sidebar toggle and scratchpad are undiscoverable via the menus. A minimal View menu with "Toggle Sidebar" and "Open Scratchpad" would follow Mac convention and make these findable without requiring users to already know the shortcut.

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

## Color palette

**Direction**: sideBar should use a single unified color palette across all platforms. The current `MacOSPalette` in `Color+Platform.swift` — hand-coded sRGB `NSColor` values that differ from the iOS semantic color layer — should be consolidated into one shared palette. Platform-specific color branching should be removed.

The target palette is the near-neutral set currently used on macOS (near-white light mode, near-black dark mode). This palette should become the single source of truth for both iOS and macOS, replacing the current iOS UIKit semantic color wrappers where they diverge.

**Direction**: Light and dark mode values should be consistent across platforms. There should be no platform-specific dark mode or light mode variants.

**Current state** (to be migrated): `Color+Platform.swift` currently branches between iOS (UIKit semantic colors) and macOS (hand-coded NSColor values). This is the implementation that needs to change. Full definition of the target palette belongs in `foundations/colour.md`.

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

- Should a View menu be added to expose the sidebar toggle shortcut (Cmd+Shift+S)? (Captured — not implementing now.)
- Should the sidebar rail width (56px) be tokenised in `DesignTokens.Size`?

---

## Related docs

- `platform-strategy/overview.md`
- `platform-strategy/ios-conventions.md`
- `system-inheritance.md`
- `audits/system-framework-usage-audit.md`
