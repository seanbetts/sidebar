# Offline Support Improvements Plan

## Goal

Transform the iOS app from "cache-first read-only" to a robust offline-first architecture where users can confidently work offline without risk of data loss.

## Problem Statement

### Current State
The app has solid infrastructure for offline reads:
- `CachedStoreBase` implements cache-first loading pattern
- `CoreDataCacheClient` provides persistent TTL-based caching
- `NetworkMonitor` detects offline state
- `OfflineBanner` indicates offline mode
- Auto-refresh triggers on network reconnect

### Critical Gaps
1. **Write operations fail silently** - No queue, no retry, user's work is lost
2. **Chat messages in memory only** - `syncMessagesToStore(persist: false)` by default
3. **Note drafts not preserved** - Autosave to API fails silently, no local backup
4. **Upload tracking ephemeral** - `IngestionStore.localItems` lost on app restart
5. **No user feedback** - Users don't know if writes succeeded or are pending

### Risk Assessment
| Scenario | Current Behavior | User Impact |
|----------|-----------------|-------------|
| Edit note while offline | Save fails silently | **Work lost** |
| Send chat message offline | Optimistic UI, no persist | **Message lost on restart** |
| Upload file, app crashes | `localItems` cleared | **Upload lost** |
| Network drops mid-save | No retry | **Partial data loss** |

## Architecture Design

### Write Queue System

```
┌─────────────────────────────────────────────────────────────┐
│                      Write Queue Flow                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  User Action ──► Local Draft ──► Write Queue ──► API Call   │
│       │              │               │              │        │
│       │              ▼               ▼              ▼        │
│       │         CoreData        CoreData       Success?      │
│       │         (drafts)        (queue)           │          │
│       │                                           │          │
│       │              ◄───────────────────────────┘          │
│       │              Update UI with result                   │
│       ▼                                                      │
│  Optimistic UI                                               │
│  (immediate feedback)                                        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Core Data Model Extensions

```swift
// New entities for offline support

@objc(PendingWrite)
class PendingWrite: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var operationType: String  // "create", "update", "delete"
    @NSManaged var entityType: String     // "note", "message", "website", "file"
    @NSManaged var entityId: String?      // nil for creates
    @NSManaged var payload: Data          // JSON-encoded write data
    @NSManaged var createdAt: Date
    @NSManaged var attempts: Int16
    @NSManaged var lastAttemptAt: Date?
    @NSManaged var lastError: String?
    @NSManaged var status: String         // "pending", "inProgress", "failed"
}

@objc(LocalDraft)
class LocalDraft: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var entityType: String     // "note", "scratchpad"
    @NSManaged var entityId: String       // note ID or "scratchpad"
    @NSManaged var content: String
    @NSManaged var savedAt: Date
    @NSManaged var syncedAt: Date?        // nil if not yet synced
}
```

## Implementation Phases

### Phase 1: Write Queue Infrastructure

**Goal**: Build the foundation for queuing and retrying failed writes.

#### 1.1 Core Data Model

Add to `sideBar.xcdatamodeld`:

```xml
<!-- PendingWrite entity -->
<entity name="PendingWrite" representedClassName="PendingWrite">
    <attribute name="id" attributeType="UUID"/>
    <attribute name="operationType" attributeType="String"/>
    <attribute name="entityType" attributeType="String"/>
    <attribute name="entityId" optional="YES" attributeType="String"/>
    <attribute name="payload" attributeType="Binary"/>
    <attribute name="createdAt" attributeType="Date"/>
    <attribute name="attempts" attributeType="Integer 16" defaultValueString="0"/>
    <attribute name="lastAttemptAt" optional="YES" attributeType="Date"/>
    <attribute name="lastError" optional="YES" attributeType="String"/>
    <attribute name="status" attributeType="String" defaultValueString="pending"/>
</entity>
```

#### 1.2 WriteQueue Service

Create `Services/Offline/WriteQueue.swift`:

```swift
import Foundation
import CoreData

