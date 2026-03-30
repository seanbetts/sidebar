---
title: Widgets
description: Design conventions for sideBar's home screen and lock screen widgets on iOS.
---

## Purpose

Define how sideBar's widgets should look, behave, and stay current. Widgets are glanceable surfaces — the user is not in the app. Every design decision should serve that constraint.

---

## Widget catalogue

### Home screen widgets

| Widget | Kind | Sizes | Content |
|---|---|---|---|
| Today's Tasks | `TodayTasksWidget` | Small, Medium, Large | Incomplete tasks for today, completion action, add action |
| Task Progress | `TaskCountWidget` | Small | Circular progress ring showing completion ratio |
| Pinned Notes | `PinnedNotesWidget` | Small, Medium, Large | Pinned notes list, create action |
| Saved Sites | `SavedSitesWidget` | Small, Medium, Large | Pinned websites with favicons |
| Pinned Files | `PinnedFilesWidget` | Small, Medium, Large | Pinned files with type icons |

### Lock screen widgets

Twelve static widgets across four content categories, three form factors each:

| Form factor | Family | Pattern |
|---|---|---|
| Circular | `accessoryCircular` | Count + label |
| Rectangular | `accessoryRectangular` | 2-item preview list + overflow indicator |
| Inline | `accessoryInline` | Single text label with count or status |

| Category | Circular | Rectangular | Inline |
|---|---|---|---|
| Tasks | `LockScreenTaskCountWidget` | `LockScreenTaskPreviewWidget` | `LockScreenInlineWidget` |
| Notes | `LockScreenNoteCountWidget` | `LockScreenNotePreviewWidget` | `LockScreenNotesInlineWidget` |
| Sites | `LockScreenSiteCountWidget` | `LockScreenSitePreviewWidget` | `LockScreenSitesInlineWidget` |
| Files | `LockScreenFileCountWidget` | `LockScreenFilePreviewWidget` | `LockScreenFilesInlineWidget` |

---

## Data architecture

Widgets cannot access the app's in-memory state directly. Data flows through a shared App Group UserDefaults container that the main app writes to and the widget extension reads from.

```
Main app (writes on data change)
  ↓ App Group UserDefaults
Widget extension (reads on timeline generation)
  ↓
TimelineProvider → Widget views
  ↓ (on user action)
AppIntent → optimistic write to UserDefaults
  ↓ pending operation record
Main app (processes on next launch or active state)
```

**`WidgetDataManager.shared`** is the single access point for all widget data reads and writes in both directions.

### Data models

Widgets use lightweight Codable structs separate from the main app's full models:

| Model | Key fields |
|---|---|
| `WidgetTask` | id, title, isCompleted, completedAt, projectName, groupName, deadline (yyyy-MM-dd) |
| `WidgetNote` | id, name, contentPreview, path, modifiedAt, pinned, pinnedOrder |
| `WidgetWebsite` | id, title, url, domain, faviconUrl, faviconR2Key, pinned, pinnedOrder |
| `WidgetFile` | id, filename, path, sizeBytes, pinned, category, mimeType, recommendedViewer |

---

## Refresh strategy

### Tasks: smart timeline boundaries

The task widget generates up to 5 timeline entries with boundary dates derived from the data:

1. An immediate entry for the current time
2. A boundary at `completedAt + 1.25s` for each completed task (removes it from the list)
3. A boundary at midnight after each task's deadline (marks it overdue)
4. Always a boundary at next midnight

Refresh policy: `.after(lastBoundary + 15 minutes)`.

This means the widget responds to task completions and deadline crossings without waiting for a system-scheduled refresh.

### Notes, files, websites: fixed interval

These widgets use a fixed `.after(now + 15 minutes)` refresh policy. There are no in-widget user actions that modify this data, so smart boundaries are not needed.

### Unauthenticated state

All providers fall back to `.after(nextMidnight())` when the user is not authenticated. No data is displayed.

### Targeted reloads from main app

When the main app writes new data, it calls `WidgetCenter.shared.reloadTimelines(ofKind:)` with the affected widget kind. This triggers an immediate timeline regeneration outside the system schedule.

---

## Display limits

| Family | Max items |
|---|---|
| `systemSmall` | 3 |
| `systemMedium` | 3 |
| `systemLarge` | 8 (7 for websites, to accommodate favicons) |
| `accessoryRectangular` | 2 + overflow indicator |

Items beyond the limit are summarised as "+N more" in the widget footer.

---

## Visual design

### Container background

All widgets use `.containerBackground(.fill.tertiary, for: .widget)`. Do not use custom backgrounds.

### Layout structure

All home screen widgets use `WidgetListLayout` — a generic three-slot layout with header, list, and optional footer:

