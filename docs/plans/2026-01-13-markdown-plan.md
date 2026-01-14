# Markdown Editor + Styling Plan (Phase 11.2)

## Purpose
Consolidate the SwiftUI Markdown Editor work and the web parity styling goals into a single, actionable plan.

## Goals
- Replace the TextKit editor with a CodeMirror 6 WYSIWYG editor in a WKWebView (macOS + iOS).
- Keep markdown as the source of truth and preserve web parity behavior.
- Share the same styling between web and native clients (single CM6 theme).

## Scope
- WKWebView-based CM6 editor (shared web bundle + native bridge).
- Shared CM6 theme (single source of truth for styling).
- Native bridge for autosave, selection, formatting commands, and external updates.

## Theme Sources (CM6)
- Shared CM6 theme (new source of truth).
- Existing web tokens: `frontend/src/app.css` (`--color-*`).
- Web markdown refinements: `docs/MARKDOWN_STYLES.md` (current canonical styling).
- Shared web rules: `frontend/src/lib/styles/markdown-shared.css` (single source for shared markdown CSS).

## Theme Mapping (Web -> CM6)
**Core typography + spacing (shared in `markdown-shared.css`):**
- Body line-height 1.7, paragraph margins 0.5rem top/bottom.
- H1 2.0em / 700 / margin-top 0, margin-bottom 0.3rem.
- H2 1.5em / 600 / margin-top 1rem, margin-bottom 0.3rem.
- H3 1.25em / 600 / margin-top 1rem, margin-bottom 0.3rem.
- H4 1.125em / 600 / margin-top 1rem, margin-bottom 0.3rem.
- H5 1.0625em / 600 / margin-top 1rem, margin-bottom 0.3rem.
- H6 1.0em / 600 / margin-top 1rem, margin-bottom 0.3rem.
- All headings use `line-height: 1.3`.
- Lists: padding-left 1.5em, line-height 1.4, margins 0.5rem 0.
- Blockquote: left border 3px, padding-left 1em, margin 1em 0, muted color.
- Horizontal rule: 1px border, margin 2em 0.

**Inline code + blocks:**
- Inline: background muted, padding 0.2em 0.4em, radius 0.25em, font-size 0.875em, monospace.
- Block: background muted, padding 1em, radius 0.5em, margin 1em 0, monospace 0.875em, overflow-x auto.

**Tables (per `docs/MARKDOWN_STYLES.md` + shared CSS):**
- 100% width, collapse, margin 1em 0, font-size 0.95em.
- Borders: 1px solid border with `!important` to ensure visibility.
- Body padding: 0.5em vertical, 0.75em horizontal.
- Header: darker OKLAB mix, 0.65em vertical padding, 2px bottom border, weight 600.
- Zebra rows: OKLAB muted 40% / transparent 60%.

**Links:**
- Primary color, underlined.

**Media:**
- Images centered, max-height 350px, max-width 80%, padding 0.5rem.
- Captions 0.85rem, muted, centered.
- Gallery: flex grid, gap 0.75rem, image width 240px.

**Token mapping:**
- foreground -> `--color-foreground`
- muted-foreground -> `--color-muted-foreground`
- muted -> `--color-muted`
- border -> `--color-border`
- primary -> `--color-primary`

## Implementation Plan

### A) CodeMirror 6 Editor (WKWebView)
1. Add CM6 editor bundle (shared build artifact for iOS/macOS).
2. Build WKWebView container with JS bridge:
   - Load markdown
   - Track selection/cursor
   - Emit change events (debounced autosave)
   - Apply formatting commands from native UI
3. Wire NotesDetailView to the webview state (loading/empty/error).
4. Add CM6 extensions: markdown, tables, task lists, code blocks, links, images.
5. External update handling: push server changes into CM6 with conflict prompts.

