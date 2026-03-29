---
title: Wait UX
description: How sideBar handles loading, saving, generating, and syncing — the language of waiting across all platforms.
---

| Field | Value |
|---|---|
| Status | draft |
| Owner | both |
| Outputs | this doc |
| Dependencies | [ios-conventions](../platform-strategy/ios-conventions), [web-conventions](../platform-strategy/web-conventions), [components](../components/overview), [feedback-and-haptics](./feedback-and-haptics) |

## Purpose

Loading, syncing, saving, and generating are the moments where users have to trust that sideBar knows what it is doing. If those moments are vague, jumpy, or inconsistent, the app feels unreliable. If they are calm and well-paced, the app feels solid.

This doc defines how sideBar should behave during short delays, long waits, and background work — and how AI generation states should feel distinct from ordinary loading.

---

## Platform scope

| Concern | iOS | macOS | Web |
|---|---|---|---|
| Spinner (`LoadingIndicatorView` / `LoadingGlyph`) | Yes | Yes | Yes |
| Skeleton loading (static, no shimmer) | Yes | Yes | Yes |
| Haptics on wait completion | Yes | No | No |
| Progressive reveal (character-paced) | Yes | Yes | No |
| Progressive reveal (chunk-driven) | No | No | Yes |
| Live Activities | Target | No (completion notification instead) | No |
| Pull-to-refresh | Yes | No | No |

Platform differences are called out inline throughout this doc. Unless noted, a rule applies to all platforms.

---

## Wait state taxonomy

Four categories, each with a different treatment:

| Category | Duration | Treatment |
|---|---|---|
| Instant | Under 150ms | No feedback. Render the result directly. |
| Short | 150ms to 1s | Skeleton or spinner. No message needed. |
| Long | Over 1s | Spinner with a message, or progress bar if determinate. |
| Background | Ongoing, non-blocking | Ambient indicator. Never blocks the UI. |

**Do not show a spinner for an instant response.** A spinner that appears and disappears in under 150ms is more disruptive than nothing. If the result arrives fast enough that a spinner would flash, skip it.

**Do not leave a blank screen for a short wait.** Skeleton loading fills the layout immediately and prevents layout shift when data arrives.

---

## Instant responses

Content that arrives from local cache or local state requires no wait feedback. Render immediately. This includes:

- Opening a note that is already locally stored
- Switching sections in the rail
- Navigating between already-loaded conversations

**Rule**: Never show a spinner for a state change that completes from local data.

---

## Short waits: skeleton loading

### Initial load

Use skeleton loading for all sidebar list panels loading initial data from the network.

Skeleton rows are static — no shimmer animation. Variable row widths create natural variation without motion. Row counts per panel:

| Panel | Rows | Subtitle |
|---|---|---|
| Conversations | 8 | Yes |
| Websites | 8 | Yes |
| Notes | 8 | No |
| Files | 8 | No |
| Memories | 8 | No |

**Native**: `SidebarListSkeleton` — `textTertiary` at 35% opacity, variable widths, no animation.

**Web**: `SidebarLoading` — same static approach. No shimmer animation.

Static skeletons are less distracting, need no reduced-motion exception, and are consistent across platforms.

**Rule**: Use skeleton loading for all list panels on initial load. Do not replace a list with a centred spinner — it causes layout shift and is less informative.

### Refresh states

When a panel already has content and is refreshing (pull-to-refresh on iOS, background revalidation), do not replace visible content with skeletons. The existing content should remain visible.

**iOS**: Use a standard pull-to-refresh control (`refreshable`) at the top of the list. The list content stays visible during the refresh.

**Web**: Background revalidation happens silently after loading from cache. No visible indicator is needed unless the refresh takes unexpectedly long (over 2s), at which case a subtle top-of-list spinner is appropriate.

**Rule**: Skeletons are for initial load only. Never replace visible content with skeletons during a refresh.

---

## Long waits: spinner with message

Use `LoadingIndicatorView` (native) or `LoadingGlyph` (web) with an accompanying message for waits expected to exceed one second, or where the user has no prior content to look at.

Both components share the same size scale:

| Size | Value | Use |
|---|---|---|
| `inline` | 16px | Inside a row or inline with text |
| `control` | 20px | Inside a button or small control |
| `panel` | 24px | Panel-level loading (default) |
| `page` | 32px | Full-page or large area loading |
| `hero` | 128px | Splash or onboarding loading |

When showing a spinner for a long wait, include a short descriptive message. Prefer specific messages over generic ones:

| Preferred | Avoid |
|---|---|
| "Loading note..." | "Loading..." |
| "Indexing your files" | "Please wait" |
| "Uploading file..." | "Working..." |

---

