import CoreData
import Foundation
import SwiftUI
import XCTest
@testable import sideBar

@MainActor
final class NotesEditorViewModelSemanticSyncTests: XCTestCase {
    func testSyncFromNativeEditorQueuesSemanticDocumentAndUpdatesLocalTitleSurfaces() async throws {
        try skipUnlessNativeEditorAvailable()

        let savedDocument = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Saved title", marks: [.bold])]),
                .paragraph([.init(text: "Body", marks: [])])
            ]
        )
        let harness = makeHarness(
            updateResult: .success(
                NotePayload(
                    id: "n1",
                    name: "Saved title",
                    document: savedDocument,
                    plainText: "Saved title\nBody",
                    path: "/note.md",
                    modified: 100,
                    created: nil
                )
            ),
            networkAvailable: true,
            treeChildren: [makeNode(name: "Note", path: "/note.md", modified: 1)]
        )
        let note = NotePayload(
            id: "n1",
            name: "Note",
            document: NotesSemanticDocumentProjection.document(fromPlainText: "Hello"),
            plainText: "Hello",
            path: "/note.md",
            modified: nil,
            created: nil
        )

        harness.store.applyEditorUpdate(note)
        try await waitUntilSemanticNoteHydrated(harness.viewModel, note: note)

        let nativeViewModel = harness.viewModel.makeNativeEditorViewModel()
        nativeViewModel.attributedContent = NotesAttributedDocumentCodec.attributedString(from: savedDocument)
        nativeViewModel.handleContentChange(previous: AttributedString("Hello"))
        try await waitUntilSemantic(timeoutSeconds: 3.0) { nativeViewModel.hasUnsavedChanges }

        await harness.viewModel.syncFromNativeEditor(nativeViewModel)
        try await waitUntilSemantic(timeoutSeconds: 3.0) {
            harness.notesViewModel.activeNote?.name == "Saved title"
        }

        let payload = try queuedNoteUpdatePayload(
            in: harness.persistence.container.viewContext,
            entityId: "n1"
        )
        XCTAssertEqual(payload.document, savedDocument)
        XCTAssertEqual(payload.plainText, "Saved title\nBody")
        XCTAssertEqual(harness.notesViewModel.activeNote?.name, "Saved title")
        XCTAssertEqual(harness.store.tree?.children.first?.name, "Saved title")
        XCTAssertEqual(harness.viewModel.content, "Saved title\nBody")
        XCTAssertTrue(harness.viewModel.isQueuedForSync)
    }

    func testSwitchingNotesReloadsSavedFormattedContent() async throws {
        try skipUnlessNativeEditorAvailable()

        let initialCanonical = semanticCanonicalPlainTextPass("Hello")
        let harness = makeHarness(
            updateResult: .success(
                NotePayload(
                    id: "n1",
                    name: "Note",
                    content: initialCanonical,
                    path: "/note.md",
                    modified: 100,
                    created: nil
                )
            ),
            networkAvailable: true
        )
        let note = NotePayload(id: "n1", name: "Note", content: initialCanonical, path: "/note.md", modified: nil, created: nil)
        let otherNote = NotePayload(
            id: "n2",
            name: "Other",
            content: semanticCanonicalPlainTextPass("Other"),
            path: "/other.md",
            modified: nil,
            created: nil
        )

        harness.store.applyEditorUpdate(note)
        try await waitUntilSemanticNoteHydrated(harness.viewModel, note: note)

        let nativeViewModel = harness.viewModel.makeNativeEditorViewModel()
        harness.viewModel.attachNativeEditor(nativeViewModel)
        harness.viewModel.enterEditMode()
        let range = semanticCharacterRange(length: 5, in: nativeViewModel.attributedContent)
        nativeViewModel.selection = AttributedTextSelection(range: range)
        harness.viewModel.setFormatting(.bold, enabled: true)

        await harness.viewModel.syncFromNativeEditor(nativeViewModel)

        let payload = try queuedNoteUpdatePayload(
            in: harness.persistence.container.viewContext,
            entityId: "n1"
        )
        let savedDocument = payload.document
        let savedNote = NotePayload(
            id: "n1",
            name: "Note",
            document: savedDocument,
            plainText: payload.plainText,
            path: "/note.md",
            modified: 101,
            created: nil
        )

        harness.store.applyEditorUpdate(otherNote)
        try await waitUntilSemanticNoteHydrated(harness.viewModel, note: otherNote)
        harness.store.applyEditorUpdate(savedNote)
        try await waitUntilSemanticNoteHydrated(harness.viewModel, note: savedNote)

        let reloadedRange = semanticCharacterRange(length: 5, in: nativeViewModel.attributedContent)
        XCTAssertTrue(noteRangeHasBoldTrait(nativeViewModel.attributedContent, range: reloadedRange))
#if os(macOS)
        XCTAssertFalse(noteRangeHasBridgedBoldPlatformFont(nativeViewModel.attributedContent, range: reloadedRange))
#endif
    }

    func testOfflineSyncQueuesSemanticDocumentAndKeepsLocalTitleSurfacesInSync() async throws {
        try skipUnlessNativeEditorAvailable()

        let harness = makeHarness(
            updateResult: .failure(SemanticSyncMockError.forced),
            networkAvailable: false,
            treeChildren: [makeNode(name: "Old title", path: "/note.md", modified: 1)]
        )
        let note = NotePayload(
            id: "n1",
            name: "Old title",
            document: NotesSemanticDocumentProjection.document(fromPlainText: "Old title"),
            plainText: "Old title",
            path: "/note.md",
            modified: 1,
            created: nil
        )

        harness.store.applyEditorUpdate(note)
        try await waitUntilSemanticNoteHydrated(harness.viewModel, note: note)

        let nativeViewModel = harness.viewModel.makeNativeEditorViewModel()
        nativeViewModel.attributedContent = AttributedString("Queued title\nBody")
        nativeViewModel.handleContentChange(previous: AttributedString("Old title"))
        try await waitUntilSemantic(timeoutSeconds: 3.0) { nativeViewModel.hasUnsavedChanges }

        await harness.viewModel.syncFromNativeEditor(nativeViewModel)
        try await waitUntilSemantic(timeoutSeconds: 3.0) {
            harness.notesViewModel.activeNote?.name == "Queued title"
        }

        let payload = try queuedNoteUpdatePayload(
            in: harness.persistence.container.viewContext,
            entityId: "n1"
        )
        XCTAssertEqual(payload.plainText, "Queued title\nBody")
        XCTAssertEqual(
            payload.document,
            NotesSemanticDocument(
                blocks: [
                    .init(type: .title, content: [.init(text: "Queued title", marks: [])]),
                    .paragraph([.init(text: "Body", marks: [])])
                ]
            )
        )
        XCTAssertEqual(harness.notesViewModel.activeNote?.name, "Queued title")
        XCTAssertEqual(harness.store.tree?.children.first?.name, "Queued title")
        XCTAssertTrue(harness.viewModel.isQueuedForSync)
    }

    func testApplyingSemanticDraftRestoresCanonicalContentWithoutFlattening() async throws {
        try skipUnlessNativeEditorAvailable()

        let draftDocument = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Draft title", marks: [.bold])]),
                .paragraph([.init(text: "Draft body", marks: [.italic])])
            ]
        )
        let draftCanonical = try XCTUnwrap(NotesSemanticDocumentCodec.encode(draftDocument))
        let harness = makeHarness(
            updateResult: .failure(SemanticSyncMockError.forced),
            networkAvailable: true
        )
        let draftStorage = DraftStorage(container: harness.persistence.container)
        let note = NotePayload(
            id: "n1",
            name: "Server title",
            document: NotesSemanticDocumentProjection.document(fromPlainText: "Server title\nServer body"),
            plainText: "Server title\nServer body",
            path: "/note.md",
            modified: 1,
            created: nil
        )

        try draftStorage.saveDraft(entityType: "note", entityId: "n1", content: draftCanonical)
        harness.store.applyEditorUpdate(note)
        try await waitUntilSemantic(timeoutSeconds: 3.0) {
            harness.viewModel.canonicalContent == draftCanonical
        }

        XCTAssertEqual(harness.viewModel.canonicalContent, draftCanonical)
        XCTAssertEqual(harness.viewModel.content, "Draft title\nDraft body")
        XCTAssertTrue(harness.viewModel.isDirty)
        XCTAssertTrue(harness.viewModel.isQueuedForSync)
    }

    func testOpenNoteContextIncludesLiveSemanticDocumentForUnsavedEdits() async throws {
        try skipUnlessNativeEditorAvailable()

        let harness = makeHarness(
            updateResult: .failure(SemanticSyncMockError.forced),
            networkAvailable: true
        )
        let note = NotePayload(
            id: "n1",
            name: "Old title",
            document: NotesSemanticDocumentProjection.document(fromPlainText: "Old title"),
            plainText: "Old title",
            path: "/note.md",
            modified: 1,
            created: nil
        )

        harness.store.applyEditorUpdate(note)
        try await waitUntilSemanticNoteHydrated(harness.viewModel, note: note)

        let nativeViewModel = harness.viewModel.makeNativeEditorViewModel()
        nativeViewModel.attributedContent = AttributedString("Live title\nLive body")
        nativeViewModel.handleContentChange(previous: AttributedString("Old title"))
        try await waitUntilSemantic(timeoutSeconds: 3.0) { nativeViewModel.hasUnsavedChanges }
        harness.viewModel.attachNativeEditor(nativeViewModel)

        let runtime = NotesRuntime(
            viewModel: harness.notesViewModel,
            editorViewModel: harness.viewModel
        )
        let context = try XCTUnwrap(runtime.openNoteContext())
        let document = try XCTUnwrap(context["document"] as? [String: Any])
        let blocks = try XCTUnwrap(document["blocks"] as? [[String: Any]])

        XCTAssertEqual(context["plain_text"] as? String, "Live title\nLive body")
        XCTAssertEqual(blocks.first?["type"] as? String, "title")
        XCTAssertEqual(
            ((blocks.first?["content"] as? [[String: Any]])?.first?["text"] as? String),
            "Live title"
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
@MainActor
private struct SemanticSyncHarness {
    let api: SemanticSyncNotesAPISpy
    let store: NotesStore
    let notesViewModel: NotesViewModel
    let persistence: PersistenceController
    let viewModel: NotesEditorViewModel
}

@available(iOS 26.0, macOS 26.0, *)
@MainActor
private func makeHarness(
    updateResult: Result<NotePayload, Error>,
    networkAvailable: Bool,
    treeChildren: [FileNode] = []
) -> SemanticSyncHarness {
    let api = SemanticSyncNotesAPISpy(updateResult: updateResult)
    let store = NotesStore(api: api, cache: TestCacheClient())
    if !treeChildren.isEmpty {
        store.applyTreeUpdate(FileTree(children: treeChildren), persist: false)
    }

    let notesViewModel = NotesViewModel(
        api: api,
        store: store,
        toastCenter: ToastCenter(),
        networkStatus: SemanticSyncTestNetworkStatus(isNetworkAvailable: true)
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
        networkStatus: SemanticSyncTestNetworkStatus(isNetworkAvailable: networkAvailable)
    )

    return SemanticSyncHarness(
        api: api,
        store: store,
        notesViewModel: notesViewModel,
        persistence: persistence,
        viewModel: viewModel
    )
}

@available(iOS 26.0, macOS 26.0, *)
@MainActor
private func semanticCanonicalPlainTextPass(_ plainText: String) -> String {
    let probe = NativeNoteEditorViewModel()
    probe.loadText(plainText)
    return probe.currentPlainText()
}

@available(iOS 26.0, macOS 26.0, *)
private func semanticCharacterRange(
    length: Int,
    in text: AttributedString
) -> Range<AttributedString.Index> {
    var index = text.startIndex
    for _ in 0..<length {
        index = text.index(afterCharacter: index)
    }
    return text.startIndex..<index
}

@MainActor
private func waitUntilSemantic(timeoutSeconds: TimeInterval, condition: @escaping () -> Bool) async throws {
    let timeout = Date().addingTimeInterval(timeoutSeconds)
    while Date() < timeout {
        if condition() {
            return
        }
        await Task.yield()
    }
    XCTFail("Timed out waiting for condition")
}

@MainActor
private func waitUntilSemanticNoteHydrated(
    _ viewModel: NotesEditorViewModel,
    note: NotePayload
) async throws {
    let unsupported = NotesUnsupportedContent.detect(in: note.document)
    try await waitUntilSemantic(timeoutSeconds: 5.0) {
        viewModel.currentNoteId == note.id
            && viewModel.content == note.plainText
            && NotesSemanticDocumentCodec.decode(viewModel.canonicalContent) == note.document
            && viewModel.isReadOnly == (unsupported != nil)
            && viewModel.unsupportedContent?.blockTypes == unsupported?.blockTypes
    }
}

private func skipUnlessNativeEditorAvailable() throws {
    guard #available(iOS 26.0, macOS 26.0, *) else {
        throw XCTSkip("Requires iOS 26 or macOS 26")
    }
}

@MainActor
private func queuedNoteUpdatePayload(
    in context: NSManagedObjectContext,
    entityId: String
) throws -> NoteUpdateRequest {
    let request = PendingWrite.fetchRequest()
    request.predicate = NSPredicate(
        format: "entityType == %@ AND operationType == %@ AND entityId == %@",
        WriteEntityType.note.rawValue,
        WriteOperation.update.rawValue,
        entityId
    )
    let writes = try context.fetch(request)
    let write = try XCTUnwrap(writes.first)
    return try JSONDecoder().decode(NoteUpdateRequest.self, from: write.payload)
}

private func makeNode(name: String, path: String, modified: Double?) -> FileNode {
    FileNode(
        name: name,
        path: path,
        type: .file,
        size: nil,
        modified: modified,
        created: nil,
        children: nil,
        expanded: nil,
        pinned: nil,
        pinnedOrder: nil,
        archived: nil,
        folderMarker: nil
    )
}

private enum SemanticSyncMockError: Error {
    case forced
}

@MainActor
private struct SemanticSyncTestNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool
    let isOffline: Bool = false
}

