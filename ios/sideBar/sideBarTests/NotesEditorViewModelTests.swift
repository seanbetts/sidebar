import Foundation
import sideBarShared
import XCTest
@testable import sideBar

@MainActor
final class NotesEditorViewModelTests: XCTestCase {
    func testHandleNoteUpdateSetsContentAndBaseline() async {
        let api = MockNotesAPI(updateResult: .failure(MockError.forced))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let persistence = PersistenceController(inMemory: true)
        let draftStorage = DraftStorage(container: persistence.container)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let writeQueue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false
        )
        let viewModel = NotesEditorViewModel(
            notesViewModel: notesViewModel,
            draftStorage: draftStorage,
            writeQueue: writeQueue,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let note = NotePayload(id: "n1", name: "Note", content: "Hello", path: "/note.md", modified: nil, created: nil)

        store.applyEditorUpdate(note)
        await Task.yield()

        XCTAssertEqual(viewModel.currentNoteId, "n1")
        XCTAssertEqual(viewModel.content, "Hello")
    }

    func testHandleNoteUpdateClearsContentWhenNoteNil() async {
        let api = MockNotesAPI(updateResult: .failure(MockError.forced))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let persistence = PersistenceController(inMemory: true)
        let draftStorage = DraftStorage(container: persistence.container)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let writeQueue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false
        )
        let viewModel = NotesEditorViewModel(
            notesViewModel: notesViewModel,
            draftStorage: draftStorage,
            writeQueue: writeQueue,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let note = NotePayload(id: "n1", name: "Note", content: "Hello", path: "/note.md", modified: nil, created: nil)

        store.applyEditorUpdate(note)
        await Task.yield()
        store.clearActiveNote()
        await Task.yield()

        XCTAssertNil(viewModel.currentNoteId)
        XCTAssertEqual(viewModel.content, "")
    }

    func testSyncFromNativeEditorUpdatesContent() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }
        let updated = NotePayload(id: "n1", name: "Note", content: "Updated", path: "/note.md", modified: 100, created: nil)
        let api = MockNotesAPI(updateResult: .success(updated))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let persistence = PersistenceController(inMemory: true)
        let draftStorage = DraftStorage(container: persistence.container)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let writeQueue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false
        )
        let viewModel = NotesEditorViewModel(
            notesViewModel: notesViewModel,
            draftStorage: draftStorage,
            writeQueue: writeQueue,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let note = NotePayload(id: "n1", name: "Note", content: "Hello", path: "/note.md", modified: nil, created: nil)

        store.applyEditorUpdate(note)
        await Task.yield()

        let nativeViewModel = viewModel.makeNativeEditorViewModel()
        nativeViewModel.attributedContent = AttributedString("Updated")
        nativeViewModel.handleContentChange(previous: AttributedString("Hello"))
        try? await Task.sleep(nanoseconds: 1_700_000_000)

        XCTAssertTrue(nativeViewModel.hasUnsavedChanges)

        await viewModel.syncFromNativeEditor(nativeViewModel)

        XCTAssertEqual(store.activeNote?.content, "Updated")
        XCTAssertFalse(nativeViewModel.hasUnsavedChanges)
    }

    func testLoadsUnsyncedDraftWhenAvailable() async throws {
        let api = MockNotesAPI(updateResult: .failure(MockError.forced))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let persistence = PersistenceController(inMemory: true)
        let draftStorage = DraftStorage(container: persistence.container)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let writeQueue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false
        )
        let viewModel = NotesEditorViewModel(
            notesViewModel: notesViewModel,
            draftStorage: draftStorage,
            writeQueue: writeQueue,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let note = NotePayload(id: "n1", name: "Note", content: "Server", path: "/note.md", modified: nil, created: nil)

        try draftStorage.saveDraft(entityType: "note", entityId: "n1", content: "Draft")
        store.applyEditorUpdate(note)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(viewModel.content, "Draft")
        XCTAssertTrue(viewModel.isDirty)
    }

    func testDetectsConflictWhenServerIsNewer() async throws {
        let api = MockNotesAPI(updateResult: .failure(MockError.forced))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let persistence = PersistenceController(inMemory: true)
        let draftStorage = DraftStorage(container: persistence.container)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let writeQueue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false
        )
        let viewModel = NotesEditorViewModel(
            notesViewModel: notesViewModel,
            draftStorage: draftStorage,
            writeQueue: writeQueue,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let serverDate = Date().addingTimeInterval(60)
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: "Server",
            path: "/note.md",
            modified: serverDate.timeIntervalSince1970,
            created: nil)

        try draftStorage.saveDraft(entityType: "note", entityId: "n1", content: "Draft")
        store.applyEditorUpdate(note)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(viewModel.content, "Server")
        XCTAssertNotNil(viewModel.conflict)
    }

    func testOfflineSaveQueuesDraftWithoutApiCall() async throws {
        let api = NotesAPISpy(updateResult: .failure(MockError.forced))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let persistence = PersistenceController(inMemory: true)
        let draftStorage = DraftStorage(container: persistence.container)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let writeQueue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false
        )
        let viewModel = NotesEditorViewModel(
            notesViewModel: notesViewModel,
            draftStorage: draftStorage,
            writeQueue: writeQueue,
            networkStatus: TestNetworkStatus(isNetworkAvailable: false)
        )
        let note = NotePayload(id: "n1", name: "Note", content: "Hello", path: "/note.md", modified: nil, created: nil)

        store.applyEditorUpdate(note)
        await Task.yield()

        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }
        let nativeViewModel = viewModel.makeNativeEditorViewModel()
        nativeViewModel.attributedContent = AttributedString("Offline Draft")
        nativeViewModel.handleContentChange(previous: AttributedString("Hello"))
        try? await Task.sleep(nanoseconds: 1_700_000_000)

        await viewModel.syncFromNativeEditor(nativeViewModel)

        XCTAssertTrue(viewModel.isQueuedForSync)
        XCTAssertFalse(viewModel.isSaving)
        XCTAssertEqual(api.updateCallCount, 0)
        let pending = await writeQueue.fetchPendingWrites()
        XCTAssertEqual(pending.count, 1)
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
    private(set) var updateCallCount = 0
    let updateResult: Result<NotePayload, Error>

    init(updateResult: Result<NotePayload, Error>) {
        self.updateResult = updateResult
    }

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
        updateCallCount += 1
        return try updateResult.get()
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

private final class MockNotesAPI: NotesProviding {
    let updateResult: Result<NotePayload, Error>

    init(updateResult: Result<NotePayload, Error>) {
        self.updateResult = updateResult
    }

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
        return try updateResult.get()
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
