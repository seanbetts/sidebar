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

### Light mode

<div style={{display:"flex",gap:"0",marginBottom:"24px",fontFamily:"-apple-system,sans-serif",borderRadius:"10px",overflow:"hidden",border:"1px solid #e0e0e0"}}>
  <div style={{flex:1,background:"#fafafa",padding:"14px",textAlign:"center"}}>
    <div style={{fontSize:"12px",fontWeight:"600",color:"#333"}}>sidebar</div>
    <div style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",marginTop:"2px"}}>#fafafa</div>
  </div>
  <div style={{flex:1,background:"#ffffff",padding:"14px",textAlign:"center",borderLeft:"1px solid #e8e8e8"}}>
    <div style={{fontSize:"12px",fontWeight:"600",color:"#333"}}>background</div>
    <div style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",marginTop:"2px"}}>#ffffff</div>
  </div>
  <div style={{flex:1,background:"#f5f5f5",padding:"14px",textAlign:"center",borderLeft:"1px solid #e8e8e8"}}>
    <div style={{fontSize:"12px",fontWeight:"600",color:"#333"}}>muted</div>
    <div style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",marginTop:"2px"}}>#f5f5f5</div>
  </div>
  <div style={{flex:1,background:"#e5e5e5",padding:"14px",textAlign:"center",borderLeft:"1px solid #ddd"}}>
    <div style={{fontSize:"12px",fontWeight:"600",color:"#444"}}>border</div>
    <div style={{fontSize:"11px",color:"#888",fontFamily:"monospace",marginTop:"2px"}}>#e5e5e5</div>
  </div>
</div>

### Dark mode

<div style={{display:"flex",gap:"0",marginBottom:"24px",fontFamily:"-apple-system,sans-serif",borderRadius:"10px",overflow:"hidden",border:"1px solid #2a2a2a"}}>
  <div style={{flex:1,background:"#171717",padding:"14px",textAlign:"center"}}>
    <div style={{fontSize:"12px",fontWeight:"600",color:"#ccc"}}>sidebar</div>
    <div style={{fontSize:"11px",color:"#555",fontFamily:"monospace",marginTop:"2px"}}>#171717</div>
  </div>
  <div style={{flex:1,background:"#0a0a0a",padding:"14px",textAlign:"center",borderLeft:"1px solid #222"}}>
    <div style={{fontSize:"12px",fontWeight:"600",color:"#ccc"}}>background</div>
    <div style={{fontSize:"11px",color:"#555",fontFamily:"monospace",marginTop:"2px"}}>#0a0a0a</div>
  </div>
  <div style={{flex:1,background:"#262626",padding:"14px",textAlign:"center",borderLeft:"1px solid #222"}}>
    <div style={{fontSize:"12px",fontWeight:"600",color:"#ccc"}}>muted</div>
    <div style={{fontSize:"11px",color:"#555",fontFamily:"monospace",marginTop:"2px"}}>#262626</div>
  </div>
  <div style={{flex:1,background:"#0a0a0a",padding:"14px",textAlign:"center",borderLeft:"1px solid #222"}}>
    <div style={{fontSize:"12px",fontWeight:"600",color:"#ccc"}}>border</div>
    <div style={{fontSize:"11px",color:"#555",fontFamily:"monospace",marginTop:"2px"}}>white 10%</div>
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

Text colors are resolved from system primitives and adapt correctly to accessibility settings (high contrast, etc.).

| Role | Semantic token | Native source | Notes |
|---|---|---|---|
| Primary text | `textPrimary` | `Color.primary` | Default body text |
| Secondary text | `textSecondary` | `Color.secondary` | Supporting labels, captions |
| Tertiary text | `textTertiary` | `platformTertiaryLabel` | De-emphasised text, placeholders |

On web, text is defined as `--foreground` (oklch near-black/near-white) and `--muted-foreground` (oklch mid-grey). These should track the native visual weight rather than exact luminance equivalents.

---

## State and action colors

