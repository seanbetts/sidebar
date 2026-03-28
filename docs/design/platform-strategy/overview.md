---
title: Platform Strategy Overview
description: Draft cross-platform strategy for keeping sideBar coherent across iPhone, iPad, Mac, and web.
---

- Status: drafted
- Owner: AI coding agent
- Inputs needed: codebase inspection (complete), Sean's platform priorities
- Outputs: this doc + ios-conventions.md + macos-conventions.md + web-conventions.md
- Dependencies: principles.md, system-inheritance.md
- Codebase review required: yes (complete)
- Human judgement required: yes - Sean to confirm platform differentiation intent

---

## Purpose

Define how sideBar should behave and feel differently across iPhone, iPad, Mac, and web, while remaining one coherent product.

---

## Core rule

**One mental model. Platform-appropriate behaviour.**

Users should always recognise sideBar regardless of which platform they are on:
- The same six sections (Chat, Notes, Tasks, Websites, Files, Skills Store)
- The same workspace concept with panels and split views
- The same assistant with the same identity and capabilities
- The same data, settings, and state

But the way they interact with it should match the platform:
- iPhone: compact, direct, touch-first, single-focus
- iPad: workspace mode, multitasking, keyboard + touch
- Mac: keyboard-first, menus, windows, pointer precision
- Web: browser-native, cross-platform accessible, same mental model without pretending to be native

---

## What is shared across all platforms

| Element | Notes |
|---|---|
| Section structure | Chat, Notes, Tasks, Websites, Files, Skills Store |
| Product voice and copy | Same labels, error messages, empty states |
| Feature set | Core features available on all platforms |
| Data model | Synced via Supabase |
| Assistant identity | Same assistant, same soul and identity |
| DesignTokens | Spacing, radius, color semantics |
| Typography scale | Same base sizes, same scaling system |
| SF Symbols | Same icon vocabulary |

---

## What intentionally differs by platform

| Element | iPhone | iPad | Mac | Web |
|---|---|---|---|---|
| Navigation | TabView | SidebarRail + WorkspaceLayout | SidebarRail + WorkspaceLayout + native menu bar | TBD |
| Layout | Compact, single column | Multi-column workspace | Multi-column workspace, multiple windows | TBD |
| Settings | Sheet | Sheet or sidebar panel | Dedicated window | TBD |
| Create actions | Floating action dock (Liquid Glass) | Toolbar buttons | Toolbar buttons + keyboard shortcuts | TBD |
| Search | Floating search dock | Inline panel search | Inline panel search | TBD |
| Rich text editor | UIKit surface | UIKit surface | AppKit surface | TBD |
| Context menus | Long press (touch) | Long press + right click | Right click + keyboard | TBD |
| Keyboard shortcuts | Limited | Extended | Full | TBD |

---

## Platform tiers

### Tier 1: iPhone

The most constrained context. One panel at a time. Thumb-friendly. Quick task completion. Compact navigation.

sideBar on iPhone should feel direct and fast. The tab bar is the primary navigation. The floating action dock and search dock are distinctive iPhone-native patterns. The workspace model is collapsed to a single active section.

### Tier 2: iPad

The workspace model shines on iPad. Two panels side by side, resizable. Keyboard supported. External display supported. The sidebar rail is always visible. Multitasking contexts (Slide Over, Split View) need to be considered.

iPad should feel like a real working environment, not a scaled-up iPhone.

### Tier 3: Mac

The Mac is sideBar's most capable platform. Keyboard shortcuts, native menus, window management, multiple windows, pointer precision, and the dock and menu bar are all available. The workspace model maps well to the Mac paradigm.

Mac should feel like a real Mac app: keyboard-first, menu-driven, and window-aware.

### Tier 4: Web

The web app should preserve the same mental model as the native apps. It should not pretend to be a native Apple app. It should use browser-native patterns for navigation, input, and accessibility. The same sections and capabilities should be accessible.

**Note**: The web app was not inspected in this audit. Web conventions are to be defined based on separate inspection of the frontend codebase.

---

## Navigation model by platform

### iPhone navigation stack

```
ContentView (compact)
  TabView
    Chat tab -> NavigationStack -> ChatView -> ChatDetailView
    Notes tab -> NavigationStack -> NotesView -> NotesDetailView
    Tasks tab -> NavigationStack -> TasksView -> TasksDetailView
    Websites tab -> NavigationStack -> WebsitesView -> WebsitesDetailView
    Files tab -> NavigationStack -> FilesView -> FilesDetailView
    More tab -> NavigationStack -> [SkillsStore, Settings, ...]
  SearchDock (floating, above tab bar)
  FloatingActionDock (trailing, above tab bar, section-specific)
```

### iPad and Mac layout stack

```
ContentView (regular/macOS)
  WorkspaceLayout
    SidebarRail (56px, left edge)
    Left panel (variable width, section list)
    Divider (8px, drag-to-resize)
    Main content (detail view, current selection)
    [Right sidebar] (optional, second content column, workspace mode)
```

---

## Input model summary

| Input type | iPhone | iPad | Mac | Web |
|---|---|---|---|---|
| Touch | Primary | Primary + pointer | None | None |
| Pointer / mouse | None | Secondary | Primary | Primary |
| Keyboard | Software keyboard | Software + hardware | Hardware (primary) | Hardware |
| Gestures | Tap, swipe, long press | Same + multitouch | None (no touch) | Limited |
| Keyboard shortcuts | App-level only | Extended | Full | Browser-level |
| Context menus | Long press | Long press + right click | Right click | Browser context |
| Drag and drop | Limited | Supported | Supported | Browser |

---

## Layout breakpoints

sideBar uses SwiftUI's `horizontalSizeClass` as the primary layout breakpoint:

- **Compact** (`horizontalSizeClass == .compact`): iPhone portrait, iPhone landscape on small phones. TabView layout.
- **Regular** (`horizontalSizeClass == .regular`): iPad all orientations, Mac, iPhone landscape on large phones (some). WorkspaceLayout.

macOS is always regular.

No custom numeric breakpoints are used. The two-state compact/regular model is the current design.

---

## Shared product rules (apply everywhere)

1. The six sections are always accessible. Routing to any section from anywhere in the app should be possible.
2. Settings is always accessible from the current platform's standard location (tab, sidebar button, menu).
3. Empty states give the user a clear next action.
4. The assistant is always available from Chat.
5. Create actions for each section are always accessible without navigating away from the section.

---

## Open questions

- Should iPad have a distinct navigation model from Mac, or should they always share WorkspaceLayout?
- Should the right sidebar be available on iPhone in some contexts (e.g. large iPhone in landscape)?
- What is the Web platform's current state and what conventions should it follow?

---

## Related docs

- `platform-strategy/ios-conventions.md`
- `platform-strategy/macos-conventions.md`
- `platform-strategy/web-conventions.md`
- `principles.md`
- `system-inheritance.md`
