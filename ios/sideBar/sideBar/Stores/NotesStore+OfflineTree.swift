import Foundation

extension NotesStore {
    func resolvedFolderPath(for request: NoteCreateRequest) -> String {
        if let folder = request.folder?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
           !folder.isEmpty {
            return folder
        }
        guard let path = request.path?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              !path.isEmpty else {
            return ""
        }
        return parentFolderPath(path)
    }

    func isArchiveFolder(_ folder: String) -> Bool {
        let normalized = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return normalized == "Archive" || normalized.hasPrefix("Archive/")
    }

    func parentFolderPath(_ path: String) -> String {
        guard let lastSlash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<lastSlash])
    }

    func updateCachedNotePath(from oldPath: String, to newPath: String, newName: String?) {
        guard let note = notePayload(forPath: oldPath) else { return }
        let updated = NotePayload(
            id: note.id,
            name: newName ?? note.name,
            document: note.document,
            documentVersion: note.documentVersion,
            plainText: note.plainText,
            path: newPath,
            modified: note.modified,
            created: note.created
        )
        let lastSyncAt = offlineStore?.lastSyncAt(for: CacheKeys.note(id: oldPath))
        cache.remove(key: CacheKeys.note(id: oldPath))
        cache.set(key: CacheKeys.note(id: note.id), value: updated, ttlSeconds: CachePolicy.noteContent)
        cache.set(key: CacheKeys.note(id: newPath), value: updated, ttlSeconds: CachePolicy.noteContent)
        offlineStore?.remove(key: CacheKeys.note(id: oldPath))
        offlineStore?.set(key: CacheKeys.note(id: note.id), entityType: "note", value: updated, lastSyncAt: lastSyncAt)
        offlineStore?.set(key: CacheKeys.note(id: newPath), entityType: "note", value: updated, lastSyncAt: lastSyncAt)
        if activeNote?.id == note.id {
            applyNoteUpdate(updated, persist: true, activeNoteMode: .force)
        }
    }

    func updatedTree(
        in sourceTree: FileTree?,
        notePath: String,
        transform: (FileNode) -> FileNode?
    ) -> FileTree? {
        guard let sourceTree else { return nil }
        let updatedChildren = updatingNodes(in: sourceTree.children, notePath: notePath, transform: transform)
        return makeTree(children: updatedChildren)
    }

    func updatingNodes(
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

    func removingNode(in nodes: [FileNode], notePath: String) -> [FileNode] {
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

    func removeNodeFromTree(in nodes: [FileNode], notePath: String) -> (nodes: [FileNode], removed: FileNode?) {
        var removed: FileNode?
        let updatedNodes: [FileNode] = nodes.compactMap { node -> FileNode? in
            if node.path == notePath {
                removed = node
                return nil
            }
            guard let children = node.children else {
                return node
            }

            let childRemoval = removeNodeFromTree(in: children, notePath: notePath)
            if let child = childRemoval.removed {
                removed = child
                return copyNode(node, children: childRemoval.nodes)
            }
            return node
        }

        return (updatedNodes, removed)
    }

    func removingFolder(in nodes: [FileNode], normalizedPath: String) -> [FileNode] {
        nodes.compactMap { node in
            if node.type == .directory, normalizedFolderNodePath(node.path) == normalizedPath {
                return nil
            }
            guard let children = node.children else {
                return node
            }
            return copyNode(node, children: removingFolder(in: children, normalizedPath: normalizedPath))
        }
    }

    func renamingFolderNodes(
        in nodes: [FileNode],
        oldPath: String,
        newPath: String,
        newName: String
    ) -> [FileNode] {
        nodes.map { node in
            guard node.type == .directory else { return node }
            let normalizedPath = normalizedFolderNodePath(node.path)
            let updatedChildren = node.children.map {
                renamingFolderNodes(in: $0, oldPath: oldPath, newPath: newPath, newName: newName)
            }
            if normalizedPath == oldPath {
                return renameFolderNodeTree(node, oldPath: oldPath, newPath: newPath, newName: newName)
            }
            return copyNode(node, children: updatedChildren)
        }
    }

    func renameFolderNodeTree(
        _ node: FileNode,
        oldPath: String,
        newPath: String,
        newName: String? = nil
    ) -> FileNode {
        let normalizedPath = normalizedFolderNodePath(node.path)
        let normalizedOldPath = normalizedFolderNodePath(oldPath)
        let normalizedNewPath = normalizedFolderNodePath(newPath)
        let replacedPath = normalizedPath.replacingOccurrences(
            of: normalizedOldPath,
            with: normalizedNewPath,
            options: [.anchored]
        )
        let renderedPath = newPath.hasPrefix("/") ? "/\(replacedPath)" : replacedPath
        let childNodes = node.children?.map {
            renamedFolderDescendant($0, oldPath: oldPath, newPath: newPath)
        }
        let resolvedName = newName ?? renderedPath.split(separator: "/").last.map(String.init) ?? node.name
        return FileNode(
            name: resolvedName,
            path: "folder:\(renderedPath)",
            type: .directory,
            size: node.size,
            modified: node.modified,
            created: node.created,
            children: childNodes,
            expanded: node.expanded,
            pinned: node.pinned,
            pinnedOrder: node.pinnedOrder,
            archived: node.archived,
            folderMarker: node.folderMarker
        )
    }

    private func renamedFolderDescendant(
        _ node: FileNode,
        oldPath: String,
        newPath: String
    ) -> FileNode {
        if node.type == .directory {
            return renameFolderNodeTree(node, oldPath: oldPath, newPath: newPath)
        }

        let normalizedOldPath = normalizedFolderNodePath(oldPath)
        let normalizedNewPath = normalizedFolderNodePath(newPath)
        let oldPrefix = node.path.hasPrefix("/") ? "/\(normalizedOldPath)" : normalizedOldPath
        let newPrefix = node.path.hasPrefix("/") ? "/\(normalizedNewPath)" : normalizedNewPath
        let replacedPath = node.path.replacingOccurrences(
            of: oldPrefix,
            with: newPrefix,
            options: [.anchored]
        )
        return FileNode(
            name: node.name,
            path: replacedPath,
            type: node.type,
            size: node.size,
            modified: node.modified,
            created: node.created,
            children: node.children,
            expanded: node.expanded,
            pinned: node.pinned,
            pinnedOrder: node.pinnedOrder,
            archived: node.archived,
            folderMarker: node.folderMarker
        )
    }

    func renamedNotePathPairs(
        in nodes: [FileNode],
        oldPath: String,
        newPath: String
    ) -> [(oldPath: String, newPath: String)] {
        nodes.flatMap { node -> [(oldPath: String, newPath: String)] in
            if node.type == .directory {
                return renamedNotePathPairs(
                    in: node.children ?? [],
                    oldPath: oldPath,
                    newPath: newPath
                )
            }

            guard node.type == .file else { return [] }
            let normalizedOldPath = normalizedFolderNodePath(oldPath)
            let normalizedNewPath = normalizedFolderNodePath(newPath)
            let oldPrefix = node.path.hasPrefix("/") ? "/\(normalizedOldPath)" : normalizedOldPath
            guard node.path == oldPrefix || node.path.hasPrefix("\(oldPrefix)/") else {
                return []
            }
            let newPrefix = node.path.hasPrefix("/") ? "/\(normalizedNewPath)" : normalizedNewPath
            let updatedPath = node.path.replacingOccurrences(
                of: oldPrefix,
                with: newPrefix,
                options: [.anchored]
            )
            return [(oldPath: node.path, newPath: updatedPath)]
        }
    }

    func insertNodeIntoFolder(_ nodes: [FileNode], node: FileNode, folder: String) -> [FileNode] {
        let normalizedFolder = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalizedFolder.isEmpty else {
            return nodes + [node]
        }
        let components = normalizedFolder.split(separator: "/").map(String.init)
        return insertNodeIntoFolder(nodes, node: node, components: components, currentPath: "")
    }

    func insertNodeIntoFolder(
        _ nodes: [FileNode],
        node: FileNode,
        components: [String],
        currentPath: String
    ) -> [FileNode] {
        guard let component = components.first else {
            return nodes + [node]
        }

        let nextPath = currentPath.isEmpty ? component : "\(currentPath)/\(component)"
        var updatedNodes = nodes
        let remaining = Array(components.dropFirst())
        let targetIndex = updatedNodes.firstIndex { existing in
            existing.type == .directory && normalizedFolderNodePath(existing.path) == nextPath
        }

        if let targetIndex {
            let existing = updatedNodes[targetIndex]
            let existingChildren = existing.children ?? []
            let updatedChildren = remaining.isEmpty
                ? existingChildren + [node]
                : insertNodeIntoFolder(existingChildren, node: node, components: remaining, currentPath: nextPath)
            updatedNodes[targetIndex] = copyNode(existing, children: updatedChildren)
            return updatedNodes
        }

        let newChildren = remaining.isEmpty
            ? [node]
            : insertNodeIntoFolder([], node: node, components: remaining, currentPath: nextPath)
        let newFolderNode = FileNode(
            name: component,
            path: "folder:\(nextPath)",
            type: .directory,
            size: nil,
            modified: nil,
            created: nil,
            children: newChildren,
            expanded: nil,
            pinned: nil,
            pinnedOrder: nil,
            archived: nil,
            folderMarker: true
        )
        updatedNodes.append(newFolderNode)
        return updatedNodes
    }

    func copyNode(
        _ node: FileNode,
        name: String? = nil,
        path: String? = nil,
        modified: Double? = nil,
        pinned: Bool? = nil,
        pinnedOrder: Int? = nil,
        archived: Bool? = nil,
        children: [FileNode]? = nil
    ) -> FileNode {
        let resolvedPinned = pinned ?? node.pinned
        let resolvedPinnedOrder: Int?
        if let pinnedOrder {
            resolvedPinnedOrder = pinnedOrder
        } else if resolvedPinned == false {
            resolvedPinnedOrder = nil
        } else {
            resolvedPinnedOrder = node.pinnedOrder
        }
        return FileNode(
            name: name ?? node.name,
            path: path ?? node.path,
            type: node.type,
            size: node.size,
            modified: modified ?? node.modified,
            created: node.created,
            children: children ?? node.children,
            expanded: node.expanded,
            pinned: resolvedPinned,
            pinnedOrder: resolvedPinnedOrder,
            archived: archived ?? node.archived,
            folderMarker: node.folderMarker
        )
    }

    func movingPath(_ path: String, to folder: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let filename = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        let normalizedFolder = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let newPath = normalizedFolder.isEmpty ? filename : "\(normalizedFolder)/\(filename)"
        return path.hasPrefix("/") ? "/\(newPath)" : newPath
    }

    func normalizedFolderNodePath(_ path: String) -> String {
        if path.hasPrefix("folder:") {
            return String(path.dropFirst("folder:".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func makeFolderNode(name: String, normalizedPath: String, children: [FileNode]) -> FileNode {
        FileNode(
            name: name,
            path: "folder:\(normalizedPath)",
            type: .directory,
            size: nil,
            modified: nil,
            created: nil,
            children: children,
            expanded: true,
            pinned: nil,
            pinnedOrder: nil,
            archived: nil,
            folderMarker: true
        )
    }
}
