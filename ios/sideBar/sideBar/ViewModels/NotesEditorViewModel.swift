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
    @Published private(set) var conflict: NoteSyncConflict?

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
            isQueuedForSync = false
            conflict = nil
            syncRequestedWhileSaving = false
            return
        }
        let isSameNote = previousNoteId == note.id
        if isSameNote, isSaving {
            // Avoid clobbering pending local edits while an in-flight save publishes
            // the same note back through NotesStore.
            return
        }
        currentNoteId = note.id
        content = note.plainText
        canonicalContent = note.content
        syncNativeEditorContent(canonicalContent: note.content, plainText: note.plainText)
        isDirty = false
        isSaving = false
        lastSavedAt = nil
        saveErrorMessage = nil
        isQueuedForSync = false
        conflict = nil
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
            let serverDate = note.modified.map { Date(timeIntervalSince1970: $0) }
            if shouldPresentNoteConflict(
                localContent: draft.content,
                localDate: draft.savedAt,
                serverContent: note.plainText,
                serverDate: serverDate
            ) {
                conflict = NoteSyncConflict(
                    id: UUID(),
                    noteId: note.id,
                    noteName: note.name,
                    notePath: note.path,
                    localContent: draft.content,
                    serverContent: note.plainText,
                    localDate: draft.savedAt,
                    serverDate: serverDate ?? Date()
                )
                content = note.plainText
                isDirty = false
                return
            }
            if draft.content == note.plainText {
                try? draftStorage.markSynced(entityType: "note", entityId: note.id)
                isQueuedForSync = false
                return
            }
            content = draft.content
            let normalized = NotesRichTextCodec.normalizeWriteInput(content: draft.content)
            canonicalContent = normalized.content
            syncNativeEditorContent(canonicalContent: normalized.content, plainText: draft.content)
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

        let plainText = nativeViewModel.currentPlainText()
        let nextCanonicalContent = nativeViewModel.currentCanonicalContent()
        guard nextCanonicalContent != canonicalContent else {
            syncRequestedWhileSaving = false
            return
        }

        isSaving = true
        saveErrorMessage = nil
        do {
            try draftStorage.saveDraft(entityType: "note", entityId: noteId, content: plainText)
        } catch {
            saveErrorMessage = "Failed to save draft"
        }

        let normalizedUpdate = normalizedNoteUpdate(
            canonicalContent: nextCanonicalContent,
            plainText: plainText
        )
        let snapshot = makeServerSnapshot(noteId: noteId)

        if !networkStatus.isNetworkAvailable {
            await enqueueNoteUpdate(
                noteId: noteId,
                payload: normalizedUpdate.payload,
                snapshot: snapshot
            )
            nativeViewModel.markSaved(
                plainText: normalizedUpdate.normalized.plainText,
                canonicalContent: normalizedUpdate.normalized.content
            )
            content = normalizedUpdate.normalized.plainText
            canonicalContent = normalizedUpdate.normalized.content
            isSaving = false
            isDirty = false
            isQueuedForSync = true
            await syncFromNativeEditorIfRequested(nativeViewModel)
            return
        }

        let saved = await notesViewModel.updateNoteContent(id: noteId, content: nextCanonicalContent)
        isSaving = false
        if saved {
            try? draftStorage.markSynced(entityType: "note", entityId: noteId)
            nativeViewModel.markSaved(
                plainText: plainText,
                canonicalContent: nextCanonicalContent
            )
            content = plainText
            canonicalContent = nextCanonicalContent
            isDirty = false
            lastSavedAt = Date()
            isQueuedForSync = false
        } else {
            saveErrorMessage = "Failed to save note"
            await enqueueNoteUpdate(
                noteId: noteId,
                payload: normalizedUpdate.payload,
                snapshot: snapshot
            )
            isQueuedForSync = true
        }
        await syncFromNativeEditorIfRequested(nativeViewModel)
    }

    public func saveIfNeeded() async {
        guard isDirty, !isSaving else { return }
        if #available(iOS 26.0, macOS 26.0, *) {
            guard let nativeViewModel = nativeEditorViewModel else { return }
            await syncFromNativeEditor(nativeViewModel)
        }
    }

    public func currentPlainTextSnapshot(fallback: String = "") -> String {
        if #available(iOS 26.0, macOS 26.0, *) {
            if let nativeEditorViewModel {
                let plainText = nativeEditorViewModel.currentPlainText()
                return plainText.isEmpty ? fallback : plainText
            }
            let source = content.isEmpty ? fallback : content
            guard !source.isEmpty else { return "" }
            return canonicalPlainTextSnapshot(from: source)
        }
        return content.isEmpty ? fallback : content
    }

    public func resolveConflictKeepLocal() async {
        guard let conflict else { return }
        let canonicalLocalContent = canonicalPlainTextForPersistence(conflict.localContent)
        content = canonicalLocalContent
        let normalized = NotesRichTextCodec.normalizeWriteInput(content: canonicalLocalContent)
        canonicalContent = normalized.content
        syncNativeEditorContent(canonicalContent: normalized.content, plainText: canonicalLocalContent)
        isDirty = true
        isQueuedForSync = true
        try? draftStorage.saveDraft(
            entityType: "note",
            entityId: conflict.noteId,
            content: canonicalLocalContent
        )
        self.conflict = nil
    }

    public func resolveConflictKeepServer() async {
        guard let conflict else { return }
        content = conflict.serverContent
        let normalized = NotesRichTextCodec.normalizeWriteInput(content: conflict.serverContent)
        canonicalContent = normalized.content
        syncNativeEditorContent(canonicalContent: normalized.content, plainText: conflict.serverContent)
        isDirty = false
        try? draftStorage.deleteDraft(entityType: "note", entityId: conflict.noteId)
        isQueuedForSync = false
        self.conflict = nil
    }

    public func resolveConflictKeepBoth() async {
        guard let conflict else { return }
        let folder = folderPath(from: conflict.notePath)
        let copyTitle = copyTitle(from: conflict.noteName)
        let localContent = canonicalPlainTextForPersistence(conflict.localContent)
        content = conflict.serverContent
        let normalized = NotesRichTextCodec.normalizeWriteInput(content: conflict.serverContent)
        canonicalContent = normalized.content
        syncNativeEditorContent(canonicalContent: normalized.content, plainText: conflict.serverContent)
        isDirty = false
        try? draftStorage.deleteDraft(entityType: "note", entityId: conflict.noteId)
        isQueuedForSync = false
        self.conflict = nil

        guard let created = await notesViewModel.createNote(title: copyTitle, folder: folder) else {
            saveErrorMessage = "Failed to create copy"
            return
        }
        _ = await notesViewModel.updateNoteContent(id: created.id, content: localContent)
        await notesViewModel.selectNote(id: conflict.notePath)
    }

    public func setDirty(_ dirty: Bool) {
        if isDirty != dirty {
            isDirty = dirty
        }
    }

    public func setReadOnly(_ readOnly: Bool) {
        if isReadOnly != readOnly {
            isReadOnly = readOnly
        }
    }

    private func syncNativeEditorContent(canonicalContent: String, plainText: String) {
        if #available(iOS 26.0, macOS 26.0, *) {
            guard let nativeEditorViewModel else { return }
            guard nativeEditorViewModel.currentCanonicalContent() != canonicalContent else { return }
            nativeEditorViewModel.loadDocument(canonicalContent: canonicalContent, plainText: plainText)
        }
    }

    private func normalizedNoteUpdate(
        canonicalContent: String,
        plainText: String
    ) -> (normalized: (content: String, plainText: String), payload: NoteUpdatePayload) {
        let normalized = NotesRichTextCodec.normalizeWriteInput(
            content: canonicalContent,
            plainText: plainText
        )
        return (
            normalized,
            NoteUpdatePayload(content: normalized.content, plainText: normalized.plainText)
        )
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

    private func canonicalPlainTextForPersistence(_ plainText: String) -> String {
        if #available(iOS 26.0, macOS 26.0, *) {
            return canonicalPlainTextSnapshot(from: plainText)
        }
        return plainText
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func canonicalPlainTextSnapshot(from plainText: String) -> String {
        let nativeViewModel = NativeNoteEditorViewModel()
        nativeViewModel.loadText(plainText)
        return nativeViewModel.currentPlainText()
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

private func folderPath(from notePath: String) -> String? {
    let trimmed = notePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let parts = trimmed.split(separator: "/")
    guard parts.count > 1 else { return nil }
    return parts.dropLast().joined(separator: "/")
}

private func copyTitle(from noteName: String) -> String {
    return "\(noteName) (Offline Copy)"
}
