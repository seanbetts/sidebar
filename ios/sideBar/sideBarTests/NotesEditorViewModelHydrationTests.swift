import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif
import XCTest
@testable import sideBar

@MainActor
final class NotesEditorViewModelHydrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        NotesDetailViewTestRetainer.reset()
    }

    override func tearDown() {
        NotesDetailViewTestRetainer.reset()
        super.tearDown()
    }

    func testHydrationStartsWithoutRetainedMountedNotesDetailViews() {
        XCTAssertTrue(NotesDetailViewTestRetainer.environments.isEmpty)
        XCTAssertTrue(NotesDetailViewTestRetainer.hostingControllers.isEmpty)
        XCTAssertTrue(NotesDetailViewTestRetainer.hostingWindows.isEmpty)
    }

    #if os(iOS)
    func testResetDetachesMountedNotesEnvironmentBeforeNextTest() async {
        let context = await makeNotesDetailViewTestContext()
        weak var weakController: UIHostingController<AnyView>?
        weak var weakWindow: UIWindow?
        weak var weakEnvironment: AppEnvironment?
        defer {
            NotesDetailViewTestRetainer.parkedHostBatches.removeAll()
            drainNotesHostingRunLoop()
        }

        let environment = makeNotesDetailTestEnvironment()
        weakEnvironment = environment
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: false)
        weakController = controller
        weakWindow = controller.view.window

        XCTAssertNotNil(weakEnvironment)
        XCTAssertNotNil(weakController)
        XCTAssertNotNil(weakWindow)

        NotesDetailViewTestRetainer.reset()

        let sceneWindows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let windowStillInScene = weakWindow.map { window in
            sceneWindows.contains { $0 === window }
        } ?? false
        let controllerStillMountedInScene = sceneWindows.contains { $0.rootViewController === weakController }

        XCTAssertTrue(NotesDetailViewTestRetainer.environments.isEmpty)
        XCTAssertTrue(NotesDetailViewTestRetainer.hostingControllers.isEmpty)
        XCTAssertTrue(NotesDetailViewTestRetainer.hostingWindows.isEmpty)
        XCTAssertNotNil(weakEnvironment)
        XCTAssertNotNil(weakController)
        XCTAssertNotNil(weakWindow)
        XCTAssertFalse(windowStillInScene)
        XCTAssertFalse(controllerStillMountedInScene)
        XCTAssertNil(weakWindow?.rootViewController)
        XCTAssertEqual(weakWindow?.isHidden, true)
        XCTAssertNil(AppEnvironment.shared)
    }
    #endif

    func testAttachNativeEditorDoesNotOverwriteLoadedNoteState() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }
        let api = HydrationMockNotesAPI(updateResult: .failure(HydrationMockError.forced))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: HydrationTestNetworkStatus(isNetworkAvailable: true)
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
            networkStatus: HydrationTestNetworkStatus(isNetworkAvailable: true)
        )
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: "Hello",
            path: "/note.md",
            modified: 100,
            created: nil
        )

        store.applyEditorUpdate(note)
        try await waitUntilHydrated(timeoutSeconds: 2.0) {
            viewModel.currentNoteId == "n1"
                && viewModel.content == "Hello"
                && NotesSemanticDocumentCodec.decode(viewModel.canonicalContent)
                .map(NotesSemanticDocumentProjection.plainText(from:)) == "Hello"
        }

        let beforeCanonical = viewModel.canonicalContent
        let nativeViewModel = NativeNoteEditorViewModel()
        viewModel.attachNativeEditor(nativeViewModel)

        XCTAssertEqual(viewModel.currentNoteId, "n1")
        XCTAssertEqual(viewModel.content, "Hello")
        XCTAssertEqual(viewModel.canonicalContent, beforeCanonical)
        XCTAssertEqual(
            NotesSemanticDocumentCodec.decode(viewModel.canonicalContent)
                .map(NotesSemanticDocumentProjection.plainText(from:)),
            "Hello"
        )
    }

    func testQueuedSaveKeepsActiveEditorOnLocalSnapshotUntilAcknowledgement() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }
        let savedNote = NotePayload(
            id: "n1",
            name: "Local edit",
            document: NotesSemanticDocumentProjection.document(fromPlainText: "Local edit"),
            plainText: "Local edit",
            path: "/note.md",
            modified: 200,
            created: nil
        )
        let context = makeQueuedSaveHydrationTestContext(savedNote: savedNote)

        context.store.applyEditorUpdate(context.note)
        try await waitUntilHydrated(timeoutSeconds: 2.0) {
            context.viewModel.currentNoteId == "n1" && context.viewModel.content == "Hello"
        }

        let nativeViewModel = context.viewModel.makeNativeEditorViewModel()
        context.viewModel.attachNativeEditor(nativeViewModel)
        context.viewModel.enterEditMode()
        nativeViewModel.attributedContent = AttributedString("Local edit")
        nativeViewModel.handleContentChange(previous: AttributedString("Hello"))

        try await waitUntilHydrated(timeoutSeconds: 2.0) {
            nativeViewModel.hasUnsavedChanges
        }

        await context.viewModel.syncFromNativeEditor(nativeViewModel)

        try await waitUntilHydrated(timeoutSeconds: 2.0) {
            context.viewModel.content == "Local edit"
                && context.notesViewModel.activeNote?.plainText == "Local edit"
                && context.notesViewModel.activeNote?.name == "Local edit"
                && context.viewModel.isQueuedForSync
        }

        let pendingWrites = try await context.writeQueue.fetchPendingWrites()
        XCTAssertEqual(pendingWrites.count, 1)
        XCTAssertEqual(context.viewModel.content, "Local edit")
        XCTAssertEqual(context.viewModel.canonicalContent, canonicalUIKitPlainTextPass("Local edit"))
        XCTAssertEqual(context.notesViewModel.activeNote?.plainText, "Local edit")
        XCTAssertEqual(context.notesViewModel.activeNote?.name, "Local edit")
        XCTAssertEqual(context.notesViewModel.activeNote?.modified, 100)
        XCTAssertTrue(context.viewModel.isQueuedForSync)
        XCTAssertNil(context.viewModel.lastSavedAt)
        XCTAssertFalse(nativeViewModel.hasUnsavedChanges)
        XCTAssertEqual(nativeViewModel.currentPersistenceSnapshot().plainText, "Local edit")

        context.store.applyEditorUpdate(savedNote)

        try await waitUntilHydrated(timeoutSeconds: 2.0) {
            context.notesViewModel.activeNote?.modified == 200
                && context.viewModel.isQueuedForSync == false
                && context.viewModel.lastSavedAt != nil
        }

        XCTAssertFalse(context.viewModel.isQueuedForSync)
        XCTAssertEqual(context.notesViewModel.activeNote?.modified, 200)
        XCTAssertNotNil(context.viewModel.lastSavedAt)
    }
}

