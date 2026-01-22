# Unified CodeMirror Editor Plan

## Goal

Achieve web app parity for iOS note editing by using a single CodeMirror 6 view for both read and edit modes. This eliminates the tap-to-caret bug where tapping in read mode lands the cursor at the wrong position.

## Problem Statement

### Current Architecture (iOS)
- **Read mode**: MarkdownUI (SwiftUI native renderer)
- **Edit mode**: CodeMirror 6 (WKWebView)
- **Transition**: Tap in read mode → swap to edit mode view

### The Bug
When tapping in read mode to enter edit mode:
1. Tap coordinates are captured relative to the MarkdownUI view
2. Coordinates are passed to CodeMirror's `setSelectionAtCoordsDeferred()`
3. CodeMirror maps coordinates using its own geometry (different from MarkdownUI)
4. Caret lands at wrong position (usually top of note)

### Root Cause
MarkdownUI and CodeMirror have completely different:
- Scroll positions (not synchronized)
- Line heights (MarkdownUI headings are 2em, CodeMirror is uniform)
- Content geometry (rendered markdown vs raw text)
- Coordinate systems

## Solution: Single CodeMirror View

Use CodeMirror 6 for both read and edit modes:
- **Read mode**: `setReadOnly(true)` + block preview widgets + marker hiding
- **Edit mode**: `setReadOnly(false)` + raw markdown with syntax highlighting

### Why This Works
1. Same view for both modes → same geometry
2. `view.posAtCoords()` maps correctly because coordinates match content
3. Scroll position preserved (no view swap)
4. Existing `blockPreviewField` already renders tables/code/images as widgets

## Existing CM6 Infrastructure

The web frontend's `frontend/src/codemirror/index.ts` (1600+ lines) already includes:

### Widgets (Ready)
| Widget | Purpose |
|--------|---------|
| `ImageWidget` | Renders `<figure><img><figcaption>` for images |
| `TablePreviewWidget` | Full HTML table from markdown table syntax |
| `CodeBlockPreviewWidget` | `<pre><code>` with language annotation |
| `ListMarkerWidget` | Bullet point replacement (`• `) |

### State Fields & Plugins (Ready)
| Component | Purpose |
|-----------|---------|
| `blockPreviewField` | Replaces tables/code blocks with widgets when read-only or cursor outside |
| `livePreviewPlugin` | Hides markdown syntax markers, reveals on caret proximity |
| `markdownLinePlugin` | Applies line decorations (headings, lists, blockquotes, etc.) |

### Line Decorations (Ready)
- Headings: `cm-heading-1` through `cm-heading-6`
- Lists: `cm-list-item`, `cm-list-ordered`, `cm-list-unordered`
- Tasks: `cm-task-item`, `cm-task-item--checked`
- Code: `cm-code-block`, `cm-code-block--start`, `cm-code-block--end`
- Blockquotes: `cm-blockquote` with `--blockquote-depth` CSS variable
- Other: `cm-paragraph`, `cm-hr`, `cm-media-line`, `cm-blank-line`

### API Functions (Ready)
- `setReadOnly(bool)` - Toggle editable state
- `setSelectionAtCoords({x, y})` - Map coordinates to position
- `setSelectionAtCoordsDeferred({x, y})` - Deferred version for mode transitions

## Implementation Phases

### Phase 1: CSS Styling for Read Mode

Add rich styling to `ios/sideBar/sideBar/Resources/CodeMirror/editor.css`:

```css
/* Headings */
.cm-heading { line-height: 1.3; }
.cm-heading-1 { font-size: 2em; font-weight: 700; margin-top: 0; margin-bottom: 0.3rem; }
.cm-heading-2 { font-size: 1.5em; font-weight: 600; margin-top: 1rem; margin-bottom: 0.3rem; }
.cm-heading-3 { font-size: 1.25em; font-weight: 600; margin-top: 1rem; margin-bottom: 0.3rem; }
.cm-heading-4 { font-size: 1.125em; font-weight: 600; margin-top: 1rem; margin-bottom: 0.3rem; }
.cm-heading-5 { font-size: 1.0625em; font-weight: 600; margin-top: 1rem; margin-bottom: 0.3rem; }
.cm-heading-6 { font-size: 1em; font-weight: 600; margin-top: 1rem; margin-bottom: 0.3rem; }

/* Paragraphs */
.cm-paragraph { line-height: 1.7; margin: 0.5rem 0; }

/* Blockquotes */
.cm-blockquote {
  border-left: 3px solid var(--color-border);
  padding-left: 1em;
  color: var(--color-muted-foreground);
  margin: 1em 0;
}

/* Code blocks */
.cm-code-block-preview {
  background: var(--color-muted);
  padding: 1em;
  border-radius: 0.5em;
  overflow-x: auto;
  margin: 1em 0;
}
.cm-code-block-preview pre { margin: 0; }
.cm-code-block-preview code {
  font-family: 'SF Mono', Monaco, monospace;
  font-size: 0.875em;
  line-height: 1.5;
}

/* Tables */
.cm-table-preview-wrapper { margin: 0.75rem 0; overflow-x: auto; }
.cm-table-preview {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.95em;
}
.cm-table-preview th, .cm-table-preview td {
  border: 1px solid var(--color-border);
  padding: 0.5em 0.75em;
  text-align: left;
  vertical-align: top;
}
.cm-table-preview thead th {
  background-color: var(--color-muted);
  font-weight: 600;
  border-bottom: 2px solid var(--color-border);
}

/* Images */
.cm-media-widget {
  display: block;
  margin: 1em 0;
  text-align: center;
}
.cm-media-widget img {
  max-width: 100%;
  max-height: 450px;
  border-radius: 0.5em;
}
.cm-media-widget figcaption {
  font-size: 0.875em;
  color: var(--color-muted-foreground);
  margin-top: 0.5em;
}

/* Lists */
.cm-list-item { line-height: 1.4; }
.cm-list-marker-widget { color: var(--color-muted-foreground); }

/* Task lists */
.cm-task-item--checked {
  color: var(--color-muted-foreground);
  text-decoration: line-through;
  opacity: 0.6;
}

/* Horizontal rules */
.cm-hr {
  border: none;
  border-top: 1px solid var(--color-border);
  margin: 2em 0;
}

/* Links (in read mode) */
.cm-link { color: var(--color-primary); text-decoration: underline; }

/* Inline code */
.cm-inline-code {
  background-color: var(--color-muted);
  padding: 0.2em 0.4em;
  border-radius: 0.25em;
  font-family: 'SF Mono', Monaco, monospace;
  font-size: 0.875em;
}
```

### Phase 2: Swift View Architecture Change

Update `MarkdownEditorView.swift` to always use CodeMirror:

```swift
// Before (two views):
@ViewBuilder
private var editorSurface: some View {
    if isEditing && !viewModel.isReadOnly {
        CodeMirrorEditorView(...)
    } else {
        ScrollView {
            SideBarMarkdownContainer(text: viewModel.content)
        }
    }
}

// After (single view):
@ViewBuilder
private var editorSurface: some View {
    CodeMirrorEditorView(
        markdown: viewModel.content,
        isReadOnly: !isEditing || viewModel.isReadOnly,
        handle: editorHandle,
        onContentChanged: viewModel.handleUserMarkdownEdit,
        onEscape: { isEditing = false }
    )
}
```

Simplify tap handling (no more coordinate translation needed):
```swift
// Before: complex coordinate mapping
.simultaneousGesture(
    DragGesture(minimumDistance: 0, coordinateSpace: .named("appRoot"))
        .onEnded { value in
            let localX = value.location.x - editorFrame.origin.x
            let localY = value.location.y - editorFrame.origin.y
            viewModel.pendingCaretCoords = CGPoint(x: localX, y: localY)
            isEditing = true
        }
)

// After: just toggle mode, CM handles position
.onTapGesture {
    guard !viewModel.isReadOnly else { return }
    isEditing = true
    editorHandle.focus()
}
```

### Phase 3: Verify Block Preview Behavior

