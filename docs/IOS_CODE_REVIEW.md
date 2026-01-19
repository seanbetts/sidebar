# iOS Codebase Review

**Date:** January 2026
**Scope:** /ios directory - SwiftUI universal app
**Standards Reference:** QUALITY_ENFORCEMENT.md, TESTING.md

---

## Executive Summary

The iOS codebase is a well-organized SwiftUI MVVM application with approximately **24,166 lines of code** across **145 Swift files**. While the architecture is sound and follows modern Swift concurrency patterns, there are significant opportunities for improvement in **testing coverage**, **error handling**, **documentation**, and **file size management**.

### Key Findings

| Area | Rating | Priority |
|------|--------|----------|
| Architecture | ✅ Good | - |
| Code Organization | ⚠️ Needs Work | Medium |
| Testing Coverage | ❌ Critical Gaps | High |
| Error Handling | ❌ Critical Issues | High |
| Documentation | ❌ Minimal | Medium |
| File Sizes | ❌ Violations | High |
| DRY Violations | ❌ Significant | High |
| Styling Consistency | ⚠️ Inconsistent | Medium |
| Security | ⚠️ Good Foundation, 5 Issues | High |

---

## 1. Architecture Overview

### Current Architecture: MVVM + Manual Dependency Injection

The codebase follows a clean MVVM architecture with:

- **Views** (37 files, 13,408 LOC) - SwiftUI views
- **ViewModels** (12 files, 3,343 LOC) - ObservableObject classes
- **Services** (31 files, 3,044 LOC) - Network, auth, cache, realtime
- **Stores** (6 files, 1,102 LOC) - Data persistence layer
- **Models** (13 files, 641 LOC) - Codable data structures

**Strengths:**
- Clear separation of concerns
- Protocol-based service abstractions
- Modern async/await patterns
- Combine framework for reactive updates
- Multi-platform support (iOS + macOS)

**Weaknesses:**
- No formal DI framework (manual dependency passing)
- 12+ dependencies in some ViewModels
- Tight coupling between some stores and ViewModels

---

## 2. File Size Violations

Per QUALITY_ENFORCEMENT.md, file size limits are:
- **Services**: 400 LOC soft, 600 LOC hard
- **Utilities**: 200 LOC soft, 300 LOC hard
- **Views**: 400 LOC soft, 600 LOC hard (extrapolated)
- **ViewModels**: 400 LOC soft, 600 LOC hard (extrapolated)

### Files Exceeding Hard Limits (11 files)

| File | LOC | Limit | Violation |
|------|-----|-------|-----------|
| SidebarPanels.swift | 2,587 | 600 | **4.3x over** |
| ChatView.swift | 1,479 | 600 | **2.5x over** |
| ChatViewModel.swift | 1,255 | 600 | **2.1x over** |
| ContentView.swift | 935 | 600 | **1.6x over** |
| IngestionViewModel.swift | 760 | 600 | **1.3x over** |
| FilesView.swift | 736 | 600 | 1.2x over |
| SettingsView.swift | 706 | 600 | 1.2x over |
| FileViewerView.swift | 702 | 600 | 1.2x over |
| NotesView.swift | 574 | 600 | Approaching limit |
| SupabaseRealtimeAdapter.swift | 528 | 400 | **1.3x over** |
| CodeMirrorEditorView.swift | 529 | 400 | **1.3x over** |

### Recommended File Splits

#### SidebarPanels.swift (2,587 → ~8 files)
```
SidebarPanels/
├── PanelComponents.swift         (~200 LOC) - Shared headers, placeholders
├── ConversationsPanelView.swift  (~250 LOC) - Chat panel
├── FilesPanel.swift              (~200 LOC) - Files panel
├── NotesPanel.swift              (~180 LOC) - Notes panel
├── WebsitesPanel.swift           (~150 LOC) - Websites panel
├── InfoPanels.swift              (~200 LOC) - Memory, Weather, Places, Scratchpad
└── TasksPanel.swift              (~150 LOC) - Tasks panel
```

#### ChatView.swift (1,479 → ~7 files)
```
Chat/
├── ChatView.swift                (~200 LOC) - Main container
├── ChatMessageListView.swift     (~200 LOC) - Message list with pagination
├── ChatMessageRow.swift          (~150 LOC) - Individual message rendering
├── ChatInputView.swift           (~150 LOC) - Input bar coordinator
├── ChatInputUIKit.swift          (~200 LOC) - iOS text input
├── ChatInputAppKit.swift         (~200 LOC) - macOS text input
├── ChatHeaderView.swift          (~120 LOC) - Header with tools/prompts
└── ChatToolComponents.swift      (~150 LOC) - Tool call rendering
```

#### ChatViewModel.swift (1,255 → ~6 files)
```
ViewModels/Chat/
├── ChatViewModel.swift           (~300 LOC) - Core ViewModel, state
├── ChatStreamEventHandler.swift  (~250 LOC) - Stream event processing
├── ChatAttachmentManager.swift   (~200 LOC) - Attachment lifecycle
├── ChatConversationManager.swift (~180 LOC) - Conversation operations
├── ChatMessageProcessor.swift    (~200 LOC) - Message handling
└── ConversationGrouping.swift    (~100 LOC) - Date grouping logic
```

---

## 3. Testing Gaps

Per TESTING.md, coverage targets are:
- **ViewModels**: 80%+ (state management critical)
- **Services**: 80%+ (business logic)
- **Utilities**: 90%+ (pure functions)

### Current Test Coverage

| Component | Files | Has Tests | Coverage |
|-----------|-------|-----------|----------|
| ViewModels | 12 | 9 (75%) | Partial |
| Services | 31 | 5 (16%) | **Critical Gap** |
| Stores | 6 | 0 (0%) | **Critical Gap** |
| Utilities | 19 | 3 (16%) | **Critical Gap** |

### Critical Testing Gaps

#### Untested ViewModels (High Priority)
1. **NotesEditorViewModel** (352 LOC) - Complex autosave, markdown formatting, conflict resolution
2. **PlacesViewModel** (38 LOC) - Has TODO for rework
3. **NavigationState** - State management

#### Untested Services (High Priority)
- **Chat Streaming**: ChatStreamClient, ChatStreamParser, URLSessionChatStreamClient
- **Network APIs**: 12 API files (ChatAPI, FilesAPI, NotesAPI, etc.)
- **Realtime**: SupabaseRealtimeAdapter, RealtimeMappers
- **Upload**: IngestionUploadManager
- **Cache**: CoreDataCacheClient, CachePolicy

#### Untested Stores (High Priority)
- ChatStore (250 LOC) - Conversation caching, deduplication
- NotesStore - File tree management
- WebsitesStore - Website list caching
- IngestionStore - File upload tracking
- ScratchpadStore, TasksStore

#### Untested Utilities (Medium Priority)
- MarkdownFormatting, MarkdownEditing, MarkdownRendering
- DateParsing, ErrorMapping
- FileNameFormatting, FileTreeSignature

### Recommended Testing Additions

