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

        if notesOfflineCapabilityPolicy.shouldQueueWrites {
            do {
                try await store.enqueueUpdate(noteId: current.id, document: renamedDocument)
                return
            } catch WriteQueueError.queueFull {
                store.applyNoteUpdate(current, persist: false, activeNoteMode: .force)
                tree = store.tree
                archivedTree = store.archivedTree
                activeNote = store.activeNote
                toastCenter.show(message: "Sync queue full. Review pending changes.")
                return
            } catch {
                store.applyNoteUpdate(current, persist: false, activeNoteMode: .force)
                tree = store.tree
                archivedTree = store.archivedTree
                activeNote = store.activeNote
                toastCenter.show(message: "Failed to queue rename")
                return
            }
        }

        do {
            let updated = try await api.updateNote(id: current.id, document: renamedDocument)
            applySavedNoteAcknowledgement(serverNote: updated, document: renamedDocument)
            tree = store.tree
            archivedTree = store.archivedTree
            activeNote = store.activeNote
        } catch {
            store.applyNoteUpdate(current, persist: false, activeNoteMode: .force)
            tree = store.tree
            archivedTree = store.archivedTree
            activeNote = store.activeNote
            toastCenter.show(message: "Failed to rename note")
        }
    }

    public func moveNote(id: String, folder: String) async {
        if notesOfflineCapabilityPolicy.shouldQueueWrites {
            do {
                try await store.enqueueMove(notePath: id, folder: folder)
                if selectedNoteId == id {
                    selectedNoteId = movingPath(id, to: folder)
                }
            } catch WriteQueueError.queueFull {
                toastCenter.show(message: "Sync queue full. Review pending changes.")
            } catch {
                toastCenter.show(message: "Failed to queue move")
            }
            return
        }
        let previousSelection = selectedNoteId
        let shouldRetainSelection = selectedNoteId == id || activeNote?.path == id
        let movedPath = movingPath(id, to: folder)
        store.applyOptimisticMove(notePath: id, folder: folder)
        tree = store.tree
        archivedTree = store.archivedTree
        activeNote = store.activeNote
        if shouldRetainSelection {
            selectedNoteId = movedPath
        }
        do {
            let updated = try await api.moveNote(id: id, folder: folder)
            store.applyEditorUpdate(updated)
            tree = store.tree
            archivedTree = store.archivedTree
            activeNote = store.activeNote
            if shouldRetainSelection && selectedNoteId != updated.path {
                selectedNoteId = updated.path
            }
        } catch {
            try? await store.loadTree(force: true)
            tree = store.tree
            archivedTree = store.archivedTree
            activeNote = store.activeNote
            if shouldRetainSelection {
                selectedNoteId = previousSelection
            }
            toastCenter.show(message: "Failed to move note")
        }
    }

    public func setArchived(id: String, archived: Bool) async {
        if notesOfflineCapabilityPolicy.shouldQueueWrites {
            do {
                try await store.enqueueArchive(notePath: id, archived: archived)
                if archived, selectedNoteId == id {
                    clearSelection()
                }
            } catch WriteQueueError.queueFull {
                toastCenter.show(message: "Sync queue full. Review pending changes.")
            } catch {
                toastCenter.show(message: archived ? "Failed to queue archive" : "Failed to queue unarchive")
            }
            return
        }
        let clearedSelection = archived && selectedNoteId == id
        store.applyOptimisticArchive(notePath: id, archived: archived)
        tree = store.tree
        archivedTree = store.archivedTree
        activeNote = store.activeNote
        if clearedSelection {
            clearSelection()
        }
        do {
            let updated = try await api.archiveNote(id: id, archived: archived)
            store.applyEditorUpdate(updated)
            tree = store.tree
            archivedTree = store.archivedTree
            activeNote = store.activeNote
        } catch {
            try? await store.loadTree(force: true)
            tree = store.tree
            archivedTree = store.archivedTree
            activeNote = store.activeNote
            if clearedSelection {
                selectedNoteId = id
            }
            toastCenter.show(message: archived ? "Failed to archive note" : "Failed to unarchive note")
        }
    }

    public func setPinned(id: String, pinned: Bool) async {
        if notesOfflineCapabilityPolicy.shouldQueueWrites {
            do {
                try await store.enqueuePin(notePath: id, pinned: pinned)
            } catch WriteQueueError.queueFull {
                toastCenter.show(message: "Sync queue full. Review pending changes.")
            } catch {
                toastCenter.show(message: pinned ? "Failed to queue pin" : "Failed to queue unpin")
            }
            return
        }
        store.applyOptimisticPin(notePath: id, pinned: pinned)
        tree = store.tree
        archivedTree = store.archivedTree
        do {
            let updated = try await api.pinNote(id: id, pinned: pinned)
            store.applyEditorUpdate(updated)
            tree = store.tree
            archivedTree = store.archivedTree
            activeNote = store.activeNote
        } catch {
            try? await store.loadTree(force: true)
            tree = store.tree
            archivedTree = store.archivedTree
            activeNote = store.activeNote
            toastCenter.show(message: pinned ? "Failed to pin note" : "Failed to unpin note")
        }
    }

    public func deleteNote(id: String) async {
        if notesOfflineCapabilityPolicy.shouldQueueWrites {
            do {
                try await store.enqueueDelete(notePath: id)
                if selectedNoteId == id {
                    clearSelection()
                }
            } catch WriteQueueError.queueFull {
                toastCenter.show(message: "Sync queue full. Review pending changes.")
            } catch {
                toastCenter.show(message: "Failed to queue delete")
            }
            return
        }
        let clearedSelection = selectedNoteId == id
        store.applyOptimisticDelete(notePath: id)
        tree = store.tree
        archivedTree = store.archivedTree
        activeNote = store.activeNote
        if clearedSelection {
            clearSelection()
        }
        do {
            _ = try await api.deleteNote(id: id)
            store.invalidateNote(id: id)
            tree = store.tree
            archivedTree = store.archivedTree
            activeNote = store.activeNote
        } catch {
            try? await store.loadTree(force: true)
            tree = store.tree
            archivedTree = store.archivedTree
            activeNote = store.activeNote
            if clearedSelection {
                selectedNoteId = id
            }
            toastCenter.show(message: "Failed to delete note")
        }
    }

    public func renameFolder(path: String, newName: String) async {
        guard let trimmed = newName.trimmedOrNil else { return }
        let normalized = normalizeFolderPath(path)
        guard !normalized.isEmpty else { return }
        if notesOfflineCapabilityPolicy.shouldQueueWrites {
            do {
                try await store.enqueueRenameFolder(path: normalized, newName: trimmed)
                tree = store.tree
                archivedTree = store.archivedTree
                return
            } catch WriteQueueError.queueFull {
                toastCenter.show(message: "Sync queue full. Review pending changes.")
                return
            } catch {
                toastCenter.show(message: "Failed to queue folder rename")
                return
            }
        }
        do {
            try await api.renameFolder(oldPath: normalized, newName: trimmed)
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
            await refreshTree(force: true)
        } catch {
            toastCenter.show(message: "Failed to rename folder")
        }
    }

    public func deleteFolder(path: String) async {
        let normalized = normalizeFolderPath(path)
        guard !normalized.isEmpty else { return }
        if notesOfflineCapabilityPolicy.shouldQueueWrites {
            do {
                try await store.enqueueDeleteFolder(path: normalized)
                tree = store.tree
                archivedTree = store.archivedTree
                if let selected = selectedNoteId {
                    let folderPrefix = normalized + "/"
                    if selected.hasPrefix(folderPrefix) || selected == normalized {
                        clearSelection()
                    }
                }
                return
            } catch WriteQueueError.queueFull {
                toastCenter.show(message: "Sync queue full. Review pending changes.")
                return
            } catch {
                toastCenter.show(message: "Failed to queue folder delete")
                return
            }
        }
        do {
            try await api.deleteFolder(path: normalized)
            if let selected = selectedNoteId {
                let folderPrefix = normalized + "/"
                if selected.hasPrefix(folderPrefix) || selected == normalized {
                    clearSelection()
                }
            }
            await refreshTree(force: true)
        } catch {
            toastCenter.show(message: "Failed to delete folder")
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
}
