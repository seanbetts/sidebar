import Foundation

extension NotesEditorViewModel {
    func scheduleNoteUpdate(_ note: NotePayload?) {
        pendingNoteUpdateTask?.cancel()
        pendingNoteUpdateTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard Task.isCancelled == false else { return }
            self?.handleNoteUpdate(note)
        }
    }
}
