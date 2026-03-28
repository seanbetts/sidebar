---
title: Token Model
description: The token architecture, all token scales, usage rules, and known gaps for the sideBar design system.
---

| Field | Value |
|---|---|
| Status | draft |
| Owner | AI coding agent |
| Outputs | this doc |
| Dependencies | [token-audit](../audits/token-audit), [colour](./colour), [system-inheritance](../system-inheritance) |

## Purpose

Define the token system for sideBar: the named values that sit between raw numbers and component code. Tokens make the design system consistent, refactorable, and self-documenting.

This document covers the structural and numeric tokens (spacing, radius, size, icon, animation). Color tokens are defined in `foundations/colour.md`. Typography is defined in `foundations/typography.md`.

---

## Architecture

The native token system is layered. Components and views should only reference layer 2 — never the raw layer directly.

| Layer | Role | Key files |
|---|---|---|
| **1. Raw values** | Named numeric and color constants with no semantic meaning | `DesignTokens.swift`, `Color+Platform.swift` |
| **2. Semantic aliases** | Intent-named wrappers over raw values — the interface views use | `DesignTokens.Colors`, `SidebarTypography`, `AppFontStyle / .appFont()` |
| **3. Usage** | Components and views — reference layer 2 only, never layer 1 directly | Views, `Design/` components |

**Rule**: Components and views must reference tokens, not raw literals. A value like `padding: 16` in a view is always wrong if `DesignTokens.Spacing.md` exists. This makes future design changes a single-line edit in `DesignTokens.swift` rather than a grep-and-replace.

**Web equivalent**: CSS custom properties in `frontend/src/app.css` serve the same role. The `--radius`, `--border`, spacing and color variables are the web token layer. These should stay aligned with the native tokens as both evolve.

---

## Spacing

All values in `CGFloat`. Used for padding, gaps, and margins.

| Token | Value | Common use |
|---|---|---|
| `Spacing.xxxs` | 2 | Icon-to-label gaps, tight stacks |
| `Spacing.xxs` | 4 | Dense list item internals |
| `Spacing.xxsPlus` | 6 | Small component padding |
| `Spacing.xs` | 8 | Standard compact padding |
| `Spacing.xsPlus` | 10 | Slightly relaxed compact padding |
| `Spacing.sm` | 12 | Default component padding |
| `Spacing.smPlus` | 14 | Slightly relaxed component padding |
| `Spacing.md` | 16 | Standard panel padding, row height base |
| `Spacing.lg` | 20 | Generous padding, section gaps |
| `Spacing.xl` | 24 | Large section separation |
| `Spacing.xxl` | 32 | Page-level spacing, major section breaks |

**Status**: Scale is correct and complete. Adoption is the problem — several views use literals that match existing tokens but do not reference them. See [implementation-gaps](../implementation-gaps) for specific files.

---

## Radius

All values in `CGFloat`. Used for `cornerRadius` on shapes, buttons, and cards.

| Token | Value | Common use |
|---|---|---|
| `Radius.xs` | 6 | Small chips, badges |
| `Radius.xsPlus` | 8 | Buttons, row highlights |
| `Radius.sm` | 10 | Cards, input fields, popovers |
| `Radius.md` | 14 | Sheets, larger cards |
| `Radius.mdPlus` | 16 | Prominent cards, floating surfaces |
| `Radius.lg` | 18 | Modal panels |
| `Radius.xl` | 24 | Large modals, floating docks |
| `Radius.xxl` | 32 | Full pill shapes |

**Status**: Scale is correct. Token adoption is good in `Design/` components. Localised drift in feature views — mainly `SidebarRail.swift` using `cornerRadius: 8` literally instead of `Radius.xsPlus`.

---

## Size

Structural layout dimensions. Not spacing or radius — these are fixed widths, heights, and minimum sizes that define the app's layout skeleton.

| Token | Value | Notes |
|---|---|---|
| `Size.touchTarget` | 44 | Minimum interactive element size (iOS HIG) |
| `Size.sidebarWidth` | 280 | Left panel width |
| `Size.panelMinWidth` | 320 | Minimum panel width before layout collapses |
| `Size.contentMaxWidth` | 520 | Maximum content column width |
| `Size.railWidth` | 56 | Sidebar rail width |
| `Size.dividerWidth` | 8 | Split view divider width |
| `Size.rightSidebarDefaultWidth` | 360 | Right sidebar default width |

