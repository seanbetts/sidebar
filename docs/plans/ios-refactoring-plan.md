# iOS/macOS Code Review & Refactoring Plan

## Context

The codebase has grown to ~293 Swift files with accumulated technical debt that's making feature development feel like whack-a-mole. The core issues are:

1. **No size guardrails** -- SwiftLint's `file_length`, `type_body_length`, and `function_body_length` rules are all disabled. 48 files exceed 300 lines, with the worst at 2,200 lines.
2. **Doc comment gaps** -- Only 26% of public declarations have `///` comments. The pre-commit hook only checks ViewModels/ and Services/ for `public class|struct|enum|protocol` (not funcs/vars), so most gaps go uncaught.
3. **Large files are hard to reason about** -- When a ViewModel or Store is 600-2200 lines, it's easy to introduce bugs because the full context doesn't fit in your head.

**What's actually in good shape:** Only 3 `swiftlint:disable` comments, 0 empty catch blocks, 0 print statements, 1 force unwrap, 1 TODO. The codebase is clean at the micro level -- the debt is structural.

---

## Phase 1 -- Lint & Tooling Tightening

Re-enable SwiftLint size rules with thresholds that catch future growth while grandfathering existing files for now.

### 1.1 Re-enable SwiftLint size rules in `.swiftlint.yml`

```yaml
# Remove from disabled_rules: file_length, function_body_length, type_body_length
# Add thresholds:
file_length:
  warning: 500
  error: 800

type_body_length:
  warning: 400
  error: 600

function_body_length:
  warning: 80
  error: 120
```

Then add a `legacy_exceptions` section or per-file `swiftlint:disable` for the ~20 files currently over 500 lines, so the build still passes. The goal: **no new file can silently grow past 500 lines**.

### 1.2 Extend doc comment hook scope

Update `scripts/check_ios_doc_comments.py`:
- Add `Stores/` to the target directories (currently only ViewModels/ and Services/)
- Add `public func` and `public var` to the regex (currently only catches `public class|struct|enum|protocol`)
- Consider adding `App/` directory

### 1.3 Cleanup

- Delete `.swift.tmp` files (6 found scattered in project)
- Re-enable `todo` SwiftLint rule (only 1 TODO exists -- it's practically free)

---

## Phase 2 -- Split Oversized Files

Target files over 600 lines. These are the biggest sources of "can't reason about this" bugs.

### 2.1 Critical splits (files over 800 lines)

| File | Lines | Proposed split |
|------|-------|----------------|
| `NativeMarkdownEditorViewModel.swift` | 2,200 | Split into `+Formatting`, `+ListHandling`, `+Selection`, `+UndoRedo` extensions |
| `NotesView.swift` | 1,039 | Extract subviews into `NotesView+Components.swift` |
| `WebsitesStore.swift` | 940 | Split into `+Offline`, `+Realtime`, `+Helpers` (mirroring IngestionStore pattern) |
| `WebsitesView.swift` | 904 | Extract subviews and list components |
| `NativeMarkdownTextView.swift` | 817 | Split platform-specific code into `+iOS` / `+macOS` |
| `MarkdownImporter.swift` | 781 | Extract inline parsing into separate file |

### 2.2 Secondary splits (600-800 lines)

| File | Lines | Proposed split |
|------|-------|----------------|
| `WebsitesViewModel.swift` | 675 | Split into `+Public` / `+Private` (mirroring IngestionViewModel) |
| `MarkdownExporter.swift` | 667 | Extract block-level export logic |
| `FilesView.swift` | 654 | Extract subviews |
| `WebsitesPanel.swift` | 607 | Extract row views and list sections |
| `SupabaseRealtimeAdapter.swift` | 607 | Extract channel setup into `+Channels` |
| `NotesStore.swift` | 601 | Already has `+Offline` -- split out `+Helpers` too |
| `FilesPanel.swift` | 600 | Extract row views |

### 2.3 Organize loose Views

45 files sit directly in `Views/` root. Group them into subdirectories by feature:
- `Views/Files/` -- FilesView, FileViewerComponents, SpreadsheetViewer, YouTubePlayerView
- `Views/Websites/` -- WebsitesView, SiteHeaderBar
- `Views/Tasks/` -- TasksView, TasksViewComponents
- `Views/Settings/` -- SettingsSections
- `Views/Common/` -- ContentViewComponents, ImagePicker, etc.

---

## Phase 3 -- Doc Comments

### 3.1 Models (highest gap -- 449 public declarations, ~0% covered)

Add `///` doc comments to all public types and their stored properties in:
- `FileModels.swift` (93 public decls)
- `WebsiteModels.swift` (88)
- `TaskModels.swift` (83)
- `ChatModels.swift` (53)
- `SettingsModels.swift` (33)
- Remaining model files (~92 decls across 8 files)

For simple Codable structs/properties, brief single-line comments are fine:
```swift
/// A file that has been ingested and processed by the backend.
public struct IngestedFileMeta: Codable {
    /// Unique server-assigned identifier.
    public let id: String
    ...
}
```

### 3.2 Stores (45% covered -- fill gaps)

Focus on undocumented public methods in:
- `IngestionStore+Realtime.swift` (11 undocumented)
- `NotesStore+Offline.swift` (11 undocumented)

### 3.3 App layer (6% covered)

- `AppEnvironment.swift` (25 undocumented public properties)
- `ServiceContainer.swift` (22 undocumented)

### 3.4 sideBarShared (17% covered)

- `PendingShareStore.swift` (23 undocumented)
- `ExtensionEventStore.swift` (14 undocumented)

---

## Phase 4 -- Complexity Reduction

### 4.1 Address cyclomatic complexity suppressions

The 3 `swiftlint:disable cyclomatic_complexity` spots:
- `NativeMarkdownEditorViewModel.swift:127` -- `applyFormatting()` switch with 10 cases. Extract each case into a helper method.
- `MarkdownExporter.swift:371` -- `prefix(for:)` with heading/list cases. Convert to dictionary lookup.
- `MarkdownImporter.swift:343` -- Large inline parsing switch. Extract as part of Phase 2 split.

### 4.2 Reduce nesting in WebsitesViewModel

100 lines with 4+ indentation levels. Extract nested logic into named helper methods.

---

## Execution Order

Suggested order for tackling these:

1. **Phase 1** (Lint config) -- ~15 min. Sets guardrails so debt stops growing.
2. **Phase 2.1** (Critical file splits) -- The biggest wins for "can't reason about this" bugs. Start with `NativeMarkdownEditorViewModel` (2,200 lines).
3. **Phase 3.1** (Model doc comments) -- Mechanical but high-impact; these are the types everything else depends on.
4. **Phase 2.2-2.3** (Secondary splits + Views reorg) -- Continue structural cleanup.
5. **Phase 3.2-3.4** (Remaining doc comments) -- Fill gaps.
6. **Phase 4** (Complexity) -- Polish.

Each phase should be committed separately for easy review/revert.

---

## Verification

- `cd ios/sideBar && swiftlint --strict` passes after each phase
- Pre-commit hooks pass (including updated doc comment checker)
- `xcodebuild build` succeeds for both iOS and macOS targets
- Existing tests still pass
