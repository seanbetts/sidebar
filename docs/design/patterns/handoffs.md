---
title: Handoffs
description: How sideBar receives and processes external context — share extension saves, widget intents, deep links, Spotlight, and push notifications.
---

| Field | Value |
|---|---|
| Status | approved |
| Owner | ios |
| Outputs | this doc |
| Dependencies | [ios-conventions](../platform-strategy/ios-conventions), [authentication](./authentication), [wait-ux](./wait-ux) |

## Purpose

Define how sideBar handles incoming context from outside the main app process — share extensions, Safari extensions, widgets, Spotlight, push notifications, and URL scheme deep links. These are referred to collectively as handoffs. Each handoff type has a consistent contract: queue if the app is not ready, drain when it is, never silently drop.

---

## Handoff types

| Type | Entry point | Trigger | Auth required |
|---|---|---|---|
| Extension save | `ExtensionEventStore` / `PendingShareStore` | Share or Safari extension records a save | Active |
| Widget intent | `WidgetDataManager` | Widget button tap (add task, add note, complete task) | Active |
| Deep link | `onOpenURL` / `scene(_:openURLContexts:)` | URL scheme link from any source | None |
| Spotlight | `scene(_:continue:)` with `NSUserActivity` | User taps a Spotlight search result | None |
| Push notification | `didReceiveRemoteNotification` | Server-sent remote notification | Active |

---

## Extension saves

Website saves from the Share extension and Safari extension are the most complex handoff type because they originate in a separate process and may arrive while the app is backgrounded, locked, or signed out.

### Two-path save model

Saves arrive via one of two paths depending on how much the extension was able to process:

| Path | Content | When used |
|---|---|---|
| Direct save | Full metadata (title, content, reading time, etc.) stored in `ExtensionEventStore` | Extension completed a full save before handing off |
| URL queue | URL only, stored in `PendingShareStore` for async processing | Extension queued the save for the main app to process |

Both paths write to App Group UserDefaults so the data survives process termination.

### Queue and drain

When an extension save is recorded, an inter-process notification wakes the main app immediately if it is running. On next foreground entry, the app drains all queued items via `consumeExtensionEvents()` followed by `consumePendingShares()`.

Direct saves are applied immediately to the store. URL-queue items are submitted to the backend, with exponential backoff retry (30s base, max 30 minutes) and a 5-attempt limit before an item is marked as failed.

### URL deduplication

Before inserting a URL-queue item, the app normalises the URL canonically and checks it against already-saved items. Duplicate saves from the extension are discarded rather than inserted.

### Auth gating

