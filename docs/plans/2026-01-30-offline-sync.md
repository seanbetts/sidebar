# Offline-First Data + Sync Plan (iOS)

Date: 2026-01-30
Owner: Codex
Status: Active (pivoted from 2026-01-22 plan)

## Goals
- Full offline experience for Notes, Tasks, Websites, Files, and Chat history (read-only offline for chat).
- Backend remains the single source of truth.
- Writes are queued offline and replayed on reconnect.
- Conflicts prompt user choice (server vs local).
- Consistent UX across all sections: cached data immediately, sync status, pending badges, conflict prompts.

## Architecture Overview

### Visual Architecture Diagram
```
┌──────────────────────────────────────────────────────────────────────────┐
│                                 UI / Views                               │
│  NotesView • TasksView • WebsitesView • FilesView • ChatView              │
└───────────────────────────────▲──────────────────────────────────────────┘
                                │
                                │
┌───────────────────────────────┴──────────────────────────────────────────┐
│                             ViewModels                                   │
│  NotesViewModel • TasksViewModel • WebsitesViewModel • IngestionViewModel │
│  ChatViewModel • SettingsViewModel                                       │
└───────────────────────────────▲──────────────────────────────────────────┘
                                │
                                │
┌───────────────────────────────┴──────────────────────────────────────────┐
│                                 Stores                                   │
│  NotesStore • TasksStore • WebsitesStore • IngestionStore • ChatStore     │
│  - loadFromOffline()  - saveOfflineSnapshot()  - enqueue*()              │
│  - applyRealtimeEvent() - resolveConflict()                               │
└───────────────▲───────────────────────┬──────────────────────▲────────────┘
                │                       │                      │
                │                       │                      │
        ┌───────┴───────┐      ┌────────┴────────┐      ┌───────┴───────┐
        │ OfflineStore  │      │  WriteQueue     │      │  CacheClient  │
        │ (durable)     │      │ (PendingWrite)  │      │ (TTL)         │
        └───────▲───────┘      └────────▲────────┘      └───────▲───────┘
                │                       │                      │
                │                       │                      │
┌───────────────┴───────────────┐  ┌────┴─────────────────┐    │
│ CoreData OfflineEntry         │  │ Executors (Notes/     │    │
│ + Local Drafts                │  │ Tasks/Websites/Files) │    │
└───────────────────────────────┘  └──────────▲────────────┘    │
                                             │                 │
                                             │                 │
                                 ┌───────────┴──────────┐      │
                                 │ API Clients          │      │
                                 │ (Notes/Tasks/...)    │◄─────┘
                                 └───────────▲──────────┘
                                             │
                                             │
                                   ┌─────────┴───────────┐
                                   │ Backend API + DB    │
                                   │ (source of truth)   │
                                   └─────────────────────┘
```

### Layers
1) API Layer (unchanged)
- `Services/Network/*` remains the only place for network IO.

2) Store Layer (expand)
- Stores become repositories that own:
  - Offline snapshot load
  - Remote refresh
  - Apply realtime events
  - Local optimistic updates
  - Queueing offline writes
  - Conflict detection

3) Offline Cache Layer (new)
- Durable Core Data snapshots (non-expiring).
- Separate from TTL cache (`CoreDataCacheClient`) which is still used for fast short-lived fetches.

4) Write Queue Layer (expand existing)
- `WriteQueue` persists pending writes in Core Data and replays on reconnect.
- Add multi-entity executors + conflict surface.

5) Sync Coordinator (new)
- Single coordinator that:
  - Processes queue when online
  - Runs background refreshes on foreground/reconnect
  - Suspends queue on conflict

### Data Flow
- On app start: load offline snapshot -> show immediately -> background refresh if online.
- On mutation while offline: apply locally -> enqueue write -> mark pending.
- On reconnect: process queue in order -> refresh lists -> clear pending states.
- On realtime events: apply only if no local pending; otherwise mark conflict.

## File-by-File Change List (with method signatures)

