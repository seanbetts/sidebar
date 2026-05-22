import Foundation
import Combine
import sideBarShared
import XCTest
@testable import sideBar

@MainActor
final class NotesStoreRefreshMergeTests: XCTestCase {
    func testNoteRealtimeForSelectedDetailRequiresDetailRefreshWithoutClearingEditorDraft() async {
        let adapter = NotesRefreshAdapter(viewModel: makeNotesViewModel(selectedNoteId: "n1"))

        let change = adapter.classifyNoteRealtime(
            noteId: "n1",
            updatedAt: Date(timeIntervalSince1970: 2_000),
            isDeleted: false
        )

        XCTAssertEqual(change.section, .notes)
        XCTAssertEqual(change.refreshTargets, [.sectionList(.notes), .visibleDetail(.notes)])
    }

    func testNoteRealtimeClassifiesActiveNoteIdAndPathAsSelectedDetail() async {
        let selectedByPath = makeNotesViewModel(selectedNoteId: "folder/Note.md")
        selectedByPath.setMirroredActiveNote(
            NotePayload(
                id: "n1",
                name: "Note.md",
                content: "Body",
                path: "folder/Note.md",
                modified: 1,
                created: nil
            )
        )
        let idChange = NotesRefreshAdapter(viewModel: selectedByPath).classifyNoteRealtime(
            noteId: "n1",
            updatedAt: nil,
            isDeleted: false
        )

        XCTAssertEqual(idChange.kind, .detailRefresh)
        XCTAssertEqual(idChange.refreshTargets, [.sectionList(.notes), .visibleDetail(.notes)])
        XCTAssertFalse(idChange.canPatchMetadata)

        let selectedById = makeNotesViewModel(selectedNoteId: "n1")
        selectedById.setMirroredActiveNote(
            NotePayload(
                id: "n1",
                name: "Note.md",
                content: "Body",
                path: "folder/Note.md",
                modified: 1,
                created: nil
            )
        )
        let pathChange = NotesRefreshAdapter(viewModel: selectedById).classifyNoteRealtime(
            noteId: "folder/Note.md",
            updatedAt: nil,
            isDeleted: false
        )

        XCTAssertEqual(pathChange.kind, .detailRefresh)
        XCTAssertEqual(pathChange.refreshTargets, [.sectionList(.notes), .visibleDetail(.notes)])
        XCTAssertFalse(pathChange.canPatchMetadata)
    }