**Phase 1 - Critical (Week 1-2)**
```
sideBarTests/
├── NotesEditorViewModelTests.swift    # Autosave, formatting, conflicts
├── ChatStreamParserTests.swift        # SSE parsing edge cases
├── ChatStoreTests.swift               # Cache coordination
└── NotesStoreTests.swift              # File tree management
```

**Phase 2 - High Priority (Week 3-4)**
```
sideBarTests/
├── APITests/
│   ├── ChatAPITests.swift
│   ├── FilesAPITests.swift
│   └── NotesAPITests.swift
├── IngestionUploadManagerTests.swift
└── SupabaseRealtimeAdapterTests.swift
```

**Phase 3 - Utilities (Week 5)**
```
sideBarTests/
├── MarkdownFormattingTests.swift
├── MarkdownEditingTests.swift
├── DateParsingTests.swift
└── ErrorMappingTests.swift
```

---

## 4. Error Handling Issues

### Critical: Silent Error Suppression

#### SupabaseRealtimeAdapter.swift - 13+ Empty Catch Blocks

**Severity: CRITICAL**

Location: `/ios/sideBar/sideBar/Services/Realtime/SupabaseRealtimeAdapter.swift`

```swift
// Lines 149-152, 199-202, 249-252, 295-298...
private func subscribeToNotes(userId: String) async {
    do {
        try await channel.subscribeWithError()
    } catch {
        // EMPTY - Real-time sync fails silently
    }
}
```

**Impact:** Users see stale data without any indication that real-time sync failed.

**Recommendation:**
```swift
private func subscribeToNotes(userId: String) async {
    do {
        try await channel.subscribeWithError()
    } catch {
        logger.error("Notes subscription failed: \(error.localizedDescription)")
        syncStatus = .failed(error)
        // Consider retry with exponential backoff
    }
}
```

#### IngestionUploadManager.swift - Silent Write Failure

**Severity: HIGH**

```swift
// Line 124 - Silent chunk write failure
try? handle.write(contentsOf: chunk)  // File upload corrupted if this fails
```

#### JavaScript Bridge Errors

**Severity: MEDIUM**

Files: YouTubePlayerView.swift, CodeMirrorEditorView.swift
```javascript
} catch (e) {}  // Bridge errors silently ignored
```

### Inconsistent Error Mapping

- `ErrorMapping.swift` only handles `APIClientError`
- ViewModels use `error.localizedDescription` directly (not user-friendly)
- No centralized error display pattern

**Recommendation:** Extend ErrorMapping to handle all error types:
```swift
public enum ErrorMapping {
    public static func message(for error: Error, operation: String? = nil) -> String {
        let base = mapError(error)
        if let op = operation {
            return "Failed to \(op): \(base)"
        }
        return base
    }

    private static func mapError(_ error: Error) -> String {
        switch error {
        case let apiError as APIClientError:
            return mapAPIError(apiError)
        case let authError as AuthAdapterError:
            return mapAuthError(authError)
        case let keychainError as KeychainError:
            return mapKeychainError(keychainError)
        default:
            return error.localizedDescription
        }
    }
}
```

### try? Overuse

The codebase uses `try?` extensively, masking errors that should be logged:

- CoreDataCacheClient.swift - Multiple `try?` for cache operations
- SupabaseAuthAdapter.swift - `try? stateStore.clear()`
- CacheClient.swift - `try? decoder.decode(...)`, `try? encoder.encode(...)`

**Recommendation:** Replace `try?` with `do/catch` blocks that log failures:
```swift
do {
    try context.save()
} catch {
    logger.error("Cache save failed: \(error)")
    // Continue execution if appropriate
}
```

---

## 5. Documentation Gaps

### Current State

| Documentation Type | Count | Rating |
|--------------------|-------|--------|
| Doc comments (///) | 2 | **Critical** |
| MARK sections | 0 | **Critical** |
| Inline comments | ~30 | Poor |
| TODO comments | 19 | Moderate |
| README.md | 4 paragraphs | Minimal |
| ENVIRONMENT.md | 10 lines | Basic |

### Critical Documentation Gaps

1. **Zero doc comments on public APIs** - 100+ public functions undocumented
2. **No MARK sections** - Files over 500 LOC have no organization
3. **No architecture documentation** - MVVM patterns not explained
4. **Complex algorithms undocumented** - Stream parsing, message reconciliation

### Recommended Documentation

#### Add Doc Comments to All ViewModels

```swift
/// Manages chat conversation state, message streaming, and attachments.
///
/// This ViewModel coordinates between the ChatStore, ChatStreamClient, and
/// various APIs to provide real-time chat functionality with file attachments.
///
/// ## Usage
/// ```swift
/// let viewModel = ChatViewModel(...)
/// await viewModel.loadConversations()
/// await viewModel.sendMessage(text: "Hello")
/// ```
///
/// ## Threading
/// All methods must be called from the main actor. The ViewModel publishes
/// state changes that trigger UI updates.
@MainActor
public final class ChatViewModel: ObservableObject {
    // ...
}
```

#### Add MARK Sections to Large Files

```swift
// MARK: - Initialization
// MARK: - Public API - Conversations
// MARK: - Public API - Messages
// MARK: - Public API - Attachments
// MARK: - Private - Stream Handling
// MARK: - Private - Message Processing
// MARK: - ChatStreamEventHandler
```

#### Create Architecture Documentation

Create `docs/IOS_ARCHITECTURE.md`:
- MVVM pattern explanation
- Store vs ViewModel distinction
- Cache invalidation strategy
- Service layer responsibilities
- Async/await patterns used

---

## 6. Code Quality Recommendations

### High Priority

1. **Add SwiftLint** - Enforce coding standards
   ```yaml
   # .swiftlint.yml
   line_length:
     warning: 120
     error: 150
   file_length:
     warning: 400
     error: 600
   type_body_length:
     warning: 300
     error: 500
   ```

2. **Add Code Coverage Reporting**
   - Enable code coverage in Xcode scheme
   - Add coverage threshold enforcement
   - Integrate with CI/CD

3. **Fix Silent Errors** - Add logging to all empty catch blocks

4. **Split Large Files** - Start with SidebarPanels.swift and ChatView.swift

### Medium Priority

5. **Improve Error Messages** - Use ErrorMapping consistently across ViewModels

6. **Add Doc Comments** - Document all public APIs

7. **Add MARK Sections** - Organize files over 200 LOC

8. **Reduce ViewModel Dependencies** - Extract managers for specific concerns

### Low Priority

9. **Create Shared Mocks** - Reduce test code duplication

10. **Add UI Tests** - Current UI tests are placeholder only

---

## 7. DRY Violations & Consolidation Opportunities

The codebase has significant opportunities for code consolidation. Addressing these DRY (Don't Repeat Yourself) violations would reduce approximately **500-800 lines of code** while improving maintainability.

### 7.1 Repeated State Management Patterns

**Violation Count:** 9+ ViewModels
**Estimated Savings:** 100+ LOC

All ViewModels duplicate identical state management boilerplate:

**Current Pattern (repeated in every ViewModel):**
```swift
// ChatViewModel.swift
@Published public private(set) var isLoadingConversations: Bool = false
@Published public private(set) var isLoadingMessages: Bool = false
@Published public private(set) var errorMessage: String? = nil

// WebsitesViewModel.swift
@Published public private(set) var isLoading: Bool = false
@Published public private(set) var isLoadingDetail: Bool = false
@Published public private(set) var errorMessage: String? = nil

// SettingsViewModel.swift
@Published public private(set) var errorMessage: String? = nil
@Published public private(set) var isLoading: Bool = false
@Published public private(set) var isLoadingSkills: Bool = false
```

**Recommended: Create `LoadableState` helper**

Create file: `Utilities/LoadableState.swift`
```swift
import Foundation
import Combine

/// Generic loading state container for async operations
public enum LoadingState<T> {
    case idle
    case loading
    case loaded(T)
    case failed(String)

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public var value: T? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    public var error: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Base class for ViewModels with common loading/error state
@MainActor
open class LoadableViewModel: ObservableObject {
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var errorMessage: String? = nil

    public func setLoading(_ loading: Bool) {
        isLoading = loading
    }

    public func setError(_ error: Error?) {
        errorMessage = error.map { ErrorMapping.message(for: $0) }
    }

    public func clearError() {
        errorMessage = nil
    }

    /// Execute an async operation with automatic loading/error state management
    public func withLoading<T>(
        _ operation: () async throws -> T,
        onSuccess: ((T) -> Void)? = nil
    ) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await operation()
            onSuccess?(result)
        } catch {
            errorMessage = ErrorMapping.message(for: error)
        }
        isLoading = false
    }
}
```

**Usage:**
```swift
// Before: 15 lines of boilerplate per ViewModel
// After: 1 line inheritance + direct usage
class WebsitesViewModel: LoadableViewModel {
    func load() async {
        await withLoading({ try await store.loadList() })
    }
}
```

---

### 7.2 Repeated Async Load Patterns

**Violation Count:** 8+ methods across ViewModels
**Estimated Savings:** 150+ LOC

Every ViewModel has nearly identical load methods with cache-first pattern:

**Current Pattern:**
```swift
// WebsitesViewModel.swift
public func load() async {
    if items.isEmpty { isLoading = true }
    errorMessage = nil
    do {
        try await store.loadList()
    } catch {
        if items.isEmpty { errorMessage = error.localizedDescription }
    }
    isLoading = false
}

