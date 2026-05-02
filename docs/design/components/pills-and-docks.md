---
title: Pills and Docks
description: Capsule-shaped UI surfaces in sideBar — status pills, metadata pills, action pills, and floating docks.
---

## Purpose

Define the four families of capsule-shaped surfaces used across sideBar, when to use each, and how they differ. Any new `Capsule()` usage should belong to one of these families.

---

## Families at a glance

| Family | Purpose | Interactive | Examples |
|---|---|---|---|
| Status pill | Show current state with icon + text | Optional tap action | Sync status, stale auth, toast banner |
| Metadata pill | Label content attributes | No | Task project/deadline, chat role, tool badge |
| Action pill | Trigger behaviour on tap | Yes | Filter chip, error popover, retry button |
| Floating dock | Glass toolbar container for iPhone compact layout | Yes (contains buttons) | Search dock, section action bar |

---

## Status pill

A small capsule that communicates a transient or ongoing state. Always has an icon and text. May optionally support a tap action (e.g. retry).

### Anatomy

```
[ icon  text ]
```

- **Shape**: `Capsule()`
- **Background**: Semantic, adapts to state. Neutral states use `DesignTokens.Colors.surface`. Error uses `error` background token. Success uses `success` background token.
- **Border**: 1px, colour matches the state. Neutral uses `DesignTokens.Colors.border`. Error/success use their respective border tokens with reduced opacity.
- **Icon**: SF Symbol, sized to match the text.
- **Text**: `.appFont(.captionSemibold)`, colour adapts to state.
- **Padding**: `Spacing.xs` horizontal, `Spacing.xxs` vertical.

### States

| State | Background | Border | Icon | Text colour |
|---|---|---|---|---|
| Neutral | `surface` | `border` | State-specific | `textPrimary` |
| Success | `successBackground` | `successBorder` | `checkmark` | `success` |
| Error | `errorBackground` | `errorBorder` | `exclamationmark.triangle` | `error` |
| Warning | `warningBackground` | `warningBorder` | `exclamationmark.triangle` | `warning` |
| Loading | `surface` | `border` | `ProgressView` (inline spinner) | `textSecondary` |

### Current implementations

| Implementation | Location | States | Tap action |
|---|---|---|---|
| `SiteHeaderBar` sync pill | `Views/Websites/` | syncing, pending | No |
| `SiteHeaderBar` ingestion pill | `Views/Websites/` | multiple | Yes (opens sheet) |
| `ToastBanner` | `Design/Components/ToastCenter.swift` | error, success | No |
| Stale auth status pill | Auth views | persistent recoverable stale after 10s | Optional |

### Target

These should converge on a shared `StatusPill` component in `Design/Components/` that accepts a semantic state and optional tap action. Individual implementations should not build their own capsule + border + icon layout.

### Key rules

- Always use a semantic state, not ad hoc colours. If the state doesn't fit the table above, add a new state to `StatusPill`, don't inline custom colours.
- Icon is required. A status pill without an icon is a metadata pill.
- Text is required. An icon-only status indicator is a badge, not a pill.
- Transient chrome (toast, retry, sync) should use Liquid Glass where the platform supports it, with `surface` as fallback.

---

## Metadata pill

A lightweight label that describes a content attribute. Display-only, never interactive.

### Anatomy

```
[ optional-icon  text ]
```

- **Shape**: `Capsule()`
- **Background**: `DesignTokens.Colors.surface` (light) or colorScheme-adaptive neutral fill.
- **Border**: 1px `DesignTokens.Colors.border`.
- **Icon**: Optional SF Symbol or custom view, sized to match text.
- **Text**: `.appFont(.caption2)`, `textSecondary`.
- **Padding**: `Spacing.xs` horizontal, `Spacing.xxs` vertical.

### Current implementations

| Implementation | Location | Content |
|---|---|---|
| `TaskPill` | `Views/Tasks/TasksViewComponents.swift` | Project name, group name, deadline |
| Chat role pill | `Views/Chat/ChatMessageRow.swift` | "User" / "Assistant" label |
| Tool call pill | `Views/Chat/ChatToolComponents.swift` | Skill name + icon |

### Target

These should converge on a shared `MetadataPill` component in `Design/Components/` that accepts optional icon and text. The component should enforce the standard capsule + border treatment so metadata labels are visually consistent across sections.

### Key rules

- Never interactive. If the pill needs a tap action, it's an action pill.
- Text is required. An icon-only metadata indicator is a badge.
- Use `textSecondary` for text colour. Metadata pills are supporting information, not primary content.
- Use `.caption2` for text size. Metadata pills should be visually smaller than status pills.

---

## Action pill

An interactive capsule that triggers behaviour on tap. Visually similar to a pill but semantically a button.

### Anatomy

```
[ optional-icon  text ]  (tappable)
```

- **Shape**: `Capsule()`
- **Background**: Context-dependent. Filter chips use accent fill when selected, `surface` when unselected. Error actions use `surface`.
- **Border**: 1px, context-dependent.
- **Text**: `.appFont(.captionSemibold)`.
- **Tap target**: Minimum 44pt height (even if the visual pill is smaller, the tap area must meet the touch target minimum).

