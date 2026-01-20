# iOS Refactor Plan (Comprehensive)

Date: 2026-01-20
Scope: /ios SwiftUI app
Source: IOS_CODE_REVIEW.md recommendations

## Guiding Principles
- Preserve behavior; refactor by extraction and consolidation.
- Service layer owns business logic; no logic moves into views.
- Soft deletes only.
- Maintain SSE update patterns and cache consistency.
- Keep files under limits (views/viewmodels/services/utilities).
- Prefer incremental PR-sized slices with tests per behavior change.

## Phase 0: Baseline & Guardrails
1) Inventory and baselines
   - Record current counts (LOC per file, tests, coverage).
   - Identify top 15 files to split and dependency graphs.
2) Tooling alignment
   - Add SwiftLint configuration and integrate into Xcode/CI.
   - Enable code coverage reporting in Xcode scheme/CI.
3) Safety net
   - Add missing doc comment coverage checks (docstrings target).
   - Confirm no debug artifacts in committed code.

## Phase 1: Security Fixes (High Priority)
1) CoreData file protection
   - Set NSPersistentStoreFileProtectionKey in PersistenceController.
2) Offline access window
   - Reduce SupabaseAuthAdapter offline window to 24–48h.
3) Clipboard auto-clear
   - Auto-clear copied tokens in SettingsView, ChatView, WebsitesView.
4) URLCache protection
   - Disable disk caching for sensitive endpoints or disable disk cache.
5) Certificate pinning (scoped)
   - Implement URLSessionDelegate pinning for critical endpoints.
   - Add configuration toggle for dev/test.
6) Tests
   - Add unit tests for offline access window behavior and cache policy.

## Phase 2: Error Handling & Logging
1) Eliminate empty catch blocks
   - SupabaseRealtimeAdapter: log, update sync status, retry policy.
2) Replace unsafe try?
   - CoreData cache, auth state store, cache client.
3) Centralize error mapping
   - Extend ErrorMapping for auth/network/decoding/unknown.
4) Tests
   - Add tests for ErrorMapping and real-time failure states.

## Phase 3: File Splits (Size Limits)
1) SidebarPanels.swift -> folderized views
2) ChatView.swift -> Chat/ module (container, list, row, input, header, tools)
3) ChatViewModel.swift -> ViewModels/Chat/* components
4) ContentView.swift, SettingsView.swift, FilesView.swift, NotesView.swift, FileViewerView.swift
5) SupabaseRealtimeAdapter.swift, CodeMirrorEditorView.swift
6) Add MARK sections in remaining large files
7) Tests
   - Update/extend view model tests to cover new components.

## Phase 4: DRY Consolidation (Utilities)
1) Utilities/String+Validation
2) Utilities/TaskManager (ManagedTask, PollingTask)
3) Utilities/LoadableState (LoadingState<T>, LoadableViewModel)
4) Utilities/CachedLoader
5) Utilities/StatusFilterable
6) Stores/CachedStore protocol
7) CacheClient invalidation helper
8) Refactor ViewModels/Stores to new helpers
9) Tests
   - Unit tests for each helper.

## Phase 5: Styling Consolidation
1) DesignTokens additions
   - Typography tokens
   - Semantic colors
2) PlatformTokens for conditional styling
3) Replace hardcoded padding/radii/colors/fonts
4) Create modifiers (BorderedModifier, ShadowModifier)
5) Tests/visual QA
   - Snapshot or manual verification for key screens.

Progress:
- Added Typography + semantic error colors, PlatformTokens, and border/shadow modifiers.
- Replaced numeric padding/radius/font usages with tokens across Views/Design components.

## Phase 6: Testing Expansion
1) ViewModels
   - NotesEditorViewModel, PlacesViewModel, NavigationState
2) Services
   - Streaming (ChatStreamClient/Parser/URLSession), APIs, realtime, upload, cache
3) Stores
   - ChatStore, NotesStore, WebsitesStore, IngestionStore, ScratchpadStore, TasksStore
4) Utilities
   - MarkdownFormatting/Editing/Rendering, DateParsing, ErrorMapping
5) Coverage targets
   - ViewModels 80%+, Services 80%+, Utilities 90%

## Phase 7: Documentation
1) Doc comments for all public ViewModels and Services
2) MARK sections for files >200 LOC
3) Create docs/IOS_ARCHITECTURE.md
4) Update README/ENVIRONMENT with iOS specifics

## Execution Strategy (Step-by-step)
- Work in small batches:
  1) Implement one category (e.g., security) + tests + lint/format.
  2) Validate build + unit tests for touched modules.
  3) Move to next category.
- Each batch must keep file sizes under limits.
- Prefer follow-up PRs when a refactor spans multiple modules.

## Acceptance Checklist
- Security issues resolved
- No empty catch blocks; try? only in justified cases
- Files under size limits
- DRY utilities in place and adopted
- Styling tokens widely used, hardcoded values removed
- Tests added per targets
- Docs updated
- Lint/typecheck/tests pass
