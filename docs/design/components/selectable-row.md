---
title: SelectableRow
description: The standard tappable row wrapper for all panel section lists, providing selection highlight, touch target enforcement, and accessibility traits.
---

## Purpose

Wrap all tappable rows in panel section lists. Handles selection highlight, 44pt minimum touch targets, selection animation (with reduce motion support), and the `.isSelected` accessibility trait. Do not build ad-hoc selection highlight or tap handling inline in list rows.

---

## API

```swift
SelectableRow(
    isSelected: Bool,
    insets: EdgeInsets = .init(top: 0, leading: Spacing.sm, bottom: 0, trailing: Spacing.sm),
    verticalPadding: CGFloat = Spacing.xs,
    useListStyling: Bool = true,
    rowBackground: Color? = nil,
    primaryAction: (() -> Void)? = nil
) {
    // row content
}
```

| Parameter | Default | Notes |
|---|---|---|
| `isSelected` | — | Required. Drives the selection highlight and `.isSelected` trait. |
| `insets` | `Spacing.sm` leading/trailing | List row insets. Only override for special layout contexts. |
| `verticalPadding` | `Spacing.xs` | Top and bottom padding inside the row. |
| `useListStyling` | `true` | `true` for rows inside a `List`. `false` for standalone rows outside a `List` — applies a rounded background instead of list row styling. |
| `rowBackground` | `nil` | Custom background color. Defaults to `DesignTokens.Colors.sidebarRowBackground`. Only override when a section has a distinct surface. |
| `primaryAction` | `nil` | When provided, wraps the row content in a `Button` with `.plain` style. Use for rows with a single primary tap action. |

---

## Key rules

- **Always use `SelectableRow` for list rows with selection state.** Do not implement selection highlight manually with `.background` or conditional color changes.
- **Pass `isSelected` correctly.** The component owns the visual state — the caller owns the selection model.
- **`primaryAction` is for a single primary tap action.** If the row navigates somewhere on tap, pass the navigation action here. Do not add a separate `Button` wrapping the row outside `SelectableRow`.
- **Use `useListStyling: false` outside `List`.** If a `SelectableRow` is used in a `VStack` or scroll view rather than a `List`, set `useListStyling: false` — this switches from `listRowBackground` to a clipped rounded background.
- **Do not nest interactive controls inside `SelectableRow` when `primaryAction` is set.** The outer button and inner buttons conflict. Use `primaryAction` only when the whole row is a single tap target.

---

## Selection animation

`SelectableRow` animates the background on selection state change using `Motion.quick`, which respects `accessibilityReduceMotion` automatically. Do not add additional `.animation` modifiers to the row content — they will conflict.

---

## Accessibility

`SelectableRow` automatically applies `.accessibilityAddTraits(.isSelected)` when `isSelected` is true. Add an `.accessibilityLabel` to the row content itself — `SelectableRow` does not set one, since the label depends on the row's data.

---

## Related

- [Components Overview](./overview) — full component list
- [Accessibility](../foundations/accessibility) — accessibility label and trait requirements
- [Token Model](../foundations/token-model) — spacing and color tokens
