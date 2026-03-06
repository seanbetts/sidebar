import Foundation
import SwiftUI
import XCTest
@testable import sideBar

@MainActor
final class NotesLegacyMigrationServiceTests: XCTestCase {
    func testMigrateLegacyNoteWritesSemanticDocumentBackAndPreservesPlainTextAndTitle() async throws {
        try skipUnlessLegacyMigrationAvailable()

        let encodedContent = try encodedLegacyRTF(title: "Legacy title", body: "Body")
        let legacyNote = try legacyNotePayload(
            id: "note-1",
            encodedContent: encodedContent
        )
        let migratedDocument = NotesSemanticDocument(
            blocks: [
                .paragraph([.init(text: "Legacy title", marks: [.bold])]),
                .paragraph([.init(text: "Body", marks: [])])
            ]
        )
        let updatedNote = NotePayload(
            id: "note-1",
            name: "Legacy title",
            document: migratedDocument,
            plainText: "Legacy title\nBody",
            path: "note-1",
            modified: 2,
            created: 1
        )
        let api = NotesLegacyMigrationNotesAPISpy(
            getNoteResult: .success(legacyNote),
            updateResult: .success(updatedNote)
        )
        let service = NotesLegacyMigrationService(api: api)

        let migrated = try await service.migrateLegacyNote(id: "note-1")

        XCTAssertEqual(api.updatedNoteIDs, ["note-1"])
        XCTAssertEqual(api.updatedDocuments, [migratedDocument])
        XCTAssertEqual(migrated.plainText, "Legacy title\nBody")
        XCTAssertEqual(migrated.name, "Legacy title")
    }

    func testMigrateLegacyNoteSkipsSemanticNotesWithoutLegacyContentFormat() async throws {
        try skipUnlessLegacyMigrationAvailable()

        let semanticNote = NotePayload(
            id: "note-2",
            name: "Semantic title",
            document: NotesSemanticDocument(
                blocks: [.paragraph([.init(text: "Semantic title", marks: [.bold])])]
            ),
            plainText: "Semantic title",
            path: "note-2",
            modified: 2,
            created: 1
        )
        let api = NotesLegacyMigrationNotesAPISpy(
            getNoteResult: .success(semanticNote),
            updateResult: .failure(NotesLegacyMigrationMockError.forced)
        )
        let service = NotesLegacyMigrationService(api: api)

        let migrated = try await service.migrateLegacyNote(id: "note-2")

        XCTAssertTrue(api.updatedNoteIDs.isEmpty)
        XCTAssertEqual(migrated, semanticNote)
    }
}

private func skipUnlessLegacyMigrationAvailable() throws {
    guard #available(iOS 26.0, macOS 26.0, *) else {
        throw XCTSkip("Requires iOS 26 or macOS 26")
    }
}

@available(iOS 26.0, macOS 26.0, *)
@MainActor
private func legacyNotePayload(
    id: String,
    encodedContent: String
) throws -> NotePayload {
    let json = """
    {
      "id": "\(id)",
      "name": "Legacy title",
      "content": "\(encodedContent)",
      "content_format": "rtf",
      "plain_text": "Legacy title\\nBody",
      "path": "\(id)",
      "modified": 1,
      "created": 1
    }
    """
    return try JSONDecoder().decode(NotePayload.self, from: Data(json.utf8))
}

@available(iOS 26.0, macOS 26.0, *)
private func encodedLegacyRTF(title: String, body: String) throws -> String {
    let document = NotesSemanticDocument(
        blocks: [
            .paragraph([.init(text: title, marks: [.bold])]),
            .paragraph([.init(text: body, marks: [])])
        ]
    )
    let attributed = NotesAttributedDocumentCodec.attributedString(from: document)
    guard let encoded = NotesRichTextCodec.encodeAttributedStringToBase64RTF(attributed) else {
        throw NotesLegacyMigrationMockError.forced
    }
    return encoded
}

private enum NotesLegacyMigrationMockError: Error {
    case forced
}

@MainActor
private final class NotesLegacyMigrationNotesAPISpy: NotesProviding {
    private(set) var updatedNoteIDs: [String] = []
    private(set) var updatedDocuments: [NotesSemanticDocument] = []
    var getNoteResult: Result<NotePayload, Error> = .failure(NotesLegacyMigrationMockError.forced)
    var updateResult: Result<NotePayload, Error> = .failure(NotesLegacyMigrationMockError.forced)

    init(
        getNoteResult: Result<NotePayload, Error> = .failure(NotesLegacyMigrationMockError.forced),
        updateResult: Result<NotePayload, Error> = .failure(NotesLegacyMigrationMockError.forced)
    ) {
        self.getNoteResult = getNoteResult
        self.updateResult = updateResult
    }

    func listTree() async throws -> FileTree { throw NotesLegacyMigrationMockError.forced }
    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        throw NotesLegacyMigrationMockError.forced
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
        throw NotesLegacyMigrationMockError.forced
    }
    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        updatedNoteIDs.append(id)
        updatedDocuments.append(document)
        return try updateResult.get()
    }
    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        _ = request
        throw NotesLegacyMigrationMockError.forced
    }
    func moveNote(id: String, folder: String) async throws -> NotePayload {
        _ = id
        _ = folder
        throw NotesLegacyMigrationMockError.forced
    }
    func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        _ = id
        _ = archived
        throw NotesLegacyMigrationMockError.forced
    }
    func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        _ = id
        _ = pinned
        throw NotesLegacyMigrationMockError.forced
    }
    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
    }
    func deleteNote(id: String) async throws -> NotePayload {
        _ = id
        throw NotesLegacyMigrationMockError.forced
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