All extension save processing is gated on `authState == .active`. Items queued while the app is signed out or loading are retained in `PendingShareStore` and drained after successful sign-in. See [Authentication — Deferred actions](./authentication#deferred-actions).

### Error classification

HTTP errors that indicate a permanent failure (400, 404, 410, 422) skip retry and mark the item as failed immediately. Network errors and server errors (5xx) are retried with backoff. The last error message is stored with the item for display in the UI.

---

## Widget intents

Widgets hand off two categories of intent to the main app: **actions** (create task, create note, complete task) and **navigation** (open a section).

### Action intents

When a user taps an action button in a widget, the intent handler:

1. Records the pending operation in App Group UserDefaults via `WidgetDataManager`
2. Posts an inter-process notification to wake the app
3. Returns a deep link URL (e.g. `sidebar://tasks/today`) for navigation

The main app consumes the pending operation on the next foreground entry or notification receipt, executing the action against the live data store.

### Task completion

Task completion is handled as its own handoff path. The widget records the completion via `WidgetDataManager.recordTaskCompletion(taskId:)`. The main app applies the completion to the store, falling back to a direct API call if the task is not yet loaded locally. Widget data and badge counts are refreshed after completion.

### Deferred execution

If the relevant section is not currently focused when an intent fires, the app sets a deferred flag (`pendingNewTaskDeepLink`, `pendingNewNoteDeepLink`) and executes the action when the section is next brought into focus.

### Auth gating

Widget intent processing is gated on `authState == .active`. Pending operations recorded while the app is signed out are retained and consumed after sign-in.

---

## Deep links

Deep links are the universal navigation primitive. Spotlight results, widget navigation, and push notification taps all convert to `sidebar://` URLs before routing. This means there is one routing implementation for all external navigation.

### URL scheme

`sidebar://` with the following hosts and paths:

| Destination | Path |
|---|---|
| Today tasks | `tasks/today` |
| New task | `tasks/new` |
| Notes list | `notes` |
| New note | `notes/new` |
| Specific note | `notes/{noteId}` |
| Websites list | `websites` |
| Specific website | `websites/{websiteId}` |
| Files list | `files` |
| Specific file | `files/{fileId}` |
| Chat list | `chat` |
| New conversation | `chat/new` |
| Specific conversation | `chat/{chatId}` |
| Scratchpad | `scratchpad` |

### Queuing on launch

Deep links that arrive before the app environment is fully initialised are queued in memory and flushed once the environment is ready. Links are never silently dropped.

### Auth gating

Deep links do not require authentication for the routing decision itself, but links that target content requiring a signed-in state must not route to blank or partially loaded screens. See [Authentication — Deferred actions](./authentication#deferred-actions).

---

## Spotlight

Spotlight search results are indexed for notes, files, and websites. When a user taps a result, the system delivers an `NSUserActivity` to the app via `scene(_:continue:)`. The app extracts the item identifier, converts it to a `sidebar://` deep link, and routes it through the standard deep link handler.

Spotlight indexes are cleared on sign-out so no content is discoverable by a subsequent user on the same device.

---

## Push notifications

Remote notifications serve as a lightweight refresh trigger, not a primary navigation mechanism. On receipt the app:

- Refreshes task counts
- Refreshes the currently selected task if one is open
- Refreshes widget data in parallel (for badge sync)

Device tokens are registered with the backend when auth transitions to `.active` and disabled on sign-out. Tokens are only re-registered if the token or user ID has changed.

---

## Foreground orchestration

Every foreground transition triggers a coordinated drain of all pending handoff data. The sequence on `handleSignedInActivation()` is:

1. Auth refresh (stale session recovery or staleness check)
2. Consume extension events (with pending share replay)
3. Consume widget task completions
4. Consume widget add-task/note intents
5. *(iOS only, after 1s delay)* Consume extension events again (catch items that arrived during step 1–4), force-reload websites, reconcile queue

The delay in step 5 catches extension saves that may have been written to App Group storage between app launch and the first drain.

---

## Outgoing handoffs

Outgoing handoffs are user-initiated actions that send content out of sideBar — to the system share sheet, the clipboard, the Files app, or an external browser. All outgoing handoffs require explicit user action; nothing is shared automatically.

### Share sheet

`SystemSharePresenter` wraps `UIActivityViewController` on iOS and `NSSharingServicePicker` on macOS, providing a single share implementation across platforms.

| Content | What is shared | Available from |
|---|---|---|
| Website URL | Original source URL | Website detail, list, sidebar context menu |
| Website text | Markdown rendered to plain text (frontmatter stripped) | Website detail, list, sidebar context menu |
| Note text | Plain text snapshot of note content | Note detail, list, sidebar context menu |
| File | Binary file (PDF, image, document, etc.) | File detail, sidebar context menu |
| Agent surface | Markdown payload or summary text | Agent workspace surfaces |
| Chat conversation | Full conversation as plain text | Chat conversation view |

### Copy to clipboard

All clipboard operations auto-clear after 30 seconds. This applies on both iOS (`UIPasteboard`) and macOS (`NSPasteboard`).

| Content | Format | Available from |
|---|---|---|
| Website content | Markdown (frontmatter stripped) | Website detail, list, sidebar |
| Website URL | URL string | Website detail, list, sidebar |
| Website title | Plain text | Website detail, list, sidebar |
| Note text | Plain text | Note detail, list, sidebar |
| File content | Plain text | Files sidebar |
| Chat message | Plain text | Chat message row |
| Agent surface | Markdown | Agent workspace surfaces |

### Download (export to Files)

Content can be exported to the Files app via SwiftUI's `fileExporter` modifier. The exported format matches what is most useful outside the app.

| Content | Format | Filename |
|---|---|---|
| Website | `.md` (frontmatter stripped) | Website title |
| Note | Plain text | Note filename |
| File | Original binary | Original filename |
| Agent surface | `.md` | Surface title |

### Open in browser

Website URLs can be opened in two ways:

- **In-app browser** (`SafariView`): tapping a website's title opens the source URL in an embedded Safari view, keeping the user in the app
- **External browser**: "Open in Browser" action hands the URL off to the system default browser via the environment's `openURL`

The in-app browser is the default for title taps. The external browser is an explicit action.

---

## Rules summary

1. **Never silently drop a handoff.** All incoming data — extension saves, widget intents, deep links — must be queued if the app is not ready, and drained when it is.
2. **App Group UserDefaults is the handoff bus.** Extension saves and widget intents write to App Group storage so data survives process termination and is available on next launch.
3. **Deep links are the universal navigation primitive.** Spotlight, widget navigation, and notifications all convert to `sidebar://` URLs before routing. There is one routing implementation.
4. **All data handoffs are gated on `authState == .active`.** Queued items are retained until the user is signed in and active.
5. **URL deduplication is mandatory for extension saves.** Canonical URL matching must run before inserting a queued save.
6. **Retry on transient errors, fail fast on permanent ones.** Network and server errors use exponential backoff. 4xx client errors mark items as permanently failed without retrying.
7. **Sign-out clears all queued handoff data.** No content from a previous session should be processed by a subsequent user on the same device.
8. **Spotlight indexes are cleared on sign-out.** Indexed content must not be discoverable after the owning user signs out.
9. **All outgoing handoffs require explicit user action.** Nothing is shared, copied, or exported automatically.
10. **Clipboard content auto-clears after 30 seconds.** Applies to all copy operations on both iOS and macOS.
11. **Use `SystemSharePresenter` for all share sheet actions.** Never invoke `UIActivityViewController` or `NSSharingServicePicker` directly — use the shared wrapper for consistent cross-platform behaviour.

---

## Related docs

- [Authentication](./authentication)
- [iOS Conventions](../platform-strategy/ios-conventions)
- [Widgets](../platform-strategy/widgets)
- [Wait UX](./wait-ux)
- [Implementation Gaps](../implementation-gaps)
