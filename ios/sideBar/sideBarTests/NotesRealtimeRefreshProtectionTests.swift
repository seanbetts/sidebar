import Foundation
import Combine
import sideBarShared
import XCTest
@testable import sideBar

@MainActor
final class NotesRealtimeRefreshProtectionTests: XCTestCase {
    func testRealtimePathSelectedDetailWithDelayedFetchDoesNotClearQueuedDraft() async {
        let baseline = note(id: "note-id", content: "Server baseline", path: "folder/Note.md")
        let incoming = note(id: "note-id", content: "Server incoming", path: "folder/Note.md", modified: 2)
        let api = ControlledNotesRealtimeAPI(
            noteResults: ["folder/Note.md": .success(incoming)],
            treeResult: FileTree(children: [])
        )
        let context = makeQueuedDraftContext(api: api, baseline: baseline, selectedNoteId: baseline.path)
        await queueLocalDraft(in: context)

        let refreshTask = startRealtimeRefresh(noteId: baseline.id, viewModel: context.notesViewModel)
        await api.waitUntilGetNotePending(id: baseline.path)

        for _ in 0..<5 {
            await Task.yield()
        }

        XCTAssertEqual(context.notesViewModel.selectedNoteId, baseline.path)
        XCTAssertEqual(context.viewModel.currentNoteId, baseline.id)
        XCTAssertEqual(context.viewModel.content, "Local draft")
        XCTAssertTrue(context.viewModel.isQueuedForSync)

        api.resumeGetNote(id: baseline.path)
        await refreshTask.value
    }

    func testSelectedRealtimeDeleteClearsActiveDetailWhenDetailFetchFails() async {
        let baseline = note(id: "n1", content: "Server baseline", path: "folder/Note.md")
        let api = ControlledNotesRealtimeAPI(
            noteResults: [
                baseline.id: .failure(NotesStoreTestsSupport.MockError.forced)
            ],
            treeResult: FileTree(children: [])
        )
        let context = makeNotesEditorViewModelTestContext(api: api)
        context.store.applyEditorUpdate(baseline)
        context.notesViewModel.selectedNoteId = baseline.id
        await waitUntilEditorContent(context.viewModel, noteId: baseline.id, content: baseline.plainText)

        await scheduleRealtimeInvalidation(noteId: baseline.id, isDeleted: true, viewModel: context.notesViewModel)
        await drainEditorUpdates()

        XCTAssertNil(context.notesViewModel.selectedNoteId)
        XCTAssertNil(context.notesViewModel.activeNote)
        XCTAssertNil(context.store.activeNote)
        XCTAssertNil(context.viewModel.currentNoteId)
        XCTAssertFalse(context.viewModel.isQueuedForSync)
    }

    func testFailedRealtimeDetailRefreshDoesNotSuppressLaterNormalUpdate() async {
        let baseline = note(id: "n1", content: "Server baseline")
        let manualUpdate = note(id: "n1", content: "Manual refresh", modified: 3)
        let api = ControlledNotesRealtimeAPI(
            noteResults: [
                baseline.id: .failure(NotesStoreTestsSupport.MockError.forced)
            ],
            treeResult: FileTree(children: [])
        )
        let context = makeQueuedDraftContext(api: api, baseline: baseline, selectedNoteId: baseline.id)
        await queueLocalDraft(in: context)

        await scheduleRealtimeInvalidation(noteId: baseline.id, isDeleted: false, viewModel: context.notesViewModel)

        context.notesViewModel.setMirroredActiveNote(manualUpdate)
        await waitUntilEditorContent(context.viewModel, noteId: baseline.id, content: "Manual refresh")

        XCTAssertFalse(context.viewModel.isQueuedForSync)
    }

    func testNoOpRealtimeDetailRefreshDoesNotSuppressSaveAcknowledgement() async {
        let baseline = note(id: "n1", content: "Server baseline")
        let api = ControlledNotesRealtimeAPI(noteResults: [:], treeResult: FileTree(children: []))
        let context = makeQueuedDraftContext(api: api, baseline: baseline, selectedNoteId: baseline.id)
        let draftDocument = await queueLocalDraft(in: context)
        guard let noOpServerNote = context.store.activeNote else {
            XCTFail("Expected queued draft to update active note")
            return
        }
        api.setImmediateNoteResult(.success(noOpServerNote), for: baseline.id)

        await scheduleRealtimeInvalidation(
            noteId: baseline.id,
            isDeleted: false,
            viewModel: context.notesViewModel
        )

        let acknowledged = acknowledgedNote(baseline: noOpServerNote, document: noOpServerNote.document, modified: 3)
        context.notesViewModel.applySavedNoteAcknowledgement(
            serverNote: acknowledged,
            document: draftDocument
        )
        await waitUntilEditorContent(context.viewModel, noteId: baseline.id, content: "Local draft")
        await waitUntilEditorQueueState(context.viewModel, isQueuedForSync: false)

        XCTAssertFalse(context.viewModel.isQueuedForSync)
    }

