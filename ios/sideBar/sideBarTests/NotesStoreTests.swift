import CoreData
import Foundation
import sideBarShared
import XCTest
@testable import sideBar

@MainActor
final class NotesStoreTests: XCTestCase {
    func testLoadTreeUsesCacheThenRefreshes() async {
        let cached = FileTree(children: [
            FileNode(
                name: "Cached",
                path: "/cached.md",
                type: .file,
                size: 1,
                modified: 1,
                created: nil,
                children: nil,
                expanded: nil,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: nil
            )
        ])
        let fresh = FileTree(children: [
            FileNode(
                name: "Fresh",
                path: "/fresh.md",
                type: .file,
                size: 2,
                modified: 2,
                created: nil,
                children: nil,
                expanded: nil,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: nil
            )
        ])
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.notesTree, value: cached, ttlSeconds: 60)
        let api = MockNotesAPI(treeResult: .success(fresh), noteResult: .failure(MockError.forced))
        api.listDelay = 0.05
        let listExpectation = expectation(description: "tree refresh")
        api.onList = {
            listExpectation.fulfill()
        }
        let store = NotesStore(api: api, cache: cache)

        try? await store.loadTree()

        XCTAssertEqual(store.tree?.children.first?.name, "Cached")
        await fulfillment(of: [listExpectation], timeout: 1.0)
        XCTAssertEqual(store.tree?.children.first?.name, "Fresh")
    }

    func testApplyRealtimeDeleteClearsActiveAndCache() async {
        let note = NotePayload(id: "n1", name: "Note", content: "Body", path: "/note.md", modified: 1, created: nil)
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.note(id: "n1"), value: note, ttlSeconds: 60)
        let api = MockNotesAPI(treeResult: .failure(MockError.forced), noteResult: .failure(MockError.forced))
        let store = NotesStore(api: api, cache: cache)
        store.applyEditorUpdate(note)

        let payload = RealtimePayload<NoteRealtimeRecord>(
            eventType: .delete,
            table: RealtimeTable.notes,
            schema: "public",
            record: nil,
            oldRecord: NoteRealtimeRecord(
                id: "n1",
                title: nil,
                document: nil,
                documentVersion: nil,
                plainText: nil,
                metadata: nil,
                updatedAt: nil,
                deletedAt: nil
            )
        )

        await store.applyRealtimeEvent(payload)

        XCTAssertNil(store.activeNote)
        let cached: NotePayload? = cache.get(key: CacheKeys.note(id: "n1"))
        XCTAssertNil(cached)
    }

    func testLoadTreeUsesOfflineStoreWhenCacheMissing() async {
        let offlineTree = FileTree(children: [
            FileNode(
                name: "Offline",
                path: "/offline.md",
                type: .file,
                size: nil,
                modified: nil,
                created: nil,
                children: nil,
                expanded: nil,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: nil
            )
        ])
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        offlineStore.set(key: CacheKeys.notesTree, entityType: "notesTree", value: offlineTree, lastSyncAt: nil)
        let api = MockNotesAPI(treeResult: .failure(MockError.forced), noteResult: .failure(MockError.forced))
        let cache = TestCacheClient()
        let store = NotesStore(
            api: api,
            cache: cache,
            offlineStore: offlineStore,
            networkStatus: TestNetworkStatus(isNetworkAvailable: false)
        )

        try? await store.loadTree()

        XCTAssertEqual(store.tree?.children.first?.name, "Offline")
    }

    func testArchivedNoteOlderThanRetentionDoesNotPersist() async {
        let archivedNode = FileNode(
            name: "Archived.md",
            path: "n1",
            type: .file,
            size: nil,
            modified: nil,
                created: nil,
            children: nil,
            expanded: nil,
            pinned: nil,
            pinnedOrder: nil,
            archived: true,
            folderMarker: nil
        )
        let tree = FileTree(children: [archivedNode])
        let cache = TestCacheClient()
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let api = MockNotesAPI(treeResult: .failure(MockError.forced), noteResult: .failure(MockError.forced))
        let store = NotesStore(api: api, cache: cache, offlineStore: offlineStore)
        store.applyTreeUpdate(tree, persist: false)

        let oldDate = Date().addingTimeInterval(-8 * 24 * 60 * 60).timeIntervalSince1970
        let note = NotePayload(id: "n1", name: "Archived", content: "Body", path: "n1", modified: oldDate, created: nil)
        store.applyEditorUpdate(note)

        let cached: NotePayload? = cache.get(key: CacheKeys.note(id: "n1"))
        XCTAssertNil(cached)
        let offlineCached: NotePayload? = offlineStore.get(key: CacheKeys.note(id: "n1"), as: NotePayload.self)
        XCTAssertNil(offlineCached)
    }

    func testArchivedNoteRecentPersists() async {
        let archivedNode = FileNode(
            name: "Archived.md",
            path: "n2",
            type: .file,
            size: nil,
            modified: nil,
                created: nil,
            children: nil,
            expanded: nil,
            pinned: nil,
            pinnedOrder: nil,
            archived: true,
            folderMarker: nil
        )
        let tree = FileTree(children: [archivedNode])
        let cache = TestCacheClient()
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let api = MockNotesAPI(treeResult: .failure(MockError.forced), noteResult: .failure(MockError.forced))
        let store = NotesStore(api: api, cache: cache, offlineStore: offlineStore)
        store.applyTreeUpdate(tree, persist: false)

        let recentDate = Date().addingTimeInterval(-2 * 24 * 60 * 60).timeIntervalSince1970
        let note = NotePayload(id: "n2", name: "Archived", content: "Body", path: "n2", modified: recentDate, created: nil)
        store.applyEditorUpdate(note)

        let cached: NotePayload? = cache.get(key: CacheKeys.note(id: "n2"))
        XCTAssertNotNil(cached)
        let offlineCached: NotePayload? = offlineStore.get(key: CacheKeys.note(id: "n2"), as: NotePayload.self)
        XCTAssertNotNil(offlineCached)
    }

    func testApplyEditorUpdateSyncsDerivedTitleIntoSidebarTree() async {
        let document = NotesSemanticDocument(
            blocks: [
                .paragraph([.init(text: "First line", marks: [.bold])]),
                .paragraph([.init(text: "Body", marks: [])])
            ]
        )
        let tree = FileTree(children: [
            FileNode(
                name: "New Note",
                path: "note-1",
                type: .file,
                size: nil,
                modified: 1,
                created: nil,
                children: nil,
                expanded: nil,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: nil
            )
        ])
        let cache = TestCacheClient()
        let api = MockNotesAPI(treeResult: .failure(MockError.forced), noteResult: .failure(MockError.forced))
        let store = NotesStore(api: api, cache: cache)
        store.applyTreeUpdate(tree, persist: false)

        let updatedNote = NotePayload(
            id: "note-1",
            name: "First line",
            document: document,
            plainText: "First line\nBody",
            path: "note-1",
            modified: 2,
            created: nil
        )

        store.applyEditorUpdate(updatedNote)

        XCTAssertEqual(store.activeNote?.name, "First line")
        XCTAssertEqual(store.tree?.children.first?.name, "First line")
        XCTAssertEqual(store.tree?.children.first?.modified, 2)
    }

    func testEnqueueArchiveClearsPinnedStateOptimistically() async throws {
        let pinnedNode = FileNode(
            name: "Pinned.md",
            path: "/pinned.md",
            type: .file,
            size: nil,
            modified: nil,
            created: nil,
            children: nil,
            expanded: nil,
            pinned: true,
            pinnedOrder: 4,
            archived: false,
            folderMarker: nil
        )
        let tree = FileTree(children: [pinnedNode])
        let cache = TestCacheClient()
        let api = MockNotesAPI(treeResult: .failure(MockError.forced), noteResult: .failure(MockError.forced))
        let store = NotesStore(api: api, cache: cache)
        store.applyTreeUpdate(tree, persist: false)

        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let writeQueue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false
        )
        store.attachWriteQueue(writeQueue)

        try await store.enqueueArchive(notePath: "/pinned.md", archived: true)

        let archivedNode = try XCTUnwrap(store.tree?.children.first)
        XCTAssertEqual(archivedNode.archived, true)
        XCTAssertEqual(archivedNode.pinned, false)
        XCTAssertNil(archivedNode.pinnedOrder)
    }

    func testConcurrentArchivedTreeRefreshTimesOutInsteadOfWaitingIndefinitely() async {
        let cached = FileTree(children: [])
        let fresh = FileTree(children: [])
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.notesArchivedTree, value: cached, ttlSeconds: 60)
        let api = MockNotesAPI(treeResult: .success(fresh), noteResult: .failure(MockError.forced))
        api.archivedListDelay = 0.6

        let store = NotesStore(
            api: api,
            cache: cache,
            archivedRefreshWaitTimeoutNanoseconds: 100_000_000,
            archivedRefreshPollIntervalNanoseconds: 10_000_000
        )

        let firstRefresh = Task {
            try? await store.loadArchivedTree()
        }
        try? await Task.sleep(nanoseconds: 30_000_000)

        let start = Date()
        try? await store.loadArchivedTree()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.35)
        await firstRefresh.value
    }

    func testResolveConflictKeepLocalEnqueuesOfflineUpdateWithLocalPlainText() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .paragraph([
                    .init(text: "Queued", marks: [.underline]),
                    .init(text: " title", marks: [])
                ]),
                .paragraph([.init(text: "Body", marks: [])])
            ]
        )
        let plainText = NotesSemanticDocumentProjection.plainText(from: document)

        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let writeQueue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false
        )
        let api = MockNotesAPI(treeResult: .failure(MockError.forced), noteResult: .failure(MockError.forced))
        let store = NotesStore(api: api, cache: TestCacheClient())
        store.attachWriteQueue(writeQueue)

        let local = NotePayload(
            id: "n1",
            name: "Local",
            document: document,
            plainText: plainText,
            path: "/note.md",
            modified: nil,
            created: nil
        )
        let server = NotePayload(
            id: "n1",
            name: "Server",
            content: "Server body",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        let conflict = SyncConflict(entityId: "n1", local: local, server: server, reason: "test")

        await store.resolveConflict(conflict, keepLocal: true)

        let request = PendingWrite.fetchRequest()
        request.predicate = NSPredicate(
            format: "entityType == %@ AND operationType == %@ AND entityId == %@",
            WriteEntityType.note.rawValue,
            WriteOperation.update.rawValue,
            "n1"
        )
        let writes = try persistence.container.viewContext.fetch(request)
        XCTAssertEqual(writes.count, 1)
        let write = try XCTUnwrap(writes.first)
        let payload = try JSONDecoder().decode(NoteUpdateRequest.self, from: write.payload)
        XCTAssertEqual(payload.document, document)
        XCTAssertEqual(payload.plainText, plainText)
    }
}

