# Token Audit

- Status: drafted
- Owner: AI coding agent
- Inputs needed: codebase inspection (complete)
- Outputs: this doc
- Dependencies: current-ui-audit.md
- Codebase review required: yes (complete)
- Human judgement required: yes - to decide which hard-coded values become tokens and where the token system should be extended

---

## Purpose

Document every token and token-like abstraction in the current sideBar iOS/macOS codebase. Identify what is working, what is missing, and where hard-coded values should be standardised.

---

## Token system overview

The token system is split across three files:

| File | Role |
|---|---|
| `Design/DesignTokens.swift` | Primary token enum. Spacing, Radius, Size, Icon, Colors, Animation, Typography. |
| `Views/Common/Color+Platform.swift` | MacOS-specific NSColor palette + Color extension with `app*` and `platform*` values. |
| `Design/PlatformTokens.swift` | Single-value enum. Only defines `panelHeaderBackground`. Effectively vestigial. |
| `Design/SidebarTypography.swift` | Semantic typography aliases for sidebar list rows. |

---

## DesignTokens.Spacing

All values in CGFloat. Scale: 2, 4, 6, 8, 10, 12, 14, 16, 20, 24, 32.

```swift
enum Spacing {
    static let xxxs: CGFloat = 2
    static let xxs:  CGFloat = 4
    static let xxsPlus: CGFloat = 6
    static let xs:   CGFloat = 8
    static let xsPlus: CGFloat = 10
    static let sm:   CGFloat = 12
    static let smPlus: CGFloat = 14
    static let md:   CGFloat = 16
    static let lg:   CGFloat = 20
    static let xl:   CGFloat = 24
    static let xxl:  CGFloat = 32
}
```

**Coverage**: Good. The scale covers the full range of spacing values visible in components.

**Gaps / drift**:
- `PanelHeader.swift:45` uses `VStack spacing: 2` (= `xxxs`) but references it as a bare literal.
- `PhoneFloatingActionMetrics.contentSpacing = 6` matches `xxsPlus` but is a separate constant.
- `PhoneFloatingActionDivider` uses `frame(height: 12)` matching `sm` but as a literal.
- `SidebarRail` uses `VStack(spacing: 16)` (= `md`) and `VStack(spacing: 12)` (= `sm`) as literals.
- Several padding values in `WorkspaceLayout` are literals that match existing tokens.

**Verdict**: The scale is correct. The problem is adoption: several spots in `Views/` still use literals that match tokens but don't reference them.

---

## DesignTokens.Radius

Scale: 6, 8, 10, 14, 16, 18, 24, 32.

```swift
enum Radius {
    static let xs:     CGFloat = 6
    static let xsPlus: CGFloat = 8
    static let sm:     CGFloat = 10
    static let md:     CGFloat = 14
    static let mdPlus: CGFloat = 16
    static let lg:     CGFloat = 18
    static let xl:     CGFloat = 24
    static let xxl:    CGFloat = 32
}
```

**Coverage**: Good.

**Gaps / drift**:
- `SidebarRail.swift:109` uses `cornerRadius: 8` (matches `xsPlus`) as a literal.
- `SelectableRow.swift` uses `DesignTokens.Radius.sm` correctly.
- `SearchField.swift` uses `DesignTokens.Radius.sm` correctly.
- `CardModifier.swift` uses `DesignTokens.Radius.md` correctly.

**Verdict**: Token adoption is good in `Design/` components. Drift is localised to feature views, especially `SidebarRail`.

---

## DesignTokens.Size

Four values covering structural layout dimensions.

```swift
enum Size {
    static let touchTarget:    CGFloat = 44
    static let sidebarWidth:   CGFloat = 280
    static let panelMinWidth:  CGFloat = 320
    static let contentMaxWidth: CGFloat = 520
}
```

**Coverage**: Partial. The most-used layout constants are not here.

**Gaps**:
- `WorkspaceLayout.swift` has `railWidth: 56`, `dividerWidth: 8`, `defaultRightSidebarWidth: 360`, `minRightSidebarWidth: 280` as private constants. `minRightSidebarWidth = 280` matches `sidebarWidth` but doesn't reference it.
- `SidebarRail.swift` has `.frame(width: 56)` hardcoded. Should match a `Size.railWidth` token.
- `SidebarSplitView.swift` has `railWidth = 56`, `dividerWidth = 8`, `minPanelWidth = 200`, `maxPanelWidth = 500` as private constants. These duplicate `WorkspaceLayout` values.
- Profile avatar in Settings is `.frame(width: 56, height: 56)` - matches rail width by coincidence.
- No token for `defaultRightSidebarWidth = 360`.

