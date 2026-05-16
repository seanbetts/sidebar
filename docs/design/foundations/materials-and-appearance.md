---
title: Materials and Appearance
description: Surface styling, native materials, Liquid Glass usage, and appearance mode handling across iOS and macOS.
---

## Purpose

Define how sideBar handles surface styling, Liquid Glass, and appearance layering. The goal is a coherent visual stack where every surface has a deliberate, documented reason for its fill.

---

## The two-surface model

sideBar uses two distinct surface systems depending on the surface's role:

| System | Used for | Implementation |
|---|---|---|
| **Solid fills** | Persistent surfaces — backgrounds, panels, sidebars | `DesignTokens.Colors.*` |
| **Liquid Glass** | Transient chrome — pills, action bars, floating docks, popovers, and action/header controls | `glassEffect` (iOS/macOS 26+) |

The dividing line is persistence. A panel background is always visible and provides the reading surface for content — it must be solid and predictable. A floating action dock or save status pill is transient chrome that sits above content — it benefits from Liquid Glass depth and adaptability.

System materials (`.regularMaterial`, `.ultraThinMaterial`, etc.) were the pre-iOS 26 tool for transient chrome. On iOS 26 and macOS 26 they are superseded by Liquid Glass for interactive chrome. System materials may still be appropriate for non-interactive blurred backgrounds in specific contexts.

---

## Surface hierarchy

From base to top, the visual stack:

| Layer | Surface | Fill |
|---|---|---|
| 1 | Window / app background | `DesignTokens.Colors.background` (solid) |
| 2 | Sidebar rail | `DesignTokens.Colors.sidebar` (solid) |
| 3 | Panel / content area | `DesignTokens.Colors.surface` (solid) |
| 4 | Panel header | Inherits the solid sidebar/panel surface |
| 5 | List rows | Transparent over panel; `DesignTokens.Colors.muted` for hover and selected states |
| 6 | Floating chrome | Liquid Glass — floating docks, action pills, formatting bars |
| 7 | Popovers and menus | Liquid Glass via `MacPopoverShell` / `MacModalShell` (planned) |
| 8 | Sheets and modals | System modal presentation (automatic via SwiftUI `.sheet`) |

**Rule**: Each layer should only use the fill defined for its role. Do not apply solid custom fills to transient chrome surfaces, and do not apply Liquid Glass to persistent content surfaces.

---

## Liquid Glass

Liquid Glass (`glassEffect`) is the primary surface primitive for transient chrome on iOS 26 and macOS 26. It provides depth, contextual colour sampling from content beneath, and automatic light/dark adaptation.

The following surfaces use Liquid Glass. Rollout order matters: primitives and shells first, then individual surfaces.

| Component | Platform | Notes |
|---|---|---|
| `PhoneFloatingActionDock` | iOS | Floating action capsule |
| `MacPopoverShell` | macOS | Popover background |
| `MacModalShell` | macOS | Modal background |
| `SettingsMacStyles` | macOS | Settings surface chrome |
| `HeaderActionIcon` / header action controls | iOS + macOS | Icon button chrome, including `SiteHeaderBar` trailing actions |
| `NoteFormattingBar` | iOS | Note formatting bar |
| `SearchField` standard chrome | iOS + macOS | Search input chrome. The compact dock variant remains transparent inside `PhoneFloatingActionDock` |
| Feature discovery and intro cards | iOS + macOS | Onboarding discovery chrome |
| `LoginView` | iOS + macOS | Onboarding/auth chrome |

**Rule**: New transient surface chrome must use Liquid Glass. Do not introduce new `.regularMaterial` or `.ultraThinMaterial` usage for interactive chrome.

The following surfaces intentionally stay solid or inherit glass from their parent surface:

| Component | Reason |
|---|---|
| `PanelHeader` | Persistent panel structure; it should inherit the surrounding solid sidebar/panel surface rather than add standalone glass. |
| `SidebarRail` | Persistent navigation rail; active and hover affordances may use tokenized button treatment, but the rail container remains solid for legibility. |
| `SiteHeaderBar` | Persistent app header container; trailing action controls may use glass, but the container remains solid. |
| `SearchField` dock chrome | The field sits inside `PhoneFloatingActionDock`, so it remains transparent to avoid nested glass. |

---

## Solid fills

