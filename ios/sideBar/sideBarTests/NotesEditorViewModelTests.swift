// swiftlint:disable file_length
import Foundation
import sideBarShared
import SwiftUI
import XCTest
@testable import sideBar

@MainActor
final class NotesEditorViewModelTests: XCTestCase {
    func testHandleNoteUpdateSetsContentAndBaseline() async {
        let api = MockNotesAPI(updateResult: .failure(MockError.forced))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
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
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let note = NotePayload(id: "n1", name: "Note", content: "Hello", path: "/note.md", modified: nil, created: nil)

        store.applyEditorUpdate(note)
        await Task.yield()

        XCTAssertEqual(viewModel.currentNoteId, "n1")
        XCTAssertEqual(viewModel.content, "Hello")
    }

    func testHandleNoteUpdateClearsContentWhenNoteNil() async {
        let api = MockNotesAPI(updateResult: .failure(MockError.forced))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
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
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let note = NotePayload(id: "n1", name: "Note", content: "Hello", path: "/note.md", modified: nil, created: nil)

        store.applyEditorUpdate(note)
        await Task.yield()
        store.clearActiveNote()
        await Task.yield()

        XCTAssertNil(viewModel.currentNoteId)
        XCTAssertEqual(viewModel.content, "")
    }

    func testSyncFromNativeEditorUpdatesContent() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }
        let updated = NotePayload(id: "n1", name: "Note", content: "Updated", path: "/note.md", modified: 100, created: nil)
        let api = MockNotesAPI(updateResult: .success(updated))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
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
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let note = NotePayload(id: "n1", name: "Note", content: "Hello", path: "/note.md", modified: nil, created: nil)

        store.applyEditorUpdate(note)
        await Task.yield()

        let nativeViewModel = viewModel.makeNativeEditorViewModel()
        try await waitUntil(timeoutSeconds: 1.0) { !nativeViewModel.isUpdatingPrefixVisibility }
        nativeViewModel.attributedContent = AttributedString("Updated")
        nativeViewModel.handleContentChange(previous: AttributedString("Hello"))
        try await waitUntil(timeoutSeconds: 3.0) { nativeViewModel.hasUnsavedChanges }

        XCTAssertTrue(nativeViewModel.hasUnsavedChanges)

        await viewModel.syncFromNativeEditor(nativeViewModel)

        XCTAssertEqual(store.activeNote?.content, "Updated")
        XCTAssertFalse(nativeViewModel.hasUnsavedChanges)
    }

    func testHandleNoteUpdateWithSameContentPreservesNativeSelection() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }
        let api = MockNotesAPI(updateResult: .failure(MockError.forced))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
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
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let note = NotePayload(id: "n1", name: "Note", content: "Hello", path: "/note.md", modified: 100, created: nil)
        store.applyEditorUpdate(note)
        await Task.yield()

        let nativeViewModel = viewModel.makeNativeEditorViewModel()
        viewModel.attachNativeEditor(nativeViewModel)
        let cursor = nativeViewModel.attributedContent.endIndex
        nativeViewModel.selection = AttributedTextSelection(range: cursor..<cursor)
        let before = nsRange(from: nativeViewModel.selection, in: nativeViewModel.attributedContent)

        let refreshed = NotePayload(id: "n1", name: "Note", content: "Hello", path: "/note.md", modified: 200, created: nil)
        store.applyEditorUpdate(refreshed)
        await Task.yield()
        let after = nsRange(from: nativeViewModel.selection, in: nativeViewModel.attributedContent)

        XCTAssertEqual(after, before)
    }

    func testLoadsUnsyncedDraftWhenAvailable() async throws {
        let api = MockNotesAPI(updateResult: .failure(MockError.forced))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
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
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: "Server",
            path: "/note.md",
            modified: Date().addingTimeInterval(-60).timeIntervalSince1970,
            created: nil
        )

        try draftStorage.saveDraft(entityType: "note", entityId: "n1", content: "Draft")
        store.applyEditorUpdate(note)
        try await waitUntil(timeoutSeconds: 2.0) { viewModel.content == "Draft" && viewModel.isDirty }

        XCTAssertEqual(viewModel.content, "Draft")
        XCTAssertTrue(viewModel.isDirty)
    }

    func testDetectsConflictWhenServerIsNewer() async throws {
        let api = MockNotesAPI(updateResult: .failure(MockError.forced))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
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
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let serverDate = Date().addingTimeInterval(60)
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: "Server",
            path: "/note.md",
            modified: serverDate.timeIntervalSince1970,
            created: nil)

        try draftStorage.saveDraft(entityType: "note", entityId: "n1", content: "Draft")
        store.applyEditorUpdate(note)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(viewModel.content, "Server")
        XCTAssertNotNil(viewModel.conflict)
    }

    func testSyncFromNativeEditorCoalescesRequestDuringInFlightSave() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }
        let updated = NotePayload(id: "n1", name: "Note", content: "Updated", path: "/note.md", modified: 100, created: nil)
        let api = NotesAPISpy(updateResult: .success(updated))
        api.updateDelayNanoseconds = 400_000_000
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
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
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let note = NotePayload(id: "n1", name: "Note", content: "Hello", path: "/note.md", modified: nil, created: nil)

        store.applyEditorUpdate(note)
        await Task.yield()

        let nativeViewModel = viewModel.makeNativeEditorViewModel()
        viewModel.attachNativeEditor(nativeViewModel)
        nativeViewModel.attributedContent = AttributedString("First")

        let firstSyncTask = Task {
            await viewModel.syncFromNativeEditor(nativeViewModel)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        nativeViewModel.attributedContent = AttributedString("Second")
        await viewModel.syncFromNativeEditor(nativeViewModel)

        await firstSyncTask.value
        try await waitUntil(timeoutSeconds: 2.0) {
            api.updateCallCount == 2
        }

        XCTAssertEqual(api.updatedContents.count, 2)
        XCTAssertEqual(
            api.updatedContents.compactMap(NotesRichTextCodec.decodeBase64RTFToPlainText),
            ["First", "Second"]
        )
    }

    func testCurrentPlainTextSnapshotUsesAttachedNativeEditorContent() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }
        let api = MockNotesAPI(updateResult: .failure(MockError.forced))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
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
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: "Server body",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        store.applyEditorUpdate(note)
        await Task.yield()

        let nativeViewModel = viewModel.makeNativeEditorViewModel()
        viewModel.attachNativeEditor(nativeViewModel)
        nativeViewModel.attributedContent = AttributedString("Local unsaved body")

        XCTAssertEqual(
            viewModel.currentPlainTextSnapshot(fallback: "fallback"),
            "Local unsaved body"
        )
    }

    func testCurrentPlainTextSnapshotCanonicalizesWhenNativeEditorDetached() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }
        let api = MockNotesAPI(updateResult: .failure(MockError.forced))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
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
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let nonCanonical = "- [x] Done"
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: nonCanonical,
            path: "/note.md",
            modified: nil,
            created: nil
        )
        store.applyEditorUpdate(note)
        await Task.yield()

        let canonical = canonicalSnapshotOutput(nonCanonical)

        XCTAssertEqual(viewModel.currentPlainTextSnapshot(fallback: "fallback"), canonical)
    }

}

