import Foundation
import sideBarShared
import XCTest
@testable import sideBar

final class ControlledNotesRealtimeAPI: NotesProviding {
    private let noteResults: [String: Result<NotePayload, Error>]
    private let treeResult: FileTree
    private var immediateNoteResults: [String: Result<NotePayload, Error>] = [:]
    private var continuations: [String: CheckedContinuation<NotePayload, Error>] = [:]
    private(set) var pendingGetNoteIDs = Set<String>()

    init(noteResults: [String: Result<NotePayload, Error>], treeResult: FileTree) {
        self.noteResults = noteResults
        self.treeResult = treeResult
    }

    func setImmediateNoteResult(_ result: Result<NotePayload, Error>, for id: String) {
        immediateNoteResults[id] = result
    }

    func listTree() async throws -> FileTree { treeResult }

    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        return FileTree(children: [])
    }

    func getNote(id: String) async throws -> NotePayload {
        if let immediateResult = immediateNoteResults[id] {
            return try immediateResult.get()
        }
        guard let result = noteResults[id] else {
            throw NotesStoreTestsSupport.MockError.forced
        }
        if case .failure(let error) = result { throw error }
        pendingGetNoteIDs.insert(id)
        return try await withCheckedThrowingContinuation { continuation in
            continuations[id] = continuation
        }
    }

    func waitUntilGetNotePending(id: String) async {
        let timeout = Date().addingTimeInterval(2)
        while Date() < timeout {
            if pendingGetNoteIDs.contains(id) {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for pending getNote(\(id))")
    }

    func resumeGetNote(id: String) {
        guard let result = noteResults[id],
              let continuation = continuations.removeValue(forKey: id) else {
            return
        }
        pendingGetNoteIDs.remove(id)
        continuation.resume(with: result)
    }

    func search(query: String, limit: Int) async throws -> [FileNode] { _ = query; _ = limit; return [] }
    func updateNote(id: String, content: String) async throws -> NotePayload { _ = content; return try await getNote(id: id) }

    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        try await updateNote(id: id, content: NotesSemanticDocumentProjection.plainText(from: document))
    }

    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        _ = request
        throw NotesStoreTestsSupport.MockError.forced
    }

    func renameNote(id: String, newName: String) async throws -> NotePayload { _ = newName; return try await getNote(id: id) }
    func moveNote(id: String, folder: String) async throws -> NotePayload { _ = folder; return try await getNote(id: id) }
    func archiveNote(id: String, archived: Bool) async throws -> NotePayload { _ = archived; return try await getNote(id: id) }
    func pinNote(id: String, pinned: Bool) async throws -> NotePayload { _ = pinned; return try await getNote(id: id) }
    func updatePinnedOrder(ids: [String]) async throws { _ = ids }
    func deleteNote(id: String) async throws -> NotePayload { try await getNote(id: id) }
    func createFolder(path: String) async throws { _ = path }

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
