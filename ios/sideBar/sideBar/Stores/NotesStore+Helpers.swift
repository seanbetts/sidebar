import Foundation
import sideBarShared
#if canImport(WidgetKit)
import WidgetKit
#endif

extension NotesStore {
    enum ActiveNoteUpdateMode {
        case matchingSelection
        case force
        case none
    }

    func indexNotesFromTree(_ tree: FileTree) {
        guard let indexer = spotlightIndexer else { return }
        let notes = flattenNoteNodes(from: tree.children)
            .filter { $0.archived != true }
            .map { node in
                SpotlightNote(
                    path: node.path,
                    name: node.name,
                    content: nil,
                    modified: node.modified.map { Date(timeIntervalSince1970: $0) }
                )
            }
        Task {
            await indexer.indexNotes(notes)
        }
    }

    func flattenNoteNodes(from nodes: [FileNode]) -> [FileNode] {
        var result: [FileNode] = []
        for node in nodes {
            if node.type == .file {
                result.append(node)
            }
            if let children = node.children {
                result.append(contentsOf: flattenNoteNodes(from: children))
            }
        }
        return result
    }

    func applyArchivedTreeUpdate(_ incoming: FileTree, persist: Bool) {
        let merged = mergeArchivedSummary(into: incoming)
        updateArchivedSummary(from: merged, persist: false)
        archivedTree = merged
        if persist {
            cache.set(key: CacheKeys.notesArchivedTree, value: merged, ttlSeconds: cacheTTL)
            let lastSyncAt = Date()
            offlineStore?.set(
                key: CacheKeys.notesArchivedTree,
                entityType: "notesArchivedTree",
                value: merged,
                lastSyncAt: lastSyncAt
            )
        }
    }

    func makeTree(children: [FileNode]) -> FileTree {
        FileTree(
            children: children,
            archivedCount: archivedSummary?.count,
            archivedLastUpdated: archivedSummary?.lastUpdated
        )
    }

    func updateArchivedSummary(from tree: FileTree, persist: Bool) {
        let summary = ArchivedSummary(
            count: tree.archivedCount,
            lastUpdated: tree.archivedLastUpdated
        )
        guard !summary.isEmpty else {
            return
        }
        archivedSummary = summary
        if persist, summary.count == 0 {
            let empty = FileTree(
                children: [],
                archivedCount: summary.count,
                archivedLastUpdated: summary.lastUpdated
            )
            applyArchivedTreeUpdate(empty, persist: true)
            archivedTreeSyncedAt = summary.lastUpdated
            persistArchivedSyncToken()
        }
    }

    func mergeArchivedSummary(into tree: FileTree) -> FileTree {
        FileTree(
            children: tree.children,
            archivedCount: tree.archivedCount ?? archivedSummary?.count,
            archivedLastUpdated: tree.archivedLastUpdated ?? archivedSummary?.lastUpdated
        )
    }

    func shouldRefreshArchivedTree(force: Bool) -> Bool {
        if force {
            return true
        }
        loadArchivedSyncTokenIfNeeded()
        if let summary = archivedSummary {
            if summary.count == 0 {
                return false
            }
            if archivedTree == nil {
                return true
            }
            guard let serverUpdated = summary.lastUpdated else {
                return archivedTree == nil
            }
            let syncedAt = archivedTreeSyncedAt ?? archivedTree?.archivedLastUpdated
            if let syncedAt {
                return syncedAt != serverUpdated
            }
            return true
        }
        return true
    }

    func loadArchivedSyncTokenIfNeeded() {
        guard !archivedSyncLoaded else {
            return
        }
        archivedSyncLoaded = true
        archivedTreeSyncedAt = offlineStore?.get(
            key: CacheKeys.notesArchivedSync,
            as: String.self
        )
    }

    func persistArchivedSyncToken() {
        guard let archivedTreeSyncedAt else {
            return
        }
        let lastSyncAt = Date()
        offlineStore?.set(
            key: CacheKeys.notesArchivedSync,
            entityType: "notesArchivedSync",
            value: archivedTreeSyncedAt,
            lastSyncAt: lastSyncAt
        )
    }

    func shouldUpdateTree(_ incoming: FileTree) -> Bool {
        guard let current = tree else {
            return true
        }
        if current.archivedCount != incoming.archivedCount ||
            current.archivedLastUpdated != incoming.archivedLastUpdated {
            return true
        }
        return FileTreeSignature.make(current) != FileTreeSignature.make(incoming)
    }

