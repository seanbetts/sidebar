---
title: Navigation
description: Navigation architecture, layout selection, detail presentation patterns, and deep linking for sideBar across iPhone, iPad, and Mac.
---

## Purpose

Document the navigation system — how layout is selected per platform, how sections and detail views are presented, and the rules that govern adding new destinations. The navigation architecture is one of the most complex parts of the codebase. This doc is the map.

---

## Layout selection

`ContentView` selects between two layout families based on platform and size class:

```
macOS                    → WorkspaceLayout (split)
iOS + compact width      → TabView (compact)
iOS + regular width      → WorkspaceLayout (split)
```

Compact width means iPhone in all orientations. Regular width means iPad (all orientations) and macOS. The decision is made in `ContentView+Layout.swift` via `horizontalSizeClass`.

---

## Compact layout (iPhone)

The root is a `TabView` with a system bottom tab bar. Five visible positions:

| Tab | Section |
|---|---|
| 1 | Chat |
| 2 | Notes |
| 3 | Tasks |
| 4 | Websites |
| 5 | More (→ Files, Skills Store) |

The primary four sections are direct tabs. Files and Skills Store live behind a "More" overflow tab.

Each tab wraps its content in a `NavigationStack`. The stack has no path binding at the root — depth is at most one level, controlled by `navigationDestination(item:)` bindings in `NavigationCoordinator`:

| State | Controls |
|---|---|
| `NavigationCoordinator.notesPhoneDetailRouteId` | Notes detail push |
| `NavigationCoordinator.tasksPhoneDetailRouteId` | Tasks detail push |

Setting these to a non-nil value pushes the detail view. Setting to `nil` pops back to the list. No manual `NavigationPath` management — these bindings are the entire phone navigation stack.

The "More" tab uses a `NavigationStack` with a path binding (`compactPhoneMoreNavigationPath`) to push section views one level deep.

**Max navigation depth on iPhone: 2 levels** (tab root → section list → detail). No deeper pushes.

### iPhone floating chrome

The iPhone compact layout adds two floating surfaces above the tab bar:

- **`PhoneFloatingActionDock`** — section-specific create actions, trailing-aligned above tab bar
- **Search dock** — floating search field, dismisses on selection or outside tap

These are always rendered at the `ContentView` level, not inside individual tabs.

---

## Split layout (iPad and Mac)

Three-column workspace with no `NavigationStack`:

| Rail | Left Panel | Main Content | Right Sidebar |
|---|---|---|---|
| 56px | 280px | flexible | 280–480px (optional) |

All navigation is state-driven through `WorkspaceStore`. There is no push/pop — content swaps in place when the state changes.

### Rail and left panel

`SidebarRail` drives section selection via `WorkspaceStore.selectSection(_:)`. Tapping the same section twice toggles the left panel. Sections that have no list view (Skills Store) collapse the left panel automatically.

Left panel visibility is computed from two conditions: `isLeftPanelExpanded` AND the selected section supports a panel. It is not user-resizable — 280px fixed.

### Main content and right sidebar

Content is described by `WorkspaceContentDescriptor` — a typed value that identifies what view to render. The workspace has two panes:

| Pane | Descriptor | Typical content |
|---|---|---|
| Primary | `primaryPane.descriptor` | Notes editor, chat view, task detail, file viewer |
| Secondary | `secondaryPane.descriptor` | Scratchpad, related content, agent surfaces |

Dispatching `WorkspaceStore.setPrimaryContent(_:)` or `setSecondaryContent(_:)` swaps the view. Panes can be swapped, resized, or closed independently.

The right sidebar is user-resizable (280–480px, snap points at 360/420/480/half-width) and persists its width via `@AppStorage`.

### State management

| Type | Role |
|---|---|
| `WorkspaceStore` | Central reducer — section selection, pane content, layout mode |
| `NavigationCoordinator` | Keyboard shortcuts, command routing, pending deep-link flags |
| `NavigationState` | Persisted preferences — last section, sidebar width |

All workspace navigation dispatches actions to `WorkspaceStore`. Do not modify workspace state directly — always dispatch an action.

---

## Detail presentation patterns

Three patterns are used depending on context:

### 1. State-driven descriptor swap (iPad/Mac)

Used for all primary and secondary pane content changes. No animation or transition — view swaps in place.

```swift
workspaceStore.dispatch(.setPrimaryContent(descriptor))
```

**Use for**: Opening notes, tasks, files, websites, chat conversations on iPad/Mac.

### 2. `navigationDestination(item:)` (iPhone)

Used for pushing detail views within a `NavigationStack` on iPhone.

```swift
// Set to push
environment.notesPhoneDetailRouteId = noteId

// Set to nil to pop
environment.notesPhoneDetailRouteId = nil
```

**Use for**: Note detail, task detail on iPhone. The binding clears automatically when the user navigates back.

### 3. `.sheet` (modal, all platforms)

Used for surfaces that are contextually separate from the main navigation flow.

| Surface | Trigger |
|---|---|
| Settings | Profile avatar button (all layouts) |
| Scratchpad | Scratchpad button, left of profile avatar (all layouts) |
| Write conflict resolution | Automatic, when conflict detected |
| Keyboard shortcuts reference | Keyboard shortcut or menu item |
| Onboarding | `fullScreenCover` on first launch only |

