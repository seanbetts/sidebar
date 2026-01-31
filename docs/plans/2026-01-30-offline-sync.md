# Offline-First Data + Sync Plan (iOS)

Date: 2026-01-30
Owner: Codex
Status: Active (pivoted from 2026-01-22 plan; Phases 5–7 remaining)

## Goals
- Full offline experience for Notes, Tasks, Websites, Files, and Chat history (read-only offline for chat).
- Backend remains the single source of truth.
- Writes are queued offline and replayed on reconnect.
- Conflicts prompt user choice (server vs local).
- Consistent UX across all sections: cached data immediately, sync status, pending badges, conflict prompts.
- Keep implementations native to iOS/macOS patterns (Core Data, Background Tasks, Swift Concurrency, URLSession).

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
  - Uses native background task scheduling for periodic refresh

### Data Flow
- On app start: load offline snapshot -> show immediately -> background refresh if online.
- On mutation while offline: apply locally -> enqueue write -> mark pending.
- On reconnect: process queue in order -> refresh lists -> clear pending states.
- On realtime events: apply only if no local pending; otherwise mark conflict.
- Conflict trigger: compare server `updated_at`/`modified` to local snapshot at enqueue time. For tasks, use `TaskSyncResponse.conflicts` from `/tasks/sync`. Pause queue until resolved.
- Offline detection should use `ConnectivityMonitor.isOffline` (network + server reachability), not just `isNetworkAvailable`.

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
- Additional progress (2026-01-31):
  - Archived notes/websites list endpoints + summary metadata (`archived_count`, `archived_last_updated`).
  - Offline archived headers cached; recent archived content retained + prefetched for notes/websites.
  - Offline archived website detail shows placeholder when uncached (no hang).
  - Backend resilience complete (threadpool/fast-fail/slow query logging) and archived list pagination fixes.
  - `is_archived` columns added to notes/websites (websites uses backfilled boolean).
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
- Reuse `ConnectivityMonitor` + `AppEnvironment.refreshOnReconnect()` wiring; avoid adding a parallel network monitor.

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
  - Snapshot schema (JSON, Codable):
```
enum ServerSnapshotPayload: Codable, Equatable {
    case note(NoteSnapshot)
    case website(WebsiteSnapshot)
    case file(FileSnapshot)
}

struct ServerSnapshot: Codable, Equatable {
    let entityType: WriteEntityType
    let entityId: String
    let capturedAt: Date
    let payload: ServerSnapshotPayload
}

struct NoteSnapshot: Codable, Equatable {
    let modified: Double?
    let name: String?
    let path: String?
    let pinned: Bool?
    let pinnedOrder: Int?
    let archived: Bool?
}

struct WebsiteSnapshot: Codable, Equatable {
    let updatedAt: String?
    let title: String?
    let pinned: Bool?
    let pinnedOrder: Int?
    let archived: Bool?
}

struct FileSnapshot: Codable, Equatable {
    let filenameOriginal: String?
    let pinned: Bool?
    let pinnedOrder: Int?
    let path: String?
}
```
Comparison rules (conflict checks):
- Notes: compare current server `modified` to snapshot `modified`. If different -> conflict.
- Websites: compare current server `updated_at` to snapshot `updatedAt`. If different -> conflict.
- Files: compare current server fields (`filename_original`, `pinned`, `pinned_order`, `path`) to snapshot. Any difference -> conflict.
- Delete ops: if server record is already deleted, treat as success and drop the write.

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
Notes:
- Use Core Data background contexts for read/write; only deliver decoded results on the main actor.
- Set store protection to `NSFileProtectionCompleteUntilFirstUserAuthentication` for offline snapshots.
- Retention/size limits (defaults):
  - Notes: keep `notes/tree` always; keep latest 200 note bodies by `modified` (LRU by `updatedAt` fallback).
  - Tasks: keep all active tasks + counts; prune completed tasks older than 30 days from offline snapshots.
  - Websites: keep list snapshot + latest 500 detail records by `updatedAt`.
  - Files: keep list snapshot + latest 500 metadata records by `updatedAt` (no binary content).
  - Chat: keep latest 100 conversations; per-conversation keep last 7 days or 1,000 messages (whichever smaller) to align with `CachePolicy.conversationMessages`.
  - Drafts are handled by `DraftStorage` and are not pruned here.