@MainActor
final class WriteQueue: ObservableObject {
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var isProcessing: Bool = false

    private let container: PersistenceContainer
    private let networkMonitor: NetworkMonitor
    private var processingTask: Task<Void, Never>?

    init(container: PersistenceContainer, networkMonitor: NetworkMonitor) {
        self.container = container
        self.networkMonitor = networkMonitor
        loadPendingCount()
        observeNetwork()
    }

    // MARK: - Enqueue Operations

    func enqueue<T: Encodable>(
        operation: WriteOperation,
        entityType: EntityType,
        entityId: String?,
        payload: T
    ) throws {
        let context = container.viewContext
        let write = PendingWrite(context: context)
        write.id = UUID()
        write.operationType = operation.rawValue
        write.entityType = entityType.rawValue
        write.entityId = entityId
        write.payload = try JSONEncoder().encode(payload)
        write.createdAt = Date()
        write.status = "pending"

        try context.save()
        pendingCount += 1

        // Attempt immediate processing if online
        if !networkMonitor.isOffline {
            processQueue()
        }
    }

    // MARK: - Queue Processing

    func processQueue() {
        guard !isProcessing, !networkMonitor.isOffline else { return }

        processingTask = Task {
            isProcessing = true
            defer { isProcessing = false }

            while let write = fetchNextPending() {
                await processWrite(write)

                // Small delay between writes to avoid hammering API
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            loadPendingCount()
        }
    }

    private func processWrite(_ write: PendingWrite) async {
        let context = container.viewContext

        write.status = "inProgress"
        write.attempts += 1
        write.lastAttemptAt = Date()
        try? context.save()

        do {
            try await executeWrite(write)
            context.delete(write)
            try? context.save()
        } catch {
            write.status = shouldRetry(write) ? "pending" : "failed"
            write.lastError = error.localizedDescription
            try? context.save()
        }
    }

    private func executeWrite(_ write: PendingWrite) async throws {
        // Route to appropriate API based on entityType
        // Implementation depends on specific write handlers
    }

    private func shouldRetry(_ write: PendingWrite) -> Bool {
        write.attempts < 5 // Max 5 attempts
    }

    private func fetchNextPending() -> PendingWrite? {
        let request = PendingWrite.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@", "pending")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PendingWrite.createdAt, ascending: true)]
        request.fetchLimit = 1
        return try? container.viewContext.fetch(request).first
    }

    private func loadPendingCount() {
        let request = PendingWrite.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@ OR status == %@", "pending", "failed")
        pendingCount = (try? container.viewContext.count(for: request)) ?? 0
    }

    private func observeNetwork() {
        // Process queue when coming back online
        networkMonitor.$isOffline
            .removeDuplicates()
            .filter { !$0 }
            .sink { [weak self] _ in
                self?.processQueue()
            }
            .store(in: &cancellables)
    }
}

enum WriteOperation: String {
    case create, update, delete
}

enum EntityType: String {
    case note, message, website, file, scratchpad
}
```

#### 1.3 Retry Strategy

Implement exponential backoff in `WriteQueue`:

```swift
private func backoffDelay(for attempt: Int) -> UInt64 {
    // Exponential backoff: 1s, 2s, 4s, 8s, 16s (max)
    let seconds = min(pow(2.0, Double(attempt - 1)), 16.0)
    return UInt64(seconds * 1_000_000_000)
}

private func processWrite(_ write: PendingWrite) async {
    // ... existing code ...

    if write.status == "pending" && write.attempts > 1 {
        // Wait before retry
        let delay = backoffDelay(for: Int(write.attempts))
        try? await Task.sleep(nanoseconds: delay)
    }
}
```

### Phase 2: Local Draft Persistence

**Goal**: Never lose user's work-in-progress content.

#### 2.1 Draft Storage

Create `Services/Offline/DraftStorage.swift`:

```swift
import Foundation
import CoreData

actor DraftStorage {
    private let container: PersistenceContainer

    init(container: PersistenceContainer) {
        self.container = container
    }

    func saveDraft(entityType: String, entityId: String, content: String) async throws {
        await MainActor.run {
            let context = container.viewContext

            // Upsert: find existing or create new
            let request = LocalDraft.fetchRequest()
            request.predicate = NSPredicate(
                format: "entityType == %@ AND entityId == %@",
                entityType, entityId
            )

            let draft = (try? context.fetch(request).first) ?? LocalDraft(context: context)
            draft.id = draft.id ?? UUID()
            draft.entityType = entityType
            draft.entityId = entityId
            draft.content = content
            draft.savedAt = Date()
            // Don't update syncedAt - that's set when successfully synced

            try? context.save()
        }
    }

    func getDraft(entityType: String, entityId: String) async -> String? {
        await MainActor.run {
            let context = container.viewContext
            let request = LocalDraft.fetchRequest()
            request.predicate = NSPredicate(
                format: "entityType == %@ AND entityId == %@",
                entityType, entityId
            )
            return try? context.fetch(request).first?.content
        }
    }

    func markSynced(entityType: String, entityId: String) async {
        await MainActor.run {
            let context = container.viewContext
            let request = LocalDraft.fetchRequest()
            request.predicate = NSPredicate(
                format: "entityType == %@ AND entityId == %@",
                entityType, entityId
            )
            if let draft = try? context.fetch(request).first {
                draft.syncedAt = Date()
                try? context.save()
            }
        }
    }

    func deleteDraft(entityType: String, entityId: String) async {
        await MainActor.run {
            let context = container.viewContext
            let request = LocalDraft.fetchRequest()
            request.predicate = NSPredicate(
                format: "entityType == %@ AND entityId == %@",
                entityType, entityId
            )
            if let draft = try? context.fetch(request).first {
                context.delete(draft)
                try? context.save()
            }
        }
    }

    func getUnsyncedDrafts() async -> [(entityType: String, entityId: String, content: String)] {
        await MainActor.run {
            let context = container.viewContext
            let request = LocalDraft.fetchRequest()
            request.predicate = NSPredicate(format: "syncedAt == nil")

            guard let drafts = try? context.fetch(request) else { return [] }
            return drafts.map { ($0.entityType, $0.entityId, $0.content) }
        }
    }
}
```

#### 2.2 Integrate with NotesEditorViewModel

Update `ViewModels/NotesEditorViewModel.swift`:

```swift
// Add property
private let draftStorage: DraftStorage

// Modify saveIfNeeded()
private func saveIfNeeded() async {
    guard isDirty, !isSaving else { return }
    isSaving = true
    defer { isSaving = false }

    let contentToSave = content

    // ALWAYS save locally first
    await draftStorage.saveDraft(
        entityType: "note",
        entityId: noteId,
        content: contentToSave
    )

    // Then attempt API save
    do {
        let updated = try await api.updateNote(id: noteId, content: contentToSave)
        notesStore.applyEditorUpdate(updated)
        await draftStorage.markSynced(entityType: "note", entityId: noteId)
        isDirty = false
    } catch {
        // Draft is safe locally - don't clear isDirty
        // Queue for retry
        try? writeQueue.enqueue(
            operation: .update,
            entityType: .note,
            entityId: noteId,
            payload: NoteUpdatePayload(content: contentToSave)
        )
    }
}

// Add draft recovery on load
func loadNote() async {
    // Check for unsynced local draft first
    if let localDraft = await draftStorage.getDraft(entityType: "note", entityId: noteId) {
        let serverNote = try? await api.getNote(id: noteId)

        if let serverNote, serverNote.updatedAt > (await draftStorage.getDraftDate(entityType: "note", entityId: noteId) ?? .distantPast) {
            // Server is newer - show conflict resolution UI
            showConflictResolution(local: localDraft, server: serverNote.content)
        } else {
            // Local draft is newer or server unavailable
            content = localDraft
            isDirty = true // Mark as needing sync
        }
    } else {
        // No local draft - load from server/cache as normal
        await loadFromServer()
    }
}
```

### Phase 3: Persistent Chat Messages

**Goal**: Chat messages survive app restarts.

#### 3.1 Message Persistence Strategy

Messages should be cached to CoreData, not just memory. Update `ChatStore`:

```swift
// In ChatStore.swift

func updateConversationMessages(
    id: String?,
    messages: [ChatMessage],
    persist: Bool = true  // Change default to true
) {
    guard let id else { return }

    // Update in-memory state
    if var conversation = conversations.first(where: { $0.id == id }) {
        conversation.messages = messages
        // ... update conversations array
    }

    // Persist to cache
    if persist {
        let cacheKey = CacheKeys.conversationMessages(id)
        cache.set(key: cacheKey, value: messages, ttlSeconds: CacheTTL.conversationMessages)
    }
}
```

#### 3.2 Add Message Cache Key

In `CacheKeys.swift`:

```swift
static func conversationMessages(_ id: String) -> String {
    "conversation_messages_\(id)"
}
```

In `CachePolicy.swift`:

```swift
static let conversationMessages: TimeInterval = 7 * 24 * 60 * 60 // 7 days
```

#### 3.3 Offline Message Queuing

Update `ChatViewModel+Conversations.swift`:

```swift
func sendMessage(_ text: String, attachments: [Attachment] = []) async {
    let tempId = UUID().uuidString
    let optimisticMessage = ChatMessage(
        id: tempId,
        role: .user,
        content: text,
        createdAt: Date(),
        isPending: true  // Add this flag to model
    )

    // Optimistic UI update
    messages.append(optimisticMessage)
    syncMessagesToStore(persist: true)  // Persist immediately

    // Queue the write
    let payload = MessagePayload(
        conversationId: activeConversationId,
        content: text,
        tempId: tempId,
        attachments: attachments.map { $0.id }
    )

    do {
        try writeQueue.enqueue(
            operation: .create,
            entityType: .message,
            entityId: nil,
            payload: payload
        )
    } catch {
        // Mark message as failed in UI
        if let index = messages.firstIndex(where: { $0.id == tempId }) {
            messages[index].isFailed = true
        }
    }
}
```

### Phase 4: Persistent Upload Tracking

**Goal**: File uploads resume after app restart.

#### 4.1 Persist localItems

Update `IngestionStore.swift`:

```swift
// Change from in-memory to UserDefaults-backed
private var localItemsKey = "ingestion_local_items"

private var localItems: [String: IngestionListItem] {
    get {
        guard let data = UserDefaults.standard.data(forKey: localItemsKey),
              let items = try? JSONDecoder().decode([String: IngestionListItem].self, from: data)
        else { return [:] }
        return items
    }
    set {
        let data = try? JSONEncoder().encode(newValue)
        UserDefaults.standard.set(data, forKey: localItemsKey)
    }
}

// Clean up completed uploads
func cleanupCompletedLocalItems() {
    var items = localItems
    let remoteIds = Set(self.items.map { $0.file.id })

    // Remove local items that now exist on server
    for (localId, _) in items {
        if remoteIds.contains(localId) {
            items.removeValue(forKey: localId)
        }
    }

    localItems = items
}
```

#### 4.2 Resume Uploads on Launch

In `AppEnvironment.swift`:

```swift
private func resumePendingUploads() {
    Task {
        await ingestionViewModel.resumePendingUploads()
    }
}
```

### Phase 5: Enhanced Offline UI

**Goal**: Users always know the sync status.

#### 5.1 Enhanced Offline Banner

Update `OfflineBanner.swift`:

```swift
struct OfflineBanner: View {
    @EnvironmentObject var writeQueue: WriteQueue
    @EnvironmentObject var networkMonitor: NetworkMonitor