// SettingsViewModel.swift
public func load() async {
    errorMessage = nil
    isLoading = true
    let cached: UserSettings? = cache.get(key: CacheKeys.userSettings)
    if let cached { settings = cached }
    do {
        let response = try await settingsAPI.getSettings()
        settings = response
        cache.set(key: CacheKeys.userSettings, value: response, ttlSeconds: CachePolicy.userSettings)
    } catch {
        if cached == nil { errorMessage = error.localizedDescription }
    }
    isLoading = false
}
```

**Recommended: Create `CachedLoader` utility**

Create file: `Utilities/CachedLoader.swift`
```swift
/// Reusable cache-first loading pattern
public struct CachedLoader<T: Codable> {
    private let cache: CacheClient
    private let cacheKey: String
    private let ttlSeconds: TimeInterval
    private let fetch: () async throws -> T

    public init(
        cache: CacheClient,
        key: String,
        ttl: TimeInterval,
        fetch: @escaping () async throws -> T
    ) {
        self.cache = cache
        self.cacheKey = key
        self.ttlSeconds = ttl
        self.fetch = fetch
    }

    /// Load with cache-first strategy
    /// - Returns: Tuple of (data, wasFromCache)
    public func load(force: Bool = false) async throws -> (T, Bool) {
        // Try cache first (unless forced)
        if !force, let cached: T = cache.get(key: cacheKey) {
            // Background refresh
            Task {
                if let fresh = try? await fetch() {
                    cache.set(key: cacheKey, value: fresh, ttlSeconds: ttlSeconds)
                }
            }
            return (cached, true)
        }

        // Fetch from network
        let remote = try await fetch()
        cache.set(key: cacheKey, value: remote, ttlSeconds: ttlSeconds)
        return (remote, false)
    }
}

// Usage:
let loader = CachedLoader(
    cache: cache,
    key: CacheKeys.userSettings,
    ttl: CachePolicy.userSettings,
    fetch: { try await settingsAPI.getSettings() }
)
let (settings, _) = try await loader.load()
```

---

### 7.3 Repeated String Trimming/Validation

**Violation Count:** 23+ occurrences
**Estimated Savings:** 50+ LOC

The pattern `trimmingCharacters(in: .whitespacesAndNewlines)` with empty check appears throughout:

**Current Pattern:**
```swift
// NotesViewModel.swift
let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
guard !trimmed.isEmpty else { return nil }

// WebsitesViewModel.swift
let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
guard !trimmed.isEmpty else {
    saveErrorMessage = "Enter a valid URL."
    return false
}

// ChatViewModel.swift
let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
guard !trimmed.isEmpty, !isStreaming else { return }
```

**Recommended: Create `String+Validation` extension**

Create file: `Utilities/String+Validation.swift`
```swift
public extension String {
    /// Returns trimmed string, or nil if empty after trimming
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Returns true if string is empty or contains only whitespace
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Trimmed version of the string
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// Usage:
// Before:
let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
guard !trimmed.isEmpty else { return nil }

// After:
guard let trimmed = title.trimmedOrNil else { return nil }
```

---

### 7.4 Repeated Cache Operations in Stores

**Violation Count:** 7+ Store classes
**Estimated Savings:** 80+ LOC

All Store classes follow identical cache-load-refresh patterns:

**Current Pattern:**
```swift
// NotesStore.swift
public func loadTree(force: Bool = false) async throws {
    let cached: FileTree? = force ? nil : cache.get(key: CacheKeys.notesTree)
    if let cached {
        applyTreeUpdate(cached, persist: false)
        Task { await self?.refreshTree() }
        return
    }
    let response = try await api.listTree()
    applyTreeUpdate(response, persist: true)
}

// WebsitesStore.swift
public func loadList(force: Bool = false) async throws {
    let cached: WebsitesResponse? = force ? nil : cache.get(key: CacheKeys.websitesList)
    if let cached {
        applyListUpdate(cached.items, persist: false)
        Task { await self?.refreshList() }
        return
    }
    let response = try await api.list()
    applyListUpdate(response.items, persist: true)
}
```

**Recommended: Create `CachedStore` protocol**

Create file: `Stores/CachedStore.swift`
```swift
/// Protocol for stores with cache-first loading
public protocol CachedStore: AnyObject {
    associatedtype CachedData: Codable

    var cache: CacheClient { get }
    var cacheKey: String { get }
    var cacheTTL: TimeInterval { get }

    func fetchFromAPI() async throws -> CachedData
    func applyData(_ data: CachedData, persist: Bool)
    func backgroundRefresh() async
}

public extension CachedStore {
    func loadWithCache(force: Bool = false) async throws {
        let cached: CachedData? = force ? nil : cache.get(key: cacheKey)

        if let cached {
            applyData(cached, persist: false)
            Task { [weak self] in await self?.backgroundRefresh() }
            return
        }

        let remote = try await fetchFromAPI()
        applyData(remote, persist: true)
        cache.set(key: cacheKey, value: remote, ttlSeconds: cacheTTL)
    }
}

// Usage:
extension NotesStore: CachedStore {
    var cacheKey: String { CacheKeys.notesTree }
    var cacheTTL: TimeInterval { CachePolicy.notesTree }

