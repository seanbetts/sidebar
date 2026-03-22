import Foundation

extension NotesStore {
    func pinnedNoteOrder() -> [String] {
        pinnedNodes(in: tree?.children ?? [])
            .sorted {
                let leftOrder = $0.pinnedOrder ?? Int.max
                let rightOrder = $1.pinnedOrder ?? Int.max
                if leftOrder != rightOrder {
                    return leftOrder < rightOrder
                }
                return $0.path < $1.path
            }
            .map(\.path)
    }

    func applyPinnedOrder(_ ids: [String]) {
        guard let tree else { return }
        let pinnedOrderLookup = ids.enumerated().reduce(into: [String: Int]()) { partialResult, pair in
            partialResult[pair.element] = pair.offset
        }
        let updatedChildren = updatingPinnedOrder(
            in: tree.children,
            pinnedOrderLookup: pinnedOrderLookup
        )
        let updatedTree = makeTree(children: updatedChildren)
        persistPinnedOrderTree(updatedTree)
    }

    private func updatingPinnedOrder(
        in nodes: [FileNode],
        pinnedOrderLookup: [String: Int]
    ) -> [FileNode] {
        nodes.map { node in
            let updatedChildren = node.children.map {
                updatingPinnedOrder(in: $0, pinnedOrderLookup: pinnedOrderLookup)
            }
            let updatedNode = copyNode(node, children: updatedChildren)
            guard updatedNode.type == .file, updatedNode.pinned == true else {
                return updatedNode
            }
            guard let pinnedOrder = pinnedOrderLookup[updatedNode.path] else {
                return updatedNode
            }
            return copyNode(updatedNode, pinnedOrder: pinnedOrder)
        }
    }

    private func persistPinnedOrderTree(_ updatedTree: FileTree) {
        tree = updatedTree
        cache.set(key: CacheKeys.notesTree, value: updatedTree, ttlSeconds: CachePolicy.notesTree)
        let lastSyncAt = offlineStore?.lastSyncAt(for: cacheKey)
        offlineStore?.set(
            key: cacheKey,
            entityType: "notesTree",
            value: updatedTree,
            lastSyncAt: lastSyncAt
        )
        updateWidgetData(from: updatedTree)
    }

    private func pinnedNodes(in nodes: [FileNode]) -> [FileNode] {
        var results: [FileNode] = []
        for node in nodes {
            if node.type == .file, node.pinned == true {
                results.append(node)
            }
            if let children = node.children {
                results.append(contentsOf: pinnedNodes(in: children))
            }
        }
        return results
    }
}