- Prefer reusing existing `CacheKeys` for offline snapshot keys to keep identifiers consistent.

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
public struct SyncConflict<T: Codable & Equatable>: Codable, Equatable {
    public let entityId: String
    public let local: T
    public let server: T
    public let reason: String
}
```
Conflict rules (shared):
- Trigger on server `updated_at`/`modified` mismatch versus local snapshot at enqueue time.
- Tasks: rely on `TaskSyncResponse.conflicts` from `/tasks/sync`; `/tasks/apply` always returns an empty conflict list.
- Notes: use `modified` (timestamp) from note payload/tree.
- Websites: use `updated_at` from `website_summary` (list/detail responses).
- Files: ingestion responses do not include a file `updated_at` field (only `created_at` and job `updated_at`), so store a snapshot of relevant fields at enqueue time (e.g., `filename_original`, `pinned`, `pinned_order`) and compare against the latest `/files` response before applying queued writes.
- Store server snapshot in conflict payload to avoid re-fetch loops.
- Queue pauses until user resolves; resolution chooses server/local and replays if needed.

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
Current code notes:
- `WriteOperation` is currently `create/update/delete`, and `WriteEntityType` excludes `task` (add it).
- `WriteQueueExecutor` + `WriteQueue` are `@MainActor` and use `viewContext`; move heavy Core Data work to background contexts, keeping only published state updates on the main actor.

- Add queue cap + cleanup:
```
public var maxPendingWrites: Int { get }
public func pruneOldestWrites(keeping maxCount: Int)
```
Queue overflow policy (explicit):
- Default: block enqueue with a user-visible error ("Sync queue full") and link to `ios/sideBar/sideBar/Views/Settings/PendingWritesView.swift`.
- Allow user-initiated "Drop oldest" action to prune and retry enqueue.

- Add enqueue convenience methods (optional):
```
public func enqueueNoteUpdate(noteId: String, payload: NoteUpdateRequest) throws
public func enqueueTaskOperation(_ operation: TaskOperationPayload) throws
```

#### New: `ios/sideBar/sideBar/Services/Offline/CompositeWriteQueueExecutor.swift`
```
final class CompositeWriteQueueExecutor: WriteQueueExecutor {
    init(executors: [WriteEntityType: WriteQueueExecutor])
    func execute(write: PendingWrite) async throws
}
```
Notes:
- Executors should perform network work off the main actor; only UI state updates should be main-actor.

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

#### `ios/sideBar/sideBar/Stores/NotesStore.swift`
Add:
```
public func loadFromOffline() async
public func saveOfflineSnapshot() async
public func enqueueUpdate(noteId: String, content: String) async
public func resolveConflict(_ conflict: SyncConflict<NotePayload>, keepLocal: Bool) async
```

#### `ios/sideBar/sideBar/Stores/TasksStore.swift`
Add:
```
public func loadFromOffline() async
public func saveOfflineSnapshot() async
public func enqueueOperation(_ operation: TaskOperationPayload) async
public func resolveConflict(_ conflict: SyncConflict<TaskItem>, keepLocal: Bool) async
```

#### `ios/sideBar/sideBar/Stores/WebsitesStore.swift`
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

#### `ios/sideBar/sideBar/Stores/IngestionStore.swift`
Add:
```
public func loadFromOffline() async
public func saveOfflineSnapshot() async
public func enqueueRename(fileId: String, filename: String) async
public func enqueuePin(fileId: String, pinned: Bool) async
public func enqueueDelete(fileId: String) async
public func resolveConflict(_ conflict: SyncConflict<IngestedFileItem>, keepLocal: Bool) async
```
Note: `IngestionStore` already tracks `isOffline` based on API failures; ensure this aligns with `ConnectivityMonitor.isOffline`.

#### `ios/sideBar/sideBar/Stores/ChatStore.swift`
Add:
```
public func loadFromOffline() async
public func saveOfflineSnapshot() async
```

### 5) ViewModel Wiring

#### `ios/sideBar/sideBar/ViewModels/NotesViewModel.swift`
- Replace direct API calls with store methods.
- Expose `syncState` + conflicts.
- `NetworkStatusProviding` currently only exposes `isNetworkAvailable`; extend or inject `ConnectivityMonitor` where true offline state is needed.

#### `ios/sideBar/sideBar/ViewModels/TasksViewModel.swift`
- Use store for all mutations; queue when offline.
- Migrate current operations from `ios/sideBar/sideBar/ViewModels/TasksViewModel+Operations.swift` into `TasksStore`.

#### `ios/sideBar/sideBar/ViewModels/WebsitesViewModel.swift`
- Queue pin/rename/archive/delete while offline.
- Migrate direct API calls in `ios/sideBar/sideBar/ViewModels/WebsitesViewModel.swift` into `WebsitesStore`.

#### `ios/sideBar/sideBar/ViewModels/IngestionViewModel.swift`
- Queue file pin/rename/delete while offline.
- Migrate direct API calls in `ios/sideBar/sideBar/ViewModels/IngestionViewModel+Public.swift` into `IngestionStore`.

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
        stores: [SyncableStore]
    )
    func start()
    func refreshAll() async
}
```
Add a protocol:
```
public protocol SyncableStore: AnyObject {
    func loadFromOffline() async
    func saveOfflineSnapshot() async
    func refreshRemote() async
}
```
Native iOS/macOS background refresh:
- iOS: `BGTaskScheduler` for periodic refresh + enqueue processing.
- macOS: `NSBackgroundActivityScheduler` for periodic refresh + enqueue processing.
Implementation note:
- `AppEnvironment+Selection.refreshOnReconnect()` already performs multi-store refresh on reconnect; SyncCoordinator should replace or call into that logic rather than duplicating it.