    func testSaveAcknowledgementClearsQueuedStateWhenOptimisticEchoIsStillPending() async {
        let baseline = note(id: "n1", content: "Server baseline")
        let api = ControlledNotesRealtimeAPI(noteResults: [:], treeResult: FileTree(children: []))
        let context = makeQueuedDraftContext(api: api, baseline: baseline, selectedNoteId: baseline.id)
        let draftDocument = await queueLocalDraft(in: context)
        guard let optimisticLocalNote = context.store.activeNote else {
            XCTFail("Expected queued draft to update active note")
            return
        }
        context.notesViewModel.activeNoteMirrorTask?.cancel()

        let acknowledged = acknowledgedNote(baseline: optimisticLocalNote, document: draftDocument, modified: 3)
        context.notesViewModel.applySavedNoteAcknowledgement(
            serverNote: acknowledged,
            document: draftDocument
        )
        await waitUntilEditorQueueState(context.viewModel, isQueuedForSync: false)

        XCTAssertFalse(context.viewModel.isQueuedForSync)
    }

    func testListMetadataPublishDuringDelayedRealtimeDetailRefreshDoesNotExposeServerContent() async {
        let baseline = note(id: "note-id", content: "Server baseline", path: "folder/Note.md")
        let incoming = note(id: "note-id", content: "Server incoming", path: "folder/Note.md", modified: 3)
        let metadataTree = FileTree(children: [
            fileNode(path: baseline.path, name: baseline.name, modified: 2)
        ])
        let api = ControlledNotesRealtimeAPI(
            noteResults: [baseline.path: .success(incoming)],
            treeResult: metadataTree
        )
        let context = makeQueuedDraftContext(api: api, baseline: baseline, selectedNoteId: baseline.path)
        let draftDocument = await queueLocalDraft(in: context)
        let draftCanonical = NotesSemanticDocumentCodec.encode(draftDocument) ?? ""
        let serverCanonical = NotesSemanticDocumentCodec.encode(incoming.document) ?? ""
        let probe = EditorServerPublishProbe(
            viewModel: context.viewModel,
            serverCanonical: serverCanonical
        )

        let refreshTask = startRealtimeRefresh(noteId: baseline.id, viewModel: context.notesViewModel)
        await api.waitUntilGetNotePending(id: baseline.path)

        for _ in 0..<5 {
            await Task.yield()
        }
        XCTAssertEqual(context.viewModel.content, "Local draft")
        XCTAssertEqual(context.viewModel.canonicalContent, draftCanonical)
        XCTAssertTrue(context.viewModel.isQueuedForSync)

        api.resumeGetNote(id: baseline.path)
        await refreshTask.value
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertFalse(probe.observedServerContent)
        XCTAssertFalse(probe.observedServerCanonical)
        XCTAssertFalse(probe.observedQueueClear)
        XCTAssertEqual(context.viewModel.content, "Local draft")
        XCTAssertEqual(context.viewModel.canonicalContent, draftCanonical)
        XCTAssertTrue(context.viewModel.isQueuedForSync)
    }

    func testSaveAcknowledgementDuringDelayedRealtimeDetailRefreshIsNotSuppressed() async {
        let baseline = note(id: "note-id", content: "Server baseline", path: "folder/Note.md")
        let incoming = note(id: "note-id", content: "Server incoming", path: "folder/Note.md", modified: 3)
        let api = ControlledNotesRealtimeAPI(
            noteResults: [baseline.path: .success(incoming)],
            treeResult: FileTree(children: [])
        )
        let context = makeQueuedDraftContext(api: api, baseline: baseline, selectedNoteId: baseline.path)
        let draftDocument = await queueLocalDraft(in: context)
        let draftCanonical = NotesSemanticDocumentCodec.encode(draftDocument) ?? ""

        let refreshTask = startRealtimeRefresh(noteId: baseline.id, viewModel: context.notesViewModel)
        await api.waitUntilGetNotePending(id: baseline.path)

        let acknowledged = acknowledgedNote(baseline: baseline, document: draftDocument, modified: 4)
        context.notesViewModel.applySavedNoteAcknowledgement(
            serverNote: acknowledged,
            document: draftDocument
        )
        await waitUntilEditorQueueState(context.viewModel, isQueuedForSync: false)
        XCTAssertEqual(context.viewModel.content, "Local draft")
        XCTAssertEqual(context.viewModel.canonicalContent, draftCanonical)

        api.resumeGetNote(id: baseline.path)
        await refreshTask.value
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertEqual(context.viewModel.content, "Local draft")
        XCTAssertEqual(context.viewModel.canonicalContent, draftCanonical)
        XCTAssertFalse(context.viewModel.isQueuedForSync)
    }

