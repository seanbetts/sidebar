// swiftlint:disable file_length
import Foundation
import Combine
import OSLog

// MARK: - NotesEditorViewModel

@MainActor
/// Manages note display state.
public final class NotesEditorViewModel: ObservableObject {
    /// Presentation mode for an open note.
    public enum PresentationMode: Equatable {
        case read
        case edit
    }

    /// One-shot selection target consumed when the native editor enters edit mode.
    public enum PendingEditSelectionTarget: Equatable {
        case start
        /// UTF-16 text-system offset produced by the read surface hit-testing APIs.
        case characterOffset(Int)
    }

    @Published public private(set) var content: String = ""
    @Published public private(set) var canonicalContent: String = ""
    @Published public private(set) var currentNoteId: String?
    @Published public private(set) var presentationMode: PresentationMode = .read
    @Published public private(set) var isDirty: Bool = false
    @Published public private(set) var isSaving: Bool = false
    @Published public private(set) var lastSavedAt: Date?
    @Published public private(set) var saveErrorMessage: String?
    @Published public private(set) var isReadOnly: Bool = true
    @Published public private(set) var isQueuedForSync: Bool = false
    @Published private(set) var unsupportedContent: NotesUnsupportedContent?

    private let notesViewModel: NotesViewModel
    private let draftStorage: DraftStorage
    private let writeQueue: WriteQueue
    private let networkStatus: any NetworkStatusProviding
    private let logger = Logger(subsystem: "sideBar", category: "AttributedEditorMigration")
    @available(iOS 26.0, macOS 26.0, *)
    private weak var nativeEditorViewModel: NativeNoteEditorViewModel?
    @available(iOS 26.0, macOS 26.0, *)
    private var sharedNativeEditorViewModel: NativeNoteEditorViewModel?
    @available(iOS 26.0, macOS 26.0, *)
    private var nativeEditorObservation: AnyCancellable?
    private var pendingEditSelectionTarget: PendingEditSelectionTarget?
    private var syncRequestedWhileSaving = false
    private var cancellables = Set<AnyCancellable>()

    init(
        notesViewModel: NotesViewModel,
        draftStorage: DraftStorage,
        writeQueue: WriteQueue,
        networkStatus: any NetworkStatusProviding
    ) {
        self.notesViewModel = notesViewModel
        self.draftStorage = draftStorage
        self.writeQueue = writeQueue
        self.networkStatus = networkStatus

        notesViewModel.$activeNote
            .sink { [weak self] note in
                self?.handleNoteUpdate(note)
            }
            .store(in: &cancellables)
    }

    private func handleNoteUpdate(_ note: NotePayload?) {
        let previousNoteId = currentNoteId
        guard let note else {
            resetStateForNoActiveNote()
            return
        }
        let isSameNote = previousNoteId == note.id
        if isSameNote, isSaving {
            // Avoid clobbering pending local edits while an in-flight save publishes
            // the same note back through NotesStore.
            return
        }
        let normalized = normalizedEditorSnapshot(for: note)
        let detectedUnsupportedContent = NotesUnsupportedContent.detect(in: note.document)
        if let detectedUnsupportedContent {
            detectedUnsupportedContent.reportDetected(
                context: "NotesEditorViewModel.handleNoteUpdate",
                logger: logger
            )
        }
        currentNoteId = note.id
        unsupportedContent = detectedUnsupportedContent
        if isSameNote,
           normalized.plainText == content,
           normalized.content == canonicalContent {
            isReadOnly = detectedUnsupportedContent != nil
            if detectedUnsupportedContent != nil {
                presentationMode = .read
                pendingEditSelectionTarget = nil
            }
            if !isSaving {
                saveErrorMessage = nil
            }
            return
        }
        content = normalized.plainText
        canonicalContent = normalized.content
        if detectedUnsupportedContent == nil {
            syncNativeEditorContent(
                canonicalContent: normalized.content,
                plainText: normalized.plainText
            )
        }
        isDirty = false
        isSaving = false
        lastSavedAt = nil
        saveErrorMessage = nil
        isReadOnly = detectedUnsupportedContent != nil
        isQueuedForSync = false
        if !isSameNote || detectedUnsupportedContent != nil {
            presentationMode = .read
            pendingEditSelectionTarget = nil
        }
        if !isSameNote {
            syncRequestedWhileSaving = false
        }
        guard detectedUnsupportedContent == nil else { return }
        Task { [weak self] in
            await self?.applyDraftIfAvailable(for: note)
        }
    }

