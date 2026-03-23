import Foundation

@MainActor
extension NotesEditorViewModel {
    public func saveDocumentSnapshotIfNeeded(_ document: NotesSemanticDocument) async {
        guard !isSaving, let noteId = currentNoteId else { return }

        let plainText = NotesSemanticDocumentProjection.plainText(from: document)
        let encodedContent = NotesSemanticDocumentCodec.encode(document) ?? ""
        let hasSnapshotDelta = encodedContent != canonicalContent || plainText != content
        guard hasSnapshotDelta || isDirty else { return }

        isSaving = true
        saveErrorMessage = nil
        do {
            try draftStorage.saveDraft(
                entityType: "note",
                entityId: noteId,
                content: plainText,
                canonicalContent: encodedContent
            )
        } catch {
            saveErrorMessage = "Failed to save draft"
        }

        let payload = NoteUpdateRequest(document: document, plainText: plainText)
        let serverSnapshot = makeServerSnapshot(noteId: noteId)

        if !networkStatus.isNetworkAvailable {
            let queued = await enqueueNoteUpdate(
                noteId: noteId,
                payload: payload,
                snapshot: serverSnapshot
            )
            if queued {
                notesViewModel.applyLocalNoteSnapshot(id: noteId, document: document)
            }
            content = plainText
            canonicalContent = encodedContent
            isSaving = false
            isDirty = false
            isQueuedForSync = queued
            return
        }

        let savedNote = await notesViewModel.updateNoteContent(id: noteId, document: document)
        isSaving = false
        if let savedNote {
            try? draftStorage.markSynced(entityType: "note", entityId: noteId)
            content = plainText
            canonicalContent = encodedContent
            isDirty = false
            lastSavedAt = Date()
            isQueuedForSync = false
            notesViewModel.applySavedNoteAcknowledgement(
                serverNote: savedNote,
                document: document
            )
        } else {
            saveErrorMessage = "Failed to save note"
            let queued = await enqueueNoteUpdate(
                noteId: noteId,
                payload: payload,
                snapshot: serverSnapshot
            )
            if queued {
                notesViewModel.applyLocalNoteSnapshot(id: noteId, document: document)
            }
            isQueuedForSync = queued
        }
    }

    public func scheduleReadModeSave(of document: NotesSemanticDocument) {
        pendingReadModeSaveTask?.cancel()
        pendingReadModeSaveTaskID &+= 1
        let taskID = pendingReadModeSaveTaskID
        pendingReadModeSaveTask = Task { @MainActor [self] in
            await saveDocumentSnapshotIfNeeded(document)
            guard pendingReadModeSaveTaskID == taskID else { return }
            pendingReadModeSaveTask = nil
        }
    }

    public func applyReadModeSnapshot(_ document: NotesSemanticDocument) {
        content = NotesSemanticDocumentProjection.plainText(from: document)
        canonicalContent = NotesSemanticDocumentCodec.encode(document) ?? ""
    }
}
