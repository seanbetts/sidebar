---
title: Platform Strategy Overview
description: Cross-platform strategy for keeping sideBar coherent across iPhone, iPad, Mac, and web.
---

| Field | Value |
|---|---|
| Status | approved |
| Owner | AI coding agent |
| Outputs | this doc + ios-conventions.md + macos-conventions.md + web-conventions.md |
| Dependencies | [principles](../principles), [system-inheritance](../system-inheritance) |

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
| Navigation | TabView | SidebarRail + WorkspaceLayout | SidebarRail + WorkspaceLayout + native menu bar | SidebarRail + WorkspaceLayout |
| Layout | Compact, single column | Multi-column workspace | Multi-column workspace, single window | Multi-column workspace (resizable left panel) |
| Right sidebar | Never | Available (workspace mode) | Available (workspace mode) | Not available |
| Settings | Sheet | Sheet | Sheet (`MacModalShell`) | Dedicated `/settings` route |
| Create actions | Floating action dock (Liquid Glass) | Toolbar buttons | Toolbar buttons + keyboard shortcuts | Section header buttons |
| Search | Floating search dock | Inline panel search | Inline panel search | Inline panel search |
| Rich text editor | UIKit surface | UIKit surface | AppKit surface | Tiptap (browser) |
| Icons | SF Symbols | SF Symbols | SF Symbols | Lucide Svelte |
| Context menus | Long press (touch) | Long press + right click | Right click + keyboard | Right click / dropdown |
| Keyboard shortcuts | Limited | Extended | Full | Cmd/Ctrl + 1–5 (partial) |
| Dark mode | System adaptive | System adaptive | System adaptive | CSS class toggle, localStorage |

---

## Platform priority

### Primary platforms: iPhone, iPad, Mac

These are the first-class platforms for sideBar. All features should be available on all three. The native app experience is the reference point for quality, consistency, and design decisions.

### Secondary platform: Web

The web app exists and has the same section structure (Chat, Notes, Tasks, Websites, Files, Scratchpad, Settings), but has feature drift from the native apps as the iOS and macOS apps have been the primary focus of development. The web app is a second citizen: it should preserve the same mental model and feature parity where practical, but it is not the reference platform.

### Platform character

**iPhone**: The most constrained context. One panel at a time. Thumb-friendly. Quick task completion. Compact navigation. Should feel direct and fast.

**iPad**: Shares the same WorkspaceLayout as Mac. Keyboard and pointer supported. Should feel like a real working environment, not a scaled-up iPhone.

**Mac**: The most capable platform. Keyboard shortcuts, native menus, window management, pointer precision. Should feel like a real Mac app: keyboard-first, menu-driven, window-aware.

**Web**: Should preserve the same mental model without pretending to be a native Apple app. Browser-native patterns for navigation, input, and accessibility.

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
    Left panel (280px fixed, section list)
    Divider (8px)
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

## Related docs

- [iOS Conventions](./ios-conventions)
- [macOS Conventions](./macos-conventions)
- [Web Conventions](./web-conventions)
- [Principles](../principles)
- [System Inheritance](../system-inheritance)
