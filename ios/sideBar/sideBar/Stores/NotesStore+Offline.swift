import Foundation

extension NotesStore {
    public func cachedNotePayload(path: String) -> NotePayload? {
        notePayload(forPath: path)
    }

    public func attachWriteQueue(_ writeQueue: WriteQueue) {
        self.writeQueue = writeQueue
    }

    public func loadFromOffline() async {
        guard let offline = offlineStore?.get(key: cacheKey, as: FileTree.self) else { return }
        applyTreeUpdate(offline, persist: false)
    }

    public func saveOfflineSnapshot() async {
        if let tree {
            let lastSyncAt = offlineStore?.lastSyncAt(for: cacheKey)
            offlineStore?.set(key: cacheKey, entityType: "notesTree", value: tree, lastSyncAt: lastSyncAt)
        }
        pruneArchivedNoteCache()
        if let activeNote {
            if shouldPersistNote(activeNote) {
                let idKey = CacheKeys.note(id: activeNote.id)
                let pathKey = CacheKeys.note(id: activeNote.path)
                let lastSyncAt = offlineStore?.lastSyncAt(for: pathKey)
                offlineStore?.set(key: idKey, entityType: "note", value: activeNote, lastSyncAt: lastSyncAt)
                offlineStore?.set(key: pathKey, entityType: "note", value: activeNote, lastSyncAt: lastSyncAt)
            } else {
                let idKey = CacheKeys.note(id: activeNote.id)
                let pathKey = CacheKeys.note(id: activeNote.path)
                cache.remove(key: idKey)
                cache.remove(key: pathKey)
                offlineStore?.remove(key: idKey)
                offlineStore?.remove(key: pathKey)
            }
        }
    }

    private func pruneArchivedNoteCache() {
        guard let offlineStore else { return }
        let prefix = CacheKeys.note(id: "")
        let cached: [NotePayload] = offlineStore.getAll(keyPrefix: prefix, as: NotePayload.self)
        for note in cached where !shouldPersistNote(note) {
            let idKey = CacheKeys.note(id: note.id)
            let pathKey = CacheKeys.note(id: note.path)
            cache.remove(key: idKey)
            cache.remove(key: pathKey)
            offlineStore.remove(key: idKey)
            offlineStore.remove(key: pathKey)
        }
    }

    public func enqueueUpdate(noteId: String, content: String) async throws {
        guard let writeQueue else { throw WriteQueueError.missingQueue }
        let snapshot = makeServerSnapshot(noteId: noteId, notePath: nil)
        try await writeQueue.enqueue(
            operation: .update,
            entityType: .note,
            entityId: noteId,
            payload: NoteUpdateRequest(content: content),
            serverSnapshot: snapshot
        )
    }

    public func enqueueRename(noteId: String, notePath: String, newName: String) async throws {
        guard let writeQueue else { throw WriteQueueError.missingQueue }
        let snapshot = makeServerSnapshot(noteId: noteId, notePath: notePath)
        try await writeQueue.enqueue(
            operation: .rename,
            entityType: .note,
            entityId: noteId,
            payload: RenameRequest(newName: newName),
            serverSnapshot: snapshot
        )
        applyLocalRename(notePath: notePath, newName: newName)
    }

    public func enqueueMove(notePath: String, folder: String) async throws {
        guard let writeQueue else { throw WriteQueueError.missingQueue }
        let snapshot = makeServerSnapshot(noteId: nil, notePath: notePath)
        try await writeQueue.enqueue(
            operation: .move,
            entityType: .note,
            entityId: notePath,
            payload: MoveRequest(folder: folder),
            serverSnapshot: snapshot
        )
        applyLocalMove(notePath: notePath, folder: folder)
    }

    public func enqueuePin(notePath: String, pinned: Bool) async throws {
        guard let writeQueue else { throw WriteQueueError.missingQueue }
        let snapshot = makeServerSnapshot(noteId: nil, notePath: notePath)
        try await writeQueue.enqueue(
            operation: .pin,
            entityType: .note,
            entityId: notePath,
            payload: PinRequest(pinned: pinned),
            serverSnapshot: snapshot
        )
        applyLocalPin(notePath: notePath, pinned: pinned)
    }

    public func enqueueArchive(notePath: String, archived: Bool) async throws {
        guard let writeQueue else { throw WriteQueueError.missingQueue }
        let snapshot = makeServerSnapshot(noteId: nil, notePath: notePath)
        try await writeQueue.enqueue(
            operation: .archive,
            entityType: .note,
            entityId: notePath,
            payload: ArchiveRequest(archived: archived),
            serverSnapshot: snapshot
        )
        applyLocalArchive(notePath: notePath, archived: archived)
    }