```
WidgetListLayout
├─ WidgetHeaderView (logo + title + item count, links to section deep link)
├─ List content (VStack of rows)
└─ Footer (overflow indicator, optional)
```

### Typography

| Context | Style |
|---|---|
| Widget header title | `.headline` (`.subheadline` for small when title reduces) |
| Header count badge | `.subheadline`, `.fontWeight(.medium)`, secondary |
| List item title (small/medium) | `.caption` |
| List item title (large) | `.subheadline` |
| List item subtitle | `.caption2` |
| Lock screen circular count | `.system(size: 22, weight: .bold, design: .rounded)` |
| Lock screen circular label | `.system(size: 8)`, `.textCase(.uppercase)` |
| Lock screen rectangular rows | `.caption` |

These do not use `appFont()` — widget typography uses system font directly because widget rendering modes affect font rendering differently from the main app.

### Color and rendering modes

Widgets support three rendering modes. Use `.widgetAccentable()` on elements that should pick up the user's chosen accent colour in tinted mode.

| Mode | Treatment |
|---|---|
| `.fullColor` | Full app colors — light: white bg/black icon, dark: black bg/white icon for action buttons |
| `.accented` | Tertiary fill with `.widgetAccentable()` for accent elements |
| `.vibrant` | System-managed for lock screen; no custom color overrides |

### Action buttons (add/create)

Circular button, 20pt diameter on small, 24pt on medium/large. Rendering-mode-aware fill and icon color (see above). On iOS 17+, backed by an `AppIntent`. Below iOS 17, a deep link.

### Signed-out state

**Home screen**: Centred layout — `person.crop.circle.badge.exclamationmark` icon (32pt), "Sign in to sideBar" headline, content-specific subtitle ("to see your tasks", etc.).

**Lock screen**: Single row — section icon + "Sign in to sideBar" label.

No data is shown. No action is provided beyond the implicit tap-to-open.

---

## Interactivity and optimistic updates

### App Intents

Interactive actions use `AppIntent` (iOS 17+) with deep link fallback for earlier versions:

| Intent | Action |
|---|---|
| `CompleteTaskIntent` | Mark task complete with immediate optimistic update |
| `AddTaskIntent` | Record pending operation, open app to new task |
| `CreateNoteIntent` | Record pending operation, open app to new note |
| `QuickSaveIntent` | Save URL to pending share queue |
| `OpenScratchpadIntent`, `StartChatIntent` | Deep link to section |

### Optimistic update pattern

When a user completes a task from the widget:

1. `CompleteTaskIntent.perform()` updates the task's `isCompleted` state and progress counters in UserDefaults immediately
2. The task shows with a checkmark and strikethrough styling
3. After 1.25 seconds (the completion display duration), the smart timeline boundary fires and the task disappears from the list
4. Simultaneously, a pending operation is recorded in UserDefaults
5. When the main app becomes active, it reads the pending operations and syncs the completion to the backend via `WriteQueue`

The widget never waits for the network. The optimistic update is the user's confirmation.

### Deep link routes

| Section | List | Item |
|---|---|---|
| Tasks | `sidebar://tasks/today` | — |
| Notes | `sidebar://notes` | `sidebar://notes/{path}` |
| Websites | `sidebar://websites` | `sidebar://websites/{id}` |
| Files | `sidebar://files` | `sidebar://files/{id}` |

---

## Favicon handling

Website favicons are fetched asynchronously during timeline generation. The resolution order:

1. R2 CDN public base URL (if configured in UserDefaults)
2. R2 endpoint + bucket path (if configured)
3. Direct `faviconUrl` from metadata (absolute URL)
4. `faviconUrl` resolved relative to the site domain
5. Standard `/favicon.ico` path

Maximum favicon size: 512KB. Failed fetches fall back to a `globe` SF Symbol.

Favicons are fetched fresh on every timeline generation. There is no disk cache.

---

## Rules summary

1. **Every element must be glanceable.** The user is not in the app. If it requires reading, it is probably too much.
2. **Show the most actionable content.** Tasks sort overdue first, then by earliest deadline. Pinned items appear because the user explicitly signalled they are important.
3. **Never block on network.** All data comes from the App Group cache. Show stale data rather than a loading state — the 15-minute cadence and targeted reloads keep it fresh enough.
4. **Optimistic actions feel instant.** Task completion updates the widget immediately. No spinner, no delay, no waiting for the server.
5. **Honest empty states.** Never pretend there is content when there is none. Provide a purposeful empty state — positive for tasks ("All done!"), actionable for notes (create affordance).

---

## Related docs

- [iOS Conventions](./ios-conventions)
- [Wait UX](../patterns/wait-ux)
- [Feedback and Haptics](../patterns/feedback-and-haptics)
- [Implementation Gaps](../implementation-gaps)
