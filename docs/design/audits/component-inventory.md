---
title: Component Inventory
description: Draft inventory of reusable iOS and macOS UI components in the sideBar codebase.
---

| Field | Value |
|---|---|
| Status | drafted |
| Owner | AI coding agent |
| Inputs needed | codebase inspection (complete) |
| Outputs | this doc |
| Dependencies | [current-ui-audit](./current-ui-audit) |
| Codebase review required | yes (complete) |
| Human judgement required | yes - to classify intent of each component and decide which should be fully documented next |

## Purpose

Inventory all shared and reusable components in the sideBar iOS/macOS app. Classify each as native, wrapped, or custom. Identify gaps, inconsistencies, and candidates for documentation.

---

## Classification key

- **Native**: Apple-provided component used as-is with no wrapping or restyling.
- **Thin wrapper**: Primarily a native component, lightly extended or adapted for cross-platform use.
- **Custom**: A component built from primitives that Apple doesn't provide, or a significant departure from native behaviour.

---

## Design system components (`Design/Components/`)

These are the intentionally shared, reusable building blocks of the UI.

### EmptyStateView
- **Classification**: Custom (thin)
- **Description**: Title + optional subtitle, centred, with token-based font and color. No native equivalent for this exact pattern.
- **Usage**: Used consistently across all panel sections when lists are empty.
- **Status**: Clean. Uses tokens throughout.
- **File**: `Design/Components/EmptyStateView.swift`

### PanelHeader
- **Classification**: Custom
- **Description**: Section title bar with title, optional subtitle, optional trailing content, and optional offline banner. Platform-adaptive background (sidebar color on iOS; sidebar in light, surface in dark on macOS).
- **Usage**: Every left-panel section.
- **Status**: Clean. Uses tokens. Minor issue: VStack spacing of 2 is a bare literal, not a token.
- **File**: `Design/Components/PanelHeader.swift`

### SearchField
- **Classification**: Custom (wrapping TextField)
- **Description**: Search input with icon, clear button, and two chrome variants: `.standard` (filled background, border) and `.dock` (transparent, no border). Uses `.appFont(.subheadline)` and tokens.
- **Usage**: Panel search in all sections, search dock on iPhone.
- **Status**: Clean. Good variant model. Token-backed.
- **File**: `Design/Components/SearchField.swift`

### SelectableRow
- **Classification**: Custom
- **Description**: Generic list row wrapper providing selection highlight, touch target, animation on selection change, and optional primary action button. Supports both `List` context (`.listRowInsets`, `.listRowBackground`) and standalone context.
- **Usage**: Core building block for all list rows in panel sections.
- **Status**: Clean. Well-parameterised. Token-backed. Respects reduce motion.
- **File**: `Design/Components/SelectableRow.swift`

### HeaderActionIcon
- **Classification**: Custom (thin)
- **Description**: Toolbar/header action button wrapping an SF Symbol. Standard sizing and interaction.
- **Usage**: Panel header trailing actions.
- **File**: `Design/Components/HeaderActionIcon.swift`

### PhoneFloatingActionDock
- **Classification**: Custom (Liquid Glass)
- **Description**: iPhone-specific floating action container using iOS 26 `.glassEffect(.regular.interactive(), in: Capsule())`. Contains `PhoneFloatingActionButton` (icon + action, 44pt touch target) and `PhoneFloatingActionDivider`.
- **Usage**: Section-specific create actions on iPhone, floating above tab bar.
- **Status**: First production use of Liquid Glass in the app. Clean.
- **File**: `Design/Components/PhoneFloatingActionDock.swift`

### LoadingView / LoadingIndicatorView
- **Classification**: Custom (thin)
- **Description**: Consistent loading state presentation.
- **Usage**: Content loading states.
- **File**: `Design/Components/LoadingView.swift`, `Design/Components/LoadingIndicatorView.swift`

