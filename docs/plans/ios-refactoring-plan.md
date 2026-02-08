# iOS/macOS Code Review & Refactoring Plan

## Context

The codebase has grown to ~293 Swift files with accumulated technical debt that's making feature development feel like whack-a-mole. A deep review revealed issues at two levels:

**Surface-level (cosmetic):** Disabled lint rules, oversized files, doc comment gaps. The codebase is clean at the micro level (only 3 `swiftlint:disable` comments, 0 empty catch blocks, 0 print statements, 1 force unwrap, 1 TODO).

**Structural (architectural):** Concurrency safety holes, state management races, code duplication across stores, inconsistent error handling, excessive coupling, and SwiftUI performance anti-patterns. These are the root causes of "whack-a-mole" bugs.

---

## Phase 1 -- Lint & Tooling Tightening

Re-enable SwiftLint size rules with thresholds that catch future growth while grandfathering existing files.

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

Add per-file `swiftlint:disable` for the ~20 files currently over 500 lines, so the build still passes. Goal: **no new file can silently grow past 500 lines**.

### 1.2 Extend doc comment hook scope

Update `scripts/check_ios_doc_comments.py`:
- Add `Stores/` to the target directories (currently only ViewModels/ and Services/)
- Add `public func` and `public var` to the regex (currently only catches `public class|struct|enum|protocol`)
- Consider adding `App/` directory

### 1.3 Cleanup