@MainActor
extension NotesEditorViewModelTests {
    func testDetachNativeEditorStopsUsingDetachedSnapshot() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }
        let api = MockNotesAPI(updateResult: .failure(MockError.forced))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
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
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: "Server body",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        store.applyEditorUpdate(note)
        await Task.yield()

        let nativeViewModel = viewModel.makeNativeEditorViewModel()
        viewModel.attachNativeEditor(nativeViewModel)
        nativeViewModel.attributedContent = AttributedString("Local unsaved body")
        XCTAssertEqual(viewModel.currentPlainTextSnapshot(fallback: "fallback"), "Local unsaved body")

        viewModel.detachNativeEditor(nativeViewModel)
        XCTAssertEqual(viewModel.currentPlainTextSnapshot(fallback: "fallback"), "Server body")
    }

    func testDetachNativeEditorIgnoresDifferentEditorInstance() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }
        let api = MockNotesAPI(updateResult: .failure(MockError.forced))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
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
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: "Server body",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        store.applyEditorUpdate(note)
        await Task.yield()

        let attachedEditor = viewModel.makeNativeEditorViewModel()
        viewModel.attachNativeEditor(attachedEditor)
        attachedEditor.attributedContent = AttributedString("Local unsaved body")
        XCTAssertEqual(viewModel.currentPlainTextSnapshot(fallback: "fallback"), "Local unsaved body")

        let differentEditor = NativeNoteEditorViewModel()
        viewModel.detachNativeEditor(differentEditor)
        XCTAssertEqual(viewModel.currentPlainTextSnapshot(fallback: "fallback"), "Local unsaved body")
    }

    func testResolveConflictKeepLocalCanonicalizesDraftContent() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }
        let nonCanonical = "- [x] Done"
        let canonical = canonicalSnapshotOutput(nonCanonical)
        XCTAssertNotEqual(canonical, nonCanonical)

        let api = MockNotesAPI(updateResult: .failure(MockError.forced))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
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
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: "Server",
            path: "/note.md",
            modified: Date().addingTimeInterval(60).timeIntervalSince1970,
            created: nil
        )

        try draftStorage.saveDraft(entityType: "note", entityId: "n1", content: nonCanonical)
        store.applyEditorUpdate(note)
        try await waitUntil(timeoutSeconds: 2.0) { viewModel.conflict != nil }

        await viewModel.resolveConflictKeepLocal()

        XCTAssertNil(viewModel.conflict)
        XCTAssertEqual(viewModel.content, canonical)
        XCTAssertTrue(viewModel.isDirty)
        XCTAssertTrue(viewModel.isQueuedForSync)
        let draft = try draftStorage.getDraft(entityType: "note", entityId: "n1")
        XCTAssertEqual(draft?.content, canonical)
    }

    func testCurrentPlainTextSnapshotCanonicalizationDriftReturnsStableOutput() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }
        let driftInput = """
        > 1. Parent
        >    - [ ] Open **bold**
        >    - [x] Done *italic* `code`
        """
        let api = MockNotesAPI(updateResult: .failure(MockError.forced))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
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
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: driftInput,
            path: "/note.md",
            modified: nil,
            created: nil
        )
        store.applyEditorUpdate(note)
        await Task.yield()

        let snapshot = viewModel.currentPlainTextSnapshot(fallback: "fallback")
        XCTAssertNotEqual(snapshot, driftInput)
        XCTAssertEqual(viewModel.currentPlainTextSnapshot(fallback: "fallback"), snapshot)
    }

    func testResolveConflictKeepBothCanonicalizesCopiedContent() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }
        let nonCanonical = "- [x] Done"
        let canonical = canonicalSnapshotOutput(nonCanonical)
        XCTAssertNotEqual(canonical, nonCanonical)

        let created = NotePayload(
            id: "copy-id",
            name: "Note.md (Offline Copy)",
            content: "",
            path: "/Note.md (Offline Copy)",
            modified: nil,
            created: nil
        )
        let updated = NotePayload(
            id: "copy-id",
            name: "Note.md (Offline Copy)",
            content: canonical,
            path: "/Note.md (Offline Copy)",
            modified: 100,
            created: nil
        )
        let api = NotesAPISpy(
            updateResult: .success(updated),
            createResult: .success(created)
        )
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
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
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let note = NotePayload(
            id: "n1",
            name: "Note.md",
            content: "Server content",
            path: "/folder/Note.md",
            modified: Date().addingTimeInterval(60).timeIntervalSince1970,
            created: nil
        )

        try draftStorage.saveDraft(entityType: "note", entityId: "n1", content: nonCanonical)
        store.applyEditorUpdate(note)
        try await waitUntil(timeoutSeconds: 2.0) { viewModel.conflict != nil }

        await viewModel.resolveConflictKeepBoth()
        try await waitUntil(timeoutSeconds: 2.0) { api.updateCallCount == 1 }

        XCTAssertNil(viewModel.conflict)
        XCTAssertEqual(viewModel.currentNoteId, "n1")
        XCTAssertEqual(viewModel.content, "Server content")
        XCTAssertFalse(viewModel.isDirty)
        XCTAssertFalse(viewModel.isQueuedForSync)
        XCTAssertEqual(notesViewModel.activeNote?.id, "n1")
        XCTAssertEqual(notesViewModel.selectedNoteId, "/folder/Note.md")
        XCTAssertEqual(api.createdTitles, ["Note.md (Offline Copy)"])
        XCTAssertEqual(api.updatedContents, [canonical])
        let draft = try draftStorage.getDraft(entityType: "note", entityId: "n1")
        XCTAssertNil(draft)
    }

    func testSyncFromNativeEditorSendsConstrainedPlainText() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }
        let nonCanonical = "- [x] Done"
        let canonicalProbe = NativeNoteEditorViewModel()
        canonicalProbe.loadText(nonCanonical)
        let canonicalPlainText = canonicalProbe.currentPlainText()
        XCTAssertNotEqual(canonicalPlainText, nonCanonical)

        let updated = NotePayload(id: "n1", name: "Note", content: canonicalPlainText, path: "/note.md", modified: 100, created: nil)
        let api = NotesAPISpy(updateResult: .success(updated))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
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
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let note = NotePayload(id: "n1", name: "Note", content: nonCanonical, path: "/note.md", modified: nil, created: nil)

        store.applyEditorUpdate(note)
        await Task.yield()

        let nativeViewModel = viewModel.makeNativeEditorViewModel()
        let expectedRoundTripPlainText = NotesRichTextCodec.decodeBase64RTFToPlainText(
            nativeViewModel.currentCanonicalContent()
        )
        await viewModel.syncFromNativeEditor(nativeViewModel)

        XCTAssertEqual(api.updatedContents.count, 1)
        XCTAssertEqual(
            NotesRichTextCodec.decodeBase64RTFToPlainText(api.updatedContents[0]),
            expectedRoundTripPlainText
        )
        XCTAssertEqual(viewModel.content, canonicalPlainText)
    }

    func testOfflineSaveQueuesDraftWithoutApiCall() async throws {
        let api = NotesAPISpy(updateResult: .failure(MockError.forced))
        let cache = TestCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toast = ToastCenter()
        let notesViewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toast,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
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
            networkStatus: TestNetworkStatus(isNetworkAvailable: false)
        )
        let note = NotePayload(id: "n1", name: "Note", content: "- [x] Done", path: "/note.md", modified: nil, created: nil)

        store.applyEditorUpdate(note)
        await Task.yield()

        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }
        let nativeViewModel = viewModel.makeNativeEditorViewModel()
        let canonicalPlainText = nativeViewModel.currentPlainText()
        XCTAssertNotEqual(canonicalPlainText, note.content)

        await viewModel.syncFromNativeEditor(nativeViewModel)

        XCTAssertTrue(viewModel.isQueuedForSync)
        XCTAssertFalse(viewModel.isSaving)
        XCTAssertEqual(api.updateCallCount, 0)
        XCTAssertEqual(viewModel.content, canonicalPlainText)
        let draft = try draftStorage.getDraft(entityType: "note", entityId: "n1")
        XCTAssertEqual(draft?.content, canonicalPlainText)
        let pending = try await writeQueue.fetchPendingWrites()
        XCTAssertEqual(pending.count, 1)
    }
}