    func fetchFromAPI() async throws -> FileTree {
        try await api.listTree()
    }

    func applyData(_ data: FileTree, persist: Bool) {
        applyTreeUpdate(data, persist: persist)
    }
}
```

---

### 7.5 Repeated Task Management Patterns

**Violation Count:** 16+ files
**Estimated Savings:** 100+ LOC

Identical patterns for canceling and managing background tasks:

**Current Pattern:**
```swift
// ChatViewModel.swift
private var refreshTask: Task<Void, Never>?

public func startAutoRefresh(intervalSeconds: TimeInterval = 30) {
    refreshTask?.cancel()
    refreshTask = Task { [weak self] in
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
            await self?.refreshConversations(silent: true)
        }
    }
}

public func stopAutoRefresh() {
    refreshTask?.cancel()
    refreshTask = nil
}

// NotesViewModel.swift (debounced search)
searchTask?.cancel()
searchTask = Task { [weak self] in
    try? await Task.sleep(nanoseconds: 300_000_000)
    await self?.performSearch(query: trimmed)
}
```

**Recommended: Create `TaskManager` utilities**

Create file: `Utilities/TaskManager.swift`
```swift
/// Manages a single cancellable task
public final class ManagedTask {
    private var task: Task<Void, Never>?

    public init() {}

    public func cancel() {
        task?.cancel()
        task = nil
    }

    /// Start a new task, canceling any existing one
    public func run(_ action: @escaping @Sendable () async -> Void) {
        cancel()
        task = Task { await action() }
    }

    /// Start task after delay (useful for debouncing)
    public func runDebounced(
        delay: TimeInterval,
        _ action: @escaping @Sendable () async -> Void
    ) {
        cancel()
        task = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await action()
        }
    }
}

/// Manages a repeating polling task
public final class PollingTask {
    private var task: Task<Void, Never>?
    private let interval: TimeInterval

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    public func start(_ action: @escaping @Sendable () async -> Void) {
        cancel()
        task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await action()
            }
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }
}

// Usage:
class ChatViewModel {
    private let autoRefresh = PollingTask(interval: 30)
    private let searchDebounce = ManagedTask()

    func startAutoRefresh() {
        autoRefresh.start { [weak self] in
            await self?.refreshConversations(silent: true)
        }
    }

    func updateSearch(query: String) {
        searchDebounce.runDebounced(delay: 0.3) { [weak self] in
            await self?.performSearch(query: query)
        }
    }
}
```

---

### 7.6 Repeated Collection Filtering

**Violation Count:** 14+ files
**Estimated Savings:** 40+ LOC

Status-based filtering repeated throughout:

**Current Pattern:**
```swift
// IngestionViewModel.swift
public var activeUploadItems: [IngestionListItem] {
    items.filter { item in
        let status = item.job.status ?? ""
        return !["ready", "failed", "canceled"].contains(status)
    }
}

public var failedUploadItems: [IngestionListItem] {
    items.filter { ($0.job.status ?? "") == "failed" }
}

// ChatViewModel.swift
public var readyAttachments: [ChatAttachmentItem] {
    attachments.filter { $0.status == .ready }
}
```

**Recommended: Create status filtering protocol**

Create file: `Utilities/StatusFilterable.swift`
```swift
/// Protocol for items with a status property
public protocol StatusFilterable {
    var statusValue: String { get }
}

public extension Array where Element: StatusFilterable {
    static let terminalStatuses = ["ready", "failed", "canceled"]

    var activeItems: [Element] {
        filter { !Self.terminalStatuses.contains($0.statusValue) }
    }

    var readyItems: [Element] {
        filter { $0.statusValue == "ready" }
    }

    var failedItems: [Element] {
        filter { $0.statusValue == "failed" }
    }

    var hasActiveItems: Bool {
        contains { !$0.statusValue.isEmpty && !Self.terminalStatuses.contains($0.statusValue) }
    }
}

// Conformance:
extension IngestionListItem: StatusFilterable {
    var statusValue: String { job.status ?? "" }
}

// Usage:
public var activeUploadItems: [IngestionListItem] { items.activeItems }
public var failedUploadItems: [IngestionListItem] { items.failedItems }
```

---

### 7.7 Repeated Cache Invalidation

**Violation Count:** 10+ locations
**Estimated Savings:** 30+ LOC

Cache invalidation logic repeated in stream event handlers:

**Current Pattern:**
```swift
// ChatViewModel.swift
private func handleNoteCreate(_ event: ChatStreamEvent) {
    cache.remove(key: CacheKeys.notesTree)
    if let id = stringValue(from: event.data, key: "id") {
        cache.remove(key: CacheKeys.note(id: id))
    }
    refreshNotesTree()
}

private func handleNoteUpdate(_ event: ChatStreamEvent) {
    cache.remove(key: CacheKeys.notesTree)
    if let id = stringValue(from: event.data, key: "id") {
        cache.remove(key: CacheKeys.note(id: id))
    }
    refreshNotesTree()
}

private func handleWebsiteSaved(_ event: ChatStreamEvent) {
    cache.remove(key: CacheKeys.websitesList)
    if let id = stringValue(from: event.data, key: "id") {
        cache.remove(key: CacheKeys.websiteDetail(id: id))
    }
    refreshWebsitesList()
}
```

**Recommended: Create cache invalidation helpers**

Add to `CacheClient.swift`:
```swift
public extension CacheClient {
    /// Invalidate a list cache and optionally a related detail cache
    func invalidateList(
        listKey: String,
        detailKey: ((String) -> String)? = nil,
        id: String? = nil
    ) {
        remove(key: listKey)
        if let detailKey, let id {
            remove(key: detailKey(id))
        }
    }
}

// Usage:
cache.invalidateList(
    listKey: CacheKeys.notesTree,
    detailKey: CacheKeys.note,
    id: extractId(from: event)
)
```

---

### 7.8 Repeated Error Handling

**Violation Count:** 9+ ViewModels
**Estimated Savings:** 50+ LOC

All ViewModels handle errors identically:

**Current Pattern:**
```swift
} catch {
    errorMessage = error.localizedDescription
}

// Or with toast:
} catch {
    toastCenter.show(message: "Failed to create note")
}

// Or with mapping:
} catch {
    errorMessage = ErrorMapping.message(for: error)
}
```

**Recommended: Extend `ErrorMapping` utility**

Update `Utilities/ErrorMapping.swift`:
```swift
public enum ErrorMapping {
    /// Map error to user-friendly message
    public static func message(for error: Error) -> String {
        switch error {
        case let apiError as APIClientError:
            return mapAPIError(apiError)
        case is URLError:
            return "Network connection failed. Please check your internet."
        case is DecodingError:
            return "Received invalid data from server."
        default:
            return error.localizedDescription
        }
    }