    func testRealtimeDeleteForPendingPathSelectionUsesCachedMappingAndClearsSelection() async {
        let path = "folder/Note.md"
        let note = NotePayload(
            id: "n1",
            name: "Note.md",
            content: "Cached body",
            path: path,
            modified: 1,
            created: nil
        )
        let tree = FileTree(children: [
            FileNode(
                name: "Note.md",
                path: path,
                type: .file,
                size: nil,
                modified: 1,
                created: nil,
                children: nil,
                expanded: nil,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: nil
            )
        ])
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.note(id: path), value: note, ttlSeconds: 60)
        let api = NotesStoreTestsSupport.MockNotesAPI(
            treeResult: .success(tree),
            noteResult: .failure(NotesStoreTestsSupport.MockError.forced)
        )
        let store = NotesStore(api: api, cache: cache)
        store.applyTreeUpdate(tree, persist: true)
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: NotesStoreTestsSupport.TestNetworkStatus(isNetworkAvailable: true)
        )
        viewModel.selectedNoteId = path
        viewModel.pendingNoteId = path

        let adapter = NotesRefreshAdapter(viewModel: viewModel)
        let change = adapter.classifyNoteRealtime(
            noteId: note.id,
            updatedAt: Date(timeIntervalSince1970: 2),
            isDeleted: true
        )

        XCTAssertEqual(change.refreshTargets, [.sectionList(.notes), .visibleDetail(.notes)])

        let coordinator = RefreshCoordinator(registry: RefreshRegistry(adapters: [adapter]))
        await coordinator.scheduleRealtimeInvalidation(
            change,
            context: RefreshContext(
                visibleSection: .notes,
                hasVisibleDetail: true,
                pinnedSections: [],
                lastOpenedSection: nil,
                staleTargets: [],
                canAttemptServerRead: true
            )
        )

        XCTAssertNil(viewModel.selectedNoteId)
        XCTAssertNil(viewModel.pendingNoteId)
    }

    func testSelectedNoteRealtimeRefreshKeepsQueuedEditorDraftUntilServerAcknowledgement() async {
        let baseline = NotePayload(
            id: "n1",
            name: "Note.md",
            content: "Server baseline",
            path: "n1",
            modified: 1,
            created: nil
        )
        let incoming = NotePayload(
            id: "n1",
            name: "Note.md",
            content: "Server incoming",
            path: "n1",
            modified: 2,
            created: nil
        )
        let tree = FileTree(children: [
            FileNode(
                name: "Note.md",
                path: "n1",
                type: .file,
                size: nil,
                modified: 2,
                created: nil,
                children: nil,
                expanded: nil,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: nil
            )
        ])
        let api = NotesStoreTestsSupport.MockNotesAPI(
            treeResult: .success(tree),
            noteResult: .success(incoming)
        )
        let context = makeNotesEditorViewModelTestContext(api: api)
        context.store.applyEditorUpdate(baseline)
        context.notesViewModel.selectedNoteId = "n1"
        await waitUntilEditorContent(context.viewModel, noteId: "n1", content: "Server baseline")

        let draftDocument = NotesSemanticDocument(
            blocks: [.paragraph([.init(text: "Local draft", marks: [])])]
        )
        await context.viewModel.saveDocumentSnapshotIfNeeded(draftDocument, force: true)
        await waitUntilEditorContent(context.viewModel, noteId: "n1", content: "Local draft")

        let adapter = NotesRefreshAdapter(viewModel: context.notesViewModel)
        let coordinator = RefreshCoordinator(registry: RefreshRegistry(adapters: [adapter]))
        let change = adapter.classifyNoteRealtime(
            noteId: "n1",
            updatedAt: Date(timeIntervalSince1970: 2),
            isDeleted: false
        )

        await coordinator.scheduleRealtimeInvalidation(
            change,
            context: RefreshContext(
                visibleSection: .notes,
                hasVisibleDetail: true,
                pinnedSections: [],
                lastOpenedSection: nil,
                staleTargets: [],
                canAttemptServerRead: true
            )
        )
        await waitUntilEditorContent(context.viewModel, noteId: "n1", content: "Local draft")

        XCTAssertEqual(context.notesViewModel.selectedNoteId, "n1")
        XCTAssertTrue(context.viewModel.isQueuedForSync)

        let acknowledged = NotePayload(
            id: "n1",
            name: "Note.md",
            content: "Local draft",
            path: "n1",
            modified: 3,
            created: nil
        )
        context.notesViewModel.applySavedNoteAcknowledgement(
            serverNote: acknowledged,
            document: draftDocument
        )
        await waitUntilEditorContent(context.viewModel, noteId: "n1", content: "Local draft")
    }

    func testSelectedRealtimeDetailRefreshDoesNotPublishServerContentBeforeDraftProtection() async {
        let baseline = NotePayload(
            id: "n1",
            name: "Note.md",
            content: "Server baseline",
            path: "n1",
            modified: 1,
            created: nil
        )
        let incoming = NotePayload(
            id: "n1",
            name: "Note.md",
            content: "Server incoming",
            path: "n1",
            modified: 2,
            created: nil
        )
        let api = NotesStoreTestsSupport.MockNotesAPI(
            treeResult: .success(FileTree(children: [])),
            noteResult: .success(incoming)
        )
        let context = makeNotesEditorViewModelTestContext(api: api)
        context.store.applyEditorUpdate(baseline)
        context.notesViewModel.selectedNoteId = "n1"
        await waitUntilEditorContent(context.viewModel, noteId: "n1", content: "Server baseline")

        let draftDocument = NotesSemanticDocument(
            blocks: [.paragraph([.init(text: "Local draft", marks: [])])]
        )
        let draftCanonical = NotesSemanticDocumentCodec.encode(draftDocument) ?? ""
        let serverCanonical = NotesSemanticDocumentCodec.encode(incoming.document) ?? ""
        await context.viewModel.saveDocumentSnapshotIfNeeded(draftDocument, force: true)
        await waitUntilEditorContent(context.viewModel, noteId: "n1", content: "Local draft")

        let probe = EditorServerPublishProbe(
            viewModel: context.viewModel,
            serverCanonical: serverCanonical
        )

        let adapter = NotesRefreshAdapter(viewModel: context.notesViewModel)
        let coordinator = RefreshCoordinator(registry: RefreshRegistry(adapters: [adapter]))
        await coordinator.scheduleRealtimeInvalidation(
            adapter.classifyNoteRealtime(
                noteId: "n1",
                updatedAt: Date(timeIntervalSince1970: 2),
                isDeleted: false
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

        XCTAssertEqual(context.viewModel.content, "Local draft")
        XCTAssertEqual(context.viewModel.canonicalContent, draftCanonical)
        XCTAssertTrue(context.viewModel.isQueuedForSync)

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

    func testApplyTreeUpdateSyncsActiveNoteMetadataWithoutDroppingContent() async {
        let cache = TestCacheClient()
        let api = NotesStoreTestsSupport.MockNotesAPI(
            treeResult: .failure(NotesStoreTestsSupport.MockError.forced),
            noteResult: .failure(NotesStoreTestsSupport.MockError.forced)
        )
        let store = NotesStore(api: api, cache: cache)
        let activeNote = NotePayload(
            id: "note-1",
            name: "Cached.md",
            content: "Preserve this note body",
            path: "/note-1.md",
            modified: 1,
            created: nil
        )
        store.applyEditorUpdate(activeNote)

        let refreshedTree = FileTree(children: [
            FileNode(
                name: "Fresh.md",
                path: "/note-1.md",
                type: .file,
                size: nil,
                modified: 2,
                created: nil,
                children: nil,
                expanded: nil,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: nil
            )
        ])

        store.applyTreeUpdate(refreshedTree, persist: true)

        XCTAssertEqual(store.activeNote?.name, "Fresh.md")
        XCTAssertEqual(store.activeNote?.modified, 2)
        XCTAssertEqual(store.activeNote?.plainText, "Preserve this note body")

        let cached: NotePayload? = cache.get(key: CacheKeys.note(id: "note-1"))
        XCTAssertEqual(cached?.name, "Fresh.md")
        XCTAssertEqual(cached?.plainText, "Preserve this note body")
    }

    private func makeNotesViewModel(selectedNoteId: String? = nil) -> NotesViewModel {
        let api = NotesStoreTestsSupport.MockNotesAPI(
            treeResult: .failure(NotesStoreTestsSupport.MockError.forced),
            noteResult: .failure(NotesStoreTestsSupport.MockError.forced)
        )
        let store = NotesStore(api: api, cache: TestCacheClient())
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: NotesStoreTestsSupport.TestNetworkStatus(isNetworkAvailable: true)
        )
        viewModel.selectedNoteId = selectedNoteId
        return viewModel
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
        XCTFail(
            """
            Timed out waiting for editor content. \
            currentNoteId=\(String(describing: viewModel.currentNoteId)) \
            content=\(viewModel.content)
            """
        )
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
                    if content == "Server incoming" {
                        self?.observedServerContent = true
                    }
                }
                .store(in: &cancellables)
            viewModel.$canonicalContent
                .sink { [weak self] canonicalContent in
                    if canonicalContent == serverCanonical {
                        self?.observedServerCanonical = true
                    }
                }
                .store(in: &cancellables)
            viewModel.$isQueuedForSync
                .sink { [weak self] isQueuedForSync in
                    if !isQueuedForSync {
                        self?.observedQueueClear = true
                    }
                }
                .store(in: &cancellables)
        }
    }

}
