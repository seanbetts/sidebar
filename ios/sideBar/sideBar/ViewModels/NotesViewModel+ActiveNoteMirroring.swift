import Foundation

extension NotesViewModel {
    func scheduleTreeMirror(_ tree: FileTree?) {
        treeMirrorTask?.cancel()
        treeMirrorTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard Task.isCancelled == false else { return }
            self?.setMirroredTree(tree)
        }
    }

    func scheduleArchivedTreeMirror(_ tree: FileTree?) {
        archivedTreeMirrorTask?.cancel()
        archivedTreeMirrorTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard Task.isCancelled == false else { return }
            self?.setMirroredArchivedTree(tree)
        }
    }

    func scheduleActiveNoteMirror(_ note: NotePayload?) {
        activeNoteMirrorTask?.cancel()
        activeNoteMirrorTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard Task.isCancelled == false else { return }
            self?.setMirroredActiveNote(note)
        }
    }
}