@MainActor
private final class SemanticSyncNotesAPISpy: NotesProviding {
    private(set) var updatedDocuments: [NotesSemanticDocument] = []
    let updateResult: Result<NotePayload, Error>

    init(updateResult: Result<NotePayload, Error>) {
        self.updateResult = updateResult
    }

    func listTree() async throws -> FileTree { throw SemanticSyncMockError.forced }
    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        throw SemanticSyncMockError.forced
    }
    func getNote(id: String) async throws -> NotePayload {
        _ = id
        throw SemanticSyncMockError.forced
    }
    func search(query: String, limit: Int) async throws -> [FileNode] {
        _ = query
        _ = limit
        return []
    }
    func updateNote(id: String, content: String) async throws -> NotePayload {
        _ = id
        return try updateResult.get()
    }
    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        _ = id
        updatedDocuments.append(document)
        return try updateResult.get()
    }
    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        _ = request
        throw SemanticSyncMockError.forced
    }
    func renameNote(id: String, newName: String) async throws -> NotePayload {
        _ = id
        _ = newName
        throw SemanticSyncMockError.forced
    }
    func moveNote(id: String, folder: String) async throws -> NotePayload {
        _ = id
        _ = folder
        throw SemanticSyncMockError.forced
    }
    func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        _ = id
        _ = archived
        throw SemanticSyncMockError.forced
    }
    func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        _ = id
        _ = pinned
        throw SemanticSyncMockError.forced
    }
    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
    }
    func deleteNote(id: String) async throws -> NotePayload {
        _ = id
        throw SemanticSyncMockError.forced
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
