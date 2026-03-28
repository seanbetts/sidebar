---
title: System Framework Usage Audit
description: Draft audit of where sideBar uses native Apple frameworks well and where custom UI departs from them.
---

| Field | Value |
|---|---|
| Status | drafted |
| Owner | AI coding agent |
| Inputs needed | codebase inspection (complete) |
| Outputs | this doc |
| Dependencies | [current-ui-audit](./current-ui-audit) |
| Codebase review required | yes (complete) |
| Human judgement required | yes - to decide where to adopt more native components vs retain custom implementations |

## Purpose

Document how sideBar uses Apple's native frameworks. Identify where native frameworks are being used well, where custom UI is fighting the platform, and where we are reinventing things Apple already provides.

---

## Framework usage overview

sideBar is primarily SwiftUI. UIKit and AppKit are used for:
- Rich text editing (notes)
- Platform-specific input surfaces (chat input on Mac)
- UIKit bridge components (image picker, Safari view, menu button)
- Low-level UIKit APIs (keyboard notifications, responder chain)

The codebase targets iOS 26 / macOS 26, giving access to all current framework capabilities including Liquid Glass.

---

## SwiftUI adoption

### Where SwiftUI is used well

**Adaptive layout**: The compact/regular split (`horizontalSizeClass == .compact`) cleanly branches between `TabView` and `WorkspaceLayout`. This is the correct SwiftUI approach.

**Environment propagation**: `@EnvironmentObject var environment: AppEnvironment` is used throughout rather than prop drilling. `@Environment(\.colorScheme)`, `@Environment(\.accessibilityReduceMotion)`, `@Environment(\.scenePhase)` are all used correctly.

**AppStorage**: `@AppStorage` is used consistently for persisted user preferences (sidebar width, text size, biometric settings, workspace state). No manual UserDefaults calls visible in views.

**Safe area handling**: `safeAreaInset(edge: .bottom)` is used correctly for the iPhone search dock and floating action dock.

**Presentation**: `.sheet`, `.fullScreenCover`, `.presentationDragIndicator`, `.presentationSizing` are used natively. Platform-specific overrides (grab bar visibility) are handled via thin modifier wrappers.

**SF Symbols**: Used throughout for all navigation icons and action icons. Correct use of `Image(systemName:)` and `.symbolVariant(.none)`.

**Accessibility**: `.accessibilityLabel`, `.accessibilityValue`, `.accessibilityAddTraits` are applied on navigation and selection elements. `@Environment(\.accessibilityReduceMotion)` controls animations.

**Animation**: `withAnimation`, `.animation(_:value:)` used correctly. Motion helpers respect reduce motion.

**Transitions**: `.transition(.move(edge: .bottom).combined(with: .opacity))` used for dock appearance.

**Keyboard handling**: Keyboard show/hide notification subscriptions correctly track software keyboard visibility.

### Where SwiftUI could be more native

**Navigation**: The split view layout (`SidebarRail` + custom panels + `WorkspaceLayout`) is a fully custom implementation. SwiftUI's `NavigationSplitView` was not adopted. The custom implementation is more flexible (drag-to-resize, three columns, custom snap behaviour) but adds maintenance cost and doesn't inherit future platform improvements automatically.

**Note**: `NavigationSplitView` may not have provided adequate flexibility for sideBar's three-column workspace model with drag-to-resize. The custom approach may have been the right call. This is a human judgement question.

**List**: Native `List` is used in panel sections. This is correct. No evidence of manual `ForEach` + scroll containers where `List` would be more appropriate.

**Toolbar**: On iPhone, native `.toolbar` and `ToolbarItem` are used for chat navigation actions. On iPad/Mac, toolbar-like controls are embedded in the custom header row. There is no use of SwiftUI `ToolbarItem` on the Mac or iPad - those are handled by custom `PanelHeader` + `HeaderActionIcon` patterns.

**Settings form**: Settings uses `Form` with `.formStyle(.grouped)` on Mac correctly. iOS settings also uses `Form`.

**Search**: sideBar uses a custom `SearchField` component rather than `.searchable`. The custom approach gives more control (dock chrome variant, positioning above tab bar) but doesn't inherit system search behaviour.

---

## UIKit usage

### UIKit bridge components

These are correct uses of UIKit where SwiftUI doesn't provide adequate native capabilities:

