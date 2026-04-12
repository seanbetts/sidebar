import Foundation
import sideBarShared
@testable import sideBar

final class NotesDetailViewDelayingNotesAPI: NotesProviding {
    private let updateDelayNanoseconds: UInt64
    private(set) var updateCallCount = 0

    init(updateDelayNanoseconds: UInt64) {
        self.updateDelayNanoseconds = updateDelayNanoseconds
    }

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

    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        updateCallCount += 1
        try? await Task.sleep(nanoseconds: updateDelayNanoseconds)
        return NotePayload(
            id: id,
            name: "Delayed semantic title",
            document: document,
            plainText: NotesSemanticDocumentProjection.plainText(from: document),
            path: "/note.md",
            modified: 100,
            created: nil
        )
    }

    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        _ = request
        throw NotesDetailViewTestError.forced
    }

    func renameNote(id: String, newName: String) async throws -> NotePayload {
        _ = id
        _ = newName
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
