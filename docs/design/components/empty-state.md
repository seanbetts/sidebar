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
    icon: AppIcon? = nil
)
```

| Parameter | Required | Notes |
|---|---|---|
| `title` | Yes | Primary message. One short sentence. |
| `subtitle` | No | Supporting detail. Use sparingly. |
| `icon` | No | Semantic `AppIcon`. Rendered at `Icon.lg` inside a muted circle. Decorative, hidden from VoiceOver. |

---

## Key rules

- Always use `EmptyStateView` for empty list and content states. Do not write ad-hoc empty state layouts inline in feature views.
- Keep `title` short — one sentence, sentence case. "No notes yet." not "You don't have any notes yet. Create one to get started."
- Use `subtitle` only when the reason or next step isn't obvious from the title alone.
- `icon` is optional. Use it when the icon adds clarity, not just decoration.
- Do not add a call-to-action button to `EmptyStateView`. If an action is needed, use [`PlaceholderView`](./placeholder) which has a built-in action slot, or place a button separately in the view hierarchy.

## Semantic categories

Use one of these semantic buckets before choosing copy:

- `noContentYet`: the surface loaded correctly but nothing has been created yet
- `noResults`: a search or filter returned no matches
- `noSelection`: the user has not selected any content yet
- `allTasksCompleted`: an active task scope is empty because work is done

These semantics may be carried in code by a helper such as `EmptyStateContent`, even when the rendered view differs by surface.

## Copy rules

- Use `No … yet` for genuinely empty content collections.
- Use `No results` for search or filter miss states.
- Use `Select a …` for no-selection states.
- Use `All tasks completed` only for active task scopes emptied by completion.
- Use activity-complete phrasing only when the surface represents finished work, not missing setup.

---

## Subscription-gated empty states

Some empty states are caused by subscription gating rather than by missing content. These require different treatment: the user needs to understand what they would see with a subscription, not just that nothing is here yet.

**Chat (free user, no conversations)**:

Use the engaged register. The empty state should communicate the value of the assistant, not just "no messages":

| Surface | Preferred copy |
|---|---|
| Chat (free user, empty) | "sideBar can help you with your notes, tasks, and more" with a "See plans" action below |

Do not use `EmptyStateView` alone for this case. Pair it with the subscription prompt card from [Subscription](../patterns/subscription#chat-free-users), which provides the upgrade action.

**Skills Store (free user browsing)**:

Free users can browse the full Skills Store. Skill cards show tier badges indicating which plan unlocks them. This is not an empty state, it is a populated browsing experience with gated install actions.

If no skills match a search or filter for a free user, use the standard empty state: "No matching skills". Do not add subscription messaging to search-no-results states.

---

## Related

- [`PlaceholderView`](./placeholder) — for load failures with an optional retry action
- [`SidebarListSkeleton`](./list-skeleton) — for the loading state before empty is confirmed
- [Error Presentation](../patterns/error-presentation) — when to show an error vs. an empty state
- [Subscription](../patterns/subscription) — subscription boundary patterns
- [Wait UX](../patterns/wait-ux) — loading state patterns
