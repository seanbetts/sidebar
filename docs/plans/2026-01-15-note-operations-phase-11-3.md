# Phase 11.3 Note Operations (iOS/macOS) Mini Plan

## Goal
Deliver native-feeling note operations (create/rename/move/delete/pin/archive) with the same API semantics and side effects as the web app.

## UX Principles
- Match Apple platform conventions: inline rename on list rows, swipe actions on iOS, context menus on macOS.
- Confirm destructive actions (delete, archive) with native alerts.
- Optimistic UI updates with rollback on failure (aligns with chat delete/rename behavior).
- Keep selection stable where possible; if the active note is deleted/archived, clear selection and exit edit mode.
- Centralize creation actions in the sidebar header (folder + plus icons) and use the note title bar menu for note-specific actions.

## Inventory (Current State)
- API: `NotesAPI` already supports create/rename/move/archive/pin/delete + folder ops.
- State: `NotesStore` + `NotesViewModel` manage tree + active note.
- UI patterns: Conversations list supports inline rename, swipe actions, and delete confirmation.
- Web behavior reference: `useEditorActions.ts` + `useFileActions.ts`.

## Implementation Plan
1) Entry points and UI action surface
   - Sidebar header buttons:
     - Folder icon: new folder flow.
     - Plus icon: new note flow.
   - Note title bar hamburger menu:
     - Primary note actions (rename, move, pin/unpin, archive/unarchive, delete).
   - iOS swipe actions:
     - Keep minimal for quick actions (e.g., rename + delete), since full actions live in the title bar menu.
   - macOS:
     - Context menu on note rows mirrors title bar actions.

2) Notes list UI actions (native patterns)
   - Add inline rename for note rows (TextField + focus) mirroring conversations list behavior.
   - Add swipe actions on iOS (Rename/Delete/Archive/Pin).
   - Add context menu on macOS with Rename/Move/Pin/Archive/Delete.
3) ViewModel actions (optimistic, rollback)
   - Add `renameNote`, `moveNote`, `archiveNote`, `pinNote`, `deleteNote` in `NotesViewModel`.
   - Apply optimistic updates to the tree and active note; rollback on API failure with toast.
4) Folder move support
   - Build folder options from tree (exclude Archive).
   - Present a native picker sheet for move targets.
5) Create note
   - Present a native dialog (new note title + optional folder).
   - Call `NotesAPI.createNote`, update tree, select new note.
6) Delete/Archive flows
   - Show confirmation alerts.
   - If active note is affected, clear selection and exit edit mode.
7) Parity checks with web app
   - Ensure `.md` suffix behavior on rename.
   - Dispatch cache invalidations in-store or refresh tree after updates.

## Success Criteria
- All note operations work on iOS and macOS with native interaction patterns.
- Tree and active note update immediately; errors rollback with a user-visible toast.
- Behavior matches web app semantics (rename/move/archive/pin/delete endpoints).

## Follow-ups (Optional)
- Folder operations in the sidebar (rename/move/delete folders).
- Drag-and-drop for pin ordering.
