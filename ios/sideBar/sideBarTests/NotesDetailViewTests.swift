import SwiftUI
import XCTest
@testable import sideBar

@MainActor
final class NotesDetailViewTests: XCTestCase {
    func testNotesDetailViewTypeLoads() {
        XCTAssertNotNil(NotesDetailView.self)
    }

    func testDisplayTitleUsesActiveNoteName() async {
        let api = NotesDetailViewMockNotesAPI()
        let store = NotesStore(api: api, cache: InMemoryCacheClient())
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: NotesDetailViewTestNetworkStatus(isNetworkAvailable: true)
        )
        let persistence = PersistenceController(inMemory: true)
        let editorViewModel = NotesEditorViewModel(
            notesViewModel: notesViewModel,
            draftStorage: DraftStorage(container: persistence.container),
            writeQueue: WriteQueue(
                container: persistence.container,
                connectivityMonitor: ConnectivityMonitor(
                    baseUrl: URL(string: "http://localhost")!,
                    startMonitoring: false
                ),
                autoProcessEnabled: false
            ),
            networkStatus: NotesDetailViewTestNetworkStatus(isNetworkAvailable: true)
        )
        store.applyEditorUpdate(
            NotePayload(
                id: "n1",
                name: "Semantic title",
                document: NotesSemanticDocumentProjection.document(fromPlainText: "Semantic title"),
                plainText: "Semantic title",
                path: "/note.md",
                modified: nil,
                created: nil
            )
        )
        await Task.yield()
        let view = NotesDetailView(
            viewModel: notesViewModel,
            editorViewModel: editorViewModel,
            isMoveSheetPresented: .constant(false),
            moveSelection: .constant(""),
            isDeleteAlertPresented: .constant(false),
            isExporting: .constant(false),
            exportDocument: .constant(nil),
            exportFilename: .constant("")
        )

        XCTAssertEqual(view.displayTitle, "Semantic title")
    }
}

@MainActor
private struct NotesDetailViewTestNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool
    let isOffline: Bool = false
}

@MainActor
private struct NotesDetailViewMockNotesAPI: NotesProviding {
    func listTree() async throws -> FileTree { FileTree(children: []) }
    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        return FileTree(children: [])
    }
    func getNote(id: String) async throws -> NotePayload {
        _ = id
        throw NotesDetailViewTestError.forced
    }
    func search(query: String, limit: Int) async throws -> [FileNode] {
        _ = query
        _ = limit
        return []
    }
    func updateNote(id: String, content: String) async throws -> NotePayload {
        _ = id
        _ = content
        throw NotesDetailViewTestError.forced
    }
    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        _ = request
        throw NotesDetailViewTestError.forced
    }
    func moveNote(id: String, folder: String) async throws -> NotePayload {
        _ = id
        _ = folder
        throw NotesDetailViewTestError.forced
    }
    func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        _ = id
        _ = archived
        throw NotesDetailViewTestError.forced
    }
    func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        _ = id
        _ = pinned
        throw NotesDetailViewTestError.forced
    }
    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
    }
    func deleteNote(id: String) async throws -> NotePayload {
        _ = id
        throw NotesDetailViewTestError.forced
    }
    func createFolder(path: String) async throws { _ = path }
    func renameFolder(oldPath: String, newName: String) async throws {
        _ = oldPath
        _ = newName
    }
    func moveFolder(oldPath: String, newParent: String) async throws {
        _ = oldPath
        _ = newParent
    }
    func deleteFolder(path: String) async throws { _ = path }
}

private enum NotesDetailViewTestError: Error {
    case forced
}
