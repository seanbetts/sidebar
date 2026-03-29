---
title: Web Conventions
description: Web app conventions for layout, navigation, settings, and browser-specific patterns in sideBar.
---

| Field | Value |
|---|---|
| Status | approved |
| Owner | AI coding agent |
| Outputs | this doc |
| Dependencies | [overview](./overview) |

## Purpose

Document web-specific design conventions for sideBar. The web app is a **secondary platform** — the native Apple apps (iPhone, iPad, Mac) are the reference point for feature completeness and design quality. The web app should preserve the same mental model and aim for feature parity where practical, but does not need to replicate native Apple chrome.

---

## Technology stack

| Layer | Technology |
|---|---|
| Framework | SvelteKit 2 / Svelte 5 (runes) |
| Styling | Tailwind CSS 4 |
| Components | bits-ui 2 (headless) |
| Icons | Lucide Svelte |
| Rich text | Tiptap 3 |
| Auth / realtime | Supabase |

---

## Web layout

The web app uses a split-view layout closely mirroring the native WorkspaceLayout:

```
[ SidebarRail 56px ] [ Left panel ~280px ] [ ResizeHandle ] [ Main content ]
```

The left panel is **user-resizable** via a drag handle, with snap points at 33%, 40%, and 50% of available width. Width is persisted in localStorage.

At ≤900px the resize handle is hidden and the sidebar fixes at 340px. Touch swipe gestures toggle the sidebar open/close at this size. This is not a full mobile redesign — the web app is primarily a desktop experience.

**Rule**: The web layout is the correct approach. It intentionally mirrors the workspace model rather than using browser-native navigation patterns.

---

## Web navigation

### SidebarRail

A 56px `SidebarRail` component matches the native rail visually and structurally:
- Five section icons (Notes, Tasks, Websites, Files, Chat) using Lucide Svelte icons
- Skills Store button (pinned bottom)
- Profile/Settings avatar button (pinned bottom)
- Collapse/expand toggle button (top)
- Active section highlighted with background and border
- Tooltips shown when sidebar is collapsed

Source: `frontend/src/lib/components/left-sidebar/SidebarRail.svelte`

**Gap**: Web uses **Lucide Svelte** icons, not SF Symbols. On web, SF Symbols are not available. The icon vocabulary differs from native. The same conceptual icons should be used where Lucide equivalents exist; icon choices should be audited against the native SF Symbol choices to keep recognition consistent.

### Section navigation

Section state is managed via Svelte stores, not URL routes. All sections render within a single authenticated layout. Last selected section is persisted in localStorage.

**Keyboard shortcuts**: Cmd/Ctrl + 1–5 to switch sections. These match the native Mac shortcuts.

### Left panel

Each section has a list panel (280px) showing the section-specific list:
- Chat: Conversation list with search
- Notes: Folder/file tree with pinning, archive, search
- Tasks: Project/group/task hierarchy with filtering
- Websites: Website list with pinning, archive
- Files: File tree with ingestion queue

Source: `frontend/src/lib/components/left-sidebar/Sidebar.svelte`

---

## Sections and feature state

| Section | Web status | Known gaps vs native |
|---|---|---|
| Chat | Complete | — |
| Notes | Complete | — |
| Tasks | Functional | No dedicated task detail view; editing via modal dialogs only |
| Websites | Complete | Transcript UI is basic (status icons only) |
| Files | Functional | Extent of file type support unclear |
| Scratchpad | Accessible (header popover) | Not a top-level section; entry point differs from native |
| Settings | Complete (modal dialog) | Settings presented as modal, not dedicated window or sheet |
| Skills Store | Available (within Settings) | Not a standalone section as on native |

---

## Web settings

Settings should be presented as a **dedicated `/settings` route**, not a modal dialog. The current implementation uses a modal `AlertDialog` which does not support browser back/forward navigation or deep-linking to specific settings sections.

The `/settings` route should:
- Use the same full-screen workspace layout as the main app
- Support deep-linking to specific sections (e.g. `/settings/account`, `/settings/skills`)
- Be navigable via browser back/forward
- Be accessible from the profile avatar in the SidebarRail

**Current state**: Modal dialog (`AlertDialog`). This needs to be migrated to a dedicated route.

This differs from native platforms by design:
- iOS: sheet (correct for mobile)
- Mac: dedicated window (correct for desktop app)
- Web: dedicated route (correct for browser)