- Delete `.swift.tmp` files (6 found scattered in project)
- Re-enable `todo` SwiftLint rule (only 1 TODO exists -- it's practically free)

---

## Phase 2 -- Concurrency Safety (CRITICAL)

These are real data race bugs that can cause crashes or data corruption in production. Fix before any structural refactoring.

### 2.1 APIClient auth refresh race

**File:** `sideBarShared/Network/APIClient.swift`
**Severity:** CRITICAL

`APIClient` is not actor-isolated but has mutable state (`lastAuthRefreshAttempt`, `authRefreshTask`) accessed from concurrent request paths. Two simultaneous 401 responses can trigger parallel token refreshes, corrupting auth state.

**Fix:** Convert `APIClient` to an actor, or isolate the auth refresh logic into a dedicated `AuthRefreshCoordinator` actor:
```swift
actor AuthRefreshCoordinator {
    private var refreshTask: Task<AuthToken, Error>?
    private var lastAttempt: Date?

    func refreshIfNeeded() async throws -> AuthToken {
        if let existing = refreshTask {
            return try await existing.value  // coalesce concurrent refreshes
        }
        let task = Task { ... }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
}
```

### 2.2 IngestionUploadManager dictionary mutations

**File:** `Services/Upload/IngestionUploadManager.swift`
**Severity:** HIGH

Dictionary mutations (`uploadProgress`, `activeUploads`) happen from both sync and async contexts on a background queue without synchronization. Multiple concurrent uploads can corrupt the dictionaries.

**Fix:** Either convert to an actor, or gate all mutations through a serial `DispatchQueue` consistently.

### 2.3 ConnectivityMonitor `@unchecked Sendable`

**File:** `App/ConnectivityMonitor.swift`
**Severity:** HIGH

Marked `@unchecked Sendable` but has mutable counters (`pendingRequestCount`, etc.) modified from async callbacks without synchronization.

**Fix:** Replace `@unchecked Sendable` with proper actor isolation. If performance is a concern, use `OSAllocatedUnfairLock` to protect mutable state.

### 2.4 NetworkMonitor `@unchecked Sendable`

**File:** `App/NetworkMonitor.swift`
**Severity:** HIGH

`@Published` property modified from NWPathMonitor's background queue callback, but `@Published` is not thread-safe.

**Fix:** Dispatch all `@Published` mutations to `@MainActor`:
```swift
pathMonitor.pathUpdateHandler = { [weak self] path in
    Task { @MainActor in
        self?.isConnected = path.status == .satisfied
    }
}
```

### 2.5 URLSessionChatStreamClient task race

**File:** `Services/Chat/URLSessionChatStreamClient.swift`
**Severity:** MEDIUM

`streamTask` property is read/written without actor isolation. A `cancel()` call racing with `startStream()` can miss the task.

**Fix:** Make the class `@MainActor` (it's already dispatching events there) or protect `streamTask` with an actor.

### 2.6 PendingShareStore concurrent file access

**File:** `sideBarShared/Utilities/PendingShareStore.swift`
**Severity:** MEDIUM

No actor isolation; FileManager and UserDefaults accessed concurrently from share extension and main app.

**Fix:** Convert to an actor. File I/O can remain synchronous inside the actor since share extension operations are infrequent.

### 2.7 CachedStore background refresh coordination

**File:** `Stores/CachedStore.swift`
**Severity:** MEDIUM

`backgroundRefresh()` launches a detached `Task {}` without tracking. Multiple triggers (app foreground, realtime event, manual refresh) can overlap, causing redundant API calls and potential state overwrites.

**Fix:** Track the refresh task and coalesce concurrent requests:
```swift
private var refreshTask: Task<Void, Never>?

func backgroundRefresh() {
    guard refreshTask == nil else { return }
    refreshTask = Task {
        defer { refreshTask = nil }
        await performRefresh()
    }
}
```

### 2.8 IngestionViewModel jobPollingTasks dictionary race

**File:** `ViewModels/IngestionViewModel+Private.swift`
**Severity:** HIGH

`jobPollingTasks[fileId]` is mutated inside a `Task` closure while `cancelJobPolling()` (called from within the same task at line 51) also modifies the dictionary. Collection mutation during enumeration can crash.

**Fix:** Ensure all dictionary mutations happen on `@MainActor` and avoid modifying the dictionary from within a task stored in it. Extract the cancel-and-remove into a separate method that runs after the task body completes.

### 2.9 SupabaseRealtimeAdapter channel mutation races

**File:** `Services/Realtime/SupabaseRealtimeAdapter.swift`
**Severity:** MEDIUM

`stop()` sets channel references to nil while `start()` may be adding subscriptions concurrently. Between `removeChannel()` and assigning the new channel, subscription references can be lost, leaking the old channel.

**Fix:** Add a `isTransitioning` guard or serialize start/stop through a single async method that awaits completion of any in-progress operation.

### 2.10 Task lifecycle management

**Severity:** MEDIUM

Multiple ViewModels store `Task` dictionaries (`ChatViewModel.attachmentPollTasks`, `IngestionViewModel.jobPollingTasks`) but do not cancel running tasks on deinit. While `[weak self]` prevents crashes, tasks continue running and consuming resources after the ViewModel is deallocated.

**Fix:** Add `deinit` (or a `cleanup()` method called from the owning View's `.onDisappear`) that cancels all stored tasks. Consider adopting the existing `PollingTask` pattern uniformly.

---

## Phase 3 -- State Management Fixes

### 3.1 Incomplete auth signout reset

**File:** `App/AppEnvironment+Auth.swift`
**Severity:** HIGH

On signout, `ChatViewModel` and `TasksViewModel` are NOT reset. `OfflineStore` is not cleared. This means stale data from user A can leak into user B's session.

**Fix:** Audit every ViewModel and Store for a `reset()` method. Call all of them in the signout handler. Add a unit test that verifies signout clears all observable state.

### 3.2 Store → ViewModel state duplication

**Severity:** MEDIUM (maintainability)

ViewModels subscribe to Store `@Published` properties via Combine and copy values into their own `@Published` properties. This creates dual sources of truth and opportunities for state divergence.

**Worst offender:** `TasksViewModel` duplicates 8 `@Published` properties from `TasksStore` via Combine sinks.

**Pattern:**
```swift
// Current: duplicated state
class TasksViewModel: ObservableObject {
    @Published var tasks: [TaskItem] = []  // copied from store
    init(store: TasksStore) {
        store.$tasks.sink { [weak self] in self?.tasks = $0 }.store(in: &cancellables)
    }
}

// Better: Views observe store directly for read-only data, ViewModel handles only UI logic
```

**Fix:** For each ViewModel, evaluate which `@Published` properties are genuine UI-only state vs. copies of Store data. For copies, have the View observe the Store directly (or use a computed property that reads from the store).

### 3.3 Adopt `LoadableViewModel` base class

**File:** `Utilities/LoadableState.swift`

A `LoadableViewModel` base class already exists but is **not used by any ViewModel**. It handles the common `loading`/`loaded`/`error` state machine.

**Fix:** Adopt `LoadableViewModel` in ViewModels that manually implement loading states (most of them). This eliminates ~20-30 lines of boilerplate per ViewModel.

### 3.4 AppEnvironment `@Published` sprawl

**File:** `App/AppEnvironment.swift`

11+ `@Published` properties cause cascading SwiftUI updates. `isAuthenticated` is a stored property that must be manually kept in sync with `authState`.

**Fix:**
- Make `isAuthenticated` a computed property derived from `authState`
- Group related properties into sub-objects (e.g., `AuthState`, `NavigationState`) to reduce observation breadth
- Consider `@Observable` migration (iOS 17+) for finer-grained observation

### 3.5 Navigation state centralization

Navigation state is scattered: some in `AppEnvironment`, some in `NavigationCoordinator`, some as local `@State` in Views, and some as `@Published` in ViewModels.

**Fix:** Audit all navigation-related state and consolidate into `NavigationCoordinator`. Use `NavigationPath` (iOS 16+) for programmatic navigation.

### 3.6 NotesStore archived tree refresh infinite wait

**File:** `Stores/NotesStore.swift`
**Severity:** MEDIUM

`waitForArchivedTreeRefresh()` polls `isRefreshingArchivedTree` with `Task.sleep(50ms)` in a `while` loop with **no timeout**. If the preceding refresh hangs (slow network, server error), all subsequent callers block indefinitely.

**Fix:** Add a timeout (e.g., 10 seconds) and fall back to returning stale data:
```swift
private func waitForArchivedTreeRefresh() async {
    let deadline = Date().addingTimeInterval(10)
    while isRefreshingArchivedTree, Date() < deadline {
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
}
```

### 3.7 Realtime events racing with conversation load

**File:** `ViewModels/Chat/ChatViewModel+Streaming.swift`
**Severity:** MEDIUM

`reconcileMessages()` appends the in-flight streaming message to the server response. If `ChatStore.loadConversation()` refreshes the message list while streaming is active, the streaming message can be duplicated or orphaned depending on timing.

**Fix:** Gate reconciliation on a `isReconciling` flag, or use the streaming message's ID to deduplicate before appending.

---

## Phase 4 -- Code Deduplication

### 4.1 Store load/cache/offline pattern

Four stores (`WebsitesStore`, `NotesStore`, `IngestionStore`, `TasksStore`) independently implement the same ~60-line pattern:
1. Check cache → return if fresh
2. Fetch from API
3. Save to cache
4. Handle offline fallback

**Fix:** Extract into a generic method on `CachedStoreBase<T>`:
```swift
func loadWithCache(
    cacheKey: String,
    fetch: () async throws -> [T],
    transform: ([T]) -> [T] = { $0 }
) async throws -> [T]
```

### 4.2 Offline enqueue consolidation

Each store has its own `enqueueOffline(operation:)` implementation with identical JSON encoding and WriteQueue insertion logic.

**Fix:** Add a generic `enqueueOfflineOperation<P: Encodable>(type:payload:)` method on `CachedStoreBase`.

### 4.3 API query building

URL query parameter construction (pagination, filtering, sorting) is duplicated across store fetch methods.

**Fix:** Create a `QueryBuilder` utility or extend `APIClient` with typed query helpers.

### 4.4 Archived item retention logic

Logic for retaining recently-archived items in the UI (grace period before removal) is duplicated across stores.

**Fix:** Extract into a shared `ArchivedRetentionPolicy` that stores can reference.

---

## Phase 5 -- Error Handling Consistency

### 5.1 WriteQueue silent failures

**File:** `Services/Offline/WriteQueue.swift`

Returns empty arrays on database errors instead of throwing. Callers have no way to know data was lost.

**Fix:** Make WriteQueue methods throwing. Update callers to handle errors (at minimum, log them).

### 5.2 Fire-and-forget Tasks

Multiple `Task { }` blocks throughout the codebase (especially in store refresh paths) have no error handling. If the task throws, the error vanishes silently.

**Pattern to fix:**
```swift
// Before:
Task { await store.refresh() }  // errors silently swallowed

// After:
Task {
    do {
        await store.refresh()
    } catch {
        logger.error("Background refresh failed: \(error)")
        // optionally surface to UI
    }
}
```

**Fix:** Audit all `Task { }` blocks. Add error handling or, where appropriate, use a shared `backgroundTask(_ work:)` helper that logs errors.

### 5.3 `try?` audit

Multiple `try?` patterns silently swallow errors in contexts where failures should at minimum be logged:
- Cache writes: data silently not persisted
- Background refresh: user sees stale data with no indication
- Offline enqueue: operations silently lost

**Fix:** Replace `try?` with `do/catch` where the failure matters. Keep `try?` only where the fallback behavior is intentional and documented.

### 5.4 Circuit breaker for repeated failures

Stores retry API calls on every app-foreground event, even if the server is unreachable. This wastes battery and network bandwidth.

**Fix:** Add exponential backoff to `CachedStoreBase.backgroundRefresh()`. After N consecutive failures, wait progressively longer before retrying. Reset on success or connectivity change.

### 5.5 401 retry limited to GET requests

**File:** `sideBarShared/Network/APIClient.swift` (line 244)

`shouldAttemptAuthRefresh(for:)` only allows retry for GET requests. A POST/PUT/DELETE that hits an expired token fails permanently -- the user must manually retry.

**Fix:** Allow retry for idempotent mutations (PUT, DELETE) at minimum. For POST, consider replaying if the request body is still available. Document which operations are safe to retry.

---

## Phase 6 -- SwiftUI Performance

### 6.1 Remove `.onChange` array creation (CRITICAL)

**File:** `Views/SidebarPanels/FilesPanel.swift:107`

```swift
.onChange(of: viewModel.items.map { $0.file.id })  // creates array EVERY evaluation
```

SwiftUI calls the `of:` expression on every view evaluation to check for changes. `.map { }` creates a new array each time, which is O(n) work on every render.

**Fix:** Track a lightweight change token instead:
```swift
.onChange(of: viewModel.itemsVersion) { ... }  // simple Int incremented on changes
```

Or use `.onChange(of: viewModel.items.count)` if the concern is only structural changes.

### 6.2 Cache expensive computations in view body

**Files:** `WebsitesPanel.swift`, `FilesPanel.swift`, `TasksPanel.swift`

Sorts, filters, and grouping operations are computed inside the view `body`. These re-run on every render.

**Fix:** Move expensive computations into the ViewModel as cached `@Published` properties that only update when source data changes:
```swift
// In ViewModel:
@Published private(set) var sortedItems: [Item] = []

private func updateSortedItems() {
    sortedItems = items.sorted(by: currentSortOrder)
}
```

### 6.3 Fix `.onChange` feedback loops

**File:** `Views/SidebarPanels/TasksPanel.swift`

`.onChange(of: searchQuery)` writes to `viewModel.searchQuery`, which triggers another `.onChange`. SwiftUI may coalesce these, but the pattern is fragile and wasteful.

**Fix:** Use a single source of truth. Either bind directly to `viewModel.searchQuery` or use `.task(id: searchQuery)` with debouncing.

### 6.4 Reduce observation breadth

Views that `@ObservedObject` an entire ViewModel re-render when ANY `@Published` property changes, even unrelated ones.

**Fix for high-frequency views (panels, lists):**
- Split ViewModels into focused sub-objects where possible
- Consider `@Observable` (iOS 17+) for automatic fine-grained tracking
- Extract expensive subviews into separate structs that only observe what they need

### 6.5 GeometryReader in scroll content

GeometryReader inside `ScrollView` / `LazyVStack` causes layout thrashing because it requests a re-layout on every scroll frame.

**Fix:** Move GeometryReader outside the scroll content, or use `.onGeometryChange` (iOS 18+) / preference keys to propagate sizes without re-layout.

### 6.6 `ForEach(Array(enumerated()))` creates temporary arrays

**Files:** `WebsitesPanel.swift` (lines 223, 234), `FilesPanel.swift` (line 229)

```swift
ForEach(Array(pinnedItemsSorted.enumerated()), id: \.element.id) { index, item in
```

`Array(enumerated())` allocates a new array on every render. Since the items already have stable `.id` properties, the enumeration index is unnecessary overhead.

**Fix:** Use `ForEach(pinnedItemsSorted)` with stable IDs. If the index is needed for drag reordering, cache the enumerated array in the ViewModel.

### 6.7 ChatMessageListView cascading `.onChange` modifiers

**File:** `Views/Chat/ChatMessageListView.swift` (lines 50-89)

Four `.onChange` modifiers fire in sequence on the same view (`selectedConversationId`, `messages.count`, `messages.last?.content`, `bottomInset`), each triggering scroll logic. The execution order is non-deterministic and can cause missed or doubled scroll-to-bottom calls.

**Fix:** Consolidate into a single `.onChange` on a lightweight state token, or use `.task(id:)` to react to the primary change (`selectedConversationId`) and derive scroll behavior from that.

### 6.8 AsyncImage without caching for markdown content

**File:** `Views/SideBarMarkdown+MarkdownUI.swift` (line 9)

`AsyncImage(url:)` has no caching layer. Images in markdown content are re-fetched on every view appearance.

**Fix:** Use `FaviconImageView`'s existing `.task(id:)` + cache pattern, or add a shared `ImageCache` that `AsyncImage` can read from.

---

## Phase 7 -- Coupling Reduction

### 7.1 ChatViewModel dependency explosion

`ChatViewModel` has 13+ injected dependencies in its `init`. This makes it hard to test, hard to reason about, and tightly coupled to the entire app.

**Fix:** Group related dependencies into coordinator objects:
- `ChatNetworkCoordinator` (APIClient, StreamClient, ConnectivityMonitor)
- `ChatStorageCoordinator` (NotesStore, WebsitesStore, IngestionStore)
- `ChatUIState` (navigation, selection, formatting state)

### 7.2 Cross-feature store coupling

`ChatViewModel` directly references `NotesStore`, `WebsitesStore`, and `IngestionStore` for context attachment. ViewModels reference other ViewModels (`NotesEditorViewModel` → `NotesViewModel`).

**Fix:** Introduce a `ContextProvider` protocol that abstracts the "get attachable items" query. Each store conforms independently. ChatViewModel depends on `[ContextProvider]` instead of concrete stores.

### 7.3 Inconsistent MVVM boundaries

`ScratchpadPopoverView` observes both its ViewModel AND a Store directly, bypassing the ViewModel layer.

**Fix:** Audit Views that directly `@ObservedObject` a Store. Either route through the ViewModel or document the pattern as intentional for simple read-only cases.

---

## Phase 8 -- Split Oversized Files

(Moved from original Phase 2 -- still important but less urgent than concurrency/state fixes)

### 8.1 Critical splits (files over 800 lines)

| File | Lines | Proposed split |
|------|-------|----------------|
| `NativeMarkdownEditorViewModel.swift` | 2,200 | Split into `+Formatting`, `+ListHandling`, `+Selection`, `+UndoRedo` extensions |
| `NotesView.swift` | 1,039 | Extract subviews into `NotesView+Components.swift` |
| `WebsitesStore.swift` | 940 | Split into `+Offline`, `+Realtime`, `+Helpers` (mirroring IngestionStore pattern) |
| `WebsitesView.swift` | 904 | Extract subviews and list components |
| `NativeMarkdownTextView.swift` | 817 | Split platform-specific code into `+iOS` / `+macOS` |
| `MarkdownImporter.swift` | 781 | Extract inline parsing into separate file |

### 8.2 Secondary splits (600-800 lines)

| File | Lines | Proposed split |
|------|-------|----------------|
| `WebsitesViewModel.swift` | 675 | Split into `+Public` / `+Private` |
| `MarkdownExporter.swift` | 667 | Extract block-level export logic |
| `FilesView.swift` | 654 | Extract subviews |
| `WebsitesPanel.swift` | 607 | Extract row views and list sections |
| `SupabaseRealtimeAdapter.swift` | 607 | Extract channel setup into `+Channels` |
| `NotesStore.swift` | 601 | Already has `+Offline` -- split out `+Helpers` |
| `FilesPanel.swift` | 600 | Extract row views |

### 8.3 Organize loose Views

45 files sit directly in `Views/` root. Group by feature:
- `Views/Files/` -- FilesView, FileViewerComponents, SpreadsheetViewer, YouTubePlayerView
- `Views/Websites/` -- WebsitesView, SiteHeaderBar
- `Views/Tasks/` -- TasksView, TasksViewComponents
- `Views/Settings/` -- SettingsSections
- `Views/Common/` -- ContentViewComponents, ImagePicker, etc.

---

## Phase 9 -- Doc Comments

### 9.1 Models (highest gap -- 449 public declarations, ~0% covered)

Add `///` doc comments to all public types and stored properties in:
- `FileModels.swift` (93 public decls)
- `WebsiteModels.swift` (88)
- `TaskModels.swift` (83)
- `ChatModels.swift` (53)
- `SettingsModels.swift` (33)
- Remaining model files (~92 decls across 8 files)

### 9.2 Stores (45% covered -- fill gaps)

Focus on undocumented public methods in:
- `IngestionStore+Realtime.swift` (11 undocumented)
- `NotesStore+Offline.swift` (11 undocumented)

### 9.3 App layer (6% covered)

- `AppEnvironment.swift` (25 undocumented public properties)
- `ServiceContainer.swift` (22 undocumented)

### 9.4 sideBarShared (17% covered)

- `PendingShareStore.swift` (23 undocumented)
- `ExtensionEventStore.swift` (14 undocumented)

---

## Phase 10 -- Test Coverage

### 10.1 Untested ViewModels

- `TasksViewModel` -- no tests at all (note: `TasksStore` has tests, but the ViewModel layer that handles optimistic updates and store synchronization does not). This is a significant gap.
- `NativeMarkdownEditorViewModel` -- no tests for the 2,200-line file. At minimum, test `applyFormatting()` cases and undo/redo.

**Note:** The dead code/test coverage investigation was interrupted before completing a full audit. Before starting this phase, run a quick scan to identify any other untested ViewModels or Stores.

### 10.2 Concurrency regression tests

After fixing Phase 2 concurrency issues, add tests that exercise concurrent access:
- Concurrent 401 responses triggering auth refresh
- Parallel upload progress updates
- Simultaneous foreground refresh + realtime event

### 10.3 Auth signout integration test

After Phase 3.1, add a test that signs out and verifies ALL observable state is cleared (no leakage across sessions).

---

## Phase 11 -- Complexity Reduction

### 11.1 Address cyclomatic complexity suppressions

The 3 `swiftlint:disable cyclomatic_complexity` spots:
- `NativeMarkdownEditorViewModel.swift:127` -- `applyFormatting()` switch with 10 cases. Extract each case into a helper method.
- `MarkdownExporter.swift:371` -- `prefix(for:)` with heading/list cases. Convert to dictionary lookup.
- `MarkdownImporter.swift:343` -- Large inline parsing switch. Extract as part of Phase 8 split.

### 11.2 Reduce nesting in WebsitesViewModel

100 lines with 4+ indentation levels. Extract nested logic into named helper methods.

---

## Execution Order

Prioritized by **risk of production bugs** (not cosmetic impact):

1. **Phase 1** (Lint config) -- Sets guardrails so debt stops growing. Quick win.
2. **Phase 2** (Concurrency safety) -- **Start here for bug prevention.** The APIClient auth race (2.1) and IngestionUploadManager (2.2) are the highest-risk items in the entire codebase.
3. **Phase 3.1** (Auth signout reset) -- Data leakage between user sessions is a correctness and privacy issue.
4. **Phase 5.1** (WriteQueue) -- Silent data loss in offline mode.
5. **Phase 6.1-6.2** (SwiftUI performance hot spots) -- The `.onChange` array creation and in-body sorts are causing real jank.
6. **Phase 3.2-3.3** (State deduplication, LoadableViewModel) -- Reduces future bug surface.
7. **Phase 4** (Code deduplication) -- Reduces maintenance burden.
8. **Phase 7** (Coupling reduction) -- Improves testability.
9. **Phase 8** (File splits) -- Structural cleanup, easier reasoning.
10. **Phase 9** (Doc comments) -- Mechanical, can be done incrementally.
11. **Phase 10** (Tests) -- Can be interleaved with other phases.
12. **Phase 11** (Complexity) -- Polish.

Each phase should be committed separately for easy review/revert.

---

## Verification

After each phase:
- `cd ios/sideBar && swiftlint --strict` passes
- Pre-commit hooks pass (including doc comment checker)
- `xcodebuild build` succeeds for both iOS and macOS targets
- Existing tests still pass
- For Phase 2 (concurrency): manual testing of auth refresh, upload, and offline flows
- For Phase 3 (state): manual testing of signout → signin with different account
- For Phase 6 (performance): profile with Instruments Time Profiler on list views with 100+ items
