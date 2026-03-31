import Foundation
import sideBarShared

extension NotesViewModel {
    public func updateNoteContent(id: String, document: NotesSemanticDocument) async -> NotePayload? {
        do {
            return try await api.updateNote(id: id, document: document)
        } catch {
            if let urlError = error as? URLError,
               urlError.code == .notConnectedToInternet || urlError.code == .timedOut {
                return nil
            }
            toastCenter.show(message: "Failed to update note")
            return nil
        }
    }

    func applySavedNoteAcknowledgement(serverNote: NotePayload, document: NotesSemanticDocument) {
        let plainText = NotesSemanticDocumentProjection.plainText(from: document)
        let acknowledged = NotePayload(
            id: serverNote.id,
            name: NotesSemanticDocumentProjection.title(from: document),
            document: document,
            documentVersion: document.version,
            plainText: plainText,
            path: serverNote.path,
            modified: serverNote.modified,
            created: serverNote.created
        )
        store.applyEditorUpdate(acknowledged)
    }

    public func applyLocalNoteSnapshot(id: String, document: NotesSemanticDocument) {
        guard let note = activeNote, note.id == id else { return }
        let plainText = NotesSemanticDocumentProjection.plainText(from: document)
        let updated = NotePayload(
            id: note.id,
            name: NotesSemanticDocumentProjection.title(from: document),
            document: document,
            documentVersion: document.version,
            plainText: plainText,
            path: note.path,
            modified: note.modified,
            created: note.created
        )
        store.applyEditorUpdate(updated)
    }

    /// Refreshes widget data by fetching the latest notes tree.
    /// Called by background refresh task to keep widgets up-to-date.
    func refreshWidgetData() async {
        do {
            try await store.loadTree(force: true)
        } catch {
            // Silently fail, widget will use cached data.
        }
    }

    public func reorderPinnedNotes(ids: [String]) async -> Bool {
        guard networkStatus.isNetworkAvailable, !networkStatus.isOffline else {
            return false
        }
        let previousOrder = store.pinnedNoteOrder()
        guard ids.count == previousOrder.count, Set(ids) == Set(previousOrder) else {
            return false
        }
        store.applyPinnedOrder(ids)
        setMirroredTree(store.tree)
        do {
            try await api.updatePinnedOrder(ids: ids)
            return true
        } catch {
            store.applyPinnedOrder(previousOrder)
            setMirroredTree(store.tree)
            toastCenter.show(message: "Failed to reorder pinned notes")
            return false
        }
    }
}
