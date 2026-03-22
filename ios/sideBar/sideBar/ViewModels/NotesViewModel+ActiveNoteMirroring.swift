import Foundation

extension NotesViewModel {
    func scheduleActiveNoteMirror(_ note: NotePayload?) {
        activeNoteMirrorTask?.cancel()
        activeNoteMirrorTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard Task.isCancelled == false else { return }
            self?.activeNote = note
        }
    }
}