    private func applyDraftIfAvailable(for note: NotePayload) async {
        do {
            guard let draft = try draftStorage.getDraft(entityType: "note", entityId: note.id) else { return }
            guard draft.syncedAt == nil else { return }
            let normalized = normalizedEditorSnapshot(for: note)
            if draft.content == normalized.plainText {
                try? draftStorage.markSynced(entityType: "note", entityId: note.id)
                isQueuedForSync = false
                return
            }
            content = draft.content
            let draftDocument = NotesSemanticDocumentProjection.document(fromPlainText: draft.content)
            let draftBaseline = (
                content: NotesSemanticDocumentCodec.encode(draftDocument) ?? "",
                plainText: draft.content
            )
            canonicalContent = draftBaseline.content
            syncNativeEditorContent(
                canonicalContent: draftBaseline.content,
                plainText: draft.content
            )
            isDirty = true
            isQueuedForSync = true
        } catch {
            saveErrorMessage = "Failed to load draft"
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    public func makeNativeEditorViewModel() -> NativeNoteEditorViewModel {
        let viewModel = buildNativeEditorViewModel()
        alignPersistenceBaseline(with: viewModel)
        return viewModel
    }

    @available(iOS 26.0, macOS 26.0, *)
    public func sharedNativeEditor() -> NativeNoteEditorViewModel {
        if let sharedNativeEditorViewModel {
            return sharedNativeEditorViewModel
        }

        let viewModel = buildNativeEditorViewModel()
        sharedNativeEditorViewModel = viewModel
        return viewModel
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func buildNativeEditorViewModel() -> NativeNoteEditorViewModel {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(canonicalContent: canonicalContent, plainText: content)
        return viewModel
    }

    @available(iOS 26.0, macOS 26.0, *)
    public func syncFromNativeEditor(_ nativeViewModel: NativeNoteEditorViewModel) async {
        guard let noteId = currentNoteId else { return }
        if isSaving {
            syncRequestedWhileSaving = true
            return
        }

        let snapshot = nativeViewModel.currentPersistenceSnapshot()
        let hasSnapshotDelta =
            snapshot.canonicalContent != canonicalContent || snapshot.plainText != content
        guard hasSnapshotDelta || nativeViewModel.hasUnsavedChanges else {
            syncRequestedWhileSaving = false
            return
        }

        isSaving = true
        saveErrorMessage = nil
        do {
            try draftStorage.saveDraft(entityType: "note", entityId: noteId, content: snapshot.plainText)
        } catch {
            saveErrorMessage = "Failed to save draft"
        }

        let payload = NoteUpdateRequest(
            document: snapshot.document,
            plainText: snapshot.plainText
        )
        let serverSnapshot = makeServerSnapshot(noteId: noteId)

        if !networkStatus.isNetworkAvailable {
            let queued = await enqueueNoteUpdate(
                noteId: noteId,
                payload: payload,
                snapshot: serverSnapshot
            )
            if queued {
                notesViewModel.applyLocalNoteSnapshot(id: noteId, document: snapshot.document)
            }
            nativeViewModel.markSaved(
                plainText: snapshot.plainText,
                canonicalContent: snapshot.canonicalContent
            )
            content = snapshot.plainText
            canonicalContent = snapshot.canonicalContent
            isSaving = false
            isDirty = false
            isQueuedForSync = queued
            await syncFromNativeEditorIfRequested(nativeViewModel)
            return
        }

        let saved = await notesViewModel.updateNoteContent(id: noteId, document: snapshot.document)
        isSaving = false
        if saved {
            try? draftStorage.markSynced(entityType: "note", entityId: noteId)
            nativeViewModel.markSaved(
                plainText: snapshot.plainText,
                canonicalContent: snapshot.canonicalContent
            )
            content = snapshot.plainText
            canonicalContent = snapshot.canonicalContent
            isDirty = false
            lastSavedAt = Date()
            isQueuedForSync = false
        } else {
            saveErrorMessage = "Failed to save note"
            let queued = await enqueueNoteUpdate(
                noteId: noteId,
                payload: payload,
                snapshot: serverSnapshot
            )
            if queued {
                notesViewModel.applyLocalNoteSnapshot(id: noteId, document: snapshot.document)
            }
            isQueuedForSync = queued
        }
        await syncFromNativeEditorIfRequested(nativeViewModel)
    }

    @available(iOS 26.0, macOS 26.0, *)
    public func canApplyFormattingCommands() -> Bool {
        currentNoteId != nil && nativeEditorViewModel != nil && !isReadOnly && isEditingNote
    }

    @available(iOS 26.0, macOS 26.0, *)
    public func isFormattingActive(_ formatting: NoteFormatting) -> Bool {
        guard let nativeEditorViewModel, canApplyFormattingCommands() else { return false }
        return nativeEditorViewModel.isFormattingActive(formatting)
    }

    @available(iOS 26.0, macOS 26.0, *)
    public func setFormatting(_ formatting: NoteFormatting, enabled: Bool) {
        guard let nativeEditorViewModel, canApplyFormattingCommands() else { return }
        let previousContent = nativeEditorViewModel.attributedContent
        let previousSelection = nativeEditorViewModel.selection
        nativeEditorViewModel.setFormatting(formatting, enabled: enabled)
        guard nativeEditorViewModel.attributedContent != previousContent
            || nativeEditorViewModel.selection != previousSelection else {
            return
        }
        if !nativeEditorViewModel.hasUnsavedChanges {
            nativeEditorViewModel.hasUnsavedChanges = true
        }
        nativeEditorViewModel.scheduleAutosave()
        nativeEditorViewModel.lastSelectionLineSpan = nativeEditorViewModel.selectionLineSpan(
            in: nativeEditorViewModel.attributedContent
        )
        isDirty = true
    }

    @available(iOS 26.0, macOS 26.0, *)
    public func toggleFormatting(_ formatting: NoteFormatting) {
        guard canApplyFormattingCommands() else { return }
        setFormatting(formatting, enabled: !isFormattingActive(formatting))
    }

#if os(iOS)
    @available(iOS 26.0, *)
    var noteFormattingBarConfiguration: NoteFormattingBarConfiguration {
        .init(
            isBoldActive: isFormattingActive(.bold),
            isItalicActive: isFormattingActive(.italic),
            isUnderlineActive: isFormattingActive(.underline),
            isEnabled: canApplyFormattingCommands(),
            onBoldTap: { [weak self] in self?.toggleFormatting(.bold) },
            onItalicTap: { [weak self] in self?.toggleFormatting(.italic) },
            onUnderlineTap: { [weak self] in self?.toggleFormatting(.underline) }
        )
    }
#endif

    public func saveIfNeeded() async {
        guard !isSaving else { return }
        if #available(iOS 26.0, macOS 26.0, *) {
            guard let nativeViewModel = nativeEditorViewModel else {
                guard isDirty else { return }
                return
            }
            let snapshot = nativeViewModel.currentPersistenceSnapshot()
            let hasNativeDelta = nativeViewModel.hasUnsavedChanges ||
                snapshot.canonicalContent != canonicalContent ||
                snapshot.plainText != content
            guard hasNativeDelta || isDirty else { return }
            await syncFromNativeEditor(nativeViewModel)
            return
        }
        guard isDirty else { return }
    }

    public func currentPlainTextSnapshot(fallback: String = "") -> String {
        if #available(iOS 26.0, macOS 26.0, *), let nativeEditorViewModel {
            let plainText = nativeEditorViewModel.currentPersistenceSnapshot().plainText
            return plainText.isEmpty ? fallback : plainText
        }
        return content.isEmpty ? fallback : content
    }

    public func currentSemanticDocumentSnapshot() -> NotesSemanticDocument {
        if #available(iOS 26.0, macOS 26.0, *) {
            if let nativeEditorViewModel {
                return nativeEditorViewModel.currentPersistenceSnapshot().document
            }
        }
        if let document = NotesSemanticDocumentCodec.decode(canonicalContent) { return document }
        return NotesSemanticDocumentProjection.document(fromPlainText: content)
    }

