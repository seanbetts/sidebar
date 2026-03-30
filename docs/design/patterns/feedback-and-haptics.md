---
title: Feedback and Haptics
description: Haptic feedback patterns, the proposed Haptics helper, and toast notification usage for sideBar on iOS.
---

## Purpose

Define when and how to use haptic feedback and toast notifications across sideBar. Haptics make the app feel responsive and native on iOS. They are one of the most visible places where the app either feels polished or flat — users notice their absence more than their presence.

---

## Platform scope

Haptics are **iOS only**. macOS and iPadOS with pointer input do not support UIKit haptic feedback generators. All haptic calls must be guarded with `#if os(iOS)`.

The proposed `Haptics` helper handles this automatically — callers do not need platform guards.

---

## The `Haptics` helper

A thin enum in `Design/` that wraps the platform API and handles the platform guard centrally. This mirrors the `Motion` pattern.

**`Design/Haptics.swift`**:

```swift
import UIKit

enum Haptics {
    /// Notification feedback — for outcomes with a clear success/warning/error meaning.
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
        #endif
    }

    /// Impact feedback — for physical interactions like button taps and dock actions.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
        #endif
    }

    /// Selection feedback — for discrete state changes like toggles, pins, and archives.
    static func selection() {
        #if os(iOS)
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        #endif
    }
}
```

---

## Feedback taxonomy

Three feedback types, each with a distinct physical character:

| Type | Feel | Use for |
|---|---|---|
| `Haptics.notification(.success)` | Double tap, positive | Completed actions — task done, save confirmed |
| `Haptics.notification(.warning)` | Double tap, neutral | Non-blocking warnings — rate limit, validation notice |
| `Haptics.notification(.error)` | Triple tap, sharp | Destructive or failed actions — delete, auth failure |
| `Haptics.impact(.light)` | Soft click | Floating action button taps, lightweight UI interactions |
| `Haptics.impact(.medium)` | Medium click | Standard button taps where impact is appropriate |
| `Haptics.impact(.heavy)` | Heavy thud | Reserved — use sparingly for high-weight interactions |
| `Haptics.selection()` | Subtle tick | Discrete state changes — toggles, pin/unpin, archive |

---

## Interaction map

The canonical mapping of interactions to feedback.

| Interaction | Feedback |
|---|---|
| Task completion checkbox | `notification(.success)` |
| Destructive delete (swipe) | `notification(.error)` |
| Floating action button tap | `impact(.light)` |
| Settings toggle state change | `selection()` |
| Archive / unarchive action | `selection()` |
| Pin / unpin action | `selection()` |
| Drag reorder completion | `notification(.success)` |
| Auth success (login, biometric) | `notification(.success)` |
| Auth failure | `notification(.error)` |
| Settings save completion | `selection()` |

---

## Toast notifications

`ToastCenter` provides non-blocking visual feedback that appears above all content and auto-dismisses. It has two styles:

| Style | Use |
|---|---|
| `.success` | Confirmed completion — "Note saved", "Link copied" |
| `.error` | Non-critical failure or warning — "Could not save", "Network unavailable" |

### When to combine haptics and toasts

Some interactions warrant both a haptic response and a visual toast. The general rule:

| Scenario | Haptic | Toast |
|---|---|---|
| Action completes silently | Yes | No — haptic alone is sufficient |
| Action result needs confirmation text | Yes | Yes |
| Error the user must know about | Yes (`.error`) | Yes |
| Purely visual state change (toggle) | Yes (`.selection`) | No |

**Rule**: Never show a toast without a haptic on iOS. If a toast is shown, the matching haptic should fire at the same moment.

### Showing a toast

```swift
// Inject via environment
@EnvironmentObject private var toastCenter: ToastCenter

// Show
toastCenter.show(message: "Note saved", style: .success)
toastCenter.show(message: "Could not connect", style: .error)
```

The default duration is 2.5 seconds. Pass a custom `duration` only when the message requires more time to read.

---

## Rules summary

1. **Use `Haptics.*` for all haptic calls.** Once `Design/Haptics.swift` exists, do not use `UINotificationFeedbackGenerator`, `UIImpactFeedbackGenerator`, or `UISelectionFeedbackGenerator` directly in views.
2. **Follow the interaction map.** Every interaction in the table gets its assigned feedback type — no substitutions.
3. **Never use haptics on macOS.** The `Haptics` helper guards this, but do not call haptic code inside `#if os(macOS)` blocks.
4. **Toast always accompanies a haptic on iOS.** If you show a toast, fire the matching haptic at the same time.
5. **No toast for silent completions.** If the action has no meaningful confirmation text, use haptic only.
6. **Do not use `.heavy` impact casually.** It is physically jarring. Reserve for explicitly high-weight interactions.

---

## Related docs

- [iOS Conventions](../platform-strategy/ios-conventions)
- [Accessibility](../foundations/accessibility)
- [Components](../components/overview)
- [Implementation Gaps](../implementation-gaps)