## Save status

Save feedback follows a location-driven principle — the treatment depends on where in the UI the save is happening, not which feature is saving.

### Principle

| Context | Treatment |
|---|---|
| Detail view with toolbar | Inline icon in toolbar area |
| Sheet or modal (no toolbar) | Floating pill at bottom of sheet |
| Background / optimistic write | Silent — no indicator |

### Detail view: toolbar icon (notes pattern)

The notes detail view shows a small icon in the title bar — icon only, no visible text label. Five states:

| State | Icon | Behaviour |
|---|---|---|
| Saving | pencil.circle | Persists while save in flight |
| Saved | checkmark.circle.fill (green) | Shows for 2 seconds, then hides |
| Unsaved changes | pencil.circle.fill | Shows when user edits after a save |
| Sync queued | icloud.and.arrow.up | Shows when offline or write queued |
| Error | exclamationmark.triangle.fill (red) | Persists until acknowledged |

The saved state auto-dismisses using a cancellable `Task.sleep` of 2 seconds. If the user edits during that window, the task cancels and the state returns to "Unsaved changes".

Each icon must carry a VoiceOver accessibility label describing its state — the absence of visible text does not remove the accessibility requirement.

This is the reference pattern for any new detail view that needs save status.

### Sheet context: floating pill (settings pattern)

`SettingsSaveStatusPill` is a floating capsule that appears inside the settings sheet. Three states:

| State | Icon | Text | Behaviour |
|---|---|---|---|
| Saving | Spinner | "Saving settings..." | Persists while saving |
| Saved | checkmark.circle.fill | "Saved" | Auto-dismisses after a short delay |
| Error | exclamationmark.triangle.fill | "Couldn't save settings" | Persists until acknowledged |

Use this pattern for any sheet or modal that has ongoing auto-save behaviour.

### Haptics and save completion (iOS only)

Auto-saves (continuous background saves triggered by typing) fire no haptic — the frequency would be disruptive.

User-triggered saves (explicit button tap or deliberate action) should fire `Haptics.selection()` on completion on iOS. This applies to settings saves and any explicit "Save" button interaction.

Long-running operation completion (file processing done, sync complete) should fire `Haptics.notification(.success)` paired with a toast.

**Rule**: Never fire a haptic for auto-save. Always fire `Haptics.selection()` for explicit user-triggered saves on iOS. See [feedback-and-haptics](./feedback-and-haptics) for the full rule set.

---

## Async buttons

When a button triggers an async operation, the button should:

1. Disable immediately on tap
2. Replace its label with the in-progress form (e.g. "Adding..." instead of "Add task")
3. Re-enable on completion or show an error state if the operation fails

**Web pattern**: Button text changes to present-progressive form. No spinner inside the button unless the wait is expected to exceed 2s.

**Native pattern**: Button disables. For retry specifically, a `ProgressView` at `.controlSize(.mini)` appears inside the button. For other async actions, disabled state alone is sufficient for short operations.

**Rule**: Keep layout stable during async button operations. Do not replace the button with a separate spinner — disable it in place. Retry actions show a spinner within the button.

---

## AI generation states

Chat streaming is different from ordinary loading. The content is arriving incrementally — it is not a wait before a result, it is the result arriving in real time. The visual treatment must reflect this across all platforms.

### Cross-platform goal: progressive reveal

The shared goal is that the assistant's response should appear to be composed in real time — content arrives and becomes visible progressively, never all at once. This applies on all platforms. An animated spinner that then dumps the full response is the wrong pattern.

Before the first token arrives, every platform shows an inline thinking indicator in the message row. Once content starts arriving, the thinking indicator is replaced by the progressively revealed response.

### Native: character-by-character reveal with pacing

On iOS and macOS, content is revealed character by character using a configurable typing reveal animation (`ChatViewModel+TypingReveal.swift`). The reveal rate is intentionally paced — it can run slower than the stream to produce a natural reading tempo. The rate is adjustable per user preference.

During streaming, the message status is `.streaming`. The UI:

- Shows a `LoadingIndicatorView` (inline, 14px) as the thinking indicator before the first token arrives
- Removes the thinking indicator once the first token lands and reveal begins
- Shows retry/error UI if the stream ends in an error

### Web: chunk-by-chunk reveal

On web, content is revealed as SSE chunks arrive — no artificial pacing. This is the appropriate approach for web because:

- Markdown is rendered progressively. Character-by-character reveal of raw markdown would expose broken syntax mid-stream.
- SSE chunk delivery already produces a natural composing feel without artificial rate-limiting.
- DOM update costs make character-level animation expensive without careful batching.

The pre-first-token thinking indicator must match native: an inline indicator in the message row, not a separate spinner above the input.

