---
title: Colour
description: Unified color palette and semantic token layer for sideBar across iOS, macOS, and web.
---

| Field | Value |
|---|---|
| Status | draft |
| Owner | AI coding agent |
| Outputs | this doc |
| Dependencies | [token-audit](../audits/token-audit), [system-inheritance](../system-inheritance), [macos-conventions](../platform-strategy/macos-conventions), [web-conventions](../platform-strategy/web-conventions) |

## Purpose

Define the single unified color palette for sideBar across all platforms (iOS, macOS, web). This document is the canonical source of truth for all color values. Platform-specific color files (`Color+Platform.swift`, `app.css`) should be derived from or aligned with the values defined here.

---

## Palette direction

sideBar uses a **near-neutral palette**: near-white in light mode, near-black in dark mode, with no chromatic hue in the base surfaces. The palette is the same across all platforms — there are no iOS-specific or macOS-specific background colors, and no separate dark mode variants per platform.

**The canonical values are drawn from the current macOS implementation.** The macOS palette is the reference because it was hand-crafted to the correct aesthetic. iOS currently diverges (UIKit semantic colors), and web diverges slightly (OKLCH approximations). Both should be migrated to match the canonical values.

Accent and system colors (action states, error, success) are documented separately below.

---

## Surface palette

<div style="display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin: 24px 0; font-family: -apple-system, BlinkMacSystemFont, sans-serif;">
  <div>
    <div style="font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.07em; color: #888; margin-bottom: 10px;">Light mode</div>
    <div style="border-radius: 10px; overflow: hidden; box-shadow: 0 0 0 1px #e0e0e0;">
      <div style="background: #fafafa; padding: 11px 14px; display: flex; justify-content: space-between; align-items: center;">
        <span style="font-size: 13px; color: #333;">sidebar</span>
        <span style="font-size: 11px; font-family: monospace; color: #aaa;">#fafafa</span>
      </div>
      <div style="background: #ffffff; padding: 11px 14px; display: flex; justify-content: space-between; align-items: center; box-shadow: 0 -1px 0 #efefef;">
        <span style="font-size: 13px; color: #333;">background · surface</span>
        <span style="font-size: 11px; font-family: monospace; color: #aaa;">#ffffff</span>
      </div>
      <div style="background: #f5f5f5; padding: 11px 14px; display: flex; justify-content: space-between; align-items: center; box-shadow: 0 -1px 0 #eaeaea;">
        <span style="font-size: 13px; color: #333;">muted · sidebarAccent</span>
        <span style="font-size: 11px; font-family: monospace; color: #aaa;">#f5f5f5</span>
      </div>
      <div style="background: #e5e5e5; padding: 11px 14px; display: flex; justify-content: space-between; align-items: center; box-shadow: 0 -1px 0 #ddd;">
        <span style="font-size: 13px; color: #333;">border · input</span>
        <span style="font-size: 11px; font-family: monospace; color: #aaa;">#e5e5e5</span>
      </div>
    </div>
  </div>
  <div>
    <div style="font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.07em; color: #888; margin-bottom: 10px;">Dark mode</div>
    <div style="border-radius: 10px; overflow: hidden; box-shadow: 0 0 0 1px #2a2a2a;">
      <div style="background: #171717; padding: 11px 14px; display: flex; justify-content: space-between; align-items: center;">
        <span style="font-size: 13px; color: #bbb;">sidebar · surface</span>
        <span style="font-size: 11px; font-family: monospace; color: #555;">#171717</span>
      </div>
      <div style="background: #0a0a0a; padding: 11px 14px; display: flex; justify-content: space-between; align-items: center; box-shadow: 0 -1px 0 #1c1c1c;">
        <span style="font-size: 13px; color: #bbb;">background</span>
        <span style="font-size: 11px; font-family: monospace; color: #555;">#0a0a0a</span>
      </div>
      <div style="background: #262626; padding: 11px 14px; display: flex; justify-content: space-between; align-items: center; box-shadow: 0 -1px 0 #1a1a1a;">
        <span style="font-size: 13px; color: #bbb;">muted · sidebarAccent</span>
        <span style="font-size: 11px; font-family: monospace; color: #555;">#262626</span>
      </div>
      <div style="background: #0a0a0a; padding: 11px 14px; display: flex; justify-content: space-between; align-items: center; box-shadow: 0 -1px 0 #1a1a1a;">
        <div style="display: flex; align-items: center; gap: 8px;">
          <div style="width: 20px; height: 20px; border-radius: 4px; border: 1px solid rgba(255,255,255,0.10); background: rgba(255,255,255,0.10);"></div>
          <span style="font-size: 13px; color: #bbb;">border</span>
        </div>
        <span style="font-size: 11px; font-family: monospace; color: #555;">rgba(255,255,255,0.10)</span>
      </div>
    </div>
  </div>