@available(iOS 26.0, macOS 26.0, *)
@MainActor
private func canonicalPlainTextPass(_ plainText: String) -> String {
    let probe = NativeNoteEditorViewModel()
    probe.loadText(plainText)
    return probe.currentPlainText()
}

@available(iOS 26.0, macOS 26.0, *)
@MainActor
private func canonicalSnapshotOutput(_ markdown: String) -> String {
    canonicalPlainTextPass(markdown)
}

private func waitUntil(timeoutSeconds: TimeInterval, condition: @escaping () -> Bool) async throws {
    let timeout = Date().addingTimeInterval(timeoutSeconds)
    while Date() < timeout {
        if condition() {
            return
        }
        try await Task.sleep(nanoseconds: 30_000_000)
    }
    XCTFail("Timed out waiting for condition")
}

@available(iOS 26.0, macOS 26.0, *)
private func nsRange(from selection: AttributedTextSelection, in text: AttributedString) -> NSRange {
    let string = String(text.characters)
    switch selection.indices(in: text) {
    case .insertionPoint(let index):
        let charOffset = text.characters.distance(from: text.startIndex, to: index)
        let stringIndex = string.index(string.startIndex, offsetBy: charOffset)
        let location = stringIndex.utf16Offset(in: string)
        return NSRange(location: location, length: 0)
    case .ranges(let ranges):
        guard let first = ranges.ranges.first else {
            return NSRange(location: 0, length: 0)
        }
        let lowerOffset = text.characters.distance(from: text.startIndex, to: first.lowerBound)
        let upperOffset = text.characters.distance(from: text.startIndex, to: first.upperBound)
        let lowerIndex = string.index(string.startIndex, offsetBy: lowerOffset)
        let upperIndex = string.index(string.startIndex, offsetBy: upperOffset)
        let location = lowerIndex.utf16Offset(in: string)
        let length = upperIndex.utf16Offset(in: string) - location
        return NSRange(location: location, length: max(0, length))
    }
}