    public func enqueueDelete(notePath: String) async throws {
        guard let writeQueue else { throw WriteQueueError.missingQueue }
        let snapshot = makeServerSnapshot(noteId: nil, notePath: notePath)
        try await writeQueue.enqueue(
            operation: .delete,
            entityType: .note,
            entityId: notePath,
            payload: EmptyPayload(),
            serverSnapshot: snapshot
        )
        applyLocalDelete(notePath: notePath)
    }

    public func resolveConflict(_ conflict: SyncConflict<NotePayload>, keepLocal: Bool) async {
        guard let writeQueue else { return }
        await writeQueue.deleteWrites(entityType: .note, entityId: conflict.entityId)
        if keepLocal {
            applyEditorUpdate(conflict.local)
            try? await enqueueUpdate(noteId: conflict.entityId, content: conflict.local.content)
        } else {
            applyEditorUpdate(conflict.server)
        }
        writeQueue.resumeProcessing()
    }

    private func applyLocalRename(notePath: String, newName: String) {
        guard let updatedTree = updatedTree(notePath: notePath, transform: { node in
            let newPath = replacingFilename(in: notePath, with: newName)
            return copyNode(node, name: newName, path: newPath)
        }) else { return }
        persistLocalTree(updatedTree)
        updateCachedNotePath(from: notePath, to: replacingFilename(in: notePath, with: newName), newName: newName)
    }

    private func applyLocalMove(notePath: String, folder: String) {
        let newPath = movingPath(notePath, to: folder)
        guard let updatedTree = updatedTree(notePath: notePath, transform: { node in
            copyNode(node, path: newPath)
        }) else { return }
        persistLocalTree(updatedTree)
        updateCachedNotePath(from: notePath, to: newPath, newName: nil)
    }

    private func applyLocalPin(notePath: String, pinned: Bool) {
        guard let updatedTree = updatedTree(notePath: notePath, transform: { node in
            copyNode(node, pinned: pinned)
        }) else { return }
        persistLocalTree(updatedTree)
    }

    private func applyLocalArchive(notePath: String, archived: Bool) {
        guard let updatedTree = updatedTree(notePath: notePath, transform: { node in
            copyNode(node, archived: archived)
        }) else { return }
        persistLocalTree(updatedTree)
        if archived, activeNote?.path == notePath {
            activeNote = nil
        }
    }

    private func applyLocalDelete(notePath: String) {
        guard let tree else { return }
        let updatedChildren = removingNode(in: tree.children, notePath: notePath)
        let updatedTree = FileTree(children: updatedChildren)
        persistLocalTree(updatedTree)
        invalidateNote(id: notePath)
        if activeNote?.path == notePath {
            activeNote = nil
        }
    }

    private func persistLocalTree(_ updatedTree: FileTree) {
        tree = updatedTree
        cache.set(key: CacheKeys.notesTree, value: updatedTree, ttlSeconds: CachePolicy.notesTree)
        let lastSyncAt = offlineStore?.lastSyncAt(for: cacheKey)
        offlineStore?.set(key: cacheKey, entityType: "notesTree", value: updatedTree, lastSyncAt: lastSyncAt)
        updateWidgetData(from: updatedTree)
    }

    private func updateCachedNotePath(from oldPath: String, to newPath: String, newName: String?) {
        guard let note = notePayload(forPath: oldPath) else { return }
        let updated = NotePayload(
            id: note.id,
            name: newName ?? note.name,
            content: note.content,
            path: newPath,
            modified: note.modified
        )
        let lastSyncAt = offlineStore?.lastSyncAt(for: CacheKeys.note(id: oldPath))
        cache.remove(key: CacheKeys.note(id: oldPath))
        cache.set(key: CacheKeys.note(id: note.id), value: updated, ttlSeconds: CachePolicy.noteContent)
        cache.set(key: CacheKeys.note(id: newPath), value: updated, ttlSeconds: CachePolicy.noteContent)
        offlineStore?.remove(key: CacheKeys.note(id: oldPath))
        offlineStore?.set(key: CacheKeys.note(id: note.id), entityType: "note", value: updated, lastSyncAt: lastSyncAt)
        offlineStore?.set(key: CacheKeys.note(id: newPath), entityType: "note", value: updated, lastSyncAt: lastSyncAt)
        if activeNote?.id == note.id {
            applyNoteUpdate(updated, persist: true)
        }
    }

    private func updatedTree(notePath: String, transform: (FileNode) -> FileNode?) -> FileTree? {
        guard let tree else { return nil }
        let updatedChildren = updatingNodes(in: tree.children, notePath: notePath, transform: transform)
        return FileTree(children: updatedChildren)
    }

