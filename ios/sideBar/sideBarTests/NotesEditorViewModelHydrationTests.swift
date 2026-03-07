import Foundation
import SwiftUI
import XCTest
@testable import sideBar

@MainActor
final class NotesEditorViewModelHydrationTests: XCTestCase {
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
        await Task.yield()

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