The existing `blockPreviewField` in `index.ts` already:
1. Checks `state.facet(EditorState.readOnly)`
2. Shows widget replacements when read-only OR cursor is outside block
3. Reveals raw markdown when cursor enters the block

Verify this works correctly:
- [ ] Tables show as rendered HTML in read mode
- [ ] Tables reveal raw markdown when editing inside
- [ ] Code blocks show styled preview in read mode
- [ ] Code blocks reveal fenced markdown when editing
- [ ] Images show `<figure>` widget in read mode
- [ ] Images reveal `![alt](url)` syntax when editing line

### Phase 4: Live Preview Marker Hiding

Enable `livePreviewPlugin` behavior in read mode to hide syntax markers:
- `#` heading markers
- `*` / `_` emphasis markers
- `[text](url)` link syntax (show only text, clickable)
- `` ` `` code backticks
- `>` blockquote markers

The plugin already supports this with reveal-on-caret logic.

### Phase 5: Polish & Testing

**Functional tests:**
- [ ] Tap anywhere in read mode → enters edit mode with caret at tap position
- [ ] Scroll down, tap → caret lands at correct line (not top)
- [ ] Toggle read/edit rapidly → no scroll jump
- [ ] Edit content → auto-save triggers correctly
- [ ] External update banner still works

**Visual parity tests:**
- [ ] Headings match MarkdownUI sizing
- [ ] Code blocks have proper background and padding
- [ ] Tables render with borders and header styling
- [ ] Images centered with max dimensions
- [ ] Blockquotes have left border
- [ ] Links are styled and clickable in read mode

**Platform tests:**
- [ ] iPhone (various sizes)
- [ ] iPad (split view, full screen)
- [ ] macOS (with hardware keyboard)

## Edit Mode Guardrails

When in edit mode (not read-only), preserve line geometry stability:

### Safe (token-level only)
- `color`, `opacity`, `font-weight`, `font-style`
- `text-decoration` (underline/strike)
- `background-color` on inline spans
- `Decoration.mark` for inline styling
- `Decoration.widget` for small inline widgets

### Unsafe (avoid in edit mode)
- `margin`, `padding`, `line-height`, `font-size` on `.cm-line`
- `display: none` on content spans
- Large `Decoration.replace` over block regions
- Position shifting that changes baselines

### Rationale
Changing line geometry while editing causes:
- Cursor position jumps
- Arrow key navigation bugs
- Scroll position instability
- Layout thrashing on every keystroke

## Migration Notes

### Files to Modify
1. `ios/sideBar/sideBar/Resources/CodeMirror/editor.css` - Add read mode styling
2. `ios/sideBar/sideBar/Views/Notes/MarkdownEditorView.swift` - Single view architecture
3. `ios/sideBar/sideBar/ViewModels/NotesEditorViewModel.swift` - Remove `pendingCaretCoords` if unused

### Files to Keep
- `frontend/src/codemirror/index.ts` - Source of truth for CM6 bundle
- `ios/sideBar/sideBar/Views/Notes/CodeMirrorEditorView.swift` - WebView bridge (no changes needed)

### Files Potentially Removable (After Verification)
- Read mode may no longer need `SideBarMarkdownContainer` for notes
- Keep `SideBarMarkdown` for other contexts (chat, files, websites) that don't need editing

## Success Criteria

1. **Tap-to-caret works**: Tap in read mode places caret at tapped content
2. **Scroll preserved**: No jump when switching modes
3. **Visual parity**: Read mode looks equivalent to current MarkdownUI rendering
4. **Edit stability**: No regressions in editing experience
5. **Performance**: Smooth scrolling and mode transitions

## Future Work (Out of Scope)

- Image gallery widget (multi-image grid layout)
- Interactive task checkboxes (tap to toggle)
- Syntax highlighting in code blocks (requires language detection)
- Collaborative editing indicators

## References

- Web TipTap editor: `frontend/src/lib/components/editor/`
- CM6 implementation: `frontend/src/codemirror/index.ts`
- Shared markdown CSS: `frontend/src/lib/styles/markdown-shared.css`
- Current iOS editor: `ios/sideBar/sideBar/Views/Notes/`
