---
title: Wait UX
description: How sideBar handles loading, saving, generating, and syncing — the language of waiting across all platforms.
---

| Field | Value |
|---|---|
| Status | draft |
| Owner | both |
| Outputs | this doc |
| Dependencies | [ios-conventions](../platform-strategy/ios-conventions), [components](../components/overview), [feedback-and-haptics](./feedback-and-haptics) |

## Purpose

Loading, syncing, saving, and generating are the moments where users have to trust that sideBar knows what it is doing. If those moments are vague, jumpy, or inconsistent, the app feels unreliable. If they are calm and well-paced, the app feels solid.

This doc defines how sideBar should behave during short delays, long waits, and background work — and how AI generation states should feel distinct from ordinary loading.

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

Use `SidebarListSkeleton` for list panels that are loading initial data from the network.

Skeleton rows use variable widths (`textTertiary` at 35% opacity) to approximate real content without flickering. The row count should match the typical content density for that section:

| Panel | Rows | Subtitle |
|---|---|---|
| Conversations | 6 | Yes |
| Websites | 8 | Yes |
| Notes | 8 | No |
| Files | 8 | No |
| Memories | 8 | No |

**Rule**: Use `SidebarListSkeleton` for all sidebar list panels. Do not use a centred spinner as a replacement for skeleton loading in lists — it causes layout shift and is less informative.

---

## Long waits: spinner with message

Use `LoadingIndicatorView` with an accompanying message for waits that are expected to exceed one second or where the user has no prior content to look at.

`LoadingIndicatorView` is a custom animated GIF indicator with platform-appropriate dark/light variants. Use the size appropriate to context:

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

## Background work: ambient indicators

Background operations should not block the UI. Two components handle ambient background state:

### SyncStatusIndicator

A small filled dot that appears when `WriteQueue.pendingCount > 0`. When the queue is actively processing, the dot gains a pulsing ring (1s easeInOut, 0.9–1.2 scale). When the queue is idle and empty, the dot disappears.

The indicator is placed in the section header area. It provides awareness without demanding attention. No label is shown in the UI — it has an accessibility label ("Syncing pending changes" or "Pending changes").

### SettingsSaveStatusPill

A floating capsule pill in the settings sheet. Three states:

| State | Icon | Text | Behaviour |
|---|---|---|---|
| Saving | Spinner | "Saving settings..." | Persists while saving |
| Saved | checkmark.circle.fill | "Saved" | Auto-dismisses after a short delay |
| Error | exclamationmark.triangle.fill | "Couldn't save settings" | Persists until acknowledged |

**Rule**: Background operations must never block navigation or interaction. If an operation fails silently, surface the error through an ambient indicator or a toast — not a blocking modal.

---

## Save status: notes

The notes detail view has a rich five-state save status indicator displayed as a small icon in the title bar. It is the most detailed save indicator in the app and serves as the pattern for any future save-status implementation in a detail view.

| State | Icon | Text | Behaviour |
|---|---|---|---|
| Saving | pencil.circle | "Saving note..." | Persists while save in flight |
| Saved | checkmark.circle.fill (green) | "Saved just now" / "Xm ago" / timestamp | Shows for 2 seconds, then hides |
| Unsaved changes | pencil.circle.fill | "Unsaved changes" | Shows when user edits after a save |
| Sync queued | icloud.and.arrow.up | "Queued to sync" / "Saved offline" | Shows when offline or write queued |
| Error | exclamationmark.triangle.fill (red) | Error message | Persists until acknowledged |

The saved state auto-dismisses using a cancellable `Task.sleep` of 2 seconds. If the user makes another edit during that window, the task is cancelled and the state returns to "Unsaved changes".

---

## File upload progress

File uploads in the Ingestion Center show determinate progress using a native `ProgressView(value:)` with a percentage label. The pattern:

| Phase | Feedback |
|---|---|
| Uploading | `LoadingIndicatorView` + `ProgressView` + "X%" text |
| Processing | `LoadingIndicatorView` only (indeterminate) |
| Failed | Error icon + Retry / Dismiss actions |

Use a determinate progress bar whenever numeric progress is available. Prefer indeterminate spinners only when progress cannot be measured.

---

## AI generation states

Chat streaming is different from ordinary loading. The content is arriving incrementally — it is not a wait before a result, it is the result arriving in real time. The visual treatment must reflect this.

### Typing reveal

The assistant's response is revealed character by character using a configurable typing reveal animation (`ChatViewModel+TypingReveal.swift`). This is not a cosmetic effect — it communicates that the model is generating, not that data is loading from a server. The reveal rate is adjustable per user preference.

During streaming, the message status is `.streaming`. The UI should:

- Render the partial message content as it arrives
- Show a `LoadingIndicatorView` (inline, 14px) as a "thinking" indicator for the AI message row before the first token arrives
- Remove the thinking indicator once the first token lands and typing reveal begins
- Show the retry/error UI if the stream ends in an error

### Framing AI generation correctly

AI generation is not fetching. Do not use the same visual language for a streamed LLM response as for a network request. The experience should feel like the assistant is composing a reply in real time, not that the app is waiting for a server to respond.

**Rule**: Never show a centred spinner while waiting for the first AI token. Use the inline thinking indicator inside the message row.

---

## Optimistic updates

The app uses optimistic updates for note edits, task changes, and website saves via the `WriteQueue` system. Local changes apply immediately; syncing happens in the background.

**Rule**: Do not show a blocking loading state for operations that are optimistically applied. Show ambient sync state (SyncStatusIndicator) or a brief save confirmation (note save status) instead.

---

## Cancellation and retry

When a long wait can be cancelled, always provide a cancel affordance. The website save overlay is the model for this pattern: a full-screen `LoadingView` with a "Cancel" button shown if `canCancelWebsiteSave()` is true.

When an operation fails:

1. Surface the error at the level where it occurred (in-row pill, title bar icon, or toast — not always a modal)
2. Provide a retry action inline where possible
3. During retry, show a spinner in the retry button (`ProgressView` at `.controlSize(.mini)`) and disable the button

**Rule**: Retry actions should show a spinner within the button itself, not replace the button with a separate indicator. Keep the layout stable.

---

## Empty states

`EmptyStateView` is for panels and lists that have finished loading but have no content. It is not a loading state.

It shows a centred title (headline weight) and optional subtitle (body weight, secondary color). Do not show it while the panel is still loading — show a skeleton instead and transition to the empty state only when the load completes with zero results.

---

## Rules summary

1. **No feedback under 150ms.** Instant responses render directly — no spinner flash.
2. **Skeleton loading for all list panels.** Never replace a list with a centred spinner while initial data loads.
3. **Descriptive messages for long waits.** Specific text ("Loading note...") is always better than generic text ("Loading...").
4. **Background operations never block.** Use `SyncStatusIndicator` and `SettingsSaveStatusPill` for ambient background state.
5. **AI generation is not fetching.** Use the inline thinking indicator in the message row, not a centred spinner.
6. **Optimistic updates need ambient confirmation, not blocking states.** `SyncStatusIndicator` and note save status are sufficient.
7. **Retry shows a spinner inside the button.** Keep layout stable during retry.
8. **Empty state appears after loading, not during.** Show skeleton first, then transition to empty state if the result is empty.

---

## Related docs

- [Feedback and Haptics](./feedback-and-haptics)
- [iOS Conventions](../platform-strategy/ios-conventions)
- [Components](../components/overview)
- [Implementation Gaps](../implementation-gaps)