    var body: some View {
        if networkMonitor.isOffline || writeQueue.pendingCount > 0 {
            HStack(spacing: 8) {
                if networkMonitor.isOffline {
                    Image(systemName: "wifi.slash")
                    Text("Offline")
                } else if writeQueue.isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Syncing...")
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }

                if writeQueue.pendingCount > 0 {
                    Text("• \(writeQueue.pendingCount) pending")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
    }
}
```

#### 5.2 Sync Status in Navigation

Add sync indicator to main navigation:

```swift
struct SyncStatusIndicator: View {
    @EnvironmentObject var writeQueue: WriteQueue

    var body: some View {
        if writeQueue.pendingCount > 0 {
            ZStack {
                Circle()
                    .fill(writeQueue.isProcessing ? .blue : .orange)
                    .frame(width: 8, height: 8)

                if writeQueue.isProcessing {
                    Circle()
                        .stroke(.blue.opacity(0.5), lineWidth: 2)
                        .frame(width: 12, height: 12)
                        .scaleEffect(pulseScale)
                        .animation(.easeInOut(duration: 1).repeatForever(), value: pulseScale)
                }
            }
        }
    }
}
```

#### 5.3 Failed Writes View

Create `Views/Settings/PendingWritesView.swift`:

```swift
struct PendingWritesView: View {
    @EnvironmentObject var writeQueue: WriteQueue
    @State private var pendingWrites: [PendingWrite] = []

    var body: some View {
        List {
            if pendingWrites.isEmpty {
                ContentUnavailableView(
                    "All Synced",
                    systemImage: "checkmark.circle",
                    description: Text("No pending changes")
                )
            } else {
                ForEach(pendingWrites, id: \.id) { write in
                    PendingWriteRow(write: write)
                }
                .onDelete(perform: deletePendingWrites)
            }
        }
        .navigationTitle("Pending Changes")
        .toolbar {
            if !pendingWrites.isEmpty {
                Button("Retry All") {
                    writeQueue.processQueue()
                }
            }
        }
        .task {
            pendingWrites = await writeQueue.fetchAllPending()
        }
    }
}

struct PendingWriteRow: View {
    let write: PendingWrite

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconForEntity(write.entityType))
                Text(titleForWrite(write))
                Spacer()
                StatusBadge(status: write.status)
            }