## Current Progress (from 2026-01-22 plan)
- Implemented:
  - `PendingWrite` Core Data entity
  - `WriteQueue` enqueue/process + retry/backoff + reconnect processing
  - `DraftStorage` Core Data drafts for notes
  - Notes editor saves drafts and enqueues note updates
  - Chat message persistence to cache (default persist true)
  - Upload tracking persisted + resume on launch
  - Offline banner + pending writes view + conflict UI for notes
- Gaps to fold into Phase 1:
  - Queue size cap
  - Auto-cleanup of synced drafts
  - Syncing indicator / pending count alignment in banner

## Pivot Guidance (for AI coding agent)
Use and extend existing infrastructure rather than replacing it:
- Keep `WriteQueue` and `PendingWrite` Core Data entity; expand enums and executors.
- Keep `DraftStorage`; add cleanup API and call site.
- Keep notes conflict flow; generalize types/UI for reuse in other sections.
- Do not re-implement chat offline queueing (out of scope).
- Use `CoreDataCacheClient` for TTL cache only; add `OfflineStore` for durable snapshots.
- Prefer Store-level APIs for offline load + queued writes; avoid adding business logic to ViewModels.

### 1) Persistence + Offline Cache

#### `ios/sideBar/sideBar/SideBarCache.xcdatamodeld`
Add entity `OfflineEntry`:
- `id: UUID`
- `key: String`
- `payload: Data`
- `entityType: String`
- `updatedAt: Date`
- `lastSyncAt: Date?`

Optional: extend `PendingWrite` with:
- `conflictReason: String?`
- `serverSnapshot: Data?` (for conflict prompt)

#### `ios/sideBar/sideBar/Services/Persistence/PersistenceController.swift`
- Ensure migration works (lightweight by default).

#### New: `ios/sideBar/sideBar/Services/Offline/OfflineStore.swift`
```
@MainActor
public final class OfflineStore {
    public init(container: NSPersistentContainer)
    public func get<T: Decodable>(key: String, as type: T.Type) -> T?
    public func set<T: Encodable>(key: String, entityType: String, value: T, lastSyncAt: Date?)
    public func getAll<T: Decodable>(keyPrefix: String, as type: T.Type) -> [T]
    public func lastSyncAt(for key: String) -> Date?
    public func remove(key: String)
}
```

### 2) Sync State + Conflict Types

#### New: `ios/sideBar/sideBar/Services/Offline/SyncState.swift`
```
public enum SyncState: String, Codable {
    case synced
    case pending
    case conflict
}
```

#### New: `ios/sideBar/sideBar/Services/Offline/SyncConflict.swift`
```
public struct SyncConflict<T: Codable>: Codable, Equatable {
    public let entityId: String
    public let local: T
    public let server: T
    public let reason: String
}
```

### 3) Write Queue Expansion

#### `ios/sideBar/sideBar/Services/Offline/WriteQueue.swift`
- Extend enums:
```
enum WriteOperation: String {
    case create
    case update
    case delete
    case rename
    case pin
    case archive
    case move
    case copy
}

enum WriteEntityType: String {
    case note
    case task
    case website
    case file
    case message
    case scratchpad
}
```

- Add queue cap + cleanup:
```
public var maxPendingWrites: Int { get }
public func pruneOldestWrites(keeping maxCount: Int)
```

- Add enqueue convenience methods (optional):
```
public func enqueueNoteUpdate(noteId: String, payload: NoteUpdateRequest) throws
public func enqueueTaskUpdate(taskId: String, payload: TaskUpdateRequest) throws
```

#### New: `ios/sideBar/sideBar/Services/Offline/CompositeWriteQueueExecutor.swift`
```
@MainActor
final class CompositeWriteQueueExecutor: WriteQueueExecutor {
    init(executors: [WriteEntityType: WriteQueueExecutor])
    func execute(write: PendingWrite) async throws
}
```

#### New: `ios/sideBar/sideBar/Services/Offline/TasksWriteQueueExecutor.swift`
```
final class TasksWriteQueueExecutor: WriteQueueExecutor {
    init(api: TasksProviding, store: TasksStore)
    func execute(write: PendingWrite) async throws
}
```

