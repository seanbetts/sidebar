// swiftlint:disable file_length
import CoreData
import Foundation
import sideBarShared
import SwiftUI
import XCTest
@testable import sideBar

// swiftlint:disable type_body_length
@MainActor
final class NotesEditorViewModelTests: XCTestCase {
    func testUnsupportedContentDetectionIdentifiesNonParagraphBlocks() {
        let document = NotesSemanticDocument(
            blocks: [
                .paragraph([.init(text: "Intro", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])]),
                .init(type: .table, content: [.init(text: "Cell", marks: [])]),
                .init(type: .heading, content: [.init(text: "Repeated", marks: [])])
            ]
        )

        XCTAssertEqual(
            NotesUnsupportedContent.detect(in: document)?.blockTypes,
            [.heading, .table]
        )
    }

    func testHandleNoteUpdateMarksUnsupportedNotesReadOnly() async {
        let context = makeNotesEditorViewModelTestContext(
            api: MockNotesAPI(updateResult: .failure(MockError.forced))
        )
        let note = makeUnsupportedTestNote()

        context.store.applyEditorUpdate(note)
        try? await waitUntilUnsupportedNoteHydrated(context.viewModel)

        XCTAssertEqual(context.viewModel.currentNoteId, "n1")
        XCTAssertEqual(context.viewModel.presentationMode, .read)
        XCTAssertTrue(context.viewModel.isReadOnly)
        XCTAssertFalse(context.viewModel.isEditingNote)
        XCTAssertEqual(
            context.viewModel.unsupportedContent?.blockTypes,
            [.heading]
        )
        XCTAssertEqual(
            NotesSemanticDocumentCodec.decode(context.viewModel.canonicalContent),
            note.document
        )
    }

    func testEnterEditModeDoesNothingForUnsupportedNotes() async {
        let context = makeNotesEditorViewModelTestContext(
            api: MockNotesAPI(updateResult: .failure(MockError.forced))
        )
        let note = makeUnsupportedTestNote()

        context.store.applyEditorUpdate(note)
        try? await waitUntilUnsupportedNoteHydrated(context.viewModel)
        context.viewModel.enterEditMode(at: .characterOffset(4))

        XCTAssertEqual(context.viewModel.presentationMode, .read)
        XCTAssertFalse(context.viewModel.isEditingNote)
        XCTAssertNil(context.viewModel.consumePendingEditSelectionTarget())
    }

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
        await waitUntilNoteHydrated(viewModel, note: note)

        XCTAssertEqual(viewModel.currentNoteId, "n1")
        XCTAssertEqual(viewModel.content, "Hello")
        XCTAssertEqual(
            decodedCanonicalPlainText(viewModel.canonicalContent),
            "Hello"
        )
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
        await waitUntilNoteHydrated(viewModel, note: note)
        store.clearActiveNote()
        await waitUntilNoActiveNote(viewModel)

        XCTAssertNil(viewModel.currentNoteId)
        XCTAssertEqual(viewModel.content, "")
    }

    func testHandleNoteUpdateStartsInReadMode() async {
        let context = makeNotesEditorViewModelTestContext(
            api: MockNotesAPI(updateResult: .failure(MockError.forced))
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
        await waitUntilNoteHydrated(context.viewModel, note: note)

        XCTAssertEqual(context.viewModel.presentationMode, .read)
        XCTAssertFalse(context.viewModel.isEditingNote)
    }

    func testEnterEditModeChangesPresentationModeWithoutClearingCurrentNote() async {
        let context = makeNotesEditorViewModelTestContext(
            api: MockNotesAPI(updateResult: .failure(MockError.forced))
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
        await waitUntilNoteHydrated(context.viewModel, note: note)
        context.viewModel.enterEditMode()

        XCTAssertEqual(context.viewModel.presentationMode, .edit)
        XCTAssertTrue(context.viewModel.isEditingNote)
        XCTAssertEqual(context.viewModel.currentNoteId, "n1")
    }

    func testEnterEditModeStoresPendingSelectionTarget() async {
        let context = makeNotesEditorViewModelTestContext(
            api: MockNotesAPI(updateResult: .failure(MockError.forced))
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
        await waitUntilNoteHydrated(context.viewModel, note: note)

        context.viewModel.enterEditMode(at: .characterOffset(7))

        XCTAssertEqual(
            context.viewModel.consumePendingEditSelectionTarget(),
            .characterOffset(7)
        )
    }

    func testConsumePendingEditSelectionTargetReturnsItOnceAndClearsIt() async {
        let context = makeNotesEditorViewModelTestContext(
            api: MockNotesAPI(updateResult: .failure(MockError.forced))
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
        await waitUntilNoteHydrated(context.viewModel, note: note)

        context.viewModel.enterEditMode(at: .characterOffset(7))

        XCTAssertEqual(
            context.viewModel.consumePendingEditSelectionTarget(),
            .characterOffset(7)
        )
        XCTAssertNil(context.viewModel.consumePendingEditSelectionTarget())
    }

    func testExitEditModeReturnsToReadMode() async {
        let context = makeNotesEditorViewModelTestContext(
            api: MockNotesAPI(updateResult: .failure(MockError.forced))
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
        await waitUntilNoteHydrated(context.viewModel, note: note)
        context.viewModel.enterEditMode()

        XCTAssertEqual(context.viewModel.presentationMode, .edit)

        context.viewModel.exitEditModeToRead()

        XCTAssertEqual(context.viewModel.presentationMode, .read)
        XCTAssertFalse(context.viewModel.isEditingNote)
        XCTAssertEqual(context.viewModel.currentNoteId, "n1")
    }

    func testExitEditModeClearsPendingSelectionTarget() async {
        let context = makeNotesEditorViewModelTestContext(
            api: MockNotesAPI(updateResult: .failure(MockError.forced))
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
        await waitUntilNoteHydrated(context.viewModel, note: note)
        context.viewModel.enterEditMode(at: .characterOffset(7))

        context.viewModel.exitEditModeToRead()

        XCTAssertNil(context.viewModel.consumePendingEditSelectionTarget())
    }

    func testHandleNoteUpdateResetsPresentationModeWhenSwitchingToDifferentNote() async {
        let context = makeNotesEditorViewModelTestContext(
            api: MockNotesAPI(updateResult: .failure(MockError.forced))
        )
        let firstNote = NotePayload(
            id: "n1",
            name: "First",
            content: "Hello",
            path: "/first.md",
            modified: nil,
            created: nil
        )
        let secondNote = NotePayload(
            id: "n2",
            name: "Second",
            content: "World",
            path: "/second.md",
            modified: nil,
            created: nil
        )

        context.store.applyEditorUpdate(firstNote)
        await waitUntilNoteHydrated(context.viewModel, note: firstNote)
        context.viewModel.enterEditMode()
        XCTAssertEqual(context.viewModel.presentationMode, .edit)

        context.store.applyEditorUpdate(secondNote)
        await waitUntilNoteHydrated(context.viewModel, note: secondNote)

        XCTAssertEqual(context.viewModel.currentNoteId, "n2")
        XCTAssertEqual(context.viewModel.presentationMode, .read)
        XCTAssertFalse(context.viewModel.isEditingNote)
    }

    func testHandleNoteUpdateClearsPresentationModeWhenNoteNil() async {
        let context = makeNotesEditorViewModelTestContext(
            api: MockNotesAPI(updateResult: .failure(MockError.forced))
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
        await waitUntilNoteHydrated(context.viewModel, note: note)
        context.viewModel.enterEditMode()
        XCTAssertEqual(context.viewModel.presentationMode, .edit)

        context.store.clearActiveNote()
        await waitUntilNoActiveNote(context.viewModel)

        XCTAssertNil(context.viewModel.currentNoteId)
        XCTAssertEqual(context.viewModel.presentationMode, .read)
        XCTAssertFalse(context.viewModel.isEditingNote)
    }

    func testHandleNoteUpdateClearsPendingSelectionTargetWhenSwitchingToDifferentNote() async {
        let context = makeNotesEditorViewModelTestContext(
            api: MockNotesAPI(updateResult: .failure(MockError.forced))
        )
        let firstNote = NotePayload(
            id: "n1",
            name: "First",
            content: "Hello",
            path: "/first.md",
            modified: nil,
            created: nil
        )
        let secondNote = NotePayload(
            id: "n2",
            name: "Second",
            content: "World",
            path: "/second.md",
            modified: nil,
            created: nil
        )

        context.store.applyEditorUpdate(firstNote)
        await waitUntilNoteHydrated(context.viewModel, note: firstNote)
        context.viewModel.enterEditMode(at: .characterOffset(7))

        context.store.applyEditorUpdate(secondNote)
        await waitUntilNoteHydrated(context.viewModel, note: secondNote)

        XCTAssertNil(context.viewModel.consumePendingEditSelectionTarget())
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
        await waitUntilNoteHydrated(viewModel, note: note)

        let nativeViewModel = viewModel.makeNativeEditorViewModel()
        nativeViewModel.attributedContent = AttributedString("Updated")
        nativeViewModel.handleContentChange(previous: AttributedString("Hello"))
        try await waitUntil(timeoutSeconds: 3.0) { nativeViewModel.hasUnsavedChanges }

        XCTAssertTrue(nativeViewModel.hasUnsavedChanges)

        await viewModel.syncFromNativeEditor(nativeViewModel)

        XCTAssertEqual(store.activeNote?.content, "Updated")
        XCTAssertFalse(nativeViewModel.hasUnsavedChanges)
    }

    func testToggleFormattingUsesAttachedNativeEditor() async throws {
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
        let note = NotePayload(id: "n1", name: "Note", content: "Hello", path: "/note.md", modified: nil, created: nil)

        store.applyEditorUpdate(note)
        await waitUntilNoteHydrated(viewModel, note: note)

        let nativeViewModel = viewModel.makeNativeEditorViewModel()
        viewModel.attachNativeEditor(nativeViewModel)
        let range = characterRange(length: 5, in: nativeViewModel.attributedContent)
        nativeViewModel.selection = AttributedTextSelection(range: range)

        XCTAssertFalse(viewModel.canApplyFormattingCommands())

        viewModel.enterEditMode()

        XCTAssertTrue(viewModel.canApplyFormattingCommands())

        viewModel.toggleFormatting(.bold)

        XCTAssertTrue(noteRangeHasBoldTrait(nativeViewModel.attributedContent, range: range))
        XCTAssertTrue(viewModel.isFormattingActive(.bold))
        XCTAssertTrue(viewModel.isDirty)
    }

    func testSetFormattingClearsAttachedNativeEditorFormatting() async throws {
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
        let note = NotePayload(id: "n1", name: "Note", content: "Hello", path: "/note.md", modified: nil, created: nil)

        store.applyEditorUpdate(note)
        await waitUntilNoteHydrated(viewModel, note: note)

        let nativeViewModel = viewModel.makeNativeEditorViewModel()
        viewModel.attachNativeEditor(nativeViewModel)
        let initialRange = characterRange(length: 5, in: nativeViewModel.attributedContent)
        nativeViewModel.selection = AttributedTextSelection(range: initialRange)

        XCTAssertFalse(viewModel.canApplyFormattingCommands())

        viewModel.enterEditMode()

        viewModel.setFormatting(.underline, enabled: true)
        let enabledRange = characterRange(length: 5, in: nativeViewModel.attributedContent)
        XCTAssertTrue(noteRangeIsUnderlined(nativeViewModel.attributedContent, range: enabledRange))

        nativeViewModel.selection = AttributedTextSelection(range: enabledRange)
        viewModel.setFormatting(.underline, enabled: false)

        let disabledRange = characterRange(length: 5, in: nativeViewModel.attributedContent)
        XCTAssertFalse(noteRangeIsUnderlined(nativeViewModel.attributedContent, range: disabledRange))
        XCTAssertFalse(viewModel.isFormattingActive(.underline))
    }

    func testSaveIfNeededPersistsFormattingOnlyNativeEditorChange() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let initialContent = canonicalPlainTextPass("Hello")
        let updated = NotePayload(
            id: "n1",
            name: "Note",
            content: initialContent,
            path: "/note.md",
            modified: 100,
            created: nil
        )
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

        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: initialContent,
            path: "/note.md",
            modified: nil,
            created: nil
        )
        store.applyEditorUpdate(note)
        await waitUntilNoteHydrated(viewModel, note: note)

        let nativeViewModel = viewModel.makeNativeEditorViewModel()
        viewModel.attachNativeEditor(nativeViewModel)
        let range = characterRange(length: 5, in: nativeViewModel.attributedContent)
        nativeViewModel.selection = AttributedTextSelection(range: range)
        viewModel.enterEditMode()

        let previous = nativeViewModel.attributedContent
        nativeViewModel.applyFormatting(.bold)
        nativeViewModel.handleContentChange(previous: previous)
        let updatedRange = characterRange(length: 5, in: nativeViewModel.attributedContent)

        XCTAssertTrue(noteRangeHasBoldTrait(nativeViewModel.attributedContent, range: updatedRange))
        XCTAssertTrue(nativeViewModel.hasUnsavedChanges)

        await viewModel.saveIfNeeded()

        XCTAssertEqual(api.updateCallCount, 1)
        XCTAssertEqual(api.updatedContents.count, 1)
        XCTAssertNotEqual(api.updatedContents[0], initialContent)
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
        await waitUntilNoteHydrated(viewModel, note: note)

        let nativeViewModel = viewModel.makeNativeEditorViewModel()
        viewModel.attachNativeEditor(nativeViewModel)
        let cursor = nativeViewModel.attributedContent.endIndex
        nativeViewModel.selection = AttributedTextSelection(range: cursor..<cursor)
        let before = nsRange(from: nativeViewModel.selection, in: nativeViewModel.attributedContent)

        let refreshed = NotePayload(id: "n1", name: "Note", content: "Hello", path: "/note.md", modified: 200, created: nil)
        store.applyEditorUpdate(refreshed)
        await waitUntilNoteHydrated(viewModel, note: refreshed)
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

    func testLocalDraftWinsAutomaticallyWhenServerIsNewer() async throws {
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

        XCTAssertEqual(viewModel.content, "Draft")
        XCTAssertTrue(viewModel.isDirty)
        XCTAssertTrue(viewModel.isQueuedForSync)
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
        await waitUntilNoteHydrated(viewModel, note: note)

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
            api.updatedContents.compactMap(decodedCanonicalPlainText),
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
        await waitUntilNoteHydrated(viewModel, note: note)

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
        await waitUntilNoteHydrated(viewModel, note: note)

        let canonical = canonicalSnapshotOutput(nonCanonical)

        XCTAssertEqual(viewModel.currentPlainTextSnapshot(fallback: "fallback"), canonical)
    }

}

@MainActor
extension NotesEditorViewModelTests {
    func testSaveIfNeededPersistsDirtyNativeEditorSnapshot() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }
        let updated = NotePayload(
            id: "n1",
            name: "Note",
            content: "Updated",
            path: "/note.md",
            modified: 100,
            created: nil
        )
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
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: "Hello",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        store.applyEditorUpdate(note)
        await waitUntilNoteHydrated(viewModel, note: note)

        let nativeViewModel = viewModel.makeNativeEditorViewModel()
        viewModel.attachNativeEditor(nativeViewModel)
        viewModel.enterEditMode()
        nativeViewModel.attributedContent = AttributedString("Updated")
        nativeViewModel.handleContentChange(previous: AttributedString("Hello"))
        viewModel.setDirty(true)
        try await waitUntil(timeoutSeconds: 1.0) { viewModel.isDirty }
        try await waitUntil(timeoutSeconds: 3.0) { nativeViewModel.hasUnsavedChanges }

        await viewModel.saveIfNeeded()

        XCTAssertEqual(api.updateCallCount, 1)
        XCTAssertEqual(viewModel.content, "Updated")
        XCTAssertFalse(nativeViewModel.hasUnsavedChanges)
    }

    func testSaveIfNeededSkipsWhenEditorIsClean() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }
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
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: "Hello",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        store.applyEditorUpdate(note)
        await waitUntilNoteHydrated(viewModel, note: note)

        let nativeViewModel = viewModel.makeNativeEditorViewModel()
        viewModel.attachNativeEditor(nativeViewModel)
        viewModel.enterEditMode()
        await viewModel.saveIfNeeded()

        XCTAssertEqual(api.updateCallCount, 0)
    }

    func testSaveIfNeededPersistsNativeFormattingBeforeDirtyFlagPropagates() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let initialCanonical = canonicalPlainTextPass("Hello")
        let updated = NotePayload(
            id: "n1",
            name: "Note",
            content: initialCanonical,
            path: "/note.md",
            modified: 100,
            created: nil
        )
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

        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: initialCanonical,
            path: "/note.md",
            modified: nil,
            created: nil
        )
        store.applyEditorUpdate(note)
        await waitUntilNoteHydrated(viewModel, note: note)

        let nativeViewModel = viewModel.makeNativeEditorViewModel()
        viewModel.attachNativeEditor(nativeViewModel)
        let fullRange = characterRange(length: 5, in: nativeViewModel.attributedContent)
        nativeViewModel.selection = AttributedTextSelection(range: fullRange)
        viewModel.enterEditMode()
        nativeViewModel.applyFormatting(.bold)

        // Simulate quick close/switch before async dirty propagation reaches NotesEditorViewModel.
        viewModel.setDirty(false)

        await viewModel.saveIfNeeded()

        XCTAssertEqual(api.updateCallCount, 1)
        XCTAssertEqual(viewModel.content, "Hello")
        XCTAssertFalse(nativeViewModel.hasUnsavedChanges)
        XCTAssertEqual(api.updatedContents.count, 1)
        XCTAssertNotEqual(api.updatedContents[0], initialCanonical)
    }

}
// swiftlint:enable type_body_length

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NotesEditorViewModelTests {
    func testDetachNativeEditorStopsUsingDetachedSnapshot() async throws {
        let context = makeNotesEditorViewModelTestContext(
            api: MockNotesAPI(updateResult: .failure(MockError.forced))
        )
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: "Server body",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        context.store.applyEditorUpdate(note)
        await waitUntilNoteHydrated(context.viewModel, note: note)

        let nativeViewModel = context.viewModel.makeNativeEditorViewModel()
        context.viewModel.attachNativeEditor(nativeViewModel)
        nativeViewModel.attributedContent = AttributedString("Local unsaved body")
        XCTAssertEqual(context.viewModel.currentPlainTextSnapshot(fallback: "fallback"), "Local unsaved body")

        context.viewModel.detachNativeEditor(nativeViewModel)
        XCTAssertEqual(context.viewModel.currentPlainTextSnapshot(fallback: "fallback"), "Server body")
    }

    func testDetachNativeEditorIgnoresDifferentEditorInstance() async throws {
        let context = makeNotesEditorViewModelTestContext(
            api: MockNotesAPI(updateResult: .failure(MockError.forced))
        )
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: "Server body",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        context.store.applyEditorUpdate(note)
        await waitUntilNoteHydrated(context.viewModel, note: note)

        let attachedEditor = context.viewModel.makeNativeEditorViewModel()
        context.viewModel.attachNativeEditor(attachedEditor)
        attachedEditor.attributedContent = AttributedString("Local unsaved body")
        XCTAssertEqual(context.viewModel.currentPlainTextSnapshot(fallback: "fallback"), "Local unsaved body")

        context.viewModel.detachNativeEditor(NativeNoteEditorViewModel())
        XCTAssertEqual(context.viewModel.currentPlainTextSnapshot(fallback: "fallback"), "Local unsaved body")
    }

    func testSharedNativeEditorSurvivesDetachForEditorSurfaceReuse() async throws {
        let context = makeNotesEditorViewModelTestContext(
            api: MockNotesAPI(updateResult: .failure(MockError.forced))
        )
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: "Server body",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        context.store.applyEditorUpdate(note)
        await waitUntilNoteHydrated(context.viewModel, note: note)

        let sharedEditor = context.viewModel.sharedNativeEditor()
        context.viewModel.attachNativeEditor(sharedEditor)
        sharedEditor.attributedContent = AttributedString("Local unsaved body")

        context.viewModel.detachNativeEditor(sharedEditor)

        let reusedEditor = context.viewModel.sharedNativeEditor()
        XCTAssertTrue(reusedEditor === sharedEditor)
        XCTAssertEqual(reusedEditor.currentPlainText(), "Local unsaved body")
        XCTAssertEqual(context.viewModel.currentPlainTextSnapshot(fallback: "fallback"), "Server body")
    }

    func testNotesRuntimeOpenNoteContextUsesProjectedPlainText() async throws {
        let context = makeNotesEditorViewModelTestContext(
            api: MockNotesAPI(updateResult: .failure(MockError.forced))
        )
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: "Server body",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        context.store.applyEditorUpdate(note)
        await waitUntilNoteHydrated(context.viewModel, note: note)

        let nativeViewModel = context.viewModel.makeNativeEditorViewModel()
        context.viewModel.attachNativeEditor(nativeViewModel)
        nativeViewModel.attributedContent = AttributedString("Local unsaved body")

        let runtime = NotesRuntime(viewModel: context.notesViewModel, editorViewModel: context.viewModel)
        let contextPayload = runtime.openNoteContext()

        XCTAssertEqual(contextPayload?["plain_text"] as? String, "Local unsaved body")
        XCTAssertNil(contextPayload?["content"])
        XCTAssertNil(contextPayload?["content_format"])
    }

    func testAppliesUnsyncedDraftWithoutConflictResolution() async throws {
        let nonCanonical = "- [x] Done"
        let canonical = canonicalSnapshotOutput(nonCanonical)
        XCTAssertEqual(canonical, nonCanonical)

        let context = makeNotesEditorViewModelTestContext(
            api: MockNotesAPI(updateResult: .failure(MockError.forced))
        )
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: "Server",
            path: "/note.md",
            modified: Date().addingTimeInterval(60).timeIntervalSince1970,
            created: nil
        )

        try context.draftStorage.saveDraft(entityType: "note", entityId: "n1", content: nonCanonical)
        context.store.applyEditorUpdate(note)

        try await waitUntil(timeoutSeconds: 2.0) { context.viewModel.content == canonical }
        XCTAssertEqual(context.viewModel.content, canonical)
        XCTAssertTrue(context.viewModel.isDirty)
        XCTAssertTrue(context.viewModel.isQueuedForSync)
        let draft = try context.draftStorage.getDraft(entityType: "note", entityId: "n1")
        XCTAssertEqual(draft?.content, canonical)
    }

    func testCurrentPlainTextSnapshotCanonicalizationDriftReturnsStableOutput() async throws {
        let driftInput = """
        > 1. Parent
        >    - [ ] Open **bold**
        >    - [x] Done *italic* `code`
        """
        let context = makeNotesEditorViewModelTestContext(
            api: MockNotesAPI(updateResult: .failure(MockError.forced))
        )
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: driftInput,
            path: "/note.md",
            modified: nil,
            created: nil
        )
        context.store.applyEditorUpdate(note)
        await waitUntilNoteHydrated(context.viewModel, note: note)

        let snapshot = context.viewModel.currentPlainTextSnapshot(fallback: "fallback")
        XCTAssertEqual(snapshot, driftInput)
        XCTAssertEqual(context.viewModel.currentPlainTextSnapshot(fallback: "fallback"), snapshot)
    }

    func testDoesNotCreateServerCopyWhenApplyingUnsyncedDraft() async throws {
        let nonCanonical = "- [x] Done"
        let canonical = canonicalSnapshotOutput(nonCanonical)
        XCTAssertEqual(canonical, nonCanonical)

        let api = NotesAPISpy(updateResult: .failure(MockError.forced))
        let context = makeNotesEditorViewModelTestContext(api: api)
        let note = NotePayload(
            id: "n1",
            name: "Note.md",
            content: "Server content",
            path: "/folder/Note.md",
            modified: Date().addingTimeInterval(60).timeIntervalSince1970,
            created: nil
        )

        try context.draftStorage.saveDraft(entityType: "note", entityId: "n1", content: nonCanonical)
        context.store.applyEditorUpdate(note)

        try await waitUntil(timeoutSeconds: 2.0) { context.viewModel.content == canonical }

        XCTAssertEqual(context.viewModel.currentNoteId, "n1")
        XCTAssertEqual(context.viewModel.content, canonical)
        XCTAssertTrue(context.viewModel.isDirty)
        XCTAssertTrue(context.viewModel.isQueuedForSync)
        XCTAssertEqual(context.notesViewModel.activeNote?.id, "n1")
        XCTAssertNil(context.notesViewModel.selectedNoteId)
        XCTAssertTrue(api.createdTitles.isEmpty)
        XCTAssertTrue(api.updatedContents.isEmpty)
        let draft = try context.draftStorage.getDraft(entityType: "note", entityId: "n1")
        XCTAssertEqual(draft?.content, canonical)
    }

    func testSyncFromNativeEditorSkipsWhenBaselineAlreadyAligned() async throws {
        let nonCanonical = "- [x] Done"
        let canonicalProbe = NativeNoteEditorViewModel()
        canonicalProbe.loadText(nonCanonical)
        let canonicalPlainText = canonicalProbe.currentPlainText()
        XCTAssertEqual(canonicalPlainText, nonCanonical)

        let updated = NotePayload(
            id: "n1",
            name: "Note",
            content: canonicalPlainText,
            path: "/note.md",
            modified: 100,
            created: nil
        )
        let api = NotesAPISpy(updateResult: .success(updated))
        let context = makeNotesEditorViewModelTestContext(api: api)
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: nonCanonical,
            path: "/note.md",
            modified: nil,
            created: nil
        )

        context.store.applyEditorUpdate(note)
        await waitUntilNoteHydrated(context.viewModel, note: note)

        let nativeViewModel = context.viewModel.makeNativeEditorViewModel()
        let expectedRoundTripPlainText = nativeViewModel.currentPersistenceSnapshot().plainText
        await context.viewModel.syncFromNativeEditor(nativeViewModel)

        XCTAssertEqual(api.updatedContents.count, 0)
        XCTAssertEqual(api.updateCallCount, 0)
        XCTAssertFalse(context.viewModel.isSaving)
        XCTAssertEqual(context.viewModel.content, canonicalPlainText)
        XCTAssertEqual(
            decodedCanonicalPlainText(context.viewModel.canonicalContent),
            expectedRoundTripPlainText
        )
    }

    func testOfflineSyncSkipsQueueWhenEditorIsClean() async throws {
        let api = NotesAPISpy(updateResult: .failure(MockError.forced))
        let context = makeNotesEditorViewModelTestContext(
            api: api,
            networkAvailable: false
        )
        let note = NotePayload(
            id: "n1",
            name: "Note",
            content: "- [x] Done",
            path: "/note.md",
            modified: nil,
            created: nil
        )

        context.store.applyEditorUpdate(note)
        await waitUntilNoteHydrated(context.viewModel, note: note)

        let nativeViewModel = context.viewModel.makeNativeEditorViewModel()
        let canonicalPlainText = nativeViewModel.currentPlainText()
        XCTAssertEqual(canonicalPlainText, note.content)

        await context.viewModel.syncFromNativeEditor(nativeViewModel)

        XCTAssertEqual(api.updateCallCount, 0)
        let pending = try await context.writeQueue.fetchPendingWrites()
        XCTAssertEqual(canonicalPlainText, note.content)
        XCTAssertFalse(context.viewModel.isQueuedForSync)
        XCTAssertFalse(context.viewModel.isSaving)
        XCTAssertEqual(context.viewModel.content, canonicalPlainText)
        let draft = try context.draftStorage.getDraft(entityType: "note", entityId: "n1")
        XCTAssertNil(draft)
        XCTAssertEqual(pending.count, 0)
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

@MainActor
private struct NotesEditorViewModelTestContext {
    let store: NotesStore
    let notesViewModel: NotesViewModel
    let draftStorage: DraftStorage
    let writeQueue: WriteQueue
    let viewModel: NotesEditorViewModel
}

@MainActor
private func makeNotesEditorViewModelTestContext(
    api: any NotesProviding,
    networkAvailable: Bool = true
) -> NotesEditorViewModelTestContext {
    let cache = TestCacheClient()
    let store = NotesStore(api: api, cache: cache)
    let toast = ToastCenter()
    let notesViewModel = NotesViewModel(
        api: api,
        store: store,
        toastCenter: toast,
        networkStatus: TestNetworkStatus(isNetworkAvailable: networkAvailable)
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
        networkStatus: TestNetworkStatus(isNetworkAvailable: networkAvailable)
    )
    return NotesEditorViewModelTestContext(
        store: store,
        notesViewModel: notesViewModel,
        draftStorage: draftStorage,
        writeQueue: writeQueue,
        viewModel: viewModel
    )
}

@available(iOS 26.0, macOS 26.0, *)
private func characterRange(
    length: Int,
    in text: AttributedString
) -> Range<AttributedString.Index> {
    var index = text.startIndex
    for _ in 0..<length {
        index = text.index(afterCharacter: index)
    }
    return text.startIndex..<index
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

@MainActor
private func waitUntilUnsupportedNoteHydrated(_ viewModel: NotesEditorViewModel) async throws {
    await waitUntilNoteHydrated(viewModel, note: makeUnsupportedTestNote())
}

@MainActor
private func waitUntilNoteHydrated(
    _ viewModel: NotesEditorViewModel,
    note: NotePayload
) async {
    let unsupported = NotesUnsupportedContent.detect(in: note.document)
    let didHydrate = await waitUntil(
        timeoutSeconds: 5.0,
        failOnTimeout: false
    ) {
        viewModel.currentNoteId == note.id
            && viewModel.content == note.plainText
            && NotesSemanticDocumentCodec.decode(viewModel.canonicalContent) == note.document
            && viewModel.isReadOnly == (unsupported != nil)
            && viewModel.unsupportedContent?.blockTypes == unsupported?.blockTypes
    }
    guard !didHydrate else { return }

    XCTFail(
        """
        Timed out waiting for note hydration. \
        currentNoteId=\(String(describing: viewModel.currentNoteId)) \
        content=\(String(reflecting: viewModel.content)) \
        decodedCanonical=\(String(describing: NotesSemanticDocumentCodec.decode(viewModel.canonicalContent))) \
        isReadOnly=\(viewModel.isReadOnly) \
        unsupported=\(String(describing: viewModel.unsupportedContent?.blockTypes)) \
        expectedUnsupported=\(String(describing: unsupported?.blockTypes))
        """
    )
}

@MainActor
private func waitUntilNoActiveNote(_ viewModel: NotesEditorViewModel) async {
    _ = await waitUntil(timeoutSeconds: 2.0, failOnTimeout: false) {
        viewModel.currentNoteId == nil
            && viewModel.content.isEmpty
            && viewModel.canonicalContent.isEmpty
            && viewModel.presentationMode == .read
    }
}

private func waitUntil(
    timeoutSeconds: TimeInterval,
    failOnTimeout: Bool,
    condition: @escaping () -> Bool
) async -> Bool {
    let timeout = Date().addingTimeInterval(timeoutSeconds)
    while Date() < timeout {
        if condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
    }
    if failOnTimeout {
        XCTFail("Timed out waiting for condition")
    }
    return false
}

@MainActor
private func decodedCanonicalPlainText(_ content: String) -> String? {
    NotesSemanticDocumentCodec.decode(content).map(NotesSemanticDocumentProjection.plainText(from:))
}

private func makeUnsupportedTestNote(
    id: String = "n1",
    name: String = "Unsupported",
    path: String = "/unsupported.md"
) -> NotePayload {
    let document = NotesSemanticDocument(
        blocks: [
            .paragraph([.init(text: "Intro", marks: [])]),
            .init(type: .heading, content: [.init(text: "Heading", marks: [])])
        ]
    )
    return NotePayload(
        id: id,
        name: name,
        document: document,
        plainText: "Intro",
        path: path,
        modified: nil,
        created: nil
    )
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

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NotesEditorViewModelTests {
    func testSaveIfNeededPreservesNativeSelectionAcrossFormattingSaveReload() async throws {
        let savedDocument = NotesSemanticDocument(
            blocks: [
                .paragraph([
                    .init(text: "Hello ", marks: []),
                    .init(text: "world", marks: [.bold])
                ])
            ]
        )
        let savedNote = NotePayload(
            id: "n1",
            name: "Hello world",
            document: savedDocument,
            plainText: "Hello world",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        let context = await makeSelectionSaveReloadContext(savedNote: savedNote)
        let nativeViewModel = context.viewModel.makeNativeEditorViewModel()
        context.viewModel.attachNativeEditor(nativeViewModel)
        context.viewModel.enterEditMode()

        let selectionRange = selectionRangeForWorld(in: nativeViewModel.attributedContent)
        nativeViewModel.selection = AttributedTextSelection(range: selectionRange)
        let before = nsRange(from: nativeViewModel.selection, in: nativeViewModel.attributedContent)
        nativeViewModel.applyFormatting(.bold)
        let formattedSelection = nsRange(from: nativeViewModel.selection, in: nativeViewModel.attributedContent)

        await context.viewModel.saveIfNeeded()

        XCTAssertEqual(context.api.updateCallCount, 1)
        XCTAssertEqual(
            NotesSemanticDocumentProjection.plainText(from: context.api.updatedDocuments[0]),
            "Hello world"
        )
        XCTAssertFalse(nativeViewModel.hasUnsavedChanges)
        XCTAssertEqual(formattedSelection, before)
        XCTAssertEqual(
            nsRange(from: nativeViewModel.selection, in: nativeViewModel.attributedContent),
            before
        )
        XCTAssertTrue(
            noteRangeHasBoldTrait(
                nativeViewModel.attributedContent,
                range: selectionRangeForWorld(in: nativeViewModel.attributedContent)
            )
        )
    }
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func makeSelectionSaveReloadContext(
    savedNote: NotePayload
) async -> (api: NotesAPISpy, viewModel: NotesEditorViewModel) {
    let api = NotesAPISpy(updateResult: .success(savedNote))
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
        name: "Hello world",
        content: "Hello world",
        path: "/note.md",
        modified: nil,
        created: nil
    )
    store.applyEditorUpdate(note)
    await waitUntilNoteHydrated(viewModel, note: note)
    return (api: api, viewModel: viewModel)
}

@available(iOS 26.0, macOS 26.0, *)
private func selectionRangeForWorld(
    in content: AttributedString
) -> Range<AttributedString.Index> {
    let fullRange = characterRange(length: 11, in: content)
    return content.index(fullRange.lowerBound, offsetByCharacters: 6)..<fullRange.upperBound
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
    private(set) var updatedDocuments: [NotesSemanticDocument] = []
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

    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        _ = id
        updateCallCount += 1
        updatedDocuments.append(document)
        let canonicalContent = NotesSemanticDocumentCodec.encode(document) ?? ""
        updatedContents.append(canonicalContent)
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

    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        try await updateNote(
            id: id,
            content: NotesSemanticDocumentProjection.plainText(from: document)
        )
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
