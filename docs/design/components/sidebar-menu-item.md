---
title: SidebarMenuItem
description: Factory type for all context menu and swipe action items, with pre-configured actions and canonical AppIcon assignments.
---

## Purpose

Provide a single source of truth for the title, `AppIcon`, and destructive role of every action that appears in context menus or swipe actions across the app. Do not assign icon names to menu items inline in views, use `SidebarMenuItem` factory methods.

---

## Factory methods

| Method | Title | Icon | Role |
|---|---|---|---|
| `.pin(isPinned:)` | "Pin" / "Unpin" | `AppIcon.Action.pin` / `AppIcon.Action.unpin` | none |
| `.archive(isArchived:)` | "Archive" / "Unarchive" | `AppIcon.Action.archive` / `AppIcon.Action.unarchive` | none |
| `.rename()` | "Rename" | `AppIcon.Action.rename` | none |
| `.move()` | "Move" | `AppIcon.Action.move` | none |
| `.reorder()` | "Reorder" | `AppIcon.Action.reorder` | none |
| `.copy()` | "Copy" | `AppIcon.Action.copy` | none |
| `.copyText()` | "Copy Text" | `AppIcon.Action.copy` | none |
| `.copyMarkdown()` | "Copy Markdown" | `AppIcon.Action.copy` | none |
| `.copyTranscript()` | "Copy Transcript" | `AppIcon.Action.copy` | none |
| `.copyTitle()` | "Copy Title" | `AppIcon.Action.copyTitle` | none |
| `.copyURL()` | "Copy URL" | `AppIcon.Action.copyURL` | none |
| `.download()` | "Download" | `AppIcon.Action.download` | none |
| `.share()` | "Share URL" | `AppIcon.Action.shareOnSquare` | none |
| `.shareFile()` | "Share" | `AppIcon.Action.share` | none |
| `.shareText()` | "Share Text" | `AppIcon.Action.shareOnSquare` | none |
| `.shareTranscript()` | "Share Transcript" | `AppIcon.Action.share` | none |
| `.exportTranscript()` | "Export Transcript" | `AppIcon.Action.download` | none |
| `.newTask()` | "New task" | `AppIcon.State.successCircle` | none |
| `.newGroup()` | "New group" | `AppIcon.Content.folder` | none |
| `.newProject()` | "New project" | `AppIcon.Content.taskList` | none |
| `.refresh()` | "Refresh" | `AppIcon.Action.refresh` | none |
| `.close()` | "Close" | `AppIcon.Action.close` | none |
| `.delete()` | "Delete" | `AppIcon.Action.delete` | `.destructive` |

Each factory method takes a `handler: @escaping () -> Void` parameter.

The toggle methods (`.pin`, `.archive`) take an additional `Bool` parameter and flip the title and symbol based on current state.

---

## Usage

### Context menu

```swift
.contextMenu {
    sidebarMenuItemsView([
        .pin(isPinned: item.isPinned, handler: { viewModel.togglePin(item) }),
        .rename(handler: { viewModel.beginRename(item) }),
        .delete(handler: { viewModel.delete(item) })
    ])
}
```

### With HeaderActionMenuButton (iOS)

```swift
HeaderActionMenuButton(
    icon: AppIcon.Action.more,
    accessibilityLabel: "More options",
    items: [
        .archive(isArchived: note.isArchived, handler: { viewModel.toggleArchive(note) }),
        .delete(handler: { showDeleteConfirmation = true })
    ]
)
```

### With SidebarSwipeActions

```swift
SidebarSwipeActions(
    trailingItems: [.delete(handler: { viewModel.delete(item) })],
    leadingItems: [.pin(isPinned: item.isPinned, handler: { viewModel.togglePin(item) })]
)
```

---

## Key rules

- **Never assign icon names to menu items inline.** Always use a `SidebarMenuItem` factory method. If the action you need does not have a factory method, add one.
- **`.delete()` is always destructive.** It uses `ButtonRole.destructive` automatically. Do not replicate this with a custom `SidebarMenuItem` initializer.
- **Destructive actions go at the bottom of the menu.** SwiftUI renders `.destructive` role items last automatically when using `sidebarMenuItemsView`.
- **Use `sidebarMenuItemsView(_:)` to render items** inside a `contextMenu` or `Menu`. Do not iterate over items and build `Button` views manually.

---

## Adding a new action

When a new context menu or swipe action is needed that does not exist as a factory method:

1. Add a new `static func` to the `SidebarMenuItem` extension in `SidebarMenuItem.swift`
2. Choose an `AppIcon.Action` from the canonical action table in [Iconography](../foundations/iconography)
3. Set `role: .destructive` if the action is irreversible
4. Use the new factory method everywhere — do not create the `SidebarMenuItem` inline

---

## Related

- [Header Actions](./header-actions) — `HeaderActionMenuButton` uses `SidebarMenuItem` items
- [Menus and Shortcuts](../patterns/menus-and-shortcuts) — full context menu and swipe action rules
- [Iconography](../foundations/iconography) — canonical `AppIcon` assignments