private enum MockError: Error {
    case forced
}

@MainActor
private struct TestNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool
    let isOffline: Bool

    init(isNetworkAvailable: Bool, isOffline: Bool = false) {
        self.isNetworkAvailable = isNetworkAvailable
        self.isOffline = isOffline
    }
}

@MainActor
private final class NotesAPISpy: NotesProviding {
    private(set) var updateCallCount = 0
    private(set) var updatedContents: [String] = []
    private(set) var createdTitles: [String] = []
    var updateDelayNanoseconds: UInt64 = 0
    let updateResult: Result<NotePayload, Error>
    let createResult: Result<NotePayload, Error>

    init(
        updateResult: Result<NotePayload, Error>,
        createResult: Result<NotePayload, Error> = .failure(MockError.forced)
    ) {
        self.updateResult = updateResult
        self.createResult = createResult
    }

    func listTree() async throws -> FileTree {
        throw MockError.forced
    }

    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        throw MockError.forced
    }

    func getNote(id: String) async throws -> NotePayload {
        _ = id
        throw MockError.forced
    }

    func search(query: String, limit: Int) async throws -> [FileNode] {
        _ = query
        _ = limit
        return []
    }

    func updateNote(id: String, content: String) async throws -> NotePayload {
        _ = id
        updateCallCount += 1
        updatedContents.append(content)
        if updateDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: updateDelayNanoseconds)
        }
        return try updateResult.get()
    }

    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        createdTitles.append(request.title ?? "")
        return try createResult.get()
    }

    func renameNote(id: String, newName: String) async throws -> NotePayload {
        _ = id
        _ = newName
        throw MockError.forced
    }

    func moveNote(id: String, folder: String) async throws -> NotePayload {
        _ = id
        _ = folder
        throw MockError.forced
    }

    func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        _ = id
        _ = archived
        throw MockError.forced
    }

    func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        _ = id
        _ = pinned
        throw MockError.forced
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
    }

    func deleteNote(id: String) async throws -> NotePayload {
        _ = id
        throw MockError.forced
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

private final class MockNotesAPI: NotesProviding {
    let updateResult: Result<NotePayload, Error>

    init(updateResult: Result<NotePayload, Error>) {
        self.updateResult = updateResult
    }

    func listTree() async throws -> FileTree {
        throw MockError.forced
    }

    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        throw MockError.forced
    }

    func getNote(id: String) async throws -> NotePayload {
        _ = id
        throw MockError.forced
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

    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        _ = request
        throw MockError.forced
    }

    func renameNote(id: String, newName: String) async throws -> NotePayload {
        _ = id
        _ = newName
        throw MockError.forced
    }

    func moveNote(id: String, folder: String) async throws -> NotePayload {
        _ = id
        _ = folder
        throw MockError.forced
    }

    func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        _ = id
        _ = archived
        throw MockError.forced
    }

    func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        _ = id
        _ = pinned
        throw MockError.forced
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
    }

    func deleteNote(id: String) async throws -> NotePayload {
        _ = id
        throw MockError.forced
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
