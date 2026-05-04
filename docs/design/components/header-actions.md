---
title: Header Action Components
description: Standard icon buttons and button groups for panel headers and content toolbars, including HeaderActionButton, HeaderActionRow, and HeaderActionMenuButton.
---

## Purpose

Provide consistent icon buttons for panel headers and content toolbars. The family enforces the accessibility label requirement and provides standard sizing and spacing. Do not build ad-hoc icon buttons inline in header views.

---

## The three components

### HeaderActionButton

A tappable icon button for a single action. Wraps `HeaderActionIcon` in a `Button` with `.plain` style.

```swift
HeaderActionButton(
    icon: AppIcon,
    accessibilityLabel: String,   // required
    action: () -> Void,
    isDisabled: Bool = false
)
```

**`accessibilityLabel` is required and enforced by the API.** There is no default — callers must provide a meaningful label. This is intentional: icon-only buttons are invisible to VoiceOver without it.

Icon is rendered at `.labelMd` font size in a 28×20pt frame.

---

### HeaderActionRow

An `HStack` wrapper for grouping multiple `HeaderActionButton` instances with consistent spacing.

```swift
HeaderActionRow(spacing: CGFloat = 20) {
    HeaderActionButton(...)
    HeaderActionButton(...)
}
```

Default spacing is 20pt. Only override if a specific layout requires tighter or wider grouping. Always use `HeaderActionRow` to group header buttons — do not build a custom `HStack`.

---

### HeaderActionMenuButton

iOS-only. A button that presents a `Menu` using `UIKitMenuButton`, backed by `SidebarMenuItem` items. Use this instead of SwiftUI `Menu` in header contexts — it avoids the long-press delay that `Menu` introduces on iOS.

```swift
#if os(iOS)
HeaderActionMenuButton(
    icon: AppIcon,
    accessibilityLabel: String,   // required
    items: [SidebarMenuItem],
    isCompact: Bool = false
)
#endif
```

`isCompact` adjusts the frame height for contexts where vertical space is constrained.

On macOS, use a standard SwiftUI `Menu` directly — `HeaderActionMenuButton` is not available.

---

## Key rules

1. **Use `HeaderActionButton` for all icon buttons in panel headers and toolbars.** Do not use `Button` with a bare `Image` inline.
2. **`accessibilityLabel` is mandatory.** The API enforces it — do not pass an empty string.
3. **Use `HeaderActionRow` to group multiple actions.** Do not build a custom `HStack` for header button groups.
4. **Use `HeaderActionMenuButton` for menu-presenting buttons on iOS.** Do not use SwiftUI `Menu` in iOS header contexts.
5. **Place `HeaderActionRow` in the `PanelHeader` trailing slot** or in the `ContentHeaderRow` trailing slot. Do not position header actions manually outside these containers.

---

## Example

```swift
PanelHeader(title: "Notes") {
    HeaderActionRow {
        HeaderActionButton(
            icon: AppIcon.Action.compose,
            accessibilityLabel: "New note",
            action: viewModel.createNote
        )
        HeaderActionMenuButton(
            icon: AppIcon.Action.more,
            accessibilityLabel: "More options",
            items: [
                .archive(isArchived: false, handler: viewModel.archiveAll),
                .reorder(handler: viewModel.reorder)
            ]
        )
    }
}
```

---

## Related

- [PanelHeader](./overview#panelheader) — the primary container for header actions in panel sections
- [ContentHeaderRow](./overview#contentHeaderRow) — the trailing slot for header actions in detail views
- [SidebarMenuItem](./sidebar-menu-item) — factory methods for menu items used with `HeaderActionMenuButton`
- [Accessibility](../foundations/accessibility) — accessibility label requirements
- [Iconography](../foundations/iconography) — canonical `AppIcon` assignments for actions
