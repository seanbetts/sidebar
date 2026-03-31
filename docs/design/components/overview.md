---
title: Components
description: Shared UI component guidance for the sideBar design system — when to use each component, key rules, and known issues.
---

## Purpose

Define the shared component library — what exists, when to use each component, and the rules that govern their use and extension. The component inventory (`audits/component-inventory`) is the source of classification and file locations. This doc is the usage guide.

**Scope**: Design system components in `Design/Components/`, design styles in `Design/Styles/`, and the navigation structure components. Feature-specific views (`Views/Chat/`, `Views/Notes/`, etc.) are not covered here — they are implementation details, not shared components.

---

## Core list and panel primitives

### SelectableRow

The core building block for all list rows in panel sections. Handles selection highlight, 44pt touch targets, reduce-motion-aware animation, and the `.isSelected` accessibility trait. See [SelectableRow](./selectable-row) for full usage rules.

### PanelHeader

Section title bar used at the top of every left-panel section. Accepts a title, optional subtitle, optional trailing content slot, and an optional offline banner. Background is platform-adaptive: `DesignTokens.Colors.sidebar` on iOS, `sidebar` in light mode and `surface` in dark mode on macOS.

**When to use**: Every left-panel section header. No panel section should roll its own header — use `PanelHeader`.

**Key rules**:
- Do not add a custom background to `PanelHeader` — the platform-adaptive background is intentional.
- The trailing content slot is for `HeaderActionRow` with `HeaderActionButton` instances. Do not place arbitrary views there.

### ContentHeaderRow

The standard header row for content detail views (the right-side content area). Renders a leading icon, title, optional subtitle, optional title accessory, and an optional trailing content slot. Used in Chat, Notes, Tasks, Files, Websites, Agent Workspace, and Skills Store detail headers.

Two layout axes:
- `.horizontal` (default) — title and subtitle sit side-by-side, separated by an optional vertical divider rule
- `.vertical` — subtitle stacks below the title

**When to use**: Any content detail view that opens from a panel section. Do not build a custom icon-title-subtitle layout for content headers — use `ContentHeaderRow`.

**Key rules**:
- Pass `iconName:` for SF Symbol icons or `iconView:` for custom icon views. Do not render the icon separately outside the component.
- The `trailing` slot is for `HeaderActionRow` / `HeaderActionButton` instances. Do not place arbitrary views there.
- Use `.vertical` axis when the subtitle needs its own line (longer metadata strings). Use `.horizontal` for compact one-line headers.

### EmptyStateView

Centred title, optional subtitle, and optional SF Symbol icon for genuinely empty content areas. See [EmptyStateView](./empty-state) for full usage rules.

### SearchField

Search input with leading icon and clear button. Two variants:
- `.standard` — filled background with border. Used in panel search bars.
- `.dock` — transparent, no border. Used in the iPhone compact search dock.

**When to use**: All search inputs. Do not build a custom search field.

**Key rules**: The variant must match the context — `.standard` inside a panel, `.dock` in the floating search chrome.

---

## Action components

### HeaderActionButton / HeaderActionRow / HeaderActionMenuButton

Standard icon buttons and button groups for panel headers and toolbars. `accessibilityLabel` is required and enforced by the API. See [Header Actions](./header-actions) for full usage rules.

### SidebarMenuItem

Factory type for all context menu and swipe action items. Provides canonical SF Symbol assignments and destructive role handling. See [SidebarMenuItem](./sidebar-menu-item) for the full factory method table and usage rules.

### SidebarSwipeActions

Configures leading and trailing swipe actions on list rows using `SidebarMenuItem`. Provides consistent swipe action layout and haptic trigger points.

**When to use**: Any list row that supports swipe actions.

### PhoneFloatingActionDock

