---
title: Iconography
description: Native SF Symbols, web Lucide mappings, semantic icon naming, sizing, rendering modes, and ownership rules for sideBar.
---

## Purpose

Define the target icon system for sideBar across iOS, macOS, widgets, extensions, and web. Icon choices should feel native, restrained, and consistent across surfaces.

This document describes the future-state design system. Current gaps are tracked in [Implementation Gaps](../implementation-gaps) and the Apple icon audit in [Apple Icon Inventory](../audits/apple-icon-inventory-2026-05-04).

---

## Icon systems

Native Apple surfaces use **SF Symbols**. Web surfaces use **Lucide Svelte**.

Native icons are selected through semantic `AppIcon` constants, not raw `Image(systemName:)` strings at call sites. Web icons should use the closest Lucide equivalent for the same concept.

**Rules**:

- Do not add custom native icon assets for concepts covered by SF Symbols.
- Do not choose Lucide icons independently from native. Start from the native semantic concept, then pick the closest Lucide equivalent.
- If no existing semantic concept fits, add one to `AppIcon` and update this doc before shipping the new icon.

---

## Native semantic API

`AppIcon` is the canonical native icon vocabulary. It lives in shared Apple code so the main app, widgets, share extension, and Safari extension can reuse the same symbol choices.

Target location:

```swift
ios/sideBar/sideBarShared/Utilities/AppIcon.swift
```

Target shape:

```swift
public struct AppIcon: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
```

Semantic constants are grouped by concept:

```swift
public extension AppIcon {
    enum Action {
        public static let add = AppIcon(rawValue: "plus")
        public static let close = AppIcon(rawValue: "xmark")
        public static let more = AppIcon(rawValue: "ellipsis")
        public static let delete = AppIcon(rawValue: "trash")
    }

    enum Domain {
        public static let chat = AppIcon(rawValue: "bubble")
        public static let notes = AppIcon(rawValue: "text.document")
        public static let tasks = AppIcon(rawValue: "checkmark.square")
        public static let websites = AppIcon(rawValue: "globe")
        public static let files = AppIcon(rawValue: "folder")
    }
}
```

**Rule**: Feature code should use semantic `AppIcon` constants. Raw SF Symbol names belong in `AppIcon` or approved dynamic resolver boundaries.

---

## Rendering helpers

`AppIcon` itself should stay UI-framework-free. Rendering helpers belong in UI-owning targets.

Recommended SwiftUI helper:

```swift
extension Image {
    init(appIcon: AppIcon) {
        self.init(systemName: appIcon.rawValue)
    }
}
```

Recommended UIKit/AppKit helpers:

```swift
#if os(iOS)
extension UIImage {
    convenience init?(appIcon: AppIcon) {
        self.init(systemName: appIcon.rawValue)
    }
}
#endif

#if os(macOS)
extension NSImage {
    convenience init?(appIcon: AppIcon, accessibilityDescription: String? = nil) {
        self.init(systemSymbolName: appIcon.rawValue, accessibilityDescription: accessibilityDescription)
    }
}
#endif
```

Components may accept `AppIcon` directly:

```swift
HeaderActionButton(
    icon: AppIcon.Action.add,
    accessibilityLabel: "New note"
) { ... }
```

Compact floating action controls use the same pattern:

```swift
PhoneFloatingActionButton(
    icon: AppIcon.Action.add,
    accessibilityLabel: "New note"
) { ... }
```

Feature chrome helpers use the same direct `AppIcon` API for migrated surfaces:

```swift
ContentHeaderRow(icon: AppIcon.Domain.skillsStore, title: "Skills Store")
PlaceholderView(title: "No store skills found", icon: AppIcon.Action.search)
SettingsMacSkillRow(title: title, subtitle: subtitle, icon: AppIcon.Domain.memories)
Label("Profile", systemImage: AppIcon.Settings.profile.rawValue)
```

---

## Semantic ownership

`AppIcon` owns raw symbol names. Domain resolvers still own domain mapping decisions.

| Owner | Responsibility |
|---|---|
| `AppIcon` | Canonical SF Symbol raw values for native concepts |
| `AppSection` | Which app section uses which `AppIcon.Domain` value |
| `SkillIconResolver` | Which skill ID or icon key maps to which `AppIcon` |
| `SidebarMenuItem` | Which action title, role, and `AppIcon.Action` belong together |
| Empty-state helpers | Which empty-state semantic category maps to which `AppIcon` |
| Widget models | Which widget selection state maps to which shared `AppIcon` |

