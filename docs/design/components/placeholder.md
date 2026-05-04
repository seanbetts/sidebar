---
title: PlaceholderView
description: Full-surface error state for content areas that failed to load, with an optional retry action.
---

## Purpose

Replace the content area of a detail view or panel when loading failed and there is nothing to show. Provides a centred message and an optional action button for recovery.

---

## When to use

Use `PlaceholderView` when a content area attempted to load and failed — not when it is empty. The distinction matters:

| Situation | Component |
|---|---|
| Content loaded successfully, nothing exists | [`EmptyStateView`](./empty-state) |
| Content failed to load | `PlaceholderView` |
| Content is loading | [`SidebarListSkeleton`](./list-skeleton) |

`PlaceholderView` is also the correct surface for selected content that exists in principle but is not available offline on the current device yet.

If the question is "which empty-state copy should I use?", stay in [`EmptyStateView`](./empty-state) and the empty-state rules. Do not repurpose `PlaceholderView` for empty states just because the layout happens to fit.

Always include a retry action when the failure is recoverable. Wire `action` to the same load function that originally triggered the failure.

---

## API

```swift
PlaceholderView(
    title: String,
    subtitle: String? = nil,
    actionTitle: String? = nil,
    action: (() -> Void)? = nil,
    icon: AppIcon? = nil
)
```

| Parameter | Required | Notes |
|---|---|---|
| `title` | Yes | Primary message. e.g. "Unable to load note." |
| `subtitle` | No | Supporting detail or hint. |
| `actionTitle` | No | Button label. e.g. "Try Again". Required if `action` is provided. |
| `action` | No | Retry callback. Should re-trigger the failed load. |
| `icon` | No | Semantic `AppIcon` for the icon above the title. |

`actionTitle` and `action` must be provided together — the button only renders when both are set.

---

## Key rules

- Always provide a retry `action` when the failure is transient (network error, timeout). Do not leave the user with no recovery path.
- For unavailable-offline states, preserve the user's current selection and explain that the content is not cached on this device yet.
- If the content area has stale data from a previous successful load, prefer showing a toast over replacing the content with `PlaceholderView`. Reserve `PlaceholderView` for when the area is blank.
- Keep `title` direct and honest. "Unable to load chat." not "Something went wrong."
- Do not use `PlaceholderView` for empty states. Use [`EmptyStateView`](./empty-state).
- `PlaceholderView` fills its container (`maxWidth: .infinity, maxHeight: .infinity`). Place it inside a container that already has the correct frame.

---

## File location

`PlaceholderView` lives in `Views/Common/ContentViewComponents.swift`, not `Design/Components/`. It is a shared view rather than a design system primitive, but it is used consistently enough across sections to be treated as a standard component.

---

## Related

- [`EmptyStateView`](./empty-state) — for genuinely empty content, not failures
- [`SidebarListSkeleton`](./list-skeleton) — for the loading state before failure is confirmed
- [Error Presentation](../patterns/error-presentation) — full rules for when to use each error surface
