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
        markAcceptedSaveAcknowledgementForRealtimeProtection(acknowledged)
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
        activeNote = store.activeNote
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
        let previousOrder = store.pinnedNoteOrder()
        guard ids.count == previousOrder.count, Set(ids) == Set(previousOrder) else {
            return false
        }
        do {
            try await store.enqueuePinnedOrder(ids: ids)
            setMirroredTree(store.tree)
            return true
        } catch WriteQueueError.queueFull {
            toastCenter.show(message: "Sync queue full. Review pending changes.")
            return false
        } catch {
            toastCenter.show(message: "Failed to queue pinned order")
            return false
        }
    }

    public func renameNote(id: String, newName: String) async {
        guard let trimmed = newName.trimmedOrNil else { return }
        guard let current = store.notePayload(forPath: id) ?? store.notePayload(forId: id) else {
            toastCenter.show(message: "Failed to rename note")
            return
        }

        let renamedDocument = NotesSemanticDocumentProjection.renamingTitle(
            in: current.document,
            to: trimmed
        )
        let optimistic = NotePayload(
            id: current.id,
            name: NotesSemanticDocumentProjection.title(from: renamedDocument),
            document: renamedDocument,
            plainText: NotesSemanticDocumentProjection.plainText(from: renamedDocument),
            path: current.path,
            modified: current.modified,
            created: current.created
        )

        store.applyNoteUpdate(optimistic, persist: false, activeNoteMode: .force)
        tree = store.tree
        archivedTree = store.archivedTree
        activeNote = store.activeNote

        do {
            try await store.enqueueUpdate(noteId: current.id, document: renamedDocument)
        } catch WriteQueueError.queueFull {
            store.applyNoteUpdate(current, persist: false, activeNoteMode: .force)
            tree = store.tree
            archivedTree = store.archivedTree
            activeNote = store.activeNote
            toastCenter.show(message: "Sync queue full. Review pending changes.")
        } catch {
            store.applyNoteUpdate(current, persist: false, activeNoteMode: .force)
            tree = store.tree
            archivedTree = store.archivedTree
            activeNote = store.activeNote
            toastCenter.show(message: "Failed to queue rename")
        }
    }

    public func moveNote(id: String, folder: String) async {
        do {
            try await store.enqueueMove(notePath: id, folder: folder)
            if selectedNoteId == id {
                selectedNoteId = movingPath(id, to: folder)
            }
            tree = store.tree
            archivedTree = store.archivedTree
            activeNote = store.activeNote
        } catch WriteQueueError.queueFull {
            toastCenter.show(message: "Sync queue full. Review pending changes.")
        } catch {
            toastCenter.show(message: "Failed to queue move")
        }
    }

    public func setArchived(id: String, archived: Bool) async {
        do {
            try await store.enqueueArchive(notePath: id, archived: archived)
            if archived, selectedNoteId == id {
                clearSelection()
            }
            tree = store.tree
            archivedTree = store.archivedTree
            activeNote = store.activeNote
        } catch WriteQueueError.queueFull {
            toastCenter.show(message: "Sync queue full. Review pending changes.")
        } catch {
            toastCenter.show(message: archived ? "Failed to queue archive" : "Failed to queue unarchive")
        }
    }

    public func setPinned(id: String, pinned: Bool) async {
        do {
            try await store.enqueuePin(notePath: id, pinned: pinned)
            tree = store.tree
            archivedTree = store.archivedTree
            activeNote = store.activeNote
        } catch WriteQueueError.queueFull {
            toastCenter.show(message: "Sync queue full. Review pending changes.")
        } catch {
            toastCenter.show(message: pinned ? "Failed to queue pin" : "Failed to queue unpin")
        }
    }

    public func deleteNote(id: String) async {
        do {
            try await store.enqueueDelete(notePath: id)
            if selectedNoteId == id {
                clearSelection()
            }
            tree = store.tree
            archivedTree = store.archivedTree
            activeNote = store.activeNote
        } catch WriteQueueError.queueFull {
            toastCenter.show(message: "Sync queue full. Review pending changes.")
        } catch {
            toastCenter.show(message: "Failed to queue delete")
        }
    }

    public func renameFolder(path: String, newName: String) async {
        guard let trimmed = newName.trimmedOrNil else { return }
        let normalized = normalizeFolderPath(path)
        guard !normalized.isEmpty else { return }
        do {
            try await store.enqueueRenameFolder(path: normalized, newName: trimmed)
            if let selected = selectedNoteId {
                let parent = parentFolderPath(normalized)
                let updatedPrefix = parent.isEmpty ? trimmed : "\(parent)/\(trimmed)"
                let folderPrefix = normalized + "/"
                if selected.hasPrefix(folderPrefix) {
                    let suffix = selected.dropFirst(folderPrefix.count)
                    selectedNoteId = updatedPrefix + "/" + suffix
                } else if selected == normalized {
                    selectedNoteId = updatedPrefix
                }
            }
            tree = store.tree
            archivedTree = store.archivedTree
        } catch WriteQueueError.queueFull {
            toastCenter.show(message: "Sync queue full. Review pending changes.")
        } catch {
            toastCenter.show(message: "Failed to queue folder rename")
        }
    }

    public func deleteFolder(path: String) async {
        let normalized = normalizeFolderPath(path)
        guard !normalized.isEmpty else { return }
        let shouldClearSelection = selectedNoteId.map {
            isSelectedNote($0, containedInFolder: normalized) || $0 == normalized
        } ?? false
        do {
            try await store.enqueueDeleteFolder(path: normalized)
            tree = store.tree
            archivedTree = store.archivedTree
            if shouldClearSelection {
                clearSelection()
            }
        } catch WriteQueueError.queueFull {
            toastCenter.show(message: "Sync queue full. Review pending changes.")
        } catch {
            toastCenter.show(message: "Failed to queue folder delete")
        }
    }

    private func normalizeFolderPath(_ path: String) -> String {
        let trimmed = path.trimmed
        if trimmed.hasPrefix("folder:") {
            let start = trimmed.index(trimmed.startIndex, offsetBy: 7)
            return String(trimmed[start...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func parentFolderPath(_ path: String) -> String {
        guard let lastSlash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<lastSlash])
    }

    private func movingPath(_ path: String, to folder: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let filename = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        let normalizedFolder = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let newPath = normalizedFolder.isEmpty ? filename : "\(normalizedFolder)/\(filename)"
        return path.hasPrefix("/") ? "/\(newPath)" : newPath
    }

    private func isSelectedNote(_ selected: String, containedInFolder folderPath: String) -> Bool {
        let containingFolder = self.folderPath(containingNote: selected)
        return containingFolder == folderPath || containingFolder.hasPrefix(folderPath + "/")
    }
}