Tool execution states are shown inline per message for both platforms: "Using {name}" (running), "Used {name}" (success), "Failed to use {name}" (error).

### Framing AI generation correctly

AI generation is not fetching. Do not use the same visual language for a streamed LLM response as for a network request. The experience should feel like the assistant is composing a reply in real time.

**Rule**: Never show a centred spinner while waiting for the first AI token. Use the inline thinking indicator inside the message row on all platforms.

**Rule**: Content must never appear all at once at stream end. Progressive reveal — whether character-paced on native or chunk-driven on web — is required.

---

## Long-running operations

### Website saving

Website saving is a long-running server-side operation that cannot be made optimistic — the server must fetch and process the page. The pattern has two entry points:

**In-app save**: A pending item appears immediately in the sidebar list (optimistic row), and the detail view shows a spinner with a contextual message ("Reading...", "Watching..." for video). A Cancel button appears when cancellation is available. The pending item persists until the server job completes or fails.

**Share extension and Safari extension**: The extension queues the URL immediately without waiting for the server. It shows "Saved for later" — not "Saved" — because the outcome is not yet guaranteed. The main app picks up the queued item on next launch or when the app is active.

**Rule**: When the outcome of a save is not yet confirmed, use "Saved for later" messaging. Never show "Saved" until the operation has actually completed. Honest feedback preserves user trust more than premature confirmation.

**Rule**: Pending items in the sidebar list are the reference pattern for surfacing in-progress long-running saves. Show the pending row immediately; update it as status changes; replace it with the real item on completion.

### File processing progress

When a file is uploading or processing, surface progress per file:

| Phase | Feedback |
|---|---|
| Uploading | Spinner + determinate progress bar + percentage |
| Processing | Spinner only (indeterminate) |
| Failed | Error message + Retry + Dismiss |

Use a determinate progress bar whenever numeric progress is available. Use an indeterminate spinner only when progress cannot be measured.

### Live Activities (iOS)

Long-running file operations on iOS use Live Activities to surface progress outside the app. The qualifying criterion is that the operation is long-running enough that users would benefit from knowing its status without staying in the app.

**Operations that use Live Activities:**

| Operation | Progress surface | Completion |
|---|---|---|
| File ingestion (upload + processing) | Dynamic Island + lock screen progress bar | `Haptics.notification(.success)` + local notification |
| Video transcription (URL input) | Dynamic Island + lock screen status | `Haptics.notification(.success)` + local notification |

Not every background task qualifies. Optimistic writes, settings saves, and brief network operations do not need Live Activities — they complete quickly enough that persistent visibility adds no value.

**In-app surface**: A lightweight summary of recent ingestion history. Not an active tracking panel — users who stay in the app see the same completion state as users who background it.

**Implementation**: `IngestionProgressActivityAttributes` and `IngestionProgressActivityCoordinator` feed from `IngestionViewModel` state. See the [notifications and progress surfaces plan](../../superpowers/plans/2026-03-15-apple-notifications-and-progress-surfaces) for rollout details.

### Long-running operations (macOS)

macOS does not support Live Activities. The same product rules apply — users should not need to stay in the app during long-running file operations — but the implementation differs:

- Normal routing and completion notifications replace Live Activities
- A completion notification fires when processing finishes, with a deep link back to the relevant panel
- The in-app surface mirrors iOS: a lightweight history summary, not an active tracker

---

## Optimistic updates

Optimistic updates are the default pattern for any user-initiated mutation where the outcome is deterministic — the result is known locally before the server confirms. The UI applies the change immediately; the write syncs in the background. This is the primary reason sideBar feels fast and responsive.

**Rule**: If the outcome of a mutation is deterministic, apply it optimistically. Never show a blocking loading state for an operation that can be optimistic.

### When to apply optimistically

Apply optimistically when:
- The outcome is entirely determined by the user's action (not server logic)
- Failure is recoverable without confusing the user (undo or retry)
- The operation is a standard CRUD mutation on user-owned content

Do not apply optimistically when:
- The server must compute the result (AI generation, file processing, transcription)
- The outcome depends on server-side validation that may reject the write
- The operation is irreversible and catastrophic if incorrectly applied

### WriteQueue: the iOS implementation

All eligible writes go through `WriteQueue`, which:

1. Applies the change to local state immediately
2. Queues a network write to CoreData
3. Executes the write when online, with up to 5 retries and exponential backoff
4. Coalesces rapid updates (note content edits merge into a single queued write)
5. Pauses the queue and surfaces a conflict resolution sheet if the server returns a conflict

**Current coverage:**