**Verdict**: Needs extension. At minimum add `railWidth = 56`, `dividerWidth = 8`, and a right sidebar default width.

---

## DesignTokens.Icon

```swift
enum Icon {
    static let sm:  CGFloat = 14
    static let md:  CGFloat = 18
    static let lg:  CGFloat = 24
    static let xl:  CGFloat = 32
    static let xxl: CGFloat = 40
}
```

**Coverage**: Partial. The values 20, 28, and 30 appear in views but have no token.

**Gaps / drift**:

| Observed size | Token | Files using it |
|---|---|---|
| 14 | `Icon.sm` | - |
| 18 | `Icon.md` | `SettingsSections+Additional.swift` (as literal) |
| 20 | none | `TasksViewComponents.swift` (multiple) |
| 24 | `Icon.lg` | `TasksViewComponents.swift` (literal) |
| 28 | none | `TasksDetailView.swift` |
| 30 | none | `StoreSkillCredentialsView.swift` |
| 32 | `Icon.xl` | `SidebarRail.swift` (literal), `SettingsSections+Utilities.swift` (literal) |
| 40 | `Icon.xxl` | - |

**Verdict**: Add `Icon.mdPlus = 20` or audit whether 20px usage should be 18 or 24. The 28 and 30 values look like one-off sizing that should be resolved to the nearest token.

---

## DesignTokens.Animation

```swift
enum Animation {
    static let quick:    Double = 0.15
    static let standard: Double = 0.25
    static let slow:     Double = 0.4
}
```

**Coverage**: Good. These are used consistently via the `Motion` enum.

**Motion enum** (`Design/Motion.swift`):
```swift
enum Motion {
    static func quick(reduceMotion: Bool) -> Animation? { ... }
    static func standard(reduceMotion: Bool) -> Animation? { ... }
}
```

The `Motion` enum wraps `DesignTokens.Animation` values and gates them behind `accessibilityReduceMotion`. This is the correct abstraction. All animations should use `Motion.*` not raw `DesignTokens.Animation.*` constants.

**Gap**: No `slow` helper in `Motion` despite `Animation.slow = 0.4` existing.

---

## DesignTokens.Typography

A set of static font vars using explicit point sizes scaled via `AppTextSizeOption.currentScaleMultiplier`.

**Problem**: This is a parallel system to `AppFontStyle`. Both produce `Font` values. `DesignTokens.Typography` is used in some places, `.appFont()` (via `AppFontStyle`) in others. The view modifier `.appFont(.labelMd)` is the ergonomic form and appears to be the intended direction. `DesignTokens.Typography` looks like it was the earlier approach.

**Recommendation**: Consolidate. `AppFontStyle` with `.appFont()` is the correct interface. `DesignTokens.Typography` should either be removed or aliased through `AppFontStyle`. Human judgement required on migration strategy.

---

## DesignTokens.Colors

Semantic color aliases that resolve to `Color+Platform.swift` values.

```swift
enum Colors {
    static let background      = Color.appBackground
    static let surface         = Color.appSurface
    static let muted           = Color.appMuted
    static let sidebar         = Color.appSidebar
    static let sidebarAccent   = Color.appSidebarAccent
    static let border          = Color.appBorder
    static let input           = Color.appInput
    static let textPrimary     = Color.primary
    static let textSecondary   = Color.secondary
    static let textTertiary    = Color.platformTertiaryLabel
    static let selection       = Color.appSelection         // accentColor at 0.18
    static let success         = textPrimary
    static let successBackground = muted.opacity(0.55)
    static let warning         = textSecondary
    static let warningBackground = muted.opacity(0.55)
    static let error           = Color.red
    static let errorBackground = Color.red.opacity(0.1)
    static let errorSurface    = Color.red.opacity(0.12)
    static let errorBorder     = Color.red.opacity(0.2)
    static let actionPrimary   = Color.blue
    static let actionDestructive = Color.red
    static let settingsBackground    = Color.appSettingsBackground
    static let settingsFormBackground = Color.appSettingsFormBackground
    static var sidebarRowBackground: Color { .clear }
    static func sidebarRowBackground(isSelected: Bool) -> Color { ... }
}
```