#### `ios/sideBar/sideBar/App/AppEnvironment+Setup.swift`
- Instantiate `OfflineStore` and inject into Stores.
- Wire `WriteQueue` with `CompositeWriteQueueExecutor`.
- Start `SyncCoordinator`.
- Run queue pruning and draft cleanup at launch/foreground.
- Configure background tasks to call `SyncCoordinator.refreshAll()` when permitted.

### 7) UI Consistency

#### Update: `ios/sideBar/sideBar/Design/Components/OfflineBanner.swift`
- Extend existing banner (used by `ios/sideBar/sideBar/Design/Components/PanelHeader.swift` and `ios/sideBar/sideBar/Views/SiteHeaderBar.swift`) to show:
  - Offline (use `environment.isOffline` to include server-unreachable cases).
  - Syncing (`WriteQueue.isProcessing`).
  - Pending count (`WriteQueue.pendingCount`) and a link to `PendingWritesView`.
- Show banner when offline or pending changes exist (not only `!isNetworkAvailable`).

#### New: `ios/sideBar/sideBar/Views/Offline/ConflictResolutionSheet.swift`
- Standard conflict prompt with server vs local.
Note: Notes already use `NoteSyncConflict` + `Views/Notes/ConflictResolutionSheet.swift`; generalize that pattern instead of replacing it.

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

### Backend Workstream (recommended to improve offline sync quality)
- [x] Conflict-aware mutations (notes/websites/files): accept `client_updated_at`/`expected_version` (or `If-Match`) and return structured conflict payloads
- [x] Add `updated_at` to file list responses (avoid field-diff workaround)
- [x] Batch apply endpoints (notes/websites/files) to process queued ops with per-op results
- [x] Idempotency for creates (idempotency keys or client-generated IDs)
- [x] Conflict responses include server snapshot to avoid extra fetches
- [x] Soft-delete/tombstone fields included in list/sync responses for idempotent deletes
- Sequencing: completed before Phase 4 (2026-01-30)

