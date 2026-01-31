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
        let note = NotePayload(id: "n1", name: "Note", content: "Body", path: "/note.md", modified: 1)
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
                content: nil,
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

    func testArchivedNoteOlderThanRetentionDoesNotPersist() {
        let archivedNode = FileNode(
            name: "Archived.md",
            path: "n1",
            type: .file,
            size: nil,
            modified: nil,
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
        let note = NotePayload(id: "n1", name: "Archived", content: "Body", path: "n1", modified: oldDate)
        store.applyEditorUpdate(note)

        let cached: NotePayload? = cache.get(key: CacheKeys.note(id: "n1"))
        XCTAssertNil(cached)
        let offlineCached: NotePayload? = offlineStore.get(key: CacheKeys.note(id: "n1"), as: NotePayload.self)
        XCTAssertNil(offlineCached)
    }

    func testArchivedNoteRecentPersists() {
        let archivedNode = FileNode(
            name: "Archived.md",
            path: "n2",
            type: .file,
            size: nil,
            modified: nil,
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
        let note = NotePayload(id: "n2", name: "Archived", content: "Body", path: "n2", modified: recentDate)
        store.applyEditorUpdate(note)

        let cached: NotePayload? = cache.get(key: CacheKeys.note(id: "n2"))
        XCTAssertNotNil(cached)
        let offlineCached: NotePayload? = offlineStore.get(key: CacheKeys.note(id: "n2"), as: NotePayload.self)
        XCTAssertNotNil(offlineCached)
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
