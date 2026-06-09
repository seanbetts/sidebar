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

    func testLoadNoteIgnoresLateResponseForPreviouslySelectedNote() async throws {
        let firstNote = NotePayload(
            id: "note-a",
            name: "First.md",
            content: "First",
            path: "note-a",
            modified: nil,
            created: nil
        )
        let secondNote = NotePayload(
            id: "note-b",
            name: "Second.md",
            content: "Second",
            path: "note-b",
            modified: nil,
            created: nil
        )
        let api = ControlledGetNotesAPI()
        let cache = InMemoryCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toastCenter = ToastCenter()
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        let firstLoad = Task { await viewModel.loadNote(id: firstNote.id) }
        try await waitUntil(timeoutSeconds: 0.2) {
            api.pendingGetNoteIDs.contains(firstNote.id)
        }

        let secondLoad = Task { await viewModel.loadNote(id: secondNote.id) }
        try await waitUntil(timeoutSeconds: 0.2) {
            api.pendingGetNoteIDs.contains(secondNote.id)
        }

        api.resumeGetNote(id: secondNote.id, result: .success(secondNote))
        await secondLoad.value
        try await waitUntil(timeoutSeconds: 0.2) {
            viewModel.activeNote?.id == secondNote.id
        }
        XCTAssertEqual(viewModel.selectedNoteId, secondNote.id)
        XCTAssertEqual(viewModel.activeNote?.id, secondNote.id)

        api.resumeGetNote(id: firstNote.id, result: .success(firstNote))
        await firstLoad.value
        await Task.yield()

        XCTAssertEqual(viewModel.selectedNoteId, secondNote.id)
        XCTAssertEqual(viewModel.activeNote?.id, secondNote.id)
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

    func testCreateBlankNoteSendsNoExplicitTitleOrPathAndSelectsIt() async throws {
        let api = NotesAPISpy()
        let cache = InMemoryCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let persistence = PersistenceController(inMemory: true)
        let writeQueue = makeNotesWriteQueue(persistence: persistence)
        store.attachWriteQueue(writeQueue)
        let toastCenter = ToastCenter()
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        let created = await viewModel.createBlankNote()

        let pending = try fetchOnlyPendingWrite(from: persistence)
        let request = try JSONDecoder().decode(NoteCreateRequest.self, from: pending.payload)
        XCTAssertNil(request.title)
        XCTAssertNil(request.path)
        XCTAssertEqual(
            request.document,
            NotesSemanticDocument(blocks: [.paragraph([.init(text: "", marks: [])])])
        )
        XCTAssertEqual(request.plainText, "")
        XCTAssertNotNil(request.clientId)
        XCTAssertEqual(pending.operationType, WriteOperation.create.rawValue)
        XCTAssertEqual(pending.entityType, WriteEntityType.note.rawValue)
        XCTAssertEqual(api.createRequests.count, 0)
        XCTAssertEqual(created?.id, request.clientId)
        XCTAssertEqual(viewModel.selectedNoteId, created?.path)
    }

    func testCreateBlankNoteShowsFailureToastWhenQueueMissing() async throws {
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

        let created = await viewModel.createBlankNote()

        XCTAssertNil(created)
        XCTAssertEqual(api.createRequests.count, 0)
        XCTAssertEqual(toastCenter.toast?.message, "Failed to queue note")
    }
}

@MainActor
final class NotesViewModelMutationTests: XCTestCase {
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