Persistent surfaces use solid adaptive colors from `DesignTokens.Colors`. Full palette documentation is in [colour](./colour). The four tokens relevant to surface fills:

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
  <div style={{flex:1,background:"#ffffff",padding:"14px",textAlign:"center",borderLeft:"1px solid #e8e8e8"}}>
    <div style={{fontSize:"12px",fontWeight:"600",color:"#333"}}>surface</div>
    <div style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",marginTop:"2px"}}>#ffffff</div>
  </div>
  <div style={{flex:1,background:"#f5f5f5",padding:"14px",textAlign:"center",borderLeft:"1px solid #e8e8e8"}}>
    <div style={{fontSize:"12px",fontWeight:"600",color:"#333"}}>muted</div>
    <div style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",marginTop:"2px"}}>#f5f5f5</div>
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
  <div style={{flex:1,background:"#171717",padding:"14px",textAlign:"center",borderLeft:"1px solid #222"}}>
    <div style={{fontSize:"12px",fontWeight:"600",color:"#ccc"}}>surface</div>
    <div style={{fontSize:"11px",color:"#555",fontFamily:"monospace",marginTop:"2px"}}>#171717</div>
  </div>
  <div style={{flex:1,background:"#262626",padding:"14px",textAlign:"center",borderLeft:"1px solid #222"}}>
    <div style={{fontSize:"12px",fontWeight:"600",color:"#ccc"}}>muted</div>
    <div style={{fontSize:"11px",color:"#555",fontFamily:"monospace",marginTop:"2px"}}>#262626</div>
  </div>
</div>

| Token | Light | Dark | Role |
|---|---|---|---|
| `DesignTokens.Colors.sidebar` | `#fafafa` | `#171717` | Sidebar rail and panel headers |
| `DesignTokens.Colors.background` | `#ffffff` | `#0a0a0a` | Root app/window background |
| `DesignTokens.Colors.surface` | `#ffffff` | `#171717` | Primary content panels |
| `DesignTokens.Colors.muted` | `#f5f5f5` | `#262626` | Row hover states, subtle differentiation within a panel |

These tokens resolve to platform-appropriate hex values and handle light/dark automatically. Do not use raw `Color` literals or `Color.primary` / `Color.secondary` for surface fills.

---

## Appearance mode

sideBar follows system appearance. There is no manual light/dark toggle in the app — the system setting controls it.

**Rule**: Never override appearance mode in individual views. Do not use `.preferredColorScheme()` on view hierarchies. Surface colors via `DesignTokens.Colors` adapt automatically.

The one exception is the design docs site, which has its own appearance handling independent of the app.

---

## Corner radius on surfaces

Surfaces take their corner radius from `DesignTokens.Radius.*`. Key values:

| Surface type | Token | Value |
|---|---|---|
| Sheets, large modals | `Radius.lg` | 18pt |
| Cards, input fields | `Radius.sm` | 10pt |
| Floating docks, capsules | `Radius.xl` | 24pt |
| Buttons, row highlights | `Radius.xsPlus` | 8pt |

Liquid Glass surfaces use continuous corner radius (`.continuous` style). Full radius reference is in [token-model](./token-model).

---

## Rules summary

1. **Persistent surfaces use solid fills.** Backgrounds, panels, and sidebars use `DesignTokens.Colors.*`. Never apply Liquid Glass or materials to content reading surfaces.
2. **Transient chrome uses Liquid Glass.** Floating docks, pills, action bars, popovers, and formatting surfaces on iOS 26+ use `glassEffect`. Do not introduce new system material usage for these.
3. **System materials are not for interactive chrome.** Do not use `.ultraThinMaterial`, `.thinMaterial`, or `.regularMaterial` for floating docks, pills, action bars, or formatting surfaces. Use Liquid Glass.
4. **Never override appearance mode.** The app follows the system setting. `DesignTokens.Colors` handles light/dark automatically.
5. **Sheets are system.** SwiftUI `.sheet` presentation uses the system modal surface automatically. Do not apply custom backgrounds to sheet root views.

---

## Related docs

- [Colour](./colour)
- [Token Model](./token-model)
- [iOS Conventions](../platform-strategy/ios-conventions)
- [macOS Conventions](../platform-strategy/macos-conventions)
- [System Inheritance](../system-inheritance)