### ListSkeletons
- **Classification**: Custom
- **Description**: Skeleton loading placeholders for lists.
- **File**: `Design/Components/ListSkeletons.swift`

### ToastCenter
- **Classification**: Custom
- **Description**: Toast notification management and display.
- **Usage**: System-level feedback notifications.
- **File**: `Design/Components/ToastCenter.swift`

### OfflineBanner
- **Classification**: Custom
- **Description**: Offline/sync status indicator shown in panel header on iPhone.
- **Usage**: Compact layout when offline, writing, or syncing.
- **File**: `Design/Components/OfflineBanner.swift`

### SyncStatusIndicator
- **Classification**: Custom
- **Description**: Sync status display component.
- **File**: `Design/Components/SyncStatusIndicator.swift`

### MacModalShell
- **Classification**: Custom (macOS only)
- **Description**: Wraps Mac modal/sheet content with appropriate background, sized presentation, and grouped form styling. iOS stub passes through content unchanged.
- **Usage**: Settings, detail panels on Mac.
- **Status**: Clean. Functional. Hard-coded `maxWidth: 1_120` for large inspector sheets could be tokenised.
- **File**: `Design/Components/MacModalShell.swift`

### MacPopoverShell
- **Classification**: Custom (macOS only)
- **Description**: Wraps Mac popover content.
- **File**: `Design/Components/MacPopoverShell.swift`

### MacModalPresentation
- **Classification**: Custom (macOS only)
- **Description**: Higher-level Mac window/panel presentation helper.
- **File**: `Design/Components/MacModalPresentation.swift`

### DeleteConfirmationAlert
- **Classification**: Custom (thin)
- **Description**: Standard delete confirmation alert. Likely wraps `.alert`.
- **File**: `Design/Components/DeleteConfirmationAlert.swift`

### RenameItemSheet
- **Classification**: Custom
- **Description**: Rename action sheet.
- **File**: `Design/Components/RenameItemSheet.swift`

### SidebarMenuItem
- **Classification**: Custom
- **Description**: Menu item for sidebar context menus.
- **File**: `Design/Components/SidebarMenuItem.swift`

### SidebarSwipeActions
- **Classification**: Custom (thin)
- **Description**: Swipe action helpers for list rows.
- **File**: `Design/Components/SidebarSwipeActions.swift`

### ContentHeaderRow
- **Classification**: Custom
- **Description**: Row-style header for content panels.
- **File**: `Design/Components/ContentHeaderRow.swift`

### StaggeredAppearance
- **Classification**: Custom
- **Description**: Staggered animation for list item appearance.
- **File**: `Design/Components/StaggeredAppearance.swift`

### UIKitMenuButton
- **Classification**: Thin wrapper (UIKit)
- **Description**: Wraps UIKit menu button for SwiftUI use.
- **File**: `Design/Components/UIKitMenuButton.swift`

### PlatformContextMenu
- **Classification**: Thin wrapper
- **Description**: Cross-platform context menu adapter.
- **File**: `Design/Components/PlatformContextMenu.swift`

---

## Design styles (`Design/Styles/`)

### CardModifier / `.cardStyle()`
- **Classification**: Custom
- **Description**: Applies `surface` background, `md` radius (14pt, continuous), 1pt `border` stroke. No padding variation.
- **Usage**: Settings cards, some content containers.
- **Status**: Clean. Token-backed. Simple and correct.
- **File**: `Design/Styles/CardModifier.swift`

### PillModifier / `.pillStyle()`
- **Classification**: Custom
- **Description**: Applies `surface` background, capsule shape, 1pt `border` stroke, standard horizontal/vertical padding.
- **Usage**: Tag-like UI elements, status indicators.
- **Status**: Clean. Pre-Liquid Glass styling. Liquid Glass plan will upgrade these.
- **File**: `Design/Styles/PillModifier.swift`

---

## Design modifiers (`Design/Modifiers/`)

