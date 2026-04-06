import Foundation

extension NotesEditorViewModel {
    func scheduleNoteUpdate(_ note: NotePayload?) {
        pendingNoteUpdateTask?.cancel()
        guard let note else {
            handleNoteUpdate(nil)
            return
        }
        pendingNoteUpdateTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard Task.isCancelled == false else { return }
            self?.handleNoteUpdate(note)
        }
    }
}