| Section | Operations |
|---|---|
| Tasks | Create, complete, rename, update notes, move, set/clear due date, defer, set repeat, trash |
| Notes | Archive, pin, move, delete |
| Websites | Pin, rename, archive, delete |

### Failure handling

When a write fails after exhausting retries:
- The write enters `failed` state and remains in the queue
- The error is surfaced at the level where it occurred — inline or toast
- The user can retry or discard the failed write

**Rule**: Do not silently swallow write failures. Surface them at the appropriate level and always provide a retry path.

### Conflict resolution: local always wins

When the server returns a conflict (the entity was changed on another device since the local write was queued), the local version always wins. The queue rebases the write automatically by updating the client timestamp to match the server's, then retries without pausing or asking the user.

There is no manual conflict resolution. The user's most recent intent — the action they took on this device — is authoritative. Showing a resolution sheet interrupts the user for a problem they cannot meaningfully reason about (they rarely remember what changed on another device).

**Rule**: Conflicts are resolved automatically in favour of local. The queue must never pause for user input. No conflict resolution UI should exist anywhere in the product.

### Web

The web frontend does not have and does not need a persistent write queue. Users are almost always online in a browser session, page refreshes are expected to reset in-memory state, and Supabase realtime heals any divergent state after transient failures. A full IndexedDB-backed queue with background sync would be significant complexity for marginal benefit on a secondary platform.

The target for web is:
- Consistent in-memory optimistic updates for all mutations (not just task creation)
- Retry within the session for transient failures before surfacing an error
- Clear error surfacing when retries are exhausted
- No manual conflict resolution — local wins, same as native

Persistent queue parity with iOS is an accepted asymmetry.

### Rule

**Rule**: Do not show a blocking loading state for operations that are optimistically applied. Optimistic writes are silent — the UI has already updated. If the write fails, surface the error through the normal error pattern.

---

## Cancellation and retry

### Cancellation

Cancellation is only relevant for operations that are genuinely long-running and cannot be made optimistic — primarily file ingestion and video transcription.

When cancellation is available, surface a Cancel button inline with the loading state. The website save detail view is an example: while a save is in progress, the detail view content area shows a spinner with an optional Cancel button below it, visible only when `canCancelWebsiteSave()` is true. There is no separate full-screen modal — the loading state occupies the view's content area in place of the normal content.

Do not add a cancel affordance to short operations or optimistic writes — they complete or fail fast enough that cancellation adds no value.

### Retry

When an operation fails:

1. Surface the error at the level where it occurred — in-row pill, toolbar icon, or toast — not a modal
2. Provide a retry action inline where possible
3. During retry, show a spinner inside the retry button and disable it

**Rule**: Retry shows a spinner within the button itself. Keep the layout stable.

---

## Empty states

`EmptyStateView` (native) and `SidebarEmptyState` (web) are for panels and lists that have finished loading but have no content. They are not loading states.

Show a skeleton first. Transition to the empty state only when the load completes with zero results. Do not show empty states during loading.

---

## Rules summary

1. **No feedback under 150ms.** Instant responses render directly.
2. **Skeleton for initial list load. Never for refresh.** Keep visible content in place during refresh.
3. **Descriptive messages for long waits.** "Loading note..." is always better than "Loading...".
4. **Save status is location-driven.** Toolbar icon for detail views, floating pill for sheets, silent for background writes.
5. **Auto-saves are silent on iOS. Explicit saves fire `Haptics.selection()`.** Long-operation completion fires `.notification(.success)` and a toast.
6. **Async buttons disable in place.** Change the label text. Show a spinner inside the button for retry.
7. **AI generation is not fetching.** Inline thinking indicator before first token. Progressive reveal once content arrives — character-paced on native, chunk-driven on web. Content must never appear all at once at stream end.
8. **Background operations never block.** Ambient indicators only.
9. **If the outcome is deterministic, apply it optimistically.** Optimistic writes are silent — the UI has already updated. Surface errors if the write fails.
10. **Conflicts resolve automatically in favour of local.** The queue never pauses for user input. No conflict resolution UI.
11. **Don't confirm what isn't confirmed.** Use "Saved for later" when a save is queued but not yet complete. "Saved" means the operation succeeded.
12. **Cancel is for genuinely long-running operations only.** Don't add cancel affordances to optimistic writes or short operations. Cancel must be available regardless of how the operation was initiated.
13. **Empty state appears after loading, not during.**
14. **Live Activities is the target for long-running file operations on iOS.**

---

## Related docs

- [Feedback and Haptics](./feedback-and-haptics)
- [iOS Conventions](../platform-strategy/ios-conventions)
- [Web Conventions](../platform-strategy/web-conventions)
- [Components](../components/overview)
- [Implementation Gaps](../implementation-gaps)
