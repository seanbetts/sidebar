# iOS Architecture Guide

**Last Updated:** January 2026
**Platform:** iOS 17+ / macOS 14+ (Universal SwiftUI App)

---

## Overview

The sideBar iOS app follows an **MVVM (Model-View-ViewModel)** architecture with a dedicated **Store layer** for data persistence and caching. The app is built entirely in SwiftUI with modern Swift concurrency (async/await).

```
┌─────────────────────────────────────────────────────────────┐
│                         Views                                │
│              (SwiftUI, observe ViewModels)                   │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│                      ViewModels                              │
│         (ObservableObject, coordinate business logic)        │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│                        Stores                                │
│            (Data persistence, caching, real-time)            │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│                       Services                               │
│         (Network, Auth, Cache, Upload, Realtime)             │
└─────────────────────────────────────────────────────────────┘
```

---

## Directory Structure

```
sideBar/
├── App/                      # App entry point, environment setup
│   ├── sideBarApp.swift      # @main entry, dependency injection
│   ├── AppEnvironment.swift  # Shared environment object
│   └── AppContainer.swift    # Dependency container
│
├── Views/                    # SwiftUI views
│   ├── Auth/                 # Login, authentication flows
│   ├── Chat/                 # Chat interface components
│   ├── Notes/                # Note editor and viewer
│   ├── SidebarPanels/        # Navigation panels (split from large file)
│   └── KeyboardShortcuts/    # macOS keyboard handling
│
├── ViewModels/               # Business logic layer
│   ├── Chat/                 # ChatViewModel + extensions
│   ├── NotesViewModel.swift
│   ├── WebsitesViewModel.swift
│   ├── IngestionViewModel.swift
│   └── ...
│
├── Stores/                   # Data persistence layer
│   ├── CachedStore.swift     # Base class for cached stores
│   ├── ChatStore.swift
│   ├── NotesStore.swift
│   ├── WebsitesStore.swift
│   └── IngestionStore.swift
│
├── Services/                 # Infrastructure layer
│   ├── Auth/                 # Supabase auth, keychain
│   ├── Cache/                # CoreData cache client
│   ├── Chat/                 # Stream client, parsers
│   ├── Network/              # API client, endpoints
│   ├── Realtime/             # Supabase realtime subscriptions
│   ├── Persistence/          # CoreData setup
│   └── Upload/               # File upload manager
│
├── Models/                   # Data structures
│   ├── CoreData/             # Core Data models
│   └── *.swift               # Codable API models
│
├── Design/                   # UI system
│   ├── DesignTokens.swift    # Spacing, colors, typography
│   ├── Components/           # Reusable UI components
│   ├── Extensions/           # SwiftUI extensions
│   ├── Modifiers/            # Custom view modifiers
│   └── Styles/               # Button styles, etc.
│
└── Utilities/                # Shared helpers
    ├── String+Validation.swift
    ├── TaskManager.swift
    ├── LoadableState.swift
    └── ...
```

---

## Key Patterns

### 1. Store vs ViewModel Distinction

**Stores** manage data lifecycle and caching:
- Own the source of truth for domain data
- Handle cache-first loading with background refresh
- Process real-time events from Supabase
- Expose data via `@Published` properties

**ViewModels** coordinate UI interactions:
- Subscribe to Store publishers
- Handle user actions (create, update, delete)
- Manage loading/error states for UI
- Don't persist data directly

```swift
// Store owns the data
class NotesStore: CachedStoreBase<FileTree> {
    @Published var tree: FileTree?
    @Published var activeNote: NotePayload?
}

// ViewModel coordinates UI
class NotesViewModel: ObservableObject {
    @Published var tree: FileTree?  // Mirrored from store

    init(store: NotesStore) {
        store.$tree.assign(to: &$tree)
    }
}
```

### 2. CachedStoreBase Pattern

All stores inherit from `CachedStoreBase<T>` for consistent cache-first loading:

```swift
open class CachedStoreBase<CachedData: Codable>: ObservableObject {
    // Subclasses override these
    open var cacheKey: String { fatalError() }
    open var cacheTTL: TimeInterval { fatalError() }
    open func fetchFromAPI() async throws -> CachedData
    open func applyData(_ data: CachedData, persist: Bool)
    open func backgroundRefresh() async

    // Inherited behavior
    public func loadWithCache(force: Bool = false) async throws {
        // 1. Check cache first
        // 2. Apply cached data immediately
        // 3. Trigger background refresh
        // 4. Or fetch from network if no cache
    }
}
```