**Rule**: Keep semantic decisions close to the domain. Keep raw symbol values in `AppIcon`.

---

## Rationalization

`AppIcon` should be a curated vocabulary, not a one-to-one wrapper around every historical SF Symbol literal.

The implementation-facing mapping lives in [Apple Icon Rationalization](../audits/apple-icon-rationalization-2026-05-09).

When adding or migrating symbols, classify each icon by concept:

| Category | Meaning | Design-system outcome |
|---|---|---|
| Canonical | Represents a stable sideBar concept | Add to `AppIcon` and use wherever the concept appears |
| Replace | Duplicates an existing concept with local variation | Replace with the canonical `AppIcon` |
| Context-specific | Low-frequency but meaningfully distinct | Keep as a named `AppIcon` |
| Dynamic/external | Comes from backend, widget configuration, or a system payload | Keep behind an explicit dynamic resolver boundary |

Do not collapse icons just to reduce the count. `paperclip` for attachments, `key.horizontal` for credentials, and `doc.viewfinder` for PDF fit are distinct concepts even if they are low-frequency.

Do collapse local variation when the symbol does not carry different meaning. Common candidates for consolidation are:

- success and completion variants
- warning and error variants
- generic document and file variants
- close, dismiss, and clear affordances
- share, export, and download actions
- disclosure and navigation chevrons

**Rule**: If a symbol cannot be given a clear semantic `AppIcon` name, review whether it should become an alias to an existing canonical icon.

---

## Canonical native concepts

### Domains

| Concept | `AppIcon` | SF Symbol |
|---|---|---|
| Chat | `Domain.chat` | `bubble` |
| Notes | `Domain.notes` | `text.document` |
| Tasks | `Domain.tasks` | `checkmark.square` |
| Websites | `Domain.websites` | `globe` |
| Files | `Domain.files` | `folder` |
| Skills Store | `Domain.skillsStore` | `command.circle` |
| Settings | `Domain.settings` | `square.grid.2x2` |
| Memories | `Domain.memories` | `bookmark` |
| Selected memory | `Domain.memoriesFilled` | `bookmark.fill` |

### Tasks

| Concept | `AppIcon` | SF Symbol |
|---|---|---|
| Today tasks | `Tasks.today` | `calendar` |
| Upcoming tasks | `Tasks.upcoming` | `calendar.badge.clock` |
| Completed tasks | `Tasks.completed` | `calendar.badge.checkmark` |
| Task group | `Tasks.group` | `square.3.layers.3d` |
| Task project | `Tasks.project` | `list.bullet` |
| Task recurrence | `Tasks.recurrence` | `repeat` |

### Actions

| Concept | `AppIcon` | SF Symbol |
|---|---|---|
| Add or create | `Action.add` | `plus` |
| Close or dismiss | `Action.close` | `xmark` |
| Clear field | `Action.clearFilled` | `xmark.circle.fill` |
| More options | `Action.more` | `ellipsis` |
| Delete | `Action.delete` | `trash` |
| Share | `Action.share` | `square.and.arrow.up` |
| Share URL or text | `Action.shareOnSquare` | `square.and.arrow.up.on.square` |
| Download | `Action.download` | `square.and.arrow.down` |
| Copy | `Action.copy` | `doc.on.doc` |
| Rename or edit | `Action.rename` | `pencil` |
| Compose | `Action.compose` | `square.and.pencil` |
| Move | `Action.move` | `arrow.forward.folder` |
| Reorder | `Action.reorder` | `line.3.horizontal` |
| Pin | `Action.pin` | `pin` |
| Unpin | `Action.unpin` | `pin.slash` |
| Archive | `Action.archive` | `archivebox` |
| Unarchive | `Action.unarchive` | `archivebox.fill` |
| Search | `Action.search` | `magnifyingglass` |
| Refresh | `Action.refresh` | `arrow.clockwise` |
| Send | `Action.send` | `arrow.up` |
| Attach | `Action.attach` | `paperclip` |
| Open external | `Action.openExternal` | `arrow.up.right.square` |
| Sign out | `Action.signOut` | `rectangle.portrait.and.arrow.right` |

### Navigation

