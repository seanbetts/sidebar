---
title: Patterns Audit
description: Current-state snapshot of behavioral patterns in sideBar — haptics, wait states, navigation, and material usage as they exist in the codebase today.
---

## Purpose

Documents how behavioral patterns are currently implemented in sideBar. This is a snapshot of reality, not a specification. As gaps are closed and the codebase converges with the design system, this doc should be updated to reflect the new state.

For the target state of each pattern, see the linked spec docs. For the list of actionable gaps, see [implementation-gaps](../implementation-gaps).

---

## Haptics

### Current implementation

Haptic feedback exists in two places only:

| Location | Implementation | Feedback types |
|---|---|---|
| `LoginView.swift` | Inline `UINotificationFeedbackGenerator` | `.success` on auth success, `.error` on auth failure |
| `BiometricLockView.swift` | Inline `UINotificationFeedbackGenerator` | `.success` on biometric success, `.error` on failure |

All other interactions that the spec requires haptic feedback for are not yet implemented. There is no `Design/Haptics.swift` helper — the target centralised enum does not yet exist.

The inline generator pattern used in `LoginView` and `BiometricLockView` is the wrong approach: it duplicates boilerplate, has no platform guard, and is not reusable. Both files must be migrated to `Haptics.notification(...)` once the helper is created.

### Interactions missing haptic feedback

| Interaction | Target feedback | File |
|---|---|---|
| Task completion checkbox | `notification(.success)` | `TasksViewComponents.swift:87` |
| Destructive delete (swipe) | `notification(.error)` | `SidebarSwipeActions.swift` |
| Floating action button tap | `impact(.light)` | `PhoneFloatingActionDock.swift:25` |
| Settings toggle state change | `selection()` | `SettingsSections+Additional.swift:41` |
| Archive / unarchive action | `selection()` | Context menu components |
| Pin / unpin action | `selection()` | Context menu components |
| Drag reorder completion | `notification(.success)` | Panel reorder files |

**Target spec**: [feedback-and-haptics](../patterns/feedback-and-haptics)

---

## Wait states

### Loading indicators

Both platforms use an animated GIF spinner:

- **Native**: `LoadingIndicatorView` (`Design/Components/LoadingIndicatorView.swift`) — platform-aware `UIImageView` (iOS) / `NSImageView` (macOS), separate assets for dark/light mode, cached via `NSCache`
- **Web**: `LoadingGlyph` (`frontend/src/lib/components/loading/LoadingGlyph.svelte`) — same GIF concept, same size scale

Both share the same six sizes: inline (16), control (20), panel (24), page (32), extensionPrimary (44), hero (128).

### Skeleton loading

- **Native**: `SidebarListSkeleton` — static placeholder rows, no animation, `textTertiary` at 35% opacity, variable widths per row
- **Web**: `SidebarLoading` — CSS shimmer animation (`loading-shimmer`, 1.6s infinite), three width variants (45%, 70%, 85%)

The web shimmer animation is being removed to align with native. Target is static placeholder rows on both platforms.

### Chat streaming

- **Native**: Typing reveal (`ChatViewModel+TypingReveal.swift`) — characters are revealed progressively at a configurable rate. A 14px inline spinner appears in the message row before the first token arrives, then disappears as reveal begins. The message status is `.streaming` during the stream.
- **Web**: Animated dot alongside "Working..." text while waiting for the first token. Once tokens arrive, content appears as SSE chunks land. Full response does not wait until stream end. Tool execution states shown inline per message: "Using {name}" (running), "Used {name}" (success), "Failed to use {name}" (error).

The web does not have character-paced reveal — this is intentional given markdown rendering constraints. The gap is the pre-first-token experience: the "Working..." dot should be replaced with an inline thinking indicator matching native.

### File ingestion and processing

**Native** (`IngestionCenterView` — `Views/Files/`):

A dedicated in-app panel tracking per-file status through three phases:

| Phase | Visual |
|---|---|
| Uploading | `LoadingIndicatorView` + `ProgressView(value:)` + percentage text |
| Processing | `LoadingIndicatorView` only (indeterminate) |
| Failed | Error icon + Retry + Dismiss buttons |

**Web** (`IngestionQueue.svelte`, `IngestionStatusCenter.svelte`):

Two separate components. `IngestionQueue` renders a list inside the files panel with per-file progress bars, pause/resume/cancel controls, and nine processing stages mapped to a 0–100% progress value. `IngestionStatusCenter` is a header component showing "In Progress" and "Failed" groups.

Both implementations are functional but surface-heavy for what is typically a background task. The target is to simplify the in-app surface and move active progress tracking to Live Activities on iOS.

### Save status

| Context | Component | States |
|---|---|---|
| Notes detail view | Toolbar icon in `NotesDetailView.swift` | Saving, Saved (2s auto-dismiss), Unsaved changes, Sync queued, Error |

`SyncStatusIndicator.swift` exists and is used in `SettingsSections+System.swift` as a verbose sync status display with text and a "View queued changes" button. This component is being removed — background/optimistic writes are silent per the spec.

### Button async states

- **Native**: Inconsistent. Most async buttons simply disable. Retry buttons additionally show a `ProgressView` at `.controlSize(.mini)` inside the button. No unified async button component exists.
- **Web**: More consistent. Button text changes to present-progressive form ("Adding..." for "Add task"). Button is disabled during the operation.

### Pull-to-refresh

Not confirmed implemented on iOS list panels. The `refreshable` modifier is the target pattern for all sidebar list panels.

**Target spec**: [wait-ux](../patterns/wait-ux)

---

## Navigation

### Scratchpad placement

The scratchpad button currently exists only inside an open `ChatView` conversation (`ChatView.swift`). It does not appear in other sections. The correct placement is in the section header or navigation bar of any section that shows the profile/settings avatar, immediately to its left.

### Web settings

Settings is currently presented as an `AlertDialog` modal (`SettingsDialog.svelte`). The layout is a two-column grid: a 240px left navigation sidebar and a scrollable content area. Section switching is state-driven via `activeSettingsSection` — there is no URL change and no browser navigation support.

Web sections differ in name from native:

| Web section | Native equivalent |
|---|---|
| Account | Profile |
| User | User |
| Agent | Agent |
| Storage | (no native equivalent) |
| Shortcuts | (no native equivalent) |
| Memory | Part of Agent tab |
| Store | (no native equivalent) |
| Skills | Skills |

**Target spec**: [navigation](../patterns/navigation)

---

## Material usage

### Liquid Glass adoption status

The only component consistently using `glassEffect` is `PhoneFloatingActionDock` (iOS). All other transient chrome surfaces are pending migration.

| Component | Current material | Target |
|---|---|---|
| `PhoneFloatingActionDock` | `glassEffect(.regular.interactive(), in: Capsule())` | Done |
| `NoteFormattingBar` | `.thinMaterial` | Liquid Glass |
| `MacPopoverShell` | Custom background | Liquid Glass |
| `MacModalShell` | Custom background | Liquid Glass |
| `SettingsMacStyles` | Custom settings surface | Liquid Glass |
| `SidebarRail` | Solid `sidebar` fill | Liquid Glass (validate against content legibility first) |
| `SiteHeaderBar` | Custom header background | Liquid Glass |
| `HeaderActionIcon` | No background | Liquid Glass |
| `PanelHeader` | `panelHeaderBackground()` solid fill | Liquid Glass |
| `SearchField` dock chrome | Custom | Liquid Glass |
| `LoginView` | Custom | Liquid Glass |

**Target spec**: [materials-and-appearance](../foundations/materials-and-appearance)

---

## Related docs

- [Implementation Gaps](../implementation-gaps)
- [Feedback and Haptics](../patterns/feedback-and-haptics)
- [Wait UX](../patterns/wait-ux)
- [Navigation](../patterns/navigation)
- [Materials and Appearance](../foundations/materials-and-appearance)