### 3. ViewModel File Splitting

Large ViewModels are split across multiple files using extensions:

```
ChatViewModel.swift              # Core state, init
ChatViewModel+Conversations.swift # Conversation CRUD
ChatViewModel+Streaming.swift     # Message sending, stream handling
ChatViewModel+Realtime.swift      # Real-time event processing
ChatViewModelTypes.swift          # Supporting types
```

### 4. Task Management

Use `ManagedTask` and `PollingTask` utilities for async operations:

```swift
class NotesViewModel {
    private let searchTask = ManagedTask()

    func updateSearch(query: String) {
        searchTask.runDebounced(delay: 0.3) { [weak self] in
            await self?.performSearch(query: query)
        }
    }
}

class IngestionViewModel {
    var listPollingTask: PollingTask?

    func startPolling() {
        listPollingTask = PollingTask(interval: 5.0)
        listPollingTask?.start { [weak self] in
            await self?.refreshList()
        }
    }
}
```

### 5. Design Token System

All UI values flow through `DesignTokens`:

```swift
// Spacing
.padding(DesignTokens.Spacing.md)        // 16pt
.padding(.horizontal, DesignTokens.Spacing.sm)  // 12pt

// Colors
.foregroundStyle(DesignTokens.Colors.textPrimary)
.background(DesignTokens.Colors.errorBackground)

// Typography
.font(DesignTokens.Typography.labelMd)   // 14pt semibold
.font(DesignTokens.Typography.titleLg)   // 18pt semibold

// Radius
.clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
```

---

## Data Flow

### Loading Data (Cache-First)

```
User opens screen
       │
       ▼
ViewModel.load()
       │
       ▼
Store.loadWithCache()
       │
       ├──► Cache hit? ──► Apply cached data immediately
       │                          │
       │                          ▼
       │                   Background refresh
       │                          │
       │                          ▼
       │                   Update if changed
       │
       └──► Cache miss? ──► Fetch from API
                                  │
                                  ▼
                           Apply & cache data
```

### Real-Time Updates

```
Supabase sends event
       │
       ▼
SupabaseRealtimeAdapter
       │
       ▼
Store.applyRealtimeEvent()
       │
       ▼
Update @Published properties
       │
       ▼
SwiftUI auto-updates UI
```

### User Actions

```
User taps "Create Note"
       │
       ▼
ViewModel.createNote()
       │
       ├──► Show optimistic UI
       │
       ▼
API.createNote()
       │
       ├──► Success: Store.applyEditorUpdate()
       │
       └──► Failure: Show error toast
```

---

## Threading Model

- **Views**: Main thread (SwiftUI requirement)
- **ViewModels**: `@MainActor` annotated
- **Stores**: `@MainActor` annotated (via CachedStoreBase)
- **Services**: Background threads, dispatch to main for callbacks
- **Real-time**: Events dispatched to main actor

All `@Published` property updates happen on the main thread.

---

## Dependency Injection

Dependencies are injected via `AppContainer` at app startup:

```swift
struct AppContainer {
    let apiClient: APIClient
    let cache: CacheClient
    let authSession: AuthSessionProviding

    // Stores
    lazy var chatStore: ChatStore
    lazy var notesStore: NotesStore

    // ViewModels created as needed
    func makeChatViewModel() -> ChatViewModel
    func makeNotesViewModel() -> NotesViewModel
}
```

`AppEnvironment` holds shared state and is injected via `@EnvironmentObject`:

```swift
class AppEnvironment: ObservableObject {
    let container: AppContainer
    @Published var isAuthenticated: Bool
    @Published var isOffline: Bool
}
```

---

## Error Handling

### Consistent Error Mapping

Use `ErrorMapping` for user-friendly messages:

```swift
catch {
    errorMessage = ErrorMapping.message(for: error)
}
```

### Toast Notifications

Non-critical errors use `ToastCenter`:

```swift
catch {
    toastCenter.show(message: "Failed to create note")
}
```

### Logging

Use structured logging with privacy annotations:

```swift
logger.error("API failed: \(error.localizedDescription, privacy: .public)")
logger.debug("Token: \(token, privacy: .private)")
```