    func applyNoteUpdate(
        _ incoming: NotePayload,
        persist: Bool,
        activeNoteMode: ActiveNoteUpdateMode = .matchingSelection
    ) {
        syncNoteMetadataIntoTrees(incoming, persist: persist)
        if shouldApplyNoteUpdateToActiveNote(incoming, mode: activeNoteMode),
           shouldUpdateActiveNote(incoming) {
            activeNote = incoming
            activeNoteRequestID = incoming.id
        }
        if persist {
            if shouldPersistNote(incoming) {
                persistNote(incoming)
                indexNoteInSpotlight(incoming)
            } else {
                clearCachedNote(incoming)
            }
        }
    }

    func syncActiveNote(with tree: FileTree, persist: Bool) {
        guard let activeNote,
              let node = findNode(path: activeNote.path, in: tree.children) else {
            return
        }
        let updated = notePayload(activeNote, syncedWith: node)
        guard shouldSyncActiveNoteMetadata(current: activeNote, updated: updated) else {
            return
        }
        self.activeNote = updated
        guard persist else { return }
        if shouldPersistNote(updated) {
            persistNote(updated)
            indexNoteInSpotlight(updated)
        } else {
            clearCachedNote(updated)
        }
    }

    private func syncNoteMetadataIntoTrees(_ note: NotePayload, persist: Bool) {
        syncNoteMetadata(
            into: tree,
            cacheKey: CacheKeys.notesTree,
            entityType: "notesTree",
            note: note,
            persist: persist
        ) { [weak self] updated in
            self?.tree = updated
            self?.updateWidgetData(from: updated)
        }

        syncNoteMetadata(
            into: archivedTree,
            cacheKey: CacheKeys.notesArchivedTree,
            entityType: "notesArchivedTree",
            note: note,
            persist: persist
        ) { [weak self] updated in
            self?.archivedTree = updated
        }
    }

    private func syncNoteMetadata(
        into sourceTree: FileTree?,
        cacheKey: String,
        entityType: String,
        note: NotePayload,
        persist: Bool,
        apply: (FileTree) -> Void
    ) {
        guard let sourceTree else { return }
        guard let updated = updatedTree(in: sourceTree, notePath: note.path, transform: { node in
            guard node.name != note.name || node.modified != note.modified else {
                return node
            }
            return copyNode(node, name: note.name, modified: note.modified)
        }) else {
            return
        }
        guard FileTreeSignature.make(sourceTree) != FileTreeSignature.make(updated) else {
            return
        }
        apply(updated)
        guard persist else { return }
        cache.set(key: cacheKey, value: updated, ttlSeconds: cacheTTL)
        let lastSyncAt = offlineStore?.lastSyncAt(for: cacheKey) ?? Date()
        offlineStore?.set(
            key: cacheKey,
            entityType: entityType,
            value: updated,
            lastSyncAt: lastSyncAt
        )
    }

    func notePayload(_ note: NotePayload, syncedWith node: FileNode) -> NotePayload {
        NotePayload(
            id: note.id,
            name: node.name,
            document: note.document,
            documentVersion: note.documentVersion,
            plainText: note.plainText,
            path: node.path,
            modified: node.modified,
            created: note.created
        )
    }

    func shouldSyncActiveNoteMetadata(current: NotePayload, updated: NotePayload) -> Bool {
        current.name != updated.name ||
            current.path != updated.path ||
            current.modified != updated.modified
    }

    func indexNoteInSpotlight(_ note: NotePayload) {
        guard let indexer = spotlightIndexer else { return }
        let spotlightNote = SpotlightNote(
            path: note.path,
            name: note.name,
            content: note.plainText,
            modified: note.modified.map { Date(timeIntervalSince1970: $0) }
        )
        Task {
            await indexer.indexNote(spotlightNote)
        }
    }

    func removeNoteFromSpotlight(path: String) {
        guard let indexer = spotlightIndexer else { return }
        Task {
            await indexer.removeNote(path: path)
        }
    }

    func shouldUpdateActiveNote(_ incoming: NotePayload) -> Bool {
        guard let current = activeNote else {
            return true
        }
        return current.modified != incoming.modified ||
            current.document != incoming.document ||
            current.documentVersion != incoming.documentVersion ||
            current.plainText != incoming.plainText ||
            current.name != incoming.name ||
            current.path != incoming.path ||
            current.created != incoming.created
    }