#### New: `ios/sideBar/sideBar/Services/Offline/WebsitesWriteQueueExecutor.swift`
```
final class WebsitesWriteQueueExecutor: WriteQueueExecutor {
    init(api: WebsitesProviding, store: WebsitesStore)
    func execute(write: PendingWrite) async throws
}
```

#### New: `ios/sideBar/sideBar/Services/Offline/FilesWriteQueueExecutor.swift`
```
final class FilesWriteQueueExecutor: WriteQueueExecutor {
    init(api: IngestionProviding, store: IngestionStore)
    func execute(write: PendingWrite) async throws
}
```

#### `ios/sideBar/sideBar/Services/Offline/NotesWriteQueueExecutor.swift`
- Expand to handle create/rename/move/pin/archive/delete in addition to update.

#### `ios/sideBar/sideBar/Services/Offline/DraftStorage.swift`
- Add cleanup for synced drafts:
```
public func cleanupSyncedDrafts(olderThan days: Int) throws
```

### 4) Store Layer Changes

(Exact store paths may vary; update these files where they exist in your repo.)

#### `ios/sideBar/sideBar/Services/Notes/NotesStore.swift`
Add:
```
public func loadFromOffline() async
public func saveOfflineSnapshot() async
public func enqueueUpdate(noteId: String, content: String) async
public func resolveConflict(_ conflict: SyncConflict<NotePayload>, keepLocal: Bool) async
```

#### `ios/sideBar/sideBar/Services/Tasks/TasksStore.swift`
Add:
```
public func loadFromOffline() async
public func saveOfflineSnapshot() async
public func enqueueUpdate(taskId: String, payload: TaskUpdateRequest) async
public func resolveConflict(_ conflict: SyncConflict<TaskItem>, keepLocal: Bool) async
```

#### `ios/sideBar/sideBar/Services/Websites/WebsitesStore.swift`
Add:
```
public func loadFromOffline() async
public func saveOfflineSnapshot() async
public func enqueueRename(id: String, title: String) async
public func enqueuePin(id: String, pinned: Bool) async
public func enqueueArchive(id: String, archived: Bool) async
public func enqueueDelete(id: String) async
public func resolveConflict(_ conflict: SyncConflict<WebsiteItem>, keepLocal: Bool) async
```

#### `ios/sideBar/sideBar/Services/Ingestion/IngestionStore.swift`
Add:
```
public func loadFromOffline() async
public func saveOfflineSnapshot() async
public func enqueueRename(fileId: String, filename: String) async
public func enqueuePin(fileId: String, pinned: Bool) async
public func enqueueDelete(fileId: String) async
public func resolveConflict(_ conflict: SyncConflict<IngestedFileItem>, keepLocal: Bool) async
```

#### `ios/sideBar/sideBar/Services/Chat/ChatStore.swift`
Add:
```
public func loadFromOffline() async
public func saveOfflineSnapshot() async
```

### 5) ViewModel Wiring

#### `ios/sideBar/sideBar/ViewModels/NotesViewModel.swift`
- Replace direct API calls with store methods.
- Expose `syncState` + conflicts.

#### `ios/sideBar/sideBar/ViewModels/TasksViewModel.swift`
- Use store for all mutations; queue when offline.

#### `ios/sideBar/sideBar/ViewModels/WebsitesViewModel.swift`
- Queue pin/rename/archive/delete while offline.

#### `ios/sideBar/sideBar/ViewModels/IngestionViewModel.swift`
- Queue file pin/rename/delete while offline.

#### `ios/sideBar/sideBar/ViewModels/Chat/ChatViewModel.swift`
- Read from offline snapshots when offline.

### 6) Sync Coordinator + App Wiring

#### New: `ios/sideBar/sideBar/App/SyncCoordinator.swift`
```
@MainActor
final class SyncCoordinator {
    init(
        connectivityMonitor: ConnectivityMonitor,
        writeQueue: WriteQueue,
        stores: [AnyObject]
    )
    func start()
    func refreshAll() async
}
```

