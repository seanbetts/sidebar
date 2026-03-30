---
title: Menus and Shortcuts
description: Mac menu bar structure, keyboard shortcuts, context menus, and swipe actions for sideBar across iOS, macOS, and web.
---

## Purpose

Define the complete shortcut set, menu bar structure, context menu conventions, and swipe action rules for sideBar across all platforms.

---

## Mac menu bar

### Menu structure

| Menu | Contents |
|---|---|
| App | Settings… (Cmd+,) |
| Navigate | Cmd+1–N for each primary section |
| View | Toggle Sidebar (Cmd+Shift+S), Open Scratchpad (Cmd+Shift+O) |
| Format | Text styles (Title, Heading, Subheading, Body) + Bold, Italic, Underline, Strikethrough, Inline Code — Notes only, macOS 26+, disabled when not in a note |
| [Section] | Context-aware: one menu for whichever section is focused |

**Rule**: The Format menu is Notes-only and must be disabled (not hidden) when the user is not actively editing a note. This follows macOS document-app conventions.

**Rule**: The View menu exposes global commands that are not tied to a section. Commands that appear in the UI must also be discoverable in the menu bar.

**Rule**: The section menu label matches the name of the active section. Only one section menu is visible at a time — the menu bar stays focused on the user's current context.

### Section menu commands

| Section | Commands |
|---|---|
| Chat | Send Message (Cmd+Return), Attach File (Cmd+Shift+F), Rename (Cmd+Shift+R), Delete (Cmd+Delete) |
| Notes | New Folder (Cmd+Shift+N), Pin (Cmd+Shift+P), Archive (Cmd+Shift+A), Delete (Cmd+Shift+Delete) |
| Websites | Pin (Cmd+Opt+P), Archive (Cmd+Opt+A), Open in Browser (Cmd+Shift+Return), Delete (Cmd+Opt+Delete) |
| Files | Quick Look (Space), Delete (Cmd+Opt+Shift+Delete) |
| Tasks | Complete (Cmd+Return), Edit Notes (Cmd+Shift+N), Move (Cmd+Shift+M), Set Due Date (Cmd+D), Edit Repeat (Cmd+Shift+R), Delete (Cmd+Shift+Delete) |

Cmd+Return maps to the primary action of the focused section: Send Message in Chat, Complete Task in Tasks. This is intentional — the shortcut mirrors what Enter does in each context.

### Universal shortcuts

These apply regardless of which section is focused.

| Shortcut | Action |
|---|---|
| Cmd+1–6 | Navigate to each section |
| Cmd+N | New item in current section |
| Cmd+F | Search in current section |
| Cmd+, | Open Settings |
| Cmd+W | Close |
| Cmd+R | Refresh |
| Cmd+Shift+O | Open Scratchpad |
| Cmd+Shift+S | Toggle sidebar |
| Cmd+Shift+/ | Show all shortcuts |
| Escape | Close open item or settings panel |

**Rule**: All common actions must have keyboard shortcuts on Mac. New Mac features must include shortcuts by default, not as an afterthought.

---

## Context menus

Context menus appear on long-press (iOS) and right-click (macOS). They surface row-level actions that are not visible inline.

### Implementation

Use `PlatformContextMenu` (`Design/Components/PlatformContextMenu.swift`) for all context menus. This adapter handles the difference between iOS `.contextMenu` and macOS right-click presentation.

All menu item icons are provided by `SidebarMenuItem` (`Design/Components/SidebarMenuItem.swift`) factory methods. Do not assign SF Symbol names to menu items inline in views — use or add a `SidebarMenuItem` factory method.

### Action ordering

Context menus follow this ordering convention:

1. Primary positive action (e.g. Open, Edit)
2. Secondary actions (e.g. Rename, Move, Duplicate)
3. State toggles (e.g. Pin, Archive)
4. Destructive actions last, separated by a divider

**Rule**: Destructive actions must use `.destructive` role so they render in red on both platforms.

### Common action set

These actions appear consistently across sections. Use `SidebarMenuItem` factory methods for all of them:

| Action | SF Symbol | Destructive |
|---|---|---|
| Rename | `pencil` | No |
| Move | `folder` | No |
| Pin / Unpin | `pin` / `pin.slash` | No |
| Archive / Unarchive | `archivebox` / `archivebox.fill` | No |
| Open in Browser | `safari` | No |
| Share | `square.and.arrow.up` | No |
| Delete | `trash` | Yes |