    func shouldApplyNoteUpdateToActiveNote(
        _ incoming: NotePayload,
        mode: ActiveNoteUpdateMode
    ) -> Bool {
        switch mode {
        case .force:
            return true
        case .none:
            return false
        case .matchingSelection:
            if let activeNoteRequestID,
               activeNoteRequestID == incoming.id || activeNoteRequestID == incoming.path {
                return true
            }
            if let activeNote,
               activeNote.id == incoming.id || activeNote.path == incoming.path {
                return true
            }
            return false
        }
    }

    func shouldPersistNote(_ note: NotePayload) -> Bool {
        guard isArchived(note) else {
            return true
        }
        return ArchivedRetentionPolicy.contains(
            epochSeconds: note.modified,
            retentionDays: archivedNoteRetentionDays
        )
    }

    func persistNote(_ note: NotePayload) {
        let idKey = CacheKeys.note(id: note.id)
        let pathKey = CacheKeys.note(id: note.path)
        cache.set(key: idKey, value: note, ttlSeconds: CachePolicy.noteContent)
        cache.set(key: pathKey, value: note, ttlSeconds: CachePolicy.noteContent)
        let lastSyncAt = Date()
        offlineStore?.set(key: idKey, entityType: "note", value: note, lastSyncAt: lastSyncAt)
        offlineStore?.set(key: pathKey, entityType: "note", value: note, lastSyncAt: lastSyncAt)
    }

    func clearCachedNote(_ note: NotePayload) {
        let idKey = CacheKeys.note(id: note.id)
        let pathKey = CacheKeys.note(id: note.path)
        cache.remove(key: idKey)
        cache.remove(key: pathKey)
        offlineStore?.remove(key: idKey)
        offlineStore?.remove(key: pathKey)
    }

    func isArchived(_ note: NotePayload) -> Bool {
        if let tree, findNode(path: note.path, in: tree.children)?.archived == true {
            return true
        }
        if let archivedTree, findNode(path: note.path, in: archivedTree.children)?.archived == true {
            return true
        }
        return false
    }

    func prefetchArchivedNotes(from tree: FileTree) async {
        guard archivedNotePrefetchLimit > 0 else { return }
        guard !(networkStatus?.isOffline ?? false) else { return }
        guard !isPrefetchingArchivedNotes else { return }
        isPrefetchingArchivedNotes = true
        defer { isPrefetchingArchivedNotes = false }

        let nodes = archivedNoteNodes(from: tree.children)
        let candidates = nodes.filter { isWithinArchivedRetention(modified: $0.modified) }
        let uncached = candidates.filter { !hasCachedNote(id: $0.path) }
        guard !uncached.isEmpty else { return }
        let sorted = uncached.sorted { ($0.modified ?? 0) > ($1.modified ?? 0) }
        for node in sorted.prefix(archivedNotePrefetchLimit) {
            do {
                let note = try await api.getNote(id: node.path)
                if shouldPersistNote(note) {
                    persistNote(note)
                } else {
                    clearCachedNote(note)
                }
            } catch {
                continue
            }
        }
    }

    func archivedNoteNodes(from nodes: [FileNode]) -> [FileNode] {
        var collected: [FileNode] = []
        for node in nodes {
            if node.type == .file {
                collected.append(node)
            }
            if let children = node.children {
                collected.append(contentsOf: archivedNoteNodes(from: children))
            }
        }
        return collected
    }

    func isWithinArchivedRetention(modified: Double?) -> Bool {
        ArchivedRetentionPolicy.contains(
            epochSeconds: modified,
            retentionDays: archivedNoteRetentionDays
        )
    }

    func findNode(path: String, in nodes: [FileNode]) -> FileNode? {
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

    // MARK: - Widget Data

    func updateWidgetData(from tree: FileTree) {
        widgetDataManager.store(makeWidgetData(from: tree), for: .notes)
    }

    func makeWidgetData(from tree: FileTree) -> WidgetNoteData {
        let allNotes = flattenNotes(from: tree.children)
        let pinnedNotes = allNotes
            .filter { $0.pinned }
            .sorted { ($0.pinnedOrder ?? Int.max) < ($1.pinnedOrder ?? Int.max) }
        let widgetNotes = Array(pinnedNotes.prefix(10))
        return WidgetNoteData(notes: widgetNotes, totalCount: pinnedNotes.count)
    }

    func flattenNotes(from nodes: [FileNode]) -> [WidgetNote] {
        var notes: [WidgetNote] = []
        for node in nodes {
            if node.type == .file, node.archived != true {
                notes.append(WidgetNote(from: node))
            }
            if let children = node.children {
                notes.append(contentsOf: flattenNotes(from: children))
            }
        }
        return notes
    }
}