    func testMoveNoteOnlineOptimisticallyMovesTreeWithoutSelectingUnselectedNote() async throws {
        let initialTree = FileTree(children: [
            FileNode(
                name: "Draft.md",
                path: "Draft.md",
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
            ),
            FileNode(
                name: "Projects",
                path: "folder:Projects",
                type: .directory,
                size: nil,
                modified: nil,
                created: nil,
                children: [],
                expanded: nil,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: true
            )
        ])
        let movedNote = NotePayload(
            id: "note-1",
            name: "Draft.md",
            content: "Body",
            path: "Projects/Draft.md",
            modified: nil,
            created: nil
        )
        let api = ControlledMoveNotesAPI(moveResult: movedNote)
        let cache = InMemoryCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let writeQueue = makeNotesWriteQueue()
        store.attachWriteQueue(writeQueue)
        store.applyTreeUpdate(initialTree, persist: false)
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.moveNote(id: "Draft.md", folder: "Projects")

        try await waitUntil(timeoutSeconds: 0.2) {
            viewModel.tree?.children.contains(where: { $0.path == "Projects/Draft.md" }) == true
                || viewModel.tree?.children.contains(where: { node in
                    node.path == "folder:Projects"
                        && (node.children ?? []).contains(where: { $0.path == "Projects/Draft.md" })
                }) == true
        }
        XCTAssertNil(viewModel.selectedNoteId)

        let pending = try await fetchFirstPendingSummary(from: writeQueue)
        XCTAssertEqual(pending.operationType, WriteOperation.move.rawValue)
        XCTAssertEqual(pending.entityType, WriteEntityType.note.rawValue)

        XCTAssertNil(viewModel.selectedNoteId)
    }

