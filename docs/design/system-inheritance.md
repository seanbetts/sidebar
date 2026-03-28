---
title: System Inheritance
description: Draft policy for what sideBar inherits from Apple frameworks and where it intentionally departs from native defaults.
---

| Field | Value |
|---|---|
| Status | drafted |
| Owner | AI coding agent |
| Inputs needed | codebase inspection (complete), Apple HIG reference, Sean's intent on customisation areas |
| Outputs | this doc |
| Dependencies | [principles](./principles), [system-framework-usage-audit](./audits/system-framework-usage-audit) |
| Codebase review required | yes (complete) |
| Human judgement required | yes - Sean to confirm customisation intent in flagged areas |

## Purpose

Define what sideBar inherits from Apple's native frameworks and where we depart from platform defaults. This is a practical guide for making decisions about native vs custom UI.

---

## Why this matters

The most expensive UI decisions are the ones that fight the platform. Overriding native components requires maintaining custom implementations, missing out on system improvements, and sometimes producing accessibility or motion behaviour that diverges from user expectations.

This document makes the inheritance policy explicit so that:
- New UI defaults to native rather than custom
- Customisations are justified and documented
- The AI coding agent knows when to reach for the system and when to use a product-specific component

---

## The three tiers

Every UI element in sideBar falls into one of three tiers:

| Tier | Description | Default policy |
|---|---|---|
| **Inherit** | Native Apple component or behaviour used as-is | Always use unless Tier 2 or 3 applies |
| **Adapt** | Native component lightly extended for cross-platform use or product-specific context | Use the native component as the foundation, add only what is needed |
| **Replace** | Custom implementation built from primitives | Requires justification. Only when native alternatives are functionally insufficient |

---

## Tier 1: Inherit (use native as-is)

These Apple-provided components and behaviours should be used without customisation.

### Native controls

| Component | SwiftUI API | Notes |
|---|---|---|
| Button | `Button` | Use `.buttonStyle(.plain)` for custom-styled tap targets |
| Toggle | `Toggle` | Settings switches |
| Picker | `Picker` | Settings selections |
| Slider | `Slider` | If used |
| Stepper | `Stepper` | If used |
| Text field | `TextField` | For simple inputs |
| Secure field | `SecureField` | For password inputs |
| Label | `Label` | For icon+text combinations |
| Menu | `Menu` | Context menus and dropdown actions |

### Containers and navigation

| Component | API | Notes |
|---|---|---|
| Tab view (iPhone) | `TabView` | Primary iPhone navigation |
| Navigation stack | `NavigationStack` | Per-section stack navigation |
| List | `List` | Panel section lists |
| Form | `Form` | Settings surfaces |
| Form grouped style | `.formStyle(.grouped)` | Settings form style |
| Sheet | `.sheet` | Modals on iPhone and Mac |
| Alert | `.alert` | Confirmation and error alerts |
| Popover | `.popover` | Mac/iPad transient content |
| Full screen cover | `.fullScreenCover` | Full-screen presentations |

### System presentation behaviours

| Behaviour | API | Notes |
|---|---|---|
| Drag indicator | `.presentationDragIndicator` | Sheet grab handles |
| Presentation sizing | `.presentationSizing` | Sheet sizing on Mac |
| Keyboard avoidance | Automatic with Form/List | Do not reimplement manually |
| Safe area insets | `safeAreaInset`, `.ignoresSafeArea` | Used correctly already |
| Scroll content background | `.scrollContentBackground(.hidden)` | For custom backgrounds under scrolling content |

### System colors and materials

| Token | What to use | Notes |
|---|---|---|
| Primary background (iOS) | `UIColor.systemBackground` via `Color.appBackground` | Adaptive |
| Secondary background (iOS) | `UIColor.secondarySystemBackground` via `Color.appSurface` | Adaptive |
| Grouped background (iOS) | `UIColor.systemGroupedBackground` via `Color.appSettingsBackground` | Settings pages |
| Separator (iOS) | `UIColor.separator` via `Color.appBorder` | Dividers |
| Text primary | `Color.primary` | Adapts to dark mode |
| Text secondary | `Color.secondary` | Adapts to dark mode |
| Accent color | `Color.accentColor` | The app tint |
| Liquid Glass | `.glassEffect(...)` | iOS 26 / macOS 26 chrome |

### SF Symbols

All iconography should default to SF Symbols. The full catalog is available. Symbol weight should match the context (navigation icons use `.semibold`; inline content icons use `.regular` or `.medium`).

Do not add a custom icon asset for anything that SF Symbols already covers.

### Typography base

The system text style sizes (`UIFont.preferredFont(forTextStyle:)`, `NSFont.preferredFont(forTextStyle:)`) are used as the base for the app font system. This baseline should be preserved.

### Accessibility

The following accessibility behaviours are inherited automatically and must not be broken by custom UI:

- VoiceOver label and value from `.accessibilityLabel` and standard control labels
- Focus ring (macOS) from standard interactive controls
- Increase contrast adaptation from system semantic colors
- Bold text adaptation from system fonts
- Reduced motion from `@Environment(\.accessibilityReduceMotion)`
- Dynamic Type from the base font system

---

## Tier 2: Adapt (native component, extended)

These components use a native foundation but add product-specific behaviour.

### SearchField

Foundation: SwiftUI `TextField`
Addition: SF Symbol search icon, clear button, two chrome variants (standard and dock), token-backed styling.

