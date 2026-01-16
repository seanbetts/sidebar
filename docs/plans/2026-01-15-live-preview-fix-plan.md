# CM6 Live Preview Fix Plan

## Goal
Ship a polished reading experience first, while keeping editing raw markdown. Live preview and edit styling parity will return after the read-mode experience is solid.

## Scope
Reading mode: rich markdown rendering with consistent styling. Editing mode: raw markdown (no live preview) until read-mode styling is stable.

## Steps
- [ ] Decide the read-mode renderer (MarkdownUI vs CodeMirror read-only).
- [ ] Implement and polish read-mode styling (tables, code blocks, headings, lists, blockquotes).
- [ ] Keep edit mode raw markdown with minimal styling.
- [ ] Validate read-mode rendering across iOS/iPad/macOS.
- [ ] Revisit live preview (caret-line raw markdown + inline marker hiding).

## Exit Criteria
- Read mode looks polished and consistent across platforms.
- Edit mode remains stable and predictable with raw markdown.
- Known caret/navigation bugs are no longer blocking progress.

## Open Issues (Investigate)
- Caret placement + vertical navigation still unstable in edit mode.
- Toolbar flicker tied to edit-mode selection timing.