**Note on the 56px profile avatar**: The settings profile avatar uses `.frame(width: 56, height: 56)` which matches `railWidth` by coincidence. These should remain independent values — rail width and avatar size happen to be the same number but are unrelated concerns.

---

## Icon

Icon frame sizes in `CGFloat`. These define the hit area or visual frame of icons, not the SF Symbol weight or rendering size.

| Token | Value | Common use |
|---|---|---|
| `Icon.sm` | 14 | Inline status icons, small decorative icons |
| `Icon.md` | 18 | Standard toolbar and list icons |
| `Icon.lg` | 24 | Prominent action icons |
| `Icon.xl` | 32 | Section header icons, large actions |
| `Icon.xxl` | 40 | Splash or onboarding icons |

**Exception — app logo**: `SidebarRail.swift` uses 26px for the app logo image frame. This is intentional — the logo is sized to sit comfortably in the 56px rail without being as large as a section icon. It should be a component-local constant (`SidebarRail.logoSize = 26`), not a global token.

---

## Animation

Duration values in `Double` (seconds). Not used directly — always accessed through the `Motion` enum which gates them behind `accessibilityReduceMotion`.

| Token | Value | Use |
|---|---|---|
| `Animation.quick` | 0.15s | Micro-interactions, hover states |
| `Animation.standard` | 0.25s | Most transitions and reveals |
| `Animation.slow` | 0.40s | Large layout changes, entrance animations |

**Rule**: Never use `DesignTokens.Animation.*` values directly in views. Always use `Motion.quick(reduceMotion:)`, `Motion.standard(reduceMotion:)`, or `Motion.slow(reduceMotion:)`. The `Motion` enum is the correct interface — it handles reduce-motion accessibility automatically.

**Rule**: Never use `DesignTokens.Animation.*` values directly in views. Always access durations via `Motion.*`.

---

## Semantic aliases

Beyond raw token values, two semantic alias layers exist for specific contexts:

### DesignTokens.Colors

Semantic color names (`background`, `surface`, `muted`, `border`, `textPrimary`, `selection`, `error`, etc.) that resolve to platform-appropriate values via `Color+Platform.swift`. This is the correct interface for all color usage in views — not raw `Color.*` values.

Full definition in [foundations/colour](./colour).

### SidebarTypography

Semantic typography roles for sidebar list rows:

| Token | Value |
|---|---|
| `SidebarTypography.primary` | `.appFont(.body)` |
| `SidebarTypography.secondary` | `.appFont(.caption)` |
| `SidebarTypography.tertiary` | `.appFont(.caption2)` |
| `SidebarTypography.sectionHeader` | `.appFont(.label)` |

This is a good pattern — it names the intent rather than the size. Similar aliasing could be useful for other repeated typography contexts (chat messages, settings rows). Tracked in `foundations/typography.md`.

---

## Redundancies to remove

| Item | Action |
|---|---|
| `DesignTokens.Typography` | Remove. Unused parallel system to `AppFontStyle`. All typography goes through `.appFont()`. |
| `PlatformTokens.panelHeaderBackground` | Remove. Single-value alias for `DesignTokens.Colors.sidebar`. Callers should use `DesignTokens.Colors.sidebar` directly. |

Both are tracked in [implementation-gaps](../implementation-gaps).

---

## Rules summary

1. **Spacing, radius, size, icon**: always reference `DesignTokens.*`. Never use bare literals that match an existing token.
2. **Color**: always use `DesignTokens.Colors.*`. Never use raw `Color.black`, `Color.white`, or other literal colors in views.
3. **Typography**: always use `.appFont()`. Never use `.font(.system(size:weight:))` in views.
4. **Animation**: always use `Motion.*`. Never use `DesignTokens.Animation.*` directly or bare `.animation(.easeInOut(duration: 0.25))`.
5. **New values**: if a value is used in more than one place and has a clear semantic meaning, it belongs in `DesignTokens`. If it is specific to one component, make it a local constant in that component.

---

## Related docs

- [Token Audit](../audits/token-audit)
- [Colour](./colour)
- [Implementation Gaps](../implementation-gaps)
- [Typography](./typography)
