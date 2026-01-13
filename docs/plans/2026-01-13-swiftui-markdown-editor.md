# SwiftUI Markdown Editor (Phase 11.2) Plan

## Goals
- Replace the read-only markdown viewer in Notes with a native TextKit-based editor.
- Keep markdown as the source of truth and preserve TipTap parity behavior.
- Add editing UX (toolbar, formatting actions, autosave, conflict handling).

## Steps
1. Review markdown formats in web TipTap (task lists, tables, image blocks) and map required markdown tokens.
2. Add a NotesEditorViewModel to own editor state (content, selection, dirty, save, conflict).
3. Build a cross-platform TextKit editor wrapper (UITextView/NSTextView) with:
   - Text binding + selection tracking
   - Undo manager integration
   - Custom keyboard commands (Cmd+B/I, etc.)
   - Formatting actions API
4. Wire NotesDetailView to use the editor and reflect state (loading, empty, errors).
5. Implement toolbar parity (primary actions + overflow on compact) and markdown actions.
6. Implement autosave with debounce and dirty state tracking.
7. Add external update handling (server/AI updates) with merge/prompt behaviors.
8. Add code block highlighting (regex-based TextKit attributes) and perf safeguards.

## Validation
- Edit a note, apply formatting, save, reload, and confirm markdown round-trip matches web output.
- Verify task lists, tables, links, and code blocks persist across reload.
- Confirm undo/redo works and cursor position is preserved on external updates.