**Rule**: `.sheet` is for surfaces that are not part of the section hierarchy. Do not present section content as a sheet — use the descriptor swap on iPad/Mac and `navigationDestination` on iPhone.

---

## Settings navigation

### iOS and iPadOS

Settings is presented as a `.sheet` from the profile avatar button. The sheet root is `SettingsTabsView`, a `TabView` with five tabs:

| Tab | Content |
|---|---|
| Profile | Profile editing, account actions |
| User | Preferences, date of birth |
| Agent | Agent behaviour, memory settings |
| Skills | Installed skills list |
| Subscription | Current plan, billing, upgrade/downgrade (see [Subscription](../patterns/subscription)) |
| More | Memories browser, app settings, about |

The More tab contains a `NavigationStack` with `NavigationLink` for sub-pages:

| Level | View |
|---|---|
| Root | Memories browser, App settings |
| Level 1 | Individual memory detail, app settings detail |

Max depth inside settings is 2 levels. This is the only context where `NavigationLink` is used for settings-internal navigation.

Nested `.sheet` presentations within settings:
- **Skill config detail** — `.sheet(item: $selectedStoreSkill)`, wrapped in `NavigationStack`
- **Date of birth picker** — `.sheet(isPresented:)`, wrapped in `NavigationStack`
- **Queued changes** — `.sheet(isPresented:)`, wrapped in `NavigationStack`

### macOS

Same `.sheet` trigger and same `SettingsTabsView` structure, but the sheet is wrapped in `MacModalShell` for appropriate window sizing and chrome. Platform-specific implementations:

- `SettingsSections+SystemMac.swift` overrides sections that differ on macOS
- `SettingsMacStyles.swift` provides macOS-specific layout modifiers
- `SettingsMacPlainTextEditor` replaces `SettingsIOSPlainTextEditor` for multi-line text inputs

The tab structure, NavigationStack depth, and nested `.sheet` rules are identical to iOS.

### Web

Settings is a dedicated `/settings` route. Section selection updates the URL (e.g. `/settings/agent`) so the browser back button works and direct links to setting sections are bookmarkable. Web sections align with the native tab structure where possible:

| Web section | Native equivalent |
|---|---|
| Account | Profile |
| User | User |
| Agent | Agent |
| Skills | Skills |
| Subscription | Subscription |

---

**Rule**: Do not add further navigation depth to native settings. New settings sub-pages should be `NavigationLink` destinations within the existing stack. New contextual detail (skill config, pickers) should use the nested `.sheet` pattern already established.

---

## Scratchpad

The scratchpad is presented as a `.sheet` on all layouts. The trigger button appears in the navigation bar or header of every section that shows the profile/settings avatar, positioned immediately to its left.

---

## Deep links

URL scheme: `sidebar://`

| URL | Action |
|---|---|
| `sidebar://chat` | Navigate to Chat |
| `sidebar://notes` | Navigate to Notes |
| `sidebar://notes/new` | Navigate to Notes, trigger new note |
| `sidebar://notes/{noteId}` | Navigate to Notes, open specific note |
| `sidebar://tasks` | Navigate to Tasks |
| `sidebar://tasks/today` | Navigate to Tasks, select Today view |
| `sidebar://tasks/new` | Navigate to Tasks, trigger new task |
| `sidebar://websites/{websiteId}` | Navigate to Websites, select website |
| `sidebar://files/{fileId}` | Navigate to Files, select file |
| `sidebar://scratchpad` | Open scratchpad |

Deep links are handled in `AppEnvironment+DeepLink.swift`. On iPhone they set `NavigationCoordinator` phone detail route IDs and select the appropriate tab. On iPad/Mac they dispatch workspace store actions.

**Rule**: All new deep link destinations must be handled in `AppEnvironment+DeepLink.swift`. Do not handle URL routing inline in views.

---

## Adding a new section

Adding a new top-level section requires changes in multiple places. The checklist:

1. Add a case to `AppSection`
2. Add a tab entry to `ContentView+CompactPhoneTabs.compactPhoneBottomTabSections` (or overflow)
3. Add a `SidebarRail` button
4. Register the left panel view in `WorkspaceBuiltInSectionRegistry`
5. Register the detail descriptor and content view
6. Add a deep link handler in `AppEnvironment+DeepLink.swift`
7. Add to the Lucide → SF Symbols mapping if a new icon is needed

**Rule**: A section that exists on iPad/Mac must also exist on iPhone. The tab bar and rail must stay in sync.

---

## Rules summary

1. **No NavigationStack on iPad/Mac.** All navigation is state-driven via `WorkspaceStore`.
2. **Max depth 2 on iPhone.** Tab root → list → detail. No deeper pushes.
3. **Use the three presentation patterns correctly.** Descriptor swap for workspace panes, `navigationDestination` for iPhone detail, `.sheet` for modal surfaces.
4. **All workspace navigation through `WorkspaceStore`.** Dispatch actions — do not mutate state directly.
5. **`.sheet` is not for section content.** Sheets are for settings, scratchpad, and system dialogs.
6. **Deep links handled in `AppEnvironment+DeepLink.swift` only.** No inline URL routing in views.
7. **Tab bar and rail must stay in sync.** Every section that appears in one must appear in the other.

---

## Related docs

- [iOS Conventions](../platform-strategy/ios-conventions)
- [macOS Conventions](../platform-strategy/macos-conventions)
- [Components](../components/overview)
- [Implementation Gaps](../implementation-gaps)