| Concept | `AppIcon` | SF Symbol |
|---|---|---|
| Back | `Navigation.back` | `chevron.left` |
| Forward | `Navigation.forward` | `chevron.right` |
| Disclosure right | `Navigation.chevronRight` | `chevron.right` |
| Disclosure down | `Navigation.chevronDown` | `chevron.down` |
| Expand picker | `Navigation.pickerDisclosure` | `chevron.up.chevron.down` |
| Expand workspace | `Navigation.expandWorkspace` | `arrow.up.right.and.arrow.down.left` |
| Collapse workspace | `Navigation.collapseWorkspace` | `arrow.down.left.and.arrow.up.right` |

### States

| Concept | `AppIcon` | SF Symbol |
|---|---|---|
| Info filled | `State.infoFilled` | `info.circle.fill` |
| Success | `State.success` | `checkmark` |
| Success in circle | `State.successCircle` | `checkmark.circle` |
| Success filled | `State.successFilled` | `checkmark.circle.fill` |
| Warning | `State.warning` | `exclamationmark.triangle` |
| Warning filled | `State.warningFilled` | `exclamationmark.triangle.fill` |
| Error | `State.error` | `exclamationmark.circle` |
| Error filled | `State.errorFilled` | `exclamationmark.circle.fill` |
| Empty circle | `State.emptyCircle` | `circle` |
| Selected filled circle | `State.selectedCircle` | `circle.fill` |
| Offline | `State.offline` | `wifi.slash` |
| Network degraded | `State.networkWarning` | `wifi.exclamationmark` |
| Syncing | `State.syncing` | `arrow.triangle.2.circlepath` |
| Retry | `State.retry` | `arrow.clockwise` |

### Content and media

| Concept | `AppIcon` | SF Symbol |
|---|---|---|
| Note document | `Content.note` | `note.text` |
| Text document | `Content.textDocument` | `doc.text` |
| Generic document | `Content.document` | `doc` |
| Filled document | `Content.documentFilled` | `doc.fill` |
| Folder | `Content.folder` | `folder` |
| Image placeholder | `Content.photo` | `photo` |
| Task list | `Content.taskList` | `list.bullet.rectangle` |
| Website fallback | `Content.websiteFallback` | `globe` |
| YouTube or video | `Media.video` | `play.rectangle` |
| Play | `Media.playFilled` | `play.circle.fill` |
| Audio transcription | `Media.waveform` | `waveform` |
| Captions | `Media.captions` | `captions.bubble` |
| PDF page fit | `PDF.fitPage` | `doc.viewfinder` |
| Zoom in | `PDF.zoomIn` | `plus.magnifyingglass` |
| Zoom out | `PDF.zoomOut` | `minus.magnifyingglass` |
| Fit width | `PDF.fitWidth` | `distribute.horizontal` |
| Fit height | `PDF.fitHeight` | `distribute.vertical` |

### Settings, profile, and skills

| Concept | `AppIcon` | SF Symbol |
|---|---|---|
| Profile | `Settings.profile` | `person.crop.circle` |
| Profile filled | `Settings.profileFilled` | `person.crop.circle.fill` |
| Add profile image | `Settings.profileAdd` | `person.crop.circle.badge.plus` |
| User settings | `Settings.user` | `person.line.dotted.person` |
| Assistant | `Settings.assistant` | `brain.fill` |
| Settings skills tab | `Settings.skills` | `command.circle` |
| Credentials | `Settings.credentials` | `key.horizontal` |
| Credentials connected | `Settings.credentialsFilled` | `key.horizontal.fill` |
| App preferences | `Settings.appPreferences` | `gearshape` |
| More settings tab | `Settings.more` | `ellipsis.circle` |
| Theme | `Settings.theme` | `paintpalette` |
| Skill fallback | `Skills.fallback` | `puzzlepiece.extension` |
| Skill category fallback | `Skills.categoryFallback` | `tag.fill` |
| Skill tools | `Skills.tools` | `hammer` |

---

## Sizing

Icon sizes come from `DesignTokens.Icon.*`. These define the frame size, not the symbol rendering size.

| Token | Value | Use |
|---|---|---|
| `Icon.sm` | 14pt | Inline status icons, small decorative icons |
| `Icon.md` | 18pt | Standard toolbar and list icons |
| `Icon.lg` | 24pt | Prominent action icons |
| `Icon.xl` | 32pt | Section header icons, large actions |
| `Icon.xxl` | 40pt | Splash or onboarding icons |