    /// Map error with operation context
    public static func message(for error: Error, during operation: String) -> String {
        "Failed to \(operation): \(message(for: error))"
    }

    private static func mapAPIError(_ error: APIClientError) -> String {
        switch error {
        case .apiError(let message): return message
        case .missingToken: return "Please sign in again."
        case .requestFailed(let code): return "Server error (\(code))"
        case .decodingFailed: return "Invalid response format"
        default: return "Something went wrong"
        }
    }
}
```

---

### 7.9 Implementation Priority

| Helper | Priority | Files Affected | LOC Savings | Complexity |
|--------|----------|----------------|-------------|------------|
| `String+Validation` | **Critical** | 23+ | 50+ | Low |
| `ManagedTask` / `PollingTask` | **Critical** | 16+ | 100+ | Low |
| `LoadableViewModel` | **High** | 9 | 100+ | Medium |
| `CachedLoader` | **High** | 8 | 150+ | Medium |
| `CachedStore` protocol | **High** | 7 | 80+ | Medium |
| `StatusFilterable` | **Medium** | 14+ | 40+ | Low |
| `ErrorMapping` extensions | **Medium** | 9 | 50+ | Low |
| Cache invalidation helpers | **Low** | 10+ | 30+ | Low |

**Total Estimated Savings:** 600-800 LOC (~3% of codebase)

---

### 7.10 New Files to Create

```
Utilities/
├── String+Validation.swift      (~30 LOC) - String trimming/validation
├── LoadableState.swift          (~80 LOC) - Loading state management
├── CachedLoader.swift           (~50 LOC) - Cache-first loading pattern
├── TaskManager.swift            (~70 LOC) - Task lifecycle management
├── StatusFilterable.swift       (~40 LOC) - Status-based filtering

Stores/
└── CachedStore.swift            (~50 LOC) - Store caching protocol
```

---

## 7.11 Styling Consolidation (iOS/macOS)

The codebase has `DesignTokens.swift` but inconsistent usage. Centralizing styling would reduce code by **35-40%** in styling-related lines.

### Current State Summary

| Pattern | Instances | Using Tokens | Hardcoded |
|---------|-----------|--------------|-----------|
| Platform conditionals | 172 | N/A | 172 |
| Padding values | 100+ | ~60% | ~40 (34) |
| Color usage | 150+ | ~90% | ~13 |
| Font modifiers | 154 | 76% (118) | 24% (36) |
| Corner radii | 47 | ~30% | ~70% |
| Border overlays | 20 | Partial | Repeated |

---

### 7.11.1 Hardcoded Padding (34 instances)

**Problem:** Padding values scattered throughout instead of using `DesignTokens.Spacing`

**Current (scattered):**
```swift
// NotesView.swift, FilesView.swift, WebsitesView.swift, etc.
.padding(16)
.padding(20)
.padding(24)
.padding(.horizontal, 12)
.padding(.vertical, 6)
```

**DesignTokens.Spacing already exists but is underused:**
```swift
enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16   // Most common hardcoded value
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}
```

**Recommendation:** Replace all hardcoded padding with tokens:
```swift
// Before:
.padding(16)
.padding(.horizontal, 12)

// After:
.padding(DesignTokens.Spacing.md)
.padding(.horizontal, DesignTokens.Spacing.sm)
```

---

### 7.11.2 Hardcoded Colors (13 instances)

**Problem:** Semantic colors (error, success) not in design system

**Current (hardcoded):**
```swift
// ToastCenter.swift
Color.red.opacity(0.12)  // Error background
Color.red                // Error foreground

// LoginView.swift
Color.green.opacity(0.9) // Success state
Color.red.opacity(0.1)   // Error background

// ChatView.swift - Role pills
Color.black / Color.white  // Hardcoded for light/dark
```

**Recommended: Add semantic colors to DesignTokens**

```swift
enum Colors {
    // Existing...

    // MARK: - Semantic Colors (NEW)
    static let success = Color.green
    static let successBackground = Color.green.opacity(0.12)
    static let error = Color.red
    static let errorBackground = Color.red.opacity(0.12)
    static let warning = Color.orange
    static let warningBackground = Color.orange.opacity(0.12)

    // MARK: - Opacity Scale (NEW)
    static func overlay(opacity: OverlayOpacity) -> Color {
        Color.black.opacity(opacity.rawValue)
    }

    enum OverlayOpacity: Double {
        case subtle = 0.08
        case light = 0.12
        case medium = 0.25
        case strong = 0.35
        case heavy = 0.5
    }
}
```

---

### 7.11.3 Custom Font Definitions (36 instances)

**Problem:** Custom font sizes scattered instead of using semantic font tokens

**Current (scattered):**
```swift
// 11+ instances of this exact pattern:
.font(.system(size: 14, weight: .semibold))

// Other scattered sizes:
.font(.system(size: 18, weight: .semibold))  // 4 instances
.font(.system(size: 12, weight: .semibold))  // 1 instance
.font(.system(size: 10, weight: .bold))      // 1 instance
.font(.system(size: 32, weight: .semibold))  // 1 instance
```

**Recommended: Add FontTokens to DesignTokens**

```swift
enum Typography {
    // MARK: - Labels (semibold)
    static let labelXS = Font.system(size: 10, weight: .bold)
    static let labelSM = Font.system(size: 12, weight: .semibold)
    static let labelMD = Font.system(size: 14, weight: .semibold)  // Most common
    static let labelLG = Font.system(size: 18, weight: .semibold)
    static let labelXL = Font.system(size: 24, weight: .semibold)

    // MARK: - Display
    static let displaySM = Font.system(size: 32, weight: .semibold)
    static let displayLG = Font.system(size: 60, weight: .regular)

    // MARK: - Body (maps to system styles)
    static let bodySmall = Font.subheadline
    static let bodyMedium = Font.body
    static let bodyLarge = Font.title3
}
```

**Usage:**
```swift
// Before:
.font(.system(size: 14, weight: .semibold))

// After:
.font(DesignTokens.Typography.labelMD)
```

---

### 7.11.4 Platform Conditionals (172 instances)

**Problem:** Platform-specific styling scattered throughout 40+ files

**Current (scattered):**
```swift
// GlassButtonStyle.swift
#if os(macOS)
return .fill(.regularMaterial)
#else
return .fill(.ultraThinMaterial)
#endif

// SelectableRow.swift
#if os(macOS)
return DesignTokens.Colors.sidebar
#else
return DesignTokens.Colors.background
#endif

// LayoutMetrics.swift
#if os(macOS)
return 64
#else
return 56
#endif
```

**Recommended: Create PlatformTokens**

```swift
enum PlatformTokens {
    // MARK: - Materials
    static var thinMaterial: Material {
        #if os(macOS)
        return .regularMaterial
        #else
        return .ultraThinMaterial
        #endif
    }

    // MARK: - Background Colors
    static var rowBackground: Color {
        #if os(macOS)
        return DesignTokens.Colors.sidebar
        #else
        return DesignTokens.Colors.background
        #endif
    }

