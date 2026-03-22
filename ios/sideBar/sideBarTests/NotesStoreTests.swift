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
        let api = NotesStoreTestsSupport.MockNotesAPI(
            treeResult: .success(fresh),
            noteResult: .failure(NotesStoreTestsSupport.MockError.forced)
        )
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
        let api = NotesStoreTestsSupport.MockNotesAPI(
            treeResult: .failure(NotesStoreTestsSupport.MockError.forced),
            noteResult: .failure(NotesStoreTestsSupport.MockError.forced)
        )
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
        let api = NotesStoreTestsSupport.MockNotesAPI(
            treeResult: .failure(NotesStoreTestsSupport.MockError.forced),
            noteResult: .failure(NotesStoreTestsSupport.MockError.forced)
        )
        let cache = TestCacheClient()
        let store = NotesStore(
            api: api,
            cache: cache,
            offlineStore: offlineStore,
            networkStatus: NotesStoreTestsSupport.TestNetworkStatus(isNetworkAvailable: false)
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
        let api = NotesStoreTestsSupport.MockNotesAPI(
            treeResult: .failure(NotesStoreTestsSupport.MockError.forced),
            noteResult: .failure(NotesStoreTestsSupport.MockError.forced)
        )
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
        let api = NotesStoreTestsSupport.MockNotesAPI(
            treeResult: .failure(NotesStoreTestsSupport.MockError.forced),
            noteResult: .failure(NotesStoreTestsSupport.MockError.forced)
        )
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
        let api = NotesStoreTestsSupport.MockNotesAPI(
            treeResult: .failure(NotesStoreTestsSupport.MockError.forced),
            noteResult: .failure(NotesStoreTestsSupport.MockError.forced)
        )
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
        let api = NotesStoreTestsSupport.MockNotesAPI(
            treeResult: .failure(NotesStoreTestsSupport.MockError.forced),
            noteResult: .failure(NotesStoreTestsSupport.MockError.forced)
        )
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

    func testApplyPinnedOrderUpdatesPinnedNodesAcrossFoldersAndCanRestorePreviousOrder() async {
        let tree = FileTree(children: [
            FileNode(
                name: "Folder A",
                path: "/folder-a",
                type: .directory,
                size: nil,
                modified: nil,
                created: nil,
                children: [
                    FileNode(
                        name: "A.md",
                        path: "/a.md",
                        type: .file,
                        size: nil,
                        modified: nil,
                        created: nil,
                        children: nil,
                        expanded: nil,
                        pinned: true,
                        pinnedOrder: 1,
                        archived: false,
                        folderMarker: nil
                    )
                ],
                expanded: nil,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: nil
            ),
            FileNode(
                name: "B.md",
                path: "/b.md",
                type: .file,
                size: nil,
                modified: nil,
                created: nil,
                children: nil,
                expanded: nil,
                pinned: true,
                pinnedOrder: 0,
                archived: false,
                folderMarker: nil
            ),
            FileNode(
                name: "Nested",
                path: "/nested",
                type: .directory,
                size: nil,
                modified: nil,
                created: nil,
                children: [
                    FileNode(
                        name: "C.md",
                        path: "/nested/c.md",
                        type: .file,
                        size: nil,
                        modified: nil,
                        created: nil,
                        children: nil,
                        expanded: nil,
                        pinned: true,
                        pinnedOrder: 2,
                        archived: false,
                        folderMarker: nil
                    )
                ],
                expanded: nil,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: nil
            )
        ])
        let api = NotesStoreTestsSupport.MockNotesAPI(
            treeResult: .failure(NotesStoreTestsSupport.MockError.forced),
            noteResult: .failure(NotesStoreTestsSupport.MockError.forced)
        )
        let store = NotesStore(api: api, cache: TestCacheClient())
        store.applyTreeUpdate(tree, persist: false)

        let previousOrder = currentPinnedOrder(in: store.tree)

        store.applyPinnedOrder(["/b.md", "/a.md", "/nested/c.md"])

        XCTAssertEqual(currentPinnedOrder(in: store.tree), ["/b.md", "/a.md", "/nested/c.md"])

        store.applyPinnedOrder(previousOrder)

        XCTAssertEqual(currentPinnedOrder(in: store.tree), previousOrder)
    }

    func testConcurrentArchivedTreeRefreshTimesOutInsteadOfWaitingIndefinitely() async throws {
        let cached = FileTree(children: [])
        let fresh = FileTree(children: [])
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.notesArchivedTree, value: cached, ttlSeconds: 60)
        let api = NotesStoreTestsSupport.MockNotesAPI(
            treeResult: .success(fresh),
            noteResult: .failure(NotesStoreTestsSupport.MockError.forced)
        )
        api.archivedListDelay = 0.2

        let store = NotesStore(
            api: api,
            cache: cache,
            archivedRefreshWaitTimeoutNanoseconds: 50_000_000,
            archivedRefreshPollIntervalNanoseconds: 10_000_000
        )

        let firstRefresh = Task {
            try? await store.loadArchivedTree()
        }
        try await NotesStoreTestsSupport.waitUntilCondition(timeoutSeconds: 1.0) {
            await api.archivedListCallCount > 0
        }

        let start = Date()
        try? await store.loadArchivedTree()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.2)
        await firstRefresh.value
    }

}

private func currentPinnedOrder(in tree: FileTree?) -> [String] {
    guard let tree else { return [] }
    return pinnedNodes(in: tree.children)
        .sorted {
            let leftOrder = $0.pinnedOrder ?? Int.max
            let rightOrder = $1.pinnedOrder ?? Int.max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return $0.path < $1.path
        }
        .map(\.path)
}

private func pinnedNodes(in nodes: [FileNode]) -> [FileNode] {
    var results: [FileNode] = []
    for node in nodes {
        if node.type == .file, node.pinned == true {
            results.append(node)
        }
        if let children = node.children {
            results.append(contentsOf: pinnedNodes(in: children))
        }
    }
    return results
}
