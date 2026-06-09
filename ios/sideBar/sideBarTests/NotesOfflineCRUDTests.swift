import Foundation
import XCTest
@testable import sideBar

@MainActor
final class NotesOfflineCRUDTests: XCTestCase {
    func testCreateBlankNoteOfflineQueuesCreateAndPersistsLocalSnapshot() async throws {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = NotesOfflineCRUDAPISpy()
        let store = NotesStore(
            api: api,
            cache: cache,
            offlineStore: offlineStore,
            networkStatus: NotesOfflineNetworkStatus(isNetworkAvailable: false, isOffline: true)
        )
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
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: NotesOfflineNetworkStatus(isNetworkAvailable: false, isOffline: true)
        )

        let created = await viewModel.createBlankNote()

        let note = try XCTUnwrap(created)
        let pending = try await writeQueue.fetchPendingWrites()
        let cached: NotePayload? = offlineStore.get(key: CacheKeys.note(id: note.id), as: NotePayload.self)

        XCTAssertEqual(api.createNoteCallCount, 0)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.operationType, WriteOperation.create.rawValue)
        XCTAssertEqual(pending.first?.entityType, WriteEntityType.note.rawValue)
        XCTAssertEqual(note.id, note.path)
        XCTAssertEqual(viewModel.selectedNoteId, note.id)
        XCTAssertEqual(store.tree?.children.first?.path, note.id)
        XCTAssertEqual(store.activeNote?.id, note.id)
        XCTAssertEqual(cached?.id, note.id)
    }

    func testCreateBlankNoteOnlineQueuesLocalNoteWithoutCallingCreateAPI() async throws {
        let context = makeNotesLocalFirstCRUDContext(networkAvailable: true)

        let created = await context.viewModel.createBlankNote()

        let note = try XCTUnwrap(created)
        let pending = try await context.writeQueue.fetchPendingWrites()

        XCTAssertEqual(context.api.createNoteCallCount, 0)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.operationType, WriteOperation.create.rawValue)
        XCTAssertEqual(pending.first?.entityType, WriteEntityType.note.rawValue)
        XCTAssertEqual(note.id, note.path)
        XCTAssertEqual(context.viewModel.selectedNoteId, note.id)
        XCTAssertEqual(context.store.tree?.children.first?.path, note.id)
    }

    func testCreateFolderOfflineUpdatesTreeAndQueuesCreate() async throws {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let api = NotesOfflineCRUDAPISpy()
        let store = NotesStore(
            api: api,
            cache: TestCacheClient(),
            offlineStore: offlineStore,
            networkStatus: NotesOfflineNetworkStatus(isNetworkAvailable: false, isOffline: true)
        )
        store.applyTreeUpdate(FileTree(children: []), persist: false)
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
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: NotesOfflineNetworkStatus(isNetworkAvailable: false, isOffline: true)
        )

        let created = await viewModel.createFolder(path: "Projects")

        let pending = try await writeQueue.fetchPendingWrites()
        XCTAssertTrue(created)
        XCTAssertEqual(api.createFolderCallCount, 0)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.operationType, WriteOperation.create.rawValue)
        XCTAssertEqual(pending.first?.entityType, WriteEntityType.noteFolder.rawValue)
        XCTAssertEqual(store.tree?.children.first?.path, "folder:Projects")
    }

    func testRenameFolderOfflinePreservesLocalTreeStateUntilSync() async throws {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let api = NotesOfflineCRUDAPISpy()
        let store = NotesStore(
            api: api,
            cache: TestCacheClient(),
            offlineStore: offlineStore,
            networkStatus: NotesOfflineNetworkStatus(isNetworkAvailable: false, isOffline: true)
        )
        store.applyTreeUpdate(
            FileTree(children: [
                FileNode(
                    name: "Projects",
                    path: "folder:Projects",
                    type: .directory,
                    size: nil,
                    modified: nil,
                    created: nil,
                    children: [
                        FileNode(
                            name: "Draft",
                            path: "note-1",
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
                    expanded: true,
                    pinned: nil,
                    pinnedOrder: nil,
                    archived: nil,
                    folderMarker: true
                )
            ]),
            persist: false
        )
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
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: NotesOfflineNetworkStatus(isNetworkAvailable: false, isOffline: true)
        )

        await viewModel.renameFolder(path: "folder:Projects", newName: "Roadmap")

        let pending = try await writeQueue.fetchPendingWrites()
        XCTAssertEqual(api.renameFolderCallCount, 0)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.operationType, WriteOperation.rename.rawValue)
        XCTAssertEqual(pending.first?.entityType, WriteEntityType.noteFolder.rawValue)
        XCTAssertEqual(store.tree?.children.first?.path, "folder:Roadmap")
        XCTAssertEqual(store.tree?.children.first?.name, "Roadmap")
    }

    func testRenameNoteOnlineQueuesUpdateAndKeepsOptimisticTitle() async throws {
        let context = makeNotesLocalFirstCRUDContext(networkAvailable: true)
        let document = NotesSemanticDocument(
            blocks: [.init(type: .title, content: [.init(text: "Old", marks: [])])]
        )
        let note = NotePayload(
            id: "note-1",
            name: "Old",
            document: document,
            plainText: "Old",
            path: "note-1",
            modified: nil,
            created: nil
        )
        context.store.applyTreeUpdate(
            FileTree(children: [
                FileNode(
                    name: "Old",
                    path: "note-1",
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
            ]),
            persist: false
        )
        context.store.applyEditorUpdate(note)

        await context.viewModel.renameNote(id: "note-1", newName: "New")

        let pending = try await context.writeQueue.fetchPendingWrites()
        XCTAssertEqual(context.api.updateNoteCallCount, 0)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.operationType, WriteOperation.update.rawValue)
        XCTAssertEqual(pending.first?.entityType, WriteEntityType.note.rawValue)
        XCTAssertEqual(context.viewModel.activeNote?.name, "New")
    }
}