#### `ios/sideBar/sideBar/App/AppEnvironment+Setup.swift`
- Instantiate `OfflineStore` and inject into Stores.
- Wire `WriteQueue` with `CompositeWriteQueueExecutor`.
- Start `SyncCoordinator`.
- Run queue pruning and draft cleanup at launch/foreground.

### 7) UI Consistency

#### New: `ios/sideBar/sideBar/Views/Offline/SyncStatusBanner.swift`
- Shows offline/syncing/pending count.

#### New: `ios/sideBar/sideBar/Views/Offline/ConflictResolutionSheet.swift`
- Standard conflict prompt with server vs local.

#### Update section views to show:
- Pending badge if `syncState == .pending`.
- Conflict badge + prompt if `syncState == .conflict`.

### 8) Tests

Add tests in `ios/sideBar/sideBarTests/`:
- `OfflineStoreTests.swift`
- `WriteQueueExecutorTests.swift` (notes/tasks/websites/files)
- `StoreOfflineLoadTests.swift`
- `ConflictResolutionTests.swift`

## Progress Tracking

### Phase 1: Core Offline Infrastructure
- Completed (prior work)
  - [x] `PendingWrite` Core Data entity
  - [x] `WriteQueue` enqueue/process + retry/backoff + reconnect processing
  - [x] `DraftStorage` Core Data drafts for notes
  - [x] Notes editor saves drafts and enqueues note updates
  - [x] Chat messages persisted to cache by default
  - [x] Upload tracking persisted + resume on launch

- [ ] Add `OfflineEntry` entity to Core Data model
- [ ] Add `OfflineStore`
- [ ] Add `SyncState` + `SyncConflict`
- [ ] Expand `WriteQueue` enums
- [ ] Add `CompositeWriteQueueExecutor`
- [ ] Add queue size cap + pruning (folded from 2026-01-22 plan)
- [ ] Add synced draft cleanup (folded from 2026-01-22 plan)
- [ ] Align offline banner with syncing + pending count (folded from 2026-01-22 plan) (in progress)

#### Phase 1 Detailed Task List (with file targets)
1) Core Data model updates
   - Update `ios/sideBar/sideBar/SideBarCache.xcdatamodeld`
     - Add `OfflineEntry` entity (id, key, payload, entityType, updatedAt, lastSyncAt)
     - Optional: add `conflictReason`/`serverSnapshot` to `PendingWrite` if needed
   - Verify `PersistenceController` supports lightweight migration:
     - `ios/sideBar/sideBar/Services/Persistence/PersistenceController.swift`

2) OfflineStore (durable snapshots)
   - Add new file: `ios/sideBar/sideBar/Services/Offline/OfflineStore.swift`
   - Provide CRUD APIs for snapshot read/write and lastSyncAt tracking.
   - Use Core Data `OfflineEntry` entity; do not use TTL.
   - Method signatures:
```
@MainActor
public final class OfflineStore {
    public init(container: NSPersistentContainer)
    public func get<T: Decodable>(key: String, as type: T.Type) -> T?
    public func getAll<T: Decodable>(keyPrefix: String, as type: T.Type) -> [T]
    public func set<T: Encodable>(key: String, entityType: String, value: T, lastSyncAt: Date?)
    public func lastSyncAt(for key: String) -> Date?
    public func remove(key: String)
}
```

3) Sync state + conflict types
   - Add:
     - `ios/sideBar/sideBar/Services/Offline/SyncState.swift`
     - `ios/sideBar/sideBar/Services/Offline/SyncConflict.swift`
   - Ensure models can store `syncState` for UI badges and `SyncConflict` payloads.
   - Method signatures:
```
public enum SyncState: String, Codable { case synced, pending, conflict }

public struct SyncConflict<T: Codable & Equatable>: Codable, Equatable {
    public let entityId: String
    public let local: T
    public let server: T
    public let reason: String
}
```