iPhone-specific floating action capsule using Liquid Glass (`glassEffect`). Contains `PhoneFloatingActionButton` instances (44pt touch targets) and `PhoneFloatingActionDivider` separators. See [Pills and Docks](./pills-and-docks#floating-dock) for full anatomy and rules.

### PlatformContextMenu

Cross-platform context menu adapter. Handles the differences between iOS `.contextMenu` and macOS right-click menu presentation.

**When to use**: Any view that needs a context menu on both platforms.

---

## Feedback and status

### ToastCenter

System-level toast notification manager. `ToastEntry` defines individual toast messages. Toasts are displayed above all content and dismiss automatically.

**When to use**: Non-blocking feedback for completed actions (save, copy, delete). Do not use toasts for errors that require user action — use alerts.

### LoadingIndicatorView / LoadingView

Consistent loading state presentation. `LoadingIndicatorView` is the visual indicator; `LoadingView` is a full-surface loading wrapper.

**When to use**: `LoadingView` for full-panel loading states. `LoadingIndicatorView` for inline loading within a populated view. Do not use bare `ProgressView()` without wrapping — use these components for consistent sizing and accessibility handling (the indicator is hidden from VoiceOver).

### SidebarListSkeleton

Skeleton loading placeholder rows for panel list sections during initial data load. See [SidebarListSkeleton](./list-skeleton) for full usage rules.

### PlaceholderView

Full-surface error state for content areas that failed to load, with an optional retry action. See [PlaceholderView](./placeholder) for full usage rules.

### OfflineBanner

Compact status banner shown inside `PanelHeader` on iPhone when the app is offline, writing, or syncing. Has accessibility label and hint.

**When to use**: Already integrated into `PanelHeader` — do not render `OfflineBanner` directly. Pass the relevant state to `PanelHeader` and it handles the banner automatically.

### DeleteConfirmationAlert

Standard delete confirmation alert wrapping `.alert`. Consistent wording and destructive button role.

**When to use**: Any destructive delete action. Do not write inline `.alert` confirmation dialogs for delete — use `DeleteConfirmationAlert`.

### RenameItemSheet

Standard rename sheet with a text field. Consistent presentation and validation.

**When to use**: Any rename action across panel sections.

---

## Platform shells (macOS)

### MacModalShell

Wraps macOS modal and sheet content with appropriate background, sizing, and grouped form styling. iOS stub passes content through unchanged, so it is safe to use universally.

**When to use**: Wrap all settings views and detail panels that are presented as modals on Mac. Do not add custom `NSVisualEffectView` or manual window sizing in modal views — `MacModalShell` handles this.

### MacPopoverShell

Wraps macOS popover content. Planned Liquid Glass migration. Currently provides consistent background and padding.

**When to use**: All popover content on Mac.

---

## Styles and modifiers

### `.cardStyle()`

Applies `surface` background, `Radius.md` (14pt continuous) corner radius, and 1pt `border` stroke. No padding — add padding within the card content.

**When to use**: Settings cards, content containers that need subtle elevation from the background.

### `.pillStyle()`

Applies `surface` background, capsule shape, and 1pt `border` stroke with standard horizontal/vertical padding. See [Pills and Docks](./pills-and-docks) for the full taxonomy of capsule-shaped surfaces and when to use `.pillStyle()` versus Liquid Glass.

### `StaggeredAppearance`

Applies a staggered entrance animation to list items, with delay scaled by index. Respects reduce motion — animation is suppressed when the setting is enabled.

**When to use**: List sections that load or refresh their content and benefit from a staggered reveal. Use sparingly — not every list needs this.

---

## Navigation structure

### SidebarRail

56px vertical icon navigation strip for iPad and Mac. Contains section navigation buttons, Skills Store button, and profile avatar (Settings). The app logo at top toggles the left panel.

**Rules**:
- Do not add new sections to `SidebarRail` without a corresponding tab bar entry on iPhone.
- Section button order must match the tab bar order on iPhone.
- Known gap: uses `.font(.system(size: 18, weight: .semibold))` — should be `.appFont(.label)`. Tracked in [implementation-gaps](../implementation-gaps).

### WorkspaceLayout

Full workspace layout container for iPad/Mac: rail + left panel + main content + optional right sidebar. Both resizable panels persist their widths via `@AppStorage`.

**Rules**: This is the root layout — do not nest `WorkspaceLayout` or add layout logic outside it for the iPad/Mac workspace.

### SidebarSplitView

Resizable split view for contexts that don't use the full `WorkspaceLayout`. Contains a drag-to-resize handle with snap points.

**Known gap**: Contains remnant `DragGesture`-based resize handle code that should be removed. Tracked in [implementation-gaps](../implementation-gaps).

---

## Native components used as-is

These Apple components are used without wrapping. Apply them directly — do not create custom wrappers.

| Component | Use |
|---|---|
| `TabView` | iPhone compact layout |
| `List` | Panel section lists |
| `Toggle` | Settings toggles |
| `Picker` | Settings pickers |
| `Form` | Settings form groups |
| `.sheet` | iPhone modals, settings, scratchpad |
| `.alert` | System confirmations (use `DeleteConfirmationAlert` for delete) |
| `Menu` | Context menus and multi-option floating actions |
| `NavigationStack` | iPhone per-section navigation |
| `.toolbar` / `ToolbarItem` | iPhone navigation toolbar buttons |

---

## Rules summary

1. **Use the component.** If a design system component exists for the pattern, use it. Do not build ad-hoc alternatives inline in feature views.
2. **Do not override backgrounds on `PanelHeader`.** The platform-adaptive background is intentional.
3. **`ContentHeaderRow` for all content detail headers.** Do not build custom icon-title layouts for right-side content views.
4. **`HeaderActionButton` is mandatory for header icon buttons.** It enforces the accessibility label requirement.
5. **`SidebarMenuItem` for all action icon assignments.** No inline SF Symbol name assignments for menu or swipe actions.
6. **`DeleteConfirmationAlert` for all delete confirmations.** Consistent wording is a UX requirement.
7. **`.pillStyle()` is not for new transient chrome.** New floating surfaces use Liquid Glass.
8. **`PhoneFloatingActionDock` is iPhone-only.** Do not render on iPad or Mac.

---

## Related docs

- [Component Inventory](../audits/component-inventory)
- [Token Model](../foundations/token-model)
- [Typography](../foundations/typography)
- [Materials and Appearance](../foundations/materials-and-appearance)
- [Iconography](../foundations/iconography)
- [Accessibility](../foundations/accessibility)
- [Implementation Gaps](../implementation-gaps)
