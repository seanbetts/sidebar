import Foundation
import Combine
import OSLog

// MARK: - NotesEditorViewModel

@MainActor
/// Manages note display state.
public final class NotesEditorViewModel: ObservableObject {
    @Published public private(set) var content: String = ""
    @Published public private(set) var canonicalContent: String = ""
    @Published public private(set) var currentNoteId: String?
    @Published public private(set) var isDirty: Bool = false
    @Published public private(set) var isSaving: Bool = false
    @Published public private(set) var lastSavedAt: Date?
    @Published public private(set) var saveErrorMessage: String?
    @Published public private(set) var isReadOnly: Bool = true
    @Published public private(set) var isQueuedForSync: Bool = false

    private let notesViewModel: NotesViewModel
    private let draftStorage: DraftStorage
    private let writeQueue: WriteQueue
    private let networkStatus: any NetworkStatusProviding
    private let logger = Logger(subsystem: "sideBar", category: "AttributedEditorMigration")
    @available(iOS 26.0, macOS 26.0, *)
    private weak var nativeEditorViewModel: NativeNoteEditorViewModel?
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
            currentNoteId = nil
            content = ""
            canonicalContent = ""
            isDirty = false
            isSaving = false
            lastSavedAt = nil
            saveErrorMessage = nil
            isReadOnly = true
            isQueuedForSync = false
            syncRequestedWhileSaving = false
            return
        }
        let isSameNote = previousNoteId == note.id
        if isSameNote, isSaving {
            // Avoid clobbering pending local edits while an in-flight save publishes
            // the same note back through NotesStore.
            return
        }
        let normalized = NotesRichTextCodec.normalizeWriteInput(
            content: note.content,
            plainText: note.plainText.isEmpty ? nil : note.plainText
        )
        currentNoteId = note.id
        if isSameNote,
           normalized.plainText == content,
           normalized.content == canonicalContent {
            isReadOnly = false
            if !isSaving {
                saveErrorMessage = nil
                isQueuedForSync = false
            }
            return
        }
        content = normalized.plainText
        canonicalContent = normalized.content
        syncNativeEditorContent(
            canonicalContent: normalized.content,
            plainText: normalized.plainText
        )
        isDirty = false
        isSaving = false
        lastSavedAt = nil
        saveErrorMessage = nil
        isReadOnly = false
        isQueuedForSync = false
        if !isSameNote {
            syncRequestedWhileSaving = false
        }
        Task { [weak self] in
            await self?.applyDraftIfAvailable(for: note)
        }
    }

    private func applyDraftIfAvailable(for note: NotePayload) async {
        do {
            guard let draft = try draftStorage.getDraft(entityType: "note", entityId: note.id) else { return }
            guard draft.syncedAt == nil else { return }
            let normalized = NotesRichTextCodec.normalizeWriteInput(
                content: note.content,
                plainText: note.plainText.isEmpty ? nil : note.plainText
            )
            if draft.content == normalized.plainText {
                try? draftStorage.markSynced(entityType: "note", entityId: note.id)
                isQueuedForSync = false
                return
            }
            content = draft.content
            let draftBaseline = NotesRichTextCodec.normalizeWriteInput(content: draft.content)
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
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(canonicalContent: canonicalContent, plainText: content)
        alignPersistenceBaseline(with: viewModel)
        return viewModel
    }

    @available(iOS 26.0, macOS 26.0, *)
    public func attachNativeEditor(_ nativeViewModel: NativeNoteEditorViewModel) {
        nativeEditorViewModel = nativeViewModel
    }

    @available(iOS 26.0, macOS 26.0, *)
    public func detachNativeEditor(_ nativeViewModel: NativeNoteEditorViewModel) {
        if nativeEditorViewModel === nativeViewModel {
            nativeEditorViewModel = nil
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    public func syncFromNativeEditor(_ nativeViewModel: NativeNoteEditorViewModel) async {
        guard let noteId = currentNoteId else { return }
        if isSaving {
            syncRequestedWhileSaving = true
            return
        }

        let snapshot = nativeViewModel.currentPersistenceSnapshot()
        guard snapshot.canonicalContent != canonicalContent || snapshot.plainText != content else {
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

        let payload = NoteUpdatePayload(
            content: snapshot.canonicalContent,
            plainText: snapshot.plainText
        )
        let serverSnapshot = makeServerSnapshot(noteId: noteId)

        if !networkStatus.isNetworkAvailable {
            await enqueueNoteUpdate(
                noteId: noteId,
                payload: payload,
                snapshot: serverSnapshot
            )
            nativeViewModel.markSaved(
                plainText: payload.plainText ?? "",
                canonicalContent: payload.content
            )
            content = payload.plainText ?? ""
            canonicalContent = payload.content
            isSaving = false
            isDirty = false
            isQueuedForSync = true
            await syncFromNativeEditorIfRequested(nativeViewModel)
            return
        }

        let saved = await notesViewModel.updateNoteContent(id: noteId, content: payload.content)
        isSaving = false
        if saved {
            try? draftStorage.markSynced(entityType: "note", entityId: noteId)
            nativeViewModel.markSaved(
                plainText: payload.plainText ?? "",
                canonicalContent: payload.content
            )
            content = payload.plainText ?? ""
            canonicalContent = payload.content
            isDirty = false
            lastSavedAt = Date()
            isQueuedForSync = false
        } else {
            saveErrorMessage = "Failed to save note"
            await enqueueNoteUpdate(
                noteId: noteId,
                payload: payload,
                snapshot: serverSnapshot
            )
            isQueuedForSync = true
        }
        await syncFromNativeEditorIfRequested(nativeViewModel)
    }

    @available(iOS 26.0, macOS 26.0, *)
    public func canApplyFormattingCommands() -> Bool {
        currentNoteId != nil && nativeEditorViewModel != nil && !isReadOnly
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
        guard let nativeEditorViewModel, canApplyFormattingCommands() else { return }
        nativeEditorViewModel.applyFormatting(formatting)
        isDirty = nativeEditorViewModel.hasUnsavedChanges || isDirty
    }

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
        if #available(iOS 26.0, macOS 26.0, *) {
            if let nativeEditorViewModel {
                let plainText = nativeEditorViewModel.currentPersistenceSnapshot().plainText
                return plainText.isEmpty ? fallback : plainText
            }
            return content.isEmpty ? fallback : content
        }
        return content.isEmpty ? fallback : content
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

    private func syncNativeEditorContent(canonicalContent: String, plainText: String) {
        if #available(iOS 26.0, macOS 26.0, *) {
            guard let nativeEditorViewModel else { return }
            guard nativeEditorViewModel.currentCanonicalContent() != canonicalContent else { return }
            nativeEditorViewModel.loadDocument(canonicalContent: canonicalContent, plainText: plainText)
            alignPersistenceBaseline(with: nativeEditorViewModel)
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func alignPersistenceBaseline(with nativeViewModel: NativeNoteEditorViewModel) {
        let snapshot = nativeViewModel.currentPersistenceSnapshot()
        content = snapshot.plainText
        canonicalContent = snapshot.canonicalContent
    }

    private func enqueueNoteUpdate(
        noteId: String,
        payload: NoteUpdatePayload,
        snapshot: ServerSnapshot?
    ) async {
        do {
            try await writeQueue.enqueue(
                operation: .update,
                entityType: .note,
                entityId: noteId,
                payload: payload,
                serverSnapshot: snapshot
            )
        } catch WriteQueueError.queueFull {
            saveErrorMessage = "Sync queue full. Review pending changes."
        } catch {
            saveErrorMessage = "Failed to queue changes"
        }
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

private struct NoteUpdatePayload: Codable {
    let content: String
    let plainText: String?

    enum CodingKeys: String, CodingKey {
        case content
        case plainText = "plain_text"
    }
}