### BorderedModifier
- **Classification**: Custom
- **File**: `Design/Modifiers/BorderedModifier.swift`

### ShadowModifier
- **Classification**: Custom
- **File**: `Design/Modifiers/ShadowModifier.swift`

---

## Navigation components

### SidebarRail
- **Classification**: Custom
- **Description**: 56px vertical icon navigation strip for iPad/Mac. Contains section buttons (icon + selection highlight), Skills Store button (bottom), and profile avatar (bottom) for Settings. App logo at top toggles left panel.
- **Usage**: Primary navigation structure on all non-compact layouts.
- **Status**: Mostly clean. One token violation: `.font(.system(size: 18, weight: .semibold))` should use `.appFont()`. Icon scale for skillsStore (1.2x) is undocumented.
- **File**: `Views/SidebarRail.swift`

### SidebarSplitView
- **Classification**: Custom
- **Description**: Resizable split view with sidebar panel + detail. Drag-to-resize with snap points. `@AppStorage` persists width.
- **Usage**: iPad/Mac when not using WorkspaceLayout.
- **File**: `Views/SidebarSplitView.swift`

### WorkspaceLayout
- **Classification**: Custom
- **Description**: Full workspace layout with rail, left panel, main content, and optional right sidebar. Both left panel and right sidebar are resizable with persisted widths.
- **Usage**: Primary layout container for iPad/Mac.
- **File**: `Views/WorkspaceLayout.swift`

---

## Common/shared views (`Views/Common/`)

### SideBarMarkdown
- **Classification**: Custom
- **Description**: Markdown rendering for chat messages. Has variants for MarkdownUI, Gallery, and TikTok embeds.
- **Files**: `SideBarMarkdown.swift`, `SideBarMarkdown+Gallery.swift`, `SideBarMarkdown+MarkdownUI.swift`, `SideBarMarkdown+TikTok.swift`

### FaviconImageView
- **Classification**: Custom
- **Description**: Displays website favicons with fallback.
- **File**: `Views/Common/FaviconImageView.swift`

### ProfileAvatarView
- **Classification**: Custom
- **Description**: User profile avatar circle. Used in SidebarRail settings button.
- **File**: `Views/Common/ProfileAvatarView.swift`

### SkillIconView
- **Classification**: Custom
- **Description**: Skill icon display.
- **File**: `Views/Common/SkillIconView.swift`

### AudioPlayerView
- **Classification**: Custom
- **Description**: Audio playback UI.
- **File**: `Views/Common/AudioPlayerView.swift`

### SafariView
- **Classification**: Thin wrapper (UIKit)
- **Description**: Wraps `SFSafariViewController` for SwiftUI use.
- **File**: `Views/Common/SafariView.swift`

### ImagePicker
- **Classification**: Thin wrapper (UIKit)
- **Description**: Wraps `UIImagePickerController`.
- **File**: `Views/Common/ImagePicker.swift`

### SidebarPanelPlaceholder
- **Classification**: Custom
- **Description**: Placeholder view for empty panel state.
- **File**: `Views/Common/SidebarPanelPlaceholder.swift`

### SidebarSparseStateRow
- **Classification**: Custom
- **Description**: Sparse/empty state row component for sidebars.
- **File**: `Views/Common/SidebarSparseStateRow.swift`

### ContentViewComponents
- **Classification**: Custom
- **Description**: Various UI helper components for ContentView.
- **File**: `Views/Common/ContentViewComponents.swift`

---

## Chat-specific components (`Views/Chat/`)