| Component | UIKit API | Reason |
|---|---|---|
| `UIKitNoteTextEditorSurface` | `UITextView` (attributed) | Rich text editing with custom formatting |
| `UIKitNoteFormattingBar` | Custom UIView | Formatting toolbar requiring UIKit layout |
| `ChatInputUIKit` | UIKit text input | Reliable text input on iOS |
| `AttributedNoteEditorContainer` | `UIViewRepresentable` | NSAttributedString editing |
| `SafariView` | `SFSafariViewController` | Full Safari experience |
| `ImagePicker` | `UIImagePickerController` | Photo library access |
| `UIKitMenuButton` | `UIButton` with menu | UIKit menu button not yet in SwiftUI |

### Direct UIKit API usage (not wrapped)

- `UIDevice.current.userInterfaceIdiom` - device type detection. Used in several places. Could be centralised.
- `UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder))` - keyboard dismiss. Used in `ContentView+Layout.swift`.
- `UIFont.preferredFont(forTextStyle:)` - Dynamic Type point size queries in `AppFontStyle` and `DesignTokens.Typography`. This is correct - SwiftUI doesn't expose the raw point size needed for the custom scaling system.
- Keyboard notification names (`UIResponder.keyboardWillShowNotification`) - for keyboard height tracking.

### Where UIKit is fighting SwiftUI

The notes editor surface has three implementations (`UIKitNoteTextEditorSurface`, `SwiftUINoteTextEditorSurface`, `AppKitNoteTextEditorSurface`) plus significant bridging complexity. The UIKit surface has accessory views, viewport restoration, attributed text handling, and formatting support, all bridged via `UIViewRepresentable`. This is complex but appears necessary for the feature requirements.

---

## AppKit usage

### AppKit bridge components

| Component | AppKit API | Reason |
|---|---|---|
| `AppKitNoteTextEditorSurface` | `NSTextView` | Rich text editing on macOS |
| `AppKitNoteFormattingBar` | Custom NSView | macOS formatting toolbar |
| `AppKitNoteFormattingPopoverView` | NSPopover | macOS-native popover for formatting |
| `ChatInputAppKit` | AppKit text input | Reliable text input on macOS |

### Direct AppKit usage

- `NSColor` - used in `Color+Platform.swift` for macOS color palette. Correct - SwiftUI Color alone can't define the same adaptive NSColor-backed dynamic colors needed for macOS.
- `NSFont.preferredFont(forTextStyle:)` - Dynamic Type point size queries in font system.

---

## System materials

### Current Liquid Glass usage

iOS 26 / macOS 26 Liquid Glass (`.glassEffect`) is currently used in:

- `PhoneFloatingActionDock`: `.glassEffect(.regular.interactive(), in: Capsule())` - the iPhone floating action container.

This is the only production Liquid Glass surface. The Liquid Glass adoption plan (`2026-03-27-apple-liquid-glass-adoption.md`) defines a rollout sequence for 12 more elements.

### System materials (pre-Liquid Glass)

No evidence of `.ultraThinMaterial`, `.regularMaterial`, or other `Material` usage outside of the Liquid Glass context. Most backgrounds use the `Color+Platform.swift` custom palette (solid colors). This is consistent with a deliberate design choice to use hand-tuned solid surfaces rather than system translucency.

---

## System colors

### iOS

Correctly using UIKit semantic colors via SwiftUI:
- `.systemBackground` for primary background
- `.secondarySystemBackground` for surface/elevated content
- `.systemGroupedBackground` for settings page background
- `.secondarySystemGroupedBackground` for form background
- `.separator` for borders/dividers
- `.tertiaryLabel` for tertiary text
- `Color.primary` / `Color.secondary` for text

### macOS

Using hand-coded sRGB `NSColor` values via `MacOSPalette`. These approximate macOS system semantics but are not using the actual macOS named colors like `NSColor.windowBackgroundColor`, `NSColor.controlBackgroundColor`, `NSColor.separatorColor`. The separator color in `SidebarRail` does use `NSColor.separatorColor` correctly, which creates a minor inconsistency.

**Implication**: The macOS color values may drift from macOS system appearance updates (e.g. if Apple changes the default window background tint). This is a maintenance risk worth documenting.

---

## Dynamic Type

### Current state

The app implements a custom text size system (`AppTextSizeOption`) layered on top of Dynamic Type rather than using SwiftUI's built-in Dynamic Type scaling directly.

The font system:
1. Reads `UIFont.preferredFont(forTextStyle:).pointSize` to get the current Dynamic Type size as a base
2. Multiplies by `AppTextSizeOption.currentScaleMultiplier` (user preference)
3. Returns a fixed-size `.system(size: scaledSize)` font

**What this means**: The app does not use `.font(.headline)` or `.font(.body)` native text styles directly. It reads the current Dynamic Type size at initialization and scales it, but the resulting fonts are not `@ScaledMetric` or `RelativeSize`-based. They will not update live if the user changes Dynamic Type size while the app is running (would require app restart or view reinit).

