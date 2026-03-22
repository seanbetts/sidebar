// swiftlint:disable file_length
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class NotesViewModelTests: XCTestCase {
    func testLoadTreeUsesCacheOnFailure() async {
        let cachedTree = FileTree(children: [
            FileNode(
                name: "Cached",
                path: "/cached",
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
        let cache = InMemoryCacheClient()
        cache.set(key: CacheKeys.notesTree, value: cachedTree, ttlSeconds: 60)

        let api = MockNotesAPI(listTreeResult: .failure(MockError.forced))
        let store = NotesStore(api: api, cache: cache)
        let toastCenter = ToastCenter()
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.loadTree()

        XCTAssertEqual(viewModel.tree?.children.first?.name, "Cached")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testApplyRealtimeEventClearsSelectionOnDelete() async {
        let tree = FileTree(children: [
            FileNode(
                name: "Note.md",
                path: "note-id",
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
        let note = NotePayload(
            id: "note-id",
            name: "Note.md",
            content: "Hello",
            path: "note-id",
            modified: nil,
            created: nil)
        let cache = InMemoryCacheClient()
        let api = MockNotesAPI(
            listTreeResult: .success(tree),
            getNoteResult: .success(note)
        )
        let store = NotesStore(api: api, cache: cache)
        let toastCenter = ToastCenter()
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.selectNote(id: "note-id")
        XCTAssertEqual(viewModel.selectedNoteId, "note-id")

        let payload = RealtimePayload(
            eventType: .delete,
            table: RealtimeTable.notes,
            schema: "public",
            record: nil,
            oldRecord: NoteRealtimeRecord(
                id: "note-id",
                title: "Note",
                document: nil,
                documentVersion: nil,
                plainText: nil,
                metadata: nil,
                updatedAt: nil,
                deletedAt: nil
            )
        )

        await viewModel.applyRealtimeEvent(payload)

        XCTAssertNil(viewModel.selectedNoteId)
        XCTAssertNil(viewModel.activeNote)
    }

    func testLoadNoteOfflineWithoutCacheShowsOfflineMessage() async {
        let api = NotesAPISpy()
        let cache = InMemoryCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toastCenter = ToastCenter()
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: TestNetworkStatus(isNetworkAvailable: false)
        )

        await viewModel.loadNote(id: "note-id")

        XCTAssertEqual(viewModel.errorMessage, "This note isn't available offline yet.")
        XCTAssertNil(viewModel.activeNote)
        XCTAssertEqual(api.getNoteCallCount, 0)
    }

    func testLoadArchivedTreeTracksLoadingState() async {
        let api = ControlledArchivedNotesAPI()
        let cache = InMemoryCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toastCenter = ToastCenter()
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        let loadTask = Task { await viewModel.loadArchivedTree() }
        await Task.yield()

        XCTAssertTrue(viewModel.isLoadingArchived)

        api.resumeArchivedList(result: .success(FileTree(children: [])))
        await loadTask.value

        XCTAssertFalse(viewModel.isLoadingArchived)
    }

    func testReorderPinnedNotesOptimisticallyUpdatesStoreAndCallsAPI() async {
        let api = NotesAPISpy()
        api.updatePinnedOrderResult = .success(())
        let cache = InMemoryCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toastCenter = ToastCenter()
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        store.applyTreeUpdate(
            FileTree(children: [
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
                    pinnedOrder: 1,
                    archived: false,
                    folderMarker: nil
                ),
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
                    pinnedOrder: 0,
                    archived: false,
                    folderMarker: nil
                )
            ]),
            persist: false
        )

        let success = await viewModel.reorderPinnedNotes(ids: ["/b.md", "/a.md"])

        XCTAssertTrue(success)
        XCTAssertEqual(api.updatedPinnedOrderIDs, [["/b.md", "/a.md"]])
        XCTAssertEqual(currentPinnedOrder(in: viewModel.tree), ["/b.md", "/a.md"])
    }

    func testReorderPinnedNotesRollsBackAndShowsToastWhenAPIFails() async {
        let api = NotesAPISpy()
        api.updatePinnedOrderResult = .failure(MockError.forced)
        let cache = InMemoryCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toastCenter = ToastCenter()
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        store.applyTreeUpdate(
            FileTree(children: [
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
                    pinnedOrder: 1,
                    archived: false,
                    folderMarker: nil
                ),
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
                    pinnedOrder: 0,
                    archived: false,
                    folderMarker: nil
                )
            ]),
            persist: false
        )
        let previousOrder = currentPinnedOrder(in: viewModel.tree)

        let success = await viewModel.reorderPinnedNotes(ids: ["/b.md", "/a.md"])

        XCTAssertFalse(success)
        XCTAssertEqual(currentPinnedOrder(in: viewModel.tree), previousOrder)
        XCTAssertEqual(toastCenter.toast?.message, "Failed to reorder pinned notes")
    }

    func testReorderPinnedNotesDoesNotCallAPIWhenOffline() async {
        let api = NotesAPISpy()
        api.updatePinnedOrderResult = .success(())
        let cache = InMemoryCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toastCenter = ToastCenter()
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: TestNetworkStatus(isNetworkAvailable: false)
        )

        let success = await viewModel.reorderPinnedNotes(ids: ["/b.md", "/a.md"])

        XCTAssertFalse(success)
        XCTAssertEqual(api.updatePinnedOrderCallCount, 0)
    }

    func testStoreActiveNoteMirrorsOnNextMainActorTurn() async throws {
        let api = NotesAPISpy()
        let cache = InMemoryCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toastCenter = ToastCenter()
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let note = NotePayload(
            id: "note-id",
            name: "Note.md",
            content: "Hello",
            path: "note-id",
            modified: nil,
            created: nil
        )

        store.applyEditorUpdate(note)

        XCTAssertNil(viewModel.activeNote)
        try await waitUntil(timeoutSeconds: 0.2) {
            viewModel.activeNote?.id == "note-id"
        }
        XCTAssertEqual(viewModel.activeNote?.id, "note-id")
    }

    func testCreateBlankNoteSendsNoExplicitTitleOrPathAndSelectsIt() async throws {
        let api = NotesAPISpy()
        api.createNoteResult = .success(
            NotePayload(
                id: "note-blank",
                name: "New Note",
                content: "",
                path: "note-blank",
                modified: nil,
                created: nil
            )
        )
        let cache = InMemoryCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toastCenter = ToastCenter()
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        let created = await viewModel.createBlankNote()

        let request = try XCTUnwrap(api.createRequests.first)
        XCTAssertNil(request.title)
        XCTAssertNil(request.path)
        XCTAssertEqual(
            request.document,
            NotesSemanticDocument(blocks: [.paragraph([.init(text: "", marks: [])])])
        )
        XCTAssertEqual(request.plainText, "")
        XCTAssertEqual(created?.id, "note-blank")
        XCTAssertEqual(viewModel.selectedNoteId, created?.path)
    }

    func testCreateBlankNoteShowsFailureToastWhenCreateFails() async throws {
        let api = NotesAPISpy()
        api.createNoteResult = .failure(MockError.forced)
        let cache = InMemoryCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toastCenter = ToastCenter()
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        let created = await viewModel.createBlankNote()

        XCTAssertNil(created)
        XCTAssertEqual(toastCenter.toast?.message, "Failed to create note")
    }

    func testSearchSuccessClearsPreviousSearchError() async throws {
        let match = FileNode(
            name: "Cafe.md",
            path: "Cafe.md",
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
        let api = SearchQueueNotesAPI(results: [
            .failure(MockError.forced),
            .success([match])
        ])
        let cache = InMemoryCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        viewModel.searchDebounceDelay = 0

        viewModel.updateSearch(query: "first")
        try? await waitUntil(timeoutSeconds: 0.2) {
            viewModel.errorMessage != nil
        }
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.searchResults.isEmpty)

        viewModel.updateSearch(query: "second")
        try? await waitUntil(timeoutSeconds: 0.2) {
            viewModel.searchResults.map(\.path) == ["Cafe.md"]
        }
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.searchResults.map(\.path), ["Cafe.md"])
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

@MainActor
private final class NotesAPISpy: NotesProviding {
    private(set) var getNoteCallCount = 0
    private(set) var createRequests: [NoteCreateRequest] = []
    private(set) var renameRequests: [(id: String, newName: String)] = []
    var listTreeResult: Result<FileTree, Error> = .failure(MockError.forced)
    var getNoteResult: Result<NotePayload, Error> = .failure(MockError.forced)
    var createNoteResult: Result<NotePayload, Error> = .failure(MockError.forced)
    var renameNoteResult: Result<NotePayload, Error> = .failure(MockError.forced)

    func listTree() async throws -> FileTree {
        try listTreeResult.get()
    }

    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        throw MockError.forced
    }

    func getNote(id: String) async throws -> NotePayload {
        _ = id
        getNoteCallCount += 1
        return try getNoteResult.get()
    }

    func search(query: String, limit: Int) async throws -> [FileNode] {
        _ = query
        _ = limit
        return []
    }

    func updateNote(id: String, content: String) async throws -> NotePayload {
        _ = id
        _ = content
        throw MockError.forced
    }

    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        try await updateNote(
            id: id,
            content: NotesSemanticDocumentProjection.plainText(from: document)
        )
    }

    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        createRequests.append(request)
        return try createNoteResult.get()
    }

    func renameNote(id: String, newName: String) async throws -> NotePayload {
        renameRequests.append((id: id, newName: newName))
        return try renameNoteResult.get()
    }

    var updatePinnedOrderCallCount = 0
    var updatedPinnedOrderIDs: [[String]] = []
    var updatePinnedOrderResult: Result<Void, Error> = .success(())

    func moveNote(id: String, folder: String) async throws -> NotePayload {
        _ = id
        _ = folder
        throw MockError.forced
    }

    func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        _ = id
        _ = archived
        throw MockError.forced
    }

    func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        _ = id
        _ = pinned
        throw MockError.forced
    }

    func updatePinnedOrder(ids: [String]) async throws {
        updatePinnedOrderCallCount += 1
        updatedPinnedOrderIDs.append(ids)
        try updatePinnedOrderResult.get()
    }

    func deleteNote(id: String) async throws -> NotePayload {
        _ = id
        throw MockError.forced
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

@MainActor
private struct MockNotesAPI: NotesProviding {
    let listTreeResult: Result<FileTree, Error>
    let getNoteResult: Result<NotePayload, Error>

    init(
        listTreeResult: Result<FileTree, Error>,
        getNoteResult: Result<NotePayload, Error> = .failure(MockError.forced)
    ) {
        self.listTreeResult = listTreeResult
        self.getNoteResult = getNoteResult
    }

    func listTree() async throws -> FileTree {
        try listTreeResult.get()
    }

    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        return try listTreeResult.get()
    }

    func getNote(id: String) async throws -> NotePayload {
        _ = id
        return try getNoteResult.get()
    }

    func search(query: String, limit: Int) async throws -> [FileNode] {
        _ = query
        _ = limit
        return []
    }

    func updateNote(id: String, content: String) async throws -> NotePayload {
        _ = id
        _ = content
        return try getNoteResult.get()
    }

    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        try await updateNote(
            id: id,
            content: NotesSemanticDocumentProjection.plainText(from: document)
        )
    }

    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        _ = request
        return try getNoteResult.get()
    }

    func renameNote(id: String, newName: String) async throws -> NotePayload {
        _ = id
        _ = newName
        return try getNoteResult.get()
    }

    func moveNote(id: String, folder: String) async throws -> NotePayload {
        _ = id
        _ = folder
        return try getNoteResult.get()
    }

    func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        _ = id
        _ = archived
        return try getNoteResult.get()
    }

    func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        _ = id
        _ = pinned
        return try getNoteResult.get()
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
    }

    func deleteNote(id: String) async throws -> NotePayload {
        _ = id
        return try getNoteResult.get()
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

@MainActor
private final class SearchQueueNotesAPI: NotesProviding {
    private var searchResults: [Result<[FileNode], Error>]

    init(results: [Result<[FileNode], Error>]) {
        searchResults = results
    }

    func listTree() async throws -> FileTree {
        FileTree(children: [])
    }

    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        return FileTree(children: [])
    }

    func getNote(id: String) async throws -> NotePayload {
        _ = id
        throw MockError.forced
    }

    func search(query: String, limit: Int) async throws -> [FileNode] {
        _ = query
        _ = limit
        guard !searchResults.isEmpty else { return [] }
        let next = searchResults.removeFirst()
        return try next.get()
    }

    func updateNote(id: String, content: String) async throws -> NotePayload {
        _ = id
        _ = content
        throw MockError.forced
    }

    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        try await updateNote(
            id: id,
            content: NotesSemanticDocumentProjection.plainText(from: document)
        )
    }

    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        _ = request
        throw MockError.forced
    }

    func renameNote(id: String, newName: String) async throws -> NotePayload {
        _ = id
        _ = newName
        throw MockError.forced
    }

    func moveNote(id: String, folder: String) async throws -> NotePayload {
        _ = id
        _ = folder
        throw MockError.forced
    }

    func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        _ = id
        _ = archived
        throw MockError.forced
    }

    func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        _ = id
        _ = pinned
        throw MockError.forced
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
    }

    func deleteNote(id: String) async throws -> NotePayload {
        _ = id
        throw MockError.forced
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

@MainActor
private final class ControlledArchivedNotesAPI: NotesProviding {
    private var archivedContinuation: CheckedContinuation<FileTree, Error>?

    func listTree() async throws -> FileTree {
        FileTree(children: [])
    }

    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        return try await withCheckedThrowingContinuation { continuation in
            archivedContinuation = continuation
        }
    }

    func getNote(id: String) async throws -> NotePayload {
        _ = id
        throw MockError.forced
    }

    func search(query: String, limit: Int) async throws -> [FileNode] {
        _ = query
        _ = limit
        return []
    }

    func updateNote(id: String, content: String) async throws -> NotePayload {
        _ = id
        _ = content
        throw MockError.forced
    }

    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        try await updateNote(
            id: id,
            content: NotesSemanticDocumentProjection.plainText(from: document)
        )
    }

    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        _ = request
        throw MockError.forced
    }

    func renameNote(id: String, newName: String) async throws -> NotePayload {
        _ = id
        _ = newName
        throw MockError.forced
    }

    func moveNote(id: String, folder: String) async throws -> NotePayload {
        _ = id
        _ = folder
        throw MockError.forced
    }

    func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        _ = id
        _ = archived
        throw MockError.forced
    }

    func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        _ = id
        _ = pinned
        throw MockError.forced
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
    }

    func deleteNote(id: String) async throws -> NotePayload {
        _ = id
        throw MockError.forced
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

    func resumeArchivedList(result: Result<FileTree, Error>) {
        guard let continuation = archivedContinuation else { return }
        archivedContinuation = nil
        continuation.resume(with: result)
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

@MainActor
private func waitUntil(timeoutSeconds: TimeInterval, condition: @escaping () -> Bool) async throws {
    let timeoutNanoseconds = UInt64(timeoutSeconds * 1_000_000_000)
    let start = DispatchTime.now().uptimeNanoseconds

    while !condition() {
        if DispatchTime.now().uptimeNanoseconds - start > timeoutNanoseconds {
            XCTFail("Timed out waiting for condition")
            return
        }
        await Task.yield()
    }
}