---

## Web color palette

**Direction**: The web color palette should be aligned with the unified iOS/macOS palette. A single consistent palette across all platforms is the goal. The web CSS custom properties (`app.css`) should be defined alongside the native token values in `foundations/colour.md` — that doc is the single source of truth for all platform palette values.

**Current state**: OKLCH-based CSS custom properties, near-neutral near-black dark mode. Broadly correct in intent, exact values to be reconciled when `foundations/colour.md` is drafted.

**Dark mode**: Full support. Theme toggled via a mode switch in the site header. Preference persisted in localStorage with system preference fallback.

---

## Web typography

No explicit font imports. System default font stack is used (Tailwind defaults: `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif`).

On macOS and iOS browsers this resolves to the system font — effectively aligning with the native apps. On Windows and other platforms it will use the platform-appropriate system font.

**Rule**: Do not import a web font for general UI text. System fonts are correct here.

Prose/markdown content uses `@tailwindcss/typography` classes. Rich text editing uses Tiptap 3.

---

## Web icons

Lucide Svelte is used for all icons. SF Symbols are not available on web.

**Rule**: Use the closest Lucide equivalent to the SF Symbol used in the native apps. Do not introduce decorative icons not present in the native apps. The icon vocabulary should be as consistent as possible across platforms even when the specific icon differs.

A formal mapping of native SF Symbols to Lucide Svelte equivalents should be maintained in `foundations/iconography.md`. This mapping is the reference for web icon choices — when adding a new icon on web, look up the SF Symbol used in the native apps and find its Lucide equivalent, not the other way around.

---

## Create actions

All create actions on web are triggered from section header buttons in the left panel. There is no floating action dock equivalent.

| Section | Create actions | Pattern |
|---|---|---|
| Chat | New chat | Header icon button — direct call, no modal |
| Notes | New note, New folder | Header icon buttons — modal dialogs |
| Tasks | New task, New group, New project | Header dropdown menu — inline draft form (task) or modal dialogs (group, project) |
| Websites | Save website | Header icon button — modal dialog with URL input and validation |
| Files | Upload file, Add YouTube video | Header icon buttons — file input (upload) or modal dialog (YouTube URL) |

**Rule**: Create actions belong in the section header, not in a floating dock. The header button pattern is the correct web equivalent of the native floating action dock.

Source: `frontend/src/lib/components/left-sidebar/Sidebar.svelte`

---

## Web-specific patterns

### Responsive behaviour

The web app targets desktop browsers primarily. The layout adapts at two breakpoints:
- **≤1100px**: Sidebar constrained to minimum width
- **≤900px**: Resize handle hidden, sidebar fixed at 340px, swipe gestures available

Below 900px the app is usable but not optimised for mobile browsers. A full mobile web experience is out of scope for now.

**Rule**: Do not design web features specifically for mobile browsers. If mobile web access is needed, the native iOS app is the correct answer.

### Scratchpad

On web, Scratchpad is accessible via a popover in the site header — not a top-level section or nav item. This differs from native where it is accessible from the Chat nav bar button. The web approach (header popover) is a reasonable web-native pattern and does not need to match native exactly.

### Drag and drop

Drag-and-drop reordering is implemented for notes pinning and file management. This is a browser-native capability used correctly.

### Keyboard shortcuts

| Shortcut | Action |
|---|---|
| Cmd/Ctrl + 1–5 | Navigate to sections |

Full shortcut documentation for web is incomplete. A web keyboard shortcut audit is needed.

---

## Web accessibility conventions

- WCAG AA is the minimum target
- Semantic HTML via SvelteKit and bits-ui headless components
- Keyboard navigation: interactive elements reachable by Tab
- Focus management: bits-ui handles focus trapping in modals and dialogs
- Screen reader: accessible labels via bits-ui ARIA defaults
- Contrast: OKLCH color palette provides good contrast ratios
- Reduce motion: respect `prefers-reduced-motion` in all animations via the CSS media query and `window.matchMedia('(prefers-reduced-motion: reduce)')`

---

## Related docs

- `platform-strategy/overview.md`
- `platform-strategy/ios-conventions.md`
- `platform-strategy/macos-conventions.md`
- [Colour](../foundations/colour)
- [Iconography](../foundations/iconography)
