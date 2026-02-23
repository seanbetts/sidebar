# Larger Text Audit (2026-02-23)

## Scope
- Settings panes
- Sidebar rows (chats, notes, tasks, websites, files)
- Task detail headers

## Changes applied
- Removed iOS Dynamic Type clamping from app-level text-size modifier.
- Added wrapping headroom for primary sidebar row titles in:
  - `ConversationsPanelComponents.swift`
  - `NotesPanelComponents.swift`
  - `TasksPanelRows.swift`
  - `WebsiteRows.swift`
  - `FilesIngestionRow.swift`
- Increased task detail header title line limits and replaced fixed-height headers with min-height headers in `TasksDetailView.swift`.
- Increased wrapping headroom for long settings values in:
  - `SettingsSections+System.swift` (masked provider key)
  - `MemoriesSettingsView.swift` (memory row title)

## QA matrix
- Added preview matrix at accessibility sizes in `Views/QA/LargerTextQAMatrix.swift`.
- Preview set includes:
  - Settings pane
  - Sidebar representative rows
  - Task header layout
  - System + App Large combinations at `.accessibility5` on iOS

## Follow-up manual checks
1. macOS: verify sidebar rows expand naturally without overlap at `System`, `Small`, `Medium`, `Large`.
2. iOS: verify task header wrapping in both compact and regular layouts.
3. iOS: verify settings forms still scroll cleanly with no clipped controls.