### Phase 1: Core Offline Infrastructure
- Completed (prior work)
  - [x] `PendingWrite` Core Data entity
  - [x] `WriteQueue` enqueue/process + retry/backoff + reconnect processing
  - [x] `DraftStorage` Core Data drafts for notes
  - [x] Notes editor saves drafts and enqueues note updates
  - [x] Chat messages persisted to cache by default
  - [x] Upload tracking persisted + resume on launch

- [x] Add `OfflineEntry` entity to Core Data model
- [x] Add `OfflineStore`
- [x] Add `SyncState` + `SyncConflict`
- [x] Expand `WriteQueue` enums
- [x] Add `CompositeWriteQueueExecutor`
- [x] Add queue size cap + overflow handling (block vs confirm drop)
- [x] Add synced draft cleanup (folded from 2026-01-22 plan)
- [x] Align offline banner with syncing + pending count (folded from 2026-01-22 plan)
- [x] Implement conflict detection + resolution policy (updated_at/modified + task sync conflicts) (notes only so far)
- [x] Implement queue overflow UX (block + user-initiated drop oldest)
- [x] Implement snapshot retention/size limits + cleanup policy

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
   - Use Core Data background contexts for read/write; only deliver decoded results on the main actor.
   - Set store protection to `NSFileProtectionCompleteUntilFirstUserAuthentication` for offline snapshots.
   - Define retention/size limits per entity type (especially chat/files) and cleanup routines.
   - Status: done for notes/websites/files/conversations (counts), pending for task-specific pruning rules.

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
   - Conflict trigger: server `updated_at`/`modified` mismatch versus local snapshot at enqueue time.
   - Tasks: rely on `TaskSyncResponse.conflicts` as the source of truth.
   - Store server snapshot in conflict payload to avoid re-fetch loops.

4) WriteQueue expansion
   - Update `ios/sideBar/sideBar/Services/Offline/WriteQueue.swift`
     - Expand enums for tasks/websites/files operations.
     - Add `maxPendingWrites` (configurable, default 200).
     - Add `pruneOldestWrites(keeping:)` and call only after user confirms dropping oldest.
     - Preserve current coalescing behavior for note updates.
     - Move Core Data work off the main actor (background context) while keeping published state updates on main.
   - Method signatures:
