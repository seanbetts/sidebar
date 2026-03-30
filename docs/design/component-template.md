---
title: Component Template
description: Template and requirements for building new shared UI components in the sideBar design system.
---

## Purpose

Define what a shared component is, where it lives, and what it must contain. Provides a copy-ready Swift scaffold to use as a starting point for any new component added to `Design/Components/`.

---

## When to create a shared component

A view belongs in `Design/Components/` when it meets at least one of these criteria:

- It is used in more than one section or feature
- It encapsulates a design system rule (token usage, accessibility label enforcement, animation gating)
- It provides a platform abstraction that multiple callers need

If a view is only used in one feature and encapsulates no system-level rule, keep it in the feature folder (`Views/Chat/`, `Views/Notes/`, etc.). Premature promotion to `Design/Components/` adds maintenance overhead without benefit.

When you create a new component, add it to the component inventory (`audits/component-inventory.md`).

---

## File location and naming

| Type | Location | Naming |
|---|---|---|
| Shared component | `Design/Components/ComponentName.swift` | `PascalCase`, noun or noun phrase |
| Design style / modifier | `Design/Styles/StyleName.swift` | `PascalCase` |
| View modifier | `Design/Modifiers/ModifierName.swift` | `PascalCase` |

Do not put shared components in `Views/Common/` — that folder is for common feature views, not design system primitives. `Design/Components/` is the correct home.

---

## Swift scaffold

Copy this as the starting point for any new component. Remove the sections that don't apply and fill in the rest.

```swift
import SwiftUI

// MARK: - ComponentName

struct ComponentName: View {

    // MARK: Properties

    // Required parameters — passed by the caller
    let title: String

    // Optional parameters — provide defaults where sensible
    var subtitle: String? = nil

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Add other environment values here if needed:
    // @Environment(\.colorScheme) private var colorScheme
    // @Environment(\.horizontalSizeClass) private var sizeClass

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .appFont(.headline)
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            if let subtitle {
                Text(subtitle)
                    .appFont(.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .padding(DesignTokens.Spacing.md)
        // If the component is interactive, add accessibility label:
        // .accessibilityLabel(title)
        // If the component represents selection state:
        // .accessibilityAddTraits(isSelected ? .isSelected : [])
        // If the component is purely decorative:
        // .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: DesignTokens.Spacing.md) {
        ComponentName(title: "Example")
        ComponentName(title: "With subtitle", subtitle: "Supporting text")
    }
    .padding()
}
```

---

## Required elements

Every component in `Design/Components/` must satisfy all of these:

### Tokens

- All spacing uses `DesignTokens.Spacing.*` — no raw numeric padding or gap values
- All corner radii use `DesignTokens.Radius.*` — no raw `cornerRadius:` literals
- All colors use `DesignTokens.Colors.*` or SwiftUI semantic colors — no raw hex or `Color(red:green:blue:)`
- All icon sizes use `DesignTokens.Icon.*`

### Typography

- All text uses `.appFont(AppFontStyle.*)` — no `.font(.system(size:weight:))` or `.font(.headline)` directly

### Animation

- Read `@Environment(\.accessibilityReduceMotion) private var reduceMotion` at the component level whenever the component animates
- Pass `reduceMotion` to all `Motion.*` calls — never hardcode `.animation(.easeInOut(duration: 0.2))` or similar

### Accessibility

- Icon-only interactive elements must have `.accessibilityLabel`
- Selection state must use `.accessibilityAddTraits(.isSelected)`
- Purely decorative elements use `.accessibilityHidden(true)`
- If the component API wraps an interactive control, enforce the accessibility label as a required parameter (see `HeaderActionButton` as the canonical example)

### Preview

- Every component must have a `#Preview` that covers the main variants
- The preview should be self-contained — no dependency on live environment objects

---

## Platform branching

Use these patterns for platform-specific behaviour. Always prefer conditional modifiers over duplicated view hierarchies.

### Conditional modifiers

```swift
var body: some View {
    content
        #if os(macOS)
        .background(DesignTokens.Colors.surface)
        #else
        .background(DesignTokens.Colors.sidebar)
        #endif
}
```

### Size class branching (layout differences)

```swift
@Environment(\.horizontalSizeClass) private var sizeClass

var body: some View {
    if sizeClass == .compact {
        compactLayout
    } else {
        regularLayout
    }
}
```

Use size class (not device idiom) for layout decisions. Size class correctly handles iPad Split View and Stage Manager.

### iOS-only code (haptics, UIKit APIs)

```swift
#if os(iOS)
// UIKit-specific code here
#endif
```

The `Haptics` helper already wraps the `#if os(iOS)` guard internally — callers do not need to add the guard when calling `Haptics.*`.

---

## Component variants

When a component has variants, use an enum or `OptionSet` — not a proliferation of Boolean flags.

```swift
// Correct
enum ChromeVariant {
    case standard
    case dock
}

struct SearchField: View {
    let chrome: ChromeVariant
    ...
}

// Wrong — booleans compose poorly and are hard to read at the call site
struct SearchField: View {
    let isTransparent: Bool
    let showsBorder: Bool
    ...
}
```

---

## What not to do

- Do not hardcode light/dark appearance by reading `colorScheme` — use adaptive `DesignTokens.Colors.*` values that handle both modes automatically
- Do not suppress or replace the system focus ring on macOS
- Do not add `.id()` modifiers to force identity unless you have a specific reason — it breaks animations
- Do not read `UIDevice.current.userInterfaceIdiom` for layout decisions — use `horizontalSizeClass`

---

## Reference components

These existing components are well-formed and serve as good examples:

| Component | What it demonstrates |
|---|---|
| `EmptyStateView` | Minimal token-backed view, correct font and color usage |
| `SelectableRow` | Reduce motion, selection trait, token usage throughout |
| `HeaderActionButton` | Enforcing accessibility label as required API parameter |
| `PhoneFloatingActionDock` | Liquid Glass, iOS-only guard, platform-specific component |
| `LoadingIndicatorView` | Multi-size variant model, accessibility hidden on decorative state |

---

## Related docs

- [Components Overview](./components/overview) — what components exist and when to use them
- [Token Model](./foundations/token-model) — full token scale reference
- [Typography](./foundations/typography) — `AppFontStyle` scale
- [Accessibility](./foundations/accessibility) — labels, traits, and reduce motion
- [Feature UI Checklist](./feature-ui-checklist) — pre-flight check before shipping