### B) Theme Parity (CM6)
1. Create CM6 theme based on `docs/MARKDOWN_STYLES.md` and `frontend/src/lib/styles/markdown-shared.css`.
2. Map CSS custom properties to native theme tokens.
3. Keep max width at 85ch in editor.
4. Ensure heading levels H1-H6 and list spacing match shared CSS (rem-based margins).

### C) Web Styling Consolidation
1. Keep `docs/MARKDOWN_STYLES.md` as the canonical styling reference.
2. Reuse CM6 theme in web app for notes editing (if migrating from TipTap).
3. Document CM6 theme tokens and extensions.

---

## CM6 + WKWebView Integration Draft

### 1) Bundle + Build Pipeline
- Create a standalone CM6 bundle in `frontend/` (Vite build output).
- Output a single `editor.html` + `editor.js` + `editor.css` with hashed assets disabled for iOS bundling.
- Add a CI step to copy the bundle into `ios/sideBar/sideBar/Resources/CodeMirror/` (script: `scripts/build-codemirror.sh`).
- Add a version stamp (`editor-version.json`) to invalidate native caches.

### 2) Web Editor Surface
- Single root `<div id="editor">` with CM6 view.
- Initialize with:
  - Markdown extension set (tables, task lists, fenced code, links, images).
  - Theme from `docs/MARKDOWN_STYLES.md` tokens.
  - Placeholder behavior (“Start writing…”).
- API surface in JS:
  - `setMarkdown(text)`
  - `getMarkdown()`
  - `setReadOnly(isReadOnly)`
  - `focus()`
  - `applyCommand(name, payload)`

### 3) Native Bridge (Swift)
- WKWebView wrapper view with message handlers:
  - `editorReady`
  - `contentChanged`
  - `selectionChanged`
  - `linkTapped` (if needed)
- Debounced save on native side (align with current autosave logic).
- Push external updates: compare version, prompt conflict UI if dirty.

### 4) Editor Commands
- Command map (native -> JS):
  - bold/italic/strike/heading/list/blockquote/hr
  - task toggle
  - insert table
  - insert link
  - insert code block
- Keep toolbar deferred for now; use keyboard shortcuts and menu actions only.

### 5) State + Lifecycle
- Load note content on `editorReady`.
- Persist scroll/selection on note switch.
- Tear down webview on note change to avoid stale state.

### 6) Validation Checklist
- Round‑trip markdown correctness (save + reload).
- Table + task list rendering parity.
- Inline/code block parity.
- Links and images parity.
- iOS + macOS consistency (font sizes, line height, spacing).

## Validation
- Edit a note, apply formatting, save, reload; content matches web output.
- Task lists, tables, links, code blocks persist across reload.
- Undo/redo works and cursor position is preserved.
- Visual parity across web + native with shared CM6 theme.

## Open Questions
- How do we package the CM6 bundle for iOS/macOS (shared build artifact)?
- Do we keep TipTap for web or migrate notes editing to CM6 for parity?

## Iteration 1 Status (2026-01-13)
- [x] CM6 bundle skeleton created (`frontend/src/codemirror` + Vite build config).
- [x] JS bridge implemented: `editorReady`, debounced `contentChanged`, editor API.
- [x] WKWebView wrapper added and Notes editor swapped to CodeMirror view.
- [x] Autosave wired to contentChanged events.
- [x] Bundle copy step automated (`scripts/build-codemirror.sh`).
- [x] CM6 loads in WKWebView and renders note content (iOS + macOS).
- [ ] CM6 theme parity + markdown extensions beyond base `markdown()` configured (needs full parity pass vs `docs/MARKDOWN_STYLES.md`).

## Remaining Work (Post-Iteration 1)
- [ ] Validate markdown extensions (tables, task lists, fenced code, links, images) against web behavior.
- [ ] Complete CM6 theme parity with `docs/MARKDOWN_STYLES.md` and `frontend/src/lib/styles/markdown-shared.css`.
- [ ] Align heading levels H1-H6, list spacing, and paragraph margins with shared CSS.
- [ ] Review CSS token mapping against `frontend/src/app.css` and remove redundant styles.