<div style={{display:"flex",gap:"0",marginBottom:"24px",fontFamily:"-apple-system,sans-serif",borderRadius:"10px",overflow:"hidden",border:"1px solid #e0e0e0"}}>
  <div style={{flex:1,background:"rgba(0,122,255,0.18)",padding:"14px",textAlign:"center"}}>
    <div style={{fontSize:"12px",fontWeight:"600",color:"#333"}}>selection</div>
    <div style={{fontSize:"11px",color:"#888",fontFamily:"monospace",marginTop:"2px"}}>accentColor 18%</div>
  </div>
  <div style={{flex:1,background:"#007AFF",padding:"14px",textAlign:"center",borderLeft:"1px solid rgba(255,255,255,0.2)"}}>
    <div style={{fontSize:"12px",fontWeight:"600",color:"#fff"}}>actionPrimary</div>
    <div style={{fontSize:"11px",color:"rgba(255,255,255,0.7)",fontFamily:"monospace",marginTop:"2px"}}>#007AFF</div>
  </div>
  <div style={{flex:1,background:"#FF3B30",padding:"14px",textAlign:"center",borderLeft:"1px solid rgba(255,255,255,0.2)"}}>
    <div style={{fontSize:"12px",fontWeight:"600",color:"#fff"}}>actionDestructive / error</div>
    <div style={{fontSize:"11px",color:"rgba(255,255,255,0.7)",fontFamily:"monospace",marginTop:"2px"}}>#FF3B30</div>
  </div>
  <div style={{flex:1,background:"#f5f5f5",padding:"14px",textAlign:"center",borderLeft:"1px solid #e0e0e0"}}>
    <div style={{fontSize:"12px",fontWeight:"600",color:"#333"}}>success / warning</div>
    <div style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",marginTop:"2px"}}>neutral</div>
  </div>
</div>

| Role | Semantic token | Current value | Notes |
|---|---|---|---|
| Selection highlight | `selection` | `Color.accentColor.opacity(0.18)` | Active row, selected state |
| Action / interactive | `actionPrimary` | `Color.blue` (system) | Links, primary buttons — approx `#007AFF` on iOS |
| Destructive action | `actionDestructive` | `Color.red` (system) | Delete, danger actions — approx `#FF3B30` on iOS |
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

**Priority**: Medium. Migrate as part of the `Color+Platform.swift` consolidation work.

### Web (current, close — alignment needed)

`frontend/src/app.css` uses OKLCH values. All web surface variables correctly use chroma `0` (no hue). Lightness values need adjustment in dark mode.

| Token | Current web (light) | Target | Current web (dark) | Target |
|---|---|---|---|---|
| `--background` | `oklch(1 0 0)` | `oklch(1 0 0)` | `oklch(0.145 0 0)` | `oklch(0.065 0 0)` |
| `--card` | `oklch(1 0 0)` | `oklch(1 0 0)` | `oklch(0.205 0 0)` | `oklch(0.145 0 0)` |
| `--muted` | `oklch(0.97 0 0)` | `oklch(0.97 0 0)` | `oklch(0.269 0 0)` | `oklch(0.205 0 0)` |
| `--sidebar` | `oklch(0.985 0 0)` | `oklch(0.985 0 0)` | `oklch(0.205 0 0)` | `oklch(0.145 0 0)` |
| `--sidebar-accent` | `oklch(0.97 0 0)` | `oklch(0.97 0 0)` | `oklch(0.269 0 0)` | `oklch(0.205 0 0)` |
| `--border` | `oklch(0.922 0 0)` | `oklch(0.922 0 0)` | `oklch(1 0 0 / 10%)` | `oklch(1 0 0 / 10%)` |
| `--input` | `oklch(0.922 0 0)` | `oklch(0.922 0 0)` | `oklch(1 0 0 / 15%)` | `oklch(1 0 0 / 15%)` |

**Key delta**: The dark mode background. Current web `--background` dark is `oklch(0.145 0 0)` (~`#1a1a1a`). The canonical dark background is `#0a0a0a` (~`oklch(0.065 0 0)`). All dark surface values are shifted by roughly the same offset. Light mode values are already correct.

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
- **Chart colors**: Web-only at present. The `--chart-*` variables in `app.css` are for data visualisation. No native equivalent. Leave as-is until native charts are needed.

---

## Related docs

- [Token Audit](../audits/token-audit)
- [System Inheritance](../system-inheritance)
- [macOS Conventions](../platform-strategy/macos-conventions)
- [iOS Conventions](../platform-strategy/ios-conventions)
- [Web Conventions](../platform-strategy/web-conventions)
- `foundations/token-model.md` (to be created)
- `foundations/typography.md` (to be created)
