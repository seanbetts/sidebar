---
title: Iconography
description: SF Symbols usage, sizing, rendering modes, and the SkillIconResolver system for sideBar.
---

| Field | Value |
|---|---|
| Status | approved |
| Owner | both |
| Outputs | this doc |
| Dependencies | [token-model](./token-model), [ios-conventions](../platform-strategy/ios-conventions), [macos-conventions](../platform-strategy/macos-conventions) |

## Purpose

Define how icons are used across sideBar: which system, how they are sized, how rendering modes are applied, and how the skill icon system works.

---

## Icon system

sideBar uses **SF Symbols exclusively**. There are no custom icon assets in the app. Every icon is rendered via `Image(systemName:)` or `Label` with a system image.

This is intentional. SF Symbols:
- Scale correctly with Dynamic Type and accessibility text sizes
- Adapt automatically to light and dark mode
- Support variable rendering modes (monochrome, palette, multicolor, hierarchical)
- Stay visually consistent with native iOS and macOS UI

**Rule**: Do not add custom icon assets. If SF Symbols does not have a suitable icon, raise it as a product decision — do not work around it with a custom asset.

---

## Sizing

Icon sizes come from `DesignTokens.Icon.*`. These define the frame size, not the symbol rendering size — the frame sets the visual footprint and touch target.

| Token | Value | Use |
|---|---|---|
| `Icon.sm` | 14pt | Inline status icons, small decorative icons |
| `Icon.md` | 18pt | Standard toolbar and list icons |
| `Icon.lg` | 24pt | Prominent action icons |
| `Icon.xl` | 32pt | Section header icons, large actions |
| `Icon.xxl` | 40pt | Splash or onboarding icons |

### Sizing pattern

SF Symbol rendering size is controlled by the font modifier, not `.imageScale`. The correct pattern is:

```swift
Image(systemName: "square.and.pencil")
    .font(.appFont(.label))       // controls symbol weight and optical size
    .frame(width: Icon.md, height: Icon.md)  // sets footprint and touch target
```

`.imageScale(.medium)` is the system default and can be omitted. Do not use `.imageScale` to size icons — use the font modifier and frame together.

**Exception — app logo**: `SidebarRail` uses a 26pt frame for the app logo image. This is intentional and should remain a component-local constant (`SidebarRail.logoSize = 26`), not a global token.

---

## Rendering modes

| Mode | When to use |
|---|---|
| `.monochrome` | Default for all UI icons. Single foreground color, adapts to context. |
| `.hierarchical` | Icons with depth — primary element is fully opaque, secondary elements are reduced opacity. Use sparingly. |
| `.palette` | Two explicit colors on a single symbol (e.g., skill store feature cards). Use only when the two-color distinction carries meaning. |
| `.multicolor` | System-defined coloring (e.g., filled emoji-style symbols). Avoid in UI — too visually heavy. |

**Rule**: Default to monochrome. Do not specify a rendering mode unless there is a specific reason. Explicitly set `.symbolRenderingMode(.monochrome)` only when overriding an inherited palette or multicolor mode.

---

## `HeaderActionIcon`

`HeaderActionIcon` is the standard component for toolbar and panel header icon buttons. It wraps `Image(systemName:)` with consistent sizing and touch target:

```swift
struct HeaderActionIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .appFont(.label)
            .frame(width: 28, height: 20)
            .imageScale(.medium)
    }
}
```

Use `HeaderActionButton` (wraps `HeaderActionIcon` in a `Button`) for interactive header actions. Use `HeaderActionMenuButton` on iOS when the button presents a menu.

**Rule**: Use `HeaderActionIcon` / `HeaderActionButton` for all panel header and toolbar icon buttons. Do not build ad-hoc icon buttons inline in header views.

---

## Skill icon system

Skill icons are resolved centrally by `SkillIconResolver` in `Utilities/SkillIconResolver.swift`. This maps skill IDs and icon keys to SF Symbol names, with `puzzlepiece.extension` as the fallback for unknown skills.

The resolver is the single source of truth for skill icon assignments. It is used by:
- `SkillsStoreCardComponents` (store UI)
- `ToolResultWorkspaceSurfaceParser` (chat tool results)
- `AgentWorkspaceSurfaceView` (workspace)

**Rule**: Do not hardcode skill icon names outside `SkillIconResolver`. Add new skill-to-symbol mappings there.

