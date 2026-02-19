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

    func testLoadTreeCachesFreshData() async {
        let freshTree = FileTree(children: [
            FileNode(
                name: "Fresh",
                path: "/fresh",
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
        let api = MockNotesAPI(listTreeResult: .success(freshTree))
        let store = NotesStore(api: api, cache: cache)
        let toastCenter = ToastCenter()
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.loadTree()

        let cached: FileTree? = cache.get(key: CacheKeys.notesTree)
        XCTAssertEqual(cached?.children.first?.name, "Fresh")
    }

    func testLoadTreeRefreshesInBackground() async {
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
        let freshTree = FileTree(children: [
            FileNode(
                name: "Fresh",
                path: "/fresh",
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

        let api = MockNotesAPI(listTreeResult: .success(freshTree))
        let store = NotesStore(api: api, cache: cache)
        let toastCenter = ToastCenter()
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.loadTree()

        for _ in 0..<10 {
            if viewModel.tree?.children.first?.name == "Fresh" {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertEqual(viewModel.tree?.children.first?.name, "Fresh")
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
                content: nil,
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

    func testCreateBlankNoteCreatesUntitledNoteAndSelectsIt() async throws {
        let api = NotesAPISpy()
        api.createNoteResult = .success(
            NotePayload(
                id: "note-blank",
                name: "Untitled 2026-02-12 101500.md",
                content: "",
                path: "Untitled 2026-02-12 101500.md",
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
        let title = try XCTUnwrap(request.title)
        let path = try XCTUnwrap(request.path)
        XCTAssertTrue(title.hasPrefix("Untitled "))
        XCTAssertTrue(path.hasPrefix("Untitled "))
        XCTAssertTrue(path.hasSuffix(".md"))
        XCTAssertEqual(created?.id, "note-blank")
        XCTAssertEqual(viewModel.selectedNoteId, created?.path)
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

        viewModel.updateSearch(query: "first")
        try? await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.searchResults.isEmpty)

        viewModel.updateSearch(query: "second")
        try? await Task.sleep(nanoseconds: 450_000_000)
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
    var createNoteResult: Result<NotePayload, Error> = .failure(MockError.forced)

    func listTree() async throws -> FileTree {
        throw MockError.forced
    }

    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        throw MockError.forced
    }

    func getNote(id: String) async throws -> NotePayload {
        _ = id
        getNoteCallCount += 1
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

    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        createRequests.append(request)
        return try createNoteResult.get()
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
        FileTree(children: [])
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