</div>

| Role | Semantic token | Light | Dark | Notes |
|---|---|---|---|---|
| App background | `background` | `#ffffff` | `#0a0a0a` | Base canvas |
| Card / surface | `surface` | `#ffffff` | `#171717` | Elevated card, sheet, secondary panel |
| Muted fill | `muted` | `#f5f5f5` | `#262626` | Subtle fill, section backgrounds |
| Sidebar panel | `sidebar` | `#fafafa` | `#171717` | Left panel and rail background |
| Sidebar accent | `sidebarAccent` | `#f5f5f5` | `#262626` | Hovered/active row in sidebar |
| Divider / border | `border` | `#e5e5e5` | `rgba(255,255,255,0.10)` | Structural lines, component borders |
| Input background | `input` | `#e5e5e5` | `rgba(255,255,255,0.15)` | Text input fill |

---

## Text palette

Text colors are resolved from system primitives — they do not have custom hex values and adapt correctly to accessibility settings (high contrast, etc.).

| Role | Semantic token | Native source | Notes |
|---|---|---|---|
| Primary text | `textPrimary` | `Color.primary` | Default body text |
| Secondary text | `textSecondary` | `Color.secondary` | Supporting labels, captions |
| Tertiary text | `textTertiary` | `platformTertiaryLabel` | De-emphasised text, placeholders |

On web, text is defined as `--foreground` (oklch near-black/near-white) and `--muted-foreground` (oklch mid-grey). These should track the native visual weight rather than exact luminance equivalents.

---

## State and action colors

<div style="display: flex; gap: 12px; flex-wrap: wrap; margin: 24px 0; font-family: -apple-system, BlinkMacSystemFont, sans-serif;">
  <div style="display: flex; flex-direction: column; align-items: center; gap: 6px; min-width: 80px;">
    <div style="width: 56px; height: 56px; border-radius: 12px; background: rgba(0,122,255,0.18);"></div>
    <span style="font-size: 11px; color: #555; text-align: center;">selection</span>
  </div>
  <div style="display: flex; flex-direction: column; align-items: center; gap: 6px; min-width: 80px;">
    <div style="width: 56px; height: 56px; border-radius: 12px; background: #007AFF;"></div>
    <span style="font-size: 11px; color: #555; text-align: center;">actionPrimary</span>
  </div>
  <div style="display: flex; flex-direction: column; align-items: center; gap: 6px; min-width: 80px;">
    <div style="width: 56px; height: 56px; border-radius: 12px; background: #FF3B30;"></div>
    <span style="font-size: 11px; color: #555; text-align: center;">actionDestructive<br/>error</span>
  </div>
  <div style="display: flex; flex-direction: column; align-items: center; gap: 6px; min-width: 80px;">
    <div style="width: 56px; height: 56px; border-radius: 12px; background: #f5f5f5; box-shadow: 0 0 0 1px #e5e5e5;"></div>
    <span style="font-size: 11px; color: #555; text-align: center;">success<br/>warning</span>
  </div>
</div>

| Role | Semantic token | Current value | Notes |
|---|---|---|---|
| Selection highlight | `selection` | `Color.accentColor.opacity(0.18)` | Active row, selected state |
| Action / interactive | `actionPrimary` | `Color.blue` (system) | Links, primary buttons — shown above as iOS system blue `#007AFF` |
| Destructive action | `actionDestructive` | `Color.red` (system) | Delete, danger actions — shown above as iOS system red `#FF3B30` |
| Error indicator | `error` | `Color.red` (system) | Error states, validation |
| Success indicator | `success` | `textPrimary` (neutral) | No green badge — communicated via text and icons |
| Warning indicator | `warning` | `textSecondary` (neutral) | No amber badge — communicated via text and icons |

**Note on success and warning**: sideBar does not use traffic-light color coding for status. Success and warning states are communicated through label text and icons, not color alone.

**Note on actionPrimary**: `Color.blue` uses the system accent color, so it respects user and OS accent preferences. If sideBar adopts a custom accent in the future, this token is the right place to define it.

---

## Platform implementations

### macOS (current, canonical)

`Color+Platform.swift` defines `MacOSPalette` using hardcoded `NSColor` sRGB values. These values ARE the canonical palette above. No changes needed to the values themselves.

**Migration needed**: The `MacOSPalette` branching in `Color+Platform.swift` should be removed and replaced with a single implementation that uses the canonical hex values for both platforms. `#if os(macOS)` color branching in that file goes away.

### iOS (current, diverges — migration needed)

