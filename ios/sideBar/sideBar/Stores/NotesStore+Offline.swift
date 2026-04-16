import Foundation
import OSLog
import sideBarShared

extension NotesStore {
    private var offlineLogger: Logger {
        Logger(subsystem: "sideBar", category: "NotesStoreOffline")
    }

    /// Returns a cached note payload for the provided note path when available.
    public func cachedNotePayload(path: String) -> NotePayload? {
        notePayload(forPath: path)
    }

    /// Attaches the write queue used for enqueueing offline note operations.
    public func attachWriteQueue(_ writeQueue: WriteQueue) {
        self.writeQueue = writeQueue
    }

    /// Loads the notes tree from offline storage into in-memory state.
    public func loadFromOffline() async {
        guard let offline = offlineStore?.get(key: cacheKey, as: FileTree.self) else { return }
        applyTreeUpdate(offline, persist: false)
    }

    /// Persists current notes tree, archived tree, and active note snapshots to offline storage.
    public func saveOfflineSnapshot() async {
        if let tree {
            let lastSyncAt = offlineStore?.lastSyncAt(for: cacheKey)
            offlineStore?.set(key: cacheKey, entityType: "notesTree", value: tree, lastSyncAt: lastSyncAt)
        }
        if let archivedTree {
            let lastSyncAt = offlineStore?.lastSyncAt(for: CacheKeys.notesArchivedTree)
            offlineStore?.set(
                key: CacheKeys.notesArchivedTree,
                entityType: "notesArchivedTree",
                value: archivedTree,
                lastSyncAt: lastSyncAt
            )
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

    /// Enqueues an offline semantic note update operation.
    public func enqueueUpdate(noteId: String, document: NotesSemanticDocument) async throws {
        let snapshot = makeServerSnapshot(noteId: noteId, notePath: nil)
        try await enqueueOfflineOperation(
            writeQueue: writeQueue,
            operation: .update,
            entityType: .note,
            entityId: noteId,
            payload: NoteUpdateRequest(document: document),
            serverSnapshot: snapshot
        )
    }

    public func enqueueCreateNote(localID: String, request: NoteCreateRequest) async throws {
        let queuedRequest = NoteCreateRequest(
            document: request.document,
            title: request.title,
            path: request.path,
            folder: request.folder,
            plainText: request.plainText,
            clientId: localID
        )
        try await enqueueOfflineOperation(
            writeQueue: writeQueue,
            operation: .create,
            entityType: .note,
            entityId: localID,
            payload: queuedRequest
        )
        applyLocalCreateNote(localID: localID, request: queuedRequest)
    }

    public func enqueueCreateFolder(path: String) async throws {
        let normalizedPath = normalizedFolderNodePath(path)
        try await enqueueOfflineOperation(
            writeQueue: writeQueue,
            operation: .create,
            entityType: .noteFolder,
            entityId: normalizedPath,
            payload: NoteFolderCreateRequest(path: normalizedPath)
        )
        applyLocalCreateFolder(path: normalizedPath)
    }

    public func enqueueRenameFolder(path: String, newName: String) async throws {
        let normalizedPath = normalizedFolderNodePath(path)
        try await enqueueOfflineOperation(
            writeQueue: writeQueue,
            operation: .rename,
            entityType: .noteFolder,
            entityId: normalizedPath,
            payload: NoteFolderRenameRequest(oldPath: normalizedPath, newName: newName)
        )
        applyLocalRenameFolder(path: normalizedPath, newName: newName)
    }

    public func enqueueDeleteFolder(path: String) async throws {
        let normalizedPath = normalizedFolderNodePath(path)
        try await enqueueOfflineOperation(
            writeQueue: writeQueue,
            operation: .delete,
            entityType: .noteFolder,
            entityId: normalizedPath,
            payload: NoteFolderDeleteRequest(path: normalizedPath)
        )
        applyLocalDeleteFolder(path: normalizedPath)
    }

    /// Enqueues an offline move operation and applies the move optimistically.
    public func enqueueMove(notePath: String, folder: String) async throws {
        let snapshot = makeServerSnapshot(noteId: nil, notePath: notePath)
        try await enqueueOfflineOperation(
            writeQueue: writeQueue,
            operation: .move,
            entityType: .note,
            entityId: notePath,
            payload: MoveRequest(folder: folder),
            serverSnapshot: snapshot
        )
        applyLocalMove(notePath: notePath, folder: folder, shouldUpdateCachedNotePath: true)
    }

    func applyOptimisticMove(notePath: String, folder: String) {
        applyLocalMove(notePath: notePath, folder: folder, shouldUpdateCachedNotePath: false)
    }

    func applyOptimisticPin(notePath: String, pinned: Bool) {
        applyLocalPin(notePath: notePath, pinned: pinned)
    }

    func applyOptimisticArchive(notePath: String, archived: Bool) {
        applyLocalArchive(notePath: notePath, archived: archived)
    }

    func applyOptimisticDelete(notePath: String) {
        applyLocalDelete(notePath: notePath)
    }

    func applyOptimisticCreateFolder(path: String) {
        applyLocalCreateFolder(path: path)
    }

    func applyOptimisticRenameFolder(path: String, newName: String) {
        applyLocalRenameFolder(path: path, newName: newName)
    }

    func applyOptimisticDeleteFolder(path: String) {
        applyLocalDeleteFolder(path: path)
    }

    /// Enqueues an offline pin toggle operation and applies it optimistically.
    public func enqueuePin(notePath: String, pinned: Bool) async throws {
        let snapshot = makeServerSnapshot(noteId: nil, notePath: notePath)
        try await enqueueOfflineOperation(
            writeQueue: writeQueue,
            operation: .pin,
            entityType: .note,
            entityId: notePath,
            payload: PinRequest(pinned: pinned),
            serverSnapshot: snapshot
        )
        applyLocalPin(notePath: notePath, pinned: pinned)
    }

    /// Enqueues an offline archive toggle operation and applies it optimistically.
    public func enqueueArchive(notePath: String, archived: Bool) async throws {
        let snapshot = makeServerSnapshot(noteId: nil, notePath: notePath)
        try await enqueueOfflineOperation(
            writeQueue: writeQueue,
            operation: .archive,
            entityType: .note,
            entityId: notePath,
            payload: ArchiveRequest(archived: archived),
            serverSnapshot: snapshot
        )
        applyLocalArchive(notePath: notePath, archived: archived)
    }

    /// Enqueues an offline delete operation and applies deletion optimistically.
    public func enqueueDelete(notePath: String) async throws {
        let snapshot = makeServerSnapshot(noteId: nil, notePath: notePath)
        try await enqueueOfflineOperation(
            writeQueue: writeQueue,
            operation: .delete,
            entityType: .note,
            entityId: notePath,
            payload: EmptyPayload(),
            serverSnapshot: snapshot
        )
        applyLocalDelete(notePath: notePath)
    }

    private func applyLocalMove(notePath: String, folder: String, shouldUpdateCachedNotePath: Bool) {
        guard let tree else { return }
        let newPath = movingPath(notePath, to: folder)
        let removal = removeNodeFromTree(in: tree.children, notePath: notePath)
        guard let removed = removal.removed else { return }

        let movedNode = copyNode(removed, path: newPath, pinned: false, pinnedOrder: nil)
        let updatedChildren = insertNodeIntoFolder(removal.nodes, node: movedNode, folder: folder)
        let updatedTree = makeTree(children: updatedChildren)
        persistLocalTree(updatedTree)
        if shouldUpdateCachedNotePath {
            updateCachedNotePath(from: notePath, to: newPath, newName: nil)
        }
    }

    private func applyLocalPin(notePath: String, pinned: Bool) {
        guard let updatedTree = updatedTree(in: tree, notePath: notePath, transform: { node in
            copyNode(node, pinned: pinned)
        }) else { return }
        persistLocalTree(updatedTree)
    }

    private func applyLocalArchive(notePath: String, archived: Bool) {
        guard let updatedTree = updatedTree(in: tree, notePath: notePath, transform: { node in
            copyNode(node, pinned: archived ? false : nil, archived: archived)
        }) else { return }
        persistLocalTree(updatedTree)
        if archived, activeNote?.path == notePath {
            activeNote = nil
            activeNoteRequestID = nil
        }
    }

    private func applyLocalDelete(notePath: String) {
        guard let tree else { return }
        let updatedChildren = removingNode(in: tree.children, notePath: notePath)
        let updatedTree = makeTree(children: updatedChildren)
        persistLocalTree(updatedTree)
        invalidateNote(id: notePath)
        if activeNote?.path == notePath {
            activeNote = nil
            activeNoteRequestID = nil
        }
    }

    private func applyLocalCreateNote(localID: String, request: NoteCreateRequest) {
        let resolvedFolder = resolvedFolderPath(for: request)
        let document = request.document
        let title = NotesSemanticDocumentProjection.title(from: document).trimmedOrNil ?? "New Note"
        let plainText = request.plainText ?? NotesSemanticDocumentProjection.plainText(from: document)
        let timestamp = Date().timeIntervalSince1970
        let note = NotePayload(
            id: localID,
            name: title,
            document: document,
            plainText: plainText,
            path: localID,
            modified: timestamp,
            created: timestamp
        )
        let node = FileNode(
            name: title,
            path: localID,
            type: .file,
            size: nil,
            modified: timestamp,
            created: timestamp,
            children: nil,
            expanded: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: isArchiveFolder(resolvedFolder),
            folderMarker: nil
        )
        let baseTree = tree ?? makeTree(children: [])
        let updatedChildren = insertNodeIntoFolder(baseTree.children, node: node, folder: resolvedFolder)
        persistLocalTree(makeTree(children: updatedChildren))
        applyNoteUpdate(note, persist: true, activeNoteMode: .force)
        activeNoteRequestID = localID
    }

    private func applyLocalCreateFolder(path: String) {
        let normalizedPath = normalizedFolderNodePath(path)
        guard !normalizedPath.isEmpty else { return }
        let components = normalizedPath.split(separator: "/").map(String.init)
        guard let name = components.last else { return }
        let parent = components.dropLast().joined(separator: "/")
        let folderNode = makeFolderNode(name: name, normalizedPath: normalizedPath, children: [])
        let baseTree = tree ?? makeTree(children: [])
        let updatedChildren = insertNodeIntoFolder(baseTree.children, node: folderNode, folder: parent)
        persistLocalTree(makeTree(children: updatedChildren))
    }

    private func applyLocalRenameFolder(path: String, newName: String) {
        guard let sourceTree = tree else { return }
        let normalizedPath = normalizedFolderNodePath(path)
        guard !normalizedPath.isEmpty else { return }
        let parent = parentFolderPath(normalizedPath)
        let updatedPath = parent.isEmpty ? newName : "\(parent)/\(newName)"
        let updatedChildren = renamingFolderNodes(
            in: sourceTree.children,
            oldPath: normalizedPath,
            newPath: updatedPath,
            newName: newName
        )
        persistLocalTree(makeTree(children: updatedChildren))
    }

    private func applyLocalDeleteFolder(path: String) {
        guard let sourceTree = tree else { return }
        let normalizedPath = normalizedFolderNodePath(path)
        let updatedChildren = removingFolder(in: sourceTree.children, normalizedPath: normalizedPath)
        persistLocalTree(makeTree(children: updatedChildren))
    }

    private func persistLocalTree(_ updatedTree: FileTree) {
        tree = updatedTree
        cache.set(key: CacheKeys.notesTree, value: updatedTree, ttlSeconds: CachePolicy.notesTree)
        let lastSyncAt = offlineStore?.lastSyncAt(for: cacheKey)
        offlineStore?.set(key: cacheKey, entityType: "notesTree", value: updatedTree, lastSyncAt: lastSyncAt)
        updateWidgetData(from: updatedTree)
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

}

private struct EmptyPayload: Codable {}
