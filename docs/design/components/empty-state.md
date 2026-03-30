---
title: EmptyStateView
description: Centred empty state for panel sections and content areas when no items exist.
---

## Purpose

Display a centred message when a list or content area is genuinely empty — no items have been created yet, a filter returns no results, or a section has no content.

---

## When to use

Use `EmptyStateView` when the content area loaded successfully but has nothing to show. Do not use bare inline `Text` for empty states — `EmptyStateView` provides consistent layout, typography, and colour.

**Do not use `EmptyStateView` for load failures.** If the content failed to load, use [`PlaceholderView`](./placeholder) instead. The distinction matters: an empty state is a valid, permanent state; a load failure is an error that may be recoverable.

---

## API

```swift
EmptyStateView(
    title: String,
    subtitle: String? = nil,
    systemImage: String? = nil
)
```

| Parameter | Required | Notes |
|---|---|---|
| `title` | Yes | Primary message. One short sentence. |
| `subtitle` | No | Supporting detail. Use sparingly. |
| `systemImage` | No | SF Symbol name. Rendered at `Icon.lg` inside a muted circle. Decorative — hidden from VoiceOver. |

---

## Key rules

- Always use `EmptyStateView` for empty list and content states. Do not write ad-hoc empty state layouts inline in feature views.
- Keep `title` short — one sentence, sentence case. "No notes yet." not "You don't have any notes yet. Create one to get started."
- Use `subtitle` only when the reason or next step isn't obvious from the title alone.
- `systemImage` is optional. Use it when the icon adds clarity, not just decoration.
- Do not add a call-to-action button to `EmptyStateView`. If an action is needed, use [`PlaceholderView`](./placeholder) which has a built-in action slot, or place a button separately in the view hierarchy.

---

## Related

- [`PlaceholderView`](./placeholder) — for load failures with an optional retry action
- [`SidebarListSkeleton`](./list-skeleton) — for the loading state before empty is confirmed
- [Error Presentation](../patterns/error-presentation) — when to show an error vs. an empty state
- [Wait UX](../patterns/wait-ux) — loading state patterns
