# CM6 Live Preview Fix Plan

## Goal
Stabilize live preview marker hiding while keeping read-only and edit styling identical (except the caret line).

## Scope
CodeMirror is the single renderer for both read-only and edit modes. Only the caret line shows raw markdown. Start with inline markers and heading marks; keep block markers visible until validated. Tables render as HTML when the caret is outside the table, and revert to raw markdown when the caret is inside. Code blocks render with the styled block wrapper unless the caret is inside.

## Steps
1. Implement inline marker collapsing for EmphasisMark/CodeMark/LinkMark (and LinkMark/URL/title) using CSS, reveal only on the caret line.
2. Replace heading `HeaderMark` with a zero-width widget via `Decoration.replace`, reveal only on the caret line.
3. Keep block markers (lists, blockquotes, fences) visible for now; revisit after stability.
4. Implement table rendering as a block widget when the caret is outside table ranges; show raw markdown when inside.
5. Implement code block rendering with the styled block wrapper when the caret is outside the block; show raw markdown when inside.
6. Ensure read-only mode uses the same CodeMirror renderer and CSS as edit mode.
7. Rebuild CM6 bundle and sync iOS resources.
8. Validate cursor navigation, line spacing, and formatting retention on iPad.
9. Update `SWIFTUI_MIGRATION_PLAN.md` and remove this plan doc when complete.