4) WriteQueue expansion
   - Update `ios/sideBar/sideBar/Services/Offline/WriteQueue.swift`
     - Expand enums for tasks/websites/files operations.
     - Add `maxPendingWrites` (configurable, default 200).
     - Add `pruneOldestWrites(keeping:)` and call on enqueue.
     - Preserve current coalescing behavior for note updates.
   - Method signatures:
```
public final class WriteQueue: ObservableObject {
    public let maxPendingWrites: Int
    public func pruneOldestWrites(keeping maxCount: Int)
}
```
   - Enum updates:
```
enum WriteOperation: String { case create, update, delete, rename, pin, archive, move, copy }
enum WriteEntityType: String { case note, task, website, file, message, scratchpad }
```

5) Composite executor scaffolding
   - Add `ios/sideBar/sideBar/Services/Offline/CompositeWriteQueueExecutor.swift`
   - No business logic here; just route by `entityType`.
   - Method signatures:
```
@MainActor
final class CompositeWriteQueueExecutor: WriteQueueExecutor {
    init(executors: [WriteEntityType: WriteQueueExecutor])
    func execute(write: PendingWrite) async throws
}
```

6) Draft cleanup
   - Extend `ios/sideBar/sideBar/Services/Offline/DraftStorage.swift`
     - Add `cleanupSyncedDrafts(olderThan days: Int)` to delete old synced drafts.
   - Method signature:
```
public func cleanupSyncedDrafts(olderThan days: Int) throws
```

7) Offline banner alignment
   - Update existing offline banner and sync indicator to show:
     - Offline state
     - Syncing state (`WriteQueue.isProcessing`)
     - Pending count (`WriteQueue.pendingCount`)
   - Files likely: `ios/sideBar/sideBar/Views/...` (existing OfflineBanner + header)

8) Wiring + initialization
   - Update `ios/sideBar/sideBar/App/AppEnvironment+Setup.swift`
     - Initialize `OfflineStore`.
     - Initialize `WriteQueue` with `CompositeWriteQueueExecutor`.
     - Call queue pruning + draft cleanup on launch/foreground.

#### Phase 1 Acceptance Checklist
- `OfflineEntry` persists and returns durable snapshots after app restart.
- `WriteQueue` refuses to grow beyond `maxPendingWrites` and prunes oldest.
- Draft cleanup removes synced drafts older than N days without touching unsynced drafts.
- Offline banner shows: Offline, Syncing, Pending count (correct live values).
- `WriteQueue` still processes on reconnect and preserves note update coalescing.
- No regression in existing notes draft or conflict behavior.

### Phase 2: Notes (template)
- [ ] Extend `NotesStore` with offline snapshot + queue
- [ ] Expand `NotesWriteQueueExecutor`
- [ ] Update `NotesViewModel` to use store
- [x] Add basic conflict UX (already in notes; reuse for shared UI)

#### Phase 2 Detailed Task List (with file targets)
1) Notes store offline snapshot
   - Update `ios/sideBar/sideBar/Services/Notes/NotesStore.swift` (or actual path)
   - Add methods:
```
public func loadFromOffline() async
public func saveOfflineSnapshot() async
```
   - Cache keys:
     - `notes/tree` -> `OfflineStore` snapshot
     - `notes/{id}` -> `OfflineStore` snapshot per note

2) Notes store queued writes
   - Add queue APIs:
```
public func enqueueUpdate(noteId: String, content: String) async
public func enqueueRename(noteId: String, newName: String) async
public func enqueueMove(noteId: String, folder: String) async
public func enqueuePin(noteId: String, pinned: Bool) async
public func enqueueArchive(noteId: String, archived: Bool) async
public func enqueueDelete(noteId: String) async
```
   - Mark `syncState = .pending` in local cache and surface to UI.

3) Notes executor expansion
   - Update `ios/sideBar/sideBar/Services/Offline/NotesWriteQueueExecutor.swift`
   - Support: create, rename, move, pin, archive, delete + update.

4) Notes conflict handling
   - Use existing notes conflict UI; align with `SyncConflict` type.
   - Add:
```
public func resolveConflict(_ conflict: SyncConflict<NotePayload>, keepLocal: Bool) async
```

#### Phase 2 Acceptance Checklist
- Notes tree + note content available offline after restart.
- All note edits queue while offline and sync when online.
- Conflicts prompt user with server vs local.


### Phase 3: Tasks
- [ ] Add `TasksWriteQueueExecutor`
- [ ] Extend `TasksStore`
- [ ] Update `TasksViewModel`

#### Phase 3 Detailed Task List (with file targets)
1) Tasks offline snapshot
   - Update `ios/sideBar/sideBar/Services/Tasks/TasksStore.swift`
   - Add:
```
public func loadFromOffline() async
public func saveOfflineSnapshot() async
```
   - Store full lists + counts in `OfflineStore`.

2) Tasks queued writes
   - Add:
```
public func enqueueCreateTask(payload: TaskCreateRequest) async
public func enqueueUpdateTask(taskId: String, payload: TaskUpdateRequest) async
public func enqueueComplete(taskId: String, completed: Bool) async
public func enqueueDelete(taskId: String) async
```

3) Tasks executor
   - Add `ios/sideBar/sideBar/Services/Offline/TasksWriteQueueExecutor.swift`
   - Route write types to `TasksAPI`.

4) Tasks conflicts
   - Add conflict storage + resolution using `SyncConflict<TaskItem>`.

#### Phase 3 Acceptance Checklist
- Tasks lists + counts available offline.
- Task edits queue and sync.
- Conflicts prompt user.


### Phase 4: Websites + Files
- [ ] Add `WebsitesWriteQueueExecutor`
- [ ] Extend `WebsitesStore` for offline queued ops
- [ ] Add `FilesWriteQueueExecutor`
- [ ] Extend `IngestionStore`

#### Phase 4 Detailed Task List (with file targets)
1) Websites offline snapshot
   - Update `ios/sideBar/sideBar/Services/Websites/WebsitesStore.swift`
   - Add:
```
public func loadFromOffline() async
public func saveOfflineSnapshot() async
```
   - Persist list + details in `OfflineStore`.

2) Websites queued writes (offline)
   - Add:
```
public func enqueueRename(id: String, title: String) async
public func enqueuePin(id: String, pinned: Bool) async
public func enqueueArchive(id: String, archived: Bool) async
public func enqueueDelete(id: String) async
```
   - Copy action is local only (clipboard); no queue.

3) Websites executor
   - Add `ios/sideBar/sideBar/Services/Offline/WebsitesWriteQueueExecutor.swift`
   - Route ops to `WebsitesAPI`.

4) Files offline snapshot
   - Update `ios/sideBar/sideBar/Services/Ingestion/IngestionStore.swift`
   - Add:
```
public func loadFromOffline() async
public func saveOfflineSnapshot() async
```
   - Persist list + meta in `OfflineStore`.

5) Files queued writes (offline)
   - Add:
```
public func enqueueRename(fileId: String, filename: String) async
public func enqueuePin(fileId: String, pinned: Bool) async
public func enqueueDelete(fileId: String) async
```
   - Copy action is local only unless server duplication is required later.

6) Files executor
   - Add `ios/sideBar/sideBar/Services/Offline/FilesWriteQueueExecutor.swift`
   - Route ops to `IngestionAPI`.

7) Conflicts
   - Use `SyncConflict<WebsiteItem>` and `SyncConflict<IngestedFileItem>`.

#### Phase 4 Acceptance Checklist
- Websites and files fully viewable offline.
- Pin/rename/archive/delete for websites queues offline and syncs.
- Pin/rename/delete for files queues offline and syncs.
- Conflicts prompt user.


### Phase 5: Chat Offline History
- [ ] Add offline snapshot to `ChatStore`
- [ ] Update `ChatViewModel` to load offline when offline

#### Phase 5 Detailed Task List (with file targets)
1) Chat offline snapshots
   - Update `ios/sideBar/sideBar/Stores/ChatStore.swift`
   - Add:
```
public func loadFromOffline() async
public func saveOfflineSnapshot() async
```
   - Persist conversation list + messages in `OfflineStore`.

2) Chat ViewModel wiring
   - Update `ios/sideBar/sideBar/ViewModels/Chat/ChatViewModel.swift`
   - Load offline messages when `ConnectivityMonitor.isOffline`.

#### Phase 5 Acceptance Checklist
- Conversation list + messages available offline after restart.
- No offline send/streaming; UI shows offline state.


### Phase 6: Sync Coordinator + Global UI
- [ ] Add `SyncCoordinator`
- [ ] Wire in `AppEnvironment+Setup`
- [ ] Add `SyncStatusBanner`
- [x] Add `ConflictResolutionSheet` (notes-only, needs generalization)

#### Phase 6 Detailed Task List (with file targets)
1) Sync coordinator
   - Add `ios/sideBar/sideBar/App/SyncCoordinator.swift` with:
```
@MainActor
final class SyncCoordinator {
    init(connectivityMonitor: ConnectivityMonitor, writeQueue: WriteQueue, stores: [AnyObject])
    func start()
    func refreshAll() async
}
```
   - On reconnect: process queue then refresh lists.
   - Pause queue on conflict flag.

2) Global UI elements
   - Add `ios/sideBar/sideBar/Views/Offline/SyncStatusBanner.swift`
   - Add `ios/sideBar/sideBar/Views/Offline/ConflictResolutionSheet.swift`
   - Wire in common UI via `ContentView` / shared layout.

#### Phase 6 Acceptance Checklist
- SyncCoordinator refreshes all stores on reconnect.
- Global banner + conflict sheet consistent across sections.


### Phase 7: Tests + Cleanup
- [ ] Add store + executor tests
- [ ] Add conflict resolution tests
- [ ] Ensure no debug prints

#### Phase 7 Detailed Task List (with file targets)
1) Tests
   - Add under `ios/sideBar/sideBarTests/`:
     - `OfflineStoreTests.swift`
     - `WriteQueueExecutorTests.swift`
     - `StoreOfflineLoadTests.swift`
     - `ConflictResolutionTests.swift`

2) Cleanup
   - Remove any temporary logging or debug flags.

#### Phase 7 Acceptance Checklist
- Tests cover offline load, queued writes, conflicts.
- No lingering debug output.

## Comprehensive Manual Test Checklist (End-to-End)

### Global
- Toggle offline/online: banner updates, sync indicator correct.
- App restart while offline: cached data is visible across all sections.
- Queue size cap: attempt > cap writes, verify oldest pruned with user feedback if needed.
- Draft cleanup: synced drafts older than N days are removed, unsynced drafts remain.

### Notes
- Create/edit/move/rename/pin/archive/delete offline; changes appear locally.
- Reconnect: queued notes sync and resolve without data loss.
- Conflict scenario: edit same note on another device, resolve via prompt.

### Tasks
- Create/edit/complete/delete offline; counts update locally.
- Reconnect: queued tasks sync; conflicts prompt.

### Websites
- Offline pin/rename/archive/delete; list reflects change locally.
- Reconnect: queued website changes sync.
- Copy action offline works (clipboard/local only).

### Files
- Offline pin/rename/delete; list reflects change locally.
- Reconnect: queued file changes sync.
- Copy action offline works (clipboard/local only).

### Chat
- Offline: conversations and messages are readable.
- Offline: sending is disabled or shows offline error.
- Reconnect: chat resumes streaming.

### Uploads / Ingestion
- Start upload, force quit, relaunch: upload resumes.
- Offline: uploads are prevented with clear messaging.

### Realtime Interaction
- While online, realtime updates appear without wiping pending local changes.

## Open Questions / Assumptions
- Copy operation: currently assumed local (clipboard) only. If server-side duplication is required, add queue op.
- Conflicts for note content: provide “merge” only for text content; other fields use choose-server/choose-local.
- Stores file paths may differ; update plan to actual files when implementing.