    static var headerBackground: Color {
        #if os(macOS)
        return DesignTokens.Colors.sidebar
        #else
        return DesignTokens.Colors.surface
        #endif
    }

    // MARK: - Sizing
    static var appHeaderHeight: CGFloat {
        #if os(macOS)
        return 64
        #else
        return 56
        #endif
    }

    static var contentHeaderHeight: CGFloat {
        #if os(macOS)
        return 58
        #else
        return 52
        #endif
    }
}
```

---

### 7.11.5 Corner Radius (47 instances, ~70% hardcoded)

**Problem:** `DesignTokens.Radius` exists but most code uses hardcoded values

**Current (hardcoded):**
```swift
RoundedRectangle(cornerRadius: 10)   // 15 instances
RoundedRectangle(cornerRadius: 12)   // 5 instances
RoundedRectangle(cornerRadius: 16)   // 4 instances
RoundedRectangle(cornerRadius: 8)    // 3 instances
```

**DesignTokens.Radius already exists:**
```swift
enum Radius {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10   // Matches common hardcoded 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 18
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}
```

**Recommendation:** Replace all hardcoded radii:
```swift
// Before:
RoundedRectangle(cornerRadius: 10, style: .continuous)
RoundedRectangle(cornerRadius: 16, style: .continuous)

// After:
RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
```

---

### 7.11.6 Repeated View Modifier Patterns

**Problem:** Same modifier combinations repeated throughout codebase

**Border Overlay Pattern (20 instances):**
```swift
.overlay(
    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
        .stroke(DesignTokens.Colors.border, lineWidth: 1)
)
```

**Recommended: Create reusable modifiers**

```swift
// Design/Modifiers/BorderModifier.swift
struct BorderedModifier: ViewModifier {
    var radius: CGFloat = DesignTokens.Radius.md
    var color: Color = DesignTokens.Colors.border
    var lineWidth: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(color, lineWidth: lineWidth)
            )
    }
}

extension View {
    func bordered(
        radius: CGFloat = DesignTokens.Radius.md,
        color: Color = DesignTokens.Colors.border
    ) -> some View {
        modifier(BorderedModifier(radius: radius, color: color))
    }
}

// Usage:
// Before (5 lines):
.clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
.overlay(
    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
        .stroke(DesignTokens.Colors.border, lineWidth: 1)
)

// After (1 line):
.bordered()
```

**Shadow Pattern (inconsistent):**
```swift
// Create standardized shadows
struct ShadowModifier: ViewModifier {
    enum Style {
        case subtle, medium, strong

        var color: Color {
            switch self {
            case .subtle: return Color.black.opacity(0.08)
            case .medium: return Color.black.opacity(0.12)
            case .strong: return Color.black.opacity(0.20)
            }
        }

        var radius: CGFloat {
            switch self {
            case .subtle: return 4
            case .medium: return 8
            case .strong: return 16
            }
        }
    }

    let style: Style

    func body(content: Content) -> some View {
        content.shadow(color: style.color, radius: style.radius, x: 0, y: style.radius * 0.5)
    }
}

extension View {
    func standardShadow(_ style: ShadowModifier.Style = .medium) -> some View {
        modifier(ShadowModifier(style: style))
    }
}
```

---

### 7.11.7 Implementation Priority

| Task | Priority | Files Affected | Impact |
|------|----------|----------------|--------|
| Replace hardcoded padding | **Critical** | 34 instances | High |
| Add Typography tokens | **Critical** | 36 instances | High |
| Add semantic colors | **High** | 13 instances | Medium |
| Replace hardcoded radii | **High** | 47 instances | Medium |
| Create PlatformTokens | **High** | 40 files | High |
| Create BorderedModifier | **Medium** | 20 instances | Medium |
| Create ShadowModifier | **Low** | 2 instances | Low |

---

### 7.11.8 Proposed DesignTokens.swift Updates

```swift
// Additions to existing DesignTokens.swift

enum DesignTokens {
    // MARK: - Existing (keep as-is)
    enum Spacing { ... }
    enum Radius { ... }
    enum Size { ... }
    enum Icon { ... }
    enum Colors { ... }
    enum Animation { ... }

    // MARK: - NEW: Typography
    enum Typography {
        static let labelXS = Font.system(size: 10, weight: .bold)
        static let labelSM = Font.system(size: 12, weight: .semibold)
        static let labelMD = Font.system(size: 14, weight: .semibold)
        static let labelLG = Font.system(size: 18, weight: .semibold)
        static let displaySM = Font.system(size: 32, weight: .semibold)
    }

    // MARK: - NEW: Semantic Colors (add to Colors enum)
    // Colors.success, Colors.error, Colors.warning
    // Colors.successBackground, Colors.errorBackground

    // MARK: - NEW: Platform
    enum Platform {
        static var material: Material { ... }
        static var rowBackground: Color { ... }
        static var headerHeight: CGFloat { ... }
    }
}
```

---

### 7.11.9 New Modifier Files to Create

```
Design/Modifiers/
├── BorderedModifier.swift    (~25 LOC) - Bordered card/field style
├── ShadowModifier.swift      (~30 LOC) - Standardized shadows
└── View+Styling.swift        (~20 LOC) - Convenience extensions
```

---

## 7.12 Security Audit

The codebase demonstrates **generally strong security practices** with proper Keychain usage, HTTPS enforcement, and careful logging. However, there are areas requiring attention.

### Security Summary

| Category | Status | Severity |
|----------|--------|----------|
| API Keys & Secrets | ✅ Secure | - |
| Keychain Usage | ✅ Excellent | - |
| HTTPS Enforcement | ✅ Secure | - |
| Certificate Pinning | ⚠️ Not Implemented | Medium |
| Session Management | ✅ Secure | - |
| Offline Access Window | ⚠️ Too Long (7 days) | Medium |
| Biometric Auth | ✅ Secure | - |
| Sensitive Logging | ✅ Excellent | - |
| Clipboard Handling | ⚠️ No Auto-Clear | Medium |
| URL Validation | ✅ Excellent | - |
| CoreData Encryption | ⚠️ Not Configured | Medium |
| URLCache Protection | ⚠️ Unencrypted | Medium |
| Debug Code | ✅ Properly Isolated | - |

---

### 7.12.1 Excellent Practices (No Action Required)

#### Keychain Implementation
**File:** `Services/Auth/KeychainAuthStateStore.swift`

- Uses AES-GCM 256-bit encryption for stored tokens
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` - tokens only accessible when device unlocked
- iCloud Keychain sync disabled - prevents token leakage across devices
- Auto-generates encryption key on first use

#### Logging Practices
**Files:** Throughout codebase

```swift
// Proper privacy annotations
logger.error("Sign in failed: \(mappedError.localizedDescription, privacy: .public)")
logger.error("Response body: \(preview, privacy: .private)")
```

- Uses `privacy: .public` and `privacy: .private` annotations properly
- No tokens, passwords, or credentials logged
- Debug logging only in `#if DEBUG` blocks

#### URL Validation
**File:** `Utilities/WebsiteURLValidator.swift`

- Blocks localhost access
- Blocks custom ports
- Blocks direct IP addresses
- Validates TLD format
- Prevents DNS rebinding attacks

