---
title: Widgets
description: Design conventions for sideBar's home screen and lock screen widgets across iOS and macOS.
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

Widgets cannot access the app's in-memory state directly. Data flows through a shared App Group store. The main app writes snapshots on data changes, and the widget extension reads them on timeline generation. When the app is closed, providers can also refresh directly from the backend using a cache-first, best-effort model.

```
Main app (writes on data change)
  ↓ App Group store
Widget extension (reads on timeline generation)
  ├─ Snapshot fresh? → render from cache
  └─ Snapshot stale + auth available? → best-effort backend fetch
       ├─ Success → update cache, render refreshed data
       └─ Failure → render from cache (no blank widgets)
  ↓
TimelineProvider → Widget views
  ↓ (on user action)
Widget interaction
  ├─ Section or row tap → open app via deep link
  ├─ Add/create action → record pending operation, open app
  └─ Task completion → optimistic App Group update
       ├─ Best-effort direct backend write
       │    ├─ Success → clear pending completion
       │    └─ Failure → keep pending completion for app recovery
       └─ pending completion record
Main app (processes pending operations on next launch or active state)
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

### Cache-first provider refresh

Every provider follows the same high-level sequence on timeline generation:

1. Load the cached snapshot from the App Group store.
2. Check whether the snapshot is stale using `lastUpdated`.
3. If the snapshot is fresh, render from cache immediately.
4. If the snapshot is stale and the extension has valid auth, perform a bounded backend fetch.
5. If the fetch succeeds, persist the refreshed snapshot back to the App Group store and render.
6. If the fetch fails, render from cache. Never blank a widget because a refresh failed.

This model keeps widgets useful when the app is closed (particularly on macOS, where the app may not run for long periods) without requiring helper processes, login items, or widget push notifications.

### Staleness thresholds

| Content type | Stale after |
|---|---|
| Tasks | 5 minutes |
| Notes | 15 minutes |
| Websites | 15 minutes |
| Files | 15 minutes |

Tasks use a tighter threshold because they are the most time-sensitive and the only mutating widget. The others are display-only surfaces.

A provider should make at most one bounded fetch attempt per timeline build. No retry loops.

### Tasks: smart timeline boundaries

The task widget generates up to 5 timeline entries with boundary dates derived from the data:

1. An immediate entry for the current time
2. A boundary at `completedAt + 1.25s` for each completed task (removes it from the list)
3. A boundary at midnight after each task's deadline (marks it overdue)
4. Always a boundary at next midnight

Refresh policy: `.after(lastBoundary + 15 minutes)`.

This means the widget responds to task completions and deadline crossings without waiting for a system-scheduled refresh.

### Notes, files, websites: age-based interval

These widgets use a data-aware `.after(...)` refresh policy derived from the snapshot age:

1. If the snapshot is fresh, refresh at `lastUpdated + 15 minutes`
2. If the snapshot is already stale and a refresh attempt fails, back off by one 15-minute window from `now`
3. If the widget is signed out and has no cached snapshot, refresh again at next midnight

These widgets are still display-only surfaces, so they do not need per-item smart boundaries like tasks.

### Unauthenticated state

If no cached snapshot exists and the widget cannot authenticate, providers fall back to `.after(nextMidnight())` and render the signed-out state.

If a cached snapshot exists, providers should continue to render it even when live auth is unavailable. Lack of auth should not blank a widget that still has useful cached content.

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

When `showsWidgetContainerBackground == false` on `WidgetFamily.systemSmall`, treat the widget as a StandBy/CarPlay style surface rather than reusing the dense home-screen layout. Remove header chrome, use fewer items, and scale up the primary text.

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

### StandBy treatment

StandBy and CarPlay reuse the small system widget with the background removed and scaled up. For the tasks widget:

- Detect this context with `showsWidgetContainerBackground == false` on `WidgetFamily.systemSmall`.
- Show at most 2 tasks.
- Remove the standard header row and replace it with a large, distance-readable title treatment.
- Use larger, heavier task typography than the home-screen small widget.
- Keep the layout high-contrast and glanceable. Do not introduce custom background colors when the system removes the container background.

### Signed-out state

**Home screen**: Centred layout — `person.crop.circle.badge.exclamationmark` icon (32pt), "Sign in to sideBar" headline, content-specific subtitle ("to see your tasks", etc.).

**Lock screen**: Single row — section icon + "Sign in to sideBar" label.

This state is only shown when there is no cached snapshot to render. If cached content exists, keep showing it rather than replacing it with the signed-out state. No action is provided beyond the implicit tap-to-open.

### Gallery previews

Widget gallery previews come from the provider preview path, not from a separate static image asset. Each provider should return family-aware sample data when WidgetKit requests a preview snapshot so the gallery reflects the actual information density of that widget size.

- `systemSmall` and `systemMedium` previews should show the compact 3-item layout used in production.
- `systemLarge` previews should use a denser sample set so the gallery demonstrates the larger layout instead of reusing the small preview payload.
- `accessoryRectangular` task previews should show exactly 2 items with overflow count potential.
- Preview data should stay realistic and current. Use curated sample content and future-relative dates for task deadlines rather than stale hard-coded examples.

### Task widget configuration

The task widget family uses an App Intent-backed configuration surface rather than a static widget configuration:

- Home screen task widgets and lock-screen task widgets share the same task-selection intent.
- Supported task scopes are `Today`, a specific project, or a specific group.
- Project and group choices should come from live task catalogs, not hard-coded strings, so the widget configuration UI stays aligned with the user’s current task model.
- Scoped task widgets should deep link back into the matching project or group in the app instead of always opening the generic Today view.

### Non-task widget configuration

The notes, websites, and files widget families now use App Intent-backed configuration surfaces across both home-screen and lock-screen variants:

- Notes widgets support `All pinned notes` and a specific notes folder. Folder choices come from the live notes tree rather than a static list.
- Website widgets support `All saved websites` and a specific saved-site domain. Domain choices come from the live websites list and act as the current widget-level collection proxy until first-class website collections exist in the product model.
- File widgets support `All pinned files` and a specific file category using the same category vocabulary as the files panel.
- Non-task selections currently deep link back to the owning workspace root rather than a scoped in-app filter route. The widget content itself remains filtered to the configured selection.

---

## Interactivity and optimistic updates

### Widget interactions

Interactive actions use `AppIntent` (iOS 17+) with deep link fallback for earlier versions where needed:

| Interaction | Action |
|---|---|
| `CompleteTaskIntent` | Mark task complete with immediate optimistic update and best-effort backend sync |
| `AddTaskIntent` | Record pending operation, open app to new task |
| `CreateNoteIntent` | Record pending operation, open app to new note |
| Section tap or row tap | Open app to the relevant list or item deep link |

Legacy app shortcuts such as `OpenScratchpadIntent` and `StartChatIntent` are outside the active widget surface and should not shape widget architecture decisions.

### Optimistic update pattern

When a user completes a task from the widget:

1. `CompleteTaskIntent.perform()` records a pending completion in the App Group store.
2. The task's `isCompleted` state and progress counters are updated in the store immediately.
3. The task shows with a checkmark and strikethrough styling.
4. After 1.25 seconds (the completion display duration), the smart timeline boundary fires and the task disappears from the list.
5. The intent attempts a direct backend completion write from the widget extension using the existing task API.
6. If the write succeeds, the pending completion is cleared and a timeline reload is requested.
7. If the write fails, the pending completion stays in the store. When the main app becomes active, it reads pending operations and replays the completion through the normal task completion or direct apply path.

The widget never waits for the network to update the UI. The optimistic local update is the user's confirmation. The direct backend write improves cross-device sync when the app is closed, with app-side recovery as fallback.

### Task refresh reconciliation

When the tasks provider refreshes from the backend, it must merge server data with any pending widget completions that have not yet been cleared. Without this, a just-completed task can reappear in the widget if the server snapshot arrives before the completion syncs.

### Deep link routes

| Section | List | Item |
|---|---|---|
| Tasks | `sidebar://tasks/today` | — |
| Notes | `sidebar://notes` | `sidebar://notes/{path}` |
| Websites | `sidebar://websites` | `sidebar://websites/{id}` |
| Files | `sidebar://files` | `sidebar://files/{id}` |

