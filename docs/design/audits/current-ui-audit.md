---
title: Current UI Audit
description: Draft inventory of the main sideBar screens, navigation, flows, and current UI patterns.
---

- Status: drafted
- Owner: AI coding agent
- Inputs needed: codebase inspection (complete), product docs (read), screenshots (not available)
- Outputs: this doc
- Dependencies: none
- Codebase review required: yes (complete)
- Human judgement required: yes - to confirm product intent behind patterns flagged as unclear

---

## Purpose

Document the main screens, flows, navigation structure, and UI patterns in sideBar as they exist today. This is the ground-truth starting point for the design system. It documents reality, not ideals.

---

## App overview

sideBar is a universal iOS/macOS productivity app built in SwiftUI with UIKit and AppKit integration where needed. It provides six primary sections: Chat (AI assistant), Notes, Tasks, Websites, Files, and Skills Store. It also has Settings as a secondary surface.

Target platforms: iOS 26+ (iPhone and iPad), macOS 26+.

---

## Navigation structure

### iPhone (compact horizontal size class)

Navigation is `TabView`-based with tabs at the bottom. The current tabs are Chat, Notes, Tasks, Websites, Files, and a "More" tab when the tab count exceeds the visible limit.

A custom `SearchDock` floats above the tab bar, pinned to the bottom safe area. It expands inline on the currently selected section and is used for filtering/searching the visible panel. This is a distinctive sideBar-specific pattern, not a system component.

A `PhoneFloatingActionDock` (iOS 26 Liquid Glass capsule) provides section-specific create actions (e.g. New chat, Add note, New task). It appears above the tab bar in the trailing position when the panel list is visible.

Settings on iPhone is presented as a `.sheet`.

Scratchpad is presented as a `.sheet` from any section.

Source:
- `ContentView+Layout.swift:compactView`
- `ContentView+CompactPhoneTabs.swift`
- `ContentView+CompactPhoneSearchDock.swift`

### iPad and Mac (regular horizontal size class, macOS always)

Navigation uses a custom `WorkspaceLayout` structure:

```
[ SidebarRail 56px ] [ Left panel ~280px ] [ Divider 8px ] [ Main content ] [ Right sidebar optional ]
```

**SidebarRail** (`SidebarRail.swift`): 56px wide vertical icon strip. Contains section buttons (icon only), the Skills Store button pinned to the bottom, and a profile avatar button for Settings. The app logo at the top toggles the left panel.

**Left panel** (`SidebarSplitView.swift`): Shows the list view for the current section (conversations, notes list, tasks list, etc.). Width is user-adjustable (min 200px, max 500px) with drag-to-resize and snap points at 33%, 40%, and 50% of available width. Persisted via `@AppStorage`.

**Main content**: The detail view for the selected item in the left panel.

**Right sidebar**: Optional second content area for workspace mode. Width adjustable (min 280px, default 360px). Exposed via workspace expand/collapse toggle.

Mac settings opens a dedicated window via `AppKit` window management, not a sheet.

Source:
- `ContentView+Layout.swift:splitView`
- `WorkspaceLayout.swift`
- `SidebarRail.swift`
- `SidebarSplitView.swift`

### Adaptive layout note

The layout branch decision is:
- macOS: always `splitView`
- iOS compact: `compactView` (TabView)
- iOS regular (iPad): `splitView`

This is handled in `ContentView+Layout.swift:mainView`. There is no NavigationSplitView in use - the split layout is a fully custom implementation.

---

## Main screens and flows

### Chat

**Panel**: List of conversations with title, preview, and timestamp. Search dock available. New conversation button in header area.

**Detail**: Chat message thread view (`ChatMessageListView`) with a custom input bar (`ChatInputBar`) at the bottom. On iPhone, the input bar sits above the keyboard. On Mac/iPad, it sits at the bottom of the detail view.

Chat has a `ChatHeaderView` for the current conversation context.

Streaming responses are displayed progressively. There are tool-call banners (`ChatToolBanners`) and tool components (`ChatToolComponents`) for displaying skill-related UI inline in the thread.

Error handling uses `ChatErrorComponents`.

Source: `Views/Chat/`

### Notes

**Panel**: List of notes with folder hierarchy. Search dock available. Create note and create folder actions in floating action dock.

**Detail**: Rich text editor with a formatting bar. Three distinct editor implementations:
- `UIKitNoteTextEditorSurface` (iOS primary)
- `SwiftUINoteTextEditorSurface` (fallback/simple)
- `AppKitNoteTextEditorSurface` (macOS primary)

Read mode is a separate view (`NotesDetailView+ReadMode`). The edit/read toggle is a notable UX pattern.

A scratchpad is available as a popover (`ScratchpadPopoverView`).

Source: `Views/Notes/`

### Tasks

**Panel**: Task list grouped by project/group. Search dock available. Floating action dock with create task, create group, create project options.