**Why not `.searchable`**: The dock placement (floating above tab bar on iPhone) requires direct control over position and layout. `.searchable` attaches to the navigation bar.

**Rule for agent**: Use `Design/Components/SearchField.swift` for all search inputs. Do not reinvent.

### Cross-platform modifier wrappers

Foundation: Native modifiers
Addition: `Views/Common/PlatformViewModifiers.swift` wraps iOS-only modifiers (`.navigationBarTitleDisplayMode`, `.textInputAutocapitalization`, `.submitLabel`, `.presentationDragIndicator`) in no-op alternatives for macOS.

**Rule for agent**: Use the wrapper modifiers. Do not add `#if os(iOS)` blocks in feature views.

### Safe area and keyboard tracking

Foundation: SwiftUI safe area APIs, UIKit keyboard notifications
Addition: Custom keyboard visibility state tracking for the search dock bottom padding.

**Rule for agent**: Do not add additional keyboard notification subscriptions. Use the existing state in `ContentView`.

### SelectableRow

Foundation: `List` row, `Button`
Addition: Selection highlight, animation, configurable insets, both list and non-list contexts.

**Rule for agent**: Always use `SelectableRow` for list rows that have a selected state. Do not reimplement selection highlighting.

### PanelHeader

Foundation: `HStack`, `Text`
Addition: Semantic title/subtitle/trailing/offline banner layout, token-backed, platform-adaptive background.

**Rule for agent**: Use `PanelHeader` for every section panel title area. Do not build ad-hoc headers.

---

## Tier 3: Replace (custom, justified)

These are custom implementations where native alternatives were insufficient.

### WorkspaceLayout + SidebarRail

**What it replaces**: `NavigationSplitView` / system split view
**Why**: sideBar's workspace model requires:
- A custom 56px icon-only rail (narrower than system sidebar)
- Drag-to-resize left panel with snap points and persisted width
- Optional right sidebar (second content column)
- Custom workspace expand/collapse toggle

`NavigationSplitView` does not support this level of layout control. The custom implementation was the right call.

**Maintenance implication**: This layout does not automatically benefit from system navigation improvements. It needs explicit maintenance when layout behaviours need updating.

### macOS color palette

**What it replaces**: `NSColor.windowBackgroundColor`, `NSColor.controlBackgroundColor` etc.
**Why**: Precise control over the surface hierarchy without depending on macOS default window appearance.

**Implication**: Values must be manually reviewed if macOS system defaults change significantly.

### App font scaling system

**What it replaces**: Native Dynamic Type live scaling
**Why**: The product adds a second scale dimension (user text size preference) on top of Dynamic Type. Native `@ScaledMetric` / `.font(.headline)` don't support an additional app-level scaling multiplier.

**Implication**: Font sizes are computed at view appearance time and do not update live with Dynamic Type changes during a session. This is an accepted trade-off.

### Rich text editing (Notes)

**What it replaces**: Native SwiftUI TextEditor
**Why**: Feature requirements (formatting, attributed text, viewport restoration, custom keyboard accessories) exceed what SwiftUI TextEditor provides.

**Implementation**: UIKit (`UITextView`) on iOS, AppKit (`NSTextView`) on macOS, each via `UIViewRepresentable` / `NSViewRepresentable` bridges.

### Liquid Glass chrome (iOS 26)

**What this extends**: System `.glassEffect`
**Why**: iOS 26's Liquid Glass is native and used as a first-class primitive. The `PhoneFloatingActionDock` already uses it. The adoption plan will extend it to additional chrome surfaces.

**Rule for agent**: Use `.glassEffect(...)` for chrome surfaces following the Liquid Glass adoption plan. Do not use system materials (`.regularMaterial`, etc.) for new surfaces targeted at iOS 26+.

---

## Decision guide for new UI

When building new UI, follow this decision tree:

1. **Does Apple provide a native component that fits?**
   - If yes: use it. Tier 1.

2. **Does a component in `Design/Components/` fit?**
   - If yes: use it. Tier 2 or existing Tier 3.

3. **Does a native component almost fit, needing minor adaptation?**
   - If yes: use the native component as a base and add the minimum wrapper. Tier 2.

4. **Is there no native or existing option?**
   - Use DesignTokens for all values.
   - Build the smallest component that solves the problem.
   - Add it to `Design/Components/` if it will be reused.
   - Document the departure from native. Tier 3.

---

## What customisation is not worth the cost

Do not build custom versions of these unless there is a documented, product-critical reason:

- Toggle, picker, slider, stepper
- Alert and confirmation dialogs
- Sheet presentation and dismissal
- Tab bar (iPhone navigation)
- Scroll behaviour
- Text field autocorrect, autocapitalisation, spell-check
- Keyboard type handling
- System colour adaptation for dark mode (on iOS)
- Accessibility label inheritance from native controls

---

## Open questions

- Should future layout work revisit `NavigationSplitView` for iPad-specific views, or is the custom implementation locked in?
- Should the macOS color palette attempt to use more system-semantic NSColor values in a future pass?
- Should the font scaling system be updated to better support live Dynamic Type updates?

---

## Related docs

- [Design Principles](./principles)
- [Platform Strategy Overview](./platform-strategy/overview)
- [System Framework Usage Audit](./audits/system-framework-usage-audit)
- [Materials and Appearance](./foundations/materials-and-appearance)
- `foundations/colour.md` (to be created)