| Component | Classification | Description |
|---|---|---|
| `ChatView` | Feature view | Root chat view, toolbar, navigation |
| `ChatMessageListView` | Custom | Scrolling message thread |
| `ChatMessageRow` | Custom | Individual message display row |
| `ChatInputBar` | Custom | Multiline text input with send action |
| `ChatInputSizing` | Custom | Input bar height/sizing logic |
| `ChatInputUIKit` | UIKit bridge | UIKit-based text input |
| `ChatInputAppKit` | AppKit bridge | AppKit-based text input |
| `ChatHeaderView` | Custom | Conversation context header |
| `ChatAttachmentsView` | Custom | File attachments display |
| `ChatToolBanners` | Custom | Skill execution progress banners |
| `ChatToolComponents` | Custom | Inline skill UI in chat thread |
| `ChatErrorComponents` | Custom | Error state display |
| `ChatLayout` | Custom | Layout helpers |

---

## Notes-specific components (`Views/Notes/`)

| Component | Classification | Description |
|---|---|---|
| `NotesView` | Feature view | Notes list panel |
| `NotesViewComponents` | Custom | Notes list row components |
| `NotesDetailView` | Feature view | Note detail container |
| `NotesDetailView+EditorSurface` | Custom | Editor surface selection logic |
| `NotesDetailView+FormattingBar` | Custom | Formatting bar controller |
| `NotesDetailView+ReadMode` | Custom | Read mode surface |
| `UIKitNoteTextEditorSurface` | UIKit bridge | Primary iOS rich text editor |
| `SwiftUINoteTextEditorSurface` | Custom | SwiftUI text editor fallback |
| `AppKitNoteTextEditorSurface` | AppKit bridge | Primary macOS rich text editor |
| `AttributedNoteEditorContainer` | UIKit bridge | Container for attributed text |
| `NoteFormattingBar` | Custom | iOS formatting toolbar |
| `UIKitNoteFormattingBar` | UIKit bridge | UIKit formatting bar |
| `AppKitNoteFormattingBar` | AppKit bridge | macOS formatting bar |
| `SelectableNoteReadView` | Custom | Read-mode display |
| `ScratchpadPopoverView` | Custom | Scratchpad popover |

---

## Native components used as-is

The following Apple-native components are used without wrapping:

| Component | Where used |
|---|---|
| `TabView` | iPhone compact layout |
| `List` | Panel sections (notes, tasks, etc.) |
| `TextField` | Search field input, form inputs |
| `Toggle` | Settings toggles |
| `Picker` | Settings pickers |
| `Form` | Settings form groups |
| `.sheet` | iPhone settings, scratchpad, modals |
| `.alert` | Confirmations |
| `Menu` | Context menus, floating action multi-options |
| `Button` | Actions throughout |
| `NavigationStack` | iPhone per-section navigation |
| `.toolbar` / `ToolbarItem` | iPhone navigation toolbar |

---

## Components with inconsistent usage

1. **Search**: `SearchField` (custom) is used in most panels but some panels may use different search patterns. The compact search dock pattern is specific to iPhone.

2. **Loading**: `LoadingView` and `LoadingIndicatorView` appear to serve similar purposes. Whether they are used consistently or one was the older implementation is unclear without deeper inspection.

3. **Empty states**: `EmptyStateView` is the shared component but some views may have inline empty state text without using it.

---

## Highest priority components to document next

Based on usage frequency and product importance:

1. **SelectableRow** - core list primitive, used in every section
2. **ChatMessageRow** - central to primary product feature
3. **ChatInputBar** - primary interaction surface
4. **PanelHeader** - every section
5. **PhoneFloatingActionDock** - iPhone's primary create action surface, first Liquid Glass pattern

---

## Open questions

- Does `LoadingView` supersede `LoadingIndicatorView` or do they serve different purposes?
- Are there any component duplications in section-specific `*ViewComponents.swift` files that should be extracted to `Design/Components/`?
- `SidebarSparseStateRow` vs `EmptyStateView`: what is the distinction?
- Which components in `Views/Common/` are candidates for moving to `Design/Components/`?

---

## Related docs

- `audits/current-ui-audit.md`
- `audits/token-audit.md`
- `audits/system-framework-usage-audit.md`
- `components/overview.md` (to be created)