    private func updatingNodes(
        in nodes: [FileNode],
        notePath: String,
        transform: (FileNode) -> FileNode?
    ) -> [FileNode] {
        nodes.compactMap { node in
            var updatedNode = node
            if let children = node.children {
                let updatedChildren = updatingNodes(in: children, notePath: notePath, transform: transform)
                updatedNode = copyNode(node, children: updatedChildren)
            }
            if updatedNode.path == notePath {
                return transform(updatedNode)
            }
            return updatedNode
        }
    }

    private func removingNode(in nodes: [FileNode], notePath: String) -> [FileNode] {
        nodes.compactMap { node in
            if node.path == notePath {
                return nil
            }
            if let children = node.children {
                let updatedChildren = removingNode(in: children, notePath: notePath)
                return copyNode(node, children: updatedChildren)
            }
            return node
        }
    }

    private func copyNode(
        _ node: FileNode,
        name: String? = nil,
        path: String? = nil,
        pinned: Bool? = nil,
        pinnedOrder: Int? = nil,
        archived: Bool? = nil,
        children: [FileNode]? = nil
    ) -> FileNode {
        FileNode(
            name: name ?? node.name,
            path: path ?? node.path,
            type: node.type,
            size: node.size,
            modified: node.modified,
            children: children ?? node.children,
            expanded: node.expanded,
            pinned: pinned ?? node.pinned,
            pinnedOrder: pinnedOrder ?? node.pinnedOrder,
            archived: archived ?? node.archived,
            folderMarker: node.folderMarker
        )
    }

    private func movingPath(_ path: String, to folder: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let filename = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        let normalizedFolder = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let newPath = normalizedFolder.isEmpty ? filename : "\(normalizedFolder)/\(filename)"
        return path.hasPrefix("/") ? "/\(newPath)" : newPath
    }

    private func replacingFilename(in path: String, with newName: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = trimmed.split(separator: "/")
        let folder = parts.dropLast().joined(separator: "/")
        let newPath = folder.isEmpty ? newName : "\(folder)/\(newName)"
        return path.hasPrefix("/") ? "/\(newPath)" : newPath
    }

    private func makeServerSnapshot(noteId: String?, notePath: String?) -> ServerSnapshot? {
        if let noteId, let snapshot = noteSnapshot(forNoteId: noteId) {
            return ServerSnapshot(
                entityType: .note,
                entityId: noteId,
                capturedAt: Date(),
                payload: .note(snapshot)
            )
        }
        if let notePath, let snapshot = noteSnapshot(forPath: notePath) {
            return ServerSnapshot(
                entityType: .note,
                entityId: notePath,
                capturedAt: Date(),
                payload: .note(snapshot)
            )
        }
        return nil
    }

    private func noteSnapshot(forPath path: String) -> NoteSnapshot? {
        if let node = findNode(path: path, in: tree?.children ?? []) {
            return NoteSnapshot(
                modified: node.modified,
                name: node.name,
                path: node.path,
                pinned: node.pinned,
                pinnedOrder: node.pinnedOrder,
                archived: node.archived
            )
        }
        if let note = notePayload(forPath: path) {
            return NoteSnapshot(
                modified: note.modified,
                name: note.name,
                path: note.path,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil
            )
        }
        return nil
    }

    private func noteSnapshot(forNoteId noteId: String) -> NoteSnapshot? {
        if let note = notePayload(forId: noteId) {
            return NoteSnapshot(
                modified: note.modified,
                name: note.name,
                path: note.path,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil
            )
        }
        return nil
    }

    func notePayload(forId noteId: String) -> NotePayload? {
        if let activeNote, activeNote.id == noteId {
            return activeNote
        }
        if let cached: NotePayload = cache.get(key: CacheKeys.note(id: noteId)) {
            return cached
        }
        guard let offlineStore else { return nil }
        let prefix = CacheKeys.note(id: "")
        let cached: [NotePayload] = offlineStore.getAll(keyPrefix: prefix, as: NotePayload.self)
        return cached.first { $0.id == noteId }
    }

    func notePayload(forPath path: String) -> NotePayload? {
        if let activeNote, activeNote.path == path {
            return activeNote
        }
        let cacheKey = CacheKeys.note(id: path)
        if let cached: NotePayload = cache.get(key: cacheKey) {
            return cached
        }
        return offlineStore?.get(key: cacheKey, as: NotePayload.self)
    }

    private func findNode(path: String, in nodes: [FileNode]) -> FileNode? {
        for node in nodes {
            if node.path == path {
                return node
            }
            if let children = node.children, let found = findNode(path: path, in: children) {
                return found
            }
        }
        return nil
    }
}

private struct EmptyPayload: Codable {}
