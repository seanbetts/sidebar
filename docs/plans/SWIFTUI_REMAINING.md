# SwiftUI Remaining Work Plan (Jan 2026)

## Goal
Finish the remaining SwiftUI parity work with a short, focused checklist.

## Remaining Items

### 1) Phase 11.2 (Markdown Editor)

**Selection/Undo Parity**
- [x] Keep cursor stable on external updates
  - ExternalUpdateBanner implemented with Keep/Reload actions
  - Cursor position clamped to valid range after reload
  - Note: Unified CM6 editor will simplify this (single view, no mode transition)

**Performance Optimization**
- [ ] Long-note performance: incremental rendering + minimal layout churn
  - Profile notes >10,000 words to identify bottlenecks
  - Consider lazy rendering for very long documents
  - Minimize expensive modifiers during scroll
  - Test with realistic long notes from actual usage

**Missing Formatting Actions**
- [ ] Underline formatting action
  - Add to toolbar (primary or overflow menu)
  - Bridge command to CodeMirror 6: apply `<u>` tag or markdown extension
  - Ensure round-trip fidelity with web editor

**Image Gallery Blocks**
- [ ] Gallery block parity (individual images work, gallery blocks pending)
  - Support markdown gallery syntax (define format with web editor)
  - Render image galleries in read mode (MarkdownUI custom block)
  - Edit mode: insert gallery block template via toolbar
  - Display multiple images in grid layout with captions

**Live Preview / Unified Editor**
- [ ] Implement unified CodeMirror editor (see `2026-01-22-unified-codemirror-editor.md`)
  - Use single CM6 view for both read and edit modes
  - Read mode: `setReadOnly(true)` + block preview widgets + marker hiding
  - Edit mode: `setReadOnly(false)` + raw markdown with syntax highlighting
  - Fixes tap-to-caret bug (caret landing at wrong position)
  - Preserves scroll position across mode transitions

### 2) Phase 11.4 (Content Creation)

**Memories CRUD**
- [ ] Add memory
  - Modal sheet with path input and content textarea
  - Path validation (format: category/subcategory/memory-name)
  - Save to backend via MemoriesAPI
  - Refresh memories list on success

- [ ] Edit memory
  - Open existing memory in same modal
  - Pre-populate path and content
  - Update via PATCH endpoint
  - Handle conflicts if memory was externally edited

- [ ] Delete memory
  - Swipe action (iOS) / context menu (macOS)
  - Confirmation alert: "Delete memory?"
  - DELETE request to backend
  - Remove from local list optimistically

- [ ] List/Detail parity
  - Memories list view with hierarchical path display
  - Search/filter by path or content
  - Empty state: "No memories yet"
  - Detail view: display full content with edit/delete actions

### 3) Phase 11.5 (Full App Testing)

**Editing Workflow Tests**
- [ ] Notes: create, edit, save, rename, move, delete, pin, archive
- [ ] Files: upload, view status, rename, pin, delete, download
- [ ] Websites: save URL, view content, pin, archive, delete
- [ ] Chat: send messages, attach files, view streaming, rename conversation, delete
- [ ] Scratchpad: edit, auto-save, realtime sync across devices

**Creation/Deletion Flow Tests**
- [ ] Create new note → verify in list → edit → save → verify persistence
- [ ] Upload file → verify processing status → view content → delete
- [ ] Save website → verify loading state → view content → archive
- [ ] Create conversation → send message → verify SSE streaming → delete
- [ ] Add memory → verify in list → edit → delete

**Native UX Parity Validation**
- [ ] Compare all features against web version for capability parity
- [ ] Verify native behaviors: context menus, keyboard shortcuts, swipe actions
- [ ] Test multi-platform: iPhone, iPad, macOS
- [ ] Validate navigation patterns match platform conventions (NavigationStack, NavigationSplitView, tabs)

**Final Polish + Bug Fixes**
- [ ] Fix any crashes or critical bugs discovered during testing
- [ ] Smooth animations and transitions across all flows
- [ ] Consistent spacing, typography, and color usage
- [ ] Loading states and error handling polish
- [ ] Accessibility: VoiceOver labels, Dynamic Type support

### 4) Addendum: Codebase Parity Gaps

**Skills Management**
- [x] Skills settings parity in Settings (COMPLETE)

**SSE UI Event Coverage**
- [x] SSE UI event coverage beyond tokens/tool calls (COMPLETE)

**Scratchpad Implementation Detail**
- [x] Backed by special note title with realtime updates (COMPLETE)

### 5) Known Issues & Technical Debt

**Code Block Wrapping (MarkdownUI Limitation)**
- [ ] Track upstream MarkdownUI behavior for code block wrapping
- [ ] Investigate custom UITextView/NSTextView wrapper as workaround
- [ ] If needed: insert soft wrap opportunities for display-only rendering
- [ ] Fallback: Accept horizontal overflow until reliable solution available
- [ ] Document limitation in app docs or release notes

**Website Archive Section Scrolling**
- [ ] Keep Archive section visible with long lists (pending revisit)
- [ ] List should scroll within max height rather than pushing archive section off-screen
- [ ] Test with 50+ pinned websites to validate behavior

### 6) Future Work (Post-MVP, Not Blocking)

**Task System Migration (Phase 7.T1)**
- [ ] Replace legacy task dependency with in-app todo management (3-5 sessions estimated)
  - Design native task data model (title, notes, due, tags, project, area, status)
  - Build task list UI (today/upcoming/all/search views)
  - Implement task CRUD operations
  - Add backend API endpoints for task sync
  - Build one-time import from legacy task source
  - Migrate UI to use InAppTaskProvider instead of legacy provider

## Definition of Done (Final Validation)

Before considering SwiftUI app complete, validate:
- [ ] All capabilities available with native UX on Mac, iPad, iPhone
- [ ] Real-time sync working reliably across all content types
- [ ] Offline reading supported with smart caching (cached content accessible offline)
- [ ] App feels native (not like a web wrapper): context menus, keyboard shortcuts, native navigation
- [ ] Performance is smooth: 60fps animations, fast app launch, responsive UI
- [ ] Accessible via VoiceOver with proper labels and focus management
- [ ] Zero critical bugs (no crashes, data loss, or blocking issues)
- [ ] Ready for daily personal use as primary sideBar client

## Notes
- Keep file sizes within limits; prefer service-layer reuse.
- Live preview editing mode is explicitly deferred until read-mode styling is locked.
- Task system migration is future work (post-MVP).
