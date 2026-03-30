---
title: Feature UI Checklist
description: Pre-flight checklist for shipping new UI. Pass/fail items covering tokens, typography, motion, haptics, accessibility, wait states, platform variants, and components.
---

## Purpose

A pre-flight checklist to run before shipping any new UI. Converts the design system's implicit requirements into an explicit pass/fail list. Running through this list takes two to five minutes and prevents the most common design system drift patterns.

---

## How to use this checklist

Read each item. Mark it **Pass**, **Fail**, or **N/A**. If any item fails, fix it before shipping. If a failure reveals a gap between the design system and the codebase that is not already tracked, add it to `implementation-gaps.md`.

The checklist is grouped by concern. Skip entire groups that genuinely do not apply to the feature being shipped.

---

## 1. Tokens and styling

| # | Check | Pass / Fail / N/A |
|---|---|---|
| 1.1 | Every spacing value uses `DesignTokens.Spacing.*`. No raw numeric literals for padding, gap, or margin (e.g. `padding: 16` is wrong; `DesignTokens.Spacing.md` is correct). | |
| 1.2 | Every `cornerRadius` value uses `DesignTokens.Radius.*`. No raw `cornerRadius: 8` or similar. | |
| 1.3 | Every icon frame size uses `DesignTokens.Icon.*` (sm=14, md=18, lg=24, xl=32, xxl=40). Raw sizes of 20, 28, or 30 are a red flag — check if they should be 18 or 24. | |
| 1.4 | Every color reference uses `DesignTokens.Colors.*` or a SwiftUI semantic color (`.primary`, `.secondary`, `Color(.systemBackground)`, etc.). No raw hex values or `Color(red:green:blue:)` literals in views. | |
| 1.5 | Card-shaped containers use `.cardStyle()`. Pill/tag/capsule surfaces use `.pillStyle()`. No inline reimplementation of these patterns. | |
| 1.6 | No use of `PlatformTokens.panelHeaderBackground` — use `DesignTokens.Colors.sidebar` directly. `PlatformTokens` is vestigial. | |

---

## 2. Typography

| # | Check | Pass / Fail / N/A |
|---|---|---|
| 2.1 | Every text element uses `.appFont(AppFontStyle.*)`. No raw `.font(.system(size:weight:))` or `.font(.headline)` calls in new views. | |
| 2.2 | No use of `DesignTokens.Typography.*` — this is a legacy path. Use `.appFont()` exclusively. | |
| 2.3 | Text content that should scale with accessibility preferences (body, labels, descriptions) uses a style with a `Font.TextStyle` anchor (e.g. `.body`, `.subheadline`, `.footnote`). | |
| 2.4 | Text scaling is not clamped or suppressed. No `.dynamicTypeSize(...)` on content views (only permissible in QA matrix views). | |

---

## 3. Animation and motion

| # | Check | Pass / Fail / N/A |
|---|---|---|
| 3.1 | Every animation uses `Motion.quick`, `Motion.standard`, or `Motion.slow`. No `.animation(.easeInOut(duration: 0.2))` or similar raw animation calls. | |
| 3.2 | `@Environment(\.accessibilityReduceMotion) private var reduceMotion` is read at the view level wherever animations appear, and passed to `Motion.*` calls. | |
| 3.3 | Transition animations (`.transition(...)`) respect reduce motion — either gated behind a conditional or using `Motion.*` which returns `nil` when reduce motion is active. | |

---

## 4. Haptics

| # | Check | Pass / Fail / N/A |
|---|---|---|
| 4.1 | All haptic calls use `Haptics.*` (once `Design/Haptics.swift` exists). No direct `UINotificationFeedbackGenerator`, `UIImpactFeedbackGenerator`, or `UISelectionFeedbackGenerator` calls in views. | |
| 4.2 | Haptic type matches the interaction map in [feedback-and-haptics](../patterns/feedback-and-haptics): task completion → `.success`; destructive delete → `.error`; floating action tap → `.impact(.light)`; toggle state change → `.selection()`; archive/pin → `.selection()`. | |
| 4.3 | No haptics on macOS or iPadOS with pointer. The `Haptics` helper guards this — but no haptic calls appear inside `#if os(macOS)` blocks. | |
| 4.4 | If a toast notification is shown on iOS, a matching haptic fires at the same moment. A toast without a haptic is a bug. | |
| 4.5 | Silent completions (no toast needed) still fire the correct haptic. | |

---

## 5. Accessibility

