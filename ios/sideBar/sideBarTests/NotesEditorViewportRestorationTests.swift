import XCTest
@testable import sideBar

@MainActor
final class NotesEditorViewportRestorationTests: XCTestCase {
    func testExitEditModeStoresPendingReadViewportRestoration() async {
        let context = makeNotesEditorViewModelTestContext(
            api: EditViewportMockNotesAPI(updateResult: .failure(EditViewportMockError.forced))
        )
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: "Hello",
            path: "/note.md",
            modified: nil,
            created: nil
        )

        context.store.applyEditorUpdate(note)
        try? await NotesStoreTestsSupport.waitUntilCondition(timeoutSeconds: 5.0) {
            context.viewModel.currentNoteId == note.id &&
                context.viewModel.content == note.plainText &&
                NotesSemanticDocumentCodec.decode(context.viewModel.canonicalContent) == note.document
        }
        context.viewModel.enterEditMode()
        context.viewModel.recordLiveEditorViewportSnapshot(
            offset: CGPoint(x: 0, y: 312),
            selectedUTF16Range: NSRange(location: 2, length: 0),
            selectionViewportAnchorY: 187
        )

        context.viewModel.exitEditModeToRead()

        XCTAssertEqual(
            context.viewModel.consumePendingReadViewportRestoration(),
            NotesEditorViewModel.PendingReadViewportRestoration(
                offset: CGPoint(x: 0, y: 312),
                target: nil,
                viewportAnchorY: nil
            )
        )
        XCTAssertNil(context.viewModel.consumePendingReadViewportRestoration())
    }
}

private enum EditViewportMockError: Error {
    case forced
}

private final class EditViewportMockNotesAPI: NotesProviding {
    let updateResult: Result<NotePayload, Error>

    init(updateResult: Result<NotePayload, Error>) {
        self.updateResult = updateResult
    }

    func listTree() async throws -> FileTree {
        throw EditViewportMockError.forced
    }

    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        throw EditViewportMockError.forced
    }

    func getNote(id: String) async throws -> NotePayload {
        _ = id
        throw EditViewportMockError.forced
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
        throw EditViewportMockError.forced
    }

    func renameNote(id: String, newName: String) async throws -> NotePayload {
        _ = id
        _ = newName
        throw EditViewportMockError.forced
    }

    func moveNote(id: String, folder: String) async throws -> NotePayload {
        _ = id
        _ = folder
        throw EditViewportMockError.forced
    }

    func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        _ = id
        _ = archived
        throw EditViewportMockError.forced
    }

    func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        _ = id
        _ = pinned
        throw EditViewportMockError.forced
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
    }

    func deleteNote(id: String) async throws -> NotePayload {
        _ = id
        throw EditViewportMockError.forced
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
