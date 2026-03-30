---
title: SidebarMenuItem
description: Factory type for all context menu and swipe action items — provides pre-configured actions with canonical SF Symbol assignments.
---

## Purpose

Provide a single source of truth for the title, SF Symbol, and destructive role of every action that appears in context menus or swipe actions across the app. Do not assign SF Symbol names to menu items inline in views — use `SidebarMenuItem` factory methods.

---

## Factory methods

| Method | Title | Symbol | Role |
|---|---|---|---|
| `.pin(isPinned:)` | "Pin" / "Unpin" | `pin` / `pin.slash` | — |
| `.archive(isArchived:)` | "Archive" / "Unarchive" | `archivebox` / `archivebox.fill` | — |
| `.rename()` | "Rename" | `pencil` | — |
| `.move()` | "Move" | `arrow.forward.folder` | — |
| `.reorder()` | "Reorder" | `line.3.horizontal` | — |
| `.copy()` | "Copy" | `doc.on.doc` | — |
| `.copyText()` | "Copy Text" | `doc.on.doc` | — |
| `.copyMarkdown()` | "Copy Markdown" | `doc.on.doc` | — |
| `.copyTranscript()` | "Copy Transcript" | `doc.on.doc` | — |
| `.download()` | "Download" | `square.and.arrow.down` | — |
| `.share()` | "Share URL" | `square.and.arrow.up.on.square` | — |
| `.shareText()` | "Share Text" | `square.and.arrow.up.on.square` | — |
| `.delete()` | "Delete" | `trash` | `.destructive` |

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
    systemImage: "ellipsis",
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

- **Never assign SF Symbol names to menu items inline.** Always use a `SidebarMenuItem` factory method. If the action you need does not have a factory method, add one.
- **`.delete()` is always destructive.** It uses `ButtonRole.destructive` automatically — do not try to replicate this with a custom `SidebarMenuItem` initialiser.
- **Destructive actions go at the bottom of the menu.** SwiftUI renders `.destructive` role items last automatically when using `sidebarMenuItemsView`.
- **Use `sidebarMenuItemsView(_:)` to render items** inside a `contextMenu` or `Menu`. Do not iterate over items and build `Button` views manually.

---

## Adding a new action

When a new context menu or swipe action is needed that does not exist as a factory method:

1. Add a new `static func` to the `SidebarMenuItem` extension in `SidebarMenuItem.swift`
2. Choose a symbol from the canonical action symbol table in [Iconography](../foundations/iconography)
3. Set `role: .destructive` if the action is irreversible
4. Use the new factory method everywhere — do not create the `SidebarMenuItem` inline

---

## Related

- [Header Actions](./header-actions) — `HeaderActionMenuButton` uses `SidebarMenuItem` items
- [Menus and Shortcuts](../patterns/menus-and-shortcuts) — full context menu and swipe action rules
- [Iconography](../foundations/iconography) — canonical SF Symbol assignments