**Coverage**: Good for the structural and semantic roles used in the app.

**Observations**:
- `success` and `warning` both alias to text colors rather than semantic status colours. This is intentional (the UI uses neutral success/warning states) but may be worth reviewing.
- `actionPrimary = Color.blue` and `actionDestructive = Color.red` are raw SwiftUI named colors, not system semantic values. On iOS, `Color.blue` adapts for dark mode but is not the same as `UIColor.tintColor`. Consider aliasing through system values.
- No token for `Color.accentColor` (the app tint). The selection token uses it as a base but the primary accent color has no direct token alias.

---

## Color+Platform.swift (underlying layer)

Provides two layers:

**iOS layer**: Wrappers around UIKit semantic colors (`UIColor.systemBackground`, `.secondarySystemBackground`, `.separator`, `.tertiaryLabel`). These are correctly using system-provided adaptive colors.

**macOS layer**: `MacOSPalette` with hand-coded sRGB NSColor values:
- `background`: white / #0a0a0a
- `card`: white / #171717
- `muted`: #f5f5f5 / #262626
- `sidebar`: #fafafa / #171717
- `sidebarAccent`: #f5f5f5 / #262626
- `border`: #e5e5e5 / white at 10% opacity
- `input`: #e5e5e5 / white at 15% opacity

These are near-neutral grays. They appear to be hand-tuned rather than pulled from Apple's named macOS colors (`NSColor.windowBackgroundColor`, `NSColor.controlBackgroundColor`, etc.). This gives precise control but requires manual maintenance when macOS system colors shift.

---

## SidebarTypography

```swift
enum SidebarTypography {
    static let primary:       AppFontStyle = .body
    static let secondary:     AppFontStyle = .caption
    static let tertiary:      AppFontStyle = .caption2
    static let sectionHeader: AppFontStyle = .labelMd
}
```

Semantic aliases for sidebar list row typography roles. Short, clear, correct. This is a good pattern.

**Coverage**: Limited to sidebar rows. Similar aliasing could be useful for other repeated typography contexts (chat messages, settings rows, etc.).

---

## PlatformTokens.swift

```swift
enum PlatformTokens {
    static var panelHeaderBackground: Color {
        DesignTokens.Colors.sidebar
    }
}
```

One value. A direct alias for `DesignTokens.Colors.sidebar` with a different name. This adds no value and creates confusion about which to use. Should be removed and callers updated to use `DesignTokens.Colors.sidebar` directly.

---

## Hard-coded values that should become tokens

Summary of gaps where new tokens are needed:

| Gap | Proposed token |
|---|---|
| Rail width 56px | `DesignTokens.Size.railWidth = 56` |
| Divider width 8px | `DesignTokens.Size.dividerWidth = 8` |
| Right sidebar default 360px | `DesignTokens.Size.rightSidebarDefaultWidth = 360` |
| Icon frame 20px | `DesignTokens.Icon.mdPlus = 20` (or audit usage) |
| Large inspector sheet max width 1120px | `DesignTokens.Size.largeInspectorMaxWidth = 1120` |

---

## Redundancies to remove

| Redundancy | Action |
|---|---|
| `DesignTokens.Typography` vs `AppFontStyle` | Consolidate - remove or alias `DesignTokens.Typography` |
| `PlatformTokens.panelHeaderBackground` | Remove - use `DesignTokens.Colors.sidebar` directly |

---

## What is working well

- The token structure is clean and covers the main visual dimensions.
- `DesignTokens` is the right abstraction layer between raw values and usage.
- The `Color+Platform.swift` file correctly bridges iOS system semantics with macOS custom values in one place.
- `SidebarTypography` demonstrates a good pattern for semantic role aliasing.
- The two-layer colour architecture (semantic tokens over platform-specific values) is sound and worth preserving.

---

## Open questions

- Should `actionPrimary` and `actionDestructive` map to system-provided interactive colors rather than raw named colors?
- Should the macOS palette attempt to use more system-semantic NSColor values, or is manual control intentional?
- Is `DesignTokens.Typography` still in active use anywhere, or is it safe to remove?
- Should `Motion.slow` be added to the `Motion` enum to match `Animation.slow`?

---

## Related docs

- `audits/current-ui-audit.md`
- `audits/component-inventory.md`
- `foundations/token-model.md` (to be created)
- `foundations/colour.md` (to be created)
- `foundations/typography.md` (to be created)