    func testSaveAcknowledgementDuringRealtimeRefreshClearsQueuedStateBeforeOptimisticEcho() async {
        let baseline = note(id: "note-id", content: "Server baseline", path: "folder/Note.md")
        let incoming = note(id: "note-id", content: "Server incoming", path: "folder/Note.md", modified: 3)
        let api = ControlledNotesRealtimeAPI(
            noteResults: [baseline.path: .success(incoming)],
            treeResult: FileTree(children: [])
        )
        let context = makeQueuedDraftContext(api: api, baseline: baseline, selectedNoteId: baseline.path)
        let draftDocument = await queueLocalDraft(in: context)
        let draftCanonical = NotesSemanticDocumentCodec.encode(draftDocument) ?? ""
        context.notesViewModel.activeNoteMirrorTask?.cancel()

        let refreshTask = startRealtimeRefresh(noteId: baseline.id, viewModel: context.notesViewModel)
        await api.waitUntilGetNotePending(id: baseline.path)
        context.notesViewModel.activeNoteMirrorTask?.cancel()

        let acknowledged = acknowledgedNote(baseline: baseline, document: draftDocument, modified: 4)
        context.notesViewModel.applySavedNoteAcknowledgement(
            serverNote: acknowledged,
            document: draftDocument
        )
        await drainEditorUpdates()

        XCTAssertEqual(context.viewModel.content, "Local draft")
        XCTAssertEqual(context.viewModel.canonicalContent, draftCanonical)
        XCTAssertFalse(context.viewModel.isQueuedForSync)

        api.resumeGetNote(id: baseline.path)
        await refreshTask.value
    }

    func testQueuedDraftRealtimeDetailRefreshDoesNotOverwriteStoreOrCacheBeforeAcknowledgement() async {
        let baseline = note(id: "note-id", content: "Server baseline", path: "folder/Note.md")
        let incoming = note(id: "note-id", content: "Server incoming", path: "folder/Note.md", modified: 3)
        let api = ControlledNotesRealtimeAPI(
            noteResults: [baseline.path: .success(incoming)],
            treeResult: FileTree(children: [])
        )
        let context = makeQueuedDraftContext(api: api, baseline: baseline, selectedNoteId: baseline.path)
        await queueLocalDraft(in: context)
        guard let localDraftNote = context.store.activeNote else {
            XCTFail("Expected queued draft to be active before realtime refresh")
            return
        }

        let refreshTask = startRealtimeRefresh(noteId: baseline.id, viewModel: context.notesViewModel)
        await api.waitUntilGetNotePending(id: baseline.path)
        api.resumeGetNote(id: baseline.path)
        await refreshTask.value

        let cachedById: NotePayload? = context.store.cache.get(key: CacheKeys.note(id: baseline.id))
        let cachedByPath: NotePayload? = context.store.cache.get(key: CacheKeys.note(id: baseline.path))
        XCTAssertEqual(context.store.activeNote?.plainText, localDraftNote.plainText)
        XCTAssertEqual(context.store.activeNote?.document, localDraftNote.document)
        XCTAssertEqual(cachedById?.plainText, localDraftNote.plainText)
        XCTAssertEqual(cachedByPath?.plainText, localDraftNote.plainText)
        XCTAssertNotEqual(context.store.activeNote?.plainText, incoming.plainText)
    }

    private func makeQueuedDraftContext(
        api: any NotesProviding,
        baseline: NotePayload,
        selectedNoteId: String
    ) -> NotesEditorViewModelTestContext {
        let context = makeNotesEditorViewModelTestContext(api: api)
        context.store.applyEditorUpdate(baseline)
        context.notesViewModel.selectedNoteId = selectedNoteId
        return context
    }