    func testRenameNoteUsesSemanticDocumentUpdateAndOptimisticallyMirrorsRenamedTitle() async throws {
        let initialDocument = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Original", marks: [])]),
                .paragraph([.init(text: "Body", marks: [])])
            ]
        )
        let initialNote = NotePayload(
            id: "note-id",
            name: "Original",
            document: initialDocument,
            plainText: "Original\nBody",
            path: "note-id",
            modified: 10,
            created: 5
        )
        let initialTree = FileTree(children: [
            FileNode(
                name: "Original",
                path: "note-id",
                type: .file,
                size: nil,
                modified: 10,
                created: 5,
                children: nil,
                expanded: nil,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: nil
            )
        ])
        let api = ControlledSemanticRenameNotesAPI(
            renamedNote: NotePayload(
                id: "note-id",
                name: "Renamed",
                document: NotesSemanticDocument(
                    version: NotesSemanticDocument.currentVersion,
                    blocks: [
                        .init(type: .title, content: [.init(text: "Renamed", marks: [])]),
                        .paragraph([.init(text: "Body", marks: [])])
                    ]
                ),
                plainText: "Renamed\nBody",
                path: "note-id",
                modified: 11,
                created: 5
            )
        )
        let cache = InMemoryCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let writeQueue = makeNotesWriteQueue()
        store.attachWriteQueue(writeQueue)
        store.applyTreeUpdate(initialTree, persist: false)
        store.applyEditorUpdate(initialNote)
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        try await waitUntil(timeoutSeconds: 0.2) {
            viewModel.activeNote?.id == "note-id"
        }

        await viewModel.renameNote(id: "note-id", newName: "Renamed")

        XCTAssertEqual(api.updateNoteCallCount, 0)
        XCTAssertEqual(api.renameNoteCallCount, 0)
        XCTAssertEqual(viewModel.activeNote?.name, "Renamed")
        XCTAssertEqual(viewModel.tree?.children.first?.name, "Renamed")
        let pending = try await fetchFirstPendingSummary(from: writeQueue)
        XCTAssertEqual(pending.operationType, WriteOperation.update.rawValue)
        XCTAssertEqual(pending.entityType, WriteEntityType.note.rawValue)

        XCTAssertEqual(viewModel.activeNote?.name, "Renamed")
        XCTAssertEqual(viewModel.tree?.children.first?.name, "Renamed")
    }

    func testFolderPathContainingNoteUsesTreeNestingForUuidNotePath() async throws {
        let tree = FileTree(children: [
            FileNode(
                name: "Projects",
                path: "folder:Projects",
                type: .directory,
                size: nil,
                modified: nil,
                created: nil,
                children: [
                    FileNode(
                        name: "Planning",
                        path: "folder:Projects/Planning",
                        type: .directory,
                        size: nil,
                        modified: nil,
                        created: nil,
                        children: [
                            FileNode(
                                name: "Spec",
                                path: "note-uuid",
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
                        ],
                        expanded: nil,
                        pinned: nil,
                        pinnedOrder: nil,
                        archived: nil,
                        folderMarker: true
                    )
                ],
                expanded: nil,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: true
            )
        ])
        let api = NotesAPISpy()
        let store = NotesStore(api: api, cache: InMemoryCacheClient())
        store.applyTreeUpdate(tree, persist: false)
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        XCTAssertEqual(viewModel.folderPath(containingNote: "note-uuid"), "Projects/Planning")
    }

    func testDeleteFolderClearsSelectedUuidNoteNestedInFolder() async throws {
        let note = NotePayload(
            id: "note-uuid",
            name: "Spec",
            content: "Body",
            path: "note-uuid",
            modified: nil,
            created: nil
        )
        let tree = FileTree(children: [
            FileNode(
                name: "Projects",
                path: "folder:Projects",
                type: .directory,
                size: nil,
                modified: nil,
                created: nil,
                children: [
                    FileNode(
                        name: "Spec",
                        path: note.path,
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
                ],
                expanded: nil,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: true
            )
        ])
        let api = NotesAPISpy()
        api.getNoteResult = .success(note)
        api.deleteFolderResult = .success(())
        api.listTreeResult = .success(FileTree(children: []))
        let store = NotesStore(api: api, cache: InMemoryCacheClient())
        let writeQueue = makeNotesWriteQueue()
        store.attachWriteQueue(writeQueue)
        store.applyTreeUpdate(tree, persist: false)
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.selectNote(id: note.path)
        XCTAssertEqual(viewModel.selectedNoteId, note.path)

        await viewModel.deleteFolder(path: "folder:Projects")

        let pending = try await fetchFirstPendingSummary(from: writeQueue)
        XCTAssertEqual(pending.operationType, WriteOperation.delete.rawValue)
        XCTAssertEqual(pending.entityType, WriteEntityType.noteFolder.rawValue)
        XCTAssertNil(viewModel.selectedNoteId)
        XCTAssertNil(viewModel.activeNote)
    }

    func testNotePlainTextForActionFetchesWithoutChangingSelection() async throws {
        let selected = NotePayload(
            id: "selected-id",
            name: "Selected",
            content: "Selected body",
            path: "selected-id",
            modified: nil,
            created: nil
        )
        let other = NotePayload(
            id: "other-id",
            name: "Other",
            content: "Other body",
            path: "other-id",
            modified: nil,
            created: nil
        )
        let api = NotesAPISpy()
        api.getNoteResults = [
            selected.path: .success(selected),
            other.path: .success(other)
        ]
        let store = NotesStore(api: api, cache: InMemoryCacheClient())
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.selectNote(id: selected.path)
        XCTAssertEqual(viewModel.selectedNoteId, selected.path)

        let content = await viewModel.notePlainTextForAction(id: other.path)

        XCTAssertEqual(content, "Other body")
        XCTAssertEqual(viewModel.selectedNoteId, selected.path)
        XCTAssertEqual(viewModel.activeNote?.id, selected.id)
    }

    func testSetPinnedOnlineOptimisticallyUpdatesTreeWithoutReload() async throws {
        let initialTree = FileTree(children: [
            FileNode(
                name: "Draft.md",
                path: "Draft.md",
                type: .file,
                size: nil,
                modified: nil,
                created: nil,
                children: nil,
                expanded: nil,
                pinned: false,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: nil
            )
        ])
        let pinnedNote = NotePayload(
            id: "note-1",
            name: "Draft.md",
            content: "Body",
            path: "Draft.md",
            modified: nil,
            created: nil
        )
        let api = ControlledPinNotesAPI(pinResult: pinnedNote)
        let cache = InMemoryCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let writeQueue = makeNotesWriteQueue()
        store.attachWriteQueue(writeQueue)
        store.applyTreeUpdate(initialTree, persist: false)
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.setPinned(id: "Draft.md", pinned: true)

        try await waitUntil(timeoutSeconds: 0.2) {
            viewModel.tree?.children.first?.pinned == true
        }

        let pending = try await fetchFirstPendingSummary(from: writeQueue)
        XCTAssertEqual(pending.operationType, WriteOperation.pin.rawValue)
        XCTAssertEqual(pending.entityType, WriteEntityType.note.rawValue)

        XCTAssertEqual(viewModel.tree?.children.first?.pinned, true)
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
    var getNoteResults: [String: Result<NotePayload, Error>] = [:]
    var createNoteResult: Result<NotePayload, Error> = .failure(MockError.forced)
    var renameNoteResult: Result<NotePayload, Error> = .failure(MockError.forced)
    var deleteFolderResult: Result<Void, Error> = .success(())

    func listTree() async throws -> FileTree {
        try listTreeResult.get()
    }

    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        throw MockError.forced
    }

    func getNote(id: String) async throws -> NotePayload {
        getNoteCallCount += 1
        if let result = getNoteResults[id] {
            return try result.get()
        }
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
        try deleteFolderResult.get()
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

@MainActor
private final class ControlledGetNotesAPI: NotesProviding {
    private var continuations: [String: CheckedContinuation<NotePayload, Error>] = [:]
    private(set) var pendingGetNoteIDs = Set<String>()

    func listTree() async throws -> FileTree {
        FileTree(children: [])
    }

    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        return FileTree(children: [])
    }

    func getNote(id: String) async throws -> NotePayload {
        pendingGetNoteIDs.insert(id)
        return try await withCheckedThrowingContinuation { continuation in
            continuations[id] = continuation
        }
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

    func resumeGetNote(id: String, result: Result<NotePayload, Error>) {
        guard let continuation = continuations.removeValue(forKey: id) else { return }
        pendingGetNoteIDs.remove(id)
        continuation.resume(with: result)
    }
}

@MainActor
private final class ControlledMoveNotesAPI: NotesProviding {
    private let moveResult: NotePayload
    private var moveContinuation: CheckedContinuation<NotePayload, Error>?

    init(moveResult: NotePayload) {
        self.moveResult = moveResult
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
        return try await withCheckedThrowingContinuation { continuation in
            moveContinuation = continuation
        }
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

    func resumeMove() {
        guard let moveContinuation else { return }
        self.moveContinuation = nil
        moveContinuation.resume(returning: moveResult)
    }
}

@MainActor
private final class ControlledPinNotesAPI: NotesProviding {
    private let pinResult: NotePayload
    private var pinContinuation: CheckedContinuation<NotePayload, Error>?

    init(pinResult: NotePayload) {
        self.pinResult = pinResult
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
        return try await withCheckedThrowingContinuation { continuation in
            pinContinuation = continuation
        }
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

    func resumePin() {
        guard let pinContinuation else { return }
        self.pinContinuation = nil
        pinContinuation.resume(returning: pinResult)
    }
}

@MainActor
private final class ControlledSemanticRenameNotesAPI: NotesProviding {
    private let renamedNote: NotePayload
    private var updateContinuation: CheckedContinuation<NotePayload, Error>?
    private(set) var updateNoteCallCount = 0
    private(set) var renameNoteCallCount = 0
    private(set) var lastUpdatedDocument: NotesSemanticDocument?

    init(renamedNote: NotePayload) {
        self.renamedNote = renamedNote
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
        return []
    }

    func updateNote(id: String, content: String) async throws -> NotePayload {
        _ = id
        _ = content
        throw MockError.forced
    }

    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        updateNoteCallCount += 1
        lastUpdatedDocument = document
        return try await withCheckedThrowingContinuation { continuation in
            updateContinuation = continuation
        }
    }

    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        _ = request
        throw MockError.forced
    }

    func renameNote(id: String, newName: String) async throws -> NotePayload {
        _ = id
        _ = newName
        renameNoteCallCount += 1
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

    func resumeUpdate() {
        guard let updateContinuation else { return }
        self.updateContinuation = nil
        updateContinuation.resume(returning: renamedNote)
    }
}

@MainActor
extension NotesViewModelTests {
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

    func testApplyLocalNoteSnapshotMirrorsActiveNoteOnNextMainActorTurn() async throws {
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
            name: "Original",
            document: NotesSemanticDocumentProjection.document(fromPlainText: "Original"),
            plainText: "Original",
            path: "note-id",
            modified: nil,
            created: nil
        )
        let updatedDocument = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Updated", marks: [])]),
                .paragraph([.init(text: "Body", marks: [])])
            ]
        )

        store.applyEditorUpdate(note)
        try await waitUntil(timeoutSeconds: 0.2) {
            viewModel.activeNote?.id == "note-id"
        }

        viewModel.applyLocalNoteSnapshot(id: "note-id", document: updatedDocument)

        XCTAssertEqual(viewModel.activeNote?.plainText, "Original")
        try await waitUntil(timeoutSeconds: 0.2) {
            viewModel.activeNote?.plainText == "Updated\nBody"
        }
        XCTAssertEqual(viewModel.activeNote?.plainText, "Updated\nBody")
    }

    func testApplySavedNoteAcknowledgementMirrorsActiveNoteOnNextMainActorTurn() async throws {
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
            name: "Original",
            document: NotesSemanticDocumentProjection.document(fromPlainText: "Original"),
            plainText: "Original",
            path: "note-id",
            modified: nil,
            created: nil
        )
        let savedDocument = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Saved", marks: [])]),
                .paragraph([.init(text: "Body", marks: [])])
            ]
        )
        let serverNote = NotePayload(
            id: "note-id",
            name: "Original",
            document: note.document,
            plainText: note.plainText,
            path: "note-id",
            modified: 42,
            created: nil
        )

        store.applyEditorUpdate(note)
        try await waitUntil(timeoutSeconds: 0.2) {
            viewModel.activeNote?.id == "note-id"
        }

        viewModel.applySavedNoteAcknowledgement(serverNote: serverNote, document: savedDocument)

        XCTAssertEqual(viewModel.activeNote?.plainText, "Original")
        try await waitUntil(timeoutSeconds: 0.2) {
            viewModel.activeNote?.plainText == "Saved\nBody"
        }
        XCTAssertEqual(viewModel.activeNote?.plainText, "Saved\nBody")
    }

    func testStoreTreeMirrorsOnNextMainActorTurn() async throws {
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
        let tree = FileTree(children: [
            FileNode(
                name: "Deferred.md",
                path: "deferred",
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

        store.applyData(tree, persist: false)

        XCTAssertNil(viewModel.tree)
        try await waitUntil(timeoutSeconds: 0.2) {
            viewModel.tree?.children.first?.path == "deferred"
        }
        XCTAssertEqual(viewModel.tree?.children.first?.path, "deferred")
    }

    func testStoreArchivedTreeMirrorsOnNextMainActorTurn() async throws {
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
        let archivedTree = FileTree(children: [
            FileNode(
                name: "Archived.md",
                path: "archived",
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
        ])

        store.applyArchivedTreeUpdate(archivedTree, persist: false)

        XCTAssertNil(viewModel.archivedTree)
        try await waitUntil(timeoutSeconds: 0.2) {
            viewModel.archivedTree?.children.first?.path == "archived"
        }
        XCTAssertEqual(viewModel.archivedTree?.children.first?.path, "archived")
    }

    func testRefreshAdapterClearsPreviousTreeLoadErrorAfterRecoveredRefresh() async throws {
        let recoveredTree = FileTree(children: [
            FileNode(
                name: "Recovered.md",
                path: "recovered",
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
        let api = SequencedNotesAPI(
            treeResults: [
                .failure(APIClientError.missingToken),
                .success(recoveredTree)
            ],
            noteResults: []
        )
        let store = NotesStore(api: api, cache: InMemoryCacheClient())
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.loadTree()
        XCTAssertNotNil(viewModel.errorMessage)

        let adapter = NotesRefreshAdapter(viewModel: viewModel)
        await adapter.refresh(
            plan: RefreshPlan(
                trigger: .coldLaunch,
                targets: [.sectionList(.notes)],
                requiresQueueReplayFirst: false
            )
        )

        XCTAssertNil(viewModel.errorMessage)
        try await waitUntil(timeoutSeconds: 0.2) {
            viewModel.tree?.children.first?.path == "recovered"
        }
    }

    func testRefreshAdapterClearsPreviousNoteLoadErrorAfterRecoveredDetailRefresh() async throws {
        let note = NotePayload(
            id: "note-1",
            name: "Recovered.md",
            content: "Recovered",
            path: "note-1",
            modified: nil,
            created: nil
        )
        let api = SequencedNotesAPI(
            treeResults: [],
            noteResults: [
                .failure(APIClientError.missingToken),
                .success(note)
            ]
        )
        let store = NotesStore(api: api, cache: InMemoryCacheClient())
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.loadNote(id: "note-1")
        XCTAssertEqual(viewModel.selectedNoteId, "note-1")
        XCTAssertNotNil(viewModel.errorMessage)

        let adapter = NotesRefreshAdapter(viewModel: viewModel)
        await adapter.refresh(
            plan: RefreshPlan(
                trigger: .coldLaunch,
                targets: [.visibleDetail(.notes)],
                requiresQueueReplayFirst: false
            )
        )

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.activeNote?.id, "note-1")
    }

    func testRefreshSelectedNoteIfNeededReloadsVisibleNote() async throws {
        let initial = NotePayload(
            id: "note-1",
            name: "Open.md",
            content: "Initial",
            path: "note-1",
            modified: 100,
            created: nil
        )
        let refreshed = NotePayload(
            id: "note-1",
            name: "Open.md",
            content: "Refreshed",
            path: "note-1",
            modified: 200,
            created: nil
        )
        let api = SequencedNotesAPI(
            treeResults: [],
            noteResults: [
                .success(initial),
                .success(refreshed)
            ]
        )
        let store = NotesStore(api: api, cache: InMemoryCacheClient())
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.loadNote(id: "note-1")
        XCTAssertEqual(viewModel.activeNote?.content, "Initial")

        await viewModel.refreshSelectedNoteIfNeeded()

        XCTAssertEqual(viewModel.activeNote?.content, "Refreshed")
    }
}

@MainActor
private func makeNotesWriteQueue(persistence: PersistenceController = PersistenceController(inMemory: true)) -> WriteQueue {
    let connectivityMonitor = ConnectivityMonitor(
        baseUrl: URL(string: "http://localhost")!,
        startMonitoring: false
    )
    return WriteQueue(
        container: persistence.container,
        connectivityMonitor: connectivityMonitor,
        autoProcessEnabled: false
    )
}

@MainActor
private func fetchOnlyPendingWrite(from persistence: PersistenceController) throws -> PendingWrite {
    let request = PendingWrite.fetchRequest()
    let writes = try persistence.container.viewContext.fetch(request)
    XCTAssertEqual(writes.count, 1)
    return try XCTUnwrap(writes.first)
}

@MainActor
private func fetchFirstPendingSummary(from writeQueue: WriteQueue) async throws -> PendingWriteSummary {
    let pending = try await writeQueue.fetchPendingWrites()
    return try XCTUnwrap(pending.first)
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

@MainActor
private final class SequencedNotesAPI: NotesProviding {
    private var treeResults: [Result<FileTree, Error>]
    private var noteResults: [Result<NotePayload, Error>]

    init(
        treeResults: [Result<FileTree, Error>],
        noteResults: [Result<NotePayload, Error>]
    ) {
        self.treeResults = treeResults
        self.noteResults = noteResults
    }

    func listTree() async throws -> FileTree {
        guard !treeResults.isEmpty else { return FileTree(children: []) }
        return try treeResults.removeFirst().get()
    }

    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        return FileTree(children: [])
    }

    func getNote(id: String) async throws -> NotePayload {
        _ = id
        guard !noteResults.isEmpty else { throw MockError.forced }
        return try noteResults.removeFirst().get()
    }

    func search(query: String, limit: Int) async throws -> [FileNode] {
        _ = query
        _ = limit
        return []
    }

    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        _ = id
        _ = document
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