**Detail**: Task detail view (`TasksDetailView`) with floating action dock for task-specific actions.

Source: `Views/Tasks/`

### Websites

**Panel**: Website list. Search dock available. Floating action dock with add website.

**Detail**: Website detail view (`WebsitesDetailView`) with copy/save actions. Custom `SiteHeaderBar` at the top.

Source: `Views/Websites/`

### Files

**Panel**: File list. Search dock available. Floating action dock with add file and add YouTube video.

**Detail**: File viewer with content display.

Source: `Views/Files/`

### Skills Store

Accessible via the `SidebarRail` bottom icon (on iPad/Mac) and the "More" tab on iPhone. Displays available skills with search.

Source: `Views/SkillsStore/`

### Settings

Contains profile, user settings, sideBar identity/soul viewer, memories, skill configuration, system settings. On iOS it's a `.sheet`. On Mac it opens as a dedicated window.

Structured as tabbed sections on iOS (`SettingsView+Tabs.swift`) and a `Settings` view on Mac.

Source: `Views/Settings/`

---

## Shared components and repeated patterns

### Panel header pattern

Every left panel section opens with a `PanelHeader` - a title bar with optional subtitle and trailing actions. Consistent across all six sections.

Implementation: `Design/Components/PanelHeader.swift`

### Search dock pattern (iPhone)

The custom search dock floats above the tab bar and expands when tapped. It uses a `SearchField` component.

Implementation: `ContentView+CompactPhoneSearchDock.swift`, `Design/Components/SearchField.swift`

### Selectable rows

List rows use `SelectableRow` which provides selection highlighting via `DesignTokens.Colors.selection` (accent color at 18% opacity) and animation.

Implementation: `Design/Components/SelectableRow.swift`

### Empty states

`EmptyStateView` provides a title + optional subtitle centred in the view. Used when panels have no content.

Implementation: `Design/Components/EmptyStateView.swift`

### Loading states

`LoadingView` and `LoadingIndicatorView` provide consistent loading feedback.

Implementation: `Design/Components/LoadingView.swift`, `Design/Components/LoadingIndicatorView.swift`

### Toast notifications

`ToastCenter` provides system-level toast feedback.

Implementation: `Design/Components/ToastCenter.swift`

### Offline banner

`OfflineBanner` appears in the panel header on iPhone when offline, writing, or syncing.

Implementation: `Design/Components/OfflineBanner.swift`

### Card style

`.cardStyle()` modifier applies `surface` background, `md` radius (14pt), and 1pt border. Used for settings cards and some content containers.

Implementation: `Design/Styles/CardModifier.swift`

### Pill style

`.pillStyle()` modifier applies `surface` background, capsule shape, and 1pt border.

Implementation: `Design/Styles/PillModifier.swift`

### Mac modal shell

`MacModalShell` wraps settings/detail panels on Mac with appropriate background and sizing. `MacPopoverShell` wraps popovers.

Implementation: `Design/Components/MacModalShell.swift`, `Design/Components/MacPopoverShell.swift`

### Floating action dock (iPhone)

`PhoneFloatingActionDock` uses iOS 26 Liquid Glass (`glassEffect(.regular.interactive(), in: Capsule())`). Section-specific create actions. Currently the only consistent Liquid Glass surface in the app.

Implementation: `Design/Components/PhoneFloatingActionDock.swift`

---

## AI assistant integration points

sideBar's AI assistant is embedded in Chat but its presence extends across the product:

- Chat section: primary assistant interface
- Skills Store: manage assistant capabilities
- Settings: view/interact with assistant identity and soul
- Agent workspace: `AgentWorkspaceSurfaceView` allows the assistant to render content in the workspace pane
- Tool banners in chat thread (`ChatToolBanners`) show in-progress skill execution

The assistant has its own identity and soul (self-managed, not developer-authored beyond the product model). These are viewable in Settings but not directly editable by the user.

---

## Hard-coded styling drift

Areas where values are not using `DesignTokens`:

| Location | Hard-coded value | Should be |
|---|---|---|
| `SidebarRail.swift:103` | `.font(.system(size: 18, weight: .semibold))` | `.appFont(.labelMd)` or a token |
| `SidebarRail.swift:31` | `VStack(spacing: 16)` | `DesignTokens.Spacing.md` |
| `SidebarRail.swift:44` | `VStack(spacing: 12)` | `DesignTokens.Spacing.sm` |
| `SidebarRail.swift:105` | `.frame(width: 32, height: 32)` | `DesignTokens.Icon.xl` (32) - matches, should be named |
| `SidebarRail.swift:109` | `cornerRadius: 8` | `DesignTokens.Radius.xsPlus` |
| `PanelHeader.swift:45` | `VStack spacing: 2` | unnamed - no token for this scale |
| `WorkspaceLayout.swift` | `defaultRightSidebarWidth: 360`, `railWidth: 56`, `dividerWidth: 8` | `DesignTokens.Size.*` (partial - 280 matches `sidebarWidth`) |
| `PhoneFloatingActionMetrics.contentSpacing: 6` | literal `6` | `DesignTokens.Spacing.xxsPlus` (6) - matches, should reference |
| `PhoneFloatingActionDivider` | `frame(height: 12)` | `DesignTokens.Spacing.sm` |
| `Settings/StoreSkillCredentialsView.swift:186` | `.frame(width: 30, height: 30)` | No matching token (between Icon.md=18 and Icon.xl=32) |
| `Settings/SettingsSections+Additional.swift:202` | `.frame(width: 18, height: 18)` | `DesignTokens.Icon.md` |
| `Tasks/TasksViewComponents.swift` | multiple `frame(width: 20/24, height: 20/24)` | Between Icon.md=18 and Icon.lg=24 |
| `MacModalShell.swift` | `maxWidth: 1_120` | No panel-size token for large inspector sheets |

---

## Biggest inconsistencies

1. **Parallel typography systems**: `DesignTokens.Typography` (static font vars) and `AppFontStyle` enum (`.appFont()` modifier) both exist. `AppFontStyle` is the correct one to use in views. `DesignTokens.Typography` appears to be a legacy or less-used path. The two systems should be unified.

2. **Icon frame sizes not consistently tokenised**: `DesignTokens.Icon` defines sm=14, md=18, lg=24, xl=32, xxl=40. But views use 18, 20, 24, 28, 30, 32 in raw literals. The 20 and 30 values have no token.

3. **SidebarRail bypasses appFont**: `SidebarRail.swift` uses `.font(.system(size: 18, weight: .semibold))` directly, bypassing the app's custom text sizing system. This means rail icons won't scale with user text size preference.

4. **PlatformTokens is vestigial**: `PlatformTokens.swift` defines one value (`panelHeaderBackground`) which is just `DesignTokens.Colors.sidebar`. It does not add value and adds cognitive overhead.

5. **WorkspaceLayout dimension constants not in DesignTokens.Size**: `railWidth: 56`, `dividerWidth: 8`, `defaultRightSidebarWidth: 360` are hardcoded in `WorkspaceLayout.swift` as private constants. Some already match existing token values (sidebarWidth=280) but are duplicated.

6. **Mac sidebar colour is custom-coded**: The macOS colour palette in `Color+Platform.swift` uses hard-coded sRGB values (near-white/near-black) rather than system semantic colours like `NSColor.windowBackgroundColor`. This is intentional for precise control but should be explicitly documented.

---

## Quickest high-value polish opportunities

1. **Fix `SidebarRail` font**: Replace `.font(.system(size: 18, weight: .semibold))` with `.appFont(...)` so icon labels scale with the app text size preference (1 line change).

2. **Consolidate `DesignTokens.Typography` vs `AppFontStyle`**: Remove or deprecate `DesignTokens.Typography` and direct all font usage through `.appFont()`. (Medium effort, no user-visible change.)

3. **Fold `PlatformTokens` into `DesignTokens.Colors`**: One-value enum is noise. (Trivial cleanup.)

4. **Add missing Icon size tokens**: Add `Icon.md2 = 20` (or similar) to cover the 20px icon usage pattern. Alternatively, audit whether 20px is intentional or should be either 18 or 24. (Design decision needed.)

5. **Extract WorkspaceLayout constants to DesignTokens.Size**: Add `railWidth = 56`, `dividerWidth = 8` so they are findable and not duplicated. (Low risk, low effort.)

---

## What is already good

- The token system is structurally sound. `DesignTokens` covers Spacing, Radius, Size, Icon, Colors, Animation, Typography.
- `.appFont()` modifier with dynamic scaling support is the right approach and is used consistently in `Design/` components.
- `Motion` enum correctly gates animation behind `accessibilityReduceMotion`.
- iOS uses system semantic colours throughout (`.systemBackground`, `.secondarySystemBackground`, etc.).
- Accessibility labels are present on navigation elements.
- `.cardStyle()` and `.pillStyle()` provide reusable, token-backed styling.
- `SelectableRow` is the consistent building block for all list rows.
- `EmptyStateView` and `PanelHeader` are used consistently across sections.
- The Liquid Glass adoption plan is well-defined and sequenced.

---

## What is unclear

- Web app: not inspected in this audit. Web conventions, tokens, and component state are unknown.
- Whether `DesignTokens.Typography` is intentionally maintained alongside `AppFontStyle` or is legacy.
- The intent behind the 20px and 30px icon frame sizes (are they intentional or drift?).
- Whether the macOS custom colour palette values are the current approved values or have drifted.

---

## Related docs

- `audits/token-audit.md`
- `audits/component-inventory.md`
- `audits/system-framework-usage-audit.md`
