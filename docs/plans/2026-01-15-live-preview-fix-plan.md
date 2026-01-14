# CM6 Live Preview Fix Plan

## Goal
Stabilize live preview marker hiding without breaking layout or selection mapping.

## Scope
Inline marker collapsing and heading marker replacement only. Block markers (lists, blockquotes, fences) remain visible or lightly styled until validated.

## Steps
1. Implement inline marker collapsing for EmphasisMark/CodeMark/LinkMark using CSS (font-size: 0 + tight letter-spacing), reveal on active selection/line.
2. Replace heading `HeaderMark` with a zero-width widget via `Decoration.replace`, reveal when caret is on the heading line.
3. Keep URLs visible but optionally faded; do not hide block markers yet.
4. Rebuild CM6 bundle and sync iOS resources.
5. Validate cursor navigation, line spacing, and formatting retention on iPad.
6. Update `SWIFTUI_MIGRATION_PLAN.md` and remove this plan doc when complete.