@MainActor
private struct NotesLocalFirstCRUDContext {
    let viewModel: NotesViewModel
    let store: NotesStore
    let writeQueue: WriteQueue
    let api: NotesOfflineCRUDAPISpy
}

@MainActor
private func makeNotesLocalFirstCRUDContext(
    networkAvailable: Bool,
    isOffline: Bool = false
) -> NotesLocalFirstCRUDContext {
    let persistence = PersistenceController(inMemory: true)
    let offlineStore = OfflineStore(container: persistence.container)
    let api = NotesOfflineCRUDAPISpy()
    let networkStatus = NotesOfflineNetworkStatus(
        isNetworkAvailable: networkAvailable,
        isOffline: isOffline
    )
    let store = NotesStore(
        api: api,
        cache: TestCacheClient(),
        offlineStore: offlineStore,
        networkStatus: networkStatus
    )
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
    let viewModel = NotesViewModel(
        api: api,
        store: store,
        toastCenter: ToastCenter(),
        networkStatus: networkStatus
    )
    return NotesLocalFirstCRUDContext(
        viewModel: viewModel,
        store: store,
        writeQueue: writeQueue,
        api: api
    )
}

@MainActor
private struct NotesOfflineNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool
    let isOffline: Bool
    let isServerReachable: Bool

    init(
        isNetworkAvailable: Bool,
        isOffline: Bool = false,
        isServerReachable: Bool = true
    ) {
        self.isNetworkAvailable = isNetworkAvailable
        self.isOffline = isOffline
        self.isServerReachable = isServerReachable
    }
}

@MainActor
private final class NotesOfflineCRUDAPISpy: NotesProviding {
    private(set) var createNoteCallCount = 0
    private(set) var createFolderCallCount = 0
    private(set) var renameFolderCallCount = 0
    private(set) var updateNoteCallCount = 0

    func listTree() async throws -> FileTree { FileTree(children: []) }

    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        return FileTree(children: [])
    }

    func getNote(id: String) async throws -> NotePayload {
        NotePayload(id: id, name: "Note", content: "", path: id, modified: nil, created: nil)
    }

    func search(query: String, limit: Int) async throws -> [FileNode] {
        _ = query
        _ = limit
        return []
    }

    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        updateNoteCallCount += 1
        return NotePayload(
            id: id,
            name: NotesSemanticDocumentProjection.title(from: document),
            document: document,
            path: id,
            modified: nil,
            created: nil
        )
    }

    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        createNoteCallCount += 1
        return NotePayload(
            id: request.clientId ?? UUID().uuidString,
            name: request.title ?? "New Note",
            document: request.document,
            path: request.clientId ?? UUID().uuidString,
            modified: nil,
            created: nil
        )
    }

    func renameNote(id: String, newName: String) async throws -> NotePayload {
        return NotePayload(id: id, name: newName, content: "", path: id, modified: nil, created: nil)
    }

    func moveNote(id: String, folder: String) async throws -> NotePayload {
        _ = folder
        return NotePayload(id: id, name: "Note", content: "", path: id, modified: nil, created: nil)
    }

    func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        _ = archived
        return NotePayload(id: id, name: "Note", content: "", path: id, modified: nil, created: nil)
    }

    func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        _ = pinned
        return NotePayload(id: id, name: "Note", content: "", path: id, modified: nil, created: nil)
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
    }

    func deleteNote(id: String) async throws -> NotePayload {
        return NotePayload(id: id, name: "Note", content: "", path: id, modified: nil, created: nil)
    }

    func createFolder(path: String) async throws {
        _ = path
        createFolderCallCount += 1
    }

    func renameFolder(oldPath: String, newName: String) async throws {
        _ = oldPath
        _ = newName
        renameFolderCallCount += 1
    }

    func moveFolder(oldPath: String, newParent: String) async throws {
        _ = oldPath
        _ = newParent
    }

    func deleteFolder(path: String) async throws {
        _ = path
    }
}