            if let error = write.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("Attempted \(write.attempts) time(s)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
```

### Phase 6: Conflict Resolution

**Goal**: Handle conflicts when local and server data diverge.

#### 6.1 Conflict Detection

```swift
enum SyncConflict {
    case localNewer(local: String, server: String, localDate: Date, serverDate: Date)
    case serverNewer(local: String, server: String, localDate: Date, serverDate: Date)
    case bothModified(local: String, server: String, localDate: Date, serverDate: Date)
}

func detectConflict(
    localContent: String,
    localDate: Date,
    serverContent: String,
    serverDate: Date
) -> SyncConflict? {
    guard localContent != serverContent else { return nil }

    if localDate > serverDate {
        return .localNewer(local: localContent, server: serverContent, localDate: localDate, serverDate: serverDate)
    } else if serverDate > localDate {
        return .serverNewer(local: localContent, server: serverContent, localDate: localDate, serverDate: serverDate)
    } else {
        return .bothModified(local: localContent, server: serverContent, localDate: localDate, serverDate: serverDate)
    }
}
```

#### 6.2 Conflict Resolution UI

```swift
struct ConflictResolutionSheet: View {
    let conflict: SyncConflict
    let onResolve: (ConflictResolution) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("This note was edited in multiple places")
                    .font(.headline)

                HStack(spacing: 16) {
                    VStack {
                        Text("Your Version")
                            .font(.subheadline.bold())
                        Text(conflict.localDate.formatted())
                            .font(.caption)
                        ScrollView {
                            Text(conflict.localContent)
                                .font(.body)
                        }
                        .frame(maxHeight: 200)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)

                        Button("Keep Mine") {
                            onResolve(.keepLocal)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    VStack {
                        Text("Server Version")
                            .font(.subheadline.bold())
                        Text(conflict.serverDate.formatted())
                            .font(.caption)
                        ScrollView {
                            Text(conflict.serverContent)
                                .font(.body)
                        }
                        .frame(maxHeight: 200)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)

                        Button("Keep Server") {
                            onResolve(.keepServer)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Button("Keep Both (Create Copy)") {
                    onResolve(.keepBoth)
                }
            }
            .padding()
            .navigationTitle("Resolve Conflict")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

enum ConflictResolution {
    case keepLocal
    case keepServer
    case keepBoth
}
```

## File Changes Summary

### New Files
| File | Purpose |
|------|---------|
| `Services/Offline/WriteQueue.swift` | Queue and retry failed writes |
| `Services/Offline/DraftStorage.swift` | Local draft persistence |
| `Views/Settings/PendingWritesView.swift` | UI for pending changes |
| `Views/Common/ConflictResolutionSheet.swift` | Conflict resolution UI |
| `Views/Common/SyncStatusIndicator.swift` | Navigation sync indicator |

### Modified Files
| File | Changes |
|------|---------|
| `sideBar.xcdatamodeld` | Add PendingWrite, LocalDraft entities |
| `Services/Cache/CacheKeys.swift` | Add message cache keys |
| `Services/Cache/CachePolicy.swift` | Add message TTL |
| `Stores/ChatStore.swift` | Default persist=true |
| `Stores/IngestionStore.swift` | Persist localItems to UserDefaults |
| `ViewModels/NotesEditorViewModel.swift` | Local draft save, conflict detection |
| `ViewModels/Chat/ChatViewModel+Conversations.swift` | Queue message writes |
| `App/AppEnvironment.swift` | Initialize WriteQueue, resume uploads |
| `Design/Components/OfflineBanner.swift` | Show pending count and sync status |

## Testing Strategy

### Unit Tests
- [ ] WriteQueue enqueue/dequeue operations
- [ ] Exponential backoff timing
- [ ] DraftStorage save/load/delete
- [ ] Conflict detection logic
- [ ] Cache key generation

### Integration Tests
- [ ] Note edit → offline → come online → syncs correctly
- [ ] Chat message → offline → restart app → message preserved
- [ ] File upload → app crash → restart → upload resumes
- [ ] Conflict resolution → both versions preserved

### Manual Testing Scenarios
1. **Airplane mode editing**: Edit note, toggle airplane mode, verify draft persists
2. **App kill during edit**: Force quit app mid-edit, relaunch, verify content
3. **Network flap**: Rapid online/offline, verify no duplicate writes
4. **Long offline session**: Stay offline 1 hour, make many edits, come online
5. **Conflict scenario**: Edit on web and iOS simultaneously, verify resolution UI

## Success Criteria

1. **Zero data loss**: User edits never lost, even with crashes/network issues
2. **Transparent sync**: Users see sync status without needing to understand details
3. **Graceful conflicts**: Conflicts detected and resolved with user choice
4. **Resumable uploads**: File uploads survive app restarts
5. **Performance**: No perceptible lag from offline infrastructure

## Rollout Plan

### Phase 1-2 (Foundation)
- WriteQueue + DraftStorage
- Critical path: note editing protected
- Feature flag: `offlineWriteQueue`

### Phase 3-4 (Full Coverage)
- Chat persistence + upload tracking
- All write operations queued
- Feature flag: `offlineFullCoverage`

### Phase 5-6 (Polish)
- Enhanced UI + conflict resolution
- Remove feature flags
- Production release

## Dependencies

- CoreData model migration (if modifying existing entities)
- No new external dependencies required
- Existing `NetworkMonitor` and `CacheClient` infrastructure reused

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| CoreData migration issues | Use lightweight migration, test thoroughly |
| Queue grows unbounded | Max queue size (100 items), oldest items warn user |
| Conflicting writes | Last-write-wins with conflict detection |
| Performance impact | Background processing, lazy loading |
| Storage bloat | Auto-cleanup synced drafts after 7 days |