SF Symbol optical size and weight are controlled by the font modifier. The frame controls footprint and touch target:

```swift
Image(appIcon: AppIcon.Action.compose)
    .appFont(.labelMd)
    .frame(width: DesignTokens.Icon.md, height: DesignTokens.Icon.md)
```

**Rule**: Use font plus frame. Do not rely on `.imageScale` for sizing. `.imageScale(.medium)` is the default and should usually be omitted.

---

## Rendering modes

| Mode | When to use |
|---|---|
| `.monochrome` | Default for all UI icons. Single foreground color, adapts to context. |
| `.hierarchical` | Icons with depth where secondary elements should be quieter. Use sparingly. |
| `.palette` | Two explicit colors when the distinction carries meaning, such as skill store feature cards. |
| `.multicolor` | Avoid in core UI unless the system-defined color is the product decision. |

**Rule**: Default to monochrome. Set `.symbolRenderingMode(.monochrome)` only when overriding an inherited palette or multicolor mode.

---

## Header actions

`HeaderActionIcon`, `HeaderActionButton`, and `HeaderActionMenuButton` are the standard components for toolbar and panel header icon buttons.

Target API:

```swift
HeaderActionButton(
    icon: AppIcon.Action.compose,
    accessibilityLabel: "New note"
) { ... }

HeaderActionMenuButton(
    icon: AppIcon.Action.more,
    accessibilityLabel: "More options",
    items: menuItems
)
```

**Rule**: Use `HeaderActionButton` for standalone header actions and `HeaderActionMenuButton` for overflow menus. Do not build ad-hoc icon buttons inline in header views.

---

## Skill icon system

Skill icons are resolved centrally by `SkillIconResolver`. The resolver maps skill IDs and icon keys to `AppIcon` values, with `AppIcon.Skills.fallback` as the fallback for unknown skills.

The resolver remains the single source of truth for skill icon assignments. It is used by:

- Skills Store surfaces
- chat tool result surfaces
- agent workspace surfaces
- settings skill rows

**Rule**: Do not hardcode skill symbol names outside `SkillIconResolver`. Add new skill-to-icon mappings there, using `AppIcon`.

---

## Action icon system

Context menu and swipe action icons are centralized in `SidebarMenuItem`. Factory methods bind action titles, roles, and `AppIcon` values:

| Action | `AppIcon` |
|---|---|
| Pin / Unpin | `Action.pin` / `Action.unpin` |
| Archive / Unarchive | `Action.archive` / `Action.unarchive` |
| Rename | `Action.rename` |
| Move | `Action.move` |
| Reorder | `Action.reorder` |
| Copy | `Action.copy` |
| Download | `Action.download` |
| Share URL / Text | `Action.shareOnSquare` |
| Refresh | `Action.refresh` |
| Close | `Action.close` |
| New Task | `State.successCircle` |
| New Group | `Content.folder` |
| New Project | `Content.taskList` |
| Delete | `Action.delete` |

**Rule**: Use `SidebarMenuItem` factory methods for context menu and swipe actions. Do not assign icon names inline in views.

Compact phone floating action docks should pass `AppIcon` values into `PhoneFloatingActionButton`. SwiftUI `Label(..., systemImage:)` remains an acceptable boundary for menu rows when it receives `AppIcon.*.rawValue`.

---

## Shared status and empty-state icons

Shared empty, search, and status components accept or choose `AppIcon` values directly:

| Component | Icon owner |
|---|---|
| `EmptyStateContent` | Shared empty-state defaults such as search and completed tasks |
| `EmptyStateView` | Rendering of an `AppIcon`, with a temporary string bridge for remaining feature-level migrations |
| `SearchField` | Search and clear controls |
| `OfflineBanner` | Offline and degraded-network state |
| `StatusPill` | Neutral, success, warning, and error indicators |
| `SuccessCheckBadge` | Success check mark |

**Rule**: Shared primitives should not choose raw SF Symbol strings inline. Feature-level empty states should pass semantic `AppIcon` values where the concept is already rationalized. Remaining feature-level string bridges stay tracked under `RES-MP-13`.

Task row, detail, modal, panel zero-count, taxonomy, and recurrence affordances use `AppIcon` for rationalized success, error, add, delete, overflow, clear, notes, move, expand/collapse, date filter, group/project, and recurrence concepts.

