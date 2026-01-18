# CM6 Live Preview Fix Plan

## Goal
Ship a polished reading experience first, while keeping editing raw markdown. Live preview and edit styling parity will return after the read-mode experience is solid.

## Scope
Reading mode: rich markdown rendering with consistent styling (MarkdownUI). Editing mode: raw markdown (no live preview) until read-mode styling is stable.

## Edit Mode Guardrails (CM6 in WKWebView)

### Core Principle
Do not change line geometry in edit mode. Treat `.cm-line` as immutable layout.

### Safe (Green List)
Safe CSS (token spans only):
- color, opacity
- font-weight, font-style
- text-decoration (underline/strike)
- background-color on inline spans
- border on inline spans (box-sizing: border-box)
- border-radius
- box-shadow (light use)
- transform (visual only)
- filter (visual only, sparingly)

Safe CM6 mechanisms:
- Syntax highlighting via `@codemirror/lang-markdown` and `HighlightStyle`
- `Decoration.mark` for inline styling (bold/italic/code/link parts)
- `Decoration.line` only to add classes (no margin/padding/font-size changes)
- `Decoration.widget` for small inline widgets (checkboxes, fold markers)
- Reveal-on-caret logic driven by selection state

Safe behavioral enhancements:
- Keymaps/commands that modify markdown text
- Selection-based toolbar state updates
- Viewport-only decoration recompute

### Unsafe (Red List)
Do not do in edit mode:
- On `.cm-line`: margin, padding, line-height, font-size changes
- display: none on content spans or marker chars
- position shifting that changes baselines
- block-level elements inside lines
- pseudo-elements on `.cm-line` that change height

Avoid:
- Large `Decoration.replace` over block regions
- Full-document regex scanning on selection/scroll

### Layered Approach to Styling
Layer 1: token styling only (no marker hiding).
Layer 2: marker fading (opacity), reveal on caret line/selection.
Layer 3: marker collapsing for punctuation markers only (font-size: 0).
Layer 4: small inline widgets (checkboxes, fold markers).

### Tricky Areas (Safe Approaches)
Headings:
- No font-size changes in edit mode.
- Use weight/color, optional token background.
- Optional experiment: `transform: scale()` on heading tokens only.

Blockquotes:
- Style quote text spans.
- Optional bar via inline widget, not line padding.

Lists/indent:
- Let CM handle indentation; avoid margins/padding.
- Use background guides on editor container if needed.

Code fences:
- Minimal token-level background tint.
- No padding or font-size changes.

Tables:
- Edit mode stays raw markdown; optional monospace tint on range.

Images/embeds:
- Edit mode shows markdown; fade markers outside active line.

### Guardrails
- Wrap decoration builders in try/catch; keep last-known-good set.
- Validate decoration ranges are sorted and in-bounds.
- Recompute only for `view.visibleRanges`.
- Feature flags per enhancement: marker fade, marker collapse, checkbox widgets, heading scale.

### Regression Checklist
- Up/down arrow navigation through headings/lists
- Caret visibility under fast scroll
- Tap-to-place caret in headings/quotes/lists/code
- Toggle read/edit mid-scroll repeatedly
- Hardware keyboard vertical navigation

## Steps
- [x] Decide the read-mode renderer (MarkdownUI vs CodeMirror read-only).
- [x] Implement and polish read-mode styling (tables, code blocks, headings, lists, blockquotes, image captions).
- [x] Keep edit mode raw markdown with minimal styling.
- [x] Unify read-mode markdown rendering across notes/websites/files/chats (one theme, one preprocessing path, shared layout).
- [x] Adjust chat-specific code styling for contrast against chat bubble backgrounds.
- [x] Validate read-mode rendering across iOS/iPad/macOS.
- [ ] Revisit live preview (caret-line raw markdown + inline marker hiding).

## Exit Criteria
- Read mode looks polished and consistent across platforms.
- Edit mode remains stable and predictable with raw markdown.
- Known caret/navigation bugs are no longer blocking progress.

## Open Issues (Investigate)
- Edit-mode: tap-to-caret should map to the correct document position when entering edit mode; currently lands on top-of-note content even when tapping deep in the note.

## Next Investigation: Tap-to-Caret Mapping (Edit Mode)

Goal: when tapping in read mode, enter edit mode with the caret mapped to the tapped content position (same paragraph/line), without scroll jump.

Candidate approaches to test (lowest risk first):
1) Use a hidden CM6 read-only overlay for hit-testing.
   - Keep a lightweight CodeMirror view in read-only mode behind the MarkdownUI view.
   - Map tap coordinates to a CM position via `posAtCoords`, then pass that to the edit view on activation.
   - Pros: uses CM’s own geometry mapping; avoids manual text layout math.
   - Cons: extra view to keep in sync; needs careful layout/scroll alignment.

2) Inline CM6 for read mode (single view toggle).
   - Use CM6 for both read/edit, but keep read mode styling minimal (raw markdown).
   - On tap, just switch editable state and set selection at `posAtCoords`.
   - Pros: single source of truth for geometry; no handoff.
   - Cons: loses MarkdownUI read-mode styling unless we add a CM6 renderer.

3) MarkdownUI hit-testing with layout manager → string index.
   - Use `TextLayout`/`TextRenderer` or attributed string layout to map tap to character index.
   - Convert attributed index to markdown offset; enter edit mode at that offset.
   - Pros: no extra CM view.
   - Cons: hard to keep mapping accurate for markdown transformations (links, images, tables).

Minimum success criteria:
- Tap in read mode at end/middle of note enters edit mode with caret on the same line.
- No jump to top of note.
- Scroll position stays stable (same content in view).