#### Configuration Management
**File:** `Config/SideBar.xcconfig`

- Secrets left empty in tracked config file
- Uses `.local.xcconfig` for actual values (not in git)
- Proper environment variable delegation

---

### 7.12.2 Issues Requiring Attention

#### Issue 1: No Certificate Pinning
**Severity:** MEDIUM
**Risk:** Vulnerable to MITM attacks if CA infrastructure is compromised

**Current State:** Uses standard URLSession without certificate pinning

**Recommendation:** Implement certificate pinning:
```swift
// Using TrustKit or custom URLSessionDelegate
class PinningDelegate: NSObject, URLSessionDelegate {
    private let pinnedCertificates: Set<Data> = [/* certificate data */]

    func urlSession(_ session: URLSession,
                   didReceive challenge: URLAuthenticationChallenge,
                   completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let serverTrust = challenge.protectionSpace.serverTrust,
              let certificate = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let serverCertData = SecCertificateCopyData(certificate) as Data
        if pinnedCertificates.contains(serverCertData) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
```

---

#### Issue 2: 7-Day Offline Access Window
**Severity:** MEDIUM
**File:** `Services/Auth/SupabaseAuthAdapter.swift:98`

**Current:**
```swift
private let offlineAccessWindow: TimeInterval = 60 * 60 * 24 * 7  // 7 days
```

**Risk:** If device is stolen, attacker has 7 days to use the account without server validation.

**Recommendation:** Reduce to 24-48 hours:
```swift
private let offlineAccessWindow: TimeInterval = 60 * 60 * 24 * 1  // 1 day
```

---

#### Issue 3: Clipboard Not Auto-Cleared
**Severity:** MEDIUM
**Files:** `SettingsView.swift:637`, `ChatView.swift:604`, `WebsitesView.swift:378`

**Current:**
```swift
private func copyToken() {
    UIPasteboard.general.string = viewModel.shortcutsToken
    // Token stays in clipboard indefinitely
}
```

**Risk:** Sensitive data (shortcuts token) persists in clipboard; other apps can read it.

**Recommendation:** Auto-clear after 30 seconds:
```swift
private func copyToken() {
    guard !viewModel.shortcutsToken.isEmpty else { return }

    #if os(iOS)
    UIPasteboard.general.string = viewModel.shortcutsToken
    #else
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(viewModel.shortcutsToken, forType: .string)
    #endif

    // Clear after 30 seconds
    DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
        #if os(iOS)
        if UIPasteboard.general.string == viewModel.shortcutsToken {
            UIPasteboard.general.string = ""
        }
        #else
        NSPasteboard.general.clearContents()
        #endif
    }
}
```

---

#### Issue 4: CoreData Cache Not Protected
**Severity:** MEDIUM
**File:** `Services/Persistence/PersistenceController.swift`

**Current:** No `NSFileProtectionKey` configured for CoreData files.

**Risk:** Cache may contain API responses, conversation snippets, and potentially sensitive data stored unencrypted.

**Recommendation:** Enable file protection:
```swift
public init(inMemory: Bool = false) {
    container = NSPersistentContainer(name: "SideBarCache")

    // Add file protection
    container.persistentStoreDescriptions.forEach { desc in
        desc.setOption(
            FileProtectionType.complete as NSObject,
            forKey: NSPersistentStoreFileProtectionKey
        )
    }

    container.loadPersistentStores { /* ... */ }
}
```

---

#### Issue 5: URLCache Unprotected
**Severity:** MEDIUM
**File:** `Services/Network/APIClient.swift:191-206`

**Current:** 100 MB disk cache stores HTTP responses without encryption in `.cachesDirectory`.

**Risk:** API responses may contain sensitive user data.

**Recommendation:** Disable caching for sensitive endpoints:
```swift
// Option 1: Disable disk cache entirely
configuration.urlCache = URLCache(
    memoryCapacity: 20 * 1024 * 1024,
    diskCapacity: 0,  // No disk caching
    diskPath: nil
)

// Option 2: Use cache policy for sensitive requests
var request = URLRequest(url: url)
request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
```

---

### 7.12.3 Security Implementation Priority

| Fix | Priority | Effort | Impact |
|-----|----------|--------|--------|
| Enable CoreData file protection | **High** | Low | High |
| Reduce offline access window | **High** | Low | Medium |
| Auto-clear clipboard | **Medium** | Low | Medium |
| Disable/protect URLCache | **Medium** | Low | Medium |
| Implement certificate pinning | **Medium** | Medium | High |

---

### 7.12.4 Security Checklist for Future Development

- [ ] Never log tokens, passwords, or PII without `privacy: .private`
- [ ] Store sensitive data in Keychain, not UserDefaults
- [ ] Use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for Keychain items
- [ ] Validate all URLs before navigation (use `WebsiteURLValidator` pattern)
- [ ] Clear clipboard after copying sensitive data
- [ ] Use HTTPS for all network requests
- [ ] Consider certificate pinning for high-security endpoints
- [ ] Enable file protection for local databases
- [ ] Keep DEBUG-only code in `#if DEBUG` blocks

---

## 8. Action Plan

### Phase 1: Critical Fixes & Quick Wins (Week 1-2)

**Security (High Priority):**
- [ ] Enable CoreData file protection in `PersistenceController.swift`
- [ ] Reduce offline access window from 7 days to 24 hours
- [ ] Add auto-clear for clipboard after copying sensitive data
- [ ] Disable or protect URLCache for sensitive endpoints

**Error Handling:**
- [ ] Fix empty catch blocks in SupabaseRealtimeAdapter.swift
- [ ] Add logging to silent `try?` statements

**DRY Consolidation (Quick Wins):**
- [ ] Create `String+Validation.swift` extension (30 LOC, affects 23+ files)
- [ ] Create `TaskManager.swift` with `ManagedTask` and `PollingTask` (70 LOC, affects 16+ files)
- [ ] Extend `ErrorMapping.swift` with comprehensive error handling

**Styling Quick Wins:**
- [ ] Replace 34 hardcoded padding values with `DesignTokens.Spacing`
- [ ] Replace 47 hardcoded corner radii with `DesignTokens.Radius`

**Testing:**
- [ ] Add tests for NotesEditorViewModel
- [ ] Add tests for ChatStreamParser

### Phase 2: File Restructuring & DRY Patterns (Week 3-4)

**File Splits:**
- [ ] Split SidebarPanels.swift into 8 focused files
- [ ] Split ChatView.swift into 7 focused files
- [ ] Split ChatViewModel.swift into 6 focused files
- [ ] Add MARK sections to remaining large files

**DRY Consolidation (Medium Complexity):**
- [ ] Create `LoadableState.swift` with `LoadableViewModel` base class (80 LOC)
- [ ] Create `CachedLoader.swift` utility (50 LOC)
- [ ] Create `StatusFilterable.swift` protocol (40 LOC)
- [ ] Refactor ViewModels to use new helpers