### Current implementations

| Implementation | Location | Action |
|---|---|---|
| `ChatErrorPillView` | `Views/Chat/ChatErrorComponents.swift` | Opens error detail popover |
| `ChatErrorRetryActionView` | `Views/Chat/ChatErrorComponents.swift` | Retries failed request |
| `SkillsStoreFilterChip` | `Views/SkillsStore/SkillsStoreCardComponents.swift` | Toggles category filter |
| `ConflictActionButtonStyle` | `Views/Offline/QueuedChangeResolutionSheet.swift` | Resolves queue conflict |

### Target

Action pills vary more in behaviour than status or metadata pills, so a single shared component may over-abstract. Instead, these should use `PillModifier` (`.pillStyle()`) for consistent visual treatment while keeping their own tap handling and state logic.

### Key rules

- Must meet the 44pt touch target minimum. The capsule shape may be smaller, but wrap it in a `contentShape` that meets the minimum.
- Use `ButtonRole.destructive` where the action is irreversible.
- Provide an `.accessibilityLabel` that describes the action, not the visual appearance.
- Action pills inside a `ScrollView` or list should not interfere with the parent scroll gesture.

---

## Floating dock

A glass-effect toolbar container for iPhone compact layout. Contains multiple interactive elements (buttons, search fields, menus) in a horizontal arrangement.

### Anatomy

```
[ button | divider | button | divider | search ]
```

- **Shape**: `Capsule()` via `glassEffect(.regular.interactive(), in: Capsule())`
- **Background**: Liquid Glass (`.glassEffect`). No manual background colour.
- **Content**: `PhoneFloatingActionButton` instances (44pt), `PhoneFloatingActionDivider` separators (1px wide, 12pt tall).
- **Spacing**: `PhoneFloatingActionMetrics.contentSpacing` (6pt) between elements.
- **Padding**: `Spacing.xs` horizontal, `Spacing.xxs` vertical.

### Components

| Component | Role |
|---|---|
| `PhoneFloatingActionDock` | Glass capsule container. Accepts `@ViewBuilder` content. |
| `PhoneFloatingActionButton` | 44pt icon button. Requires `systemName` and `accessibilityLabel`. |
| `PhoneFloatingActionDivider` | 1px vertical separator using `DesignTokens.Colors.border`. |

### Dock types

| Dock | Location | Content |
|---|---|---|
| Section search dock | `ContentView+CompactPhoneSearchDock.swift` | Search icon/field + section-specific create actions. Collapses actions into a menu when search is expanded. |
| Task detail dock | `TasksDetailView+FloatingDock.swift` | Task-specific actions (pin, archive, delete). |

### Key rules

- **iPhone compact only.** Do not render floating docks on iPad or Mac. Use `HeaderActionRow` for those platforms.
- **Liquid Glass only.** Do not use `.pillStyle()`, materials, or manual backgrounds. The dock uses `.glassEffect`.
- **44pt touch targets.** Every `PhoneFloatingActionButton` is 44pt. Do not reduce this.
- **`accessibilityLabel` required.** Enforced by the `PhoneFloatingActionButton` API.
- **One dock per screen.** Do not stack multiple floating docks. If more actions are needed, collapse into a menu.
- **Compose, don't subclass.** Build section-specific dock content by composing `PhoneFloatingActionButton` and `PhoneFloatingActionDivider` inside `PhoneFloatingActionDock`. Do not create dock subclasses.

---

## When to use which

| Situation | Family |
|---|---|
| Showing sync, save, or connection state | Status pill |
| Labelling a task's project, group, or deadline | Metadata pill |
| Labelling a chat message's role | Metadata pill |
| Filter toggle in a list | Action pill |
| Error indicator that opens detail | Action pill |
| Section create actions on iPhone | Floating dock |
| Search + actions on iPhone | Floating dock |

If a capsule doesn't fit any of these, ask whether it should be a capsule at all.

---

## Rules summary

1. **Every `Capsule()` belongs to a family.** If it doesn't fit status, metadata, action, or dock, reconsider the shape.
2. **Status pills use semantic states.** Never hardcode colours for status indication.
3. **Metadata pills are never interactive.** If it needs a tap action, it's an action pill.
4. **Action pills meet the 44pt touch target.** The visual capsule can be smaller, but the tap area cannot.
5. **Floating docks are iPhone-only.** iPad and Mac use header action rows.
6. **Floating docks use Liquid Glass.** No materials, no manual backgrounds.
7. **One floating dock per screen.** Collapse into menus rather than stacking docks.
8. **`accessibilityLabel` is required** on all interactive pills and all dock buttons.

---

## Related docs

- [Components Overview](./overview) — full component index
- [Header Actions](./header-actions) — iPad/Mac equivalent of dock actions
- [Feedback and Haptics](../patterns/feedback-and-haptics) — haptic feedback on pill interactions
- [Materials and Appearance](../foundations/materials-and-appearance) — Liquid Glass guidance
- [Implementation Gaps](../implementation-gaps) — known pill inconsistencies