Widget create actions use:

- Tasks: `sidebar://tasks/new`
- Notes: `sidebar://notes/new`

---

## Favicon handling

Website favicons are fetched asynchronously during timeline generation. The resolution order:

1. R2 CDN public base URL (if configured in UserDefaults)
2. R2 endpoint + bucket path (if configured)
3. Direct `faviconUrl` from metadata (absolute URL)
4. `faviconUrl` resolved relative to the site domain
5. Standard `/favicon.ico` path

Maximum favicon size: 512KB. Failed fetches fall back to a `globe` SF Symbol.

Fetched favicons are persisted in a lightweight disk cache keyed by website ID and reused across timeline generations. Uncached websites still fetch on demand.

---

## Rules summary

1. **Widgets are available to all users, including free tier.** Widgets surface notes, tasks, websites, and files, which are not subscription-gated. No subscription check is needed for widget rendering or interaction.
2. **Every element must be glanceable.** The user is not in the app. If it requires reading, it is probably too much.
2. **Show the most actionable content.** Tasks sort overdue first, then by earliest deadline. Pinned items appear because the user explicitly signalled they are important.
3. **Cache-first, always.** Show cached data immediately. Best-effort provider refresh improves freshness when the app is closed, but never blocks rendering. Show stale data rather than a loading state.
4. **Optimize background-removed small widgets for distance.** In StandBy and CarPlay, prefer fewer items, larger type, and less chrome over feature parity with the home-screen layout.
5. **Optimistic actions feel instant.** Task completion updates the widget immediately. No spinner, no delay, no waiting for the server.
6. **Honest empty states.** Never pretend there is content when there is none. Provide a purposeful empty state — positive for tasks ("All done!"), actionable for notes (create affordance).

---

## Related docs

- [iOS Conventions](./ios-conventions)
- [Wait UX](../patterns/wait-ux)
- [Feedback and Haptics](../patterns/feedback-and-haptics)
- [Implementation Gaps](../implementation-gaps)