private enum MockError: Error {
    case forced
}

@MainActor
private struct TestNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool
    let isOffline: Bool

    init(isNetworkAvailable: Bool, isOffline: Bool = false) {
        self.isNetworkAvailable = isNetworkAvailable
        self.isOffline = isOffline
    }
}

private final class MockNotesAPI: NotesProviding {
    let treeResult: Result<FileTree, Error>
    let noteResult: Result<NotePayload, Error>
    var onList: (() -> Void)?
    var listDelay: TimeInterval?
    var onArchivedList: (() -> Void)?
    var archivedListDelay: TimeInterval?

    init(treeResult: Result<FileTree, Error>, noteResult: Result<NotePayload, Error>) {
        self.treeResult = treeResult
        self.noteResult = noteResult
    }

    func listTree() async throws -> FileTree {
        if let listDelay {
            try? await Task.sleep(nanoseconds: UInt64(listDelay * 1_000_000_000))
        }
        onList?()
        return try treeResult.get()
    }

    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        if let archivedListDelay {
            try? await Task.sleep(nanoseconds: UInt64(archivedListDelay * 1_000_000_000))
        }
        onArchivedList?()
        return try treeResult.get()
    }

    func getNote(id: String) async throws -> NotePayload {
        _ = id
        return try noteResult.get()
    }

    func search(query: String, limit: Int) async throws -> [FileNode] {
        _ = query
        _ = limit
        return []
    }

    func updateNote(id: String, content: String) async throws -> NotePayload {
        _ = id
        _ = content
        return try noteResult.get()
    }

    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        try await updateNote(
            id: id,
            content: NotesSemanticDocumentProjection.plainText(from: document)
        )
    }

    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        _ = request
        return try noteResult.get()
    }

    func renameNote(id: String, newName: String) async throws -> NotePayload {
        _ = id
        _ = newName
        return try noteResult.get()
    }

    func moveNote(id: String, folder: String) async throws -> NotePayload {
        _ = id
        _ = folder
        return try noteResult.get()
    }

    func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        _ = id
        _ = archived
        return try noteResult.get()
    }

    func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        _ = id
        _ = pinned
        return try noteResult.get()
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
    }

    func deleteNote(id: String) async throws -> NotePayload {
        _ = id
        return try noteResult.get()
    }

    func createFolder(path: String) async throws {
        _ = path
    }

    func renameFolder(oldPath: String, newName: String) async throws {
        _ = oldPath
        _ = newName
    }

    func moveFolder(oldPath: String, newParent: String) async throws {
        _ = oldPath
        _ = newParent
    }

    func deleteFolder(path: String) async throws {
        _ = path
    }
}