`Color+Platform.swift` maps iOS tokens to UIKit semantic colors:

| Token | Current iOS value | Target value |
|---|---|---|
| `background` | `UIColor.systemBackground` | `#ffffff` / `#0a0a0a` |
| `surface` | `UIColor.secondarySystemBackground` | `#ffffff` / `#171717` |
| `muted` | `UIColor.systemGroupedBackground` | `#f5f5f5` / `#262626` |
| `sidebar` | `UIColor.secondarySystemBackground` | `#fafafa` / `#171717` |
| `sidebarAccent` | `UIColor.secondarySystemGroupedBackground` | `#f5f5f5` / `#262626` |
| `border` | `UIColor.separator` | `#e5e5e5` / `rgba(255,255,255,0.10)` |
| `input` | `UIColor.separator` | `#e5e5e5` / `rgba(255,255,255,0.15)` |

UIKit semantic colors adapt per OS and accessibility settings. The migration replaces them with fixed light/dark value pairs matching the macOS palette. This trades OS-level automatic adaptation for visual consistency across platforms. Given sideBar's near-neutral palette, the loss of UIKit adaptation is minimal in practice.

**Priority**: Medium. The visual difference is subtle on most devices. Migrate as part of the `Color+Platform.swift` consolidation work.

### Web (current, close — alignment needed)

`frontend/src/app.css` uses OKLCH values. The current values are close but not exactly aligned with the canonical hex palette. All web surface variables use chroma `0` (no hue), which is correct. Lightness values need adjustment in dark mode.

| Token | Current web (light) | Target | Current web (dark) | Target |
|---|---|---|---|---|
| `--background` | `oklch(1 0 0)` | `oklch(1 0 0)` | `oklch(0.145 0 0)` | `oklch(0.065 0 0)` |
| `--card` | `oklch(1 0 0)` | `oklch(1 0 0)` | `oklch(0.205 0 0)` | `oklch(0.145 0 0)` |
| `--muted` | `oklch(0.97 0 0)` | `oklch(0.97 0 0)` | `oklch(0.269 0 0)` | `oklch(0.205 0 0)` |
| `--sidebar` | `oklch(0.985 0 0)` | `oklch(0.985 0 0)` | `oklch(0.205 0 0)` | `oklch(0.145 0 0)` |
| `--sidebar-accent` | `oklch(0.97 0 0)` | `oklch(0.97 0 0)` | `oklch(0.269 0 0)` | `oklch(0.205 0 0)` |
| `--border` | `oklch(0.922 0 0)` | `oklch(0.922 0 0)` | `oklch(1 0 0 / 10%)` | `oklch(1 0 0 / 10%)` |
| `--input` | `oklch(0.922 0 0)` | `oklch(0.922 0 0)` | `oklch(1 0 0 / 15%)` | `oklch(1 0 0 / 15%)` |

**Key delta**: The dark mode background gap. Current web `--background` dark is `oklch(0.145 0 0)` ≈ `#1a1a1a`. The canonical dark background is `#0a0a0a` ≈ `oklch(0.065 0 0)`. The web dark mode is significantly lighter than native. All dark surface values are shifted by roughly the same offset. Light mode values are already correct.

**Priority**: Medium. Align dark mode values during the next web pass.

---

## Dark mode approach

All platforms support full dark mode. The mechanism differs:

| Platform | Dark mode trigger |
|---|---|
| iOS | System appearance (`UITraitCollection`) |
| macOS | System appearance (`NSAppearance`) |
| Web | `.dark` CSS class on root, toggled via header switch, persisted in localStorage with system preference fallback |

The values are the same regardless of trigger mechanism. There are no platform-specific dark mode variants.

---

## What is not in this document

- **Radius tokens**: Defined in `DesignTokens.Radius` and `foundations/token-model.md`
- **Spacing tokens**: Defined in `DesignTokens.Spacing` and `foundations/token-model.md`
- **Typography**: Defined in `foundations/typography.md`
- **Iconography**: Defined in `foundations/iconography.md`
- **Liquid Glass**: A rendering primitive, not a color. Covered per-component in platform convention docs.
- **Chart colors**: Web-only at present. The `--chart-*` variables in `app.css` are used for data visualisation. No native equivalent. Leave as-is until native charts are needed.

---

## Related docs

- [Token Audit](../audits/token-audit)
- [System Inheritance](../system-inheritance)
- [macOS Conventions](../platform-strategy/macos-conventions)
- [iOS Conventions](../platform-strategy/ios-conventions)
- [Web Conventions](../platform-strategy/web-conventions)
- `foundations/token-model.md` (to be created)
- `foundations/typography.md` (to be created)