    public var isEditingNote: Bool { presentationMode == .edit }
    public func enterEditMode() { enterEditMode(at: .start) }

    public func enterEditMode(at target: PendingEditSelectionTarget) {
        guard currentNoteId != nil, unsupportedContent == nil else { return }
        pendingEditSelectionTarget = target
        presentationMode = .edit
    }

    public func consumePendingEditSelectionTarget() -> PendingEditSelectionTarget? {
        defer { pendingEditSelectionTarget = nil }
        return pendingEditSelectionTarget
    }

    public func exitEditModeToRead() { pendingEditSelectionTarget = nil; presentationMode = .read }

    private func syncNativeEditorContent(canonicalContent: String, plainText: String) {
        if #available(iOS 26.0, macOS 26.0, *) {
            guard let nativeEditorViewModel,
                  nativeEditorViewModel.currentCanonicalContent() != canonicalContent else { return }
            let selectionSnapshot = presentationMode == .edit && pendingEditSelectionTarget == nil ?
                nativeEditorViewModel.selectionSnapshot(in: nativeEditorViewModel.attributedContent) : nil
            nativeEditorViewModel.loadDocument(canonicalContent: canonicalContent, plainText: plainText)
            if let target = consumePendingEditSelectionTarget() {
                nativeEditorViewModel.applySelectionTarget(target)
            } else if let selectionSnapshot {
                let content = nativeEditorViewModel.attributedContent
                nativeEditorViewModel.selection = nativeEditorViewModel.selection(from: selectionSnapshot, in: content)
                nativeEditorViewModel.lastSelectionLineSpan = nativeEditorViewModel.selectionLineSpan(in: content)
            }
            alignPersistenceBaseline(with: nativeEditorViewModel)
        }
    }

    private func enqueueNoteUpdate(
        noteId: String,
        payload: NoteUpdateRequest,
        snapshot: ServerSnapshot?
    ) async -> Bool {
        do {
            try await writeQueue.enqueue(
                operation: .update,
                entityType: .note,
                entityId: noteId,
                payload: payload,
                serverSnapshot: snapshot
            )
            return true
        } catch WriteQueueError.queueFull {
            saveErrorMessage = "Sync queue full. Review pending changes."
        } catch {
            saveErrorMessage = "Failed to queue changes"
        }
        return false
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func syncFromNativeEditorIfRequested(_ nativeViewModel: NativeNoteEditorViewModel) async {
        guard syncRequestedWhileSaving else { return }
        syncRequestedWhileSaving = false
        await syncFromNativeEditor(nativeViewModel)
    }

    private func makeServerSnapshot(noteId: String) -> ServerSnapshot? {
        guard let note = notesViewModel.activeNote, note.id == noteId else {
            return nil
        }
        let node = notesViewModel.noteNode(id: note.path)
        let snapshot = NoteSnapshot(
            modified: note.modified,
            name: note.name,
            path: note.path,
            pinned: node?.pinned,
            pinnedOrder: node?.pinnedOrder,
            archived: node?.archived
        )
        return ServerSnapshot(
            entityType: .note,
            entityId: noteId,
            capturedAt: Date(),
            payload: .note(snapshot)
        )
    }

}