---

## Web icon mapping

The web app uses `lucide-svelte`. Lucide does not have parity with SF Symbols, but concepts should remain aligned across platforms.

| Concept | Native `AppIcon` | SF Symbol | Lucide |
|---|---|---|---|
| Notes section | `Domain.notes` | `text.document` | `FileText` |
| Tasks section | `Domain.tasks` | `checkmark.square` | `CheckSquare` |
| Websites section | `Domain.websites` | `globe` | `Globe` |
| Files section | `Domain.files` | `folder` | `FolderOpen` |
| Chat section | `Domain.chat` | `bubble` | `MessageSquare` |
| Skills Store | `Domain.skillsStore` | `command.circle` | `Store` |
| Search | `Action.search` | `magnifyingglass` | `Search` |
| Add / Create | `Action.add` | `plus` | `Plus` |
| Pin / Unpin | `Action.pin` / `Action.unpin` | `pin` / `pin.slash` | `Pin` / `PinOff` |
| Rename | `Action.rename` | `pencil` | `Pencil` |
| Delete | `Action.delete` | `trash` | `Trash2` |
| Copy | `Action.copy` | `doc.on.doc` | `Copy` |
| Download | `Action.download` | `square.and.arrow.down` | `Download` |
| Close / Dismiss | `Action.close` | `xmark` | `X` |
| More options | `Action.more` | `ellipsis` | `MoreHorizontal` |
| Warning / Error | `State.warningFilled` | `exclamationmark.triangle.fill` | `AlertTriangle` |
| Success / Check | `State.success` | `checkmark` | `Check` / `CheckCircle2` |
| Profile | `Settings.profile` | `person.crop.circle` | `User` |
| Memory / Brain | `Domain.memories` / `Settings.assistant` | `bookmark` / `brain.fill` | `Bookmark` / `Brain` |
| Credentials | `Settings.credentials` | `key.horizontal` | `Key` |
| Send | `Action.send` | `arrow.up` | `ArrowUp` |
| Attach | `Action.attach` | `paperclip` | `Paperclip` |
| Chevron right | `Navigation.chevronRight` | `chevron.right` | `ChevronRight` |
| Sign out | `Action.signOut` | `rectangle.portrait.and.arrow.right` | `LogOut` |

**Rule**: When adding a new icon concept to both platforms, update this table before shipping the cross-platform change.

---

## Drift prevention

Raw SF Symbol literals are design-system drift unless they are inside an approved resolver boundary.

Approved places for raw native symbol names:

- `AppIcon`
- source tests for `AppIcon`
- explicit resolvers that ingest dynamic backend or widget payload values before mapping to an `AppIcon`

**Rule**: Feature views and shared components should use `AppIcon`. A source check should block new direct `Image(systemName: "...")`, `Label(systemImage: "...")`, `UIImage(systemName: "...")`, and `NSImage(systemSymbolName: "...")` literals outside approved files.

---

## Rules summary

1. **SF Symbols on native.** No custom native icon assets for concepts covered by SF Symbols.
2. **Lucide on web.** Use the closest Lucide equivalent for the native semantic concept.
3. **Use `AppIcon`.** Do not put raw SF Symbol strings in feature views.
4. **Keep resolvers semantic.** `AppSection`, `SkillIconResolver`, and `SidebarMenuItem` map domain concepts to `AppIcon`.
5. **Size with tokens.** Use `DesignTokens.Icon.*` for icon frames.
6. **Size with font.** Use `.appFont(...)` for symbol optical size and weight.
7. **Monochrome by default.** Only specify rendering mode when the default is wrong.
8. **Use header components.** Do not build ad-hoc icon-only header buttons.
9. **Use menu factories.** Context menu and swipe action icons go through `SidebarMenuItem`.
10. **Prevent drift.** New raw symbol literals should fail source checks unless explicitly approved.

---

## Related docs

- [Token Model](./token-model)
- [Header Actions](../components/header-actions)
- [SidebarMenuItem](../components/sidebar-menu-item)
- [iOS Conventions](../platform-strategy/ios-conventions)
- [macOS Conventions](../platform-strategy/macos-conventions)
- [Apple Icon Inventory](../audits/apple-icon-inventory-2026-05-04)
- [Implementation Gaps](../implementation-gaps)
