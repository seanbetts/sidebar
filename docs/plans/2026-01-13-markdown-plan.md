# Markdown Editor + Styling Plan (Phase 11.2)

## Purpose
Consolidate the SwiftUI Markdown Editor work and the web parity styling goals into a single, actionable plan.

## Goals
- Replace the read-only markdown viewer with a native TextKit editor (macOS + iOS).
- Keep markdown as the source of truth and preserve TipTap parity behavior.
- Match SwiftUI rendering to the existing web editor theme (not GitHub CSS).
- Reduce duplication in web markdown styling (shared CSS).

## Scope
- SwiftUI editor (TextKit wrapper, formatting actions, autosave, conflict handling).
- SwiftUI markdown theme that mirrors web styling.
- Web markdown CSS consolidation (shared styles + documentation).

## Web Theme Parity Sources
- Editor block styles: `frontend/src/lib/components/editor/MarkdownEditor.svelte`
- Shared media styles: `frontend/src/app.css`
- Color tokens: `frontend/src/app.css` (`--color-*`)

## Theme Mapping (Web -> SwiftUI)
**Core typography + spacing:**
- Body line-height 1.7, paragraph margins 0.75em.
- H1 2.0em / 700 / margin-bottom 0.5em.
- H2 1.5em / 600 / margin 0.5em 0.
- H3 1.25em / 600 / margin 0.5em 0.
- Lists: padding-left 1.5em, line-height 1.4, margins 0.75em 0.
- Blockquote: left border 3px, padding-left 1em, margin 1em 0, muted color.
- Horizontal rule: 1px border, margin 2em 0.

**Inline code + blocks:**
- Inline: background muted, padding 0.2em 0.4em, radius 0.25em, font-size 0.875em.
- Block: background muted, padding 1em, radius 0.5em, margin 1em 0, monospace 0.875em.

**Tables:**
- 100% width, collapse, margin 1em 0, font-size 0.95em.
- Borders: 1px solid border, padding 0 0.75em.
- Thead muted + 600 weight.
- Zebra rows: color-mix muted 40%.

**Links:**
- Primary color, underlined.

**Media:**
- Images centered, max-height 350px, max-width 80%, padding 0.5rem.
- Captions 0.85rem, muted, centered.
- Gallery: flex grid, gap 0.75rem, image width 240px.

**SwiftUI token mapping:**
- foreground -> `DesignTokens.Colors.textPrimary`
- muted-foreground -> `DesignTokens.Colors.textSecondary`
- muted -> `DesignTokens.Colors.muted`
- border -> `DesignTokens.Colors.border`
- primary -> `Color.accentColor`
- radii -> `DesignTokens.Radius`

## Implementation Plan

### A) SwiftUI Editor (TextKit)
1. Add NotesEditorViewModel (content, selection, dirty, save, conflict).
2. Add cross-platform TextKit wrapper (UITextView/NSTextView):
   - Text binding + selection tracking
   - Undo integration
   - Formatting actions API
3. Wire NotesDetailView to editor state (loading/empty/error).
4. Add formatting toolbar (full + overflow on compact).
5. Autosave with debounce and dirty tracking.
6. External update handling (reload/keep).
7. Code block highlighting (regex attributes).

### B) SwiftUI Theme Parity
1. Build MarkdownTheme constants (fonts, spacing, colors).
2. Apply theme via NSAttributedString attributes in MarkdownFormatting.
3. Match list/blockquote indentation with paragraph style.
4. Keep max width at 85ch in editor.

### C) Web CSS Consolidation
1. Create `frontend/src/lib/styles/markdown-shared.css`.
2. Move duplicated table + task list styles into shared file.
3. Import shared file in `frontend/src/app.css`.
4. Remove per-component duplicates.
5. Document variations in `docs/MARKDOWN_STYLES.md`.

## Validation
- Edit a note, apply formatting, save, reload; content matches web output.
- Task lists, tables, links, code blocks persist across reload.
- Undo/redo works and cursor position is preserved.
- Visual parity check against web editor (typography, spacing, colors).

## Open Questions
- Inline code size: same as body or slightly smaller?
- Heading font choices: system with size overrides vs custom fonts?
- macOS link hover: keep underline or always underline?
