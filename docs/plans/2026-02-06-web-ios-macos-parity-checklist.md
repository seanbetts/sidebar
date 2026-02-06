# Web iOS/macOS Sidebar Parity Checklist (2026-02-06)

## Scope
- Left sidebar section naming parity
- Left sidebar section switch/hide behavior parity
- Subsection visibility parity (Pinned, Results, Archive) for Notes, Files, Websites

## Decisions
- Web section keys should match native naming: `files` and `chat` (instead of `workspace` and `history`).
- For Files/Websites, the Pinned subsection should be hidden when empty in non-search mode.
- For Files, search mode should not render a separate Pinned subsection.

## Checklist
- [x] Rename web sidebar section key `workspace` -> `files`
- [x] Rename web sidebar section key `history` -> `chat`
- [x] Keep backwards compatibility for persisted localStorage values (`workspace`/`history`)
- [x] Update keyboard section shortcuts to open `files`/`chat`
- [x] Update rail activation/open handlers to use `files`/`chat`
- [x] Files panel: hide Pinned section when empty
- [x] Files panel: hide Pinned section during search
- [x] Websites panel: hide Pinned section when empty
- [x] Notes panel: no change (already parity-aligned)
- [x] Add/update tests for sidebar-section persistence and legacy key migration

## Verification Targets
- Web: switching sections still lazy-loads data for Notes/Tasks/Websites/Files/Chat
- Web: existing users with old localStorage still land on equivalent section
- Web: Files non-search with zero pinned shows no Pinned block
- Web: Files search view shows only search results/categories (no Pinned block)
- Web: Websites non-search with zero pinned shows no Pinned block

## Follow-ups
- [x] Websites now hide the empty `Websites` block when only archived items exist.
- [x] Rename CSS classes containing `workspace` to `files` for consistency.