---

## Swipe actions (iOS)

Swipe actions on list rows are the primary mechanism for destructive actions and quick toggles without opening an item.

### Implementation

Use `SidebarSwipeActions` (`Design/Components/SidebarSwipeActions.swift`) for all row swipe actions. Icon assignment goes through `SidebarMenuItem` factory methods — the same set used in context menus.

### Rules

- **Trailing swipe**: destructive actions only (Delete, Archive). Delete must fire `Haptics.notification(.error)`.
- **Leading swipe**: non-destructive quick actions (Pin, Complete). These fire `Haptics.selection()`.
- Do not put more than two actions in a single swipe direction.
- Swipe actions are iOS only. On macOS, the same actions appear in the context menu and section menu.

---

## Section header menus

Content header bars in Notes, Websites, Files, and Tasks include a `HeaderActionMenuButton` — an `ellipsis` icon that opens a menu of actions for the currently open item.

### Implementation

Use `HeaderActionMenuButton` (`Design/Components/HeaderActionIcon.swift`) for all content header overflow menus. It accepts an array of `SidebarMenuItem` items, using the same factory methods as context menus and swipe actions.

On iOS, the header menu is the primary surface for actions on an open item that don't warrant a persistent toolbar button. On macOS, the equivalent actions appear in the section menu bar menu.

### Actions by section

| Section | Header menu actions |
|---|---|
| Notes | Pin/Unpin, Move, Copy Text, Share, Download, Archive/Unarchive, Delete |
| Websites | Pin/Unpin, Rename, Copy Markdown, Copy Title, Copy URL, Share, Share Text, Download, Archive/Unarchive, Delete |
| Files | Pin/Unpin, Rename, Copy Text, Download, Delete |
| Tasks | Actions available via row-level context menu |

**Rule**: Reserve standalone `HeaderActionIcon` buttons for the two or three most frequent actions. Everything else goes in the `HeaderActionMenuButton` overflow menu.

**Rule**: The header menu must be disabled when no item is selected. Apply `.disabled(selection == nil)`.

---

## iOS keyboard shortcuts (external keyboard)

On iPad and iPhone with an external keyboard, shortcuts mirror the Mac set exactly. The full shortcut set — universal navigation, section-specific commands, and Notes formatting — is available. Shortcuts are context-aware, changing with the active section.

---

## Web keyboard shortcuts

| Shortcut | Action |
|---|---|
| Cmd/Ctrl+1–5 | Navigate to sections |

**Rule**: Web navigation shortcuts must match native Mac (Cmd+1–N). Use `Ctrl` as the modifier on non-Mac platforms. When new shortcuts are added to the web app, document them here.

---

## Rules summary

1. **All common Mac actions must have keyboard shortcuts.** New Mac features include shortcuts by default.
2. **The View menu exposes global commands.** Toggle Sidebar and Open Scratchpad belong in the menu bar.
3. **Section menus are context-aware.** One section menu at a time, matching the active section.
4. **Use `PlatformContextMenu` for all context menus.** Do not use `.contextMenu` directly in views.
5. **Use `SidebarMenuItem` factory methods for all action icons.** No inline SF Symbol assignments for menu or swipe items.
6. **Use `SidebarSwipeActions` for all swipe actions.** Trailing = destructive. Leading = non-destructive.
7. **Destructive actions use `.destructive` role.** They appear last in context menus, separated by a divider.
8. **Use `HeaderActionMenuButton` for content header overflow actions.** Reserve standalone `HeaderActionIcon` buttons for the most frequent actions only.
9. **Header menus are disabled when no item is selected.** Apply `.disabled(selection == nil)`.
10. **Web shortcuts mirror Mac.** Use Ctrl as modifier on non-Mac platforms.

---

## Related docs

- [macOS Conventions](../platform-strategy/macos-conventions)
- [iOS Conventions](../platform-strategy/ios-conventions)
- [Web Conventions](../platform-strategy/web-conventions)
- [Iconography](../foundations/iconography) — SF Symbol assignments via `SidebarMenuItem`
- [Components Overview](../components/overview) — `SidebarMenuItem`, `SidebarSwipeActions`, `PlatformContextMenu`
- [Feedback and Haptics](./feedback-and-haptics) — haptic rules for swipe and menu actions
- [Implementation Gaps](../implementation-gaps)
