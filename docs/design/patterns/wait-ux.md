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
| Live Activities | Target | No | No |
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
| Conversations | 6 | Yes |
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
| "Connecting to sync" | "Working..." |

---

## Save status

Save feedback follows a location-driven principle — the treatment depends on where in the UI the save is happening, not which feature is saving.

### Principle

| Context | Treatment |
|---|---|
| Detail view with toolbar | Inline icon in toolbar area |
| Sheet or modal (no toolbar) | Floating pill at bottom of sheet |
| Background / optimistic write | Ambient dot only (`SyncStatusIndicator`) |

### Detail view: toolbar icon (notes pattern)

The notes detail view shows a small icon in the title bar. Five states:

| State | Icon | Text | Behaviour |
|---|---|---|---|
| Saving | pencil.circle | "Saving note..." | Persists while save in flight |
| Saved | checkmark.circle.fill (green) | "Saved just now" / "Xm ago" | Shows for 2 seconds, then hides |
| Unsaved changes | pencil.circle.fill | "Unsaved changes" | Shows when user edits after a save |
| Sync queued | icloud.and.arrow.up | "Queued to sync" / "Saved offline" | Shows when offline or write queued |
| Error | exclamationmark.triangle.fill (red) | Error message | Persists until acknowledged |

The saved state auto-dismisses using a cancellable `Task.sleep` of 2 seconds. If the user edits during that window, the task cancels and the state returns to "Unsaved changes".

This is the reference pattern for any new detail view that needs save status.

### Sheet context: floating pill (settings pattern)

`SettingsSaveStatusPill` is a floating capsule that appears inside the settings sheet. Three states:

| State | Icon | Text | Behaviour |
|---|---|---|---|
| Saving | Spinner | "Saving settings..." | Persists while saving |
| Saved | checkmark.circle.fill | "Saved" | Auto-dismisses after a short delay |
| Error | exclamationmark.triangle.fill | "Couldn't save settings" | Persists until acknowledged |

Use this pattern for any sheet or modal that has ongoing auto-save behaviour.

### Background / optimistic writes: ambient dot

`SyncStatusIndicator` is a small filled dot that appears when `WriteQueue.pendingCount > 0`. When the queue is actively processing, the dot gains a pulsing ring (1s easeInOut, 0.9–1.2 scale). No blocking UI. No label in the default layout.

Use this for background sync of notes, tasks, and websites where optimistic updates have already updated the UI.

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

### File processing progress

When a file is uploading or processing, surface progress per file:

| Phase | Feedback |
|---|---|
| Uploading | Spinner + determinate progress bar + percentage |
| Processing | Spinner only (indeterminate) |
| Failed | Error message + Retry + Dismiss |

Use a determinate progress bar whenever numeric progress is available. Use an indeterminate spinner only when progress cannot be measured.

### Live Activities (iOS)

Long-running file operations on iOS use Live Activities to surface progress outside the app:

- Upload and processing progress appears in the Dynamic Island and on the lock screen
- Users do not need to stay in the app during file processing
- The in-app surface is a lightweight summary of recent ingestion history, not an active tracking panel
- `Haptics.notification(.success)` fires and a local notification is sent when processing completes

---

## Optimistic updates

The app uses optimistic updates for note edits, task changes, and website saves via the `WriteQueue` system. Local changes apply immediately; syncing happens in the background.

**Rule**: Do not show a blocking loading state for operations that are optimistically applied. Show ambient sync state (`SyncStatusIndicator`) or a brief save confirmation (toolbar icon, pill) instead.

---

## Cancellation and retry

When a long wait can be cancelled, always provide a cancel affordance. The website save overlay is the model for this: a full-screen `LoadingView` with a "Cancel" button when cancellation is available.

When an operation fails:

1. Surface the error at the level where it occurred — in-row pill, toolbar icon, or toast — not always a modal
2. Provide a retry action inline where possible
3. During retry, show a spinner in the retry button and disable it

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
4. **Save status is location-driven.** Toolbar icon for detail views, floating pill for sheets, ambient dot for background writes.
5. **Auto-saves are silent on iOS. Explicit saves fire `Haptics.selection()`.** Long-operation completion fires `.notification(.success)` and a toast.
6. **Async buttons disable in place.** Change the label text. Show a spinner inside the button for retry.
7. **AI generation is not fetching.** Inline thinking indicator before first token. Progressive reveal once content arrives — character-paced on native, chunk-driven on web. Content must never appear all at once at stream end.
8. **Background operations never block.** Ambient indicators only.
9. **Optimistic updates need ambient confirmation, not blocking states.**
10. **Empty state appears after loading, not during.**
11. **Live Activities is the target for long-running file operations on iOS.** IngestionCenter is the current interim pattern.

---

## Related docs

- [Feedback and Haptics](./feedback-and-haptics)
- [iOS Conventions](../platform-strategy/ios-conventions)
- [Web Conventions](../platform-strategy/web-conventions)
- [Components](../components/overview)
- [Implementation Gaps](../implementation-gaps)