    @discardableResult
    private func queueLocalDraft(in context: NotesEditorViewModelTestContext) async -> NotesSemanticDocument {
        guard let noteId = context.store.activeNote?.id else {
            XCTFail("Expected active note before queuing draft")
            return localDraftDocument()
        }
        await waitUntilEditorContent(context.viewModel, noteId: noteId, content: "Server baseline")
        let draftDocument = localDraftDocument()
        await context.viewModel.saveDocumentSnapshotIfNeeded(draftDocument, force: true)
        await waitUntilEditorContent(context.viewModel, noteId: noteId, content: "Local draft")
        return draftDocument
    }

    private func localDraftDocument() -> NotesSemanticDocument {
        NotesSemanticDocument(
            blocks: [.paragraph([.init(text: "Local draft", marks: [])])]
        )
    }

    private func acknowledgedNote(
        baseline: NotePayload,
        document: NotesSemanticDocument,
        modified: TimeInterval
    ) -> NotePayload {
        NotePayload(
            id: baseline.id,
            name: baseline.name,
            document: document,
            documentVersion: document.version,
            plainText: NotesSemanticDocumentProjection.plainText(from: document),
            path: baseline.path,
            modified: modified,
            created: baseline.created
        )
    }

    private func startRealtimeRefresh(noteId: String, viewModel: NotesViewModel) -> Task<Void, Never> {
        Task { await scheduleRealtimeInvalidation(noteId: noteId, isDeleted: false, viewModel: viewModel) }
    }

    private func scheduleRealtimeInvalidation(
        noteId: String,
        isDeleted: Bool,
        viewModel: NotesViewModel
    ) async {
        let adapter = NotesRefreshAdapter(viewModel: viewModel)
        let coordinator = RefreshCoordinator(registry: RefreshRegistry(adapters: [adapter]))
        await coordinator.scheduleRealtimeInvalidation(
            adapter.classifyNoteRealtime(
                noteId: noteId,
                updatedAt: Date(timeIntervalSince1970: 2),
                isDeleted: isDeleted
            ),
            context: RefreshContext(
                visibleSection: .notes,
                hasVisibleDetail: true,
                pinnedSections: [],
                lastOpenedSection: nil,
                staleTargets: [],
                canAttemptServerRead: true
            )
        )
    }

    private func note(
        id: String,
        content: String,
        path: String? = nil,
        modified: TimeInterval = 1
    ) -> NotePayload {
        NotePayload(
            id: id,
            name: "Note.md",
            content: content,
            path: path ?? id,
            modified: modified,
            created: nil
        )
    }

    private func fileNode(path: String, name: String, modified: TimeInterval) -> FileNode {
        FileNode(
            name: name, path: path, type: .file, size: nil, modified: modified, created: nil,
            children: nil, expanded: nil, pinned: nil, pinnedOrder: nil, archived: nil, folderMarker: nil
        )
    }

    private func drainEditorUpdates() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    private func waitUntilEditorContent(
        _ viewModel: NotesEditorViewModel,
        noteId: String,
        content: String
    ) async {
        let timeout = Date().addingTimeInterval(2)
        while Date() < timeout {
            if viewModel.currentNoteId == noteId, viewModel.content == content {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for editor content: \(String(describing: viewModel.currentNoteId)) \(viewModel.content)")
    }

    private func waitUntilEditorQueueState(
        _ viewModel: NotesEditorViewModel,
        isQueuedForSync: Bool
    ) async {
        let timeout = Date().addingTimeInterval(2)
        while Date() < timeout {
            if viewModel.isQueuedForSync == isQueuedForSync {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for editor queue state: \(isQueuedForSync) \(viewModel.isQueuedForSync)")
    }

}

@MainActor
private final class EditorServerPublishProbe {
    var observedServerContent = false
    var observedServerCanonical = false
    var observedQueueClear = false
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: NotesEditorViewModel, serverCanonical: String) {
        viewModel.$content
            .sink { [weak self] content in
                if content == "Server incoming" { self?.observedServerContent = true }
            }
            .store(in: &cancellables)
        viewModel.$canonicalContent
            .sink { [weak self] canonicalContent in
                if canonicalContent == serverCanonical { self?.observedServerCanonical = true }
            }
            .store(in: &cancellables)
        viewModel.$isQueuedForSync
            .sink { [weak self] isQueuedForSync in
                if !isQueuedForSync { self?.observedQueueClear = true }
            }
            .store(in: &cancellables)
    }
}