private struct QueuedSaveHydrationTestContext {
    let note: NotePayload
    let store: NotesStore
    let notesViewModel: NotesViewModel
    let viewModel: NotesEditorViewModel
    let writeQueue: WriteQueue
}

@MainActor
private func makeQueuedSaveHydrationTestContext(savedNote: NotePayload) -> QueuedSaveHydrationTestContext {
    let api = HydrationMockNotesAPI(updateResult: .success(savedNote))
    let store = NotesStore(api: api, cache: TestCacheClient())
    let notesViewModel = NotesViewModel(
        api: api,
        store: store,
        toastCenter: ToastCenter(),
        networkStatus: HydrationTestNetworkStatus(isNetworkAvailable: true)
    )
    let persistence = PersistenceController(inMemory: true)
    let writeQueue = WriteQueue(
        container: persistence.container,
        connectivityMonitor: ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        ),
        autoProcessEnabled: false
    )
    let viewModel = NotesEditorViewModel(
        notesViewModel: notesViewModel,
        draftStorage: DraftStorage(container: persistence.container),
        writeQueue: writeQueue,
        networkStatus: HydrationTestNetworkStatus(isNetworkAvailable: true)
    )
    let note = NotePayload(
        id: "n1",
        name: "Note",
        document: NotesSemanticDocumentProjection.document(fromPlainText: "Hello"),
        plainText: "Hello",
        path: "/note.md",
        modified: 100,
        created: nil
    )

    return QueuedSaveHydrationTestContext(
        note: note,
        store: store,
        notesViewModel: notesViewModel,
        viewModel: viewModel,
        writeQueue: writeQueue
    )
}

@MainActor
private func waitUntilHydrated(
    timeoutSeconds: TimeInterval,
    condition: @escaping () -> Bool
) async throws {
    let timeout = Date().addingTimeInterval(timeoutSeconds)
    while Date() < timeout {
        if condition() {
            return
        }
        await Task.yield()
    }
    XCTFail("Timed out waiting for hydrated note state")
}

private enum HydrationMockError: Error {
    case forced
}

@MainActor
private struct HydrationTestNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool
    let isOffline: Bool

    init(isNetworkAvailable: Bool, isOffline: Bool = false) {
        self.isNetworkAvailable = isNetworkAvailable
        self.isOffline = isOffline
    }
}

@MainActor
private struct HydrationMockNotesAPI: NotesProviding {
    let updateResult: Result<NotePayload, Error>

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
        return try updateResult.get()
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

    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        try await updateNote(
            id: id,
            content: NotesSemanticDocumentProjection.plainText(from: document)
        )
    }

    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        _ = request
        return try updateResult.get()
    }

    func renameNote(id: String, newName: String) async throws -> NotePayload {
        _ = id
        _ = newName
        return try updateResult.get()
    }

    func moveNote(id: String, folder: String) async throws -> NotePayload {
        _ = id
        _ = folder
        return try updateResult.get()
    }

    func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        _ = id
        _ = archived
        return try updateResult.get()
    }

    func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        _ = id
        _ = pinned
        return try updateResult.get()
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
    }

    func deleteNote(id: String) async throws -> NotePayload {
        _ = id
        return try updateResult.get()
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