This is a deliberate choice to add a second scale dimension (app text size preference) on top of Dynamic Type. The trade-off is reduced Dynamic Type fidelity (no live updates, no full range support) for user-controlled text size preference.

---

## SF Symbols

Used throughout as the icon system. No custom icon assets visible in the navigation or action layer.

Current symbol usage by section:
- Chat: `bubble`
- Notes: `text.document`
- Files: `folder`
- Websites: `globe`
- Tasks: `checkmark.square`
- Skills Store: `command.circle`
- Settings toggle: profile avatar (custom view)
- Search: `magnifyingglass`, `xmark.circle.fill`
- Actions: `plus`, `square.and.pencil`, `folder`, `checkmark.circle`, `list.bullet.rectangle`, `play.rectangle`

`.symbolVariant(.none)` is used on tab items to prevent automatic variant application. This is correct.

Icon weight is set via `.font(.system(size: 18, weight: .semibold))` in `SidebarRail` rather than via `.imageScale` or a symbol configuration. This is the token violation flagged in the current UI audit.

---

## Keyboard shortcuts

`onKeyPress(.escape)` used in compact layout to dismiss search dock. The `KeyboardShortcuts/` folder suggests broader shortcut management.

---

## Accessibility

Native accessibility behaviours inherited:
- `TabView` tab item accessibility is native
- `List` row accessibility is native
- `Toggle`, `Picker`, `Button` accessibility is native
- `.sheet` focus management is native

Explicit accessibility additions:
- `.accessibilityLabel` on `SidebarRail` navigation buttons
- `.accessibilityValue("Selected")` and `.accessibilityAddTraits(.isSelected)` on active rail items
- `.accessibilityLabel` on all `PhoneFloatingActionButton` instances
- `@Environment(\.accessibilityReduceMotion)` used to suppress animations

Gap: `.accessibilityLabel` coverage in chat message rows, notes list rows, and task rows is not visible from the files inspected. This needs further audit.

---

## Where we get platform behaviour for free (document, don't recreate)

These platform capabilities are already available via native components and should not be reimplemented:

| Capability | How we get it |
|---|---|
| Dark mode color adaptation | System semantic colors on iOS; NSColor dynamic colors on macOS |
| Tab bar appearance | Native `TabView` |
| Sheet dismissal gestures | Native `.sheet` |
| Form keyboard avoidance | Native `Form` |
| Context menu long-press | Native `Menu` / `.contextMenu` |
| List swipe actions | Native `.swipeActions` |
| Toggle/picker state | Native SwiftUI controls |
| Alert accessibility | Native `.alert` |
| Keyboard type/autocorrect | Native `TextField` attributes |

---

## Where custom UI is fighting the platform

1. **Navigation splitting**: Custom three-column layout vs `NavigationSplitView`. The custom approach is more flexible but bypasses system navigation behaviours (e.g. automatic column collapse on narrow screens, system back button behaviour in some edge cases).

2. **Search**: Custom `SearchField` vs `.searchable`. The custom implementation correctly handles the dock placement, but doesn't integrate with system search history or Spotlight.

3. **Font scaling**: Custom `AppTextSizeOption` layer vs native `@ScaledMetric` / Dynamic Type. The custom approach adds user preference, but loses live Dynamic Type update behaviour.

4. **macOS colors**: Hand-coded palette vs system NSColor semantics. Precise control but no automatic adaptation if macOS changes defaults.

---

## What should stay native

- `TabView` for iPhone navigation - correct, preserve it
- `List` for panel lists - correct, preserve it
- Native `.sheet` / `.fullScreenCover` - correct
- `Form` / `.formStyle(.grouped)` for settings - correct
- `Toggle`, `Picker`, `Button` - correct
- SF Symbols - correct, expand usage

---

## What should move toward native

- Consider `NavigationSplitView` for future layout work on iPad (subject to flexibility requirements)
- Consider `.searchable` for any future search surfaces that don't need the dock placement model

---

## Open questions

- Does `NavigationSplitView` provide enough flexibility for the workspace layout model, or is the custom implementation necessary?
- Should the font system use `@ScaledMetric` for a future version that better supports live Dynamic Type updates?
- Is the macOS custom color palette the current approved design direction, or should it track system colors more closely?
- Are there accessibility gaps in list rows and chat message accessibility labels?

---

## Related docs

- `audits/current-ui-audit.md`
- `audits/component-inventory.md`
- [System Inheritance](../system-inheritance)
- [iOS Conventions](../platform-strategy/ios-conventions)
- [macOS Conventions](../platform-strategy/macos-conventions)
