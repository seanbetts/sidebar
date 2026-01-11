# macOS Styling Audit + Plan

## Goal
Bring macOS UI styling in line with the iPad build and the web app design system, while keeping a native-feeling layout. Focus on surface colors, list/row treatments, header styling, and spacing so macOS looks like the same product, not a different skin.

## Observations (Code-Level)
- macOS uses AppKit defaults for surfaces and controls in multiple places (e.g. `windowBackgroundColor`, `underPageBackgroundColor`, `controlBackgroundColor`, `separatorColor`). This yields a much more macOS-native palette that diverges from iPad/web.
- Many lists are `.sidebar` style and inherit default background/row styling. On iPad we override `scrollContentBackground(.hidden)` and custom row backgrounds; macOS keeps default list chrome.
- Panel/header styling diverges because macOS code paths use different colors in `SiteHeaderBar`, `SidebarSplitView`, `WorkspaceLayout`, `SidebarRail`, and `SidebarPanels`.
- Selection styling is using black/white inversions in `SelectableRow` and row backgrounds, which can be harsh on macOS because the surrounding surfaces are lighter and use NSColors.
- Web app uses a defined token system (`frontend/src/app.css`) with distinct background / card / sidebar / border / muted colors. iPad styling leans on `platformSystemBackground` and `platformSecondarySystemBackground` (customized). macOS bypasses those tokens.

## Gaps vs iPad + Web
1. Surface palette mismatch: macOS window/panel/headers are native greys instead of web/iPad surfaces.
2. Sidebar and panel backgrounds don’t match the web sidebar / muted surfaces.
3. List rows and selection don’t match iPad/web (row backgrounds, hover/selection emphasis).
4. Header treatment (site header + panel header) doesn’t match the web card/toolbar styling.
5. Search bars and control containers lack consistent background/border treatment across macOS.

## Proposed Approach
Create a shared macOS styling layer that reuses the same semantic tokens as iPad/web, then roll it out component-by-component. This avoids ad-hoc per-view tweaks and makes future updates global.

### Phase A — Define macOS surface tokens
- Introduce a macOS-specific palette in one place (e.g. `DesignTokens.Colors` or a new `SurfaceTokens` struct) that maps to the web token categories: background, sidebar surface, panel surface, card, border, muted text.
- If needed, add an asset catalog with explicit light/dark colors to match web tokens instead of NSColors.

### Phase B — Standardize surface usage
- Replace macOS-only AppKit colors with the semantic tokens in:
  - `SidebarSplitView`
  - `WorkspaceLayout`
  - `SidebarRail`
  - `SidebarPanels`
  - `SiteHeaderBar`
  - `MemoriesView`
  - `ContentView` (primary background)
- Ensure panels + headers share the same surfaces as iPad/web.

### Phase C — Lists and rows
- Apply consistent list background handling on macOS (`scrollContentBackground(.hidden)` where needed).
- Align `SelectableRow` row backgrounds and selection styling to the web accent/selection patterns.
- Normalize row padding and corner radius in list rows (match iPad and web).

### Phase D — Controls + search bars
- Align search bar fill + border with the web’s input styling and iPad’s search field.
- Ensure header button backgrounds/borders match the web “card” or “accent” styles.

### Phase E — Visual parity checks
- Compare macOS vs iPad panel-by-panel (Chat, Notes, Files, Websites, Settings, Memories) and apply tokenized tweaks only where it still diverges.
- Validate in light and dark mode.

## Deliverables
- A single macOS theme/tokens source of truth.
- Refactored view styling to use semantic tokens.
- A checklist mapping each macOS panel to parity fixes.

## Risks / Notes
- Some native macOS controls (e.g., `List` selection) may require custom row rendering to avoid default chrome.
- Avoid large layout changes; focus on styling, surfaces, and spacing.
