---
title: Accessibility
description: Reduce motion, Dynamic Type, VoiceOver, keyboard navigation, and ARIA patterns for sideBar across iOS, macOS, and web.
---

| Field | Value |
|---|---|
| Status | approved |
| Owner | both |
| Outputs | this doc |
| Dependencies | [token-model](./token-model), [typography](./typography), [ios-conventions](../platform-strategy/ios-conventions), [macos-conventions](../platform-strategy/macos-conventions), [web-conventions](../platform-strategy/web-conventions) |

## Purpose

Define accessibility requirements and patterns for sideBar. This is not aspirational — these are working requirements that apply to every surface shipped.

---

## Reduce motion

### Native

All animations must go through the `Motion` enum (`Design/Motion.swift`), which gates every animation behind `@Environment(\.accessibilityReduceMotion)`. When reduce motion is enabled, `Motion.*` returns `nil`, suppressing the animation entirely.

```swift
// Correct
.animation(Motion.quick(reduceMotion: reduceMotion), value: isSelected)

// Wrong — bypasses reduce motion
.animation(.easeInOut(duration: 0.15), value: isSelected)
```

Read `reduceMotion` from the environment at the view level:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

**Rule**: Never use `.animation()` with a hardcoded duration. Always use `Motion.quick`, `Motion.standard`, or `Motion.slow`.

**Gap**: `Motion.slow` is missing from `Motion.swift` despite `Animation.slow = 0.4` existing in `DesignTokens`. Tracked in [implementation-gaps](../implementation-gaps).

### Web

`prefers-reduced-motion` support is not yet confirmed across all web animations. Tracked as a medium-priority gap in [implementation-gaps](../implementation-gaps).

---

## Dynamic Type

The native app supports Dynamic Type through the `.appFont()` modifier. Styles that anchor to a `textStyle` (e.g., `.body`, `.footnote`) scale with the system text size setting. Styles without an anchor use `AppTextSizeOption` scaling only.

| Anchor type | Scales with |
|---|---|
| Styles with `textStyle` (e.g. `body`, `footnote`, `caption`) | System Dynamic Type setting |
| Styles without `textStyle` (e.g. `label`, `titleSm`, `badge`) | `AppTextSizeOption` only (in-app preference) |

`AppTextSizeOption` provides an in-app text size preference (system 1.0×, small 0.8×, medium 0.9×, large 1.05×) that applies on top of Dynamic Type. Both inputs stack — a user on Large Dynamic Type with the in-app large setting gets the maximum scaling.

**Rule**: Do not clamp or override Dynamic Type scaling in views. Never set `.dynamicTypeSize(.small)` or similar constraints on content views. The QA matrix (`LargerTextQAMatrix`) uses `.dynamicTypeSize(.accessibility5)` for layout stress testing only — do not ship this in production views.

---

## VoiceOver (native)

### Accessibility labels

Every interactive element that lacks a visible text label must have an `.accessibilityLabel`. This includes icon buttons, image buttons, and any control whose purpose is not obvious from its visible content.

```swift
// Correct — HeaderActionButton requires a label
HeaderActionButton(
    systemName: "square.and.pencil",
    accessibilityLabel: "Edit note"
) { ... }

// Wrong — no label on an icon-only button
Button { ... } label: {
    Image(systemName: "square.and.pencil")
}
```

**Rule**: `HeaderActionButton` and `PhoneFloatingActionButton` enforce the label at the API level — they require `accessibilityLabel` as a parameter. For any other icon-only button, add `.accessibilityLabel()` explicitly.

### Accessibility hints

Use `.accessibilityHint` to describe the result of an action when the label alone is insufficient. Hints are read after a pause and should describe the outcome, not repeat the label.

```swift
.accessibilityLabel("Profile photo")
.accessibilityHint("Double tap to change your profile photo.")
```

Use hints sparingly — only when the result of an action would be non-obvious to a VoiceOver user.

### Traits

Use `.accessibilityAddTraits` to convey element state and role:

| Trait | When to use |
|---|---|
| `.isSelected` | Row or tab that is currently selected |
| `.isButton` | Non-button view that acts as a button |
| `.isHeader` | Section header labels |
| `.updatesFrequently` | Values that update in real time (status indicators) |

`SelectableRow` applies `.isSelected` automatically based on its `isSelected` parameter.

### Combining and hiding

Use `.accessibilityElement(children: .combine)` when a group of elements should be read as a single VoiceOver element (e.g., a label + value pair in settings).

Use `.accessibilityHidden(true)` for purely decorative elements that add no information (e.g., loading spinners, decorative dividers, background images).

---

## Keyboard navigation (macOS)

All interactive elements must be reachable by Tab key on macOS. The system focus ring is used — do not suppress or replace it.

Standard macOS keyboard shortcuts must be supported. Critical shortcuts are documented in [macos-conventions](../platform-strategy/macos-conventions).

**Rule**: Do not use `.focusable(false)` on elements that are semantically interactive. If an element responds to click, it must respond to keyboard activation.

---

## Web (ARIA)

### Labels

Every icon button and interactive element without visible text must have `aria-label`:

```html
<button aria-label="Send message">
  <ArrowUp size={18} />
</button>
```

### Roles

Use semantic HTML elements where possible — `<button>`, `<nav>`, `<main>`, `<dialog>`. Apply `role` only when the semantic element is not available or appropriate.

| Pattern | Usage |
|---|---|
| `role="dialog"` + `aria-modal="true"` | Custom modal overlays |
| `role="separator"` | Resize handles and structural dividers |
| `role="img"` + `aria-label` | Decorative SVGs that convey meaning |
| `aria-hidden="true"` | Decorative icons and purely visual elements |

### Loading states

The `LoadingGlyph` component handles its own ARIA correctly: it applies `role="img"` and `aria-label` when a label is provided, and `aria-hidden="true"` when it is purely decorative.

**Rule**: Do not add `aria-hidden` to interactive elements. Do not suppress focus on focusable elements via `tabindex="-1"` unless managing a custom focus trap (e.g., inside a modal).

---

## Rules summary

1. **Reduce motion on native**: always use `Motion.*`. Never use `.animation()` with a hardcoded duration.
2. **Dynamic Type**: never clamp or suppress text scaling in content views.
3. **VoiceOver labels**: every icon-only button must have an accessibility label. `HeaderActionButton` and `PhoneFloatingActionButton` enforce this at the API level.
4. **Accessibility hints**: use sparingly, only when the action outcome is non-obvious.
5. **Decorative elements**: apply `.accessibilityHidden(true)` (native) or `aria-hidden="true"` (web) to purely visual elements.
6. **Keyboard navigation**: all interactive elements reachable by Tab on macOS. Never suppress focus.
7. **Web ARIA**: use semantic HTML first. Apply ARIA roles and labels only where needed.

---

## Related docs

- [Token Model](./token-model) — `Motion` enum and animation tokens
- [Typography](./typography) — Dynamic Type anchors and `AppTextSizeOption`
- [iOS Conventions](../platform-strategy/ios-conventions)
- [macOS Conventions](../platform-strategy/macos-conventions)
- [Web Conventions](../platform-strategy/web-conventions)
- [Implementation Gaps](../implementation-gaps)