```
public final class WriteQueue: ObservableObject {
    public let maxPendingWrites: Int
    public func pruneOldestWrites(keeping maxCount: Int)
}
```
   - Queue overflow policy: block enqueue with user-visible error, allow user-initiated "Drop oldest" to prune then retry.
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
final class CompositeWriteQueueExecutor: WriteQueueExecutor {
    init(executors: [WriteEntityType: WriteQueueExecutor])
    func execute(write: PendingWrite) async throws
}
```
   - Executors should perform network work off the main actor; only UI state updates should be main-actor.

6) Draft cleanup
   - Extend `ios/sideBar/sideBar/Services/Offline/DraftStorage.swift`
     - Add `cleanupSyncedDrafts(olderThan days: Int)` to delete old synced drafts.
     - Consider moving Core Data work to a background context.
   - Method signature:
```
public func cleanupSyncedDrafts(olderThan days: Int) throws
```
   - Default retention: 7 days (aligns with prior offline plan).

7) Offline banner alignment
   - Update existing offline banner and sync indicator to show:
     - Offline state
     - Syncing state (`WriteQueue.isProcessing`)
     - Pending count (`WriteQueue.pendingCount`)
   - Files: `ios/sideBar/sideBar/Design/Components/OfflineBanner.swift`,
     `ios/sideBar/sideBar/Design/Components/PanelHeader.swift`,
     `ios/sideBar/sideBar/Views/SiteHeaderBar.swift`

8) Wiring + initialization
   - Update `ios/sideBar/sideBar/App/AppEnvironment+Setup.swift`
     - Initialize `OfflineStore`.
     - Initialize `WriteQueue` with `CompositeWriteQueueExecutor`.
     - Call queue pruning + draft cleanup on launch/foreground.
     - Configure background tasks to call `SyncCoordinator.refreshAll()` when permitted.

#### Phase 1 Acceptance Checklist
- `OfflineEntry` persists and returns durable snapshots after app restart.
- `WriteQueue` refuses to grow beyond `maxPendingWrites`.
- Draft cleanup removes synced drafts older than N days without touching unsynced drafts.
- Offline banner shows: Offline, Syncing, Pending count (correct live values).
- `WriteQueue` still processes on reconnect and preserves note update coalescing.
- No regression in existing notes draft or conflict behavior.
- Conflict detection uses server `updated_at`/`modified` (tasks use `TaskSyncResponse.conflicts`) and pauses queue until resolution.
- Queue overflow behavior is user-visible (blocked or confirmed drop).
- Offline snapshot retention limits apply without deleting unsynced local data.

### Phase 2: Notes (template)
- [x] Extend `NotesStore` with offline snapshot + queue
- [x] Expand `NotesWriteQueueExecutor`
- [x] Update `NotesViewModel` to use store
- [x] Add basic conflict UX (already in notes; reuse for shared UI)

#### Phase 2 Detailed Task List (with file targets)
1) Notes store offline snapshot
   - Update `ios/sideBar/sideBar/Stores/NotesStore.swift`
   - Add methods:
```
public func loadFromOffline() async
public func saveOfflineSnapshot() async
```
   - Cache keys:
     - `notes/tree` -> `OfflineStore` snapshot
     - `notes/{id}` -> `OfflineStore` snapshot per note
   - Prefetch recent archived note bodies after archived tree refresh (retention window).
   - Status: done

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
   - Mark `syncState = .pending` in local cache and surface to UI. (pending)
   - Status: done (syncState pending)

3) Notes executor expansion
   - Update `ios/sideBar/sideBar/Services/Offline/NotesWriteQueueExecutor.swift`
   - Support: create, rename, move, pin, archive, delete + update. (create pending)
   - Status: partial (update/rename/move/pin/archive/delete)

4) Notes conflict handling
   - Use existing notes conflict UI; align with `SyncConflict` type.
   - Conflict source of truth: server `modified` timestamp vs local snapshot; store server snapshot in conflict payload.
   - Add:
```
public func resolveConflict(_ conflict: SyncConflict<NotePayload>, keepLocal: Bool) async
```
   - Status: partial (queue conflict detection for update/rename/move/pin/archive/delete; pending writes UI supports keep local/server)

#### Phase 2 Acceptance Checklist
- Notes tree + note content available offline after restart.
- All note edits queue while offline and sync when online.
- Conflicts prompt user with server vs local.


### Backend Detail (to fold into API work)
1) Conflict-aware mutations
   - Notes/Websites/Files: accept `client_updated_at` (or ETag/If-Match)
   - Return `409 Conflict` with a structured payload (server snapshot + reason)

2) File list schema
   - Add `updated_at` to `/files` list response items

3) Batch apply endpoints
   - Add `/notes/sync` and `/websites/sync` (or `/apply`) to accept queued ops
   - Response includes per-op success/failure/conflict, plus updated snapshots

4) Idempotency
   - Support `idempotency_key` (or client-generated IDs) for creates

5) Tombstones
   - Return `deleted_at` or `is_deleted` in list/sync responses so deletes are idempotent


### Phase 3: Tasks
- [x] Add `TasksWriteQueueExecutor`
- [x] Extend `TasksStore`
- [x] Update `TasksViewModel`

#### Phase 3 Detailed Task List (with file targets)
1) Tasks offline snapshot
   - Update `ios/sideBar/sideBar/Stores/TasksStore.swift`
   - Add:
```
public func loadFromOffline() async
public func saveOfflineSnapshot() async
```
   - Store full lists + counts in `OfflineStore`.
   - Persist `serverUpdatedSince` from `/tasks/sync` as `last_sync` in `OfflineStore`.

2) Tasks queued writes
   - Add:
```
public func enqueueOperation(_ operation: TaskOperationPayload) async
public func enqueueBatch(_ batch: TaskOperationBatch) async
```
   - Reuse existing `TaskOperationPayload` + `clientUpdatedAt` pattern from `ios/sideBar/sideBar/ViewModels/TasksViewModel+Operations.swift`.
   - For queued offline operations, prefer `/tasks/sync` (POST `/sync`) to apply outbox + receive conflicts/deltas.
   - Persist `last_sync` timestamp in `OfflineStore` (per user) to feed `/tasks/sync`.
   - Keep `/tasks/apply` for immediate online mutations where conflicts are handled optimistically.

3) Tasks executor
   - Add `ios/sideBar/sideBar/Services/Offline/TasksWriteQueueExecutor.swift`
   - Route write types to `TasksAPI`.

4) Tasks conflicts
   - Add conflict storage + resolution using `SyncConflict<TaskItem>`.

#### Phase 3 Acceptance Checklist
- Tasks lists + counts available offline.
- Task edits queue and sync.
- Conflicts prompt user.
- `/tasks/sync` returns conflicts when `client_updated_at` is stale and updates `serverUpdatedSince`.


### Phase 4: Websites + Files
- [x] Add `WebsitesWriteQueueExecutor`
- [x] Extend `WebsitesStore` for offline queued ops
- [x] Add `FilesWriteQueueExecutor`
- [x] Extend `IngestionStore`

#### Phase 4 Detailed Task List (with file targets)
1) Websites offline snapshot
   - Update `ios/sideBar/sideBar/Stores/WebsitesStore.swift`
   - Add:
```
public func loadFromOffline() async
public func saveOfflineSnapshot() async
```
   - Persist list + details in `OfflineStore`.
   - Prefetch recent archived website details after archived list refresh.
   - Show offline placeholder when an archived detail isn't cached yet.

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
   - Update `ios/sideBar/sideBar/Stores/IngestionStore.swift`
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
   - Since `/files` responses do not include file `updated_at`, store server snapshot fields in the queued write (`PendingWrite.serverSnapshot`) for conflict checks.

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
- Recent archived details are prefetched; uncached details show placeholder without hanging.


### Phase 5: Chat Offline History
- [x] Add offline snapshot to `ChatStore`
- [x] Update `ChatViewModel` to load offline when offline

#### Phase 5 Detailed Task List (with file targets)
1) Chat offline snapshots
   - Update `ios/sideBar/sideBar/Stores/ChatStore.swift`
   - Add:
```
public func loadFromOffline() async
public func saveOfflineSnapshot() async
```
   - Persist conversation list + messages in `OfflineStore`.
   - Status: done

2) Chat ViewModel wiring
   - Update `ios/sideBar/sideBar/ViewModels/Chat/ChatViewModel.swift`
   - Load offline messages when `ConnectivityMonitor.isOffline`.
   - Status: done (store-level offline fallback + cached checks)

#### Phase 5 Acceptance Checklist
- Conversation list + messages available offline after restart.
- No offline send/streaming; UI shows offline state.


### Phase 6: Sync Coordinator + Global UI
- [x] Add `SyncCoordinator`
- [x] Wire in `AppEnvironment+Setup`
- [x] Update `OfflineBanner`
- [x] Add global write conflict resolution sheet (notes keep dedicated resolver)

#### Phase 6 Detailed Task List (with file targets)
1) Sync coordinator
   - Add `ios/sideBar/sideBar/App/SyncCoordinator.swift` with:
```
@MainActor
final class SyncCoordinator {
    init(connectivityMonitor: ConnectivityMonitor, writeQueue: WriteQueue, stores: [SyncableStore])
    func start()
    func refreshAll() async
}
```
   - On reconnect: process queue then refresh lists.
   - Pause queue on conflict flag.
   - Schedule native background refresh (iOS `BGTaskScheduler`, macOS `NSBackgroundActivityScheduler`).
   - Status: done

2) Global UI elements
   - Update `ios/sideBar/sideBar/Design/Components/OfflineBanner.swift` (and usages in `PanelHeader`/`SiteHeaderBar`)
   - Add `ios/sideBar/sideBar/Views/Offline/WriteConflictResolutionSheet.swift`
   - Wire in common UI via `ContentView` / shared layout.
   - Status: done

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
- Queue overflow and conflict-trigger tests added.

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