---

## Action icon system

Context menu and swipe action icons are centralised in `SidebarMenuItem` (`Design/Components/SidebarMenuItem.swift`). It provides factory methods for all common row actions with pre-assigned SF Symbol names:

| Action | SF Symbol |
|---|---|
| Pin / Unpin | `pin` / `pin.slash` |
| Archive / Unarchive | `archivebox` / `archivebox.fill` |
| Rename | `pencil` |
| Move | `arrow.forward.folder` |
| Reorder | `line.3.horizontal` |
| Copy | `doc.on.doc` |
| Download | `square.and.arrow.down` |
| Share | `square.and.arrow.up.on.square` |
| Delete | `trash` (destructive role) |

**Rule**: Use `SidebarMenuItem` factory methods for all context menu and swipe actions. Do not assign SF Symbol names to action items inline in views — add a factory method to `SidebarMenuItem` if one does not exist.

---

## Tab bar icons

Tab bar items use `Label` with `Image(systemName:)` and `.symbolVariant(.none)`. The tab bar tint is set via `.tint(tabBarTint)` at the tab view level. Do not override tint on individual tab items.

---

## Web icons (Lucide)

The web app uses **Lucide Svelte** (`lucide-svelte`) for icons. Lucide does not have parity with SF Symbols, but the same semantic concepts should map to visually equivalent icons across platforms. The table below is the canonical mapping:

| Concept | SF Symbol (native) | Lucide (web) |
|---|---|---|
| Notes section | `note.text` | `FileText` |
| Tasks section | `checkmark.square` | `CheckSquare` |
| Websites section | `globe` | `Globe` |
| Files section | `folder` | `FolderOpen` |
| Chat section | `message` | `MessageSquare` |
| Skills Store | `puzzlepiece.extension` | `Store` |
| Toggle sidebar | — | `Menu` |
| Search | `magnifyingglass` | `Search` |
| Add / Create | `plus` | `Plus` |
| Pin / Unpin | `pin` / `pin.slash` | `Pin` / `PinOff` |
| Rename | `pencil` | `Pencil` |
| Delete | `trash` | `Trash2` |
| Copy | `doc.on.doc` | `Copy` |
| Download | `square.and.arrow.down` | `Download` |
| Close / Dismiss | `xmark` | `X` |
| More options | `ellipsis` | `MoreHorizontal` |
| Warning / Error | `exclamationmark.triangle.fill` | `AlertTriangle` |
| Success / Check | `checkmark` | `Check` / `CheckCircle2` |
| User / Profile | `person.crop.circle` | `User` |
| Memory / Brain | `brain` | `Brain` |
| Key / Credentials | `key.horizontal` | `Key` |
| Send / Submit | `arrow.up` | `ArrowUp` |
| Attach | `paperclip` | `Paperclip` |
| Chevron right | `chevron.right` | `ChevronRight` |
| Folder | `folder` | `Folder` / `FolderOpen` |
| Sign out | `rectangle.portrait.and.arrow.right` | `LogOut` |

**Rule**: When adding a new icon concept to both platforms, consult this table first. If the concept is new, add it to the table before shipping to both platforms so the mapping is documented.

---

## Rules summary

1. **SF Symbols only on native.** No custom icon assets.
2. **Lucide on web.** Use `lucide-svelte`. Consult the mapping table for cross-platform semantic alignment.
3. **Size with tokens.** Use `DesignTokens.Icon.*` for frame sizing. Never use bare integer literals (20, 22, 28px) when a token exists.
4. **Size with font modifier.** Use `.font(.appFont(style))` to control symbol weight and optical size. Do not rely on `.imageScale` for sizing.
5. **Monochrome by default.** Only specify a rendering mode when the default is wrong for the context.
6. **Use `HeaderActionIcon` for header buttons.** Do not build ad-hoc icon buttons in header views.
7. **Use `SkillIconResolver` for skill icons.** Do not hardcode skill symbol names outside the resolver.
8. **Use `SidebarMenuItem` factory methods for action icons.** Do not assign SF Symbol names to context menu or swipe actions inline in views.

---

## Related docs

- [Token Model](./token-model)
- [iOS Conventions](../platform-strategy/ios-conventions)
- [macOS Conventions](../platform-strategy/macos-conventions)
- [Implementation Gaps](../implementation-gaps)