---

## Security Practices

1. **Keychain**: All tokens stored with AES-GCM encryption
2. **File Protection**: CoreData uses `FileProtectionType.complete`
3. **Clipboard**: Auto-cleared after 30 seconds for sensitive data
4. **URLCache**: Disk caching disabled for API responses
5. **Certificate Pinning**: Implemented for production API
6. **Offline Access**: Limited to 24-hour window

---

## Testing Strategy

### Coverage Targets

| Layer | Target | Current |
|-------|--------|---------|
| ViewModels | 80% | ~75% |
| Stores | 80% | ~70% |
| Services | 80% | ~65% |
| Utilities | 90% | ~85% |

### Test Organization

```
sideBarTests/
├── ViewModels/           # ViewModel unit tests
├── Stores/               # Store tests with mock cache
├── Services/             # Service tests with mock network
├── Utilities/            # Pure function tests
└── TestSupport/          # Shared mocks and helpers
```

### Testing Patterns

```swift
// Use protocol mocks for dependencies
class MockNotesAPI: NotesProviding {
    var listTreeResult: Result<FileTree, Error> = .success(FileTree(...))

    func listTree() async throws -> FileTree {
        try listTreeResult.get()
    }
}

// Test ViewModel behavior
func testLoadTree_cachesResult() async {
    let mockAPI = MockNotesAPI()
    let store = NotesStore(api: mockAPI, cache: TestCacheClient())
    let viewModel = NotesViewModel(api: mockAPI, store: store, toastCenter: MockToastCenter())

    await viewModel.loadTree()

    XCTAssertNotNil(viewModel.tree)
}
```

---

## Platform Considerations

### iOS vs macOS

Use `PlatformTokens` for platform-specific values:

```swift
#if os(macOS)
// macOS-specific code
#else
// iOS-specific code
#endif

// Or use PlatformTokens
.background(PlatformTokens.panelHeaderBackground)
```

### Keyboard Navigation

- macOS: Full keyboard shortcut support via `KeyboardShortcutsView`
- iOS: Focus management via `@FocusState`

### Window Management

- macOS: Multi-window support via `WindowGroup`
- iOS: Scene-based lifecycle with state restoration

---

## Common Tasks

### Adding a New Feature

1. **Model**: Add Codable structs in `Models/`
2. **API**: Add endpoint in `Services/Network/`
3. **Store**: Create store extending `CachedStoreBase`
4. **ViewModel**: Create ViewModel subscribing to store
5. **View**: Build SwiftUI view observing ViewModel
6. **Tests**: Add tests for Store and ViewModel

### Adding a New API Endpoint

```swift
// 1. Add to appropriate API file
extension NotesAPI {
    func newEndpoint(param: String) async throws -> Response {
        try await client.request(
            method: .post,
            path: "/notes/new-endpoint",
            body: ["param": param]
        )
    }
}

// 2. Add protocol method
protocol NotesProviding {
    func newEndpoint(param: String) async throws -> Response
}

// 3. Add mock for testing
class MockNotesAPI: NotesProviding {
    var newEndpointResult: Result<Response, Error> = ...
}
```

### Adding Design Tokens

```swift
// In DesignTokens.swift
enum Colors {
    static let newColor = Color.blue.opacity(0.5)
}

enum Typography {
    static let newStyle = Font.system(size: 16, weight: .medium)
}
```

---

## Performance Guidelines

1. **Lazy Loading**: Use `LazyVStack` for long lists
2. **Image Caching**: Use async image loading with caching
3. **Debouncing**: Use `ManagedTask.runDebounced` for search
4. **Background Refresh**: Don't block UI for network calls
5. **Memory**: Cancel tasks in `deinit`, use `[weak self]`

---

## Troubleshooting

### Common Issues

**"Cannot find type in scope"**: Ensure file is added to target
**UI not updating**: Check `@Published` and `@MainActor`
**Memory leak**: Check for retain cycles in closures
**Cache stale**: Call `store.invalidate*()` methods

### Debug Tools

- Xcode Memory Graph Debugger
- Console.app for structured logs
- Network Link Conditioner for offline testing

---

## Related Docs

- Project overview: `README.md`
- Local setup: `docs/LOCAL_DEVELOPMENT.md`
- Code review: `IOS_CODE_REVIEW.md`
