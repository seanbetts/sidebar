import Foundation
import sideBarShared
import XCTest
@testable import sideBar

enum NotesStoreTestsSupport {
    enum MockError: Error {
        case forced
    }

    @MainActor
    static func waitUntilCondition(
        timeoutSeconds: TimeInterval,
        condition: @escaping () async -> Bool
    ) async throws {
        let timeout = Date().addingTimeInterval(timeoutSeconds)
        while Date() < timeout {
            if await condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for notes store condition")
    }

    @MainActor
    struct TestNetworkStatus: NetworkStatusProviding {
        let isNetworkAvailable: Bool
        let isOffline: Bool

        init(isNetworkAvailable: Bool, isOffline: Bool = false) {
            self.isNetworkAvailable = isNetworkAvailable
            self.isOffline = isOffline
        }
    }

    private actor ArchivedListCallCounter {
        private var count = 0

        func increment() {
            count += 1
        }

        var current: Int {
            count
        }
    }

    final class MockNotesAPI: NotesProviding {
        private let archivedListCounter = ArchivedListCallCounter()

        let treeResult: Result<FileTree, Error>
        let noteResult: Result<NotePayload, Error>
        var onList: (() -> Void)?
        var listDelay: TimeInterval?
        var onArchivedList: (() -> Void)?
        var archivedListDelay: TimeInterval?

        var archivedListCallCount: Int {
            get async {
                await archivedListCounter.current
            }
        }

        init(treeResult: Result<FileTree, Error>, noteResult: Result<NotePayload, Error>) {
            self.treeResult = treeResult
            self.noteResult = noteResult
        }

        func listTree() async throws -> FileTree {
            if let listDelay {
                try? await Task.sleep(nanoseconds: UInt64(listDelay * 1_000_000_000))
            }
            onList?()
            return try treeResult.get()
        }

        func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
            _ = limit
            _ = offset
            await archivedListCounter.increment()
            if let archivedListDelay {
                try? await Task.sleep(nanoseconds: UInt64(archivedListDelay * 1_000_000_000))
            }
            onArchivedList?()
            return try treeResult.get()
        }

        func getNote(id: String) async throws -> NotePayload {
            _ = id
            return try noteResult.get()
        }

        func search(query: String, limit: Int) async throws -> [FileNode] {
            _ = query
            _ = limit
            return []
        }

        func updateNote(id: String, content: String) async throws -> NotePayload {
            _ = id
            _ = content
            return try noteResult.get()
        }

        func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
            try await updateNote(
                id: id,
                content: NotesSemanticDocumentProjection.plainText(from: document)
            )
        }

        func createNote(request: NoteCreateRequest) async throws -> NotePayload {
            _ = request
            return try noteResult.get()
        }

        func renameNote(id: String, newName: String) async throws -> NotePayload {
            _ = id
            _ = newName
            return try noteResult.get()
        }

        func moveNote(id: String, folder: String) async throws -> NotePayload {
            _ = id
            _ = folder
            return try noteResult.get()
        }

        func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
            _ = id
            _ = archived
            return try noteResult.get()
        }

        func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
            _ = id
            _ = pinned
            return try noteResult.get()
        }

        func updatePinnedOrder(ids: [String]) async throws {
            _ = ids
        }

        func deleteNote(id: String) async throws -> NotePayload {
            _ = id
            return try noteResult.get()
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
}
