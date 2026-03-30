---
title: SidebarListSkeleton
description: Skeleton loading placeholder for panel list sections during initial data load.
---

## Purpose

Show structural placeholder rows in a panel list section while data is loading for the first time. Prevents layout shift and gives the user a sense of the content structure before it arrives.

---

## When to use

Use `SidebarListSkeleton` during the initial load of a panel section list — before the first successful data fetch completes. Once data has loaded at least once, do not show the skeleton again on subsequent refreshes. For refresh failures, use a toast and leave the existing content in place.

Do not use `SidebarListSkeleton` in content detail views (the right-side area). It is specific to left-panel list sections.

---

## API

```swift
SidebarListSkeleton(
    rowCount: Int = 8,
    showSubtitle: Bool = false
)
```

| Parameter | Default | Notes |
|---|---|---|
| `rowCount` | 8 | Number of placeholder rows. Use 8 for all panels. |
| `showSubtitle` | false | Adds a shorter second line to each row. Use for panels where rows have a visible subtitle (e.g. websites). |

---

## Key rules

- Use 8 rows for all panels. This is the design system standard — do not pass a custom `rowCount`.
- Match `showSubtitle` to the panel's actual row structure. If the real rows show a subtitle, set `showSubtitle: true` so the skeleton matches the loaded layout.
- No shimmer animation. The skeleton uses static muted fill. Do not add animation — it conflicts with the reduce motion accessibility setting and adds visual noise.
- The skeleton applies `.sidebar` background automatically. Do not wrap it in an additional background modifier.

---

## Related

- [`EmptyStateView`](./empty-state) — for after load completes with no content
- [`PlaceholderView`](./placeholder) — for when load fails entirely
- [Wait UX](../patterns/wait-ux) — full loading state patterns and the skeleton-to-content transition