**Styling Consolidation:**
- [ ] Add `Typography` tokens to DesignTokens.swift (replace 36 hardcoded fonts)
- [ ] Add semantic colors (success, error, warning) to DesignTokens.Colors
- [ ] Create `PlatformTokens` enum to centralize 172 platform conditionals
- [ ] Create `BorderedModifier.swift` (replace 20 border patterns)
- [ ] Create `ShadowModifier.swift` for consistent shadows

### Phase 3: Store Consolidation & Testing (Week 5-6)

**DRY Consolidation:**
- [ ] Create `CachedStore.swift` protocol (50 LOC)
- [ ] Refactor NotesStore, WebsitesStore, IngestionStore to use protocol
- [ ] Add cache invalidation helpers to CacheClient

**Testing Expansion:**
- [ ] Add Store tests (ChatStore, NotesStore, WebsitesStore)
- [ ] Add API tests (ChatAPI, FilesAPI, NotesAPI)
- [ ] Add utility tests (MarkdownFormatting, DateParsing)
- [ ] Add tests for new helper utilities
- [ ] Achieve 70%+ coverage on ViewModels

### Phase 4: Documentation & Polish (Week 7-8)

- [ ] Add doc comments to all ViewModels
- [ ] Add doc comments to all Services
- [ ] Document new helper utilities
- [ ] Create IOS_ARCHITECTURE.md
- [ ] Update README.md with setup instructions
- [ ] Add SwiftLint configuration
- [ ] Enable code coverage reporting

---

## 9. Metrics Summary

| Metric | Current | Target | Gap |
|--------|---------|--------|-----|
| Files over 600 LOC | 11 | 0 | -11 |
| Test coverage (ViewModels) | ~60% | 80% | -20% |
| Test coverage (Services) | ~16% | 80% | -64% |
| Doc comments | 2 | 100+ | -98 |
| Empty catch blocks | 15+ | 0 | -15 |
| MARK sections | 0 | 50+ | -50 |
| DRY violations | 80+ | 0 | -80 |
| Reusable helpers | 0 | 6 | -6 |
| Estimated duplicate LOC | 600-800 | 0 | -600 |

### Styling Metrics

| Metric | Current | Target | Gap |
|--------|---------|--------|-----|
| Hardcoded padding values | 34 | 0 | -34 |
| Hardcoded font definitions | 36 | 0 | -36 |
| Hardcoded corner radii | ~33 | 0 | -33 |
| Hardcoded colors | 13 | 0 | -13 |
| Platform conditionals (styling) | 172 | ~20 | -152 |
| Repeated border patterns | 20 | 0 | -20 |
| Typography tokens | 0 | 10+ | -10 |
| Semantic color tokens | 0 | 6+ | -6 |
| Platform token coverage | 0% | 90%+ | -90% |

### Security Metrics

| Metric | Current | Target | Status |
|--------|---------|--------|--------|
| Keychain for sensitive data | ✅ Yes | Yes | Secure |
| HTTPS enforcement | ✅ Yes | Yes | Secure |
| Certificate pinning | ❌ No | Yes | Action needed |
| CoreData file protection | ❌ No | Yes | Action needed |
| URLCache protection | ❌ No | Yes | Action needed |
| Offline access window | 7 days | 1-2 days | Action needed |
| Clipboard auto-clear | ❌ No | Yes | Action needed |
| Sensitive data logging | ✅ Secure | Secure | Secure |
| Debug code isolation | ✅ Secure | Secure | Secure |

---

## Appendix A: File Size Breakdown

| Component | Files | LOC | % of Total |
|-----------|-------|-----|------------|
| Views | 37 | 13,408 | 55.5% |
| ViewModels | 12 | 3,343 | 13.8% |
| Services | 31 | 3,044 | 12.6% |
| Utilities | 19 | 1,277 | 5.3% |
| Stores | 6 | 1,102 | 4.6% |
| Design | 21 | 804 | 3.3% |
| Models | 13 | 641 | 2.7% |
| App | 5 | 456 | 1.9% |
| **Total** | **145** | **24,166** | **100%** |

## Appendix B: Test Files

| Test File | Tests | Coverage Area |
|-----------|-------|---------------|
| ChatViewModelTests.swift | 5 | Conversation, messages |
| WebsitesViewModelTests.swift | 8 | Website CRUD |
| NotesViewModelTests.swift | 4 | Notes CRUD |
| IngestionViewModelTests.swift | 4 | File uploads |
| SettingsViewModelTests.swift | 4 | Settings |
| MemoriesViewModelTests.swift | 2 | Memory browsing |
| ScratchpadViewModelTests.swift | 3 | Scratchpad |
| WeatherViewModelTests.swift | 1 | Weather data |
| APIClientTests.swift | 5 | HTTP client |
| KeychainAuthStateStoreTests.swift | 4 | Token storage |
| SupabaseAuthAdapterTests.swift | 2 | JWT parsing |
| ThemeManagerTests.swift | 2 | Theme switching |
| WebsiteURLValidatorTests.swift | 5 | URL validation |
| ScratchpadFormattingTests.swift | 6 | Text formatting |
| EnvironmentConfigFileReaderTests.swift | 1 | Config loading |

## Appendix C: Proposed New Helper Files

### DRY Consolidation Files

| File | LOC | Purpose | Files Affected |
|------|-----|---------|----------------|
| `Utilities/String+Validation.swift` | ~30 | String trimming, blank checking | 23+ |
| `Utilities/TaskManager.swift` | ~70 | `ManagedTask`, `PollingTask` classes | 16+ |
| `Utilities/LoadableState.swift` | ~80 | `LoadingState<T>`, `LoadableViewModel` base | 9 |
| `Utilities/CachedLoader.swift` | ~50 | Generic cache-first loading pattern | 8 |
| `Utilities/StatusFilterable.swift` | ~40 | Status-based collection filtering | 14+ |
| `Stores/CachedStore.swift` | ~50 | Protocol for cached store pattern | 7 |

### Styling Consolidation Files

| File | LOC | Purpose | Files Affected |
|------|-----|---------|----------------|
| `Design/DesignTokens+Typography.swift` | ~40 | Font tokens (labelXS-XL, display, body) | 36 |
| `Design/DesignTokens+SemanticColors.swift` | ~30 | success, error, warning + backgrounds | 13 |
| `Design/PlatformTokens.swift` | ~60 | Centralized platform conditionals | 40+ |
| `Design/Modifiers/BorderedModifier.swift` | ~25 | `.bordered()` view modifier | 20 |
| `Design/Modifiers/ShadowModifier.swift` | ~30 | `.standardShadow()` view modifier | 10+ |
| `Design/Modifiers/View+Styling.swift` | ~20 | Convenience extensions | All views |

**Total New Code (DRY):** ~320 LOC
**Total New Code (Styling):** ~205 LOC
**Total New Code:** ~525 LOC

**Estimated Savings (DRY):** 600-800 LOC
**Estimated Savings (Styling):** 300-400 LOC
**Total Estimated Savings:** 900-1,200 LOC

**Net Reduction:** ~400-700 LOC (~2-3% of codebase)

---

*Report generated by automated code review. For questions, see QUALITY_ENFORCEMENT.md and TESTING.md.*