| # | Check | Pass / Fail / N/A |
|---|---|---|
| 5.1 | Every icon-only button has an `.accessibilityLabel`. If using `HeaderActionButton` or `PhoneFloatingActionButton`, the label is required by the API. For any other icon-only `Button`, add `.accessibilityLabel()` explicitly. | |
| 5.2 | Selection state is conveyed via `.accessibilityAddTraits(.isSelected)` on selected rows or tabs. `SelectableRow` handles this automatically — verify manually if not using `SelectableRow`. | |
| 5.3 | Section header labels have `.accessibilityAddTraits(.isHeader)`. | |
| 5.4 | Purely decorative elements (dividers, background shapes, loading spinners that duplicate visible text) have `.accessibilityHidden(true)`. | |
| 5.5 | On macOS, all interactive elements are reachable by Tab key. No `.focusable(false)` on elements that respond to click. | |
| 5.6 | On web, every icon button and interactive element without visible text has `aria-label`. Semantic HTML elements (`<button>`, `<nav>`, `<dialog>`) are used before ARIA roles. | |

---

## 6. Wait states

| # | Check | Pass / Fail / N/A |
|---|---|---|
| 6.1 | Sub-150ms responses render immediately with no spinner or skeleton. | |
| 6.2 | 150ms–1s waits use a skeleton (`ListSkeletons`) or `LoadingIndicatorView`. No blank white space during short waits. | |
| 6.3 | Over-1s waits use `LoadingView` (spinner + optional message) or a progress indicator if determinate. | |
| 6.4 | Background/ongoing operations use an ambient indicator and never block the UI. | |
| 6.5 | `LoadingIndicatorView` is the spinner primitive (six sizes, platform-aware). `LoadingView` is the full-screen wrapper. The correct one is used for the context. | |

---

## 7. Empty and error states

| # | Check | Pass / Fail / N/A |
|---|---|---|
| 7.1 | Fully empty lists use `EmptyStateView` (title + optional subtitle, centred). No inline ad hoc empty state text. | |
| 7.2 | Row-level placeholder states (where a list has items but a row needs a sparse/placeholder appearance) use `SidebarSparseStateRow`, not `EmptyStateView`. | |
| 7.3 | Error states use the established `ChatErrorComponents` pattern in the chat context. For other contexts, error presentation follows the [feedback-and-haptics](../patterns/feedback-and-haptics) toast conventions. | |
| 7.4 | Error copy follows the voice and content guidelines: specific, human, actionable. No "Something went wrong." No technical jargon exposed to the user. | |

---

## 8. Platform variants

| # | Check | Pass / Fail / N/A |
|---|---|---|
| 8.1 | The feature works in all three contexts: iPhone (compact), iPad (regular), Mac. If it is intentionally iPhone-only or Mac-only, that constraint is intentional and documented. | |
| 8.2 | Compact/regular branching uses `@Environment(\.horizontalSizeClass) var sizeClass` and `sizeClass == .compact`. No device idiom checks (`UIDevice.current.userInterfaceIdiom`) for layout decisions that should use size class. | |
| 8.3 | Platform-specific code uses `#if os(iOS)` / `#if os(macOS)` compiler directives, not runtime `ProcessInfo` checks, for genuinely platform-different implementations. | |
| 8.4 | Modals on Mac use `MacModalShell` or `MacPopoverShell`. iOS modals use `.sheet` or `.fullScreenCover`. The wrappers are not mixed. | |
| 8.5 | New actions that should appear in Mac menus are added to `AppCommands.swift`. New keyboard shortcuts for Mac are added to the shortcut registry and documented in `patterns/menus-and-shortcuts.md` once that doc exists. | |

---

## 9. Component reuse

| # | Check | Pass / Fail / N/A |
|---|---|---|
| 9.1 | List rows use `SelectableRow` as the base wrapper. No custom reimplementation of selection highlighting or animation. | |
| 9.2 | Panel sections open with `PanelHeader`. No custom section header implementation that duplicates the `PanelHeader` pattern. | |
| 9.3 | Search inputs use `SearchField`. Compact iPhone search uses the `.dock` chrome variant; standard panel search uses the `.standard` variant. | |
| 9.4 | iPhone create actions use `PhoneFloatingActionDock` with `PhoneFloatingActionButton` children. No new floating action surface that doesn't use the Liquid Glass dock. | |
| 9.5 | If the feature introduces a new shared component (used in more than one section), the component lives in `Design/Components/`, follows the token model, and is listed in the component inventory. | |

---

## 10. Implementation gaps

| # | Check | Pass / Fail / N/A |
|---|---|---|
| 10.1 | Before shipping, check `implementation-gaps.md` for any gaps that affect the area being built. If the feature would be blocked by a tracked gap, note the dependency explicitly. | |
| 10.2 | If the feature resolves a tracked gap, remove that gap from `implementation-gaps.md`. Do not leave resolved gaps in the tracker. | |
| 10.3 | If the feature introduces a new deviation from the design system (intentional or unintentional), add it to `implementation-gaps.md`. Do not ship deviations silently. | |

---

## Related docs

- [Token Model](../foundations/token-model)
- [Typography](../foundations/typography)
- [Accessibility](../foundations/accessibility)
- [Feedback and Haptics](../patterns/feedback-and-haptics)
- [Wait UX](../patterns/wait-ux)
- [Components Overview](../components/overview)
- [Implementation Gaps](../implementation-gaps)