extension NotesEditorViewModel {
    private func resetStateForNoActiveNote() {
        if #available(iOS 26.0, macOS 26.0, *) {
            resetNativeEditorObservation()
            sharedNativeEditorViewModel = nil
        }
        currentNoteId = nil
        presentationMode = .read
        pendingEditSelectionTarget = nil
        content = ""
        canonicalContent = ""
        isDirty = false
        isSaving = false
        lastSavedAt = nil
        saveErrorMessage = nil
        isReadOnly = true
        isQueuedForSync = false
        unsupportedContent = nil
        syncRequestedWhileSaving = false
    }

    @available(iOS 26.0, macOS 26.0, *)
    public func attachNativeEditor(_ nativeViewModel: NativeNoteEditorViewModel) {
        nativeEditorViewModel = nativeViewModel
        sharedNativeEditorViewModel = nativeViewModel
        observeNativeEditor(nativeViewModel)
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    public func detachNativeEditor(_ nativeViewModel: NativeNoteEditorViewModel) {
        if nativeEditorViewModel === nativeViewModel {
            resetNativeEditorObservation()
            nativeEditorViewModel = nil
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func observeNativeEditor(_ nativeViewModel: NativeNoteEditorViewModel) {
        resetNativeEditorObservation()
        nativeEditorObservation = nativeViewModel.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func resetNativeEditorObservation() {
        nativeEditorObservation?.cancel()
        nativeEditorObservation = nil
    }

    public func setDirty(_ dirty: Bool) {
        guard isDirty != dirty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isDirty != dirty else { return }
            self.isDirty = dirty
        }
    }

    public func setReadOnly(_ readOnly: Bool) {
        guard isReadOnly != readOnly else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isReadOnly != readOnly else { return }
            self.isReadOnly = readOnly
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    fileprivate func alignPersistenceBaseline(with nativeViewModel: NativeNoteEditorViewModel) {
        let snapshot = nativeViewModel.currentPersistenceSnapshot()
        content = snapshot.plainText
        canonicalContent = snapshot.canonicalContent
    }

    fileprivate func normalizedEditorSnapshot(for note: NotePayload) -> (content: String, plainText: String) {
        (
            content: NotesSemanticDocumentCodec.encode(note.document) ?? "",
            plainText: note.plainText
        )
    }
}
// swiftlint:enable file_length
